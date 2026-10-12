#!/usr/bin/env bats
# AGENT-IDENTITY PER-HOP WALK — the ancestry is read one `ps -p` at a time, never the whole table
# (2026-10-11, docs/research/load-hook-timeouts-2026-10-11 item 2).
#
# THE DEFECT. hooks/lib/agent-identity.sh read `ps -axo pid=,ppid=,command=` — every process on the
# box — to visit at most maxhop of them. A full-table ps comes in WAVES where it blocks
# uninterruptibly for minutes, while single-pid `ps -p` stays fast through the same wave, and this
# lib sits under 15+ hooks including the Stop hooks with the most cancels. hooks/teammate-auto-
# shutdown.sh's survivor check carried its own copy of the same full-table read.
#
# WHAT IS ASSERTED. The `ps` stub below HANGS (sleep 30) on any full-table form and answers `-p <pid>`
# from a fixture, so a call that still reads the table cannot pass the elapsed bound:
#   W1  the walk returns fast with the right verdict, for an assignee AND a lead (the control)
#   W2  a brief that merely MENTIONS the three flags is still a non-match
#   W3  the walk stops at pid 1 and at maxhop, fetching exactly the hops the awk visits
#   W4  the CC_WF_PSTABLE_FILE seam is untouched, and per-hop rows give the seam's verdict (parity)
#   W5  a `claude -p` nested under a teammate still reads as that teammate (no early stop — pinned)
#   W6  teammate-auto-shutdown's survivor check finds the member by name, ancestors included

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/agent-identity.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  # No team config anywhere ⇒ agent_team_member_confirms reads UNKNOWN (2), so the argv walk alone
  # decides — which is the half this file is about.
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/no-teams"
  unset CC_WF_PSTABLE_FILE CC_WF_MAX_HOPS
  export CC_WF_START_PID=1000
  CCBIN="/x/claude-code/bin/claude.exe"

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export PS_FIXTURE="$BATS_TEST_TMPDIR/fixture" PS_LOG="$BATS_TEST_TMPDIR/ps.log"
  export PGREP_LOG="$BATS_TEST_TMPDIR/pgrep.log" PGREP_PIDS="$BATS_TEST_TMPDIR/pgrep-pids"
  export PGREP_ANCESTORS="$BATS_TEST_TMPDIR/pgrep-ancestors"
  : > "$PS_FIXTURE"; : > "$PGREP_PIDS"; : > "$PGREP_ANCESTORS"
  # The elapsed bound sits well under the stub's 30 s hang and well over a 4-hop walk at the load
  # this suite runs at (measured 2026-10-11: ~1-1.5 s per stubbed hop at a load of ~500). Each
  # timed test ALSO asserts no full-table call was made, so the bound is the backstop, not the proof.
  BOUND_S=20
  # ps: any full-table form (-A, -e, -a…, -x…) sleeps 30 s — the measured wave, bounded so a
  # regression costs 30 s rather than hanging the suite. `-p <pid>` answers from the fixture and
  # exits 1 on a miss, like the real ps.
  cat > "$STUB/ps" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$PS_LOG"
pid=""; prev=""
for a in "$@"; do
  case "$a" in -A|-e|-a*|-x*) sleep 30; exit 0 ;; esac
  [ "$prev" = "-p" ] && pid="$a"
  prev="$a"
done
[ -n "$pid" ] || exit 1
# Builtins only: under the load this suite is run at, every extra fork per hop is ~0.3 s.
while IFS= read -r line; do
  f1="${line#"${line%%[! ]*}"}"; f1="${f1%% *}"
  [ "$f1" = "$pid" ] && { printf '%s\n' "$line"; exit 0; }
done < "$PS_FIXTURE"
exit 1
EOF
  # pgrep: macOS semantics for the one shape the survivor check uses — ancestors are DROPPED unless
  # -a is passed (pgrep(1)), which is exactly the difference from the old full table.
  cat > "$STUB/pgrep" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$PGREP_LOG"
cat "$PGREP_PIDS"
case " $* " in *" -a "*) cat "$PGREP_ANCESTORS" ;; esac
EOF
  chmod +x "$STUB/ps" "$STUB/pgrep"
  export PATH="$STUB:$PATH"
}

# Rows are "pid ppid command…" — the shape `ps -o pid=,ppid=,command=` prints (pid right-aligned).
fixture() { local r; : > "$PS_FIXTURE"; for r in "$@"; do printf '%s\n' "$r" >> "$PS_FIXTURE"; done; }
assignee_rows() { fixture \
  " 1000  1001 bash /x/hook.sh" \
  " 1001  1002 /bin/zsh -c source /snap.zsh" \
  " 1002  1003 $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1 --parent-session-id p1 --permission-mode auto" \
  " 1003     1 -zsh"; }
