#!/bin/bash
# Batch wrapper for import-knowledge to avoid OOM on large transcript collections.
# Processes files in batches of 100 by creating temp directories with symlinks.

set -e

TOOL_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL="$TOOL_DIR/import-knowledge"
SOURCE="${1:-$HOME/.claude/projects}"

if [ ! -f "$TOOL" ]; then
    echo "Compiling import-knowledge..."
    swiftc -O -o "$TOOL" "$TOOL_DIR/import-knowledge.swift" -framework NaturalLanguage -lsqlite3
fi

# Collect all jsonl files
ALL_FILES=$(find "$SOURCE" -name "*.jsonl" -type f)
TOTAL=$(echo "$ALL_FILES" | wc -l | tr -d ' ')
echo "Found $TOTAL total .jsonl files"

BATCH_SIZE=50
BATCH_NUM=0
IMPORTED_TOTAL=0

echo "$ALL_FILES" | while IFS= read -r file; do
    BATCH_NUM=$((BATCH_NUM + 1))

    if [ $((BATCH_NUM % BATCH_SIZE)) -eq 1 ]; then
        BATCH_DIR=$(mktemp -d)
        BATCH_START=$BATCH_NUM
    fi

    # Symlink into batch dir (preserve some path info in filename)
    SAFE_NAME=$(echo "$file" | sed 's|/|__|g')
    ln -sf "$file" "$BATCH_DIR/$SAFE_NAME.jsonl" 2>/dev/null || cp "$file" "$BATCH_DIR/$SAFE_NAME.jsonl"

    if [ $((BATCH_NUM % BATCH_SIZE)) -eq 0 ] || [ "$BATCH_NUM" -eq "$TOTAL" ]; then
        echo ""
        echo "=== Batch $BATCH_START-$BATCH_NUM of $TOTAL ==="
        "$TOOL" "$BATCH_DIR" 2>&1 || true
        rm -rf "$BATCH_DIR"
    fi
done

echo ""
echo "All batches complete!"
