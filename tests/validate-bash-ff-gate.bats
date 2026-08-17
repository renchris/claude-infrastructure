#!/usr/bin/env bats
# validate-bash FF-GATE — the CHOKEPOINT that stops an ungated advance of the SHARED CHECKOUT.
#
# Subject: hooks/validate-bash.sh, FF-GATE span. The class (backlog 8c6606b6f048) was DETECTED and
# enforced by nothing: deploy-parity-assert.sh's provenance leg scores it UNGATED after the fact and
# .claude/commands/ship.md:120 forbids it in prose, but a bare `git merge origin/main` /
# `git pull --ff-only` in ~/Development/claude-infrastructure advances the files, creates no
# symlinks, skips the green-stamp gate, and leaves live and checkout in perfect agreement — so
# nothing that measures a QUANTITY can see it, and nothing at all could stop it.
#
# The discriminator is REUSED, not invented (deploy-parity-assert.sh:813-822): deploy-live.sh
# rev-parses its target before merging, so the sanctioned advance always names an object name;
# every ungated path names a REF or is not a merge. Each DENY below is therefore PAIRED with the
# control that differs by exactly one lever, because a guard that always fires discriminates
# nothing (MEMORY.md alarm-polarity-and-attention-budget):
#   deny in the shared checkout ↔ (4) the identical spelling in a WORKTREE   — innocent population
#   deny `merge origin/main`    ↔ (5) `merge <sha>` — the ref-vs-SHA lever alone
#   deny                        ↔ (7) the deny's OWN prescribed remedy, fed back through the guard
# and (10) is the control that can FAIL: an anchor-checked mutant with the FF-GATE span deleted
# must ALLOW case (1), so a green suite credits this block and not the fixture
# (MEMORY.md control-must-replay-the-real-artifact, per-site-mutation-attributes-coverage).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  # Ambient seams pinned: the hook sources hooks/lib/*.sh and logs under $HOME.
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  # NEVER the real checkout — a fixture stands in for it, via the same env seam operator-readout.sh
  # already uses (CC_SHARED_CHECKOUT), so no test can advance the live layer by accident.
  export CC_SHARED_CHECKOUT="$D/shared"
  SHARED="$D/shared"; WT="$D/wt-1a2b3c4d5e6f"
  mkdir -p "$SHARED/scripts" "$WT"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

probe() { # <command> <cwd> [hook-path]
  run bash -c 'jq -nc --arg c "$1" --arg w "$2" "{tool_input:{command:\$c}, cwd:\$w}" | "$0"' \
    "${3:-$HOOK}" "$1" "$2"
}
denied() { printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; }
reason() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

@test "(1) DENIES the MEASURED incident verbatim: agent-typed pull --ff-only in the shared checkout" {
  # docs/research/land-architecture-100p-2026-08-10/E-live.md §1.2 path B, session d3b1290e.
  probe "cd $SHARED && git pull --ff-only -q origin main 2>&1 | tail -2" "$D"
  [ "$status" -eq 0 ]
  denied "$output"
  reason "$output" | grep -q 'creates no symlinks' || false
  reason "$output" | grep -q "deploy-live.sh" || false
}

@test "(2) DENIES \`git merge origin/main\` when the CWD is the shared checkout" {
  probe "git merge origin/main" "$SHARED"
  [ "$status" -eq 0 ]
  denied "$output"
}

@test "(3) DENIES it through \`git -C\` from anywhere — the target is named, not inherited" {
  probe "git -C $SHARED merge --ff-only origin/main" "$WT"
  denied "$output"
}

@test "(3b) DENIES from a SUBDIRECTORY of the shared checkout — same repo, same HEAD" {
  probe "git pull --ff-only" "$SHARED/scripts"
  denied "$output"
}

@test "(3c) DENIES the incident's MULTI-LINE form — the \`cd\` governs the NEXT line" {
  # The verbatim tool call in E-live.md §1.2 is two lines, not an `&&` chain. A cd tracked only
  # within its own clause would miss the one command this guard exists to stop.
  probe "cd $SHARED
git pull --ff-only -q origin main 2>&1 | tail -2" "$D"
  denied "$output"
}

@test "(3d) DENIES a merge CHAINED after another git command (\`git fetch && git merge …\`)" {
  probe "git fetch origin && git merge origin/main" "$SHARED"
  denied "$output"
}

@test "(3e) DENIES the TILDE spelling — a hook reads the command BEFORE the shell expands it" {
  export CC_SHARED_CHECKOUT="$HOME/Development/claude-infrastructure"
  mkdir -p "$CC_SHARED_CHECKOUT"
  probe 'cd ~/Development/claude-infrastructure && git merge --ff-only origin/main' "$D"
  denied "$output"
}

