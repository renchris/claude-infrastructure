#!/usr/bin/env bats
# cc-permission-audit --drops — names the approved permission patterns that Claude Code DELETES
# from the ruleset on entering `--permission-mode auto`.
#
# Backlog row 78b76e1a8311 asked for the 339 `permissions.allow` entries to be audited against
# that drop list. The audit had to be a MODE OF THE TOOL rather than a one-shot grep, because the
# entry list changes weekly and a report written into a doc is stale the day after it lands.
#
# 🚨 THE POLARITY THAT MATTERS, and the reason this is not folded into `--prune`: a dropped rule
# is INERT, not DEAD. The drop is undone the moment the session leaves auto mode, and the rule
# still decides in `default`/`acceptEdits`. Removing it would silently disarm every non-auto
# session. So `--drops` reports and NEVER writes — the arms below assert that at both poles (no
# CONFIRM path, and byte-identical files afterwards).
#
# Predicate source: docs/research/permission-matcher-truth-2026-08-20.md § "Auto mode drops broad
# allow rules — the exact predicate" (Claude Code 2.1.220, `pme`/`qNt`/`gsn`/`_sn`/`PHs`, tables
# `iSd`/`nSd`; findings F9/F10).
#
# Harness laws: L1 every arm drives the REAL tool against its OWN temp settings file (HOME is
# redirected, and one arm proves discovery finds nothing there); L2 assertions key on the
# failure-distinct quantity — the EXACT inert count, so an under-wide and an over-wide predicate
# fail in opposite directions; L3 `[ ]` / `jq -e` / `grep -q` only; L4 both poles — a rule the
# filter deletes is named, a rule that survives it is NOT named.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -f "$AUDIT" ] || skip "cc-permission-audit missing"
  FIX="$BATS_TEST_TMPDIR/fixture.settings.json"
  # 10 entries are dropped in auto mode, 10 survive. Each survivor survives for a DIFFERENT
  # reason, so a predicate that over-fires by one clause fails a named arm rather than a count.
  cat > "$FIX" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(python3:*)",
      "Bash(node -e *)",
      "Bash(sudo *)",
      "Bash(env)",
      "Bash(xargs*)",
      "Bash(curl:*)",
      "Bash(kubectl exec:*)",
      "Bash(aws:*)",
      "Agent(Explore)",

      "Bash(npm run build:*)",
      "Bash(python3 scripts/gen.py *)",
      "Bash(python -m pkg.module *)",
      "Bash(git status:*)",
      "Bash(rg:*)",
      "Bash(jq:*)",
      "Bash(kubectl get pods:*)",
      "Bash(aws s3 ls:*)",
      "Bash(curl https://api.github.com/*)",
      "Read(//tmp/fixture/**)"
    ],
    "deny": ["Bash(dd:*)"]
  }
}
JSON
  ORIG_SHA="$(shasum -a 256 "$FIX" | awk '{print $1}')"
}

# Both helpers put their `[[ ]]` in FINAL position inside the function, so the function's own
# exit status carries the verdict and a bare call to it is live under bats' errexit. `! names …`
# would NOT be: bash exempts a `!`-negated command from errexit, so the negative pole has to be
# its own function rather than a negation of the positive one.
names() { # <rule> — the rule IS named as inert in $output
  [[ "$output" == *"✗ $1 "* ]]
}

not_named() { # <rule> — the rule is NOT named as inert in $output
  [[ "$output" != *"✗ $1 "* ]]
}

@test "the broad forms on the iSd list are named — bare, :*, ' *', '*', and a flag tail" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  names "Bash(npm run:*)"     # <cmd>:*      — a task runner
  names "Bash(python3:*)"     # <cmd>:*      — a script runner
  names "Bash(node -e *)"     # <cmd> -flag* — the flag-tail branch
  names "Bash(sudo *)"        # <cmd> *
  names "Bash(env)"           # bare <cmd>
  names "Bash(xargs*)"        # <cmd>*
}

@test "the nSd branch fires on its three clauses and not otherwise" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  names "Bash(curl:*)"        # no positional argument
  names "Bash(aws:*)"         # no positional argument
  names "Bash(kubectl exec:*)"
  [[ "$output" == *"mutating verb"* ]] || false
}

@test "every Agent allow rule is named, whatever its specifier" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  names "Agent(Explore)"
  [[ "$output" == *"whatever its specifier"* ]] || false
}

