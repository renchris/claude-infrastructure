#!/usr/bin/env bats
# why-tier — the `--why <topic>` reference tier (backlog 1031594b6327; DoD
# docs/plans/STOPHOOK_MESSAGE_TIERING.md §3).
#
# WHAT THIS GUARDS. 48 of 58 proposed Stop-hook message shortenings were refused because ~1,100 words
# were routed to a `--why <topic>` flag that three emitters cited and none wrote — "a deletion wearing
# a pointer's clothes". This suite pins the properties that make the tier a real destination:
#
#   P1  the arm RESOLVES on every wired emitter                        (measured pre-fix: prints nothing)
#   P2  the arm NEVER READS STDIN — it is run from a terminal          (measured pre-fix: rc 124, blocked)
#   P3  the arm writes NO state (no IDL row for a Stop that never happened)
#   P4  `+`-joined topics print BOTH bodies, in order  (completion-assert composes arm="handoff+fence")
#   P5  an unknown topic FAILS LOUD (rc 3 + the available list), never a silent rc 0
#   P6  a MISSING library FAILS LOUD (rc 2 + a named cure), never a silent rc 0
#   P7  the listing and the bodies are the SAME SET — a body with no row, or a row with no body, is red
#   P8  session-continue serves the arm even when its sentinel lib is unresolvable (the :108 fail-safe
#       path exits 0 SILENTLY on an unknown argv, so a `--why` dispatched below it would be inert
#       exactly where a misconfigured hook needs it most — §3.4's governing objection)
#   P9  hook mode is untouched
#
# THE MUTANT ARM IS WHY THESE CASES HAVE POWER. Every P1/P2 case would pass on a hook that served
# `--why` from anywhere, so each is paired with a per-site mutant — the same file with its `--why`
# block excised — which must NOT serve the arm. A case green in both arms tests nothing.
# The mutant is built from the file under test, never from origin/main: a trunk-derived control
# inverts into a false red the moment this lands.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/why-tier.sh"
  EMITTERS="completion-assert session-continue waiting-recycle boundary-handoff"
  # HERMETIC — this suite EXECUTES four live Stop hooks, and their default state paths (IDL, latch,
  # sentinel, telemetry) resolve under $HOME / an absolute /tmp. Unfixtured, P3's "writes no state"
  # would be asserted over the OPERATOR's stores and P9's hook-mode runs would append to them.
  # CC_TELEMETRY_DIR is pinned separately because fixturing $HOME does not redirect an ABSOLUTE
  # default (/tmp/cc-telemetry). An ABSENT path is the right fixture here — these sensors fail open.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
}

# Build a mutant of $1 (hook basename) into $BATS_TEST_TMPDIR/mut/, with the `--why` block excised
# and hooks/lib carried alongside so every OTHER resolution still works.
mk_mutant() {
  local name="$1" d="$BATS_TEST_TMPDIR/mut"
  mkdir -p "$d"
  ln -sfn "$REPO/hooks/lib" "$d/lib"
  awk '/^# ── `--why <topic>` REFERENCE TIER/{skip=1} skip && /^fi$/{skip=0; next} skip{next} {print}' \
    "$REPO/hooks/$name.sh" > "$d/$name.sh"
  chmod +x "$d/$name.sh"
  printf '%s' "$d/$name.sh"
}

# ── P1 · P2 — the arm resolves, and it does it without touching stdin ───────────────────────────

@test "P1: every wired emitter resolves --why <topic>" {
  for e in $EMITTERS; do
    run bash "$REPO/hooks/$e.sh" --why hedge </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == HEDGE\ —* ]] || false
  done
}

@test "P1-mutant: the same emitters WITHOUT the block serve nothing (the case has power)" {
  for e in $EMITTERS; do
    m="$(mk_mutant "$e")"
    run bash "$m" --why hedge </dev/null
    [[ "$output" != *"HEDGE —"* ]] || false
  done
}

