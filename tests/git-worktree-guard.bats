#!/usr/bin/env bats
# git-worktree-guard.bats — the -C blindness fix (2026-07-25): the guard's literal matches never
# saw `git -C <repo> worktree remove` / `git -C <repo> branch -d`, so the audit-§7 cleanup form
# ran entirely unguarded; and the worktree-list check ran in the hook's cwd, not the -C target.
# Red-proof: test 2 FAILS against the pre-fix guard (verified by stash-revert during authoring:
# `git -C … branch -d <held>` exited 0 instead of 2). Test 4 proves the -C form reaches the
# worktree-remove leg by being BLOCKED on a live target; its idle half alone would pass even an
# unmatched command (pass-through is also exit 0).

setup() {
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet): fixture $HOME FIRST so every test
  # inherits it. The git commands below already pass -c user.email/-c user.name explicitly, so they
  # do not depend on the real ~/.gitconfig this hides.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/projects"
  # The guard now writes a tombstone for every idle linked worktree it lets through (2b), so every
  # store it can reach points inside this test — the idle-path tests below would otherwise record
  # into whatever the library's defaults resolve to.
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset WT_TRUNK WT_NOW CC_WTGC_DISPOSAL_LOG CC_WTG_TOMBSTONE CC_WTG_TOMB_TIMEOUT
  export WT_LEDGER="$BATS_TEST_TMPDIR/ledger.jsonl" WT_TOMB_DIR="$BATS_TEST_TMPDIR/tombs" \
         WT_STATE_DIR="$BATS_TEST_TMPDIR/state" WT_CONFIG_ROOTS="$HOME/.claude"
  export WT_EVENTS_FILE="$WT_STATE_DIR/wt-events.jsonl" WT_WAKE_FILE="$WT_STATE_DIR/worktree-gc.wake" \
         WT_PARK_INDEX="$WT_STATE_DIR/wt-parked" WT_PARK_ROOT="$BATS_TEST_TMPDIR/parked"
  export CC_WTG_TOMBSTONE_LIB="$BATS_TEST_DIRNAME/../scripts/lib/wt-tombstone.sh"
  OUT="$BATS_TEST_TMPDIR/hook.out"; ERR="$BATS_TEST_TMPDIR/hook.err"   # guard_split's two streams
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
  [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null || true
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
  cd "$TDIR"   # NOT the repo — the -C target must be interrogated, not the cwd
  run run_guard "git -C $REPO worktree remove $TDIR/nonexistent-wt"
  [ "$status" -eq 0 ]
  # the discriminating half: exit 0 is also what an UNMATCHED command gets, so only a block on a
  # live target proves the -C form reached the leg at all
  spawn_live_probe "$TDIR/wt-held"
  run run_guard "git -C $REPO worktree remove $TDIR/wt-held"
  [ "$status" -eq 2 ]
}

# ── the liveness leg's own verdict — the guard's WHOLE PURPOSE, previously untested ──────────────
# Tests 3/4 once asserted only that the remove leg PASSES on idle, so the suite went green whether the
# guard blocked a live worktree or fell wide open (test 4 has since gained a live -C half).
# That is the fail-open-pinned-by-its-own-suite shape (memory: present-but-inverted-guard). These two
# pin both directions, and together they discriminate the batched lsof: a batch that lost the exact
# cwd match would block test B, and one that lost the population would miss test A.
@test "A: worktree remove of a LIVE worktree (process cwd'd in it) is BLOCKED" {
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  run run_guard "git worktree remove $TDIR/wt-held"
  [ "$status" -eq 2 ]
}

@test "A2: a LIVE worktree is still BLOCKED when the remove is followed by another command" {
  # The live check read the LAST non-flag token of the whole line, so `remove X && git branch -D y`
  # checked "y" and let X go (fail-open). It now reads the remove segment only.
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  run run_guard "git worktree remove $TDIR/wt-held && git branch -d some-other-branch"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'live process'
}

