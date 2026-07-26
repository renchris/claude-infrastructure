#!/usr/bin/env bats
# The WORKTREE-SCOPED KILL contract (backlog a0718a5d78b3 — root cause of the 2026-07-26 false-RED
# epidemic). Three artifacts, one contract, so they are tested together:
#   scripts/gate-cleanup.sh   the correct tool — selects only THIS worktree's gate processes
#   hooks/validate-bash.sh    the enforcement — denies a worktree-UNSCOPED pkill of gate processes
#   (repo lint)               no tracked script may ship an unscoped one
#
# WHAT HAPPENED: peers ran `pkill -9 -f bats-core/bats`. Every bats command line on this box
# contains `/libexec/bats-core/bats`, so that is machine-wide BY CONSTRUCTION. The desk tied victim
# gates to actor commands with a 3-5s lag twice over (>=8 broad-pkill events, 5 sessions, 24h).
# Victims mis-read their own SIGKILL as OOM/jetsam — REFUTED: 68% memory free, zero memorystatus
# kills — and propagated that wrong theory into their block reasons.
#
# Assertions use `|| false` where they are non-final: a bare `[[ ]]` / `!` / `A && B` is
# errexit-EXEMPT in bats and would be a DEAD assertion (memory: bats-dead-assertions).

setup() {
  # HERMETIC $HOME — required, and not a formality here: `decision()` below runs the REAL
  # validate-bash.sh, whose last act is `mkdir -p ~/.claude/logs; echo "$CMD" >> …/bash-commands.log`.
  # Unfixtured, every probe in this file appends to the OPERATOR'S live command-audit log. Caught by
  # scripts/test-hermeticity-lint.sh, which is exactly the leak class it was built to ratchet out.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLEANUP="$REPO/scripts/gate-cleanup.sh"
  HOOK="$REPO/hooks/validate-bash.sh"
  # PHYSICAL paths, because that is what the real producer emits: `lsof -d cwd` reports a resolved
  # path, and on macOS BATS_TEST_TMPDIR is under /var/folders → /private/var/folders. A fixture
  # carrying the logical spelling matches nothing and every selection assertion below reads
  # "nothing to clean" — green-looking for the wrong reason.
  mkdir -p "$BATS_TEST_TMPDIR/wt" "$BATS_TEST_TMPDIR/other"
  WT="$(cd "$BATS_TEST_TMPDIR/wt" && pwd -P)"
  OTHER="$(cd "$BATS_TEST_TMPDIR/other" && pwd -P)"
  BATS_BIN_PATH="/opt/homebrew/Cellar/bats-core/1.13.0/libexec/bats-core"
}

