#!/usr/bin/env bats
# The last four surfaces that could ONLY drive iTerm2 — limit recovery, boot resume, pane census.
#
# WHY THIS SUITE EXISTS. Each of these four files opens (or counts) a pane by telling
# `application id "com.googlecode.iterm2"`, and each had no other spelling. On a kitty fleet that is
# not a cosmetic gap:
#   lr-handoff.sh          both call sites refuse ⇒ a limit handoff fires NOTHING and degrades to a
#                          manual-fallback line in stderr — in the one path whose whole job is to
#                          lose nothing.
#   lr-reset-poller.sh     spawn_gui refuses ⇒ every auto-resume lands in a DETACHED tmux session
#                          the operator never sees.
#   boot-resume-launch.sh  worse than inert: `open -a iTerm` RESURRECTS iTerm2 behind an operator
#                          whose fleet deliberately left it, then resumes into the wrong terminal.
#   render-census.sh       reports 0 panes on a box with a dozen live ones — and panes are the
#                          alarm's only shed lever.
#
# iTerm2 REMAINS THE DEFAULT: every kitty branch is gated on the predicate copied verbatim from
# bin/it2-wrapper:75 (kill switch included), and each iTerm2 assertion below pins the terminal so
# the incumbent path is tested even when the suite itself is run from inside kitty — which it now
# routinely is, and which would otherwise make these verdicts depend on the operator's window.
#
# THE PROPERTIES, in priority order:
#   1. INDETERMINATE ≠ ZERO. An unreadable terminal makes the census report null, never 0 — a 0
#      lets a caller reap a live fleet.
#   2. The failure TAXONOMY is preserved: boot-resume-launch still exits 3 for "driver unavailable"
#      and 4 for "driver failed", on both terminals, because callers key on those codes.
#   3. A kitty GUI spawn that fails still `return 1`s, so the poller's auto mechanism falls through
#      to tmux (LR-m) rather than stranding a resume.
#   4. The kitty split is ANCHORED on the invoking window and refuses a non-integer id, so it can
#      never fall through to --match-nothing and hijack the operator's active window.
#   5. The kill switch restores the byte-identical iTerm2 path in all four files.
#
# Hermeticity: fixture $HOME in setup(); `kitty` and `osascript` are both stubbed AND pinned via
# CC_TERM_KITTY, so no test can reach the operator's real fleet. Every assertion is `[ ]`, a bare
# command, or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and silently DEAD
# anywhere but a body's last line.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  BRL="$REPO/scripts/boot-resume-launch.sh"
  CENSUS="$REPO/scripts/render-census.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export KITTY_LOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KITTY_LOG"
  export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"; : > "$OSA_LOG"
  export OPEN_LOG="$BATS_TEST_TMPDIR/open.log"; : > "$OPEN_LOG"

  # kitty stub — records argv, opens nothing. KITTY_FAIL=1 fails every call; KITTY_SPLIT_FAIL=1
  # fails ONLY the in-window split, which is how the os-window fallback becomes reachable.
  # `@ ls` answers with KITTY_LS_JSON so the census parser is exercised on real JSON shape.
  cat > "$STUB/kitty" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${KITTY_LOG:?}"
if [ "${KITTY_FAIL:-0}" = 1 ]; then exit 1; fi
case " $* " in
  *" --type=window "*) [ "${KITTY_SPLIT_FAIL:-0}" = 1 ] && exit 1 ;;
esac
case " $* " in
  *" ls "*) printf '%s' "${KITTY_LS_JSON:-[]}"; exit 0 ;;
