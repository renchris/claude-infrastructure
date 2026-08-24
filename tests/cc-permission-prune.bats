#!/usr/bin/env bats
# cc-permission-audit --prune — removes approved permission patterns that provably cannot
# change any decision, from the settings.local.json files that hold them.
#
# Backlog row a78f0fa4223a asked for the "one-shot exact-match" class (a pattern naming a
# literal that can only ever have occurred once). Re-measured 2026-08-17: 63 files, 2399
# approved patterns, 63.2% of the 1748 Bash patterns are exact matches — but exactness is NOT
# deadness. Nothing on disk proves the operator will not type `mkdir -p /tmp/advV/x` again, so
# that class is not provable and is NOT pruned. What IS provable is REDUNDANCY (10.2% of all
# patterns): a duplicate, or a wildcard-free rule whose own file already carries a `:*` prefix
# rule that matches everything it matches. See THE DEAD-ENTRY PREDICATE in bin/cc-permission-audit.
#
# Harness laws: L1 every arm drives the REAL tool against its OWN temp settings file — the
# operator's real ~/.claude*/settings.local.json is never a fixture (HOME is redirected too, and
# one arm proves discovery finds nothing there); L2 assertions key on the failure-distinct
# quantity (the EXACT survivor count, so a no-op prune and an over-wide prune fail in opposite
# directions); L3 `[ ]` / `jq -e` / `grep -q` only; L4 both poles — a provably-dead entry goes,
# an entry that could match again stays.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  AUDIT="$REPO/bin/cc-permission-audit"
  [ -f "$AUDIT" ] || skip "cc-permission-audit missing"
  FIX="$BATS_TEST_TMPDIR/fixture.settings.local.json"
  # 2 entries are provably dead: `git -C … status` (shadowed by Bash(git:*)) and the second
  # `npm run build` (a byte-identical duplicate). Everything else must survive, each for a
  # DIFFERENT reason — see the arms below.
  cat > "$FIX" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(git:*)",
      "Bash(git -C /tmp/wt-gone status)",
      "Bash(npm run test:*)",
      "Bash(npm run test)",
      "Bash(npm run build)",
      "Bash(npm run build)",
      "Bash(rm -f /tmp/one-shot-3f9a1c/pid-8842.lock)",
      "Bash(gh repo *)",
      "Read(//tmp/fixture/**)",
      "WebFetch(domain:example.com)"
    ],
    "deny": ["Bash(dd:*)"],
    "ask": ["Bash(git push --force:*)"]
  },
  "enabledMcpjsonServers": ["ms365"]
}
JSON
  ORIG_SHA="$(shasum -a 256 "$FIX" | awk '{print $1}')"
}

allow_n() { jq '.permissions.allow | length' "$1"; }

has_rule() { # <file> <rule>
  jq -e --arg r "$2" '(.permissions.allow | index($r)) != null' "$1" >/dev/null
}

backups() { # count of backups made for the fixture
  local c=0 f
  for f in "$FIX".permprune-bak-*; do [ -e "$f" ] && c=$((c + 1)); done
  printf '%s' "$c"
}

@test "--prune alone is a DRY RUN: it names the dead entries and writes nothing" {
  run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  # It must actually FIND them — a tool that prints nothing also writes nothing, and would
  # otherwise pass the untouched-file half of this arm.
  [[ "$output" == *"Bash(git -C /tmp/wt-gone status)"* ]] || false
  [[ "$output" == *"shadowed by Bash(git:*)"* ]] || false
  [[ "$output" == *"duplicate of an earlier entry"* ]] || false
  [[ "$output" == *"2 provably-dead entr(ies) of 10 approved patterns"* ]] || false
  [[ "$output" == *"DRY RUN"* ]] || false
  # …and the file is byte-identical, with no backup taken.
  [ "$(shasum -a 256 "$FIX" | awk '{print $1}')" = "$ORIG_SHA" ]
  [ "$(backups)" -eq 0 ]
}

