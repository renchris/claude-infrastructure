#!/usr/bin/env bats
# THE COVERAGE LEDGER — which spawn paths carry a hardware admission term, asserted from the tree.
#
# MACHINE_CAPACITY_V2 §12.1 answered that question by hand on 2026-07-31 and produced a table:
# handoff-fire's callers GATED, and `boot-resume.sh`, `limit-recover/lr-fire-resume.sh`,
# `~/.reso/bin/reso-resume-one` and the **Agent tool** BYPASS. A hand-measured table decays the
# moment someone edits a file — memory `scan-revision-predates-the-fix`. This suite is that table
# as an executable assertion, so a path that LOSES its gate goes RED instead of quietly rejoining
# the bypass list and waiting for the next audit to notice.
#
# §12.1 also recorded the reason it matters that the claim be checkable rather than written down:
# handoff-fire's own header asserts "EVERY fire mode funnels through this script … this is the ONE
# place where a HARDWARE term can bind", and §12.1's verdict on that sentence is that it "is false
# in the tree and should be corrected to name the paths it actually covers — an in-source claim of
# chokepoint status that is untrue is worse than no claim, because it stops the next reader from
# checking." Case 20 pins the corrected sentence so it cannot silently become false again.
#
# ASSERTED BY INVOCATION, NOT BY MENTION (memory `caller-census-keyed-on-path-misses-the-name`: a
# census keyed on the wrong token read "zero callers" for a hook that was live). Every case here
# greps for a real `cc_capacity_admit` CALL, and each is paired with a check that the call is
# reachable rather than parked behind a dead branch.
#
# RED-PROOF for the 2026-08-07 extraction (item a27a4d9485da, re-runnable): this file was replayed
# against the pristine pre-change tree recovered via `git archive 07f9707c` (0 occurrences of
# `CC_HW_DEFAULT` in the library), run from that tree's OWN root so REPO/HF/LIB resolve pre-change.
# 5 of 14 went RED there, 0 skips either side:
#   26   no shared constant exists — the two gates still carry a literal each.
#   26b  the vm_stat headroom parser is found in TWO files, not one.
#   26c  the load-per-core verdict awk is found in TWO files, not one.
#   27   `absent` is not in capacity_gate's vocabulary — it had no library to lose.
#   28   handoff-fire.sh carries no loud-inertness message, for the same reason.
# The other 9 are pre-existing coverage assertions and stay GREEN on both trees BY DESIGN: the
# extraction moved terms between two files and must not have changed which spawn paths are gated.
# A case among 20–25 going red here would mean it did.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  # Two cases here DELIBERATELY read the live layer — case 24 must confirm the hook is registered
  # in the real settings.json (a gate registered only in a fixture is exactly the inert wiring this
  # suite exists to catch), and case 25 must confirm ~/.reso is still untracked. Capture the real
  # path FIRST, then fixture $HOME, so the live reads are explicit and named while every other case
  # is hermetic (scripts/test-hermeticity-lint.sh RULE 1 — an ambient $HOME is the flake seam).
  REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # This suite only GREPS handoff-fire.sh, never executes it — but the seams below are pinned
  # anyway, so that a case added later which does execute it cannot go red-by-machine-load or reach
  # the operator's live /tmp state (RULES 4 and 5).
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # Case 29 made bin/cc-pane and bin/it2-kitty subjects of this suite, and both READ these two —
  # which this repo INJECTS into every pane, so they arrive with an ambient value here. Case 29 only
  # greps them, but the seam is pinned for the same reason the block above pins handoff-fire's: a
  # case added later that EXECUTES either file must not inherit a live pane's launch command.
  # UNSET rather than assigned, because "absent" is the state their readers branch on.
  # CC_PANE_CMD_DIR rides with its two siblings: bin/it2-kitty:989 injects all three from ONE
  # `--env` block, so a pane that carries either of the above carries this one too. It was missed
  # here (and in two sibling suites) only because rule 6 excluded any seam whose default mentions
  # $HOME — deleted 2026-08-21, backlog b2775a8bbc3a.
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR
}

# a real call site, not a comment or a doc mention
calls_gate() { grep -qE '^[^#]*[^_a-zA-Z]cc_capacity_admit[[:space:]]' "$1"; }

@test "20 handoff-fire's chokepoint claim names the paths it ACTUALLY covers (§12.1)" {
  # The false sentence was: "EVERY fire mode funnels through this script". If it returns, the next
  # reader stops checking — which is how the four bypasses survived unnoticed until §12.1.
  #
  # ANCHORED TO LINE START, because the corrected header QUOTES the old sentence verbatim in order
  # to record what was wrong with it. An unanchored grep matches that citation and convicts the fix
  # for documenting itself — the guard blocking its own remedy (`guard-proxy-fails-in-both-
  # directions`). Position is the discriminator: `# EVERY fire mode …` at the head of a comment line
  # is the CLAIM; the same words mid-line inside quotes are a CITATION. Proven in both directions —
  # re-adding the line-start form reddens this case, and the citation below it does not.
  ! grep -qE '^#[[:space:]]*EVERY fire mode funnels through this script' "$HF" || false
  grep -q 'used to say it was' "$HF" || false      # the citation is PRESENT and must stay tolerated
  # and the corrected claim must point at the sibling term rather than leaving a bare denial
  grep -q 'capacity-admit' "$HF"
}

