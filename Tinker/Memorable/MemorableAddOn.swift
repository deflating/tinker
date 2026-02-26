import Foundation
import os.log

/// Memorable — a complete memory system for Tinker.
/// Three layers: working (real-time), episodic (5-day rolling), semantic (long-term).
/// Identity (persona/preferences) is owned by Familiar, not Memorable.
/// Memory files (episodic, semantic, working) are read actively by Claude, not injected.
@Observable
@MainActor
class MemorableAddOn: TinkerAddOn {
    static let shared = MemorableAddOn()

    let id = "memorable"
    let name = "Memorable"
    let icon = "brain.head.profile"
    let description = "Memory system. Captures working context and distills long-term memory."

    private let logger = Logger(subsystem: "app.tinker", category: "Memorable")

    // MARK: - UserDefaults Keys

    private static let enabledKey = "memorableEnabled"
    private static let captureEnabledKey = "memorableCaptureEnabled"
    private static let distillationEnabledKey = "memorableDistillationEnabled"
    private static let distillationFrequencyKey = "memorableDistillationFrequency"
    private static let directoryKey = "memorableDirectory"
    private static let apiKeyKey = "memorableApiKey"
    private static let defaultDirectory = NSString("~/.memorable/data").expandingTildeInPath

    // MARK: - Settings

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var captureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.captureEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.captureEnabledKey) }
    }

    var distillationEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.distillationEnabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.distillationEnabledKey)
            if newValue { distiller.start() } else { distiller.stop() }
        }
    }

    var distillationFrequency: Int {
        get { UserDefaults.standard.integer(forKey: Self.distillationFrequencyKey).clamped(to: 1...12) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.distillationFrequencyKey)
            distiller.updateFrequency(newValue)
        }
    }

    var directory: String {
        get { UserDefaults.standard.string(forKey: Self.directoryKey) ?? Self.defaultDirectory }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.directoryKey)
            ensureDirectoryStructure()
            reloadFiles()
        }
    }

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: Self.apiKeyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Self.apiKeyKey) }
    }

    // MARK: - File Contents (cached for UI display)

    private(set) var episodicContent: String = ""
    private(set) var semanticContent: String = ""
    private(set) var workingLineCount: Int = 0
    private(set) var workingSize: Int = 0

    // MARK: - Sub-components

    let writer: WorkingMemoryWriter
    let distiller: MemorableDistiller

    // MARK: - File Paths

    var workingDirectory: String { "\(directory)/working" }
    var episodicPath: String { "\(directory)/episodic.md" }
    var semanticPath: String { "\(directory)/semantic.md" }

    // MARK: - Init

    init() {
        let dir = UserDefaults.standard.string(forKey: Self.directoryKey) ?? Self.defaultDirectory
        self.writer = WorkingMemoryWriter(directory: dir)
        self.distiller = MemorableDistiller(directory: dir)

        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.captureEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.captureEnabledKey)
        }
        if UserDefaults.standard.object(forKey: Self.distillationEnabledKey) == nil {
            UserDefaults.standard.set(false, forKey: Self.distillationEnabledKey)
        }
        if UserDefaults.standard.integer(forKey: Self.distillationFrequencyKey) == 0 {
            UserDefaults.standard.set(3, forKey: Self.distillationFrequencyKey)
        }

        ensureDirectoryStructure()
        reloadFiles()

        if distillationEnabled {
            let freq = UserDefaults.standard.integer(forKey: Self.distillationFrequencyKey).clamped(to: 1...12)
            distiller.start(timesPerDay: freq)
        }
    }

    // MARK: - TinkerAddOn

    var systemPromptContent: String? {
        // Memorable doesn't inject into the system prompt.
        // Identity comes from Familiar. Memory (episodic, semantic, working)
        // is read actively by Claude at session start.
        return nil
    }

    // MARK: - File Operations

    func reloadFiles() {
        episodicContent = readFile(at: episodicPath)
        semanticContent = readFile(at: semanticPath)
        updateWorkingStats()
    }

    func updateWorkingStats() {
        let stats = writer.stats()
        workingSize = stats.size
        workingLineCount = stats.lineCount
    }

    // MARK: - Directory Setup

    private func ensureDirectoryStructure() {
        let fm = FileManager.default
        let dirs = [directory, workingDirectory]
        for dir in dirs {
            if !fm.fileExists(atPath: dir) {
                try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            }
        }

        if !fm.fileExists(atPath: semanticPath) {
            let template = """
            # Semantic Memory

            ## Immutable

            <!-- Core identity facts. Never modified by automation. Edit manually. -->

            ---IMMUTABLE ABOVE / MUTABLE BELOW---

            ## Mutable

            <!-- Knowledge that graduated from episodic memory. Updated by distillation. -->

            """
            try? template.write(toFile: semanticPath, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Helpers

    private func readFile(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writeFile(_ content: String, at path: String) {
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - Int clamping

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
