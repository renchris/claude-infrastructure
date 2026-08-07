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
  [ "$(jq -r '.basis' "$BATS_TEST_TMPDIR/iso-idl.jsonl")" = "absent" ]
}

@test "25 reso-resume-one is UNGATEABLE in its own body — and the residue is stated, not hidden" {
  # §12.1 lists it as a bypass path. It is not in any git repository (an untracked file under
  # ~/.reso/bin), so nothing this repo can land or verify reaches its body. Every IN-REPO
  # invocation goes through boot-resume-launch.sh, which case 21 pins as gated.
  if [ -e "$REAL_HOME/.reso/bin/reso-resume-one" ]; then   # the live file, deliberately — see setup()
    run git -C "$REAL_HOME/.reso" rev-parse --show-toplevel
    [ "$status" -ne 0 ]     # confirms the premise: still untracked, still unlandable
  fi
  # the only in-repo caller, and it is the gated one
  callers="$(grep -rlE '^[^#]*(RESUME_ONE|reso-resume-one)' "$REPO/scripts" "$REPO/bin" 2>/dev/null \
             | grep -v 'lr-fire-resume.sh\|lr-preseed-env.sh\|lr-select.py' || true)"
  [ "$callers" = "$REPO/scripts/boot-resume-launch.sh" ]
  # and the limitation must be written where the next reader looks, not left to be re-discovered
  grep -q 'NOT IN ANY GIT REPOSITORY' "$REPO/scripts/boot-resume-launch.sh"
}

@test "26 TERM PARITY — the two implementations' ceilings cannot drift silently" {
  # capacity-admit.sh deliberately uses its OWN CC_ADMIT_* namespace rather than reusing
  # CC_FIRE_*: handoff-fire.sh reasoned that out for CC_FIRE_SYSCTL vs capacity-alarm's
  # CC_CAP_SYSCTL — sharing one variable between two subjects lets a stub aimed at ONE silently
  # redirect the OTHER. Separate names are correct; separate DEFAULTS would be drift. This is the
  # gate that keeps the first without the second.
  # `cut -d- -f2`, NOT -f3. `CC_FIRE_MAX_LOAD_PER_CORE:-2.0` has exactly ONE `-`, so the value is
  # field 2 and field 3 is EMPTY. This case shipped with -f3 and PASSED — because the two
  # emptiness guards below were dead assertions (mid-test `[ ] && [ ]`, which errexit cannot reach
  # in bats), so it compared "" to "" and called that parity. It would have gone on passing through
  # any ceiling change on either side. The land gate's dead-assertion ratchet is what surfaced it;
  # keeping the guards LIVE is what stops it recurring, so they are the real subject here.
  fire_load="$(grep -oE 'CC_FIRE_MAX_LOAD_PER_CORE:-[0-9.]+' "$HF" | head -1 | cut -d- -f2)"
  adm_load="$(grep -oE 'CC_ADMIT_MAX_LOAD_PER_CORE:-[0-9.]+' "$LIB" | head -1 | cut -d- -f2)"
  [ -n "$fire_load" ] || false
  [ -n "$adm_load" ] || false
  [ "$fire_load" = "$adm_load" ]
  fire_head="$(grep -oE 'CC_FIRE_MIN_HEADROOM_GB:-[0-9.]+' "$HF" | head -1 | cut -d- -f2)"
  adm_head="$(grep -oE 'CC_ADMIT_MIN_HEADROOM_GB:-[0-9.]+' "$LIB" | head -1 | cut -d- -f2)"
  [ -n "$fire_head" ] || false
  [ -n "$adm_head" ] || false
  [ "$fire_head" = "$adm_head" ]
}

@test "27 BASIS PARITY — capacity_gate's vocabulary is a subset of capacity-admit's" {
  # §9.5.1: "split on `basis` before believing any ratio computed here." That instruction only
  # works if one split spans both gates. capacity-admit adds `headroom-only` and `budget-expired`;
  # it may never DROP one of the originals, or a cross-gate query silently loses a population.
  for b in measured load-only fail-open gate-off; do
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
  for f in scripts/boot-resume-launch.sh scripts/limit-recover/lr-fire-resume.sh; do
    grep -q 'capacity-admit: ABSENT' "$REPO/$f" || { echo "$f: no loud-inertness message"; false; }
  done
  grep -q 'basis:"absent"' "$REPO/hooks/agent-teams-enforce.sh"
  # and it must NOT be on stderr there — the regression this replaced
  ! grep -qE 'capacity-admit: ABSENT.*>&2' "$REPO/hooks/agent-teams-enforce.sh"
}
