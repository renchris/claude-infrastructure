#!/usr/bin/env bats
# session-register.sh — the WORKER-KEYED BACKLOG CLAIM actuator (backlog a13fb1d41044).
#
# cc-dispatch claims a backlog item with `--by <host>-$$` — its own pid — and then exits, so the
# ledger's claim names a dead process within seconds. Past cc-backlog's stale gate `claimer_live` is
# false BY CONSTRUCTION for every dispatched item, and the dead-worker sweep degrades to age-only: a
# live 91-minute worker gets its item reopened (a second peer onto live work), a worker dead at
# minute 5 strands 85 minutes. The dispatcher cannot fix it — the session it is spawning has no
# identity yet. This hook fixes it from the worker's side: at SessionStart, from inside the worktree
# that names the item, it re-keys the claim to its own durable `claude` pid.
#
# WHY THIS SUITE RUNS THE HOOK UNDER `command /bin/bash`: macOS /bin/bash is 3.2, and its two known
# runtime deaths (a `case` pattern inside `$( )`, a control-char `IFS` that never splits) are SILENT
# and pass `bash -n`, shellcheck, and zsh alike (memory: bash32-case-in-substitution-zsh-repro-trap).
# The reclaim path has both shapes — a `case` over a command substitution and a function invoked as
# `$(claude_ancestor_pid)` whose body is a `case` — so every assertion here is on the EFFECT (a record
# in the ledger, a line in the IDL), never on the hook's own report of itself.
#
# The load-bearing test is "round trip": the identity string this WRITER emits must be resolvable by
# the READER that consumes it (cc-backlog's claimer_live), which only takes the cheap `kill -0` path
# when `$by` equals "$host-$pid" for its OWN host derivation. Two independently-correct halves that
# disagree on the host spelling would yield a claim that resolves as PROVEN DEAD — worse than no fix
# at all (memory: output-must-round-trip-into-input).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-register.sh"
  CB="$REPO/bin/cc-backlog"
  # HERMETIC $HOME (enforced by scripts/test-hermeticity-lint.sh, which this land is scoped by). Both
  # subjects fall back to $HOME when their seams are unset — the hook's IDL and cc-backlog resolution,
  # cc-backlog's own ledger, session registry, and worktree root — so an unfixtured run would read and
  # write the operator's live ~/.claude. Every seam below is also set explicitly; $HOME is the backstop
  # that catches the one someone forgets to override later.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export SESSION_REGISTER_BACKLOG_BIN="$CB"
  export SESSION_REGISTER_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  # The registry oracle: EMPTY, so no session-shaped claimer is ever live and the pid path is the
  # only thing that can absolve — the isolation every verdict below depends on.
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"
  DEADPID=2147483647
  # In production the re-key is DETACHED (the hook must not delay a session start), which makes the
  # moment of effect nondeterministic — and no amount of polling can prove a NEGATIVE case wrote
  # nothing. This seam runs it in the foreground so every assertion below has a defined observation
  # point. The detached shape that actually ships is covered by its own case at the end of this file.
  export SESSION_REGISTER_RECLAIM_WAIT=1
}

# NEGATIVE assertions must NOT be written `! cmd`: bash exempts a `!`-inverted command from set -e, so
# such a line only fails the test when it is the LAST line of the body. These return non-zero directly.
refute_match()   { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }
refute_in_file() { [ ! -s "$2" ] || [ "$(grep -c "$1" "$2")" -eq 0 ]; }

# fire <cwd> — run the hook exactly as SessionStart does: JSON on stdin, under /bin/bash 3.2.
#
# `3>&-` is mandatory, not hygiene: the hook detaches a child in its production path, and a background
# process that inherits bats' fd 3 makes bats emit a phantom `not ok` beside the real `ok` (plus
# "Executed 2 instead of expected 1 tests") for a body that passed. The landing gate's verdict is
# `grep -c '^not ok'`, so one fabricated line refuses a push no assertion ever failed
# (memory: bats-background-job-fabricates-not-ok — it wedged every /ship on 2026-07-25). The hook
# closes fd 3 on its own detached child too; this closes it one level earlier, at the boundary bats
# actually owns.
fire() {
  printf '{"cwd":"%s","session_id":"deadbeef-0000-0000-0000-000000000000"}' "$1" \
    | command /bin/bash "$HOOK" 3>&-
}

# a dispatched item, claimed the way cc-dispatch claims it: the dispatcher's own, now-dead, pid.
dispatched_item() {
  local id; id="$(bash "$CB" add --project /r --title "$1" --source s)"
  bash "$CB" claim "$id" --by "$HOST-$DEADPID" >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  printf '%s' "$id"
}

by_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.by'; }

