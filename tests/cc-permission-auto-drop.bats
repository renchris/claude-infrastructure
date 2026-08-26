#!/usr/bin/env bats
# cc-permission-audit --auto-drop — the allow entries the BINARY deletes on entering
# `--permission-mode auto`, which every live session on this box runs.
#
# Backlog row 78b76e1a8311: "the 339 existing allow entries have never been audited against
# the auto-mode drop list". Two things made that audit impossible rather than merely undone:
# no code implemented the predicate, and `--prune` discovery matched `settings.local.json`
# only while the 339-entry file is `~/.claude/settings.json` (that half is pinned in
# cc-permission-prune.bats).
#
# The predicate is transcribed from the binary in
# docs/research/permission-matcher-truth-2026-08-20.md § "Auto mode drops broad allow rules —
# the exact predicate" (`pme`/`qNt`/`bsn`/`gsn`/`_sn`/`iSd`/`PHs`). These arms are that
# section's own examples, both poles, so a drift in either direction fails one.
#
# Harness laws: L1 the REAL tool against its OWN temp settings file, HOME redirected; L2
# assertions key on the failure-distinct quantity (the EXACT dropped count, so an over-wide
# and a no-op predicate fail in opposite directions); L3 `[ ]` / `jq -e` / `grep -q` only;
# L4 both poles — and the sharpest pole here is the NEAR-MISS: the research doc's own remedy
# was a substring grep for `sudo|env|exec|node|sh|…`, which sweeps `sudoku`, `envsubst`,
# `execa`, `nodemon`, `shellcheck` and `npm run-script`. Every one of those must survive.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -f "$AUDIT" ] || skip "cc-permission-audit missing"
  FIX="$BATS_TEST_TMPDIR/fixture.settings.json"
  ORIG_SHA=""
}

# Write a settings fixture from the allow entries given as arguments.
fixture() {
  local first=1 out='{"permissions":{"allow":['
  local r
  for r in "$@"; do
    [ "$first" -eq 1 ] || out+=','
    first=0
    out+="\"$r\""
  done
  out+=']}}'
  printf '%s\n' "$out" > "$FIX"
  ORIG_SHA="$(shasum -a 256 "$FIX" | awk '{print $1}')"
}

dropped_count() { # parse the tool's own headline, never a re-derivation
  sed -n 's/^  \([0-9]\{1,\}\) of [0-9]\{1,\} approved pattern(s) cannot fire.*/\1/p' <<<"$1"
}

@test "the broad interpreter forms are dropped — bare, :*, * and <cmd>*" {
  fixture 'Bash(python3:*)' 'Bash(node *)' 'Bash(npm run:*)' 'Bash(sudo:*)' \
          'Bash(env:*)' 'Bash(xargs:*)' 'Bash(eval:*)' 'Bash(sh:*)' 'Bash(ssh:*)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  # ALL NINE. A predicate that catches eight is the bug this count exists to fail on.
  [ "$(dropped_count "$output")" -eq 9 ]
  [[ "$output" == *'`python3` in bare / `:*` / `*` form'* ]] || false
  [[ "$output" == *'`npm run` in bare / `:*` / `*` form'* ]] || false
}

@test "the narrow forms the research doc tells you to write all SURVIVE" {
  # Straight from its DO list — if any of these is reported, the remedy it recommends is
  # itself flagged as dead weight and the audit is worse than useless.
  fixture 'Bash(git status:*)' 'Bash(rg:*)' 'Bash(jq:*)' 'Bash(gh pr view:*)' \
          'Bash(npm run test:*)' 'Bash(pnpm build:*)' 'Bash(python3 scripts/gen.py *)' \
          'Bash(node scripts/build.js *)' 'Bash(kubectl get pods:*)' 'Bash(aws s3 ls:*)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(dropped_count "$output")" -eq 0 ]
}

@test "a NEAR-MISS command name is never swept — the substring-grep failure mode" {
  fixture 'Bash(shellcheck:*)' 'Bash(nodemon:*)' 'Bash(sudoku:*)' 'Bash(envsubst:*)' \
          'Bash(execa:*)' 'Bash(npm run-script:*)' 'Bash(shasum:*)' 'Bash(evalx:*)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(dropped_count "$output")" -eq 0 ]
}

@test "a flag tail drops, and the python -m exception survives it" {
  fixture 'Bash(node -e *)' 'Bash(sudo -u *)' 'Bash(bash -c *)' \
          'Bash(python -m pkg.module *)' 'Bash(python3 -m http.server *)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(dropped_count "$output")" -eq 3 ]
  [[ "$output" == *'`node` with a flag tail'* ]] || false
  [[ "$output" != *'python -m pkg.module'* ]] || false
}

