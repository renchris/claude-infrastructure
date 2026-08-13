#!/usr/bin/env bats
# spawn-wedge-watchdog.bats — proof for bin/cc-wedge-watch + hooks/lib/engagement.sh, the detector
# for a spawned Claude Code session that never produced an assistant turn (backlog 71908843ff77,
# docs/research/cc-startup-modals-2026-08-04.md §3).
#
# THE NEGATIVE ARM IS THE POINT OF THIS FILE. The census made it mandatory in words: "Positive
# control is mandatory (the anchor is UI text and will change) … must include a deliberately-stalled
# arm that FAILS the check. Without it, the day `? for shortcuts` changes every pane silently reads
# as wedged — or worse, someone inverts the check to quiet it." That day arrived four days later,
# before this detector shipped: `?forshortcuts` measured 0/23 on live panes (see @test "REGRESSION").
# So this suite pins BOTH directions — a stalled pane must PAGE, a healthy one must not — and pins
# the measurement that killed the census's own anchor.
#
# Hermetic: HOME is fixtured (test-hermeticity-lint RULE 1), kitty is a stub selected through the
# sanctioned CC_TERM_KITTY seam, the pager is a stub via CC_NOTIFY_BIN, and every run uses --now so
# the suite never sleeps for the real 180s deadline.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WATCH="$REPO/bin/cc-wedge-watch"
  LIB="$REPO/hooks/lib/engagement.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/cc-registry" "$HOME/.claude/projects/slug" "$HOME/.claude/bin"

  # Seams that do NOT resolve under $HOME, pinned per test-hermeticity-lint rules 2/5. This suite
  # only `sed`-extracts text from handoff-fire.sh (the parity pin) and never fires it, but pinning
  # is free and the alternative — an allowlist entry — is the exemption the ratchet exists to
  # prevent. Absent paths are the right value: every one of these sensors fails open on one.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_REGISTRY_DIR="$HOME/.claude/cc-registry"
  export CC_ENGAGE_HOMES="$HOME/.claude"

  PANE=4242
  SID="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
  PROJ="$HOME/.claude/projects/slug"

  # ── the kitty stub ────────────────────────────────────────────────────────────────────────────
  # Answers the two calls cc-wedge-watch makes: `@ ls --match id:N` (pane alive?) and `@ get-text
  # --match id:N` (what is on screen?). The screen content comes from a file the test writes, so a
  # test names a pane STATE rather than re-stubbing the binary.
  SCREEN_FILE="$BATS_TEST_TMPDIR/screen.txt"
  ALIVE_FILE="$BATS_TEST_TMPDIR/alive"
  echo 1 > "$ALIVE_FILE"
  KSTUB="$BATS_TEST_TMPDIR/kitty-stub"
  cat > "$KSTUB" <<STUB
#!/bin/bash
# args: @ [--to X] <verb> ...
for a in "\$@"; do
  case "\$a" in
    ls)       [ "\$(cat "$ALIVE_FILE")" = 1 ] && { echo '[{"id":$PANE}]'; exit 0; }; echo '[]'; exit 0 ;;
    get-text) cat "$SCREEN_FILE" 2>/dev/null; exit 0 ;;
  esac
done
exit 0
STUB
  chmod +x "$KSTUB"
  export CC_TERM_KITTY="$KSTUB"     # cc-kitty-bin's documented "explicit choice wins verbatim" seam
  unset KITTY_LISTEN_ON

  # ── the pager stub ────────────────────────────────────────────────────────────────────────────
  PAGED="$BATS_TEST_TMPDIR/paged.txt"
  NSTUB="$BATS_TEST_TMPDIR/notify-stub"
  cat > "$NSTUB" <<STUB
#!/bin/bash
printf '%s\n' "\$@" >> "$PAGED"
STUB
  chmod +x "$NSTUB"
  export CC_NOTIFY_BIN="$NSTUB"

  : > "$SCREEN_FILE"
  # The variables the pane tools this suite drives put on every pane THEY launch, and therefore
  # inherit from any pane launched that way — bats included, when an agent runs this from the pane
  # that fired it (0588d255: 5 failures on a pristine trunk, one of them a negative CONTROL).
  # In setup, not per-test: a per-test unset leaves every OTHER test inheriting.
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

