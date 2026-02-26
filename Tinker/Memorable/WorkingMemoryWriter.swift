import Foundation
import os.log

/// Appends to working.md in real-time as messages flow through Tinker.
/// Taps into the same data flow as CommandRunner's callbacks.
/// Format:
///   [HH:MM] Matt: <text>
///   Claude: <text>
///     -> ToolName(target)
///   --- Session started YYYY-MM-DD HH:MM ---
@MainActor
final class WorkingMemoryWriter {

    private let logger = Logger(subsystem: "app.tinker", category: "WorkingMemory")
    private var directory: String
    private var fileHandle: FileHandle?
    private var currentSessionId: String?
    private var hasWrittenSessionHeader = false

    /// Non-isolated box for deinit cleanup.
    private nonisolated(unsafe) var _handleForDeinit: FileHandle?

    var filePath: String { "\(directory)/working.md" }

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
        // Truncate very long responses to keep working.md manageable
        let truncated = stripped.count > 2000 ? String(stripped.prefix(2000)) + " [...]" : stripped
        append("Claude: \(truncated)\n\n")
    }

    func logToolUse(name: String, target: String?) {
        ensureOpen()
        let suffix = target.map { "(\($0))" } ?? ""
        append("  -> \(name)\(suffix)\n")
    }

    // MARK: - Private

    private func ensureOpen() {
        guard fileHandle == nil else { return }
        let fm = FileManager.default
        let path = filePath

        // Ensure parent directory exists
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: "# Working Memory\n\n".data(using: .utf8))
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
}
