#!/usr/bin/env bats
# waiting-recycle.sh — M13 BOUNDED TRANSCRIPT READS (docs/plans/MACHINE_CAPACITY_V2.md §11).
#
# WHAT IS UNDER TEST — exactly two extracted behaviors, nothing else in the 1067-line hook:
#   (a) the ROT-tell read (§4b): was a FULL `jq` pass over the whole transcript on EVERY PostToolUse
#       (~19× the Stop chain's rate; transcripts reach 3-5 MB — measured 438ms/call at 5.5 MB vs 24ms
#       bounded). Now `tail -c $CC_WR_TAIL_BYTES | jq -Rr 'fromjson?|objects|…'`.
#   (b) the S6 interactive-recency read: ce_last_interactive_age, handed CC_WR_TAIL_BYTES through the
#       lib's own CC_CE_TAIL_BYTES seam (the lib is owned elsewhere and is NOT modified here).
#   (c) the osascript page fork is bound by wrc_osa (grep-assert + positive control).
#
# THE CONTRACT BEING PINNED IS EQUIVALENCE, NOT SPEED: bounded output == unbounded output. Every case
# below therefore asserts the SAME verdict under the bounded default and under CC_WR_TAIL_BYTES=0
# (the incumbent unbounded read), and the fixtures are built so a NAIVE bound would visibly break:
#   • a tail window's FIRST line is usually a PARTIAL record and plain `jq -c` ABORTS THE WHOLE STREAM
#     on it (zero records emitted) ⇒ MSG blanks ⇒ the entire rot axis goes dark, silently.
#   • a single record LARGER than the window is invisible to the window ⇒ needs the unbounded fallback.
#   • an operator turn buried BEFORE the window must still hold S6 (the lib's whole-file re-scan).
#
# OBSERVABLES (no real recycle side effects — CC_WR_HANDOFF_FIRE is never armed, so Stage 2 cannot
# exec; every case here is a Stage-1 advisory, i.e. stdout only):
#   fire  = '"decision":"block"' on stdout.   hold/abstain = empty stdout, exit 0.
# used_pct is pinned BELOW T_IDLE for the (a) cases so the ONLY thing that can fire is the rot tell
# read by the site under test; the S6 cases pin it ABOVE T_IDLE so the only thing that can SUPPRESS
# the fire is the hold computed from the site-(b) read.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity ratchet: never the live ~/
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/waiting-recycle.sh"
  export CC_WR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  # Idle bar 55 (so used=40 can ONLY fire via a rot tell); busy ceiling 75; nudge OFF; forecast off.
  export CC_WR_T_IDLE=55 CC_WR_T_BUSY=75 CC_WR_AGE_MAX=180 CC_WR_T_NUDGE=101
  # COOLDOWN 0 + a generous cap: several cases drive the SAME cwd twice (bounded, then unbounded) and
  # the cwd-keyed cooldown / per-SID cap would otherwise silence the second half of the comparison.
  export CC_WR_COOLDOWN_S=0 CC_WR_MAX=9
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"; export CC_WR_UUID="DESK-UUID-M13"; export CC_WR_QUIET_S=180
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_STATE_DIR" "$CC_WR_COORD_DIR/wait-contracts" \
           "$CC_WR_COORD_DIR/mailbox" "$CC_WR_COORD_DIR/cc-roles" "$CLAUDE_CONFIG_DIR/teams"
  # No-op osascript-page stub so no case can pop a real OS notification.
  export CC_WR_NOTIFY="$BATS_TEST_TMPDIR/notify-noop.sh"; printf '#!/bin/bash\nexit 0\n' > "$CC_WR_NOTIFY"; chmod +x "$CC_WR_NOTIFY"
  DESK="$BATS_TEST_TMPDIR/desk"; mkdir -p "$DESK"
  git -C "$DESK" init -q
  git -C "$DESK" config user.email t@t; git -C "$DESK" config user.name t
  echo seed > "$DESK/f.txt"; git -C "$DESK" add -A; git -C "$DESK" commit -qm init
  ( cd "$DESK" && bash "$HOOK" arm >/dev/null )
}

