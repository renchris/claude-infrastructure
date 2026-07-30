#!/usr/bin/env bats
# gate-select.bats — RED-proofs for the changed-scope test selector. Every test asserts a
# FAIL-CLOSED or a coupling the naive selector misses:
#   * lib/ + hooks/lib/  → FULL   (a `^lib/`-only rule misses two thirds of shared helpers)
#   * delete / rename of CODE → FULL (the map cannot describe a path that moved out from under it)
#   * delete / rename of PROSE → the suites that NAME the vanished path (and, on a rename, the
#                       new one) — FULL there means "no smoke at all" in the v2 lane, so the
#                       blanket rung ran ZERO suites on a docs land; both ends must be prose
#   * new file        → the SAME clauses as a modified one; FULL only via the `unmapped` rung
#                       (a blanket `added ⇒ FULL` widened nearly every land to 1,749 tests)
#   * suite-comment refs → DIRECT (comments are evidence: real suites name their script only there)
#   * 3-hop chain       → selected via CLOSURE, and provably NOT via a direct clause
#                         (a depth-2 walk drops it — this is the closure-depth floor)
#   * 4-hop chain       → NOT selected: CLOSURE_DEPTH=3 is the ceiling, and 3 is the floor above
#   * doc in the chain  → NOT a relay: an index node is reached but never composed THROUGH
#                         (both bounds: clause (c) reads mentions as "uses", which an inventory
#                          inverts — unbounded, the median changed file dragged in 48 suites)
#   * stoplist stem     → the word "common" in prose does NOT drag a suite in
# Fixture git repo per test under BATS_TEST_TMPDIR; one real-repo read-only smoke test.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SEL="$REPO/scripts/gate-select.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX/scripts" "$FIX/tests" "$FIX/hooks/lib" "$FIX/bin" "$FIX/lib" "$FIX/docs" \
           "$FIX/settings-templates"
  cd "$FIX" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name tester
  seed
  git add -A
  git commit -q -m base
}

suite() {  # $1=path $2=body — a minimal bats file whose TEXT is the coupling evidence
  printf '#!/usr/bin/env bats\n@test "%s" {\n  %s\n}\n' "$(basename "$1" .bats)" "$2" > "$1"
}

seed() {
  printf 'echo install\n' > install.sh
  printf '{}\n' > settings-templates/settings.json
  printf 'desk() { :; }\n' > lib/desk.zsh
  printf 'interactive() { :; }\n' > hooks/lib/cc-interactive.sh
  printf '#!/bin/bash\necho guard\n' > hooks/guard.sh
  printf '#!/bin/bash\necho notify\n' > bin/cc-notify
  printf '#!/bin/bash\necho orphan\n' > bin/orphan-tool
  printf '#!/bin/bash\necho noise\n' > scripts/noise-source.sh
  for f in foo bar common supervisor-e2e deep-leaf doomed rename-me; do
    printf '#!/bin/bash\necho %s\n' "$f" > "scripts/$f.sh"
  done
  # the 3-hop chain: suite → alpha-entry → mid-layer → deep-leaf (refs on NON-comment lines),
  # extended one hop to abyss-leaf so the SAME chain proves both the floor (hop 3 reaches) and
  # the ceiling (hop 4 does not). Overwrites the loop's plain deep-leaf.sh — order matters.
  printf '#!/bin/bash\nsource scripts/mid-layer.sh\n' > scripts/alpha-entry.sh
  printf '#!/bin/bash\nbash scripts/deep-leaf.sh "$@"\n' > scripts/mid-layer.sh
  printf '#!/bin/bash\nbash scripts/abyss-leaf.sh "$@"\n' > scripts/deep-leaf.sh
  printf '#!/bin/bash\necho abyss\n' > scripts/abyss-leaf.sh
  suite tests/abyss.bats 'run bash scripts/abyss-leaf.sh'
  # an INDEX node: a doc that COVERS a script. The suite documenting the inventory must not be
  # dragged in by every file the inventory happens to list.
  printf '# inventory\ncovers scripts/inventoried.sh\n' > docs/inventory.md
  printf '#!/bin/bash\necho inventoried\n' > scripts/inventoried.sh
  suite tests/inventory-reader.bats 'documents docs/inventory.md'
  suite tests/inventoried.bats 'run bash scripts/inventoried.sh'
  printf '# guide\nprose\n' > docs/guide.md
  printf '# named\nprose\n' > docs/named.md
  # The prose-REMOVAL fixtures: one doc named by a suite, plus a suite that names the path it
  # is about to be renamed TO. Proving the dst end is scanned needs an owner that does NOT also
  # name the src end, so this one is kept lint-reachable by its own dedicated anchor script.
  printf '# moving\nprose\n' > docs/moving.md
  printf '#!/bin/bash\necho anchor\n' > scripts/doc-anchor.sh
  suite tests/doc-src-owner.bats 'documents docs/moving.md'
  suite tests/doc-dst-owner.bats 'will document docs/moved.md  # anchor: scripts/doc-anchor.sh'
  suite tests/foo.bats 'run bash scripts/foo.sh'
  suite tests/bar.bats 'run bash "$BAR"'
  suite tests/common-utils.bats 'run bash scripts/common.sh'
  suite tests/noise.bats 'run bash scripts/noise-source.sh  # the common case is prose'
  suite tests/alpha.bats 'run bash scripts/alpha-entry.sh'
  suite tests/lead-supervisor.bats '# drives scripts/supervisor-e2e.sh end to end'
  suite tests/docs-owner.bats 'documents docs/named.md'
  suite tests/install-wire-hooks.bats 'install wiring'
  # The ratchet suite plus the analyzer it owns — mirroring the real repo, so the suite is
  # reachable by the naming clause and the map lint stays green on this fixture.
  printf '#!/usr/bin/env python3\nprint("liveness")\n' > scripts/bats-assert-liveness.py
  suite tests/bats-assert-liveness.bats 'the dead-assertion ratchet'
}

