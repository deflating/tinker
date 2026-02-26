import Foundation
import os.log

/// Scheduled distillation job.
/// Reads working notes → calls Claude CLI (Haiku) → writes episodic.md and semantic.md.
/// Runs N times per day on a timer.
@MainActor
final class MemorableDistiller {

    private let logger = Logger(subsystem: "app.tinker", category: "MemorableDistiller")
    private var directory: String
    private var timer: Timer?

    private static let immutableSeparator = "---IMMUTABLE ABOVE / MUTABLE BELOW---"

    init(directory: String) {
        self.directory = directory
    }

    func updateDirectory(_ dir: String) {
        directory = dir
    }

    func updateFrequency(_ timesPerDay: Int) {
        guard timer != nil else { return }
        stop()
        start(timesPerDay: timesPerDay)
    }

    // MARK: - Scheduling

    func start(timesPerDay: Int? = nil) {
        stop()
        let freq = timesPerDay ?? MemorableAddOn.shared.distillationFrequency
        let intervalSeconds = (24.0 * 3600.0) / Double(max(freq, 1))
        logger.info("Starting distillation timer: every \(Int(intervalSeconds))s (\(freq)x/day)")

        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.runDistillation()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Run distillation manually (e.g., from settings button).
    func runNow() async {
        await runDistillation()
    }

    // MARK: - Distillation Pipeline

    private func runDistillation() async {
        let workingContent = MemorableAddOn.shared.writer.recentContent(days: 5)
        guard !workingContent.isEmpty else {
            logger.info("No working memory to distill")
            return
        }

        let episodicPath = "\(directory)/episodic.md"
        let semanticPath = "\(directory)/semantic.md"
        let existingEpisodic = (try? String(contentsOfFile: episodicPath, encoding: .utf8)) ?? ""
        let existingSemantic = (try? String(contentsOfFile: semanticPath, encoding: .utf8)) ?? ""

        // Step 1: Distill working notes → episodic.md
        logger.info("Running episodic distillation...")
        let episodicPrompt = """
        You are a memory distillation system. Read the raw conversation log and produce a concise \
        rolling summary of the last 5 days of activity.

        Rules:
        - Focus on what happened, what was decided, what was built, what problems were encountered
        - Use present tense for ongoing things, past tense for completed things
        - Group by topic/project, not chronologically
        - Be concise: aim for 500-1500 words total
        - Include dates where relevant
        - Drop small talk and routine exchanges
        - If there's an existing episodic summary, merge new information and drop entries older than 5 days
        - Output ONLY the summary, no preamble or explanation

        Here is the existing episodic summary (if any):

        \(existingEpisodic)

        ---

        Here is the raw working memory to distill:

        \(workingContent)

        ---

        Produce an updated 5-day rolling episodic summary. Drop anything older than 5 days.
        """

        if let newEpisodic = await callCLI(prompt: episodicPrompt) {
            try? newEpisodic.write(toFile: episodicPath, atomically: true, encoding: .utf8)
            logger.info("Wrote updated episodic.md (\(newEpisodic.count) chars)")
        }

        // Step 2: Graduate persistent knowledge → semantic.md (mutable section only)
        logger.info("Running semantic graduation...")
        let mutableSection = extractMutableSection(from: existingSemantic)

        let semanticPrompt = """
        You are a knowledge graduation system. Identify facts and knowledge that have persisted \
        across multiple days and should be stored in long-term memory.

        Rules:
        - Only graduate knowledge that has appeared consistently over multiple days
        - Focus on: project states, architectural decisions, file paths, learned patterns, \
          user preferences discovered through interaction, tool configurations
        - Do NOT include: transient conversation topics, one-off questions, debugging sessions \
          that were resolved
        - Keep the section organized with clear markdown headers
        - Merge with existing content — update entries, don't duplicate
        - Be concise: each fact should be 1-2 lines
        - Output ONLY the mutable section content, no preamble or explanation

        Here is the current mutable knowledge section:

        \(mutableSection)

        ---

        Here is the current episodic summary (what's been happening recently):

        \(existingEpisodic)

        ---

        Update the mutable knowledge section. Only add things that seem to have persisted \
        beyond a single session. Return ONLY the mutable section content.
        """

        if let newMutable = await callCLI(prompt: semanticPrompt) {
            let immutableSection = extractImmutableSection(from: existingSemantic)
            let newSemantic = immutableSection + "\n\n" + Self.immutableSeparator + "\n\n" + newMutable
            try? newSemantic.write(toFile: semanticPath, atomically: true, encoding: .utf8)
            logger.info("Wrote updated semantic.md mutable section (\(newMutable.count) chars)")
        }

        // Step 3: Purge working files older than 5 days
        MemorableAddOn.shared.writer.purgeOldFiles(days: 5)

        // Reload cached file contents
        MemorableAddOn.shared.reloadFiles()

        logger.info("Distillation complete")
    }

    // MARK: - Claude CLI

    private func callCLI(prompt: String) async -> String? {
        let claudePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/claude").path

        guard FileManager.default.fileExists(atPath: claudePath) else {
            logger.error("Claude CLI not found at \(claudePath)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = [
            "-p", prompt,
            "--model", "claude-haiku-4-5-20251001",
            "--max-turns", "1"
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            logger.error("Failed to launch Claude CLI: \(error.localizedDescription)")
            return nil
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

                if process.terminationStatus != 0 {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errOutput = String(data: errData, encoding: .utf8) ?? ""
                    Task { @MainActor in
                        self.logger.error("Claude CLI exited with code \(process.terminationStatus): \(errOutput.prefix(200))")
                    }
                }

                continuation.resume(returning: output?.isEmpty == true ? nil : output)
            }
        }
    }

    // MARK: - Semantic Section Parsing

    private func extractImmutableSection(from semantic: String) -> String {
        guard let range = semantic.range(of: Self.immutableSeparator) else {
            return semantic
        }
        return String(semantic[semantic.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractMutableSection(from semantic: String) -> String {
        guard let range = semantic.range(of: Self.immutableSeparator) else {
            return ""
        }
        return String(semantic[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
