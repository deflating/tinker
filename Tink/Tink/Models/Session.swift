import Foundation

// Mirror of Tinker's Session model.

struct Session: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var lastMessage: String
    var updatedAt: Date
    var cliSessionId: String?
    var workingDirectory: String?
    var isPinned: Bool
    var threadId: String?
    var tags: [String]
}
