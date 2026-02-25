import ClaudeCodeSDK
import Foundation
import os.log

/// Encapsulates Claude Code CLI execution using a persistent process.
/// Instead of spawning a new CLI process per message, keeps a long-running
/// `claude` process with `--input-format stream-json` and pushes messages via stdin.
@Observable
@MainActor
final class CommandRunner {

    private let logger = Logger(subsystem: "app.tinker", category: "CommandRunner")

    // State
    private(set) var runState: CommandRunState = .idle
    private(set) var currentSessionId: String?

    // Token usage from last run
    private(set) var lastInputTokens: Int = 0
    private(set) var lastOutputTokens: Int = 0
    private(set) var lastCostUsd: Double = 0
    private(set) var lastDurationMs: Int = 0

    /// Callbacks the view model hooks into
    var onSessionIdEstablished: ((String) -> Void)?
    var onAssistantContent: ((UUID, String, Bool) -> Void)?
    var onToolMessage: ((MessageRole, String, MessageType, String?) -> Void)?
var onResultReceived: ((ResultMessage) -> Void)?
    var onError: ((Error) -> Void)?
    var onComplete: ((String) -> Void)?

    // Persistent process state
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isProcessRunning: Bool { process?.isRunning == true }

    // Current message tracking
    private var currentMessageId: UUID?
    private var contentBuffer = ""
    private var stdoutLineBuffer = ""
    private var hadInterruptSinceLastText = false
    private var startTime: Date?

    // Configuration
    private var workingDirectory: String
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    init(workingDirectory: String) {
        self.workingDirectory = workingDirectory
    }

    // MARK: - Client Management

    func updateWorkingDirectory(_ path: String) {
        killProcess()
        workingDirectory = path
        currentSessionId = nil
    }

    // MARK: - Process Lifecycle

