#!/usr/bin/env python3
"""
Standalone knowledge importer for Familiar.
Parses Claude Code transcripts, chunks text, stores in SQLite.
Vectors are left NULL — the app embeds them lazily on first search.

Usage:
    python3 tools/import-knowledge.py                          # Claude Code from ~/.claude/projects
    python3 tools/import-knowledge.py /path/to/projects        # custom path
    python3 tools/import-knowledge.py --claude-ai export.json  # Claude.ai export
    python3 tools/import-knowledge.py --file doc.md            # arbitrary file
"""

import json
import os
import sqlite3
import sys
import uuid
from pathlib import Path
from time import time

# Config
KNOWLEDGE_DIR = Path.home() / ".familiar" / "knowledge"
DB_PATH = KNOWLEDGE_DIR / "knowledge.db"
MIN_HUMAN_MESSAGES = 5
MAX_FILE_SIZE = 50_000_000  # 50MB

def init_db():
    KNOWLEDGE_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(DB_PATH))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            filename TEXT NOT NULL,
            import_date REAL NOT NULL,
            source_type TEXT NOT NULL DEFAULT 'file',
            source_path TEXT,
            source_mod_date REAL
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id TEXT PRIMARY KEY,
            document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
            text TEXT NOT NULL,
            vector BLOB
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_document_id ON chunks(document_id);
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            text, content=chunks, content_rowid=rowid
        );
        CREATE TRIGGER IF NOT EXISTS chunks_ai AFTER INSERT ON chunks BEGIN
            INSERT INTO chunks_fts(rowid, text) VALUES (new.rowid, new.text);
        END;
        CREATE TRIGGER IF NOT EXISTS chunks_ad AFTER DELETE ON chunks BEGIN
            INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES('delete', old.rowid, old.text);
        END;
    """)
    conn.commit()
    return conn


def existing_source_paths(conn):
    rows = conn.execute("SELECT source_path FROM documents WHERE source_path IS NOT NULL").fetchall()
    return {r[0] for r in rows}


def parse_cc_jsonl(path):
    """Stream-parse a Claude Code JSONL file, extracting human + assistant text only."""
    messages = []
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type")
            msg = obj.get("message", {})

            if msg_type == "user":
                content = msg.get("content")
                if isinstance(content, str) and content.strip():
                    messages.append(("Human", content))
            elif msg_type == "assistant":
                content = msg.get("content")
                if isinstance(content, list):
                    text_parts = []
                    for block in content:
                        if isinstance(block, dict) and block.get("type") == "text":
                            t = block.get("text", "")
                            if t.strip():
                                text_parts.append(t)
                    if text_parts:
                        messages.append(("Assistant", "\n".join(text_parts)))
    return messages


def chunk_text(text):
    """Split text into ~500-token chunks (approximated by characters)."""
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    chunks = []
    buffer = ""

    for para in paragraphs:
        if len(para) > 800:
            if buffer:
                chunks.append(buffer)
                buffer = ""
            # Split long paragraphs by sentences (rough)
            sentences = para.replace(". ", ".\n").split("\n")
            sent_buf = ""
            for sent in sentences:
                if len(sent_buf) + len(sent) > 600:
                    if sent_buf:
                        chunks.append(sent_buf)
                    sent_buf = sent
                else:
                    sent_buf += (" " if sent_buf else "") + sent
            if sent_buf:
                chunks.append(sent_buf)
        elif len(buffer) + len(para) < 100:
            buffer += ("\n\n" if buffer else "") + para
        else:
            if buffer:
                chunks.append(buffer)
            buffer = para

    if buffer:
        chunks.append(buffer)
    return chunks


def insert_document(conn, doc_id, filename, source_type, source_path=None, source_mod_date=None):
    import time as _time
    conn.execute(
        "INSERT INTO documents (id, filename, import_date, source_type, source_path, source_mod_date) VALUES (?, ?, ?, ?, ?, ?)",
        (doc_id, filename, _time.time(), source_type, source_path, source_mod_date)
    )


def insert_chunks(conn, chunks, document_id):
    conn.executemany(
        "INSERT INTO chunks (id, document_id, text, vector) VALUES (?, ?, ?, NULL)",
        [(str(uuid.uuid4()), document_id, text) for text in chunks]
    )


def import_claude_code(conn, directory):
    directory = Path(directory)
    jsonl_files = sorted(directory.rglob("*.jsonl"))
    if not jsonl_files:
        print(f"No .jsonl files found under {directory}")
        return

    existing = existing_source_paths(conn)
    to_process = [f for f in jsonl_files if str(f) not in existing]

    print(f"Found {len(jsonl_files)} total transcripts, {len(to_process)} new")
    if not to_process:
        return

    imported = 0
    skipped = 0
    start = time()

    for i, fpath in enumerate(to_process):
        # Skip huge files
        try:
            size = fpath.stat().st_size
        except OSError:
            skipped += 1
            continue
        if size > MAX_FILE_SIZE:
            skipped += 1
            if (i + 1) % 100 == 0:
                print(f"  [{i+1}/{len(to_process)}] imported: {imported}, skipped: {skipped}")
            continue

        try:
            messages = parse_cc_jsonl(str(fpath))
        except Exception:
            skipped += 1
            continue

        human_count = sum(1 for r, _ in messages if r == "Human")
        if human_count < MIN_HUMAN_MESSAGES:
            skipped += 1
            if (i + 1) % 100 == 0:
                print(f"  [{i+1}/{len(to_process)}] imported: {imported}, skipped: {skipped}")
            continue

        transcript = "\n\n".join(f"[{role}]\n{text}" for role, text in messages)
        chunks = chunk_text(transcript)
        if not chunks:
            skipped += 1
            continue

        project_dir = fpath.parent.name
        session_id = fpath.stem
        display_name = f"claude-code/{project_dir}/{session_id}"
        doc_id = str(uuid.uuid4())
        mod_date = fpath.stat().st_mtime

        insert_document(conn, doc_id, display_name, "claude_code", str(fpath), mod_date)
        insert_chunks(conn, chunks, doc_id)
        conn.commit()
        imported += 1

        if (i + 1) % 10 == 0:
            elapsed = time() - start
            rate = imported / elapsed if elapsed > 0 else 0
            print(f"  [{i+1}/{len(to_process)}] imported: {imported}, skipped: {skipped} ({rate:.1f}/s)")

    conn.commit()
    elapsed = time() - start
    print(f"\nDone! Imported {imported} sessions, skipped {skipped} in {elapsed:.1f}s")


def import_claude_ai(conn, json_path):
    with open(json_path, 'r') as f:
        conversations = json.load(f)

    eligible = [c for c in conversations
                if sum(1 for m in c.get("chat_messages", []) if m.get("sender") == "human") >= MIN_HUMAN_MESSAGES]

    print(f"Found {len(conversations)} conversations, {len(eligible)} with >= {MIN_HUMAN_MESSAGES} human messages")

    imported = 0
    for i, conv in enumerate(eligible):
        transcript = "\n\n".join(
            f"[{'Human' if m['sender'] == 'human' else 'Assistant'}]\n{m['text']}"
            for m in conv["chat_messages"]
        )
        chunks = chunk_text(transcript)
        if not chunks:
            continue

        doc_id = str(uuid.uuid4())
        name = conv.get("name", "Untitled")
        insert_document(conn, doc_id, f"claude.ai: {name}", "claude_ai")
        insert_chunks(conn, chunks, doc_id)
        imported += 1

        if (i + 1) % 10 == 0:
            print(f"  [{i+1}/{len(eligible)}] imported: {imported}")

    conn.commit()
    print(f"Done! Imported {imported} Claude.ai conversations")


def import_file(conn, file_path):
    path = Path(file_path)
    text = path.read_text(encoding='utf-8', errors='replace')
    chunks = chunk_text(text)
    if not chunks:
        print("File is empty or produced no chunks")
        return

    doc_id = str(uuid.uuid4())
    insert_document(conn, doc_id, path.name, "file", str(path))
    insert_chunks(conn, chunks, doc_id)
    conn.commit()
    print(f"Imported {path.name} — {len(chunks)} chunks")


def main():
    conn = init_db()
    args = sys.argv[1:]

    if len(args) >= 2 and args[0] == "--claude-ai":
        import_claude_ai(conn, args[1])
    elif len(args) >= 2 and args[0] == "--file":
        import_file(conn, args[1])
    else:
        directory = args[0] if args else str(Path.home() / ".claude" / "projects")
        import_claude_code(conn, directory)

    # Report totals
    doc_count = conn.execute("SELECT COUNT(*) FROM documents").fetchone()[0]
    chunk_count = conn.execute("SELECT COUNT(*) FROM chunks").fetchone()[0]
    print(f"\nKnowledge base: {doc_count} documents, {chunk_count} chunks")
    print(f"Database: {DB_PATH}")

    conn.close()


if __name__ == "__main__":
    main()
