#!/usr/bin/env bats
# goal-state INCREMENTAL SCAN — goal_live_condition caches its verdict beside the byte offset it
# covers and greps only the bytes appended since (docs/research/load-hook-timeouts-2026-10-11/
# DESIGN.md item 6). The contract under test is the one every consumer relies on: the answer is
# IDENTICAL to a full scan, whatever happened to the file between calls.
#
# Three readers are compared at every step:
#   inc    — the subject, cache on (floor and write threshold at 0, so every call caches)
#   full   — the same lib with the cache switched off (CC_GOAL_SCAN_CACHE=0)
#   legacy — the pre-change algorithm, copied verbatim below, as the independent reference
# Run under /bin/bash (3.2 on macOS) with `set -uo pipefail`, which is how the hooks run it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/goal-state.sh"
  D="$BATS_TEST_TMPDIR"
  T="$D/t.jsonl"
  export CC_GOAL_SCAN_DIR="$D/scan"
  export CC_GOAL_SCAN_MIN_BYTES=0 CC_GOAL_SCAN_WRITE_BYTES=0
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

arm_rec()   { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"%s"}}\n' "$1"; }
unmet_rec() { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"condition":"%s","reason":"open"}}\n' "$1"; }
met_rec()   { printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"%s","iterations":2}}\n' "$1"; }
fail_rec()  { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"failed":true,"condition":"%s"}}\n' "$1"; }
prose()     { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"a goal_status \\"type\\":\\"goal_status\\" decoy"}]}}\n'; }
filler()    { local i; for i in $(seq 1 "${1:-20}"); do printf '{"type":"user","message":{"content":"filler line %s"}}\n' "$i"; done; }

