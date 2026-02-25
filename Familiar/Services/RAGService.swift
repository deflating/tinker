import Foundation
import NaturalLanguage
import SQLite3
import os.log

@Observable
final class RAGService: @unchecked Sendable {

    private let logger = Logger(subsystem: "app.tinker", category: "RAG")

    // MARK: - Types

    enum SourceType: String, Codable, CaseIterable {
        case claudeAI = "claude_ai"
        case claudeCode = "claude_code"
        case file = "file"

        var label: String {
            switch self {
            case .claudeAI: return "Claude.ai"
            case .claudeCode: return "Claude Code"
            case .file: return "File"
            }
        }
    }

    struct DocumentEntry: Identifiable {
        let id: String
        let filename: String
        let importDate: Date
        let chunkCount: Int
        let sourceType: SourceType
        var sourcePath: String?
        var sourceModDate: Date?
    }

    struct SearchResult: Identifiable {
        let id: String
        let text: String
        let filename: String
        let sourceType: SourceType
        let score: Double
    }

    struct ImportProgress {
        let total: Int
        var completed: Int
        var currentItem: String
        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
    }

    // MARK: - State

    private(set) var documentIndex: [DocumentEntry] = []
    private(set) var isLoading = false
    private(set) var importProgress: ImportProgress?

    // MARK: - Embedding

    private let embeddingService = EmbeddingService()
    let vectorIndex = VectorIndex()

    // MARK: - Storage

    private var db: OpaquePointer?

