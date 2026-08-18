#!/usr/bin/env bats
# land-content-verify.sh — the CONTENT oracle that decides whether a `re-land …` backlog row still
# describes anything real.
#
# THE DEFECT IT CLOSES. `land_failure_inbox()` files a row keyed on ship-land's EXIT CODE, and
# nothing ever re-asks by content — so 24 of the 25 `re-land …` rows of the master-stranded-work
# effort were FALSE when censused against trunk, and actioning four of them would have REVERTED
# trunk. A row that cannot be falsified is a prediction, and predictions here decay within a day.
#
# THE CONTROLS ARE THE REJECTED INSTRUMENTS, and they are not decoration. Three were tried before
# this rule, and each is asserted here AGAINST THE SAME FIXTURE the oracle answers correctly — so a
# rewrite that quietly regressed to one of them cannot stay green:
#   * `rev-list --count` (control, "landed under a different sha") — reads 1, i.e. "unlanded", while
#     every path is blob-identical to trunk. 17 of the 93 live refs/land/failed/* have exactly this
#     shape; it is the false-row generator.
#   * three-dot `git diff` non-empty ⇒ unlanded (same control) — over-reports for the same reason.
#   * a TWO-DOT path set (control, "ancestor of trunk") — holds lines only the ref has, purely
#     because a sibling moved trunk on underneath it, so a two-dot oracle convicts work that is
#     literally in trunk's history. Measured: the 19 ancestor refs have a three-dot set of 0 paths
#     and a two-dot set of 77–412.
#
# EXIT 2 IS PINNED SEPARATELY FROM 0 AND 1 in both directions: the fetch-failure case answers 2 for
# a ref that the very same fixture answers 0 for once the fetch works. "I could not look" must never
# be reachable from, or collapse into, "I looked and the answer was no" (memory:
# sensor-default-off-makes-blindness-the-shipping-path).
#
# Fixtures are real git repos under $BATS_TEST_TMPDIR — a bare `up.git` as origin plus a working
# clone — never the checkout this suite lives in. No destructive verb appears anywhere: every test
# gets a fresh $BATS_TEST_TMPDIR, so nothing needs removing.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/land-content-verify.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.invalid
  export GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.invalid
  D="$BATS_TEST_TMPDIR/fx"; U="$D/up.git"; W="$D/work"
  mkdir -p "$D"
  git init -q --bare "$U"
  git init -q "$W"
  git -C "$W" symbolic-ref HEAD refs/heads/main
  printf 'sib-1\n' > "$W/sib.txt"
  git -C "$W" add -A
  git -C "$W" commit -qm seed
  git -C "$W" remote add origin "$U"
  git -C "$W" push -q origin main
  git -C "$W" fetch -q origin main
  git -C "$U" symbolic-ref HEAD refs/heads/main   # else a clone of $U checks nothing out
}

wcommit()   { git -C "$W" add -A; git -C "$W" commit -qm "$1"; }
push_main() { git -C "$W" push -q origin main; }   # NOT fetched: the SUT's own fetch must refresh it
sha()       { git -C "$W" rev-parse "${1:-HEAD}"; }
verify()    { bash "$SUT" "$@" --repo "$W"; }

# The ref carries f.txt; trunk carries byte-identical f.txt under a DIFFERENT commit — the shape of
# a branch whose work landed via a sibling's rebase. Leaves $REF set.
fx_landed_other_sha() {
  git -C "$W" checkout -q -b feat
  printf 'alpha\nbeta\n' > "$W/f.txt"; wcommit feat
  REF="$(sha)"
  git -C "$W" checkout -q main
  printf 'alpha\nbeta\n' > "$W/f.txt"; wcommit "same content, different sha"
  push_main
}

# ── the LANDED verdicts (exit 0) ─────────────────────────────────────────────────────────────────

@test "blob-identical under a DIFFERENT sha ⇒ 0 (landed)" {
  fx_landed_other_sha
  run verify "$REF"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'LANDED'
}