    /// Spawns the persistent claude process if not already running.
    private func ensureProcessRunning(model: String, permissionMode: String?) {
        guard !isProcessRunning else { return }

        let claudePath = findClaudePath()
        logger.info("Spawning persistent claude process at: \(claudePath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: claudePath)

        // Build args — no shell wrapper, direct spawn
        var args = [
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--model", model
        ]

        let tools = ["Task", "Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "WebSearch"]
        args.append(contentsOf: ["--allowedTools", tools.joined(separator: ",")])

        if let permissionMode, !permissionMode.isEmpty, permissionMode != "default" {
            args.append(contentsOf: ["--permission-mode", permissionMode])
        }

        let systemPromptMode = UserDefaults.standard.string(forKey: "systemPromptMode") ?? "off"
        let customSystemPrompt = UserDefaults.standard.string(forKey: "customSystemPrompt") ?? ""
        if systemPromptMode == "override" && !customSystemPrompt.isEmpty {
            args.append(contentsOf: ["--system-prompt", customSystemPrompt])
        } else if systemPromptMode == "append" && !customSystemPrompt.isEmpty {
            args.append(contentsOf: ["--append-system-prompt", customSystemPrompt])
        }

        // Resume existing session if we have one
        if let sessionId = currentSessionId {
            args.append(contentsOf: ["--resume", sessionId])
        }

        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)

        // Environment — clean, with necessary paths
        var env = ProcessInfo.processInfo.environment
        let homeDir = NSHomeDirectory()
        let additionalPaths = [
            "\(homeDir)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin"
        ]
        if let currentPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + currentPath
        }
        // Remove CLAUDECODE env var to avoid "nested session" detection
        env.removeValue(forKey: "CLAUDECODE")
        env.removeValue(forKey: "CLAUDE_CODE_ENTRYPOINT")
        // Enable experimental agent teams
        env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"
        proc.environment = env

        // Set up pipes
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.process = proc

        // Handle stdout — parse JSON lines with line buffering
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — process ended
                handle.readabilityHandler = nil
                return
            }
            guard let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.stdoutLineBuffer += text
                while let newlineIndex = self.stdoutLineBuffer.firstIndex(of: "\n") {
                    let line = String(self.stdoutLineBuffer[self.stdoutLineBuffer.startIndex..<newlineIndex])
                    self.stdoutLineBuffer = String(self.stdoutLineBuffer[self.stdoutLineBuffer.index(after: newlineIndex)...])
                    if !line.isEmpty {
                        self.processJsonLine(line)
                    }
                }
            }
        }

        // Handle stderr — log for debugging
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8) else { return }
            self?.logger.debug("stderr: \(text)")
        }

        // Handle process termination
        proc.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                self?.logger.info("Claude process terminated with code \(proc.terminationStatus)")
                self?.handleProcessTermination()
            }
        }

        do {
            try proc.run()
            logger.info("Persistent claude process started (PID: \(proc.processIdentifier))")
        } catch {
            logger.error("Failed to start claude process: \(error.localizedDescription)")
            self.process = nil
            runState = .failed(message: "Failed to start claude: \(error.localizedDescription)")
            onError?(error)
        }
    }

    private func handleProcessTermination() {
        process = nil
        stdinPipe = nil
        stdoutLineBuffer = ""
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil

        // If we were in the middle of a message, resolve terminal state.
        if runState == .stopping {
            runState = .cancelled
            if let messageId = currentMessageId, !contentBuffer.isEmpty {
                onAssistantContent?(messageId, contentBuffer, true)
            }
            return
        }

        if runState.isActive {
            let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
            runState = .completed(duration: duration)
            if let messageId = currentMessageId {
                onAssistantContent?(messageId, contentBuffer, true)
                onComplete?(contentBuffer)
            }
        }
    }

    // MARK: - Execution

    func run(prompt: String, sessionId: String?, model: String, messageId: UUID, permissionMode: String? = nil) {
        guard !runState.isActive else {
            logger.warning("Attempted to run while already active")
            return
        }

        // If session ID changed (switching sessions), kill old process
        if let sessionId, sessionId != currentSessionId, isProcessRunning {
            logger.info("Session changed, killing old process")
            killProcess()
        }

        // Track the session ID from the view model
        if let sessionId {
            currentSessionId = sessionId
        }

        let now = Date()
        runState = .running(startedAt: now)
        startTime = now
        currentMessageId = messageId
        contentBuffer = ""
        hadInterruptSinceLastText = false

        // Ensure persistent process is running
        ensureProcessRunning(model: model, permissionMode: permissionMode)

        // Send the user message as a JSON line to stdin
        let userMessage: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": prompt
            ]
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: userMessage),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            logger.error("Failed to serialize user message")
            runState = .failed(message: "Failed to serialize message")
            return
        }
        jsonString += "\n"

        guard let stdinPipe = stdinPipe else {
            logger.error("No stdin pipe available")
            runState = .failed(message: "Process not running")
            return
        }

        stdinPipe.fileHandleForWriting.write(jsonString.data(using: .utf8)!)
        logger.info("Sent user message to persistent process")
    }

    func cancel() {
        guard runState.isActive || isProcessRunning else { return }
        runState = .stopping

        // Kill the persistent process — a new one will be spawned on next run()
        if let process, process.isRunning {
            process.terminate()
        }
        currentSessionId = nil

        // Ensure we converge to terminal state
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.runState == .stopping else { return }
            self.runState = .cancelled
        }
    }

    /// Kill the persistent process and reset state. Called when changing working directory, etc.
    func killProcess() {
        if let process, process.isRunning {
            process.terminate()
        }
        handleProcessTermination()
        runState = .idle
    }

    func reset() {
        guard runState.isTerminal || runState == .idle else { return }
        runState = .idle
    }

    // MARK: - JSON Line Processing

    private func processJsonLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        print("[CR] processJsonLine type=\(type) subtype=\((json["subtype"] as? String) ?? "none")")

        switch type {
        case "system":
            processSystemMessage(data: data, json: json)

        case "assistant":
            print("[CR] → processing assistant message")
            processAssistantMessage(data: data)

        case "user":
            break // Our own messages echoed back

        case "result":
            processResultMessage(data: data)

        default:
            logger.debug("Unknown message type: \(type)")
        }
    }

    private func processSystemMessage(data: Data, json: [String: Any]) {
        guard let subtype = json["subtype"] as? String else { return }

        if subtype == "init" {
            if let initMessage = try? decoder.decode(InitSystemMessage.self, from: data) {
                if currentSessionId == nil || currentSessionId != initMessage.sessionId {
                    currentSessionId = initMessage.sessionId
                    onSessionIdEstablished?(initMessage.sessionId)
                }
            }
        } else {
            // Result-type system message (success, error_max_turns, etc.)
            processResultMessage(data: data)
        }
    }

    private func processAssistantMessage(data: Data) {
        do {
            let message = try decoder.decode(AssistantMessage.self, from: data)
            guard let messageId = currentMessageId else {
                print("[CR] ✗ No currentMessageId for assistant message")
                return
            }
            print("[CR] ✓ Decoded assistant message with \(message.message.content.count) content blocks")
            processAssistantContent(message: message, messageId: messageId)
        } catch {
            print("[CR] ✗ Failed to decode AssistantMessage: \(error)")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = json["message"] as? [String: Any],
               let content = msg["content"] as? [[String: Any]] {
                print("[CR] ✗ Raw content types: \(content.map { $0["type"] as? String ?? "?" })")
            }
        }
    }

    private func processAssistantContent(message: AssistantMessage, messageId: UUID) {

        for content in message.message.content {
            switch content {
            case .text(let text, _):
                print("[CR] text block: \(text.prefix(80))")
                if hadInterruptSinceLastText && !contentBuffer.isEmpty {
                    contentBuffer += "\n\n" + text
                } else {
                    contentBuffer = text
                }
                hadInterruptSinceLastText = false
                onAssistantContent?(messageId, contentBuffer, false)

            case .toolUse(let toolUse):
                hadInterruptSinceLastText = true
                onToolMessage?(.toolUse, "Tool: \(toolUse.name)\n\(toolUse.input.formattedDescription())", .toolUse, toolUse.name)

            case .toolResult(let toolResult):
                let isError = toolResult.isError == true
                let text: String
                switch toolResult.content {
                case .string(let value): text = value
                case .items(let items): text = items.compactMap { $0.text }.joined(separator: "\n")
                }
                onToolMessage?(isError ? .toolError : .toolResult, text, isError ? .toolError : .toolResult, nil)

            case .thinking(let thinking):
                hadInterruptSinceLastText = true
                onToolMessage?(.thinking, thinking.thinking, .thinking, nil)

            default:
                break
            }
        }
    }

    private func processResultMessage(data: Data) {
        // Always print the raw result for debugging
        if let raw = String(data: data, encoding: .utf8) {
            print("[CR] result raw: \(raw.prefix(500))")
        }
        guard let resultMessage = try? decoder.decode(ResultMessage.self, from: data) else {
            print("[CR] ✗ Failed to decode ResultMessage")
            return
        }

        currentSessionId = resultMessage.sessionId

        if let messageId = currentMessageId {
            if let finalContent = resultMessage.result, !finalContent.isEmpty, contentBuffer.isEmpty {
                contentBuffer = finalContent
            }
            onAssistantContent?(messageId, contentBuffer, true)
        }

        lastCostUsd = resultMessage.totalCostUsd
        lastDurationMs = resultMessage.durationMs
        if let usage = resultMessage.usage {
            lastInputTokens = usage.inputTokens
            lastOutputTokens = usage.outputTokens
        }
        onResultReceived?(resultMessage)

        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        runState = .completed(duration: duration)
        onComplete?(contentBuffer)
    }

    // MARK: - Path Resolution

    private func findClaudePath() -> String {
        let candidates = [
            "\(NSHomeDirectory())/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude"
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return "/usr/local/bin/claude" // fallback
    }
}