@test "CONFIRM=1 removes the provably-dead entries — and ONLY those two" {
  run env CONFIRM=1 python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  # The exact count is the failure-distinct quantity: 10 means the prune no-op'd, <8 means it
  # took something it could not prove dead.
  [ "$(allow_n "$FIX")" -eq 8 ]
  run has_rule "$FIX" "Bash(git -C /tmp/wt-gone status)"
  [ "$status" -ne 0 ]
  # the duplicate collapses to exactly one surviving copy
  [ "$(jq '[.permissions.allow[] | select(. == "Bash(npm run build)")] | length' "$FIX")" -eq 1 ]
}

@test "an entry that COULD match again is left alone — four ways of could" {
  run env CONFIRM=1 python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  # no prefix rule covers it at all
  has_rule "$FIX" "Bash(npm run build)"
  # one-shot-LOOKING (a temp dir + a pid) but nothing proves it unrepeatable — the row's own
  # requested class, deliberately NOT pruned rather than pruned by spelling
  has_rule "$FIX" "Bash(rm -f /tmp/one-shot-3f9a1c/pid-8842.lock)"
  # the equality case: whether Bash(npm run test:*) also matches the bare `npm run test` is the
  # matcher's business, so it is not used as proof
  has_rule "$FIX" "Bash(npm run test)"
  # a wildcard-bearing rule is never a prune candidate (its match set is not a single literal)
  has_rule "$FIX" "Bash(gh repo *)"
}

@test "the surviving file is valid JSON with every other key preserved" {
  run env CONFIRM=1 python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  jq -e . "$FIX" >/dev/null
  [ "$(jq -r '.permissions.deny[0]' "$FIX")" = "Bash(dd:*)" ]
  [ "$(jq -r '.permissions.ask[0]' "$FIX")" = "Bash(git push --force:*)" ]
  [ "$(jq -r '.enabledMcpjsonServers[0]' "$FIX")" = "ms365" ]
  # non-Bash tools are untouched by a Bash-shadowing predicate
  has_rule "$FIX" "Read(//tmp/fixture/**)"
  has_rule "$FIX" "WebFetch(domain:example.com)"
}

@test "a timestamped backup of the pre-prune file exists and matches it byte for byte" {
  run env CONFIRM=1 python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  [ "$(backups)" -eq 1 ]
  local bak
  for bak in "$FIX".permprune-bak-*; do
    [ "$(shasum -a 256 "$bak" | awk '{print $1}')" = "$ORIG_SHA" ]
  done
}

@test "a file with nothing provably dead is not rewritten and gets no backup" {
  local clean="$BATS_TEST_TMPDIR/clean.settings.local.json"
  printf '%s\n' '{"permissions":{"allow":["Bash(git:*)","Bash(npm run build)"]}}' > "$clean"
  local sha; sha="$(shasum -a 256 "$clean" | awk '{print $1}')"
  run env CONFIRM=1 python3 "$AUDIT" --prune "$clean"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 provably-dead"* ]] || false
  [ "$(shasum -a 256 "$clean" | awk '{print $1}')" = "$sha" ]
  run bash -c 'ls "$1".permprune-bak-* 2>/dev/null' _ "$clean"
  [ "$status" -ne 0 ]
}

@test "pruning is idempotent — a second pass finds nothing left to remove" {
  run env CONFIRM=1 python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 provably-dead"* ]] || false
}

@test "an invalid-JSON settings file is SKIPPED, never truncated or rewritten" {
  local torn="$BATS_TEST_TMPDIR/torn.settings.local.json"
  printf '%s' '{"permissions":{"allow":["Bash(git:*)"' > "$torn"
  local sha; sha="$(shasum -a 256 "$torn" | awk '{print $1}')"
  run env CONFIRM=1 python3 "$AUDIT" --prune "$torn"
  [ "$status" -ne 0 ]                      # a skipped file is reported, never a silent success
  [[ "$output" == *"SKIP"* ]] || false
  [ "$(shasum -a 256 "$torn" | awk '{print $1}')" = "$sha" ]
}

