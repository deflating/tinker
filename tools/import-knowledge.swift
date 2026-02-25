#!/usr/bin/env swift

// Standalone knowledge importer for Familiar
// Runs outside the app — parses Claude Code transcripts, chunks, stores in SQLite with FTS5.
//
// Usage:
//   swift tools/import-knowledge.swift                          # import from ~/.claude/projects
//   swift tools/import-knowledge.swift /path/to/projects        # custom path
//   swift tools/import-knowledge.swift --claude-ai export.json  # import claude.ai export
//   swift tools/import-knowledge.swift --file doc.md            # import arbitrary file

import Foundation
import NaturalLanguage
import SQLite3

// MARK: - Config

let knowledgeDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".familiar/knowledge")
let dbPath = knowledgeDir.appendingPathComponent("knowledge.db").path
let minimumHumanMessages = 5

// MARK: - Database

var db: OpaquePointer?

func openDB() {
    try? FileManager.default.createDirectory(at: knowledgeDir, withIntermediateDirectories: true)
    guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
        print("ERROR: Could not open database at \(dbPath)")
        exit(1)
    }
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
    exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            text, content=chunks, content_rowid=rowid
        )
    """)
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
    exec("PRAGMA foreign_keys = ON")
}

func exec(_ sql: String) {
    var err: UnsafeMutablePointer<CChar>?
    if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
        let msg = err.map { String(cString: $0) } ?? "unknown"
        print("SQL error: \(msg)")
        sqlite3_free(err)
    }
}

func existingSourcePaths() -> Set<String> {
    var paths = Set<String>()
    let sql = "SELECT source_path FROM documents WHERE source_path IS NOT NULL"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return paths }
    defer { sqlite3_finalize(stmt) }
    while sqlite3_step(stmt) == SQLITE_ROW {
        if let cStr = sqlite3_column_text(stmt, 0) {
            paths.insert(String(cString: cStr))
        }
    }
    return paths
}

func insertDocument(id: String, filename: String, importDate: Date, sourceType: String,
                    sourcePath: String? = nil, sourceModDate: Date? = nil) {
    let sql = "INSERT INTO documents (id, filename, import_date, source_type, source_path, source_mod_date) VALUES (?, ?, ?, ?, ?, ?)"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
    sqlite3_bind_text(stmt, 2, (filename as NSString).utf8String, -1, nil)
    sqlite3_bind_double(stmt, 3, importDate.timeIntervalSinceReferenceDate)
    sqlite3_bind_text(stmt, 4, (sourceType as NSString).utf8String, -1, nil)
    if let sourcePath {
        sqlite3_bind_text(stmt, 5, (sourcePath as NSString).utf8String, -1, nil)
    } else { sqlite3_bind_null(stmt, 5) }
    if let sourceModDate {
        sqlite3_bind_double(stmt, 6, sourceModDate.timeIntervalSinceReferenceDate)
    } else { sqlite3_bind_null(stmt, 6) }
    sqlite3_step(stmt)
}

func insertChunks(_ texts: [String], documentId: String) {
    exec("BEGIN TRANSACTION")
    let sql = "INSERT INTO chunks (id, document_id, text) VALUES (?, ?, ?)"
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        exec("ROLLBACK"); return
    }
    defer { sqlite3_finalize(stmt) }
    for text in texts {
        sqlite3_reset(stmt)
        let id = UUID().uuidString
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (documentId as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (text as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
    }
    exec("COMMIT")
}

// MARK: - Chunking

func chunkText(_ text: String) -> [String] {
    let raw = text.components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    var chunks: [String] = []
    var buffer = ""
    for paragraph in raw {
        if paragraph.count > 800 {
            if !buffer.isEmpty { chunks.append(buffer); buffer = "" }
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
            if !buffer.isEmpty { chunks.append(buffer) }
            buffer = paragraph
        }
    }
    if !buffer.isEmpty { chunks.append(buffer) }
    return chunks
}

func splitSentences(_ text: String) -> [String] {
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

// MARK: - Streaming JSONL Line Reader

class LineReader {
    let fileHandle: FileHandle
    let bufferSize: Int
    var buffer = Data()
    var atEOF = false

    init?(path: String, bufferSize: Int = 65536) {
        guard let fh = FileHandle(forReadingAtPath: path) else { return nil }
        self.fileHandle = fh
        self.bufferSize = bufferSize
    }

    deinit { fileHandle.closeFile() }

    func nextLine() -> String? {
        while true {
            if let range = buffer.range(of: Data([0x0A])) { // newline
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0...range.lowerBound)
                return String(data: lineData, encoding: .utf8)
            }
            if atEOF {
                if buffer.isEmpty { return nil }
                let lineData = buffer
                buffer = Data()
                return String(data: lineData, encoding: .utf8)
            }
            let chunk = fileHandle.readData(ofLength: bufferSize)
            if chunk.isEmpty { atEOF = true } else { buffer.append(chunk) }
        }
    }
}

// MARK: - Claude Code JSONL Parser (streaming)

func countHumanMessages(path: String) -> Int {
    guard let reader = LineReader(path: path) else { return 0 }
    var count = 0
    while let line = reader.nextLine() {
        guard !line.isEmpty,
              let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              type == "user",
              let msg = obj["message"] as? [String: Any],
              msg["content"] is String else { continue }
        count += 1
    }
    return count
}

func parseClaudeCodeJSONLStreaming(path: String) -> [(role: String, text: String)] {
    guard let reader = LineReader(path: path) else { return [] }
    var messages: [(role: String, text: String)] = []
    while let line = reader.nextLine() {
        autoreleasepool {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = obj["type"] as? String else { return }
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
    }
    return messages
}

// MARK: - Import Claude Code Transcripts

func importClaudeCodeTranscripts(from directory: URL) {
    let fm = FileManager.default
    var jsonlFiles: [URL] = []
    if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension == "jsonl" {
                jsonlFiles.append(fileURL)
            }
        }
    }
    guard !jsonlFiles.isEmpty else {
        print("No .jsonl files found under \(directory.path)")
        return
    }

    let existing = existingSourcePaths()
    let filesToProcess = jsonlFiles.filter { !existing.contains($0.path) }

    print("Found \(jsonlFiles.count) total transcripts, \(filesToProcess.count) new to import")
    guard !filesToProcess.isEmpty else { return }

    var imported = 0
    var skipped = 0

    for (i, file) in filesToProcess.enumerated() {
        autoreleasepool {
            let projectDir = file.deletingLastPathComponent().lastPathComponent
            let sessionId = file.deletingPathExtension().lastPathComponent
            let displayName = "claude-code/\(projectDir)/\(sessionId)"

            // Skip files > 10MB (agent subprocesses, not real sessions)
            if let attrs = try? fm.attributesOfItem(atPath: file.path),
               let size = attrs[.size] as? UInt64, size > 10_000_000 {
                skipped += 1; return
            }

            // Fast reject: stream-count human messages without loading full file
            let humanCount = countHumanMessages(path: file.path)
            guard humanCount >= minimumHumanMessages else {
                skipped += 1; return
            }

            let messages = parseClaudeCodeJSONLStreaming(path: file.path)
            let transcript = messages.map { "[\($0.role)]\n\($0.text)" }.joined(separator: "\n\n")
            let paragraphs = chunkText(transcript)
            guard !paragraphs.isEmpty else { skipped += 1; return }

            let docId = UUID().uuidString
            let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

            insertDocument(id: docId, filename: displayName, importDate: Date(), sourceType: "claude_code",
                          sourcePath: file.path, sourceModDate: modDate)
            insertChunks(paragraphs, documentId: docId)
            imported += 1
        }

        if (i + 1) % 10 == 0 || i == filesToProcess.count - 1 {
            print("  [\(i + 1)/\(filesToProcess.count)] imported: \(imported), skipped: \(skipped)")
        }
    }

    print("Done! Imported \(imported) sessions, skipped \(skipped) (< \(minimumHumanMessages) human messages or empty)")
}

// MARK: - Import Claude.ai Export

func importClaudeAIExport(from url: URL) {
    struct Msg: Decodable { let text: String; let sender: String }
    struct Conv: Decodable { let uuid: String; let name: String; let chat_messages: [Msg] }

    guard let data = try? Data(contentsOf: url),
          let conversations = try? JSONDecoder().decode([Conv].self, from: data) else {
        print("ERROR: Could not parse Claude.ai export JSON")
        return
    }

    let eligible = conversations.filter { $0.chat_messages.filter { $0.sender == "human" }.count >= minimumHumanMessages }
    print("Found \(conversations.count) conversations, \(eligible.count) with >= \(minimumHumanMessages) human messages")

    var imported = 0
    for (i, conv) in eligible.enumerated() {
        let transcript = conv.chat_messages.map { msg in
            let role = msg.sender == "human" ? "Human" : "Assistant"
            return "[\(role)]\n\(msg.text)"
        }.joined(separator: "\n\n")

        let paragraphs = chunkText(transcript)
        guard !paragraphs.isEmpty else { continue }

        let docId = UUID().uuidString
        insertDocument(id: docId, filename: "claude.ai: \(conv.name)", importDate: Date(), sourceType: "claude_ai")
        insertChunks(paragraphs, documentId: docId)
        imported += 1

        if (i + 1) % 10 == 0 || i == eligible.count - 1 {
            print("  [\(i + 1)/\(eligible.count)] imported: \(imported)")
        }
    }
    print("Done! Imported \(imported) Claude.ai conversations")
}

// MARK: - Import File

func importFile(from url: URL) {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        print("ERROR: Could not read \(url.path)")
        return
    }
    let paragraphs = chunkText(content)
    guard !paragraphs.isEmpty else { print("File is empty or produced no chunks"); return }

    let docId = UUID().uuidString
    insertDocument(id: docId, filename: url.lastPathComponent, importDate: Date(), sourceType: "file",
                  sourcePath: url.path)
    insertChunks(paragraphs, documentId: docId)
    print("Imported \(url.lastPathComponent) — \(paragraphs.count) chunks")
}

// MARK: - Main

let args = CommandLine.arguments

openDB()

if args.count >= 3 && args[1] == "--claude-ai" {
    let url = URL(fileURLWithPath: args[2])
    importClaudeAIExport(from: url)
} else if args.count >= 3 && args[1] == "--file" {
    let url = URL(fileURLWithPath: args[2])
    importFile(from: url)
} else {
    // Default: import Claude Code transcripts
    let dir: URL
    if args.count >= 2 {
        dir = URL(fileURLWithPath: args[1])
    } else {
        dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }
    importClaudeCodeTranscripts(from: dir)
}

sqlite3_close(db)
