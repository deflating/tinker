import Foundation
import Observation

@Observable
final class MCPExtensionManager {
    var extensions: [MCPExtension] = []
    var isLoading = false

    /// Recommended max tools before performance degrades
    static let toolWarningThreshold = 50
    /// Recommended max extensions
    static let extensionWarningThreshold = 5

    private let configPath: String

    init() {
        self.configPath = NSHomeDirectory() + "/.claude.json"
        loadExtensions()
    }

    var estimatedTotalTools: Int {
        extensions.filter(\.enabled).reduce(0) { $0 + $1.estimatedToolCount }
    }

    var hasToolWarning: Bool {
        extensions.filter(\.enabled).count > Self.extensionWarningThreshold
            || estimatedTotalTools > Self.toolWarningThreshold
    }

    var enabledCount: Int {
        extensions.filter(\.enabled).count
    }

    // MARK: - Read

    func loadExtensions() {
        guard let data = FileManager.default.contents(atPath: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: Any] else {
            extensions = []
            return
        }

        extensions = servers.compactMap { key, value -> MCPExtension? in
            guard let config = value as? [String: Any] else { return nil }
            let typeStr = config["type"] as? String ?? "stdio"
            let type = MCPExtension.MCPType(rawValue: typeStr) ?? .stdio

            // Look up catalog for friendly name/description
            let catalog = MCPCatalogEntry.find(key)

            return MCPExtension(
                id: key,
                name: catalog?.name ?? key.replacingOccurrences(of: "-", with: " ").capitalized,
                description: catalog?.description ?? "",
                type: type,
                command: config["command"] as? String,
                args: config["args"] as? [String],
                url: config["url"] as? String,
                env: config["env"] as? [String: String] ?? [:],
                enabled: true  // If it's in the config, it's enabled
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Write

    func saveExtensions() {
        guard let data = FileManager.default.contents(atPath: configPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        var servers: [String: Any] = [:]
        for ext in extensions where ext.enabled {
            var config: [String: Any] = ["type": ext.type.rawValue]
            if let cmd = ext.command { config["command"] = cmd }
            if let args = ext.args { config["args"] = args }
            if let url = ext.url { config["url"] = url }
            if !ext.env.isEmpty { config["env"] = ext.env }
            servers[ext.id] = config
        }

        json["mcpServers"] = servers

        if let outData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? outData.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - Mutations

    func toggle(_ extension_: MCPExtension) {
        guard let idx = extensions.firstIndex(where: { $0.id == extension_.id }) else { return }
        extensions[idx].enabled.toggle()
        saveExtensions()
    }

    func install(from catalog: MCPCatalogEntry, env: [String: String] = [:]) {
        // Check if already installed
        if extensions.contains(where: { $0.id == catalog.id }) { return }

        let ext = MCPExtension(
            id: catalog.id,
            name: catalog.name,
            description: catalog.description,
            type: catalog.type,
            command: catalog.command,
            args: catalog.args,
            url: catalog.url,
            env: env,
            enabled: true
        )
        extensions.append(ext)
        extensions.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveExtensions()
    }

    func installCustom(id: String, name: String, type: MCPExtension.MCPType, command: String?, args: [String]?, url: String?, env: [String: String]) {
        let ext = MCPExtension(
            id: id,
            name: name,
            description: "Custom extension",
            type: type,
            command: command,
            args: args,
            url: url,
            env: env,
            enabled: true
        )
        extensions.append(ext)
        extensions.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveExtensions()
    }

    func remove(_ extension_: MCPExtension) {
        extensions.removeAll { $0.id == extension_.id }
        saveExtensions()
    }

    func updateEnv(for extensionId: String, key: String, value: String) {
        guard let idx = extensions.firstIndex(where: { $0.id == extensionId }) else { return }
        extensions[idx].env[key] = value
        saveExtensions()
    }
}