@test "in a dispatch worktree: the claim is re-keyed from the dead dispatcher pid to this worker" {
  id="$(dispatched_item reclaim-basic)"
  [ "$(by_of "$id")" = "$HOST-$DEADPID" ]                     # precondition: the V1 shape
  run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
  new="$(by_of "$id")"
  [ "$new" != "$HOST-$DEADPID" ]
  echo "$new" | grep -qE "^$HOST-[0-9]+\$"                    # <host>-<pid>, the form kill -0 takes
  kill -0 "${new##*-}"                                        # and the pid it names is genuinely LIVE
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = claimed ]
}

@test "ROUND TRIP: the identity the hook writes is read back as LIVE by cc-backlog's own oracle" {
  # The coupling that a two-halves-each-correct review misses. cc-backlog derives $host itself and
  # only takes the `kill -0` branch when `$by` is exactly "$host-$pid"; any disagreement (hostname -s
  # vs hostname, a domain suffix) falls through to the registry, which does not list a pid-shaped
  # claimer and answers PROVEN NOT-LIVE — a false death, the one verdict that lets reap reopen.
  id="$(dispatched_item roundtrip)"
  fire "$BATS_TEST_TMPDIR/wt-$id"
  # 2h past the stale gate, with the worktree root pointed at an EMPTY dir so `owned_wait` cannot
  # absolve: if the claim resolves LIVE here, it is the re-keyed identity that did it and nothing else.
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/empty-wtroot"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  export CC_BACKLOG_NOW; CC_BACKLOG_NOW=$(( $(date -u +%s) + 7200 ))
  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "KEEP $id \[claimer .* LIVE"
  refute_match "$output" "WOULD-REOPEN $id"
}

@test "RED control: without the hook, the same item at the same age is reopened as a dead worker" {
  # The paired negative control. If this passed too, the test above would be proving nothing about
  # the hook — an always-alive oracle would keep every item regardless.
  id="$(dispatched_item red-control)"
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/empty-wtroot"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  export CC_BACKLOG_NOW; CC_BACKLOG_NOW=$(( $(date -u +%s) + 7200 ))
  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "WOULD-REOPEN $id"
}

@test "the re-key is journalled to the IDL — a silent no-op cannot be told from an inert mechanism" {
  id="$(dispatched_item idl-line)"
  fire "$BATS_TEST_TMPDIR/wt-$id"
  [ -s "$SESSION_REGISTER_IDL" ]
  run cat "$SESSION_REGISTER_IDL"
  printf '%s' "$output" | jq -e --arg i "$id" \
    'select(.hook=="session-register" and .disposition=="reclaimed" and .item==$i)'
}

@test "NOT a dispatch worktree: no ledger write, no IDL line, no fork (this hook runs on every session)" {
  id="$(dispatched_item not-a-worktree)"
  mkdir -p "$BATS_TEST_TMPDIR/some-project"
  run fire "$BATS_TEST_TMPDIR/some-project"
  [ "$status" -eq 0 ]
  [ "$(by_of "$id")" = "$HOST-$DEADPID" ]
  refute_in_file 'reclaim' "$CC_BACKLOG_FILE"
  [ ! -s "$SESSION_REGISTER_IDL" ]
}

@test "a wt-<name> worktree that is not a 12-hex id is ignored (wt-pool-7, gu-*, wt-feature-x)" {
  # The dispatch-worktree gate must key on the ID SHAPE, not the wt- prefix: the pool and ground-up
  # worktrees share the prefix and are not backlog items.
  bash "$CB" add --project /r --title padding --source s >/dev/null
  for d in wt-pool-7 wt-feature-x wt-ABCDEF123456 wt-abc; do
    mkdir -p "$BATS_TEST_TMPDIR/$d"
    run fire "$BATS_TEST_TMPDIR/$d"
    [ "$status" -eq 0 ]
  done
  refute_in_file 'reclaim' "$CC_BACKLOG_FILE"
  [ ! -s "$SESSION_REGISTER_IDL" ]
}

@test "a well-formed wt-<hex> whose id is not in the ledger writes nothing and stays silent" {
  bash "$CB" add --project /r --title padding --source s >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/wt-ffffffffffff"
  run fire "$BATS_TEST_TMPDIR/wt-ffffffffffff"
  [ "$status" -eq 0 ]
  refute_in_file 'reclaim' "$CC_BACKLOG_FILE"
  [ ! -s "$SESSION_REGISTER_IDL" ]
}

@test "an OPEN item is not claimed by the hook — only a claimed item is re-keyed" {
  id="$(bash "$CB" add --project /r --title open-item --source s)"
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = open ]
  refute_in_file 'reclaim' "$CC_BACKLOG_FILE"
  run cat "$SESSION_REGISTER_IDL"
  printf '%s' "$output" | jq -e 'select(.disposition=="noop" and .reason=="not claimed")'
}

@test "a DONE item is never resurrected by a session opening in its old worktree" {
  id="$(bash "$CB" add --project /r --title done-item --source s)"
  bash "$CB" claim "$id" --by "$HOST-$DEADPID" >/dev/null
  bash "$CB" done "$id" --evidence commit:abc123 >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = done ]
  refute_in_file 'reclaim' "$CC_BACKLOG_FILE"
}

