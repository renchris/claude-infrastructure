#!/usr/bin/env bats
# cc-teardown — ADOPTION of an UNREGISTERED Agent-Team assignee pane (backlog 95281da714f0 leg b).
#
# WHY THIS SUITE EXISTS. resolve() knows exactly one oracle: the session registry. An Agent-Team
# assignee is never in it — measured 134 of 134 member panes across all 50 team dirs on this
# machine had NO registry row, because an assignee is not a launched session but a
# `claude.exe --agent-id <name>@session-<lead>` child that nothing registers. So the lead-crash
# watchdog's close leg could only ever get REFUSE unknown-target, which it counted as a *trusted*
# policy refusal: 100% abstain BY CONSTRUCTION, and its own suite passed because the spy returned 0
# (memory: feature-durability-mechanism-not-memory + fixture-shape-parity-with-real-producer).
#
# The rules pinned here, each of which was a real trap:
#   TRI-STATE      an unreadable/blind it2 enumeration is INDETERMINATE, never "pane absent". An
#                  ad-hoc probe written while diagnosing this bug called all six live panes ABSENT
#                  because its it2 call timed out under load. Absence of evidence ≠ evidence of
#                  absence, and here the wrong read means killing a live session.
#   ARGV NOT TEXT  identity must come from argv (argv[0] basename == claude.exe AND a real
#                  --agent-id token), never a substring: a sibling on ttys029 carried the literal
#                  string "--agent-id <name>@session-8891c11f" inside a prose TASK argument
#                  (memory: detector-matching-its-own-skill-description).
#   OPT-IN ONLY    without --assignee-of the unknown-target refusal is byte-for-byte unchanged, so
#                  no existing caller (cc-reaper) can reach the new path.
#   RIGHT LEAD     an assignee of a DIFFERENT lead is never adopted.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Seam so the RED proof is reproducible forever, not a one-off: point CCT_UNDER_TEST at the
  # pre-fix cc-teardown (git show origin/main:bin/cc-teardown) and tests 2-8 must FAIL. A suite that
  # was never run against the broken tree cannot show it detects the bug.
  TD="${CCT_UNDER_TEST:-$REPO/bin/cc-teardown}"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin"
  export HOME="$D/home"; mkdir -p "$HOME/.claude"

  LEAD=8891c11f
  PANE=8A43425B-C6AA-493D-A14E-678AF747C6A8

  # Registry MISS — the real, measured condition for every assignee pane.
  cat > "$D/bin/cc-sessions" <<'EOF'
#!/bin/bash
echo '[]'
EOF

  # it2: `session list --json` serves $IT2_JSON verbatim, so each test can pose a readable list, a
  # blind [] , or unparseable output. `session close` is a no-op success (we never reach it here).
  cat > "$D/bin/it2" <<'EOF'
#!/bin/bash
if [ "$1" = session ] && [ "$2" = list ]; then printf '%s' "${IT2_JSON:-[]}"; exit 0; fi
exit 0
EOF

  # ps: `-t <tty> -o pid=,args=` serves $PS_TABLE; everything else passes through to real ps.
  # NOTE the shape: `pid argv0 argv...`. Deliberately NOT `comm` — macOS truncates comm to 16 chars,
  # which is what made the first version of this resolver refuse every real pane.
  cat > "$D/bin/ps" <<'EOF'
#!/bin/bash
case "$*" in
  *"-t "*) printf '%s\n' "${PS_TABLE:-}" ;;
  *)       exec /bin/ps "$@" ;;
esac
EOF

  # gate: always REFUSE. We are testing RESOLUTION, not teardown — a REFUSE here means nothing is
  # ever actually killed by this suite, while the resolve-time NOTE still proves adoption happened.
  cat > "$D/bin/gate" <<'EOF'
#!/bin/bash
echo '{"decision":"REFUSE","reason_kind":"test-gate","reason":"gate stubbed REFUSE","git_state":"x"}'
exit 2
EOF
  chmod +x "$D/bin/cc-sessions" "$D/bin/it2" "$D/bin/ps" "$D/bin/gate"

  export CC_TEARDOWN_SESSIONS_BIN="$D/bin/cc-sessions"
  export IT2_BIN="$D/bin/it2"
  export CC_TEARDOWN_PS_BIN="$D/bin/ps"
  export CC_TEARDOWN_GATE_BIN="$D/bin/gate"
  export CCT_IT2_TIMEOUT_BIN=            # set-but-empty ⇒ no timeout wrapper around the mocks
  export CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1   # belt has its own suite; keep these focused
  export CC_REAP_LEASE=off
  export CC_TEARDOWN_SELF_UUID=DESK-PANE-NOT-THE-TARGET
  export CC_TEARDOWN_DIR="$D/teardown" CC_TEARDOWN_RECORDS_DIR="$D/records"

  # A readable list in which the target pane is present on ttys011.
  IT2_PRESENT='[{"id":"8A43425B-C6AA-493D-A14E-678AF747C6A8","tty":"/dev/ttys011"},{"id":"DESK","tty":"/dev/ttys999"}]'
  # The real assignee argv shape, verbatim from `ps -t <tty> -o pid=,args=` on this machine.
  PS_REAL='36549 /Users/chrisren/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id gu5-decide@session-8891c11f'
}

