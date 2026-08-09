#!/usr/bin/env bats
# P0-11 engagement verification + P0-12 registration guarantee for handoff-fire.sh (FM2 / INC-4).
#
# FM2 / INC-4 (memory cold-worktree-fire-autosubmit-race, 2026-07-17): a cold --worktree fire can
# race CC boot so the auto-submit keystroke is lost and the pane sits at an empty composer — 0
# commits, no ping — yet the fire printed "→ fired" exit 0. These tests prove the fix: a
# never-engaged fire now FAILS LOUD, and an engaged fire whose registry row never lands gets a
# provisional row.
#
# Isolation (fire-autonomy.bats pattern): HOME → a temp dir (config/projects/registry all under it;
# pre_trust no-ops with no .claude.json), IT2_BIN stubs the it2 transport, and the engagement /
# registration windows shrink to seconds via env. The pure detectors are extracted + sourced.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either
  # is past its bar — which turned 16 corpus tests RED purely because the machine was busy (map R-1),
  # a gate failing its own suite and blocking deploy verification. Both terms are pinned off here;
  # tests/handoff-fire-capacity-gate.bats is the ONE place the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # handoff-fire.sh bounds every external iTerm2 call (osascript / it2 CLI / iterm2 python) through
  # hf_bounded — a timeout(1) wrapper — because a wedged iTerm2 API blocks them indefinitely. These
  # suites EXTRACT individual functions instead of sourcing the script, so that helper is not in
  # scope and an extracted function would die with "hf_bounded: command not found". A passthrough
  # keeps the extracted behaviour byte-identical and deterministic; the helper's OWN semantics
  # (bound applied, expiry -> 124, set-but-empty disable seam) are covered by
  # tests/handoff-fire-it2-bound.bats against the real definition.
  hf_bounded() { "$@"; }
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  eval "$(sed -n '/^assistant_turn_in() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^engagement_seen() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^check_slash_head() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"

  HOMEDIR="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOMEDIR/.claude/projects" "$HOMEDIR/.claude/cc-registry"
  PROJ="$HOMEDIR/.claude/projects"
  REG="$HOMEDIR/.claude/cc-registry"
  PANE="FAKEPANE-0000-0000-0000-000000000001"

  PF="$BATS_TEST_TMPDIR/brief.md"
  printf 'BRIEF BODY line one\nline two\n' > "$PF"

  # it2 stub: `session split` echoes a fake pane; `session send`/`run` record the payload and
  # `session read` echoes it back (terminal-echo sim) so it2_type_verified's echo-verify passes;
  # focus + everything else are silent successes.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/it2" <<STUB
#!/bin/bash
LAST="$BATS_TEST_TMPDIR/it2-last-send"
case "\$1 \$2" in
  "session send"|"session run") printf '%s' "\${!#}" > "\$LAST" ;;
esac
case "\$*" in
  *"session split"*) echo "Created new pane: $PANE" ;;
  *"session read"*)  cat "\$LAST" 2>/dev/null ;;
  *) : ;;
esac
STUB
  chmod +x "$BIN/it2"
  # IT2_SHIM ($HOME/.claude/bin/it2) must EXIST or the script's `sed | head` REAL_IT2 probe aborts
  # under pipefail (in prod the shim is always present; IT2_BIN then overrides it to our stub).
  mkdir -p "$HOMEDIR/.claude/bin"; cp "$BIN/it2" "$HOMEDIR/.claude/bin/it2"
  # …and the variables the SUBJECT itself puts on every pane it launches. `--env CC_PANE_CMD=…` is
  # set on the launch, so every DESCENDANT of a fired pane carries them — including bats, when an
  # agent runs this suite from the pane that fired it. That is the shape a feature's own suite can
  # least afford: red exactly THERE, green everywhere else, so it reads as a genuine trunk red
  # (0588d255 — 5 failures across two sibling suites, one of them a negative CONTROL).
  # In setup, not per-test: a per-test unset leaves every OTHER test in the file inheriting, which
  # is rule 1's argument in scripts/test-hermeticity-lint.sh verbatim. Rule 6 there now enforces it.
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