@test "A3: a relative LIVE path under git -C is resolved against the -C directory and BLOCKED" {
  cd "$BATS_TEST_TMPDIR"
  spawn_live_probe "$TDIR/wt-held"
  run run_guard "git -C $TDIR worktree remove wt-held"
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

# --- the two membership tests, drained 2026-08-28 (recycle #252) -----------------------------
# Both were `printf '%s\n' "$var" | grep -q…`, whose consumer exits at the FIRST match: the
# producer then takes EPIPE, `set -o pipefail` (:17) promotes that over grep's own 0, and the `if`
# reads FALSE ON A TRUE MATCH. In THIS file both inversions are fail-OPEN in a PreToolUse safety
# refusal — :52 force-deletes a branch that has a worktree, :115 lets a live worktree be removed.
#
# WHY 120,000 B AND NOT SOME OTHER NUMBER: measured 2026-08-28 at load ~20-27, needle on line 1 —
# this spelling is correct 20/20 at 4,000 B and 0/20 at 120,000 B, so a fixture at 120,000 B fails
# EVERY run against the old spelling rather than one run in twenty. Sizing a behavioural fixture
# from the measured regime is what makes it deterministic (memory: control-fixture-must-reach-the
# -bugs-regime). The REAL feeds are small — `git worktree list` 7,585 B, the lsof cwd list 3,580 B,
# both measured 0 inversions in 1,000 trials — so these arms pin the SHAPE, not today's exposure.

# Build an `lsof -Fn` payload of at least $2 bytes; $1, when non-empty, is placed on the FIRST line
# (the worst case: the earlier the needle, the sooner the consumer closes the pipe).
mk_cwd_payload() {  # $1=needle-path-or-empty  $2=bytes  $3=outfile
  { [ -n "$1" ] && printf 'n%s\n' "$1"
    awk -v want="$2" 'BEGIN{n=0; while(n<want){p=sprintf("n/Users/x/pad/path-%06d",n); print p; n+=length(p)+1}}'
  } > "$3"
}

# A stub lsof: the cwd leg (-Fn) gets the oversized payload, every other call answers nothing, so
# the SECOND liveness leg cannot rescue the verdict and the arm reads the FIRST leg alone.
mk_lsof_stub() {  # $1=outfile
  cat > "$1" <<'STUB'
#!/bin/bash
case "$*" in
  *-Fn*) cat "$CC_WTG_STUB_PAYLOAD" ;;
  *)     exit 1 ;;
esac
STUB
  chmod +x "$1"
}

@test "MECHANISM: a cwd list past the measured SIGPIPE floor still BLOCKS a live worktree" {
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  local wtabs stub payload
  wtabs="$(cd "$TDIR/wt-held" && pwd -P)"
  stub="$BATS_TEST_TMPDIR/lsof-stub"; payload="$BATS_TEST_TMPDIR/cwds-pos"
  mk_lsof_stub "$stub"
  mk_cwd_payload "$wtabs" 120000 "$payload"
  [ "$(wc -c < "$payload")" -ge 120000 ] || { echo "payload too small to reach the measured regime"; false; }
  run env CC_WTG_LSOF="$stub" CC_WTG_STUB_PAYLOAD="$payload" \
      bash -c "$(declare -f guard_json); guard_json 'git worktree remove $TDIR/wt-held' | bash '$GUARD'"
  [ "$status" -eq 2 ] || { echo "exited $status, expected 2 — the cwd leg lost a TRUE match at $(wc -c < "$payload") B"; false; }
  true
}

@test "NEG CONTROL: an oversized cwd list NOT naming the path must still pass (no blanket block)" {
  # Without this the arm above could pass by blocking unconditionally. Deliberately GREEN in both
  # states — it pins the other direction, and says so rather than reading as a second red.
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  local stub payload
  stub="$BATS_TEST_TMPDIR/lsof-stub"; payload="$BATS_TEST_TMPDIR/cwds-neg"
  mk_lsof_stub "$stub"
  mk_cwd_payload "" 120000 "$payload"
  run env CC_WTG_LSOF="$stub" CC_WTG_STUB_PAYLOAD="$payload" \
      bash -c "$(declare -f guard_json); guard_json 'git worktree remove $TDIR/wt-idle-nonexistent' | bash '$GUARD'"
  [ "$status" -eq 0 ] || { echo "exited $status, expected 0 — a non-member must not be blocked"; false; }
  true
}

@test "CLASS: the repo's own detector reports no early-exit pipe consumer in this hook" {
  # Keyed on the DETECTOR's predicate, not on my spelling, so it survives any rewording of the cure
  # (memory: control-calibrated-to-implementation-decays). Its POS control runs FIRST: a mute
  # detector would otherwise pass this arm vacuously with a table of zeros.
  local lint="$BATS_TEST_DIRNAME/../scripts/pipefail-sigpipe-lint.sh"
  [ -f "$lint" ] || { echo "detector missing at $lint"; false; }
  run bash "$lint" --census
  [ "$status" -eq 0 ] || { echo "--census exited $status"; false; }
  [ "$(printf '%s\n' "$output" | grep -c ':')" -ge 50 ] \
    || { echo "--census reported $(printf '%s\n' "$output" | grep -c ':') rows repo-wide — it is mute here, so this arm proves nothing"; false; }
  [ "$(printf '%s\n' "$output" | grep -c '^hooks/git-worktree-guard\.sh:')" -eq 0 ] \
    || { echo "detector still names $(printf '%s\n' "$output" | grep -c '^hooks/git-worktree-guard\.sh:') site(s) in this hook"; false; }
  true
}