esac
echo 99
exit 0
STUB
  chmod +x "$STUB/kitty"
  export CC_TERM_KITTY="$STUB/kitty"

  # osascript stub — records argv AND (heredoc/`-` callers) stdin. Prints OSA_OUT on stdout, which
  # is how lr-handoff's FIRED capture sees a successful split.
  #
  # THE ECHO-VERIFY ARM (added 2026-08-10). Both iTerm2 arms below stopped at "a pane exists" until
  # 5fff9df6 split create from type: the launcher now goes in through osa_type_verified, which types
  # WITHOUT submitting, reads the pane's visible contents back, and sends the CR only if the line it
  # typed is on screen (scripts/lib/cc-type-verified.sh). A stub that answers every call with the
  # same OSA_OUT can never satisfy that read-back, so the verify fails, FIRED stays empty, and both
  # iTerm2 kill-switch tests fail for a reason that is purely fixture: the subject is fine.
  # Recognise the read-back call by its own last statement and echo the wire back — the helper
  # anchors on a per-attempt nonce it MINTS, so this can only be satisfied by the text the subject
  # actually typed on THIS attempt, never by a canned string. Trailing argv of that call is
  # <sid> <wire> <presettle> <settle>, so the wire is the third from the end.
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
[ "${OSA_FAIL:-0}" = 1 ] && exit 1
exit 0
STUB
  chmod +x "$STUB/osascript"

  # `open -a iTerm` must never run under kitty — record it rather than trust the read.
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${OPEN_LOG:?}"\nexit 0\n' > "$STUB/open"
  chmod +x "$STUB/open"

  # Default terminal pin = iTerm2. Each kitty test opts IN explicitly, so a stray KITTY_WINDOW_ID
  # inherited from the operator's own window can never decide a verdict here.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # PIN THE MACHINE, for the same reason the terminal is pinned above. boot-resume-launch.sh runs
  # cc_capacity_admit (scripts/lib/capacity-admit.sh) before it launches anything, and refuses above
  # 2.0 loadavg per core — so its three tests below go red BY LOAD on a busy box while the subject is
  # perfectly healthy. Measured 2026-08-10: green run after green run in isolation, then three
  # simultaneous failures inside a 228-test sweep that was itself driving the load, and no failure at
  # all on pristine trunk in the same order. That reads exactly like a regression in the diff and is
  # not one — the corpus was deciding a verdict on machine state. Same pin and same reasoning as
  # tests/handoff-orphaned-assignee.bats' CC_FIRE_CAPACITY_GATE; capacity-admit's own behaviour has
  # its own coverage in tests/capacity-admit.bats, which is where that gate is exercised ON.
  export CC_ADMIT_GATE=off
  export PATH="$STUB:$PATH"
}

# NEGATIVE assertions are `[ "$(… | grep -c PAT)" = 0 ]`. The three obvious spellings are all
# broken here and each was tried: `! grep` inverts the status and is errexit-EXEMPT (dead);
# `grep -qv` succeeds whenever ANY line fails to match, which is true of almost every log, so it
# asserts nothing; and `grep -q PAT && false` inverts correctly in the MIDDLE of a body but INVERTS
# ITSELF on the last line, where the list's status becomes the test's — measured, three tests went
# red for absence. A count is the only form that reads the same everywhere.
gone() { # $1=pattern, $2=file — assert the pattern does NOT appear
  [ "$(grep -c -- "$1" "$2" 2>/dev/null || true)" = "0" ]
}
gone_out() { # $1=pattern — same, against bats' $output
  [ "$(printf '%s\n' "$output" | grep -c -- "$1" || true)" = "0" ]
}

in_kitty() { unset IT2_WRAPPER_NO_KITTY; export KITTY_WINDOW_ID="${1:-31}"; }

# ── lr-handoff.sh — the recovery pane ─────────────────────────────────────────────────────────────

# The $HOME-rooted stubs lr-handoff reaches through $LR (lr-handoff.sh:41). Same seam the sibling
# suite tests/lr-handoff-launcher-quoting.bats uses; no source edit needed.
mk_handoff_fixture() {
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
  chmod +x "$HOME/.claude/scripts/limit-recover/"*.sh
}

fire() { # $1=sid, rest=extra args — the REAL --launch path, with every external stubbed
  local sid="$1"; shift
  env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$sid" --target next2 --cwd "$BATS_TEST_TMPDIR/plain" \
      --no-transplant --launch "$@"
}

@test "lr-handoff: inside kitty the recovery pane is a kitty vsplit ANCHORED on the invoking window" {
  mk_handoff_fixture
  in_kitty 31
  export ITERM_SESSION_ID="w0t0p0:31"      # the shim's synthesized form; ##*: yields the kitty id
  run fire "khan0001-0000-0000-0000-000000000001"
  [ "$status" -eq 0 ]
  grep -q -- '--type=window' "$KITTY_LOG"
  grep -q -- '--location=vsplit' "$KITTY_LOG"
  # both anchors, or kitty silently drops --next-to and the pane lands in the active tab
  grep -q -- '--match window_id:31' "$KITTY_LOG"
  grep -q -- '--next-to id:31' "$KITTY_LOG"
  grep -q -- '/bin/bash .*lr-launch-' "$KITTY_LOG"
  [ ! -s "$OSA_LOG" ]                       # the AppleScript surface was never touched
  echo "$output" | grep -q 'fired split pane'
}

