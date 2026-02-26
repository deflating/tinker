import SwiftUI

struct FamiliarConfigView: View {
    var onBack: () -> Void
    @State private var familiar = FamiliarAddOn.shared
    @State private var editingPreferences = false
    @State private var editingPersona = false
    @State private var preferencesText = ""
    @State private var personaText = ""

    var body: some View {
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
                Image(systemName: "person.text.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Familiar")
                        .font(.title3.weight(.semibold))
                    Text("Identity and persona seed files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Seeds Directory")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(familiar.directory)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Change…") {
                            pickDirectory()
                        }
                        .controlSize(.small)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preferences Configurator")
                                .font(.callout.weight(.medium))
                            Text("Visual editor for generating your preferences.md file")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Configurator") {
                            openConfigurator()
                        }
                        .controlSize(.small)
                    }
                }
                .padding(4)
            } label: {
                Label("Configuration", systemImage: "folder")
            }

            // Seed files
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    seedFileRow(
                        name: "preferences.md",
                        hint: "User preferences — who you are, how you like Claude to behave",
                        content: familiar.preferencesContent,
                        modified: familiar.preferencesModified,
                        isEditing: $editingPreferences,
                        editText: $preferencesText,
                        onSave: { familiar.savePreferences(preferencesText) }
                    )

                    Divider()

                    seedFileRow(
                        name: "persona.md",
                        hint: "Claude's self-authored identity document",
                        content: familiar.personaContent,
                        modified: familiar.personaModified,
                        isEditing: $editingPersona,
                        editText: $personaText,
                        onSave: { familiar.savePersona(personaText) }
                    )
                }
                .padding(4)
            } label: {
                Label("Seed Files", systemImage: "doc.text")
            }

            Spacer()
        }
        .padding(20)
    }

    @ViewBuilder
    private func seedFileRow(
        name: String,
        hint: String,
        content: String,
        modified: Date?,
        isEditing: Binding<Bool>,
        editText: Binding<String>,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.callout.weight(.medium))
                    if let modified {
                        Text("Modified \(modified.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if content.isEmpty && modified == nil {
                    Text("Not created")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                } else if content.isEmpty {
                    Text("Empty")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                } else {
                    Text("\(content.count) chars")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
                Button(isEditing.wrappedValue ? "Done" : "Edit") {
                    if isEditing.wrappedValue {
                        onSave()
                        isEditing.wrappedValue = false
                    } else {
                        editText.wrappedValue = content
                        isEditing.wrappedValue = true
                    }
                }
                .controlSize(.small)
            }

            if isEditing.wrappedValue {
                TextEditor(text: editText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150, maxHeight: 300)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.08))
                    )
            }
        }
    }

    private func openConfigurator() {
        if let url = Bundle.main.url(forResource: "FamiliarConfigurator", withExtension: "html") {
            NSWorkspace.shared.open(url)
        }
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: familiar.directory)
        if panel.runModal() == .OK, let url = panel.url {
            familiar.directory = url.path
            familiar.reload()
        }
    }
}
