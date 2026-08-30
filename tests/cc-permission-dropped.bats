#!/usr/bin/env bats
# cc-permission-audit --prune, AUTO-MODE DROP LIST axis — the entries `--permission-mode auto`
# discards before matching, so they read as coverage while granting nothing.
#
# This is the SECOND deadness axis and it is deliberately not the first one's twin. Redundancy is
# semantics-preserving in any mode and gets removed; an auto-mode drop is undone the moment you
# leave auto mode, so removing it is a real behaviour change under `default`/`acceptEdits` and the
# tool only ever REPORTS it. Both halves are asserted here (L4, both poles): a dropped entry is
# named, and the same run leaves it in the file.
#
# Predicate source: docs/research/permission-matcher-truth-2026-08-20.md § "Auto mode drops broad
# allow rules" (`pme`/`qNt`/`gsn`/`_sn`/`iSd`/`nSd`/`PHs`, CC 2.1.220). That section flags itself
# as code-and-doc verified but NOT probe-verified, which is exactly why report-only is the design
# and why the survivor arm below matters as much as the hit arm — a predicate that over-fires here
# would tell the operator to narrow rules that are in fact live.
#
# Harness laws, inherited from tests/cc-permission-prune.bats: L1 every arm drives the REAL tool
# against its OWN temp settings file (HOME redirected); L2 assertions key on the failure-distinct
# quantity — the EXACT dropped count, so an over-wide and an inert predicate fail in opposite
# directions; L3 `[ ]` / `jq -e` / `grep -q` only.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -f "$AUDIT" ] || skip "cc-permission-audit missing"
  FIX="$BATS_TEST_TMPDIR/fixture.settings.local.json"
  # 8 of the 22 entries are on the drop list, each for a DIFFERENT documented branch of the
  # predicate; the remaining 14 are SURVIVORS, likewise each for a different reason — eight of them
  # prefix-confusion cases that a `startswith` implementation would wrongly condemn. Those eight
  # are the exact false positives produced by the substring grep this tool replaced (struck from
  # permission-matcher-truth-2026-08-20.md DO #8), so they are the arms that keep it struck.
  cat > "$FIX" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(python3:*)",
      "Bash(npm run:*)",
      "Bash(sudo -u *)",
      "Bash(node -e *)",
      "Bash(*)",
      "Bash",
      "Agent(Explore)",
      "Bash(kubectl exec mypod)",
      "Bash(npm run test:*)",
      "Bash(python -m pkg.module *)",
      "Bash(python3 scripts/foo.py *)",
      "Bash(git status:*)",
      "Bash(rg:*)",
      "Bash(envsubst:*)",
      "Bash(evaluate:*)",
      "Bash(shellcheck:*)",
      "Bash(npm:*)",
      "Bash(nodemon:*)",
      "Bash(sudoku:*)",
      "Bash(execa:*)",
      "Bash(npm run-script:*)",
      "Read(//tmp/fixture/**)"
    ],
    "deny": [], "ask": []
  }
}
JSON
  ORIG_SHA="$(shasum -a 256 "$FIX" | awk '{print $1}')"
}

dropped_line() { # <rule> — the report line naming this rule as dropped
  grep -F "· $1 " <<<"$OUTPUT"
}

run_audit() {
  run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  OUTPUT="$output"
}

@test "the drop-list section reports the EXACT population, not a superset" {
  run_audit
  [[ "$OUTPUT" == *"8 of 22 approved patterns (36.4%) are DROPPED"* ]] || false
}

@test "each documented drop branch fires, and says WHICH branch" {
  run_audit
  # bare / `:*` form of an iSd command
  dropped_line "Bash(python3:*)" | grep -q "dangerous-command list"
  # a multi-word iSd entry — `npm run` is on the list, `npm` alone is not
  dropped_line "Bash(npm run:*)" | grep -q "dangerous-command list"
  # `<cmd> …*` whose tail starts with a flag
  dropped_line "Bash(sudo -u *)" | grep -q "flag form"
  dropped_line "Bash(node -e *)" | grep -q "flag form"
  # gsn's wildcard and empty-content branches
  dropped_line "Bash(*)" | grep -q "bare/wildcard Bash form"
  dropped_line "Bash" | grep -q "empty-content form"
  # PHs: every Agent rule, whatever its specifier
  dropped_line "Agent(Explore)" | grep -q "every Agent allow rule"
  # nSd: a kubectl verb on the dropped-verb list, despite having a positional arg
  dropped_line "Bash(kubectl exec mypod)" | grep -q "dropped-verb list"
}