@test "lr-handoff: a failed kitty split falls back to a kitty OS-WINDOW, never to iTerm2" {
  mk_handoff_fixture
  in_kitty 31
  export ITERM_SESSION_ID="w0t0p0:31" KITTY_SPLIT_FAIL=1
  run fire "khan0002-0000-0000-0000-000000000002"
  [ "$status" -eq 0 ]
  grep -q -- '--type=os-window' "$KITTY_LOG"
  [ ! -s "$OSA_LOG" ]
  echo "$output" | grep -q 'fired new kitty window'
}

@test "lr-handoff: a non-integer pane id inside kitty REFUSES the split (no hijack of the active window)" {
  # An iTerm2 UUID in ITERM_SESSION_ID means the env came from another terminal. Without the guard
  # `--match window_id:<uuid>` matches nothing and kitty would split whatever is focused.
  mk_handoff_fixture
  in_kitty 31
  export ITERM_SESSION_ID="w0t0p0:8F3C1D2E-AAAA-BBBB-CCCC-000000000001"
  run fire "khan0003-0000-0000-0000-000000000003"
  [ "$status" -eq 0 ]
  grep -q -- '--type=os-window' "$KITTY_LOG"
  gone '--type=window ' "$KITTY_LOG"      # `gone` supplies grep's own `--`; passing one here is $1
  [ ! -s "$OSA_LOG" ]
}

@test "lr-handoff: the kill switch restores the iTerm2 split verbatim (kitty untouched)" {
  mk_handoff_fixture
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1     # in kitty, but pinned to iTerm2
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="split"
  run fire "khan0004-0000-0000-0000-000000000004"
  [ "$status" -eq 0 ]
  grep -q 'split vertically with default profile' "$OSA_LOG"
  grep -q 'com.googlecode.iterm2' "$OSA_LOG"
  [ ! -s "$KITTY_LOG" ]
  echo "$output" | grep -q 'fired split pane'
}

# The CONTROL for the test above. Its verdict now depends on the osascript stub's read-back arm
# answering the echo-verify, so that arm must be able to say NO — otherwise the stub grants every
# fire a pass and "fired split pane" stops carrying information. OSA_TYPE_FAIL=1 makes the read-back
# silent (the pane's screen never shows the typed line), which is exactly the mangled-line case
# osa_type_verified exists for: the CR is never sent, FIRED stays empty, and the split must NOT be
# announced as fired.
@test "lr-handoff: a pane whose typed line cannot be verified is never announced as fired" {
  mk_handoff_fixture
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export ITERM_SESSION_ID="w0t0p0:31" OSA_OUT="split" OSA_TYPE_FAIL=1
  run fire "khan0009-0000-0000-0000-000000000009"
  [ "$status" -eq 0 ]
  grep -q 'split vertically with default profile' "$OSA_LOG"   # it was still ATTEMPTED
  gone_out 'fired split pane'
  [ ! -s "$KITTY_LOG" ]
}

# ── lr-reset-poller.sh — spawn_gui ────────────────────────────────────────────────────────────────

# Sourcing the poller whole is not an option (it polls and can fire resumes), so the spawn seam is
# extracted exactly as tests/kitty-divert-real-it2.bats extracts its subject.
load_spawn_gui() {
  # lrp_bounded degrades to a direct call, still bounded-shaped. Split onto separate lines because a
  # ShellCheck directive applies to the NEXT COMMAND only — on `A=1; B=2` it would cover A and not B.
  # (Capitalised deliberately: a comment whose first word is the lowercase tool name parses as a
  # MALFORMED DIRECTIVE and aborts analysis of the whole file, so nothing in it is checked at all.)
  # shellcheck disable=SC2034  # read by the eval-extracted lrp_bounded below
  LRP_TIMEOUT_BIN=""
  # shellcheck disable=SC2034  # read by the eval-extracted lrp_bounded below
  LRP_TIMEOUT_S=5
  eval "$(sed -n '/^lrp_bounded() {/,/^}/p' "$POLLER")"
  eval "$(sed -n '/^lrp_kitty() {/,/^}/p' "$POLLER")"
  eval "$(sed -n '/^spawn_gui() {/,/^}/p' "$POLLER")"
  # Extracting ONE function drops the top-level preamble with it, and since 5fff9df6 the iTerm2 arm
  # depends on two pieces of that preamble: the sourced osa_type_verified, and the LRP_TYPE_VERIFIED
  # flag it sets. Without them spawn_gui takes its "verified typing unavailable ⇒ refuse the GUI
  # path" branch and returns 1 — a REAL and deliberate behaviour, reached here only because the
  # fixture is incomplete, which is the extracted-function trap this file's own NOTE warns about.
  # Reproduce the preamble rather than stub the helper, so the assertions below still run against
  # the real echo-verify (answered by the osascript stub's read-back arm in setup()).
  # shellcheck source=../scripts/lib/cc-type-verified.sh
  # shellcheck disable=SC1091
  . "$REPO/scripts/lib/cc-type-verified.sh"
  # shellcheck disable=SC2034  # read by the eval-extracted spawn_gui above, which shellcheck cannot see
  LRP_TYPE_VERIFIED=1
}

