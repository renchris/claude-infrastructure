#!/usr/bin/env bats
# Regression guard for the SESSION-PINNED successor gate + its close-instant (T-0) re-verify —
# handoff-fire.sh, backlog f44a901152d9 / infra-reliability-audit-2026-07-22 row 1+2.
#
# THE DEFECT. Both halves of the successor gate keyed on `ps -o comm= -t <tty> | grep -qE
# 'node|claude'` — a CONTROLLING-TTY match on a pattern ANY Node process satisfies. So a pane whose
# CC session had died still read "successor alive" as long as *something* node-ish sat on its tty (a
# `npm run dev`, a vite, an esbuild, or a different session launched into the reused pane). The
# predecessor closed onto a dead continuation and the work stranded in BOTH panes — precisely the
# failure the gate exists to prevent. Worse than the imprecision: the ENGAGEMENT half resolves pane →
# registry row → session_id → that transcript, so the two halves of one gate could be proving things
# about two DIFFERENT sessions.
#
# THE FIX under test: successor_pin resolves (pane UUID → registry row → session_id + pid) and
# asserts THAT pid is a live CC process still owning the pane's tty; the pin is handed to the
# detached watcher (6th arg) which re-checks the SAME pid at the close instant. Three states — a pane
# with no registry row is UNPINNABLE, not dead, and falls back to the tty check LOUDLY (an adopted
# operator pane legitimately has no row; convicting it would refuse every legitimate close).
#
# RED-PROOF. Tests 2, 3 and 7 are the ones that fail on the pre-fix tree: each builds a successor
# whose OWN session is gone while a node process sits on its tty, which the old check passed.
# Verified RED against the pre-fix script (see the commit message for the reproduced numbers).
#
# Technique follows tests/handoff-selfclose.bats: PATH shims for osascript/ps/git driven through
# --dry-run so the gate runs but nothing is armed, a fake HOME with recording it2/cc-notify stubs for
# the watcher path, and sed-extracted functions for the unit-level predicates. The ps shim is
# EXTENDED here to answer `-p <pid>` for comm/tty/args, because that is the form the pin uses.

setup() {
  # PIN THE TERMINAL. Every test in this file asserts the iTerm2 path and stubs `osascript`, but
  # handoff-fire.sh's primitives now branch on KITTY_WINDOW_ID (in_kitty), so run from inside kitty
  # the subject takes the kitty branch while only osascript is stubbed — and the suite's verdict
  # silently becomes a function of which terminal the developer is sitting in. Measured 2026-08-01:
  # unpinned from kitty this file went red; env-pinned it returns to its exact baseline count, and
  # baseline HEAD is green either way. The dependency PREDATES the branch (nothing read
  # KITTY_WINDOW_ID before); the branch only made it observable. Same pin, same reason, as
  # tests/it2-wrapper.bats and tests/cc-pane.bats. The kitty branches have their own coverage in
  # tests/handoff-fire-kitty.bats. Unset the real var AND pin the kill switch — both spellings.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # FIXTURE $HOME in setup(), not per-test (test-hermeticity-lint's rule, and it is the right rule
  # here): the arm-time gate tests below drive the real script, which resolves REAL_IT2, cc-notify and
  # the roles dir under $HOME. Unfixtured they would read — and in the non-dry paths write — the
  # OPERATOR'S live ~/.claude. The it2 shim must EXIST or the `sed … | head -1` REAL_IT2 probe aborts
  # the script under pipefail before any gate runs.
  export HOME="$BATS_TEST_TMPDIR/fixture-home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/cc-roles" "$HOME/.claude/logs"
  printf '#!/bin/bash\nREAL_IT2="%s"\nexit 0\n' "$HOME/.claude/bin/it2" > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  OSA_GONE_DIR="$BATS_TEST_TMPDIR/gone"; mkdir -p "$OSA_GONE_DIR"
  PS_DEAD_DIR="$BATS_TEST_TMPDIR/dead";  mkdir -p "$PS_DEAD_DIR"
  PS_PID_DIR="$BATS_TEST_TMPDIR/pids";   mkdir -p "$PS_PID_DIR"
  export OSA_GONE_DIR PS_DEAD_DIR PS_PID_DIR

  # as_tty: `osascript - <uuid>` → TTY-<uuid>, or empty when a gone-marker exists.
  cat > "$SHIM/osascript" <<'SH'
#!/usr/bin/env bash
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in
    -e) shift 2 2>/dev/null || shift ;;
    -)  shift ;;
    *)  uuid="$1"; shift ;;
  esac
