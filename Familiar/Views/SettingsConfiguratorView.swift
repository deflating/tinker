import SwiftUI

// MARK: - Settings Tab

private enum SettingsTab: String, CaseIterable {
    case general = "General"
    case appearance = "Appearance"
    case agentProfile = "Agent Profile"
    case userProfile = "User Profile"
    case memories = "Memories"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .agentProfile: return "cpu"
        case .userProfile: return "person.fill"
        case .memories: return "brain.head.profile"
        }
    }
}

// MARK: - Main View

struct SettingsConfiguratorView: View {
    var seedManager: SeedManager
    var onDismiss: () -> Void

    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch selectedTab {
                case .general: generalTab
                case .appearance: appearanceTab
                case .agentProfile: agentProfileTab
                case .userProfile: userProfileTab
                case .memories: memoriesTab
                }
            }
            Divider()
            footer
        }
        .onAppear {
            seedManager.loadAll()
        }
        .background(FamiliarApp.canvasBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2.weight(.bold))
            Spacer()
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 500)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") {
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(FamiliarApp.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - General Tab

    @AppStorage("accentR") private var accentR = 0.2
    @AppStorage("accentG") private var accentG = 0.62
    @AppStorage("accentB") private var accentB = 0.58
    @AppStorage("customSystemPrompt") private var systemPrompt = ""
    @AppStorage("appendSystemPrompt") private var appendSystemPrompt = ""
    @AppStorage("agentProfileSystemPrompt") private var agentProfileSystemPrompt = ""
    @AppStorage("userProfileSystemPrompt") private var userProfileSystemPrompt = ""

    private struct AccentPreset: Identifiable {
        let id = UUID()
        let name: String
        let r: Double, g: Double, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
    }

    private let presets: [AccentPreset] = [
        .init(name: "Teal", r: 0.2, g: 0.62, b: 0.58),
        .init(name: "Amber", r: 0.82, g: 0.63, b: 0.22),
        .init(name: "Coral", r: 0.85, g: 0.42, b: 0.38),
        .init(name: "Violet", r: 0.55, g: 0.38, b: 0.78),
        .init(name: "Copper", r: 0.72, g: 0.45, b: 0.2),
        .init(name: "Sage", r: 0.42, g: 0.62, b: 0.45),
        .init(name: "Slate", r: 0.4, g: 0.48, b: 0.58),
        .init(name: "Rose", r: 0.78, g: 0.38, b: 0.52),
        .init(name: "Noir", r: 0.15, g: 0.15, b: 0.15),
        .init(name: "Rainbow", r: -1, g: -1, b: -1),
    ]

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // System Prompt
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("System Prompt Override")
                                .font(.callout.weight(.medium))
                            Text("Replaces the default system prompt sent to Claude.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextEditor(text: $systemPrompt)
                                .font(.system(size: 12))
                                .frame(minHeight: 60, maxHeight: 120)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(FamiliarApp.surfaceBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Prompts", systemImage: "text.bubble")
                }
            }
            .padding(20)
        }
    }

    // MARK: - Appearance Tab

    private var appearanceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                            ForEach(presets) { preset in
                                let isSelected = abs(accentR - preset.r) < 0.01
                                    && abs(accentG - preset.g) < 0.01
                                    && abs(accentB - preset.b) < 0.01
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        accentR = preset.r
                                        accentG = preset.g
                                        accentB = preset.b
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        if preset.r < 0 {
                                            Circle()
                                                .fill(
                                                    AngularGradient(
                                                        colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                        center: .center
                                                    )
                                                )
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
                                                        .padding(-3)
                                                )
                                        } else {
                                            Circle()
                                                .fill(preset.color)
                                                .frame(width: 32, height: 32)
                                                .overlay(
                                                    Circle()
                                                        .stroke(Color.primary, lineWidth: isSelected ? 2 : 0)
                                                        .padding(-3)
                                                )
                                        }
                                        Text(preset.name)
                                            .font(.caption2)
                                            .foregroundStyle(isSelected ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Signature Color", systemImage: "paintbrush")
                }
            }
            .padding(20)
        }
    }

    // MARK: - Agent Profile Tab

    private var agentProfileTab: some View {
        VStack(spacing: 0) {
            AgentConfiguratorView(onDismiss: onDismiss)
            Divider()
            // Append to System Prompt
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Append to System Prompt")
                        .font(.callout.weight(.medium))
                    Text("Agent personality and behavior instructions appended to the system prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $agentProfileSystemPrompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(FamiliarApp.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(4)
            } label: {
                Label("System Prompt", systemImage: "text.bubble")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - User Profile Tab

    private var userProfileTab: some View {
        VStack(spacing: 0) {
            UserConfiguratorView(onDismiss: onDismiss)
            Divider()
            // Append to System Prompt
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Append to System Prompt")
                        .font(.callout.weight(.medium))
                    Text("Personal context about you that gets appended to the system prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $userProfileSystemPrompt)
                        .font(.system(size: 12))
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(FamiliarApp.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(4)
            } label: {
                Label("System Prompt", systemImage: "text.bubble")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Memories Tab

    private var memoriesTab: some View {
        MemorySettingsView()
    }

}