# ── fixture seams ───────────────────────────────────────────────────────────────────────────────
# A REAL process table cannot be staged (we would have to spawn — and then kill — live processes,
# which is the very blast radius under test), so the two facts gate-cleanup reads are injected:
# `ps -eo pid=,ppid=,command=` and a pid→cwd resolver. Both fixtures emit the LITERAL shapes the
# real producers emit — a fixture is a contract claim about its producer (memory:
# fixture-shape-parity-with-real-producer), so the bats lines carry real bats-core paths and the
# claude line carries a real `--model … TASK …` argv.
mk_ps() {  # writes the ps fixture; $1..$n = extra "pid ppid command" rows
  {
    echo '#!/bin/bash'
    # SELF-ROW — the cleanup process's OWN pid, parented at $CLEANUP_PARENT (default 1).
    # Without it the fixture severs gate-cleanup from its own ancestry: `ppid_of "$$"` finds
    # nothing in the fake table, the ancestor walk never runs, and EXCLUDE stays { self }. Every
    # self-preservation assertion in this file then passes for the wrong reason — the script is
    # not being spared, it is being asked about processes it cannot relate to itself.
    #
    # The pid is DISCOVERED, not assumed. `$PPID` alone is wrong: gate-cleanup reads the table via
    # `PS_SNAPSHOT="$(ps_all)"`, and because ps_all is a function bash forks a subshell for the
    # substitution — so the fake ps's parent is that subshell, not the script. Measured: the fake
    # ps saw 24531 while the script's own $$ was 24727, and the un-excluded 24727 then appeared in
    # the selection.
    #
    # Nor is "first ancestor whose argv says gate-cleanup.sh" enough: a forked subshell INHERITS
    # its parent's argv, so that match returns the subshell (measured: 96975, which then showed up
    # in the selection). Argv is not identity — the same lesson gate-cleanup.sh itself is built on.
    # So walk the whole chain and keep the TOPMOST consecutive match: the real script, whose own
    # parent is the bats test shell and no longer matches. Empty ⇒ no self-row, which fails the
    # assertions loudly rather than naming the wrong process.
    echo 'CC_CUR=$PPID; CC_SELF=""; CC_HOPS=0'
    echo 'while [ "$CC_HOPS" -lt 12 ]; do'
    echo '  CC_HOPS=$(( CC_HOPS + 1 ))'
    echo '  case "$(ps -o command= -p "$CC_CUR" 2>/dev/null)" in *gate-cleanup.sh*) CC_SELF="$CC_CUR" ;; esac'
    echo '  CC_NEXT="$(ps -o ppid= -p "$CC_CUR" 2>/dev/null | tr -d " ")"'
    echo '  [ -n "$CC_NEXT" ] && [ "$CC_NEXT" != 1 ] || break'
    echo '  CC_CUR="$CC_NEXT"'
    echo 'done'
    echo 'cat <<TABLE'
    printf '$CC_SELF %s bash %s/scripts/gate-cleanup.sh\n' "${CLEANUP_PARENT:-1}" "$REPO"
    printf '1000 1 bash %s/bats tests/\n'                      "$BATS_BIN_PATH"
    printf '1001 1000 bash %s/bats-exec-suite --dummy-flag\n'  "$BATS_BIN_PATH"
    printf '1002 1001 sleep 30\n'
    printf '2000 1 bash %s/bats tests/\n'                      "$BATS_BIN_PATH"
    printf '2001 2000 bash %s/bats-exec-file --dummy-flag\n'   "$BATS_BIN_PATH"
    printf '3000 1 /Users/x/.claude-219/node_modules/.bin/claude --model claude-opus-5 TASK run ./scripts/ship-land.sh and bats tests/\n'
    printf '4000 1 bash /w/scripts/ship-land.sh\n'
    printf '5000 1 bash /w/scripts/deploy.sh --note bats tests/ ship-land.sh\n'
    local extra
    for extra in "$@"; do printf '%s\n' "$extra"; done
    echo 'TABLE'
  } > "$BATS_TEST_TMPDIR/ps"
  chmod +x "$BATS_TEST_TMPDIR/ps"
  export CC_GATE_CLEANUP_PS="$BATS_TEST_TMPDIR/ps"
}

mk_cwd() {  # pid→cwd resolver. 1xxx/3000/4000/5000 live in WT; 2xxx in OTHER; 1001/1002 chdir'd
  {                                                              # away (the bats-TMPDIR case)
    echo '#!/bin/bash'
    echo 'case "$1" in'
    printf '  1000|3000|4000|5000|9%s) echo "%s" ;;\n' '9999' "$WT"
    printf '  1001|1002) echo "/private/var/folders/bats-run-XXX/test/1" ;;\n'
    printf '  2000|2001) echo "%s" ;;\n' "$OTHER"
    echo '  *) echo "" ;;'
    echo 'esac'
  } > "$BATS_TEST_TMPDIR/cwd"
  chmod +x "$BATS_TEST_TMPDIR/cwd"
  export CC_GATE_CLEANUP_CWD="$BATS_TEST_TMPDIR/cwd"
}

selection() { "$CLEANUP" --worktree "$WT" --dry-run --quiet 2>/dev/null | sort -n | tr '\n' ' '; }

# ════ scripts/gate-cleanup.sh — selection ═══════════════════════════════════════════════════════

@test "cleanup: selects THIS worktree's gate root and its descendants" {
  mk_ps; mk_cwd
  run selection
  [ "$status" -eq 0 ]
  # 1000 root (cwd in WT) · 1001,1002 descendants (their OWN cwd is a bats tmpdir, NOT in WT —
  # cwd alone would miss exactly the children holding the CPU) · 4000 ship-land root.
  [ "$output" = "1000 1001 1002 4000 " ]
}

# The three exclusion tests below each assert a NEGATIVE, which passes vacuously on an empty
# selection (a deleted or broken helper). Each therefore carries the positive control inline:
# something WAS selected, and the excluded pid was not it.
@test "cleanup: NEVER selects an identical gate in another worktree (the whole point)" {
  mk_ps; mk_cwd
  run selection
  echo "$output" | grep -q 1000 || false                # positive control: selection is non-empty
  ! echo "$output" | grep -q 2000 || false
  ! echo "$output" | grep -q 2001 || false
}

@test "cleanup: NEVER selects a claude session whose PROMPT merely names ship-land/bats" {
  # This is not hypothetical: the first draft of gate-cleanup.sh matched a live peer's `claude`
  # process for SIGKILL, because a session's argv embeds its whole task brief. Text is not
  # evidence of execution — the same defect the script exists to fix, one level up.
  mk_ps; mk_cwd
  run selection
  echo "$output" | grep -q 1000 || false                # positive control: selection is non-empty
  ! echo "$output" | grep -q 3000 || false
}

