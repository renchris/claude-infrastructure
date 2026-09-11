#!/usr/bin/env bats
# cc-permission-harvest — the read-only half: partition the permission archive, decompose what is
# left to leaves, set-cover the uncovered ones into prefix rules, and REFUTE every candidate before
# proposing it.
#
# WHY THESE ARMS AND NOT A COUNT. The 2026-08-23 attempt at this produced nine allowlist proposals
# from bash-commands.log and an adversarial verifier refuted all nine: counts inflated 2x-174x, and
# two of them granted arbitrary code execution. The refutation was not that the tool was wrong about
# what it saw — it was that nothing in the tool could tell a prompt an allow rule COULD have cleared
# from one no rule of any form can reach. So the arms below are organised around the two partitions
# that make a proposal defensible, and each gate gets an arm that would go red if the gate were
# deleted:
#
#   STRUCTURAL first — `$( )`, backticks, subshells, `{ }`, `&`, redirection, heredocs, multiple
#   `cd`, `cd`+`git` are hard-gated in the harness (docs/research/permission-matcher-truth-2026-08-20
#   §2). 45.4% of real prompts are these. A rule proposed off them is a rule that clears nothing.
#
#   HOOK-RAISED next — 1,367 of 1,368 curl-only "gap" rows were curl-gate asks. A hook runs BEFORE
#   rules, so an allow rule cannot clear a hook-raised prompt; counting them re-inflates everything.
#
# The fixture is generated, never literal: see tests/fixtures/permission-harvest/mkfixture.py for
# why (dates rot by calendar; the transcript's rejection text carries an apostrophe that a printf
# stub cannot survive).
#
# Harness laws, following tests/cc-permission-prune.bats: L1 HOME is redirected into the test tmpdir
# and every store the tool reads resolves under it, so the operator's real archive/settings are
# never an input; L2 each arm keys on the failure-DISTINCT quantity (the gate CODE, not merely the
# absence of a rule — absence is also what a crash produces); L3 `[ ]`, `run`, and `[[ ]] || false`
# — never a bare `[[ ]]` or `! cmd` mid-body (both are errexit-exempt and would pass while failing);
# L4 gates are asserted from the JSON, and the human report only for its section headers and the
# literal `proposed=0` line; L5 where a head trips MORE than one gate (`curl` is hook-owned AND
# auto-dropped; bare `git` is ARG_EXEC, HOOK_OWNED and a collision) the arm keys on that gate's OWN
# verdict in the gates map the plan says every candidate carries, never on the single `code`, whose
# choice among several true answers is the table's order and not this suite's business; the
# code-level arms use the fixture heads that trip exactly one gate.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HARVEST="$REPO/bin/cc-permission-harvest"
  FIXD="$REPO/tests/fixtures/permission-harvest"
  MK="$FIXD/mkfixture.py"
  Q="$FIXD/qjson.py"
  OUT="$BATS_TEST_TMPDIR/out"
  PROP="$OUT/latest.json"
  mkfix base
  # The archive seam cc-permission-beacon.sh and cc-permission-audit already share. Pinned even
  # though HOME is redirected: it is the one store whose ABSENCE has to be constructible, and an
  # arm that builds it by unsetting a seam is not the same test as one that points the seam at a
  # directory that is not there.
  export CC_PERMARCHIVE_DIR="$HOME/.claude/autonomy/permission-archive"
  # The runner's own session leaks two things a tool could read past the redirected HOME: the
  # config dir the operator's shell points at, and the out-dir seam the weekly wrapper sets. Neither
  # may reach the fixture.
  unset CLAUDE_CONFIG_DIR CC_PERMHARVEST_OUT
}

mkfix() { # $1 = base|covered|decayed|dark|empty
  python3 "$MK" "$HOME" --scenario "$1"
}

have_tool() { [ -f "$HARVEST" ] || skip "bin/cc-permission-harvest not present (unit C2)"; }

# One 30-day JSON run into $OUT. Every arm that reads $PROP calls this first, so a tool that exits
# non-zero fails the arm HERE rather than downstream on a missing file.
run_json() {
  have_tool
  run python3 "$HARVEST" 30 --json --out "$OUT"
  [ "$status" -eq 0 ]
  [ -f "$PROP" ]
}

q() { python3 "$Q" "$PROP" "$@"; }

# How many LINES of the last run's report are the null-result line — a line whose first token is
# exactly `proposed=0`. Anchored, never a substring search: the BLIND banner reads "this is NOT an
# all-clear and NOT proposed=0", so a substring test convicts the correct tool of the very defect
# the banner exists to deny, and does it in the direction that HIDES a real regression (a tool that
# silently switched the banner for a null line would still contain the substring). The report is
# written to a file rather than piped, because `producer | grep` under pipefail is what
# scripts/pipefail-sigpipe-lint.sh refuses.
proposed_zero_lines() {
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/report.txt"
  run grep -cE '^[[:space:]]*proposed=0([[:space:]]|$)' "$BATS_TEST_TMPDIR/report.txt"
}

# ── THE ANCHOR — the one arm that must never skip ────────────────────────────────────────────────
# Every other arm skips when the binary is absent, which is the house pattern (cc-permission-prune,
# cc-permission-audit) and is right: a suite whose subject has not landed should not manufacture a
# red for every gate. But a suite that skips ENTIRELY is a vacuous green, and the whole point of
# this file is that a silent all-clear is the failure mode. This arm is the floor.
@test "the harvester exists and is executable" {
  [ -f "$HARVEST" ]
  [ -x "$HARVEST" ]
}

