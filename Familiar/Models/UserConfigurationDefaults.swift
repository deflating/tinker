import Foundation

enum UserConfigurationDefaults {

    // MARK: - Neurodivergence Options

    static let neurodivergenceOptions: [String] = [
        "ADHD",
        "Autism",
        "Dyslexia",
        "OCD",
        "Anxiety",
        "Depression",
        "PTSD",
        "Bipolar",
        "Tourette's",
        "Dyscalculia",
    ]

    // MARK: - Values

    static let valueOptions: [String] = [
        "Accuracy > comfort",
        "Honesty > harmony",
        "Authorship > automation",
        "Clarity > reassurance",
        "Depth > breadth",
        "Being understood > being soothed",
        "Constraint > open encouragement",
        "Privacy > convenience",
        "Simplicity > completeness",
        "Action > analysis",
        "Autonomy > consensus",
        "Curiosity > certainty",
        "Craft > speed",
        "Substance > style",
    ]

    // MARK: - Relationship Types

    static let relationshipTypes: [UserConfiguration.RelationshipType] = UserConfiguration.RelationshipType.allCases

    // MARK: - Project Statuses

    static let projectStatuses: [UserConfiguration.ProjectStatus] = UserConfiguration.ProjectStatus.allCases

    // MARK: - Cognitive Style Options

    static let cognitiveStyleOptions: [String: [String]] = [
        "Guidance Style": [
            "Let ideas wander",
            "Keep me on track",
            "Ask clarifying questions",
            "Offer structured frameworks",
        ],
        "Starting Point": [
            "Start with the big picture",
            "Start with details",
            "Start with examples",
            "Start with context",
        ],
        "Threading": [
            "Explain step by step",
            "Give me the summary",
            "Show me the connections",
            "Let me discover it",
        ],
    ]

    // MARK: - Interest Categories

    static let interestCategories: [String] = [
        "AI/ML",
        "Programming",
        "Music",
        "Photography",
        "Gaming",
        "Reading",
        "Writing",
        "Design",
        "Hardware",
        "Science",
        "Philosophy",
        "Fitness",
        "Cooking",
        "Travel",
        "Film",
        "Art",
    ]
}
