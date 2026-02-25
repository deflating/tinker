import Foundation
import NaturalLanguage
import os.log

/// Memory pipeline:
/// L1 (per-batch): NLTagger extracts entities+sentiment, mechanical extraction for topic/outcomes → JSON entries
/// L2 (hourly): Haiku generates episodic.md from session notes; mechanical template as fallback
/// L3 (daily): Mechanical frequency-based graduation → semantic.md
/// Session notes: On idle (5min), Haiku summarizes transcript → notes.jsonl
@Observable
final class MemoryDaemon: @unchecked Sendable {

    static let shared = MemoryDaemon()

    private let logger = Logger(subsystem: "app.familiar", category: "MemoryDaemon")

    // MARK: - Configuration

    var batchSize: Int {
        let stored = UserDefaults.standard.integer(forKey: "daemonBatchSize")
        return stored > 0 ? stored : 5
    }

    /// How often to render episodic.md
    let renderInterval: TimeInterval = 60 * 60 // 1 hour

    /// How often to run semantic graduation
    let graduationInterval: TimeInterval = 24 * 60 * 60

    /// Minimum sessions for a topic to graduate to semantic
    let graduationThreshold = 4

    /// Minimum day-span for graduation
    let graduationDaySpan = 3

    /// Idle threshold for session note generation (seconds)
    let idleThreshold: TimeInterval = 300 // 5 minutes

    // MARK: - State

    private(set) var humanMessageCount = 0
    private(set) var isProcessing = false
    private(set) var lastExtraction: Date?
    private(set) var lastRender: Date?
    private(set) var lastGraduation: Date?
    private(set) var status: String?

    private var renderTimer: Timer?
    private var graduationTimer: Timer?
    private var idleTimer: Timer?

    /// Tracks last human message time for idle detection
    private var lastMessageTime: Date?
    /// Session IDs that have already been noted
    private var notedSessionIds: Set<String> = []
    /// Current active session ID (set externally)
    var activeSessionId: String?
    /// Current active transcript path (set externally)
    var activeTranscriptPath: String?

    // MARK: - Paths

    /// Structured JSON entries live here
    static let dataDir: String = {
        let dir = NSHomeDirectory() + "/.familiar/memory"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// JSON store of all extraction entries
    static let entriesPath: String = { dataDir + "/entries.json" }()

    /// JSONL store of Haiku-generated session notes
    static let notesPath: String = { dataDir + "/notes.jsonl" }()

    /// Seeds directory — where episodic.md gets written
    static let seedsDir: String = {
        let dir = NSHomeDirectory() + "/.memorable/data/seeds"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let episodicPath: String = { seedsDir + "/episodic.md" }()
    static let semanticPath: String = { seedsDir + "/semantic.md" }()

    /// Parses "2026-02-25 11:20:58" from transcript headers
    static let transcriptDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // MARK: - Entry Model

    struct MemoryEntry: Codable {
        let id: String
        let timestamp: Date
        let sessionId: String?

        var topic: String
        var outcomes: [String]

        // NLTagger-extracted
        var entities: [String]
        var sentiment: Double // -1.0 to 1.0
    }

    /// In-memory store, persisted to entries.json
    private var entries: [MemoryEntry] = []

    // MARK: - Session Note Model

    struct SessionNote: Codable {
        let ts: Date
        let sessionId: String
        let note: String
        let topicTags: [String]
    }

    // MARK: - Init

    init() {
        loadEntries()
        startTimers()
    }

    private func startTimers() {
        renderTimer = Timer.scheduledTimer(withTimeInterval: renderInterval, repeats: true) { [weak self] _ in
            Task { await self?.generateEpisodic() }
        }
        graduationTimer = Timer.scheduledTimer(withTimeInterval: graduationInterval, repeats: true) { [weak self] _ in
            Task { await self?.runGraduation() }
        }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.checkIdle() }
        }
    }

    // MARK: - Idle Detection

