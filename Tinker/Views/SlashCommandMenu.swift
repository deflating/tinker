import SwiftUI

struct SlashCommand: Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let isAgent: Bool

    static let builtIn: [SlashCommand] = [
        SlashCommand(id: "compact", name: "/compact", description: "Compact conversation context", isAgent: false),
        SlashCommand(id: "clear", name: "/clear", description: "Clear conversation", isAgent: false),
        SlashCommand(id: "help", name: "/help", description: "Show help", isAgent: false),
    ]

    static func loadAgents() -> [SlashCommand] {
        let agentsDir = NSHomeDirectory() + "/.claude/agents"
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: agentsDir) else { return [] }
        return files
            .filter { $0.hasSuffix(".md") }
            .map { file in
                let name = String(file.dropLast(3))
                return SlashCommand(id: "agent-\(name)", name: "/\(name)", description: "Agent", isAgent: true)
            }
            .sorted { $0.name < $1.name }
    }

    static func allCommands() -> [SlashCommand] {
        builtIn + loadAgents()
    }
}

struct FileMentionMenu: View {
    let files: [String]
    let selectedIndex: Int
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(files.enumerated()), id: \.element) { index, file in
                Button(action: { onSelect(file) }) {
                    HStack(spacing: 8) {
                        Image(systemName: fileIcon(file))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(file)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: -2)
    }

    private func fileIcon(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md": return "doc.text"
        case "json", "yaml", "yml", "toml": return "gearshape"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        case "": return "folder"
        default: return "doc"
        }
    }
}

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let selectedIndex: Int
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(commands.enumerated()), id: \.element.id) { index, command in
                Button(action: { onSelect(command) }) {
                    HStack(spacing: 8) {
                        Image(systemName: command.isAgent ? "person.circle" : "terminal")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(command.name)
                            .font(.body.weight(.medium))
                        Spacer()
                        Text(command.description)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: -2)
    }
}
