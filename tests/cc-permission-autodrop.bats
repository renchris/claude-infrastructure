#!/usr/bin/env bats
# cc-permission-audit --auto-drop — names the approved patterns the harness DELETES on entering
# auto mode, so an allow list can be audited against the behaviour it actually gets.
#
# WHY THIS IS NOT --prune. The two modes answer different questions and neither subsumes the
# other. `--prune` finds REDUNDANCY (a duplicate, or a literal already covered by a `:*` rule in
# the same file): dead in every mode, so the file may be rewritten. This mode finds CONDITIONAL
# deadness: `pme`/`qNt`/`gsn`/`_sn` drop broad allow rules on entering auto mode and RESTORE them
# on leaving it, so every entry it names is still load-bearing under `default` and `acceptEdits`.
# Deleting one is a behaviour change, not a cleanup — hence the never-writes arm below, which is
# the safety property of this whole mode and is asserted against CONFIRM=1 explicitly.
#
# The predicate is transcribed from docs/research/permission-matcher-truth-2026-08-20.md §3,
# read out of the 2.1.220 binary. Its own §"Open / UNVERIFIED" flags the drop as code-and-doc
# verified but not probe-verified; these arms therefore assert THIS TOOL against THAT document,
# which is the strongest claim available, and the tool's footer discloses the bound.
#
# Harness laws, inherited from tests/cc-permission-prune.bats: L1 every arm drives the REAL tool
# against its OWN temp settings file (HOME is redirected, and one arm proves discovery finds
# nothing in an empty one); L2 assertions key on the failure-distinct quantity — the EXACT
# dropped count, so a silent no-op and an over-wide predicate fail in opposite directions;
# L3 `[ ]` / `jq -e` / `grep -q` only; L4 both poles — a dropped form is named AND the narrow
# spelling that survives it is proven untouched.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -f "$AUDIT" ] || skip "cc-permission-audit missing"
  FIX="$BATS_TEST_TMPDIR/fixture.settings.json"
  # 12 entries are dropped in auto mode, each by a DIFFERENT branch of the predicate; the other
  # 12 survive, each for a different reason. Both halves matter: the failure mode of a danger
  # list is over-reach, and the survivors are what catch it.
  cat > "$FIX" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(python3:*)",
      "Bash(node)",
      "Bash(npm run:*)",
      "Bash(sudo *)",
      "Bash(xargs*)",
      "Bash(node -e *)",
      "Bash(curl -sS *)",
      "Bash(kubectl exec *)",
      "Bash(aws s3api $BUCKET *)",
      "Bash(gcloud --project x *)",
      "Bash(*)",
      "Agent(explore)",
      "Bash(npm run test:*)",
      "Bash(python3 scripts/gen.py *)",
      "Bash(python -m pkg.module *)",
      "Bash(git status:*)",
      "Bash(rg:*)",
      "Bash(jq:*)",
      "Bash(gh pr view:*)",
      "Bash(pnpm build:*)",
      "Bash(kubectl get pods:*)",
      "Bash(curl https://api.github.com/*)",
      "Read(//tmp/fixture/**)",
      "WebFetch(domain:example.com)"
    ],
    "deny": ["Bash(dd:*)"],
    "ask": ["Bash(git push --force:*)"]
  }
}
JSON
  ORIG_SHA="$(shasum -a 256 "$FIX" | awk '{print $1}')"
}

named() { # <rule> — the tool listed this rule as dropped
  # -F, not a regex: every rule in this corpus contains `:*` or `(`, and as a BRE `python3:*`
  # means "python3 followed by zero or more colons" — which matches a DIFFERENT string than the
  # one in the file and silently passed/failed for the wrong reason.
  printf '%s\n' "$output" | grep -qF -- "- $1"
}

not_named() { # <file> <rule> — the tool left this rule alone
  [ "$(python3 "$AUDIT" --auto-drop "$1" | grep -cF -- "- $2")" -eq 0 ]
}

@test "the bare / :* / space-star / suffix-star forms of a dangerous command are all named" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  named "Bash(python3:*)"
  named "Bash(node)"
  named "Bash(npm run:*)"     # the two-token member: `npm run` is on the list, `npm` is not
  named "Bash(sudo *)"
  named "Bash(xargs*)"
  # the reason must attribute the LONGEST matching member, or the operator fixes the wrong rule
  [[ "$output" == *'bare `python3`'* ]] || false
  [[ "$output" == *'bare `npm run`'* ]] || false
}

@test "a flag tail is dropped, and quotes the operator's own casing back at them" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  named 'Bash(node -e *)'
  named 'Bash(curl -sS *)'
  # -sS, not -ss: the verdict is computed lowercased (as `_sn` does) but a reason naming a flag
  # that appears nowhere in the file sends them hunting for a rule they never wrote.
  [[ "$output" == *'`-sS…`'* ]] || false
}

