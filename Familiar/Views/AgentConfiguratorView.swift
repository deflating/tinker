import SwiftUI

// MARK: - Option Banks

private let knowledgeDomainOptions = [
    "Programming", "Science", "Creative Writing", "Business",
    "Education", "Health", "Law", "Mathematics", "Design",
    "Music", "Philosophy", "History", "Engineering", "Finance"
]

private let behavioralRuleOptions = [
    "Always explain reasoning",
    "Ask before making changes",
    "Show work step-by-step",
    "Prefer simple solutions",
    "Cite sources when possible",
    "Use examples liberally",
    "Suggest alternatives",
    "Verify before answering"
]

private let boundaryOptions = [
    "Never give medical advice",
    "Don't write essays without asking",
    "Avoid political opinions",
    "Don't make assumptions about intent",
    "Always clarify ambiguous requests",
    "Don't generate harmful content",
    "Respect privacy boundaries",
    "Decline unethical requests"
]

private let iconOptions = [
    "sparkle", "brain.head.profile", "cpu", "wand.and.stars",
    "lightbulb", "book", "hammer", "paintbrush", "terminal",
    "globe", "heart", "star", "bolt", "leaf", "flame"
]

// MARK: - Presets

private struct AgentPreset {
    let name: String
    let icon: String
    let config: AgentConfiguration
}

private let presets: [AgentPreset] = [
    AgentPreset(
        name: "Helpful Assistant",
        icon: "sparkle",
        config: AgentConfiguration(
            identity: .init(name: "Assistant", icon: "sparkle", roleDescription: "A helpful, general-purpose AI assistant"),
            personality: .init(warmth: 70, humor: 30, formality: 50, curiosity: 50, confidence: 70, patience: 80),
            communicationStyle: .init(verbosity: .balanced, tone: .friendly),
            behavioralRules: ["Always explain reasoning", "Ask before making changes"]
        )
    ),
    AgentPreset(
        name: "Creative Partner",
        icon: "paintbrush",
        config: AgentConfiguration(
            identity: .init(name: "Muse", icon: "paintbrush", roleDescription: "A creative collaborator for writing, brainstorming, and ideation"),
            personality: .init(warmth: 80, humor: 60, formality: 20, curiosity: 90, confidence: 60, patience: 70),
            communicationStyle: .init(verbosity: .detailed, tone: .casual, useEmoji: true),
            knowledgeDomains: ["Creative Writing", "Design", "Music"],
            behavioralRules: ["Suggest alternatives", "Use examples liberally"]
        )
    ),
    AgentPreset(
        name: "Code Reviewer",
        icon: "terminal",
        config: AgentConfiguration(
            identity: .init(name: "Reviewer", icon: "terminal", roleDescription: "A thorough code reviewer focused on quality and best practices"),
            personality: .init(warmth: 40, humor: 20, formality: 70, curiosity: 60, confidence: 80, patience: 60),
            communicationStyle: .init(verbosity: .concise, tone: .professional),
            knowledgeDomains: ["Programming", "Engineering"],
            behavioralRules: ["Show work step-by-step", "Prefer simple solutions"],
            responseFormat: .init(codeStyle: .documented)
        )
    ),
    AgentPreset(
        name: "Tutor",
        icon: "book",
        config: AgentConfiguration(
            identity: .init(name: "Tutor", icon: "book", roleDescription: "A patient educator that adapts to your learning style"),
            personality: .init(warmth: 85, humor: 40, formality: 40, curiosity: 70, confidence: 65, patience: 95),
            communicationStyle: .init(verbosity: .detailed, tone: .friendly),
            knowledgeDomains: ["Education", "Science", "Mathematics"],
            behavioralRules: ["Always explain reasoning", "Show work step-by-step", "Use examples liberally"],
            emotionalIntelligence: .init(empathyLevel: 80, encouragementStyle: .coaching, handleFrustration: .simplify, celebrateSuccess: true)
        )
    ),
]

// MARK: - AgentConfiguratorView

struct AgentConfiguratorView: View {
    var onDismiss: () -> Void