# ---- P0-11 unit: engagement_seen (the pure detector) ----------------------------------------

@test "engagement_seen: marker in a transcript WITH an assistant turn -> engaged (0)" {
  mkdir -p "$PROJ/proj"
  { printf '{"type":"user","message":{"role":"user","content":"hi MARKER-XYZ ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]}}\n'
  } > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

# THE ff2d6609a33e RED: transcript BIRTH is not engagement. This is the exact live shape — the fired
# brief landed in the transcript (attachment/system rows + the harness's own /goal rejection line),
# the marker is present, and the model NEVER took a turn. The old birth-check called this engaged.
@test "engagement_seen: marker present but ONLY attachment/system rows (rejected /goal) -> NOT engaged (1)" {
  mkdir -p "$PROJ/proj"
  { printf '{"type":"attachment","content":"the brief MARKER-XYZ ok"}\n'
    printf '{"type":"system","content":"Goal condition is limited to 4000 characters"}\n'
  } > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: an assistant row with EMPTY content is not a turn -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"assistant","message":{"role":"assistant","content":""},"x":"MARKER-XYZ"}\n' > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: marker absent + no registry row -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"user","message":{"role":"user","content":"unrelated"}}\n' > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: registry session_id whose transcript HAS an assistant turn -> engaged (0)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}\n' \
    > "$PROJ/proj/sid-123.jsonl"
  printf '{"paneUUID":"%s","session_id":"sid-123"}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

# The registry row is written by the SessionStart hook — pure birth. On its own it must not engage.
@test "engagement_seen: registry session_id with NO assistant turn in its transcript -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"system","content":"boot"}\n' > "$PROJ/proj/sid-123.jsonl"
  printf '{"paneUUID":"%s","session_id":"sid-123"}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: registry row with NULL session_id -> not engaged (1)" {
  printf '{"paneUUID":"%s","session_id":null}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

# ---- ff2d6609a33e: the slash-command HEAD guard ----------------------------------------------