ROT="Wait, which sessions did I fire again? Let me reconstruct the state."
WAIT="next3 is still running; next4 pinged done. Waiting on the rest."

iso_at() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%S.000Z; }
mk_tel() { printf '{"session_id":"%s","ts":%s,"used_pct":%s,"cwd":"%s"}' "$1" "$(date +%s)" "$2" "$DESK" > "$CC_TELEMETRY_DIR/$1.json"; }
# $1=sid $2=transcript $3=used_pct — ONE PostToolUse poll. Telemetry is minted per SID HERE, not once
# per test: every comparison drives a SECOND, fresh SID, and a SID with no telemetry file reads as
# fresh=0 ⇒ used=0 ⇒ neither the threshold nor the (freshness-floored) rot tell can fire. Minting it
# once per test would therefore have made the unbounded half of each comparison silently unfalsifiable.
drive() {
  mk_tel "$1" "$3"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","tool_input":{"command":"echo poll"}}' "$1" "$2" "$DESK" | bash "$HOOK"
}
fired() { printf '%s' "$1" | grep -q '"decision":"block"'; }

# One assistant JSONL record carrying $1 as its text.
asst() { jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}'; }
# A production-shaped OPERATOR turn (type:user + userType:external + isMeta:null + STRING content).
# The trailing \n is load-bearing: these fixtures append filler AFTER the turn, and without it the two
# records fuse into one unparseable line — the turn would vanish and the S6 cases would pass vacuously.
human() { printf '{"parentUuid":"p","isSidechain":false,"userType":"external","cwd":"/x","sessionId":"s","version":"2.1.207","type":"user","isMeta":null,"message":{"role":"user","content":"%s"},"uuid":"u","timestamp":"%s"}\n' "$2" "$(iso_at "$1")"; }

# $1=path $2=final assistant text [$3=lines of filler ≈277 B each] — a transcript whose LAST assistant
# record carries $2, preceded by enough filler to OVERFLOW the 256 KB window (default ≈440 KB: the
# contract only needs file > window, and this machine runs many suites at once — the headline 5.5 MB
# case passes 20000 explicitly rather than taxing every case with it).
mk_big() {
  local p="$1" txt="$2" n="${3:-1600}" filler
  filler="$(asst "filler $(printf 'x%.0s' {1..200})")"
  yes "$filler" | head -n "$n" > "$p"
  asst "$txt" >> "$p"
}

@test "small transcript (< window): bounded == unbounded — rot tell fires on both" {
  # 40 < T_IDLE=55 ⇒ ONLY a rot tell can fire
  local tx="$BATS_TEST_TMPDIR/small.jsonl"
  asst "$WAIT" > "$tx"; asst "$ROT" >> "$tx"
  run drive s1 "$tx" 40
  [ "$status" -eq 0 ]; fired "$output"
  CC_WR_TAIL_BYTES=0 run drive s1b "$tx" 40                # incumbent unbounded read
  [ "$status" -eq 0 ]; fired "$output"
}

@test "5 MB transcript: bounded == unbounded — the FINAL rot tell fires on both" {
  local tx="$BATS_TEST_TMPDIR/big.jsonl"; mk_big "$tx" "$ROT" 20000
  [ "$(wc -c < "$tx" | tr -d ' ')" -gt 5000000 ]
  run drive s2 "$tx" 40
  [ "$status" -eq 0 ]; fired "$output"
  CC_WR_TAIL_BYTES=0 run drive s2b "$tx" 40
  [ "$status" -eq 0 ]; fired "$output"
}

@test "5 MB transcript, BENIGN final: silent on both — the read takes the LAST record, not any in-window one" {
  local tx="$BATS_TEST_TMPDIR/buried.jsonl"
  asst "$ROT" > "$tx"                                   # a rot line buried at byte 0 must NOT fire…
  mk_big "$BATS_TEST_TMPDIR/tail.jsonl" "$WAIT"; cat "$BATS_TEST_TMPDIR/tail.jsonl" >> "$tx"
  run drive s3 "$tx" 40
  [ "$status" -eq 0 ]; [ -z "$output" ]
  CC_WR_TAIL_BYTES=0 run drive s3b "$tx" 40
  [ "$status" -eq 0 ]; [ -z "$output" ]
  # …POSITIVE CONTROL: the identical fixture with the rot line LAST does fire, so the silence above is
  # the last-record rule, not a dead observable.
  asst "$ROT" >> "$tx"
  run drive s3c "$tx" 40
  [ "$status" -eq 0 ]; fired "$output"
}

