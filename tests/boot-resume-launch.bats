#!/usr/bin/env bats
# boot-resume-launch.sh — the TTY-coupled resume seam (T-P16-2). The GUI drive (iTerm2) is not
# unit-testable, but --dry-run makes the command-construction (shell-quoting a spacey cwd, the
# osascript assembly, the reso-resume-one arg order) fully verifiable without a display.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LAUNCH="$REPO/scripts/boot-resume-launch.sh"
  export CC_RESUME_ONE_BIN="/Users/x/.reso/bin/reso-resume-one"
  # PIN THE TERMINAL. Since 2026-07-31 the script has a kitty arm, so every assertion below is
  # about the iTerm2 arm SPECIFICALLY — and this suite is now routinely run from inside kitty,
  # where an inherited KITTY_WINDOW_ID would otherwise decide the verdict. The kitty arm has its
  # own suite (tests/kitty-recovery-launch.bats).
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # PIN THE SUBJECT'S WALL-CLOCK BUDGET (LOAD_INSENSITIVE_VERIFY_V2 §3 / §6b channel 3, and the
  # same discipline tests/cc-authbrowser.bats setup() already applies to its two budgets).
  # scripts/boot-resume-launch.sh:41 bounds the bin/cc-kitty-socket resolver at
  # CC_OSA_TIMEOUT_S:-20. If that bound fires, _brl_sock is empty, IN_KITTY stays 0, dispatch
  # falls to the iTerm2 arm and no `KITTY: ` line is printed — a PLAUSIBLE RED that is a
  # statement about how fast the box is, not about the tree. Unpinned, the daemon-context tests
  # below measure the load average of a box designed to run 20-40 concurrent sessions.
  #
  # A CEILING, NOT A SLEEP: `timeout N` returns the instant the resolver answers, so a generous
  # value costs a passing run nothing. Deliberately NOT a bigger constant in the SUBJECT — §5's
  # rejected row ("raise the ceiling until tests pass"): time is unbounded above under that
  # steady state, so any production constant is a future permanent-red. The seam is the fix.
  # The positive control below proves this pin is REACHED rather than decorative.
  export CC_OSA_TIMEOUT_S=180
  # A FIXTURE HOME: the successful-launch cases below reach cc_log_pane_spawn, whose log lives
  # under $HOME — a stubbed launch must never write a row into the operator's live spawn log.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # THE CAPACITY GATE'S STATE IS A FIXTURE. The capacity cases below reach the REAL gate, whose
  # refusal BUDGET and IDL default to ~/.claude/autonomy — on 2026-09-28 the segments case wrote
  # "refusal 1 of 3" into the PRODUCTION budget, spending the box's real admission bound on a test.
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # RESUME DEBT (CLOSE_RESUME_CUSTODY §2 D4) — a recorder, never the real ledger.
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt"
  # An INDETERMINATE launch (exit 6) leaves its token here for cc-resume-debt's sweep — a fixture.
  export CC_PENDING_LAUNCH_DIR="$BATS_TEST_TMPDIR/pending-launch"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/debt.log"\n' "$BATS_TEST_TMPDIR" > "$CC_RESUME_DEBT_BIN"
  chmod +x "$CC_RESUME_DEBT_BIN"
  unset CC_RESUME_DEBT_SETTLING
}

# A successful kitty launch, fully stubbed: kitty accepts `@ launch`, the engine exists, the gate admits.
kitty_ok_env() {
  unset IT2_WRAPPER_NO_KITTY CC_TERM_KITTY_TO KITTY_LISTEN_ON
  export KITTY_WINDOW_ID=1
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/kitty"; chmod +x "$BATS_TEST_TMPDIR/kitty"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/kitty"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/rro-k"; chmod +x "$BATS_TEST_TMPDIR/rro-k"
  export CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/rro-k"
  export CC_ADMIT_GATE=off
}

@test "RESUME DEBT: a successful kitty launch opens ONE debt carrying the sid, cwd, account and cfg" {
  kitty_ok_env
  run bash "$LAUNCH" next3 /tmp sid-debt-1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(wc -l < "$BATS_TEST_TMPDIR/debt.log" | tr -d ' ')" -eq 1 ]
  grep -q '^open --sid sid-debt-1 --cfg .*/\.claude-tertiary --cwd /tmp --account next3 --by boot-resume-launch$' \
    "$BATS_TEST_TMPDIR/debt.log" || { cat "$BATS_TEST_TMPDIR/debt.log"; false; }
}

