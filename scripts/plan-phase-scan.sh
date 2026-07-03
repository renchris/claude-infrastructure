#!/bin/bash
# plan-phase-scan.sh — scan a plan file, emit structured summary of sections
# with completion status, commit hashes, line ranges, and phase-0 flags.
#
# Usage:
#   plan-phase-scan.sh <plan-file>                # JSON output (default)
#   plan-phase-scan.sh <plan-file> --markdown     # human-readable table
#
# Output modes:
#   json      : {"file": "...", "sections": [{...}, ...], "summary": {...}}
#   markdown  : table with | title | level | status | lines | hashes |
#
# Status detection (priority order):
#   1. "SUPERSEDED" in heading       → SUPERSEDED
#   2. "DONE" in heading             → DONE
#   3. commit hash (7+ hex) in head  → DONE (implicit)
#   4. "WIP" or "IN_PROGRESS"        → IN_PROGRESS
#   5. otherwise                     → PENDING
#
# Phase 0 detection:
#   heading matches /Phase 0|Agent Team Orchestration/ (case-insensitive)
#
# Exit codes:
#   0 = scan succeeded
#   1 = bad usage or file not found
#   2 = parse error (no headings detected in a non-empty file)
#
# Dependencies: awk, sed, grep. No jq required (JSON emitted by hand).

set -uo pipefail

FILE="${1:-}"
FORMAT="${2:-json}"

if [[ -z "$FILE" ]]; then
  cat >&2 <<EOF
usage: plan-phase-scan.sh <plan-file> [--markdown]

Scans a plan file and emits a section-by-section status report.
Default output: JSON. Pass --markdown for a human-readable table.

Status values: DONE, IN_PROGRESS, PENDING, SUPERSEDED
EOF
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo "error: file not found: $FILE" >&2
  exit 1
fi

TOTAL_LINES=$(wc -l < "$FILE" | tr -d ' ')

