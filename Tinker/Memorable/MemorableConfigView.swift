import SwiftUI

struct MemorableConfigView: View {
    var onBack: () -> Void
    @State private var memorable = MemorableAddOn.shared
    @State private var isDistilling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Back button
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

                // Header
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Memorable")
                            .font(.title3.weight(.semibold))
                        Text("Memory system — capture, distill, inject")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Toggle controls
                togglesSection

                // Directory
                directorySection

                // Working memory stats
                workingMemorySection

                // Memory files (read-only)
                memoryFilesSection

                // Distillation
                distillationSection
            }
            .padding(20)
        }
    }

    // MARK: - Sections

    private var togglesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                toggleRow(
                    label: "Capture",
                    hint: "Record conversation to working.md in real-time",
                    icon: "record.circle",
                    isOn: Binding(
                        get: { memorable.captureEnabled },
                        set: { memorable.captureEnabled = $0 }
                    )
                )
                Divider()
                toggleRow(
                    label: "Injection",
                    hint: "Instruct Claude to read memory files on first message",
                    icon: "syringe",
                    isOn: Binding(
                        get: { memorable.injectionEnabled },
                        set: { memorable.injectionEnabled = $0 }
                    )
                )
                Divider()
                toggleRow(
                    label: "Distillation",
                    hint: "Scheduled Haiku calls to distill and graduate knowledge",
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
    }

    private var directorySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
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

                if memorable.distillationEnabled {
                    Divider()
                    HStack {
                        Text("Distillation Frequency")
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
                        Text("Haiku API Key")
                            .font(.callout.weight(.medium))
                        Spacer()
                        SecureField("sk-ant-...", text: Binding(
                            get: { memorable.apiKey },
                            set: { memorable.apiKey = $0 }
                        ))
                        .frame(width: 220)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Configuration", systemImage: "folder")
        }
    }

    private var workingMemorySection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("working.md")
                        .font(.callout.weight(.medium))
                    Text("Raw conversation transcript, captured in real-time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(memorable.workingLineCount) lines")
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
    }

    private var memoryFilesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                readOnlyFileRow(
                    name: "episodic.md",
                    hint: "Rolling 5-day summary — distilled from working.md",
                    content: memorable.episodicContent
                )

                Divider()

                readOnlyFileRow(
                    name: "semantic.md",
                    hint: "Long-term knowledge — immutable identity + graduated facts",
                    content: memorable.semanticContent
                )
            }
            .padding(4)
        } label: {
            Label("Memory Files", systemImage: "brain")
        }
    }

    private var distillationSection: some View {
        GroupBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run Distillation Now")
                        .font(.callout.weight(.medium))
                    Text("Manually trigger episodic + semantic distillation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDistilling {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Distill") {
                        guard !memorable.apiKey.isEmpty else { return }
                        isDistilling = true
                        Task {
                            await memorable.distiller.runNow()
                            memorable.reloadFiles()
                            isDistilling = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(memorable.apiKey.isEmpty)
                }
            }
            .padding(4)
        } label: {
            Label("Distillation", systemImage: "flask")
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
