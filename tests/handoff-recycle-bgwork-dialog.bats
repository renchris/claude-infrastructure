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

# THE DIALOG AT ANY WIDTH (FLEET_V2 W6 grown scope, 2026-09-30). At 29 columns Claude Code wraps its
# own modal (`Background work is` / `running`, `2. Move to background` / `and exit`; repro on pane
# 1371), the row-anchored matchers returned rc 1, the watcher never answered it and the nudge said
# `unknown` for 600 s. The fixtures are the measured 2.1.284 screen re-wrapped at 29, 40 and 80
# columns (.RECONSTRUCTED: word wrap with a 2-column right pad, which reproduces the measured split).
# Mutants: drop hf_screen_unwrapped from pane_bgwork_key (29 loses its key) · from pane_bgwork_seen
# (29 is not seen) · drop the nudge's bg-work-dialog arm (29 reads `unknown`).
wrap_funcs() {
  local f
  { echo 'hf_bounded() { "$@"; }'
    for f in hf_screen_unwrapped pane_bgwork_key pane_bgwork_seen composer_content recycle_nudge_decision; do
      sed -n "/^$f() {/,/^}/p" "$HF"; done; } > "$BATS_TEST_TMPDIR/wrap-funcs.sh"
}
@test "WIDTH: the dialog is seen, keyed 2, and named by the nudge at 29, 40 and 80 columns" {
  wrap_funcs
  local w fx="$REPO_SRC/tests/fixtures/lr-recon/screens"
  for w in 29 40 80; do
    export SCREEN="$fx/bgwork-dialog-2.1.284-${w}col.RECONSTRUCTED.txt"
    [ -s "$SCREEN" ] || { echo "no fixture for $w"; false; }
    run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/wrap-funcs.sh'; pane_bgwork_key '$H/.claude/bin/it2' P"
    [ "$status" -eq 0 ] || { echo "[$w] key rc=$status"; false; }
    [ "$output" = 2 ] || { echo "[$w] key=[$output]"; false; }
    run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/wrap-funcs.sh'; pane_bgwork_seen '$H/.claude/bin/it2' P"
    [ "$status" -eq 0 ] || { echo "[$w] seen rc=$status"; false; }
    run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/wrap-funcs.sh'; recycle_nudge_decision '$H/.claude/bin/it2' P"
    [ "$output" = bg-work-dialog ] || { echo "[$w] nudge=[$output]"; false; }
  done
  # The 29-column screen really is wrapped: the unchanged row-anchored matcher alone misses it.
  run bash -c ". '$LIB'; pane_bgwork_dialog < '$fx/bgwork-dialog-2.1.284-29col.RECONSTRUCTED.txt'"
  [ "$status" -ne 0 ] || { echo "the 29-col fixture is not wrapped"; false; }
  # Prose that merely quotes the dialog mid-sentence is still not a pane sitting at it.
  printf '%s\n' "It said Background work is running and offered 2. Move to background and exit." > "$BATS_TEST_TMPDIR/prose.txt"
  export SCREEN="$BATS_TEST_TMPDIR/prose.txt"
  run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/wrap-funcs.sh'; pane_bgwork_seen '$H/.claude/bin/it2' P"
  [ "$status" -ne 0 ] || { echo "prose read as the dialog"; false; }
  run bash -c ". '$LIB'; . '$BATS_TEST_TMPDIR/wrap-funcs.sh'; recycle_nudge_decision '$H/.claude/bin/it2' P"
  [ "$output" = unknown ] || { echo "nudge=[$output]"; false; }
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

# ── a SELF-recycle under agent-view-off: the dialog is raised by the recycle's OWN tool call (W7c) ──
# Measured on 2.1.284 under a PTY (docs/research/selfrecycle-agentview-off-2026-09-30/): an /exit typed
# while the session's own foreground Bash call is in flight raises "Background work is running", and
# with CLAUDE_CODE_DISABLE_AGENT_VIEW=1 the menu is only "Exit and stop tasks · Stay". Stay was the
# right answer and the whole answer, so the recycle held forever (pane 38, twice, 2026-09-30). The
# cure waits — dialog up, nothing sent — for that call to return, then Esc and /exit again; a dialog
# that comes back is somebody else's work and gets the old hold.
#
# The stub is stateful like _goal_stub, and it records whether the CALLER was alive at every send,
# because the property is an order across processes: no key may reach the pane while the call runs.
_selfcall_stub() {
  # The view-off menu over an in-flight call, verbatim from the probe's fgbash capture (pyte's stray
  # border cell before the footer dropped, as in the fixture above).
  printf '%s\n' \
    "✢ Seasoning… (20s · ↓ 215 tokens)" \
    "▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔" \
    "   Background work is running" \
    "   The following will stop when you exit:" \
    "" \
    "   shell · bash wait45.sh" \
    "" \
    "   ❯ 1. Exit and stop tasks" \
    "     2. Stay" \
    "" \
    "   Enter to confirm · Esc to cancel" > "$SCREEN"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
st="$(cat "$HOME/stub.state" 2>/dev/null || echo dialog)"
cm="$(cat "$HOME/stub.composer" 2>/dev/null || true)"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-BGWORK-PANE}"
    else printf '%s\n' "${STUB_PANE:-BGWORK-PANE}"; fi
    exit 0 ;;
  "session read")
    case "$st" in
      dialog)   cat "$SCREEN"; : > "$HOME/dialog-read" ;;
      composer) printf '%s\n' "────────────────────" "❯ $cm" "────────────────────" ;;
      *)        printf '%s\n' "(session ended)" ;;
    esac
    exit 0 ;;
  "session send")
    p="${5-}"
    if kill -0 "${CALLER_PID:-0}" 2>/dev/null; then cs=alive; else cs=gone; fi
    printf 'send caller=%s %q\n' "$cs" "$p" >> "$HOME/sends.log"
    case "$p" in
      $'\e')   [ "$st" = dialog ] && { echo composer > "$HOME/stub.state"; printf '%s' "${STUB_AFTER_ESC-/exit}" > "$HOME/stub.composer"; } ;;
      $'\x15') : > "$HOME/stub.composer" ;;
      $'\x7f') printf '%s' "${cm%?}" > "$HOME/stub.composer" ;;
      $'\r')
        if [ "$cm" = /exit ]; then
          if [ "${STUB_REDIALOG:-0}" = 1 ]; then echo dialog > "$HOME/stub.state"; else echo gone > "$HOME/stub.state"; fi
        fi
        : > "$HOME/stub.composer" ;;
      $'\e[200~'*) t="${p#$'\e[200~'}"; printf '%s%s' "$cm" "${t%$'\e[201~'}" > "$HOME/stub.composer" ;;
      [0-9]) echo gone > "$HOME/stub.state" ;;
    esac
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  # Not a lead: a team library that finds no members, so the subject's team read is hermetic.
  printf '%s\n' 'lr_team_snapshot() { echo snap; }' "lr_team_members() { echo \"\${STUB_MEMBERS:-0}\"; }" \
    > "$BATS_TEST_TMPDIR/lr-team.sh"
  export HF_LR_TEAM="$BATS_TEST_TMPDIR/lr-team.sh"
  export CC_FIRE_COMPOSER_GATE=off FIRE_TYPE_SETTLE=0.05 FIRE_PASTE_PREIVL=1 CC_RECYCLE_GOAL_CLEAR_PREWAIT_S=2
  export HF_RECYCLE_SHELL_WAIT_S=12
  # The recycle's own tool call: a real process the watcher can ask about. It lives until 3 s after
  # the watcher first READS the dialog — keyed on that read, not on a clock, because the watcher's
  # own start-up takes 5-20 s on this box under load — so the watcher has to WAIT for it.
  # CALLER_LIFE=<s> instead gives it a plain fixed life (the never-returns case).
  if [ -n "${CALLER_LIFE:-}" ]; then
    sleep "$CALLER_LIFE" >/dev/null 2>&1 3>&- &
  else
    # Bounded (60 s) and off bats' fd 3, so a case that never reads the dialog cannot hang the suite.
    ( n=0; until [ -f "$HOME/dialog-read" ] || [ "$n" -ge 300 ]; do /bin/sleep 0.2; n=$((n + 1)); done
      /bin/sleep 3 ) >/dev/null 2>&1 3>&- &
  fi
  CALLER_PID=$!; export CALLER_PID
}
# $6 = the predecessor sid; $16 = the invoking tool call the foreground resolved (hf_invoking_call_pid).
drive_sc() { bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR" sid-before "" "" "" "" "" "" "" "" "" "${1-$CALLER_PID}"; }
# `grep -c` prints 0 AND exits 1 on no match, so a `|| printf 0` fallback would print "00".
sc_sends() { local n; n="$(grep -c -- "${1:-.}" "$H/sends.log" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }

@test "[RED] SELF-RECYCLE, agent view off: waits for its own call, then Esc and /exit again — never 'stop tasks'" {
  _selfcall_stub
  run drive_sc
  cat "$H/sends.log" "$H/.claude/logs/handoffs.jsonl" 2>/dev/null   # shown only on failure
  [ "$(sc_sends 'caller=alive')" = 0 ]                              # nothing reached the pane mid-call
  [ "$(sc_sends "caller=gone \$'\\\\E'$")" = 1 ]                    # exactly one Esc (Stay)
  [ "$(sc_sends 'caller=gone.*/exit')" = 1 ]                        # /exit went back in once
  [ "$(sc_sends "caller=gone 1$")" = 0 ]                            # "1. Exit and stop tasks": never
  run row recycle-bgwork-selfcall
  [[ "$output" == *"own tool call pid $CALLER_PID returned:"* ]] || { echo "$output"; false; }
  [[ "$output" != *"returned:0s"* ]] || { echo "the watcher never had to wait: $output"; false; }
  run row recycle-held-bgwork
  [ -z "$output" ]
}

@test "[RED] the dialog COMES BACK after the retry ⇒ that is someone else's work: Stay, HELD, nothing typed" {
  _selfcall_stub
  STUB_REDIALOG=1 run drive_sc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"recycle HELD"*"sent Esc (Stay)"* ]] || { echo "$output"; false; }
  [ "$(sc_sends '/exit')" = 1 ] || { cat "$H/sends.log"; false; }  # one retry, never a second
  [ "$(sc_sends "\$'\\\\E'$")" = 2 ] || { cat "$H/sends.log"; false; }
  [ "$(sc_sends ' 1$')" = 0 ]
  run bash -c "grep -c 'session run' '$H/it2-calls.log' 2>/dev/null || true"
  [ "$output" = 0 ] || [ -z "$output" ]
}