@test "21 boot-resume-launch.sh — the reso-resume-one seam — is GATED" {
  calls_gate "$REPO/scripts/boot-resume-launch.sh"
  # rc 9 must be its own code: boot-resume.sh reads it as `shed`, and 2/3/4 already mean
  # usage / missing-dep / launch-failed. A shed collapsed into a failure is the wrong operator action.
  grep -qE '^[[:space:]]*exit 9' "$REPO/scripts/boot-resume-launch.sh"
}

@test "21b the gate is placed AFTER --dry-run (an inspection must not be refused)" {
  # A dry run prints a command and spawns nothing. Gating it would refuse an inspection — and worse,
  # would spend budget on a spawn that never happened.
  dry="$(grep -n 'DRYRUN' "$REPO/scripts/boot-resume-launch.sh" | grep -c 'exit 0' || true)"
  [ "$dry" -ge 0 ]
  dryline="$(awk '/if \[ "\$DRYRUN" = "1" \]/{print NR; exit}' "$REPO/scripts/boot-resume-launch.sh")"
  gateline="$(awk '/cc_capacity_admit boot-resume-launch/{print NR; exit}' "$REPO/scripts/boot-resume-launch.sh")"
  [ -n "$dryline" ] && [ -n "$gateline" ] || false
  [ "$gateline" -gt "$dryline" ]
}

@test "22 boot-resume.sh keeps SHED distinct from FAILED (rc 9 is not a launch failure)" {
  grep -qE '9\)[[:space:]]*resume_shed' "$REPO/scripts/boot-resume.sh"
  # and it must SURFACE on BOTH channels — a shed that only exists in a counter is a silent drop,
  # which is §12.4's entire concern (the boot storm quietly eating the recovery). Keyed on the
  # emitting statement, not on the bare token: `grep resume_shed` would be satisfied by the
  # declaration alone and would pass on a script that counts sheds and tells nobody.
  grep -qE '\[ "\$resume_shed" -gt 0 \].*shed by the capacity gate' "$REPO/scripts/boot-resume.sh"
  grep -qE 'log_idl fired.*resume_shed' "$REPO/scripts/boot-resume.sh"
}

@test "23 lr-fire-resume.sh is GATED before its exec" {
  calls_gate "$REPO/scripts/limit-recover/lr-fire-resume.sh"
  # BEFORE `exec expect` — a gate after the exec is unreachable by construction, which is exactly
  # the kind of inert wiring that reads as coverage and is not.
  gateline="$(awk '/cc_capacity_admit lr-fire-resume/{print NR; exit}' "$REPO/scripts/limit-recover/lr-fire-resume.sh")"
  execline="$(awk '/^exec expect/{print NR; exit}' "$REPO/scripts/limit-recover/lr-fire-resume.sh")"
  [ -n "$gateline" ] && [ -n "$execline" ] || false
  [ "$gateline" -lt "$execline" ]
}

@test "24 the Agent tool is GATED — in a hook ALREADY in settings.json, not a new one" {
  # §12.1: "The Agent path matters most — it is the highest-volume spawn surface." Its two
  # PreToolUse hooks bound policy and frontier budget, never hardware.
  calls_gate "$REPO/hooks/agent-teams-enforce.sh"
  grep -q 'permissionDecision' "$REPO/hooks/agent-teams-enforce.sh"
  # The hook must ALREADY be registered on PreToolUse|Agent in the live settings.json. A new hook
  # file would need a new entry = a C10 operator hand-step = the pending-activation queue, where 11
  # scripts are currently rotting unrun. A gate that ships INERT is the 2026-08-07 inertness
  # generator, and this case is what stops this one shipping that way.
  s="$REAL_HOME/.claude/settings.json"      # the LIVE enforcing store, deliberately — see setup()
  [ -f "$s" ] || skip "no live settings.json on this box"
  run jq -r '[.hooks.PreToolUse[] | select(.matcher|test("Agent")) | .hooks[].command] | join(" ")' "$s"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-teams-enforce.sh"* ]]
}

@test "24b the Agent gate runs BEFORE every early-exit, so no subagent type escapes it" {
  # This hook exits 0 early for read-only types, research markers and the delivery-contract guard.
  # A capacity term placed after any of them would gate some spawns and not others — coverage that
  # looks complete in a grep and is not.
  h="$REPO/hooks/agent-teams-enforce.sh"
  gateline="$(awk '/cc_capacity_admit agent-tool/{print NR; exit}' "$h")"
  [ -n "$gateline" ] || false
  # the read-only-type early exit is the earliest policy exit; the gate must precede it
  roline="$(awk '/Explore\|Plan\|claude-code-guide/{print NR; exit}' "$h")"
  [ -n "$roline" ] || false
  [ "$gateline" -lt "$roline" ]
}

