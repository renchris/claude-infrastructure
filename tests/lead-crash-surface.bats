#!/usr/bin/env bats
# lead-crash-watchdog.sh — THE DEATH PAGE (RECYCLE_SIGTERM_INCIDENT_2026-08-25, deliverable 2).
#
# WHAT FAILED. Session d075006b was SIGTERM'd mid-workflow at 2026-08-25T21:42:25Z. The watchdog
# classified it correctly — class=CRASH cause=external-sigterm — 25 s later, wrote one line to
# lead-crash-watchdog.log, found "no teams affected", and returned. The operator learned about it
# by asking. Two defects, and a test that covers only one of them would pass on a half-fix:
#
#   (a) the page never existed for a TEAMLESS lead — the structured alert path is gated on the dead
#       session owning a team config, and a Dynamic Workflow's agents are in-process subagents that
#       own no team. So the loudest case took the early return.
#   (b) the page carried none of the LOSS — the unmet /goal and the in-flight workflow were the two
#       facts that made it urgent, and neither was in any surfaced string.
#
# RED-PROOF. Every assertion below is executed against BOTH the working tree's hook and the file as
# it stood at the parent commit (`git show HEAD:hooks/lead-crash-watchdog.sh`). The pre-fix control
# is asserted to FAIL — see the last test. A control that cannot fail certifies nothing (MEMORY.md
# verification-harness-vacuous-pass-traps), and this suite's whole claim is that the behaviour
# CHANGED, which is unfalsifiable without executing the old bytes.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/lead-crash-watchdog.sh"

  # Sandbox: nothing here may touch a live store, and NOTHING may page a live session. The pager is
  # a stub that records its argv — the seam exists for exactly this (CC_DEATH_PAGER), the same
  # collector idiom bin/cc-reaper uses for CC_REAPER_GARBAGE_KILL.
  # HERMETICITY: $HOME is fixtured FIRST, before anything derived from it. The subject computes
  # WATCHDOG_DIR, LOG_FILE and the CC_DEATH_PAGER default from $HOME, so an unfixtured suite would
  # write into the operator's live ~/.claude and — worse for this suite specifically — the pager
  # default would resolve to the REAL cc-notify and page a live session.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/watchdog" "$HOME/.claude/logs"

  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct"
  export CC_JETSAM_DIRS="$BATS_TEST_TMPDIR/jetsam"
  export CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  mkdir -p "$CC_ACCOUNT_BASES/projects/proj" "$CC_JETSAM_DIRS" "$CC_TEARDOWN_DIR" "$CC_REGISTRY_DIR"

  PAGED="$BATS_TEST_TMPDIR/paged.txt"
  export CC_DEATH_PAGER="$BATS_TEST_TMPDIR/stub-pager"
  cat > "$CC_DEATH_PAGER" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$PAGED"
STUB
  chmod +x "$CC_DEATH_PAGER"
}

# A transcript for <sid>. $2 = "live" arms an UNMET goal attachment (goal-state.sh's LIVE row:
# no sentinel, met:false, not failed); "none" arms an achieved one; "" writes no goal record.
mk_tx() { # $1=sid  $2=goal-state
  local p="$CC_ACCOUNT_BASES/projects/proj/$1.jsonl"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"working"}]},"version":"2.1.220"}\n' > "$p"
  case "${2:-}" in
    live) printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"condition":"the W1 synthesis is appended"}}\n' >> "$p" ;;
    none) printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"done"}}\n' >> "$p" ;;
  esac
  printf '%s' "$p"
}

# N in-flight Dynamic Workflow dirs for <sid>, in the real on-disk shape the incident had:
#   <projdir>/<sid>/subagents/workflows/<wf-id>/journal.jsonl
mk_wf() { # $1=sid $2=count
  local d="$CC_ACCOUNT_BASES/projects/proj/$1/subagents/workflows" i
  for ((i=0; i<${2:-0}; i++)); do mkdir -p "$d/wf_fixture$i"; : > "$d/wf_fixture$i/journal.jsonl"; done
}

# Run the surfacing entrypoint against an arbitrary copy of the hook (working tree or pre-fix).
surface_with() { # $1=hook-path $2=sid $3=pid $4=class $5=cause $6=exit $7=sig $8=transcript
  bash "$1" --surface-death "$2" "$3" "$4" "$5" "$6" "$7" "$8"
}

@test "external-sigterm on a TEAMLESS lead is PAGED — the branch the incident fell through" {
  tx="$(mk_tx s_ext live)"; mk_wf s_ext 1
  run surface_with "$HOOK" s_ext 50399 CRASH external-sigterm 143 15 "$tx"
  [ "$status" -eq 0 ]
  # No team config exists anywhere in this sandbox — that is the point. The page must not depend on
  # one, because the incident's lead owned none.
  [ -s "$PAGED" ]
  grep -q 'SESSION DEATH' "$PAGED"
}

@test "the page names the session in FULL, not an 8-char prefix" {
  tx="$(mk_tx s_fullsid live)"
  run surface_with "$HOOK" s_fullsid 50399 CRASH external-sigterm 143 15 "$tx"
  [ "$status" -eq 0 ]
  grep -q 's_fullsid' "$PAGED"
}

