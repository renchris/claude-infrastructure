#!/usr/bin/env bats
# stranded-sweep.sh — detect commits stranded on local branches (content never landed).
# Builds scratch repos (bare "origin" + working clone) in BATS_TEST_TMPDIR so
# origin/<trunk> tracking works. No network, no real repo touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SWEEP="$REPO/scripts/stranded-sweep.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m "base"
  git push -q -u origin main

  # HERMETIC: --mine reads land.log for its own-session land anchors. Without this the
  # suite would read the operator's real ~/.claude/land.log.
  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  : > "$LAND_LOG"
}

@test "clean: all commits landed → exit 0, '0 stranded'" {
  run bash "$SWEEP" main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 stranded"
}

@test "GATE 2: synthetic stranded (new file never merged) → detected in both modes" {
  # Detection is the gate. Since the fd517a5863cc damping, the per-commit sha/path/recipe
  # is the OWNER's view (--mine); default mode counts it and names its branch.
  git checkout -q -b feature
  echo hello > newfile.txt
  git add newfile.txt
  git commit -q -m "add newfile"
  sha="$(git rev-parse --short HEAD)"
  git update-ref refs/land/failed/20260812T000000Z-SID-G2-feature HEAD

  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "1 commit(s)"
  echo "$output" | grep -q "feature"

  run bash "$SWEEP" --mine SID-G2 main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "$sha"
  echo "$output" | grep -q "newfile.txt"
  echo "$output" | grep -q "cherry-pick"
}

@test "GATE 1: race simulation — sibling lands only C2, C1 stranded" {
  git checkout -q -b featureF
  echo A > fileA.txt; git add fileA.txt; git commit -q -m "C1 fileA"
  c1="$(git rev-parse --short HEAD)"
  echo B > fileB.txt; git add fileB.txt; git commit -q -m "C2 fileB"
  c2="$(git rev-parse HEAD)"

  # sibling lands ONLY C2 onto origin/main (a rebase-land that dropped C1)
  git checkout -q main
  git cherry-pick "$c2" >/dev/null 2>&1
  git push -q origin main

  git checkout -q featureF
  git update-ref refs/land/failed/20260812T000000Z-SID-G1-featureF HEAD

  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "1 commit(s)"
  echo "$output" | grep -q "featureF"

  run bash "$SWEEP" --mine SID-G1 main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "$c1"
  echo "$output" | grep -q "fileA.txt"
}

@test "false-positive guard: path also on trunk with different content → NOT flagged" {
  # both sides touch fileX; branch commit is a `+` (not patch-equiv) but fileX exists on trunk
  echo original > fileX.txt; git add fileX.txt; git commit -q -m "seed fileX"
  git push -q origin main

  git checkout -q -b diverge
  echo branchside > fileX.txt; git add fileX.txt; git commit -q -m "branch edits fileX"

  # trunk moves fileX differently (so branch commit is NOT patch-equivalent to trunk)
  git checkout -q main
  echo trunkside > fileX.txt; git add fileX.txt; git commit -q -m "trunk edits fileX"
  git push -q origin main

  git checkout -q diverge
  run bash "$SWEEP" main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 stranded"
}

# --- --mine <sid> (T-P9-4): ownership-decidable sweep. Two stranded branches with
# distinct Session-Id trailers; --mine attributes the drop, default mode is unchanged.
seed_two_owned_strands() {
  git checkout -q -b featA main
  echo aaa > fileA.txt && git add fileA.txt
  git commit -q -m "$(printf 'add fileA\n\nSession-Id: SID-A\n')"
  git checkout -q -b featB main
  echo bbb > fileB.txt && git add fileB.txt
  git commit -q -m "$(printf 'add fileB\n\nSession-Id: SID-B\n')"
}

@test "--mine: reports only own-session drop, silent on peer → exit 1, own file only" {
  seed_two_owned_strands
  run bash "$SWEEP" --mine SID-A main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileA.txt"
  ! echo "$output" | grep -q "fileB.txt" || false
  echo "$output" | grep -q "SID-A"
}

@test "--mine: only a peer is stranded → exit 0 (decidable pass)" {
  git checkout -q -b featB main
  echo bbb > fileB.txt && git add fileB.txt
  git commit -q -m "$(printf 'add fileB\n\nSession-Id: SID-B\n')"

  run bash "$SWEEP" --mine SID-A main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 own-session"
}