@test "lr-reset-poller: inside kitty spawn_gui opens a kitty OS-window running the launcher" {
  in_kitty 31
  load_spawn_gui
  run spawn_gui "/tmp/lr-launch-fixture.sh"
  [ "$status" -eq 0 ]
  grep -q -- 'launch --type=os-window -- /bin/bash /tmp/lr-launch-fixture.sh' "$KITTY_LOG"
  [ ! -s "$OSA_LOG" ]
}

@test "lr-reset-poller: a kitty spawn failure returns 1 so \`auto\` still falls through to tmux (LR-m)" {
  in_kitty 31
  export KITTY_FAIL=1
  load_spawn_gui
  run spawn_gui "/tmp/lr-launch-fixture.sh"
  [ "$status" -eq 1 ]
}

@test "lr-reset-poller: no kitty binary is a GUI-unavailable return 1, not a stranded resume" {
  in_kitty 31
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/no-such-kitty"
  load_spawn_gui
  run spawn_gui "/tmp/lr-launch-fixture.sh"
  [ "$status" -eq 1 ]
  [ ! -s "$KITTY_LOG" ]
}

@test "lr-reset-poller: the kill switch restores the iTerm2 spawn verbatim (kitty untouched)" {
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  # The create call RETURNS the new session's id since 5fff9df6 — the command is addressed at that
  # id afterwards, so a stub answering with nothing is now "the window could not be made".
  export OSA_OUT="w0t0p1:5F1E0000-DEAD-BEEF-0000-000000000008"
  load_spawn_gui
  run spawn_gui "/tmp/lr-launch-fixture.sh"
  [ "$status" -eq 0 ]
  grep -q 'create window with default profile' "$OSA_LOG"
  grep -q 'com.googlecode.iterm2' "$OSA_LOG"
  # …and the launcher went in as a SEPARATE verified step, not as a rider on the create.
  grep -q 'exec /bin/bash /tmp/lr-launch-fixture.sh' "$OSA_LOG"
  gone 'with default profile command' "$OSA_LOG"
  [ ! -s "$KITTY_LOG" ]
}

# ── boot-resume-launch.sh — the boot resume window ────────────────────────────────────────────────

@test "boot-resume-launch: inside kitty --dry-run shows a kitty launch, not AppleScript" {
  in_kitty 31
  run env CC_RESUME_ONE_BIN=/Users/x/.reso/bin/reso-resume-one \
      bash "$BRL" --dry-run next4 /Users/x/wt sid-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'KITTY:'
  echo "$output" | grep -q -- '--type=os-window'
  echo "$output" | grep -q 'sid-123'
  gone_out 'create window with default profile'
}

@test "boot-resume-launch: inside kitty it launches kitty and NEVER \`open -a iTerm\`" {
  in_kitty 31
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/resume-one"; chmod +x "$BATS_TEST_TMPDIR/resume-one"
  run env PATH="$STUB:$PATH" CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/resume-one" \
      bash "$BRL" next4 "$BATS_TEST_TMPDIR" sid-123 feat/x
  [ "$status" -eq 0 ]
  grep -q -- 'launch --type=os-window' "$KITTY_LOG"
  grep -q 'sid-123' "$KITTY_LOG"
  grep -q 'feat/x' "$KITTY_LOG"
  [ ! -s "$OPEN_LOG" ]      # resurrecting iTerm2 behind the operator is the harm, not the fallback
  [ ! -s "$OSA_LOG" ]
}

