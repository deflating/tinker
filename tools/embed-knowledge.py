#!/usr/bin/env python3
"""Backfill vector embeddings using Apple NLContextualEmbedding (BERT, 768-dim).

Uses subprocess isolation — each worker embeds a batch then exits,
preventing ObjC memory accumulation from crashing the process.
"""

import json
import sqlite3
import subprocess
import sys
import time

DB_PATH = "/Users/mattkennelly/.familiar/knowledge/knowledge.db"
BATCH_SIZE = 2000  # ~600MB peak per worker, well within limits

WORKER_SCRIPT = '''
import json, sqlite3, struct, sys
import NaturalLanguage

db = sqlite3.connect(sys.argv[1])
emb = NaturalLanguage.NLContextualEmbedding.contextualEmbeddingForLanguage_("en")
ok, err = emb.loadWithError_(None)
if not ok:
    print(json.dumps({"error": str(err)}))
    sys.exit(1)

dim = emb.sentenceVectorDimension()
rows = db.execute("SELECT id, text FROM chunks WHERE vector IS NULL LIMIT ?", (int(sys.argv[2]),)).fetchall()

count = 0
for chunk_id, text in rows:
    vec = emb.sentenceEmbeddingVectorForString_language_error_(text[:512], "en", None)
    if vec and len(vec) == dim:
        blob = struct.pack(f"{dim}f", *[float(vec[i]) for i in range(dim)])
        db.execute("UPDATE chunks SET vector = ? WHERE id = ?", (blob, chunk_id))
        count += 1

db.commit()
db.close()
print(json.dumps({"embedded": count, "processed": len(rows)}))
'''


def main():
    db = sqlite3.connect(DB_PATH)
    total = db.execute("SELECT count(*) FROM chunks WHERE vector IS NULL").fetchone()[0]
    db.close()

    print(f"{total} chunks need embeddings")
    if total == 0:
        print("Nothing to do!")
        return

    done = 0
    start = time.time()
    retries = 0

    while done < total:
        result = subprocess.run(
            [sys.executable, "-c", WORKER_SCRIPT, DB_PATH, str(BATCH_SIZE)],
            capture_output=True, text=True, timeout=600
        )

        if result.returncode != 0:
            retries += 1
            err = result.stderr.strip()[:200]
            print(f"Worker crashed (attempt {retries}): {err}")
            if retries > 5:
                print("Too many failures, stopping.")
                break
            time.sleep(2)
            continue

        retries = 0
        try:
            info = json.loads(result.stdout.strip())
        except (json.JSONDecodeError, ValueError):
            print(f"Bad output: {result.stdout.strip()[:200]}")
            break

        if "error" in info:
            print(f"Worker error: {info['error']}")
            break

        if info["processed"] == 0:
            break

        done += info["embedded"]
        elapsed = time.time() - start
        rate = done / elapsed if elapsed > 0 else 0
        remaining = (total - done) / rate if rate > 0 else 0
        print(f"  {done}/{total} ({done*100//total}%) — {rate:.0f}/sec — ~{remaining/60:.0f}min left", flush=True)

    elapsed = time.time() - start
    print(f"\nDone! Embedded {done} chunks in {elapsed/60:.1f} minutes")


if __name__ == "__main__":
    main()