@test "the documented SURVIVORS are not reported — an over-wide predicate fails here" {
  run_audit
  # Narrower than the bare form: the tail is not `*` and does not start with a flag.
  ! grep -qF "· Bash(npm run test:*) " <<<"$OUTPUT" || false
  # The one documented exception inside the flag-tail branch.
  ! grep -qF "· Bash(python -m pkg.module *) " <<<"$OUTPUT" || false
  ! grep -qF "· Bash(python3 scripts/foo.py *) " <<<"$OUTPUT" || false
  # Never on either list at all.
  ! grep -qF "· Bash(git status:*) " <<<"$OUTPUT" || false
  ! grep -qF "· Bash(rg:*) " <<<"$OUTPUT" || false
  # gsn returns false for every non-Bash tool (Agent excepted, asserted above).
  ! grep -qF "· Read(//tmp/fixture/**) " <<<"$OUTPUT" || false
  # PREFIX CONFUSION, the failure mode a naive `startswith` would ship: each of these begins with
  # a listed command's letters and is a different command. `_sn` keys on the whole token, so the
  # boundary (`:`, a space, or `*`) is what makes a match, not the prefix.
  ! grep -qF "· Bash(envsubst:*) " <<<"$OUTPUT" || false   # not `env`
  ! grep -qF "· Bash(evaluate:*) " <<<"$OUTPUT" || false   # not `eval`
  ! grep -qF "· Bash(shellcheck:*) " <<<"$OUTPUT" || false   # not `sh`
  ! grep -qF "· Bash(npm:*) " <<<"$OUTPUT" || false   # `npm run` is listed; bare `npm` is not
  ! grep -qF "· Bash(nodemon:*) " <<<"$OUTPUT" || false   # not `node`
  ! grep -qF "· Bash(sudoku:*) " <<<"$OUTPUT" || false   # not `sudo`
  ! grep -qF "· Bash(execa:*) " <<<"$OUTPUT" || false   # not `exec`
  ! grep -qF "· Bash(npm run-script:*) " <<<"$OUTPUT" || false   # `run-script` is not the `run` token
}

@test "a kubectl verb drops in BOTH spellings of the same rule — \`:*\` is not narrower" {
  # THE MISS THIS ARM EXISTS FOR (2026-08-30). `_tail_after` treats `:` and ` ` as the same
  # separator at the COMMAND boundary — `Bash(kubectl …)` and `Bash(kubectl:…)` both reach the
  # nSd branch — but the verb check then compared the RAW token, so `Bash(kubectl exec *)` was
  # reported and `Bash(kubectl exec:*)` was not. Same rule, two spellings, opposite verdicts, and
  # `:*` is the spelling every rule in this repo's own settings files is written in, so the form
  # that actually occurs was the invisible one. Under-reporting is the failure that matters on
  # this axis: the section's whole job is naming entries that grant nothing.
  kube="$BATS_TEST_TMPDIR/kube.settings.local.json"
  cat > "$kube" <<'JSON'
{"permissions":{"allow":[
  "Bash(kubectl exec *)","Bash(kubectl exec:*)",
  "Bash(kubectl apply:*)","Bash(kubectl port-forward:*)",
  "Bash(kubectl get:*)","Bash(kubectl applyfoo:*)","Bash(kubectl execute-hook:*)"
]}}
JSON
  run python3 "$AUDIT" --prune "$kube"
  [ "$status" -eq 0 ]
  OUTPUT="$output"
  # BOTH poles, per L4. The hit arm: the four verb rules drop, and the `:*` half is the new one.
  [[ "$OUTPUT" == *"4 of 7 approved patterns"* ]] || false
  dropped_line "Bash(kubectl exec *)" | grep -q "dropped-verb list"
  dropped_line "Bash(kubectl exec:*)" | grep -q "dropped-verb list"
  dropped_line "Bash(kubectl apply:*)" | grep -q "dropped-verb list"
  # a hyphenated verb survives the suffix strip intact rather than being truncated to a non-verb
  dropped_line "Bash(kubectl port-forward:*)" | grep -q "dropped-verb list"
  # The over-fire arm: stripping the suffix must not MANUFACTURE a verb out of a longer token.
  ! grep -qF "· Bash(kubectl get:*) " <<<"$OUTPUT" || false        # `get` is not on the verb list
  ! grep -qF "· Bash(kubectl applyfoo:*) " <<<"$OUTPUT" || false   # not `apply`
  ! grep -qF "· Bash(kubectl execute-hook:*) " <<<"$OUTPUT" || false  # not `exec`
}