@test "CONTROL — both rejected instruments call that same ref UNLANDED" {
  fx_landed_other_sha
  git -C "$W" fetch -q origin main
  # `rev-list --count` sees a commit trunk does not contain and reports work to re-land…
  [ "$(git -C "$W" rev-list --count origin/main.."$REF")" -eq 1 ]
  # …and the three-dot diff is non-empty, because a landed patch still diffs against the old
  # merge-base. Both say "unlanded"; the content is on trunk. This is the false-row generator.
  [ -n "$(git -C "$W" diff origin/main..."$REF")" ]
  run verify "$REF"
  [ "$status" -eq 0 ]
}

@test "trunk is a SUPERSET of the ref's version ⇒ 0 (landed)" {
  git -C "$W" checkout -q -b feat
  printf 'A\nB\n' > "$W/h.txt"; wcommit feat
  REF="$(sha)"
  git -C "$W" checkout -q main
  printf 'A\nB\nC\n' > "$W/h.txt"; wcommit "landed, then extended"
  push_main
  run verify "$REF"
  [ "$status" -eq 0 ]
}

@test "a DELETION that also landed ⇒ 0" {
  git -C "$W" checkout -q -b feat
  git -C "$W" rm -q sib.txt; wcommit "drop sib"
  REF="$(sha)"
  git -C "$W" checkout -q main
  git -C "$W" rm -q sib.txt; wcommit "drop sib, different sha"
  push_main
  run verify "$REF"
  [ "$status" -eq 0 ]
}

@test "an ANCESTOR of trunk ⇒ 0, and says so" {
  printf 'landed\n' > "$W/f.txt"; wcommit "on trunk"
  REF="$(sha)"
  printf 'sib-2\n' > "$W/sib.txt"; wcommit "a sibling moves trunk on"
  push_main
  run verify "$REF"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'ANCESTOR'
}

@test "CONTROL — a TWO-DOT base would convict that ancestor" {
  printf 'landed\n' > "$W/f.txt"; wcommit "on trunk"
  REF="$(sha)"
  printf 'sib-2\n' > "$W/sib.txt"; wcommit "a sibling moves trunk on"
  push_main
  git -C "$W" fetch -q origin main
  # Two-dot drags in the sibling's path, whose OLDER copy the ref still carries — a line trunk
  # genuinely lacks, on a ref whose every commit is in trunk's history. Three-dot sees 0 paths.
  git -C "$W" diff --name-only origin/main "$REF" | grep -qF 'sib.txt'
  [ -z "$(git -C "$W" diff --name-only origin/main..."$REF")" ]
  [ "$(git -C "$W" rev-list --count origin/main.."$REF")" -eq 0 ]
  run verify "$REF"
  [ "$status" -eq 0 ]
}

# ── the NOT-LANDED verdicts (exit 1) ─────────────────────────────────────────────────────────────

@test "a path ABSENT from trunk ⇒ 1, and is named" {
  git -C "$W" checkout -q -b feat
  printf 'only here\n' > "$W/g.txt"; wcommit feat
  REF="$(sha)"
  run verify "$REF"
  [ "$status" -eq 1 ]
  # The MESSAGE, not just the verdict: disabling the absent-on-trunk arm leaves the fallback
  # ("blobs differ and one could not be read") reporting the same exit 1 over the same path, so an
  # assertion on the path alone credits no site (memory: per-site-mutation-attributes-coverage).
  echo "$output" | grep -qF 'g.txt — ABSENT from origin/main'
}

@test "the ref holds a LINE trunk lacks ⇒ 1" {
  git -C "$W" checkout -q -b feat
  printf 'A\nB\nZ\n' > "$W/h.txt"; wcommit feat
  REF="$(sha)"
  git -C "$W" checkout -q main
  printf 'A\nB\nC\n' > "$W/h.txt"; wcommit "trunk took a different line"
  push_main
  run verify "$REF"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF 'only in the ref'
}

@test "ONE unlanded path among landed ones ⇒ 1 (exit 0 iff EVERY path landed)" {
  git -C "$W" checkout -q -b feat
  printf 'alpha\n' > "$W/f.txt"; printf 'only here\n' > "$W/g.txt"; wcommit feat
  REF="$(sha)"
  git -C "$W" checkout -q main
  printf 'alpha\n' > "$W/f.txt"; wcommit "half of it landed"
  push_main
  run verify "$REF"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF '1 of 2 path'
}