inc()  { /bin/bash -c 'set -uo pipefail; . "$1"; goal_live_condition "$2"' _ "$LIB" "$1"; }
full() { CC_GOAL_SCAN_CACHE=0 /bin/bash -c 'set -uo pipefail; . "$1"; goal_live_condition "$2"' _ "$LIB" "$1"; }
legacy() { # the pre-change goal_live_condition, verbatim apart from the name
  /bin/bash -c '
    rec="$(grep -a goal_status "$1" 2>/dev/null | jq -rc --slurp "
      [ .[] | select(.type == \"attachment\") | .attachment | select(.type == \"goal_status\") ] | last // empty" 2>/dev/null)" || exit 1
    [ -n "$rec" ] || exit 1
    [ "$(printf "%s" "$rec" | jq -r "(.met // false) or (.failed // false)" 2>/dev/null)" = "false" ] || exit 1
    printf "%s" "$(printf "%s" "$rec" | jq -r ".condition // \"\"" 2>/dev/null)"' _ "$1"
}
verdict() { local o rc; o="$("$1" "$2")"; rc=$?; printf 'rc=%s out=[%s]' "$rc" "$o"; }

# All three readers agree on $T, and the subject answered from its cache (the file exists and
# names this transcript). Prints the verdict on mismatch so a red names the step.
agree() {
  local a b c
  a="$(verdict inc "$T")"; b="$(verdict full "$T")"; c="$(verdict legacy "$T")"
  [ "$a" = "$b" ] && [ "$b" = "$c" ] || { echo "step ${1:-?}: inc $a | full $b | legacy $c" >&2; return 1; }
  [ "$(head -n1 "$CC_GOAL_SCAN_DIR"/*.scan)" = "$T" ] || { echo "step ${1:-?}: no cache for $T" >&2; return 1; }
}
cached_offset() { sed -n '2p' "$CC_GOAL_SCAN_DIR"/*.scan | awk '{print $2}'; }
file_size() { wc -c < "$1" | tr -d ' '; }
inode() { ls -i "$1" | awk '{print $1}'; }

@test "append: the incremental answer equals a full scan after every append" {
  { prose; filler 30; } > "$T";                agree 1 || false
  arm_rec "ship the first goal" >> "$T";       agree 2 || false
  { filler 10; prose; } >> "$T";               agree 3 || false   # tail with no goal record: cache stands
  unmet_rec "ship the first goal" >> "$T";     agree 4 || false
  met_rec "ship the first goal" >> "$T";       agree 5 || false   # achieved ⇒ not live
  filler 5 >> "$T";                            agree 6 || false
  arm_rec "then the second" >> "$T";           agree 7 || false   # re-armed ⇒ live again
  agree 8 || false                                                # no growth: answered from the cache alone
  fail_rec "then the second" >> "$T";          agree 9 || false
  [ "$(inc "$T"; echo "rc=$?")" = "rc=1" ] || false
}

@test "append: a call reads only the bytes past the cached offset" {
  { filler 40; arm_rec "watch the tail"; } > "$T"
  inc "$T" >/dev/null
  off="$(cached_offset)"; [ "$off" -eq "$(file_size "$T")" ] || false
  filler 3 >> "$T"
  # a tail stub on PATH logs its byte argument and hands over to the real tail
  mkdir -p "$D/bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexec /usr/bin/tail "$@"\n' "$D/tail.log" > "$D/bin/tail"
  chmod +x "$D/bin/tail"
  run env PATH="$D/bin:$PATH" /bin/bash -c 'set -uo pipefail; . "$1"; goal_live_condition "$2"' _ "$LIB" "$T"
  [ "$status" -eq 0 ] && [ "$output" = "watch the tail" ] || false
  grep -qx -- "-c +$(( off + 1 )) $T" "$D/tail.log" || { cat "$D/tail.log" >&2; false; }
  [ "$(cached_offset)" -eq "$(file_size "$T")" ] || false
}

@test "TRUNCATION: a file shorter than the cached offset is rescanned from byte 0" {
  { filler 60; arm_rec "the long first goal"; } > "$T"
  agree 1 || false
  ino="$(inode "$T")"; off="$(cached_offset)"
  # truncate IN PLACE (same inode) to something shorter that carries a different goal
  { arm_rec "short second"; } > "$T"
  [ "$(inode "$T")" = "$ino" ] || false                 # only the size check can see this
  [ "$(file_size "$T")" -lt "$off" ] || false
  agree 2 || false
  [ "$(inc "$T")" = "short second" ] || false
  # and the rescan re-based the cache, so appends after it are incremental again
  met_rec "short second" >> "$T";              agree 3 || false
}

@test "REWRITE: a transcript replaced by a new file is rescanned even when it is larger" {
  { filler 5; arm_rec "old goal"; } > "$T"
  agree 1 || false
  off="$(cached_offset)"
  { filler 80; met_rec "old goal"; arm_rec "new goal"; } > "$D/new.jsonl"
  mv -f "$D/new.jsonl" "$T"
  [ "$(file_size "$T")" -gt "$off" ] || false           # the size check alone cannot see this one
  agree 2 || false
  [ "$(inc "$T")" = "new goal" ] || false
}

@test "FRAGMENT: a scan that resumes inside a line falls back to the full scan" {
  # the cached offset lands mid-record: the writer had flushed only the record's head
  { filler 5; printf '{"type":"attachment","attachment":'; } > "$T"
  agree 1 || false
  printf '{"type":"goal_status","met":false,"sentinel":true,"condition":"split record"}}\n' >> "$T"
  agree 2 || false
  [ "$(inc "$T")" = "split record" ] || false
}

@test "a corrupt goal record is rc 1 on the incremental path too (never live)" {
  { arm_rec "finish"; } > "$T"
  agree 1 || false
  printf '{"type":"attachment","attachment":{"type":"goal_status"\n' >> "$T"
  run inc "$T"
  [ "$status" -eq 1 ] && [ -z "$output" ] || false
  [ "$(verdict full "$T")" = "$(verdict legacy "$T")" ] || false
}

@test "a TAB/newline condition comes back byte-identical, from the scan and from the cache" {
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"a\\tb\\nc  "}}\n' > "$T"
  agree 1 || false
  agree 2 || false                                      # second call: no growth, cache only
  [ "$(inc "$T")" = "$(printf 'a\tb\nc  ')" ] || false
}

@test "a cache naming another transcript is not trusted" {
  { arm_rec "real goal"; } > "$T"
  inc "$T" >/dev/null
  cf="$(ls "$CC_GOAL_SCAN_DIR"/*.scan)"
  printf '%s\n%s %s live\nforged goal' "$D/other.jsonl" "$(inode "$T")" "$(file_size "$T")" > "$cf"
  [ "$(inc "$T")" = "real goal" ] || false
}

@test "below the size floor nothing is cached (small transcripts scan whole)" {
  unset CC_GOAL_SCAN_MIN_BYTES
  { arm_rec "small"; } > "$T"
  [ "$(inc "$T")" = "small" ] || false
  [ ! -e "$CC_GOAL_SCAN_DIR" ] || false
}
