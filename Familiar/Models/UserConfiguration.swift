import Foundation

struct UserConfiguration: Identifiable, Codable, Equatable {
    var id: String
    var identity: Identity
    var about: String
    var neurodivergence: [NDEntry]
    var cognitiveStyle: [CognitiveStyleEntry]
    var values: [String]
    var interests: [Interest]
    var people: [Person]
    var projects: [Project]
    var customSections: [CustomSection]

    struct CustomSection: Identifiable, Codable, Equatable {
        var id: String
        var title: String
        var body: String

        init(id: String = UUID().uuidString, title: String = "", body: String = "") {
            self.id = id
            self.title = title
            self.body = body
        }
    }

    init(
        id: String = UUID().uuidString,
        identity: Identity = .init(),
        about: String = "",
        neurodivergence: [NDEntry] = [],
        cognitiveStyle: [CognitiveStyleEntry] = [],
        values: [String] = [],
        interests: [Interest] = [],
        people: [Person] = [],
        projects: [Project] = [],
        customSections: [CustomSection] = []
    ) {
        self.id = id
        self.identity = identity
        self.about = about
        self.neurodivergence = neurodivergence
        self.cognitiveStyle = cognitiveStyle
        self.values = values
        self.interests = interests
        self.people = people
        self.projects = projects
        self.customSections = customSections
    }
}

// MARK: - Identity

extension UserConfiguration {
    struct Identity: Codable, Equatable {
        var name: String
        var age: Int?
        var location: String
        var pronouns: PronounOption
        var language: String
        var timezone: String

        init(
            name: String = "",
            age: Int? = nil,
            location: String = "",
            pronouns: PronounOption = .heHim,
            language: String = "English",
            timezone: String = ""
        ) {
            self.name = name
            self.age = age
            self.location = location
            self.pronouns = pronouns
            self.language = language
            self.timezone = timezone
        }
    }

    enum PronounOption: String, Codable, CaseIterable {
        case heHim = "he/him"
        case sheHer = "she/her"
        case theyThem = "they/them"
        case heThey = "he/they"
        case sheThey = "she/they"
        case itIts = "it/its"
        case any = "any"
        case other = "other"

        var label: String { rawValue }
    }
}

// MARK: - Neurodivergence

extension UserConfiguration {
    struct NDEntry: Identifiable, Codable, Equatable {
        var id: String
        var label: String
        var qualifier: NDQualifier

        init(id: String = UUID().uuidString, label: String = "", qualifier: NDQualifier = .yes) {
            self.id = id
            self.label = label
            self.qualifier = qualifier
        }
    }

    enum NDQualifier: String, Codable, CaseIterable {
        case yes = "Yes"
        case maybe = "Maybe"
        case suspected = "Suspected"
        case diagnosed = "Diagnosed"

        var label: String { rawValue }
    }
}

// MARK: - Cognitive Style

extension UserConfiguration {
    struct CognitiveStyleEntry: Identifiable, Codable, Equatable {
        var id: String
        var key: CognitiveStyleKey
        var customKey: String
        var value: String

        init(id: String = UUID().uuidString, key: CognitiveStyleKey = .guidanceStyle, customKey: String = "", value: String = "") {
            self.id = id
            self.key = key
            self.customKey = customKey
            self.value = value
        }

        var displayKey: String {
            key == .custom ? customKey : key.label
        }
    }

    enum CognitiveStyleKey: String, Codable, CaseIterable {
        case guidanceStyle = "Guidance Style"
        case startingPoint = "Starting Point"
        case threading = "Threading"
        case custom = "Custom"

        var label: String { rawValue }
    }
}

// MARK: - Interest

extension UserConfiguration {
    struct Interest: Identifiable, Codable, Equatable {
        var id: String
        var name: String
        var description: String

        init(id: String = UUID().uuidString, name: String = "", description: String = "") {
            self.id = id
            self.name = name
            self.description = description
        }
    }
}

// MARK: - Person

extension UserConfiguration {
    struct Person: Identifiable, Codable, Equatable {
        var id: String
        var name: String
        var relationship: RelationshipType
        var description: String

        init(id: String = UUID().uuidString, name: String = "", relationship: RelationshipType = .friend, description: String = "") {
            self.id = id
            self.name = name
            self.relationship = relationship
            self.description = description
        }
    }

    enum RelationshipType: String, Codable, CaseIterable {
        case pet
        case family
        case partner
        case closeFriend = "close friend"
        case friend
        case colleague
        case significant
        case medical
        case other

