#!/usr/bin/env bats
# handoff-fire.sh self-close — THE THIRD SESSION CATEGORY (docs/plans/SESSION_LIFECYCLE_V2.md §5.1).
#
# THE DEFECT (cc-backlog 95281da714f0, two confirmed occurrences 2026-07-26 + 2026-07-29): self-close
# modelled exactly TWO kinds of session — a FIRED PEER (has a stamp, may retire) and an ORIGIN session
# (no stamp, never retires). An Agent-Team ASSIGNEE whose LEAD IS DEAD is NEITHER: it has an
# originator, and that originator no longer exists. So every sanctioned route refused it — lead
# shutdown_request (channel died with the process), cc-teardown (0 registry rows), it2-by-cwd (0 panes
# match), self-close --terminal ("no fired-peer stamp") — and closing 5, then 7, then 11 panes became
# an operator hand-step. THE GAP WAS A MISSING CATEGORY, NOT A MISSING FEATURE.
#
# WHY NOT --allow-origin-close: it already exists, documented "deliberate, loud, almost never right".
# Forcing a gate whose entire purpose is to stop closes-with-no-continuation, for tidiness, is the
# wrong trade — the coordinator refused it and was right. So this suite pins that the new path is a
# NAMED CATEGORY WITH PRECONDITIONS, not a wider override: every test below is a REFUSAL except the
# one that satisfies all four.
#
# THE PRECONDITION THAT MATTERS MOST IS R1 — POSITIVE DEATH EVIDENCE. Treating a 6-minute upstream-529
# silence as terminal is what put two leads in one worktree and came within a read-before-write guard
# of clobbering 581 landed lines. So originator_liveness is TRICHOTOMOUS and UNKNOWN refuses. There is
# deliberately NO path from "no evidence" to "dead".
#
# Technique mirrors tests/handoff-selfclose.bats: PATH shims for osascript/ps/git, --dry-run so the
# gate runs but nothing is armed or closed, sed-extracted units for the oracles.

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
  # The env pins the DIVERT decision; identity (kitty_identity) reads CC_TERM first, and self-close
  # resolves that from the ancestry walk at entry — so run from kitty this suite would take the kitty
  # branch and never consult its osascript stub. 5 tests here go red under `CC_TERM=kitty`, on trunk
  # too. Same "PIN THE TERMINAL" intent as the two lines above, in the place that governs identity.
  export CC_TERM=iterm2
  hf_bounded() { "$@"; }          # the timeout(1) wrapper is out of scope for extracted units
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  # HERMETICITY: the units resolve defaults under $HOME (~/.claude/cc-registry, ~/.claude/cc-fired).
  # An unfixtured $HOME would read and MUTATE the operator's live state. Never the allowlist.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  PS_ARGV_DIR="$BATS_TEST_TMPDIR/argv"; mkdir -p "$PS_ARGV_DIR"
  PS_COMM_DIR="$BATS_TEST_TMPDIR/comm"; mkdir -p "$PS_COMM_DIR"
  OSA_GONE_DIR="$BATS_TEST_TMPDIR/gone"; mkdir -p "$OSA_GONE_DIR"
  export PS_ARGV_DIR PS_COMM_DIR OSA_GONE_DIR

  # as_tty's query: `osascript - <uuid>` → "TTY-<uuid>", or empty when a gone-marker exists.
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

  # TWO distinct ps forms are used and the shim must not conflate them:
  #   ps -t <tty> -o command=   → full argv    (agent_id_on_tty, the assignee oracle)
  #   ps -o comm= -p <pid>      → command NAME (originator_liveness's recycled-pid discriminator)
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
tty="" pid="" want=""
while [ $# -gt 0 ]; do
  case "$1" in
    -t) tty="${2:-}"; shift 2 ;;
    -p) pid="${2:-}"; shift 2 ;;
    -o) case "${2:-}" in command=) want=argv ;; comm=) want=comm ;; esac; shift 2 ;;
    *)  shift ;;
  esac
