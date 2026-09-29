#!/usr/bin/env bats
# handoff-fire.sh __recycle — the /exit that raises the harness's BACKGROUND-WORK dialog.
#
# THE DEFECT (cc-backlog 004d154032e8, measured 2026-09-01T04:43Z, drain recycle #277). A drain link
# backgrounds its land exactly once because its brief mandates it, so the harness is tracking a
# shell when `--recycle` types /exit. /exit then does not exit — it raises a menu. The pane keeps a
# LIVE session with no composer box, so composer_content reads UNKNOWN, all three nudge checkpoints
# decide `unknown` and HOLD, and the watcher dies at 600 s having typed nothing. The chain's only
# symptom is absence, and the desk had to page a human for one keystroke.
#
# THE MEASUREMENT THIS SUITE PINS (docs/research/exit-bgwork-dialog-2026-09-10/, 2.1.260, PTY,
# three arms so the reading can be wrong):
#   no background work  → NO dialog, /exit EXITS          (the negative arm)
#   `sleep 600` running → dialog,    /exit does NOT exit  (the incident)
#   same + the keep-work index as ONE byte → EXITS        (the cure)
#
# WHAT IS DRIVEN. The detached `__recycle` watcher, directly, against a stub `it2` that renders the
# real captured screen for `session read` and logs every `session send`. The tty path does not
# exist, so pane_cc_state abstains, at_shell is never satisfied, and the watcher walks its loop —
# which is exactly the state the incident sat in.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  LIB="$REPO_SRC/hooks/lib/pane-modal.sh"
  [ -f "$HF" ] && [ -f "$LIB" ] || { echo "subject missing" >&2; return 1; }

  # M11 (MACHINE_CAPACITY_V2 §11.3) — both terms of the fire gate pinned off, ONE export per line:
  # the pin-guard ratchet (tests/handoff-fire-capacity-gate.bats _setup_gate_off) matches the literal
  # `export CC_FIRE_HEADROOM_GATE=off`, so a combined `export A=off B=off` line reads as UNPINNED.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export REAL_HOME="$HOME"
  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"; export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"
  export CC_PANE_MODAL_LIB="$LIB"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"; chmod +x "$SHIM/osascript"
  export PATH="$SHIM:$PATH"
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"

  # THE SCREEN, captured verbatim from the PTY probe — never hand-written. A fixture that renders
  # the menu differently from the binary is a fixture that cannot express this bug (MEMORY.md
  # fixture-identifier-shape-collapses-two-spaces).
  export SCREEN="$BATS_TEST_TMPDIR/screen.txt"
  cat > "$SCREEN" <<'SCR'
✻ Cooked for 10s · done 5:49 AM · 1 shell still running
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
   Background work is running
   The following will stop when you exit:

   shell · sleep 600

   ❯ 1. Exit and stop tasks
     2. Move to background and exit
     3. Stay
─
   Enter to confirm · Esc to cancel
SCR

  export STUB_PANE="BGWORK-PANE"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-BGWORK-PANE}"
    else printf '%s\n' "${STUB_PANE:-BGWORK-PANE}"; fi
    exit 0 ;;
  "session read") cat "$SCREEN"; exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"

  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'claude --permission-mode auto\n' > "$CMDFILE"
  export CMDFILE
  export HF_RECYCLE_SHELL_WAIT_S=6 CC_RECYCLE_BGWORK_EVERY_S=3
}