        var label: String { rawValue.capitalized }
    }
}

// MARK: - Project

extension UserConfiguration {
    struct Project: Identifiable, Codable, Equatable {
        var id: String
        var name: String
        var status: ProjectStatus
        var description: String

        init(id: String = UUID().uuidString, name: String = "", status: ProjectStatus = .active, description: String = "") {
            self.id = id
            self.name = name
            self.status = status
            self.description = description
        }
    }

    enum ProjectStatus: String, Codable, CaseIterable {
        case active
        case legacy
        case paused
        case planned
        case archived

        var label: String { rawValue.capitalized }
    }
}

// MARK: - Markdown Export

extension UserConfiguration {
    func toMarkdown() -> String {
        var lines: [String] = []

        // Header
        lines.append("# \(identity.name)")
        lines.append("")
        var meta: [String] = []
        if let age = identity.age { meta.append("**Age:** \(age)") }
        if !identity.location.isEmpty { meta.append("**Location:** \(identity.location)") }
        meta.append("**Pronouns:** \(identity.pronouns.rawValue)")
        if !identity.language.isEmpty { meta.append("**Language:** \(identity.language)") }
        if !identity.timezone.isEmpty { meta.append("**Timezone:** \(identity.timezone)") }
        if !meta.isEmpty {
            lines.append(meta.joined(separator: " | "))
            lines.append("")
        }

        // About
        if !about.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## About")
            lines.append("")
            lines.append(about.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        // Neurodivergence
        if !neurodivergence.isEmpty {
            lines.append("## Neurodivergence")
            lines.append("")
            let entries = neurodivergence.map { entry -> String in
                if entry.qualifier == .yes {
                    return entry.label
                }
                return "\(entry.qualifier.rawValue) \(entry.label)"
            }
            lines.append(entries.joined(separator: ", "))
            lines.append("")
        }

        // Cognitive Style
        if !cognitiveStyle.isEmpty {
            lines.append("## Cognitive Style")
            lines.append("")
            for entry in cognitiveStyle {
                lines.append("- \(entry.displayKey): \(entry.value)")
            }
            lines.append("")
        }

        // Values
        if !values.isEmpty {
            lines.append("## Values")
            lines.append("")
            for value in values {
                lines.append("- \(value)")
            }
            lines.append("")
        }

        // Interests
        if !interests.isEmpty {
            lines.append("## Interests")
            lines.append("")
            for interest in interests {
                lines.append("### \(interest.name)")
                if !interest.description.isEmpty {
                    lines.append(interest.description.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                lines.append("")
            }
        }

        // People
        if !people.isEmpty {
            lines.append("## People")
            lines.append("")
            for person in people {
                lines.append("### \(person.name) (\(person.relationship.rawValue))")
                if !person.description.isEmpty {
                    lines.append(person.description.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                lines.append("")
            }
        }

        // Projects
        if !projects.isEmpty {
            lines.append("## Projects")
            lines.append("")
            for project in projects {
                lines.append("### \(project.name) [\(project.status.rawValue)]")
                if !project.description.isEmpty {
                    lines.append(project.description.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                lines.append("")
            }
        }

        // Custom Sections
        for section in customSections where !section.title.isEmpty {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Markdown Import

extension UserConfiguration {
    private static let knownSections: Set<String> = [
        "About", "Neurodivergence", "Cognitive Style", "Values",
        "Interests", "People", "Projects",
    ]

    static func fromMarkdown(_ markdown: String) -> UserConfiguration {
        var config = UserConfiguration()

        let lines = markdown.components(separatedBy: "\n")
        var headerLines: [String] = []
        var sections: [(heading: String, body: String)] = []
        var currentHeading: String?
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("## ") {
                if let heading = currentHeading {
                    sections.append((heading: heading, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                } else {
                    headerLines = currentLines
                }
                currentHeading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        if let heading = currentHeading {
            sections.append((heading: heading, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        } else {
            headerLines = currentLines
        }

        // Parse header
        for line in headerLines {
            if line.hasPrefix("# ") {
                config.identity.name = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.contains("**") {
                let pairs = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                for pair in pairs {
                    let cleaned = pair.replacingOccurrences(of: "**", with: "")
                    if let colonIdx = cleaned.firstIndex(of: ":") {
                        let key = cleaned[cleaned.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                        let val = cleaned[cleaned.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                        switch key {
                        case "age":
                            config.identity.age = Int(val)
                        case "location":
                            config.identity.location = val
                        case "pronouns":
                            config.identity.pronouns = PronounOption(rawValue: val.lowercased()) ?? .other
                        case "language":
                            config.identity.language = val
                        case "timezone":
                            config.identity.timezone = val
                        default: break
                        }
                    }
                }
            }
        }

        // Parse sections
        for section in sections {
            let heading = section.heading
            let body = section.body

            switch heading {
            case "About":
                config.about = body

            case "Neurodivergence":
                config.neurodivergence = parseNeurodivergence(body)

            case "Cognitive Style":
                config.cognitiveStyle = parseCognitiveStyle(body)

            case "Values":
                config.values = parseBulletItems(body)

            case "Interests":
                config.interests = parseSubEntries(body).map { entry in
                    Interest(name: entry.name, description: entry.body)
                }

            case "People":
                config.people = parsePeople(body)

            case "Projects":
                config.projects = parseProjects(body)

            default:
                config.customSections.append(CustomSection(title: heading, body: body))
            }
        }

        return config
    }

    private static func parseBulletItems(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- ") }
            .map { String($0.trimmingCharacters(in: .whitespaces).dropFirst(2)) }
    }

    private static func parseNeurodivergence(_ text: String) -> [NDEntry] {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return [] }

        let items = content.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return items.compactMap { item -> NDEntry? in
            guard !item.isEmpty else { return nil }
            let lower = item.lowercased()
            for qualifier in NDQualifier.allCases where qualifier != .yes {
                if lower.hasPrefix(qualifier.rawValue.lowercased() + " ") {
                    let label = String(item.dropFirst(qualifier.rawValue.count + 1)).trimmingCharacters(in: .whitespaces)
                    return NDEntry(label: label, qualifier: qualifier)
                }
            }
            return NDEntry(label: item, qualifier: .yes)
        }
    }

    private static func parseCognitiveStyle(_ text: String) -> [CognitiveStyleEntry] {
        parseBulletItems(text).compactMap { item -> CognitiveStyleEntry? in
            guard let colonIdx = item.firstIndex(of: ":") else { return nil }
            let key = item[item.startIndex..<colonIdx].trimmingCharacters(in: .whitespaces)
            let value = item[item.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
            let styleKey = CognitiveStyleKey(rawValue: key) ?? .custom
            return CognitiveStyleEntry(key: styleKey, customKey: styleKey == .custom ? key : "", value: value)
        }
    }

    private struct SubEntry {
        let name: String
        let body: String
    }

    private static func parseSubEntries(_ text: String) -> [SubEntry] {
        var entries: [SubEntry] = []
        var currentName: String?
        var currentLines: [String] = []
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            if line.hasPrefix("### ") {
                if let name = currentName {
                    entries.append(SubEntry(name: name, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
                }
                currentName = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        if let name = currentName {
            entries.append(SubEntry(name: name, body: currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return entries
    }

    private static func parsePeople(_ text: String) -> [Person] {
        parseSubEntries(text).map { entry in
            var name = entry.name
            var relationship: RelationshipType = .other
            // Parse "Name (relationship)"
            if let parenStart = name.lastIndex(of: "("),
               let parenEnd = name.lastIndex(of: ")"),
               parenStart < parenEnd {
                let relStr = String(name[name.index(after: parenStart)..<parenEnd]).trimmingCharacters(in: .whitespaces).lowercased()
                name = String(name[name.startIndex..<parenStart]).trimmingCharacters(in: .whitespaces)
                relationship = RelationshipType(rawValue: relStr) ?? .other
            }
            return Person(name: name, relationship: relationship, description: entry.body)
        }
    }

    private static func parseProjects(_ text: String) -> [Project] {
        parseSubEntries(text).map { entry in
            var name = entry.name
            var status: ProjectStatus = .active
            // Parse "Name [status]"
            if let bracketStart = name.lastIndex(of: "["),
               let bracketEnd = name.lastIndex(of: "]"),
               bracketStart < bracketEnd {
                let statusStr = String(name[name.index(after: bracketStart)..<bracketEnd]).trimmingCharacters(in: .whitespaces).lowercased()
                name = String(name[name.startIndex..<bracketStart]).trimmingCharacters(in: .whitespaces)
                status = ProjectStatus(rawValue: statusStr) ?? .active
            }
            return Project(name: name, status: status, description: entry.body)
        }
    }
}

// MARK: - Persistence

extension UserConfiguration {
    private static let storageKey = "userConfiguration"

    static func load() -> UserConfiguration? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(UserConfiguration.self, from: data) else {
            return nil
        }
        return config
    }

    static func save(_ config: UserConfiguration) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