# A FIFO held open O_RDWR is the never-closing stdin: the reader blocks on read instead of seeing
# EOF, and nothing outlives the test. A `< <(sleep N)` would also work, but the suite then WAITS on
# the sleep after the subject has already exited — the measurement is instant, the suite is not.
open_blocking_stdin() {
  FIFO="$BATS_TEST_TMPDIR/blocking.fifo"
  [ -p "$FIFO" ] || mkfifo "$FIFO"
  exec 9<>"$FIFO"
}

@test "P2: --why never reads stdin (never-closing stdin must not block)" {
  open_blocking_stdin
  for e in $EMITTERS; do
    run timeout 10 bash -c "bash '$REPO/hooks/$e.sh' --why ledger < '$FIFO'"
    [ "$status" -eq 0 ]
    [[ "$output" == LEDGER\ —* ]] || false
  done
  exec 9>&-
}

@test "P2-mutant: without the block, the same invocation BLOCKS on stdin (rc 124)" {
  open_blocking_stdin
  m="$(mk_mutant completion-assert)"
  run timeout 5 bash -c "bash '$m' --why ledger < '$FIFO'"
  exec 9>&-
  [ "$status" -eq 124 ]
}

# ── P3 — no state write ────────────────────────────────────────────────────────────────────────

@test "P3: --why writes no IDL row" {
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state"
  run bash "$REPO/hooks/completion-assert.sh" --why ledger </dev/null
  [ "$status" -eq 0 ]
  run bash "$REPO/hooks/session-continue.sh" --why custody </dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/idl.jsonl" ]
}

# ── P4 — the `+`-joined multi-arm form completion-assert actually composes ──────────────────────

@test "P4: --why handoff+fence prints BOTH bodies, in that order" {
  run bash "$REPO/hooks/completion-assert.sh" --why handoff+fence </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == HANDOFF\ —* ]] || false
  [[ "$output" == *"FENCE —"* ]] || false
  h="$(printf '%s\n' "$output" | grep -n '^HANDOFF —' | head -1 | cut -d: -f1)"
  f="$(printf '%s\n' "$output" | grep -n '^FENCE —' | head -1 | cut -d: -f1)"
  [ "$h" -lt "$f" ]
}

@test "P4: every arm completion-assert can compose is a real topic" {
  # The pointer a block prints is literally `--why $arm`, so an arm with no topic is a dangling
  # pointer by construction. Arms are read from the source, not restated here.
  arms="$(grep -oE 'arm="\$\{arm:\+\$arm\+\}[a-z]+"|arm="[a-z]+"' "$REPO/hooks/completion-assert.sh" \
          | grep -oE '[a-z]+"$' | tr -d '"' | sort -u)"
  [ -n "$arms" ]
  for a in $arms; do
    run bash "$REPO/hooks/completion-assert.sh" --why "$a" </dev/null
    [ "$status" -eq 0 ]
  done
}

# ── P5 · P6 — both failure modes are LOUD ──────────────────────────────────────────────────────

@test "P5: an unknown topic exits 3 and names what IS available" {
  run bash "$REPO/hooks/session-continue.sh" --why definitely-not-a-topic </dev/null
  [ "$status" -eq 3 ]
  [[ "$output" == *"no such topic: definitely-not-a-topic"* ]] || false
  [[ "$output" == *"Available topics:"* ]] || false
  [[ "$output" == *"custody"* ]]
}

@test "P6: a missing library exits 2 with a named cure, never a silent 0" {
  d="$BATS_TEST_TMPDIR/nolib"; mkdir -p "$d/hooks/lib"
  cp "$REPO/hooks/completion-assert.sh" "$d/completion-assert.sh"
  run env HOME="$d" CLAUDE_CONFIG_DIR="$d/nothing" bash "$d/completion-assert.sh" --why ledger </dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"FATAL"* ]] || false
  [[ "$output" == *"install.sh"* ]]
}