@test "check_slash_head: a plain-text first line passes silently" {
  printf 'TASK — do the thing.\nmore body\n' > "$BATS_TEST_TMPDIR/p1.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p1.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_slash_head: a /goal head over the cap is REFUSED (the silent-dead-fire shape)" {
  { printf '/goal do the thing.\n'; head -c 5000 /dev/zero | tr '\0' 'x'; printf '\n'; } \
    > "$BATS_TEST_TMPDIR/p2.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p2.txt"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'parses the ENTIRE submission'
}

# item c89b9c7b1526 — this test previously asserted `[ "$status" -eq 0 ]`: a short /goal head only
# WARNED and fired. That was never a statement about the harness, only about what had been measured
# — a slash head is parsed as a command whatever its length, so a short one submits `/goal <body>`
# and the pane gets a goal, not a task. The leading-blank-line half of the property is unchanged and
# is why it stays one test: blanks must not let a slash head slip past the scan.
@test "check_slash_head: a SHORT /goal head is REFUSED too — leading blank lines ignored" {
  printf '\n\n/goal read the plan and satisfy the DoD\n' > "$BATS_TEST_TMPDIR/p3.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p3.txt"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "STARTS with the slash command '/goal'"
}

# The [S2] shape from the 2026-07-22 reliability audit, and the whole reason the refusal was
# universalized: a brief that accidentally leads with a REAL command that is not /goal. Before this
# item it warned and fired, and on --recycle it then reported CONFIRMED off pure process liveness.
@test "check_slash_head: a NON-/goal slash head (/research) is REFUSED, not warned — audit [S2]" {
  printf '/research the design space of X\n\nmore brief body here\n' > "$BATS_TEST_TMPDIR/p5.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p5.txt"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q "STARTS with the slash command '/research'"
  # the override must be discoverable AT the refusal — see the guard's header comment
  printf '%s\n' "$output" | grep -q 'FIRE_ALLOW_SLASH_HEAD=1'
}

# NEGATIVE CONTROL for the case above: the refusal must key on "the first line is a slash command",
# never on "a slash appears at the head of a line". A path, a fraction, or an inline /command deeper
# in the brief are all normal brief content and must stay silent — a guard that also refuses those
# would refuse most real briefs, and the fleet-wide stop would read as this item's fault.
@test "check_slash_head: a LATER slash-command line does not trigger the head refusal" {
  printf 'TASK — do the thing.\n\nSTEP 2: run /research on the open axes.\n/ship when green.\n' \
    > "$BATS_TEST_TMPDIR/p6.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p6.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_slash_head: FIRE_ALLOW_SLASH_HEAD=1 bypasses the refusal" {
  { printf '/goal do the thing.\n'; head -c 5000 /dev/zero | tr '\0' 'x'; printf '\n'; } \
    > "$BATS_TEST_TMPDIR/p4.txt"
  run env FIRE_ALLOW_SLASH_HEAD=1 bash -c \
    "$(declare -f check_slash_head); check_slash_head '$BATS_TEST_TMPDIR/p4.txt'"
  [ "$status" -eq 0 ]
}

@test "cc-dispatch's composed brief does NOT start with a slash command (would be parsed as one)" {
  # LOCATOR, not a contract: this grep only has to FIND the composed TASK line so the assertion below
  # can inspect it. It was pinned to the whole parenthesised tail `(project $PROJECT)`, which
  # f90fd1bd rewrote to `(project $iproj, repo $irepo)` for multi-project dispatch — so the locator
  # matched nothing, `[ "$status" -eq 0 ]` failed, and the suite went red on trunk while the safety
  # property it guards was never actually in question. Anchor on the STABLE head of the line instead;
  # a locator that re-breaks on every wording change tests the wording, not the property.
  run grep -n 'cc-backlog item \$id (project ' "$REPO/bin/cc-dispatch"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q '"/'
}

# ---- P0-11 E2E: never-engaged FAILS LOUD (the RED->GREEN), engaged still succeeds ------------

@test "E2E: a never-engaged fire prints FIRE FAILED and exits non-zero (no false '→ fired')" {
  run env HOME="$HOMEDIR" IT2_BIN="$BIN/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_ENGAGE_TIMEOUT=1 FIRE_ENGAGE_RETRY=1 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 \
    FIRE_ENGAGE_MARKER=NEVER-SEEN-MARKER \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'FIRE FAILED — never engaged'
  ! printf '%s\n' "$output" | grep -q '→ fired'
}

# item 7146aab37a9a — the THIRD state. A pane parked on an interactive shell prompt is not a slower
# "never engaged": the launcher never ran, there is no session to recover, and the INC-4 re-send
# that fixes a real engagement miss would paste the brief into a shell that EXECUTES it. The fire
# must say so specifically, and must say it in seconds rather than after the 8-15min disk-poll
# window that let the live 2026-07-26 wedge die before any verdict was written.
#
# ── TWO ARMS, BECAUSE THE TRANSPORT CHANGED UNDERNEATH THIS TEST (item 4c5eddc16c2d) ────────────
# This was ONE test, and it went RED on trunk for a reason that indicts the FIXTURE, not the
# subject. fda70147 (item 2f074ef14947, the same day) made a kitty pane's command its ARGV: on a
# kitty box hf_argv_launch sets HF_ARGV_ACTIVE=1 and it2_land returns EARLY — the launch command is
# never typed, so there is no bracketed paste, no echo-verify and NO CR. The old stub keyed "the
# command was submitted" on seeing that CR, so it never flipped to the parked screen,
# pane_parked_reason correctly reported not-parked, and the fire fell through to the INC-4 verdict.
# The detector was healthy the whole time; the fixture was asserting through a retired transport.
#
# It could rot silently because the suite never PINNED the transport (M11: a test's environment is
# PINNED, not ambient). in_kitty() reads the FIRING process's own KITTY_WINDOW_ID, so this same
# file was green on an iTerm2 box and red on a kitty one — the host terminal, not the code, decided
# the verdict. Both transports are live and the parked verdict must reach the caller on either, so
# each gets its own arm with the transport pinned by its documented seam, and each carries the
# positive control that keeps it from silently degrading into the other:
#   TYPED (FIRE_ARGV_LAUNCH=0) — a `session send` MUST have happened.
#   ARGV  (kitty + a runner)   — NOTHING may have been typed, and $CC_PANE_CMD must have ridden the
#                                split. Without that pair, an arm that fell back to typing would
#                                pass just as well as one exercising the branch it names.
#
# The stub is keyed on the MECHANISM both share — "the command has been DELIVERED, by whatever
# transport delivered it" — not on the keystroke one of them happens to use, which is the property
# whose absence made the old one decay (memory: control-calibrated-to-implementation-decays).
# Delivery is the launch under argv and the CR under typing; only after it does the screen show the
# shell's refusal, which is exactly when the wedge becomes observable. Ordering matters on the
# typed arm: the echo-verify BEFORE the CR must still see the command, else typing fails first and
# the engagement gate is never reached.
#
# The SCREEN is a parameter, because the two transports do not wedge the same way. zsh's CORRECT
# prompt is raised by ZLE while READING a typed line, so the 2026-07-26 `[nyae]` shape belongs to
# the typed arm; an argv pane never reads a line through ZLE. What it CAN produce — and what the
# verdict's own remedy text names — is the launcher word failing to resolve, because the launchers
# are interactive-rc zsh functions and cc-pane-runner runs $CMD under `$SHELL -l -i -c`. Each arm
# therefore feeds the oracle a refusal ITS transport can actually generate. (Pattern coverage
# across all the shapes is tests/handoff-fire-pane-parked.bats's subject, not this suite's.)
parked_it2_stub() { # $1=path $2=the shell refusal its screen shows → an it2 stub that parks the
                    # pane once $CMD has been delivered
  cat > "$1" <<STUB
#!/bin/bash
LAST="$BATS_TEST_TMPDIR/it2-last-send2"
DELIVERED="$BATS_TEST_TMPDIR/cmd-delivered"
SENDS="$BATS_TEST_TMPDIR/it2-sends"
case "\$1 \$2" in
  # ARGV transport: delivery IS the launch — it2_split exports \$CC_PANE_CMD across this one call.
  "session split") [ -n "\${CC_PANE_CMD:-}" ] && : > "\$DELIVERED" ;;
  # TYPED transport: every send is recorded (the control), and the CR is the submit.
  "session send"|"session run")
    txt="\${!#}"; printf 'SEND\n' >> "\$SENDS"
    if [ "\$txt" = \$'\r' ]; then : > "\$DELIVERED"; else printf '%s' "\$txt" > "\$LAST"; fi ;;
esac
case "\$*" in
  *"session split"*) echo "Created new pane: $PANE" ;;
  # A real screen shows the refusal AND whatever is on the input line — never one INSTEAD of the
  # other. An either/or stub made this arm load-flaky, and the flake was measured, not theorised:
  # \`_it2_type_line\` submits with \`send CR && return 0\`, so a CR that TAKES EFFECT but whose bounded
  # call returns non-zero (a loaded box; observed once at 1-min load ~30) leaves DELIVERED set and
  # the function retrying. With either/or, every later echo-verify then reads a screen that no
  # longer echoes anything, all 4 attempts × 2 rounds fail, and the fire dies on "typing the launch
  # command failed" — red on the parked-verdict grep, having never reached the oracle. Reproduced
  # deterministically by making the first CR exit 1 after writing DELIVERED; green again with this.
  # Printing both is also the strictly more faithful model, and it weakens nothing: the oracle's
  # patterns are ^-anchored per physical line, and the echo-verify greps a whitespace-stripped
  # screen for its own nonce, so neither can be satisfied by the other's line.
  *"session read"*)
    [ -f "\$DELIVERED" ] && printf '%s\n' "$2"
    cat "\$LAST" 2>/dev/null ;;
  *) : ;;