@test "boot-resume-launch: a failed kitty launch keeps the rc-4 'driver failed' taxonomy" {
  in_kitty 31
  export KITTY_FAIL=1
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/resume-one"; chmod +x "$BATS_TEST_TMPDIR/resume-one"
  run env PATH="$STUB:$PATH" CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/resume-one" \
      bash "$BRL" next4 "$BATS_TEST_TMPDIR" sid-123
  [ "$status" -eq 4 ]
  echo "$output" | grep -q 'kitty launch failed'
}

@test "boot-resume-launch: a missing kitty binary keeps the rc-3 'driver unavailable' taxonomy" {
  in_kitty 31
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/no-such-kitty"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/resume-one"; chmod +x "$BATS_TEST_TMPDIR/resume-one"
  run env PATH="$STUB:$PATH" CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/resume-one" \
      bash "$BRL" next4 "$BATS_TEST_TMPDIR" sid-123
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'kitty unavailable'
}

@test "boot-resume-launch: a non-executable reso-resume-one still exits 3 on the kitty path" {
  # Terminal-independent guard: it must not be reachable only through the AppleScript arm.
  in_kitty 31
  run env PATH="$STUB:$PATH" CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/nope" \
      bash "$BRL" next4 "$BATS_TEST_TMPDIR" sid-123
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'reso-resume-one not executable'
}

@test "boot-resume-launch: the kill switch restores the byte-identical AppleScript" {
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  run env CC_RESUME_ONE_BIN=/Users/x/.reso/bin/reso-resume-one \
      bash "$BRL" --dry-run next4 /Users/x/wt sid-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'create window with default profile'
  echo "$output" | grep -q 'com.googlecode.iterm2'
  gone_out 'KITTY:'
}

# ── render-census.sh — the pane column ────────────────────────────────────────────────────────────

# A fast, deterministic `top` (the census bounds and parses the SECOND sample only).
make_top() {
  cat > "$STUB/top" <<'EOF'
#!/bin/bash
cat <<'BLOCK'
Processes: 100 total, 2 running, 98 sleeping, 500 threads
PID    COMMAND          %CPU
999    iTerm2           1.0
371    WindowServer     1.0
BLOCK
cat <<'BLOCK'
Processes: 100 total, 2 running, 98 sleeping, 500 threads
PID    COMMAND          %CPU
999    iTerm2           10.0
371    WindowServer     20.0
555    mds_stores       1.0
BLOCK
EOF
  chmod +x "$STUB/top"
}

census() {
  env PATH="$STUB:$PATH" CC_RENDER_SAMPLE_S=1 CC_RENDER_PAGE=off \
      CC_RENDER_LOG="$BATS_TEST_TMPDIR/render.jsonl" CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages" \
      bash "$CENSUS" --json --no-append
}

@test "render-census: inside kitty panes = every window across every tab of every OS window" {
  make_top
  in_kitty 31
  # 2 OS windows · 3 tabs · 5 windows total — a flat count would read 2, a per-tab count 3.
  export KITTY_LS_JSON='[{"tabs":[{"windows":[{"id":1},{"id":2}]},{"windows":[{"id":3}]}]},{"tabs":[{"windows":[{"id":4},{"id":5}]}]}]'
  run census
  echo "$output" | grep -q '"panes":5'
  [ ! -s "$OSA_LOG" ]
}

@test "render-census: an UNREADABLE kitty reports null — INDETERMINATE, never 0" {
  # The load-bearing property: a census that says 0 lets a caller reap a live fleet.
  make_top
  in_kitty 31
  export KITTY_FAIL=1
  run census
  echo "$output" | grep -q '"panes":null'
  gone_out '"panes":0'
}

@test "render-census: malformed kitty JSON is also null, not a guess" {
  make_top
  in_kitty 31
  export KITTY_LS_JSON='not json at all'
  run census
  echo "$output" | grep -q '"panes":null'
}

@test "render-census: the kill switch restores the iTerm2 AppleScript count (kitty untouched)" {
  make_top
  export KITTY_WINDOW_ID=31 IT2_WRAPPER_NO_KITTY=1
  export OSA_OUT="7"
  run census
  echo "$output" | grep -q '"panes":7'
  grep -q 'com.googlecode.iterm2' "$OSA_LOG"
  [ ! -s "$KITTY_LOG" ]
}
