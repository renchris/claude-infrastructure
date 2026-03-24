#!/bin/bash
set -euo pipefail

INDEX="$HOME/.claude/plans-index.json"
PLANS_DIR="$HOME/.claude/plans"
PROJECTS_DIR="$HOME/.claude/projects"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

echo '{"version":1,"generated":"'"$NOW"'","plans":{}}' > "$INDEX"

# Phase 1: Mine session JSONL files for plan path references
for proj_dir in "$PROJECTS_DIR"/*/; do
    sessions_idx="$proj_dir/sessions-index.json"
    [ ! -f "$sessions_idx" ] && continue

    orig_path=$(jq -r '.originalPath // empty' "$sessions_idx" 2>/dev/null)
    [ -z "$orig_path" ] && continue
    proj_name=$(basename "$orig_path")

    # Grep only Write/Edit/MultiEdit tool events for plan file references
    plan_refs=$(grep -h '"name"\s*:\s*"Write\|"name"\s*:\s*"Edit\|"name"\s*:\s*"MultiEdit' "$proj_dir"*.jsonl 2>/dev/null \
      | grep -oh '"file_path"\s*:\s*"[^"]*\.claude/plans/[^"]*\.md"' \
      | sed 's/.*"file_path"\s*:\s*"//; s/"//' \
      | xargs -I{} basename {} \
      | sort -u || true)

    for fname in $plan_refs; do
        [ ! -f "$PLANS_DIR/$fname" ] && continue
        TEMP=$(mktemp)
        jq --arg f "$fname" --arg p "$orig_path" --arg pn "$proj_name" --arg now "$NOW" \
           '.plans[$f] //= {} | .plans[$f].project = $p | .plans[$f].projectName = $pn |
            .plans[$f].firstIndexed = (.plans[$f].firstIndexed // $now) | .plans[$f].lastSeen = $now' \
           "$INDEX" > "$TEMP" && mv "$TEMP" "$INDEX"
    done
done

# Phase 2: Agent sub-plan inheritance
for f in "$PLANS_DIR"/*-agent-*.md; do
    [ ! -f "$f" ] && continue
    fname=$(basename "$f")
    parent_slug=$(echo "$fname" | sed 's/-agent-[a-f0-9]*\.md/.md/')

    parent_project=$(jq -r --arg p "$parent_slug" '.plans[$p].project // empty' "$INDEX" 2>/dev/null)
    if [ -n "$parent_project" ]; then
        parent_name=$(jq -r --arg p "$parent_slug" '.plans[$p].projectName // empty' "$INDEX" 2>/dev/null)
        TEMP=$(mktemp)
        jq --arg f "$fname" --arg p "$parent_project" --arg pn "$parent_name" --arg now "$NOW" \
           '.plans[$f] //= {} | .plans[$f].project //= $p | .plans[$f].projectName //= $pn |
            .plans[$f].firstIndexed //= $now | .plans[$f].lastSeen = $now' \
           "$INDEX" > "$TEMP" && mv "$TEMP" "$INDEX"
    fi
done

# Report
TOTAL=$(find "$PLANS_DIR" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
INDEXED=$(jq '.plans | length' "$INDEX")
echo "Migration complete: $INDEXED / $TOTAL plans indexed"
echo ""
echo "=== Unassociated files ==="
for f in "$PLANS_DIR"/*.md; do
    fname=$(basename "$f")
    project=$(jq -r --arg f "$fname" '.plans[$f].project // empty' "$INDEX" 2>/dev/null)
    [ -z "$project" ] && echo "  $fname"
done