@test "RESUME DEBT: a dry run opens NO debt" {
  kitty_ok_env
  run bash "$LAUNCH" --dry-run next3 /tmp sid-debt-2
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^KITTY: '                  # positive control: it took the kitty arm
  [ ! -e "$BATS_TEST_TMPDIR/debt.log" ]
}

@test "RESUME DEBT: CC_RESUME_DEBT_SETTLING=1 (cc-resume-debt's own retry) opens NO debt" {
  kitty_ok_env
  CC_RESUME_DEBT_SETTLING=1 run bash "$LAUNCH" next3 /tmp sid-debt-3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/debt.log" ]
}

@test "RESUME DEBT: a failing debt binary never changes the launch's exit code" {
  kitty_ok_env
  printf '#!/bin/bash\nexit 7\n' > "$CC_RESUME_DEBT_BIN"
  run bash "$LAUNCH" next3 /tmp sid-debt-4
  [ "$status" -eq 0 ]
}

@test "--help exits 0" {
  run bash "$LAUNCH" --help
  [ "$status" -eq 0 ]
}

@test "missing args → usage exit 2" {
  run bash "$LAUNCH"
  [ "$status" -eq 2 ]
}

@test "dry-run builds a reso-resume-one command with account, cwd, sid" {
  run bash "$LAUNCH" --dry-run next4 /Users/x/Development/.worktrees/wt-zeta sid-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "reso-resume-one"
  echo "$output" | grep -q "next4"
  echo "$output" | grep -q "/Users/x/Development/.worktrees/wt-zeta"
  echo "$output" | grep -q "sid-123"
  echo "$output" | grep -q "create window with default profile"
  # The command is NO LONGER blind-sent by a combined `write text` (item 270106134cc8). It is typed
  # through osa_type_verified, which echo-verifies each line before sending its Enter, so the
  # osascript the dry-run prints CREATES ONLY — it must not carry the command with it.
  ! echo "$output" | grep -q 'write text' || false
  echo "$output" | grep -q 'TYPE (verified): unsetopt correct correct_all'
  echo "$output" | grep -qE 'TYPE \(verified\): .*reso-resume-one'
}

@test "the spell-correction disarm is typed FIRST, on its own accepted line" {
  # Order is the whole mechanism: zsh CORRECT fires as a line is READ, so a disarm that arrives
  # after the command (or inline with it) has not run when the command word is resolved.
  run bash "$LAUNCH" --dry-run next4 /tmp/wt sid-123
  [ "$status" -eq 0 ]
  local dis cmdline
  dis="$(echo "$output" | grep -n 'TYPE (verified): unsetopt correct' | head -1 | cut -d: -f1)"
  cmdline="$(echo "$output" | grep -nE 'TYPE \(verified\): .*reso-resume-one' | head -1 | cut -d: -f1)"
  # Split, one assertion per value. `[ A ] && [ B ] || { …; false; }` reads fine but is and-absorbed
  # under errexit, so it can never fail the test — and it names neither value when it does.
  [ -n "$dis" ] || { echo "the disarm line was never typed: $output"; false; }
  [ -n "$cmdline" ] || { echo "the command line was never typed: $output"; false; }
  [ "$dis" -lt "$cmdline" ] || { echo "disarm ($dis) does not precede the command ($cmdline)"; false; }
}

@test "RED-PROOF: the pre-fix blind-send shape would fail the guard above" {
  # Proves the assertions discriminate rather than passing vacuously — the exact pre-fix
  # construction, checked by the same predicate, must trip it.
  local old='  tell current session of w
    write text "$osa_cmd"
  end tell'
  echo "$old" | grep -q 'write text' || false
  ! echo "$old" | grep -q 'TYPE (verified)' || false
}

@test "a missing verified-typing lib fails LOUD, never a silent blind send" {
  # This runs at BOOT from launchd. Degrading to an unverified `write text` because a lib went
  # missing would reinstate the exact silent-hang this file was changed to remove.
  local fake="$BATS_TEST_TMPDIR/fakehome"
  mkdir -p "$fake/scripts"
  cp "$LAUNCH" "$fake/scripts/boot-resume-launch.sh"
  HOME="$fake" CLAUDE_CONFIG_DIR="$fake" run bash "$fake/scripts/boot-resume-launch.sh" \
    --dry-run next4 /tmp/wt sid-123
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "cannot source"
}