    private static let knowledgeDir: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".familiar/knowledge", isDirectory: true)
    }()

    private static let dbPath: String = {
        knowledgeDir.appendingPathComponent("knowledge.db").path
    }()

    // MARK: - Init

    init() {
        try? FileManager.default.createDirectory(at: Self.knowledgeDir, withIntermediateDirectories: true)
        openDatabase()
        Task.detached { [weak self] in
            await self?.loadIndex()
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Database Setup

    private func openDatabase() {
        guard sqlite3_open_v2(Self.dbPath, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            logger.error("Failed to open knowledge database")
            return
        }

        // WAL mode for better concurrent reads
        exec("PRAGMA journal_mode=WAL")

        exec("""
            CREATE TABLE IF NOT EXISTS documents (
                id TEXT PRIMARY KEY,
                filename TEXT NOT NULL,
                import_date REAL NOT NULL,
                source_type TEXT NOT NULL DEFAULT 'file',
                source_path TEXT,
                source_mod_date REAL
            )
        """)

        exec("""
            CREATE TABLE IF NOT EXISTS chunks (
                id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
                text TEXT NOT NULL
            )
        """)

        exec("CREATE INDEX IF NOT EXISTS idx_chunks_document_id ON chunks(document_id)")

        // FTS5 virtual table
        exec("""
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
                text,
                content=chunks,
                content_rowid=rowid
            )
        """)

        // Triggers to keep FTS5 in sync
        exec("""
            CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
                INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
            END
        """)
        exec("""
            CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
                INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
            END
        """)

        // Enable foreign keys for CASCADE deletes
        exec("PRAGMA foreign_keys = ON")

        // Add surrogate and embedding columns (ALTER ADD COLUMN errors if exists — exec swallows it)
        exec("ALTER TABLE chunks ADD COLUMN surrogate_full TEXT")
        exec("ALTER TABLE chunks ADD COLUMN surrogate_gist TEXT")
        exec("ALTER TABLE chunks ADD COLUMN surrogate_micro TEXT")
        exec("ALTER TABLE chunks ADD COLUMN embedding BLOB")
        exec("ALTER TABLE chunks ADD COLUMN vector_key INTEGER")
        exec("CREATE INDEX IF NOT EXISTS idx_chunks_vector_key ON chunks(vector_key)")
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            logger.error("SQL error: \(msg)")
            sqlite3_free(err)
        }
    }

    // MARK: - Load Index

    private func loadIndex() async {
        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        guard let db else { return }

        let sql = """
            SELECT d.id, d.filename, d.import_date, d.source_type, d.source_path, d.source_mod_date,
                   (SELECT COUNT(*) FROM chunks c WHERE c.document_id = d.id) as chunk_count
            FROM documents d
            ORDER BY d.import_date DESC
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        var entries: [DocumentEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let filename = String(cString: sqlite3_column_text(stmt, 1))
            let importDate = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 2))
            let sourceTypeRaw = String(cString: sqlite3_column_text(stmt, 3))
            let sourceType = SourceType(rawValue: sourceTypeRaw) ?? .file
            let sourcePath = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
            let sourceModDate = sqlite3_column_type(stmt, 5) != SQLITE_NULL
                ? Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 5))
                : nil
            let chunkCount = Int(sqlite3_column_int(stmt, 6))

            entries.append(DocumentEntry(
                id: id, filename: filename, importDate: importDate,
                chunkCount: chunkCount, sourceType: sourceType,
                sourcePath: sourcePath, sourceModDate: sourceModDate
            ))
        }

        await MainActor.run { documentIndex = entries }
        logger.info("Indexed \(entries.count) knowledge documents from SQLite")
    }

    // MARK: - Import File

    func importFile(url: URL) async {
        let filename = url.lastPathComponent
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            logger.error("Could not read file: \(url.path)")
            return
        }

        let paragraphs = chunkText(content)
        guard !paragraphs.isEmpty else { return }

        let docId = UUID().uuidString
        let now = Date()

        insertDocument(id: docId, filename: filename, importDate: now, sourceType: .file)
        insertChunks(paragraphs, documentId: docId)

        let entry = DocumentEntry(id: docId, filename: filename, importDate: now, chunkCount: paragraphs.count, sourceType: .file)
        await MainActor.run { documentIndex.insert(entry, at: 0) }
        logger.info("Imported \(filename) with \(paragraphs.count) chunks")
    }

    // MARK: - Import Claude.ai Export

    func importClaudeAIExport(url: URL) async -> Int {
        guard let data = try? Data(contentsOf: url) else {
            logger.error("Could not read Claude.ai export: \(url.path)")
            return 0
        }

        struct ClaudeAIMessage: Decodable {
            let text: String
            let sender: String
        }
        struct ClaudeAIConversation: Decodable {
            let uuid: String
            let name: String
            let chat_messages: [ClaudeAIMessage]
        }

        guard let conversations = try? JSONDecoder().decode([ClaudeAIConversation].self, from: data) else {
            logger.error("Could not parse Claude.ai export JSON")
            return 0
        }

        let eligible = conversations.filter { $0.chat_messages.filter { $0.sender == "human" }.count >= 5 }
        await MainActor.run {
            importProgress = ImportProgress(total: eligible.count, completed: 0, currentItem: "Starting…")
        }

        var imported = 0
        for conv in eligible {
            await MainActor.run { importProgress?.currentItem = conv.name }

            let transcript = conv.chat_messages.map { msg in
                let role = msg.sender == "human" ? "Human" : "Assistant"
                return "[\(role)]\n\(msg.text)"
            }.joined(separator: "\n\n")

            let paragraphs = chunkText(transcript)
            guard !paragraphs.isEmpty else {
                await MainActor.run { importProgress?.completed += 1 }
                continue
            }

            let docId = UUID().uuidString
            let now = Date()
            let displayName = "claude.ai: \(conv.name)"

            insertDocument(id: docId, filename: displayName, importDate: now, sourceType: .claudeAI)
            insertChunks(paragraphs, documentId: docId)

            imported += 1
            let entry = DocumentEntry(id: docId, filename: displayName, importDate: now, chunkCount: paragraphs.count, sourceType: .claudeAI)
            await MainActor.run {
                documentIndex.insert(entry, at: 0)
                importProgress?.completed += 1
            }
        }
        await MainActor.run { importProgress = nil }
        logger.info("Imported \(imported) conversations from Claude.ai export")
        return imported
    }

    // MARK: - Import Claude Code Transcripts

    func importClaudeCodeTranscripts(directoryURL: URL) async -> Int {
        let fm = FileManager.default

        var jsonlFiles: [URL] = []
        if let enumerator = fm.enumerator(at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "jsonl" {
                    jsonlFiles.append(fileURL)
                }
            }
        }

        guard !jsonlFiles.isEmpty else {
            logger.error("No .jsonl files found under \(directoryURL.path)")
            return 0
        }

        let existingIndex: [String: Date] = Dictionary(
            uniqueKeysWithValues: documentIndex.compactMap { entry in
                guard let path = entry.sourcePath, let modDate = entry.sourceModDate else { return nil }
                return (path, modDate)
            }
        )

        let filesToProcess = jsonlFiles.filter { url in
            let path = url.path
            guard let existingModDate = existingIndex[path] else { return true }
            let currentModDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return currentModDate != existingModDate
        }

        guard !filesToProcess.isEmpty else {
            logger.info("All \(jsonlFiles.count) transcripts already indexed")
            return 0
        }

        await MainActor.run {
            importProgress = ImportProgress(total: filesToProcess.count, completed: 0, currentItem: "Scanning \(jsonlFiles.count) files, \(filesToProcess.count) new…")
        }

        var imported = 0
        for file in filesToProcess {
            let projectDir = file.deletingLastPathComponent().lastPathComponent
            let sessionId = file.deletingPathExtension().lastPathComponent
            let displayName = "claude-code/\(projectDir)/\(sessionId)"

            await MainActor.run { importProgress?.currentItem = displayName }

            guard let content = try? String(contentsOf: file, encoding: .utf8) else {
                await MainActor.run { importProgress?.completed += 1 }
                continue
            }

            let messages = parseClaudeCodeJSONL(content)
            guard messages.filter({ $0.role == "Human" }).count >= 5 else {
                await MainActor.run { importProgress?.completed += 1 }
                continue
            }

            let transcript = messages.map { "[\($0.role)]\n\($0.text)" }.joined(separator: "\n\n")
            let paragraphs = chunkText(transcript)
            guard !paragraphs.isEmpty else {
                await MainActor.run { importProgress?.completed += 1 }
                continue
            }

            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

            // Remove old version if re-importing
            if let oldEntry = documentIndex.first(where: { $0.sourcePath == file.path }) {
                removeDocument(id: oldEntry.id)
            }

            let docId = UUID().uuidString
            let now = Date()

            insertDocument(id: docId, filename: displayName, importDate: now, sourceType: .claudeCode,
                          sourcePath: file.path, sourceModDate: modDate)
            insertChunks(paragraphs, documentId: docId)

            imported += 1
            let entry = DocumentEntry(id: docId, filename: displayName, importDate: now, chunkCount: paragraphs.count,
                                      sourceType: .claudeCode, sourcePath: file.path, sourceModDate: modDate)
            await MainActor.run {
                documentIndex.insert(entry, at: 0)
                importProgress?.completed += 1
            }
        }
        await MainActor.run { importProgress = nil }
        logger.info("Imported \(imported) Claude Code transcripts")
        return imported
    }

    // MARK: - JSONL Parser

    private func parseClaudeCodeJSONL(_ content: String) -> [(role: String, text: String)] {
        var messages: [(role: String, text: String)] = []
        for line in content.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            if type == "user", let msg = obj["message"] as? [String: Any] {
                if let text = msg["content"] as? String {
                    messages.append(("Human", text))
                }
            } else if type == "assistant", let msg = obj["message"] as? [String: Any],
                      let contentArr = msg["content"] as? [[String: Any]] {
                let textParts = contentArr.compactMap { block -> String? in
                    guard let blockType = block["type"] as? String, blockType == "text",
                          let text = block["text"] as? String else { return nil }
                    return text
                }
                if !textParts.isEmpty {
                    messages.append(("Assistant", textParts.joined(separator: "\n")))
                }
            }
        }
        return messages
    }

    // MARK: - SQL Helpers

    private func insertDocument(id: String, filename: String, importDate: Date, sourceType: SourceType,
                                sourcePath: String? = nil, sourceModDate: Date? = nil) {
        guard let db else { return }
        let sql = "INSERT INTO documents (id, filename, import_date, source_type, source_path, source_mod_date) VALUES (?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (filename as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 3, importDate.timeIntervalSinceReferenceDate)
        sqlite3_bind_text(stmt, 4, (sourceType.rawValue as NSString).utf8String, -1, nil)
        if let sourcePath {
            sqlite3_bind_text(stmt, 5, (sourcePath as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let sourceModDate {
            sqlite3_bind_double(stmt, 6, sourceModDate.timeIntervalSinceReferenceDate)
        } else {
            sqlite3_bind_null(stmt, 6)
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            logger.error("Failed to insert document: \(id)")
        }
    }

    private func insertChunks(_ texts: [String], documentId: String) {
        guard let db else { return }

        exec("BEGIN TRANSACTION")
        let sql = "INSERT INTO chunks (id, document_id, text) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            exec("ROLLBACK")
            return
        }
        defer { sqlite3_finalize(stmt) }

        for text in texts {
            sqlite3_reset(stmt)
            let id = UUID().uuidString
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 2, (documentId as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 3, (text as NSString).utf8String, -1, nil)

            if sqlite3_step(stmt) != SQLITE_DONE {
                logger.error("Failed to insert chunk")
            }
        }

        exec("COMMIT")
    }

    // MARK: - Remove

    func removeDocument(id: String) {
        guard let db else { return }

        // Delete chunks first (triggers FTS cleanup), then document
        let chunkSql = "DELETE FROM chunks WHERE document_id = ?"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, chunkSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        let docSql = "DELETE FROM documents WHERE id = ?"
        if sqlite3_prepare_v2(db, docSql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        documentIndex.removeAll { $0.id == id }
    }

    // MARK: - Search (FTS5 keyword search)

    func search(query: String, topK: Int = 10) -> [SearchResult] {
        guard let db else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Sanitize query for FTS5: wrap each word in quotes to avoid syntax errors
        let ftsQuery = trimmed.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }
            .joined(separator: " ")

        guard !ftsQuery.isEmpty else { return [] }

        let sql = """
            SELECT c.id, c.text, d.filename, d.source_type, chunks_fts.rank
            FROM chunks_fts
            JOIN chunks c ON c.rowid = chunks_fts.rowid
            JOIN documents d ON c.document_id = d.id
            WHERE chunks_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(topK))

        var results: [SearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let chunkId = String(cString: sqlite3_column_text(stmt, 0))
            let text = String(cString: sqlite3_column_text(stmt, 1))
            let filename = String(cString: sqlite3_column_text(stmt, 2))
            let sourceTypeRaw = String(cString: sqlite3_column_text(stmt, 3))
            let sourceType = SourceType(rawValue: sourceTypeRaw) ?? .file
            let rank = sqlite3_column_double(stmt, 4)

            results.append(SearchResult(
                id: chunkId, text: text, filename: filename,
                sourceType: sourceType, score: -rank  // FTS5 rank is negative; negate so higher = better
            ))
        }

        return results
    }

    // MARK: - Retrieve (RAG context injection — wraps search)

    func retrieve(query: String, topK: Int = 5) -> String {
        let results = embeddingService.isReady
            ? hybridSearch(query: query, topK: topK)
            : search(query: query, topK: topK)
        guard !results.isEmpty else { return "" }

        let contextBlock = results.map(\.text).joined(separator: "\n\n---\n\n")
        return """
        The user has a personal knowledge base. Relevant excerpts are provided below — use them to inform your response when applicable, but don't mention them unless asked.

        <context>
        \(contextBlock)
        </context>
        """
    }

    // MARK: - Chunking

    private func chunkText(_ text: String) -> [String] {
        let raw = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var buffer = ""

        for paragraph in raw {
            if paragraph.count > 800 {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                    buffer = ""
                }
                let sentences = splitSentences(paragraph)
                var sentBuf = ""
                for sentence in sentences {
                    if sentBuf.count + sentence.count > 600 {
                        if !sentBuf.isEmpty { chunks.append(sentBuf) }
                        sentBuf = sentence
                    } else {
                        sentBuf += (sentBuf.isEmpty ? "" : " ") + sentence
                    }
                }
                if !sentBuf.isEmpty { chunks.append(sentBuf) }
            } else if buffer.count + paragraph.count < 100 {
                buffer += (buffer.isEmpty ? "" : "\n\n") + paragraph
            } else {
                if !buffer.isEmpty {
                    chunks.append(buffer)
                }
                buffer = paragraph
            }
        }
        if !buffer.isEmpty { chunks.append(buffer) }

        return chunks
    }

    private func splitSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { sentences.append(s) }
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    // MARK: - Extractive Surrogates

    /// Score a sentence for information density.
    /// Higher score = more likely to contain useful content.
    private func scoreSentence(_ sentence: String) -> Double {
        var score: Double = 1.0

        // Digits suggest data, IDs, versions, measurements
        let digitCount = sentence.filter(\.isNumber).count
        if digitCount > 0 { score += min(Double(digitCount), 4.0) * 0.5 }

        // Colons suggest key:value, paths, labels
        let colonCount = sentence.filter({ $0 == ":" }).count
        if colonCount > 0 { score += min(Double(colonCount), 3.0) * 0.7 }

        // Code fences / backticks suggest code content
        if sentence.contains("```") || sentence.contains("`") { score += 3.0 }

        // Slashes suggest file paths or URLs
        let slashCount = sentence.filter({ $0 == "/" }).count
        if slashCount >= 2 { score += 1.5 }

        // Unique word ratio — diverse vocabulary = more informative
        let words = sentence.lowercased().split(separator: " ")
        if words.count >= 3 {
            let uniqueRatio = Double(Set(words).count) / Double(words.count)
            score += uniqueRatio * 2.0
        }

        // Penalize very short sentences (likely filler)
        if sentence.count < 20 { score *= 0.5 }

        // Penalize boilerplate markers
        let lower = sentence.lowercased()
        let boilerplate = ["thank you", "let me know", "hope this helps", "sure,", "of course", "i'll help", "here's"]
        for marker in boilerplate {
            if lower.hasPrefix(marker) { score *= 0.3; break }
        }

        return score
    }

    /// Compute word-overlap similarity between two sentences (Jaccard).
    private func jaccardSimilarity(_ a: String, _ b: String) -> Double {
        let setA = Set(a.lowercased().split(separator: " "))
        let setB = Set(b.lowercased().split(separator: " "))
        guard !setA.isEmpty || !setB.isEmpty else { return 0 }
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return Double(intersection) / Double(union)
    }

    /// Select top-k sentences using MMR (Maximal Marginal Relevance) for diversity.
    /// lambda controls relevance vs. diversity tradeoff (0.7 = favor relevance).
    private func mmrSelect(sentences: [String], scores: [Double], k: Int, lambda: Double = 0.7) -> [String] {
        guard !sentences.isEmpty else { return [] }
        let n = min(k, sentences.count)

        var selected: [Int] = []
        var remaining = Set(0..<sentences.count)

        // First pick: highest score
        if let best = remaining.max(by: { scores[$0] < scores[$1] }) {
            selected.append(best)
            remaining.remove(best)
        }

        // Subsequent picks: MMR
        while selected.count < n && !remaining.isEmpty {
            var bestIdx = -1
            var bestMMR = -Double.infinity

            for idx in remaining {
                let relevance = scores[idx]
                let maxSim = selected.map { jaccardSimilarity(sentences[idx], sentences[$0]) }.max() ?? 0
                let mmr = lambda * relevance - (1.0 - lambda) * maxSim
                if mmr > bestMMR {
                    bestMMR = mmr
                    bestIdx = idx
                }
            }

            if bestIdx >= 0 {
                selected.append(bestIdx)
                remaining.remove(bestIdx)
            } else {
                break
            }
        }

        // Return in original document order
        return selected.sorted().map { sentences[$0] }
    }

    /// Generate extractive surrogates for a chunk of text.
    /// Returns (full, gist, micro) — Full=8 sentences, Gist=3, Micro=1.
    func generateSurrogates(for text: String) -> (full: String, gist: String, micro: String) {
        let sentences = splitSentences(text)
        guard !sentences.isEmpty else { return (text, text, text) }

        let scores = sentences.map { scoreSentence($0) }

        let fullSentences = mmrSelect(sentences: sentences, scores: scores, k: 8)
        let gistSentences = mmrSelect(sentences: sentences, scores: scores, k: 3)
        let microSentences = mmrSelect(sentences: sentences, scores: scores, k: 1)

        return (
            full: fullSentences.joined(separator: " "),
            gist: gistSentences.joined(separator: " "),
            micro: microSentences.joined(separator: " ")
        )
    }

    // MARK: - Vector Search (HNSW via USearch)

    /// Search by embedding similarity using HNSW index. Returns top-k chunks.
    func vectorSearch(query: String, topK: Int = 10) -> [SearchResult] {
        guard let db else { return [] }
        guard vectorIndex.isReady, vectorIndex.count > 0 else { return [] }
        guard let queryEmbedding = embeddingService.embed(query) else { return [] }

        let (keys, distances) = vectorIndex.search(vector: queryEmbedding, count: topK)
        guard !keys.isEmpty else { return [] }

        // Look up chunk data by vector_key (indexed column)
        let placeholders = keys.map { _ in "?" }.joined(separator: ",")
        let sql = """
            SELECT c.id, c.text, c.vector_key, d.filename, d.source_type
            FROM chunks c
            JOIN documents d ON c.document_id = d.id
            WHERE c.vector_key IN (\(placeholders))
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, key) in keys.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), Int64(bitPattern: key))
        }

        // Build rank/distance lookup
        var keyRank: [UInt64: (rank: Int, distance: Float)] = [:]
        for (i, key) in keys.enumerated() {
            keyRank[key] = (i, distances[i])
        }

        var results: [(result: SearchResult, rank: Int)] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))
            let text = String(cString: sqlite3_column_text(stmt, 1))
            let vectorKey = UInt64(bitPattern: sqlite3_column_int64(stmt, 2))
            let filename = String(cString: sqlite3_column_text(stmt, 3))
            let sourceTypeRaw = String(cString: sqlite3_column_text(stmt, 4))
            let sourceType = SourceType(rawValue: sourceTypeRaw) ?? .file

            guard let info = keyRank[vectorKey] else { continue }
            let similarity = Double(1.0 - info.distance)
            results.append((SearchResult(id: id, text: text, filename: filename,
                                         sourceType: sourceType, score: similarity), info.rank))
        }

        results.sort { $0.rank < $1.rank }
        return results.map(\.result)
    }

    // MARK: - Hybrid Search (RRF Fusion)

    /// Reciprocal Rank Fusion: combine FTS5 keyword and vector search results.
    /// k = 60 is the standard RRF constant.
    func hybridSearch(query: String, topK: Int = 10, rrf_k: Double = 60) -> [SearchResult] {
        let keywordResults = search(query: query, topK: topK * 2)
        let vectorResults = vectorSearch(query: query, topK: topK * 2)

        // If no vector results, fall back to keyword only
        if vectorResults.isEmpty { return Array(keywordResults.prefix(topK)) }

        // RRF scoring
        var rrfScores: [String: Double] = [:]
        var resultMap: [String: SearchResult] = [:]

        for (rank, result) in keywordResults.enumerated() {
            rrfScores[result.id, default: 0] += 1.0 / (rrf_k + Double(rank + 1))
            resultMap[result.id] = result
        }

        for (rank, result) in vectorResults.enumerated() {
            rrfScores[result.id, default: 0] += 1.0 / (rrf_k + Double(rank + 1))
            resultMap[result.id] = result
        }

        // Sort by RRF score
        let sorted = rrfScores.sorted { $0.value > $1.value }
        return Array(sorted.prefix(topK)).compactMap { (id, score) in
            guard var result = resultMap[id] else { return nil }
            return SearchResult(id: result.id, text: result.text, filename: result.filename,
                                sourceType: result.sourceType, score: score)
        }
    }

    // MARK: - Backfill Embeddings

    /// Backfill embedding column using surrogate_gist (or raw text) for all chunks without embeddings.
    func backfillEmbeddings(batchSize: Int = 100, onProgress: ((Int, Int) -> Void)? = nil) async -> Int {
        guard let db, embeddingService.isReady else { return 0 }

        let countSql = "SELECT COUNT(*) FROM chunks WHERE embedding IS NULL"
        var countStmt: OpaquePointer?
        var total = 0
        if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }
        guard total > 0 else { return 0 }

        logger.info("Backfilling embeddings for \(total) chunks")

        let selectSql = "SELECT id, COALESCE(surrogate_gist, text) FROM chunks WHERE embedding IS NULL LIMIT ?"
        let updateSql = "UPDATE chunks SET embedding = ?, vector_key = ? WHERE id = ?"

        var processed = 0

        while processed < total {
            var batch: [(id: String, text: String)] = []

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(batchSize))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let text = String(cString: sqlite3_column_text(stmt, 1))
                    batch.append((id, text))
                }
                sqlite3_finalize(stmt)
            }

            guard !batch.isEmpty else { break }

            exec("BEGIN TRANSACTION")
            var updateStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK else {
                exec("ROLLBACK")
                break
            }

            for item in batch {
                guard let embedding = embeddingService.embed(item.text) else { continue }

                let key = VectorIndex.hashKey(item.id)

                // Add to HNSW index
                try? vectorIndex.add(key: key, vector: embedding)

                // Store embedding blob + vector key in SQLite
                let data = embedding.withUnsafeBufferPointer { Data(buffer: $0) }
                sqlite3_reset(updateStmt)
                data.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(updateStmt, 1, ptr.baseAddress, Int32(data.count), nil)
                }
                sqlite3_bind_int64(updateStmt, 2, Int64(bitPattern: key))
                sqlite3_bind_text(updateStmt, 3, (item.id as NSString).utf8String, -1, nil)
                sqlite3_step(updateStmt)
            }
            sqlite3_finalize(updateStmt)
            exec("COMMIT")

            processed += batch.count
            onProgress?(processed, total)
            if processed % 500 == 0 {
                logger.info("Embeddings: \(processed)/\(total)")
                vectorIndex.saveToDisk()
            }

            await Task.yield()
        }

        vectorIndex.saveToDisk()
        logger.info("Embedding backfill complete: \(processed) chunks")
        return processed
    }

    // MARK: - Build HNSW Index from existing embeddings

    /// Rebuild the HNSW index from embeddings already stored in SQLite.
    /// Also backfills vector_key column for chunks that have embeddings but no key.
    func buildVectorIndex(onProgress: ((Int, Int) -> Void)? = nil) async -> Int {
        guard let db else { return 0 }

        // Count chunks with embeddings
        let countSql = "SELECT COUNT(*) FROM chunks WHERE embedding IS NOT NULL"
        var countStmt: OpaquePointer?
        var total = 0
        if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }
        guard total > 0 else { return 0 }

        // If index already has roughly the right count, skip
        if vectorIndex.count >= total - 100 {
            logger.info("HNSW index already has \(self.vectorIndex.count)/\(total) vectors, skipping rebuild")
            return 0
        }

        logger.info("Building HNSW index from \(total) embeddings")
        try? vectorIndex.clear()
        try? vectorIndex.reserve(total)

        let selectSql = "SELECT id, embedding FROM chunks WHERE embedding IS NOT NULL"
        let updateKeySql = "UPDATE chunks SET vector_key = ? WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK else { return 0 }

        var keyStmt: OpaquePointer?
        let hasKeyColumn = sqlite3_prepare_v2(db, updateKeySql, -1, &keyStmt, nil) == SQLITE_OK

        var processed = 0
        exec("BEGIN TRANSACTION")

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = String(cString: sqlite3_column_text(stmt, 0))

            guard let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let blobLen = sqlite3_column_bytes(stmt, 1)
            let floatCount = Int(blobLen) / MemoryLayout<Float>.size
            guard floatCount == 384 else { continue }

            let embedding = Array(UnsafeBufferPointer(
                start: blobPtr.assumingMemoryBound(to: Float.self),
                count: floatCount
            ))

            let key = VectorIndex.hashKey(id)
            try? vectorIndex.add(key: key, vector: embedding)

            // Update vector_key in SQLite
            if hasKeyColumn, let ks = keyStmt {
                sqlite3_reset(ks)
                sqlite3_bind_int64(ks, 1, Int64(bitPattern: key))
                sqlite3_bind_text(ks, 2, (id as NSString).utf8String, -1, nil)
                sqlite3_step(ks)
            }

            processed += 1
            if processed % 1000 == 0 {
                onProgress?(processed, total)
            }
            if processed % 5000 == 0 {
                exec("COMMIT")
                exec("BEGIN TRANSACTION")
                logger.info("HNSW build: \(processed)/\(total)")
                await Task.yield()
            }
        }
        exec("COMMIT")
        sqlite3_finalize(stmt)
        if let ks = keyStmt { sqlite3_finalize(ks) }

        vectorIndex.saveToDisk()
        logger.info("HNSW index built: \(self.vectorIndex.count) vectors")
        onProgress?(processed, total)
        return processed
    }

    // MARK: - Backfill Surrogates

    /// Backfill surrogate columns for all chunks that don't have them yet.
    func backfillSurrogates(batchSize: Int = 500) async -> Int {
        guard let db else { return 0 }

        let countSql = "SELECT COUNT(*) FROM chunks WHERE surrogate_full IS NULL"
        var countStmt: OpaquePointer?
        var total = 0
        if sqlite3_prepare_v2(db, countSql, -1, &countStmt, nil) == SQLITE_OK {
            if sqlite3_step(countStmt) == SQLITE_ROW {
                total = Int(sqlite3_column_int(countStmt, 0))
            }
            sqlite3_finalize(countStmt)
        }
        guard total > 0 else { return 0 }

        logger.info("Backfilling surrogates for \(total) chunks")

        let selectSql = "SELECT id, text FROM chunks WHERE surrogate_full IS NULL LIMIT ?"
        let updateSql = "UPDATE chunks SET surrogate_full = ?, surrogate_gist = ?, surrogate_micro = ? WHERE id = ?"

        var processed = 0

        while processed < total {
            var batch: [(id: String, text: String)] = []

            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, selectSql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int(stmt, 1, Int32(batchSize))
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let id = String(cString: sqlite3_column_text(stmt, 0))
                    let text = String(cString: sqlite3_column_text(stmt, 1))
                    batch.append((id, text))
                }
                sqlite3_finalize(stmt)
            }

            guard !batch.isEmpty else { break }

            exec("BEGIN TRANSACTION")
            var updateStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateSql, -1, &updateStmt, nil) == SQLITE_OK else {
                exec("ROLLBACK")
                break
            }

            for item in batch {
                let (full, gist, micro) = generateSurrogates(for: item.text)
                sqlite3_reset(updateStmt)
                sqlite3_bind_text(updateStmt, 1, (full as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStmt, 2, (gist as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStmt, 3, (micro as NSString).utf8String, -1, nil)
                sqlite3_bind_text(updateStmt, 4, (item.id as NSString).utf8String, -1, nil)
                sqlite3_step(updateStmt)
            }
            sqlite3_finalize(updateStmt)
            exec("COMMIT")

            processed += batch.count
            logger.info("Surrogates: \(processed)/\(total)")

            // Yield to avoid blocking
            await Task.yield()
        }

        logger.info("Surrogate backfill complete: \(processed) chunks")
        return processed
    }
}