# --- DAMPING (backlog fd517a5863cc) -----------------------------------------------------
# The un-`--mine` verdict fired on 955 of 989 lands and printed a per-commit wall with a
# cherry-pick recipe for peer WIP that its own next line forbids cherry-picking. It is now
# a bounded count. These cases pin that; they go red against the pre-damping subject.

@test "DAMPED: default mode counts both strands but prints no per-commit wall and no recipe" {
  seed_two_owned_strands
  run bash "$SWEEP" main
  [ "$status" -eq 1 ]                              # still a REVIEW prompt — it must fire
  echo "$output" | grep -q "2 commit(s)"           # …as a count
  echo "$output" | grep -q "featA"                 # …naming the branches, not the commits
  echo "$output" | grep -q "featB"
  ! echo "$output" | grep -q "fileA.txt" || false       # no per-commit path wall
  ! echo "$output" | grep -q "recovery:" || false       # no recipe for a peer's WIP…
  ! echo "$output" | grep -q "git cherry-pick" || false # …the phrase that remains is the
                                                       # sentence FORBIDDING it
  echo "$output" | grep -q -- "--mine"             # points at the one actionable question
}

@test "DAMPED: the branch list is bounded — 5 stranded branches render 3 names + a count" {
  for n in 1 2 3 4 5; do
    git checkout -q -b "wip$n" main
    echo "x$n" > "file$n.txt" && git add "file$n.txt" && git commit -q -m "add file$n"
  done
  git checkout -q main

  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "5 commit(s)"
  echo "$output" | grep -q "(+2 more)"
  # exactly 3 branch names survive the cap (they share one line, so count occurrences)
  [ "$(echo "$output" | grep -o 'wip[0-9] (1)' | wc -l | tr -d ' ')" -eq 3 ]
}

@test "--mine accepts trunk in any arg order (--mine SID then trunk)" {
  seed_two_owned_strands
  run bash "$SWEEP" --mine=SID-B main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileB.txt"
  ! echo "$output" | grep -q "fileA.txt"
}

# --- the ORACLE: `git cherry` enumerates, the per-path content check decides ------------
# Backlog 634ecdccbc55(a). Both cases below PASS-as-clean against the pre-fix script:
# it read only `+` lines out of a `$(git cherry ... 2>/dev/null)` heredoc, so both a
# cherry FAILURE and a cherry `-` verdict reached the loop as "nothing to look at".

@test "instrument failure: unreadable branch is a NON-VERDICT, never counted clean" {
  # A ref pointing at a missing object is listed by for-each-ref but makes `git cherry`
  # exit 128 with EMPTY stdout — pre-fix, that branch was silently certified CLEAN.
  printf '%s\n' 0000000000000000000000000000000000000001 > .git/refs/heads/brokenref

  run bash "$SWEEP" main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "NO VERDICT"
  echo "$output" | grep -q "brokenref"          # names the branch it could not read
  # …and never renders the clean certificate. The non-verdict deliberately reuses the
  # words "0 stranded" (0 of the READABLE branches were), so the discriminator is the ✓.
  ! echo "$output" | grep -q "✓ stranded-sweep" || false
}

@test "instrument failure: POSITIVE CONTROL — a healthy branch in the SAME run still gets a real verdict" {
  # Guards the other direction: the new non-verdict arm must not swallow every branch.
  git checkout -q -b feat
  echo hi > newfile.txt; git add newfile.txt; git commit -q -m "add newfile"
  sha="$(git rev-parse --short HEAD)"
  git update-ref refs/land/failed/20260812T000000Z-SID-PC-feat HEAD
  git checkout -q main
  printf '%s\n' 0000000000000000000000000000000000000001 > .git/refs/heads/brokenref

  run bash "$SWEEP" --mine SID-PC main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "NO VERDICT"         # the unreadable branch is reported...
  echo "$output" | grep -q "brokenref"
  echo "$output" | grep -q "$sha"               # ...and the readable one is still judged
  echo "$output" | grep -q "newfile.txt"
}