@test "dry-run: a cwd with spaces stays single-quoted (survives the write-text shell)" {
  run bash "$LAUNCH" --dry-run next2 "/Users/x/My Worktrees/wt a" sid-x branchy
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "'/Users/x/My Worktrees/wt a'"
  echo "$output" | grep -q "branchy"      # optional branch arg carried through
}

@test "CC_LAUNCH_DRYRUN=1 env also triggers dry-run" {
  CC_LAUNCH_DRYRUN=1 run bash "$LAUNCH" next /tmp/wt sid9
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CMD:"
}

# A REAL AF_UNIX socket, asserted — a plain file would make the two cases below vacuous.
#
# THE BIND IS RELATIVE, AND THAT IS THE WHOLE POINT (postland RED 2026-08-08..09, 17 consecutive
# sweeps). Darwin caps sun_path at 104 bytes, and the cap applies to THE STRING HANDED TO bind(2) —
# not to the file's absolute location. Binding the absolute path charged the whole $BATS_TEST_TMPDIR
# prefix against a budget the fixture does not control, and this file's two longest test NAMES are
# part of that prefix. So the suite read 11/11 green in every hand-check — including the re-run
# command postland itself prints, which uses a SHORT /tmp/pv-repro — and went red on tests 9 and 10
# inside postland, whose corpus TMPDIR is launchd's 49-byte /var/folders/… plus 21 bytes of
# postland-run.XXXXXX (scripts/postland-verify.sh:1050,1104). chdir + bind the basename spends 10
# bytes instead of ~130 and changes nothing else: the socket file still lands at the same absolute
# path, and `[ -S ]` still asserts it there.
#
# THIS IS THE THIRD AND FOURTH SITE OF ONE DEFECT. tests/kitty-socket-address.bats and
# tests/handoff-fire-kitty-daemon.bats already carry this exact fix and this exact comment
# (item e1d43f93da19, postland RED 2026-08-06); this file and tests/cc-kitty-socket.bats were
# missed because a per-file fix cannot see its own class. The invariant is asserted corpus-wide by
# scripts/test-afunix-path-lint.sh so a fifth site cannot land silently.
mksock() {
  /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"
  [ -S "$1" ]
}

# ── DAEMON-CONTEXT DISPATCH (2026-08-07). Under launchd there is no terminal env at all, and
# until this date the fall-through was the iTerm2 arm + `open -a iTerm` — which RESURRECTED
# iTerm2 behind a kitty-fleet operator (03:51:18 that morning, 6 sessions fired into it while
# kitty held 153 panes). These tests pin both halves of the fix hermetically: the live-socket
# resolver (bin/cc-kitty-socket, fixtured via CC_KITTY_SOCKET_DIR/_PS) decides the absent-env
# case, and the iTerm2 arm REFUSES rather than launches.

@test "daemon context (no terminal env) + live kitty socket -> kitty arm" {
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID CC_TERM_KITTY_TO KITTY_LISTEN_ON
  mkdir -p "$BATS_TEST_TMPDIR/sock"
  mksock "$BATS_TEST_TMPDIR/sock/kitty-42"
  cat > "$BATS_TEST_TMPDIR/ps" <<'EOF'
#!/bin/bash
pid=""; col=""
while [ $# -gt 0 ]; do case "$1" in -p) pid="$2"; shift 2 ;; -o) col="$2"; shift 2 ;; *) shift ;; esac; done
[ "$pid" = "42" ] || exit 1
case "$col" in ucomm=) echo kitty ;; etime=) echo 05:00 ;; esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/ps"
  export CC_KITTY_SOCKET_DIR="$BATS_TEST_TMPDIR/sock" CC_KITTY_SOCKET_PS="$BATS_TEST_TMPDIR/ps"
  run bash "$LAUNCH" --dry-run next4 /tmp sid-dc1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^KITTY: '                  # dispatch chose kitty with no env at all
}