    @State private var config = AgentConfiguration()
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
                        presetsSection
                        identitySection
                        personalitySection
                        communicationStyleSection
                        knowledgeDomainsSection
                        behavioralRulesSection
                        boundariesSection
                        responseFormatSection
                        autonomySection
                        emotionalIntelligenceSection
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
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Agent Configurator")
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
                    withAnimation { config = AgentConfiguration.fromMarkdown(content) }
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
                config = AgentConfiguration()
            }
            .buttonStyle(.bordered)
            Spacer()
            Button("Save Agent") {
                var all = AgentConfiguration.loadAll()
                if let idx = all.firstIndex(where: { $0.id == config.id }) {
                    all[idx] = config
                } else {
                    all.append(config)
                }
                AgentConfiguration.saveAll(all)
                onDismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(FamiliarApp.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 0. Presets

    private var presetsSection: some View {
        GroupBox {
            HStack(spacing: 12) {
                ForEach(presets, id: \.name) { preset in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            config = preset.config
                            config.id = UUID().uuidString
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 20))
                                .frame(width: 40, height: 40)
                                .background(FamiliarApp.surfaceBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(preset.name)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        } label: {
            Label("Presets", systemImage: "square.grid.2x2")
        }
    }

    // MARK: - 1. Identity

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                formRow("Name") {
                    TextField("Agent name", text: $config.identity.name)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Icon") {
                    Picker("", selection: $config.identity.icon) {
                        ForEach(iconOptions, id: \.self) { icon in
                            Label(icon, systemImage: icon).tag(icon)
                        }
                    }
                    .frame(width: 180)
                }
                formRow("Tagline") {
                    TextField("Short tagline", text: $config.identity.tagline)
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Role Description")
                        .font(.callout.weight(.medium))
                    TextEditor(text: $config.identity.roleDescription)
                        .font(.system(size: 12))
                        .frame(minHeight: 60, maxHeight: 100)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(FamiliarApp.surfaceBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(4)
        } label: {
            Label("Identity", systemImage: "person.fill")
        }
    }

    // MARK: - 2. Personality

    private var personalitySection: some View {
        GroupBox {
            VStack(spacing: 10) {
                personalitySlider("Warmth", value: $config.personality.warmth, label: warmthLabel)
                personalitySlider("Humor", value: $config.personality.humor, label: humorLabel)
                personalitySlider("Formality", value: $config.personality.formality, label: formalityLabel)
                personalitySlider("Curiosity", value: $config.personality.curiosity, label: curiosityLabel)
                personalitySlider("Confidence", value: $config.personality.confidence, label: confidenceLabel)
                personalitySlider("Patience", value: $config.personality.patience, label: patienceLabel)
            }
            .padding(4)
        } label: {
            Label("Personality", systemImage: "face.smiling")
        }
    }

    private func personalitySlider(_ title: String, value: Binding<Int>, label: @escaping (Int) -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.callout.weight(.medium))
                    .frame(width: 90, alignment: .leading)
                Slider(value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ), in: 0...100, step: 1)
                .tint(FamiliarApp.accent)
                Text("\(value.wrappedValue)")
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 28, alignment: .trailing)
                Text(label(value.wrappedValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 100, alignment: .leading)
            }
        }
    }

    // MARK: - 3. Communication Style

    private var communicationStyleSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                formRow("Verbosity") {
                    Picker("", selection: $config.communicationStyle.verbosity) {
                        ForEach(AgentConfiguration.Verbosity.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                formRow("Tone") {
                    Picker("", selection: $config.communicationStyle.tone) {
                        ForEach(AgentConfiguration.Tone.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                Toggle("Use Emoji", isOn: $config.communicationStyle.useEmoji)
                    .tint(FamiliarApp.accent)
                Toggle("Use Markdown", isOn: $config.communicationStyle.useMarkdown)
                    .tint(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Communication Style", systemImage: "text.bubble")
        }
    }

    // MARK: - 4. Knowledge Domains

    private var knowledgeDomainsSection: some View {
        GroupBox {
            TagListEditor(
                items: $config.knowledgeDomains,
                optionBank: knowledgeDomainOptions,
                placeholder: "Add domain..."
            )
            .padding(4)
        } label: {
            Label("Knowledge Domains", systemImage: "books.vertical")
        }
    }

    // MARK: - 5. Behavioral Rules

    private var behavioralRulesSection: some View {
        GroupBox {
            TagListEditor(
                items: $config.behavioralRules,
                optionBank: behavioralRuleOptions,
                placeholder: "Add rule..."
            )
            .padding(4)
        } label: {
            Label("Behavioral Rules", systemImage: "list.bullet.rectangle")
        }
    }

    // MARK: - 6. Boundaries

    private var boundariesSection: some View {
        GroupBox {
            TagListEditor(
                items: $config.boundaries,
                optionBank: boundaryOptions,
                placeholder: "Add boundary..."
            )
            .padding(4)
        } label: {
            Label("Boundaries", systemImage: "shield")
        }
    }

    // MARK: - 7. Response Format

    private var responseFormatSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                formRow("Default Length") {
                    Picker("", selection: $config.responseFormat.defaultLength) {
                        ForEach(AgentConfiguration.ResponseLength.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                formRow("List Style") {
                    Picker("", selection: $config.responseFormat.listStyle) {
                        ForEach(AgentConfiguration.ListStyle.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                formRow("Code Style") {
                    Picker("", selection: $config.responseFormat.codeStyle) {
                        ForEach(AgentConfiguration.CodeStyle.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                Toggle("Include Explanations", isOn: $config.responseFormat.includeExplanations)
                    .tint(FamiliarApp.accent)
                Toggle("Include Sources", isOn: $config.responseFormat.includeSources)
                    .tint(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Response Format", systemImage: "doc.text")
        }
    }

    // MARK: - 8. Autonomy

    private var autonomySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Proactivity")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(config.autonomyLevel.proactivity) — \(proactivityLabel(config.autonomyLevel.proactivity))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(config.autonomyLevel.proactivity) },
                        set: { config.autonomyLevel.proactivity = Int($0) }
                    ), in: 0...100, step: 1)
                    .tint(FamiliarApp.accent)
                }
                Toggle("Ask Before Acting", isOn: $config.autonomyLevel.askBeforeActing)
                    .tint(FamiliarApp.accent)
                Toggle("Suggest Improvements", isOn: $config.autonomyLevel.suggestImprovements)
                    .tint(FamiliarApp.accent)
                Toggle("Auto-Correct Errors", isOn: $config.autonomyLevel.autoCorrect)
                    .tint(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Autonomy", systemImage: "gauge.with.needle")
        }
    }

    // MARK: - 9. Emotional Intelligence

    private var emotionalIntelligenceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Empathy Level")
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text("\(config.emotionalIntelligence.empathyLevel) — \(empathyLabel(config.emotionalIntelligence.empathyLevel))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { Double(config.emotionalIntelligence.empathyLevel) },
                        set: { config.emotionalIntelligence.empathyLevel = Int($0) }
                    ), in: 0...100, step: 1)
                    .tint(FamiliarApp.accent)
                }
                formRow("Encouragement") {
                    Picker("", selection: $config.emotionalIntelligence.encouragementStyle) {
                        ForEach(AgentConfiguration.EncouragementStyle.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                formRow("Frustration Response") {
                    Picker("", selection: $config.emotionalIntelligence.handleFrustration) {
                        ForEach(AgentConfiguration.FrustrationResponse.allCases, id: \.self) {
                            Text($0.rawValue.capitalized).tag($0)
                        }
                    }
                    .frame(width: 150)
                }
                Toggle("Celebrate Successes", isOn: $config.emotionalIntelligence.celebrateSuccess)
                    .tint(FamiliarApp.accent)
            }
            .padding(4)
        } label: {
            Label("Emotional Intelligence", systemImage: "heart")
        }
    }

    // MARK: - 10. Custom Sections

    private var customSectionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(config.customSections.enumerated()), id: \.element.id) { idx, section in
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

    // MARK: - 11. Custom Instructions

    private var customInstructionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                Text("Freeform instructions appended to the agent's system prompt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $config.customInstructions)
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

// MARK: - TagListEditor

private struct TagListEditor: View {
    @Binding var items: [String]
    let optionBank: [String]
    let placeholder: String

    @State private var showingPopover = false
    @State private var customEntry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item)
                        .font(.callout)
                    Spacer()
                    Button {
                        withAnimation { _ = items.remove(at: index) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                TextField(placeholder, text: $customEntry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let trimmed = customEntry.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty && !items.contains(trimmed) {
                            withAnimation { items.append(trimmed) }
                            customEntry = ""
                        }
                    }
                Button {
                    showingPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(FamiliarApp.accent)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Options")
                            .font(.headline)
                            .padding(.bottom, 4)
                        ForEach(optionBank.filter { !items.contains($0) }, id: \.self) { option in
                            Button {
                                withAnimation { items.append(option) }
                                showingPopover = false
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
    }
}