@test "24c an ABSENT capacity library must not disarm the hook's OTHER guards" {
  # The failure mode this forbids: a missing library takes an early `exit 0` and silently turns off
  # Agent-Teams enforcement, the brief-size cap and the delivery-contract guard along with it.
  #
  # ABSENCE IS SIMULATED BY ISOLATION, NOT BY ENV. The hook resolves its library script-relative
  # FIRST (deliberately — see its header), so pointing CLAUDE_CONFIG_DIR and HOME at /nonexistent
  # does NOT make it absent: it still finds the repo's own scripts/lib. Copying the hook to a
  # directory with no sibling scripts/lib is the only thing that actually reproduces the state.
  # (An earlier version of this case used the env-only form and proved nothing.)
  iso="$BATS_TEST_TMPDIR/iso"
  mkdir -p "$iso"
  cp "$REPO/hooks/agent-teams-enforce.sh" "$iso/agent-teams-enforce.sh"
  run env CLAUDE_CONFIG_DIR=/nonexistent HOME="$BATS_TEST_TMPDIR/nohome" \
      CC_ADMIT_IDL="$BATS_TEST_TMPDIR/iso-idl.jsonl" \
      bash -c 'echo "{\"tool_input\":{\"prompt\":\"implement the new schema migration and write the code\",\"run_in_background\":true}}" | bash "$1" 2>/dev/null' _ "$iso/agent-teams-enforce.sh"
  # the library really is unreachable in this arrangement — otherwise the case is vacuous
  ! grep -q 'cc_capacity_admit' <<< "$(command -v cc_capacity_admit || true)" || false
  [[ "$output" == *'"deny"'* ]] || false
  [[ "$output" == *"Background subagents cannot write code"* ]] || false
  # and the absence is recorded in the ledger rather than printed on stderr (see case 28)
  [ -f "$BATS_TEST_TMPDIR/iso-idl.jsonl" ]
  # SELECT THIS CASE'S OWN ROW. The bare `jq -r '.basis'` this replaces spanned the WHOLE ledger
  # and only ever worked because capacity-admit was its sole writer — so the first hook to record a
  # second row (the spawn-budget term, 66ef300dd0b4) made it compare "absent\n<other>" to "absent"
  # and reddened a case about a subject that had not changed. That is a tripwire for someone else's
  # correct addition, not a guard (memory: assertion-span-must-equal-its-subject). Keyed on the
  # gate, it now also cannot be SATISFIED by another writer's row, which the old form could.
  [ "$(jq -r 'select(.gate=="capacity-admit") | .basis' "$BATS_TEST_TMPDIR/iso-idl.jsonl")" = "absent" ]
}

@test "25 reso-resume-one is GATED in its own body — the last capacity bypass is closed" {
  # §12.1 listed it as a bypass path: every IN-REPO invocation goes through boot-resume-launch.sh,
  # which case 21 pins as gated, but a DIRECT call — the runbook's, an operator's, the Agent-tool
  # path — reached a spawn against no admission check at all.
  #
  # THE PREMISE MOVED UNDER THIS CASE TWICE, and both moves are the point of keeping the history.
  # (1) It first read "UNGATEABLE … not in any git repository". That reasoning died the moment
  # 5c38ad5a tracked the engine at bin/ precisely so fixes would reach it, and the case then failed
  # for a reason with nothing to do with its subject — the file census counted the ENGINE as a
  # caller of itself — blocking every land in the repo, including diffs that never touched it.
  # (2) It was then restated to assert the residue: tracked AND still ungated, filed rather than
  # accepted, with the standing instruction "will redden the moment that lands, which is when it
  # should be rewritten to assert the gate."
  #
  # 2026-08-17: that landed, so this is the instructed rewrite — NOT an assertion relaxed to let a
  # change through. A test pinning behaviour the subject deliberately changed becomes a guard for
  # the bug (memory: stale-assertion-becomes-an-inverted-guard); the discriminator is that the old
  # text named the new state as the correct one and said what should replace it.
  [ -f "$REPO/bin/reso-resume-one" ] \
    || skip "the engine is not in this tree — nothing to make a claim about"
  grep -q 'cc_capacity_admit ' "$REPO/bin/reso-resume-one" \
    || { echo "the engine lost its capacity gate — the §12.1 bypass is open again"; false; }
  # SHED IS ITS OWN CODE. Reusing 2/3/4 would fold "the box is busy" into "this is broken", and
  # boot-resume.sh reports the two separately because the operator's next action differs.
  grep -q 'exit 9' "$REPO/bin/reso-resume-one" \
    || { echo "the engine's gate does not shed with exit 9 — a shed is not a failure"; false; }
  # The behaviour itself (shed · admit · absent-is-loud · no double evaluation) is asserted in
  # tests/reso-resume-one.bats, which executes the real engine. This case owns the CENSUS below —
  # that no NEW ungated invoker has appeared — and only checks here that the gate is present at all.

  # The invocation census: which OTHER in-repo files reach it. The engine itself is the subject,
  # not a caller, so it is excluded by name alongside the three limit-recover files that only
  # mention it in prose.
  callers="$(grep -rlE '^[^#]*(RESUME_ONE|reso-resume-one)' "$REPO/scripts" "$REPO/bin" 2>/dev/null \
             | grep -v 'lr-fire-resume.sh\|lr-preseed-env.sh\|lr-select.py\|bin/reso-resume-one' || true)"
  # TWO gated invokers as of 2026-08-24. bin/cc-resume-layout.sh joined boot-resume-launch.sh when
  # /resume-sessions grew a per-monitor layout: it fires a BATCH, which is precisely the shape this
  # gate exists to bound. It was landed UNGATED, this case caught it, and the post-land verifier
  # auto-reverted the commit — the ratchet working exactly as designed. So the entry is added WITH
  # its own gating asserted immediately below, never by loosening the census.
  expected_callers="$(printf '%s\n%s\n' "$REPO/scripts/boot-resume-launch.sh" \
                                        "$REPO/bin/cc-resume-layout.sh" | sort)"
  [ "$(printf '%s\n' "$callers" | sort)" = "$expected_callers" ] \
    || { echo "a NEW in-repo invoker appeared, and it is not a gated launcher: $callers"; false; }
  # The batch caller must gate the way the launcher does — admit ONCE, then hand the engine
  # CC_ADMIT_DONE so it does not evaluate again and double-spend the shared consecutive-refusal
  # budget. Without both halves the census entry above is a hole rather than a record.
  grep -q 'cc_capacity_admit ' "$REPO/bin/cc-resume-layout.sh" \
    || { echo "cc-resume-layout invokes the engine but never admits — the batch is ungated"; false; }
  grep -q 'CC_ADMIT_DONE=1' "$REPO/bin/cc-resume-layout.sh" \
    || { echo "cc-resume-layout does not mark its admission — the engine will gate twice per spawn"; false; }
  # The launcher must MARK its admission, or the engine's new gate double-evaluates on every
  # in-repo resume and double-spends the shared consecutive-refusal budget. This pins the pairing
  # from the launcher's side; tests/reso-resume-one.bats pins the engine's side of the same handshake.
  grep -q 'export CC_ADMIT_DONE=1' "$REPO/scripts/boot-resume-launch.sh" \
    || { echo "the launcher no longer marks its admission — the engine will evaluate the gate twice"; false; }
  # The old form of this line required the phrase UNGATED IN ITS OWN BODY to be written where the
  # next reader looks. That residue is closed, so requiring its statement would now pin a FALSE
  # claim in the tree — the assertion moves to the pairing that replaced it, not away entirely.
}

