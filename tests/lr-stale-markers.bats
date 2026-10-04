#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# STALE HANDOFF MARKERS — set aside, never deleted (2026-10-04).
# Subjects: scripts/limit-recover/lr-upgrade.sh (--stale-markers classifier · kind marker-setaside in
#           the drain · --marker-drive), bin/cc-lr repair-markers, scripts/limit-recover/lr-transplant.sh
#           (the confirm-time target sweep and the round-trip retired copy).
#
# THE SHAPE (live, read-only): 762a6daa's LIVE transcript is in tertiary beside an OLD marker pointing
# at quaternary (2026-10-03T02:28:25Z), while quaternary holds only a retired copy and a NEWER marker
# pointing back (2026-10-04T17:09:35Z) — a round trip nothing swept. hooks/handed-off-session-guard.sh
# then refused every prompt in the live pane (exit 2). Beside the live copy also sits the first
# departure's `.jsonl.handed-off`, an exact byte prefix of it, which made every later confirm off that
# store refuse stub-beside-retired. Auto mode refuses an agent renaming under ~/.claude*, so the rename
# is the launchd drainer's, requested by `cc-lr repair-markers`.
#
# Every unknown resolves to KEEP (the act is a rename), so the controls here matter as much as the
# positives: a GENUINE kept source (the target is live too) and a back-marker that is OLDER must never
# be touched — that is the 2026-08-16 split-brain guard staying armed.
#
# Hermetic: stores under a fixture $HOME, named by LR_CONFIG_DIRS; `ps` is a snapshot FILE; the real
# guard hook is run read-only against fixture stores; launchctl is a recorder.
bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  LRT="$REPO/scripts/limit-recover/lr-transplant.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover" LR_STATE_DIR="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh" LRU_GAP_S=0
  export LR_CONFIG_DIRS="$HOME/.claude-secondary:$HOME/.claude-tertiary:$HOME/.claude-quaternary"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s\n' "$BATS_TEST_TMPDIR/notify.log" > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  unset CLAUDE_CONFIG_DIR CC_HANDED_OFF_GUARD_DISABLED LRU_MARKER_SETASIDE LR_MARKER_SETASIDE LRT_STALE_SETASIDE CLAUDE_CODE_SESSION_ID
  mkdir -p "$HOME/.claude-secondary/projects" "$(SA)" "$(SB)"
}

LST="Tue Sep 22 06:47:13 2026"
MSID=762a6daa-0000-4000-8000-000000000001
SA() { printf '%s' "$HOME/.claude-tertiary/projects/-ci"; }     # A: where the session runs NOW (live)
SB() { printf '%s' "$HOME/.claude-quaternary/projects/-ci"; }   # B: the store it left, then came back from
tomb() { # <dir> <to-store> <ts> → the verbatim lr-transplant tombstone shape
  printf '{"handed_off_to":"%s","target_transcript":"%s","ts":"%s","lock":"%s","confirm_len":1}\n' \
    "$2" "$2/projects/-ci/$MSID.jsonl" "$3" "$LRU_STATE/locks/$MSID.lock" > "$1/$MSID.HANDOFF.json"
}
# stalefix <stale|legit|older-return> [retired: prefix|foreign]
stalefix() {
  printf '%s\n' '{"type":"user","message":{"content":"first"}}' > "$(SA)/$MSID.jsonl.handed-off"
  if [ "${2:-prefix}" = foreign ]; then printf '%s\n' '{"type":"user","message":{"content":"ELSEWHERE"}}' > "$(SA)/$MSID.jsonl.handed-off"; fi
  printf '%s\n%s\n' '{"type":"user","message":{"content":"first"}}' '{"type":"assistant","message":{"content":"back again"}}' > "$(SA)/$MSID.jsonl"
  tomb "$(SA)" "$HOME/.claude-quaternary" 2026-10-03T02:28:25Z
  case "$1" in
    stale)        echo '{}' > "$(SB)/$MSID.jsonl.handed-off"; tomb "$(SB)" "$HOME/.claude-tertiary" 2026-10-04T17:09:35Z ;;
    legit)        echo '{"type":"user"}' > "$(SB)/$MSID.jsonl" ;;                 # the forward move is real: B is live
    older-return) echo '{}' > "$(SB)/$MSID.jsonl.handed-off"; tomb "$(SB)" "$HOME/.claude-tertiary" 2026-10-02T00:00:00Z ;;
  esac
  cp -p "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/a-tomb.orig"
  cp -p "$(SA)/$MSID.jsonl" "$BATS_TEST_TMPDIR/a-live.orig"
  cp -p "$(SA)/$MSID.jsonl.handed-off" "$BATS_TEST_TMPDIR/a-ret.orig"
  [ ! -f "$(SB)/$MSID.HANDOFF.json" ] || cp -p "$(SB)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/b-tomb.orig"
}
guard() { # → the guard's exit status for a prompt in store A
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/tmp","prompt":"hi"}' "$MSID" "$(SA)/$MSID.jsonl" \
    | CLAUDE_CONFIG_DIR="$HOME/.claude-tertiary" bash "$REPO/hooks/handed-off-session-guard.sh" >/dev/null 2>&1
}
verdict_of() { printf '%s\n' "$output" | awk -F'\t' -v s="$MSID" '$1 == s { print $4 }' | head -1; }
mres() { jq -r ".$1" "$LRU_STATE/results/markers-$MSID.json"; }
queue_marker() {
  mkdir -p "$LRU_STATE/upgrade-queue"
  printf '{"kind":"marker-setaside","sid":"%s","requested_by":"999","req_id":"%s"}\n' "$MSID" "${1:-m1}" > "$LRU_STATE/upgrade-queue/m.json"
}

