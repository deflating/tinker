import Foundation

// MARK: - Cognitive Style Options

enum GuidanceStyle: String, CaseIterable, Identifiable {
    case wander = "Let ideas wander"
    case direct = "Guide directly"
    case balance = "Balance both"
    var id: String { rawValue }
}

enum StartingPoint: String, CaseIterable, Identifiable {
    case bigPicture = "Start with the big picture"
    case details = "Details first"
    case depends = "Depends on topic"
    var id: String { rawValue }
}

enum ThreadingStyle: String, CaseIterable, Identifiable {
    case stepByStep = "Explain step by step"
    case allAtOnce = "All at once"
    case flexible = "Flexible"
    var id: String { rawValue }
}

// MARK: - Neurodivergence

struct NeurodivergenceOption: Identifiable, Hashable {
    let id: String
    let label: String

    static let common: [NeurodivergenceOption] = [
        .init(id: "adhd", label: "ADHD"),
        .init(id: "autism", label: "Autism"),
        .init(id: "dyslexia", label: "Dyslexia"),
        .init(id: "dyscalculia", label: "Dyscalculia"),
        .init(id: "ocd", label: "OCD"),
        .init(id: "tourettes", label: "Tourette's"),
        .init(id: "bipolar", label: "Bipolar"),
        .init(id: "ptsd", label: "PTSD"),
        .init(id: "anxiety", label: "Anxiety"),
        .init(id: "depression", label: "Depression"),
    ]
}

enum NDQualifier: String, CaseIterable, Identifiable {
    case confirmed = ""
    case maybe = "Maybe"
    case suspected = "Suspected"
    case diagnosed = "Diagnosed"
    var id: String { rawValue }
    var display: String { self == .confirmed ? "Yes" : rawValue }
}

// MARK: - Relationship Types

enum RelationshipType: String, CaseIterable, Identifiable {
    case pet = "pet"
    case family = "family"
    case partner = "partner"
    case closeFriend = "close friend"
    case friend = "friend"
    case colleague = "colleague"
    case significant = "significant"
    case medical = "medical"
    case other = "other"
    var id: String { rawValue }
}

// MARK: - Project Status

enum ProjectStatus: String, CaseIterable, Identifiable {
    case active = "active"
    case legacy = "legacy"
    case paused = "paused"
    case planned = "planned"
    case archived = "archived"
    var id: String { rawValue }
}

// MARK: - Value Banks

let commonValues: [String] = [
    "Accuracy > comfort",
    "Authorship > automation",
    "Clarity > reassurance",
    "Depth > breadth",
    "Being understood > being soothed",
    "Constraint > open encouragement",
    "Honesty > harmony",
    "Privacy > visibility",
    "Quality > speed",
    "Autonomy > guidance",
    "Simplicity > completeness",
    "Action > perfection",
    "Substance > style",
    "Growth > safety",
]

// MARK: - Agent Behavior Banks

let commonBehaviors: [String] = [
    "Challenge me when I'm wrong",
    "Admit uncertainty clearly",
    "Calibrate emotional tone to context",
    "Be present, not performative",
    "Match directness",
    "Be okay with uncertainty and meandering",
    "Don't shy away from the philosophical",
    "Ask clarifying questions",
    "Offer alternatives",
    "Explain reasoning",
]

let commonAvoidances: [String] = [
    "Treating user as fragile",
    "Flattening interesting questions into safe answers",
    "Overlong essays",
    "Leading with references to past sessions",
    "Starting with 'Great question!'",
    "Bullet-point brain when prose would be better",
    "Unsolicited advice",
    "Excessive caveats",
    "Performative enthusiasm",
    "Over-apologizing",
]

let commonToneOptions: [String] = [
    "Be direct",
    "Be warm",
    "Be formal",
    "Be casual",
    "No sycophancy",
    "No hedging",
    "Use humor",
    "Be concise",
    "Be thorough",
    "Be playful",
]