# A transcript that shows a REAL assistant turn.
seed_engaged_transcript() {
  {
    printf '{"type":"system","subtype":"init"}\n'
    printf '{"type":"user","message":{"content":"go"}}\n'
    printf '{"type":"assistant","message":{"content":"working on it"}}\n'
  } > "$PROJ/$SID.jsonl"
}

# A transcript that exists but carries NO assistant turn — the ff2d6609a33e "birth is not
# engagement" state: rows landed, the model never ran.
seed_born_but_silent_transcript() {
  {
    printf '{"type":"system","subtype":"init"}\n'
    printf '{"type":"user","message":{"content":"go"}}\n'
  } > "$PROJ/$SID.jsonl"
}

seed_registry_row() { printf '{"paneUUID":"%s","session_id":"%s"}\n' "$PANE" "$SID" > "$CC_REGISTRY_DIR/$PANE.json"; }

# Screen states. The modal text is a REAL capture shape — a blocking dialog owns the screen, so
# none of the composer chrome is present.
screen_modal() { cat > "$SCREEN_FILE" <<'EOF'
 Try the new fullscreen renderer?

   Claude Code can use your terminal's alternate screen for a
   cleaner, flicker-free interface.

   1. Yes, use fullscreen
   2. No, keep the current renderer
EOF
}
screen_auto_mode_composer() { cat > "$SCREEN_FILE" <<'EOF'
> ready

  ──────────────────────────────────────────────
  (2) wt-abc123 (deadbeef) · max · 14% /rc
  ⏵⏵ auto mode on (shift+tab to cycle) · ← for agents
EOF
}
screen_shortcuts_composer() { cat > "$SCREEN_FILE" <<'EOF'
> ready

  ──────────────────────────────────────────────
  ? for shortcuts
EOF
}

# ── AXIS 1: the structural oracle (the item's own predicate) ─────────────────────────────────────

@test "engaged: a real assistant turn in the pane's transcript reads ENGAGED" {
  seed_registry_row; seed_engaged_transcript; screen_modal   # screen deliberately hostile
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"proof=registry:$SID"* ]]
}

@test "NEGATIVE ARM (mandatory): a stalled pane — no registry row, a modal on screen — PAGES" {
  # This is the deliberately-stalled arm the census required. If this test ever goes green while
  # asserting status 0, the detector has been inverted and the class is invisible again.
  screen_modal
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"WEDGED"* ]] || false
  [[ "$output" == *"engage_why=no-registry-row"* ]]
}

@test "NEGATIVE ARM: birth is not engagement — a transcript with no assistant turn still PAGES" {
  seed_registry_row; seed_born_but_silent_transcript; screen_modal
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"engage_why=transcript-without-assistant-turn"* ]]
}

@test "NEGATIVE ARM: a registry row without a session_id is birth, not engagement" {
  printf '{"paneUUID":"%s"}\n' "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  screen_modal
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 3 ]
  [[ "$output" == *"engage_why=row-without-session-id"* ]]
}

@test "the page reaches the pager, carries the pane id and the last screen" {
  screen_modal
  run "$WATCH" --pane "$PANE" --now          # NOT --dry-run: the real notify path
  [ "$status" -eq 3 ]
  [ -f "$PAGED" ]
  grep -q "SPAWN-WEDGED: pane $PANE" "$PAGED"
  grep -q "fullscreen renderer" "$PAGED"     # the operator needs to see WHICH dialog it is
}

# ── AXIS 2: the suppressor, and the measurement that demoted it from being the anchor ────────────

@test "suppressor: an auto-mode composer on screen reads ENGAGED even with no registry row" {
  screen_auto_mode_composer
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"proof=ui-anchor"* ]]
}

@test "REGRESSION: the anchor set must not be '? for shortcuts' alone (measured 0/23 live)" {
  # THE MEASUREMENT THIS PINS. docs/research/cc-startup-modals-2026-08-04.md §3 prescribed a
  # detector keyed on whitespace-collapsed `?forshortcuts`, "measured 9/9 across every probe".
  # Re-measured 2026-08-08 against the live fleet: PRESENT in 0 of 23 healthy working panes,
  # because every pane runs auto mode and its footer REPLACES that hint. Shipped as prescribed,
  # this detector's first act would have been to page 23 healthy panes.
  #
  # Both spellings must suppress: `?forshortcuts` is still correct for a pane NOT in auto mode.
  screen_auto_mode_composer
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 0 ]
  screen_shortcuts_composer
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 0 ]
  # And the guard against someone "simplifying" the set back to the dead anchor: with ONLY the
  # census's anchor configured, the auto-mode pane is unrecognised and pages. That is the failure
  # this suite exists to make loud.
  screen_auto_mode_composer
  CC_WEDGE_ANCHORS='?forshortcuts' run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 3 ]
}