# POSITIVE CONTROL for setup()'s CC_OSA_TIMEOUT_S pin. Without it that pin is decoration: the test
# above would pass identically whether the budget is honoured or hardcoded, and an unpinned suite
# silently goes back to measuring ambient load (a control that cannot fail proves nothing — the
# NO-REACH rule, LOAD_INSENSITIVE_VERIFY_V2 §6b).
#
# Same fixture as above, one variable moved: crush the budget to a value the resolver cannot meet.
# The bound then fires, _brl_sock is empty, IN_KITTY stays 0 — so dispatch must fall to the iTerm2
# arm and print NO `KITTY: ` line, even though a live socket is sitting right there. That is
# precisely the false red the pin exists to prevent, asserted rather than assumed.
@test "POSITIVE CONTROL: the resolver's wall-clock budget is REACHED (a crushed one loses the kitty arm)" {
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID CC_TERM_KITTY_TO KITTY_LISTEN_ON
  mkdir -p "$BATS_TEST_TMPDIR/sock"
  mksock "$BATS_TEST_TMPDIR/sock/kitty-42"
  cat > "$BATS_TEST_TMPDIR/ps" <<'EOF'
#!/bin/bash
pid=""; col=""
while [ $# -gt 0 ]; do case "$1" in -p) pid="$2"; shift 2 ;; -o) col="$2"; shift 2 ;; *) shift ;; esac; done
[ "$pid" = "42" ] || exit 1
case "$col" in ucomm=) echo kitty ;; etime=) echo 05:00 ;; esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/ps"
  export CC_KITTY_SOCKET_DIR="$BATS_TEST_TMPDIR/sock" CC_KITTY_SOCKET_PS="$BATS_TEST_TMPDIR/ps"
  export CC_OSA_TIMEOUT_S=0.001                        # the ONE variable that moves
  run bash "$LAUNCH" --dry-run next4 /tmp sid-dc1
  [ "$status" -eq 0 ]
  # `! … || false` is THIS file's own negative idiom (see the `write text` assertion above).
  # `refute` is not defined here — it is a local helper in tests/cc-authbrowser.bats, and using
  # it lands as `command not found`, which errexit turns into a red that says nothing.
  ! echo "$output" | grep -q '^KITTY: ' || false       # the budget fired ⇒ no kitty arm
  echo "$output" | grep -q 'create window with default profile'   # ...it fell to the iTerm2 arm
}

@test "daemon context + NO kitty anywhere + iTerm2 not running -> rc 3 refusal, app NEVER launched" {
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID CC_TERM_KITTY_TO KITTY_LISTEN_ON
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  export CC_KITTY_SOCKET_DIR="$BATS_TEST_TMPDIR/empty"
  # non-dry-run reaches the executable check on reso-resume-one BEFORE the terminal arm (its own
  # exit 3) — the suite's default CC_RESUME_ONE_BIN names a path that never exists, so give it a
  # real stub or this test asserts the WRONG exit-3.
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/rro"; chmod +x "$BATS_TEST_TMPDIR/rro"
  export CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/rro"
  # The capacity gate sits ahead of the terminal arms — pin it ADMIT so this test reaches the arm
  # under any host load (it runs on the very box the load-781 incident melted).
  #
  # 🚨 ALL FOUR TERMS, not the two this line used to carry. cc_capacity_admit evaluates
  # load · headroom · segments · active (scripts/lib/capacity-admit.sh:79-81, 557-558) and ANY ONE of
  # them refusing exits 9 — before the terminal arm this case is about. Pinning half of them states
  # an intent ("under any host load") the code does not implement, and the gap is invisible on a
  # quiet box: measured 2026-09-09, this case passed 5/5 standalone and failed BOTH runs inside a
  # full ship gate, whose own parallel suites are what move `segments` and `active`. Reproduced
  # directly — same invocation, segments alone saturated: `rc=9 … compressor segments 99% of limit >
  # ceiling 50%` against rc=3 with all four pinned. The refusal BUDGET (3, then it admits and pages)
  # is why it read as a flake rather than a wall.
  export CC_ADMIT_LOADAVG_OVERRIDE=1 CC_ADMIT_HEADROOM_OVERRIDE=64
  export CC_ADMIT_SEGMENT_OVERRIDE=0 CC_SP_ACTIVE_OVERRIDE=0
  # osascript stub: the is-running probe answers NOTHING (iTerm2 down); every invocation is
  # recorded — reaching the window-creating payload would BE the defect being pinned.
  cat > "$BATS_TEST_TMPDIR/osa" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/osa.calls"
exit 0
EOF
  chmod +x "$BATS_TEST_TMPDIR/osa"
  export CC_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/osa"
  run bash "$LAUNCH" next4 /tmp sid-dc2
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'refusing to launch'
  [ -f "$BATS_TEST_TMPDIR/osa.calls" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/osa.calls" | tr -d ' ')" -eq 1 ]   # the probe, and ONLY the probe
  grep -q 'is running' "$BATS_TEST_TMPDIR/osa.calls"                 # ...and it WAS the probe
}