@test "(4) CONTROL — INNOCENT POPULATION: the identical spelling in a WORKTREE passes SILENTLY" {
  probe "git pull --ff-only -q origin main" "$WT"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
  # SILENTLY: not merely un-denied. A guard that answered every ff with advice would still pass
  # a `! denied` assertion, and every session's own worktree runs this command routinely.
  [ -z "$output" ] || false
}

@test "(4b) CONTROL: \`git -C <worktree>\` wins over a shared-checkout cwd" {
  probe "git -C $WT merge origin/main" "$SHARED"
  ! denied "$output" || false
}

@test "(5) CONTROL — ALLOW ITS OWN CURE: deploy-live's resolved-SHA merge passes in the checkout" {
  # The ONE lever that differs from case (2): a resolved object name instead of a ref. This is the
  # literal shape deploy-live.sh:1540 executes, so denying it would deadlock the sanctioned lane.
  probe "git merge --ff-only 7ac9d6970ce809993ede2cc0719ded82c230a053" "$SHARED"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
  [ -z "$output" ] || false
}

@test "(5b) CONTROL: deploy-live's own un-expanded line (\`merge --ff-only \"\$TARGET\"\`) passes" {
  probe 'git merge --ff-only "$TARGET"' "$SHARED"
  ! denied "$output" || false
}

@test "(5c) CONTROL: a \`cd\` into a WORKTREE first — the last cd wins, as the shell has it" {
  probe "cd $WT && git pull --ff-only origin main" "$SHARED"
  ! denied "$output" || false
}

@test "(6) CONTROL: \`git fetch\` in the shared checkout is untouched (refs ≠ HEAD)" {
  probe "git fetch origin --prune" "$SHARED"
  ! denied "$output" || false
  [ -z "$output" ] || false
}

@test "(6b) CONTROL: read-only commands that merely CONTAIN the words pass (position, not regex)" {
  probe "git log --merges -n 5 --oneline" "$SHARED"
  ! denied "$output" || false
  probe "git branch --merged origin/main" "$SHARED"
  ! denied "$output" || false
  probe "gh pr list --search 'pull merge'" "$SHARED"
  ! denied "$output" || false
}

@test "(7) CONTROL — the deny's OWN prescribed remedy passes its OWN guard" {
  # This repo has shipped the opposite (a -rf denylist that denied its own documented fix). So the
  # remedy is not eyeballed: it is EXTRACTED from the live deny message and fed back through the
  # hook, in the very directory the deny fired in.
  probe "git merge origin/main" "$SHARED"
  denied "$output"
  cure="$(reason "$output" | grep -oE 'bash [^ ]*/scripts/deploy-live\.sh')"
  [ -n "$cure" ]
  probe "$cure" "$SHARED"
  [ "$status" -eq 0 ]
  ! denied "$output" || false
  [ -z "$output" ] || false
}

@test "(8) FAILS OPEN on an undecidable target directory (never strand the deploy lane)" {
  probe 'git -C "$REPO" merge origin/main' "$WT"
  ! denied "$output" || false
}

@test "(9) the deny names the ONE sanctioned command and the escape hatch, not a menu" {
  probe "git merge origin/main" "$SHARED"
  r="$(reason "$output")"
  [ "$(printf '%s' "$r" | grep -oc 'deploy-live\.sh')" -eq 1 ]
  printf '%s' "$r" | grep -q -- '--force' || false
}

@test "(10) MUTATION CONTROL: with the FF-GATE span deleted, case (1) is ALLOWED" {
  # The pre-fix artifact, built from the REAL subject rather than hand-written: delete exactly the
  # anchored span. Anchor-checked in both directions — if the markers move, this errors instead of
  # silently certifying a mutation that never applied.
  grep -q '── FF-GATE BEGIN' "$HOOK" || { echo "FF-GATE BEGIN anchor moved — mutant cannot be built"; false; }
  grep -q '── FF-GATE END' "$HOOK"   || { echo "FF-GATE END anchor moved — mutant cannot be built"; false; }
  sed '/── FF-GATE BEGIN/,/── FF-GATE END/d' "$HOOK" > "$D/mutant.sh"
  chmod +x "$D/mutant.sh"
  ! diff -q "$HOOK" "$D/mutant.sh" >/dev/null || { echo "mutation did not apply"; false; }
  bash -n "$D/mutant.sh" || { echo "mutant is not a valid script — the span is not self-contained"; false; }

  probe "cd $SHARED && git pull --ff-only -q origin main 2>&1 | tail -2" "$D" "$D/mutant.sh"
  [ "$status" -eq 0 ]
  ! denied "$output" || { echo "the mutant still denies — something OTHER than the FF-GATE is doing the work"; false; }

  # ...and the real hook denies the identical payload. The pair is the whole claim: the block is
  # load-bearing, and nothing else in the file happens to cover this case.
  probe "cd $SHARED && git pull --ff-only -q origin main 2>&1 | tail -2" "$D"
  denied "$output"
}