@test "with no paths given, discovery stays inside HOME — an empty HOME prunes nothing" {
  # The guard that keeps every other arm honest: fixtures pass explicit paths, and the default
  # walk is rooted at HOME, which setup() has redirected into the test tmpdir.
  run python3 "$AUDIT" --prune
  [ "$status" -eq 0 ]
  [[ "$output" == *"scope: 0 settings file(s)"* ]] || false
}

# ─────────────────────── the INERT class (auto-mode drop list) ───────────────────────
#
# A SECOND, DISJOINT class: entries `--permission-mode auto` drops before rule matching, so
# they grant nothing in the mode every session on this box runs. Predicate transcribed from
# docs/research/permission-matcher-truth-2026-08-20.md §3 (`pme`→`qNt`→`gsn`/`_sn`, `PHs`).
#
# L4 applies with unusual force here, because the two poles are what the predicate IS: a false
# hit tells the operator to delete a rule that was carrying real weight. So every arm below
# pairs a dropped spelling with the NEAREST spelling §3 says survives.

INERT_FIX() { # <path> — one fixture holding both poles of every clause in §3
  cat > "$1" <<'JSON'
{
  "permissions": {
    "allow": [
      "Bash(python3:*)",
      "Bash(python3 scripts/foo.py *)",
      "Bash(node -e *)",
      "Bash(python -m pkg.module:*)",
      "Bash(npm run)",
      "Bash(npm run test:*)",
      "Bash(*)",
      "Bash(curl -sS *)",
      "Bash(curl https://api.github.com/*)",
      "Bash(wget https://x.dev/a)",
      "Bash(kubectl exec *)",
      "Bash(kubectl get pods *)",
      "Bash(gcloud logging read *)",
      "Bash(git status:*)",
      "Bash(rg:*)",
      "Agent(Explore)",
      "Read(//tmp/fixture/**)"
    ]
  }
}
JSON
}

inert_hit() { # <file> <rule> — did the report mark this rule INERT?
  # -F is load-bearing, not tidiness: a rule spelling is FULL of regex metacharacters, and as a
  # BRE `[INERT:` is an unterminated bracket expression — grep then fails for a reason that has
  # nothing to do with the report, which would make every `! inert_hit` arm below pass vacuously.
  python3 "$AUDIT" --prune "$1" | grep -qF -- "~ $2   [INERT:"
}

