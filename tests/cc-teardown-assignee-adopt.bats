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
#
# ── ADDED 2026-07-31 (backlog 99f87bf7a6f7): THE FALSE-SUCCESS CLASS, tests 9-15 ───────────────────
# The rules above still let the worst outcome through, because rc 1 ("pane provably absent") was
# INFERRED from a failed `.id == $target` lookup rather than READ. Reproduced against the pre-fix
# tree: `cc-teardown gu2-seams --assignee-of a8e72ae5` returned **exit 0 "already gone"** while pid
# 44938 was alive at 6h48m in pane CB29B303-…, because an agent NAME can never equal a pane id and
# the guaranteed miss was booked as absence. Its sibling gu2-archaeology returned REFUSE from the
# identical command — same state, opposite verdicts, differing only in it2 readability at that
# instant. exit 0 is the one verdict an automated caller cannot second-guess, and LCW_ORPHAN_CLOSE=1
# had just given this path its first automated caller.
#   NOT-A-PANE-KEY   a target that is not a pane UUID makes every lookup vacuous ⇒ REFUSE (9, 10)
#   TWO ORACLES      absence must be agreed by it2 AND the process table; a pane still hosting live
#                    processes is NOT gone however the enumerator answers (11, 12, 13)
#   TOKEN NOT TEXT   occupancy comes from an ITERM_SESSION_ID env TOKEN, never a uuid appearing in
#                    argv — cc-teardown's own argv carries the target uuid (14)
#   VERDICT TOKEN    every branch prints one parseable verdict= line; callers key on it (15)

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

  # ps: `-t <tty> -o pid=,args=` serves $PS_TABLE; `-E -Ao pid=,command=` serves $PS_ENV; everything
  # else passes through to real ps.
  # NOTE the shape: `pid argv0 argv...`. Deliberately NOT `comm` — macOS truncates comm to 16 chars,
  # which is what made the first version of this resolver refuse every real pane.
  # PS_ENV mirrors `ps -E` VERBATIM: `pid argv0 argv... KEY=v KEY=v` — argv and environment share one
  # whitespace-delimited column with nothing marking the boundary. That shape IS the trap tests 12
  # and 14 pin, so the mock must not tidy it away (memory: fixture-shape-parity-with-real-producer).
  # DEFAULT EMPTY = a BLIND occupancy oracle, so a test that forgets PS_ENV refuses loudly rather
  # than silently inheriting the real machine's process table and going nondeterministic.
  cat > "$D/bin/ps" <<'EOF'
#!/bin/bash
case "$*" in
  *"-E "*) printf '%s\n' "${PS_ENV:-}" ;;
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
  # A readable, NON-EMPTY list that simply omits the target — the "looks absent" case.
  IT2_ABSENT='[{"id":"DESK","tty":"/dev/ttys999"},{"id":"OTHER","tty":"/dev/ttys998"}]'
  # The real assignee argv shape, verbatim from `ps -t <tty> -o pid=,args=` on this machine.
  PS_REAL='36549 /Users/chrisren/.claude-219/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id gu5-decide@session-8891c11f'

  # `ps -E` tables. OTHER_PANE gives every one of them a live ITERM_SESSION_ID token, which is the
  # POSITIVE CONTROL: it proves the scan can see environments, so "no token for OUR pane" is a read
  # rather than a blind spot. Drop it (ENV_BLIND) and the oracle must say indeterminate, not vacant —
  # a broken oracle and an empty pane both measure zero.
  ENV_OCCUPIED="36549 /x/claude-code/bin/claude.exe --agent-id gu5-decide@session-8891c11f SHELL=/bin/zsh ITERM_SESSION_ID=w0t0p1:$PANE
777 -zsh SHELL=/bin/zsh ITERM_SESSION_ID=w9t9p9:D0D0D0D0-1111-2222-3333-444455556666"
  ENV_VACANT='777 -zsh SHELL=/bin/zsh ITERM_SESSION_ID=w9t9p9:D0D0D0D0-1111-2222-3333-444455556666'
  ENV_BLIND='777 -zsh SHELL=/bin/zsh'
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