# --- OWNERSHIP keyed on anchors that EXIST ---------------------------------------------
# Backlog 634ecdccbc55(b). Pre-fix, --mine matched only a `Session-Id:` trailer that
# nothing writes (0 of the last 500 trunk commits carry one), so every case below reported
# "0 own-session drops" — the sweep's only damping mechanism could not fire at all.

seed_anchor_strands() {
  # featA — OUR dropped work, pinned by our own failed-land ref (ship-land.sh:806-812)
  git checkout -q -b featA main
  echo aaa > fileA.txt && git add fileA.txt && git commit -q -m "add fileA"
  git update-ref refs/land/failed/20260812T000000Z-SID-A-featA HEAD
  # featB — a PEER session's unlanded WIP, pinned by THEIR failed-land ref
  git checkout -q -b featB main
  echo bbb > fileB.txt && git add fileB.txt && git commit -q -m "add fileB"
  git update-ref refs/land/failed/20260812T000100Z-SID-B-featB HEAD
  git checkout -q main
}

@test "ALARM POLARITY: --mine FIRES on an own-session drop (failed-land ref) and stays silent on the peer" {
  seed_anchor_strands
  run bash "$SWEEP" --mine SID-A main
  [ "$status" -eq 1 ]                            # counting NOT-success: it must still fire
  echo "$output" | grep -q "fileA.txt"
  echo "$output" | grep -q "cherry-pick"         # the owner still gets the recovery recipe
  ! echo "$output" | grep -q "fileB.txt" || false # the peer's WIP is not the owner's problem
}

@test "ALARM POLARITY: --mine is SILENT when only a peer's anchor matches → exit 0" {
  # The other half of the polarity control — a damped alarm that can never fire says as
  # little as one that always fires.
  seed_anchor_strands
  run bash "$SWEEP" --mine SID-Z main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 own-session"
}

@test "--mine: a SUCCEEDED land later dropped by a sibling (land.log head) → fires" {
  # The 2026-07-11 incident class itself: the land SUCCEEDED, so no failed-land ref
  # exists; the only record that the session put this content on the trunk is land.log.
  git checkout -q -b featC main
  echo ccc > fileC.txt && git add fileC.txt && git commit -q -m "add fileC"
  head="$(git rev-parse HEAD)"
  sha="$(git rev-parse --short HEAD)"
  git checkout -q main
  printf '{"ts":"2026-08-12T00:00:00Z","tool":"ship-land","branch":"featC","sid":"SID-C","verify":"ok","sweep":"clean","exit":0,"head":"%s"}\n' "$head" > "$LAND_LOG"

  run bash "$SWEEP" --mine SID-C main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "fileC.txt"
  echo "$output" | grep -q "$sha"

  # negative control on the SAME log: another session's sid matches no anchor
  run bash "$SWEEP" --mine SID-OTHER main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "0 own-session"
}

@test "cherry '-' is not landedness: patch-equivalent commit whose content is absent → flagged" {
  # Trunk lands the same patch (→ `git cherry` marks the branch commit `-`), then a later
  # trunk commit removes the file. Content is NOT on the trunk tree; cherry says landed.
  git checkout -q -b feat
  echo zzz > fileZ.txt; git add fileZ.txt; git commit -q -m "branch adds fileZ"
  sha="$(git rev-parse --short HEAD)"
  git update-ref refs/land/failed/20260812T000000Z-SID-CM-feat HEAD

  git checkout -q main
  echo zzz > fileZ.txt; git add fileZ.txt; git commit -q -m "trunk lands the same patch"
  git rm -q fileZ.txt; git commit -q -m "trunk later removes fileZ"
  git push -q origin main

  run git cherry origin/main feat
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '^- '                # the premise: cherry's own verdict is "landed"

  run bash "$SWEEP" --mine SID-CM main
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "$sha"
  echo "$output" | grep -q "fileZ.txt"
}

