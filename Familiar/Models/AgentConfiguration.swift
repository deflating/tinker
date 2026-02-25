import Foundation

struct AgentConfiguration: Identifiable, Codable, Equatable {
    var id: String
    var identity: Identity
    var personality: Personality
    var communicationStyle: CommunicationStyle
    var knowledgeDomains: [String]
    var behavioralRules: [String]
    var boundaries: [String]
    var responseFormat: ResponseFormat
    var autonomyLevel: AutonomyLevel
    var emotionalIntelligence: EmotionalIntelligence
    var customSections: [CustomSection]
    var customInstructions: String

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
        personality: Personality = .init(),
        communicationStyle: CommunicationStyle = .init(),
        knowledgeDomains: [String] = [],
        behavioralRules: [String] = [],
        boundaries: [String] = [],
        responseFormat: ResponseFormat = .init(),
        autonomyLevel: AutonomyLevel = .init(),
        emotionalIntelligence: EmotionalIntelligence = .init(),
        customSections: [CustomSection] = [],
        customInstructions: String = ""
    ) {
        self.id = id
        self.identity = identity
        self.personality = personality
        self.communicationStyle = communicationStyle
        self.knowledgeDomains = knowledgeDomains
        self.behavioralRules = behavioralRules
        self.boundaries = boundaries
        self.responseFormat = responseFormat
        self.autonomyLevel = autonomyLevel
        self.emotionalIntelligence = emotionalIntelligence
        self.customSections = customSections
        self.customInstructions = customInstructions
    }
}

// MARK: - Identity

extension AgentConfiguration {
    struct Identity: Codable, Equatable {
        var name: String
        var icon: String
        var roleDescription: String
        var tagline: String

        init(
            name: String = "Assistant",
            icon: String = "sparkle",
            roleDescription: String = "A helpful AI assistant",
            tagline: String = ""
        ) {
            self.name = name
            self.icon = icon
            self.roleDescription = roleDescription
            self.tagline = tagline
        }
    }
}

// MARK: - Personality

extension AgentConfiguration {
    struct Personality: Codable, Equatable {
        var warmth: Int
        var humor: Int
        var formality: Int
        var curiosity: Int
        var confidence: Int
        var patience: Int

        init(
            warmth: Int = 70,
            humor: Int = 40,
            formality: Int = 50,
            curiosity: Int = 60,
            confidence: Int = 70,
            patience: Int = 80
        ) {
            self.warmth = warmth
            self.humor = humor
            self.formality = formality
            self.curiosity = curiosity
            self.confidence = confidence
            self.patience = patience
        }
    }
}

// MARK: - Communication Style

extension AgentConfiguration {
    struct CommunicationStyle: Codable, Equatable {
        var verbosity: Verbosity
        var tone: Tone
        var useEmoji: Bool
        var useMarkdown: Bool
        var preferredLanguage: String

        init(
            verbosity: Verbosity = .balanced,
            tone: Tone = .neutral,
            useEmoji: Bool = false,
            useMarkdown: Bool = true,
            preferredLanguage: String = "en"
        ) {
            self.verbosity = verbosity
            self.tone = tone
            self.useEmoji = useEmoji
            self.useMarkdown = useMarkdown
            self.preferredLanguage = preferredLanguage
        }
    }

    enum Verbosity: String, Codable, CaseIterable {
        case terse
        case concise
        case balanced
        case detailed
        case verbose
    }

    enum Tone: String, Codable, CaseIterable {
        case casual
        case friendly
        case neutral
        case professional
        case formal
    }
}

// MARK: - Response Format

extension AgentConfiguration {
    struct ResponseFormat: Codable, Equatable {
        var defaultLength: ResponseLength
        var listStyle: ListStyle
        var codeStyle: CodeStyle
        var includeExplanations: Bool
        var includeSources: Bool

        init(
            defaultLength: ResponseLength = .medium,
            listStyle: ListStyle = .bullets,
            codeStyle: CodeStyle = .commented,
            includeExplanations: Bool = true,
            includeSources: Bool = false
        ) {
            self.defaultLength = defaultLength
            self.listStyle = listStyle
            self.codeStyle = codeStyle
            self.includeExplanations = includeExplanations
            self.includeSources = includeSources
        }
    }

    enum ResponseLength: String, Codable, CaseIterable {
        case brief
        case medium
        case long
        case unrestricted
    }

    enum ListStyle: String, Codable, CaseIterable {
        case bullets
        case numbered
        case prose
        case headers
    }

    enum CodeStyle: String, Codable, CaseIterable {
        case minimal
        case commented
        case documented
    }
}

