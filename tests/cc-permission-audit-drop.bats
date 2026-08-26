#!/usr/bin/env bats
# cc-permission-audit --drop — the AUTO-MODE drop audit: which `permissions.allow` entries
# Claude Code DELETES for the duration of an auto-mode session (`pme` → `qNt` → `gsn`/`_sn`,
# transcribed in bin/cc-permission-audit from docs/research/permission-matcher-truth-2026-08-20.md
# §3, read out of CC 2.1.220).
#
# WHY THIS SUITE IS NOT AN EXTENSION OF cc-permission-prune.bats. The two modes report DIFFERENT
# kinds of dead and the difference is the safety property being tested here:
#   --prune  dead under EVERY mode (rule algebra, proven inside one file)  → it WRITES.
#   --drop   dead ONLY in auto mode; the rule is RESTORED on leaving auto  → it must NEVER write.
# So the load-bearing arms below are the two negatives: --drop leaves every byte alone even under
# CONFIRM=1, and --prune's own discovery still refuses to reach a primary settings.json.
#
# THE FIXTURE IS BUILT FROM THE FOUR CLASSES A GREP GETS WRONG. Recommendation 8 of that research
# doc proposes grepping the command names, which is why each of those classes appears here as its
# own pole: `npm run:*` dies but `npm run test:*` lives · `python -m pkg.module *` survives the
# flag-tail rule by documented exception · `kubectl exec` dies where `kubectl get` lives · and
# `git log … -- bin/env:*` merely CONTAINS a listed command and must not be touched.
#
# Harness laws, inherited from cc-permission-prune.bats: L1 every arm drives the REAL tool against
# its OWN temp settings file, with HOME redirected so the operator's live ~/.claude is never read;
# L2 assertions key on the failure-distinct quantity (the EXACT dropped count, so an under-wide and
# an over-wide predicate fail in opposite directions); L3 `[ ]` / `jq -e` / `grep -q` only; L4 both
# poles for every branch — a rule that dies and a near-neighbour that lives.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -f "$AUDIT" ] || skip "cc-permission-audit missing"
  FIX="$BATS_TEST_TMPDIR/fixture.settings.json"
  # 11 of these 24 entries are dropped in auto mode. Every dropped one is paired with a survivor
  # that a name-based match would confuse it with — see the header.
  cat > "$FIX" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(python:*)",
      "Bash(python3 scripts/gen.py *)",
      "Bash(python -m pkg.module *)",
      "Bash(node -e *)",
      "Bash(npm run:*)",
      "Bash(npm run test:*)",
      "Bash(sudo -u *)",
      "Bash(env)",
      "Bash(xargs *)",
      "Bash(kubectl exec *)",
      "Bash(kubectl get pods *)",
      "Bash(curl:*)",
      "Bash(curl https://api.github.com/*)",
      "Bash(curl -sS $URL)",
      "Bash(gcloud *)",
      "Bash(aws s3 ls *)",
      "Bash(git status:*)",
      "Bash(git log --format=%h -- bin/env:*)",
      "Bash(rg:*)",
      "Bash(jq:*)",
      "Agent(Explore)",
      "Read(//tmp/fixture/**)",
      "WebFetch(domain:example.com)",
      "Bash(gh pr view:*)"
    ],
    "deny": ["Bash(dd:*)"],
    "ask": ["Bash(git push --force:*)"]
  },
  "enabledMcpjsonServers": ["ms365"]
}
JSON
  ORIG_SHA="$(shasum -a 256 "$FIX" | awk '{print $1}')"
}

# The report lists one `    - <rule>   [<why>]` line per dropped entry.
dropped_lines() { grep -c '^    - ' <<<"$1" || true; }

@test "--drop names every auto-dropped entry and EXACTLY those — 11 of 24" {
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"11 of 24 allow entr(ies) are INERT in auto mode (45.8%)"* ]] || false
  [ "$(dropped_lines "$output")" -eq 11 ]
  [[ "$output" == *"24 entries → 13 survive auto mode, 11 dropped"* ]] || false
}

@test "the broad forms die: bare, prefix, flag-tail, wildcard-only" {
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  grep -q 'Bash(python:\*).*grants arbitrary code execution' <<<"$output"
  grep -q 'Bash(env).*grants arbitrary code execution' <<<"$output"
  grep -q 'Bash(xargs \*).*grants arbitrary code execution' <<<"$output"
  grep -q 'Bash(node -e \*).*starts with a flag' <<<"$output"
  grep -q 'Bash(sudo -u \*).*starts with a flag' <<<"$output"
}

@test "the four classes a grep gets wrong keep their survivor — each pole named" {
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  # Each pair: the dropped one is reported, its near-neighbour is NOT.
  grep -q 'Bash(npm run:\*)' <<<"$output"
  ! grep -q -- '- Bash(npm run test:\*)' <<<"$output" || false
  ! grep -q -- '- Bash(python -m pkg.module \*)' <<<"$output" || false
  ! grep -q -- '- Bash(python3 scripts/gen.py \*)' <<<"$output" || false
  grep -q 'Bash(kubectl exec \*).*mutating verb' <<<"$output"
  ! grep -q -- '- Bash(kubectl get pods \*)' <<<"$output" || false
  # merely CONTAINS `env` and `sh`; a name grep flags it, the predicate must not
  ! grep -q -- '- Bash(git log --format=%h -- bin/env:\*)' <<<"$output"
}

