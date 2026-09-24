#!/usr/bin/env bats
# validate-bash FF-GATE — the CHOKEPOINT that stops an ungated advance of the SHARED CHECKOUT.
#
# Subject: hooks/validate-bash.sh, FF-GATE span. The class (backlog 8c6606b6f048) was DETECTED and
# enforced by nothing: deploy-parity-assert.sh's provenance leg scores it UNGATED after the fact and
# .claude/commands/ship.md ("Never raw-ff the shared checkout") forbids it in prose — anchored on
# that phrase rather than a line number, which had already rotted — but a bare `git merge origin/main` /
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

# ════════════════════════════════════════════════════════════════════════════════════════════════
# THE COMMIT ARM (G1, backlog 5529482875e8). A commit in the shared checkout is not an ADVANCE, it
# is the thing that makes an advance impossible: the live layer moves by `merge --ff-only`, which
# compares ANCESTRY, so one local commit wedges the converge for the WHOLE FLEET until a human
# cures it. Measured 63 commits in 36 days, 16 hand-cures, 45+ logged DIVERGED refusals.
#
# WHY A BLANKET DENY IS SAFE HERE, WHERE IT WAS NOT FOR `reset`/`checkout`. The gate's own header
# declines those two because "every innocent spelling outnumbers the guilty one and no predicate
# here separates them". For commit the ratio is INVERTED and measured: all 63 reflog commits in
# that window are ordinary development work (23 fix / 18 docs / 11 feat / 5 test / 2 perf / 1 wip /
# 1 revert / 1 chore), and NOT ONE is machine-, desk- or bus-authored. The desk has never needed to
# commit there. The innocent population is not small, it is EMPTY — and the one shape that looks
# innocent, a session whose cwd resets to the shared checkout, is already handled by the cd walk
# that ships above: case (14) is that exact shape and it is ALLOWED.
# ════════════════════════════════════════════════════════════════════════════════════════════════

@test "(11) DENIES \`git commit\` when the CWD is the shared checkout" {
  probe "git commit -m 'some work'" "$SHARED"
  [ "$status" -eq 0 ]
  denied "$output"
  reason "$output" | grep -q 'ARITHMETICALLY IMPOSSIBLE' || false
  reason "$output" | grep -q 'new-worktree.sh' || false      # names the remedy, not just the sin (e2d8c9816 moved it off `git worktree add`)
}

@test "(12) CONTROL: the identical spelling in a WORKTREE is ALLOWED — the innocent population" {
  probe "git commit -m 'some work'" "$WT"
  ! denied "$output" || { echo "fired on the innocent population"; false; }
}

@test "(13) DENIES through \`git -C\` from anywhere — the target is named, not inherited" {
  probe "git -C $SHARED commit -m x" "$WT"
  denied "$output"
}

@test "(14) CONTROL: \`cd <worktree> && git commit\` FROM the shared checkout is ALLOWED" {
  # THE LOAD-BEARING CONTROL. The backlog row was filed needs-human on the belief that "the desk's
  # cwd resets to the shared checkout, so a blanket deny WILL break the desk". That conflates the
  # shell's STARTING cwd with the directory the commit ACTS in. _ffg_scan already tracks a
  # governing `cd`, so this — the exact shape every session on this box uses, and the one the
  # objection describes — resolves to the worktree and is untouched. If this case ever reds, the
  # objection has become true and the arm must be reconsidered, not patched.
  probe "cd $WT && git commit -m 'work in my own worktree'" "$SHARED"
  ! denied "$output" || { echo "BROKE THE ORDINARY SHAPE — the filed objection is now real"; false; }
}

@test "(15) DENIES from a SUBDIRECTORY of the shared checkout — same repo, same HEAD" {
  probe "git commit -am wip" "$SHARED/scripts"
  denied "$output"
}

@test "(16) the kill switch CC_SHARED_COMMIT_GATE=off allows it" {
  export CC_SHARED_COMMIT_GATE=off
  probe "git commit -m x" "$SHARED"
  ! denied "$output" || false
}

@test "(17) CONTROL: that kill switch is PER-ARM — it does not disarm the advance arm" {
  # A switch that silently widened to merge/pull would hand back the key to the older, narrower
  # guard while appearing to relax only the new one.
  export CC_SHARED_COMMIT_GATE=off
  probe "git merge origin/main" "$SHARED"
  denied "$output" || { echo "the commit switch disarmed the ADVANCE arm"; false; }
}

@test "(18) POSITION, not substring: \`git log\` mentioning commit is not a commit" {
  probe "git log --format=%H --grep=commit" "$SHARED"
  ! denied "$output" || { echo "matched the word, not the subcommand"; false; }
}

@test "(19) FAIL OPEN on a heredoc — a fixture that CONTAINS the words is not an invocation" {
  # The measured failure mode of the sibling git-add guard (three refusals in one session,
  # 2026-09-17): clause splitting never breaks on newlines, so a heredoc body is flattened into
  # the writer's own clause. A false deny here blocks writing a TEST.
  probe "cat > /tmp/f.bats <<'EOF'
git commit -m fixture
EOF" "$SHARED"
  ! denied "$output" || { echo "denied a heredoc that merely mentions git commit"; false; }
}

@test "(20) MUTATION CONTROL: with the SHARED-COMMIT-ARM span deleted, (11) is ALLOWED" {
  # Anchor-checked, and it must leave the ADVANCE arm intact — a mutant that disabled both would
  # credit this suite for coverage it does not have.
  grep -q '── SHARED-COMMIT-ARM BEGIN' "$HOOK" || { echo "BEGIN anchor moved"; false; }
  grep -q '── SHARED-COMMIT-ARM END' "$HOOK"   || { echo "END anchor moved"; false; }
  sed '/── SHARED-COMMIT-ARM BEGIN/,/── SHARED-COMMIT-ARM END/d' "$HOOK" > "$D/cmutant.sh"
  chmod +x "$D/cmutant.sh"
  ! diff -q "$HOOK" "$D/cmutant.sh" >/dev/null || { echo "mutation did not apply"; false; }
  bash -n "$D/cmutant.sh" || { echo "mutant is not valid — the span is not self-contained"; false; }

  probe "git commit -m x" "$SHARED" "$D/cmutant.sh"
  ! denied "$output" || { echo "still denies — something OTHER than the commit arm is doing it"; false; }

  probe "git merge origin/main" "$SHARED" "$D/cmutant.sh"
  denied "$output" || { echo "the mutant also killed the ADVANCE arm — control is too coarse"; false; }
}