# Extract headings AND body Status lines with line numbers, excluding fenced code.
# HEADINGS: ^#, ##, ### ... up to level 6 followed by a space.
# BODY STATUS: lines matching **Status**: VALUE (case-insensitive on "Status").
#   Emitted with sentinel prefix "S:" so second awk pass can associate them
#   with their enclosing section.
# Fenced block detection: toggle state on ``` or ~~~ lines (at column 0).
SCAN_OUT=$(awk '
  BEGIN { in_fence = 0 }
  /^```/   { in_fence = !in_fence; next }
  /^~~~/   { in_fence = !in_fence; next }
  in_fence { next }
  /^#{1,6} / { printf "H:%d:%s\n", NR, $0; next }
  # Body status line — accepts canonical "**Status**:" and prefixed forms like
  # "**v1 Status**:", "**Phase 3 Status**:", plus bare "Status:" at line start.
  /^\*\*[^*]*[Ss]tatus\*\*:/ { printf "S:%d:%s\n", NR, $0; next }
  /^[Ss]tatus:[ \t]/ { printf "S:%d:%s\n", NR, $0; next }
' "$FILE")

HEADING_COUNT=$(printf '%s\n' "$SCAN_OUT" | grep -c '^H:' || true)
if [[ "$HEADING_COUNT" -eq 0 ]] && [[ "$TOTAL_LINES" -gt 0 ]]; then
  echo "error: no markdown headings (^#) found in $FILE" >&2
  exit 2
fi

# ---------- Build section records ----------
# Each record: line|level|title|status|commit_hashes|is_phase_0|status_source

tmp_records=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$tmp_records'" EXIT

# Single awk over SCAN_OUT which contains both H: headings and S: body statuses.
# Avoids -v newline limitations that broke body-status passing.
awk -v total="$TOTAL_LINES" '
  BEGIN { n = 0; bs_n = 0 }
  /^H:[0-9]+:#{1,6} / {
    # Strip "H:" prefix — lines[n] holds "LINENUM:#### Title"
    lines[++n] = substr($0, 3)
  }
  /^S:[0-9]+:/ {
    rec = substr($0, 3)
    sc = index(rec, ":")
    if (sc > 0) {
      bs_n++
      bs_line[bs_n] = substr(rec, 1, sc - 1) + 0
      bs_text[bs_n] = substr(rec, sc + 1)
    }
  }
  END {
    for (i = 1; i <= n; i++) {
      raw = lines[i]
      colon = index(raw, ":")
      lnum = substr(raw, 1, colon - 1) + 0
      rest = substr(raw, colon + 1)
      # Count leading #
      level = 0
      while (substr(rest, level + 1, 1) == "#") level++
      title = substr(rest, level + 2)  # skip # chars + one space
      # Strip trailing whitespace
      sub(/[ \t\r]+$/, "", title)

      # Determine end line: next heading with level <= this level, or EOF
      end_line = total
      for (j = i + 1; j <= n; j++) {
        raw2 = lines[j]
        colon2 = index(raw2, ":")
        rest2 = substr(raw2, colon2 + 1)
        l2 = 0
        while (substr(rest2, l2 + 1, 1) == "#") l2++
        if (l2 <= level) {
          lnum2 = substr(raw2, 1, colon2 - 1) + 0
          end_line = lnum2 - 1
          break
        }
      }

      # Status detection (priority order).
      # DONE and SUPERSEDED must be bounded tokens — not substrings — to avoid
      # false positives like "Definition of done" or "Undone work".
      # Bounded means surrounded by non-letter chars or start/end of title.
      status = "PENDING"
      status_source = "heading"
      upper_title = toupper(title)
      if (upper_title ~ /(^|[^A-Z])SUPERSEDED([^A-Z]|$)/) {
        status = "SUPERSEDED"
      } else if (upper_title ~ /(^|[^A-Z])DONE([^A-Z]|$)/) {
        status = "DONE"
      } else if (upper_title ~ /(^|[^A-Z])WIP([^A-Z]|$)/ || \
                upper_title ~ /(^|[^A-Z])IN[ _]PROGRESS([^A-Z]|$)/) {
        status = "IN_PROGRESS"
      }

      # Body **Status**: line detection — overrides PENDING if a body status
      # line exists within this sections range (lnum+1 .. end_line).
      # Does not override SUPERSEDED (stricter signal already captured).
      if (status == "PENDING") {
        for (bi = 1; bi <= bs_n; bi++) {
          if (bs_line[bi] > lnum && bs_line[bi] <= end_line) {
            upper_body = toupper(bs_text[bi])
            if (upper_body ~ /(^|[^A-Z])SUPERSEDED([^A-Z]|$)/) {
              status = "SUPERSEDED"; status_source = "body"; break
            } else if (upper_body ~ /(^|[^A-Z])DONE([^A-Z]|$)/) {
              status = "DONE"; status_source = "body"; break
            } else if (upper_body ~ /(^|[^A-Z])WIP([^A-Z]|$)/ || \
                       upper_body ~ /(^|[^A-Z])IN[ _]PROGRESS([^A-Z]|$)/) {
              status = "IN_PROGRESS"; status_source = "body"; break
            }
          }
        }
      }

      # Commit-hash detection: 7+ lowercase hex chars, surrounded by backticks or word boundaries
      # (Accept 7-40 to match short + long hashes. Exclude purely numeric strings.)
      hashes = ""
      t = title
      while (match(t, /[0-9a-f]{7,40}/)) {
        h = substr(t, RSTART, RLENGTH)
        # Reject if purely numeric (unlikely to be a real hash — e.g., dates)
        if (h !~ /^[0-9]+$/) {
          if (hashes == "") hashes = h; else hashes = hashes "," h
          # If heading contained a hash but no explicit DONE token, treat as DONE
          if (status == "PENDING") status = "DONE"
        }
        t = substr(t, RSTART + RLENGTH)
      }

      # Phase 0 flag
      is_phase_0 = 0
      if (upper_title ~ /PHASE 0/ || upper_title ~ /AGENT TEAM ORCHESTRATION/) {
        is_phase_0 = 1
      }

      line_count = end_line - lnum + 1
      # Escape pipes in title for pipe-delimited record (rare but safe)
      gsub(/\|/, "\\|", title)
      printf "%d|%d|%d|%d|%s|%s|%d|%s|%s\n", lnum, end_line, line_count, level, status, hashes, is_phase_0, status_source, title
    }
  }
' <<< "$SCAN_OUT" > "$tmp_records"

if [[ ! -s "$tmp_records" ]]; then
  echo "error: parse produced no records for $FILE" >&2
  exit 2
fi

# ---------- Summary counters ----------
TOTAL_SECTIONS=$(wc -l < "$tmp_records" | tr -d ' ')
DONE_COUNT=$(awk -F'|' '$5=="DONE"' "$tmp_records" | wc -l | tr -d ' ')
IN_PROGRESS_COUNT=$(awk -F'|' '$5=="IN_PROGRESS"' "$tmp_records" | wc -l | tr -d ' ')
PENDING_COUNT=$(awk -F'|' '$5=="PENDING"' "$tmp_records" | wc -l | tr -d ' ')
SUPERSEDED_COUNT=$(awk -F'|' '$5=="SUPERSEDED"' "$tmp_records" | wc -l | tr -d ' ')
PHASE_0_COUNT=$(awk -F'|' '$7=="1"' "$tmp_records" | wc -l | tr -d ' ')

# ---------- Output ----------
if [[ "$FORMAT" == "--markdown" || "$FORMAT" == "markdown" ]]; then
  echo "# Plan scan: $FILE"
  echo ""
  echo "**Total lines**: $TOTAL_LINES · **Sections**: $TOTAL_SECTIONS · **Phase-0 sections**: $PHASE_0_COUNT"
  echo ""
  echo "**Status**: DONE=$DONE_COUNT · IN_PROGRESS=$IN_PROGRESS_COUNT · PENDING=$PENDING_COUNT · SUPERSEDED=$SUPERSEDED_COUNT"
  echo ""
  echo "| # | L | Status | Src | Lines | Phase-0 | Range | Commits | Title |"
  echo "|---|---|--------|-----|-------|---------|-------|---------|-------|"
  idx=0
  while IFS='|' read -r start end lines level status hashes is_p0 status_src title; do
    idx=$((idx + 1))
    p0_flag="—"
    [[ "$is_p0" == "1" ]] && p0_flag="✓"
    [[ -z "$hashes" ]] && hashes="—"
    printf "| %d | %s | %s | %s | %s | %s | %s–%s | %s | %s |\n" \
      "$idx" "$level" "$status" "$status_src" "$lines" "$p0_flag" "$start" "$end" "$hashes" "$title"
  done < "$tmp_records"
  exit 0
fi

# JSON output (hand-built; no jq dep).
printf '{\n'
printf '  "file": "%s",\n' "$FILE"
printf '  "total_lines": %s,\n' "$TOTAL_LINES"
printf '  "summary": {\n'
printf '    "sections": %s,\n' "$TOTAL_SECTIONS"
printf '    "done": %s,\n' "$DONE_COUNT"
printf '    "in_progress": %s,\n' "$IN_PROGRESS_COUNT"
printf '    "pending": %s,\n' "$PENDING_COUNT"
printf '    "superseded": %s,\n' "$SUPERSEDED_COUNT"
printf '    "phase_0": %s\n' "$PHASE_0_COUNT"
printf '  },\n'
printf '  "sections": [\n'

first=1
while IFS='|' read -r start end lines level status hashes is_p0 status_src title; do
  [[ -z "$start" ]] && continue
  if [[ "$first" -eq 0 ]]; then
    printf ',\n'
  fi
  first=0
  # Escape JSON string: backslash, double-quote, control chars
  escaped_title=$(printf '%s' "$title" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g')
  # hashes → JSON array
  if [[ -z "$hashes" ]]; then
    hashes_json="[]"
  else
    # comma-split, wrap each in quotes
    hashes_json="["
    IFS=',' read -ra HASH_ARR <<< "$hashes"
    first_h=1
    for h in "${HASH_ARR[@]}"; do
      [[ "$first_h" -eq 0 ]] && hashes_json="${hashes_json},"
      hashes_json="${hashes_json}\"${h}\""
      first_h=0
    done
    hashes_json="${hashes_json}]"
  fi
  [[ "$is_p0" == "1" ]] && is_p0_json="true" || is_p0_json="false"
  printf '    {"start_line": %s, "end_line": %s, "line_count": %s, "level": %s, "status": "%s", "status_source": "%s", "commit_hashes": %s, "is_phase_0": %s, "title": "%s"}' \
    "$start" "$end" "$lines" "$level" "$status" "$status_src" "$hashes_json" "$is_p0_json" "$escaped_title"
done < "$tmp_records"

printf '\n  ]\n}\n'
exit 0