done
[ -n "$uuid" ] || exit 0
[ -n "${OSA_GONE_DIR:-}" ] && [ -e "$OSA_GONE_DIR/$uuid" ] && exit 0
printf '%s' "TTY-$uuid"
exit 0
SH

  # ps shim — TWO query forms, mirroring what the real ps answers:
  #   -t <tty>          the OLD tty-wide check: prints "claude" unless a dead-marker exists.
  #                     THIS IS THE DEFECT'S SURFACE: it stays satisfiable in the pinned-dead tests,
  #                     which is what proves the pin (not the tty) is doing the deciding.
  #   -o <f> -p <pid>   the PIN's check, driven by a per-pid fixture file $PS_PID_DIR/<pid>:
  #                     line 1 = comm, line 2 = tty, line 3 = argv. Absent file ⇒ no output ⇒ dead,
  #                     exactly as real ps behaves for a reaped pid.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
tty="" pid="" want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) want="$want${2:-}"; shift 2 ;;
    -t) tty="${2:-}"; shift 2 ;;
    -p) pid="${2:-}"; shift 2 ;;
    *)  shift ;;
  esac
done
if [ -n "$pid" ]; then
  f="${PS_PID_DIR:-/nonexistent}/$pid"
  [ -f "$f" ] || exit 0                       # reaped pid → no line at all
  case "$want" in
    *comm*) sed -n 1p "$f" ;;
    *tty*)  sed -n 2p "$f" ;;
    *args*) sed -n 3p "$f" ;;
  esac
  exit 0
fi
[ -n "$tty" ] || exit 0
[ -n "${PS_DEAD_DIR:-}" ] && [ -e "$PS_DEAD_DIR/$tty" ] && exit 0
printf '%s\n' "claude"
exit 0
SH

  # only `git rev-parse --is-inside-work-tree` is hit in the dry-run gate path → "not a work tree".
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = rev-parse ] && exit 1
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/ps" "$SHIM/git"
  export PATH="$SHIM:$PATH"

  REGDIR="$BATS_TEST_TMPDIR/reg";   mkdir -p "$REGDIR"
  PROJDIR="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJDIR"
  export CC_REGISTRY_DIR="$REGDIR" CC_PROJECTS_DIRS="$PROJDIR"

  SUCC="SUCC-PANE"; PRED="PRED-PANE"; SUCC_SESS="succ-sess-0"
  # The successor is ENGAGED throughout this suite — every assertion below is about the LIVENESS
  # half, so the engagement half must never be the thing that decides.
  printf '%s\n' \
    '{"type":"user","message":{"content":"go"}}' \
    '{"type":"assistant","message":{"content":"on it"}}' > "$PROJDIR/$SUCC_SESS.jsonl"

  # self-close is available only to a session a peer FIRED (origin gate) — stamp the predecessor.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  printf '{"paneUUID":"%s","cwd":"/tmp","firedBy":"ORIGINATOR","firedAt":"2026-07-26T18:00:00Z","selfRetire":true}\n' \
    "$PRED" > "$CC_FIRED_DIR/$PRED.json"
}

# registry row for the successor pane. $1=pid ("" ⇒ no pid field ⇒ UNPINNABLE)
succ_row() {
  if [ -n "${1:-}" ]; then
    printf '{"paneUUID":"%s","session_id":"%s","pid":%s}\n' "$SUCC" "$SUCC_SESS" "$1" > "$REGDIR/$SUCC.json"
  else
    printf '{"paneUUID":"%s","session_id":"%s"}\n' "$SUCC" "$SUCC_SESS" > "$REGDIR/$SUCC.json"
  fi
}

