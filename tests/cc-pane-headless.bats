#!/usr/bin/env bats
# cc-pane-headless — the SCALING driver (T2 of docs/plans/TERMINAL_AGNOSTIC_L3_L4.md).
#
# The design claim under test is "an addressable agent with NO surface", so the tests are built
# to falsify exactly that: a poisoned `it2` on PATH fails loudly if the driver ever reaches for a
# terminal, and the lifecycle assertions are all made against the OS (pid, process state) rather
# than against the driver's own bookkeeping.
#
# Two of these RED-prove defects that were real in the first cut and were caught by smoke test
# before any test existed — both are pinned here so they cannot return:
#   * BSD `hexdump -e` PADS to the field width, minting ids with 16 trailing spaces;
#   * `kill -0` SUCCEEDS on a ZOMBIE, so `spawn -- /usr/bin/false` returned rc 0 and a fresh id
#     (memory: kill-on-reaped-child-fails-fast-path-hides-it).
#
# Every assertion is `[ ]` / `|| false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and
# would be silently DEAD in any but the body's last line.

setup() {
  # Same hermeticity contract as the sibling suite: fixture $HOME first, because the headless
  # registry's own default is $HOME/.claude/autonomy/panes — an unfixtured run would spawn and
  # REAP processes in the operator's live registry.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-pane"
  export CC_PANE_DRIVER=headless
  export CC_PANE_HOME="$BATS_TEST_TMPDIR/panes"
  export CC_PANE_KILL_WAIT_S=3
  # Poison every terminal entrypoint. If the headless driver ever shells out to one, these turn a
  # silent design violation into a loud, attributable failure.
  local pz="$BATS_TEST_TMPDIR/poison"; mkdir -p "$pz"
  local t
  for t in it2 osascript tmux; do
    printf '#!/bin/bash\necho "HEADLESS TOUCHED A TERMINAL: %s $*" >&2\nexit 66\n' "$t" > "$pz/$t"
    chmod +x "$pz/$t"
  done
  export PATH="$pz:$PATH"
}

teardown() {
  # Never leave a spawned sleeper behind if an assertion aborted mid-test.
  local d p
  for d in "$CC_PANE_HOME"/hdl-* "$CC_PANE_HOME"/dead-*; do
    [ -d "$d" ] || continue
    p="$(sed -n 's/^pid=//p' "$d/meta" 2>/dev/null | head -1)"
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null
  done
  return 0
}

live_pid() { sed -n 's/^pid=//p' "$CC_PANE_HOME/$1/meta" | head -1; }

# ── spawn: an addressable id, no surface ──────────────────────────────────────────────────

@test "spawn mints an addressable id WITHOUT touching any terminal" {
  run "$CP" spawn -- sleep 30
  [ "$status" -eq 0 ]
  # The poison stubs exit 66 and shout on stderr; neither may appear.
  [ "$status" -ne 66 ]
  printf '%s' "$output" | grep -q 'TOUCHED A TERMINAL' && false
  printf '%s' "$output" | grep -qE '^hdl-[0-9a-f]{16}$' || false
}

@test "RED-proof: the minted id carries NO trailing whitespace" {
  # BSD `hexdump -n 8 -e '4/4 "%08x"'` pads to the field width and minted
  # `hdl-<16hex><16 spaces>` — an id that becomes a directory name with trailing spaces and
  # compares unequal to its own echoed form. `od` is used instead; this pins it.
  run "$CP" spawn -- sleep 30
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 20 ]
  case "$output" in *" "*) false ;; esac
}

@test "RED-proof: a dead-on-arrival spawn is rc 1 with NO id on stdout" {
  # `kill -0` succeeds on a zombie, so the naive liveness check returned rc 0 and a usable-looking
  # id for a process that had already exited. Callers would then address a corpse forever.
  run "$CP" spawn -- /usr/bin/false
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q '^hdl-' && false
  printf '%s' "$output" | grep -q 'exited immediately' || false
}