# ── the classifier ───────────────────────────────────────────────────────────────────────────────

@test "C1 [RED] the 762a6daa round trip is STALE, and its prefix-proven retired copy goes with it; CONTROL an OLDER back-marker is KEEP" {
  stalefix stale
  run bash "$LRU" --stale-markers
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | awk -F'\t' -v s="$MSID" '$1 == s { print $2 "|" $4 "|" $7 }')" = "$HOME/.claude-tertiary|STALE|STALE-RETIRED" ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ] || { echo "B's marker is not beside a live copy and must yield no row: $output"; false; }
  tomb "$(SB)" "$HOME/.claude-tertiary" 2026-10-02T00:00:00Z
  run bash "$LRU" --stale-markers "$MSID"
  [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"is not newer"* ]] || { echo "$output"; false; }
}

@test "C2 a GENUINE kept source (the target holds a live copy too, no marker back) is KEEP" {
  stalefix legit
  run bash "$LRU" --stale-markers
  [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"also holds a live copy"* ]] || { echo "$output"; false; }
}

@test "C3 a live holder under the target keeps it — sessions file with a matching procStart, or a live registry row on its account; a recycled pid does not" {
  stalefix stale
  mkdir -p "$HOME/.claude-quaternary/sessions"
  printf '%d 1 %s %s\n' 64001 "$LST" '/opt/cc/claude --resume x' >> "$LRU_PS_SNAPSHOT"
  # procStart in ps's padded form ("Sep 22  06:…"): compared space-collapsed, so it is the same instant
  printf '{"pid":64001,"sessionId":"%s","procStart":"%s"}\n' "$MSID" "Tue Sep 22  06:47:13 2026" > "$HOME/.claude-quaternary/sessions/64001.json"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"pid 64001"* ]] || { echo "$output"; false; }
  # CONTROL: the same pid number started at another instant is not that holder
  printf '{"pid":64001,"sessionId":"%s","procStart":"Mon Sep 21 01:00:00 2026"}\n' "$MSID" > "$HOME/.claude-quaternary/sessions/64001.json"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = STALE ] || { echo "$output"; false; }
  rm -f "$HOME/.claude-quaternary/sessions/64001.json"
  printf '{"paneUUID":"20","pid":64001,"session_id":"%s","account":"claude-quaternary"}\n' "$MSID" > "$LRU_REG_DIR/20.json"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"registry row on claude-quaternary"* ]] || { echo "$output"; false; }
}

@test "C4 a --resume process no S-side record accounts for keeps it; one the registry puts on S does not" {
  stalefix stale
  printf '%d 1 %s %s\n' 64002 "$LST" "/opt/cc/.claude-284/node_modules/.bin/claude --resume $MSID" >> "$LRU_PS_SNAPSHOT"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"unattributed claude --resume process (pid 64002)"* ]] || { echo "$output"; false; }
  printf '{"paneUUID":"20","pid":64002,"session_id":"%s","account":"claude-tertiary"}\n' "$MSID" > "$LRU_REG_DIR/20.json"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = STALE ] || { echo "$output"; false; }
}