ev() { echo "test: lead $LEAD DEAD; report harvested"; }

@test "(1) OPT-IN: with no --assignee-of, an unregistered pane still REFUSEs unknown-target" {
  run env IT2_JSON="$IT2_PRESENT" PS_TABLE="$PS_REAL" \
      bash "$TD" "$PANE" --done-evidence "$(ev)"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=unknown-target"* ]] || false
  # and it must NOT have wandered into the adoption path
  ! [[ "$output" == *"adopted UNREGISTERED"* ]] || false
}

@test "(2) ADOPTED: registry miss + live pane + claude.exe with the lead's agent-id ⇒ resolved" {
  run env IT2_JSON="$IT2_PRESENT" PS_TABLE="$PS_REAL" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [[ "$output" == *"adopted UNREGISTERED assignee pane $PANE"* ]] || false
  [[ "$output" == *"pid 36549"* ]] || false
  [[ "$output" == *"gu5-decide@session-8891c11f"* ]] || false
  # resolution succeeded, so the run proceeds INTO the gates (stub REFUSEs) — never unknown-target
  ! [[ "$output" == *"unknown-target"* ]] || false
}

@test "(3) TRI-STATE: a BLIND it2 enumeration ([]) is indeterminate — REFUSE, never already-gone" {
  run env IT2_JSON='[]' PS_TABLE="$PS_REAL" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=assignee-unproven"* ]] || false
  # the fatal misread this pins: a blind enumerator must NEVER produce a success verdict
  ! [[ "$output" == *"already gone"* ]] || false
}

@test "(3b) TRI-STATE: unparseable it2 output is also indeterminate, not absent" {
  run env IT2_JSON='not json at all' PS_TABLE="$PS_REAL" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=assignee-unproven"* ]] || false
  ! [[ "$output" == *"already gone"* ]] || false
}

@test "(4) a READABLE list that omits the pane is a REAL absence ⇒ idempotent already-gone (rc 0)" {
  run env IT2_JSON='[{"id":"DESK","tty":"/dev/ttys999"},{"id":"OTHER","tty":"/dev/ttys998"}]' \
      PS_TABLE="$PS_REAL" bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"already gone"* ]] || false
}

@test "(5) ARGV NOT TEXT: a prose argv merely CONTAINING the agent-id string is never adopted" {
  # The real ttys029 process: argv[0]=bash, and the agent-id appears inside a TASK prose argument.
  local prose='1299 bash /Users/chrisren/.claude/bin/cc-close-attrib /x/claude --model claude-opus-5 TASK — lead died; its assignees are still keyed --agent-id gu5-decide@session-8891c11f and hang forever'
  run env IT2_JSON="$IT2_PRESENT" PS_TABLE="$prose" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=assignee-unproven"* ]] || false
  ! [[ "$output" == *"adopted UNREGISTERED"* ]] || false
}

@test "(6) RIGHT LEAD: an assignee of a DIFFERENT lead on that pane is never adopted" {
  local other='49707 /x/claude-code/bin/claude.exe --agent-id R1-archaeology@session-9f958f36'
  run env IT2_JSON="$IT2_PRESENT" PS_TABLE="$other" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=assignee-unproven"* ]] || false
}

@test "(7) a pane hosting only a shell (no claude.exe at all) is never adopted" {
  run env IT2_JSON="$IT2_PRESENT" PS_TABLE='400 -zsh' \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=assignee-unproven"* ]] || false
}

@test "(8) every adoption decision is RECORDED — no silent branch" {
  run env IT2_JSON='[]' PS_TABLE="$PS_REAL" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  # the reason_kind must be on disk, not only on stderr
  grep -rql 'assignee-unproven' "${CC_TEARDOWN_RECORDS_DIR:-$D/records}" "$HOME/.claude" 2>/dev/null || false
}
