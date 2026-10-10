#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent; patterns are literal
# handoff-fire.sh — A TRANSPLANT RECYCLE CARRIES THE PROMPT BOX, IT DOES NOT HAND IT TO THE HUMAN
# (lr-stranded-husk 2026-10-10, causes C4 + C6; operator ruling of that day; docs/research/
# lr-stranded-husk-2026-10-10/ROOT-CAUSE.md, round2/C4-C6.md).
#
# THE INCIDENT. Pane 168 (session 186452ed) was transplanted next2 → next4, its in-place restart
# failed, and the one path that accepts that state (`--recycle --transplanted-source --husk`) REFUSED
# after 180 s because the box held `[Image #5]`: "clearing it is not ours to do". A husk's guard
# blocks every submit, so nothing in that box could ever be delivered where it sat.
#
# What runs here is the REAL chain extracted from the script: recycle_fire_gated → recycle_composer_block
# → hf_rcy_carry_eligible / hf_rcy_carry / rcy_draft_refusal, plus the watcher's hf_rcy_carry_putback and
# the EXIT arm hf_rcy_carry_exit_restore. lib/composer-carry.sh is the REAL library; cc-tui.sh is a stub
# whose box is a file ($W/composer) mirrored onto the screen composer_content reads, and whose paste of
# an existing image path attaches a chip, as Claude Code 2.1.293 does (round2/M1b-pty.md). Nothing
# touches a pane. The new functions are extracted WITHOUT a presence check, so on the unfixed tree the
# old gate runs and the [RED] cases fail on behaviour (a refusal), not on a missing name.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  unset KITTY_WINDOW_ID CC_PANE_ID ITERM_SESSION_ID
  export IT2_WRAPPER_NO_KITTY=1 CC_FIRE_CAPACITY_GATE=off
  # The account-sweep and heal seams default to /tmp and a bare claude-accounts: absent paths here.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json" CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts" \
         CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue" CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/retry"
  export W="$BATS_TEST_TMPDIR"
  export SCREEN_FILE="$W/screen.txt" SENT_LOG="$W/sent.log" EVENTS="$W/events.log" ARMED="$W/armed"
  export TYPE_LOG="$W/type.log" BOX="$W/composer" NOTIFY_LOG="$W/notify.log"
  : > "$SENT_LOG"; : > "$EVENTS"; : > "$TYPE_LOG"; : > "$NOTIFY_LOG"
  export LR_STATE_DIR="$W/lr" CC_CARRY_CC_TMPDIR="$W/cctmp"
  export SRC_SID=186452ed-02e5-4749-a4aa-8ece6f9ba1bf
  export TOMB="$W/src/projects/-Users-x-wt/$SRC_SID.HANDOFF.json"; mkdir -p "$(dirname "$TOMB")"; echo '{}' > "$TOMB"
  IMG="$CC_CARRY_CC_TMPDIR/claude-$(id -u)/-Users-x-wt/$SRC_SID/images"; export IMG; mkdir -p "$IMG"
  printf '\x89PNG-five' > "$IMG/5.png"
  export CC_NOTIFY_BIN="$W/cc-notify"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$NOTIFY_LOG" > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  export HF_CARRY_LIB="$REPO/scripts/lib/composer-carry.sh"
  export HF_TUI_LIB="$W/tui.sh"
  B="$(printf '─%.0s' $(seq 1 100))"; export B
  # The box stub. A paste whose payload is the path of an existing .png ATTACHES (the box gains
  # `[Image #K] `, K counting from 1), unless NO_ATTACH=1; any other payload lands as text.
  cat > "$HF_TUI_LIB" <<'TUI'