// MARK: - Autonomy Level

extension AgentConfiguration {
    struct AutonomyLevel: Codable, Equatable {
        var proactivity: Int
        var askBeforeActing: Bool
        var suggestImprovements: Bool
        var autoCorrect: Bool

        init(
            proactivity: Int = 50,
            askBeforeActing: Bool = true,
            suggestImprovements: Bool = true,
            autoCorrect: Bool = false
        ) {
            self.proactivity = proactivity
            self.askBeforeActing = askBeforeActing
            self.suggestImprovements = suggestImprovements
            self.autoCorrect = autoCorrect
        }
    }
}

// MARK: - Emotional Intelligence

extension AgentConfiguration {
    struct EmotionalIntelligence: Codable, Equatable {
        var empathyLevel: Int
        var encouragementStyle: EncouragementStyle
        var handleFrustration: FrustrationResponse
        var celebrateSuccess: Bool

        init(
            empathyLevel: Int = 60,
            encouragementStyle: EncouragementStyle = .supportive,
            handleFrustration: FrustrationResponse = .acknowledge,
            celebrateSuccess: Bool = true
        ) {
            self.empathyLevel = empathyLevel
            self.encouragementStyle = encouragementStyle
            self.handleFrustration = handleFrustration
            self.celebrateSuccess = celebrateSuccess
        }
    }

    enum EncouragementStyle: String, Codable, CaseIterable {
        case minimal
        case supportive
        case enthusiastic
        case coaching
    }

    enum FrustrationResponse: String, Codable, CaseIterable {
        case acknowledge
        case redirect
        case simplify
        case stepBack
    }
}

// MARK: - Label Helpers

func warmthLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Reserved"
    case 20..<40: return "Cool"
    case 40..<60: return "Neutral"
    case 60..<80: return "Warm"
    default: return "Very warm"
    }
}

func humorLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Serious"
    case 20..<40: return "Dry"
    case 40..<60: return "Balanced"
    case 60..<80: return "Witty"
    default: return "Playful"
    }
}

func formalityLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Very casual"
    case 20..<40: return "Casual"
    case 40..<60: return "Balanced"
    case 60..<80: return "Formal"
    default: return "Very formal"
    }
}

func curiosityLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Task-focused"
    case 20..<40: return "Practical"
    case 40..<60: return "Balanced"
    case 60..<80: return "Inquisitive"
    default: return "Deeply curious"
    }
}

func confidenceLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Tentative"
    case 20..<40: return "Cautious"
    case 40..<60: return "Balanced"
    case 60..<80: return "Confident"
    default: return "Assertive"
    }
}

func patienceLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Direct"
    case 20..<40: return "Efficient"
    case 40..<60: return "Balanced"
    case 60..<80: return "Patient"
    default: return "Very patient"
    }
}

func proactivityLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Only when asked"
    case 20..<40: return "Mostly reactive"
    case 40..<60: return "Balanced"
    case 60..<80: return "Proactive"
    default: return "Highly autonomous"
    }
}

func empathyLabel(_ v: Int) -> String {
    switch v {
    case 0..<20: return "Matter-of-fact"
    case 20..<40: return "Practical"
    case 40..<60: return "Balanced"
    case 60..<80: return "Empathetic"
    default: return "Deeply empathetic"
    }
}

// MARK: - Markdown Export