# ── THE PROPOSAL — what the loop is FOR ──────────────────────────────────────────────────────────

@test "an approved simple prompt becomes the prefix rule Bash(gh pr view:*)" {
  run_json
  # The sub-verb head, not the 1-token verb: `Bash(gh:*)` would also cover these rows, and it is
  # exactly the over-wide grant B1-2 refuses on purpose. The fixture makes the difference
  # observable — a Stop-refused `gh pr merge 9 --squash` row sits under the same verb.
  run q has "Bash(gh pr view:*)"
  [ "$status" -eq 0 ]
  run q receipt "Bash(gh pr view:*)" sessions
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
  run q receipt "Bash(gh pr view:*)" weeks_present
  [ "$output" -ge 2 ]
  run q receipt "Bash(gh pr view:*)" distinct_projects
  [ "$output" -ge 2 ]
}

@test "the 1-token verb head is not proposed when a refused row sits under it" {
  run_json
  run q has "Bash(gh:*)"
  [ "$status" -ne 0 ]
}

@test "an approved compound row is cleared by covering its ONE uncovered leaf" {
  run_json
  # `cd /x && pnpm test && gh pr view 7`: cd and pnpm test are fleet-covered, so the row clears the
  # moment `gh pr view` is picked. The count is EXACT, recomputed from the fixture: three simple
  # approved rows + this compound = 4 approved, + the SessionEnd `gh pr view 33` = 5 total. A tool
  # that only counts whole-command matches reads 4/3; one whose hook join swallows a same-session
  # row (the fixture's first defect — every row of a day shared one timestamp) reads 4/3 too.
  run q receipt "Bash(gh pr view:*)" prompts_cleared.total
  [ "$status" -eq 0 ]
  [ "$output" -eq 5 ]
  run q receipt "Bash(gh pr view:*)" prompts_cleared.approved
  [ "$output" -eq 4 ]
}