# a live pid fixture. $1=pid $2=tty (defaults to the successor pane's tty)
live_pid() {
  printf '%s\n%s\n%s\n' \
    "/Users/chrisren/.claude-219/node_modules/.bin/claude" \
    "${2:-TTY-$SUCC}" \
    "/Users/chrisren/.claude-219/node_modules/.bin/claude --continue" > "$PS_PID_DIR/$1"
}

mk_home() { # $1=dir — it2 + cc-notify stubs that RECORD their args (watcher tests)
  local h="$1"; mkdir -p "$h/.claude/bin" "$h/.claude/cc-roles"
  # `session list` must ENUMERATE the panes this fixture models. Every T-0 test below models a pane
  # the watcher CAN reach — the scenario under test is what happens at the CLOSE INSTANT, which the
  # watcher only reaches once pane_proof has passed. A stub answering the empty list asserts the
  # opposite of its own setup, and did: these four tests have been RED on trunk since the
  # reachability handshake landed (2026-08-02), refusing at the probe and never reaching the pin
  # logic they exist to cover. The sibling tests/handoff-selfclose.bats mk_home was updated then;
  # this one was missed. It answers BOTH shapes the real transports emit — `--json` (the real it2
  # and bin/it2-kitty) and bare ids — because a fixture that only models the shape that happened to
  # work is exactly how item 191d1fc4143c stayed invisible to a green suite.
  cat > "$h/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
if [ "${1:-}" = session ] && [ "${2:-}" = list ]; then
  panes="${STUB_PANES:-PREDSID SUCC-B}"
  if [ "${3:-}" = --json ]; then
    sep=""; printf '['
    for p in $panes; do printf '%s{"id": "%s", "tty": "/dev/ttys999"}' "$sep" "$p"; sep=", "; done
    printf ']\n'
  else
    printf '%s\n' $panes
  fi
  exit 0
fi
exit 0
SH
  cat > "$h/.claude/bin/cc-notify" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/ccnotify-calls.log"
exit 0
SH
  chmod +x "$h/.claude/bin/it2" "$h/.claude/bin/cc-notify"
  printf 'DESK-PANE\n' > "$h/.claude/cc-roles/desk"
}

# ── 1. ARM-TIME GATE: the pin decides, not the tty ──────────────────────────────────────────────

@test "pin LIVE: registry pid runs on the pane's tty → gate passes, SESSION-PINNED" {
  succ_row 4242; live_pid 4242
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SESSION-PINNED"* ]] || false
  [[ "$output" == *"pid 4242"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]] || false   # reached the plan → gate passed
}

@test "RED-PROOF pin DEAD: successor session gone while a node still owns its tty → exit 3" {
  # THE AUDIT DEFECT, replayed. The tty check is deliberately SATISFIABLE here (no dead-marker), so
  # the pre-fix gate passed and closed the predecessor onto a dead continuation. No pid fixture ⇒
  # the registry pid is reaped, exactly as a real dead session leaves it.
  succ_row 4242
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"THAT process is gone"* ]] || false
  [[ "$output" == *"pid 4242"* ]] || false
  [[ "$output" == *"merely sharing the pane's tty is NOT proof"* ]] || false
  ! [[ "$output" == *"dry run (self-close)"* ]] || false  # aborted BEFORE the plan → no close
}

@test "RED-PROOF pin DEAD: pid alive but RECYCLED onto another pane's tty → exit 3" {
  # A bare kill -0 / pid-exists check cannot express this: the pid runs, it just is not this pane's
  # session any more. The tty leg of the pin is what catches it.
  succ_row 4242; live_pid 4242 "TTY-SOME-OTHER-PANE"
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no longer owns tty"* ]] || false
}