@test "RED-proof: a ZOMBIE pid is NOT live — kill -0 is fooled by one, so state must be read" {
  # The dead-on-arrival test above CANNOT prove this on its own: whether an exited child is still
  # a zombie or has already been reaped is a RACE, and when it loses the race a naive `kill -0`
  # fails "correctly" and the guard looks proven when it is not. The red-proof harness caught
  # exactly that — the kill -0 mutant SURVIVED (memory:
  # kill-on-reaped-child-fails-fast-path-hides-it, "a no-delay repro proves nothing").
  #
  # So the zombie is constructed DETERMINISTICALLY instead of raced for: a perl parent forks a
  # child that exits immediately and never waits on it, so the child is pinned in state Z for as
  # long as the parent lives. Measured on this box: `ps -o stat=` reads Z while `kill -0` reports
  # ALIVE. The control asserts the Z PREFIX, not an exact flag string — a niced zombie reads `ZN`,
  # and the trailing scheduling flags are incidental to the zombie property under test.
  local zp
  perl -e '$|=1; my $p=fork(); if($p==0){exit 0} print "$p\n"; sleep 20;' > "$BATS_TEST_TMPDIR/zpid" &
  local perlpid=$!
  local waited=0
  while [ ! -s "$BATS_TEST_TMPDIR/zpid" ] && [ "$waited" -lt 50 ]; do sleep 0.1; waited=$((waited+1)); done
  zp="$(cat "$BATS_TEST_TMPDIR/zpid")"
  [ -n "$zp" ]
  # positive control: the fixture really is a zombie, and kill -0 really is fooled by it.
  # Without this the test could pass because the pid was simply GONE — a different, easier case
  # that would leave the actual claim unproven.
  case "$(ps -o stat= -p "$zp" | tr -d ' ')" in Z*) ;; *) false ;; esac
  run kill -0 "$zp"
  [ "$status" -eq 0 ]

  # Point a registry row at the zombie and require the driver to call it DEAD.
  mkdir -p "$CC_PANE_HOME/hdl-0000000000000001"
  printf 'id=hdl-0000000000000001\npid=%s\npstart=\n' "$zp" > "$CC_PANE_HOME/hdl-0000000000000001/meta"
  run "$CP" address hdl-0000000000000001
  [ "$status" -eq 1 ]
  run "$CP" send hdl-0000000000000001 hello
  [ "$status" -eq 1 ]
  kill -9 "$perlpid" 2>/dev/null
  return 0
}

@test "a dead-on-arrival spawn PRESERVES its log where list's reap cannot race-delete it" {
  run "$CP" spawn -- /usr/bin/false
  [ "$status" -eq 1 ]
  ls "$CC_PANE_HOME"/dead-* >/dev/null 2>&1 || false
  run "$CP" list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ls "$CC_PANE_HOME"/dead-* >/dev/null 2>&1 || false
}

@test "spawn REFUSES with no command — a headless pane IS a process, or liveness is unfalsifiable" {
  run "$CP" spawn
  [ "$status" -eq 3 ]
}

@test "spawn refuses a --cwd that does not exist instead of silently using \$PWD" {
  run "$CP" spawn --cwd "$BATS_TEST_TMPDIR/nope" -- sleep 30
  [ "$status" -eq 1 ]
}

@test "the registry is owner-only — an agent's inbox and full output log are not world-readable" {
  local id perms
  id="$("$CP" spawn -- sleep 30)"
  perms="$(stat -f '%Lp' "$CC_PANE_HOME/$id")"
  [ "$perms" = "700" ]
}

@test "argv is recorded but NEVER re-executed — shell metacharacters stay literal" {
  # The whole json-quoting-is-not-shell-quoting injection class is excluded by construction:
  # argv is exec'd as "$@" and only ever serialised for the human-readable record. If any path
  # re-parsed the record as shell, this payload would create the canary.
  #
  # The payload rides as $0 of a `bash -c` whose SCRIPT is inert, so the agent stays alive and
  # the assertion is about the payload's literalness rather than about a spawn failure. (A first
  # cut passed it to `sleep`, which correctly rejected the whole string as one bad operand —
  # right property, but proven via a dead process, which is a much weaker witness.)
  local id canary="$BATS_TEST_TMPDIR/canary"
  id="$("$CP" spawn -- /bin/bash -c 'sleep 30' "; touch $canary")"
  [ -n "$id" ]
  sleep 1
  [ ! -f "$canary" ]
  run "$CP" address "$id"
  [ "$status" -eq 0 ]
  # the record kept the payload verbatim, and keeping it changed nothing
  grep -qF "; touch $canary" "$CC_PANE_HOME/$id/argv" || false
  [ ! -f "$canary" ]
}