@test "the call does NOT return inside the bound ⇒ one Esc (the old hold) and no /exit re-typed" {
  CALLER_LIFE=30 _selfcall_stub
  CC_RECYCLE_SELFCALL_WAIT_S=2 run drive_sc
  kill "$CALLER_PID" 2>/dev/null || true
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"did not return (still-running:2s)"*"recycle HELD"* ]] || { echo "$output"; false; }
  [ "$(sc_sends '/exit')" = 0 ] || { cat "$H/sends.log"; false; }
  [ "$(sc_sends "\$'\\\\E'$")" = 1 ] || { cat "$H/sends.log"; false; }
}

@test "NOT a self-recycle (no caller handed over) ⇒ unchanged: Stay at first sight, no retry" {
  _selfcall_stub
  run drive_sc ""
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"the menu offers no keep-work option"* ]] || { echo "$output"; false; }
  [ "$(sc_sends '/exit')" = 0 ] || { cat "$H/sends.log"; false; }
  [ "$(sc_sends 'caller=gone')" = 0 ] || { cat "$H/sends.log"; false; }  # held at once, not after a wait
}

@test "a LEAD with live members keeps Stay even on its own self-recycle" {
  _selfcall_stub
  STUB_MEMBERS=2 run drive_sc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(sc_sends '/exit')" = 0 ] || { cat "$H/sends.log"; false; }
  [ "$(sc_sends "\$'\\\\E'$")" = 1 ] || { cat "$H/sends.log"; false; }
}

