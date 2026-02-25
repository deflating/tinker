import SwiftUI

// MARK: - Option Banks

private let neurodivergenceOptions = UserConfigurationDefaults.neurodivergenceOptions
private let valueOptions = UserConfigurationDefaults.valueOptions
private let cognitiveStyleOptions = UserConfigurationDefaults.cognitiveStyleOptions

// MARK: - UserConfiguratorView

struct UserConfiguratorView: View {
    var onDismiss: () -> Void

    @State private var config = UserConfiguration()
    @State private var showingImport = false

    @State private var previewMode: PreviewMode = .markdown

    private enum PreviewMode: String, CaseIterable {
        case markdown = "Markdown"
        case richText = "Rich Text"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                // Editor panel
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        identitySection
                        aboutSection
                        neurodivergenceSection
                        cognitiveStyleSection
                        valuesSection
                        interestsSection
                        peopleSection
                        projectsSection
                        customSectionsSection
                        customInstructionsSection
                    }
                    .padding(20)
                }
                .frame(maxWidth: .infinity)
                Divider()
                // Preview panel
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Preview").font(.headline)
                        Spacer()
                        Picker("", selection: $previewMode) {
                            ForEach(PreviewMode.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    ScrollView {
                        Group {
                            if previewMode == .markdown {
                                Text(config.toMarkdown())
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                if let attr = try? AttributedString(markdown: config.toMarkdown(), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                                    Text(attr).font(.system(size: 12))
                                } else {
                                    Text(config.toMarkdown()).font(.system(size: 12))
                                }
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
                .frame(maxWidth: .infinity)
                .background(FamiliarApp.surfaceBackground.opacity(0.55))
            }
            Divider()
            footer
        }
        .background(FamiliarApp.canvasBackground)
        .onAppear {
            if let saved = UserConfiguration.load() {
                config = saved
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("User Profile")
                .font(.title2.weight(.bold))
            Spacer()
            Button {
                showingImport = true
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .fileImporter(isPresented: $showingImport, allowedContentTypes: [.plainText]) { result in
                if case .success(let url) = result,
                   url.startAccessingSecurityScopedResource(),
                   let content = try? String(contentsOf: url, encoding: .utf8) {
                    url.stopAccessingSecurityScopedResource()
                    withAnimation { config = UserConfiguration.fromMarkdown(content) }
                }
            }
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
            Button("Reset") {
                config = UserConfiguration()
            }
            .buttonStyle(.bordered)
            Spacer()
            Button("Save") {
                UserConfiguration.save(config)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(FamiliarApp.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 1. Identity

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                formRow("Name") {
                    TextField("Your name", text: $config.identity.name)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Age") {
                    TextField("Age", value: $config.identity.age, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                formRow("Location") {
                    TextField("City, Country", text: $config.identity.location)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Language") {
                    TextField("Primary language", text: $config.identity.language)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Timezone") {
                    TextField("e.g. America/New_York", text: $config.identity.timezone)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Pronouns") {
                    Picker("", selection: $config.identity.pronouns) {
                        ForEach(UserConfiguration.PronounOption.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
            }
            .padding(4)
        } label: {
            Label("Identity", systemImage: "person.fill")
        }
    }

    // MARK: - 2. About

    private var aboutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tell the AI about yourself in your own words.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $config.about)
                    .font(.system(size: 12))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(FamiliarApp.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(4)
        } label: {
            Label("About", systemImage: "text.alignleft")
        }
    }

    // MARK: - 3. Neurodivergence

    @State private var showingNDPopover = false
    @State private var customNDEntry = ""

    private var neurodivergenceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(config.neurodivergence.enumerated()), id: \.element.id) { idx, _ in
                    HStack {
                        Picker("", selection: Binding(
                            get: { config.neurodivergence[idx].qualifier },
                            set: { config.neurodivergence[idx].qualifier = $0 }
                        )) {
                            ForEach(UserConfiguration.NDQualifier.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .frame(width: 120)
                        Text(config.neurodivergence[idx].label)
                            .font(.callout)
                        Spacer()
                        Button {
                            withAnimation { _ = config.neurodivergence.remove(at: idx) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add custom...", text: $customNDEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = customNDEntry.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                withAnimation { config.neurodivergence.append(.init(label: trimmed)) }
                                customNDEntry = ""
                            }
                        }
                    Button {
                        showingNDPopover = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(FamiliarApp.accent)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingNDPopover, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Options")
                                .font(.headline)
                                .padding(.bottom, 4)
                            ForEach(neurodivergenceOptions.filter { opt in
                                !config.neurodivergence.contains(where: { $0.label == opt })
                            }, id: \.self) { option in
                                Button {
                                    withAnimation { config.neurodivergence.append(.init(label: option)) }
                                    showingNDPopover = false
                                } label: {
                                    Text(option)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(12)
                        .frame(width: 240)
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Neurodivergence", systemImage: "brain.head.profile")
        }
    }

    // MARK: - 4. Cognitive Style

    private var cognitiveStyleSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(config.cognitiveStyle.enumerated()), id: \.element.id) { idx, entry in
                    HStack {
                        Picker("", selection: Binding(
                            get: { config.cognitiveStyle[idx].key },
                            set: { config.cognitiveStyle[idx].key = $0 }
                        )) {
                            ForEach(UserConfiguration.CognitiveStyleKey.allCases, id: \.self) {
                                Text($0.label).tag($0)
                            }
                        }
                        .frame(width: 150)

                        if entry.key == .custom {
                            TextField("Key", text: Binding(
                                get: { config.cognitiveStyle[idx].customKey },
                                set: { config.cognitiveStyle[idx].customKey = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                        }

                        if entry.key != .custom,
                           let options = cognitiveStyleOptions[entry.key.rawValue] {
                            Picker("", selection: Binding(
                                get: { config.cognitiveStyle[idx].value },
                                set: { config.cognitiveStyle[idx].value = $0 }
                            )) {
                                Text("Select...").tag("")
                                ForEach(options, id: \.self) { Text($0).tag($0) }
                            }
                            .frame(minWidth: 180)
                        } else {
                            TextField("Value", text: Binding(
                                get: { config.cognitiveStyle[idx].value },
                                set: { config.cognitiveStyle[idx].value = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        Button {
                            withAnimation { _ = config.cognitiveStyle.remove(at: idx) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    withAnimation { config.cognitiveStyle.append(.init()) }
                } label: {
                    Label("Add Entry", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Cognitive Style", systemImage: "lightbulb")
        }
    }

    // MARK: - 5. Values

    @State private var showingValuesPopover = false
    @State private var customValueEntry = ""

    private var valuesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(config.values.enumerated()), id: \.offset) { index, item in
                    HStack {
                        Text(item)
                            .font(.callout)
                        Spacer()
                        Button {
                            withAnimation { _ = config.values.remove(at: index) }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("Add value...", text: $customValueEntry)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            let trimmed = customValueEntry.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty && !config.values.contains(trimmed) {
                                withAnimation { config.values.append(trimmed) }
                                customValueEntry = ""
                            }
                        }
                    Button {
                        showingValuesPopover = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(FamiliarApp.accent)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingValuesPopover, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Options")
                                .font(.headline)
                                .padding(.bottom, 4)
                            ForEach(valueOptions.filter { !config.values.contains($0) }, id: \.self) { option in
                                Button {
                                    withAnimation { config.values.append(option) }
                                    showingValuesPopover = false
                                } label: {
                                    Text(option)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .padding(.vertical, 2)
                                .padding(.horizontal, 8)
                                .contentShape(Rectangle())
                            }
                        }
                        .padding(12)
                        .frame(width: 280)
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Values", systemImage: "heart.fill")
        }
    }

    // MARK: - 6. Interests

    private var interestsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(config.interests.enumerated()), id: \.element.id) { idx, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Interest name", text: Binding(
                                get: { config.interests[idx].name },
                                set: { config.interests[idx].name = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .fontWeight(.medium)
                            Button {
                                withAnimation { _ = config.interests.remove(at: idx) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Description", text: Binding(
                            get: { config.interests[idx].description },
                            set: { config.interests[idx].description = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    }
                    if idx < config.interests.count - 1 { Divider() }
                }
                Button {
                    withAnimation { config.interests.append(.init()) }
                } label: {
                    Label("Add Interest", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Interests", systemImage: "star")
        }
    }

    // MARK: - 7. People

    private var peopleSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(config.people.enumerated()), id: \.element.id) { idx, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Name", text: Binding(
                                get: { config.people[idx].name },
                                set: { config.people[idx].name = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .fontWeight(.medium)

                            Picker("", selection: Binding(
                                get: { config.people[idx].relationship },
                                set: { config.people[idx].relationship = $0 }
                            )) {
                                ForEach(UserConfiguration.RelationshipType.allCases, id: \.self) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .frame(width: 140)

                            Button {
                                withAnimation { _ = config.people.remove(at: idx) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Description", text: Binding(
                            get: { config.people[idx].description },
                            set: { config.people[idx].description = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    }
                    if idx < config.people.count - 1 { Divider() }
                }
                Button {
                    withAnimation { config.people.append(.init()) }
                } label: {
                    Label("Add Person", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("People", systemImage: "person.2")
        }
    }

    // MARK: - 8. Projects

    private var projectsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(config.projects.enumerated()), id: \.element.id) { idx, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Project name", text: Binding(
                                get: { config.projects[idx].name },
                                set: { config.projects[idx].name = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .fontWeight(.medium)

                            Picker("", selection: Binding(
                                get: { config.projects[idx].status },
                                set: { config.projects[idx].status = $0 }
                            )) {
                                ForEach(UserConfiguration.ProjectStatus.allCases, id: \.self) {
                                    Text($0.label).tag($0)
                                }
                            }
                            .frame(width: 120)

                            Button {
                                withAnimation { _ = config.projects.remove(at: idx) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Description", text: Binding(
                            get: { config.projects[idx].description },
                            set: { config.projects[idx].description = $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    }
                    if idx < config.projects.count - 1 { Divider() }
                }
                Button {
                    withAnimation { config.projects.append(.init()) }
                } label: {
                    Label("Add Project", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Projects", systemImage: "folder")
        }
    }

    // MARK: - 9. Custom Sections

    private var customSectionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(config.customSections.enumerated()), id: \.element.id) { idx, _ in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Section Title", text: Binding(
                                get: { config.customSections[idx].title },
                                set: { config.customSections[idx].title = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .fontWeight(.medium)
                            Button {
                                withAnimation { _ = config.customSections.remove(at: idx) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                        TextEditor(text: Binding(
                            get: { config.customSections[idx].body },
                            set: { config.customSections[idx].body = $0 }
                        ))
                        .font(.system(size: 12))
                        .frame(minHeight: 60, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(FamiliarApp.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if idx < config.customSections.count - 1 { Divider() }
                }
                Button {
                    withAnimation {
                        config.customSections.append(.init())
                    }
                } label: {
                    Label("Add Section", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Custom Sections", systemImage: "rectangle.stack.badge.plus")
        }
    }

    // MARK: - 10. Custom Instructions

    @State private var customInstructions = ""

    private var customInstructionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Freeform instructions appended to your user profile.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $customInstructions)
                    .font(.system(size: 12))
                    .frame(minHeight: 80, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(FamiliarApp.surfaceBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(4)
        } label: {
            Label("Custom Instructions", systemImage: "pencil.and.list.clipboard")
        }
    }

    // MARK: - Helpers

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.callout.weight(.medium))
            Spacer()
            content()
        }
    }
}