@test "a dropped entry is REPORTED but never removed — even under CONFIRM=1" {
  CONFIRM=1 run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"are DROPPED"* ]] || false
  # The file is byte-identical: nothing here is redundant, so the redundancy axis writes nothing,
  # and the auto-mode axis is barred from writing at all.
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  jq -e '(.permissions.allow | index("Bash(python3:*)")) != null' "$FIX" >/dev/null
  jq -e '(.permissions.allow | length) == 22' "$FIX" >/dev/null
}

@test "the two axes are independent — a redundant entry goes, a dropped one stays" {
  both="$BATS_TEST_TMPDIR/both.settings.local.json"
  # `Bash(git -C /tmp/x status)` is redundant (shadowed); `Bash(sudo:*)` is auto-mode dropped.
  cat > "$both" <<'JSON'
{"permissions":{"allow":["Bash(git:*)","Bash(git -C /tmp/x status)","Bash(sudo:*)"]}}
JSON
  CONFIRM=1 run python3 "$AUDIT" --prune "$both"
  [ "$status" -eq 0 ]
  jq -e '(.permissions.allow) == ["Bash(git:*)","Bash(sudo:*)"]' "$both" >/dev/null
}

@test "classifyAllShell is surfaced — it makes the per-entry list moot, not longer" {
  shell="$BATS_TEST_TMPDIR/shell.settings.local.json"
  cat > "$shell" <<'JSON'
{"autoMode":{"classifyAllShell":true},"permissions":{"allow":["Bash(rg:*)"]}}
JSON
  run python3 "$AUDIT" --prune "$shell"
  [ "$status" -eq 0 ]
  [[ "$output" == *"classifyAllShell is set"* ]] || false
  [[ "$output" == *"the whole Bash allowlist is inert"* ]] || false
}

@test "a file with nothing on the drop list says so — silence is not the all-clear" {
  clean="$BATS_TEST_TMPDIR/clean.settings.local.json"
  cat > "$clean" <<'JSON'
{"permissions":{"allow":["Bash(git status:*)","Bash(rg:*)"]}}
JSON
  run python3 "$AUDIT" --prune "$clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 of 2 approved patterns are on the drop list"* ]] || false
}

@test "discovery reaches settings.json, the file the 339 entries actually live in" {
  # Until 2026-08-28 the walk matched only `settings.local.json`, so `--prune` with no arguments
  # could not see `~/.claude/settings.json` at all — the population its own backlog row named.
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(sudo:*)","Bash(git:*)","Bash(git -C /tmp/x status)"]}}
JSON
  run python3 "$AUDIT" --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 1 settings file(s)"* ]] || false
  [[ "$output" == *"1 of 3 approved patterns"* ]] || false
}

@test "a DISCOVERED settings.json is reported but never rewritten without being named" {
  # Widening discovery must not widen what a bare `CONFIRM=1` run mutates: settings.json is the
  # operator's primary file and a settings watcher reloads it live.
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(git:*)","Bash(git -C /tmp/x status)"]}}
JSON
  sha="$(shasum -a 256 "$HOME/.claude/settings.json" | awk '{print $1}')"
  CONFIRM=1 run python3 "$AUDIT" --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT rewritten — name this path explicitly"* ]] || false
  [ "$(shasum -a 256 "$HOME/.claude/settings.json" | awk '{print $1}')" = "$sha" ]
  # …and naming it IS the authorisation.
  CONFIRM=1 run python3 "$AUDIT" --prune "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  jq -e '(.permissions.allow) == ["Bash(git:*)"]' "$HOME/.claude/settings.json" >/dev/null
}