@test "the KEEP-WORK menu (agent view on) is answered as before — the retry is for the view-off menu only" {
  _selfcall_stub
  cp "$BATS_TEST_TMPDIR/screen.keep" "$SCREEN" 2>/dev/null || printf '%s\n' \
    "   Background work is running" "   The following will stop when you exit:" "" "   shell · sleep 600" "" \
    "   ❯ 1. Exit and stop tasks" "     2. Move to background and exit" "     3. Stay" "" \
    "   Enter to confirm · Esc to cancel" > "$SCREEN"
  CC_RECYCLE_BGWORK_GOAL_CLEAR=off run drive_sc
  [ "$(sc_sends '/exit')" = 0 ] || { cat "$H/sends.log"; false; }
  [ "$(sc_sends ' 2$')" = 1 ] || { cat "$H/sends.log"; false; }
}

@test "KILL SWITCH: CC_RECYCLE_SELFCALL_RETRY=off restores the hold" {
  _selfcall_stub
  CC_RECYCLE_SELFCALL_RETRY=off run drive_sc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(sc_sends '/exit')" = 0 ] || { cat "$H/sends.log"; false; }
}

@test "[RED] Esc spent but /exit cannot go back in ⇒ HELD with NO second Esc (it would interrupt a live turn)" {
  _selfcall_stub
  STUB_AFTER_ESC="operator draft" run drive_sc
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"/exit could not be re-submitted"* ]] || { echo "$output"; false; }
  [ "$(sc_sends "\$'\\\\E'$")" = 1 ] || { cat "$H/sends.log"; false; }
  [ "$(sc_sends '/exit')" = 0 ] || { cat "$H/sends.log"; false; }
}

