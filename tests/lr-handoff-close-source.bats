#!/usr/bin/env bats
# lr-handoff.sh --close-source — retiring the pane the session LEFT.
#
# THE DEFECT. A limit or login-cliff recovery transplants the session to another account and fires a
# successor to carry it. The source pane survives that as a HUSK: a window over a transcript that
# moved, which will never produce another turn, and which is indistinguishable from live work in the
# operator's window. Closing it was an operator hand-step — and self-close refused to do it, because
# an operator-launched pane has no fired-peer stamp and the origin gate reads `origin`.
#
# TWO THINGS HAD TO EXIST FOR THE FIX, and this suite pins the second:
#   1. a named admissible class in self-close (tests/handoff-selfclose-transplanted-source.bats), and
#   2. A SUCCESSOR PANE ID TO NAME. lr-handoff's four spawn arms all THREW THE ID AWAY — FIRED only
#      ever held the literal string "split". kitty prints the new window id on stdout and the call
#      redirected it to /dev/null; the two AppleScript arms already `return id of` the new session
#      (osa_type_verified has to address it) and the value was simply dropped after typing.
#
# THE PROPERTY THAT MATTERS MOST is the NEGATIVE one: no pane id ⇒ NO CLOSE. A close that names no
# successor is exactly the vanishing pane the succession contract exists to prevent, so an
# uncapturable id must print the command and exit non-zero — never close anything blind. Two tests
# below drive that from each terminal's own failure mode.
#
# AND THE CLOSE GOES THROUGH self-close, NOTHING ELSE. Never `it2 session close`, never raw
# osascript, never a typed /exit. That is asserted directly rather than trusted: every one of those
# primitives is stubbed and its log required to be empty.
#
# Hermeticity: $HOME, $CLAUDE_CONFIG_DIR and TMPDIR are fixtures; kitty, osascript, open, cursor and
# handoff-fire.sh are all stubbed and PINNED via env seams, so no test can reach the operator's
# fleet or arm a real close. Negative assertions use the `[ "$(grep -c …)" = 0 ]` count form — `!
# grep` and `grep -q … && false` are both errexit-EXEMPT or self-inverting under bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  # --close-source drives handoff-fire, whose capacity_gate refuses a net-new fire above 2.0/core.
  # Unpinned, this suite would go red-by-LOAD on a busy box rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export KITTY_LOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KITTY_LOG"
  export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"; : > "$OSA_LOG"
  export HF_LOG="$BATS_TEST_TMPDIR/handoff-fire.log"; : > "$HF_LOG"
  export IT2_LOG="$BATS_TEST_TMPDIR/it2.log"; : > "$IT2_LOG"

  # kitty stub. KITTY_NEW_ID is what `@ launch` prints — the new window id — and it is a SEAM rather
  # than a constant so a test can hand back a non-integer and watch the id be rejected.
  cat > "$STUB/kitty" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${KITTY_LOG:?}"
if [ "${KITTY_FAIL:-0}" = 1 ]; then exit 1; fi
case " $* " in
  *" --type=window "*) [ "${KITTY_SPLIT_FAIL:-0}" = 1 ] && exit 1 ;;
esac
printf '%s\n' "${KITTY_NEW_ID-99}"
exit 0
STUB
  chmod +x "$STUB/kitty"; export CC_TERM_KITTY="$STUB/kitty"

  # osascript stub — records argv AND stdin. OSA_OUT is what the create/split arms read back as the
  # new pane's id; the `contents of s` arm answers osa_type_verified's echo-verify with the wire it
  # was handed, so the typed line VERIFIES. OSA_TYPE_FAIL=1 makes that read-back silent, which is the
  # unverifiable-pane case.
  cat > "$STUB/osascript" <<'STUB'
#!/bin/bash
printf 'ARGV: %s\n' "$*" >> "${OSA_LOG:?}"
if [ "$#" -eq 0 ] || [ "${1:-}" = "-" ]; then cat >> "$OSA_LOG"; fi
if [ "${OSA_TYPE_FAIL:-0}" != 1 ]; then
  case " $* " in
    *"return (contents of s)"*) printf '%s\n' "${@: -3:1}"; exit 0 ;;
  esac