@test "26 TERM PARITY — ONE literal per term, so the ceilings CANNOT drift (not merely 'do not')" {
  # capacity-admit.sh deliberately uses its OWN CC_ADMIT_* namespace rather than reusing
  # CC_FIRE_*: handoff-fire.sh reasoned that out for CC_FIRE_SYSCTL vs capacity-alarm's
  # CC_CAP_SYSCTL — sharing one variable between two subjects lets a stub aimed at ONE silently
  # redirect the OTHER. Separate names are correct; separate DEFAULTS would be drift.
  #
  # UNTIL 2026-08-07 THIS CASE COMPARED TWO LITERALS, and that is a detector, not a gate: it could
  # only report drift after someone had written it, and it was blind to the ~25 OTHER lines the two
  # gates duplicated — the vm_stat page-size parser most of all, where a fix on one side only is
  # invisible here and wrong by 4x (cases 17/18 of handoff-fire-capacity-gate.bats are that pair).
  # Item a27a4d9485da made the terms one implementation, so this case now asserts the STRUCTURE:
  # there is one literal for each term, in the library, and NEITHER gate carries a number of its own.
  #
  # (The old form is also why this file's dead-assertion history matters: it shipped with
  # `cut -d- -f3` — `CC_FIRE_MAX_LOAD_PER_CORE:-2.0` has ONE `-`, so field 3 is EMPTY — and PASSED,
  # because its emptiness guards were mid-test `[ ] && [ ]` that errexit cannot reach in bats. It
  # compared "" to "" and called that parity. Every guard below is a separate live assertion.)
  local shared_load shared_head
  shared_load="$(grep -oE '^CC_HW_DEFAULT_MAX_LOAD_PER_CORE=[0-9.]+' "$LIB" | head -1 | cut -d= -f2)"
  shared_head="$(grep -oE '^CC_HW_DEFAULT_MIN_HEADROOM_GB=[0-9.]+' "$LIB" | head -1 | cut -d= -f2)"
  [ -n "$shared_load" ] || { echo "no shared load ceiling in $LIB"; false; }
  [ -n "$shared_head" ] || { echo "no shared headroom floor in $LIB"; false; }

  # BOTH gates must expand it. A constant nothing reads is not a shared term, it is a comment.
  grep -q 'CC_FIRE_MAX_LOAD_PER_CORE:-\$CC_HW_DEFAULT_MAX_LOAD_PER_CORE' "$HF" \
    || { echo "capacity_gate does not expand the shared load ceiling"; false; }
  grep -q 'CC_FIRE_MIN_HEADROOM_GB:-\$CC_HW_DEFAULT_MIN_HEADROOM_GB' "$HF" \
    || { echo "capacity_gate does not expand the shared headroom floor"; false; }
  grep -q 'CC_ADMIT_MAX_LOAD_PER_CORE:-\$CC_HW_DEFAULT_MAX_LOAD_PER_CORE' "$LIB" \
    || { echo "cc_capacity_admit does not expand the shared load ceiling"; false; }
  grep -q 'CC_ADMIT_MIN_HEADROOM_GB:-\$CC_HW_DEFAULT_MIN_HEADROOM_GB' "$LIB" \
    || { echo "cc_capacity_admit does not expand the shared headroom floor"; false; }

  # THE RATCHET: no second literal anywhere. A gate that re-acquires its own `:-2.0` has silently
  # left the shared term, and would do so while every assertion above still passed.
  local stray
  stray="$(grep -nE 'CC_(FIRE|ADMIT)_(MAX_LOAD_PER_CORE|MIN_HEADROOM_GB):-[0-9]' "$HF" "$LIB" || true)"
  [ -z "$stray" ] || { echo "a gate re-acquired its own literal default:"; echo "$stray"; false; }

  # MUTATION CONTROL — the ratchet must be able to FAIL, or the emptiness above is all it proves.
  # Same predicate, run over the exact string it exists to reject.
  printf 'ceiling="${CC_FIRE_MAX_LOAD_PER_CORE:-2.0}"\n' > "$BATS_TEST_TMPDIR/drifted.sh"
  grep -qE 'CC_(FIRE|ADMIT)_(MAX_LOAD_PER_CORE|MIN_HEADROOM_GB):-[0-9]' "$BATS_TEST_TMPDIR/drifted.sh" \
    || { echo "the stray-literal predicate cannot match a drifted default — it proves nothing"; false; }
}