@test "a DELETION that did NOT land ⇒ 1" {
  git -C "$W" checkout -q -b feat
  git -C "$W" rm -q sib.txt; wcommit "drop sib"
  REF="$(sha)"
  run verify "$REF"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF 'trunk still carries it'
}

@test "BINARY blobs that differ ⇒ 1 — differing bytes are content, not a non-verdict" {
  git -C "$W" checkout -q -b feat
  printf 'bin\000\001ref\n' > "$W/b.dat"; wcommit feat
  REF="$(sha)"
  git -C "$W" checkout -q main
  printf 'bin\000\001trunk-different\n' > "$W/b.dat"; wcommit "trunk's own binary"
  push_main
  run verify "$REF"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF 'b.dat'
}

@test "a path with a SPACE is looked up under its real name ⇒ 1, and is named" {
  git -C "$W" checkout -q -b feat
  printf 'only here\n' > "$W/a file.txt"; wcommit feat
  REF="$(sha)"
  run verify "$REF"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF 'a file.txt'
}

# ── the CANNOT-TELL verdicts (exit 2), pinned apart from 0 and 1 ─────────────────────────────────

@test "an unknown ref ⇒ 2, never 1" {
  run verify deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  [ "$status" -eq 2 ]
  echo "$output" | grep -qF 'cannot tell'
}

@test "no trunk to compare against ⇒ 2" {
  run verify HEAD --trunk no-such-branch --no-fetch
  [ "$status" -eq 2 ]
}

@test "no <commit-ish> at all ⇒ 2, never 0" {
  run bash "$SUT" --repo "$W"
  [ "$status" -eq 2 ]
}

@test "POSITIVE CONTROL — a broken fetch turns a 0 into a 2, on the SAME ref" {
  fx_landed_other_sha
  run verify "$REF"
  [ "$status" -eq 0 ]                                  # it can look: LANDED
  git -C "$W" remote set-url origin "$D/gone.git"
  run verify "$REF"
  [ "$status" -eq 2 ]                                  # it cannot look: NOT a verdict
  echo "$output" | grep -qF 'could not fetch'
}

@test "the FETCH is load-bearing — the same ref reads 1 off a stale trunk and 0 once refreshed" {
  # A SIBLING lands the content, from its own clone. That is the only way trunk actually goes stale
  # here: our own `git push` updates refs/remotes/origin/main as a side effect, so a fixture that
  # pushes from $W can never exercise this — the first draft of this case passed vacuously for that
  # reason (memory: harness-default-collapses-the-states-under-test).
  git -C "$W" checkout -q -b feat
  printf 'alpha\nbeta\n' > "$W/f.txt"; wcommit feat
  REF="$(sha)"
  git clone -q "$U" "$D/sibling"
  printf 'alpha\nbeta\n' > "$D/sibling/f.txt"
  git -C "$D/sibling" add -A; git -C "$D/sibling" commit -qm "the sibling lands it"
  git -C "$D/sibling" push -q origin main
  run verify "$REF" --no-fetch
  [ "$status" -eq 1 ]                                  # our origin/main is still at seed
  run verify "$REF"
  [ "$status" -eq 0 ]                                  # the script's own fetch refreshed it
}

# ── the live-layer shape ─────────────────────────────────────────────────────────────────────────

@test "resolves its own repo THROUGH a symlink, not the cwd's" {
  git -C "$W" checkout -q -b feat
  printf 'only here\n' > "$W/g.txt"; wcommit feat
  REF="$(sha)"
  mkdir -p "$W/scripts" "$D/live"
  cp "$SUT" "$W/scripts/land-content-verify.sh"
  ln -s "$W/scripts/land-content-verify.sh" "$D/live/land-content-verify.sh"
  # No --repo. A `dirname "$0"/..` that stopped at the symlink would resolve $D/live/.., which is no
  # git repo — and the fixture sha exists in no other repo, so a mis-resolution can only answer 2.
  run bash "$D/live/land-content-verify.sh" "$REF" --no-fetch
  [ "$status" -eq 1 ]
  echo "$output" | grep -qF 'g.txt'
}

