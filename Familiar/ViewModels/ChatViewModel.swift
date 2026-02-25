import AppKit
import ClaudeCodeSDK
import Foundation
import os.log
import UserNotifications

@Observable
@MainActor
class ChatViewModel {

    private let logger = Logger(subsystem: "app.familiar", category: "Chat")
    private(set) var currentSessionId: String?
    private var currentMessageId: UUID?

    private static let selectedModelKey = "selectedModel"
    private static let selectedPermissionModeKey = "selectedPermissionMode"
    private static let workingDirectoryKey = "lastWorkingDirectory"
    private static let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Familiar", isDirectory: true)
    }()
    private static let sessionsFile: URL = storageDirectory.appendingPathComponent("sessions.json")
    private static let messagesDirectory: URL = storageDirectory.appendingPathComponent("messages", isDirectory: true)

    /// Persist all message types so tool use, thinking, etc. survive reload
    private static let persistableRoles: Set<MessageRole> = [.user, .assistant, .toolUse, .toolResult, .toolError, .thinking, .system]

    let ragService = RAGService()
    let memoryDaemon = MemoryDaemon.shared
    let gitService = GitService()
    var messages: [ChatMessage] = []
    var error: Error?
    var workingDirectory: String
    var sessions: [Session] = []
    var currentSession: Session?
    var lastSentMessage: String = ""
    var showSettings: Bool = false

    // Message queue — holds messages while agent is busy
    var messageQueue: [QueuedMessage] = []

    // Command execution
    private(set) var commandRunner: CommandRunner

    var isLoading: Bool { commandRunner.runState.isActive }
    var runState: CommandRunState { commandRunner.runState }
    var requestStartTime: Date? { commandRunner.runState.startedAt }

    // Git — delegated to GitService
    var gitBranch: String? { gitService.branch }

    // Seed manager for context extraction
    let seedManager = SeedManager()
    var seedsLoaded: Bool { seedManager.contents.values.contains { !$0.isEmpty } }

    // Lean transcript logger
    private let transcriptLogger = TranscriptLogger()

    // Token usage & cost tracking (delegated from runner)
    var lastInputTokens: Int { commandRunner.lastInputTokens }
    var lastOutputTokens: Int { commandRunner.lastOutputTokens }
    var lastCostUsd: Double { commandRunner.lastCostUsd }
    var lastDurationMs: Int { commandRunner.lastDurationMs }
    var totalSessionCost: Double = 0

    // Model selection
    static let availableModels = [
        ("claude-sonnet-4-6", "Sonnet 4.6"),
        ("claude-opus-4-6", "Opus 4.6"),
        ("claude-haiku-4-5-20251001", "Haiku 4.5"),
    ]
    var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: ChatViewModel.selectedModelKey) }
    }

    // Permission mode selection
    static let availablePermissionModes: [(String, String, String)] = [
        ("default", "Default", "shield.checkered"),
        ("acceptEdits", "Accept Edits", "pencil.circle"),
        ("bypassPermissions", "Bypass All", "bolt.shield"),
        ("plan", "Plan Mode", "list.clipboard"),
    ]
    var selectedPermissionMode: String {
        didSet { UserDefaults.standard.set(selectedPermissionMode, forKey: ChatViewModel.selectedPermissionModeKey) }
    }

    /// In-memory cache of messages per session (LRU, max 5)
    private var sessionMessages: [String: [ChatMessage]] = [:]
    private var sessionAccessOrder: [String] = []
    private static let maxCachedSessions = 5

    /// Max characters to keep in-memory for tool result content
    private static let maxToolResultChars = 4_000

    init() {
        let savedDir = UserDefaults.standard.string(forKey: ChatViewModel.workingDirectoryKey)
        let dir = savedDir ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.workingDirectory = dir
        self.selectedModel = UserDefaults.standard.string(forKey: ChatViewModel.selectedModelKey) ?? "claude-sonnet-4-6"
        self.selectedPermissionMode = UserDefaults.standard.string(forKey: ChatViewModel.selectedPermissionModeKey) ?? "default"
        self.commandRunner = CommandRunner(workingDirectory: dir)
        setupRunnerCallbacks()
        loadSessions()
        refreshGitBranch()

        // Start session server for iOS companion app
        SessionServer.shared.viewModel = self
        SessionServer.shared.start()
    }

    private func setupRunnerCallbacks() {
        commandRunner.onSessionIdEstablished = { [weak self] sessionId in
            guard let self else { return }
            self.currentSessionId = sessionId
            self.transcriptLogger.startSession(
                id: sessionId,
                model: self.selectedModel,
                workingDirectory: self.workingDirectory
            )
            // Wire up memory daemon for idle-based session note generation
            let transcriptPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".familiar/transcripts/\(sessionId).md").path
            self.memoryDaemon.activeSessionId = sessionId
            self.memoryDaemon.activeTranscriptPath = transcriptPath
            if var session = self.currentSession,
               let idx = self.sessions.firstIndex(where: { $0.id == session.id }) {
                session.cliSessionId = sessionId
                self.sessions[idx] = session
                self.currentSession = session
                self.saveSessions()
            }
        }

        commandRunner.onAssistantContent = { [weak self] messageId, content, isComplete in
            guard let self else { return }
            self.updateMessage(messageId, content: content, isComplete: isComplete)
        }

        commandRunner.onToolMessage = { [weak self] role, content, type, toolName in
            guard let self else { return }
            self.addMessage(role: role, content: content, type: type, toolName: toolName)

            // Log to lean transcript
            switch type {
            case .toolUse:
                self.transcriptLogger.logToolUse(name: toolName ?? "unknown", input: content)
            case .toolResult:
                self.transcriptLogger.logToolResult(name: toolName, content: content, isError: false)
            case .toolError:
                self.transcriptLogger.logToolResult(name: toolName, content: content, isError: true)
            case .thinking:
                self.transcriptLogger.logThinking(content)
            default:
                break
            }
        }

        commandRunner.onResultReceived = { [weak self] resultMessage in
            guard let self else { return }
            self.currentSessionId = resultMessage.sessionId
            self.totalSessionCost += resultMessage.totalCostUsd
            self.transcriptLogger.endSession(
                cost: resultMessage.totalCostUsd,
                inputTokens: resultMessage.usage?.inputTokens ?? 0,
                outputTokens: resultMessage.usage?.outputTokens ?? 0,
                durationMs: resultMessage.durationMs
            )
        }

        commandRunner.onError = { [weak self] error in
            guard let self else { return }
            self.handleError(error)
        }

        commandRunner.onComplete = { [weak self] content in
            guard let self else { return }
            self.transcriptLogger.logAssistantMessage(content)
            self.autoSave()
            self.sendCompletionNotificationIfNeeded(content: content)
            SessionServer.shared.broadcastState(isLoading: false, runState: self.runState.displayLabel)

            // Refresh git status after agent turn
            Task { await self.gitService.quickRefresh(in: self.workingDirectory) }

            // Drain message queue — send next queued message if any
            if !self.messageQueue.isEmpty {
                // Small delay so the UI can breathe
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.sendNextFromQueue()
                }
            }
        }
    }

    func newSession() {
        // If current session is already empty, just reuse it — don't stack empties
        if let current = currentSession, current.name == "New Session" && messages.isEmpty {
            return
        }

        // Save current session before switching
        if let current = currentSession {
            cacheCurrentMessages(for: current.id)
            saveMessages(for: current.id)
        }

        commandRunner.cancel()
        commandRunner.reset()
        messages = []
        currentSessionId = nil
        currentMessageId = nil
        error = nil

        let session = Session(workingDirectory: workingDirectory)
        sessions.insert(session, at: 0)
        currentSession = session
        saveSessions()
    }

    func selectSession(_ session: Session) {
        // Clean up empty session when switching away from it
        if let current = currentSession, current.id != session.id,
           current.name == "New Session" && messages.isEmpty {
            deleteSession(current)
        } else if let current = currentSession {
            cacheCurrentMessages(for: current.id)
        }

        commandRunner.cancel()
        commandRunner.reset()
        currentMessageId = nil
        error = nil

        currentSession = session
        currentSessionId = session.cliSessionId
        messages = loadMessages(for: session.id)

        // Switch working directory if session has a specific one (worktree or otherwise)
        if let sessionDir = session.worktreePath ?? session.workingDirectory,
           sessionDir != workingDirectory {
            workingDirectory = sessionDir
            UserDefaults.standard.set(sessionDir, forKey: ChatViewModel.workingDirectoryKey)
            commandRunner.updateWorkingDirectory(sessionDir)
        }
        refreshGitBranch()
    }

    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // If agent is busy, queue the message
        if isLoading {
            messageQueue.append(QueuedMessage(text: trimmed))
            return
        }

        sendMessageDirectly(trimmed)
    }

    func removeFromQueue(_ message: QueuedMessage) {
        messageQueue.removeAll { $0.id == message.id }
    }

    func editQueuedMessage(_ message: QueuedMessage, newText: String) {
        if let idx = messageQueue.firstIndex(where: { $0.id == message.id }) {
            messageQueue[idx].text = newText
        }
    }

    func moveQueuedMessage(from source: Int, to destination: Int) {
        guard source >= 0, source < messageQueue.count,
              destination >= 0, destination <= messageQueue.count else { return }
        let item = messageQueue.remove(at: source)
        let adjustedDest = destination > source ? destination - 1 : destination
        messageQueue.insert(item, at: min(adjustedDest, messageQueue.count))
    }

    private func sendNextFromQueue() {
        guard !messageQueue.isEmpty else { return }
        let next = messageQueue.removeFirst()
        sendMessageDirectly(next.text)
    }

    private func sendMessageDirectly(_ trimmed: String) {
        // Ensure we have a session
        if currentSession == nil {
            let session = Session(workingDirectory: workingDirectory)
            sessions.insert(session, at: 0)
            currentSession = session
        }

        lastSentMessage = trimmed
        let userMsg = ChatMessage(role: .user, content: trimmed)
        messages.append(userMsg)
        SessionServer.shared.broadcastMessage(userMsg)
        transcriptLogger.logUserMessage(trimmed)
        memoryDaemon.onHumanMessage(trimmed)
        error = nil

        // Update session metadata
        if var session = currentSession, let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            session.lastMessage = String(trimmed.prefix(80))
            session.updatedAt = Date()
            if session.name == "New Session" {
                session.name = String(trimmed.prefix(40))
            }
            sessions[idx] = session
            currentSession = session
            saveSessions()
        }

        let assistantId = UUID()
        currentMessageId = assistantId
        messages.append(ChatMessage(
            id: assistantId,
            role: .assistant,
            content: "",
            isComplete: false
        ))

        let ragContext = ragService.retrieve(query: trimmed)
        let augmentedPrompt = ragContext.isEmpty ? trimmed : ragContext + "\n\n" + trimmed

        // Build seed context for injection into system prompt
        let seedContext = buildSeedContext()

        commandRunner.run(
            prompt: augmentedPrompt,
            sessionId: currentSessionId,
            model: selectedModel,
            messageId: assistantId,
            permissionMode: selectedPermissionMode == "default" ? nil : selectedPermissionMode,
            contextInjection: seedContext
        )

        SessionServer.shared.broadcastState(isLoading: true, runState: runState.displayLabel)
    }

    func selectSessionByIndex(_ index: Int) {
        guard index >= 0 && index < sessions.count else { return }
        selectSession(sessions[index])
    }

    func renameSession(_ session: Session, to newName: String) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx].name = newName
        if currentSession?.id == session.id {
            currentSession?.name = newName
        }
        saveSessions()
    }

    func deleteSession(_ session: Session) {
        // Clean up worktree if this session had one
        if session.isWorktree { cleanupWorktree(for: session) }

        sessions.removeAll { $0.id == session.id }
        sessionMessages.removeValue(forKey: session.id)
        sessionAccessOrder.removeAll { $0 == session.id }
        try? FileManager.default.removeItem(at: messagesFile(for: session.id))
        if currentSession?.id == session.id {
            currentSession = sessions.first
            if let current = currentSession {
                messages = loadMessages(for: current.id)
                currentSessionId = current.cliSessionId
            } else {
                messages = []
                currentSessionId = nil
            }
        }
        saveSessions()
    }

    func duplicateSession(_ session: Session) {
        let newSession = Session(name: "\(session.name) (Copy)", lastMessage: session.lastMessage)
        sessions.insert(newSession, at: 0)
        // Copy messages if available
        let msgs = loadMessages(for: session.id)
        if !msgs.isEmpty {
            sessionMessages[newSession.id] = msgs
            saveMessages(for: newSession.id)
        }
        saveSessions()
    }

    func clearConversation() {
        if let session = currentSession {
            sessionMessages[session.id] = []
            saveMessages(for: session.id)
            if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[idx].lastMessage = ""
                sessions[idx].updatedAt = Date()
                currentSession = sessions[idx]
            }
            saveSessions()
        }
        messages = []
        currentSessionId = nil
        currentMessageId = nil
        error = nil
    }

    func cancelRequest() {
        commandRunner.cancel()
    }

    func setWorkingDirectory(_ path: String) {
        workingDirectory = path
        UserDefaults.standard.set(path, forKey: ChatViewModel.workingDirectoryKey)
        commandRunner.updateWorkingDirectory(path)
        refreshGitBranch()
    }

    func refreshGitBranch() {
        Task { await gitService.refresh(in: workingDirectory) }
    }

    /// Builds combined seed file content for system prompt injection.
    /// Returns nil if no seed files have content.
    private func buildSeedContext() -> String? {
        seedManager.loadAll()
        // Only inject stable identity seeds. Dynamic memory seeds (now, episodic, semantic)
        // are read actively via CLAUDE.md READ instructions.
        let injectableSeeds: [SeedManager.SeedFile] = [.user, .agent]
        var parts: [String] = []
        for seed in injectableSeeds {
            let content = seedManager.contents[seed] ?? ""
            if !content.isEmpty {
                parts.append("# \(seed.displayName) Seed\n\n\(content)")
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Worktree Support

    func newWorktreeSession() {
        let dir = workingDirectory
        let session = Session(workingDirectory: dir)

        Task {
            guard let wtPath = await gitService.createWorktree(sessionId: session.id, from: dir) else {
                // Fall back to normal session if worktree creation fails
                await MainActor.run {
                    sessions.insert(session, at: 0)
                    currentSession = session
                    saveSessions()
                }
                return
            }
            await MainActor.run {
                var wtSession = session
                wtSession.worktreePath = wtPath
                wtSession.worktreeOrigin = dir
                // Point the session's working directory at the worktree
                commandRunner.cancel()
                commandRunner.reset()
                messages = []
                currentSessionId = nil
                currentMessageId = nil
                error = nil

                sessions.insert(wtSession, at: 0)
                currentSession = wtSession
                workingDirectory = wtPath
                UserDefaults.standard.set(wtPath, forKey: ChatViewModel.workingDirectoryKey)
                commandRunner.updateWorkingDirectory(wtPath)
                saveSessions()
                refreshGitBranch()
            }
        }
    }

    func cleanupWorktree(for session: Session) {
        guard let wtPath = session.worktreePath,
              let origin = session.worktreeOrigin else { return }
        Task { await gitService.removeWorktree(path: wtPath, from: origin) }
    }

    func pickWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a working directory for Claude Code"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            setWorkingDirectory(url.path)
        }
    }


    // MARK: - Private

    private func updateMessage(_ id: UUID, content: String, isComplete: Bool) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            let msg = ChatMessage(id: id, role: .assistant, content: content, isComplete: isComplete)
            messages[idx] = msg
            SessionServer.shared.broadcastMessage(msg)

            // Update session lastMessage when assistant finishes
            if isComplete, !content.isEmpty,
               var session = currentSession,
               let sIdx = sessions.firstIndex(where: { $0.id == session.id }) {
                session.lastMessage = String(content.prefix(80))
                session.updatedAt = Date()
                sessions[sIdx] = session
                currentSession = session
                saveSessions()

                // Feed completed assistant message to memory daemon
                memoryDaemon.onAssistantMessage(content)
            }
        }
    }

    private func addMessage(role: MessageRole, content: String, type: MessageType, toolName: String? = nil) {
        let displayContent: String
        if type == .toolResult && content.count > Self.maxToolResultChars {
            displayContent = String(content.prefix(Self.maxToolResultChars)) + "\n… (truncated, \(content.count) chars total)"
        } else {
            displayContent = content
        }
        let msg = ChatMessage(role: role, content: displayContent, messageType: type, toolName: toolName)
        // Insert tool messages BEFORE the current assistant message so they appear above it
        if let currentMessageId,
           let idx = messages.firstIndex(where: { $0.id == currentMessageId }) {
            messages.insert(msg, at: idx)
        } else {
            messages.append(msg)
        }
        SessionServer.shared.broadcastMessage(msg)
    }

    private func handleError(_ error: Error) {
        logger.error("Error: \(error.localizedDescription)")
        self.error = error

        if let currentMessageId,
           let idx = messages.firstIndex(where: { $0.id == currentMessageId && !$0.isComplete }) {
            messages.remove(at: idx)
        }
    }

    func applyPreset(_ preset: WorkflowPreset) {
        if let model = preset.model { selectedModel = model }
        if let mode = preset.permissionMode { selectedPermissionMode = mode }
        if let dir = preset.workingDirectory { setWorkingDirectory(dir) }
    }

    func loadMessagesForSplit(sessionId: String) -> [ChatMessage] {
        if sessionId == currentSession?.id { return messages }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: messagesFile(for: sessionId)),
              let loaded = try? decoder.decode([ChatMessage].self, from: data) else {
            return []
        }
        return loaded
    }

    // MARK: - Export

    func exportSessionAsMarkdown(_ session: Session) {
        let msgs = session.id == currentSession?.id ? messages : loadMessages(for: session.id)
        let exportable = msgs.filter { $0.role == .user || $0.role == .assistant }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        var md = "# \(session.name)\n\nExported \(dateFormatter.string(from: Date()))\n\n---\n\n"
        for msg in exportable {
            let role = msg.role == .user ? "User" : "Assistant"
            md += "## \(role)\n\n\(msg.content)\n\n---\n\n"
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "\(session.name).md"
        if panel.runModal() == .OK, let url = panel.url {
            try? md.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Notifications

    private func sendCompletionNotificationIfNeeded(content: String) {
        guard !NSApplication.shared.isActive else { return }
        let center = UNUserNotificationCenter.current()
        let notifContent = UNMutableNotificationContent()
        notifContent.title = "Familiar"
        notifContent.body = String(content.prefix(100))
        notifContent.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: notifContent, trigger: nil)
        center.add(request)
    }

    // MARK: - Persistence

    private func ensureStorageDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.storageDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Self.messagesDirectory, withIntermediateDirectories: true)
    }

    private func saveSessions() {
        ensureStorageDirectories()
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: Self.sessionsFile, options: .atomic)
        } catch {
            logger.error("Failed to save sessions: \(error.localizedDescription)")
        }
    }

    private func loadSessions() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: Self.sessionsFile),
              let loaded = try? decoder.decode([Session].self, from: data) else {
            return
        }
        sessions = loaded
    }

    private func messagesFile(for sessionId: String) -> URL {
        Self.messagesDirectory.appendingPathComponent("\(sessionId).json")
    }

    private func saveMessages(for sessionId: String) {
        ensureStorageDirectories()
        let msgs = sessionMessages[sessionId] ?? []
        let persistable = msgs.filter { Self.persistableRoles.contains($0.role) }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(persistable)
            try data.write(to: messagesFile(for: sessionId), options: .atomic)
        } catch {
            logger.error("Failed to save messages for session \(sessionId): \(error.localizedDescription)")
        }
    }

    private func loadMessages(for sessionId: String) -> [ChatMessage] {
        if let cached = sessionMessages[sessionId] {
            touchSession(sessionId)
            return cached
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: messagesFile(for: sessionId)),
              let loaded = try? decoder.decode([ChatMessage].self, from: data) else {
            return []
        }
        sessionMessages[sessionId] = loaded
        touchSession(sessionId)
        evictOldSessions()
        return loaded
    }

    private func cacheCurrentMessages(for sessionId: String) {
        sessionMessages[sessionId] = messages
        touchSession(sessionId)
        evictOldSessions()
    }

    private func touchSession(_ sessionId: String) {
        sessionAccessOrder.removeAll { $0 == sessionId }
        sessionAccessOrder.append(sessionId)
    }

    private func evictOldSessions() {
        while sessionAccessOrder.count > Self.maxCachedSessions {
            let evicted = sessionAccessOrder.removeFirst()
            sessionMessages.removeValue(forKey: evicted)
        }
    }

    private func autoSave() {
        guard let session = currentSession else { return }
        cacheCurrentMessages(for: session.id)
        saveMessages(for: session.id)
        saveSessions()
    }

}
