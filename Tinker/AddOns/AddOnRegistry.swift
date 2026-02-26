import Foundation

/// Central registry of all Tinker add-ons.
@MainActor
enum AddOnRegistry {
    static let all: [any TinkerAddOn] = [
        FamiliarAddOn.shared,
        MemorableAddOn.shared,
    ]

    /// Combined system prompt content from all enabled add-ons.
    static var combinedSystemPrompt: String? {
        let parts = all.compactMap(\.systemPromptContent)
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: "\n\n---\n\n")
    }
}