# ── the tombstone arm (2b) and the prune arm (3) — DESIGN load-root-cause-2026-10-17 §3.7 item 8 ──
# WHAT IS LOAD-BEARING. The guard records INSIDE the hook and must stay invisible on success: any byte
# on stdout or stderr is a change to what the permission flow sees, which is the fault the second
# revision exists to remove. So every success case asserts BOTH streams empty, and every case asserts
# the tree is byte-identical afterwards — a PreToolUse hook runs before the permission decision, and a
# removal that is then denied must find the tree exactly as it was. The RED control at the end runs
# the pre-change hook on the residue case and pins that it recorded nothing.

lab() { # a bare origin + clone (trunk origin/main) with the X6 ignore list; sets L to the clone
  L="$BATS_TEST_TMPDIR/lab/main"
  git init -q --bare -b main "$BATS_TEST_TMPDIR/lab/origin.git"
  git init -q -b main "$L"
  printf 'node_modules/\n.next/\nbrag-output/\nasset-workspace/\n' > "$L/.gitignore"
  echo base > "$L/f.txt"
  git -C "$L" add -A && git -C "$L" commit -qm base
  git -C "$L" remote add origin "$BATS_TEST_TMPDIR/lab/origin.git" && git -C "$L" push -q -u origin main
  git -C "$L" remote set-head origin main
}

lwt() { # <name> → a linked worktree of $L on branch <name>; prints its physical path
  git -C "$L" worktree add -q -b "$1" "$BATS_TEST_TMPDIR/lab/wts/$1" main
  (cd "$BATS_TEST_TMPDIR/lab/wts/$1" && pwd -P)
}

# stdout → $OUT, stderr → $ERR, both set in setup(). Not assigned inside the helper: `run` executes it
# in a subshell, so anything it assigned would read EMPTY here and `[ ! -s "" ]` would pass vacuously.
guard_split() { # <command> [hook] → runs the hook with its two streams split into files; returns its rc
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" \
    | bash "${2:-$GUARD}" >"$BATS_TEST_TMPDIR/hook.out" 2>"$BATS_TEST_TMPDIR/hook.err"
}

nrows() { if [ -f "$WT_LEDGER" ]; then grep -c . "$WT_LEDGER"; else echo 0; fi; }
lastrow() { tail -1 "$WT_LEDGER"; }
tree_sums() { (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs shasum); }
dfree_kb() { df -k "$BATS_TEST_TMPDIR" | awk 'NR==2{print $4}'; }

@test "TOMBSTONE: idle tree with ignored residue → exit 0, both streams empty, one guard-snapshot row, residue cloned, tree untouched" {
  lab; w="$(lwt res)"
  mkdir -p "$w/brag-output"; echo '{"run":1}' > "$w/brag-output/x.json"
  before="$(tree_sums "$w")"
  run guard_split "git -C $L worktree remove $w"
  [ "$status" -eq 0 ] || { echo "exit $status: $(cat "$ERR")"; false; }
  [ ! -s "$OUT" ] || { echo "stdout not empty: $(cat "$OUT")"; false; }
  [ ! -s "$ERR" ] || { echo "stderr not empty: $(cat "$ERR")"; false; }
  [ "$(nrows)" -eq 1 ]
  row="$(lastrow)"
  [ "$(printf '%s' "$row" | jq -r .event)" = guard-snapshot ]
  [ "$(printf '%s' "$row" | jq -r .mode)" = clone ]
  [ "$(printf '%s' "$row" | jq -r .actor)" = guard-raw ]
  [ "$(printf '%s' "$row" | jq -r .path)" = "$w" ]
  [ "$(printf '%s' "$row" | jq -c .preserved_list)" = '["brag-output"]' ]
  cmp "$w/brag-output/x.json" "$WT_TOMB_DIR/$(printf '%s' "$row" | jq -r .id)/residue/brag-output/x.json"
  [ "$(tree_sums "$w")" = "$before" ] || { echo "the tree changed under the hook"; false; }
  git -C "$L" worktree list --porcelain | grep -Fx "worktree $w" >/dev/null
}

