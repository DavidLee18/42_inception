#!/usr/bin/env bash
set -e

SRC=./site
OUT=./out
mkdir -p "$OUT"

# ── Step 1: convert Markdown → HTML fragment with pandoc ────────────────────
pandoc "$SRC/index.md" -o "$SRC/content.bar"

# ── Step 2: barbell-style substitution ──────────────────────────────────────
# For each |variable| in the template, replace it with the contents of
# variable.bar — exactly how barbell (the BQN tool) works.
barbell() {
    local template="$1"
    local output="$2"
    cp "$template" "$output"

    for bar_file in "$SRC"/*.bar; do
        local var_name
        var_name=$(basename "$bar_file" .bar)
        local var_value
        var_value=$(cat "$bar_file")
        # Escape special sed characters in value
        var_value_escaped=$(printf '%s\n' "$var_value" | sed 's/[&/\]/\\&/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
        sed -i "s|${var_name}|${var_value_escaped}|g" "$output"
    done
}

barbell "$SRC/template.html" "$OUT/index.html"

# ── Step 3: copy static assets ──────────────────────────────────────────────
cp "$SRC/style.css" "$OUT/style.css"

echo "Build complete → $OUT"
ls -lh "$OUT"
