import Foundation
import Observation

@Observable
final class SeedManager {

    enum SeedFile: String, CaseIterable {
        case user = "user.md"
        case agent = "agent.md"
        case now = "now.md"
        case episodic = "episodic.md"
        case semantic = "semantic.md"

        var displayName: String {
            switch self {
            case .user: "User"
            case .agent: "Agent"
            case .now: "Now"
            case .episodic: "Episodic"
            case .semantic: "Semantic"
            }
        }
    }

    private let seedsDirectory: URL

    var lastModified: [SeedFile: Date] = [:]
    var contents: [SeedFile: String] = [:]

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.seedsDirectory = base.appendingPathComponent(".memorable/data/seeds")
        ensureDirectoryExists()
        loadAll()
    }

    // MARK: - Directory Setup

    private func ensureDirectoryExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: seedsDirectory.path) {
            try? fm.createDirectory(at: seedsDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Read / Write

    func fileURL(for seed: SeedFile) -> URL {
        seedsDirectory.appendingPathComponent(seed.rawValue)
    }

    func read(_ seed: SeedFile) -> String {
        (try? String(contentsOf: fileURL(for: seed), encoding: .utf8)) ?? ""
    }

    func write(_ seed: SeedFile, content: String) throws {
        try content.write(to: fileURL(for: seed), atomically: true, encoding: .utf8)
        contents[seed] = content
        lastModified[seed] = Date()
    }

    func loadAll() {
        let fm = FileManager.default
        for seed in SeedFile.allCases {
            let url = fileURL(for: seed)
            contents[seed] = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let date = attrs[.modificationDate] as? Date {
                lastModified[seed] = date
            }
        }
    }
}
