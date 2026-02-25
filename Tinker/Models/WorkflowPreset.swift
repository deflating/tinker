import Foundation

struct WorkflowPreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var model: String?
    var permissionMode: String?
    var workingDirectory: String?

    static let builtIn: [WorkflowPreset] = [
        WorkflowPreset(
            id: "fast-iterate",
            name: "Fast Iterate",
            icon: "hare",
            model: "claude-haiku-4-5-20251001",
            permissionMode: "bypassPermissions"
        ),
        WorkflowPreset(
            id: "careful-review",
            name: "Careful Review",
            icon: "shield.checkered",
            model: "claude-opus-4-6",
            permissionMode: "default"
        ),
        WorkflowPreset(
            id: "plan-first",
            name: "Plan First",
            icon: "list.clipboard",
            model: "claude-sonnet-4-6",
            permissionMode: "plan"
        ),
        WorkflowPreset(
            id: "yolo",
            name: "YOLO",
            icon: "bolt.shield",
            model: "claude-sonnet-4-6",
            permissionMode: "bypassPermissions"
        ),
    ]

    static func loadCustom() -> [WorkflowPreset] {
        guard let data = UserDefaults.standard.data(forKey: "customWorkflowPresets"),
              let presets = try? JSONDecoder().decode([WorkflowPreset].self, from: data) else {
            return []
        }
        return presets
    }

    static func saveCustom(_ presets: [WorkflowPreset]) {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: "customWorkflowPresets")
        }
    }

    static var all: [WorkflowPreset] {
        builtIn + loadCustom()
    }
}
