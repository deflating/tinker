import Foundation

actor CloudReader {
    static let shared = CloudReader()

    private var containerURL: URL?
    private var isResolved = false

    private func resolveContainer() async {
        guard !isResolved else { return }
        isResolved = true
        containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.app.tinker"
        )?.appendingPathComponent("Documents")
    }

    private func documentsURL() async -> URL? {
        await resolveContainer()
        return containerURL
    }

    func readFile(relativePath: String) async -> String? {
        guard let base = await documentsURL() else { return nil }
        let url = base.appendingPathComponent(relativePath)

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: url.path) {
                return try? String(contentsOf: url, encoding: .utf8)
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return nil
    }

    func writeFile(relativePath: String, content: String) async {
        guard let base = await documentsURL() else { return }
        let url = base.appendingPathComponent(relativePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    func listFiles(in relativePath: String) async -> [URL] {
        guard let base = await documentsURL() else { return [] }
        let dir = base.appendingPathComponent(relativePath)

        try? FileManager.default.startDownloadingUbiquitousItem(at: dir)

        guard let enumerator = FileManager.default.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(url)
            }
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