lead_rows() { fixture \
  " 1000  1001 bash /x/hook.sh" \
  " 1001  1002 /bin/zsh -c source /snap.zsh" \
  " 1002  1003 $CCBIN --permission-mode auto --model claude-opus-5 --effort high" \
  " 1003     1 -zsh"; }
prose_lead_rows() { fixture \
  " 1000  1001 bash /x/hook.sh" \
  " 1001  1002 /bin/zsh -c source /snap.zsh" \
  " 1002  1003 $CCBIN --model claude-opus-5 Investigate: a teammate argv carries --agent-id x@session-y --agent-name x --team-name y and * globs" \
  " 1003     1 -zsh"; }
# A `claude -p` run from a teammate's Bash tool, whose own hook is the walk's start.
nested_print_rows() { fixture \
  " 1000  1001 bash /x/hook.sh" \
  " 1001  1002 $CCBIN -p summarise the diff" \
  " 1002  1003 /bin/zsh -c source /snap.zsh" \
  " 1003  1004 $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1 --parent-session-id p1" \
  " 1004     1 -zsh"; }
# A straight chain 1000→1001→…→1011→1 whose assignee sits at hop $1 (pid 1000+$1).
deep_rows() {
  local at="$1" i rows=()
  for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
    if [ "$i" = "$at" ]; then
      rows+=( " $((1000 + i))  $((1001 + i)) $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1" )
    elif [ "$i" = 11 ]; then
      rows+=( " $((1000 + i))     1 -zsh" )
    else
      rows+=( " $((1000 + i))  $((1001 + i)) /bin/zsh -c step$i" )
    fi
  done
  fixture "${rows[@]}"
}
ps_p_calls() { grep -c -- '-p ' "$PS_LOG" 2>/dev/null || true; }
no_full_table() { ! grep -qE -- '(^| )(-A|-e|-a[^ ]*|-x[^ ]*)( |$)' "$PS_LOG" 2>/dev/null; }

# ── W1 ───────────────────────────────────────────────────────────────────────────────────────────
@test "W1: a hanging full-table ps does not stall the walk — assignee id inside the bound" {
  assignee_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  local t0=$SECONDS
  run agent_is_assignee
  local el=$((SECONDS - t0))
  [ "$status" -eq 0 ]
  [ "$output" = "tm@session-t1" ]
  [ "$el" -lt "$BOUND_S" ] || { echo "walk took ${el}s — it read the full table"; false; }
  no_full_table
}

@test "W1 control: a lead reads as not-assignee, just as fast" {
  lead_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  local t0=$SECONDS
  run agent_is_assignee
  local el=$((SECONDS - t0))
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$el" -lt "$BOUND_S" ]
  no_full_table
  # And agent_has_operator_entrypoint keeps the lead's surface.
  run agent_has_operator_entrypoint
  [ "$status" -eq 0 ]
}

# ── W2 ───────────────────────────────────────────────────────────────────────────────────────────
@test "W2: a brief that merely MENTIONS the three flags is still a non-match" {
  prose_lead_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  local t0=$SECONDS
  run agent_assignee_argv
  local el=$((SECONDS - t0))
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ "$el" -lt "$BOUND_S" ] || { echo "walk took ${el}s; ps calls:"; cat "$PS_LOG"; false; }
  no_full_table
}

# ── W3 ───────────────────────────────────────────────────────────────────────────────────────────
@test "W3: the walk stops at pid 1 and never asks ps about it" {
  lead_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  run agent_assignee_argv
  [ "$status" -eq 1 ]
  [ "$(ps_p_calls)" -eq 4 ]                      # 1000, 1001, 1002, 1003 — then ppid 1 ends it
  run grep -E -- '-p 1$' "$PS_LOG"
  [ "$status" -ne 0 ]
}

@test "W3: the walk stops at maxhop — an assignee one hop past the bound is not reached" {
  deep_rows 8                                    # hop 8 = the 9th process; default maxhop is 8
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  run agent_assignee_argv
  [ "$status" -eq 1 ]
  [ "$(ps_p_calls)" -eq 8 ]
  # The same chain with the bound raised reaches it — the stop above was the bound, not a miss.
  : > "$PS_LOG"
  CC_WF_MAX_HOPS=9 run agent_assignee_argv
  [ "$status" -eq 0 ]
  [ "$output" = "tm@session-t1" ]
  [ "$(ps_p_calls)" -eq 9 ]
}

@test "W3: a caller's strict-mode IFS does not cut the walk short" {
  # Unpinned, `read` put the whole row in the pid field under IFS=$'\n\t' and the walk stopped at
  # hop 1 — not-an-assignee for a real assignee, while the seam (awk's own FS) still said yes.
  assignee_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  IFS=$'\n\t' run agent_is_assignee
  [ "$status" -eq 0 ]
  [ "$output" = "tm@session-t1" ]
}

@test "W3: a vanished ancestor ends the walk cleanly (ps -p misses)" {
  fixture " 1000  1001 bash /x/hook.sh"          # 1001 is gone
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  run agent_assignee_argv
  [ "$status" -eq 1 ]
  [ "$(ps_p_calls)" -eq 2 ]
}