fi
[ -n "${OSA_OUT:-}" ] && printf '%s\n' "$OSA_OUT"
exit 0
STUB
  chmod +x "$STUB/osascript"

  # The two teardown primitives that MUST NEVER be reached. Their logs are asserted empty.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${IT2_LOG:?}"\nexit 0\n' > "$STUB/it2"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/open"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cursor"
  chmod +x "$STUB/it2" "$STUB/open" "$STUB/cursor"

  # handoff-fire stub, pinned through the CC_HANDOFF_FIRE_BIN seam. Without the pin the subject would
  # resolve the REAL handoff-fire.sh beside itself and arm an actual close.
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${HF_LOG:?}"
exit "${HF_RC:-0}"
STUB
  chmod +x "$STUB/handoff-fire.sh"
  export CC_HANDOFF_FIRE_BIN="$STUB/handoff-fire.sh"

  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export PATH="$STUB:$PATH"

  # The session registry — the binding --source-pane is admitted on. Fixtured (never the operator's
  # live ~/.claude/cc-registry) through the same env seam handoff-fire reads.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"

  # --target next2 is validated against the generated account map, which resolves to a $HOME-relative
  # config dir and requires it to EXIST — so the fixture must provide it or every fire dies on
  # "bad target" before reaching any spawn arm.
  mkdir -p "$HOME/.claude/scripts/limit-recover" "$HOME/.claude/projects" \
           "$HOME/.claude-secondary/projects" "$BATS_TEST_TMPDIR/plain"
  cat > "$HOME/.claude/scripts/limit-recover/lr-audit.py" <<'PY'
import sys, json, os
a = sys.argv
out = a[a.index('--json') + 1]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"session_dir": "/nonexistent",
           "transcript_sha256": "deadbeef",
           "counts": {"gaps": 0}}, open(out, "w"))
PY
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/limit-recover/lr-preseed-env.sh"
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh"
  # lr-transplant stub: writes the tombstone + lock the real one does, so the fixture is the shape
  # --close-source's downstream gate is admitted on. Nothing here reads them (the close is stubbed);
  # they exist so the fixture cannot drift into an incoherent state a reader would trust.
  cat > "$HOME/.claude/scripts/limit-recover/lr-transplant.sh" <<'STUB'
#!/bin/bash
printf '{"ok":true,"sid":"stub","slug":"stub","target_transcript":"/dev/null"}\n'
exit 0
STUB
  chmod +x "$HOME/.claude/scripts/limit-recover/"*.sh
}

gone() { [ "$(grep -c -- "$1" "$2" 2>/dev/null || true)" = "0" ]; }
gone_out() { [ "$(printf '%s\n' "$output" | grep -c -- "$1" || true)" = "0" ]; }

fire() { # $1=sid, rest=extra args
  local sid="$1"; shift
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$sid" --target next2 --cwd "$BATS_TEST_TMPDIR/plain" \
      --no-transplant --launch "$@"
}

# `--no-transplant` is refused WITH --close-source (the close is admitted on the tombstone that flag
# never writes), so the close-driving tests need the transplant path — stubbed above.
fire_tx() { # $1=sid, rest=extra args
  local sid="$1"; shift
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$sid" --target next2 --cwd "$BATS_TEST_TMPDIR/plain" --launch "$@"
}

# every test asserts this: the ONLY teardown path is self-close
no_raw_teardown() {
  [ ! -s "$IT2_LOG" ]
  gone 'session close' "$OSA_LOG"
  gone '/exit' "$OSA_LOG"
}

# ── 1. the id is CAPTURED at each of the four spawn arms ─────────────────────────────────────────

@test "kitty vsplit: the new window id printed by \`kitty @ launch\` becomes the successor" {
  unset IT2_WRAPPER_NO_KITTY; export KITTY_WINDOW_ID=31
  export ITERM_SESSION_ID="w0t0p0:31" KITTY_NEW_ID=71
  fire_tx "clos0001-0000-0000-0000-000000000001" --close-source
  [ "$status" -eq 0 ]
  grep -q -- '--location=vsplit' "$KITTY_LOG"
  grep -q -- 'self-close --successor 71 --transplanted-source' "$HF_LOG"
  no_raw_teardown
}

