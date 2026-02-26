import SwiftUI

struct MemorableConfigView: View {
    var onBack: () -> Void
    @State private var memorable = MemorableAddOn.shared
    @State private var isDistilling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add-Ons")
                            .font(.callout)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Memorable")
                            .font(.title3.weight(.semibold))
                        Text("Working memory capture and distillation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Toggles
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        toggleRow(
                            label: "Capture",
                            hint: "Record conversations to per-session files in working/",
                            icon: "record.circle",
                            isOn: Binding(
                                get: { memorable.captureEnabled },
                                set: { memorable.captureEnabled = $0 }
                            )
                        )
                        Divider()
                        toggleRow(
                            label: "Distillation",
                            hint: "Periodically distill working notes into episodic and semantic memory",
                            icon: "flask",
                            isOn: Binding(
                                get: { memorable.distillationEnabled },
                                set: { memorable.distillationEnabled = $0 }
                            )
                        )
                    }
                    .padding(4)
                } label: {
                    Label("Features", systemImage: "switch.2")
                }

                // Distillation config (only when enabled)
                if memorable.distillationEnabled {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Frequency")
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Picker("", selection: Binding(
                                    get: { memorable.distillationFrequency },
                                    set: { memorable.distillationFrequency = $0 }
                                )) {
                                    Text("1x/day").tag(1)
                                    Text("2x/day").tag(2)
                                    Text("3x/day").tag(3)
                                    Text("4x/day").tag(4)
                                    Text("6x/day").tag(6)
                                }
                                .fixedSize()
                            }

                            Divider()

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Run Now")
                                        .font(.callout.weight(.medium))
                                    Text("Manually trigger distillation via Claude CLI")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isDistilling {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Distill") {
                                        isDistilling = true
                                        Task {
                                            await memorable.distiller.runNow()
                                            memorable.reloadFiles()
                                            isDistilling = false
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(4)
                    } label: {
                        Label("Distillation", systemImage: "flask")
                    }
                }

                // Working memory stats
                GroupBox {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session Files")
                                .font(.callout.weight(.medium))
                            Text("Per-session capture files in working/")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(memorable.writer.stats().fileCount) files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(memorable.workingSize), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            memorable.updateWorkingStats()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .controlSize(.small)
                        .help("Refresh stats")
                    }
                    .padding(4)
                } label: {
                    Label("Working Memory", systemImage: "waveform")
                }

                // Memory files preview
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        readOnlyFileRow(
                            name: "episodic.md",
                            hint: "Rolling 5-day summary — distilled from working notes",
                            content: memorable.episodicContent
                        )
                        Divider()
                        readOnlyFileRow(
                            name: "semantic.md",
                            hint: "Long-term knowledge — graduated from episodic",
                            content: memorable.semanticContent
                        )
                    }
                    .padding(4)
                } label: {
                    Label("Memory Files", systemImage: "brain")
                }

                // Directory
                GroupBox {
                    HStack {
                        Text("Data Directory")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(memorable.directory)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…") { pickDirectory() }
                            .controlSize(.small)
                    }
                    .padding(4)
                } label: {
                    Label("Configuration", systemImage: "folder")
                }
            }
            .padding(20)
        }
    }

    // MARK: - Row Builders

    @ViewBuilder
    private func toggleRow(label: String, hint: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout.weight(.medium))
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    @ViewBuilder
    private func readOnlyFileRow(name: String, hint: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.callout.weight(.medium))
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if content.isEmpty {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                } else {
                    Text("\(content.count) chars")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }

            if !content.isEmpty {
                Text(content.prefix(500) + (content.count > 500 ? "\n…" : ""))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Actions

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: memorable.directory)
        if panel.runModal() == .OK, let url = panel.url {
            memorable.directory = url.path
            memorable.reloadFiles()
        }
    }
}