@test "a SessionEnd abandoned row does not block the proposal a Stop row would" {
  run_json
  # 16 of 23 real "refused" rows are SessionEnd — nobody answered. Treating silence as a refusal
  # would kill this proposal; the fixture carries an abandoned `gh pr view 33` row for exactly that.
  run q has "Bash(gh pr view:*)"
  [ "$status" -eq 0 ]
  run q get resolution.abandoned
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ── THE GATES — one arm each, keyed on the CODE ──────────────────────────────────────────────────

@test "a leaf the operator refused at a Stop prompt refuses its head with REFUSED_PROMPT_COLLISION" {
  run_json
  # `gh pr merge 9 --squash` was Stop-resolved. Auto-approving its verb inverts a recorded human
  # decision, so every head that leaf carries is refused — `gh` and `gh pr` both — while
  # `gh pr view`, which no refused leaf carries, is untouched. Both wider heads outrank the
  # sub-verb on rows covered, so a tool that skipped this gate would PROPOSE one of them.
  run q code "Bash(gh pr:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "REFUSED_PROMPT_COLLISION" ]
  run q code "Bash(gh:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "REFUSED_PROMPT_COLLISION" ]
  run q gate "Bash(gh pr view:*)" REFUSED_PROMPT_COLLISION
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "the 2026-08-23 refuted set Bash(bash:*) is refused with ACE_CLASS" {
  run_json
  run q code "Bash(bash:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "ACE_CLASS" ]
}

@test "Bash(python3:*) is refused with ACE_CLASS" {
  run_json
  run q code "Bash(python3:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "ACE_CLASS" ]
}

@test "a bare curl candidate is refused on AUTO_MODE_DROP" {
  run_json
  # The two unattributed curl rows exist so a curl candidate survives the hook_raised partition and
  # actually reaches the gates; without them the arm would pass over a candidate never generated.
  # `curl` is ALSO hook-owned (curl-gate.py) and the plan's table lists HOOK_OWNED first, so the
  # single `code` may legitimately name either (L5) — the gate's own verdict is what this keys on;
  # the code-level assertion belongs to the `aws` arm below.
  run q has "Bash(curl:*)"
  [ "$status" -ne 0 ]
  run q gate "Bash(curl:*)" AUTO_MODE_DROP
  [ "$status" -eq 0 ]
  [ "$output" != "pass" ]
}

@test "Bash(aws:*) is refused with AUTO_MODE_DROP and nothing else" {
  run_json
  # `aws` in bare form is on auto mode's dropped list, owned by no hook, named by no ask or deny,
  # and refused at no prompt — the one fixture head that can only die here.
  run q code "Bash(aws:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "AUTO_MODE_DROP" ]
}

@test "Bash(git:*) under ask Bash(git push:*) is refused, and ASK_DENY_COLLISION is among its verdicts" {
  run_json
  # Bidirectional at 1 token: `git` is a prefix of the ask content `git push`. Bare `git` also
  # trips ARG_EXEC (it reaches rebase -x) and HOOK_OWNED (it reaches git push), so the single code
  # may name any of the three (L5); the gate's own verdict is the assertion.
  run q has "Bash(git:*)"
  [ "$status" -ne 0 ]
  run q gate "Bash(git:*)" ASK_DENY_COLLISION
  [ "$status" -eq 0 ]
  [ "$output" != "pass" ]
  # …and the ask-hit leaf itself never becomes a rule at any token count.
  run q head-proposed "git push"
  [ "$status" -ne 0 ]
}

@test "Bash(zzsvc:*) is refused with ASK_DENY_COLLISION against ask Bash(zzsvc restart:*)" {
  run_json
  # The unambiguous witness: zzsvc is on no ACE, hook or auto-drop list and was refused at no
  # prompt, so the 1-token head can die on the collision alone.
  run q code "Bash(zzsvc:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "ASK_DENY_COLLISION" ]
  # …and the DIRECTION is what the pair proves: a sub-verb head the ask content does not prefix
  # survives it (one-directional at >=2 tokens), so the collision refuses the verb and not its family.
  run q gate "Bash(zzsvc status:*)" ASK_DENY_COLLISION
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "Bash(git stash:*) passes the collision carve-out for a 2-token sub-verb head" {
  run_json
  # The legitimate case the bidirectional rule would destroy: `git stash` under ask
  # `Bash(git stash drop:*)`. One-directional applies only to a >=2-token sub-verb head, so this
  # passes and `Bash(git:*)` above does not — the pair is what makes the direction observable.
  run q gate "Bash(git stash:*)" ASK_DENY_COLLISION
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "Bash(git rebase:*) is refused with ARG_EXEC" {
  run_json
  # MEASURED: `git rebase -x 'touch MARK' --root` executes. A 2-token head does not pin past the
  # exec-bearing argument, so the prefix is a grant over arguments not yet typed.
  run q code "Bash(git rebase:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "ARG_EXEC" ]
}

@test "Bash(rm -f:*) is refused on FLAG_HEAD" {
  run_json
  # `rm -f` is the bare verb in disguise, and it inherits rm's HOOK_OWNED verdict too (L5): key on
  # the gate, and on the rule not existing.
  run q has "Bash(rm -f:*)"
  [ "$status" -ne 0 ]
  run q gate "Bash(rm -f:*)" FLAG_HEAD
  [ "$status" -eq 0 ]
  [ "$output" != "pass" ]
}

@test "Bash(rm:*) is refused with HOOK_OWNED" {
  run_json
  # validate-bash.sh's rm guard runs BEFORE rules, so this rule would claim a clearance that cannot
  # happen. HOOK_OWNED and FLAG_HEAD are different heads, which is why both arms exist.
  run q code "Bash(rm:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "HOOK_OWNED" ]
}

@test "a do-headed loop leaf never mints a rule" {
  run_json
  # F19's splitter saves loop and test leaves as exact acceptances — 73 of them exist — and
  # `Bash(do:*)` is nonsense that passes every other gate. Assert the mint, not the code: the
  # failure this prevents is the rule EXISTING.
  run q head-proposed "do"
  [ "$status" -ne 0 ]
  run q has "Bash(do:*)"
  [ "$status" -ne 0 ]
}

@test "a test-bracket leaf reaches the gates and is refused on SHELL_KEYWORD" {
  run_json
  # `do` is peeled by the splitter and never becomes a head, so the arm above can only prove a
  # non-mint. `[` is NOT peeled: `[ -f /tmp/zz-flag ] && ls -la /tmp` decomposes to a test leaf and
  # a fleet-covered `ls`, so the head `[` would clear two rows if picked — a real candidate, and
  # the one keyword head a cover-driven tool has to evaluate. (It trips TOKEN_CAP too, L5.)
  run q gate "Bash([:*)" SHELL_KEYWORD
  [ "$status" -eq 0 ]
  [ "$output" != "pass" ]
  # No shell grammar reaches the proposal under any code. Every item is quoted: an unquoted `do`
  # after `in` is the KEYWORD to bash, and the loop does not parse.
  for h in "do" "done" "then" "fi" "else" "elif" "for" "while" "until" "if" "[" "[[" \
           "case" "esac" "function" "select" "time"; do
    run q head-proposed "$h"
    [ "$status" -ne 0 ]
  done
}

@test "a path-ful head is refused with PATH_BOUND" {
  run_json
  run q code "Bash(/tmp/permharvest-fx/bin/zzdeploy:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "PATH_BOUND" ]
}

@test "a one-prompt candidate is refused with MIN_EVIDENCE" {
  run_json
  # No escape clause, not even for an approved row: a single acceptance the operator chose NOT to
  # persist is a one-shot wearing a prefix.
  run q has "Bash(shellcheck:*)"
  [ "$status" -ne 0 ]
  run q code "Bash(shellcheck:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "MIN_EVIDENCE" ]
}

@test "a repo-relative script head is refused for a fleet target" {
  run_json
  # PATH_BOUND is scope-aware: at fleet scope `./scripts/zzlocal.sh` names whatever sits at that
  # path in ANY cwd. No proposed rule may carry that head at ANY token count (`run`, `run --dry`);
  # the project-local half of the rule is the consolidation arm below.
  run q proposed
  [ "$status" -eq 0 ]
  [[ "$output" != *"zzlocal.sh"* ]] || false
  run q gate "Bash(./scripts/zzlocal.sh:*)" PATH_BOUND
  [ "$status" -eq 0 ]
  [ "$output" != "pass" ]
}

# ── THE PARTITIONS — what makes the counts defensible ────────────────────────────────────────────

@test "structural rows land in STRUCTURAL and never inside a candidate's count" {
  run_json
  for kind in command_substitution backtick process_substitution subshell command_group \
              background redirect_file heredoc multi_cd cd_git_compound; do
    run q get "structural.by_kind.$kind"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
  done
  run q get buckets.structural
  [ "$status" -eq 0 ]
  [ "$output" -ge 10 ]
  # …and no rule is proposed off a structural row's verb. `sleep` and `diff` appear ONLY in
  # structural rows, so a proposal naming either proves the partition did not run first.
  run q head-proposed "sleep"
  [ "$status" -ne 0 ]
  run q head-proposed "diff"
  [ "$status" -ne 0 ]
}

@test "a bash -c row is ACE, not structural — no rule is minted and no structural kind is charged" {
  run_json
  # B2-6 moved `bash_c` out of the structural partition: the harness refuses it for the
  # interpreter, not for shell grammar, and the head dies on ACE_CLASS like every other bash. A
  # tool that still charges it as structural under-reports the ACE share by exactly those rows.
  run q get structural.by_kind.bash_c
  if [ "$status" -eq 0 ]; then [ "$output" -eq 0 ]; fi
  run q code "Bash(bash:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "ACE_CLASS" ]
  run q head-proposed "bash -c"
  [ "$status" -ne 0 ]
}

@test "unverified structural kinds are reported apart from the headline" {
  run_json
  run q get structural.unverified_kinds
  [ "$status" -eq 0 ]
  [[ "$output" == *"function_def"* ]] || false
  [[ "$output" == *"case"* ]] || false
}

@test "a curl row joined to a curl-gate ask lands in hook_raised, never in a candidate" {
  run_json
  run q get hook_raised.by_hook.curl-gate
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
  # The joined rows name api.example.test; the unjoined ones name cdn.example.test. If the join
  # were missing, hook_raised would be 0 and the api rows would swell the curl candidate instead.
  # EXACTLY 2, not "at least": a join that also caught the deny row and a `gh pr view` sharing the
  # session read 5 here and passed a `-ge 2` — the over-wide direction is the one that re-inflates.
  run q get buckets.hook_raised
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "the buckets are MECE and sum to inputs.rows" {
  run_json
  run q bucketsum
  [ "$status" -eq 0 ]
  rows="${output%% *}"
  sum="${output##* }"
  [ "${rows#rows=}" = "${sum#sum=}" ]
  [ "${rows#rows=}" -gt 0 ]
}

@test "a row whose leaves are all covered lands in hook_or_classifier, not in a rule gap" {
  run_json
  run q get buckets.hook_or_classifier
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ]
  run q head-proposed "pnpm test"
  [ "$status" -ne 0 ]
}

@test "a per-cwd local rule suppresses a false fleet gap" {
  run_json
  # `zzfmt check` has 3 rows / 3 sessions / 3 weeks — it clears MIN_EVIDENCE outright. The ONLY thing
  # keeping it out of the proposal is project A's own settings.local.json, so a tool that reads
  # fleet rules alone proposes it and this arm goes red.
  #
  # THE VERB IS SYNTHETIC ON PURPOSE (was `pnpm lint` until 2026-09-09). `npm`/`yarn`/`pnpm` joined
  # ACE_VERBS that day, and ACE keys on the head's FIRST token, so a pnpm-headed subject would be
  # refused by ACE whether or not the per-cwd rule was read at all — the arm would have kept
  # passing over a broken cwd resolver. A control whose subject is also caught by a sibling gate
  # measures the sibling. (memory: sibling-guard-makes-the-fixture-vacuous)
  run q head-proposed "zzfmt check"
  [ "$status" -ne 0 ]
}

@test "an ask-rule row lands in ask_hit and a deny-rule row in deny_hit" {
  run_json
  run q get buckets.ask_hit
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run q get buckets.deny_hit
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "a row the beacon truncated lands in the truncated bucket" {
  run_json
  run q get buckets.truncated
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "a row whose cwd no longer exists is counted as gap_unrecoverable" {
  run_json
  # 40.9% of real rows have a cwd that is gone, so their local rules cannot be reconstructed. They
  # are excluded from MIN_EVIDENCE counting rather than silently credited to the fleet.
  run q get buckets.gap_unrecoverable
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "an auto-dropped fleet rule does not cover its own command in mode auto" {
  run_json
  run q get mode
  [ "$status" -eq 0 ]
  [ "$output" = "auto" ]
  # `Bash(python3:*)` IS in the fixture fleet allow list. In mode auto it is inert, so `python3
  # scripts/zzreport.py` is an uncovered leaf and mints a candidate — which then dies on ACE_CLASS.
  # A tool that credited the dropped rule would generate no candidate and `code` would be MISSING.
  run q code "Bash(python3:*)"
  [ "$status" -eq 0 ]
  [ "$output" = "ACE_CLASS" ]
}

# ── RESOLUTION — proven, never inferred ──────────────────────────────────────────────────────────

@test "a transcript carrying the rejection text marks its row denied" {
  run_json
  # ~19 genuine denials hide inside `collateral` with no signature to prove them. The transcript
  # tool_result is the only oracle that separates them from a collateral clear.
  run q get resolution.denied
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "resolution splits approved, refused and abandoned rather than folding them" {
  run_json
  run q get resolution.approved
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run q get resolution.refused
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  run q get resolution.abandoned
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

# ── THE WIDENING RECEIPT — corpus by RECORD, never by LINE ───────────────────────────────────────

@test "a multi-line corpus record counts once, so widening.count is 1 and not 5" {
  run_json
  # 82% of the real log's LINES are continuation fragments (1,636,089 lines vs 286,466 records).
  # The fixture's heredoc record carries four continuation lines that each start with `gh pr view`;
  # a line-based counter reports 5 for a head that occurred once.
  run q receipt "Bash(gh pr view:*)" widening.count
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]
}

@test "the rotated .gz corpus is read — records from both files are counted" {
  run_json
  run q get inputs.corpus_records
  [ "$status" -eq 0 ]
  [ "$output" -eq 5 ]
}

@test "the corpus is labelled as the pass-through record it is, never as a prompt count" {
  run_json
  run q get inputs.corpus_scope
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate-bash"* ]] || false
}

# ── CONSOLIDATION — the loop's largest denominator, and it is PROJECT-LOCAL ───────────────────────

@test "a project-local cluster of exact entries proposes its prefix into that same file" {
  run_json
  run q consolidation "gh pr view"
  [ "$status" -eq 0 ]
  [[ "$output" == *"proj-a/.claude/settings.local.json"* ]] || false
  [[ "$output" == *"Bash(gh pr view:*)"* ]] || false
}

@test "consolidation shadows the exact entries a proposed prefix covers" {
  run_json
  run q cons-shadows "gh pr view"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Bash(gh pr view 12 --json state)"* ]] || false
  [[ "$output" == *"Bash(gh pr view 7 --json title)"* ]] || false
}

@test "a repo-relative script head passes PATH_BOUND into the project file it came from" {
  run_json
  # The scope carve-out: `./scripts/zzlocal.sh` is a location at fleet scope and a program inside
  # the repo that accepted it. Same head, opposite verdicts — the fleet half is asserted above.
  run q cons-gate "zzlocal.sh" PATH_BOUND
  [ "$status" -eq 0 ]
  [ "$output" = "pass" ]
}

@test "ssh -i lands in unretirable as a 3-entry cluster" {
  run_json
  # ~60% of the acceptance corpus can never be retired, and reporting it as residue is what stops
  # the absent 60% from reading as a clean sweep. Count and reason are separate arms so a red
  # says which half is wrong.
  run q unretirable-entries "ssh -i"
  [ "$status" -eq 0 ]
  [ "$output" -eq 3 ]
  run q consolidation "ssh -i"
  [ "$status" -ne 0 ]
}

@test "the ssh -i residue names AUTO_MODE_DROP as its reason" {
  run_json
  run q unretirable "ssh -i"
  [ "$status" -eq 0 ]
  [ "$output" = "AUTO_MODE_DROP" ]
}

# ── THE NULL RESULT AND THE BLIND STATES — three outcomes, never two ─────────────────────────────

@test "a run that proposes nothing exits 0 and prints proposed=0 with its denominator" {
  have_tool
  mkfix covered
  run python3 "$HARVEST" 30
  [ "$status" -eq 0 ]
  # The denominator is what separates "nothing to propose" from "nothing was read".
  [[ "$output" == *"rows_in_window"* ]] || false
  proposed_zero_lines
  [ "$output" -eq 1 ]
}

@test "a run that proposes nothing still emits a schema-1 document with an empty proposed list" {
  have_tool
  mkfix covered
  run python3 "$HARVEST" 30 --json --out "$OUT"
  [ "$status" -eq 0 ]
  run q get schema
  [ "$output" = "1" ]
  run q get proposed
  [ "$output" = "[]" ]
}

@test "a missing archive exits 3 and says BLIND" {
  have_tool
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/nope"
  run python3 "$HARVEST" 30
  [ "$status" -eq 3 ]
  [[ "$output" == *"BLIND"* ]] || false
  proposed_zero_lines
  [ "$output" -eq 0 ]
}

@test "an unreadable archive file exits 3 and says BLIND" {
  have_tool
  # UID-INDEPENDENT BY CONSTRUCTION: a DIRECTORY named `*.jsonl` matches the glob and raises
  # IsADirectoryError on open(), where a chmod 000 is simply ignored under uid 0 and the arm would
  # read a healthy tree (tests/cc-permission-audit.bats D3 records the land this blocked).
  mkdir -p "$CC_PERMARCHIVE_DIR/2026-07.jsonl"
  run python3 "$HARVEST" 30
  [ "$status" -eq 3 ]
  [[ "$output" == *"BLIND"* ]] || false
}

@test "a 4-day-old heartbeat with no rows in window exits 3 as oracle-dark, not proposed=0" {
  have_tool
  mkfix dark
  run python3 "$HARVEST" 30
  [ "$status" -eq 3 ]
  [[ "$output" == *"BLIND"* ]] || false
  # The whole point: a dead beacon must not read as a healthy null. A `proposed=0` line here would
  # be a true sentence about an empty window and a false one about the machine.
  proposed_zero_lines
  [ "$output" -eq 0 ]
}

# ── THE DOCUMENT — schema 1, asserted key by key ─────────────────────────────────────────────────

@test "the emitted JSON validates against schema 1" {
  run_json
  run q get schema
  [ "$output" = "1" ]
  for key in generated_utc tool.sha rules_snapshot mode apply_hint \
             inputs.archive_dir inputs.rows inputs.rows_in_window inputs.sessions_in_window \
             inputs.oracle_age_s inputs.window_days inputs.settings_files inputs.corpus_records \
             inputs.corpus_scope inputs.blind \
             buckets.structural buckets.hook_raised buckets.ask_hit buckets.deny_hit \
             buckets.truncated buckets.hook_or_classifier buckets.rule_gap \
             buckets.gap_unrecoverable \
             resolution.approved resolution.refused resolution.denied resolution.abandoned \
             resolution.collateral resolution.unknown \
             structural.by_kind structural.unverified_kinds structural.top_verbs \
             hook_raised.by_hook proposed refused consolidation unretirable; do
    run q get "$key"
    [ "$status" -eq 0 ]
  done
}

@test "every proposed rule carries a verdict for every gate" {
  run_json
  for gate in ACE_CLASS ARG_EXEC FLAG_HEAD SHELL_KEYWORD HOOK_OWNED AUTO_MODE_DROP \
              ASK_DENY_COLLISION REFUSED_PROMPT_COLLISION MIN_EVIDENCE PATH_BOUND TOKEN_CAP; do
    run q gate "Bash(gh pr view:*)" "$gate"
    [ "$status" -eq 0 ]
    [ "$output" = "pass" ]
  done
}

@test "every settings file discovered carries its scope" {
  run_json
  run q get inputs.settings_files.0.scope
  [ "$status" -eq 0 ]
  [[ "$output" == "fleet" || "$output" == "project" || "$output" == "worktree" ]] || false
  run q get inputs.settings_files.0.allow
  [ "$status" -eq 0 ]
  # Five fleet forks and project A's local file: six discovered, and the fleet count is the one
  # the apply path writes as a SET or silently lands on one account.
  run q scopes
  [ "$status" -eq 0 ]
  [[ "$output" == *"fleet=5"* ]] || false
  [[ "$output" == *"project=1"* ]] || false
}

@test "inputs.rows is the fixture's row count and every row is inside the 30-day window" {
  run_json
  # The denominator, checked against the generator's own manifest: a reader that drops a row it
  # cannot parse or double-counts a session file moves this number, and every share downstream is
  # a fraction of it.
  want="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["archive_rows"])' \
          "$HOME/fixture-manifest.json")"
  run q get inputs.rows
  [ "$status" -eq 0 ]
  [ "$output" -eq "$want" ]
  run q get inputs.rows_in_window
  [ "$output" -eq "$want" ]
  run q get inputs.sessions_in_window
  [ "$output" -eq 4 ]
  run q get inputs.window_days
  [ "$output" -eq 30 ]
  run q get inputs.blind
  [ "$output" = "[]" ]
}

@test "resolution carries an unknown row — the honest default, never inferred into approved" {
  run_json
  run q get resolution.unknown
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
}

@test "--out writes one UTC-named proposal and latest.json as a byte-identical copy" {
  run_json
  run bash -c 'ls "$1"/proposal-*.json' _ "$OUT"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  cmp -s "${lines[0]}" "$PROP"
}

@test "no proposed rule exceeds the prefix form: at most 3 tokens, no wildcard inside the head" {
  run_json
  # TOKEN_CAP, asserted on the OUTPUT rather than on a refused code: the form that survives is the
  # one that is whitespace-tolerant, survives the auto-mode drop and composes across compounds.
  run q proposed
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 1 ]
  for rule in "${lines[@]}"; do
    [[ "$rule" == "Bash("*":*)" ]] || false
    head="${rule#Bash(}"; head="${head%:\*)}"
    read -r -a toks <<<"$head"
    [ "${#toks[@]}" -le 3 ]
    [[ "$head" != *"*"* && "$head" != *"?"* && "$head" != *"["* ]] || false
  done
}

@test "the human report names its sections rather than dumping the JSON" {
  run_json
  run python3 "$HARVEST" 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"STRUCTURAL"* ]] || false
  [[ "$output" == *"PROPOSED"* ]] || false
  [[ "$output" == *"REFUSED"* ]] || false
  [[ "$output" == *"CONSOLIDATION"* ]] || false
}

# ── COMPLETENESS ARMS added 2026-09-09 (review). Each one names a property the plan asserts and
#    that NO arm could previously fail on: the fixture never built the shape that exercises it.

@test "a backup FORK of a config dir is not a discovery target — the glob reaches it, the guard drops it" {
  # §3.3 "fleet = every discovered ~/.claude*/settings.json (backup/`pre-` names excluded)". The
  # exclusion was basename-only, and every path in both discovery populations has basename
  # `settings.json` — so the guard governed an EMPTY population and deleting it changed nothing.
  # `~/.claude.bak/` and `~/.claude-pre-cutover/` DO match the production glob and DO classify as
  # `fleet`, i.e. `--apply` would rewrite the operator's own snapshot. Both halves asserted: the
  # backup forks are absent from `settings_files`, and the five real forks are still all present.
  have_tool
  mkdir -p "$HOME/.claude.bak" "$HOME/.claude-pre-cutover"
  cp "$HOME/.claude/settings.json" "$HOME/.claude.bak/settings.json"
  cp "$HOME/.claude/settings.json" "$HOME/.claude-pre-cutover/settings.json"
  run_json
  run q get inputs.settings_files
  [ "$status" -eq 0 ]
  [[ "$output" != *".claude.bak"* ]] || false
  [[ "$output" != *"claude-pre-cutover"* ]] || false
  [[ "$output" == *"$HOME/.claude/settings.json"* ]] || false
  [[ "$output" == *"$HOME/.claude-next3/settings.json"* ]] || false
  run q scopes
  [ "$status" -eq 0 ]
  [[ "$output" == "fleet=5 "* ]] || false
}

@test "the collision set is the UNION of fleet AND project deny/ask — a project ask refuses a fleet candidate" {
  # §3.2 ASK_DENY_COLLISION: "the collision set (= UNION of every discovered deny/ask, fleet AND
  # project files)". The fixture's only project file carries deny:[] ask:[], so every collision arm
  # in this suite resolved against the FLEET half alone and a regression narrowing the union to
  # fleet-only stayed green. `zzloopcmd` is a 1-token head, so the gate is bidirectional there.
  have_tool
  python3 - "$HOME/Development/proj-a/.claude/settings.local.json" <<'PY'
import json, sys
p = sys.argv[1]
doc = json.load(open(p))
doc["permissions"]["ask"] = ["Bash(zzloopcmd --danger:*)"]
doc["permissions"]["deny"] = ["Bash(zzloopcmd --wipe:*)"]
json.dump(doc, open(p, "w"), indent=2)
PY
  run_json
  run q get inputs.collision_set
  [ "$status" -eq 0 ]
  [[ "$output" == *'"deny": 2'* || "$output" == *'"deny":2'* ]] || false
  [[ "$output" == *'"ask": 4'* || "$output" == *'"ask":4'* ]] || false
  # …and it is not merely counted: the project ask actually REFUSES the candidate it governs.
  run q gate "Bash(zzloopcmd:*)" ASK_DENY_COLLISION
  [ "$status" -eq 0 ]
  [ "$output" != pass ]
  run q code "Bash(zzloopcmd:*)"
  [ "$output" = ASK_DENY_COLLISION ]
}

@test "the five fleet forks are read as a UNION, not as one representative copy" {
  # mkfixture writes ONE object into all five forks, so every fork is byte-identical and a tool
  # that read only the first would produce an identical proposal — the read-side fan-out was
  # untestable. Wave A2 measured the operator's real five forks as DIFFERING by one entry.
  # The two divergences run in SEPARATE passes on purpose: `classify_all_shell` in ANY fork makes
  # every Bash allow rule inert in auto mode (that is what the tool warns about), which would mask
  # the coverage half — mixing them into one run proves neither.
  have_tool
  # (a) COVERAGE — the rule lives in exactly ONE fork and must cover the whole fleet's leaves.
  run_json
  run q has "Bash(zzloopcmd:*)"
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["permissions"]["allow"]=list(d["permissions"]["allow"])+["Bash(zzloopcmd:*)"]; json.dump(d, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude-next2/settings.json"
  run_json
  run q has "Bash(zzloopcmd:*)"
  [ "$status" -ne 0 ]
  # (b) PER-FILE FIELDS — classify_all_shell is reported per FILE, never folded from copy 1.
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); d["autoMode"]={"classifyAllShell": True}; json.dump(d, open(sys.argv[1],"w"), indent=2)' "$HOME/.claude-next3/settings.json"
  run_json
  run python3 -c 'import json,sys; rows=json.load(open(sys.argv[1]))["inputs"]["settings_files"]; on=sorted(r["path"] for r in rows if r.get("classify_all_shell")); print(len(rows), len(on), on[0] if on else "-")' "$PROP"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | awk '{print $1}')" -ge 6 ]
  [ "$(printf '%s' "$output" | awk '{print $2}')" = 1 ]
  [[ "$output" == *".claude-next3/settings.json" ]] || false
  # …and its fleet-wide consequence is WARNED about, naming the one file that set it
  run q get inputs.warnings
  [ "$status" -eq 0 ]
  [[ "$output" == *"classifyAllShell"* ]] || false
  [[ "$output" == *".claude-next3/settings.json"* ]] || false
}

@test "the consolidation header reports the NET, and a prefix never widens the list for no shrink" {
  # The gross "N prefix(es) retiring M entr(ies)" answers a different question from the one a reader
  # asks: a prefix that is not already present COSTS an allow entry, so the number that says whether
  # the list shrank is M − (prefixes added). On the real 30-day proposal the gross read "7 retiring
  # 15" over a true net of 8, because `dead_entries` could not see `literal == base`.
  run_json
  run python3 "$HARVEST" 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"net -"* ]] || false
  # the arithmetic, recomputed from the document the header summarises
  run python3 - "$PROP" <<'PY'
import json, sys
cons = json.load(open(sys.argv[1]))["consolidation"]
retires = sum(len(c["shadows"]) for c in cons)
adds = len([c for c in cons if not c.get("present")])
print("%d %d %d" % (len(cons), retires, adds - retires))
# every proposed prefix retires at least as many entries as it adds
print("OK" if all(len(c["shadows"]) >= 1 for c in cons) else "WIDENS")
PY
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = OK ]
  net="$(printf '%s' "${lines[0]}" | awk '{print $3}')"
  [ "$net" -lt 0 ]
  run bash -c 'printf "%s\n" "$1" | grep -c -- "net $2 allow"' _ "$(python3 "$HARVEST" 30)" "$net"
  [ "$output" -eq 1 ]
}

@test "the read-only pipeline is BOUNDED: past CC_PERMHARVEST_MAX_S it exits 6 and writes no partial proposal" {
  # scripts/permission-harvest-run.sh runs this from launchd with no bound of its own, and
  # timeout(1) is not on the stock macOS floor — so the bound has to live in the interpreter. On the
  # live stores the same invocation measured 1,045 s, which is 52x cc-premise's 20 s probe bound and
  # long enough to hold the wrapper's lock past the fleet board's staleness window.
  #
  # WHY 0.001 AND NOT THE 0.01 THIS ARM SHIPPED WITH, AND WHY THE MARGIN IS NOW ASSERTED. The cut
  # can only fire while the pipeline is STILL RUNNING, so this arm carries an unstated precondition
  # — `pipeline runtime > bound` — and that runtime is pure-Python CPU (set_cover / rule_matches_leaf
  # dominate its profile; there is no I/O or subprocess term to speak of on this fixture). The
  # margin is therefore a bet on CORE SPEED, and it erodes on a FASTER, QUIETER box rather than on a
  # loaded one. That is the direction no triage looks in: every load-keyed diagnosis in this repo
  # reads "the box was too busy", while this arm fails when the box was too QUICK — and it fails as
  # `status 0` with a proposal written, i.e. byte-for-byte how a DELETED deadline would read.
  # Measured 2026-09-11 on a cloud vCPU against this fixture: `_pipeline` 30.3-35.5 ms over 7 runs,
  # and a bound sweep flips the verdict between 0.030 s (8/8 exit 6) and 0.040 s (1/8) — so 0.01 s
  # left a 3.5x margin, which a ~3x faster single core closes. 0.001 s is ~31x on the same reading,
  # and the third arm below RE-DERIVES that ratio at run time so an erosion goes red NAMING itself
  # instead of a working deadline being reported as a broken one. `bin/cc-permission-harvest`'s own
  # `_deadline_s` docstring already specified 0.001 as the exercisable figure; this arm had drifted
  # 10x off its subject's spec, and nothing measured the gap.
  have_tool
  run env CC_PERMHARVEST_MAX_S=0.001 python3 "$HARVEST" 30 --json --out "$BATS_TEST_TMPDIR/bounded"
  [ "$status" -eq 6 ]
  [[ "$output" == *"DEADLINE"* ]] || false
  [[ "$output" == *"NO PARTIAL result"* ]] || false
  [ ! -d "$BATS_TEST_TMPDIR/bounded" ]
  # the control: the SAME command with the bound at its default completes and writes the proposal.
  run env -u CC_PERMHARVEST_MAX_S python3 "$HARVEST" 30 --json --out "$BATS_TEST_TMPDIR/bounded"
  [ "$status" -eq 0 ]
  [ -f "$BATS_TEST_TMPDIR/bounded/latest.json" ]
  # THE MARGIN, measured on THIS box rather than assumed from the reading above. It times
  # `_pipeline` itself and not the process: interpreter startup is ~as large as the pipeline here
  # and is NOT subject to the timer (the alarm is armed inside `pipeline()`), so timing the process
  # would inflate the ratio in the one direction that HIDES erosion. Same in-process import shape as
  # the marker-timeout arm below, and the same interpreter the arm above runs under — a margin read
  # under a different python is a fact about that python.
  cat > "$BATS_TEST_TMPDIR/margin.py" <<'PY'
import sys, time, importlib.util
from importlib.machinery import SourceFileLoader
tool, bound, floor = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
spec = importlib.util.spec_from_loader("hv", SourceFileLoader("hv", tool))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
args = m.build_parser().parse_args(["30", "--json"])
t = time.perf_counter()
m._pipeline(args, m.Seams(args), 30)
elapsed = time.perf_counter() - t
ratio = elapsed / bound
print("MARGIN %.4fs / %.4fs = %.1fx" % (elapsed, bound, ratio))
assert ratio >= floor, (
    "the deadline arm's margin has eroded to %.1fx (pipeline %.4fs against a %.4fs bound, floor "
    "%.0fx). The deadline is NOT broken and this is NOT a flake: the bound has simply come too "
    "close to this box's pipeline runtime, and at ~1x the arm above starts reporting exit 0 with a "
    "proposal written — which reads exactly like a deleted deadline. LOWER the bound in that arm "
    "and re-record the reading in its comment. Do not relax this floor." % (ratio, elapsed, bound, floor))
PY
  run python3 "$BATS_TEST_TMPDIR/margin.py" "$HARVEST" 0.001 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"MARGIN"* ]] || false
}

