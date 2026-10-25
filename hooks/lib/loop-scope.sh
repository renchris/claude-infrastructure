#!/bin/bash
# loop-scope.sh — the ONE definition of "this frozen scope is a loop" (ruling d610f8473106,
# docs/research/lead-keeps-working-2026-10-24.md §3.1 (ii), §3.2).
#
# Readers: scripts/wrap-ledger.sh (§ LOOP, the consumer: LOOP_SCOPE/LOOP_OPEN) and
# hooks/dod-persist.sh (capture-loop, the producer). One definition, so the producer can never
# record a line the consumer does not read as a loop, or the reverse.
#
# THE TEST IS VERB-FIRST on the text after the `Scope (frozen):` prefix: the scope must OPEN with
# loop|repeat|iterate|keep going|keep looping|keep running, then "until". Measured over the DoD store
# it matches 1 of 362 lines (the B13 lead's) and 8 of 1,648 recent transcripts, all B13 lineage, with
# 0 false positives; it rejects "add the loop until dry floor…" and "review why a loop until dry lead
# idled", the phrasings that fooled a 40-character-prefix match (design §3.1, §9.3 M1-M2).
# Leading markdown emphasis (`**loop until**`) and leading whitespace are allowed; case is ignored.
#
# LOOP_RE is an awk ERE, matched against the LOWERCASED text. Pass it through `awk -v`, which turns
# the `\t` into a tab; bash `=~` would not, so never test it with `=~`.
#
# Pure definitions only; safe to source under `set -u` and under /bin/bash 3.2.

LOOP_RE='^[*_`]*(loop|repeat|iterate|keep (going|looping|running))[ \t]+until([^a-z]|$)'

# loop_scope_is_loop <scope text, with or without the `Scope (frozen):` prefix> → rc 0 when a loop.
# Only the first line is read. Any error (no awk) reads as "not a loop": the fail-open direction.
loop_scope_is_loop() {
  printf '%s\n' "${1:-}" | awk -v re="$LOOP_RE" '
    NR == 1 { s = tolower($0); sub(/^[ \t]*scope \(frozen\):/, "", s); sub(/^[ \t]+/, "", s)
              if (s ~ re) f = 1 }
    END { exit (f ? 0 : 1) }' 2>/dev/null
}