# ── the precedence the case above depends on, asserted rather than assumed ─────────────────────────
# A pin that is silently insufficient is only detectable if something FAILS when a term is missing.
# This case is that something: it saturates ONE unpinned term and requires the capacity refusal to
# win over the terminal arm. If a future edit reorders the gate below the terminal checks, this goes
# red and the case above stops being load-sensitive for a reason nobody would otherwise look for.
@test "an unpinned capacity term saturating exits 9 (capacity) BEFORE the terminal arm's rc 3" {
  unset IT2_WRAPPER_NO_KITTY KITTY_WINDOW_ID CC_TERM_KITTY_TO KITTY_LISTEN_ON
  mkdir -p "$BATS_TEST_TMPDIR/empty2"
  export CC_KITTY_SOCKET_DIR="$BATS_TEST_TMPDIR/empty2"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/rro2"; chmod +x "$BATS_TEST_TMPDIR/rro2"
  export CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/rro2"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/osa2"; chmod +x "$BATS_TEST_TMPDIR/osa2"
  export CC_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/osa2"
  # three of four pinned ADMIT; `segments` saturated — exactly the shape a loaded box produces.
  export CC_ADMIT_LOADAVG_OVERRIDE=1 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_SP_ACTIVE_OVERRIDE=0
  export CC_ADMIT_SEGMENT_OVERRIDE=99
  run bash "$LAUNCH" next4 /tmp sid-dc3
  [ "$status" -eq 9 ]                                    # capacity, NOT the terminal arm's 3
  echo "$output" | grep -q 'segments'                    # ...and segments is why
  echo "$output" | grep -q 'DEFERRED, not lost'          # a shed is not a failure
}

# ── RECYCLE_KEYSTROKELESS_DELIVERY §D4: --prompt-file, --next-to, the launch token, rc 124/137 ─────
# kitty stub for the launch cases: `@ launch` appends its argv (one per line, then a `----` line)
# and exits KITTY_LAUNCH_RC; `@ ls` records its argv and, only when KITTY_LATE=1, prints a window
# whose env carries the token read back from the launch argv — the window that arrived late.
kitty_launch_env() {
  kitty_ok_env
  export KT="$BATS_TEST_TMPDIR"
  cat > "$BATS_TEST_TMPDIR/kitty" <<'SH'
#!/bin/bash
[ "$1" = @ ] && shift
[ "$1" = --to ] && { printf '%s\n' "$2" > "$KT/kitty.to"; shift 2; }
case "$1" in
  launch) printf '%s\n' "$@" -------- >> "$KT/kitty.launch"; exit "${KITTY_LAUNCH_RC:-0}" ;;
  ls) printf '%s\n' "$@" > "$KT/kitty.ls"
      tok="$(sed -n 's/^CC_LAUNCH_TOKEN=//p' "$KT/kitty.launch" | tail -1)"
      [ "${KITTY_LATE:-0}" = 1 ] || { echo "No matching windows" >&2; exit 1; }
      printf '[{"tabs":[{"windows":[{"id":134,"env":{"CC_LAUNCH_TOKEN":"%s"}}]}]}]\n' "$tok" ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/kitty"
}
launches() { grep -c '^launch$' "$BATS_TEST_TMPDIR/kitty.launch" 2>/dev/null || echo 0; }
launch_token() { sed -n 's/^CC_LAUNCH_TOKEN=//p' "$BATS_TEST_TMPDIR/kitty.launch" | tail -1; }

@test "D4: every kitty launch carries --env CC_LAUNCH_TOKEN, ahead of the program argv" {
  kitty_launch_env
  run bash "$LAUNCH" next3 /tmp sid-tok-1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx -- '--env' "$BATS_TEST_TMPDIR/kitty.launch"
  [ -n "$(launch_token)" ] || { cat "$BATS_TEST_TMPDIR/kitty.launch"; false; }
  # the token sits before `--`, so the window's program argv is untouched
  [ "$(sed -n '/^--$/,$p' "$BATS_TEST_TMPDIR/kitty.launch" | grep -c CC_LAUNCH_TOKEN)" -eq 0 ]
  grep -qx -- '--type=os-window' "$BATS_TEST_TMPDIR/kitty.launch"
}