@test "kitty os-window fallback: its id is captured too" {
  unset IT2_WRAPPER_NO_KITTY; export KITTY_WINDOW_ID=31
  export ITERM_SESSION_ID="w0t0p0:31" KITTY_SPLIT_FAIL=1 KITTY_NEW_ID=72
  fire_tx "clos0002-0000-0000-0000-000000000002" --close-source
  [ "$status" -eq 0 ]
  grep -q -- '--type=os-window' "$KITTY_LOG"
  grep -q -- 'self-close --successor 72 --transplanted-source' "$HF_LOG"
  no_raw_teardown
}

@test "iTerm2 split: the id the AppleScript returns becomes the successor" {
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1     # in kitty, pinned to iTerm2
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  fire_tx "clos0003-0000-0000-0000-000000000003" --close-source
  [ "$status" -eq 0 ]
  grep -q 'split vertically with default profile' "$OSA_LOG"
  grep -q -- 'self-close --successor w0t0p1:AAAA-SPLIT --transplanted-source' "$HF_LOG"
  [ ! -s "$KITTY_LOG" ]
  no_raw_teardown
}

@test "iTerm2 window fallback: the created window's session id becomes the successor" {
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  unset ITERM_SESSION_ID                                # no invoking pane ⇒ the create-window arm
  export OSA_OUT="w0t0p2:BBBB-WINDOW"
  fire_tx "clos0004-0000-0000-0000-000000000004" --close-source
  [ "$status" -eq 0 ]
  grep -q 'create window with default profile' "$OSA_LOG"
  grep -q -- 'self-close --successor w0t0p2:BBBB-WINDOW --transplanted-source' "$HF_LOG"
  no_raw_teardown
}

# ── 2. NO PANE ID ⇒ NO CLOSE — the property the whole flag turns on ──────────────────────────────

@test "a kitty id that is not an integer is REFUSED as a pane id: nothing is closed" {
  # kitty's window ids are integers. Anything else is a diagnostic or a format change, and passing it
  # on would send self-close hunting a pane that never existed. The split itself still stands.
  unset IT2_WRAPPER_NO_KITTY; export KITTY_WINDOW_ID=31
  export ITERM_SESSION_ID="w0t0p0:31" KITTY_NEW_ID="OK: launched"
  fire_tx "clos0005-0000-0000-0000-000000000005" --close-source
  [ "$status" -eq 3 ]
  [ ! -s "$HF_LOG" ]
  no_raw_teardown
  [[ "$output" == *"could NOT identify the pane it created"* ]] || { echo "$output"; false; }
  [[ "$output" == *"self-close --successor <successor-pane-id> --transplanted-source"* ]] || { echo "$output"; false; }
}

@test "an iTerm2 pane whose typed launcher cannot be VERIFIED is not named as successor" {
  # osa_type_verified never sent the CR, so the launcher may never have run in that pane. Naming it
  # as the continuation would hand the session to a husk — the exact failure self-close's engagement
  # gate exists to catch, reached here one layer earlier.
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT" OSA_TYPE_FAIL=1
  fire_tx "clos0006-0000-0000-0000-000000000006" --close-source
  [ "$status" -eq 3 ]
  [ ! -s "$HF_LOG" ]
  no_raw_teardown
  [[ "$output" == *"could NOT identify the pane it created"* ]] || { echo "$output"; false; }
}

@test "a failed kitty fire closes nothing and says so" {
  unset IT2_WRAPPER_NO_KITTY; export KITTY_WINDOW_ID=31
  export ITERM_SESSION_ID="w0t0p0:31" KITTY_FAIL=1
  fire_tx "clos0007-0000-0000-0000-000000000007" --close-source
  [ "$status" -eq 3 ]
  [ ! -s "$HF_LOG" ]
  no_raw_teardown
}