@test "PARTIAL first line in the window does not blank the read (plain jq -c would abort the stream)" {
  local tx="$BATS_TEST_TMPDIR/partial.jsonl" tailb
  asst "$(printf 'lead %s' "$(printf 'y%.0s' {1..900})")" > "$tx"   # a long first record…
  asst "$WAIT" >> "$tx"; asst "$ROT" >> "$tx"
  # …window sized to slice INTO it: last two records + 40 B, so the window opens mid-record.
  tailb=$(( $(wc -c < "$tx" | tr -d ' ') - 900 ))
  [ "$tailb" -gt 40 ]
  CC_WR_TAIL_BYTES="$tailb" run drive s4 "$tx" 40
  [ "$status" -eq 0 ]; fired "$output"
  # The window really was partial: its first line is not parseable on its own.
  run bash -c "tail -c $tailb '$tx' | head -1 | jq -e . >/dev/null 2>&1"
  [ "$status" -ne 0 ]
}

@test "pathological single 400 KB record (bigger than the window) falls back to the unbounded read" {
  local tx="$BATS_TEST_TMPDIR/huge.jsonl" pad
  pad="$(head -c 400000 /dev/zero | tr '\0' z)"
  # ROT text FIRST (the hook truncates MSG to 4000 chars), 400 KB of padding after, all ONE line.
  asst "$ROT $pad" > "$tx"
  [ "$(wc -l < "$tx" | tr -d ' ')" -eq 1 ]
  [ "$(wc -c < "$tx" | tr -d ' ')" -gt 262144 ]
  run drive s5 "$tx" 40                                    # default 256 KB window cannot see the record
  [ "$status" -eq 0 ]; fired "$output"
  CC_WR_TAIL_BYTES=0 run drive s5b "$tx" 40
  [ "$status" -eq 0 ]; fired "$output"
}

@test "CC_WR_TAIL_BYTES=0 / set-but-EMPTY / non-numeric all take the incumbent unbounded path" {
  # Asserted on the REAL seam lines lifted out of the hook, so a re-worded source fails LOUD here
  # rather than leaving a vacuous pass behind.
  local seam; seam="$(grep -n 'CC_WR_TAIL_BYTES+set' -A 1 "$HOOK" | sed -E 's/^[0-9]+[-:]//' | grep -v '^--$')"
  [ "$(printf '%s\n' "$seam" | grep -c .)" -eq 2 ]      # positive control: the extraction MATCHED
  probe() { printf '%s\nprintf %%s "$TAIL_B"\n' "$seam" | env "$@" bash -s; }
  [ "$(probe CC_WR_TAIL_BYTES=0)" = 0 ]                 # explicit 0 ⇒ full read
  [ "$(probe CC_WR_TAIL_BYTES=)" = 0 ]                  # set-but-empty ⇒ honoured verbatim
  [ "$(probe CC_WR_TAIL_BYTES=lots)" = 0 ]              # non-numeric ⇒ fail-safe to correctness
  [ "$(probe CC_WR_TAIL_BYTES=4096)" = 4096 ]
  [ "$(probe CC_WR_UNRELATED=1)" = 262144 ]             # unset ⇒ the 256 KB default
}

@test "each incumbent-path seam value still produces the correct verdict end-to-end" {
  local tx="$BATS_TEST_TMPDIR/seam.jsonl"; mk_big "$tx" "$ROT"
  CC_WR_TAIL_BYTES=0 run drive s6 "$tx" 40;      [ "$status" -eq 0 ]; fired "$output"
  CC_WR_TAIL_BYTES= run drive s6b "$tx" 40;      [ "$status" -eq 0 ]; fired "$output"
  CC_WR_TAIL_BYTES=lots run drive s6c "$tx" 40;  [ "$status" -eq 0 ]; fired "$output"
}

