#!/bin/bash
# Run once per machine to symlink memory/seed files to iCloud container.
# Requires Tinker to have been launched at least once (to create the container).

set -e

ICLOUD="$HOME/Library/Mobile Documents/iCloud~app~tinker/Documents"

if [ ! -d "$ICLOUD" ]; then
    echo "iCloud container not found. Launch Tinker first, then re-run this script."
    exit 1
fi

mkdir -p "$ICLOUD/memorable" "$ICLOUD/familiar/seeds" "$ICLOUD/familiar/transcripts"

link_dir() {
    local LOCAL="$1"
    local CLOUD="$2"

    if [ -L "$LOCAL" ]; then
        echo "Already symlinked: $LOCAL"
        return
    fi

    if [ -d "$LOCAL" ]; then
        # Copy any files not already in iCloud
        for f in "$LOCAL"/*; do
            [ -f "$f" ] || continue
            base=$(basename "$f")
            [ ! -f "$CLOUD/$base" ] && cp "$f" "$CLOUD/$base" && echo "Copied $base → iCloud"
        done
        mv "$LOCAL" "${LOCAL}.pre-icloud"
        echo "Backed up $LOCAL"
    fi

    mkdir -p "$(dirname "$LOCAL")"
    ln -s "$CLOUD" "$LOCAL"
    echo "Symlinked $LOCAL → $CLOUD"
}

link_dir "$HOME/.memorable/data" "$ICLOUD/memorable"
link_dir "$HOME/.familiar/seeds" "$ICLOUD/familiar/seeds"
link_dir "$HOME/.familiar/transcripts" "$ICLOUD/familiar/transcripts"

echo "Done. Files are now syncing via iCloud."
