import Foundation
import os.log

/// Appends to per-session files in working/ directory in real-time as messages flow through Tinker.
/// Taps into the same data flow as CommandRunner's callbacks.
/// Format:
///   [HH:MM] Matt: <text>
///   Claude: <text>
///     -> ToolName(target)
///   --- Session started YYYY-MM-DD HH:MM ---
///
/// Each session gets its own file: working/YYYY-MM-DD-<sessionId>.md
/// This avoids iCloud sync conflicts when multiple machines write concurrently.
@MainActor
final class WorkingMemoryWriter {

    private let logger = Logger(subsystem: "app.tinker", category: "WorkingMemory")
    private var directory: String
    private var fileHandle: FileHandle?
    private var currentSessionId: String?
    private var currentFilePath: String?
    private var hasWrittenSessionHeader = false

    /// Non-isolated box for deinit cleanup.
    private nonisolated(unsafe) var _handleForDeinit: FileHandle?

    var workingDirectory: String { "\(directory)/working" }

    init(directory: String) {
        self.directory = directory
    }

    deinit {
        try? _handleForDeinit?.close()
    }

    func updateDirectory(_ dir: String) {
        close()
        directory = dir
    }

    // MARK: - Session Lifecycle

    func startSession(id: String) {
        if currentSessionId != id {
            close()
            currentSessionId = id
            hasWrittenSessionHeader = false

            let dateStr = Self.dateOnly()
            let shortId = String(id.prefix(8))
            currentFilePath = "\(workingDirectory)/\(dateStr)-\(shortId).md"
        }
        ensureOpen()
        if !hasWrittenSessionHeader {
            let separator = "\n--- Session started \(Self.timestamp()) ---\n\n"
            append(separator)
            hasWrittenSessionHeader = true
        }
    }

    // MARK: - Capture

    func logUserMessage(_ text: String) {
        ensureOpen()
        let stripped = stripSystemReminders(text)
        guard !stripped.isEmpty else { return }
        append("[\(Self.timeOnly())] Matt: \(stripped)\n\n")
    }

    func logAssistantMessage(_ text: String) {
        ensureOpen()
        guard !text.isEmpty else { return }
        let stripped = stripSystemReminders(text)
        guard !stripped.isEmpty else { return }
        // Truncate very long responses to keep files manageable
        let truncated = stripped.count > 2000 ? String(stripped.prefix(2000)) + " [...]" : stripped
        append("Claude: \(truncated)\n\n")
    }

    func logToolUse(name: String, target: String?) {
        ensureOpen()
        let suffix = target.map { "(\($0))" } ?? ""
        append("  -> \(name)\(suffix)\n")
    }

    // MARK: - Stats

    /// Returns total size and line count across all working files.
    func stats() -> (size: Int, lineCount: Int, fileCount: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: workingDirectory) else {
            return (0, 0, 0)
        }
        let mdFiles = files.filter { $0.hasSuffix(".md") }
        var totalSize = 0
        var totalLines = 0
        for file in mdFiles {
            let path = "\(workingDirectory)/\(file)"
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int {
                totalSize += size
            }
            if let content = try? String(contentsOfFile: path, encoding: .utf8) {
                totalLines += content.components(separatedBy: "\n").count
            }
        }
        return (totalSize, totalLines, mdFiles.count)
    }

    /// Returns all working file contents within the last N days, concatenated.
    func recentContent(days: Int = 5) -> String {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: workingDirectory) else {
            return ""
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = Self.dateOnlyFormatter().string(from: cutoff)

        let mdFiles = files.filter { $0.hasSuffix(".md") }
            .sorted()
            .filter { $0 >= cutoffStr }  // date-prefixed filenames sort chronologically

        var parts: [String] = []
        for file in mdFiles {
            if let content = try? String(contentsOfFile: "\(workingDirectory)/\(file)", encoding: .utf8) {
                parts.append(content)
            }
        }
        return parts.joined(separator: "\n")
    }

    /// Removes working files older than N days.
    func purgeOldFiles(days: Int = 5) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: workingDirectory) else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let cutoffStr = Self.dateOnlyFormatter().string(from: cutoff)

        for file in files where file.hasSuffix(".md") && file < cutoffStr {
            let path = "\(workingDirectory)/\(file)"
            try? fm.removeItem(atPath: path)
            logger.info("Purged old working file: \(file)")
        }
    }

    // MARK: - Private

    private func ensureOpen() {
        guard fileHandle == nil, let path = currentFilePath else { return }
        let fm = FileManager.default

        // Ensure working directory exists
        if !fm.fileExists(atPath: workingDirectory) {
            try? fm.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path))
        _handleForDeinit = fileHandle
        fileHandle?.seekToEndOfFile()
    }

    private func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }

    private func close() {
        try? fileHandle?.close()
        fileHandle = nil
        _handleForDeinit = nil
    }

    /// Strip <system-reminder>...</system-reminder> blocks and thinking blocks.
    private func stripSystemReminders(_ text: String) -> String {
        var result = text
        // Remove system-reminder blocks
        while let start = result.range(of: "<system-reminder>"),
              let end = result.range(of: "</system-reminder>") {
            let fullRange = start.lowerBound..<end.upperBound
            result.removeSubrange(fullRange)
        }
        // Trim whitespace artifacts
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Timestamps

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private static func timeOnly() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private static func dateOnly() -> String {
        dateOnlyFormatter().string(from: Date())
    }

    private static func dateOnlyFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