@test "cleanup: a non-gate program in this worktree is not selected for MENTIONING bats" {
  mk_ps; mk_cwd
  run selection
  echo "$output" | grep -q 1000 || false                # positive control: selection is non-empty
  ! echo "$output" | grep -q 5000 || false
}

@test "cleanup: refuses to select itself or any ancestor" {
  # Inject the running shell as a would-be gate root in this worktree. A bare `pkill -f bats` run
  # from inside a bats suite kills its own caller — one way the observed events cascaded.
  mk_cwd
  # Parent the cleanup at 99999, so the real chain is cleanup → 99999 → $$ and the ancestor walk
  # has something to walk. This is the scenario in the comment above: cleanup running INSIDE the
  # suite it would otherwise select.
  CLEANUP_PARENT=99999
  mk_ps "$$ 1 bash $BATS_BIN_PATH/bats tests/" "99999 $$ bash $BATS_BIN_PATH/bats-exec-test"
  run selection
  echo "$output" | grep -q 1000 || false              # positive control: selection is non-empty
  ! echo "$output" | grep -qw "$$" || false
  ! echo "$output" | grep -qw 99999 || false          # nor a descendant reached only through us
}

@test "cleanup: an empty selection is exit 0 with a clear line, never a failure" {
  mk_ps; mk_cwd
  run "$CLEANUP" --worktree "$OTHER/nowhere-at-all" --dry-run
  [ "$status" -eq 2 ]                                  # a nonexistent dir is a usage error…
  mkdir -p "$OTHER/empty"
  run "$CLEANUP" --worktree "$OTHER/empty" --dry-run
  [ "$status" -eq 0 ]                                  # …an empty but real one is simply clean
  echo "$output" | grep -q "nothing to clean" || false
}

@test "cleanup: --dry-run signals NOTHING (stdout is the selection, nothing is killed)" {
  mk_cwd
  # A REAL victim: a live sleep we own, injected as a descendant of a gate root in this worktree.
  sleep 45 & victim=$!
  mk_ps "1003 1000 sleep 45" "6000 1 bash $BATS_BIN_PATH/bats tests/" "$victim 6000 sleep 45"
  cat > "$BATS_TEST_TMPDIR/cwd" <<EOF
#!/bin/bash
case "\$1" in
  1000|4000|6000) echo "$WT" ;;
  *) echo "" ;;
esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/cwd"
  run "$CLEANUP" --worktree "$WT" --dry-run --quiet
  [ "$status" -eq 0 ]
  echo "$output" | grep -qw "$victim" || false         # it WAS selected…
  kill -0 "$victim" 2>/dev/null || false               # …and is still alive
  kill "$victim" 2>/dev/null || true
}

@test "cleanup: --grace rejects a non-integer (a bad bound must be loud, not silently 0)" {
  run "$CLEANUP" --worktree "$WT" --grace abc --dry-run
  [ "$status" -eq 2 ]
}

@test "cleanup: --worktree resolves symlinks, so a /tmp vs /private/tmp spelling still matches" {
  # macOS /tmp → /private/tmp. A prefix test against the unresolved spelling matches NOTHING and
  # would report "nothing to clean" on a worktree full of stuck gates — a silent no-op.
  mk_cwd
  real="$(cd "$WT" && pwd -P)"
  ln -s "$WT" "$BATS_TEST_TMPDIR/link"
  mk_ps
  cat > "$BATS_TEST_TMPDIR/cwd" <<EOF
#!/bin/bash
case "\$1" in 1000|4000) echo "$real" ;; *) echo "" ;; esac
EOF
  chmod +x "$BATS_TEST_TMPDIR/cwd"
  run "$CLEANUP" --worktree "$BATS_TEST_TMPDIR/link" --dry-run --quiet
  [ "$status" -eq 0 ]
  echo "$output" | grep -qw 1000 || false
}

# ════ hooks/validate-bash.sh — the guard ════════════════════════════════════════════════════════

decision() {  # $1 = command → DENY | ASK | ALLOW | PASS  (PASS = no decision emitted)
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" \
        | bash "$HOOK" 2>/dev/null)"
  [ -z "$out" ] && { printf 'PASS'; return 0; }
  # Parsing is part of the assertion: a decision the harness cannot parse is NOT enforced.
  printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"].upper())'
}

@test "guard: the four observed unscoped forms are DENIED" {
  [ "$(decision 'pkill -9 -f bats-core/bats')" = "DENY" ]
  [ "$(decision 'pkill -f "ship-land.sh --trunk main"')" = "DENY" ]
  [ "$(decision 'pkill -9 -f "bats tests/"')" = "DENY" ]
  [ "$(decision 'pkill -f bats-exec-test')" = "DENY" ]
}