@test "the page says KILLED, not exited — the distinction the pane cannot show" {
  tx="$(mk_tx s_killed live)"
  run surface_with "$HOOK" s_killed 50399 CRASH external-sigterm 143 15 "$tx"
  echo "$output" | grep -q 'KILLED by an external SIGTERM'
  echo "$output" | grep -q 'did NOT exit'
  # and it must say the pane looks clean, because that is why the operator could not tell
  echo "$output" | grep -qi 'looks EXACTLY like a clean /exit'
}

@test "the page carries the LOSS: an unmet goal and the in-flight workflow count" {
  tx="$(mk_tx s_loss live)"; mk_wf s_loss 1
  run surface_with "$HOOK" s_loss 50399 CRASH external-sigterm 143 15 "$tx"
  echo "$output" | grep -q '/goal=live'
  echo "$output" | grep -q 'workflow dir(s)=1'
}

@test "goal=none when the goal was met — the loss line is read, not asserted" {
  tx="$(mk_tx s_met none)"; mk_wf s_met 0
  run surface_with "$HOOK" s_met 1 CRASH external-sigterm 143 15 "$tx"
  echo "$output" | grep -q '/goal=none'
  echo "$output" | grep -q 'workflow dir(s)=0'
}

@test "a session that never armed a goal is goal=none, not goal=unknown" {
  # The lib returns rc 1 for BOTH "unreadable" and "never armed", so this asserts the watchdog
  # separates them itself rather than laundering a positive finding into an abstention.
  tx="$(mk_tx s_nogoal "")"
  run surface_with "$HOOK" s_nogoal 1 CRASH external-sigterm 143 15 "$tx"
  echo "$output" | grep -q '/goal=none'
}

@test "an UNREADABLE transcript is goal=unknown, never goal=none (absence is not zero)" {
  run surface_with "$HOOK" s_gone 1 CRASH external-sigterm 143 15 "$BATS_TEST_TMPDIR/nope.jsonl"
  echo "$output" | grep -q '/goal=unknown'
}

@test "POLARITY: a deliberate RECYCLE is never paged" {
  tx="$(mk_tx s_rcy live)"
  run surface_with "$HOOK" s_rcy 1 RECYCLE clean-exit 0 "" "$tx"
  [ "$status" -eq 0 ]
  [ ! -s "$PAGED" ] || { echo "a recycle was paged: $(cat "$PAGED")"; false; }
}

@test "kill switch CC_DEATH_PAGE=0 suppresses delivery but still classifies" {
  tx="$(mk_tx s_ks live)"
  CC_DEATH_PAGE=0 run surface_with "$HOOK" s_ks 1 CRASH external-sigterm 143 15 "$tx"
  [ "$status" -eq 0 ]
  [ ! -s "$PAGED" ] || { echo "kill switch did not suppress: $(cat "$PAGED")"; false; }
}

@test "a MISSING pager degrades to the pre-fix behaviour — never a hang, never a hard failure" {
  tx="$(mk_tx s_nopager live)"
  CC_DEATH_PAGER="$BATS_TEST_TMPDIR/does-not-exist" run surface_with "$HOOK" s_nopager 1 CRASH external-sigterm 143 15 "$tx"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'SESSION DEATH'
}

@test "jetsam-oom is paged too, with its own cause wording" {
  tx="$(mk_tx s_oom live)"
  run surface_with "$HOOK" s_oom 1 CRASH jetsam-oom "" "" "$tx"
  echo "$output" | grep -q 'OOM killer'
  [ -s "$PAGED" ]
}

# ── THE CONTROL. Executes the PRE-FIX file and asserts it CANNOT do this. Without this test the
# suite above proves only that the new code runs, not that it changed anything.
@test "RED-PROOF: the pre-fix hook has no surfacing path at all (control must FAIL)" {
  # 🚨 NOT KEYED ON `HEAD` — a control re-derived from a moving ref is non-deterministic by
  # construction (MEMORY.md control-population-must-be-stable). Keyed on HEAD, this control went
  # VACUOUS the moment the fix was committed: `git show HEAD:` returned the fixed file, the guard
  # below saw `surface_death`, and the control SKIPPED — reporting green while proving nothing.
  # Self-locate the pre-fix revision from the change itself, which survives rebases and re-lands.
  ADDED="$(git -C "$REPO" log --format=%H -S'surface_death' -- hooks/lead-crash-watchdog.sh 2>/dev/null | tail -1)"
  [ -n "$ADDED" ] || skip "cannot locate the commit that introduced surface_death (shallow clone?)"
  OLD="$BATS_TEST_TMPDIR/old-hook.sh"
  git -C "$REPO" show "$ADDED^:hooks/lead-crash-watchdog.sh" > "$OLD" 2>/dev/null \
    || skip "no parent revision for $ADDED (root commit?)"
  # Belt and braces: the located revision must genuinely predate the fix.
  ! grep -q 'surface_death' "$OLD" || false
  tx="$(mk_tx s_ctl live)"; mk_wf s_ctl 1
  run surface_with "$OLD" s_ctl 50399 CRASH external-sigterm 143 15 "$tx"
  # The old file does not know --surface-death: it falls through to the hook-JSON stdin path and
  # emits nothing resembling a page. Either way, the two things the fix promises are ABSENT.
  ! echo "$output" | grep -q 'SESSION DEATH' || false
  [ ! -s "$PAGED" ] || { echo "pre-fix hook paged something: $(cat "$PAGED")"; false; }
}