@test "C5 the custody lock: naming the target keeps it; absent, naming S, or a pre-W5-B lock whose only 'to' is S are all STALE" {
  stalefix stale
  mkdir -p "$LRU_STATE/locks"
  printf '{"to":"%s","owner":"%s"}\n' "$HOME/.claude-quaternary" "$HOME/.claude-quaternary" > "$LRU_STATE/locks/$MSID.lock"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"custody lock names"* ]] || { echo "$output"; false; }
  printf '{"to":"%s","owner":"%s"}\n' "$HOME/.claude-tertiary" "$HOME/.claude-tertiary" > "$LRU_STATE/locks/$MSID.lock"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = STALE ] || { echo "$output"; false; }
  printf '{"to":"%s"}\n' "$HOME/.claude-tertiary" > "$LRU_STATE/locks/$MSID.lock"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = STALE ] || { echo "$output"; false; }
}

@test "C6 a malformed or EQUAL ts is KEEP; a same-account marker (naming its own store) yields no row" {
  stalefix stale
  tomb "$(SB)" "$HOME/.claude-tertiary" 2026-10-03T02:28:25Z
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = KEEP ] || { echo "$output"; false; }
  tomb "$(SB)" "$HOME/.claude-tertiary" "Sat Oct 4 17:09:35 2026"
  run bash "$LRU" --stale-markers; [ "$(verdict_of)" = KEEP ] && [[ "$output" == *"malformed"* ]] || { echo "$output"; false; }
  tomb "$(SA)" "$HOME/.claude-tertiary" 2026-10-03T02:28:25Z
  run bash "$LRU" --stale-markers; [ -z "$output" ] || { echo "$output"; false; }
}

# ── the drainer kind ─────────────────────────────────────────────────────────────────────────────

@test "D1 [RED] the drainer sets a stale marker aside (renamed, cmp-equal, never deleted), the guard then ADMITS the live pane; CONTROL a pane-less upgrade is still dropped as malformed" {
  stalefix stale
  guard && { echo "the fixture does not reproduce the block"; false; } || [ $? -eq 2 ]
  queue_marker d1
  run bash "$LRU" --drain
  [ "$(mres verdict)" = SETASIDE ] && [ "$(mres req_id)" = d1 ] || { echo "$output"; cat "$LRU_STATE/results/markers-$MSID.json"; false; }
  [ "$(mres guard_before)" = 2 ] && [ "$(mres guard_after)" = 0 ] || { cat "$LRU_STATE/results/markers-$MSID.json"; false; }
  [ ! -e "$(SA)/$MSID.HANDOFF.json" ] && [ ! -e "$(SA)/$MSID.jsonl.handed-off" ] || { ls -a "$(SA)"; false; }
  set -- "$(SA)/$MSID.HANDOFF.json.stale-"*;        cmp -s "$1" "$BATS_TEST_TMPDIR/a-tomb.orig" || { ls -a "$(SA)"; false; }
  set -- "$(SA)/$MSID.jsonl.handed-off.stale-"*;    cmp -s "$1" "$BATS_TEST_TMPDIR/a-ret.orig" || { ls -a "$(SA)"; false; }
  cmp -s "$(SA)/$MSID.jsonl" "$BATS_TEST_TMPDIR/a-live.orig" && cmp -s "$(SB)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/b-tomb.orig" || false
  guard || { echo "the guard still refuses"; false; }
  grep -q "^999 CC-LR-MARKERS 762a6daa: verdict=SETASIDE" "$BATS_TEST_TMPDIR/notify.log" || { cat "$BATS_TEST_TMPDIR/notify.log"; false; }
  # CONTROL: the pane-less exemption is the marker kind's alone
  printf '{"kind":"upgrade","sid":"%s","requested_by":"999"}\n' "$MSID" > "$LRU_STATE/upgrade-queue/u.json"
  run bash "$LRU" --drain
  [[ "$output" == *"malformed request"*"no sid/pane"* ]] || { echo "$output"; false; }
}