@test "(4) a readable omission CORROBORATED by a vacant pane ⇒ idempotent already-gone (rc 0)" {
  # The one path that may still exit 0 — and it now takes TWO agreeing oracles, not one lookup miss.
  # Keeping it green is as load-bearing as the refusals below: absence does happen, and a fix that
  # could only ever refuse would trade a false success for a permanent false alarm.
  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$ENV_VACANT" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
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

# ── THE FALSE-SUCCESS CLASS (backlog 99f87bf7a6f7) ────────────────────────────────────────────────

@test "(9) THE INCIDENT verbatim: an agent NAME target must REFUSE, never 'already gone' (rc 2)" {
  # cc-teardown gu2-seams --assignee-of a8e72ae5 --force-adopted, with that pane and its pid ALIVE.
  # Pre-fix this returned exit 0 'assignee pane already gone'. The pane's own registry key is
  # gu-session-lifecycle-<prefix>, so the name matches nothing anywhere — the miss proves nothing.
  local live='[{"id":"CB29B303-BD07-42F6-AE0C-E56F2D540431","tty":"/dev/ttys011"},{"id":"DESK","tty":"/dev/ttys999"}]'
  local alive='44938 /x/claude-code/bin/claude.exe --agent-id gu2-seams@session-a8e72ae5'
  run env IT2_JSON="$live" PS_TABLE="$alive" PS_ENV="44938 claude.exe ITERM_SESSION_ID=w0t0p1:CB29B303-BD07-42F6-AE0C-E56F2D540431" \
      bash "$TD" gu2-seams --done-evidence "$(ev)" --assignee-of a8e72ae5 --force-adopted
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=target-not-a-pane-uuid"* ]] || false
  ! [[ "$output" == *"already gone"* ]] || false
  # and it must name the working form, so the refusal is actionable rather than a dead end
  [[ "$output" == *"pane UUID"* ]] || false
}

@test "(10) SAME STATE, SAME VERDICT: a name target no longer flips with it2 readability" {
  # The tell that the pre-fix rc 1 was a coin flip, not a verdict: gu2-seams (it2 readable) exited 0
  # while gu2-archaeology (it2 unreadable) exited 2, from the identical command against the identical
  # state. The shape guard fires before any it2 dependency, so both must now agree.
  local a=0 b=0
  env IT2_JSON="$IT2_PRESENT" PS_TABLE="$PS_REAL" \
    bash "$TD" gu2-seams --done-evidence "$(ev)" --assignee-of a8e72ae5 >/dev/null 2>&1 || a=$?
  env IT2_JSON='' PS_TABLE="$PS_REAL" \
    bash "$TD" gu2-archaeology --done-evidence "$(ev)" --assignee-of a8e72ae5 >/dev/null 2>&1 || b=$?
  [ "$a" = "$b" ] || false
  [ "$a" = 2 ] || false
}

@test "(11) PARTIAL BLINDNESS: it2 omits the pane but processes still live in it ⇒ REFUSE (rc 2)" {
  # The half of the class that the AUTOMATED caller can reach — it always passes a real uuid. it2
  # walks only app.windows, so a list can enumerate some windows and omit the target's and still be
  # readable and non-empty. Absence must lose to a live occupant, never the other way round.
  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$ENV_OCCUPIED" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=absence-contradicted"* ]] || false
  [[ "$output" == *"36549"* ]] || false          # names WHAT is still running
  ! [[ "$output" == *"already gone"* ]] || false
}

@test "(12) BLIND OCCUPANCY ORACLE: no environment visible anywhere ⇒ REFUSE, never vacant (rc 2)" {
  # The positive control. With no ITERM_SESSION_ID token in the whole table the scan is not reporting
  # environments at all, and a broken oracle measures exactly what an empty pane does.
  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$ENV_BLIND" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=absence-uncorroborated"* ]] || false
  ! [[ "$output" == *"already gone"* ]] || false
}

@test "(13) LOWERCASE target: occupancy still matches, so a live pane is never read as vacant" {
  # iTerm2 emits uppercase on both sides; a case-sensitive compare would miss every occupant and
  # answer VACANT — a silent false 'gone' reachable by nothing louder than a typo.
  local lower; lower="$(printf '%s' "$PANE" | tr '[:upper:]' '[:lower:]')"
  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$ENV_OCCUPIED" \
      bash "$TD" "$lower" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 2 ] || false
  [[ "$output" == *"reason_kind=absence-contradicted"* ]] || false
}

@test "(14) TOKEN NOT TEXT: a uuid in ARGV is not occupancy — the scan's own argv carries it" {
  # `ps -E` prints argv and environment in ONE column with nothing marking the boundary, so a naive
  # matcher counts ARGUMENTS as environment. Measured on this machine while building this fix: a
  # whole-line `index($0, ":"uuid)` returned the scanning **awk** as an occupant of the pane it was
  # scanning for — the detector matching itself. Occupancy must therefore be a whole field that IS an
  # ITERM_SESSION_ID assignment whose value ENDS in :<uuid>; neither a line-wide nor an unanchored
  # per-field substring qualifies.
  #
  # The fixture replays the real artifact rather than an approximation, and each row kills a
  # different naive implementation (verified by mutation — an approximation passed all of them):
  #   row 1  the scanning awk, argv carrying `u=":<uuid>"`  → kills whole-line AND unanchored-field
  #   row 2  cc-teardown's own invocation on this target    → kills bare-uuid matching
  #   row 3  a live but UNRELATED pane                      → the positive control (see ENV_OCCUPIED)
  local argv_only="998 awk -v u=:$PANE {print}
999 /bin/bash /x/cc-teardown $PANE --done-evidence pane $PANE survived
777 -zsh SHELL=/bin/zsh ITERM_SESSION_ID=w9t9p9:D0D0D0D0-1111-2222-3333-444455556666"
  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$argv_only" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"already gone"* ]] || false
}

@test "(15) VERDICT TOKEN: every branch emits one parseable verdict= line naming its exit code" {
  # Callers must never have to parse prose or guess from rc alone (rc 2 spans 'a gate declined' and
  # 'the actuator is blind'). Proven on both polarities so the assertion cannot pass vacuously.
  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$ENV_OCCUPIED" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [[ "$output" == *"verdict=REFUSE reason_kind=absence-contradicted exit=2 target=$PANE"* ]] || false

  run env IT2_JSON="$IT2_ABSENT" PS_TABLE="$PS_REAL" PS_ENV="$ENV_VACANT" \
      bash "$TD" "$PANE" --done-evidence "$(ev)" --assignee-of "$LEAD"
  [[ "$output" == *"verdict=ALREADY-GONE reason_kind=idempotent exit=0"* ]] || false

  # …and the exit code the token advertises is the one the caller actually gets
  [ "$status" -eq 0 ] || false
}