render() { { echo "⏺ reply"; echo "$B"; echo "❯ $(cat "$BOX" 2>/dev/null)"; echo "$B"; echo "  status"; } > "$SCREEN_FILE"; }
cc_tui_composer_text() { cat "$BOX" 2>/dev/null; return 0; }
cc_tui_composer() { tr -d '[:space:]' < "$BOX" 2>/dev/null; return 0; }
cc_tui_clear() { echo "CLEAR:$1" >> "$SENT_LOG"; [ -z "${CLEAR_BLANKS:-}" ] || { : > "$BOX"; render; }
  [ "${CLEAR_RC:-0}" = 0 ] || return "$CLEAR_RC"; : > "$BOX"; render; }
cc_tui_type_keys() { case "$(head -c 1 "$2")" in '!'|'#'|'/'|'?'|'&') return 2 ;; esac
  printf 'keys:%s|%s\n' "$1" "$(cat "$2")" >> "$TYPE_LOG"; cat "$2" >> "$BOX"; render; }
cc_tui_type() { local p; p="$(cat "$2")"; printf 'paste:%s|%s\n' "$1" "$p" >> "$TYPE_LOG"
  case "$p" in /*.png) if [ -f "$p" ] && [ -z "${NO_ATTACH:-}" ]; then
      printf '[Image #%s] ' "$(( $(grep -o '\[Image #' "$BOX" 2>/dev/null | wc -l) + 1 ))" >> "$BOX"; render; return 0; fi ;; esac
  printf '%s' "$p" >> "$BOX"; render; }
TUI
  UNITS="$W/units.sh"
  {
    for f in composer_content recycle_composer_gate hf_transcript_at_rest hf_recycle_retry_ticket \
             rcy_composer_unreadable hf_new_prompt_since recycle_turn_wait hf_recycle_defer_eligible \
             hf_recycle_defer composer_scrub_verified composer_residue_forget composer_residue_is_ours \
             recycle_fire_gated recycle_composer_block rcy_draft_refusal \
             hf_rcy_carry_libs hf_rcy_carry_retired hf_rcy_carry_eligible hf_rcy_carry hf_rcy_carry_what \
             hf_rcy_carry_exit_restore hf_rcy_carry_restore_here hf_rcy_carry_putback; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
    sed -n '/^hf_recycle_retry_dir() {/p;/^composer_residue_dir() {/p' "$HF"
  } > "$UNITS"
  bash -n "$UNITS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  for f in recycle_composer_block recycle_composer_gate composer_content hf_transcript_at_rest; do
    grep -q "^$f() {" "$UNITS" || { echo "$f was not extracted from $HF" >&2; return 1; }
  done
  # The foreground of a REMOTE transplant recycle from the composer gate on, under the script's own
  # shell options and its own EXIT trap. recycle_fire_armed (watcher, last read, /exit) is a stub: it
  # marks ARMED, then either aborts before /exit (ABORT_BEFORE_EXIT=1) or does what the real one does
  # after recycle_fire_commit returns — hand the carry to the watcher (pinned by case 7). `cc-notify`
  # is shadowed so the UNFIXED tree's `command -v cc-notify` pages a function, never the live notifier.
  DRIVER="$W/handoff-fire-driver.sh"
  cat > "$DRIVER" <<'DRV'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
. "$W/units.sh"
hf_bounded() {
  if [ "${2:-}" = session ] && [ "${3:-}" = read ]; then cat "$SCREEN_FILE" 2>/dev/null; return 0; fi
  if [ "${2:-}" = session ] && [ "${3:-}" = send ]; then printf 'SEND:%s\n' "${6:-}" >> "$SENT_LOG"; return 0; fi
  return 1
}
emit_recycle_event() { printf '%s\t%s\n' "$1" "${4:-}" >> "$EVENTS"; }
cc-notify() { printf 'NOTIFY:%s\n' "$*" >> "$EVENTS"; }
hf_invoking_call_pid() { return 1; }
hf_pane_focused() { echo "${FOCUSED:-no}"; }
cc_sid_for_pane() { echo "$SRC_SID"; }
fire_cleanup() { :; }
hf_inflight_release() { :; }
recycle_fire_armed() {
  echo reached > "$ARMED"
  [ "${ABORT_BEFORE_EXIT:-0}" = 0 ] || exit 1
  [ "${HF_RCY_CARRY_STATE:-}" != cleared ] || HF_RCY_CARRY_STATE=handed
  printf '%s' "${HF_RCY_CARRY_DIR:-}" > "$W/handed-dir"
}
trap 'fire_cleanup; hf_inflight_release' EXIT
SID=77; tty=/dev/ttys999; CMD="bash launcher.sh"; REAL_IT2=it2
RCY_REMOTE="${RCY_REMOTE:-1}"; RCY_TRANSPLANTED_SOURCE="${RCY_TRANSPLANTED_SOURCE:-1}"; RCY_HUSK="${RCY_HUSK:-1}"
RESUME_LAUNCHER="${RESUME_LAUNCHER-$W/launcher.sh}"; RCY_SOURCE_SESSION="$SRC_SID"; HF_TS_TOMBSTONE="$TOMB"
PROMPT_FILE="$W/brief.txt"
HF_ORIG_SELF=/x/handoff-fire.sh; HF_ORIG_PWD="$W/orig dir"; HF_ORIG_ARGV=(--recycle --prompt-file brief.txt)
recycle_fire_gated
DRV
  chmod +x "$DRIVER"
  export CC_RECYCLE_TURN_WAIT_PROBE_S=0 CC_RECYCLE_DRAFT_WAIT=1 CC_RECYCLE_DRAFT_IVL=1
  export CC_CARRY_SETTLE_S=0 CC_RECYCLE_CARRY_SETTLE_S=0 CC_RECYCLE_CARRY_POLL_S=0 CC_RECYCLE_CARRY_HERE_WAIT_S=3
}

# shellcheck disable=SC1090  # the stub library written in setup
box() { printf '%s' "$1" > "$BOX"; ( . "$HF_TUI_LIB"; render ); }
carried_dir() { find "$LR_STATE_DIR/drafts/$SRC_SID" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | awk 'NR<=1'; }
no_bare_draft_word() { ! printf '%s\n' "$1" | grep -iw 'draft' >/dev/null; }   # lr_recon/classify.py maps it to HOLD
# The refusal never hands the box to a human (operator ruling 2026-10-10, round2/C5.md A2).
no_handback() {
  ! printf '%s\n' "$1" | grep -qiE 'clear/send|not ours to do|send or clear|clear it|then re-run the recycle|asks nothing of the operator' || { printf '%s\n' "$1"; false; }
}
# A target transcript whose last record is $1's stop_reason.
target_tx() { cfg="$W/tgt"; mkdir -p "$cfg/projects/-Users-x-wt"
  printf '{"type":"assistant","message":{"stop_reason":"%s","content":[{"type":"text","text":"resumed"}]}}\n' "$1" > "$cfg/projects/-Users-x-wt/$SRC_SID.jsonl"; }
saved() { d="$LR_STATE_DIR/drafts/$SRC_SID/$1"; mkdir -p "$d"; printf '%s' "$2" > "$d/draft.txt"; : > "$d/images.txt"; : > "$d/unsaved.txt"; }
putback() { # runs the watcher's put-back over the extracted units, its env given as "K=V" words
  run env "$@" bash -c 'set -euo pipefail; . "$W/units.sh"
    emit_recycle_event() { printf "%s\t%s\n" "$1" "${4:-}" >> "$EVENTS"; }
    hf_bounded() { "$@"; }
    RCY_RESUME_CFG="$W/tgt" RCY_RESUME_SID="$SRC_SID" RSID=77 hf_rcy_carry_putback'
}

@test "1 [RED] --husk, box holds only [Image #5]: image bytes saved by chip number, box cleared, the recycle PROCEEDS" {
  box '[Image #5]'
  run bash "$DRIVER"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$EVENTS"; false; }
  [ -f "$ARMED" ] || { echo "$output"; false; }
  d="$(carried_dir)"; [ -n "$d" ] || { echo "$output"; false; }
  [ "$(cat "$d/draft.txt")" = '[Image #5]' ] || false
  cmp -s "$d/5.png" "$IMG/5.png" || { ls -la "$d"; false; }
  [ "$(cat "$d/images.txt")" = "$d/5.png" ] || { cat "$d/images.txt"; false; }
  [ "$(grep -c '^CLEAR:77$' "$SENT_LOG")" = 1 ] || { cat "$SENT_LOG"; false; }
  [ ! -s "$TYPE_LOG" ] || { cat "$TYPE_LOG"; false; }                     # the foreground never types
  [ ! -s "$BOX" ] || false
  grep -q "^recycle-composer-carried.*$d/5.png" "$EVENTS" || { cat "$EVENTS"; false; }
  ! grep -q '^recycle-held-draft' "$EVENTS" || { cat "$EVENTS"; false; }
  [ "$(cat "$W/handed-dir")" = "$d" ] || { cat "$W/handed-dir"; false; }   # exported for the watcher
  no_bare_draft_word "$output" || { echo "$output"; false; }
}

@test "2 [RED] unfocused transplanted source (no --husk): text saved WITH its spaces, cleared once, recycle proceeds" {
  box 'fix the  login bug, then ship'
  RCY_HUSK=0 FOCUSED=no run bash "$DRIVER"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$EVENTS"; false; }
  d="$(carried_dir)"
  [ "$(cat "$d/draft.txt")" = 'fix the  login bug, then ship' ] || false
  [ "$(grep -c '^CLEAR:77$' "$SENT_LOG")" = 1 ] || false
  [ ! -s "$d/images.txt" ] || false
}

@test "2b [RED] a RETIRED source (its .handed-off exists) is carried even when focused and without --husk" {
  box 'typed into a husk'
  : > "${TOMB%.HANDOFF.json}.jsonl.handed-off"
  RCY_HUSK=0 FOCUSED=yes run bash "$DRIVER"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$EVENTS"; false; }
  [ -f "$ARMED" ] || { echo "$output"; cat "$EVENTS"; false; }
  [ "$(cat "$(carried_dir)/draft.txt")" = 'typed into a husk' ] || false
}

@test "2c [RED] a pasted block on a LIVE source is not carried: its content is not on disk, so the refusal stands and says so" {
  box 'also fix the margin[Pasted text #1 +19 lines]'
  RCY_HUSK=0 FOCUSED=no run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  ! grep -q '^CLEAR:' "$SENT_LOG" || { cat "$SENT_LOG"; false; }
  [ "$(cat "$BOX")" = 'also fix the margin[Pasted text #1 +19 lines]' ] || false
  grep -q '^recycle-held-draft.*pasted block' "$EVENTS" || { cat "$EVENTS"; false; }
  no_handback "$output"
}

@test "2d [RED] a pasted block on a RETIRED source is carried, and every line says the block could not be saved" {
  box 'also fix the margin[Pasted text #1 +19 lines]'
  run bash "$DRIVER"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$EVENTS"; false; }
  [ -f "$ARMED" ] || { echo "$output"; cat "$EVENTS"; false; }
  d="$(carried_dir)"
  [ "$(cat "$d/unsaved.txt")" = '[Pasted text #1 +19 lines]' ] || { cat "$d/unsaved.txt"; false; }
  grep -q '^recycle-composer-carried.*pasted block.*could not be saved' "$EVENTS" || { cat "$EVENTS"; false; }
  [[ "$output" == *"pasted block"*"could not be saved"* ]] || { echo "$output"; false; }
  no_bare_draft_word "$output" || { echo "$output"; false; }
}

@test "3 controls: focused (no --husk), kill switch, self form, not transplanted all REFUSE — no CLEAR, box intact, no hand-back" {
  box 'operator mid-thought'
  RCY_HUSK=0 FOCUSED=yes run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  no_handback "$output"
  CC_RECYCLE_CARRY_DRAFT=off run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  RCY_REMOTE=0 RESUME_LAUNCHER='' run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  RCY_TRANSPLANTED_SOURCE=0 run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  ! grep -q '^CLEAR:' "$SENT_LOG" || { cat "$SENT_LOG"; false; }
  [ "$(cat "$BOX")" = 'operator mid-thought' ] || false
  [ "$(grep -c '^recycle-held-draft' "$EVENTS")" = 4 ] || { cat "$EVENTS"; false; }
}

@test "3b [RED] the refusal: a self-recycle files a retry ticket and names it; two pages via CC_NOTIFY_BIN; re-run line keeps the cwd" {
  box 'operator mid-thought'
  RCY_REMOTE=0 RESUME_LAUNCHER='' run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -f "$CC_RECYCLE_RETRY_DIR/$SRC_SID.json" ] || { echo "$output"; ls -la "$CC_RECYCLE_RETRY_DIR" 2>&1; false; }
  [[ "$output" == *"retry ticket"* ]] || { echo "$output"; false; }
  [[ "$output" == *"Re-run as is: cd $(printf '%q' "$W/orig dir") && /x/handoff-fire.sh --recycle --prompt-file brief.txt"* ]] || { echo "$output"; false; }
  [ "$(grep -c '^--role desk RECYCLE HELD on pane 77' "$NOTIFY_LOG")" = 1 ] || { cat "$NOTIFY_LOG"; false; }
  [ "$(grep -c '^77 RECYCLE DEFERRED' "$NOTIFY_LOG")" = 1 ] || { cat "$NOTIFY_LOG"; false; }
  ! grep -q '^NOTIFY:' "$EVENTS" || { cat "$EVENTS"; false; }              # never the PATH notifier
  no_handback "$output"; no_handback "$(cat "$NOTIFY_LOG")"; no_handback "$(cat "$EVENTS")"
  # A transplant recycle the carry declined names no process it does not have.
  : > "$NOTIFY_LOG"; RCY_HUSK=0 FOCUSED=yes run bash "$DRIVER"
  [ "$status" -eq 1 ] || false
  ! printf '%s\n' "$output" "$(cat "$NOTIFY_LOG")" | grep -qi 'automated' || { echo "$output"; cat "$NOTIFY_LOG"; false; }
  no_handback "$output"
}

@test "4 [RED] a clear that fails with the box untouched: refusal stands, box intact, the saved copy is named, nothing called lost" {
  box 'keep me'
  CLEAR_RC=1 run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  [ "$(cat "$BOX")" = 'keep me' ] || false                                # stub's clear failed before blanking
  [ ! -s "$TYPE_LOG" ] || { cat "$TYPE_LOG"; false; }                     # nothing to put back: it never left
  d="$(carried_dir)"; [ -n "$d" ] || false
  grep -q "^recycle-held-draft.*$d" "$EVENTS" || { cat "$EVENTS"; false; }
  ! grep -q '^recycle-composer-not-restored' "$EVENTS" || { cat "$EVENTS"; false; }
  no_handback "$output"
}

@test "4b [RED] a clear that emptied the box but could not prove it: the text is put back in place and the refusal says so (spent, not untouched)" {
  box 'keep me too'
  CLEAR_RC=1 CLEAR_BLANKS=1 run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -f "$ARMED" ] || { echo "$output"; false; }
  [ "$(cat "$TYPE_LOG")" = 'keys:77|keep me too' ] || { cat "$TYPE_LOG"; false; }
  d="$(carried_dir)"
  grep -q '^recycle-composer-restored' "$EVENTS" || { cat "$EVENTS"; false; }
  grep '^recycle-held-draft' "$EVENTS" | grep -q "put back in place.*$d" || { cat "$EVENTS"; false; }
  ! grep '^recycle-held-draft' "$EVENTS" | grep -qi 'untouched' || { cat "$EVENTS"; false; }
  [[ "$output" == *"$d"* ]] || { echo "$output"; false; }
}

@test "5 [RED] the recycle stops after the clear and before /exit: the EXIT arm types the text back into the SAME box" {
  box 'half a thought'
  ABORT_BEFORE_EXIT=1 run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -f "$ARMED" ] || { echo "$output"; false; }
  [ "$(cat "$TYPE_LOG")" = 'keys:77|half a thought' ] || { cat "$TYPE_LOG"; false; }
  [ "$(cat "$BOX")" = 'half a thought' ] || false
  grep -q '^recycle-composer-restored' "$EVENTS" || { cat "$EVENTS"; false; }
}

@test "5b [RED] stopped before /exit with only [Image #5]: the saved image is re-attached by a bracketed paste of its path" {
  box '[Image #5]'
  ABORT_BEFORE_EXIT=1 run bash "$DRIVER"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ -f "$ARMED" ] || { echo "$output"; false; }
  d="$(carried_dir)"
  [ "$(cat "$TYPE_LOG")" = "paste:77|$d/5.png" ] || { cat "$TYPE_LOG"; false; }
  [ "$(tr -d '[:space:]' < "$BOX")" = '[Image#1]' ] || { cat "$BOX"; false; }
  grep -q '^recycle-composer-restored' "$EVENTS" || { cat "$EVENTS"; false; }
}

@test "6 [RED] watcher put-back: target at rest + empty box ⇒ image re-attached, then the text typed back unsent" {
  saved 20261010T000000Z 'look at [Image #5] this'; cp "$IMG/5.png" "$d/"; printf '%s\n' "$d/5.png" > "$d/images.txt"
  target_tx end_turn; box ''
  putback HF_RCY_CARRY_DIR="$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$TYPE_LOG")" = "$(printf 'paste:77|%s\nkeys:77|look at this' "$d/5.png")" ] || { cat "$TYPE_LOG"; false; }
  [ "$(tr -d '[:space:]' < "$BOX")" = '[Image#1]lookatthis' ] || { cat "$BOX"; false; }
  grep -q "^recycle-composer-returned.*$d/5.png" "$EVENTS" || { cat "$EVENTS"; false; }
  grep -q -- "--no-wake --from recycle-watcher 77 RECYCLE-CARRY: .*$d/5.png" "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
  no_bare_draft_word "$output" || { echo "$output"; false; }
}

@test "6b watcher put-back: the successor never comes to rest ⇒ nothing typed, the saved path is named" {
  saved 20261010T000001Z 'later'; target_tx tool_use; box ''
  putback CC_RECYCLE_CARRY_WAIT_S=1 HF_RCY_CARRY_DIR="$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$TYPE_LOG" ] || false
  grep -q "^recycle-composer-not-returned.*saved in $d" "$EVENTS" || { cat "$EVENTS"; false; }
}

@test "6c [RED] the put-back fits under cc-reaper's 600 s TERM: a watcher 590 s old records not-returned and notifies at once" {
  saved 20261010T000002Z 'late text'; target_tx end_turn; box ''
  t0=$(( $(date +%s) - 590 )); s=$(date +%s)
  putback CC_RECYCLE_CARRY_WAIT_S=900 CC_RECYCLE_CARRY_POLL_S=5 rcy_w_t0="$t0" HF_RCY_CARRY_DIR="$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ $(( $(date +%s) - s )) -lt 30 ] || false
  [ ! -s "$TYPE_LOG" ] || { cat "$TYPE_LOG"; false; }
  grep -q "^recycle-composer-not-returned.*saved in $d" "$EVENTS" || { cat "$EVENTS"; false; }
  grep -q -- "--no-wake --from recycle-watcher 77 RECYCLE-CARRY: .*$d" "$NOTIFY_LOG" || { cat "$NOTIFY_LOG"; false; }
}

@test "6d [RED] put-back of a box that held a pasted block: the text goes back, the block is named as not saved, never 'exact'" {
  saved 20261010T000003Z 'also fix the margin[Pasted text #1 +19 lines]'; printf '%s\n' '[Pasted text #1 +19 lines]' > "$d/unsaved.txt"
  target_tx end_turn; box ''
  putback HF_RCY_CARRY_DIR="$d"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$TYPE_LOG")" = 'keys:77|also fix the margin' ] || { cat "$TYPE_LOG"; false; }
  grep -q '^recycle-composer-partly-returned.*pasted block.*could not be saved' "$EVENTS" || { cat "$EVENTS"; false; }
  ! grep -q '^recycle-composer-returned' "$EVENTS" || { cat "$EVENTS"; false; }
  ! grep -qi 'exact' "$EVENTS" "$NOTIFY_LOG" || false
}

@test "7 pins: /exit hands the carry to the watcher; four engaged exits put it back; the watcher does not re-export it" {
  grep -A3 '^  recycle_fire_commit "\$rcy_old_sid"$' "$HF" | grep -q 'HF_RCY_CARRY_STATE=handed' || false
  [ "$(grep -cE '^ +hf_rcy_carry_putback$' "$HF")" = 4 ] || false
  grep -q '^  export -n HF_RCY_CARRY_DIR' "$HF" || false
  grep -qE '^  export HF_RCY_CARRY_DIR HF_RCY_CARRY_STATE' "$HF" || false
}

@test "8 [RED] the by-process engaged arm (HF_ENGAGE_BY_PROCESS=1, every lr_recon husk actuator) puts the text back" {
  # The real watcher, harnessed as tests/handoff-recycle-custody.bats drives its by-process case.
  SHIM="$W/shim"; mkdir -p "$SHIM" "$HOME/.claude/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"; cc=0
[ -s "$HOME/it2-screen" ] && cc=1
case "$args" in *pgid=*) printf '4242\n'; exit 0 ;; esac
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
case "$args" in
  *"-axww -o args="*) [ "$cc" = 1 ] && printf 'claude --resume %s\n' "$SRC_SID"; exit 0 ;;
  *"-o pid= -t"*)     printf '100\n' ;;
  *"-o tpgid= -t"*)   printf '100\n' ;;
  *"-o comm= -t"*)    if [ "$cc" = 1 ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)       printf '100 1\n' ;;
  *"pid=,comm= -g"*)  printf '100 /bin/zsh\n' ;;
  *"-p 100"*)         if [ "$cc" = 1 ]; then printf 'claude\n'; else printf '/bin/zsh\n'; fi ;;
esac
exit 0
SH
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session list") [ "${3:-}" = --json ] && printf '[{"id": "77", "tty": "/dev/ttys999"}]\n' || printf '77\n'; exit 0 ;;
  "session send") txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$SHIM/ps" "$SHIM/osascript" "$HOME/.claude/bin/it2"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$W/cc-resume-debt"; chmod +x "$W/cc-resume-debt"
  export PATH="$SHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" CC_RESUME_DEBT_BIN="$W/cc-resume-debt"
  export CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off HANDOFF_ACCOUNT_SWEEP=off CC_ADMIT_IDL="$W/idl.jsonl"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$W/no-sweep" CC_ACCOUNTS_BIN="$W/no-accounts" CC_HEAL_LOCK_PREFIX="$W/no-heal-"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export HF_RECYCLE_SHELL_WAIT_S=6 FIRE_TYPE_ATTEMPTS=1 FIRE_TYPE_SETTLE=0 FIRE_TYPE_PRESETTLE=0 CC_RECYCLE_TYPE_DEADLINE_S=0
  export RCY_BOOT_WAIT_S=1 RCY_BOOT_STALE_S=2 RCY_BOOT_IVL_S=0.2 RCY_BOOT_SLOW_IVL_S=1 RCY_BOOT_PANE_EVERY=2
  export HF_ENGAGE_BY_PROCESS=1 HF_ENGAGE_PROC_HOLD_S=0 RCY_ENGAGE_TIMEOUT=6
  printf 'cd /tmp && nocorrect bash /tmp/lr-launch-c4.sh\n' > "$W/relaunch.cmd"; : > "$W/ttys999"
  cfg="$HOME/.claude-next"; mkdir -p "$cfg/projects/-Users-x-wt"
  printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"resumed"}]}}' > "$cfg/projects/-Users-x-wt/$SRC_SID.jsonl"
  saved 20261010T000004Z 'carry me home'; box ''
  HF_RCY_CARRY_DIR="$d" run bash "$HF" __recycle 77 "$W/ttys999" "$W/relaunch.cmd" /tmp "$SRC_SID" "" "" "" \
    "$cfg" "$SRC_SID" "2026-09-28T23:12:00"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"ENGAGEMENT CONFIRMED BY PROCESS"* ]] || { echo "$output"; false; }
  [ "$(cat "$TYPE_LOG")" = 'keys:77|carry me home' ] || { echo "$output"; cat "$TYPE_LOG"; false; }
  grep -q '"class":"recycle-composer-returned"' "$HOME/.claude/logs/handoffs.jsonl" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "9 [RED] cc_carry_save: rc 3 for a pasted block (listed in unsaved.txt), missing image bytes named, plain text rc 0" {
  run bash -c '. "$HF_TUI_LIB"; . "$HF_CARRY_LIB"; printf "%s" "a [Image #5] b [Image #9][Pasted text #2 +4 lines]" > "$BOX"
    cc_carry_save 77 "$W/s1" "$IMG"; echo "rc=$?"
    printf "%s" "just text" > "$BOX"; cc_carry_save 77 "$W/s2" "$IMG"; echo "rc=$?"
    : > "$BOX"; cc_carry_save 77 "$W/s3" "$IMG"; echo "rc=$?"'
  [ "${lines[0]}" = rc=3 ] || { echo "$output"; false; }
  [ "${lines[1]}" = rc=0 ] || { echo "$output"; false; }
  [ "${lines[2]}" = rc=1 ] || { echo "$output"; false; }
  [ "$(cat "$W/s1/unsaved.txt")" = '[Pasted text #2 +4 lines]' ] || false
  [ "$(cat "$W/s1/images.txt")" = "$(printf '%s\n%s' "$W/s1/5.png" "missing:$IMG/9.png")" ] || { cat "$W/s1/images.txt"; false; }
  cmp -s "$W/s1/5.png" "$IMG/5.png" || false
  [ "$(cat "$W/s2/draft.txt")" = 'just text' ] && [ ! -s "$W/s2/unsaved.txt" ] || false
}

@test "10 [RED] cc_carry_putback: a paste that does not attach is cleared away, the text still goes back, rc 5 names the image" {
  saved 20261010T000005Z 'see [Image #5] here'; cp "$IMG/5.png" "$d/"; printf '%s\n' "$d/5.png" > "$d/images.txt"; box ''
  run env NO_ATTACH=1 bash -c '. "$HF_TUI_LIB"; . "$HF_CARRY_LIB"; cc_carry_putback 77 "'"$d"'" 5 0 true; echo "rc=$?"'
  [ "${lines[${#lines[@]}-1]}" = rc=5 ] || { echo "$output"; false; }
  [ "$(cat "$BOX")" = 'see here' ] || { cat "$BOX"; false; }
  [ "$(cat "$d/putback.txt")" = "not-attached:$d/5.png" ] || { cat "$d/putback.txt"; false; }
  grep -q '^CLEAR:77$' "$SENT_LOG" || false
}