@test "the network subset splits on its argument, not its name" {
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  grep -q 'Bash(curl:\*).*no positional argument' <<<"$output"
  grep -q 'Bash(gcloud \*).*no positional argument' <<<"$output"
  grep -q 'Bash(curl -sS \$URL).*interpolates' <<<"$output"
  # a scheme-carrying URL and a read-only cloud verb are the constraint — both survive
  ! grep -q -- '- Bash(curl https://api.github.com/\*)' <<<"$output" || false
  ! grep -q -- '- Bash(aws s3 ls \*)' <<<"$output"
}

@test "every Agent rule is dropped, and non-Bash tool rules are untouched" {
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  grep -q 'Agent(Explore).*whatever its specifier' <<<"$output"
  ! grep -q -- '- Read(//tmp/fixture/\*\*)' <<<"$output" || false
  ! grep -q -- '- WebFetch(domain:example.com)' <<<"$output"
}

@test "--drop writes NOTHING, and CONFIRM=1 does not change that" {
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  # CONFIRM=1 is --prune's apply arm. --drop has no counterpart and must ignore it entirely:
  # a rule that is live outside auto mode is not this tool's to delete.
  CONFIRM=1 run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  [[ "$output" == *"has no apply arm"* ]] || false
  # no backup file either — nothing was ever opened for writing
  run bash -c "ls '$FIX'.permprune-bak-* 2>/dev/null | wc -l"
  [ "$(tr -d ' ' <<<"$output")" -eq 0 ]
}

@test "classifyAllShell in ANY source drops every Bash rule, however narrow" {
  jq '. + {autoMode: {classifyAllShell: true}}' "$FIX" > "$FIX.tmp" && mv "$FIX.tmp" "$FIX"
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"autoMode.classifyAllShell is set"* ]] || false
  # 21 Bash rules + Agent(Explore) = 22; Read and WebFetch are the only two left standing.
  [[ "$output" == *"22 of 24 allow entr(ies) are INERT in auto mode"* ]] || false
  grep -q 'Bash(git status:\*).*classifyAllShell' <<<"$output"
  ! grep -q -- '- Read(//tmp/fixture/\*\*)' <<<"$output"
}

@test "discovery finds a primary settings.json — the file that holds the real allow list" {
  # Measured 2026-08-20: no settings.local.json exists in ANY config dir on the operator's box,
  # while the primaries hold 339 entries each. Discovery limited to `.local` reports 0 files over
  # the entire live rule set, which reads as an all-clear. This arm is that false negative.
  cp "$FIX" "$HOME/.claude/settings.json"
  run python3 "$AUDIT" --drop
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 1 settings file(s)"* ]] || false
  [[ "$output" == *"11 of 24 allow entr(ies) are INERT in auto mode"* ]] || false
}

@test "--prune discovery still refuses to reach a primary settings.json" {
  # The writing mode keeps the narrow default: a primary is rewritten only when named out loud on
  # the command line. Widening --drop must not have widened --prune with it.
  cp "$FIX" "$HOME/.claude/settings.json"
  PRIMARY_SHA="$(shasum -a 256 "$HOME/.claude/settings.json" | awk '{print $1}')"
  CONFIRM=1 run python3 "$AUDIT" --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 0 settings.local.json file(s)"* ]] || false
  [ "$(shasum -a 256 "$HOME/.claude/settings.json" | awk '{print $1}')" = "$PRIMARY_SHA" ]
}

@test "no settings file is reported as BLIND, never as an all-clear" {
  run python3 "$AUDIT" --drop
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 0 settings file(s)"* ]] || false
  [[ "$output" == *"NOT an all-clear"* ]] || false
}

@test "an invalid-JSON settings file is SKIPPED and the run exits nonzero" {
  printf '{ this is not json' > "$FIX"
  run python3 "$AUDIT" --drop "$FIX"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SKIP (unreadable/invalid JSON)"* ]] || false
}

@test "--drop is additive: --prune keeps its own, much smaller, verdict" {
  # The two predicates OVERLAP without agreeing, and this arm pins the difference. --drop calls 11
  # of these 24 inert; --prune calls exactly ONE dead, `Bash(curl -sS $URL)`, and for an unrelated
  # reason — it is shadowed by `Bash(curl:*)` in the same file, which is true in every mode. The
  # other 10 are live rules that auto mode ignores, so the writing mode must keep its hands off
  # them: a --drop finding may never widen what --prune deletes.
  run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 provably-dead entr(ies) of 24 approved patterns"* ]] || false
  [[ "$output" == *"shadowed by Bash(curl:*)"* ]] || false
  [ "$(dropped_lines "$output")" -eq 1 ]
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
}