@test "guard: killall, sudo, and a later clause in a compound are all reached" {
  [ "$(decision 'killall bats')" = "DENY" ]
  [ "$(decision 'sudo pkill -f bats')" = "DENY" ]
  [ "$(decision 'cd /tmp && pkill -9 -f bats-core/bats')" = "DENY" ]
  [ "$(decision 'foo || pkill -f "bats tests/"')" = "DENY" ]
}

@test "guard: every SCOPED form passes untouched" {
  [ "$(decision 'pkill -f "bats.*$(basename $PWD)"')" = "PASS" ]     # the form a0718a5d78b3 names
  [ "$(decision 'pkill -f "bats.*${PWD##*/}"')" = "PASS" ]
  [ "$(decision 'pkill -f "bats.*wt-d5534a171556"')" = "PASS" ]
  [ "$(decision 'pkill -f ".worktrees/gate-runaway-loop.*bats"')" = "PASS" ]
  [ "$(decision 'pkill -P 12345 -f bats')" = "PASS" ]                # parent-pid scope
  [ "$(decision './scripts/gate-cleanup.sh --force')" = "PASS" ]     # the helper itself
}

@test "guard: unrelated kills are none of its business" {
  [ "$(decision 'pkill -f my-daemon')" = "PASS" ]
  [ "$(decision 'killall Dock')" = "PASS" ]
  [ "$(decision 'echo hello')" = "PASS" ]
}

@test "guard: MENTIONING pkill in a message body is not executing it" {
  # The guard must not repeat, in its own detector, the text-is-not-execution defect it exists to
  # stop. A commit describing this very fix has to be writable.
  [ "$(decision 'git commit -m "fix: do not pkill bats"')" = "PASS" ]
  [ "$(decision 'git commit -m "fix(gate): scoped pkill; killall bats banned"')" = "PASS" ]
  [ "$(decision 'echo "never run pkill -9 -f bats-core/bats"')" = "PASS" ]
}

@test "guard: the emitted decision is VALID JSON even when the reason quotes the command" {
  # A malformed body means the harness cannot parse the decision, so the deny silently becomes a
  # no-op: a guard that REPORTS blocking while not blocking. `decision` above already fails on
  # unparsable output; this asserts the byte-level contract directly, on the worst case.
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"tool_input\":{\"command\":sys.argv[1]}}))' 'pkill -f \"ship-land.sh --trunk main\"' | bash '$HOOK' | python3 -m json.tool"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"permissionDecision": "deny"' || false
}

@test "guard: a reason containing quotes and backslashes survives json_escape" {
  run bash -c "python3 -c 'import json,sys;print(json.dumps({\"tool_input\":{\"command\":sys.argv[1]}}))' 'rm -rf \"a\\\\b\"' | bash '$HOOK' | python3 -m json.tool"
  [ "$status" -eq 0 ]
}

@test "guard: VALIDATE_BASH_DISABLED=1 is a real kill switch" {
  out="$(python3 -c 'import json;print(json.dumps({"tool_input":{"command":"pkill -9 -f bats-core/bats"}}))' \
        | VALIDATE_BASH_DISABLED=1 bash "$HOOK" 2>/dev/null)"
  [ -z "$out" ]
}

# ════ repo lint — no tracked script may ship an unscoped gate kill ══════════════════════════════

@test "lint: no tracked shell file contains a worktree-unscoped kill of gate processes" {
  # ONE detector, no drift: the lint does not re-implement the rule, it RUNS the guard over every
  # candidate line. A second copy of the pattern logic would rot out of sync with the hook, and
  # then the repo would ship exactly what the hook blocks at the keyboard.
  cd "$REPO"
  hits="$(git grep -hE '(pkill|killall)' -- '*.sh' '*.bats' 'bin/*' 'hooks/*' 'scripts/*' 2>/dev/null || true)"
  bad=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1)" in '#') continue ;; esac
    [ "$(decision "$line")" = "DENY" ] && bad="$bad
$line"
  done <<EOF
$hits
EOF
  [ -z "$bad" ] || { echo "unscoped gate kill(s) in tracked files:$bad"; false; }
}

@test "lint: the lint itself can FAIL (a zero-candidate sweep is not a pass)" {
  # A lint whose corpus is empty passes forever. Prove the detector fires on a planted line, so a
  # green result above means "checked and clean", not "checked nothing".
  [ "$(decision 'pkill -9 -f bats-core/bats')" = "DENY" ]
  cd "$REPO"
  n="$(git grep -hE '(pkill|killall)' -- '*.sh' '*.bats' 'bin/*' 'hooks/*' 'scripts/*' 2>/dev/null | grep -c . || true)"
  [ "$n" -gt 0 ]
}
