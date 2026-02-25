import Foundation

struct ChatMessage: Identifiable, Equatable, Codable {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var isComplete: Bool
    var messageType: MessageType
    var toolName: String?

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isComplete: Bool = true,
        messageType: MessageType = .text,
        toolName: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isComplete = isComplete
        self.messageType = messageType
        self.toolName = toolName
    }

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.content == rhs.content &&
        lhs.isComplete == rhs.isComplete &&
        lhs.messageType == rhs.messageType
    }
}

enum MessageType: String, Codable {
    case text
    case toolUse
    case toolResult
    case toolError
    case thinking
    case webSearch
}

enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case toolUse
    case toolResult
    case toolError
    case thinking
}

// MARK: - Queued Message (for message queue feature)

struct QueuedMessage: Identifiable, Equatable {
    let id: UUID
    var text: String
    let queuedAt: Date

    init(text: String) {
        self.id = UUID()
        self.text = text
        self.queuedAt = Date()
    }
}