@test "D2 CONTROL a legit forward move and an older back-marker: NOTHING, nothing renamed, the guard still refuses" {
  stalefix legit
  queue_marker; run bash "$LRU" --drain
  [ "$(mres verdict)" = NOTHING ] || { cat "$LRU_STATE/results/markers-$MSID.json"; false; }
  cmp -s "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/a-tomb.orig" || false
  [ -z "$(find "$HOME" -name '*.stale-*')" ] || { find "$HOME" -name '*.stale-*'; false; }
  guard && false || [ $? -eq 2 ]
  rm -f "$(SB)/$MSID.jsonl"; stalefix older-return
  queue_marker; run bash "$LRU" --drain
  [ "$(mres verdict)" = NOTHING ] && [ -z "$(find "$HOME" -name '*.stale-*')" ] || { cat "$LRU_STATE/results/markers-$MSID.json"; false; }
}

@test "D3 a retired copy that is NOT a prefix of the live one holds bytes the live one lacks: the marker goes, the copy is kept and named" {
  stalefix stale foreign
  run bash "$LRU" --marker-drive "$MSID" --requested-by 999 --req-id d3
  [ "$status" -eq 0 ] && [ "$(mres verdict)" = SETASIDE ] || { echo "$output"; false; }
  cmp -s "$(SA)/$MSID.jsonl.handed-off" "$BATS_TEST_TMPDIR/a-ret.orig" || { echo "a non-prefix retired copy was moved"; false; }
  [ "$(mres 'kept[0]')" = "$(SA)/$MSID.jsonl.handed-off" ] || { cat "$LRU_STATE/results/markers-$MSID.json"; false; }
}

@test "D4 kill switches (env and file) rename nothing; without them it renames; a second run finds NOTHING" {
  stalefix stale
  LRU_MARKER_SETASIDE=off run bash "$LRU" --marker-drive "$MSID"
  [ "$status" -eq 3 ] && [ "$(mres verdict)" = KEPT ] || { echo "$output"; false; }
  touch "$LRU_STATE/marker-setaside.off"
  run bash "$LRU" --marker-drive "$MSID"
  [ "$status" -eq 3 ] && [ -z "$(find "$HOME" -name '*.stale-*')" ] || { echo "$output"; false; }
  rm -f "$LRU_STATE/marker-setaside.off"
  run bash "$LRU" --marker-drive "$MSID"
  [ "$status" -eq 0 ] && [ "$(mres verdict)" = SETASIDE ] || { echo "$output"; false; }
  run bash "$LRU" --marker-drive "$MSID"
  [ "$status" -eq 0 ] && [ "$(mres verdict)" = NOTHING ] || { echo "$output"; false; }
}

# ── cc-lr repair-markers ─────────────────────────────────────────────────────────────────────────

@test "R1 [RED] cc-lr repair-markers: --dry-run writes nothing; the real run queues ONE request per STALE sid (none for KEEP) straight into the drainer's queue, and the drainer's verdict closes it" {
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl.log" > "$STUBS/launchctl"; chmod +x "$STUBS/launchctl"
  export PATH="$STUBS:$PATH" CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999
  stalefix stale
  # a second session whose marker is a genuine kept source: KEEP, never queued
  K=7193ec2b-0000-4000-8000-000000000001
  printf '{}\n' > "$(SA)/$K.jsonl"; printf '{}\n' > "$(SB)/$K.jsonl"
  printf '{"handed_off_to":"%s","ts":"2026-10-01T00:00:00Z"}\n' "$HOME/.claude-quaternary" > "$(SA)/$K.HANDOFF.json"
  run bash "$REPO/bin/cc-lr" repair-markers --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^STALE 762a6daa ' && printf '%s\n' "$output" | grep -q '^KEEP  7193ec2b ' || { echo "$output"; false; }
  [[ "$output" == *"1 stale marker(s) · DRY RUN"* ]] && [ -z "$(ls -A "$LRU_STATE/upgrade-queue" 2>/dev/null)" ] || { echo "$output"; false; }
  CC_LR_MARKERS_WAIT_S=0 run bash "$REPO/bin/cc-lr" repair-markers
  [ "$status" -eq 1 ] && [[ "$output" == *"pending  762a6daa"* ]] || { echo "$output"; false; }
  [ "$(ls "$LRU_STATE/upgrade-queue")" = "cc-lr-markers-$MSID.json" ] || { ls "$LRU_STATE/upgrade-queue"; false; }
  [ "$(jq -r '.kind + " " + .sid + " " + .requested_by' "$LRU_STATE/upgrade-queue/cc-lr-markers-$MSID.json")" = "marker-setaside $MSID 999" ] || false
  grep -q '^kickstart gui/' "$BATS_TEST_TMPDIR/launchctl.log" && ! grep -q -- '-k' "$BATS_TEST_TMPDIR/launchctl.log" || { cat "$BATS_TEST_TMPDIR/launchctl.log"; false; }
  [ -f "$(SA)/$MSID.HANDOFF.json" ] || { echo "cc-lr renamed something itself"; false; }
  run bash "$LRU" --drain
  [ "$(mres verdict)" = SETASIDE ] || { echo "$output"; false; }
  [ "$(mres req_id)" = "$(jq -r .req_id "$LRU_STATE/claimed/cc-lr-markers-$MSID.json")" ] || false
}