@test "the box-drawing rule is NOT an anchor — a modal draws one too" {
  # A first cut used `─────` (present on 23/23 healthy panes). Every dialog draws a frame, so it
  # false-GREENs on the exact state this tool exists to catch.
  printf ' ┌──────────────────────┐\n │ Trust this folder?   │\n └──────────────────────┘\n' > "$SCREEN_FILE"
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 3 ]
}

# ── REFUSING TO PAGE ON EVIDENCE IT DOES NOT HAVE ────────────────────────────────────────────────

@test "a pane that has closed is NOT-APPLICABLE, never a page" {
  echo 0 > "$ALIVE_FILE"
  screen_modal
  run "$WATCH" --pane "$PANE" --now --dry-run
  [ "$status" -eq 4 ]
  [ ! -f "$PAGED" ]
}

@test "usage errors are rejected, not guessed" {
  run "$WATCH" --now --dry-run
  [ "$status" -eq 2 ]
  run "$WATCH" --pane "$PANE" --timeout notanumber --now
  [ "$status" -eq 2 ]
}

# ── AXIS 4: the SID-keyed entry point (backlog f76e7d78aaac) ─────────────────────────────────────
# cc_engaged_pane is keyed on a pane. scripts/limit-recover/lr-reset-poller.sh holds a SESSION ID
# and never a pane id — it claims a sid BEFORE the launcher→expect→claude chain exists — so the
# pane oracle was structurally unreachable from the one daemon in limit-recovery that survives its
# own spawns. cc_engaged_sid is that entry point, EXTRACTED from cc_engaged_pane rather than
# re-spelled beside it.

@test "sid oracle: a content-bearing assistant turn in <sid>.jsonl reads ENGAGED" {
  seed_engaged_transcript
  # No registry row on purpose — the whole point of the sid path is that it needs none.
  run bash -c '. "$1"; cc_engaged_sid "$2"; printf "rc=%s why=%s sid=%s proof=%s\n" \
                 "$?" "$CC_ENGAGE_WHY" "$CC_ENGAGE_SID" "$CC_ENGAGE_PROOF"' _ "$LIB" "$SID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]] || false
  [[ "$output" == *"why=assistant-turn"* ]] || false
  [[ "$output" == *"sid=$SID"* ]] || false
  [[ "$output" == *"proof=transcript:$SID"* ]] || false
}

@test "sid oracle: birth is not engagement — a transcript with no assistant turn is NOT engaged" {
  seed_born_but_silent_transcript
  run bash -c '. "$1"; cc_engaged_sid "$2"; printf "rc=%s why=%s\n" "$?" "$CC_ENGAGE_WHY"' \
      _ "$LIB" "$SID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=1"* ]] || false
  [[ "$output" == *"why=transcript-without-assistant-turn"* ]] || false
}

@test "sid oracle: an EMPTY sid is a reasoned abstain, never a positive" {
  # `find -name ".jsonl"` would otherwise sweep every account home for a file that cannot exist,
  # and a caller reading only the rc would get the same 1 with no way to tell the two apart.
  seed_engaged_transcript          # a real engaged session exists — the answer must still be no
  run bash -c '. "$1"; cc_engaged_sid ""; printf "rc=%s why=%s\n" "$?" "$CC_ENGAGE_WHY"' _ "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=1"* ]] || false
  [[ "$output" == *"why=no-session-id"* ]] || false
}