    private func checkIdle() async {
        guard let lastMsg = lastMessageTime,
              Date().timeIntervalSince(lastMsg) > idleThreshold,
              let sessionId = activeSessionId,
              !notedSessionIds.contains(sessionId),
              let transcriptPath = activeTranscriptPath else {
            return
        }

        debugLog("Idle detected for session \(sessionId), generating session note")
        await generateSessionNote(transcriptPath: transcriptPath, sessionId: sessionId)
    }

    // MARK: - L1: Per-Batch Extraction

    private var pendingMessages: [(role: String, content: String)] = []

    func onHumanMessage(_ content: String) {
        pendingMessages.append((role: "human", content: content))
        humanMessageCount += 1
        lastMessageTime = Date()
        debugLog("onHumanMessage: count=\(humanMessageCount)/\(batchSize), pending=\(pendingMessages.count)")

        if humanMessageCount >= batchSize {
            triggerExtraction()
        }
    }

    func onAssistantMessage(_ content: String) {
        pendingMessages.append((role: "assistant", content: content))
    }

    func triggerExtraction() {
        guard !isProcessing, !pendingMessages.isEmpty else { return }

        debugLog("triggerExtraction: processing \(pendingMessages.count) messages")
        let batch = pendingMessages
        pendingMessages = []
        humanMessageCount = 0

        Task { await extractL1(batch) }
    }

    private func extractL1(_ messages: [(role: String, content: String)]) async {
        isProcessing = true
        defer { isProcessing = false }

        let conversationText = messages.map { msg in
            let label = msg.role == "human" ? "Human" : "Assistant"
            let text = msg.content.count > 500 ? String(msg.content.prefix(500)) + "..." : msg.content
            return "\(label): \(text)"
        }.joined(separator: "\n\n")

        // Mechanical extraction from the conversation text
        let mechanicalResult = extractMechanicallyFromText(conversationText)
        let taggerResult = extractWithNLTagger(conversationText)

        guard !mechanicalResult.topic.trimmingCharacters(in: .whitespaces).isEmpty else {
            logger.info("L1: No meaningful extraction from \(messages.count) messages")
            return
        }

        let entry = MemoryEntry(
            id: UUID().uuidString,
            timestamp: Date(),
            sessionId: activeSessionId,
            topic: mechanicalResult.topic,
            outcomes: mechanicalResult.outcomes,
            entities: taggerResult.entities,
            sentiment: taggerResult.sentiment
        )

        entries.append(entry)
        saveEntries()
        lastExtraction = Date()
        logger.info("L1: Extracted topic='\(mechanicalResult.topic)' outcomes=\(mechanicalResult.outcomes.count) entities=\(taggerResult.entities.count)")
    }

    /// Simple mechanical extraction from conversation text (no transcript structure)
    private func extractMechanicallyFromText(_ text: String) -> MechanicalExtraction {
        let lines = text.components(separatedBy: "\n")
        let firstLine = lines.first(where: { $0.hasPrefix("Human:") })?.replacingOccurrences(of: "Human: ", with: "") ?? "Session"
        let topic = firstLine.count > 80 ? String(firstLine.prefix(80)) : firstLine
        let filePaths = extractAllFilePaths(from: text).map { ($0 as NSString).lastPathComponent }
        var outcomes: [String] = []
        if !filePaths.isEmpty {
            outcomes.append("Files: \(Array(Set(filePaths)).prefix(4).joined(separator: ", "))")
        }
        return MechanicalExtraction(topic: topic, outcomes: outcomes, mentionedFiles: filePaths)
    }

    struct TaggerResult {
        var entities: [String]
        var sentiment: Double
    }

