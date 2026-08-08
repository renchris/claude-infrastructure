#!/usr/bin/env bats
# git-worktree-guard.bats — the -C blindness fix (2026-07-25): the guard's literal matches never
# saw `git -C <repo> worktree remove` / `git -C <repo> branch -d`, so the audit-§7 cleanup form
# ran entirely unguarded; and the worktree-list check ran in the hook's cwd, not the -C target.
# Red-proof: test 2 FAILS against the pre-fix guard (verified by stash-revert during authoring:
# `git -C … branch -d <held>` exited 0 instead of 2). Test 4 is a reaches-the-leg smoke only —
# its idle path exits 0 pre- and post-fix, so it discriminates nothing on its own.

setup() {
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet): fixture $HOME FIRST so every test
  # inherits it. The git commands below already pass -c user.email/-c user.name explicitly, so they
  # do not depend on the real ~/.gitconfig this hides.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TDIR="$(mktemp -d)"
  export REPO="$TDIR/repo"
  git init -q "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$REPO" worktree add -q "$TDIR/wt-held" -b held-branch
  GUARD="$BATS_TEST_DIRNAME/../hooks/git-worktree-guard.sh"
}

teardown() {
  # Kill the liveness probe FIRST. A backgrounded grandchild that outlives the test holds bats' TAP
  # fd open and wedges the whole run (memory: fixture-lifetime-is-an-orphan-leak-bound) — which is
  # why the probe below is spawned with all three fds detached and is killed unconditionally here.
  [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null
  git -C "$REPO" worktree remove --force "$TDIR/wt-held" 2>/dev/null || true
  rm -rf "$TDIR"
}

# Spawn a process that (a) matches `pgrep -f claude` and (b) is cwd'd in $1 — i.e. exactly what the
# liveness leg exists to find. `exec -a` sets argv[0], which is what pgrep -f reads.
spawn_live_probe() {
  ( cd "$1" && exec -a "claude-guard-liveprobe" sleep 120 ) >/dev/null 2>&1 </dev/null &
  PROBE_PID=$!
  sleep 0.4   # let the exec land so lsof can see the cwd
}

run_guard() {  # $1 = the bash command string
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" | bash "$GUARD"
}

@test "plain branch -d of a worktree-held branch is BLOCKED" {
  cd "$REPO"
  run run_guard "git branch -d held-branch"
  [ "$status" -eq 2 ]
}

@test "-C form: branch -d of a worktree-held branch is BLOCKED from any cwd" {
  cd "$TDIR"   # NOT the repo — the -C target must be interrogated, not the cwd
  run run_guard "git -C $REPO branch -d held-branch"
  [ "$status" -eq 2 ]
}

@test "plain worktree remove of a non-live path passes (fail-open on idle)" {
  cd "$REPO"
  run run_guard "git worktree remove $TDIR/nonexistent-wt"
  [ "$status" -eq 0 ]
}

@test "-C form reaches the worktree-remove leg (idle path still passes)" {
  cd "$TDIR"
  run run_guard "git -C $REPO worktree remove $TDIR/nonexistent-wt"
  [ "$status" -eq 0 ]
}

# ── the liveness leg's own verdict — the guard's WHOLE PURPOSE, previously untested ──────────────
# Tests 3/4 only assert the remove leg PASSES on idle, so the suite went green whether the guard
# blocked a live worktree or fell wide open (this file's own header: test 4 "discriminates nothing").
# That is the fail-open-pinned-by-its-own-suite shape (memory: present-but-inverted-guard). These two
# pin both directions, and together they discriminate the batched lsof: a batch that lost the exact
# cwd match would block test B, and one that lost the population would miss test A.
@test "A: worktree remove of a LIVE worktree (process cwd'd in it) is BLOCKED" {
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  run run_guard "git worktree remove $TDIR/wt-held"
  [ "$status" -eq 2 ]
}

@test "B: worktree remove of a real IDLE worktree passes despite claude processes elsewhere" {
  cd "$REPO"
  git -C "$REPO" worktree add -q "$TDIR/wt-idle" -b idle-branch
  spawn_live_probe "$TDIR"           # live, matches pgrep — but cwd'd OUTSIDE the target worktree
  run run_guard "git worktree remove $TDIR/wt-idle"
  [ "$status" -eq 0 ]
}

@test "unrelated git commands pass through untouched" {
  cd "$REPO"
  run run_guard "git -C $REPO log --oneline -1"
  [ "$status" -eq 0 ]
}

@test "branch delete of a NON-held branch passes" {
  cd "$REPO"
  git -C "$REPO" branch free-branch
  run run_guard "git branch -d free-branch"
  [ "$status" -eq 0 ]
}

# ── PATH INDEPENDENCE (2026-08-08) ───────────────────────────────────────────────────────────────
# Every test above runs on the ambient session PATH, which carries /usr/sbin — so none of them could
# see the defect that lived here. lsof IS /usr/sbin/lsof, and the PATH a LaunchAgent exports for its
# children stops at /usr/bin:/bin. Off-session, both liveness calls found nothing, `live` stayed 0,
# and this SAFETY REFUSAL returned 0: it permitted exactly the removal it exists to block. Measured
# at trunk under the literal PATH below — test A returned 0, not 2 — and 8/8 on the same tree with
# /usr/sbin restored, which is what isolates the cause to PATH and nothing else.

# The runner's literal PATH, read FROM THE PLIST rather than restated here: a copy in the test could
# drift from the plist and pass while production is broken. This suite is executed BY that job, so
# it is the environment in which the defect was measured, not a hypothetical one.
runner_path() {
  /usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' \
    "$BATS_TEST_DIRNAME/../launchd/com.claude.postland-verify.plist" 2>/dev/null \
    | sed -n 's/.*export PATH="\([^"]*\)".*/\1/p'
}

