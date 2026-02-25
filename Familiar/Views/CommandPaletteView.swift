import SwiftUI

struct CommandPaletteView: View {
    @Binding var isPresented: Bool
    let onAction: (PaletteAction) -> Void
    @State private var searchText = ""
    @State private var selectedIndex = 0

    enum PaletteAction: String, CaseIterable {
        case newSession = "New Session"
        case clearConversation = "Clear Conversation"
        case compactContext = "Compact Context"
        case cancelRequest = "Cancel Request"
        case openSettings = "Settings"
        case runDoctor = "Run Diagnostics"
        case pickDirectory = "Change Working Directory"
        case exportMarkdown = "Export as Markdown"

        var icon: String {
            switch self {
            case .newSession: return "plus"
            case .clearConversation: return "trash"
            case .compactContext: return "arrow.down.right.and.arrow.up.left"
            case .cancelRequest: return "stop.circle"
            case .openSettings: return "gearshape"
            case .runDoctor: return "stethoscope"
            case .pickDirectory: return "folder"
            case .exportMarkdown: return "square.and.arrow.up"
            }
        }

        var shortcut: String? {
            switch self {
            case .newSession: return "⌘N"
            case .clearConversation: return "⌘K"
            case .cancelRequest: return "Esc"
            case .openSettings: return "⌘,"
            default: return nil
            }
        }
    }

    private var filteredActions: [PaletteAction] {
        if searchText.isEmpty { return PaletteAction.allCases }
        return PaletteAction.allCases.filter {
            $0.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredPresets: [WorkflowPreset] {
        let all = WorkflowPreset.all
        if searchText.isEmpty { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var totalItems: Int { filteredActions.count + filteredPresets.count }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            actionsList
        }
        .frame(width: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        .onKeyPress(.upArrow) {
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            selectedIndex = min(filteredActions.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
        .onChange(of: searchText) {
            selectedIndex = 0
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("Type a command…", text: $searchText)
                .font(.body)
                .textFieldStyle(.plain)
                .onSubmit {
                    if let action = filteredActions[safe: selectedIndex] {
                        onAction(action)
                        isPresented = false
                    }
                }
        }
        .padding(12)
    }

    private var actionsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(filteredActions.enumerated()), id: \.element) { index, action in
                    paletteRow(action: action, index: index)
                }

                if !filteredPresets.isEmpty {
                    HStack {
                        Text("PRESETS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    ForEach(filteredPresets) { preset in
                        presetRow(preset: preset)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 300)
    }

    private func paletteRow(action: PaletteAction, index: Int) -> some View {
        Button(action: {
            onAction(action)
            isPresented = false
        }) {
            HStack(spacing: 10) {
                Image(systemName: action.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(index == selectedIndex ? .white : .secondary)
                    .frame(width: 20)
                Text(action.rawValue)
                    .font(.body)
                    .foregroundStyle(index == selectedIndex ? .white : .primary)
                Spacer()
                if let shortcut = action.shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(index == selectedIndex ? Color.white.opacity(0.7) : Color.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(index == selectedIndex ? FamiliarApp.accent : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    private func presetRow(preset: WorkflowPreset) -> some View {
        Button(action: {
            NotificationCenter.default.post(name: .applyWorkflowPreset, object: preset)
            isPresented = false
        }) {
            HStack(spacing: 10) {
                Image(systemName: preset.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(FamiliarApp.accent)
                    .frame(width: 20)
                Text(preset.name)
                    .font(.body)
                Spacer()
                if let model = preset.model {
                    let label = ChatViewModel.availableModels.first(where: { $0.0 == model })?.1 ?? model
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