@test "R2 cc-lr repair-markers refuses a malformed --sid and an ambiguous prefix; a sid with nothing beside a live copy is a clean no-op" {
  export CC_LR_UPGRADE_BIN="$LRU"
  run bash "$REPO/bin/cc-lr" repair-markers --sid 'x;rm'
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  stalefix stale
  M2=762a6dab-0000-4000-8000-000000000001
  printf '{}\n' > "$(SA)/$M2.jsonl"; printf '{"handed_off_to":"%s","ts":"2026-10-01T00:00:00Z"}\n' "$HOME/.claude-quaternary" > "$(SA)/$M2.HANDOFF.json"
  run bash "$REPO/bin/cc-lr" repair-markers --sid 762a6da --dry-run
  [ "$status" -eq 2 ] && [[ "$output" == *"more than one session"* ]] || { echo "$output"; false; }
  run bash "$REPO/bin/cc-lr" repair-markers --sid abcdef12 --dry-run
  [ "$status" -eq 0 ] && [[ "$output" == *"nothing to repair"* ]] || { echo "$output"; false; }
}

# ── lr-transplant stops producing the state ──────────────────────────────────────────────────────
# A move quaternary → tertiary of a session that LEFT tertiary earlier: tertiary still holds the old
# marker (→ quaternary) and the old retired copy, a prefix of what is about to land there.
lrtfix() {
  printf '%s\n' '{"type":"user","message":{"content":"first"}}' > "$(SA)/$MSID.jsonl.handed-off"
  tomb "$(SA)" "$HOME/.claude-quaternary" 2026-10-03T02:28:25Z
  printf '%s\n%s\n' '{"type":"user","message":{"content":"first"}}' '{"type":"assistant","message":{"content":"on q"}}' > "$(SB)/$MSID.jsonl"
}
lrt() { run --separate-stderr bash "$LRT" --sid "$MSID" --from "$HOME/.claude-quaternary" --to "$HOME/.claude-tertiary" "$@"; }

@test "X1 [RED] confirm sweeps the TARGET: its older marker and its prefix-proven retired copy go aside, and the successor's prompt is admitted; CONTROL LRT_STALE_SETASIDE=off leaves both and the guard refuses" {
  lrtfix
  lrt --phase admit; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ -f "$(SA)/$MSID.HANDOFF.json" ] || { echo "admit must not sweep the target"; false; }
  lrt --phase confirm; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ ! -e "$(SA)/$MSID.HANDOFF.json" ] && [ ! -e "$(SA)/$MSID.jsonl.handed-off" ] || { ls -a "$(SA)"; false; }
  [ "$(printf '%s' "$output" | jq '.set_aside | length')" -eq 2 ] || { echo "$output"; false; }
  guard || { echo "the successor's prompt is still refused"; false; }
  # CONTROL, a second session id on the same shape
  MSID=762a6daa-0000-4000-8000-000000000002; lrtfix
  LRT_STALE_SETASIDE=off lrt --phase admit; LRT_STALE_SETASIDE=off lrt --phase confirm
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ -f "$(SA)/$MSID.HANDOFF.json" ] && [ "$(printf '%s' "$output" | jq 'has("set_aside")')" = false ] || { echo "$output"; false; }
  guard && false || [ $? -eq 2 ]
}

