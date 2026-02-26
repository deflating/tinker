import Foundation

@Observable
@MainActor
class FamiliarAddOn: TinkerAddOn {
    static let shared = FamiliarAddOn()

    let id = "familiar"
    let name = "Familiar"
    let icon = "person.text.rectangle"
    let description = "Identity and persona. Injects seed files into every session."

    private static let enabledKey = "familiarEnabled"
    private static let directoryKey = "familiarDirectory"
    private static let defaultDirectory = NSString("~/.familiar/seeds").expandingTildeInPath

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var directory: String {
        get { UserDefaults.standard.string(forKey: Self.directoryKey) ?? Self.defaultDirectory }
        set { UserDefaults.standard.set(newValue, forKey: Self.directoryKey); startWatching() }
    }

    private(set) var preferencesContent: String = ""
    private(set) var personaContent: String = ""
    private(set) var preferencesModified: Date?
    private(set) var personaModified: Date?

    private var fileMonitor: DispatchSourceFileSystemObject?
    private var directoryDescriptor: Int32 = -1

    var systemPromptContent: String? {
        guard isEnabled else { return nil }
        var parts: [String] = []
        if !preferencesContent.isEmpty {
            parts.append("## Preferences\n\n\(preferencesContent)")
        }
        if !personaContent.isEmpty {
            parts.append("## Persona\n\n\(personaContent)")
        }
        guard !parts.isEmpty else { return nil }
        return "# Familiar\n\n" + parts.joined(separator: "\n\n---\n\n")
    }

    init() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.enabledKey)
        }
        reload()
        startWatching()
    }

    func reload() {
        let dir = directory
        preferencesContent = readFile(at: "\(dir)/preferences.md")
        personaContent = readFile(at: "\(dir)/persona.md")
        preferencesModified = modDate(at: "\(dir)/preferences.md")
        personaModified = modDate(at: "\(dir)/persona.md")
    }

    func savePreferences(_ content: String) {
        writeFile(content, at: "\(directory)/preferences.md")
        preferencesContent = content
        preferencesModified = Date()
    }

    func savePersona(_ content: String) {
        writeFile(content, at: "\(directory)/persona.md")
        personaContent = content
        personaModified = Date()
    }

    // MARK: - File Watching

    private func startWatching() {
        stopWatching()

        let path = directory
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }

        directoryDescriptor = open(path, O_EVTONLY)
        guard directoryDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryDescriptor,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reload()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.directoryDescriptor, fd >= 0 { close(fd) }
            self?.directoryDescriptor = -1
        }
        source.resume()
        fileMonitor = source
    }

    private func stopWatching() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }

    // MARK: - Helpers

    private func readFile(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writeFile(_ content: String, at path: String) {
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func modDate(at path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}