    /// Common words NLTagger misidentifies as entities in conversational text
    private static let entityBlocklist: Set<String> = [
        "'s", "OK", "BTW", "Hmm", "Yeah", "Nah", "Hey", "Hi", "Lol",
        "API", "CLI", "URL", "UI", "UX", "CSS", "HTML", "JSON", "XML",
        "Access", "Agent", "App", "Build", "Code", "Edit", "Error",
        "File", "Fix", "Get", "Help", "Let", "New", "Run", "Set",
        "Test", "Tool", "Use", "View", "Work", "Read", "Write",
        "Oh", "Ah", "Um", "Uh", "Yep", "Nope", "Sure", "Maybe",
        "Today", "Tomorrow", "Yesterday", "Monday", "Tuesday",
        "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    ]

    private func extractWithNLTagger(_ text: String) -> TaggerResult {
        var entities: Set<String> = []
        var sentimentSum: Double = 0
        var sentimentCount = 0

        // Entity extraction
        let entityTagger = NLTagger(tagSchemes: [.nameType])
        entityTagger.string = text
        entityTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType) { tag, range in
            if let tag, tag == .personalName || tag == .organizationName || tag == .placeName {
                let entity = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if entity.count >= 2,
                   entity.first?.isUppercase == true,
                   !Self.entityBlocklist.contains(entity) {
                    entities.insert(entity)
                }
            }
            return true
        }

        // Sentiment scoring — per-sentence
        let sentimentTagger = NLTagger(tagSchemes: [.sentimentScore])
        sentimentTagger.string = text
        sentimentTagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .sentimentScore) { tag, _ in
            if let tag, let score = Double(tag.rawValue) {
                sentimentSum += score
                sentimentCount += 1
            }
            return true
        }

        let avgSentiment = sentimentCount > 0 ? sentimentSum / Double(sentimentCount) : 0