done
if [ "$want" = argv ] && [ -n "$tty" ]; then
  [ -f "$PS_ARGV_DIR/$tty" ] && cat "$PS_ARGV_DIR/$tty"
  exit 0
fi
if [ "$want" = comm ] && [ -n "$pid" ]; then
  [ -f "$PS_COMM_DIR/$pid" ] && cat "$PS_COMM_DIR/$pid"
  exit 0
fi
exit 0
SH

  # only `git rev-parse --is-inside-work-tree` is hit on the gate path — report "not a work tree" so
  # the dirty-tree guard is skipped (hermetic, independent of the test's CWD).
  cat > "$SHIM/git" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = rev-parse ] && exit 1
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/ps" "$SHIM/git"
  export PATH="$SHIM:$PATH"

  REGDIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$REGDIR"
  export CC_REGISTRY_DIR="$REGDIR"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"

  ASSIGNEE="AAAA1111-2222-3333-4444-555566667777"
  LEAD_SID="lead-sess-0001"

  # All three units are MULTI-LINE, so every one needs the /^f() {/,/^}/ range form. (A `grep` of the
  # opening line alone yields an unterminated function and a `syntax error: unexpected end of file`
  # that fails all 15 tests identically — which reads as 15 bugs and is one extraction fault.)
  {
    sed -n '/^agent_id_on_tty() {/,/^}/p'      "$HF"
    sed -n '/^session_of_agent_id() {/,/^}/p'  "$HF"
    sed -n '/^originator_liveness() {/,/^}/p'  "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  # Fail LOUD if extraction produced something unsourceable, instead of letting every test blame its
  # own subject.
  bash -n "$BATS_TEST_TMPDIR/units.sh" || {
    echo "unit extraction from $HF is not valid bash" >&2; return 1
  }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"
}

# A pid that is provably gone: start a child, reap it, return its pid. Deterministic — unlike a
# guessed-high pid, which a busy box can reuse.
dead_pid() {
  local p
  ( exec true ) & p=$!
  wait "$p" 2>/dev/null || true
  printf '%s' "$p"
}

# make the assignee's tty report an assignee argv
argv_assignee() { # $1=tty $2=agent-id
  printf '%s\n' "/usr/local/bin/node /opt/claude/cli.js --agent-id $2 --model claude-opus-5" \
    > "$PS_ARGV_DIR/$1"
}

reg_row() { # $1=pane $2=sid $3=pid
  printf '{"paneUUID":"%s","session_id":"%s","pid":%s}\n' "$1" "$2" "$3" > "$REGDIR/$1.json"
}

# ── 1. the assignee oracle — POSITION-matched, never a substring ────────────────────────────────

@test "agent_id_on_tty reads the agent-id from argv at the COMMAND POSITION" {
  argv_assignee "TTY-X" "gu5-decide@session-$LEAD_SID"
  run agent_id_on_tty "TTY-X"
  [ "$status" -eq 0 ]
  [ "$output" = "gu5-decide@session-$LEAD_SID" ]
}

@test "pgrep -f TRAP: a LEAD whose brief QUOTES --agent-id in prose is not thereby an assignee" {
  # `ps -o command=` flattens argv into one line, so it cannot tell a separate argv WORD from a word
  # INSIDE a single quoted element — and a brief is one such element. This is the REAL text every
  # brief in this campaign carries (including the one that fired this very session), so the fixture
  # is verbatim rather than invented. Before strict shape validation this parsed, and would have
  # classified an ordinary lead as an assignee of a nonexistent originator.
  printf '%s\n' \
    "/usr/local/bin/node /opt/claude/cli.js --model claude-opus-5 A resume never restores the TEAM CHANNEL — assignees are keyed --agent-id <name>@session-<sid> to the PROCESS that died" \
    > "$PS_ARGV_DIR/TTY-LEAD"
  run session_of_agent_id "$(agent_id_on_tty TTY-LEAD)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  # POSITIVE CONTROL: the real assignee argv on the same code path DOES parse — so the rejection
  # above is the validator discriminating, not a function that always returns empty.
  argv_assignee "TTY-REAL" "gu5-decide@session-$LEAD_SID"
  run session_of_agent_id "$(agent_id_on_tty TTY-REAL)"
  [ "$output" = "$LEAD_SID" ]
}