drive() { bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"; }
sends() { grep -c 'session send' "$H/it2-calls.log" 2>/dev/null || printf 0; }
alarms() { cat "$CC_HANDOFF_ALARM_DIR"/* 2>/dev/null; }

# ── the predicates, against the real screen ──────────────────────────────────────────────────────
@test "the dialog is RECOGNISED on the captured screen" {
  run bash -c ". '$LIB'; pane_bgwork_dialog < '$SCREEN'"
  [ "$status" -eq 0 ]
}

@test "the keep-work index is READ off the menu, not assumed" {
  run bash -c ". '$LIB'; pane_bgwork_choice < '$SCREEN'"
  [ "$status" -eq 0 ]
  [ "$output" = 2 ]
}

@test "MUTANT — a REORDERED menu yields the moved index, which is the whole point of reading it" {
  # If `2` were hardcoded, this screen would answer "Exit and stop tasks" and KILL a land in
  # flight. The mutant is the only thing that distinguishes a read index from a lucky constant.
  sed 's/❯ 1. Exit and stop tasks/❯ 1. Move to background and exit/; s/     2. Move to background and exit/     2. Exit and stop tasks/' "$SCREEN" > "$BATS_TEST_TMPDIR/swapped.txt"
  run bash -c ". '$LIB'; pane_bgwork_choice < '$BATS_TEST_TMPDIR/swapped.txt'"
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
}

@test "MUTANT — an UNINDEXED menu REFUSES rather than guessing a position" {
  sed 's/[0-9]\. //' "$SCREEN" > "$BATS_TEST_TMPDIR/noidx.txt"
  run bash -c ". '$LIB'; pane_bgwork_choice < '$BATS_TEST_TMPDIR/noidx.txt'"
  [ "$status" -ne 0 ]
}

@test "PROSE quoting the dialog is NOT a pane sitting at it (the cfdd9fc3 class)" {
  printf '%s\n' "It said Background work is running and offered 2. Move to background and exit." \
    > "$BATS_TEST_TMPDIR/prose.txt"
  run bash -c ". '$LIB'; pane_bgwork_dialog < '$BATS_TEST_TMPDIR/prose.txt'"
  [ "$status" -ne 0 ]
}

@test "MUTANT — the ANCHOR is what refuses prose; an unanchored matcher accepts it" {
  # Cases 5 and 6 pass pre-fix too (the function does not exist, so rc is 127 and a `-ne 0`
  # assertion is satisfied vacuously). They are EQUIVALENCE guards, and an equivalence guard is
  # worth nothing until something shows it has power (MEMORY.md: green in both arms is not a
  # red-proof). This is that something: the same conjunction with `_pane_modal_anchor` replaced by
  # a bare substring test — the implementation a successor would reach for — ACCEPTS the prose
  # screen that case 5 requires be refused.
  printf '%s\n' "It said Background work is running and offered 2. Move to background and exit." \
    > "$BATS_TEST_TMPDIR/prose.txt"
  # The shim is written to a FILE rather than inlined into `bash -c`. Inline, its body reads as a
  # top-level `A && B` to scripts/bats-assert-liveness-lint.py and lands as DEAD [and-absorbed] —
  # a true reading of the shape and a false one of the intent, since this is a function definition
  # inside a quoted string, not an assertion. A file keeps the mutant honest and the lint honest.
  cat > "$BATS_TEST_TMPDIR/unanchored.sh" <<'SHIM'
_pane_modal_both() {
  printf '%s\n' "$1" | grep -qE -- "$2" || return 1
  printf '%s\n' "$1" | grep -qE -- "$3"
}
SHIM
  run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/unanchored.sh'; pane_bgwork_dialog < '$BATS_TEST_TMPDIR/prose.txt'"
  [ "$status" -eq 0 ]   # the mutant ACCEPTS — which is exactly why the anchor is not decoration
}

@test "an EMPTY screen is never a dialog — a blind read cannot manufacture a keystroke" {
  : > "$BATS_TEST_TMPDIR/empty.txt"
  run bash -c ". '$LIB'; pane_bgwork_dialog < '$BATS_TEST_TMPDIR/empty.txt'"
  [ "$status" -ne 0 ]
}

# ── the watcher, driven ──────────────────────────────────────────────────────────────────────────
@test "RED-PROOF: the watcher ANSWERS the dialog with the index it read" {
  drive || true
  run cat "$H/it2-calls.log"
  echo "$output" | grep -q 'session send -s BGWORK-PANE 2'
}

@test "it is BOUNDED — a screen that never clears costs at most CC_RECYCLE_BGWORK_MAX keystrokes" {
  CC_RECYCLE_BGWORK_MAX=1 HF_RECYCLE_SHELL_WAIT_S=15 drive || true
  run bash -c "grep -c 'session send' '$H/it2-calls.log' || true"
  [ "$output" = 1 ]
}

@test "KILL SWITCH: CC_RECYCLE_BGWORK_ANSWER=off sends nothing at all" {
  CC_RECYCLE_BGWORK_ANSWER=off drive || true
  run bash -c "grep -c 'session send' '$H/it2-calls.log' || true"
  [ "$output" = 0 ]
}

@test "[RED] CANCEL (team relaunch): the watcher sends Esc — never a menu index — and types no relaunch" {
  run env CC_RECYCLE_BGWORK_ANSWER=cancel bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"recycle HELD"*"sent Esc (Stay)"*"NO relaunch was typed"* ]] || { echo "$output"; false; }
  run bash -c "grep 'session send' '$H/it2-calls.log' || true"
  [ "$(printf '%s\n' "$output" | grep -c 'session send')" = 1 ] || { echo "$output"; false; }
  [[ "$output" == *$'\e'* ]] || { echo "the one key sent was not Esc: $output"; false; }
  run bash -c "grep -c 'session run' '$H/it2-calls.log' || true"
  [ "$output" = 0 ] || { echo "a relaunch was typed after the cancel"; false; }
}

@test "a pane showing NO dialog is never sent a key (the negative arm of the actuator)" {
  printf '%s\n' "❯ ready" "────────────" "" "────────────" > "$SCREEN"
  drive || true
  run bash -c "grep -c 'session send' '$H/it2-calls.log' || true"
  [ "$output" = 0 ]
}

@test "the terminal alarm STOPS asserting the predecessor is gone when the dialog was seen" {
  # The shipped line says "the /exit landed, so the predecessor is GONE". Under this dialog the
  # /exit did NOT land and the session is alive at a menu — an operator handed the generic line
  # goes hunting for stranded work that is sitting right there.
  drive || true
  run alarms
  echo "$output" | grep -q 'THE /exit DID NOT LAND'
  echo "$output" | grep -qi 'nothing is stranded yet'
  echo "$output" | grep -q 'Move to background and exit'
}

@test "NO-DIALOG path is UNCHANGED — the terminal refusal still reads exactly as it did" {
  # An EQUIVALENCE guard, and labelled as one. It was written believing the empty-note line could
  # trip errexit and kill the watcher before its own refusal; the mutant (the `[ … ] && echo` form)
  # SURVIVED, and bash's errexit is measured to exempt a failing first command of an AND-OR list,
  # so that bug never existed. What the case does buy is the property the new note must not break:
  # a recycle that failed for any OTHER reason still reaches both operator lines and carries no
  # dialog sentence at all. Every other case in this file populates the note, so nothing else
  # covers the common path.
  printf '%s\n' "❯ ready" "────────────" "" "────────────" > "$SCREEN"
  run drive
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'never reached a CONFIRMED shell prompt'
  echo "$output" | grep -q 'Relaunch manually'
  ! echo "$output" | grep -q 'THE /exit DID NOT LAND'
}

@test "the answer is recorded in the ledger, so the class is countable rather than anecdotal" {
  drive || true
  run cat "$H/.claude/logs/handoffs.jsonl"
  echo "$output" | grep -q 'recycle-bgwork-answered'
}

# ── anti-rot: the fragments must still exist in the binary that renders them ─────────────────────
# tests/pane-modal.bats derives its anchor population with `compgen -v` over CC_MODAL_*_(HEADER|
# OPTION), so CC_MODAL_BGWORK_HEADER/_OPTION are pinned there the moment they are defined. The KEEP
# label is NOT matched by that suffix filter and would otherwise ship unpinned — an exact label the
# actuator selects ON is the one string whose rot would be most expensive, so it is anchored here.
@test "ANTI-ROT: the keep-work label is present in the shipping claude binary" {
  BIN=""
  for p in "$REAL_HOME"/.claude-*/node_modules/@anthropic-ai/claude-code/bin/claude.exe; do
    [ -f "$p" ] && BIN="$p"
  done
  [ -n "$BIN" ] || skip "no claude binary under \$HOME/.claude-*/ — a NON-VERDICT, not a pass"
  # shellcheck disable=SC1090  # the subject's path is resolved at runtime, by design
  . "$LIB"
  run bash -c "LC_ALL=C grep -qaF -- '$CC_MODAL_BGWORK_KEEP' '$BIN'"
  [ "$status" -eq 0 ]
}

# ── the predecessor's /goal is CLEARED before keep-work (recycle-bgwork-orphan, 2026-09-29) ─────
# "Move to background and exit" relocates the conversation to a background worker that KEEPS its
# /goal: on 2.1.284 session 43ef47fc took goal-driven turns for ~4 min beside its own successor.
# The remedy (measured end to end under a PTY, docs/research/recycle-bgwork-orphan-2026-09-29/):
# Esc → /goal clear → proven on disk → /exit again → the keep-work index on the dialog it re-raises.
#
# The stub is STATEFUL, because the property is an ORDER across screens: `dialog` renders the captured
# menu; Esc drops to a composer holding our /exit residue (the W5-rig shape); a bracketed paste fills
# the composer; CR submits it — `/goal clear` appends the harness's own sentinel record to the
# predecessor's transcript, `/exit` re-raises the dialog; a digit ends the session.
_goal_stub() {
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
st="$(cat "$HOME/stub.state" 2>/dev/null || echo dialog)"
cm="$(cat "$HOME/stub.composer" 2>/dev/null || true)"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-BGWORK-PANE}"
    else printf '%s\n' "${STUB_PANE:-BGWORK-PANE}"; fi
    exit 0 ;;
  "session read")
    case "$st" in
      dialog)   cat "$SCREEN" ;;
      composer) printf '%s\n' "────────────────────" "❯ $cm" "────────────────────" ;;
      *)        printf '%s\n' "(session ended)" ;;
    esac
    exit 0 ;;
  "session send")
    p="${5-}"
    case "$p" in
      $'\e')   [ "$st" = dialog ] && { echo composer > "$HOME/stub.state"; printf '/exit' > "$HOME/stub.composer"; } ;;
      $'\x15') : > "$HOME/stub.composer" ;;
      $'\x7f') printf '%s' "${cm%?}" > "$HOME/stub.composer" ;;
      $'\r')
        case "$cm" in
          "/goal clear")
            [ "${STUB_CLEAR_WRITES:-1}" = 1 ] && printf '%s\n' '{"type":"attachment","attachment":{"type":"goal_status","met":true,"sentinel":true,"condition":"ship it"}}' >> "$GOAL_TX"
            printf '%s' "${STUB_AFTER_CLEAR:-}" > "$HOME/stub.composer" ;;
          "/exit") echo dialog > "$HOME/stub.state"; : > "$HOME/stub.composer" ;;
          *) : > "$HOME/stub.composer" ;;
        esac ;;
      $'\e[200~'*) t="${p#$'\e[200~'}"; printf '%s%s' "$cm" "${t%$'\e[201~'}" > "$HOME/stub.composer" ;;
      [0-9]) echo gone > "$HOME/stub.state" ;;
    esac
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  export CC_PROJECTS_DIRS="$H/projects"
  mkdir -p "$H/projects/-p"
  export GOAL_TX="$H/projects/-p/sid-before.jsonl"
  printf '%s\n' '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"ship it"}}' > "$GOAL_TX"
  export CC_FIRE_COMPOSER_GATE=off FIRE_TYPE_SETTLE=0.05 FIRE_PASTE_PREIVL=1 CC_RECYCLE_GOAL_CLEAR_WAIT_S=2
  export HF_RECYCLE_SHELL_WAIT_S=12
}
# $6 = the predecessor sid, $8 = the goal the foreground inherited (inherit_recycle_goal, pre-/exit).
drive_goal() { bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR" sid-before "" "ship it" "$@"; }
row() { jq -c --arg c "$1" 'select(.class==$c)' "$H/.claude/logs/handoffs.jsonl" 2>/dev/null | tail -1; }
send_line() { grep -n "session send" "$H/it2-calls.log" | grep -F -- "$1" | head -1 | cut -d: -f1; }

@test "[RED] the goal is CLEARED, proven on disk, BEFORE the keep-work answer — and /exit goes back in" {
  _goal_stub
  drive_goal || true
  gc="$(send_line '/goal clear')"; ex="$(grep -n 'session send' "$H/it2-calls.log" | grep -F '/exit' | tail -1 | cut -d: -f1)"
  kw="$(send_line 'session send -s BGWORK-PANE 2')"
  cat "$H/it2-calls.log"   # shown only on failure
  [ -n "$gc" ]
  [ -n "$ex" ]
  [ -n "$kw" ]
  [ "$gc" -lt "$ex" ]
  [ "$ex" -lt "$kw" ]
  run jq -r 'select(.type=="attachment") | .attachment.met' "$GOAL_TX"
  [ "$(printf '%s\n' "$output" | tail -1)" = true ]
  run row recycle-bgwork-goal-clear
  [[ "$output" == *'goal=cleared'* ]] || { echo "$output"; false; }
}

@test "[RED] the answered row NAMES the predecessor (prev_sid) and says its goal was cleared" {
  _goal_stub
  drive_goal || true
  run row recycle-bgwork-answered
  [ "$(printf '%s' "$output" | jq -r '.prev_sid')" = sid-before ] || { echo "$output"; false; }
  [[ "$(printf '%s' "$output" | jq -r '.detail')" == *'predecessor goal=cleared'* ]] || { echo "$output"; false; }
}

@test "[RED] the successor still INHERITS: \$8 survives the clear (goal_requested stays true)" {
  # The clear empties the predecessor's transcript goal; the successor's condition is the one the
  # foreground captured before /exit. A watcher that re-read the transcript after the clear would
  # arm nothing — this row is written AFTER the clear, so it sees what the successor will be given.
  _goal_stub
  drive_goal || true
  run row recycle-bgwork-answered
  [ "$(printf '%s' "$output" | jq -r '.goal_requested')" = true ] || { echo "$output"; false; }
  run jq -r 'select(.type=="attachment") | .attachment.met' "$GOAL_TX"
  [ "$(printf '%s\n' "$output" | tail -1)" = true ]
}

@test "a clear the harness did NOT record reads as unverified, never as cleared" {
  _goal_stub
  STUB_CLEAR_WRITES=0 drive_goal || true
  run row recycle-bgwork-goal-clear
  [[ "$output" == *'goal=unverified'* ]] || { echo "$output"; false; }
}

@test "KILL SWITCH: CC_RECYCLE_BGWORK_GOAL_CLEAR=off answers directly, and the row says the goal is LIVE" {
  _goal_stub
  CC_RECYCLE_BGWORK_GOAL_CLEAR=off drive_goal || true
  run bash -c "grep -c 'session send' '$H/it2-calls.log'"
  [ "$output" = 1 ] || { cat "$H/it2-calls.log"; false; }
  run row recycle-bgwork-answered
  [[ "$output" == *'predecessor goal=live'* ]] || { echo "$output"; false; }
}

@test "RESUME MODE is left alone — the successor is the same session and carries the goal itself" {
  _goal_stub
  drive_goal "" "$BATS_TEST_TMPDIR/cfg" sid-before || true
  run bash -c "grep -F '/goal clear' '$H/it2-calls.log' || true"
  [ -z "$output" ] || { cat "$H/it2-calls.log"; false; }
  grep -q 'session send -s BGWORK-PANE 2' "$H/it2-calls.log"
}

@test "[RED] /exit cannot go back in ⇒ HELD loudly, nothing typed, and the alarm names the goal to re-arm" {
  _goal_stub
  STUB_AFTER_CLEAR="operator draft" CC_RECYCLE_GOAL_CLEAR_PREWAIT_S=0 run drive_goal
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"recycle HELD"*"/exit could not be re-submitted"* ]] || { echo "$output"; false; }
  run bash -c "grep -c 'session send -s BGWORK-PANE 2' '$H/it2-calls.log' || true"
  [ "$output" = 0 ]
  run alarms
  [[ "$output" == *'re-arm it in that pane: /goal ship it'* ]] || { echo "$output"; false; }
}