@test "26b ONE PARSER — the vm_stat headroom sum exists exactly once in the shell tree" {
  # The ceilings were never the expensive half. This is: a 10-line awk that reads the page size from
  # vm_stat's OWN header and sums exactly free+speculative+inactive+purgeable. Case 26's literal
  # comparison could not see it at all, so a page-size fix landing on one copy only would have been
  # invisible AND wrong by 4x on an Apple-silicon box.
  local owners
  owners="$(grep -rlE '^[[:space:]]*/\^Pages speculative:/' "$REPO/scripts" "$REPO/hooks" \
              --include='*.sh' 2>/dev/null | sed "s#^$REPO/##" | sort | tr '\n' ' ')"
  [ "$owners" = "scripts/lib/capacity-admit.sh " ] \
    || { echo "the headroom parser must exist exactly once, in the library; found: [$owners]"; false; }

  # scripts/capacity-alarm.sh reads the same vm_stat and is DELIBERATELY not folded in — it is a
  # different INSTRUMENT (a monitor with warn/alarm rungs at 1.5/2.5 per core) that also sums the
  # compressor, active and wired populations these gates exclude. The exemption is ASSERTED, not
  # assumed: if it ever became a bare copy of the four-population sum, that is a duplicate and the
  # `owners` check above would have to catch it.
  grep -q 'Pages occupied by compressor' "$REPO/scripts/capacity-alarm.sh" \
    || { echo "capacity-alarm no longer sums a wider population — re-check whether it is now a duplicate"; false; }
}

@test "26c ONE VERDICT — the load-per-core awk exists once, and both gates call it" {
  # Same class as 26b for the other term. `lpc > c ? "REFUSE" : "ADMIT"` was written out twice.
  local owners
  owners="$(grep -rlF 'lpc > c ? "REFUSE" : "ADMIT"' "$REPO/scripts" "$REPO/hooks" \
              --include='*.sh' 2>/dev/null | sed "s#^$REPO/##" | sort | tr '\n' ' ')"
  [ "$owners" = "scripts/lib/capacity-admit.sh " ] \
    || { echo "the load verdict must exist exactly once, in the library; found: [$owners]"; false; }
  grep -q 'cc_hw_load_verdict' "$HF"  || { echo "capacity_gate does not call the shared verdict"; false; }
  grep -q 'cc_hw_load_verdict' "$LIB" || { echo "cc_capacity_admit does not call the shared verdict"; false; }
  # ...and the same for the resolver and the headroom read, so "one implementation" is the whole
  # term rather than the one line this case happens to name (memory `inventory-before-building`).
  local fn
  for fn in cc_hw_resolve_sysctl cc_hw_ncpu cc_hw_load1 cc_hw_headroom_gb cc_hw_headroom_verdict; do
    grep -qE "^$fn\(\)" "$LIB" || { echo "$fn is not defined in the library"; false; }
    grep -q "$fn" "$HF"  || { echo "capacity_gate does not use $fn"; false; }
    grep -q "$fn" "$LIB" || { echo "cc_capacity_admit does not use $fn"; false; }
  done
}

@test "27 BASIS PARITY — capacity_gate's vocabulary is a subset of capacity-admit's" {
  # §9.5.1: "split on `basis` before believing any ratio computed here." That instruction only
  # works if one split spans both gates. capacity-admit adds `headroom-only` and `budget-expired`;
  # it may never DROP one of the originals, or a cross-gate query silently loses a population.
  #
  # `absent` joined the list on 2026-08-07 and is the one no gate can emit for itself — it means the
  # LIBRARY was unreachable, so a caller writes it (this hook, and capacity_gate since the terms
  # moved there). It has to be in the shared vocabulary for the same reason as the rest: an ungated
  # window that reads back as a plain admit is the §9.5.1 population defect exactly.
  for b in measured load-only fail-open gate-off absent; do
    grep -q "emit_gate_admit capacity $b" "$HF" || grep -q "$b" "$HF"
    grep -q "$b" "$LIB" || { echo "basis '$b' exists in capacity_gate but NOT in capacity-admit"; false; }
  done
}

@test "28 every gated path is LOUD when the library is absent (§12.2: never a silent admit)" {
  # "Inertness must be LOUD (`capacity_gate: ABSENT`) rather than a silent admit." Each caller
  # degrades rather than dying — a resume that refuses to run because a telemetry library is
  # missing would be the gate causing the outage it exists to prevent — so the ONLY thing standing
  # between a degraded path and an invisible one is this signal.
  #
  # THE CHANNEL DIFFERS BY CALLER, and that is the point rather than an inconsistency. A script a
  # human or launchd runs says it on stderr, where its operator is already reading. A hook that
  # fires on EVERY Agent call on the box cannot: a per-spawn stderr line is noise that gets tuned
  # out (`alarm-polarity-and-attention-budget` — an alarm that always fires carries the same zero
  # bits as one that cannot) AND it lands in the hook's own output stream, where it corrupts the
  # JSON contract (measured: it broke 6 cases in agent-teams-enforce.bats with a jq parse error,
  # because bats' `run` merges stderr into $output). Its channel is the ledger.
  #
  # handoff-fire.sh JOINED THIS LIST on 2026-08-07. Until then it needed no library and so had no
  # absence to be loud about; the extraction gave it one, and it is the highest-stakes of the four —
  # its call site turns any non-zero status into rc 9, so a missing file that reached the terms
  # would refuse every fire on the box. tests/handoff-fire-capacity-gate.bats case 32 EXECUTES that
  # path; this is the source-level half, so a caller that loses the signal goes red in both places.
  for f in scripts/boot-resume-launch.sh scripts/limit-recover/lr-fire-resume.sh scripts/handoff-fire.sh; do
    grep -q 'capacity-admit: ABSENT' "$REPO/$f" || { echo "$f: no loud-inertness message"; false; }
  done
  grep -q 'basis:"absent"' "$REPO/hooks/agent-teams-enforce.sh"
  # and it must NOT be on stderr there — the regression this replaced
  ! grep -qE 'capacity-admit: ABSENT.*>&2' "$REPO/hooks/agent-teams-enforce.sh"
}