@test "the python -m carve-out survives — the one flag tail that is not dropped" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  not_named "$FIX" "Bash(python -m pkg.module *)"
}

@test "the network/cloud subset gets its own three branches, and narrow uses survive" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  named 'Bash(kubectl exec *)'            # a mutating verb
  named 'Bash(aws s3api $BUCKET *)'      # the argument interpolates
  named 'Bash(gcloud --project x *)'      # flag tail, no positional arg
  [[ "$output" == *'a mutating verb'* ]] || false
  [[ "$output" == *'interpolates'* ]] || false
  # …while a read-only verb and a curl carrying a scheme are both narrow enough to keep
  not_named "$FIX" "Bash(kubectl get pods:*)"
  not_named "$FIX" "Bash(curl https://api.github.com/*)"
}

@test "every Agent rule goes, whatever its specifier; other tools are untouched" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  named "Agent(explore)"
  not_named "$FIX" "Read(//tmp/fixture/**)"
  not_named "$FIX" "WebFetch(domain:example.com)"
}

@test "the exact dropped count is 12 of 24 — the failure-distinct quantity" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  # 12 means the predicate agrees with §3 on this fixture. Fewer means a branch stopped firing;
  # more means it reached a survivor, which is the expensive direction — it would tell the
  # operator to rewrite a rule that works.
  [[ "$output" == *"12 of 24 approved pattern(s) are dead weight in auto mode (50.0%)"* ]] || false
}

@test "the narrow spellings the fix recommends are proven to survive" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  local r
  # L4's other pole: each of these is the documented replacement for a dropped entry above, so
  # a predicate that took one would be recommending a rewrite to something equally dead.
  for r in 'Bash(npm run test:*)' 'Bash(python3 scripts/gen.py *)' 'Bash(git status:*)' \
           'Bash(rg:*)' 'Bash(jq:*)' 'Bash(gh pr view:*)' 'Bash(pnpm build:*)'; do
    not_named "$FIX" "$r"
  done
}

@test "it NEVER writes — not even under CONFIRM=1, the env var that arms --prune" {
  # THE safety property of this mode. These rules are live outside auto mode, so a write here
  # would be a silent behaviour change; --prune's own confirm idiom must not reach it.
  run env CONFIRM=1 python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  run bash -c 'ls "$1".permprune-bak-* 2>/dev/null' _ "$FIX"
  [ "$status" -ne 0 ]
  [[ "$output" != *"rewritten"* ]] || false
}

@test "discovery reaches settings.json, not just settings.local.json" {
  # The reason this mode exists: the fleet-wide ~/.claude/settings.json holds the entries the
  # backlog row is about, and --prune's walk has never been able to see it.
  cp "$FIX" "$HOME/.claude/settings.json"
  printf '%s\n' '{"permissions":{"allow":["Bash(perl:*)"]}}' > "$HOME/.claude/settings.local.json"
  run python3 "$AUDIT" --auto-drop
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 2 settings file(s)"* ]] || false
  named "Bash(python3:*)"                 # from settings.json
  named "Bash(perl:*)"                    # from settings.local.json
  [[ "$output" == *"13 of 25"* ]] || false
}

@test "with no paths given, discovery stays inside HOME — an empty HOME audits nothing" {
  run python3 "$AUDIT" --auto-drop
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 0 settings file(s)"* ]] || false
  [[ "$output" == *"n/a"* ]] || false
}

@test "classifyAllShell in ANY source is reported as making the count a FLOOR" {
  printf '%s\n' '{"autoMode":{"classifyAllShell":true},"permissions":{"allow":[]}}' \
    > "$HOME/.claude/settings.local.json"
  run python3 "$AUDIT" --auto-drop "$FIX" "$HOME/.claude/settings.local.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"classifyAllShell"* ]] || false
  [[ "$output" == *"floor"* ]] || false
}

@test "an invalid-JSON settings file is SKIPPED and reported, never a silent success" {
  local torn="$BATS_TEST_TMPDIR/torn.settings.json"
  printf '%s' '{"permissions":{"allow":["Bash(node:*)"' > "$torn"
  run python3 "$AUDIT" --auto-drop "$torn"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKIP"* ]] || false
}

@test "the report discloses its own bound and refuses to recommend deletion" {
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"report only"* ]] || false
  [[ "$output" == *"NOT probe-verified"* ]] || false
  # the fix is to NARROW, never to delete — these entries work in default/acceptEdits
  [[ "$output" == *"Do NOT simply delete them"* ]] || false
}

@test "--prune points at this audit, and the two compose in one invocation" {
  run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  # a clean prune otherwise reads as 'the allow list is audited', and it is not
  [[ "$output" == *"--auto-drop"* ]] || false
  run python3 "$AUDIT" --prune --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"AUTO-MODE DROP AUDIT"* ]] || false
  [[ "$output" == *"PRUNE"* ]] || false
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
}
