import Foundation
import os.log

/// Writes lean session transcripts — just the meaningful conversation, not the full tool machinery.
/// Output: ~/.familiar/transcripts/{session-id}.md
@Observable
@MainActor
final class TranscriptLogger {

    private let logger = Logger(subsystem: "app.familiar", category: "TranscriptLogger")

    private static let transcriptsDirectory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".familiar/transcripts", isDirectory: true)
    }()

    private var fileHandle: FileHandle?
    private var currentSessionId: String?
    private var currentFilePath: URL?

    // Track tool use groups so we can summarize them
    private var pendingToolUses: [(name: String, inputSummary: String)] = []

    /// Non-isolated box so deinit can close the handle.
    private nonisolated(unsafe) var _fileHandleForDeinit: FileHandle?

    init() {
        ensureDirectory()
    }

    deinit {
        try? _fileHandleForDeinit?.close()
    }

    // MARK: - Session Lifecycle

    func startSession(id: String, model: String, workingDirectory: String) {
        flushToolGroup()
        closeFile()

        currentSessionId = id
        let filePath = Self.transcriptsDirectory.appendingPathComponent("\(id).md")
        currentFilePath = filePath

        let fm = FileManager.default
        if !fm.fileExists(atPath: filePath.path) {
            let header = """
            # Session \(id)
            **Started:** \(Self.timestamp())
            **Model:** \(model)
            **Directory:** \(workingDirectory)

            ---


            """
            fm.createFile(atPath: filePath.path, contents: header.data(using: .utf8))
        }

        fileHandle = try? FileHandle(forWritingTo: filePath)
        _fileHandleForDeinit = fileHandle
        fileHandle?.seekToEndOfFile()
    }

    func endSession(cost: Double, inputTokens: Int, outputTokens: Int, durationMs: Int) {
        flushToolGroup()
        let summary = """

        ---
        **Turn complete** — \(Self.timestamp())
        Cost: $\(String(format: "%.4f", cost)) | Tokens: \(inputTokens) in / \(outputTokens) out | Duration: \(durationMs)ms


        """
        append(summary)
    }

    // MARK: - Message Logging

    func logUserMessage(_ text: String) {
        flushToolGroup()
        append("\n### User\n\(text)\n")
    }

    func logAssistantMessage(_ text: String) {
        flushToolGroup()
        guard !text.isEmpty else { return }
        append("\n### Assistant\n\(text)\n")
    }

    func logThinking(_ text: String) {
        flushToolGroup()
        // Just a one-liner indicating thinking happened, not the full content
        let preview = String(text.prefix(120)).replacingOccurrences(of: "\n", with: " ")
        append("\n> *Thinking: \(preview)...*\n")
    }

    func logToolUse(name: String, input: String) {
        // Summarize the tool call into a compact one-liner
        let summary = summarizeToolInput(name: name, input: input)
        pendingToolUses.append((name: name, inputSummary: summary))
    }

    func logToolResult(name: String?, content: String, isError: Bool) {
        // For errors, log them explicitly. Otherwise the tool group flush handles it.
        if isError {
            let preview = String(content.prefix(200)).replacingOccurrences(of: "\n", with: " ")
            pendingToolUses.append((name: name ?? "error", inputSummary: "❌ \(preview)"))
        }
    }

    // MARK: - Private

    private func flushToolGroup() {
        guard !pendingToolUses.isEmpty else { return }

        var block = "\n<details><summary>🔧 \(pendingToolUses.count) tool call\(pendingToolUses.count == 1 ? "" : "s")</summary>\n\n"
        for tool in pendingToolUses {
            block += "- **\(tool.name)**: \(tool.inputSummary)\n"
        }
        block += "\n</details>\n"

        append(block)
        pendingToolUses = []
    }

    private func summarizeToolInput(name: String, input: String) -> String {
        // Extract the most useful bit depending on tool type
        switch name {
        case "Read":
            return extractJsonValue(input, key: "file_path") ?? truncate(input, to: 80)
        case "Write":
            let path = extractJsonValue(input, key: "file_path") ?? "unknown"
            let lines = input.components(separatedBy: "\n").count
            return "\(path) (\(lines) lines)"
        case "Edit":
            let path = extractJsonValue(input, key: "file_path") ?? "unknown"
            return "edit \(path)"
        case "Bash":
            let cmd = extractJsonValue(input, key: "command") ?? truncate(input, to: 100)
            return "`\(truncate(cmd, to: 100))`"
        case "Glob":
            let pattern = extractJsonValue(input, key: "pattern") ?? truncate(input, to: 80)
            return "pattern: \(pattern)"
        case "Grep":
            let pattern = extractJsonValue(input, key: "pattern") ?? truncate(input, to: 80)
            return "search: \(pattern)"
        case "WebFetch":
            return extractJsonValue(input, key: "url") ?? truncate(input, to: 100)
        case "WebSearch":
            return extractJsonValue(input, key: "query") ?? truncate(input, to: 100)
        case "Task":
            return extractJsonValue(input, key: "description") ?? truncate(input, to: 100)
        default:
            return truncate(input, to: 100)
        }
    }

    private func extractJsonValue(_ json: String, key: String) -> String? {
        // Quick and dirty — look for "key": "value" pattern
        let pattern = "\"\(key)\"\\s*:\\s*\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: json, range: NSRange(json.startIndex..., in: json)),
              let range = Range(match.range(at: 1), in: json) else {
            return nil
        }
        return String(json[range])
    }

    private func truncate(_ text: String, to length: Int) -> String {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        return clean.count > length ? String(clean.prefix(length)) + "…" : clean
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    private func closeFile() {
        try? fileHandle?.close()
        fileHandle = nil
        _fileHandleForDeinit = nil
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: Self.transcriptsDirectory, withIntermediateDirectories: true)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