@test "29 the pane-spawn PRIMITIVE is ungated BY DESIGN — the gate is the CALLER's (item 9a88cb04dab2)" {
  # THE RESIDUE §12.1 NEVER STATED, and the reason a drain recycle re-derived it from scratch.
  # Item 9a88cb04dab2 reads "it2-kitty split path has NO capacity admission … wire cc_capacity_admit
  # into the split/os-window spawn sites", and its stored falsifier is `grep -q cc_capacity_admit
  # bin/cc-pane`. Both halves of that are true of the tree and the conclusion is still wrong, which
  # is exactly the shape this ledger exists to make un-re-derivable.
  #
  # WHY GATING THE PRIMITIVE IS THE REFUTED FIX, not merely an unnecessary one. handoff-fire.sh:6354
  # reads `if [ "$RECYCLE" = 0 ]; then capacity_gate || exit 9; fi` — a recycle REPLACES a session
  # (net-zero panes) and is exempt on purpose. A term inside the primitive cannot see $RECYCLE: it
  # fires on every split, so it would refuse recycles, and it would place the BUDGET-BOUNDED
  # cc_capacity_admit underneath handoff-fire's UNBOUNDED capacity_gate. handoff-fire.sh:4210-4213
  # names that composition directly — "ONE gate for both would re-commit the fix that §8.5.2 and
  # §12.2 already refuted" — and §12.1's own closing note says the extraction was "NOT by
  # universalising capacity_gate() — §12.2 below stands unamended".
  #
  # SO THE DESIGN IS: the CALLER owns the gate, because boundedness is a property of the caller and
  # not of the primitive. Unattended callers (boot storm, limit-recovery, the Agent tool) take the
  # bounded term — cases 21/23/24/25. The attended caller takes the unbounded one with the recycle
  # exemption. The primitive itself stays neutral so both policies remain expressible through it.
  # (pane-spawn-coverage-lint.sh reaches the same split for LOGGING and states the mirror rule —
  # there the CALLEE owns the row, so the two ledgers are not in tension: one counts surfaces, this
  # one binds policy.)

  # ANTI-VACUITY FIRST: if a refactor moves the raw split sites out of cc-pane, every assertion
  # below would pass over nothing. Locate the subject before making a claim about it.
  grep -qE '^[^#]*session split' "$REPO/bin/cc-pane" \
    || { echo "bin/cc-pane no longer issues 'session split' — this case is asserting over nothing"; false; }

  # THE CENSUS, and the ONE assertion here that should ever red. `cc-pane spawn` is the verb that
  # owns those sites, and nothing in the tree calls it — so wiring the item's remedy there would
  # green its own falsifier while gating a path with no traffic. Measured 2026-08-19 with a
  # positive control (the same instrument returns 114 for cc-notify, which is called everywhere;
  # memory `caller-census-keyed-on-path-misses-the-name` and `positive-control-the-denominator`).
  # The day a caller appears, this reds — which is precisely when the capacity question has to be
  # answered, at that new caller and with its own boundedness policy.
  spawn_callers="$(grep -rnE '^[^#]*(bin/)?cc-pane (spawn|split)' "$REPO/scripts" "$REPO/bin" "$REPO/hooks" 2>/dev/null || true)"
  [ -z "$spawn_callers" ] \
    || { echo "cc-pane spawn gained a caller — decide its capacity policy AT THE CALLER, not in the primitive: $spawn_callers"; false; }

  # THE ATTENDED CALLER STAYS GATED, and keeps its exemption. If either half of this line moves, the
  # reasoning above stops holding and the item deserves a fresh answer rather than this one.
  grep -qF 'if [ "$RECYCLE" = 0 ]; then capacity_gate || exit 9; fi' "$REPO/scripts/handoff-fire.sh" \
    || { echo "handoff-fire's gate or its recycle exemption moved — re-derive whether the primitive should stay neutral"; false; }

  # AND THE PRIMITIVES STAY NEUTRAL. This is a real ratchet, not decoration: adding the bounded term
  # to either file is the change that would refuse recycles. If a future design genuinely wants a
  # term here, that is a §12.2 amendment and this case should be rewritten to assert the new shape —
  # the discriminator case 25 established (the old text must name the new state as correct and say
  # what replaces it), NOT an assertion relaxed to let a change through.
  for prim in "$REPO/bin/it2-kitty" "$REPO/bin/cc-pane"; do
    [ -f "$prim" ] || continue
    if calls_gate "$prim"; then
      echo "$prim took the BOUNDED term: it cannot see \$RECYCLE, so this refuses recycles (handoff-fire.sh:6354). Gate the CALLER."
      false
    fi
  done
}