esac
STUB
  chmod +x "$1"
  cp "$1" "$HOMEDIR/.claude/bin/it2"
  : > "$BATS_TEST_TMPDIR/it2-sends"      # so the control reads 0, not "file not found"
}

# `env -u CC_PANE_CMD` on BOTH arms is load-bearing, not tidiness. cc-pane-runner's variable is
# INHERITED by every descendant of an argv-launched pane (measured: a session fired this way has
# $CC_PANE_CMD set to its own launch line, and it reaches this suite's stub), so an ambient value
# would mark the command "delivered" at the split on the TYPED arm too — flipping the screen to the
# refusal before the echo-verify ever runs, and killing the fire on a path that tests nothing.
@test "E2E: a PARKED pane (zsh [nyae]) fails loud as parked, not as 'never engaged' [TYPED]" {
  local BIN2="$BATS_TEST_TMPDIR/bin2"; mkdir -p "$BIN2"
  parked_it2_stub "$BIN2/it2" "zsh: correct 'go' to 'god' [nyae]? "
  # FIRE_NOCORRECT=0 — 0e03861c types a separate `unsetopt correct correct_all` disarm line, with
  # its own CR, BEFORE the launch command. The stub keys the typed arm on a CR, so the disarm's CR
  # would flip it to the parked screen before the real command is ever typed — the echo-verify would
  # then fail and the fire would die on a different path. Pinning the disarm off keeps this arm about
  # the parked-pane verdict. (That disarm and this detector are complementary: it removes the cause,
  # this reports the state when anything else still produces it — including its own documented
  # failure mode, where it warns and PROCEEDS unprotected.)
  run env -u CC_PANE_CMD HOME="$HOMEDIR" IT2_BIN="$BIN2/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_NOCORRECT=0 FIRE_ARGV_LAUNCH=0 \
    FIRE_ENGAGE_TIMEOUT=5 FIRE_ENGAGE_RETRY=5 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 \
    FIRE_ENGAGE_MARKER=NEVER-SEEN-MARKER \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'pane PARKED, launcher never ran'
  printf '%s\n' "$output" | grep -q "correct 'go' to 'god'"
  # must NOT be misreported as the INC-4 shape, whose printed remedy is wrong here
  ! printf '%s\n' "$output" | grep -q 'FIRE FAILED — never engaged' || false
  ! printf '%s\n' "$output" | grep -q '→ fired' || false
  # CONTROL: this arm really did TYPE. Without it the arm passes identically on the argv path, and
  # the transport-blindness that made this test rot is back.
  [ -s "$BATS_TEST_TMPDIR/it2-sends" ]
  grep -q 'claude-test' "$BATS_TEST_TMPDIR/it2-last-send2"
}

