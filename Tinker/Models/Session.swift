import Foundation

struct Session: Identifiable, Codable {
    let id: String
    var name: String
    var lastMessage: String
    var updatedAt: Date
    var cliSessionId: String?
    var workingDirectory: String?
    /// Path to the git worktree if this session uses one
    var worktreePath: String?
    /// The original repo directory the worktree was created from
    var worktreeOrigin: String?

    // Organisation
    var isPinned: Bool
    var threadId: String?
    var tags: [String]

    var isWorktree: Bool { worktreePath != nil }

    init(id: String = UUID().uuidString, name: String = "New Session", lastMessage: String = "", cliSessionId: String? = nil, workingDirectory: String? = nil, worktreePath: String? = nil, worktreeOrigin: String? = nil, isPinned: Bool = false, threadId: String? = nil, tags: [String] = []) {
        self.id = id
        self.name = name
        self.lastMessage = lastMessage
        self.updatedAt = Date()
        self.cliSessionId = cliSessionId
        self.workingDirectory = workingDirectory
        self.worktreePath = worktreePath
        self.worktreeOrigin = worktreeOrigin
        self.isPinned = isPinned
        self.threadId = threadId
        self.tags = tags
    }
}

// MARK: - Thread

struct SessionThread: Identifiable, Codable {
    let id: String
    var name: String
    var color: String  // SF Symbol color name or hex
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, color: String = "blue") {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
    }

    static let threadColors = [
        "blue", "purple", "pink", "red", "orange", "yellow", "green", "teal", "cyan", "indigo"
    ]
}