guard_json() {  # $1 = command string → the hook's stdin payload. Paths here come from mktemp -d,
  printf '{"tool_input":{"command":"%s"}}' "$1"   # so they carry no quote/backslash to escape.
}

@test "RED CONTROL: the corpus runner's own PATH really does hide a bare lsof" {
  # If this ever passes, /usr/sbin joined that PATH and the two tests below prove nothing — a control
  # that cannot fail is not a control.
  local p; p="$(runner_path)"; p="${p//\$HOME/$HOME}"
  [ -n "$p" ] || { echo "could not parse PATH from the postland-verify plist"; false; }
  run env -i PATH="$p" HOME="$HOME" bash -c 'command -v lsof'
  [ "$status" -ne 0 ] || { echo "lsof IS reachable on: $p — this suite no longer discriminates"; false; }
}

@test "PATH-INDEPENDENT: a LIVE worktree is still BLOCKED with /usr/sbin off the PATH" {
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  local p; p="$(runner_path)"; p="${p//\$HOME/$HOME}"
  run env PATH="$p" bash -c "$(declare -f guard_json); guard_json 'git worktree remove $TDIR/wt-held' | bash '$GUARD'"
  [ "$status" -eq 2 ]
}

@test "THIRD STATE: an UNRESOLVABLE lsof BLOCKS — unreadable liveness is not 'nothing is live'" {
  # Deliberately no live probe: even the idle-looking path must refuse, because an oracle that cannot
  # answer cannot distinguish idle from live. Both spellings of unresolvable are pinned — set-but-
  # EMPTY (honoured verbatim; the only way to reach this branch on a host that HAS /usr/sbin/lsof)
  # and a path that does not exist. The pre-fix code took the opposite branch on both: `command -v`
  # turned a missing lsof into a clean skip and the guard exited 0.
  cd "$REPO"
  local v
  for v in "" /nonexistent/lsof; do
    run env CC_WTG_LSOF="$v" bash -c "$(declare -f guard_json); guard_json 'git worktree remove $TDIR/wt-held' | bash '$GUARD'"
    [ "$status" -eq 2 ] || { echo "CC_WTG_LSOF=[$v] exited $status, expected 2 (fail-CLOSED)"; false; }
    [[ "$output" == *"lsof is not resolvable"* ]] || { echo "wrong refusal for CC_WTG_LSOF=[$v]: $output"; false; }
  done
}
