#!/bin/bash
# post-compact.sh — the COMPACTION LEDGER: one bounded line per compaction, carrying the two fields
# that exist nowhere else (HOOK_SURFACE_100P § 3 row 15, W3-D).
#
# 🚨 WHAT THIS HOOK IS AND IS NOT FOR — stated first because the honest version of the case is
# narrower than the obvious one. `SessionStart` with `source=compact` already fires ~1.3 s earlier
# and is ALREADY WIRED fleet-wide, so the OCCURRENCE of a compaction is free today. **Counting
# compactions does not justify this hook.** Two fields do, and they are the whole argument:
#   · `trigger` ∈ {manual, auto} — the exact field CONTEXT_ECONOMY_V2 derives today by SCRAPING
#     transcripts. That derivation is the thing this replaces: 39/39 compactions fleet-wide read
#     `trigger:"manual"` with 0 auto, and that finding rests entirely on a scraper. An observed
#     field is a different class of evidence from a re-derived one, and it is what would let the
#     "the harness may not emit auto at all" question be settled by a single row rather than a
#     corpus pass.
#   · `compact_summary` — the model-written summary the successor context is built from. It exists
#     in no other payload.
#
# 🚨 THE CONSTRAINT THAT SHAPES THE ROW: NEVER ECHO OR STORE THE STDIN WHOLE. The two captured
# `compact_summary` values measured **21,834** and **5,989** characters (/tmp/hs/log/session.tsv and
# session114.tsv, W1). Appending that to a log per compaction mints exactly the unbounded-log defect
# HOOK_CHAIN_COST R-5 already records against bash-execution.log, and it copies the summary — which
# can carry anything the conversation carried — into a second store. So the row records a DIGEST:
# the length, a sha256, and a bounded head. Length + sha make two compactions distinguishable and
# a summary verifiable against a transcript; they do not reproduce it.
#
# MEASURED PAYLOAD (2.1.114 AND 2.1.220 · headless `-p`, `--resume` + `/compact`):
#   {session_id, transcript_path, cwd, hook_event_name:"PostCompact", trigger, compact_summary}
#   + optional `prompt_id` (present in the 220 capture, ABSENT in the 114 one — do not key on it).
#   Both captures carry `trigger:"manual"`; `auto` is in the schema and has never been observed
#   here, which is precisely why the field is worth logging rather than assuming.
#
# STDOUT IS ALWAYS EMPTY. PostCompact is observability-class, but the fleet rule stands on its own:
# a hook whose output schema you have not read must not emit one (§ 4). Nothing below writes to
# stdout; `tests/post-compact.bats` asserts it per path.
#
# FAIL-OPEN BY CONSTRUCTION: no `set -e`. Empty stdin, malformed JSON, a wrong event name, an absent
# jq, no sha tool on PATH, an unwritable log — every one exits 0.
#
# Env seams (tests): POST_COMPACT_LOG · POST_COMPACT_MAX_BYTES · POST_COMPACT_HEAD_CHARS
# Kill switch: CC_POST_COMPACT_DISABLED=1
set -uo pipefail

[ "${CC_POST_COMPACT_DISABLED:-0}" = "1" ] && exit 0

LOG="${POST_COMPACT_LOG:-$HOME/.claude/logs/post-compact.jsonl}"
MAX_BYTES="${POST_COMPACT_MAX_BYTES:-1048576}"     # 1 MiB — a row is ~400 B and compaction is rare
HEAD_CHARS="${POST_COMPACT_HEAD_CHARS:-160}"       # enough to recognise a summary, never to reuse it
case "$MAX_BYTES"  in ''|*[!0-9]*) MAX_BYTES=1048576 ;; esac
case "$HEAD_CHARS" in ''|*[!0-9]*) HEAD_CHARS=160 ;; esac

IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0

LOGDIR="${LOG%/*}"
ensure_dir() { [ -d "$LOGDIR" ] || mkdir -p "$LOGDIR" 2>/dev/null || true; }

abstain() {
  local ts
  ensure_dir
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')"
  printf '{"ts":"%s","hook":"post-compact","abstain":"%s"}\n' "$ts" "$1" >> "$LOG" 2>/dev/null || true
  exit 0
}

command -v jq >/dev/null 2>&1 || abstain "no-jq"

# The event gate first, and on its own, because everything after it costs a fork. A payload from any
# other event leaves this handler having spent one jq and written nothing.
printf '%s' "$INPUT" | jq -e '.hook_event_name == "PostCompact"' >/dev/null 2>&1 || {
  if ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then abstain "malformed-json"; fi
  exit 0
}

# The summary is streamed to the sha tool, never held in a shell variable: `$(...)` on a 22 KB value
# is affordable, but the same code meeting a 2 MB summary would not be, and the size of this field
# is not ours to bound. `shasum -a 256` (BSD) then `sha256sum` (GNU); a box with neither records
# `sha:"-"` rather than a fabricated digest.
SUM="-"
if command -v shasum >/dev/null 2>&1; then
  SUM="$(printf '%s' "$INPUT" | jq -j '.compact_summary // ""' 2>/dev/null | shasum -a 256 2>/dev/null | cut -c1-16)"
elif command -v sha256sum >/dev/null 2>&1; then
  SUM="$(printf '%s' "$INPUT" | jq -j '.compact_summary // ""' 2>/dev/null | sha256sum 2>/dev/null | cut -c1-16)"
fi
[ -n "$SUM" ] || SUM="-"

# `.[0:$hc]` on the summary is the ONLY place the body is touched, and it is bounded before it can
# reach the row. jq-encoded end to end, so a summary carrying a quote, a backslash or a newline
# cannot shred the line — one malformed line aborts a downstream `jq -s` slurp, which reads as
# "no compactions ever happened".
ROW="$(printf '%s' "$INPUT" | jq -c --argjson hc "$HEAD_CHARS" --arg sha "$SUM" '
    (.compact_summary // "" | tostring) as $s
  | { ts:            (now | todate),
      hook:          "post-compact",
      sid:           (.session_id // "-"),
      trigger:       (.trigger // "-"),
      summary_chars: ($s | length),
      summary_sha:   $sha,
      summary_head:  ($s | .[0:$hc]),
      cwd:           (.cwd // "-"),
      transcript:    (.transcript_path // "-") }
' 2>/dev/null)" || ROW=""

[ -n "$ROW" ] || exit 0
case "$ROW" in '{'*) ;; *) exit 0 ;; esac

ensure_dir
SIZE="$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)"
case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
if [ "$SIZE" -ge "$MAX_BYTES" ]; then mv -f "$LOG" "$LOG.1" 2>/dev/null || true; fi

printf '%s\n' "$ROW" >> "$LOG" 2>/dev/null || true
exit 0