@test "TOMBSTONE: only a node_modules matching its pnpm lock → a row with an empty preserved_list" {
  lab; w="$(lwt nm)"
  echo 'lockfileVersion: 9' > "$w/pnpm-lock.yaml"
  git -C "$w" add pnpm-lock.yaml && git -C "$w" commit -qm lock
  mkdir -p "$w/node_modules/.pnpm" && cp "$w/pnpm-lock.yaml" "$w/node_modules/.pnpm/lock.yaml"
  run guard_split "git -C $L worktree remove $w"
  if ! { [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; }; then echo "exit $status: $(cat "$ERR")"; false; fi
  [ "$(nrows)" -eq 1 ]
  [ "$(lastrow | jq -c .preserved_list)" = '[]' ]
  [ "$(lastrow | jq -c .caches_skipped)" = '["node_modules"]' ]
}

@test "TOMBSTONE: --force on a dirty tree → the wip ref holds tracked + untracked at working content; tree untouched and still intact after a later deny" {
  lab
  for flags in "--force" "-f -f"; do
    name="dirty$(printf '%s' "$flags" | tr -dc 'a-z')"
    w="$(lwt "$name")"
    echo modified > "$w/f.txt"; echo fresh > "$w/new.txt"
    before="$(tree_sums "$w")"
    run guard_split "git -C $L worktree remove $flags $w"
    if ! { [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; }; then echo "[$flags] exit $status: $(cat "$ERR")"; false; fi
    wip="$(lastrow | jq -r .wip_ref)"
    [ "$wip" != null ] || { echo "[$flags] no wip_ref in $(lastrow)"; false; }
    [ "$(git -C "$L" show "$wip:f.txt")" = modified ]
    [ "$(git -C "$L" show "$wip:new.txt")" = fresh ]
    # A later hook denies: the removal never runs, and the tree must be exactly as the session left it.
    [ "$(tree_sums "$w")" = "$before" ] || { echo "[$flags] the tree changed under the hook"; false; }
    [ "$(git -C "$w" status --porcelain | LC_ALL=C sort | tr '\n' ' ')" = " M f.txt ?? new.txt " ]
  done
  # a NON-forced removal of a dirty tree gets no wip snapshot (git refuses it on its own)
  w="$(lwt dirtyplain)"; echo modified > "$w/f.txt"
  run guard_split "git -C $L worktree remove $w"
  [ "$status" -eq 0 ]
  [ "$(lastrow | jq -r .wip_ref)" = null ]
}

@test "TOMBSTONE: 120 MB .next and 120 MB asset-workspace both pass; .next skipped, asset-workspace cloned at ~0 free-space cost" {
  lab
  w1="$(lwt nextjs)"; mkdir -p "$w1/.next/cache"; /usr/sbin/mkfile -n 120m "$w1/.next/cache/big.pack"
  w2="$(lwt assets)"; mkdir -p "$w2/asset-workspace"; /usr/sbin/mkfile -n 120m "$w2/asset-workspace/big.bin"
  f0="$(dfree_kb)"
  run guard_split "git -C $L worktree remove $w1"
  if ! { [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; }; then echo "next: exit $status: $(cat "$ERR")"; false; fi
  [ "$(lastrow | jq -c .preserved_list)" = '[]' ]
  [ "$(lastrow | jq -c .caches_skipped)" = '[".next"]' ]
  [ ! -e "$WT_TOMB_DIR/$(lastrow | jq -r .id)/residue/.next" ]
  run guard_split "git -C $L worktree remove $w2"
  if ! { [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; }; then echo "assets: exit $status: $(cat "$ERR")"; false; fi
  f1="$(dfree_kb)"
  [ "$(lastrow | jq -c .preserved_list)" = '["asset-workspace"]' ]
  cmp "$w2/asset-workspace/big.bin" "$WT_TOMB_DIR/$(lastrow | jq -r .id)/residue/asset-workspace/big.bin"
  d=$(( f0 - f1 )); [ "$d" -lt 0 ] && d=$(( -d ))
  # The volume is shared with every other process on the box, so free space moves on its own (33 MB
  # measured during one run). A data copy of the 120 MB file would move ~120 MB; a clone moves ~0.
  # Half the file size separates the two with room for that background churn.
  [ "$d" -le 61440 ] || { echo "free space moved ${d} KB across the clones (cap 61440 = half a real copy)"; false; }
}

@test "FAIL-CLOSED: missing library, failed tombstone and an overrun bound each exit 2 naming the step, tree untouched" {
  lab; w="$(lwt failing)"
  mkdir -p "$w/brag-output"; echo keep > "$w/brag-output/x.json"
  before="$(tree_sums "$w")"
  run env CC_WTG_TOMBSTONE_LIB=/nonexistent/wt-tombstone.sh bash -c "$(declare -f guard_split); GUARD='$GUARD' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' guard_split 'git -C $L worktree remove $w'"
  [ "$status" -eq 2 ] || { echo "missing lib: exit $status"; false; }
  grep -F "step 'locate library'" "$BATS_TEST_TMPDIR/hook.err" >/dev/null
  [ "$(grep -c . "$BATS_TEST_TMPDIR/hook.err")" -eq 1 ]
  run env WT_LEDGER=/dev/null/ledger.jsonl bash -c "$(declare -f guard_split); GUARD='$GUARD' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' guard_split 'git -C $L worktree remove $w'"
  [ "$status" -eq 2 ] || { echo "unwritable ledger: exit $status"; false; }
  grep -F "step 'tombstone' failed" "$BATS_TEST_TMPDIR/hook.err" >/dev/null
  stub="$BATS_TEST_TMPDIR/stub-lib.sh"
  printf 'wt_tombstone() { sleep 30; }\n' > "$stub"
  t0="$(date +%s)"
  run env CC_WTG_TOMBSTONE_LIB="$stub" CC_WTG_TOMB_TIMEOUT=1 bash -c "$(declare -f guard_split); GUARD='$GUARD' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' guard_split 'git -C $L worktree remove $w'"
  el=$(( $(date +%s) - t0 ))
  [ "$status" -eq 2 ] || { echo "overrun: exit $status"; false; }
  [ "$el" -le 3 ] || { echo "overrun took ${el}s, bound 1s (+1s kill grace)"; false; }
  grep -F "timed out after 1s" "$BATS_TEST_TMPDIR/hook.err" >/dev/null
  [ "$(tree_sums "$w")" = "$before" ]
}

@test "PRUNE: a raw prune of a deleted tree's admin entry → exit 0 silent, one admin-pruned row, admin dir left for the command; --dry-run and -n record nothing" {
  lab; w="$(lwt gone)"
  rm -rf "$w"
  run guard_split "git -C $L worktree prune"
  if ! { [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ]; }; then echo "exit $status: $(cat "$ERR")"; false; fi
  [ "$(nrows)" -eq 1 ]
  [ "$(lastrow | jq -r .event)" = admin-pruned ]
  [ "$(lastrow | jq -r .branch)" = gone ]
  [ -d "$L/.git/worktrees/gone" ] || { echo "the hook pruned — only the command may"; false; }
  for dry in "--dry-run" "-n" "-nv"; do
    run guard_split "git -C $L worktree prune $dry"
    [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ] || false
    [ "$(nrows)" -eq 1 ] || { echo "[$dry] recorded a row"; false; }
  done
}

@test "SEAM + SCOPE: CC_WTG_TOMBSTONE=off and a non-worktree directory both pass and record nothing" {
  lab; w="$(lwt seam)"; mkdir -p "$BATS_TEST_TMPDIR/plain"
  run env CC_WTG_TOMBSTONE=off bash -c "$(declare -f guard_split); GUARD='$GUARD' BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' guard_split 'git -C $L worktree remove $w'"
  [ "$status" -eq 0 ]
  run guard_split "git -C $L worktree remove $BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ] && [ ! -s "$OUT" ] && [ ! -s "$ERR" ] || false
  [ "$(nrows)" -eq 0 ]
}

@test "RED CONTROL: the pre-change hook lets the residue case through and records NOTHING" {
  lab; w="$(lwt red)"
  mkdir -p "$w/brag-output"; echo '{"run":1}' > "$w/brag-output/x.json"
  old="$BATS_TEST_TMPDIR/guard-pre.sh"
  git -C "$BATS_TEST_DIRNAME/.." show 7fa90e0c2:hooks/git-worktree-guard.sh > "$old"
  run guard_split "git -C $L worktree remove $w" "$old"
  [ "$status" -eq 0 ]
  [ "$(nrows)" -eq 0 ] || { echo "the pre-change hook recorded a row — this control no longer discriminates"; false; }
}