# The SAME verdict on the transport that is now the default wherever kitty runs. Nothing is typed
# here at all, so a parked pane can only be caught by reading the pane — which is the whole point of
# the oracle, and the half the suite was blind to. in_kitty()'s env clause is forced (rather than
# inherited) so this arm is the argv path on an iTerm2 box too; CC_PANE_RUNNER_BIN points at the real
# runner because hf_argv_launch REFUSES to activate without an executable one (it degrades to typing,
# which the control below would catch).
@test "E2E: a PARKED pane fails loud as parked on the ARGV transport too (nothing typed) [ARGV]" {
  local BIN2="$BATS_TEST_TMPDIR/bin3"; mkdir -p "$BIN2"
  parked_it2_stub "$BIN2/it2" "zsh: command not found: claude-test"
  run env -u CC_PANE_CMD -u IT2_WRAPPER_NO_KITTY HOME="$HOMEDIR" IT2_BIN="$BIN2/it2" \
    TMPDIR="$BATS_TEST_TMPDIR" KITTY_WINDOW_ID=1 FIRE_ARGV_LAUNCH=1 \
    CC_PANE_RUNNER_BIN="$REPO/bin/cc-pane-runner" \
    FIRE_ENGAGE_TIMEOUT=5 FIRE_ENGAGE_RETRY=5 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 \
    FIRE_ENGAGE_MARKER=NEVER-SEEN-MARKER \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'pane PARKED, launcher never ran'
  printf '%s\n' "$output" | grep -q 'command not found: claude-test'
  ! printf '%s\n' "$output" | grep -q 'FIRE FAILED — never engaged' || false
  ! printf '%s\n' "$output" | grep -q '→ fired' || false
  # CONTROL, both halves: the command rode the SPLIT (so this is the argv branch), and NOTHING was
  # typed (so it did not quietly degrade to the typed arm above and prove that instead).
  [ -f "$BATS_TEST_TMPDIR/cmd-delivered" ]
  [ ! -s "$BATS_TEST_TMPDIR/it2-sends" ]
  # …and the verdict must not blame a keystroke on a transport that makes none. The arm above is
  # what made this checkable: nothing here was typed, so "the typed line" would be a false lead in
  # a fail-loud message whose whole job is naming the cause.
  ! printf '%s\n' "$output" | grep -q 'typed line' || false
  ! printf '%s\n' "$output" | grep -q 'The typed command was' || false
}