@test "30 the ceiling's OWN caller list is DERIVED from the tree, not written down (item e981656df348)" {
  # WHY THIS CASE EXISTS. The 2.0/core block in capacity-admit.sh argues that an underived ceiling is
  # TOLERABLE, and its whole warrant is the size of the blast radius: "it still binds only where
  # cc_capacity_admit leaves the term on". Until 2026-08-25 that sentence said TWO callers and the
  # tree had FOUR — both misses in bin/, both added by later lands that never touched this comment,
  # so nothing conflicted and the argument silently understated itself by 2x. A hand-maintained
  # census decays exactly this way (memory `scan-revision-predates-the-fix`); case 20 already pins
  # ONE such sentence, and this is the same ratchet for the one that prices the underived literal.
  #
  # DERIVED IN BOTH DIRECTIONS. A caller that GAINS the term must appear in the comment, and a
  # caller that LOSES it (or is deleted) must leave — a one-way check would let the list rot in the
  # other direction, which is how the original defect survived. The population is the same one
  # `calls_gate` defines, minus two non-callers by construction:
  #   · the library itself, which DEFINES cc_capacity_admit rather than calling it;
  #   · scripts/test-hermeticity-lint.sh, whose matches are embedded @test fixtures, not spawns
  #     (memory `caller-census-keyed-on-path-misses-the-name` cuts the other way here — the token is
  #     right and the SUBJECT is wrong, so the exclusion is by file, and it is named not blanket).
  #
  # THE OFF-MARKER IS FILE-SCOPED ON PURPOSE. hooks/agent-teams-enforce.sh sets CC_ADMIT_LOAD_TERM=off
  # on the `if !` line and calls the gate on the NEXT line, so a line-scoped test would read the
  # Agent-tool path as binding. CC_ADMIT_LOAD_TERM defaults to `on`, so absence of the marker IS the
  # binding condition — the same default the load-term block below the comment documents.
  #
  # RED-PROOFED IN BOTH DIRECTIONS, 2026-08-25, and re-runnable:
  #   UNDERCOUNT — replayed against the pristine pre-fix tree (`git archive HEAD` before the comment
  #     was corrected, i.e. the "the two unattended recovery callers" sentence): RED on
  #     bin/cc-resume-layout.sh. That is the original defect, caught.
  #   OVERCOUNT  — appending `· hooks/agent-teams-enforce.sh` to the list line on an otherwise
  #     unmodified tree: RED on the stale-entry arm. A caller that LATER gains CC_ADMIT_LOAD_TERM=off
  #     travels the identical path, so that direction is covered by the same proof.
  # The other 15 cases in this file are unaffected by the correction and stay GREEN on both trees.
  binds=""
  while read -r f; do
    [ -n "$f" ] || continue
    grep -q 'CC_ADMIT_LOAD_TERM=off' "$REPO/$f" || binds="$binds $f"
  done <<< "$(cd "$REPO" && grep -rlE '^[^#]*[^_a-zA-Z]cc_capacity_admit[[:space:]]' scripts bin hooks 2>/dev/null \
                | grep -v '^scripts/lib/capacity-admit\.sh$' \
                | grep -v '^scripts/test-hermeticity-lint\.sh$' | sort)"

  [ -n "$binds" ] || { echo "no caller binds the load term at all — if that is now true the comment must SAY so, and this case must be rewritten to assert the new shape (the case-25 discriminator), not deleted"; false; }

  # the comment must name every binding caller ...
  for f in $binds; do
    grep -qF "$f" "$LIB" \
      || { echo "$f binds the underived 2.0/core ceiling and the block that prices it does not name it — update the WHERE IT STILL BINDS list in $LIB"; false; }
  done

  # ... and must name NOTHING ELSE as binding. Scoped TWICE, because the block's own prose names the
  # one caller that is exempt: `hooks/agent-teams-enforce.sh` appears three lines above the list as
  # the file that passes CC_ADMIT_LOAD_TERM=off, and a range-only read convicts the comment for
  # explaining itself — the same `guard-proxy-fails-in-both-directions` shape case 20 documents.
  # Indentation is the discriminator: the LIST is the continuation lines (`#` + 3 spaces), the prose
  # around it is `#` + 1. So the second filter is load-bearing, not tidying.
  listed="$(awk '/^# WHERE IT STILL BINDS/,/^# DELIBERATELY/' "$LIB" | grep '^#   ' \
              | grep -oE '(scripts|bin|hooks)/[A-Za-z0-9_/.-]+' | sort -u)"
  [ -n "$listed" ] || { echo "the WHERE IT STILL BINDS block lost its shape — case 30 can no longer read the list it ratchets"; false; }
  for f in $listed; do
    case " $binds " in
      *" $f "*) ;;
      *) echo "$LIB lists $f as binding the load term, but the tree says it does not (deleted, or it now passes CC_ADMIT_LOAD_TERM=off) — a stale list overstates the ceiling's reach just as the old one understated it"; false ;;
    esac
  done

  # AND THE DERIVATION ITSELF STAYS REFUTED. e981656df348 was filed as "blocked on the marginal-load
  # measurement"; that blocker is a slope and a ceiling wants a failure point. If someone re-files it
  # as merely pending, this line reds and they have to argue with the paragraph instead of the id.
  grep -qF 'e981656df348' "$LIB" \
    || { echo "the refutation of e981656df348's premise left $LIB — a future reader will re-file the ceiling as 'blocked on 193ae8ddce72', which is the loop this case closes"; false; }
}

