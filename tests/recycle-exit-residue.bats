#!/usr/bin/env bats
# shellcheck disable=SC2329
# SC2329: bats invokes setup and the stubs (hf_bounded, emit_recycle_event, …) through its runner or
# through the extracted units, so the linter reads them as never called.
# A HELD SELF-RECYCLE LEAVES THE COMPOSER EMPTY, AND ITS RETRY COMPLETES (pane 206, 2026-10-10).
# Evidence + root cause: docs/research/recycle-exit-residue-2026-10-10.md.
#
# THE INCIDENT. f14b42653 taught composer_content that a ❯ row at indent 1-4 ABOVE the box is a
# dialog. Claude Code's slash-command menu, which our own typed `/exit` opens, draws exactly that
# row (`  ❯ /exit   Exit the CLI`) above the box. So every /exit read-back after the deploy said
# `<unreadable>`; hf_exit_readback held, sent no DELs (they are sent only over a READ trailing
# /exit) and wrote no receipt, so `/exit` stayed in the box with the menu open, every later read
# stayed UNKNOWN, and the deferred retry refused after 180 s. The operator /exit-ed by hand.
#
# The screen is a stateful fake of the pane: a tall Stop-hook block above the composer (the incident
# shape), the REAL 2.1.291 slash-menu capture whenever the box holds `/exit`, and keystrokes that
# edit the box the way the TUI does (text appends, DEL erases one, Ctrl-U clears, CR submits).
#
# The pane-168 sibling fix (0584f0720) exempted ANY `❯ /…` row above the box; this suite's control
# 5 pins the tightening on top of it: only a highlight naming the command the box holds is exempt,
# because with the menu open a CR submits the HIGHLIGHTED row, not the box.
#
# RED-proof: on 1b2b93357 (before both fixes) tests 1-3 fail — 1 reads UNKNOWN (rc 1), 2 holds
# with `/exit` left in the box and no CR, 3 writes no receipt and never reaches the recycle. On
# 0584f0720 (the sibling fix alone) test 5 fails: the `/export` highlight reads as `/exit`.
# Control 4 passes on all three, by the dialog-above rule it names.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  FX="$REPO/tests/fixtures/recycle-exit-residue"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1 CC_FIRE_CAPACITY_GATE=off
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  export CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/retry"
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/no-such-cc-notify"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export W="$BATS_TEST_TMPDIR" FX
  export BOX="$W/box" MODE="$W/mode" SENT_LOG="$W/sent.log" EVENTS="$W/events.log"
  export TX="$W/tx.jsonl" SIDFILE="$W/sid" ARMED="$W/armed"
  : > "$BOX"; echo none > "$MODE"; : > "$SENT_LOG"; : > "$EVENTS"; printf 'sess-206' > "$SIDFILE"
  UNITS="$W/units.sh"
  {
    grep '^_iso_now() {' "$HF"
    for f in composer_content recycle_composer_gate hf_transcript_at_rest hf_recycle_retry_ticket \
             rcy_composer_unreadable hf_new_prompt_since recycle_turn_wait hf_recycle_defer_eligible \
             hf_recycle_defer rcy_composer_unreadable_static composer_scrub_verified composer_residue_dir composer_residue_record \
             composer_residue_forget composer_residue_is_ours hf_exit_readback recycle_fire_gated \
             recycle_composer_block; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
    sed -n '/^hf_recycle_retry_dir() {/p' "$HF"
  } > "$UNITS"
  bash -n "$UNITS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  for f in composer_content hf_exit_readback recycle_composer_block composer_residue_record; do
    grep -q "^$f() {" "$UNITS" || { echo "$f was not extracted from $HF" >&2; return 1; }
  done

  # THE PANE. Read: the Stop-hook block, a dialog when MODE=dialog, then the composer — the real
  # slash-menu capture when it holds exactly /exit. Send: edits $BOX like the TUI; CR logs a SUBMIT.
  cat > "$W/tui.sh" <<'TUI'