@test "EXTRACTION: cc_engaged_pane CALLS cc_engaged_sid — the search exists exactly once" {
  # memory: make-the-actuator-the-arbiter. Two spellings of "engaged" would diverge the day someone
  # improves one of them, and nothing would name the other. Pinned structurally because a
  # behavioural test cannot tell a call from a duplicated body.
  local pane_body
  pane_body="$(sed -n '/^cc_engaged_pane() {/,/^}/p' "$LIB")"
  [ -n "$pane_body" ]
  printf '%s' "$pane_body" | grep -q 'cc_engaged_sid'
  run bash -c 'grep -c -- "-name \"\$sid.jsonl\"" "$1"' _ "$LIB"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "EXTRACTION control: a re-inlined duplicate of the search is CAUGHT" {
  # Without this the count above passes vacuously the day the grep pattern stops matching at all
  # (memory: control-must-replay-the-real-artifact).
  local mutant="$BATS_TEST_TMPDIR/reinlined.sh"
  { cat "$LIB"; printf '  find "$t" -name "$sid.jsonl" -type f 2>/dev/null\n'; } > "$mutant"
  run bash -c 'grep -c -- "-name \"\$sid.jsonl\"" "$1"' _ "$mutant"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "PANE PATH UNCHANGED: proof still names the REGISTRY, not the transcript" {
  # The extraction must not leak the sid path's provenance into the pane path. cc-wedge-watch
  # prints CC_ENGAGE_PROOF verbatim (bin/cc-wedge-watch:276) and the operator reads it to know
  # which evidence answered.
  seed_registry_row; seed_engaged_transcript
  run bash -c '. "$1"; cc_engaged_pane "$2"; printf "rc=%s proof=%s why=%s\n" \
                 "$?" "$CC_ENGAGE_PROOF" "$CC_ENGAGE_WHY"' _ "$LIB" "$PANE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]] || false
  [[ "$output" == *"proof=registry:$SID"* ]] || false
  [[ "$output" == *"why=assistant-turn"* ]] || false
}

# ── THE PARITY PIN: two spellings of one predicate may never diverge ─────────────────────────────

@test "PARITY: assistant_turn_in in the lib is byte-identical to handoff-fire.sh's" {
  # hooks/lib/engagement.sh carries a COPY rather than handoff-fire.sh sourcing it, because six
  # suites sed-extract that function out of handoff-fire.sh as an isolated unit and a refactor
  # would break all six for a refactor's benefit. This test is what makes the copy safe: improve
  # one spelling and forget the other, and the gate names the file.
  local a b
  a="$(sed -n '/^assistant_turn_in() {/,/^}/p' "$REPO/scripts/handoff-fire.sh")"
  b="$(sed -n '/^assistant_turn_in() {/,/^}/p' "$LIB")"
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" = "$b" ]
}

@test "PARITY control: the comparison can actually FAIL (a mutated copy is caught)" {
  # Without this, the parity test above passes vacuously the day either sed range stops matching
  # (memory: control-must-replay-the-real-artifact — an extraction that yields "" equals another "").
  local mutant="$BATS_TEST_TMPDIR/mutant.sh" a b
  sed 's/^  \[ -s "\$f" \] || return 1/  [ -s "$f" ] || return 0/' "$LIB" > "$mutant"
  a="$(sed -n '/^assistant_turn_in() {/,/^}/p' "$REPO/scripts/handoff-fire.sh")"
  b="$(sed -n '/^assistant_turn_in() {/,/^}/p' "$mutant")"
  [ -n "$b" ]
  [ "$a" != "$b" ]
}

# ── THE ARMING SITE: a side-car that must never widen its own blast radius ───────────────────────

@test "arming: fires for a claude verb, stays out of the way for anything else" {
  eval "$(sed -n '/^_arm_wedge_watch() {/,/^}/p' "$REPO/bin/cc-pane-runner")"
  export KITTY_WINDOW_ID=999999
  # A stub cc-wedge-watch on the live-layer path records that it was armed.
  ARMED="$BATS_TEST_TMPDIR/armed.txt"
  cat > "$HOME/.claude/bin/cc-wedge-watch" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$ARMED"
STUB
  chmod +x "$HOME/.claude/bin/cc-wedge-watch"

  run _arm_wedge_watch "/usr/bin/env python3 monitor.py"
  [ "$status" -eq 0 ]
  run _arm_wedge_watch "cc-notify --role desk hi"
  [ "$status" -eq 0 ]
  [ ! -f "$ARMED" ]                                   # a non-session command must not arm

  _arm_wedge_watch "nocorrect claude4 --model x"      # `nocorrect` is stripped; verb is claude4
  sleep 0.3
  [ -f "$ARMED" ]
  grep -q -- "--pane 999999" "$ARMED"
  grep -q -- "--label claude4" "$ARMED"
}

@test "arming: a TEAM pane arms — claude.exe is the measured teammate spelling (bc50117059ac)" {
  # THE REGRESSION THIS PINS. Backlog bc50117059ac ranks the un-acked spawn surfaces by who survives
  # to notice: handoff successor first (fail-closed since 0a4c8c9c), then TEAM PANES. Team panes
  # reached this gate and fell out of it — the verb is `claude.exe` and `claude-*` does not match a
  # dot, so every Agent-Teams teammate launched with NO wedge watchdog at all.
  #
  # `claude.exe` is not a guess: capacity-alarm.sh:583 measured it as EXACTLY the `--agent-id`
  # teammate set, disjoint from the launcher family (intersection ZERO), and agent-identity.sh:14
  # records the same argv shape from the live 2.1.220 fleet.
  eval "$(sed -n '/^_arm_wedge_watch() {/,/^}/p' "$REPO/bin/cc-pane-runner")"
  export KITTY_WINDOW_ID=999999
  ARMED="$BATS_TEST_TMPDIR/armed.txt"
  cat > "$HOME/.claude/bin/cc-wedge-watch" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$ARMED"
STUB
  chmod +x "$HOME/.claude/bin/cc-wedge-watch"

  # The command as Claude Code delivers it: an absolute path to the agent binary plus the three
  # flags that identify a teammate. The basename is what the gate sees.
  _arm_wedge_watch "/Users/x/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id n@session-t --agent-name n --team-name t"
  sleep 0.3
  [ -f "$ARMED" ]
  grep -q -- "--pane 999999" "$ARMED"
  grep -q -- "--label claude.exe" "$ARMED"
}

@test "arming CONTROL: the widened gate can still REFUSE — a mention is not a verb" {
  # The mutation guard on the fix above. Adding a spelling to a gate is one edit away from widening
  # it into an argv match, and this gate's whole contract is "the verb is matched, not the whole
  # line". Both cases below name claude.exe and must NOT arm: one in the arguments, one as a
  # neighbouring spelling the evidence never covered (memory: denylist-enumerates-spellings-not-
  # the-class). If this goes green by accident the gate has stopped being a verb gate.
  eval "$(sed -n '/^_arm_wedge_watch() {/,/^}/p' "$REPO/bin/cc-pane-runner")"
  export KITTY_WINDOW_ID=999999
  ARMED="$BATS_TEST_TMPDIR/armed.txt"
  cat > "$HOME/.claude/bin/cc-wedge-watch" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$ARMED"
STUB
  chmod +x "$HOME/.claude/bin/cc-wedge-watch"

  run _arm_wedge_watch "bash cc-close-attrib /usr/lib/claude.exe --agent-name n"
  [ "$status" -eq 0 ]
  run _arm_wedge_watch "claude.py --probe"
  [ "$status" -eq 0 ]
  sleep 0.2
  [ ! -f "$ARMED" ]
}

@test "arming: the kill switch and an absent pane id are both silent no-ops" {
  eval "$(sed -n '/^_arm_wedge_watch() {/,/^}/p' "$REPO/bin/cc-pane-runner")"
  ARMED="$BATS_TEST_TMPDIR/armed.txt"
  cat > "$HOME/.claude/bin/cc-wedge-watch" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$ARMED"
STUB
  chmod +x "$HOME/.claude/bin/cc-wedge-watch"

  KITTY_WINDOW_ID=999999 CC_PANE_WEDGE_WATCH=0 run _arm_wedge_watch "claude"
  [ "$status" -eq 0 ]
  sleep 0.2
  [ ! -f "$ARMED" ]

  unset KITTY_WINDOW_ID
  run _arm_wedge_watch "claude"
  [ "$status" -eq 0 ]
  sleep 0.2
  [ ! -f "$ARMED" ]
}

@test "arming: survives set -u with every optional variable unset (blast radius)" {
  # This function runs INSIDE bin/cc-pane-runner's `set -u` region, before its `set +u`. An unbound
  # variable here does not degrade the watchdog — it aborts the runner and takes the pane's command
  # with it. That is a side-car failing wider than itself, and it is the failure mode the whole
  # guard exists to avoid.
  run bash -c '
    set -u
    eval "$(sed -n "/^_arm_wedge_watch() {/,/^}/p" "'"$REPO"'/bin/cc-pane-runner")"
    unset KITTY_WINDOW_ID CC_PANE_WEDGE_WATCH
    _arm_wedge_watch "claude" || true
    KITTY_WINDOW_ID=1 _arm_wedge_watch "claude" || true
    echo REACHED-END
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"REACHED-END"* ]]
}