@test "a rule that SURVIVES the filter is never named — six ways of surviving" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  not_named "Bash(npm run build:*)"          # the documented remedy for Bash(npm run:*)
  not_named "Bash(python3 scripts/gen.py *)" # a named script, not a flag tail
  not_named "Bash(python -m pkg.module *)"   # the ONE documented flag-tail survivor
  not_named "Bash(git status:*)"             # never on either table
  not_named "Bash(kubectl get pods:*)"       # a read-only verb with a positional arg
  not_named "Bash(aws s3 ls:*)"              # has positional args
  not_named "Bash(curl https://api.github.com/*)"  # a URL-bearing positional
  not_named "Read(//tmp/fixture/**)"         # a non-Bash, non-Agent tool
}

@test "the exact inert count is 10 of 20 — the failure-distinct quantity" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  # 10 means the predicate is exactly right; 9 or fewer means it under-fires, 11 or more means it
  # took a rule that survives. Both directions are a distinct failure of a distinct clause.
  [[ "$output" == *"10 of 20 distinct approved pattern(s) are inert"* ]] || false
}

@test "--drops NEVER writes — not with CONFIRM=1, not with anything" {
  run env CONFIRM=1 python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  # …and no backup either, because nothing was ever at risk
  run bash -c 'ls "$1".permprune-bak-* 2>/dev/null' _ "$FIX"
  [ "$status" -ne 0 ]
}

@test "the report states the polarity: inert is not dead, replace rather than delete" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT DEAD"* ]] || false
  [[ "$output" == *"leaves auto mode"* ]] || false
  # every named entry carries the narrower form that survives
  [[ "$output" == *"enumerate the scripts you run"* ]] || false
  [[ "$output" == *"name the script"* ]] || false
}

@test "the honest bound travels with the number, not just with the research doc" {
  run python3 "$AUDIT" --drops "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT probe-verified"* ]] || false
  [[ "$output" == *"2.1.220"* ]] || false
}

@test "autoMode.classifyAllShell escalates the verdict from 'these' to 'all of them'" {
  local wide="$BATS_TEST_TMPDIR/wide.settings.json"
  cat > "$wide" <<'JSON'
{"autoMode":{"classifyAllShell":true},
 "permissions":{"allow":["Bash(git status:*)","Bash(rg:*)"]}}
JSON
  run python3 "$AUDIT" --drops "$wide"
  [ "$status" -eq 0 ]
  # neither rule is on either table, so the per-entry list is empty…
  [[ "$output" == *"0 of 2 distinct approved pattern(s) are inert"* ]] || false
  # …and that count would be the wrong answer without this banner
  [[ "$output" == *"classifyAllShell is TRUE"* ]] || false
  [[ "$output" == *"EVERY Bash and PowerShell allow rule is dropped"* ]] || false
}

@test "an invalid-JSON settings file is SKIPPED and reported, never parsed past" {
  local torn="$BATS_TEST_TMPDIR/torn.settings.json"
  printf '%s' '{"permissions":{"allow":["Bash(sudo *)"' > "$torn"
  run python3 "$AUDIT" --drops "$torn"
  [ "$status" -ne 0 ]                      # a skipped file is reported, never a silent success
  [[ "$output" == *"SKIP"* ]] || false
}

@test "with no paths given, discovery stays inside HOME — an empty HOME finds nothing" {
  run python3 "$AUDIT" --drops
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 0 settings file(s)"* ]] || false
}

@test "discovery reads settings.json too — the file the 339 entries actually live in" {
  # `--prune` walks only settings.local.json because it REWRITES what it finds. The entries this
  # audit is about are in settings.json, so the read-only walk has to be wider or the default
  # invocation reports on an empty population.
  mkdir -p "$HOME/.claude-secondary"
  printf '%s\n' '{"permissions":{"allow":["Bash(sudo *)"]}}' > "$HOME/.claude/settings.json"
  printf '%s\n' '{"permissions":{"allow":["Bash(npx:*)"]}}' > "$HOME/.claude-secondary/settings.json"
  run python3 "$AUDIT" --drops
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 2 settings file(s)"* ]] || false
  names "Bash(sudo *)"
  names "Bash(npx:*)"
}

@test "--prune points at this audit, so the two questions cannot be confused" {
  printf '%s\n' '{"permissions":{"allow":["Bash(git:*)"]}}' > "$BATS_TEST_TMPDIR/p.settings.local.json"
  run python3 "$AUDIT" --prune "$BATS_TEST_TMPDIR/p.settings.local.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--drops"* ]] || false
}