B="$(printf '─%.0s' $(seq 1 100))"
tui_render() {
  local t r; t="$(cat "$BOX")"
  for r in $(seq 1 30); do echo "  Stop says: OPERATOR ▸ close block row $r — ✅ Good to close: no"; done
  if [ "$(cat "$MODE")" = dialog ]; then
    echo "  Background work is running"; echo "  ❯ 1. Exit and stop tasks"; echo "    2. Stay"; echo
  fi
  if [ "$t" = /exit ]; then tail -n 8 "$FX/slash-menu-exit-2.1.291.txt"
  else echo "$B"; echo "❯ $t"; echo "$B"; echo "  (1) #206 4d08e115 35%"; echo "  ⏵⏵ auto mode on"; fi
}
hf_bounded() { # <bin> session read -s <id> -n N [--ansi] | <bin> session send -s <id> <payload>
  local n=24 i a p
  if [ "${2:-} ${3:-}" = "session read" ]; then
    for ((i = 4; i <= $#; i++)); do a="${!i}"; if [ "$a" = -n ]; then i=$((i + 1)); n="${!i}"; fi; done
    tui_render | tail -n "$n"; return 0
  fi
  if [ "${2:-} ${3:-}" = "session send" ]; then
    p="${6:-}"; printf 'SEND:%q\n' "$p" >> "$SENT_LOG"
    case "$p" in
      $'\r')   printf 'SUBMIT:%s\n' "$(cat "$BOX")" >> "$SENT_LOG"; : > "$BOX" ;;
      $'\x15') : > "$BOX" ;;
      *[!$'\x7f']*) printf '%s' "$(cat "$BOX")$p" > "$BOX" ;;
      *) t="$(cat "$BOX")"; printf '%s' "${t:0:$(( ${#t} > ${#p} ? ${#t} - ${#p} : 0 ))}" > "$BOX" ;;
    esac
    return 0
  fi
  return 1
}
emit_recycle_event() { printf '%s\t%s\n' "$1" "${4:-}" >> "$EVENTS"; }
TUI

  # The deferred-path driver: the foreground of a self-recycle from the composer gate on, under the
  # script's own shell options (handoff-recycle-turn-wait.bats's driver, on this pane).
  DRIVER="$W/handoff-fire-driver.sh"
  cat > "$DRIVER" <<'DRV'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090,SC1091
. "$W/units.sh"; . "$W/tui.sh"
hf_invoking_call_pid() { [ -n "${CALLER_PID:-}" ] || return 1; printf '%s' "$CALLER_PID"; }
cc_sid_for_pane() { cat "$SIDFILE" 2>/dev/null || true; }
transcript_for_sid() { printf '%s' "$TX"; }
fire_cleanup() { :; }
hf_inflight_release() { :; }
recycle_fire_armed() { echo reached > "$ARMED"; }
SID=206; tty=/dev/ttys999; CMD="claude 'brief'"; RCY_REMOTE=0; RESUME_LAUNCHER=""
PROMPT_FILE="$W/brief.txt"; REAL_IT2=it2
recycle_fire_gated
DRV
  chmod +x "$DRIVER"
  export CC_RECYCLE_TURN_WAIT_PROBE_S=0 CC_RECYCLE_DRAFT_WAIT=2 CC_RECYCLE_DRAFT_IVL=1
  export CC_RECYCLE_TURN_WAIT_S=6 CC_RECYCLE_TURN_WAIT_IVL_S=1 CC_RECYCLE_TURN_SETTLE_S=1
  export FIRE_TYPE_SETTLE=0.01 HF_SLEEP=true RCY_IT2=it2
  LIVE_PID=""
}

teardown() {
  [ -z "${LIVE_PID:-}" ] || kill "$LIVE_PID" 2>/dev/null || true
  local p
  for p in "$CC_RECYCLE_RETRY_DIR"/.turn-wait-*.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null || true
  done
}

units() {
  # shellcheck disable=SC1090
  . "$UNITS"
  # shellcheck disable=SC1091
  . "$W/tui.sh"
}
read_box() { units; composer_content it2 206; }
wait_for() { local n=0 max=$(( $1 * 5 )); shift; while [ "$n" -lt "$max" ]; do "$@" && return 0; sleep 0.2; n=$((n + 1)); done; return 1; }
armed() { [ -f "$ARMED" ]; }
not() { if "$@"; then return 1; fi; }