# ── 3. the flag's own preconditions, refused before any work is done ─────────────────────────────

@test "--close-source without --launch is refused: nothing fired ⇒ nothing to hand off to" {
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "clos0008-0000-0000-0000-000000000008" --target next2 \
      --cwd "$BATS_TEST_TMPDIR/plain" --print-only --close-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --launch"* ]] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ]
}

@test "--close-source with --no-transplant is refused: the close is admitted on the tombstone" {
  fire "clos0009-0000-0000-0000-000000000009" --close-source
  [ "$status" -eq 2 ]
  [[ "$output" == *"incompatible with --no-transplant"* ]] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ]
  [ ! -s "$OSA_LOG" ]          # refused BEFORE any work — nothing was fired
}

# ── 4. the controls ──────────────────────────────────────────────────────────────────────────────

@test "CONTROL: without --close-source the same fire closes nothing" {
  # Every assertion above is about a close happening; this is the one that shows the close is driven
  # by the FLAG and not by the fire. Without it the suite could not tell "--close-source works" from
  # "lr-handoff always calls self-close".
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  fire_tx "clos0010-0000-0000-0000-000000000010"
  [ "$status" -eq 0 ]
  grep -q 'split vertically with default profile' "$OSA_LOG"    # it DID fire
  [ ! -s "$HF_LOG" ]                                            # …and closed nothing
  no_raw_teardown
}

@test "a self-close that REFUSES is propagated, not swallowed" {
  # --close-source execs self-close, so self-close's verdict IS this script's exit status. A close
  # refused by the origin gate (or by a dead successor) must not read as a clean handoff.
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT" HF_RC=2
  fire_tx "clos0011-0000-0000-0000-000000000011" --close-source
  [ "$status" -eq 2 ]
  grep -q -- 'self-close --successor w0t0p1:AAAA-SPLIT --transplanted-source' "$HF_LOG"
}

@test "DEFAULT PATH BYTE-IDENTICAL: a self-close carries the same four words it always has" {
  # The remote form below APPENDS to this invocation, so the risk it introduces is that the ordinary
  # case — a session closing ITSELF — quietly starts carrying something new. Asserted as EQUALITY on
  # the whole recorded argv rather than as `grep -q` + absences: a grep for the four words passes on
  # a line that also carries a fifth, which is exactly the drift this must catch.
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  fire_tx "clos0018-0000-0000-0000-000000000018" --close-source
  [ "$status" -eq 0 ]
  [ "$(cat "$HF_LOG")" = "self-close --successor w0t0p1:AAAA-SPLIT --transplanted-source" ] \
    || { echo "argv drifted: $(cat "$HF_LOG")"; false; }
}

@test "the close NEVER passes --successor-assume-engaged or --allow-origin-close" {
  # Both would work and both are wrong. --allow-origin-close spends a safety gate on a case that can
  # prove it is safe; --successor-assume-engaged skips the assistant-turn check, and a transplant
  # whose successor never woke up is the one failure this close must not walk past.
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  fire_tx "clos0012-0000-0000-0000-000000000012" --close-source
  [ "$status" -eq 0 ]
  # The PRESENCE assertion comes first and is load-bearing: three `gone` checks over an EMPTY log all
  # pass, so without this the test would go green on a build where the close was never invoked at all
  # — measured, it survived the per-site mutant that removed the exec.
  grep -q -- 'self-close --successor w0t0p1:AAAA-SPLIT --transplanted-source' "$HF_LOG"
  gone 'allow-origin-close' "$HF_LOG"
  gone 'successor-assume-engaged' "$HF_LOG"
  gone 'terminal' "$HF_LOG"
}