@test "shape validator rejects prose-shaped ids: angle brackets, short tails, spaces" {
  run session_of_agent_id '<name>@session-<sid>'
  [ -z "$output" ]
  run session_of_agent_id 'name@session-x'          # 1-char tail — prose, not a session id
  [ -z "$output" ]
  run session_of_agent_id 'name@session-'           # empty tail
  [ -z "$output" ]
  run session_of_agent_id 'not-an-agent-id'
  [ -z "$output" ]
  # POSITIVE CONTROL: a well-formed id still parses.
  run session_of_agent_id 'gu2-telemetry@session-a8e72ae5'
  [ "$output" = "a8e72ae5" ]
}

@test "DEFENCE IN DEPTH: even a prose id that SURVIVES shape validation cannot authorize a close" {
  # The validator is not claimed to be perfect — prose could contain a plausible-looking id. R1 is the
  # second wall: a fictional originator has no registry row, so the verdict is UNKNOWN and the close
  # is refused. Two independent walls, which is why neither has to be flawless.
  printf '%s\n' \
    "/usr/local/bin/node /opt/claude/cli.js do not send to --agent-id ghost-worker@session-deadbeef12345678 any more" \
    > "$PS_ARGV_DIR/TTY-$ASSIGNEE"
  run session_of_agent_id "$(agent_id_on_tty "TTY-$ASSIGNEE")"
  [ "$output" = "deadbeef12345678" ]                # shape-valid: wall 1 passes
  run bash "$HF" self-close --orphaned-assignee --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 2 ]                               # wall 2 holds
  [[ "$output" == *"cannot PROVE"* ]] || false
}

@test "agent_id_on_tty on a tty with no processes yields empty, and never fails" {
  run agent_id_on_tty "TTY-EMPTY"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── 2. R1 — the trichotomous death oracle ───────────────────────────────────────────────────────

@test "originator_liveness: registry row present + pid GONE = provably DEAD (0)" {
  DP="$(dead_pid)"
  run kill -0 "$DP"                      # positive control: the pid really is gone
  [ "$status" -ne 0 ]
  reg_row "LEADPANE" "$LEAD_SID" "$DP"
  run originator_liveness "$LEAD_SID" "$REGDIR"
  [ "$status" -eq 0 ]
}

@test "originator_liveness: row present + pid alive + CC process = ALIVE (1), so the close refuses" {
  printf 'node\n' > "$PS_COMM_DIR/$$"
  reg_row "LEADPANE" "$LEAD_SID" "$$"
  run originator_liveness "$LEAD_SID" "$REGDIR"
  [ "$status" -eq 1 ]
}

@test "RECYCLED PID: row present + pid alive but NOT a CC process = UNKNOWN (2), never DEAD" {
  # pids are recycled. Calling this dead would close a pane whose lead is working; calling it alive
  # is the safe error (a refusal). Neither is a guess — it is explicitly the third state.
  printf 'Finder\n' > "$PS_COMM_DIR/$$"
  reg_row "LEADPANE" "$LEAD_SID" "$$"
  run originator_liveness "$LEAD_SID" "$REGDIR"
  [ "$status" -eq 2 ]
}

@test "NO registry row at all = UNKNOWN (2) — a row that never existed is not evidence of death" {
  run originator_liveness "$LEAD_SID" "$REGDIR"
  [ "$status" -eq 2 ]
  # POSITIVE CONTROL: the same oracle DOES reach a DEAD verdict once real evidence exists, so the 2
  # above is a considered verdict and not a function that can only ever return 2.
  DP="$(dead_pid)"
  reg_row "LEADPANE" "$LEAD_SID" "$DP"
  run originator_liveness "$LEAD_SID" "$REGDIR"
  [ "$status" -eq 0 ]
}

@test "row present but carrying NO pid = UNKNOWN (2) — cannot judge without the field it needs" {
  printf '{"paneUUID":"LEADPANE","session_id":"%s"}\n' "$LEAD_SID" > "$REGDIR/LEADPANE.json"
  run originator_liveness "$LEAD_SID" "$REGDIR"
  [ "$status" -eq 2 ]
}

@test "R5 fail-soft: an ABSENT registry dir degrades to UNKNOWN, never to a guess" {
  run originator_liveness "$LEAD_SID" "$BATS_TEST_TMPDIR/no-such-dir"
  [ "$status" -eq 2 ]
}

# ── 3. the gate — one ALLOW, and a refusal for every unmet precondition ─────────────────────────

@test "ALLOWED: assignee whose lead is provably dead closes, and its close is LEGIBLE" {
  DP="$(dead_pid)"
  argv_assignee "TTY-$ASSIGNEE" "gu5-decide@session-$LEAD_SID"
  reg_row "LEADPANE" "$LEAD_SID" "$DP"
  run bash "$HF" self-close --orphaned-assignee --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphaned-assignee close AUTHORIZED"* ]] || false
  [[ "$output" == *"gu5-decide@session-$LEAD_SID"* ]] || false
  # R10 — an assignee's findings live ONLY in its transcript, so a close that does not say where the
  # work went is exactly the illegible exit this row exists to prevent.
  [[ "$output" == *"its work survives the close"* ]] || false
  [[ "$output" == *"transcript recoverable by agentName 'gu5-decide'"* ]] || false
}

@test "REFUSED: --orphaned-assignee on a pane that is NOT an assignee (the flag cannot confer a category)" {
  run bash "$HF" self-close --orphaned-assignee --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"NOT an Agent-Team assignee"* ]] || false
}