# ── 1. the parse ────────────────────────────────────────────────────────────────────────────

@test "[RED] the real 2.1.291 slash menu over a typed /exit reads back as exactly '/exit'" {
  units
  hf_bounded() { if [ "${2:-} ${3:-}" = "session read" ]; then
      case " $* " in *" --ansi "*) cat "$FX/slash-menu-exit-2.1.291.ansi.txt" ;; *) cat "$FX/slash-menu-exit-2.1.291.txt" ;; esac; fi; }
  run composer_content it2 206
  [ "$status" -eq 0 ]
  [ "$output" = /exit ]
}

# ── 2. the incident: tall Stop-hook block above, /exit typed mid-turn ────────────────────────

@test "[RED] pane-206 shape: /exit typed under a tall Stop-hook block reads back, gets its CR, and leaves the box empty" {
  units
  run hf_exit_readback 206
  [ "$status" -eq 0 ]
  grep -qx 'SUBMIT:/exit' "$SENT_LOG"
  [ ! -s "$BOX" ]
}

# ── 3. the deferred path: a hold that could not read its box, then the retry ─────────────────

@test "[RED] an unreadable read-back types nothing, receipts its /exit, and the deferred retry clears it and goes on" {
  # Attempt 1: a dialog sits above the box, so the read-back cannot be trusted.
  echo dialog > "$MODE"
  units
  hf_exit_readback 206 || rc=$?
  [ "${rc:-0}" -eq 1 ]
  [ "$(cat "$BOX")" = /exit ]                                  # our /exit is still in the box…
  not grep -q 'SUBMIT:' "$SENT_LOG"                            # …unsubmitted
  [ "$(grep -c "SEND:" "$SENT_LOG")" -eq 1 ]                   # and nothing but /exit was typed
  [[ "$HF_EXIT_RB_UNDO" == *"no DELs"* ]] || false               # and the hold says so
  composer_residue_is_ours 206 /exit                           # the box carries a receipt
  # Attempt 2, from inside a later turn (its caller still running), after the dialog went away:
  # the box reads `/exit` with the menu open, the receipt attributes it, the scrub clears it.
  echo none > "$MODE"; : > "$SENT_LOG"
  sleep 300 & LIVE_PID=$!
  printf '{"type":"assistant","timestamp":"2026-10-11T01:24:12.000Z","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}\n' > "$TX"
  CALLER_PID="$LIVE_PID" run "$DRIVER" 3>&-
  wait_for 10 armed
  [ ! -s "$BOX" ]
  grep -qxF "SEND:$(printf '%q' $'\x15')" "$SENT_LOG"          # cleared by Ctrl-U, read back empty
  not grep -q 'SUBMIT:' "$SENT_LOG"
  grep -q '^recycle-residue-scrubbed' "$EVENTS"
  [ ! -f "$CC_RECYCLE_RETRY_DIR/sess-206.json" ]
}

# ── 4-5. the fail-closed half: only the menu row naming the box's own command is exempt ───────

@test "CONTROL: a real dialog above a box holding /exit still reads UNKNOWN" {
  echo dialog > "$MODE"; printf '/exit' > "$BOX"
  run read_box
  [ "$status" -eq 3 ]                # UNKNOWN, static shape (dialog-above): REPORT.md fix 3
}

@test "CONTROL: a menu whose highlighted command is not the box's own reads UNKNOWN" {
  units
  sed 's/❯ \/exit  /❯ \/export/' "$FX/slash-menu-exit-2.1.291.txt" > "$W/other.txt"
  grep -q '❯ /export' "$W/other.txt"                            # the mutation took
  hf_bounded() { [ "${2:-} ${3:-}" = "session read" ] && cat "$W/other.txt"; }
  run composer_content it2 206
  [ "$status" -eq 3 ]                # UNKNOWN, static shape (dialog-above): REPORT.md fix 3
}