@test "E2E: an engaged fire (marker in a transcript) prints '→ fired' exit 0" {
  mkdir -p "$PROJ/proj"
  { printf '{"type":"user","message":{"role":"user","content":"the brief SEEN-MARKER ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n'
  } > "$PROJ/proj/s.jsonl"
  run env HOME="$HOMEDIR" IT2_BIN="$BIN/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_ENGAGE_TIMEOUT=5 FIRE_ENGAGE_RETRY=1 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 \
    FIRE_ENGAGE_MARKER=SEEN-MARKER \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '→ fired'
}

# ---- P0-12 unit: ensure_registration --------------------------------------------------------

@test "ensure_registration: an existing P8 row is NOT clobbered" {
  printf '{"paneUUID":"%s","session_id":"real-sid","pid":4242}\n' "$PANE" > "$REG/$PANE.json"
  before="$(cat "$REG/$PANE.json")"
  export FIRE_REG_TIMEOUT=0
  run ensure_registration "$REG" "$PANE" "nm" "/cwd" "cmd"
  [ "$status" -eq 0 ]
  [ "$(cat "$REG/$PANE.json")" = "$before" ]
}

@test "ensure_registration: no row -> writes a PROVISIONAL row (provisional:true, no pid)" {
  export FIRE_REG_TIMEOUT=0
  run ensure_registration "$REG" "$PANE" "desk-fire" "/some/cwd" "launcher xyz"
  [ "$status" -eq 0 ]
  [ -f "$REG/$PANE.json" ]
  run jq -e '.provisional == true and .paneUUID=="'"$PANE"'" and .name=="desk-fire" and (has("pid")|not)' "$REG/$PANE.json"
  [ "$status" -eq 0 ]
}

@test "ensure_registration: empty pane arg is a clean no-op" {
  export FIRE_REG_TIMEOUT=0
  run ensure_registration "$REG" "" "nm" "/cwd" "cmd"
  [ "$status" -eq 0 ]
}

# ---- T-P3-4 unit: mark_fired_peer (the cc-reaper auto-reap key) -------------------------------
# The marker is the ONLY thing that distinguishes a fired peer worker from an operator's own
# session, and cc-reaper will CLOSE a marked pane without asking. So the invariant that matters is
# not "it writes a file" — it is that nothing else can ever produce one.

