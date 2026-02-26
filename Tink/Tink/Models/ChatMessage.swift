import Foundation

// Mirror of Tinker's ChatMessage — decoded from WebSocket sync/broadcast payloads.

struct ChatMessage: Identifiable, Equatable, Codable {
    var id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date
    var isComplete: Bool
    var messageType: MessageType
    var toolName: String?
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
