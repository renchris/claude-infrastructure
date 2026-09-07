#!/usr/bin/env bats
# `cc-venue dodspec` — the item's dodRef rendered as a TRUNK PATHSPEC, for the brief composer.
#
# WHAT THIS GUARDS, and why it is not the fix MASTER_FIRE_GATE.md § F4 prescribes. § F4's remedy is
# "make every producer write `origin/main:<path>`" — rewrite the STORE. Two arms downstream resolve
# a dodRef as a FILESYSTEM path and both fail silently on that spelling: `cc-eligible._dod_path`
# asks `os.path.isabs("origin/main:docs/…")`, gets False, and joins it onto the repo; and
# `cc-premise._plan_dodref` requires `os.path.isfile(dod)`, returns None, and FAILS OPEN — deleting
# the derived plan-open falsifier that 18 of this store's live rows depend on. So the staleness is
# cured in the BYTES THE WORKER READS and the stored path is left alone.
#
# THE THREE-ANSWER CONTRACT IS THE SUBJECT. A caller that cannot tell "not a path claim" from
# "could not ask" renders a guess, so the two are separate exits and both are tested:
#   exit 0 + one line  — resolved
#   exit 0 + NO line   — not a path claim (render the stored value verbatim)
#   exit 3             — the DoD is on no trunk commit
#   exit 4             — could not ask
# Every non-resolving answer is paired with the assertion that stdout is EMPTY, because the
# composer keys on "exit 0 AND a line" and a stray byte on any other path would be rendered.
#
# RED-PROOF (re-runnable, one command) — and the ENV OVERRIDES ARE LOAD-BEARING, not tidiness.
# 🚨 THE SHA IS A LITERAL AND MUST STAY ONE. `origin/main` advances past this fix the moment it
# lands, so a proof written against it would run the verb against ITSELF and report 0 red — a
# vacuous green, which is worse than a red because a red gets fixed (memory:
# control-must-replay-the-real-artifact). The land gate's moving-ref ratchet caught exactly this
# in the sibling suite before it landed.
#   git show 9b0410823b79c767260da077ea1bd2ee572afff5:bin/cc-venue > /tmp/pre-venue && chmod +x /tmp/pre-venue \
#     && CC_VENUE_UNDER_TEST=/tmp/pre-venue \
#        CC_VENUE_ELIGIBLE_BIN="$PWD/bin/cc-eligible" CC_VENUE_PREMISE_BIN="$PWD/bin/cc-premise" \
#        bats tests/cc-venue-dodspec.bats
# 15 of 15 fail: the verb does not exist pre-fix, so it exits 2 ("unknown verb") on every case,
# including the three that expect a nonzero exit — they assert 3 and 4 SPECIFICALLY, never merely
# "not zero".
#
# 🚨 WITHOUT THOSE TWO OVERRIDES THE PROOF IS VACUOUS FOR TWO CASES, and it fails in the flattering
# direction. cc-venue resolves its siblings relative to its OWN directory, so a copy sitting in
# /tmp cannot find `cc-eligible` and exits 3 at import — BEFORE any verb dispatch. Exit 3 is
# exactly what the "line suffix" and "absent" cases expect, so both go GREEN against a binary that
# never ran a line of the code under test. Measured: 13 of 15 red without the overrides, 15 of 15
# with them (memory: verification-harness-vacuous-pass-traps — a control must be able to fail, and
# an exit code shared by an abort and a verdict is not a verdict). The ONE case that is red pre-fix for a different and sharper reason is
# "an already-trunk-ref dodRef resolves": `_dod_candidates` treated `origin/main:docs/x.md` as a
# relative path, so `git cat-file -e origin/main:origin/main:docs/x.md` could only miss and the
# state came back `absent`. Measured on this tree before the fix: the SAME file returned `ok`
# under both the absolute and the relative spelling and `absent` under the trunk-ref one.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # The subject is overridable so the RED-PROOF in this header is one command rather than a
  # description of one: point it at `git show 9b0410823b79c767260da077ea1bd2ee572afff5:bin/cc-venue` and every case must fail.
  CV="${CC_VENUE_UNDER_TEST:-$REPO/bin/cc-venue}"

  # A REAL git repo with a REAL origin/main, because the predicate under test is `git cat-file -e`
  # against a ref. A fixture that stubbed git would test the stub's spelling of the answer, not the
  # resolution (memory: hermetic-in-stubs-not-in-interpreter).
  FIX="$BATS_TEST_TMPDIR/repo"; mkdir -p "$FIX/docs/plans"
  git init -q -b main "$FIX"
  git -C "$FIX" config user.email t@t; git -C "$FIX" config user.name t
  printf 'the spec\n' > "$FIX/docs/plans/PLAN.md"
  git -C "$FIX" add -A; git -C "$FIX" commit -qm init
  # origin/main must EXIST as a remote-tracking ref: the verb resolves against it by name.
  git -C "$FIX" update-ref refs/remotes/origin/main refs/heads/main

  # The ledger is a STUB cc-backlog, so a case controls its own dodRef. `dodref_of` reads
  # `cc-backlog list --all --json`, so that is the whole contract this stub must satisfy.
  STUB="$BATS_TEST_TMPDIR/cc-backlog"
  export CC_VENUE_BACKLOG_BIN="$STUB"
  export CC_VENUE_PREMISE=off
}