@test "a LIVE incumbent claim is not stolen — a second session in the worktree stands down" {
  id="$(bash "$CB" add --project /r --title live-incumbent --source s)"
  bash "$CB" claim "$id" --by "$HOST-$$" >/dev/null           # incumbent: the test's own pid, alive
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
  [ "$(by_of "$id")" = "$HOST-$$" ]
  run cat "$SESSION_REGISTER_IDL"
  printf '%s' "$output" | jq -e 'select(.disposition=="noop" and .reason=="incumbent live")'
}

@test "IDEMPOTENT across restarts: firing twice appends ONE record (resume/compact must not reset the clock)" {
  id="$(dispatched_item idempotent)"
  fire "$BATS_TEST_TMPDIR/wt-$id"
  n=$(grep -c 'reclaim' "$CC_BACKLOG_FILE")
  [ "$n" -eq 1 ]
  fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$(grep -c 'reclaim' "$CC_BACKLOG_FILE")" -eq 1 ]
  run cat "$SESSION_REGISTER_IDL"
  printf '%s' "$output" | jq -e 'select(.disposition=="noop" and .reason=="already ours")'
}

@test "FAIL-OPEN: an unresolvable cc-backlog abstains loudly and still exits 0" {
  id="$(dispatched_item no-bin)"
  SESSION_REGISTER_BACKLOG_BIN="$BATS_TEST_TMPDIR/nope" run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
  [ "$(by_of "$id")" = "$HOST-$DEADPID" ]
  run cat "$SESSION_REGISTER_IDL"
  printf '%s' "$output" | jq -e 'select(.disposition=="abstained" and (.reason|test("not resolvable")))'
}

@test "FAIL-OPEN: no jq on PATH still exits 0 (a registration spine must never cost a session)" {
  id="$(dispatched_item no-jq)"
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/bash\nexit 127\n' > "$BATS_TEST_TMPDIR/stub/jq"; chmod +x "$BATS_TEST_TMPDIR/stub/jq"
  PATH="$BATS_TEST_TMPDIR/stub:/usr/bin:/bin" run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
}

@test "the PRIMARY duty is not starved: the pane registry row is still written alongside the re-key" {
  # The re-key was folded into this hook because a new SessionStart hook needs a settings.json entry
  # (C10 operator-only) and would ship inert. That is only sound if registration still happens — it
  # runs under its own timeout, and this asserts both effects land from one fire.
  id="$(dispatched_item both-effects)"
  export ITERM_SESSION_ID="w0t0p0:AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
  run fire "$BATS_TEST_TMPDIR/wt-$id"
  [ "$status" -eq 0 ]
  [ -s "$CC_REGISTRY_DIR/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.json" ]
  run cat "$CC_REGISTRY_DIR/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.json"
  printf '%s' "$output" | jq -e '.session_id == "deadbeef-0000-0000-0000-000000000000"'
  # and the registry pid is the SAME durable claude pid the claim was keyed on — one derivation, two
  # consumers, so cc-sessions and cc-backlog can never disagree about who the worker is.
  regpid="$(printf '%s' "$output" | jq -r '.pid')"
  [ "$(by_of "$id")" = "$HOST-$regpid" ]
}

@test "PRODUCTION SHAPE: fired DETACHED (no wait seam), the re-key still lands its durable record" {
  # The shipped path: the hook returns immediately and the work completes in a detached child. Every
  # other case here uses the foreground seam for a deterministic observation point, so without this
  # one the suite would be green against a shape that never runs in production.
  #
  # The bound is deliberately generous — this asserts the record LANDS, not how fast. An 8s cap on
  # this same work was measured killing it at loadavg 33, which is why it is detached rather than
  # waited on (memory: actuator-must-see-the-target-population).
  unset SESSION_REGISTER_RECLAIM_WAIT
  id="$(dispatched_item detached)"
  fire "$BATS_TEST_TMPDIR/wt-$id"
  landed=0 i=0
  while [ "$i" -lt 120 ]; do
    if [ "$(by_of "$id")" != "$HOST-$DEADPID" ]; then landed=1; break; fi
    sleep 1; i=$((i + 1))
  done
  [ "$landed" -eq 1 ]
  by_of "$id" | grep -qE "^$HOST-[0-9]+\$"
  [ "$(grep -c 'reclaim' "$CC_BACKLOG_FILE")" -eq 1 ]
}

@test "registration is unaffected outside a worktree (no regression to the hook's original duty)" {
  export ITERM_SESSION_ID="w0t0p0:11111111-2222-3333-4444-555555555555"
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run fire "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ]
  run cat "$CC_REGISTRY_DIR/11111111-2222-3333-4444-555555555555.json"
  printf '%s' "$output" | jq -e '.cwd | test("/plain$")'
  printf '%s' "$output" | jq -e '.pid > 1'
}