@test "UNPINNABLE: row has session_id but no pid → tty fallback, LOUDLY, gate passes" {
  # An adopted operator pane legitimately has no pid field. Refusing it would be worse than the
  # weaker proof — but the weaker proof must never be reported as the strong one.
  succ_row ""
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT session-pinnable"* ]] || false
  [[ "$output" == *"UNPINNED"* ]] || false
  ! [[ "$output" == *"SESSION-PINNED"* ]] || false
  [[ "$output" == *"dry run (self-close)"* ]] || false
}

@test "UNPINNABLE: no registry row at all → tty fallback (non-regression for adopted panes)" {
  rm -f "$REGDIR/$SUCC.json"
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC" --successor-assume-engaged
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT session-pinnable"* ]] || false
}

@test "UNPINNABLE + nothing on the tty → still ABORTS (the fallback keeps enforcing)" {
  succ_row ""
  : > "$PS_DEAD_DIR/TTY-$SUCC"
  run bash "$HF" self-close --dry-run --session-id "$PRED" --successor "$SUCC"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no live claude on successor"* ]] || false
}

# ── 2. CLOSE-INSTANT (T-0) RE-VERIFY: the watcher re-checks the SAME session ─────────────────────

@test "RED-PROOF watcher T-0: pinned session died mid-window while a node holds the tty → no close" {
  # The 180s hole. Pre-fix the watcher re-ran the tty check, which a leftover node satisfies — so a
  # successor that died after arming was closed onto anyway. No dead-marker for TTY-B here: the tty
  # check WOULD pass; only the pin convicts.
  H="$BATS_TEST_TMPDIR/home-t0"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"                       # predecessor already exited → skip the wait loop
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B "succ-sess-0 4242"
  [ "$status" -ne 0 ]
  [[ "$output" == *"close-instant pin check FAILED"* ]] || false
  [[ "$output" == *"ABORTED at close-instant"* ]] || false
  # The invariant is "no CLOSE", not "no it2 call at all": the watcher's second act is a READ-ONLY
  # `session list` reachability probe, so the log exists on every path. Same correction the sibling
  # tests/handoff-selfclose.bats already carries.
  ! grep -q "session close" "$H/it2-calls.log" 2>/dev/null || false  # predecessor left alive
  grep -q "HANDOFF-STRAND-RISK" "$H/ccnotify-calls.log"
}

@test "watcher T-0: pinned session still alive on its tty → closes predecessor, focuses successor" {
  H="$BATS_TEST_TMPDIR/home-t0-ok"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"
  live_pid 4242 "TTY-B"
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B "succ-sess-0 4242"
  [ "$status" -eq 0 ]
  grep -q "session close -f -s PREDSID" "$H/it2-calls.log"
  grep -q "session focus SUCC-B" "$H/it2-calls.log"
  [ ! -f "$H/ccnotify-calls.log" ]               # happy path pages nobody
}

@test "watcher T-0: NO pin handed over (deployed-copy skew) → falls back to the tty check" {
  # The 6th arg is optional and positional-last precisely so an older deployed watcher mid-land
  # ignores it. That back-compat must keep the OLD behaviour, not become a silent no-check.
  H="$BATS_TEST_TMPDIR/home-t0-skew"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"
  : > "$PS_DEAD_DIR/TTY-B"                       # nothing on the successor's tty either
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B
  [ "$status" -ne 0 ]
  [[ "$output" == *"ABORTED at close-instant"* ]] || false
  ! grep -q "session close" "$H/it2-calls.log" 2>/dev/null || false  # predecessor left alive
}

@test "watcher T-0: pin is NOT re-derived from the registry row (a NEW session cannot satisfy it)" {
  # If the watcher re-read the row instead of re-checking the handed-over pin, a DIFFERENT session
  # launched into that pane during the window would satisfy a gate that proved the OLD one engaged.
  H="$BATS_TEST_TMPDIR/home-t0-newsess"; mk_home "$H"
  : > "$PS_DEAD_DIR/TTY-A"
  printf '{"paneUUID":"SUCC-B","session_id":"a-brand-new-session","pid":9999}\n' > "$REGDIR/SUCC-B.json"
  live_pid 9999 "TTY-B"                          # the NEW session is alive on that tty…
  run env HOME="$H" bash "$HF" __selfclose PREDSID TTY-A SUCC-B TTY-B "succ-sess-0 4242"
  [ "$status" -ne 0 ]                            # …but pid 4242 — the one we verified — is gone
  [[ "$output" == *"close-instant pin check FAILED"* ]] || false
  ! grep -q "session close" "$H/it2-calls.log" 2>/dev/null || false  # predecessor left alive
}