@test "REFUSED: assignee whose lead is ALIVE — finish and be harvested, do not self-close" {
  printf 'claude\n' > "$PS_COMM_DIR/$$"
  argv_assignee "TTY-$ASSIGNEE" "gu5-decide@session-$LEAD_SID"
  reg_row "LEADPANE" "$LEAD_SID" "$$"
  run bash "$HF" self-close --orphaned-assignee --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"is ALIVE"* ]] || false
}

@test "REFUSED on UNKNOWN: R1 — a stall is not a death, so no-evidence never authorizes a close" {
  argv_assignee "TTY-$ASSIGNEE" "gu5-decide@session-$LEAD_SID"      # no registry row for the lead
  run bash "$HF" self-close --orphaned-assignee --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot PROVE"* ]] || false
  [[ "$output" == *"UNKNOWN"* ]] || false
}

@test "the ORIGIN GATE is untouched: a bare self-close on the same pane is still refused" {
  # The new path must not widen the old gate. Same pane, same absent stamp, no --orphaned-assignee.
  DP="$(dead_pid)"
  argv_assignee "TTY-$ASSIGNEE" "gu5-decide@session-$LEAD_SID"
  reg_row "LEADPANE" "$LEAD_SID" "$DP"
  run bash "$HF" self-close --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"ORIGIN session"* ]] || false
}

@test "A11 kill switch: CC_ORPHAN_ASSIGNEE_CLOSE=0 falls back to the origin refusal" {
  DP="$(dead_pid)"
  argv_assignee "TTY-$ASSIGNEE" "gu5-decide@session-$LEAD_SID"
  reg_row "LEADPANE" "$LEAD_SID" "$DP"
  run env CC_ORPHAN_ASSIGNEE_CLOSE=0 bash "$HF" self-close --orphaned-assignee --terminal \
    --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"ORIGIN session"* ]] || false
  # POSITIVE CONTROL: with the switch ON, the identical invocation is AUTHORIZED — so the refusal
  # above is the switch acting, not a broken fixture.
  run bash "$HF" self-close --orphaned-assignee --terminal --session-id "$ASSIGNEE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUTHORIZED"* ]] || false
}