@test "no assistant record at all: silent + exit 0 on both paths (no fabricated tell)" {
  local tx="$BATS_TEST_TMPDIR/noasst.jsonl"
  human "$(( $(date +%s) - 99999 ))" "old prompt" > "$tx"
  run drive s7 "$tx" 40
  [ "$status" -eq 0 ]; [ -z "$output" ]
  CC_WR_TAIL_BYTES=0 run drive s7b "$tx" 40
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "S6: a FRESH operator turn buried before the window still HOLDS (lib whole-file re-scan survives the smaller window)" {
  # 60 ≥ T_IDLE=55 ⇒ fires unless S6 holds
  local tx="$BATS_TEST_TMPDIR/s6.jsonl" now; now="$(date +%s)"
  human "$(( now - 60 ))" "how is the wave going?" > "$tx"        # 60s old ⇒ well inside CONV_HOLD_S=900
  mk_big "$BATS_TEST_TMPDIR/t8.jsonl" "$WAIT"; cat "$BATS_TEST_TMPDIR/t8.jsonl" >> "$tx"
  run drive s8 "$tx" 60
  [ "$status" -eq 0 ]; [ -z "$output" ]                  # bounded: held
  CC_WR_TAIL_BYTES=0 run drive s8b "$tx" 60
  [ "$status" -eq 0 ]; [ -z "$output" ]                  # unbounded: held identically
}

@test "S6 positive control: the SAME buried-turn fixture fires when that turn is OLD" {
  local tx="$BATS_TEST_TMPDIR/s6old.jsonl" now; now="$(date +%s)"
  human "$(( now - 3000 ))" "how is the wave going?" > "$tx"      # 3000s > CONV_HOLD_S=900 ⇒ no hold
  mk_big "$BATS_TEST_TMPDIR/t9.jsonl" "$WAIT"; cat "$BATS_TEST_TMPDIR/t9.jsonl" >> "$tx"
  run drive s9 "$tx" 60
  [ "$status" -eq 0 ]; fired "$output"
  CC_WR_TAIL_BYTES=0 run drive s9b "$tx" 60
  [ "$status" -eq 0 ]; fired "$output"
}

@test "an explicit CC_CE_TAIL_BYTES is the more specific seam and is never clobbered" {
  grep -q 'CC_CE_TAIL_BYTES:-' "$HOOK"                  # the guard exists at the call site…
  grep -q 'CC_CE_TAIL_BYTES="\$TAIL_B" ce_last_interactive_age' "$HOOK"
  # …and behaviorally: a 64-byte lib window cannot see the buried turn in its tail, but the lib's own
  # whole-file fallback still finds it ⇒ the S6 hold is window-INDEPENDENT, which is the M13 contract.
  local tx="$BATS_TEST_TMPDIR/ce.jsonl" now; now="$(date +%s)"
  human "$(( now - 60 ))" "still here" > "$tx"
  mk_big "$BATS_TEST_TMPDIR/t10.jsonl" "$WAIT"; cat "$BATS_TEST_TMPDIR/t10.jsonl" >> "$tx"
  CC_CE_TAIL_BYTES=64 run drive s10 "$tx" 60
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "the osascript page fork is BOUNDED (wrc_osa) — with a positive control" {
  grep -q 'wrc_osa osascript -e' "$HOOK"                # the page call site is wrapped…
  grep -q 'WRC_OSA_TIMEOUT_S="\${WRC_OSA_TIMEOUT_S:-5}"' "$HOOK"   # …by a 5s default bound…
  grep -qE '"\$WRC_OSA_TB" -k 3 "\$WRC_OSA_TIMEOUT_S" "\$@"' "$HOOK"  # …applied with a hard -k kill…
  grep -q '/opt/homebrew/bin/timeout' "$HOOK"           # …resolving timeout(1) off-PATH too (hooks run without Homebrew)
  # POSITIVE CONTROL: the same assertions MUST fail on a copy with the wrapper stripped.
  local strip="$BATS_TEST_TMPDIR/unbounded.sh"
  sed 's/wrc_osa osascript -e/osascript -e/' "$HOOK" > "$strip"
  run grep -c 'wrc_osa osascript -e' "$strip"
  [ "$output" -eq 0 ]
}
