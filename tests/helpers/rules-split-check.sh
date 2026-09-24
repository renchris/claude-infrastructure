#!/usr/bin/env bash
# rules-split-check.sh — prove a rules file was split without losing or duplicating a line.
#
# `.claude/rules/agent-operating-lessons.md` was split on 2026-09-23 into a resident half (the same
# path) and `agent-operating-lessons-situational.md`, so a per-account claudeMdExcludes glob can
# drop the situational half (docs/research/token-efficiency-2026-09-23/audit/C7.labels.md). The
# split is only safe if every line of the original is in exactly ONE of the two files: a line in
# neither is a lesson lost from the default load, a line in both is one rule paid for twice.
#
# Lines compare with leading and trailing whitespace stripped, because one resident lesson was a
# nested bullet in the original and is de-indented in the resident file. Blank lines are ignored.
# Lines the two new files ADD (the pointer, the situational header) are not judged.
#
# Usage: rules-split-check.sh <original> <resident> <situational>
# Exit:  0 every original line in exactly one file · 1 findings · 2 unreadable input
set -u

[ $# -eq 3 ] || { echo "usage: $0 <original> <resident> <situational>" >&2; exit 2; }
for f in "$1" "$2" "$3"; do
  [ -r "$f" ] || { echo "rules-split-check: NON-VERDICT — cannot read $f" >&2; exit 2; }
done

awk '
  function norm(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
  FNR == 1 { part++ }
  { l = norm($0); if (l == "") next }
  part == 1 { o[l]++; n++; if (l ~ /^- /) b++; next }
  part == 2 { r[l]++; next }
  part == 3 { s[l]++; next }
  END {
    bad = 0
    for (l in o) {
      got = r[l] + s[l]
      if (r[l] > 0 && s[l] > 0) { printf "IN BOTH: %s\n", substr(l, 1, 120); bad++; continue }
      if (got < o[l]) { printf "MISSING (%d of %d): %s\n", o[l] - got, o[l], substr(l, 1, 120); bad++; continue }
      if (got > o[l]) { printf "DUPLICATED (%d, original had %d): %s\n", got, o[l], substr(l, 1, 120); bad++ }
    }
    if (n == 0) { print "rules-split-check: NON-VERDICT — the original has no lines" > "/dev/stderr"; exit 2 }
    if (bad) { printf "rules-split-check: %d finding(s) over %d original line(s)\n", bad, n > "/dev/stderr"; exit 1 }
    printf "rules-split-check: ok — %d original line(s), %d of them bullets, each in exactly one file\n", n, b
  }
' "$1" "$2" "$3"