# ── address / send ────────────────────────────────────────────────────────────────────────

@test "address resolves a live id and refuses an unknown one" {
  local id
  id="$("$CP" spawn -- sleep 30)"
  run "$CP" address "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
  run "$CP" address "hdl-0000000000000000"
  [ "$status" -eq 1 ]
}

@test "send delivers durably into the id's inbox" {
  local id
  id="$("$CP" spawn -- sleep 30)"
  run "$CP" send "$id" hello agent
  [ "$status" -eq 0 ]
  grep -q 'hello agent' "$CC_PANE_HOME/$id/inbox" || false
}

@test "send to a DEAD id is rc 1 — delivery to a corpse is never reported as success" {
  local id pid
  id="$("$CP" spawn -- sleep 30)"
  pid="$(live_pid "$id")"
  kill -9 "$pid"
  sleep 1
  run "$CP" send "$id" hello
  [ "$status" -eq 1 ]
}

@test "address goes rc 1 the moment the process dies, on the OS's word not the registry's" {
  local id pid
  id="$("$CP" spawn -- sleep 30)"
  pid="$(live_pid "$id")"
  run "$CP" address "$id"
  [ "$status" -eq 0 ]
  kill -9 "$pid"
  sleep 1
  # The registry row still exists here — that is the point. Liveness must come from the kernel.
  [ -d "$CC_PANE_HOME/$id" ]
  run "$CP" address "$id"
  [ "$status" -eq 1 ]
}

# ── close / list ──────────────────────────────────────────────────────────────────────────

@test "close actually reaps the process, verified by EXACT pid" {
  local id pid
  id="$("$CP" spawn -- sleep 45)"
  pid="$(live_pid "$id")"
  kill -0 "$pid"
  run "$CP" close "$id"
  [ "$status" -eq 0 ]
  # By exact pid, never `pgrep -f` — argv-pattern matching counts unrelated sessions whose
  # command line merely MENTIONS the pattern (memory: pgrep-f-matches-agent-briefs).
  run kill -0 "$pid"
  [ "$status" -ne 0 ]
  [ ! -d "$CC_PANE_HOME/$id" ]
}

@test "close reaps a process that ignores SIGTERM" {
  local id pid
  id="$("$CP" spawn -- /bin/bash -c 'trap "" TERM; sleep 45')"
  pid="$(live_pid "$id")"
  run "$CP" close "$id"
  [ "$status" -eq 0 ]
  run kill -0 "$pid"
  [ "$status" -ne 0 ]
}

@test "list enumerates live ids and reaps dead rows on read" {
  local a b pb
  a="$("$CP" spawn -- sleep 45)"
  b="$("$CP" spawn -- sleep 45)"
  run "$CP" list
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  pb="$(live_pid "$b")"
  kill -9 "$pb"
  sleep 1
  run "$CP" list
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "$a" ]
  [ ! -d "$CC_PANE_HOME/$b" ]
}

@test "an empty registry is a TRUE empty (rc 0), not indeterminate" {
  run "$CP" list
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "RED-proof: an UNREADABLE registry is INDETERMINATE (rc 2), never an empty fleet" {
  # The symmetric case to the iterm2 driver's blind-enumerator refusal. Without it the glob
  # silently yields nothing and a caller concludes the whole headless fleet is gone. Found by
  # shellcheck SC2034 flagging RC_INDET as unused here while the iterm2 driver used it — the
  # asymmetry WAS the bug.
  mkdir -p "$CC_PANE_HOME"
  chmod 000 "$CC_PANE_HOME"
  run "$CP" list
  chmod 700 "$CC_PANE_HOME"
  [ "$status" -eq 2 ]
}

@test "a headless id survives being addressed by a DIFFERENT process — the registry is the seam" {
  # Level 3 has ~95 of 100 agents with no pane, addressed by an orchestrator that did not spawn
  # them. If addressing only worked from the spawning shell, none of that is reachable.
  local id
  id="$("$CP" spawn -- sleep 30)"
  run env CC_PANE_DRIVER=headless CC_PANE_HOME="$CC_PANE_HOME" "$CP" address "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
}