@test "the network/cloud subset: substitution, kubectl mutators, and no-positional" {
  fixture 'Bash(curl:*)' 'Bash(aws:*)' 'Bash(kubectl exec *)' 'Bash(kubectl delete pods:*)' \
          'Bash(curl https://x/$TOKEN *)' \
          'Bash(kubectl get pods:*)' 'Bash(curl https://api.github.com/*)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(dropped_count "$output")" -eq 5 ]
  [[ "$output" == *'`kubectl exec` is a mutating verb'* ]] || false
  [[ "$output" == *'substitution'* ]] || false
}

@test "every Agent rule drops whatever its specifier; other tools are untouched" {
  fixture 'Agent(*)' 'Agent(general-purpose)' 'Read(//tmp/**)' \
          'WebFetch(domain:example.com)' 'PowerShell(Get-ChildItem:*)' 'Skill(ship)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  # Exactly the two Agent rules. PowerShell drops ONLY via classifyAllShell (next arm).
  [ "$(dropped_count "$output")" -eq 2 ]
  [[ "$output" == *"every Agent rule is dropped in auto mode"* ]] || false
}

@test "autoMode.classifyAllShell drops EVERY Bash and PowerShell rule, however narrow" {
  cat > "$FIX" <<'JSON'
{
  "autoMode": { "classifyAllShell": true },
  "permissions": { "allow": ["Bash(git status:*)", "PowerShell(Get-ChildItem:*)",
                             "Read(//tmp/**)", "Agent(*)"] }
}
JSON
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  # Bash + PowerShell + the Agent rule = 3; Read survives.
  [ "$(dropped_count "$output")" -eq 3 ]
  [[ "$output" == *"classifyAllShell is TRUE here"* ]] || false
}

@test "--auto-drop NEVER writes, even under CONFIRM=1 — it is a report, not a prune" {
  # The load-bearing distinction: an auto-dropped rule is restored on leaving auto mode, so
  # it is dead WEIGHT, not a dead ENTRY. Removing it would change behaviour in default mode.
  fixture 'Bash(python3:*)' 'Bash(sudo:*)' 'Agent(*)'
  run env CONFIRM=1 python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [ "$(dropped_count "$output")" -eq 3 ]
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  [ "$(jq '.permissions.allow | length' "$FIX")" -eq 3 ]
  run bash -c 'ls "$1".permprune-bak-* 2>/dev/null' _ "$FIX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"REPORTED ONLY"* ]] || [[ "$output" == "" ]]
}

@test "--prune runs BOTH audits, and prunes only the provably-dead half" {
  # The row's own spelling was `cc-permission-audit --prune`, so that command must answer
  # both halves of "is this entry doing anything?" — while still removing only redundancy.
  fixture 'Bash(git:*)' 'Bash(git -C /tmp/gone status)' 'Bash(python3:*)' 'Bash(rg:*)'
  run env CONFIRM=1 python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 provably-dead entr(ies) of 4 approved patterns"* ]] || false
  [[ "$output" == *"AUTO-MODE DROP AUDIT"* ]] || false
  [[ "$output" == *"Bash(python3:*)"* ]] || false
  # The shadowed entry is gone; the auto-dropped one is REPORTED and still present.
  [ "$(jq '.permissions.allow | length' "$FIX")" -eq 3 ]
  jq -e '(.permissions.allow | index("Bash(python3:*)")) != null' "$FIX" >/dev/null
  jq -e '(.permissions.allow | index("Bash(git -C /tmp/gone status)")) == null' "$FIX" >/dev/null
}

@test "an invalid-JSON settings file is SKIPPED and reported, never read as an all-clear" {
  printf '%s' '{"permissions":{"allow":["Bash(python3:*)"' > "$FIX"
  local sha; sha="$(shasum -a 256 "$FIX" | awk '{print $1}')"
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKIP"* ]] || false
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$sha" ]
}

@test "the report carries its own honest bound — not probe-verified" {
  # This predicate rests on code reading plus the vendor docs; no observable distinguishes
  # 'allowed by rule' from 'allowed by classifier' in auto mode. A report that omits that
  # invites the operator to delete rules on a certainty the evidence does not carry.
  fixture 'Bash(python3:*)'
  run python3 "$AUDIT" --auto-drop "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT probe-verified"* ]] || false
  [[ "$output" == *"REPORTED ONLY"* ]] || false
}