@test "31 the REFUTED 2.5-5 figure's quote sites are DERIVED from the tree, not written down (item e981656df348)" {
  # WHY THIS CASE EXISTS. Case 30 ratchets one hand-maintained census (which callers bind the
  # underived 2.0/core ceiling). Fixing it surfaced a SECOND one, in the same week and with the same
  # cause: docs/research/marginal-load-per-active-session-2026-08-19.md refutes the published 2.5-5
  # figure and tells a future session which quote sites to update on a PASS — and that list said TWO
  # while the tree had THREE. The miss was the load-bearing one: scripts/lib/spawn-presence.sh does
  # not merely cite 2.5-5, it DERIVES its `~4-8 concurrent actives` ceiling from it, so a PASS that
  # updated only the two named sites would leave the number that sets the actual spawn ceiling still
  # quoting a value that document refutes. A census with no falsifier decays in one direction only.
  #
  # DERIVED IN BOTH DIRECTIONS, like case 30 — a site that GAINS the figure must appear in the doc,
  # and a site that LOSES it must leave. A one-way check is how the original defect survived.
  #
  # THIS CASE MUST NOT OUTLIVE ITS SUBJECT. On a §6 PASS the figure is replaced everywhere and this
  # census goes empty; that is the case-25 discriminator, so the empty state fails LOUD with the
  # instruction to rewrite the case to the new shape rather than letting it silently pass.
  DOC="$REPO/docs/research/marginal-load-per-active-session-2026-08-19.md"
  [ -f "$DOC" ] || skip "the refutation doc is gone — if 2.5-5 was re-derived, rewrite this case to the new shape"

  sites="$(cd "$REPO" && grep -rl '2\.5-5 runnable threads' scripts hooks bin 2>/dev/null | sort)"
  [ -n "$sites" ] \
    || { echo "no file quotes 2.5-5 any more. If §6 PASSED and the figure was re-derived, this case must be REWRITTEN to ratchet the new value's quote sites (case 25's discriminator), not deleted — an empty census that passes is how the next one rots"; false; }

  # BOTH ARMS READ THE SAME DELIMITED BLOCK, and that symmetry is the fix for this case's own second
  # false green. The first draft asserted "the doc NAMES every site" with a whole-file `grep -qF`,
  # which passed the undercount red-proof: dropping spawn-presence.sh from the census still left the
  # path in the doc's PROSE (the history callout explains that exact miss by name), so the guard was
  # satisfied by the sentence describing the defect it was meant to catch. A census arm must read the
  # census, never the document — the same lesson as the anchor scoping below, in the other direction.
  # for the reason case 30 hit and this case re-hit HARDER: the doc necessarily mentions these same
  # paths in prose for other reasons (the refutation, the history callout, §6's protocol), so a
  # whole-file path scrape cannot tell "this file carries the figure" from "this file is discussed".
  # The first draft of this arm tried a keyword-proximity regex instead and SILENTLY PASSED its own
  # red-proof — the stale-entry direction did not red at all, because the fuzzy context match simply
  # failed to fire and `grep && { false; }` swallowed it. A delimited block is read exactly.
  listed="$(awk '/QUOTE-SITE CENSUS/{f=1;next} f&&/^    [a-z]/{print $1;next} f&&NF==0{next} f{exit}' "$DOC")"
  [ -n "$listed" ] \
    || { echo "the QUOTE-SITE CENSUS block in $DOC lost its shape — case 31 can no longer read the list it ratchets; restore the marker comment and the 4-space-indented one-path-per-line block"; false; }
  # ARM 1 — every site the TREE has must be IN THE CENSUS (the original defect: spawn-presence.sh).
  for f in $sites; do
    case "$(printf '%s\n' $listed)" in *"$f"*) ;; *)
      echo "$f quotes the refuted 2.5-5 figure and is MISSING from the QUOTE-SITE CENSUS in $DOC — a §6 PASS would leave it quoting a value this document refutes; that is exactly the miss this case was built from (spawn-presence.sh, 2026-08-26)"; false ;;
    esac
  done

  # ARM 2 — every site the CENSUS names must still carry it in the tree.
  for f in $listed; do
    grep -q '2\.5-5 runnable threads' "$REPO/$f" 2>/dev/null \
      || { echo "$DOC's QUOTE-SITE CENSUS lists $f, but the tree says it does not carry the 2.5-5 figure (deleted, or already re-derived) — a stale census sends a §6 PASS to edit a file that has nothing to edit"; false; }
  done

  # AND THE CITATIONS STAY CONTENT-ANCHORED. The list decayed while wearing line numbers that had
  # ALREADY drifted (capacity-admit.sh:698 -> 750, agent-teams-enforce.sh:220 -> 235). A line number
  # is a citation with an expiry date and no alarm; if a LIVE one comes back, this reds.
  #
  # SCOPED TO PROSE, NOT TO THE RECORD — and the scoping is load-bearing, not tidying. The doc's
  # blockquote callout necessarily QUOTES the two drifted anchors, because a reader who finds only
  # the correction cannot tell what was wrong; an unscoped grep convicts the doc for explaining
  # itself, which is the `guard-proxy-fails-in-both-directions` shape case 20 documents and case 30
  # solves with the same move (there by indentation, here by the `>` marker). Blockquote = history,
  # bare prose = a live instruction to a future session. Only the second kind may carry an anchor.
  live_anchor="$(grep -vE '^[[:space:]]*>' "$DOC" \
                   | grep -nE '(capacity-admit|agent-teams-enforce|spawn-presence)\.sh:[0-9]+' || true)"
  [ -z "$live_anchor" ] \
    || { echo "$DOC re-acquired a LIVE line-anchored citation into a shell file — cite by CONTENT (grep '2.5-5 runnable threads'); every line anchor this doc has ever carried had drifted by the time anyone re-read it: $live_anchor"; false; }
}