bump() { printf 'echo touched\n' >> "$1"; git add -A; git commit -q -m change; }
gs() { run bash "$SEL" "$@" HEAD~1..HEAD; }
# $output = the --explain STDERR only: asserting the REASON pins WHICH fail-closed rung
# fired. Without it a FULL assertion passes on any rung — the rules are defence-in-depth,
# so removing the one under test still yields FULL via the next one down.
# No `$*`: all 13 call sites are bare, so the forwarding was dead — and a function that
# references positional params while never being passed any makes every bare call an SC2119,
# which the .bats shellcheck ratchet blocks on for any line a land actually writes.
gse() { run bash -c "bash '$SEL' --explain HEAD~1..HEAD 2>&1 >/dev/null"; }

# `[[ ]]` is NOT usable for a mid-body assertion: on bats 1.13.0 a failing `[[ ]]` that is
# not the test's LAST command is silently swallowed (probed: `false` and `[ ]` do fail the
# test, `[[ ]]` does not) — every such assertion would be decorative. These helpers are
# plain functions, whose non-zero return DOES propagate anywhere in the body.
has() { printf '%s\n' "$output" | grep -qxF -- "$1"; }
lacks() { ! printf '%s\n' "$output" | grep -qxF -- "$1"; }

@test "lib/ helper ⇒ FULL" {
  bump lib/desk.zsh
  gs
  [ "$status" -eq 0 ]
  [ "$output" = FULL ]
}

@test "hooks/lib/ helper ⇒ FULL (the /lib/ component rule, not ^lib/)" {
  bump hooks/lib/cc-interactive.sh
  gs
  [ "$output" = FULL ]
}

@test "deletion ⇒ FULL" {
  git rm -q scripts/doomed.sh
  git commit -q -m drop
  gs
  [ "$output" = FULL ]
  gse
  has "FULL <- deleted:scripts/doomed.sh"
}

@test "rename ⇒ FULL" {
  git mv scripts/rename-me.sh scripts/renamed.sh
  git commit -q -m move
  gs
  [ "$output" = FULL ]
  gse
  has "FULL <- renamed:scripts/renamed.sh"
}

@test "PROSE delete ⇒ the suites that still NAME it, not FULL" {
  # The docs-land defect (backlog 4a420270c9c8). A land that archives one research doc hit the
  # blanket `D ⇒ FULL` rung — and in the v2 lane FULL is read as "selection untrustworthy ⇒ NO
  # smoke" (ship-land.sh:797) and "exonerate nothing" (:1199), so the land ran ZERO suites. The
  # suite that still names the removed doc is exactly the one that can break; FULL runs none.
  git rm -q docs/named.md
  git commit -q -m archive
  gs
  [ "$status" -eq 0 ]
  [ "$output" = "tests/docs-owner.bats" ]
  gse
  has "tests/docs-owner.bats <- prose-removed:docs/named.md"
  gs --direct
  # DIRECT: a doc you are landing is never exonerated as a merely-adjacent flake.
  [ "$output" = "tests/docs-owner.bats" ]
}