# ── 5. --source-pane: retiring a pane OTHER than the invoker ─────────────────────────────────────
#
# THE CASE THE FLAG EXISTS FOR, measured 2026-08-10. Three sessions were transplanted off next3
# while next3 sat at 100% of its 5-hour window. A session at its limit CANNOT EXECUTE A TURN, so it
# cannot run the command that retires it — the recovery has to be driven from a THIRD pane, where
# --close-source alone closes the DRIVER. So the flag was not used and three husk panes were left
# standing: the operator asked for this behaviour explicitly and did not get it.
#
# WHY THE NAIVE VERSION WAS CORRECTLY REFUSED, and what makes this one safe: letting a caller assert
# "pane P holds session X" with nothing tying P to X retires an innocent pane that merely got named.
# The registry row is the tie, from an independent producer (hooks/session-start.sh) and with an
# existing consumer (handoff-fire's successor_pin reads the SAME row to prove the successor half of
# this very close). Every test below but the first is a REFUSAL, because a binding nothing can fail
# is not a binding.

reg_row() { # $1=pane · $2=session_id (omit for a row that names none)
  if [ -n "${2:-}" ]; then
    printf '{"paneUUID":"%s","name":"n","cwd":"%s","account":"claude-tertiary","pid":4242,"session_id":"%s"}\n' \
      "$1" "$BATS_TEST_TMPDIR/plain" "$2" > "$CC_REGISTRY_DIR/$1.json"
  else
    printf '{"paneUUID":"%s","name":"n","cwd":"%s","account":"claude-tertiary","pid":4242}\n' \
      "$1" "$BATS_TEST_TMPDIR/plain" > "$CC_REGISTRY_DIR/$1.json"
  fi
}

@test "--source-pane: a registry row naming the transplanted session admits closing ANOTHER pane" {
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  local sid="clos0013-0000-0000-0000-000000000013"
  reg_row "w0t0p9:HUSK" "$sid"
  fire_tx "$sid" --close-source --source-pane "w0t0p9:HUSK"
  [ "$status" -eq 0 ]
  # The pair is what handoff-fire re-checks; passing only the pane would let the registry supply
  # whatever session that pane happens to hold, which is not a check.
  grep -q -- "self-close --successor w0t0p1:AAAA-SPLIT --transplanted-source --source-pane w0t0p9:HUSK --source-session $sid" "$HF_LOG"
  gone 'allow-origin-close' "$HF_LOG"
  gone 'successor-assume-engaged' "$HF_LOG"
  no_raw_teardown
}

@test "CONTROL A: the row names a DIFFERENT session — refused, and refused BEFORE the fire" {
  # The whole hazard in one test. Without the binding this pane id would simply be passed through
  # and a live, unrelated session retired. The refusal also lands before any work: a transplant that
  # has already moved the transcript cannot be un-fired by a later refusal.
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  reg_row "w0t0p9:HUSK" "SOMEONE-ELSE-0000-0000-000000000000"
  fire_tx "clos0014-0000-0000-0000-000000000014" --close-source --source-pane "w0t0p9:HUSK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"does NOT hold session clos0014"* ]] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ]
  [ ! -s "$OSA_LOG" ]
  no_raw_teardown
}

@test "CONTROL B: no registry row for that pane — refused, nothing closed" {
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  fire_tx "clos0015-0000-0000-0000-000000000015" --close-source --source-pane "w0t0p9:NOROW"
  [ "$status" -eq 2 ]
  [[ "$output" == *"has no session-registry row"* ]] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ]
  [ ! -s "$OSA_LOG" ]
  no_raw_teardown
}

@test "CONTROL C: the row exists but names no session_id — refused, never guessed at" {
  # A row without one records that a pane exists, not which session lives in it. successor_pin
  # refuses the same row for the same reason one gate later (handoff-fire.sh:2192).
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="w0t0p1:AAAA-SPLIT"
  reg_row "w0t0p9:HUSK"
  fire_tx "clos0016-0000-0000-0000-000000000016" --close-source --source-pane "w0t0p9:HUSK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"names no .session_id"* ]] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ]
  [ ! -s "$OSA_LOG" ]
  no_raw_teardown
}

@test "--source-pane without --close-source is refused: it names the pane the close would retire" {
  reg_row "w0t0p9:HUSK" "clos0017-0000-0000-0000-000000000017"
  fire_tx "clos0017-0000-0000-0000-000000000017" --source-pane "w0t0p9:HUSK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --close-source"* ]] || { echo "$output"; false; }
  [ ! -s "$HF_LOG" ]
}