# ── P7 — the listing and the bodies are one set ────────────────────────────────────────────────

@test "P7: every listed topic has a body, and every body is listed" {
  # shellcheck disable=SC1090
  . "$LIB"
  listed="$(why_topic_list | cut -f1 | sort)"
  [ -n "$listed" ]
  for t in $listed; do
    run why_topic_body "$t"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
  done
  # …and the reverse: the case arms in the library, read from the source.
  cased="$(grep -oE '^    [a-z-]+\) cat <<' "$LIB" | sed -E 's/^ +([a-z-]+)\).*/\1/' | sort)"
  [ "$listed" = "$cased" ]
}

@test "P7: a topic body is substantive, not a stub" {
  # shellcheck disable=SC1090
  . "$LIB"
  for t in $(why_topic_list | cut -f1); do
    n="$(why_topic_body "$t" | wc -w | tr -d ' ')"
    [ "$n" -ge 40 ]
  done
}

# ── P8 — the arm survives the fail-safe path that exits 0 silently on unknown argv ──────────────

@test "P8: session-continue serves --why with its sentinel lib unresolvable" {
  d="$BATS_TEST_TMPDIR/nosent"; mkdir -p "$d/lib" "$d/home/.claude/hooks/lib"
  cp "$REPO/hooks/session-continue.sh" "$d/session-continue.sh"
  cp "$LIB" "$d/lib/why-tier.sh"          # the tier is reachable; continue-sentinel.sh is NOT
  run env HOME="$d/home" CLAUDE_CONFIG_DIR="$d/home/.claude" \
      bash "$d/session-continue.sh" --why custody </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == CUSTODY\ —* ]]
}

@test "P8-mutant: without the block, that same invocation serves no topic" {
  d="$BATS_TEST_TMPDIR/nosent2"; mkdir -p "$d/lib" "$d/home/.claude/hooks/lib"
  awk '/^# ── `--why <topic>` REFERENCE TIER/{skip=1} skip && /^fi$/{skip=0; next} skip{next} {print}' \
    "$REPO/hooks/session-continue.sh" > "$d/session-continue.sh"
  cp "$LIB" "$d/lib/why-tier.sh"
  run env HOME="$d/home" CLAUDE_CONFIG_DIR="$d/home/.claude" \
      bash "$d/session-continue.sh" --why custody </dev/null
  # The :108 fail-safe allows the stop (rc 0) and emits only its OWN sentinel-lib FATAL — the topic
  # the reader asked for is never served. That is precisely the inertness §3.4 named: "on the
  # fail-safe path at :85 an unknown argv already exits 0 silently, so even a partial implementation
  # would be inert exactly where it matters."
  [ "$status" -eq 0 ]
  [[ "$output" != *"CUSTODY —"* ]] || false
  [[ "$output" == *"cannot source"* ]]
}

# ── P9 — hook mode is untouched ────────────────────────────────────────────────────────────────

@test "P9: bare --why lists the topics and exits 0" {
  run bash "$REPO/hooks/waiting-recycle.sh" --why </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"TOPIC"* ]] || false
  [[ "$output" == *"recycle-rc"* ]] || false
  [[ "$output" == *"--why handoff+fence"* ]]
}

@test "P9: hook mode still exits 0 on empty stdin for every wired emitter" {
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl2.jsonl"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl2.jsonl"
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state2"
  for e in completion-assert session-continue boundary-handoff; do
    run bash -c "echo '{}' | bash '$REPO/hooks/$e.sh'"
    [ "$status" -eq 0 ]
  done
}

@test "P9: the existing CLI verbs still dispatch (--why did not shadow them)" {
  run bash "$REPO/hooks/session-continue.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == inactive* || "$output" == ARMED* ]] || false
  run bash "$REPO/hooks/waiting-recycle.sh" status
  [ "$status" -eq 0 ]
}