extension AgentConfiguration {
    func toMarkdown() -> String {
        var lines: [String] = []

        // Header
        lines.append("# \(identity.name)")
        lines.append("")
        var meta: [String] = []
        if !identity.tagline.isEmpty { meta.append("**Tagline:** \(identity.tagline)") }
        meta.append("**Role:** \(identity.roleDescription)")
        if !meta.isEmpty { lines.append(meta.joined(separator: " | ")) }
        lines.append("")

        // Personality
        lines.append("## Character Traits")
        lines.append("")
        lines.append("- **Warmth:** \(warmthLabel(personality.warmth)) (\(personality.warmth)/100)")
        lines.append("- **Humor:** \(humorLabel(personality.humor)) (\(personality.humor)/100)")
        lines.append("- **Formality:** \(formalityLabel(personality.formality)) (\(personality.formality)/100)")
        lines.append("- **Curiosity:** \(curiosityLabel(personality.curiosity)) (\(personality.curiosity)/100)")
        lines.append("- **Confidence:** \(confidenceLabel(personality.confidence)) (\(personality.confidence)/100)")
        lines.append("- **Patience:** \(patienceLabel(personality.patience)) (\(personality.patience)/100)")
        lines.append("")

        // Communication Style
        lines.append("## Tone & Format")
        lines.append("")
        lines.append("- Verbosity: \(communicationStyle.verbosity.rawValue.capitalized)")
        lines.append("- Tone: \(communicationStyle.tone.rawValue.capitalized)")
        if communicationStyle.useEmoji { lines.append("- Use emoji") }
        if !communicationStyle.useMarkdown { lines.append("- Avoid markdown formatting") }
        lines.append("")

        // Knowledge Domains
        if !knowledgeDomains.isEmpty {
            lines.append("## Knowledge Domains")
            lines.append("")
            for domain in knowledgeDomains { lines.append("- \(domain)") }
            lines.append("")
        }

        // Behavioral Rules
        if !behavioralRules.isEmpty {
            lines.append("## Behaviors")
            lines.append("")
            for rule in behavioralRules { lines.append("- \(rule)") }
            lines.append("")
        }

        // Boundaries
        if !boundaries.isEmpty {
            lines.append("## Avoid")
            lines.append("")
            for boundary in boundaries { lines.append("- \(boundary)") }
            lines.append("")
        }

        // Response Format
        lines.append("## Response Format")
        lines.append("")
        lines.append("- Default length: \(responseFormat.defaultLength.rawValue.capitalized)")
        lines.append("- List style: \(responseFormat.listStyle.rawValue.capitalized)")
        lines.append("- Code style: \(responseFormat.codeStyle.rawValue.capitalized)")
        if responseFormat.includeExplanations { lines.append("- Include explanations") }
        if responseFormat.includeSources { lines.append("- Include sources") }
        lines.append("")

        // Autonomy
        lines.append("## Autonomy")
        lines.append("")
        lines.append("- **Autonomy:** \(proactivityLabel(autonomyLevel.proactivity)) (\(autonomyLevel.proactivity)/100)")
        if autonomyLevel.askBeforeActing { lines.append("- Ask before acting") }
        if autonomyLevel.suggestImprovements { lines.append("- Suggest improvements") }
        if autonomyLevel.autoCorrect { lines.append("- Auto-correct errors") }
        lines.append("")

        // Emotional Intelligence
        lines.append("## Emotional Intelligence")
        lines.append("")
        lines.append("- **Empathy:** \(empathyLabel(emotionalIntelligence.empathyLevel)) (\(emotionalIntelligence.empathyLevel)/100)")
        lines.append("- Encouragement style: \(emotionalIntelligence.encouragementStyle.rawValue.capitalized)")
        lines.append("- Frustration response: \(emotionalIntelligence.handleFrustration.rawValue.capitalized)")
        if emotionalIntelligence.celebrateSuccess { lines.append("- Celebrate successes") }
        lines.append("")

        // Custom Sections
        for section in customSections where !section.title.isEmpty {
            lines.append("## \(section.title)")
            lines.append("")
            lines.append(section.body.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        // Custom Instructions
        if !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("## Custom Instructions")
            lines.append("")
            lines.append(customInstructions.trimmingCharacters(in: .whitespacesAndNewlines))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - Markdown Import

extension AgentConfiguration {
    /// Known section headings that map to structured fields
    private static let knownSections: Set<String> = [
        "Character Traits", "Tone & Format", "Knowledge Domains",
        "Behaviors", "Avoid", "Response Format", "Autonomy",
        "Emotional Intelligence", "Custom Instructions",
        // Also recognize common seed file variants
        "Personality", "Communication Style", "Behavioral Rules", "Boundaries",
    ]

    static func fromMarkdown(_ markdown: String) -> AgentConfiguration {
        var config = AgentConfiguration()

        // Parse into sections
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

        // Parse header (# Name line and **Key:** Value pairs)
        let headerText = headerLines.joined(separator: "\n")
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
                        case "role": config.identity.roleDescription = val
                        case "tagline": config.identity.tagline = val
                        case "model": config.identity.tagline = val // store model as tagline
                        default: break
                        }
                    }
                }
            }
        }