@test "mark_fired_peer: writes a marker keyed by the fired pane UUID" {
  FPANE="2BE82E97-1111-4222-8333-444455556666"
  FDIR="$BATS_TEST_TMPDIR/fired"
  run mark_fired_peer "$FDIR" "$FPANE" "/work/cwd" "FIRING-0000-0000-0000-000000000002"
  [ "$status" -eq 0 ]
  [ -f "$FDIR/$FPANE.json" ]
  run jq -e '.selfRetire == true and .paneUUID=="'"$FPANE"'" and .cwd=="/work/cwd"' "$FDIR/$FPANE.json"
  [ "$status" -eq 0 ]
}

@test "mark_fired_peer: a non-UUID pane is refused (no marker, no path escape)" {
  # A pane value is never trusted as a path component — '../' must not reach the filesystem.
  FDIR="$BATS_TEST_TMPDIR/fired2"
  run mark_fired_peer "$FDIR" "../../etc/pwned" "/cwd" "by"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/etc/pwned.json" ]
  [ ! -d "$FDIR" ]
}

@test "mark_fired_peer: empty pane / empty dir are clean no-ops (fail-safe, never fatal)" {
  run mark_fired_peer "$BATS_TEST_TMPDIR/fired3" "" "/cwd" "by"
  [ "$status" -eq 0 ]
  [ ! -d "$BATS_TEST_TMPDIR/fired3" ]
  run mark_fired_peer "" "2BE82E97-1111-4222-8333-444455556666" "/cwd" "by"
  [ "$status" -eq 0 ]
}

@test "the fire path stamps the marker ONLY for a self-retiring peer fire" {
  # Guards the call-site condition, not just the function: a --no-self-retire or --recycle fire
  # must leave NO marker (⇒ cc-reaper treats it as an operator session ⇒ never auto-reaped).
  run grep -B4 'mark_fired_peer "$FIRED_DIR"' "$HF"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'if \[ "$WANT_SELF_RETIRE" = 1 \]; then'
}

@test "mark_fired_peer: persists the final fired brief beside the marker (recovery brief source)" {
  # cc-recover-safeguard re-fires THIS exact brief on a different model when a fire is refused DOA.
  FPANE="2BE82E97-1111-4222-8333-444455556666"; FDIR="$BATS_TEST_TMPDIR/firedP"
  PFB="$BATS_TEST_TMPDIR/final-brief.txt"
  printf 'You are a FRONTIER session.\nGoal: converge.\nPing back on completion.\n' > "$PFB"
  run mark_fired_peer "$FDIR" "$FPANE" "/work/cwd" "ORIG-0000-0000-0000-000000000009" "$PFB"
  [ "$status" -eq 0 ]
  [ -f "$FDIR/$FPANE.prompt" ]
  run diff "$PFB" "$FDIR/$FPANE.prompt"                 # byte-identical brief carried
  [ "$status" -eq 0 ]
}

@test "mark_fired_peer: omitted/absent prompt-file → marker written, no .prompt (fail-safe)" {
  FPANE="2BE82E97-1111-4222-8333-444455556666"; FDIR="$BATS_TEST_TMPDIR/firedQ"
  run mark_fired_peer "$FDIR" "$FPANE" "/work/cwd" "by"           # 4 args — no prompt-file
  [ "$status" -eq 0 ]
  [ -f "$FDIR/$FPANE.json" ]
  [ ! -f "$FDIR/$FPANE.prompt" ]
  run mark_fired_peer "$FDIR" "$FPANE" "/cwd" "by" "$BATS_TEST_TMPDIR/does-not-exist.txt"  # missing file
  [ "$status" -eq 0 ]
  [ ! -f "$FDIR/$FPANE.prompt" ]
}