# ── the foreground half: which tool call are we running inside? ──────────────────────────────────
# Executed, not grepped: a fake `claude` on a real pty (script(1)) runs a shell that asks
# hf_invoking_call_pid about a pane tty. On its own tty it must name that shell; on any other tty
# (a peer recycling some other pane) it must name nothing.
_icp() { # $1 = "own" | "other" → prints "CALL=<tool-call shell pid> ANS=<answer|none> TTY=<tty>"
  local fn="$BATS_TEST_TMPDIR/icp-funcs.sh"
  { sed -n '/^pin_still_live() {/,/^}/p' "$HF"; sed -n '/^pid_is_cc() {/,/^}/p' "$HF"
    sed -n '/^hf_invoking_call_pid() {/,/^}/p' "$HF"; } > "$fn"
  mkdir -p "$BATS_TEST_TMPDIR/fakebin"
  # argv[0] = "claude", which is what pid_is_cc reads — the session process on the pane's pty.
  printf '#!/bin/bash\nexec -a claude bash "$@"\n' > "$BATS_TEST_TMPDIR/fakebin/claude"
  chmod +x "$BATS_TEST_TMPDIR/fakebin/claude"
  # The "tool call" is the `bash -c` the fake claude forks; the script it runs is two levels down.
  # shellcheck disable=SC2016  # expanded by the inner shells
  script -q /dev/null "$BATS_TEST_TMPDIR/fakebin/claude" -c '
    t="$(ps -o tty= -p $$ | tr -d " ")"; [ "$2" = other ] && t=ttys999
    bash -c "bash -c \". \\\"\$1\\\"; a=\\\$(hf_invoking_call_pid \$2); echo CALL=\$\$ ANS=\\\${a:-none} TTY=\$2\"" _ "$1" "$t"
  ' _ "$fn" "$1" | tr -d '\r'
}

@test "hf_invoking_call_pid names the tool-call shell whose parent is the claude on the pane's own tty" {
  command -v script >/dev/null || skip "script(1) absent — a NON-VERDICT, not a pass"
  run _icp own
  echo "$output"
  [[ "$output" =~ CALL=([0-9]+)\ ANS=([0-9]+) ]] || false
  [ "${BASH_REMATCH[2]}" = "${BASH_REMATCH[1]}" ]
}

@test "hf_invoking_call_pid names NOTHING when the claude above us owns another pane" {
  command -v script >/dev/null || skip "script(1) absent — a NON-VERDICT, not a pass"
  run _icp other
  echo "$output"
  [[ "$output" == *"ANS=none"* ]] || false
}