# Rewrite the stub ledger to hold exactly one item with the given dodRef.
ledger() { # <id> <dodRef>
  cat > "$STUB" <<EOF
#!/bin/bash
printf '%s\n' '[{"id":"$1","status":"open","project":"p","title":"t","dodRef":"$2"}]'
EOF
  chmod +x "$STUB"
}

# STDOUT ONLY. bats `run` merges stderr into $output, and every non-resolving answer here writes a
# DIAGNOSTIC to stderr on purpose — so asserting on $output would either forbid the diagnostic or,
# worse, pass because the diagnostic happened to be there. The composer keys on stdout alone, so
# that is the stream the contract is about. `run --separate-stderr` is unavailable on Bats 1.13.
dodspec_out() { # <args…> — stdout on fd1, stderr discarded; sets $ds_status
  ds_status=0
  ds_out="$("$CV" dodspec "$@" 2>/dev/null)" || ds_status=$?
}

@test "an ABSOLUTE dodRef into the shared checkout resolves to a trunk pathspec" {
  ledger i1 "$FIX/docs/plans/PLAN.md"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "a RELATIVE dodRef resolves to the same trunk pathspec" {
  ledger i1 "docs/plans/PLAN.md"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "an ALREADY-trunk-ref dodRef resolves — the spelling F4's own remedy would mint" {
  # THE SHARP CASE. Pre-fix this returned exit 3 `absent`, because the whole string was treated as
  # a relative path and `origin/main:origin/main:docs/…` can only miss. Anyone following § F4's
  # literal prescription would mint this spelling at scale and question 1b would then refuse the
  # newly-correct rows off-box with "your DoD is on no trunk commit".
  ledger i1 "origin/main:docs/plans/PLAN.md"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "a DEEP absolute path still resolves — the bound truncates the unresolvable end" {
  # REGRESSION, and it was found by the land gate rather than by reasoning. `_dod_candidates` caps
  # at 12 suffixes of a LONGEST-FIRST list, so on a deep enough path the twelve kept all still
  # carried the mount prefix — unresolvable by construction — and the repo-relative tail that is
  # the actual answer was discarded, yielding `absent` for a file plainly on trunk. The on-box
  # sandbox sat at 14 segments and passed; the OFF-BOX runner nests two directories deeper, hit 16,
  # and went red. This pins the property directly rather than depending on how deep a runner nests.
  local deep="$FIX/a/b/c/d/e/f/g/h/i/j/k/l/m/docs/plans/PLAN.md"
  ledger i1 "$deep"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "a NON-origin ref prefix resolves too, and the CALLER's ref is what is rendered" {
  # The stored prefix is discarded, not honoured: the composer asked for `--ref`, and rendering the
  # row's stale prefix would let a dodRef pin a worker to a ref the dispatcher did not choose.
  ledger i1 "HEAD:docs/plans/PLAN.md"
  run "$CV" dodspec i1 --repo "$FIX" --ref origin/main
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "a LINE SUFFIX is not mistaken for a ref prefix" {
  # THE GUARD'S CONTROL. `docs/plans/PLAN.md:12` splits on ':' exactly like a pathspec does; the
  # discriminator is that a ref never carries a file extension. Stripping here would leave the
  # candidate `12` and resolve some other file, or nothing — a FALSE answer, which is the one
  # direction this file must never be wrong in.
  ledger i1 "docs/plans/PLAN.md:12"
  dodspec_out i1 --repo "$FIX"
  [ "$ds_status" -eq 3 ] || { echo "status=$ds_status out=$ds_out"; false; }
  [ -z "$ds_out" ] || { echo "stdout must be empty on a non-resolution: $ds_out"; false; }
}

@test "a dodRef that is NOT a path claim answers n/a — exit 0 with NO line" {
  ledger i1 "decision:5f0a1b2c"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ -z "$output" ] || { echo "n/a must print nothing, got: $output"; false; }
}

@test "an EMPTY dodRef answers n/a — exit 0 with NO line" {
  ledger i1 ""
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ -z "$output" ] || { echo "got: $output"; false; }
}

@test "a dodRef naming a file that is on NO trunk commit is exit 3, not a rendered guess" {
  ledger i1 "$FIX/docs/plans/NEVER_LANDED.md"
  dodspec_out i1 --repo "$FIX"
  [ "$ds_status" -eq 3 ] || { echo "status=$ds_status out=$ds_out"; false; }
  [ -z "$ds_out" ] || { echo "stdout must be empty on absent: $ds_out"; false; }
}

@test "an unreadable repo is COULD NOT ASK (4), never absent (3)" {
  # Collapsing unknown into absent would let a missing checkout look like a deleted plan. The
  # composer treats 3 and 4 identically today, but the CALLER's freedom to distinguish them is the
  # property (memory: lookup-miss-is-not-absence).
  ledger i1 "docs/plans/PLAN.md"
  dodspec_out i1 --repo "$BATS_TEST_TMPDIR/no-such-repo"
  [ "$ds_status" -eq 4 ] || { echo "status=$ds_status out=$ds_out"; false; }
  [ -z "$ds_out" ] || { echo "stdout must be empty on unknown: $ds_out"; false; }
}

@test "an unreadable LEDGER is COULD NOT ASK (4), never an absent dodRef" {
  printf '#!/bin/bash\nexit 9\n' > "$STUB"; chmod +x "$STUB"
  dodspec_out i1 --repo "$FIX"
  [ "$ds_status" -eq 4 ] || { echo "status=$ds_status out=$ds_out"; false; }
  [ -z "$ds_out" ] || { echo "stdout must be empty on unknown: $ds_out"; false; }
}

@test "a missing id is answered, not crashed — it has no dodRef, so n/a" {
  ledger other "docs/plans/PLAN.md"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ -z "$output" ] || { echo "got: $output"; false; }
}

@test "the verb requires an id" {
  # THE EXIT CODE ALONE CANNOT PROVE THIS ONE. Pre-fix, `dodspec` is an UNKNOWN VERB and that also
  # exits 2, so an exit-code-only assertion goes green against a binary without the verb — the last
  # vacuous pass in this file's red-proof. The MESSAGE is what distinguishes an argument check from
  # a verb that does not exist, so it is asserted too.
  run "$CV" dodspec
  [ "$status" -eq 2 ] || { echo "status=$status out=$output"; false; }
  [[ "$output" == *"dodspec: <id> is required"* ]] || { echo "got: $output"; false; }
}

@test "a valueless --repo does not swallow the NEXT flag as its value" {
  # `_opt_value`'s own case. Without the guard, `--repo --ref origin/main` sets repo to "--ref",
  # which is a directory that does not exist — an UNKNOWN wearing a configured repo's clothes.
  ledger i1 "docs/plans/PLAN.md"
  CC_PREMISE_REPO="$FIX" run "$CV" dodspec i1 --repo --ref origin/main
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "the repo falls back to CC_PREMISE_REPO when --repo is absent" {
  ledger i1 "docs/plans/PLAN.md"
  CC_PREMISE_REPO="$FIX" run "$CV" dodspec i1
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ "$output" = "origin/main:docs/plans/PLAN.md" ] || { echo "got: $output"; false; }
}

@test "dodspec NEVER writes: the ledger stub is read-only and no venue record is emitted" {
  # The composer calls this on every fire. A verb that wrote would put a store mutation on the hot
  # path of every brief — and `cc-venue label` is the verb that is ALLOWED to write.
  #
  # COMPARED BY CONTENT, WITH NO EXTERNAL BINARY. This read `md5 -q … || md5sum …` and the land
  # gate's unattended-path ratchet refused it: `md5` lives in /sbin, which is NOT on the
  # com.claude.nightly-regression launchd job's PATH, so the suite would have died the first time
  # it ran unattended — reporting nothing about the verb. `$(<file)` is a bash expansion and needs
  # no PATH lookup at all, and the comparison it feeds is strictly stronger than a digest.
  ledger i1 "docs/plans/PLAN.md"
  local before; before="$(<"$STUB")"
  run "$CV" dodspec i1 --repo "$FIX"
  [ "$status" -eq 0 ] || { echo "status=$status"; false; }
  local after; after="$(<"$STUB")"
  [ "$before" = "$after" ] || { echo "the verb mutated its input"; false; }
}