# ── THE FAIL-OPEN PIPELINE IN mine_match (drain recycle #242) ─────────────────────────────────────
# The sibling of scripts/worktree-gc.sh's is_live_cwd, and the second of the two members of #241's
# six-site class that its derived class guard cannot see (that guard's population is
# scripts/*-lint.sh × {in_own, in_allowlist}; this is neither).
#
# THE SHAPE. mine_match's last arm is `git show -s --format='%(trailers:…)' | grep -qxF "${MINE}"`,
# the FUNCTION-FINAL statement, so its rc is what the `! mine_match "${sha}" && return 0` at the
# candidate verdict reads. Under the `set -uo pipefail` this script declares load-bearing, a MATCH
# makes grep exit early, git show dies of SIGPIPE, and the caller is handed 141 — which reads as NOT
# MINE. The direction matters here: --mine is the machine-decidable arm (exit 1 = YOUR content was
# dropped), so an inverted answer SILENTLY DROPS the report of a genuinely stranded own commit,
# which is the one thing this mode exists to surface.
#
# LATENT, and by a wider margin than its sibling: this feed is one commit's own trailer block, and
# the header above records that NOTHING writes Session-Id/Land-Session (0 of the last 500 trunk
# commits carry one). Today the producer emits approximately nothing. It is drained because a commit
# message is not a bounded quantity and because the whole class is being closed out, not because a
# real commit is near the floor.
#
# THE REGIME IS MEASURED ON THIS SHAPE, NOT BORROWED (2026-08-26, load ~14-16, 20 trials per size,
# needle on line 1, second column counting the needle as the subject matches it):
#     external producer  cat | grep -q   safe to 55,722 B · 19/20 inverted at 65,580 · ALWAYS 87,151+
#     builtin producer   printf | grep -q (#241)  safe 37,121 · 1/20 at 55,721 · ALWAYS 87,122+
# The two bands coincide. An external producer does NOT invert earlier than a builtin one; what
# lowered the floor in #241's other row was the third STAGE, not the producer.

@test "mine_match still answers MINE on a trailer block past the pipe-buffer regime" {
  # THE BEHAVIOURAL ARM: the MECHANISM, not a spelling, so it survives a rewording of the fix. The
  # function is EXTRACTED from the shipped script and sourced, never re-implemented, so this replays
  # the real artifact (memory: control-must-replay-the-real-artifact). MINE_ANCHORS is empty on
  # purpose — that is what routes the call past the anchor loop and onto the trailer pipeline this
  # arm is about.
  local f="$BATS_TEST_TMPDIR/mine_match.sh" msg="$BATS_TEST_TMPDIR/bigtrailers.txt" sha bytes
  /usr/bin/sed -n '/^mine_match()/,/^}/p' "$SWEEP" > "$f"
  [ -s "$f" ] || { echo "mine_match not found in stranded-sweep.sh — the extractor has stopped matching" >&2; return 1; }
  { printf 'a commit whose trailer block exceeds the pipe buffer\n\n'
    printf 'Session-Id: zz-the-needle-session\n'
    awk 'BEGIN{ for (i = 1; i <= 2600; i++) printf "Session-Id: filler-%06d-aaaaaaaaaaaaaaaaaaaaaaaaaaaa\n", i }'
  } > "$msg"
  echo t > trailers.txt
  git add trailers.txt
  git commit -q -F "$msg"
  sha="$(git rev-parse HEAD)"
  bytes="$(git show -s --format='%(trailers:key=Session-Id,valueonly,separator=%x0A)' "$sha" | wc -c | tr -d ' ')"
  [ "$bytes" -ge 87151 ] || { echo "the trailer block is $bytes B — under the inverting floor, so this cannot discriminate" >&2; return 1; }

  # POSITIVE: the session named on line 1 of the block IS ours. A re-introduced -q answers 141 here.
  run bash -c "set -uo pipefail; cd '$WORK'; . '$f'; MINE='zz-the-needle-session'; MINE_ANCHORS=''; mine_match '$sha'; echo rc=\$?"
  [ "$output" = "rc=0" ] || { echo "our own session's trailer read as NOT MINE: $output" >&2; return 1; }

  # NEGATIVE: a session absent from the block must still answer non-zero, so this cannot pass by
  # always returning 0.
  run bash -c "set -uo pipefail; cd '$WORK'; . '$f'; MINE='absent-from-this-commit'; MINE_ANCHORS=''; mine_match '$sha'; echo rc=\$?"
  [ "$output" = "rc=1" ] || { echo "a peer session's sha did not answer 1: $output" >&2; return 1; }
}