        return TaggerResult(
            entities: Array(entities).sorted(),
            sentiment: avgSentiment
        )
    }

    // MARK: - Haiku Track: claude -p Subprocess

    /// Spawns `claude -p` as a subprocess and returns stdout
    private func claudeP(prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["claude", "-p", prompt, "--model", "claude-haiku-4-5", "--max-turns", "1", "--no-tools"]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        debugLog("claudeP: launching subprocess")

        try process.run()

        // 240-second timeout
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: 240_000_000_000)
            if process.isRunning {
                process.terminate()
            }
        }

        process.waitUntilExit()
        timeoutTask.cancel()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        if let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.isEmpty {
            debugLog("claudeP stderr: \(stderrStr)")
        }

        guard process.terminationStatus == 0 else {
            let errMsg = String(data: stderrData, encoding: .utf8) ?? "unknown error"
            throw NSError(domain: "MemoryDaemon", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "claude -p exited with status \(process.terminationStatus): \(errMsg)"])
        }

        let result = String(data: stdoutData, encoding: .utf8) ?? ""
        debugLog("claudeP: got \(result.count) chars")
        return result
    }

    // MARK: - Haiku Track: Session Notes

    func generateSessionNote(transcriptPath: String, sessionId: String) async {
        guard !notedSessionIds.contains(sessionId) else { return }

        guard let transcript = try? String(contentsOfFile: transcriptPath, encoding: .utf8),
              transcript.count > 300 else {
            debugLog("generateSessionNote: transcript too short or missing at \(transcriptPath)")
            return
        }

        // Truncate to ~60K chars to stay within context
        let truncated = transcript.count > 60_000 ? String(transcript.suffix(60_000)) : transcript

        let prompt = """
        You are a memory system. Read this conversation transcript and write a session note.

        Format:
        ## Summary
        (2-3 sentences)

        ## Decisions
        - (bullet points of choices made)

        ## Technical Context
        - (files edited, commands run, architecture discussed)

        ## Open Threads
        - (anything unresolved or in-progress)

        ## Mood
        (1 sentence on emotional tone)

        Rules:
        - Third person ("Matt did X")
        - Concise bullets
        - Include personal AND technical context equally
        - If in doubt, include it

        Transcript:
        \(truncated)
        """

        do {
            let note = try await claudeP(prompt: prompt)

            // Extract simple topic tags from the note
            let topicTags = extractTopicTags(from: note)

            let sessionNote = SessionNote(
                ts: Date(),
                sessionId: sessionId,
                note: note,
                topicTags: topicTags
            )

            // Append to notes.jsonl
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let jsonData = try encoder.encode(sessionNote)
            let jsonLine = String(data: jsonData, encoding: .utf8)! + "\n"

            if let handle = FileHandle(forWritingAtPath: Self.notesPath) {
                handle.seekToEndOfFile()
                handle.write(jsonLine.data(using: .utf8)!)
                handle.closeFile()
            } else {
                try jsonLine.write(toFile: Self.notesPath, atomically: true, encoding: .utf8)
            }

            notedSessionIds.insert(sessionId)
            debugLog("generateSessionNote: wrote note for session \(sessionId) (\(note.count) chars, tags: \(topicTags))")
            logger.info("Session note generated for \(sessionId)")
        } catch {
            debugLog("generateSessionNote failed: \(error)")
            logger.error("Session note generation failed: \(error.localizedDescription)")
        }
    }

    /// Extract topic tags from a session note by looking at headings and key terms
    private func extractTopicTags(from note: String) -> [String] {
        var tags: [String] = []
        let lines = note.components(separatedBy: "\n")
        for line in lines {
            // Look for file names mentioned
            if line.contains(".swift") || line.contains(".md") || line.contains(".json") || line.contains(".ts") {
                let words = line.components(separatedBy: .whitespaces)
                for word in words {
                    let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                    if cleaned.contains(".") && (cleaned.hasSuffix(".swift") || cleaned.hasSuffix(".md") || cleaned.hasSuffix(".json") || cleaned.hasSuffix(".ts")) {
                        tags.append(cleaned)
                    }
                }
            }
        }
        return Array(Set(tags)).sorted().prefix(10).map { $0 }
    }

    // MARK: - Haiku Track: Episodic.md Generation

    func generateEpisodic() async {
        status = "Updating episodic memory…"

        // Read notes from the last 5 days
        let notes = loadRecentNotes(days: 5)

        if notes.isEmpty {
            debugLog("generateEpisodic: no notes found, falling back to mechanical")
            // Fall back to mechanical episodic
            let calendar = Calendar.current
            let cutoff = calendar.date(byAdding: .day, value: -5, to: Date())!
            let recentEntries = entries.filter { $0.timestamp >= cutoff }
            if !recentEntries.isEmpty {
                renderMechanicalEpisodic(recentEntries)
            }
            lastRender = Date()
            status = nil
            return
        }

        // Concatenate notes (up to 60K chars)
        var notesContent = ""
        for note in notes {
            let dateStr = ISO8601DateFormatter().string(from: note.ts)
            let entry = "--- Session \(note.sessionId) at \(dateStr) ---\n\(note.note)\n\n"
            if notesContent.count + entry.count > 60_000 { break }
            notesContent += entry
        }

        let prompt = """
        Write a rolling 5-day summary from these session notes. This document orients a new Claude instance at session start.

        Sections:
        ## Active Focus
        (1-2 sentences on current work)

        ## Current State
        (bullets covering both personal and technical context)

        ## Last 5 Days
        (day-by-day, newest first, with key events)

        ## Recent Decisions
        (all choices made, technical and personal)

        ## Open Threads
        (CRITICAL: must be exhaustive — nothing gets dropped)

        ## Mood
        (how Matt has been feeling, with direct quotes if available)

        Rules:
        - Completeness over brevity
        - Personal context = technical context in importance
        - If unsure, INCLUDE IT
        - Max 4000 words

        Session notes:
        \(notesContent)
        """

        do {
            let episodic = try await claudeP(prompt: prompt)

            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
            let content = "# Episodic Memory\n\n*Generated by Familiar at \(dateStr)*\n\n\(episodic)"

            try content.write(toFile: Self.episodicPath, atomically: true, encoding: .utf8)
            debugLog("generateEpisodic: wrote episodic.md (\(content.count) chars)")
            lastRender = Date()
            status = nil
            logger.info("Episodic.md generated via Haiku (\(content.count) chars)")
        } catch {
            debugLog("generateEpisodic failed: \(error), falling back to mechanical")
            logger.error("Episodic generation failed: \(error.localizedDescription)")

            // Fall back to mechanical
            let calendar = Calendar.current
            let cutoff = calendar.date(byAdding: .day, value: -5, to: Date())!
            let recentEntries = entries.filter { $0.timestamp >= cutoff }
            if !recentEntries.isEmpty {
                renderMechanicalEpisodic(recentEntries)
            }
            lastRender = Date()
            status = nil
        }
    }

    /// Load recent session notes from notes.jsonl
    private func loadRecentNotes(days: Int) -> [SessionNote] {
        guard let data = try? String(contentsOfFile: Self.notesPath, encoding: .utf8) else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var notes: [SessionNote] = []
        for line in data.components(separatedBy: "\n") where !line.isEmpty {
            if let lineData = line.data(using: .utf8),
               let note = try? decoder.decode(SessionNote.self, from: lineData),
               note.ts >= cutoff {
                notes.append(note)
            }
        }
        return notes.sorted { $0.ts > $1.ts }
    }

    // MARK: - Mechanical Episodic (Fallback)

    private func renderMechanicalEpisodic(_ entries: [MemoryEntry]) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        // Group by day
        let grouped = Dictionary(grouping: entries) { entry in
            dateFormatter.string(from: entry.timestamp)
        }

        let today = dateFormatter.string(from: Date())
        let yesterday = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        var output = "# Episodic Memory\n\nRolling 5-day log. Auto-generated by Familiar (mechanical fallback).\n"

        for day in grouped.keys.sorted().reversed() {
            let label: String
            if day == today { label = "Today (\(day))" }
            else if day == yesterday { label = "Yesterday (\(day))" }
            else { label = day }

            let dayEntries = grouped[day]!.sorted { $0.timestamp > $1.timestamp }

            let isRecent = day == today || day == yesterday

            output += "\n## \(label)\n"

            for entry in dayEntries {
                let time = timeFormatter.string(from: entry.timestamp)
                output += "\n### \(entry.topic) (\(time))\n"

                if isRecent {
                    for outcome in entry.outcomes {
                        output += "- \(outcome)\n"
                    }
                    if !entry.entities.isEmpty {
                        output += "- *Entities: \(entry.entities.joined(separator: ", "))*\n"
                    }
                } else {
                    if let first = entry.outcomes.first {
                        output += "- \(first)\n"
                    }
                    if entry.outcomes.count > 1 {
                        output += "- *(\(entry.outcomes.count - 1) more)*\n"
                    }
                }
            }
        }

        do {
            try output.write(toFile: Self.episodicPath, atomically: true, encoding: .utf8)
            debugLog("Wrote mechanical episodic.md (\(output.count) chars)")
        } catch {
            logger.error("Failed to write episodic.md: \(error.localizedDescription)")
        }
    }

    // MARK: - L3: Mechanical Graduation → semantic.md

    func runGraduation() async {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        status = "Checking semantic graduation…"

        // Group entries by topic
        let byTopic = Dictionary(grouping: entries, by: { $0.topic })

        var graduates: [(topic: String, sessionCount: Int, daySpan: Int, entities: Set<String>, outcomes: [String])] = []

        for (topic, topicEntries) in byTopic {
            let sessionCount = topicEntries.count

            let days = Set(topicEntries.map { dateFormatter.string(from: $0.timestamp) })
            let daySpan = days.count

            if sessionCount >= graduationThreshold && daySpan >= graduationDaySpan {
                let allEntities = Set(topicEntries.flatMap { $0.entities })
                let recentOutcomes = topicEntries
                    .sorted { $0.timestamp > $1.timestamp }
                    .prefix(3)
                    .flatMap { $0.outcomes }

                graduates.append((
                    topic: topic,
                    sessionCount: sessionCount,
                    daySpan: daySpan,
                    entities: allEntities,
                    outcomes: Array(recentOutcomes.prefix(3))
                ))
            }
        }

        guard !graduates.isEmpty else {
            logger.info("L3: Nothing to graduate")
            status = nil
            lastGraduation = Date()
            return
        }

        // Read existing semantic to deduplicate
        let existingSemantic = (try? String(contentsOfFile: Self.semanticPath, encoding: .utf8)) ?? ""

        var newEntries: [String] = []
        for grad in graduates {
            if existingSemantic.localizedCaseInsensitiveContains(grad.topic) {
                continue
            }
            var entry = "### \(grad.topic)\n"
            entry += "*Appeared in \(grad.sessionCount) sessions over \(grad.daySpan) days*\n"
            for outcome in grad.outcomes {
                entry += "- \(outcome)\n"
            }
            if !grad.entities.isEmpty {
                entry += "- *Related: \(grad.entities.sorted().joined(separator: ", "))*\n"
            }
            newEntries.append(entry)
        }

        guard !newEntries.isEmpty else {
            logger.info("L3: All graduates already in semantic.md")
            status = nil
            lastGraduation = Date()
            return
        }

        let appendText = "\n" + newEntries.joined(separator: "\n")

        if FileManager.default.fileExists(atPath: Self.semanticPath) {
            if let handle = FileHandle(forWritingAtPath: Self.semanticPath) {
                handle.seekToEndOfFile()
                handle.write(appendText.data(using: .utf8)!)
                handle.closeFile()
            }
        } else {
            let content = "# Semantic Memory\n\nStable facts graduated from episodic memory by frequency and recency.\n" + appendText
            try? content.write(toFile: Self.semanticPath, atomically: true, encoding: .utf8)
        }

        lastGraduation = Date()
        status = nil
        logger.info("L3: Graduated \(newEntries.count) topics to semantic.md")
    }

    // MARK: - Persistence

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: Self.entriesPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: Self.entriesPath)),
              let decoded = try? JSONDecoder.withISO8601.decode([MemoryEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded

        // Expire entries older than 30 days (keep them for graduation window)
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        entries = entries.filter { $0.timestamp >= cutoff }

        debugLog("Loaded \(entries.count) entries from disk")
    }

    private func saveEntries() {
        do {
            let data = try JSONEncoder.withISO8601.encode(entries)
            try data.write(to: URL(fileURLWithPath: Self.entriesPath))
        } catch {
            logger.error("Failed to save entries: \(error.localizedDescription)")
        }
    }

    // MARK: - Manual Triggers

    func forceExtraction() {
        triggerExtraction()
    }

    func forceRender() {
        Task { await generateEpisodic() }
    }

    func forceGraduation() {
        Task { await runGraduation() }
    }

    func forceSessionNote() {
        guard let path = activeTranscriptPath, let sid = activeSessionId else { return }
        Task { await generateSessionNote(transcriptPath: path, sessionId: sid) }
    }

    // MARK: - Backfill from Transcripts

    private(set) var backfillProgress: String?

    static let transcriptsDir: String = {
        NSHomeDirectory() + "/.familiar/transcripts"
    }()

    /// Read all transcripts from the last N days, chunk them, and run L1 extraction on each chunk.
    /// Call once to bootstrap the entries.json store.
    func backfill(days: Int = 5) {
        Task { await runBackfill(days: days) }
    }

    private func runBackfill(days: Int) async {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        guard let files = try? fm.contentsOfDirectory(atPath: Self.transcriptsDir) else {
            debugLog("Backfill: no transcripts directory")
            return
        }

        let mdFiles = files.filter { $0.hasSuffix(".md") }
            .map { Self.transcriptsDir + "/" + $0 }
            .filter { path in
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mod = attrs[.modificationDate] as? Date else { return false }
                return mod >= cutoff
            }
            .sorted()

        debugLog("Backfill: found \(mdFiles.count) transcripts from last \(days) days")
        backfillProgress = "Found \(mdFiles.count) transcripts…"

        // Clear existing entries to prevent duplicates on re-run
        entries.removeAll()
        var totalEntries = 0

        for (i, path) in mdFiles.enumerated() {
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let filename = (path as NSString).lastPathComponent

            backfillProgress = "Processing \(i + 1)/\(mdFiles.count): \(filename)"
            debugLog("Backfill: processing \(filename) (\(content.count) chars)")

            // Skip tiny transcripts (just a header, no real conversation)
            guard content.count > 300 else {
                debugLog("Backfill: skipping \(filename) — too short")
                continue
            }

            // Parse start date from transcript header, fall back to file mod date
            let fileDate: Date
            if let startedStr = extractHeaderValue(content, key: "Started"),
               let parsed = Self.transcriptDateFormatter.date(from: startedStr) {
                fileDate = parsed
            } else if let attrs = try? fm.attributesOfItem(atPath: path),
                      let mod = attrs[.modificationDate] as? Date {
                fileDate = mod
            } else {
                fileDate = Date()
            }

            let sessionId = filename.replacingOccurrences(of: ".md", with: "")

            // Mechanical extraction — no LLM, just parsing + NLTagger
            let extracted = extractMechanically(from: content)
            let userText = extractUserMessages(from: content)
            let taggerResult = extractWithNLTagger(userText)

            let entry = MemoryEntry(
                id: UUID().uuidString,
                timestamp: fileDate,
                sessionId: sessionId,
                topic: extracted.topic,
                outcomes: extracted.outcomes,
                entities: (taggerResult.entities + extracted.mentionedFiles).uniqued(),
                sentiment: taggerResult.sentiment
            )
            entries.append(entry)
            totalEntries += 1

            debugLog("Backfill: \(filename) → topic='\(extracted.topic)' outcomes=\(extracted.outcomes.count) entities=\(entry.entities.count)")
        }

        saveEntries()
        debugLog("Backfill complete: \(totalEntries) entries from \(mdFiles.count) transcripts")
        backfillProgress = "Done — \(totalEntries) entries extracted"

        // Immediately generate episodic.md
        await generateEpisodic()
        backfillProgress = nil

        logger.info("Backfill complete: \(totalEntries) entries, episodic.md rendered")
    }

    // MARK: - Mechanical Extraction (no LLM)

    struct MechanicalExtraction {
        var topic: String
        var outcomes: [String]
        var mentionedFiles: [String]
    }

    /// Extract topic, outcomes, and file references from transcript using regex and structure.
    private func extractMechanically(from content: String) -> MechanicalExtraction {
        // Extract working directory from header as project context
        let directory = extractHeaderValue(content, key: "Directory")
        let project = directory.flatMap { dir -> String? in
            if dir.contains("/Projects/") {
                return dir.components(separatedBy: "/Projects/").last?.components(separatedBy: "/").first
            }
            return nil
        }

        // Extract tool activity summary for topic derivation
        let toolLines = extractToolLines(from: content)
        let editedFiles = toolLines.filter { $0.contains("edit ") || $0.contains("Edit") }
            .compactMap { extractFilePath(from: $0) }
            .map { ($0 as NSString).lastPathComponent }

        let bashCommands = toolLines.filter { $0.contains("Bash") }
        let searchTerms = toolLines.filter { $0.contains("Grep") || $0.contains("search:") }
            .compactMap { line -> String? in
                if let patternRange = line.range(of: "pattern: \"") {
                    let after = line[patternRange.upperBound...]
                    if let endQuote = after.firstIndex(of: "\"") {
                        return String(after[..<endQuote])
                    }
                }
                if let patternRange = line.range(of: "pattern: ") {
                    let after = String(line[patternRange.upperBound...]).prefix(40)
                    return String(after).trimmingCharacters(in: .whitespaces)
                }
                return nil
            }
            .filter { !$0.isEmpty && !$0.hasPrefix("Tool:") }

        // Build topic
        let firstUserMsg = extractFirstUserMessage(from: content)
        let topic: String
        if let proj = project, !editedFiles.isEmpty {
            topic = "\(proj): \(editedFiles.prefix(2).joined(separator: ", "))"
        } else if let proj = project, !bashCommands.isEmpty {
            topic = "\(proj) session"
        } else if let msg = firstUserMsg, msg.count > 15 && msg.count < 80,
                  !Self.isGreeting(msg) {
            topic = msg
        } else if let proj = project {
            topic = proj
        } else if let msg = firstUserMsg, msg.count > 5 && msg.count < 80 {
            topic = msg
        } else {
            topic = "Session"
        }

        // Build outcomes from tool activity
        var outcomes: [String] = []
        if !editedFiles.isEmpty {
            let uniqueFiles = Array(Set(editedFiles)).prefix(4)
            outcomes.append("Edited: \(uniqueFiles.joined(separator: ", "))")
        }
        if !bashCommands.isEmpty {
            outcomes.append("Ran \(bashCommands.count) command\(bashCommands.count == 1 ? "" : "s")")
        }
        if !searchTerms.isEmpty {
            outcomes.append("Searched: \(searchTerms.prefix(2).joined(separator: ", "))")
        }

        // Extract file paths mentioned anywhere
        let mentionedFiles = extractAllFilePaths(from: content)
            .map { ($0 as NSString).lastPathComponent }
            .filter { $0.hasSuffix(".swift") || $0.hasSuffix(".md") || $0.hasSuffix(".json") }

        return MechanicalExtraction(
            topic: topic,
            outcomes: outcomes,
            mentionedFiles: Array(Set(mentionedFiles)).sorted()
        )
    }

    /// Check if a message is just a greeting/filler, not a topic-worthy statement
    private static func isGreeting(_ msg: String) -> Bool {
        let lower = msg.lowercased().trimmingCharacters(in: .punctuationCharacters)
        let greetings: Set<String> = [
            "hello", "hey", "hi", "yo", "sup", "morning", "evening",
            "pretty good", "good", "fine", "ok", "okay", "sure",
            "yes", "yeah", "yep", "no", "nah", "nope",
            "thanks", "thank you", "cheers", "done",
        ]
        return greetings.contains(lower) || lower.count < 5
    }

    private func extractHeaderValue(_ content: String, key: String) -> String? {
        let pattern = "\\*\\*\(key):\\*\\*\\s*(.*)"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else { return nil }
        return String(content[range]).trimmingCharacters(in: .whitespaces)
    }

    private func extractToolLines(from content: String) -> [String] {
        content.components(separatedBy: "\n")
            .filter { $0.hasPrefix("- **") }
    }

    private func extractFirstUserMessage(from content: String) -> String? {
        let sections = content.components(separatedBy: "\n### User\n")
        guard sections.count > 1 else { return nil }
        let msg = sections[1].components(separatedBy: "\n").first ?? ""
        return msg.trimmingCharacters(in: .whitespaces)
    }

    private func extractUserMessages(from content: String) -> String {
        let sections = content.components(separatedBy: "\n### User\n")
        guard sections.count > 1 else { return "" }
        return sections.dropFirst().map { section in
            let lines = section.components(separatedBy: "\n")
            return lines.prefix(while: { !$0.hasPrefix("### ") && !$0.hasPrefix("---") && !$0.hasPrefix("> *") && !$0.hasPrefix("<details>") })
                .joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private func extractFilePath(from line: String) -> String? {
        let pattern = "/[\\w/.-]+\\.[a-z]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        return String(line[range])
    }

    private func extractAllFilePaths(from content: String) -> [String] {
        let pattern = "/Users/[\\w/.-]+\\.[a-z]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
        return matches.compactMap { match in
            guard let range = Range(match.range, in: content) else { return nil }
            return String(content[range])
        }
    }

    // MARK: - Debug

    private func debugLog(_ message: String) {
        let path = Self.dataDir + "/debug.log"
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - JSON Coding Helpers

private extension JSONEncoder {
    static let withISO8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

private extension JSONDecoder {
    static let withISO8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