        // Parse each section
        for section in sections {
            let heading = section.heading
            let body = section.body

            switch heading {
            case "Character Traits", "Personality":
                // Parse slider lines: - **Name:** Label (N/100)
                let traitLines = body.components(separatedBy: "\n")
                for tLine in traitLines {
                    let cleaned = tLine.trimmingCharacters(in: .whitespaces)
                    guard cleaned.hasPrefix("- **") else { continue }
                    let inner = String(cleaned.dropFirst(4))
                    guard let colonEnd = inner.range(of: ":**") else { continue }
                    let name = String(inner[inner.startIndex..<colonEnd.lowerBound]).lowercased()
                    let rest = String(inner[colonEnd.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if let parenStart = rest.lastIndex(of: "("),
                       let slashIdx = rest.lastIndex(of: "/"),
                       parenStart < slashIdx,
                       let num = Int(rest[rest.index(after: parenStart)..<slashIdx]) {
                        switch name {
                        case "warmth": config.personality.warmth = num
                        case "humor": config.personality.humor = num
                        case "formality": config.personality.formality = num
                        case "curiosity": config.personality.curiosity = num
                        case "confidence": config.personality.confidence = num
                        case "patience": config.personality.patience = num
                        default: break
                        }
                    }
                }

            case "Tone & Format", "Communication Style":
                let bullets = parseBulletItems(body)
                for bullet in bullets {
                    let lower = bullet.lowercased()
                    if lower.hasPrefix("verbosity:") {
                        let val = String(bullet.dropFirst(10)).trimmingCharacters(in: .whitespaces).lowercased()
                        config.communicationStyle.verbosity = Verbosity(rawValue: val) ?? .balanced
                    } else if lower.hasPrefix("tone:") {
                        let val = String(bullet.dropFirst(5)).trimmingCharacters(in: .whitespaces).lowercased()
                        config.communicationStyle.tone = Tone(rawValue: val) ?? .neutral
                    } else if lower.contains("emoji") {
                        config.communicationStyle.useEmoji = true
                    } else if lower.contains("no sycophancy") || lower.contains("be direct") {
                        config.communicationStyle.tone = .casual
                    }
                }

            case "Knowledge Domains":
                config.knowledgeDomains = parseBulletItems(body)

            case "Behaviors", "Behavioral Rules":
                config.behavioralRules = parseBulletItems(body)

            case "Avoid", "Boundaries":
                config.boundaries = parseBulletItems(body)

            case "Response Format":
                let bullets = parseBulletItems(body)
                for bullet in bullets {
                    let lower = bullet.lowercased()
                    if lower.hasPrefix("default length:") {
                        let val = String(bullet.dropFirst(15)).trimmingCharacters(in: .whitespaces).lowercased()
                        config.responseFormat.defaultLength = ResponseLength(rawValue: val) ?? .medium
                    } else if lower.hasPrefix("list style:") {
                        let val = String(bullet.dropFirst(11)).trimmingCharacters(in: .whitespaces).lowercased()
                        config.responseFormat.listStyle = ListStyle(rawValue: val) ?? .bullets
                    } else if lower.hasPrefix("code style:") {
                        let val = String(bullet.dropFirst(11)).trimmingCharacters(in: .whitespaces).lowercased()
                        config.responseFormat.codeStyle = CodeStyle(rawValue: val) ?? .commented
                    }
                }

            case "Autonomy":
                let traitLines = body.components(separatedBy: "\n")
                for tLine in traitLines {
                    let cleaned = tLine.trimmingCharacters(in: .whitespaces)
                    if cleaned.contains("/100"),
                       let parenStart = cleaned.lastIndex(of: "("),
                       let slashIdx = cleaned.lastIndex(of: "/"),
                       parenStart < slashIdx,
                       let num = Int(cleaned[cleaned.index(after: parenStart)..<slashIdx]) {
                        config.autonomyLevel.proactivity = num
                    } else {
                        let lower = cleaned.lowercased()
                        if lower.contains("ask before") { config.autonomyLevel.askBeforeActing = true }
                        if lower.contains("suggest improvement") { config.autonomyLevel.suggestImprovements = true }
                        if lower.contains("auto-correct") || lower.contains("auto correct") { config.autonomyLevel.autoCorrect = true }
                    }
                }

            case "Emotional Intelligence":
                let traitLines = body.components(separatedBy: "\n")
                for tLine in traitLines {
                    let cleaned = tLine.trimmingCharacters(in: .whitespaces)
                    if cleaned.contains("/100"),
                       let parenStart = cleaned.lastIndex(of: "("),
                       let slashIdx = cleaned.lastIndex(of: "/"),
                       parenStart < slashIdx,
                       let num = Int(cleaned[cleaned.index(after: parenStart)..<slashIdx]) {
                        config.emotionalIntelligence.empathyLevel = num
                    }
                }

            case "Custom Instructions":
                config.customInstructions = body

            default:
                // Any unrecognized section becomes a custom section
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
}

// MARK: - Persistence

extension AgentConfiguration {
    private static let storageKey = "agentConfigurations"

    static func loadAll() -> [AgentConfiguration] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let configs = try? JSONDecoder().decode([AgentConfiguration].self, from: data) else {
            return []
        }
        return configs
    }

    static func saveAll(_ configs: [AgentConfiguration]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