@test "PROSE delete with nothing naming it ⇒ inert (empty, exit 0), not FULL" {
  git rm -q docs/guide.md
  git commit -q -m archive
  gs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "PROSE rename ⇒ BOTH ends' literal refs, not FULL" {
  # The src end is a removal (who still names the path that went away) and the dst end is an ADD
  # (who names the new one). Selecting only one end is the half-fix: the owner of the destination
  # never runs, so a suite pinned to the new doc path lands unproven.
  git mv docs/moving.md docs/moved.md
  git commit -q -m move
  gs
  [ "$status" -eq 0 ]
  has tests/doc-src-owner.bats
  has tests/doc-dst-owner.bats
  gse
  has "tests/doc-src-owner.bats <- prose-removed:docs/moving.md"
  has "tests/doc-dst-owner.bats <- prose-literal:docs/moved.md"
}

@test "rename ACROSS the prose/code boundary still ⇒ FULL (BOTH ends must be prose)" {
  # The guard on the rung above. A doc renamed INTO the code tree hands the code end a path whose
  # clause ladder was never run — which is the `unmapped` fail-closed case, not an inert doc.
  git mv docs/moving.md scripts/moving.sh
  git commit -q -m promote
  gs
  [ "$output" = FULL ]
  gse
  has "FULL <- renamed:scripts/moving.sh"
}

@test "rename of CODE into the docs tree still ⇒ FULL (the src end is the code end)" {
  git mv scripts/rename-me.sh docs/rename-me.md
  git commit -q -m demote
  gs
  [ "$output" = FULL ]
  gse
  has "FULL <- renamed:docs/rename-me.md"
}

@test "new unmapped script ⇒ FULL (via the unmapped rung, not a blanket added ⇒ FULL)" {
  printf '#!/bin/bash\necho new\n' > scripts/brand-new.sh
  git add -A
  git commit -q -m add
  gs
  [ "$output" = FULL ]
  gse
  has "FULL <- unmapped:scripts/brand-new.sh"
}

@test "new script ADDED WITH the suite that names it ⇒ that suite, NOT FULL" {
  # The fleet's dominant change shape. Under the old blanket `added ⇒ FULL` rung this widened
  # to all 124 suites, so nearly every land ran 1,749 tests and was cut under concurrency.
  printf '#!/bin/bash\necho brandnew\n' > bin/cc-brandnew
  suite tests/cc-brandnew.bats 'run bash bin/cc-brandnew'
  git add -A
  git commit -q -m add-pair
  gs
  [ "$status" -eq 0 ]
  [ "$output" != FULL ]
  has tests/cc-brandnew.bats
  # …and it is DIRECT (no flake exoneration for code you are landing)
  run bash "$SEL" --direct HEAD~1..HEAD
  has tests/cc-brandnew.bats
}

@test "added file mapped ONLY by an existing suite ⇒ that suite, NOT FULL" {
  # No new test file — the coupling is an EXISTING suite whose text names the new path.
  suite tests/adopter.bats 'run bash scripts/adopted.sh'
  git add -A
  git commit -q -m adopter
  printf '#!/bin/bash\necho adopted\n' > scripts/adopted.sh
  git add -A
  git commit -q -m add-adopted
  gs
  [ "$output" != FULL ]
  printf '%s\n' "$output" | grep -qxF -- tests/adopter.bats
}

@test "install.sh and settings-templates ⇒ FULL" {
  bump install.sh
  gse
  has "FULL <- full-trigger:install.sh"
  bump settings-templates/settings.json
  gse
  has "FULL <- settings-template:settings-templates/settings.json"
}

@test "docs-only with no owning suite ⇒ inert (empty, exit 0)" {
  bump docs/guide.md
  gs
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "doc literally named by a suite ⇒ that suite" {
  bump docs/named.md
  gs
  [ "$output" = "tests/docs-owner.bats" ]
}

@test "literal ref inside a suite COMMENT is a DIRECT selection" {
  bump scripts/supervisor-e2e.sh
  gs --direct
  has tests/lead-supervisor.bats
}

@test "3-hop chain selected by closure, not by any direct clause" {
  bump scripts/deep-leaf.sh
  gs
  has tests/alpha.bats
  gs --direct
  lacks tests/alpha.bats
}

@test "4-hop chain is NOT selected — CLOSURE_DEPTH is the ceiling over the same chain" {
  # The hop above the floor the test before this one pins. Unbounded, the walk composed a
  # MENTION graph to fixpoint and reached most of the repo from most roots: real chains ran to
  # nine hops through four inventories (host-suites.manifest → nightly-regression →
  # never-stuck-gate → a hook), which describe no dependency at all.
  bump scripts/abyss-leaf.sh
  gs
  has tests/abyss.bats
  lacks tests/alpha.bats
}

@test "an index node (doc) is REACHED but never RELAYED through" {
  # docs/inventory.md names scripts/inventoried.sh, and tests/inventory-reader.bats names the
  # doc. A doc cannot execute, so a path it lists is never a dependency OF it — composing
  # "documents" with "covers" yields a coupling that does not exist.
  bump scripts/inventoried.sh
  gs
  has tests/inventoried.bats
  lacks tests/inventory-reader.bats
}

@test "an index node is still selectable AS a target" {
  # The sink rule must not make docs unreachable — reaching one still counts, so the suite
  # that documents it is still picked when the DOC itself changes.
  bump docs/inventory.md
  gs
  [ "$output" = "tests/inventory-reader.bats" ]
}

@test "stoplist stem does not over-select" {
  bump scripts/common.sh
  gs
  has tests/common-utils.bats
  lacks tests/noise.bats
}

@test "naming convention selects tests/<stem>.bats with no literal ref" {
  bump scripts/bar.sh
  gs --direct
  [ "$output" = "tests/bar.bats" ]
}

@test "changed suite selects itself (+ the dead-assertion ratchet, clause g)" {
  # Clause (g): a changed suite must ALSO run the liveness ratchet. Selecting only itself
  # let a reintroduced dead assertion land green — the edited file's own tests still pass,
  # because a dead assertion is discarded rather than failed.
  bump tests/foo.bats
  gs
  has "tests/foo.bats"
  has "tests/bats-assert-liveness.bats"
  gse
  has "tests/bats-assert-liveness.bats <- assert-liveness:tests/foo.bats"
}

@test "clause g does not fire for the ratchet's OWN edit (no self-selection loop)" {
  bump tests/bats-assert-liveness.bats
  gs
  [ "$output" = "tests/bats-assert-liveness.bats" ]
}

@test "clause g does not drag the ratchet into a NON-suite change" {
  bump scripts/foo.sh
  gs
  has "tests/foo.bats"
  lacks "tests/bats-assert-liveness.bats"
}

@test "code file no clause maps ⇒ FULL (the unmapped rung)" {
  bump bin/orphan-tool
  gs
  [ "$output" = FULL ]
  gse
  has "FULL <- unmapped:bin/orphan-tool"
}

@test "install-wired hook change adds the install suite" {
  bump hooks/guard.sh
  gs
  has tests/install-wire-hooks.bats
}

@test "--explain names the clause, and the reason on FULL" {
  bump scripts/foo.sh
  gse
  has "tests/foo.bats <- literal:scripts/foo.sh"
  bump lib/desk.zsh
  gse
  has "FULL <- shared-lib:lib/desk.zsh"
}

@test "bad range, unresolvable rev and unknown option all fail CLOSED" {
  run bash "$SEL" HEAD
  [ "$status" -eq 0 ]
  [ "$output" = FULL ]
  run bash "$SEL" deadbeef1234..HEAD
  [ "$output" = FULL ]
  run bash "$SEL" --nope HEAD~1..HEAD
  [ "$output" = FULL ]
}

@test "multi-range: the changed sets of every range are UNIONed" {
  bump scripts/foo.sh
  bump scripts/bar.sh
  run bash "$SEL" --direct HEAD~1..HEAD
  has tests/bar.bats
  lacks tests/foo.bats
  run bash "$SEL" --direct HEAD~2..HEAD~1 HEAD~1..HEAD
  has tests/foo.bats
  has tests/bar.bats
}

@test "lint: green on a reachable tree, RED naming a planted orphan suite" {
  run bash "$SEL" lint
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  suite tests/zz-orphan-thing.bats 'run true'
  git add -A
  git commit -q -m orphan
  run bash "$SEL" lint
  [ "$status" -eq 1 ]
  has tests/zz-orphan-thing.bats
}

@test "real repo: lint green — a suite nothing selects would fail HERE (anti-rot)" {
  run bash -c "cd '$REPO' && bash scripts/gate-select.sh lint"
  [ "$status" -eq 0 ]
}

@test "real repo: HEAD~1..HEAD yields FULL or only existing tests/*.bats (read-only)" {
  run bash -c "cd '$REPO' && bash scripts/gate-select.sh HEAD~1..HEAD"
  [ "$status" -eq 0 ]
  if [ "$output" != FULL ]; then
    bad=""
    while read -r line; do
      if [ -n "$line" ]; then
        case "$line" in
          tests/*.bats) [ -f "$REPO/$line" ] || bad="$bad $line" ;;
          *) bad="$bad $line" ;;
        esac
      fi
    done <<< "$output"
    [ -z "$bad" ]
  fi
}