# ── W4 ───────────────────────────────────────────────────────────────────────────────────────────
@test "W4: the CC_WF_PSTABLE_FILE seam is unchanged and never calls ps" {
  assignee_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  CC_WF_PSTABLE_FILE="$PS_FIXTURE" run agent_assignee_argv
  [ "$status" -eq 0 ]
  [ "$output" = "tm@session-t1" ]
  [ ! -s "$PS_LOG" ]
}

@test "W4 parity: per-hop rows give the seam's verdict on every fixture" {
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  local f seam walk
  for f in assignee_rows lead_rows prose_lead_rows nested_print_rows "deep_rows 3" "deep_rows 8"; do
    $f
    seam="$(CC_WF_PSTABLE_FILE="$PS_FIXTURE" agent_assignee_argv; echo "rc=$?")"
    walk="$(agent_assignee_argv; echo "rc=$?")"
    [ "$seam" = "$walk" ] || { echo "$f: seam=[$seam] walk=[$walk]"; false; }
  done
}

# ── W5 ───────────────────────────────────────────────────────────────────────────────────────────
@test "W5: a claude -p nested under a teammate still reads as that teammate (no early stop)" {
  # Pinned, not judged: the walk stays maxhop deep rather than stopping at the nearest claude
  # ancestor, so the verdict matches the full-table walk this replaced. Changing that is a policy
  # call for agent_is_assignee's consumers, and this test is where it would show.
  nested_print_rows
  # shellcheck disable=SC1090  # $LIB is resolved from the repo root in setup
  source "$LIB"
  run agent_is_assignee
  [ "$status" -eq 0 ]
  [ "$output" = "tm@session-t1" ]
  no_full_table
}

# ── W6 ───────────────────────────────────────────────────────────────────────────────────────────
# The function is taken from the hook as written (the hook body has side effects on source).
load_survivor_fn() {
  sed -n '/^_surviving_member_pid() {/,/^}/p' "$REPO/hooks/teammate-auto-shutdown.sh" > "$BATS_TEST_TMPDIR/fn.sh"
  [ -s "$BATS_TEST_TMPDIR/fn.sh" ]
  # shellcheck disable=SC1091  # generated above at test time; the ship gate runs shellcheck without -x
  source "$BATS_TEST_TMPDIR/fn.sh"
}

@test "W6: survivor check finds the member's claude.exe by name, without the full table" {
  fixture \
    " 2000     1 $CCBIN --model claude-opus-5 Investigate --agent-id tm@session-t1 --agent-name tm --team-name t1" \
    " 2001     1 $CCBIN --agent-id other@session-t1 --agent-name other --team-name session-t1" \
    " 2002     1 $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1 --parent-session-id p1"
  printf '%s\n' 2000 2001 2002 > "$PGREP_PIDS"
  load_survivor_fn
  local t0=$SECONDS
  run _surviving_member_pid tm
  [ "$status" -eq 0 ]
  [ "$output" = "2002" ]
  [ $((SECONDS - t0)) -lt "$BOUND_S" ]
  no_full_table
  # The candidate filter is the scan's whole narrowing, so its exact form is pinned: both argv[0]
  # spellings, ancestors kept. The stub ignores the pattern, so only this line can catch a drift.
  grep -qxF -- "-a -x claude|claude.exe" "$PGREP_LOG"
}

@test "W6: a brief that merely MENTIONS the member is not a survivor" {
  fixture " 2000     1 $CCBIN --model claude-opus-5 a brief: --agent-id tm@session-t1 --agent-name tm --team-name t1"
  printf '%s\n' 2000 > "$PGREP_PIDS"
  load_survivor_fn
  run _surviving_member_pid tm
  [ -z "$output" ]
  # Positive control: the brief row WAS fetched and judged — an empty answer from a broken pgrep or
  # a hung full-table read would also be empty, and would prove nothing.
  [ -s "$PGREP_LOG" ]
  grep -qE -- '-p 2000$' "$PS_LOG"
  no_full_table
}

@test "W6: a survivor that is the hook's own ANCESTOR is still seen (pgrep drops those by default)" {
  fixture " 2002     1 $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1"
  printf '%s\n' 2002 > "$PGREP_ANCESTORS"
  load_survivor_fn
  run _surviving_member_pid tm
  [ "$output" = "2002" ]
}

@test "W6: the seam still wins — CC_WF_PSTABLE_FILE set ⇒ no pgrep, no ps" {
  fixture " 2002     1 $CCBIN --agent-id tm@session-t1 --agent-name tm --team-name session-t1"
  load_survivor_fn
  CC_WF_PSTABLE_FILE="$PS_FIXTURE" run _surviving_member_pid tm
  [ "$output" = "2002" ]
  [ ! -s "$PS_LOG" ]
  [ ! -s "$PGREP_LOG" ]
}
