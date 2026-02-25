import SwiftUI

// MARK: - Settings Tab

private enum SettingsTab: String, CaseIterable {
    case appearance = "Appearance"
    case systemPrompt = "System Prompt"

    var icon: String {
        switch self {
        case .appearance: return "paintbrush"
        case .systemPrompt: return "text.bubble"
        }
    }
}

// MARK: - Main View

struct SettingsConfiguratorView: View {
    var onDismiss: () -> Void

    @State private var selectedTab: SettingsTab = .appearance

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Group {
                switch selectedTab {
                case .appearance: appearanceTab
                case .systemPrompt: systemPromptTab
                }
            }
            Divider()
            footer
        }
        .background(TinkerApp.canvasBackground)
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
            .frame(width: 300)
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
            .tint(TinkerApp.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Appearance Tab

    @AppStorage("accentR") private var accentR = 0.2
    @AppStorage("accentG") private var accentG = 0.62
    @AppStorage("accentB") private var accentB = 0.58

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

    // MARK: - System Prompt Tab

    @AppStorage("systemPromptMode") private var systemPromptMode: String = "off"
    @AppStorage("customSystemPrompt") private var customSystemPrompt: String = ""

    private var systemPromptTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Mode", selection: $systemPromptMode) {
                        Text("Off").tag("off")
                        Text("Override").tag("override")
                        Text("Append").tag("append")
                    }
                    .pickerStyle(.segmented)

                    switch systemPromptMode {
                    case "override":
                        Text("Replaces the default system prompt entirely.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    case "append":
                        Text("Appended to the existing system prompt.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    default:
                        Text("No custom system prompt is used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
            } label: {
                Label("Mode", systemImage: "slider.horizontal.3")
            }

            if systemPromptMode != "off" {
                GroupBox {
                    TextEditor(text: $customSystemPrompt)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200)
                        .scrollContentBackground(.hidden)
                } label: {
                    Label("Prompt Text", systemImage: "text.alignleft")
                }
            }

            Spacer()
        }
        .padding(20)
    }
}
