import SwiftUI

// MARK: - Markdown Section Parser

struct MarkdownSection: Identifiable {
    let id = UUID()
    var heading: String
    var body: String
    var isHeader: Bool { heading.isEmpty }
}

private func parseSections(from markdown: String) -> [MarkdownSection] {
    let lines = markdown.components(separatedBy: "\n")
    var sections: [MarkdownSection] = []
    var currentHeading = ""
    var currentLines: [String] = []

    for line in lines {
        if line.hasPrefix("## ") {
            sections.append(MarkdownSection(heading: currentHeading, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .newlines)))
            currentHeading = String(line.dropFirst(3))
            currentLines = []
        } else {
            currentLines.append(line)
        }
    }
    sections.append(MarkdownSection(heading: currentHeading, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .newlines)))
    return sections
}

private func compileSections(_ sections: [MarkdownSection]) -> String {
    var parts: [String] = []
    for section in sections {
        if section.isHeader {
            parts.append(section.body)
        } else {
            parts.append("## \(section.heading)\n\n\(section.body)")
        }
    }
    return parts.joined(separator: "\n\n") + "\n"
}

// MARK: - Identity Fields

private struct IdentityFields {
    var name = ""
    var age = ""
    var location = ""
    var pronouns = ""
    var language = ""
    var timezone = ""
    var extraHeaderLines: [String] = []

