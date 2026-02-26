import Foundation

/// Protocol for Tinker add-ons. Each add-on can inject context into sessions
/// and provide its own configuration UI.
protocol TinkerAddOn: Identifiable {
    var id: String { get }
    var name: String { get }
    var icon: String { get }  // SF Symbol name
    var description: String { get }
    var isEnabled: Bool { get set }

    /// Content to append to the system prompt at session start. Return nil to skip.
    var systemPromptContent: String? { get }
}