# ── 3. pid_is_cc — the CONVICTING predicate, against the REAL ps ─────────────────────────────────

@test "POSITIVE CONTROL: pid_is_cc resolves a REAL live node process, and a reaped pid" {
  # A hermetic shim cannot prove this predicate works against the real process table — and a false
  # negative here ABORTS a healthy self-close, so it needs a control that runs the REAL ps against a
  # REAL pid. Prefer an actual node (that IS the population: CC runs as node/claude); fall back to a
  # symlink named `node`, which real ps reports by the path used to exec it. NOT `cp /bin/sleep` —
  # copying a signed system binary breaks its signature and macOS SIGKILLs it on exec.
  local realbin
  if command -v node >/dev/null 2>&1; then
    realbin="$(command -v node)"
    "$realbin" -e 'setTimeout(function(){}, 30000)' >/dev/null 2>&1 &
  else
    mkdir -p "$BATS_TEST_TMPDIR/realbin"
    ln -sf /bin/sleep "$BATS_TEST_TMPDIR/realbin/node"
    "$BATS_TEST_TMPDIR/realbin/node" 30 >/dev/null 2>&1 &
  fi
  local real_pid=$!
  # PATH with the shim REMOVED, so this exercises the real /bin/ps rather than the fixture.
  local realpath_env; realpath_env="$(printf '%s' "$PATH" | sed "s|$SHIM:||")"
  local fn; fn="$(sed -n '/^pid_is_cc() {/,/^}/p' "$HF")"
  run env PATH="$realpath_env" bash -c "$fn; pid_is_cc $real_pid"
  [ "$status" -eq 0 ] || { echo "a REAL live node pid ($real_pid) was NOT recognised — comm=[$(ps -o comm= -p "$real_pid")]"; kill "$real_pid" 2>/dev/null; false; }

  kill -9 "$real_pid" 2>/dev/null || true
  wait "$real_pid" 2>/dev/null || true
  run env PATH="$realpath_env" bash -c "$fn; pid_is_cc $real_pid"
  [ "$status" -eq 1 ] || { echo "a reaped pid was reported LIVE"; false; }
}

@test "pid_is_cc survives the macOS 16-char comm truncation via argv[0]" {
  # `ps -o comm=` can fall back to the kernel's 16-char p_comm — "/Users/chrisren/" with the
  # node|claude substring truncated clean off (memory actuator-must-see-the-target-population).
  # comm alone would convict a healthy session; argv[0] is never truncated.
  eval "$(sed -n '/^pid_is_cc() {/,/^}/p' "$HF")"
  printf '%s\n%s\n%s\n' "/Users/chrisren/" "TTY-X" \
    "/Users/chrisren/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe --continue" \
    > "$PS_PID_DIR/7777"
  run pid_is_cc 7777
  [ "$status" -eq 0 ]
}

@test "pid_is_cc does NOT match the BRIEF in a session's argv (pgrep -f class)" {
  # A fired session's argv carries its whole brief, which routinely says "claude". Only argv[0] may
  # be consulted, else the predicate matches any process that merely MENTIONS claude.
  eval "$(sed -n '/^pid_is_cc() {/,/^}/p' "$HF")"
  printf '%s\n%s\n%s\n' "/bin/zsh" "TTY-X" \
    "/bin/zsh -lc drive the claude-infrastructure backlog item to done" > "$PS_PID_DIR/8888"
  run pid_is_cc 8888
  [ "$status" -eq 1 ]
}
