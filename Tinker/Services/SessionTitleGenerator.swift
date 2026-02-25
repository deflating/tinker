import Foundation
import FoundationModels

@MainActor
class SessionTitleGenerator {
    static let shared = SessionTitleGenerator()

    private var generationTasks: [String: Task<Void, Never>] = [:]

    /// Generate a session title from conversation messages.
    /// Call after first user message, then again after first assistant reply and after ~5 exchanges.
    func generateTitle(
        for sessionId: String,
        messages: [ChatMessage],
        onTitle: @escaping (String) -> Void
    ) {
        // Cancel any in-flight generation for this session
        generationTasks[sessionId]?.cancel()

        let conversationContext = messages
            .filter { $0.role == .user || $0.role == .assistant }
            .prefix(10)
            .map { msg in
                let role = msg.role == .user ? "User" : "Assistant"
                return "\(role): \(String(msg.content.prefix(300)))"
            }
            .joined(separator: "\n")

        guard !conversationContext.isEmpty else { return }

        generationTasks[sessionId] = Task {
            do {
                let session = LanguageModelSession()
                let prompt = """
                Generate a short, descriptive title (3-6 words) for this conversation. \
                Return ONLY the title, no quotes, no punctuation at the end, no explanation.

                \(conversationContext)
                """
                let response = try await session.respond(to: prompt)
                let title = response.content
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'."))

                guard !Task.isCancelled, !title.isEmpty else { return }
                onTitle(String(title.prefix(60)))
            } catch {
                // Silently fail — the fallback title from the first message is fine
            }
            generationTasks.removeValue(forKey: sessionId)
        }
    }
}