@test "X2 a target marker naming the TARGET itself is untouched; an aborted admit leaves the target's marker; an ordinary receipt has no set_aside key" {
  printf '%s\n' '{"type":"user"}' > "$(SB)/$MSID.jsonl"
  printf '{"handed_off_to":"%s","ts":"2026-10-01T00:00:00Z","superseded_by_pid":1}\n' "$HOME/.claude-tertiary" > "$(SA)/$MSID.HANDOFF.json"
  cp -p "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/self.orig"
  lrt --phase admit; lrt --phase confirm
  [ "$status" -eq 0 ] && cmp -s "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/self.orig" || { echo "$output $stderr"; false; }
  [ "$(printf '%s' "$output" | jq 'has("set_aside")')" = false ] || { echo "$output"; false; }
  MSID=762a6daa-0000-4000-8000-000000000003; lrtfix
  lrt --phase admit; lrt --phase abort
  [ -f "$(SA)/$MSID.HANDOFF.json" ] || { echo "abort lost the target's marker: $output $stderr"; false; }
}

@test "X3 [RED] a SOURCE whose old retired copy is a prefix of its live one confirms (no stub-beside-retired) and lists it set aside; CONTROL a genuine stub still refuses, byte-identical" {
  # the 762a6daa store itself moving on: live jsonl beside the first departure's prefix copy
  printf '%s\n' '{"type":"user","message":{"content":"first"}}' > "$(SB)/$MSID.jsonl.handed-off"
  printf '%s\n%s\n' '{"type":"user","message":{"content":"first"}}' '{"type":"assistant","message":{"content":"more"}}' > "$(SB)/$MSID.jsonl"
  # the admit arm would already set it aside; switched off there, the confirm arm is the one under test
  LRT_STALE_SETASIDE=off lrt --phase admit; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ -f "$(SB)/$MSID.jsonl.handed-off" ] || false
  # RED: without the arm, confirm refuses this source outright
  LRT_STALE_SETASIDE=off lrt --phase confirm
  [ "$status" -eq 2 ] && [[ "$stderr" == *"REFUSED (stub-beside-retired)"* ]] || { echo "$output $stderr"; false; }
  lrt --phase confirm
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  # FROM is resolved physically by lr-transplant (/private/var…), so match the store-relative tail
  [[ "$(printf '%s' "$output" | jq -r '.set_aside[]')" == *"/.claude-quaternary/projects/-ci/$MSID.jsonl.handed-off.stale-"* ]] || { echo "$output"; false; }
  [ -f "$(SB)/$MSID.jsonl.handed-off" ] && [ ! -e "$(SB)/$MSID.jsonl" ] || { ls -a "$(SB)"; false; }
  # the admit arm, on a fresh sid: the source's prefix copy is set aside before the tombstone
  MSID=762a6daa-0000-4000-8000-000000000005
  printf '%s\n' '{"type":"user","message":{"content":"first"}}' > "$(SB)/$MSID.jsonl.handed-off"
  printf '%s\n%s\n' '{"type":"user","message":{"content":"first"}}' '{"type":"assistant","message":{"content":"more"}}' > "$(SB)/$MSID.jsonl"
  lrt --phase admit
  [ "$status" -eq 0 ] && [ "$(printf '%s' "$output" | jq '.set_aside | length')" -eq 1 ] && [ ! -e "$(SB)/$MSID.jsonl.handed-off" ] || { echo "$output $stderr"; false; }
  # CONTROL: a stub (bytes written after the retire, not a superset of it) still refuses
  MSID=762a6daa-0000-4000-8000-000000000004
  printf '%s\n%s\n' '{"type":"user","uuid":"a1"}' '{"type":"assistant","uuid":"a2"}' > "$(SB)/$MSID.jsonl.handed-off"
  printf '%s\n' '{"type":"assistant","uuid":"tail1"}' > "$(SB)/$MSID.jsonl"
  local before; before="$(shasum "$(SB)/$MSID.jsonl" "$(SB)/$MSID.jsonl.handed-off")"
  lrt --phase confirm
  [ "$status" -eq 2 ] && [[ "$stderr" == *"REFUSED (stub-beside-retired)"* ]] || { echo "$output $stderr"; false; }
  [ "$(shasum "$(SB)/$MSID.jsonl" "$(SB)/$MSID.jsonl.handed-off")" = "$before" ] || false
}

@test "X4 an already-confirmed re-run heals a target the first confirm left (the pre-sweep state)" {
  lrtfix
  LRT_STALE_SETASIDE=off lrt --phase admit; LRT_STALE_SETASIDE=off lrt --phase confirm
  [ -f "$(SA)/$MSID.HANDOFF.json" ] || false
  lrt --phase confirm
  [ "$status" -eq 0 ] && [ "$(printf '%s' "$output" | jq -r .already_confirmed)" = true ] || { echo "$output $stderr"; false; }
  [ ! -e "$(SA)/$MSID.HANDOFF.json" ] && [ "$(printf '%s' "$output" | jq '.set_aside | length')" -eq 2 ] || { echo "$output"; ls -a "$(SA)"; false; }
}