# ── SUPERSESSION: value that reached trunk AND WAS THEN IMPROVED ──────────────────────────────────
# Measured 2026-08-12 against the census that motivated this script: it called 3 of 5 already-landed
# refs NOT-landed, and for 0a131da73 the single "line present only in the ref" was the exact line
# trunk replaced in 12343c527 — the bug that fix removed, reported back as "content trunk lacks".
# Because ship-land wires this as a FALSIFIER and a falsifier retracts on exit 0, a ref whose region
# trunk later rewrote could never reach exit 0 again: the rows it exists to close would stay open
# forever while the mechanism read as installed.

@test "SUPERSEDED — trunk carried this exact blob and then improved it ⇒ 0, and it SAYS so" {
  # THE REF MUST NOT BE AN ANCESTOR, and the first cut of this case got that wrong: committing v1 on
  # main and then v2 on main makes the ref an ancestor, whose three-dot path set is 0, so it takes
  # the ancestor early-exit and never reaches the arm under test — a case that passed for a reason
  # that had nothing to do with supersession. The real shape is a SIDE branch whose content reached
  # trunk under a DIFFERENT sha (a rebase copy — which is how 24 of the 25 censused rows landed),
  # after which trunk improved it.
  git -C "$W" checkout -q -b sup-side
  printf 'v1\n' > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'side v1'
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  printf 'v1\n' > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'trunk copy of v1'
  git -C "$W" push -q origin main                       # trunk now CARRIES that exact blob
  printf 'v2-improved\n' > "$W/f.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'trunk improves it'
  git -C "$W" push -q origin main
  git -C "$W" fetch -q origin main
  run git -C "$W" merge-base --is-ancestor "$ref" origin/main
  [ "$status" -ne 0 ]                                   # the fixture is only valid if it is NOT an ancestor
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "SUPERSEDED, not lost" || { echo "did not name supersession: $output"; false; }
  echo "$output" | grep -q "would REVERT" || { echo "did not warn that re-landing reverts: $output"; false; }
}

@test "CONTROL — the arm does NOT forgive everything: a blob trunk NEVER carried still ⇒ 1" {
  # Without this the fix could be `always exit 0`, which would satisfy the case above and destroy
  # the script's whole purpose (memory: alarm-polarity-and-attention-budget — count NOT-success).
  printf 'trunk-only\n' > "$W/g.txt"; git -C "$W" add -A; git -C "$W" commit -qm base; git -C "$W" push -q origin main
  git -C "$W" checkout -q -b side
  printf 'trunk-only\nnever-on-trunk\n' > "$W/g.txt"; git -C "$W" add -A; git -C "$W" commit -qm side
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "g.txt" || { echo "the genuinely-stranded path was not named: $output"; false; }
}

@test "MIXED — one superseded path and one genuinely stranded ⇒ 1, and the strand is what decides" {
  # The verdict must key on the STRAND, never on the count of differing paths. A superseded sibling
  # must not launder a real loss into a retraction — that is the direction where a wrong answer
  # costs work rather than noise.
  printf 'a1\n' > "$W/a.txt"; printf 'b1\n' > "$W/b.txt"
  git -C "$W" add -A; git -C "$W" commit -qm both; git -C "$W" push -q origin main
  git -C "$W" checkout -q -b side2
  printf 'b1\nb-never-lands\n' > "$W/b.txt"; git -C "$W" add -A; git -C "$W" commit -qm side2
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  printf 'a2-improved\n' > "$W/a.txt"; git -C "$W" add -A; git -C "$W" commit -qm improve-a; git -C "$W" push -q origin main
  git -C "$W" fetch -q origin main
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "b.txt" || { echo "the strand was not named: $output"; false; }
}

@test "the walk is BOUNDED and exhausting it does NOT forgive — LCV_HISTORY_MAX=0 ⇒ 1" {
  # Cost control that must fail SAFE: if the history walk is cut short before it can prove
  # supersession, the verdict falls through to the strand, never to a retraction.
  # Same non-ancestor shape as the SUPERSEDED case above, for the same reason: an ancestor never
  # reaches the walk, so a bound over it would be untested.
  git -C "$W" checkout -q -b bound-side
  printf 'v1\n' > "$W/h.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'side h1'
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  printf 'v1\n' > "$W/h.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'trunk copy of h1'; git -C "$W" push -q origin main
  printf 'v2\n' > "$W/h.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'trunk improves h'; git -C "$W" push -q origin main
  git -C "$W" fetch -q origin main
  run env LCV_HISTORY_MAX=0 bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 1 ]
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 0 ]
}