@test "D4: --next-to <pane> launches a window beside that pane, not an os-window" {
  kitty_launch_env
  run bash "$LAUNCH" next3 /tmp sid-nt-1 --next-to 44
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx -- '--type=window' "$BATS_TEST_TMPDIR/kitty.launch"
  [ "$(grep -A1 -x -- '--next-to' "$BATS_TEST_TMPDIR/kitty.launch" | tail -1)" = "id:44" ]
  ! grep -qx -- '--type=os-window' "$BATS_TEST_TMPDIR/kitty.launch" || false
  run bash "$LAUNCH" next3 /tmp sid-nt-2 --next-to 'id:44; rm'
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}

@test "D4: client rc 124 with NO window carrying the token ⇒ exit 6, indeterminate, launched ONCE, token persisted, debt opened" {
  kitty_launch_env
  export CC_TERM_KITTY_TO=unix:/tmp/kitty-fixture
  KITTY_LAUNCH_RC=124 run bash "$LAUNCH" next3 /tmp sid-to-1
  [ "$status" -eq 6 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"launch indeterminate, reconciling (exit 6"* ]] || { echo "$output"; false; }
  [ "$(launches)" -eq 1 ] || { cat "$BATS_TEST_TMPDIR/kitty.launch"; false; }
  # the reconciliation asked for exactly this launch's token
  grep -qx -- "env:CC_LAUNCH_TOKEN=$(launch_token)" "$BATS_TEST_TMPDIR/kitty.ls"
  # review item 2: one immediate ls cannot see a window 9 minutes late, so the token is PERSISTED
  m="$CC_PENDING_LAUNCH_DIR/sid-to-1.json"
  [ "$(jq -r .token "$m")" = "$(launch_token)" ] || { cat "$m"; false; }
  [ "$(jq -r '.acct + " " + .cwd + " " + .kitty_to' "$m")" = "next3 /tmp unix:/tmp/kitty-fixture" ]
  [ "$(jq -r '.launched_at | type' "$m")" = number ]
  # …and a debt is opened, so the sweep that reconciles the marker has something to step
  grep -q '^open --sid sid-to-1 ' "$BATS_TEST_TMPDIR/debt.log" || { cat "$BATS_TEST_TMPDIR/debt.log"; false; }
}

@test "D4: an indeterminate launch under cc-resume-debt's own retry still persists the token, and opens no second debt" {
  kitty_launch_env
  CC_RESUME_DEBT_SETTLING=1 KITTY_LAUNCH_RC=137 run bash "$LAUNCH" next3 /tmp sid-to-4
  [ "$status" -eq 6 ] || { echo "status $status: $output"; false; }
  [ -f "$CC_PENDING_LAUNCH_DIR/sid-to-4.json" ]
  [ ! -e "$BATS_TEST_TMPDIR/debt.log" ] || { cat "$BATS_TEST_TMPDIR/debt.log"; false; }
}

@test "D4: client rc 137 but the token's window exists ⇒ exit 0, launched late, debt opened" {
  kitty_launch_env
  KITTY_LAUNCH_RC=137 KITTY_LATE=1 run bash "$LAUNCH" next3 /tmp sid-to-2
  [ "$status" -eq 0 ] || { echo "status $status: $output"; false; }
  [[ "$output" == *"launched late"* ]] || { echo "$output"; false; }
  [ "$(launches)" -eq 1 ]
  grep -q '^open --sid sid-to-2 ' "$BATS_TEST_TMPDIR/debt.log"
}

@test "D4: any other client failure is still exit 4 (control for the timeout reconcile)" {
  kitty_launch_env
  KITTY_LAUNCH_RC=1 KITTY_LATE=1 run bash "$LAUNCH" next3 /tmp sid-to-3
  [ "$status" -eq 4 ] || { echo "status $status: $output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/kitty.ls" ] || false
}

@test "D4: --prompt-file rides into the reso-resume-one command, quoted, after the branch" {
  run bash "$LAUNCH" --dry-run next4 /tmp sid-pf-1 br-x --prompt-file "/tmp/it's here.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qF "CMD: 'env' 'CC_ADMIT_DONE=1' '/Users/x/.reso/bin/reso-resume-one' 'next4' '/tmp' 'sid-pf-1' 'br-x' '--prompt-file' '/tmp/it'\\''s here.md'"
  # without a branch the option is the 4th word, and is not swallowed as a branch
  run bash "$LAUNCH" --dry-run next4 /tmp sid-pf-2 --prompt-file /tmp/p.md
  echo "$output" | grep -qF "'sid-pf-2' '--prompt-file' '/tmp/p.md'"
  run bash "$LAUNCH" --dry-run next4 /tmp sid-pf-3 --bogus
  [ "$status" -eq 2 ]
}