@test "X5 [RED] a stale re-run of an OLD confirm never sweeps a LATER move's tombstone: Q->T confirmed, T->S --keep-source, then Q->T confirm again leaves T's tombstone and the guard in T still refuses (X4 is the control)" {
  # REVIEW REPRO-3. T stays live after the keep-source move; its tombstone is the only guard there.
  printf '%s\n%s\n' '{"type":"user","message":{"content":"first"}}' '{"type":"assistant","message":{"content":"on q"}}' > "$(SB)/$MSID.jsonl"
  lrt --phase admit; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  lrt --phase confirm; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  run --separate-stderr bash "$LRT" --sid "$MSID" --from "$HOME/.claude-tertiary" --to "$HOME/.claude-secondary" --keep-source
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ -f "$(SA)/$MSID.jsonl" ] && [ -f "$(SA)/$MSID.HANDOFF.json" ] || { ls -a "$(SA)"; false; }
  cp -p "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/t-tomb.orig"
  rc=0; guard || rc=$?; [ "$rc" -eq 2 ] || { echo "the guard in T should refuse before the re-run (rc $rc)"; false; }
  lrt --phase confirm
  [ "$status" -eq 0 ] && [ "$(printf '%s' "$output" | jq -r .already_confirmed)" = true ] || { echo "$output $stderr"; false; }
  cmp -s "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/t-tomb.orig" || { ls -a "$(SA)"; echo "$output $stderr"; false; }
  [ "$(printf '%s' "$output" | jq 'has("set_aside")')" = false ] || { echo "$output"; false; }
  rc=0; guard || rc=$?; [ "$rc" -eq 2 ] || { echo "two live writable copies: the guard in T now admits (rc $rc)"; false; }
  # EACH GUARD ALONE (the lock is edited so the other two pass): ‹lockset owner ts›
  local S2="$HOME/.claude-secondary/projects/-ci"
  lockset() { jq -c --arg o "$1" --arg ts "$2" '.owner = $o | .to = $o | .ts = $ts' "$LRU_STATE/locks/$MSID.lock" > "$BATS_TEST_TMPDIR/l" \
                && mv "$BATS_TEST_TMPDIR/l" "$LRU_STATE/locks/$MSID.lock"; }
  # 1. custody: S's copy moved on (no live copy there), the lock is newer than T's marker, but a
  #    later move owns the lock — the stale run holds no custody and sweeps nothing
  mv "$S2/$MSID.jsonl" "$S2/$MSID.jsonl.moved"
  lockset "$HOME/.claude-secondary" 2099-01-01T00:00:00Z
  lrt --phase confirm
  cmp -s "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/t-tomb.orig" || { echo "custody guard: $output $stderr"; false; }
  # 2. the named store's live copy: custody handed back to T, lock newer, S live again
  mv "$S2/$MSID.jsonl.moved" "$S2/$MSID.jsonl"
  lockset "$HOME/.claude-tertiary" 2099-01-01T00:00:00Z
  lrt --phase confirm
  cmp -s "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/t-tomb.orig" || { echo "live-copy guard: $output $stderr"; false; }
  [[ "$stderr" == *"kept the target marker"*"holds a live copy"* ]] || { echo "$stderr"; false; }
  # 3. the ts: custody T, S not live, but the marker is not older than this move's lock
  mv "$S2/$MSID.jsonl" "$S2/$MSID.jsonl.moved"
  lockset "$HOME/.claude-tertiary" 2000-01-01T00:00:00Z
  lrt --phase confirm
  cmp -s "$(SA)/$MSID.HANDOFF.json" "$BATS_TEST_TMPDIR/t-tomb.orig" || { echo "ts guard: $output $stderr"; false; }
  [[ "$stderr" == *"not provably older than this move"* ]] || { echo "$stderr"; false; }
  # and with all three satisfied the re-run does heal (the X4 behaviour, on this same fixture)
  lockset "$HOME/.claude-tertiary" 2099-01-01T00:00:00Z
  lrt --phase confirm
  [ ! -e "$(SA)/$MSID.HANDOFF.json" ] || { echo "$output $stderr"; ls -a "$(SA)"; false; }
}