# ── STOP-IF-WATCHER (design-swap-v3 F15, 2026-10-04) ──────────────────────────────────────────────
# The move lane restarts an idle session with no model turn. A session whose only background job is
# its cc-await-ping mailbox watcher is answered "Exit and stop tasks"; everything else is answered
# Stay, as `cancel` does. The keep-work index (2 on this screen) is never sent.
# WHAT OLD CODE DOES WITH THE VALUE: `stop-if-watcher` is neither `cancel` nor `off`, so the pre-fix
# watcher fell through to the answer branch and sent the KEEP-WORK index 2 ("Move to background and
# exit"), the one answer this lane forbids. Every case below that asserts "2 is never sent" is
# therefore red on the pre-fix handoff-fire.sh.
SIW_L="Sun Oct  4 10:00:00 2026"
siw_env() { # $1=jobs: watcher | work | none
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"%s","pid":5000,"session_id":"siw-sid"}\n' "$STUB_PANE" > "$CC_REGISTRY_DIR/$STUB_PANE.json"
  export HF_PS_SNAPSHOT="$BATS_TEST_TMPDIR/siw-ps.txt"
  printf '%s\n' "5000 4000 $SIW_L claude --resume siw-sid" > "$HF_PS_SNAPSHOT"
  case "$1" in
    watcher)
      printf '%s\n' "5200 5000 $SIW_L /bin/zsh -c source \$HOME/.claude/shell-snapshots/snapshot-zsh-x.sh && eval '\$HOME/.claude/bin/cc-await-ping --timeout 3300'" \
        "5201 5200 $SIW_L /bin/bash \$HOME/.claude/bin/cc-await-ping --timeout 3300" >> "$HF_PS_SNAPSHOT" ;;
    work)
      printf '%s\n' "5100 5000 $SIW_L /bin/zsh -c source \$HOME/.claude/shell-snapshots/snapshot-zsh-x.sh && eval 'sleep 600'" \
        "5101 5100 $SIW_L sleep 600" >> "$HF_PS_SNAPSHOT" ;;
  esac
  export HF_TEAM_HOLD=off
}
siw_drive() { run env CC_RECYCLE_BGWORK_ANSWER=stop-if-watcher "$@" bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"; }
siw_keys() { grep 'session send' "$H/it2-calls.log" 2>/dev/null || true; }

@test "[RED] stop-if-watcher: a watcher-only session is answered with the STOP-TASKS index, never keep-work" {
  siw_env watcher
  siw_drive
  [[ "$output" == *"stop-if-watcher answered '1' (Exit and stop tasks)"* ]] || false
  siw_keys | grep -q 'session send -s BGWORK-PANE 1$'
  ! siw_keys | grep -q 'session send -s BGWORK-PANE 2$'
}

@test "[RED] stop-if-watcher: real background WORK is answered Stay and held — no index is sent" {
  siw_env work
  siw_drive
  [ "$status" -eq 1 ]
  [[ "$output" == *"stop-if-watcher HOLDS (its background jobs are not watcher-only"* ]] || false
  [[ "$output" == *"recycle HELD"*"sent Esc (Stay)"* ]] || false
  ! siw_keys | grep -qE 'session send -s BGWORK-PANE [0-9]$'
}

@test "[RED] stop-if-watcher: an unreadable stop-tasks index is answered Stay and held" {
  siw_env watcher
  sed -i '' 's/1\. Exit and stop tasks/Exit and stop tasks/' "$SCREEN"
  siw_drive
  [ "$status" -eq 1 ]
  [[ "$output" == *"stop-if-watcher HOLDS"* ]] || false
  ! siw_keys | grep -qE 'session send -s BGWORK-PANE [0-9]$'
}

@test "[RED] stop-if-watcher: a pane whose registry row names another session is held" {
  siw_env watcher
  printf '{"paneUUID":"%s","pid":5000,"session_id":"someone-else"}\n' "$STUB_PANE" > "$CC_REGISTRY_DIR/$STUB_PANE.json"
  run env CC_RECYCLE_BGWORK_ANSWER=stop-if-watcher bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR" siw-sid
  [ "$status" -eq 1 ]
  [[ "$output" == *"stop-if-watcher HOLDS (the pane's registry row names session someone-else"* ]] || false
  ! siw_keys | grep -qE 'session send -s BGWORK-PANE [0-9]$'
}

@test "[RED] KILL SWITCH: CC_RECYCLE_STOP_IF_WATCHER=off makes the value mean cancel — Stay, held, no index" {
  siw_env watcher
  siw_drive CC_RECYCLE_STOP_IF_WATCHER=off
  [ "$status" -eq 1 ]
  [[ "$output" == *"stop-if-watcher HOLDS (CC_RECYCLE_STOP_IF_WATCHER=off)"* ]] || false
  ! siw_keys | grep -qE 'session send -s BGWORK-PANE [0-9]$'
}

@test "stop-if-watcher leaves the other values alone: the default still answers the keep-work index it read" {
  siw_env watcher
  run bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"
  siw_keys | grep -q 'session send -s BGWORK-PANE 2$'
}