# ── RELOCATED: content that landed at a DIFFERENT POSITION in the same file ──────────────────────
# `diff` is POSITIONAL, so a line trunk carries at another offset is reported as ref-only and the
# path is convicted. The blob-supersession arm above cannot rescue it: trunk never carried the ref's
# whole-file blob, only its lines. That makes the miss SYSTEMATIC for exactly the file class this
# repo mandates everywhere — INTEGRATE-only, newest-first logs, where landing an entry at the top
# while the ref appended it at the bottom re-positions every line.
#
# LIVE INSTANCE (why these cases exist): refs/land/failed/20260817T072101Z-…-reland-drain-chain.
# Its docs/plans/BACKLOG_DRAIN_24_7.md was reported as "19 line(s) present only in the ref" while
# all 18 non-blank ref-only lines were present on trunk VERBATIM (grep -qxF -- each, 0 absent).
# Two `re-land …` rows sat open on that verdict for a day.

@test "RELOCATED — every ref line is on trunk at another position ⇒ 0, and it SAYS relocated" {
  # Newest-first is this repo's own log convention: the ref appended NEW at the bottom, the land put
  # it at the top. Same lines, no loss, yet positional diff calls NEW ref-only.
  printf 'OLD\n' > "$W/log.md"; git -C "$W" add -A; git -C "$W" commit -qm base; git -C "$W" push -q origin main
  git -C "$W" checkout -q -b reloc-side
  printf 'OLD\nNEW\n' > "$W/log.md"; git -C "$W" add -A; git -C "$W" commit -qm 'ref appends at bottom'
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  printf 'NEW\nOLD\n' > "$W/log.md"; git -C "$W" add -A; git -C "$W" commit -qm 'land puts it on top'
  git -C "$W" push -q origin main; git -C "$W" fetch -q origin main
  run git -C "$W" merge-base --is-ancestor "$ref" origin/main
  [ "$status" -ne 0 ]                                   # fixture is only valid if NOT an ancestor
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "RELOCATED" || { echo "did not name relocation: $output"; false; }
}

@test "CONTROL — MULTIPLICITY: the ref holds a line TWICE and trunk once ⇒ 1, still a strand" {
  # The forgiving arm is a MULTISET superset, not a set one. A set test would forgive a lost
  # duplicate — the shape of a hunk deleted from a file whose other copy survives elsewhere.
  printf 'X\n' > "$W/m.txt"; git -C "$W" add -A; git -C "$W" commit -qm base; git -C "$W" push -q origin main
  git -C "$W" checkout -q -b mult-side
  printf 'X\nX\n' > "$W/m.txt"; git -C "$W" add -A; git -C "$W" commit -qm 'ref holds it twice'
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "m.txt" || { echo "the strand was not named: $output"; false; }
}

@test "CONTROL — RELOCATION does not forgive a genuinely absent line in a reordered file" {
  # The sharp control for the arm: same reordering shape as the RELOCATED case, PLUS one line trunk
  # never carried. Relocation must not launder that away.
  printf 'OLD\n' > "$W/n.md"; git -C "$W" add -A; git -C "$W" commit -qm base; git -C "$W" push -q origin main
  git -C "$W" checkout -q -b reloc-strand
  printf 'OLD\nNEW\nLOST\n' > "$W/n.md"; git -C "$W" add -A; git -C "$W" commit -qm 'ref has an extra line'
  local ref; ref="$(git -C "$W" rev-parse HEAD)"
  git -C "$W" checkout -q main
  printf 'NEW\nOLD\n' > "$W/n.md"; git -C "$W" add -A; git -C "$W" commit -qm 'land reorders, drops LOST'
  git -C "$W" push -q origin main; git -C "$W" fetch -q origin main
  run bash "$SUT" "$ref" --repo "$W" --no-fetch
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "n.md" || { echo "the strand was not named: $output"; false; }
}