@test "INERT entries are REPORTED — every clause of the auto-mode drop predicate fires" {
  local f="$BATS_TEST_TMPDIR/inert.settings.json"; INERT_FIX "$f"
  # The exact count is the failure-distinct quantity: 0 means the predicate never ran, >7 means
  # it swallowed one of the survivors this fixture pairs against each hit.
  run python3 "$AUDIT" --prune "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"7 auto-mode-INERT entr(ies) of"* || "$output" == *"7 auto-mode-INERT entr(ies) ("* ]] || false
  inert_hit "$f" 'Bash(python3:*)'        # bare `<cmd>:*`
  inert_hit "$f" 'Bash(node -e *)'        # tail starts with a flag
  inert_hit "$f" 'Bash(npm run)'          # bare multi-word member
  inert_hit "$f" 'Bash(*)'                # gsn's blanket-star branch
  inert_hit "$f" 'Bash(curl -sS *)'       # nSd member with no positional argument
  inert_hit "$f" 'Bash(kubectl exec *)'   # nSd member whose first positional is a mutator
  inert_hit "$f" 'Agent(Explore)'         # PHs: every Agent rule, whatever its specifier
}

@test "the nearest SURVIVING spelling of each clause is not flagged — no false hits" {
  local f="$BATS_TEST_TMPDIR/inert.settings.json"; INERT_FIX "$f"
  # Each of these is §3's own stated counter-example to the hit directly above it.
  ! inert_hit "$f" 'Bash(python3 scripts/foo.py *)'   # narrowed by a positional
  ! inert_hit "$f" 'Bash(python -m pkg.module:*)'     # the `-m` carve-out, `:*` spelling
  ! inert_hit "$f" 'Bash(npm run test:*)'             # tail does not start with a flag
  ! inert_hit "$f" 'Bash(curl https://api.github.com/*)'  # positional carrying a URL
  ! inert_hit "$f" 'Bash(wget https://x.dev/a)'
  ! inert_hit "$f" 'Bash(kubectl get pods *)'         # `get` is not a mutating verb
  ! inert_hit "$f" 'Bash(gcloud logging read *)'      # nSd member WITH a positional
  ! inert_hit "$f" 'Bash(git status:*)'               # never on the list
  ! inert_hit "$f" 'Bash(rg:*)'
  ! inert_hit "$f" 'Read(//tmp/fixture/**)'           # non-Bash, non-Agent
}

@test "CONFIRM=1 NEVER removes an INERT entry — the drop is mode-scoped, so it is a policy call" {
  local f="$BATS_TEST_TMPDIR/inert.settings.json"; INERT_FIX "$f"
  local sha; sha="$(shasum -a 256 "$f" | awk '{print $1}')"
  run env CONFIRM=1 python3 "$AUDIT" --prune "$f"
  [ "$status" -eq 0 ]
  # Byte-identical: nothing dead lives here, and 7 inert entries must not make it a rewrite.
  [ "$(shasum -a 256 "$f" | awk '{print $1}')" = "$sha" ]
  [ "$(allow_n "$f")" -eq 17 ]
  run bash -c 'ls "$1".permprune-bak-* 2>/dev/null' _ "$f"
  [ "$status" -ne 0 ]
}

@test "the redundancy fixture reports ZERO inert — the two classes are disjoint" {
  # Guards the direction the count arms cannot: an ordinary allow list must not light up.
  run python3 "$AUDIT" --prune "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 auto-mode-INERT"* ]] || false
}

@test "autoMode.classifyAllShell=true is called out — it drops every Bash rule, fleet-wide" {
  local f="$BATS_TEST_TMPDIR/cas.settings.json"
  printf '%s\n' '{"autoMode":{"classifyAllShell":true},"permissions":{"allow":["Bash(python3:*)"]}}' > "$f"
  run python3 "$AUDIT" --prune "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *"classifyAllShell"* ]] || false
}

@test "discovery finds settings.json — the file that actually holds the entries" {
  # THE REGRESSION THIS CLOSES: the walk collected only `settings.local.json`, but
  # permission-settings-store-2026-08-20.md §1a measured "No settings.local.json exists in any
  # config dir" — all five user-level stores are `settings.json`. So a bare `--prune` scanned
  # zero of the entries it was pointed at and reported a clean bill.
  printf '%s\n' '{"permissions":{"allow":["Bash(git:*)","Bash(git status --short)"]}}' \
    > "$HOME/.claude/settings.json"
  printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"]}}' \
    > "$HOME/.claude/settings.local.json"
  run python3 "$AUDIT" --prune
  [ "$status" -eq 0 ]
  # BOTH names, and the exact count is the quantity that distinguishes a fixed walk from the
  # old one (which would report 1) and from an unbounded one (which would report more).
  [[ "$output" == *"scope: 2 settings file(s)"* ]] || false
  [[ "$output" == *"Bash(git status --short)"* ]] || false
}

@test "the plain report still works — --prune is additive, not a rewrite of the tool" {
  cat > "$HOME/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Bash(ls:*)"],"deny":[],"ask":[]}}
JSON
  run python3 "$AUDIT" 7d
  [ "$status" -eq 0 ]
  [[ "$output" == *"no data"* ]] || false
}