@test "the denial-oracle grep batch carries a timeout, and expiry is UNKNOWN not an acquittal" {
  # This is the only call in the tool that walks gigabytes, and it shipped with no timeout while
  # both git calls beside it carried one. Bounded WORK is not a bounded WAIT: a stalled mount parks
  # the weekly job, and the wrapper writes its evidence line only on return, so cc-fleet reads a
  # healthy job as broken. Two arms: the bound EXISTS, and on expiry the batch comes back WHOLE.
  # Returning [] there would weaken REFUSED_PROMPT_COLLISION into "no denials exist" — the false
  # all-clear this file's BLIND states exist to prevent.
  run grep -c "timeout=_MARKER_TIMEOUT_S" "$HARVEST"
  [ "$status" -eq 0 ]

  printf '#!/bin/sh\nsleep 5\n' > "$BATS_TEST_TMPDIR/slowgrep"
  chmod +x "$BATS_TEST_TMPDIR/slowgrep"
  echo hello > "$BATS_TEST_TMPDIR/t.jsonl"

  cat > "$BATS_TEST_TMPDIR/probe.py" <<'PY'
import os, sys, importlib.util
from importlib.machinery import SourceFileLoader
tool, stub, victim = sys.argv[1], sys.argv[2], sys.argv[3]
spec = importlib.util.spec_from_loader("hv", SourceFileLoader("hv", tool))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m._GREP = stub
m._MARKER_TIMEOUT_S = 0.5
got = m._files_with_marker([victim])
assert got == [victim], "timeout must fail OPEN (return the batch), got %r" % (got,)
assert m._MARKER_STATE["timed_out"] == 1, m._MARKER_STATE
print("BOUNDED-FAIL-OPEN")
PY
  run /usr/bin/python3 "$BATS_TEST_TMPDIR/probe.py" "$HARVEST" "$BATS_TEST_TMPDIR/slowgrep" "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BOUNDED-FAIL-OPEN"* ]]
}