    static func parse(from text: String) -> IdentityFields {
        var fields = IdentityFields()
        let lines = text.components(separatedBy: "\n")
        var extras: [String] = []
        for line in lines {
            if line.hasPrefix("# ") {
                fields.name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.contains("**Age:**") || line.contains("**Location:**") || line.contains("**Model:**") {
                let pairs = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                for pair in pairs {
                    let cleaned = pair.replacingOccurrences(of: "**", with: "")
                    if let colonIdx = cleaned.firstIndex(of: ":") {
                        let key = cleaned[cleaned.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                        let val = cleaned[cleaned.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                        switch key {
                        case "age": fields.age = val
                        case "location": fields.location = val
                        case "pronouns": fields.pronouns = val
                        case "language": fields.language = val
                        case "timezone": fields.timezone = val
                        default: break
                        }
                    }
                }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                extras.append(line)
            }
        }
        fields.extraHeaderLines = extras
        return fields
    }

    func compile() -> String {
        var parts: [String] = ["# \(name)", ""]
        var fields: [String] = []
        if !age.isEmpty { fields.append("**Age:** \(age)") }
        if !location.isEmpty { fields.append("**Location:** \(location)") }
        if !pronouns.isEmpty { fields.append("**Pronouns:** \(pronouns)") }
        if !language.isEmpty { fields.append("**Language:** \(language)") }
        if !timezone.isEmpty { fields.append("**Timezone:** \(timezone)") }
        if !fields.isEmpty { parts.append(fields.joined(separator: " | ")) }
        parts.append(contentsOf: extraHeaderLines)
        return parts.joined(separator: "\n")
    }
}

// MARK: - Agent Identity Fields

private struct AgentIdentityFields {
    var name = ""
    var model = ""
    var role = ""
    var extraHeaderLines: [String] = []

    static func parse(from text: String) -> AgentIdentityFields {
        var fields = AgentIdentityFields()
        let lines = text.components(separatedBy: "\n")
        var extras: [String] = []
        for line in lines {
            if line.hasPrefix("# ") {
                fields.name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.contains("**Model:**") || line.contains("**Role:**") {
                let pairs = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                for pair in pairs {
                    let cleaned = pair.replacingOccurrences(of: "**", with: "")
                    if let colonIdx = cleaned.firstIndex(of: ":") {
                        let key = cleaned[cleaned.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                        let val = cleaned[cleaned.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                        switch key {
                        case "model": fields.model = val
                        case "role": fields.role = val
                        default: break
                        }
                    }
                }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                extras.append(line)
            }
        }
        fields.extraHeaderLines = extras
        return fields
    }

    func compile() -> String {
        var parts: [String] = ["# \(name)", ""]
        var fields: [String] = []
        if !model.isEmpty { fields.append("**Model:** \(model)") }
        if !role.isEmpty { fields.append("**Role:** \(role)") }
        if !fields.isEmpty { parts.append(fields.joined(separator: " | ")) }
        parts.append(contentsOf: extraHeaderLines)
        return parts.joined(separator: "\n")
    }
}

// MARK: - Character Trait

private struct CharacterTrait: Identifiable {
    let id = UUID()
    var name: String
    var label: String
    var value: Double

    static func parse(from line: String) -> CharacterTrait? {
        let cleaned = line.trimmingCharacters(in: .whitespaces)
        guard cleaned.hasPrefix("- **") else { return nil }
        let inner = String(cleaned.dropFirst(4))
        guard let colonEnd = inner.range(of: ":**") else { return nil }
        let name = String(inner[inner.startIndex..<colonEnd.lowerBound])
        let rest = String(inner[colonEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let parenStart = rest.lastIndex(of: "("),
           let slashIdx = rest.lastIndex(of: "/"),
           let parenEnd = rest.lastIndex(of: ")"),
           parenStart < slashIdx, slashIdx < parenEnd {
            let numStr = rest[rest.index(after: parenStart)..<slashIdx]
            let label = String(rest[rest.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
            if let num = Double(numStr) {
                return CharacterTrait(name: name, label: label, value: num)
            }
        }
        return nil
    }

    func compile() -> String {
        "- **\(name):** \(label) (\(Int(value))/100)"
    }
}

// MARK: - Bullet Helpers

private func parseBullets(from text: String) -> [String] {
    text.components(separatedBy: "\n")
        .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
        .map { String($0.trimmingCharacters(in: .whitespaces).dropFirst(2)) }
}

private func compileBullets(_ items: [String]) -> String {
    items.map { "- \($0)" }.joined(separator: "\n")
}

// MARK: - People Entry

private struct PersonEntry: Identifiable {
    let id = UUID()
    var name: String
    var relationship: String
    var description: String
}

private func parsePeople(from text: String) -> [PersonEntry] {
    var people: [PersonEntry] = []
    let lines = text.components(separatedBy: "\n")
    var currentName = ""
    var currentRel = ""
    var currentDesc: [String] = []
    for line in lines {
        if line.hasPrefix("### ") {
            if !currentName.isEmpty {
                people.append(PersonEntry(name: currentName, relationship: currentRel, description: currentDesc.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            let raw = String(line.dropFirst(4))
            if let parenStart = raw.firstIndex(of: "("), let parenEnd = raw.lastIndex(of: ")") {
                currentName = String(raw[raw.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
                currentRel = String(raw[raw.index(after: parenStart)..<parenEnd])
            } else {
                currentName = raw.trimmingCharacters(in: .whitespaces)
                currentRel = ""
            }
            currentDesc = []
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            currentDesc.append(line)
        }
    }
    if !currentName.isEmpty {
        people.append(PersonEntry(name: currentName, relationship: currentRel, description: currentDesc.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return people
}

private func compilePeople(_ people: [PersonEntry]) -> String {
    people.map { p in
        let header = p.relationship.isEmpty ? "### \(p.name)" : "### \(p.name) (\(p.relationship))"
        return "\(header)\n\(p.description)"
    }.joined(separator: "\n\n")
}

// MARK: - Interest / Project Entries

private struct InterestEntry: Identifiable {
    let id = UUID()
    var name: String
    var description: String
}

private struct ProjectEntry: Identifiable {
    let id = UUID()
    var name: String
    var status: String
    var description: String
}

private func parseSubsections(from text: String) -> [(name: String, body: String)] {
    var items: [(name: String, body: String)] = []
    let lines = text.components(separatedBy: "\n")
    var currentName = ""
    var currentLines: [String] = []
    for line in lines {
        if line.hasPrefix("### ") {
            if !currentName.isEmpty {
                items.append((name: currentName, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            currentName = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            currentLines = []
        } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
            currentLines.append(line)
        }
    }
    if !currentName.isEmpty {
        items.append((name: currentName, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
    }
    return items
}

private func parseInterests(from text: String) -> [InterestEntry] {
    parseSubsections(from: text).map { InterestEntry(name: $0.name, description: $0.body) }
}

private func compileInterests(_ items: [InterestEntry]) -> String {
    items.map { "### \($0.name)\n\($0.description)" }.joined(separator: "\n\n")
}

private func parseProjects(from text: String) -> [ProjectEntry] {
    parseSubsections(from: text).map { sub in
        // "Memorable [active]" -> name: "Memorable", status: "active"
        let name = sub.name
        if let bracketStart = name.lastIndex(of: "["), let bracketEnd = name.lastIndex(of: "]"), bracketStart < bracketEnd {
            let projName = String(name[name.startIndex..<bracketStart]).trimmingCharacters(in: .whitespaces)
            let status = String(name[name.index(after: bracketStart)..<bracketEnd])
            return ProjectEntry(name: projName, status: status, description: sub.body)
        }
        return ProjectEntry(name: name, status: "", description: sub.body)
    }
}

private func compileProjects(_ items: [ProjectEntry]) -> String {
    items.map { p in
        let header = p.status.isEmpty ? "### \(p.name)" : "### \(p.name) [\(p.status)]"
        return "\(header)\n\(p.description)"
    }.joined(separator: "\n\n")
}

// MARK: - Neurodivergence Parsing

private struct NDSelection {
    var label: String
    var qualifier: String  // "", "Maybe", "Suspected", "Diagnosed"
}

private func parseNeurodivergence(from text: String) -> [NDSelection] {
    let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !raw.isEmpty else { return [] }
    return raw.components(separatedBy: ",").map { item in
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        for q in ["Maybe ", "Suspected ", "Diagnosed "] {
            if trimmed.hasPrefix(q) {
                return NDSelection(label: String(trimmed.dropFirst(q.count)), qualifier: String(q.trimmingCharacters(in: .whitespaces)))
            }
        }
        return NDSelection(label: trimmed, qualifier: "")
    }
}

private func compileNeurodivergence(_ items: [NDSelection]) -> String {
    items.map { $0.qualifier.isEmpty ? $0.label : "\($0.qualifier) \($0.label)" }.joined(separator: ", ")
}

// MARK: - Cognitive Style Parsing

private struct CognitiveStyleEntry {
    var key: String
    var value: String
}

private func parseCognitiveStyle(from text: String) -> [CognitiveStyleEntry] {
    parseBullets(from: text).compactMap { bullet in
        if let colonRange = bullet.range(of: ": ") {
            return CognitiveStyleEntry(
                key: String(bullet[bullet.startIndex..<colonRange.lowerBound]),
                value: String(bullet[colonRange.upperBound...])
            )
        }
        return nil
    }
}

private func compileCognitiveStyle(_ entries: [CognitiveStyleEntry]) -> String {
    entries.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
}

private func optionsForCognitiveKey(_ key: String) -> [String] {
    switch key {
    case "Guidance Style": return GuidanceStyle.allCases.map(\.rawValue)
    case "Starting Point": return StartingPoint.allCases.map(\.rawValue)
    case "Threading": return ThreadingStyle.allCases.map(\.rawValue)
    default: return []
    }
}

// MARK: - SeedFormView

struct SeedFormView: View {
    let seedType: SeedManager.SeedFile
    @Binding var content: String
    var onChange: () -> Void

    @State private var sections: [MarkdownSection] = []
    @State private var identityFields = IdentityFields()
    @State private var agentFields = AgentIdentityFields()
    @State private var traits: [CharacterTrait] = []
    @State private var people: [PersonEntry] = []
    @State private var interests: [InterestEntry] = []
    @State private var projects: [ProjectEntry] = []
    @State private var ndSelections: [NDSelection] = []
    @State private var cognitiveStyle: [CognitiveStyleEntry] = []
    @State private var values: [String] = []
    @State private var didParse = false

    // Popover state
    @State private var showValueBank = false
    @State private var showBehaviorBank = false
    @State private var showAvoidBank = false
    @State private var showToneBank = false
    @State private var showNDPicker = false
    @State private var customAddText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if seedType == .user {
                    userForm
                } else if seedType == .agent {
                    agentForm
                }
            }
            .padding(20)
        }
        .onAppear { parseContent() }
    }

    // MARK: - User Form

    private var userForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("Identity", icon: "person.fill") {
                formRow("Name") {
                    TextField("Name", text: identityBinding(\.name))
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Age") {
                    TextField("Age", text: identityBinding(\.age))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
                formRow("Location") {
                    TextField("City, Country", text: identityBinding(\.location))
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Pronouns") {
                    Picker("", selection: identityBinding(\.pronouns)) {
                        Text("he/him").tag("he/him")
                        Text("she/her").tag("she/her")
                        Text("they/them").tag("they/them")
                        Text("Custom").tag("")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    if !["he/him", "she/her", "they/them"].contains(identityFields.pronouns) {
                        TextField("Custom", text: identityBinding(\.pronouns))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                }
                formRow("Language") {
                    TextField("Language", text: identityBinding(\.language))
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Timezone") {
                    TextField("Timezone", text: identityBinding(\.timezone))
                        .textFieldStyle(.roundedBorder)
                }
            }

            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                if !section.isHeader {
                    sectionEditor(idx: idx, section: section)
                }
            }
        }
    }

    // MARK: - Agent Form

    private var agentForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            settingsGroup("Identity", icon: "cpu") {
                formRow("Name") {
                    TextField("Name", text: $agentFields.name)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: agentFields.name) { _, _ in recompileAgentHeader() }
                }
                formRow("Model") {
                    TextField("Model", text: $agentFields.model)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: agentFields.model) { _, _ in recompileAgentHeader() }
                }
                formRow("Role") {
                    Picker("", selection: Binding(
                        get: { agentFields.role },
                        set: { agentFields.role = $0; recompileAgentHeader() }
                    )) {
                        Text("Companion").tag("Companion")
                        Text("Assistant").tag("Assistant")
                        Text("Collaborator").tag("Collaborator")
                        Text("Mentor").tag("Mentor")
                        Text("Custom").tag("")
                    }
                    .pickerStyle(.menu)
                    if !["Companion", "Assistant", "Collaborator", "Mentor"].contains(agentFields.role) {
                        TextField("Custom", text: $agentFields.role)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: agentFields.role) { _, _ in recompileAgentHeader() }
                    }
                }
            }

            ForEach(Array(sections.enumerated()), id: \.offset) { idx, section in
                if !section.isHeader {
                    agentSectionEditor(idx: idx, section: section)
                }
            }
        }
    }

    // MARK: - User Section Editors

    @ViewBuilder
    private func sectionEditor(idx: Int, section: MarkdownSection) -> some View {
        let heading = section.heading
        let icon = iconForSection(heading)

        switch heading {
        case "Cognitive Style":
            settingsGroup(heading, icon: icon) {
                ForEach(Array(cognitiveStyle.enumerated()), id: \.offset) { cIdx, entry in
                    let options = optionsForCognitiveKey(entry.key)
                    if !options.isEmpty {
                        formRow(entry.key) {
                            Picker("", selection: Binding(
                                get: { cognitiveStyle[safe: cIdx]?.value ?? entry.value },
                                set: { cognitiveStyle[cIdx].value = $0; recompileCognitiveStyle(into: idx) }
                            )) {
                                ForEach(options, id: \.self) { opt in
                                    Text(opt).tag(opt)
                                }
                                if !options.contains(entry.value) {
                                    Text(entry.value + " (custom)").tag(entry.value)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    } else {
                        formRow(entry.key) {
                            TextField("", text: Binding(
                                get: { cognitiveStyle[safe: cIdx]?.value ?? entry.value },
                                set: { cognitiveStyle[cIdx].value = $0; recompileCognitiveStyle(into: idx) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                addCognitiveStyleButton(sectionIdx: idx)
            }

        case "Values":
            settingsGroup(heading, icon: icon) {
                ForEach(Array(values.enumerated()), id: \.offset) { vIdx, value in
                    HStack {
                        TextField("Value", text: Binding(
                            get: { values[safe: vIdx] ?? value },
                            set: { values[vIdx] = $0; recompileValues(into: idx) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        Button {
                            values.remove(at: vIdx)
                            recompileValues(into: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button {
                        showValueBank.toggle()
                    } label: {
                        Label("Add Value", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarApp.accent)
                    .popover(isPresented: $showValueBank) {
                        optionBankPopover(
                            title: "Common Values",
                            options: commonValues.filter { !values.contains($0) },
                            onSelect: { val in
                                values.append(val)
                                recompileValues(into: idx)
                                showValueBank = false
                            },
                            onCustom: { val in
                                values.append(val)
                                recompileValues(into: idx)
                                showValueBank = false
                            }
                        )
                    }
                }
                .padding(.top, 4)
            }

        case "Neurodivergence":
            settingsGroup(heading, icon: icon) {
                ForEach(Array(ndSelections.enumerated()), id: \.offset) { nIdx, sel in
                    HStack {
                        Picker("", selection: Binding(
                            get: { ndSelections[safe: nIdx]?.qualifier ?? sel.qualifier },
                            set: { ndSelections[nIdx].qualifier = $0; recompileND(into: idx) }
                        )) {
                            Text("Yes").tag("")
                            Text("Maybe").tag("Maybe")
                            Text("Suspected").tag("Suspected")
                            Text("Diagnosed").tag("Diagnosed")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 110)

                        Text(sel.label)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button {
                            ndSelections.remove(at: nIdx)
                            recompileND(into: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button { showNDPicker.toggle() } label: {
                        Label("Add", systemImage: "plus")
                            .font(.callout)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FamiliarApp.accent)
                    .popover(isPresented: $showNDPicker) {
                        let existingLabels = Set(ndSelections.map(\.label))
                        optionBankPopover(
                            title: "Neurodivergence",
                            options: NeurodivergenceOption.common.map(\.label).filter { !existingLabels.contains($0) },
                            onSelect: { val in
                                ndSelections.append(NDSelection(label: val, qualifier: ""))
                                recompileND(into: idx)
                                showNDPicker = false
                            },
                            onCustom: { val in
                                ndSelections.append(NDSelection(label: val, qualifier: ""))
                                recompileND(into: idx)
                                showNDPicker = false
                            }
                        )
                    }
                }
                .padding(.top, 4)
            }

        case "People":
            settingsGroup(heading, icon: icon) {
                ForEach(Array(people.enumerated()), id: \.offset) { pIdx, person in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            TextField("Name", text: Binding(
                                get: { people[safe: pIdx]?.name ?? "" },
                                set: { people[pIdx].name = $0; recompilePeople(into: idx) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .fontWeight(.medium)

                            Picker("", selection: Binding(
                                get: {
                                    let rel = people[safe: pIdx]?.relationship ?? ""
                                    if RelationshipType.allCases.contains(where: { $0.rawValue == rel }) {
                                        return rel
                                    }
                                    return "custom"
                                },
                                set: { newVal in
                                    if newVal != "custom" {
                                        people[pIdx].relationship = newVal
                                        recompilePeople(into: idx)
                                    }
                                }
                            )) {
                                ForEach(RelationshipType.allCases) { type in
                                    Text(type.rawValue).tag(type.rawValue)
                                }
                                if !RelationshipType.allCases.contains(where: { $0.rawValue == person.relationship }) {
                                    Text(person.relationship.isEmpty ? "custom" : person.relationship).tag("custom")
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 130)

                            if !RelationshipType.allCases.contains(where: { $0.rawValue == person.relationship }) {
                                TextField("Custom", text: Binding(
                                    get: { people[safe: pIdx]?.relationship ?? "" },
                                    set: { people[pIdx].relationship = $0; recompilePeople(into: idx) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .font(.caption)
                            }

                            Button(role: .destructive) {
                                people.remove(at: pIdx)
                                recompilePeople(into: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Description", text: Binding(
                            get: { people[safe: pIdx]?.description ?? "" },
                            set: { people[pIdx].description = $0; recompilePeople(into: idx) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    if pIdx < people.count - 1 { Divider() }
                }
                Button {
                    people.append(PersonEntry(name: "", relationship: "friend", description: ""))
                    recompilePeople(into: idx)
                } label: {
                    Label("Add Person", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
                .padding(.top, 4)
            }

        case "Interests":
            settingsGroup(heading, icon: icon) {
                ForEach(Array(interests.enumerated()), id: \.offset) { iIdx, interest in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Interest", text: Binding(
                                get: { interests[safe: iIdx]?.name ?? "" },
                                set: { interests[iIdx].name = $0; recompileInterests(into: idx) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .fontWeight(.medium)
                            TextField("Description", text: Binding(
                                get: { interests[safe: iIdx]?.description ?? "" },
                                set: { interests[iIdx].description = $0; recompileInterests(into: idx) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        Button {
                            interests.remove(at: iIdx)
                            recompileInterests(into: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if iIdx < interests.count - 1 { Divider() }
                }
                Button {
                    interests.append(InterestEntry(name: "", description: ""))
                    recompileInterests(into: idx)
                } label: {
                    Label("Add Interest", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
                .padding(.top, 4)
            }

        case "Projects":
            settingsGroup(heading, icon: icon) {
                ForEach(Array(projects.enumerated()), id: \.offset) { pIdx, project in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                TextField("Project", text: Binding(
                                    get: { projects[safe: pIdx]?.name ?? "" },
                                    set: { projects[pIdx].name = $0; recompileProjects(into: idx) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .fontWeight(.medium)

                                Picker("", selection: Binding(
                                    get: { projects[safe: pIdx]?.status ?? "active" },
                                    set: { projects[pIdx].status = $0; recompileProjects(into: idx) }
                                )) {
                                    ForEach(ProjectStatus.allCases) { status in
                                        Text(status.rawValue).tag(status.rawValue)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 100)
                            }
                            TextField("Description", text: Binding(
                                get: { projects[safe: pIdx]?.description ?? "" },
                                set: { projects[pIdx].description = $0; recompileProjects(into: idx) }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        }
                        Button {
                            projects.remove(at: pIdx)
                            recompileProjects(into: idx)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if pIdx < projects.count - 1 { Divider() }
                }
                Button {
                    projects.append(ProjectEntry(name: "", status: "active", description: ""))
                    recompileProjects(into: idx)
                } label: {
                    Label("Add Project", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
                .padding(.top, 4)
            }

        default:
            settingsGroup(heading, icon: icon) {
                sectionTextArea(idx: idx, minHeight: 60)
            }
        }
    }

    // MARK: - Agent Section Editors

    @ViewBuilder
    private func agentSectionEditor(idx: Int, section: MarkdownSection) -> some View {
        let heading = section.heading
        let icon = iconForSection(heading)

        switch heading {
        case "Character Traits":
            settingsGroup(heading, icon: "slider.horizontal.3") {
                ForEach(Array(traits.enumerated()), id: \.offset) { tIdx, trait in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(trait.name)
                                .font(.callout.weight(.medium))
                                .frame(width: 110, alignment: .leading)
                            Slider(value: Binding(
                                get: { traits[safe: tIdx]?.value ?? 50 },
                                set: { traits[tIdx].value = $0; recompileTraits(into: idx) }
                            ), in: 0...100, step: 5)
                            Text("\(Int(trait.value))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }
                        TextField("Label", text: Binding(
                            get: { traits[safe: tIdx]?.label ?? "" },
                            set: { traits[tIdx].label = $0; recompileTraits(into: idx) }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

        case "Autonomy":
            settingsGroup(heading, icon: "bolt.fill") {
                if let trait = CharacterTrait.parse(from: section.body.components(separatedBy: "\n").first(where: { $0.contains("/100") }) ?? "") {
                    let traitBinding = Binding<Double>(
                        get: {
                            if let t = CharacterTrait.parse(from: sections[safe: idx]?.body.components(separatedBy: "\n").first(where: { $0.contains("/100") }) ?? "") {
                                return t.value
                            }
                            return trait.value
                        },
                        set: { newVal in
                            var t = trait
                            t.value = newVal
                            sections[idx].body = t.compile()
                            recompile()
                        }
                    )
                    HStack {
                        Text(trait.name)
                            .font(.callout.weight(.medium))
                            .frame(width: 110, alignment: .leading)
                        Slider(value: traitBinding, in: 0...100, step: 5)
                        Text("\(Int(traitBinding.wrappedValue))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                } else {
                    sectionTextArea(idx: idx, minHeight: 40)
                }
            }

        case "Behaviors":
            bulletBankSection(heading: heading, icon: icon, sectionIdx: idx, bank: commonBehaviors, showBank: $showBehaviorBank)

        case "Avoid":
            bulletBankSection(heading: heading, icon: icon, sectionIdx: idx, bank: commonAvoidances, showBank: $showAvoidBank)

        case "Tone & Format":
            bulletBankSection(heading: heading, icon: icon, sectionIdx: idx, bank: commonToneOptions, showBank: $showToneBank)

        case "When User Is Low", "Technical Style":
            settingsGroup(heading, icon: icon) {
                editableBulletListWithRemove(sectionIdx: idx)
            }

        default:
            settingsGroup(heading, icon: icon) {
                sectionTextArea(idx: idx, minHeight: 60)
            }
        }
    }

    // MARK: - Reusable Components

    private func settingsGroup<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(4)
        } label: {
            Label(title, systemImage: icon)
        }
    }

    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }

    private func sectionTextArea(idx: Int, minHeight: CGFloat) -> some View {
        TextEditor(text: sectionBodyBinding(idx))
            .font(.system(size: 12))
            .frame(minHeight: minHeight, maxHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(FamiliarApp.surfaceBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // Bullet list with remove buttons and an add button (for simple bullet sections)
    @ViewBuilder
    private func editableBulletListWithRemove(sectionIdx: Int) -> some View {
        let bullets = parseBullets(from: sections[safe: sectionIdx]?.body ?? "")
        ForEach(Array(bullets.enumerated()), id: \.offset) { bIdx, bullet in
            HStack {
                TextField("", text: Binding(
                    get: {
                        let current = parseBullets(from: sections[safe: sectionIdx]?.body ?? "")
                        return current[safe: bIdx] ?? bullet
                    },
                    set: { newVal in
                        var current = parseBullets(from: sections[sectionIdx].body)
                        if bIdx < current.count {
                            current[bIdx] = newVal
                            sections[sectionIdx].body = compileBullets(current)
                            recompile()
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                Button {
                    var current = parseBullets(from: sections[sectionIdx].body)
                    if bIdx < current.count {
                        current.remove(at: bIdx)
                        sections[sectionIdx].body = compileBullets(current)
                        recompile()
                    }
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        Button {
            var current = parseBullets(from: sections[sectionIdx].body)
            current.append("")
            sections[sectionIdx].body = compileBullets(current)
            recompile()
        } label: {
            Label("Add", systemImage: "plus")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(FamiliarApp.accent)
        .padding(.top, 4)
    }

    // Bullet list with remove buttons + option bank popover
    private func bulletBankSection(heading: String, icon: String, sectionIdx: Int, bank: [String], showBank: Binding<Bool>) -> some View {
        settingsGroup(heading, icon: icon) {
            let bullets = parseBullets(from: sections[safe: sectionIdx]?.body ?? "")
            ForEach(Array(bullets.enumerated()), id: \.offset) { bIdx, bullet in
                HStack {
                    TextField("", text: Binding(
                        get: {
                            let current = parseBullets(from: sections[safe: sectionIdx]?.body ?? "")
                            return current[safe: bIdx] ?? bullet
                        },
                        set: { newVal in
                            var current = parseBullets(from: sections[sectionIdx].body)
                            if bIdx < current.count {
                                current[bIdx] = newVal
                                sections[sectionIdx].body = compileBullets(current)
                                recompile()
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    Button {
                        var current = parseBullets(from: sections[sectionIdx].body)
                        if bIdx < current.count {
                            current.remove(at: bIdx)
                            sections[sectionIdx].body = compileBullets(current)
                            recompile()
                        }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Button { showBank.wrappedValue.toggle() } label: {
                    Label("Add", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(FamiliarApp.accent)
                .popover(isPresented: showBank) {
                    let existing = Set(parseBullets(from: sections[safe: sectionIdx]?.body ?? ""))
                    optionBankPopover(
                        title: heading,
                        options: bank.filter { !existing.contains($0) },
                        onSelect: { val in
                            var current = parseBullets(from: sections[sectionIdx].body)
                            current.append(val)
                            sections[sectionIdx].body = compileBullets(current)
                            recompile()
                            showBank.wrappedValue = false
                        },
                        onCustom: { val in
                            var current = parseBullets(from: sections[sectionIdx].body)
                            current.append(val)
                            sections[sectionIdx].body = compileBullets(current)
                            recompile()
                            showBank.wrappedValue = false
                        }
                    )
                }
            }
            .padding(.top, 4)
        }
    }

    // Option bank popover for adding from predefined + custom
    private func optionBankPopover(title: String, options: [String], onSelect: @escaping (String) -> Void, onCustom: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.medium))
                .padding(.bottom, 4)

            if !options.isEmpty {
                ForEach(options, id: \.self) { opt in
                    Button {
                        onSelect(opt)
                    } label: {
                        Text(opt)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
                }
            }

            Divider().padding(.vertical, 4)

            HStack {
                TextField("Custom...", text: $customAddText)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    .onSubmit {
                        if !customAddText.isEmpty {
                            onCustom(customAddText)
                            customAddText = ""
                        }
                    }
                Button("Add") {
                    if !customAddText.isEmpty {
                        onCustom(customAddText)
                        customAddText = ""
                    }
                }
                .disabled(customAddText.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func addCognitiveStyleButton(sectionIdx: Int) -> some View {
        Button {
            cognitiveStyle.append(CognitiveStyleEntry(key: "New Preference", value: ""))
            recompileCognitiveStyle(into: sectionIdx)
        } label: {
            Label("Add Preference", systemImage: "plus")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .foregroundStyle(FamiliarApp.accent)
        .padding(.top, 4)
    }

    // MARK: - Bindings

    private func identityBinding(_ keyPath: WritableKeyPath<IdentityFields, String>) -> Binding<String> {
        Binding(
            get: { identityFields[keyPath: keyPath] },
            set: {
                identityFields[keyPath: keyPath] = $0
                recompileHeader()
            }
        )
    }

    private func sectionBodyBinding(_ idx: Int) -> Binding<String> {
        Binding(
            get: { sections[safe: idx]?.body ?? "" },
            set: {
                if idx < sections.count {
                    sections[idx].body = $0
                    recompile()
                }
            }
        )
    }

    // MARK: - Parse / Compile

    private func parseContent() {
        sections = parseSections(from: content)

        if seedType == .user {
            if let header = sections.first(where: { $0.isHeader }) {
                identityFields = IdentityFields.parse(from: header.body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "People" }) {
                people = parsePeople(from: sections[idx].body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "Interests" }) {
                interests = parseInterests(from: sections[idx].body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "Projects" }) {
                projects = parseProjects(from: sections[idx].body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "Neurodivergence" }) {
                ndSelections = parseNeurodivergence(from: sections[idx].body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "Cognitive Style" }) {
                cognitiveStyle = parseCognitiveStyle(from: sections[idx].body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "Values" }) {
                values = parseBullets(from: sections[idx].body)
            }
        } else if seedType == .agent {
            if let header = sections.first(where: { $0.isHeader }) {
                agentFields = AgentIdentityFields.parse(from: header.body)
            }
            if let idx = sections.firstIndex(where: { $0.heading == "Character Traits" }) {
                traits = sections[idx].body.components(separatedBy: "\n").compactMap { CharacterTrait.parse(from: $0) }
            }
        }
        didParse = true
    }

    private func recompileHeader() {
        if let idx = sections.firstIndex(where: { $0.isHeader }) {
            sections[idx].body = identityFields.compile()
            recompile()
        }
    }

    private func recompileAgentHeader() {
        if let idx = sections.firstIndex(where: { $0.isHeader }) {
            sections[idx].body = agentFields.compile()
            recompile()
        }
    }

    private func recompilePeople(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = compilePeople(people)
        recompile()
    }

    private func recompileTraits(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = traits.map { $0.compile() }.joined(separator: "\n")
        recompile()
    }

    private func recompileValues(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = compileBullets(values)
        recompile()
    }

    private func recompileInterests(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = compileInterests(interests)
        recompile()
    }

    private func recompileProjects(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = compileProjects(projects)
        recompile()
    }

    private func recompileND(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = compileNeurodivergence(ndSelections)
        recompile()
    }

    private func recompileCognitiveStyle(into sectionIdx: Int) {
        guard sectionIdx < sections.count else { return }
        sections[sectionIdx].body = compileCognitiveStyle(cognitiveStyle)
        recompile()
    }

    private func recompile() {
        didParse = true
        content = compileSections(sections)
        onChange()
    }

    // MARK: - Icons

    private func iconForSection(_ heading: String) -> String {
        switch heading {
        case "About": return "text.quote"
        case "Neurodivergence": return "brain"
        case "Cognitive Style": return "lightbulb"
        case "Values": return "heart.fill"
        case "Interests": return "star"
        case "People": return "person.2.fill"
        case "Projects": return "folder.fill"
        case "How Matt's Mind Works": return "brain.head.profile"
        case "Work": return "briefcase.fill"
        case "Behaviors": return "list.bullet"
        case "When User Is Low": return "heart.slash"
        case "Avoid": return "xmark.circle"
        case "Character Traits": return "slider.horizontal.3"
        case "Tone & Format": return "text.alignleft"
        case "Technical Style": return "chevron.left.forwardslash.chevron.right"
        case "Autonomy": return "bolt.fill"
        case "The Journal Practice": return "book.fill"
        case "The Glossary": return "character.book.closed"
        case "Photos": return "photo"
        case "Creative Work": return "paintbrush"
        case "Memory": return "brain.head.profile"
        case "The Relationship": return "heart.circle"
        case "Memorable": return "tray.full"
        case "Matt": return "person.fill"
        case "Buddy": return "pawprint.fill"
        default: return "doc.text"
        }
    }
}

// MARK: - Safe Array Access

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
