#!/usr/bin/env bats
# deploy-parity-assert.sh — the ~/bin deployment drift assertion.
#
# Guards the failure that motivated the script: bin/claude-accounts was deployed to ~/bin as a
# COPY, so a repo edit did not reach the running tool. It drifted for two days undetected while
# every consumer ran the old code, and sync.sh (which copies ~/bin BACK into the repo with no
# direction guard) would have clobbered the newer repo file with the stale copy.
#
# FULLY HERMETIC, and now literally so (2026-07-31): every case builds a fake repo + fake bindir in
# BATS_TEST_TMPDIR and drives the script via CC_PARITY_REPO / CC_PARITY_BINDIR / CC_PARITY_STRICT /
# CC_PARITY_COPY / CC_PARITY_LIVE. Nothing here reads the real ~/bin, the real ~/.claude or the real
# checkout, so it passes on a fresh clone, a worktree and CI.
#
# THAT CLAIM WAS ONCE A HALF-TRUTH, and it cost this suite its place in the gate. Two tests DID read
# the operator's live layer, and because scripts/host-suites.manifest partitions the corpus per
# FILE, listing this one file to accommodate those two excluded ALL of it: postland-verify.sh runs
# tests/*.bats MINUS the manifest, and ship-land.sh's filter_host_suites drops manifest suites from
# the land smoke. Measured on the tree at 09a0214a: a land touching scripts/deploy-parity-assert.sh
# selected exactly one direct suite — this one — which the filter then removed, so the land ran ZERO
# tests, and the exit-3 third-state guards below (7a40d5a8) were first exercised only post-deploy,
# after the change was already live. The two live tests moved to tests/deploy-parity-live.bats,
# which is what the manifest lists now; the split is pinned in both directions by the two tests
# under THE PARTITION ITSELF below, so this file cannot drift back out of the gate unnamed.
#
# The fixture $HOME is part of that: it is what lets scripts/test-hermeticity-lint.sh's rule 1 see
# the hermeticity structurally, so this suite's grandfather line in that ratchet was DELETED rather
# than carried. A suite that runs in the tree verdict has to earn it the same way every other one does.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export ASSERT="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  export MANIFEST="$REPO_ROOT/scripts/host-suites.manifest"
  # Fixture HOME: BINDIR defaults to $HOME/bin and LIVE to $HOME/.claude in the script under test,
  # so an unfixtured HOME leaves any case that forgets a CC_PARITY_* export pointed at the operator's
  # real deployment. Every case below already declares its subject explicitly; this makes forgetting
  # one a fixture miss instead of a live read.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_PARITY_REPO="$BATS_TEST_TMPDIR/repo"
  export CC_PARITY_BINDIR="$BATS_TEST_TMPDIR/bin"
  export CC_PARITY_STRICT="toolA"
  export CC_PARITY_COPY="toolB"
  mkdir -p "$CC_PARITY_REPO/bin" "$CC_PARITY_BINDIR"
  printf 'echo A v2\n' > "$CC_PARITY_REPO/bin/toolA"
  printf 'echo B v1\n' > "$CC_PARITY_REPO/bin/toolB"
  # PATH must resolve the strict tool to our fake bindir, never the operator's real one.
  export PATH="$CC_PARITY_BINDIR:$PATH"
}

@test "strict tool symlinked into the repo ⇒ LINKED, exit 0" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LINKED"* ]]
}

@test "strict tool is a STALE copy ⇒ drift, exit 1 (the 2026-07-19 regression)" {
  printf 'echo A v1\n' > "$CC_PARITY_BINDIR/toolA"     # the old, drifted content
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]] || false
  [[ "$output" == *"toolA"* ]]
}

@test "strict tool is a copy that currently MATCHES ⇒ still drift (it will rot again)" {
  cp "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"   # identical today, copy not link
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNLINKED"* ]]
}

@test "strict tool not deployed at all ⇒ MISSING, exit 1" {
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING"* ]]
}

@test "copy-class tool differing ⇒ drift, but the strict tool stays LINKED" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  printf 'echo B v0\n' > "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LINKED"* ]] || false
  [[ "$output" == *"STALE"*  ]]
}

@test "an earlier PATH entry shadowing the strict tool is caught even when ~/bin is correct" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  mkdir -p "$BATS_TEST_TMPDIR/shadow"
  printf 'echo A imposter\n' > "$BATS_TEST_TMPDIR/shadow/toolA"
  chmod +x "$BATS_TEST_TMPDIR/shadow/toolA"
  PATH="$BATS_TEST_TMPDIR/shadow:$PATH" run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SHADOWED"* ]]
}

# ── PATH-REACHABILITY IS THE CALLER'S PROPERTY, NOT THE DEPLOYMENT'S (2026-07-29) ───────────────
# "not on PATH" used to set drift, which made the verdict a function of WHO CALLED the script: a
# daemon whose PATH lacks $BINDIR was told "DRIFT — the code running is not the code in this
# checkout" while every filesystem leg read LINKED/OK. Both launchd plists that drive this repo's
# deploy path export a PATH without $HOME/bin, so the false alarm was real and only masked by
# claude-accounts also being linked into ~/.claude/bin. The three cases below pin the split.

@test "strict tool not on THIS caller's PATH ⇒ advisory PATHGAP, exit 0 (the daemon false alarm)" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  PATH=/usr/bin:/bin run "$ASSERT"          # a PATH that cannot see $CC_PARITY_BINDIR
  [ "$status" -eq 0 ]
  [[ "$output" == *"PATHGAP"* ]] || false
  [[ "$output" != *"DRIFT"* ]]
}

@test "CC_PARITY_REQUIRE_PATH=1 keeps the strict verdict — detection is moved, never deleted" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  PATH=/usr/bin:/bin CC_PARITY_REQUIRE_PATH=1 run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOPATH"* ]] || false
  [[ "$output" == *"DRIFT"* ]]
}

@test "SHADOWED is still drift while reachability is advisory (the split kept the real check)" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  mkdir -p "$BATS_TEST_TMPDIR/shadow"
  printf 'echo A IMPOSTOR\n' > "$BATS_TEST_TMPDIR/shadow/toolA"
  # Default (advisory) reachability — the shadow must still convict on its own.
  PATH="$BATS_TEST_TMPDIR/shadow:/usr/bin:/bin" run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SHADOWED"* ]] || false
  [[ "$output" != *"PATHGAP"* ]]
}

@test "a tool absent from the checkout is skipped, not reported as drift" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  CC_PARITY_COPY="toolB toolZZ" run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"toolZZ"* ]]
}

# ── THE PARTITION ITSELF (2026-07-31) — this file's own admission ticket to the gate ─────────────
# The two assertions below are why the 29 hermetic tests in this file are allowed to run in the
# tree verdict and the land smoke at all. They pin BOTH directions of the file split, because a
# one-directional pin cannot see the drift that matters: asserting only that the live suite is
# listed would stay green if this file were re-listed beside it, which is the exact state the split
# undid. Cheap tree reads (the manifest and the sibling path), so they cost the gate nothing.
@test "the partition: this HERMETIC suite is NOT a host suite (it must run in the tree verdict)" {
  # RED before the split, green after — not a vacuous absence assertion. tests/deploy-parity.bats
  # WAS on this list, which is what rode all 31 tests out of the land gate and the tree verdict and
  # left the exit-3 third-state guards below running only post-deploy, after the change was live.
  [ -f "$MANIFEST" ]                                    # the absence claim needs a subject to be about
  run grep -qxF 'tests/deploy-parity.bats' "$MANIFEST"
  # EXACTLY 1, never a bare `!`. grep has three outcomes and this repo has already paid for
  # collapsing two of them (afaf40de: rc=2 under fork exhaustion read as "no match" and fabricated
  # hermeticity LEAKs). 0 = listed, the regression this pins · 1 = ran and found nothing, the only
  # honest green · >=2 = could not run, which is a fact about the machine and must not read as pass.
  [ "$status" -eq 1 ]
}

@test "the partition: the LIVE half exists and IS a host suite (detection moved, never deleted)" {
  # The other direction, and the control for the test above: the split must not have simply DELETED
  # the live-layer coverage. Without this, the test above is satisfiable by dropping the live tests
  # on the floor. tests/deploy-parity-live.bats holds the two that resolve the real ~/bin and
  # ~/.claude, and deploy-live.sh runs exactly the manifest lines post-deploy against that layer.
  [ -f "$REPO_ROOT/tests/deploy-parity-live.bats" ]
  run grep -qxF 'tests/deploy-parity-live.bats' "$MANIFEST"
  [ "$status" -eq 0 ]
}

# ── EXISTENCE PARITY (2026-07-25) — the bare-ff deploy hole ──────────────────────────────────────
# ~/.claude/{hooks,hooks/lib,commands,scripts,bin} are real dirs of PER-FILE symlinks, so a
# BRAND-NEW tracked file is never linked at all, however current the checkout — only ./install.sh
# links it, and the operator's documented deploy step (ff-sync) cannot. That shipped live:
# hooks/lib/cc-interactive.sh landed unlinked, collapsing all three of cc-classify's resolve
# candidates and silently disabling the operator-adoption hold (a reaper fail-OPEN).
# Still fully hermetic: a throwaway git checkout + a fake live root under BATS_TEST_TMPDIR.

_livefix() {   # real checkout + empty live root; ~/bin legs made to PASS so exit code isolates this leg
  # `git -C ""` is a NO-OP, not an error — an empty $CC_PARITY_REPO would write this identity into
  # the caller's repo. Guarded at the BINDING (once, here) so every use site below reads bare.
  : "${CC_PARITY_REPO:?_livefix: repo path required}"
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  git -C "$CC_PARITY_REPO" init -q
  git -C "$CC_PARITY_REPO" config user.email t@t
  git -C "$CC_PARITY_REPO" config user.name t
}
_track() { git -C "$CC_PARITY_REPO" add -A >/dev/null 2>&1; }   # ls-files reads the INDEX; no commit needed

@test "existence: a tracked runtime file with NO live counterpart ⇒ the exact ln -sf, exit 1" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-interactive.sh"     # the real 2026-07-25 landmine
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf $CC_PARITY_REPO/hooks/lib/cc-interactive.sh $CC_PARITY_LIVE/hooks/lib/cc-interactive.sh"* ]]
}

@test "existence: the same file symlinked live ⇒ no miss, exit 0" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-interactive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-interactive.sh" "$CC_PARITY_LIVE/hooks/lib/cc-interactive.sh"
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

@test "existence: a DANGLING live symlink still counts as missing (resolving, not merely present)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-interactive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/gone.sh" "$CC_PARITY_LIVE/hooks/lib/cc-interactive.sh"   # target absent
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf"* ]] || false
  [[ "$output" == *"cc-interactive.sh"* ]]
}

@test "existence: all seven install.sh-linked classes are asserted (hooks, hooks/lib, commands, scripts, limit-recover, bin/cc-*, skills)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO"/{hooks/lib,commands,scripts/limit-recover,bin,skills/a-skill}
  printf 'x\n' > "$CC_PARITY_REPO/hooks/a-hook.sh"
  printf 'x\n' > "$CC_PARITY_REPO/hooks/lib/a-lib.sh"
  printf 'x\n' > "$CC_PARITY_REPO/commands/a-cmd.md"
  printf 'x\n' > "$CC_PARITY_REPO/scripts/a-script.sh"
  printf 'x\n' > "$CC_PARITY_REPO/scripts/limit-recover/lr-any-ext.py"     # limit-recover globs ALL types
  printf 'x\n' > "$CC_PARITY_REPO/bin/cc-thing"
  printf 'x\n' > "$CC_PARITY_REPO/skills/a-skill/SKILL.md"                 # skills/<name>/* — the 07-27 live gap
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^MISSING: ln -sf')" -eq 7 ]
  for f in hooks/a-hook.sh hooks/lib/a-lib.sh commands/a-cmd.md scripts/a-script.sh \
           scripts/limit-recover/lr-any-ext.py bin/cc-thing skills/a-skill/SKILL.md; do
    [[ "$output" == *"$CC_PARITY_REPO/$f $CC_PARITY_LIVE/$f"* ]] || false
  done
}

# CORRECTED 2026-08-10 (P6). This case used to seed `lib/thing.sh` with the comment "top-level lib/
# — install.sh has NO lib leg", and to require exit 0 over it. That was true when written and became
# FALSE at 931641a4, which added install.sh:360 `for zlib in "$REPO_DIR"/lib/*.zsh
# "$REPO_DIR"/lib/*.sh`. From that commit on, this test was pinning the ABSENCE of a check the tree
# needed — a stale assertion inverted into a guard for the bug, and it stayed green for weeks
# because the fixture's clean exit 0 is indistinguishable from the correct one. lib/ moved to the
# case below that demands it; what remains here is only what install.sh genuinely does not glob.
@test "existence: files install.sh does NOT link are never asserted (no false demands)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO"/{hooks/other,commands/sub,scripts/sub,scripts/limit-recover/deep,bin/cc-dir,skills/a-skill/refs,lib/sub,agents/sub}
  printf 'x\n' > "$CC_PARITY_REPO/hooks/README.md"                  # hooks/*.md — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/hooks/other/nested.sh"            # hooks/<subdir>/ — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/commands/sub/nested.md"           # commands/<subdir>/ — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/scripts/sub/nested.sh"            # scripts/ is top-level only
  printf 'x\n' > "$CC_PARITY_REPO/scripts/limit-recover/deep/x.sh"  # limit-recover is top-level only
  printf 'x\n' > "$CC_PARITY_REPO/bin/cc-dir/nested"                # bin/cc-*/ subdir — not a file link
  printf 'x\n' > "$CC_PARITY_REPO/bin/other-tool"                   # bin/ non-cc-*, non-desk-* — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/skills/a-skill/refs/deep.md"      # skills/<name>/<subdir>/ — one level only
  printf 'x\n' > "$CC_PARITY_REPO/skills/stray.md"                  # a file directly in skills/ — not a skill dir
  printf 'x\n' > "$CC_PARITY_REPO/lib/sub/nested.sh"                # lib/<subdir>/ — install.sh globs lib/ top-level only
  printf 'x\n' > "$CC_PARITY_REPO/lib/notes.md"                     # lib/*.md — only *.sh and *.zsh are globbed
  printf 'x\n' > "$CC_PARITY_REPO/agents/sub/nested.md"             # agents/<subdir>/ — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/agents/notes.txt"                 # agents/*.md only
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

@test "existence: a fixture repo that is not a checkout skips the leg (keeps the ~/bin cases hermetic)" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  mkdir -p "$CC_PARITY_REPO/hooks/lib"                              # present but NOT tracked (no .git)
  printf 'x\n' > "$CC_PARITY_REPO/hooks/lib/cc-interactive.sh"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

# ── STAGED-PENDING (2026-07-30) — the third state between linked and drift ───────────────────────
# A settings-wired hook is deliberately left UNLINKED until its staged activation script runs: the
# missing link IS the signal that the wiring is pending, which is why deploy-link-parity.sh REPORTS
# instead of repairing. This leg had no such notion and convicted the live layer for obeying that
# design — every staging became a permanent false RED. Measured at 5d85e916: this assert said
# 7 MISSING where deploy-link-parity, over the same tracked set, said "2 staged-pending · 5
# actionable". The 5 stay MISSING below; only the owned 2 are reclassified.
_pendfix() {   # a staged activation naming <path>, un-run; $1 = repo-relative path it owns
  mkdir -p "$CC_PARITY_LIVE/autonomy/pending-activation"
  printf '#!/bin/bash\nln -sfn "$REPO/%s" "$CFG/%s"\n' "$1" "$1" \
    > "$CC_PARITY_LIVE/autonomy/pending-activation/22-thing-activate.sh"
}

@test "existence: unlinked BUT owned by an UN-RUN staged activation ⇒ PENDING, not drift, exit 0" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks"
  printf 'x\n' > "$CC_PARITY_REPO/hooks/qos-rewrite.sh"
  _pendfix hooks/qos-rewrite.sh
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDING"* ]] || false
  [[ "$output" == *"22-thing-activate.sh"* ]] || false
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

# The control that must be able to FAIL the same way: once the operator has run the activation, an
# unlinked file is a REAL gap again. Without this, the fix above could be a blanket amnesty.
@test "existence: a .done-marked activation no longer excuses the file ⇒ MISSING, exit 1" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks"
  printf 'x\n' > "$CC_PARITY_REPO/hooks/qos-rewrite.sh"
  _pendfix hooks/qos-rewrite.sh
  touch "$CC_PARITY_LIVE/autonomy/pending-activation/22-thing-activate.sh.done"
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf"* ]] || false
  [[ "$output" != *"PENDING"* ]]
}

# The silent-failure direction: a loose basename match would launder a genuinely inert file into a
# false all-clear. An activation must spell the repo-relative PATH (it needs it to build $REPO/<p>).
@test "existence: a BARE BASENAME mention does not excuse an unlinked file (path-matched)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks" "$CC_PARITY_LIVE/autonomy/pending-activation"
  printf 'x\n' > "$CC_PARITY_REPO/hooks/qos-rewrite.sh"
  printf '#!/bin/bash\n# mentions qos-rewrite.sh but never the path\n' \
    > "$CC_PARITY_LIVE/autonomy/pending-activation/22-thing-activate.sh"
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf"* ]] || false
}

@test "existence: a PENDING file alongside a REAL miss ⇒ still exit 1, and only the real one is MISSING" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks" "$CC_PARITY_REPO/scripts"
  printf 'x\n' > "$CC_PARITY_REPO/hooks/qos-rewrite.sh"
  printf 'x\n' > "$CC_PARITY_REPO/scripts/render-census.sh"      # no owner — genuinely inert
  _pendfix hooks/qos-rewrite.sh
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^MISSING: ln -sf')" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf $CC_PARITY_REPO/scripts/render-census.sh"* ]] || false
  [[ "$output" == *"PENDING"* ]] || false
}

# THE REMEDY IS PART OF THE VERDICT. f0186bbd taught this leg to CLASSIFY staged-pending but left it
# prescribing "run ./install.sh" — and install.sh globs hooks/*.sh + scripts/*.sh unconditionally
# with zero pending-awareness, so following that advice links the PENDING file and erases the very
# signal the same output just reported. A correct classification with a state-destroying remedy is
# still a defect; these two pin both halves. RED-proof: pre-fix the bare recommendation is present.
@test "existence: a PENDING file present ⇒ the remedy steers to ln -sf, never a bare ./install.sh" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks" "$CC_PARITY_REPO/scripts"
  printf 'x\n' > "$CC_PARITY_REPO/hooks/qos-rewrite.sh"
  printf 'x\n' > "$CC_PARITY_REPO/scripts/render-census.sh"      # no owner — a genuine miss
  _pendfix hooks/qos-rewrite.sh
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Do NOT run ./install.sh"* ]] || false
  [[ "$output" == *"run the ln -sf lines above"* ]] || false
  [[ "$output" != *"run ./install.sh (or the ln -sf lines above)"* ]]
}

# The control that must keep passing: with NOTHING pending, install.sh IS the right remedy and the
# guidance must survive intact. Without this, the fix above could silently delete the advice
# outright — detection moved, not deleted, is the same rule the PATHGAP split above follows.
@test "existence: no PENDING file ⇒ ./install.sh remains the recommended remedy" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/scripts"
  printf 'x\n' > "$CC_PARITY_REPO/scripts/render-census.sh"      # a genuine miss, no pending anywhere
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"run ./install.sh (or the ln -sf lines above)"* ]] || false
  [[ "$output" != *"Do NOT run ./install.sh"* ]]
}

# Regression, measured 2026-07-27 minutes after the existence leg landed: invoked by its DEPLOYED
# path the assert returned RC=1 "claude-accounts must be a symlink" while the same file returned
# RC=0 from the checkout — opposite verdicts, and the DRIFT claim was the false one. Cause: a bare
# dirname "$0" yields ~/.claude (not a git repo), so REPO became ~/.claude and every correctly
# linked tool was compared against ~/.claude/bin/<tool>. A guard that false-REDs through its own
# deployed path trains readers to ignore it — which is how the drift it exists to catch survived.
#
# The OUTCOME half of that pair — the two invocations actually agreeing — needs the real ~/bin to
# make the verdicts diverge under the bug, so it lives in tests/deploy-parity-live.bats and runs
# post-deploy. What stays here is the MECHANISM: a text grep, hermetic, and therefore able to catch
# a removal of the resolution loop in the land gate rather than after the change is already live.
@test "resolving \$0 through symlinks is present (the mechanism, not just the outcome)" {
  grep -q 'while \[ -L "\$_self" \]' "$ASSERT" || false
}

# ── THE THIRD STATE: "could not compare" is not parity (2026-07-29, backlog 816015ecb30b) ─────────
# tm-closure-a finding #3 said this script "silently no-ops when invoked via its live symlink". Half
# of that was already fixed by f94d9631 (the two tests above pin it). The half that SURVIVED is the
# consequence, not the cause: every leg here is written to SKIP what it cannot find — the strict loop
# on `[ ! -f "$src" ]`, the COPY and PATH loops via a silent `continue`, the existence leg behind
# `[ -e "$REPO/.git" ]` — so ANY route that leaves the script without a real subject made all of them
# skip and still exit 0: "the code running IS the code in this checkout", about a checkout it never
# located. Exit 0 (parity) and 1 (drift) both CLAIM a comparison happened. When none did, the answer
# is neither — exit 3. Each test below pins the EXACT exit code, never merely `-ne 0`: a guard whose
# proof accepts any non-zero cannot tell a no-verdict from the drift it exists to report.

@test "a DERIVED repo that is not a checkout ⇒ NO VERDICT exit 3, never a vacuous 0" {
  # A COPY of the script into a non-repo: $0 resolves fine, and lands somewhere that is not a
  # checkout. Pre-fix this printed a single `SKIP claude-accounts` line and returned 0 (measured).
  # CC_PARITY_* must all be UNSET — CC_PARITY_REPO short-circuits the derivation under test.
  d="$BATS_TEST_TMPDIR/nonrepo"; mkdir -p "$d/scripts"
  cp "$ASSERT" "$d/scripts/deploy-parity-assert.sh"
  run env -u ITERM_SESSION_ID -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY -u CC_PARITY_LIVE bash "$d/scripts/deploy-parity-assert.sh"
  [ "$status" -eq 3 ]
  [[ "$output" == *"CANNOT DETERMINE"* ]]
}

# The guard names its own path as a literal, so a rename would make it fire on every invocation.
# That is fail-CLOSED (loud), but this pins it so the rename is caught here instead of in production.
@test "the self-path named by the derivation guard exists in the tree (a rename cannot rot silently)" {
  grep -q '\[ ! -f "\$REPO/scripts/deploy-parity-assert.sh" \]' "$ASSERT" || false
  [ -f "$REPO_ROOT/scripts/deploy-parity-assert.sh" ]
}

# `diff` has THREE outcomes: 0 same, 1 differ, >=2 COULD NOT RUN. The script collapsed >=2 into the
# `else` that reports STALE, so a diff that could not run fabricated drift about byte-identical
# files. Measured 2026-07-29: `STALE  toolB  copy differs from repo` + exit 1 under the DRIFT banner.
# Same shape this repo already paid for once with a bare `grep -q` whose rc=2 under fork exhaustion
# fabricated hermeticity LEAKs naming clean suites (afaf40de / ed4e6c6a; scripts/host-suites.manifest).
@test "a diff that CANNOT RUN (rc≥2) ⇒ NOVERDICT exit 3, never fabricated STALE drift" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"   # BYTE-IDENTICAL: "same" is the only honest verdict
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  fake="$BATS_TEST_TMPDIR/fakebin"; mkdir -p "$fake"
  printf '#!/bin/sh\nexit 2\n' > "$fake/diff"; chmod +x "$fake/diff"
  PATH="$fake:$PATH" run "$ASSERT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NOVERDICT"* ]] || false
  [[ "$output" != *"STALE"* ]]
}

# A genuine difference must STILL be drift — the positive control. Without it the test above is
# satisfiable by a script that simply stopped detecting drift at all.
@test "a diff that CAN run still reports a real difference as drift (the fix removed no detection)" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  printf 'echo B DIFFERENT\n' > "$CC_PARITY_BINDIR/toolB"
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
}

# The existence leg inlined `$(git ls-files …)` in its heredoc, discarding git's rc — so a FAILED
# listing was indistinguishable from an empty one: zero loop iterations, `missing` 0, parity reported.
# This is the leg that catches the unlinked-new-file class, so a silent zero here is the worst placed
# of the three. Hermetic, no stubbing: a DANGLING gitfile is what a linked worktree becomes once its
# main .git is gone — `[ -e "$REPO/.git" ]` passes and ls-files fails.
@test "existence: a FAILED tracked-file listing ⇒ NOVERDICT exit 3, never 'nothing missing'" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  printf 'gitdir: /nonexistent\n' > "$CC_PARITY_REPO/.git"
  run "$ASSERT"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NOVERDICT"* ]] || false
  [[ "$output" == *"(existence)"* ]]
}

# A real drift and a no-verdict can co-occur (one tool differs, another's diff could not run). The
# NAMED failure must win: it is a positive observation about the subject, where the no-verdict is a
# fact about the machine. Same rule deploy-live.sh's host_checks applies (R6).
@test "a named drift OUTRANKS a co-occurring no-verdict (exit 1, not 3)" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  printf 'echo B DIFFERENT\n' > "$CC_PARITY_BINDIR/toolB"      # a REAL difference
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  printf 'gitdir: /nonexistent\n' > "$CC_PARITY_REPO/.git"     # AND a failed enumeration
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
}

# ── THIRD LEG: DEPLOY PROVENANCE (2026-07-31) — the bare-ff deploy, caught by its CAUSE ──────────
# ship.md:98 names this script "the check that catches a bare-ff deploy after the fact", and until
# this leg it could not: a raw `git merge --ff-only origin/main` leaves live and checkout in PERFECT
# agreement, so every leg above reads clean by construction. What made it urgent is 70d86739, which
# made deploy-live's link_refresh unconditional — it now repairs the unlinked-new-file residue on
# every 600s tick INCLUDING the refusing ones, erasing the last downstream trace while the ungated
# advance continues. Measured on the live host with this leg in place: the ~/bin and existence legs
# reported zero findings and provenance reported UNGATED + UNVERIFIED, i.e. it was the only thing
# left that could see the defect that five prior sessions each closed as "drift at its minimum".
# These cases stay in THIS file (not the -live sibling) because they are fully hermetic: the
# admission rule there is "lets the assert resolve the REAL ~/bin or ~/.claude", and every case
# below declares its own repo, live root and stamps dir under $BATS_TEST_TMPDIR.

_provfix() {   # ~/bin legs made to PASS so the exit code isolates this leg; provenance forced ON
  # Guarded at the BINDING — see _livefix. `git -C ""` is a NO-OP, so an empty path would land the
  # fixture identity in the caller's repo.
  : "${CC_PARITY_REPO:?_provfix: repo path required}"
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  export CC_PARITY_LIVE="$BATS_TEST_TMPDIR/live"; mkdir -p "$CC_PARITY_LIVE"
  export CC_PARITY_PROVENANCE=1
  # Absent by default, so the CONTENT fact is unclaimed unless a case opts in — that keeps the
  # mechanism cases measuring one thing. mkdir'd only where the verification fact is the subject.
  export CC_PARITY_STAMPS="$BATS_TEST_TMPDIR/stamps"
  # PINNED, not left to default. PAGES falls back through deploy-live's OWN seam CC_PAGES_DIR, which
  # is an absolute path independent of the fixture HOME above — so an inherited one would point every
  # case below at the operator's real pages dir, where a genuine deploy-degraded-*.page could make the
  # DEGRADED case pass without the fixture writing anything. Absent by default, same as stamps.
  export CC_PARITY_PAGES="$BATS_TEST_TMPDIR/pages"
  git -C "$CC_PARITY_REPO" init -q
  git -C "$CC_PARITY_REPO" config user.email t@t
  git -C "$CC_PARITY_REPO" config user.name t
  git -C "$CC_PARITY_REPO" config core.logAllRefUpdates true   # the reflog IS the subject here
  git -C "$CC_PARITY_REPO" commit -q --allow-empty -m base
  _BASE="$(git -C "$CC_PARITY_REPO" rev-parse HEAD)"
  git -C "$CC_PARITY_REPO" commit -q --allow-empty -m landed
  git -C "$CC_PARITY_REPO" update-ref refs/remotes/origin/main HEAD
  git -C "$CC_PARITY_REPO" reset -q --hard "$_BASE"            # back to the pre-deploy live tip
}
_ff_raw()   { git -C "$CC_PARITY_REPO" merge -q --ff-only origin/main; }                       # ungated
_ff_gated() { git -C "$CC_PARITY_REPO" merge -q --ff-only \
                "$(git -C "$CC_PARITY_REPO" rev-parse refs/remotes/origin/main)"; }            # deploy-live's shape
_stamp_green() {   # stamp the CURRENT HEAD tree green, exactly as postland-verify keys them
  mkdir -p "$CC_PARITY_STAMPS"
  printf '{"verdict":"green"}\n' \
    > "$CC_PARITY_STAMPS/$(git -C "$CC_PARITY_REPO" rev-parse 'HEAD^{tree}').json"
}

@test "provenance: a raw \`merge origin/main\` ff ⇒ UNGATED, exit 1 (29 of the last 30 live advances)" {
  _provfix; _ff_raw
  run "$ASSERT"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'UNGATED'
  printf '%s' "$output" | grep -q 'merge origin/main'          # the actual reflog subject is quoted back
}

# The leg must be able to say YES, or "UNGATED" carries no information. Same repo, same commits,
# same resulting HEAD — only the spelling of the merge argument differs, which is precisely the
# discriminator: deploy-live rev-parses its target, every ungated path names a ref.
@test "provenance: deploy-live's resolved-SHA ff ⇒ GATED, exit 0 (not an always-red alarm)" {
  _provfix; _ff_gated
  run "$ASSERT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^  GATED'
  if printf '%s' "$output" | grep -q 'UNGATED'; then false; fi
}

# Reflogs are local and expire (gc.reflogExpire, 90d) and a fresh clone has none. "I cannot tell"
# must never borrow the pass — the same third-state doctrine the diff and ls-files guards above pin.
@test "provenance: an expired/absent HEAD reflog ⇒ NOVERDICT exit 3, never a silent pass" {
  _provfix; _ff_raw
  # The WHOLE logs dir, not just logs/HEAD: HEAD is a symref, and git falls back to the branch's
  # own reflog when the HEAD log is absent — so deleting one file leaves the subject still readable
  # and this case would have passed for the wrong reason (measured: it did, returning exit 1).
  rm -rf "$CC_PARITY_REPO/.git/logs"
  run "$ASSERT"
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'NOVERDICT'
  printf '%s' "$output" | grep -q '(provenance)'
}

# THE NON-REGRESSION PIN for the other 31 cases in this file. Every one of them declares
# CC_PARITY_REPO against a fixture whose reflog is nothing like a sanctioned deploy, so a leg that
# ran on the declared path would have turned this entire suite red. Non-vacuous: the case above
# proves this exact repo state DOES convict once the leg is switched on.
@test "provenance: a DECLARED fixture subject skips the leg (why the other cases stay hermetic)" {
  _provfix; _ff_raw
  unset CC_PARITY_PROVENANCE
  run "$ASSERT"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'provenance'; then false; fi
}

# MECHANISM and CONTENT are scored apart because --force/--bootstrap separate them in real life:
# the operator's documented escape hatch reaches HEAD through deploy-live (so the mechanism is
# sanctioned) but deploys a tree nothing has verified. Collapsing the two would either excuse a
# --force deploy or convict deploy-live for offering the hatch at all.
@test "provenance: --force's shape ⇒ GATED but UNVERIFIED (the two facts are independent)" {
  _provfix; mkdir -p "$CC_PARITY_STAMPS"; _ff_gated
  run "$ASSERT"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q '^  GATED'
  printf '%s' "$output" | grep -q 'UNVERIFIED'
}

@test "provenance: a green-stamped tree reached by a resolved-SHA ff ⇒ VERIFIED, exit 0" {
  _provfix; _ff_gated; _stamp_green
  run "$ASSERT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^  VERIFIED'
}

# ── THE T2 DEGRADE, the CONTENT fact's third value (2026-08-07, backlog 13ba97f1701d) ────────────
# Regression pin for a self-inflicted RED: deploy-live's two-tier lane degraded to the newest NOT-RED
# commit under its declared staleness budget, printed the banner, deployed, then ran THIS suite's
# live sibling — which reddened on "no green stamp", i.e. on the state the banner had just announced,
# and paged + filed a backlog item for it. The evidence is four consecutive deploy.log lines, quoted
# at the branch itself. The discriminator is the page the LANE writes after the merge, sha-keyed.
_degrade_page() {   # what deploy-live.sh:715 writes on a T2 advance, keyed as it keys it
  mkdir -p "$CC_PARITY_PAGES"
  printf 'deploy-live DEGRADED advance: … — NO green-verified tree was deployable\n' \
    > "$CC_PARITY_PAGES/deploy-degraded-$(git -C "$CC_PARITY_REPO" rev-parse HEAD | cut -c1-12).page"
}

@test "provenance: a lane-DECLARED degraded advance ⇒ DEGRADED, exit 0 (the banner is not a finding)" {
  _provfix; mkdir -p "$CC_PARITY_STAMPS"; _ff_gated; _degrade_page
  run "$ASSERT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^  DEGRADED'
  if printf '%s' "$output" | grep -q 'UNVERIFIED'; then false; fi
}

# NON-VACUITY, and the fail-closed direction in one case. Identical to the pass above except the page
# names a DIFFERENT commit — so it proves the sha key is load-bearing rather than "any file in the
# pages dir", and it proves a stale page from an earlier degraded advance cannot vouch for the commit
# the checkout is on NOW. The `--force's shape` case above is the same guard from the other side: a
# sanctioned-but-unverified advance that writes no page at all is still exit 1.
@test "provenance: a degrade page for ANOTHER sha does NOT vouch for this one ⇒ UNVERIFIED, exit 1" {
  _provfix; mkdir -p "$CC_PARITY_STAMPS"; _ff_gated
  mkdir -p "$CC_PARITY_PAGES"
  printf 'deploy-live DEGRADED advance: …\n' \
    > "$CC_PARITY_PAGES/deploy-degraded-$(printf '%s' "$_BASE" | cut -c1-12).page"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'UNVERIFIED'
  if printf '%s' "$output" | grep -q 'DEGRADED'; then false; fi
}

# No stamps dir = the verification net is not active, which is deploy-live's own separate refusal
# state. Asserting "unverified" there would convict a host for a net that was never switched on.
@test "provenance: no stamps dir ⇒ the verification fact is not claimed in either direction" {
  _provfix; export CC_PARITY_STAMPS="$BATS_TEST_TMPDIR/absent"; _ff_gated
  run "$ASSERT"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'VERIFIED'; then false; fi
}

# Two kinds of exit 1 with two different remedies. Telling an operator "the code running is not the
# code in this checkout" after a raw ff sends them hunting a content difference that does not exist
# — under a bare ff the checkout matches live byte for byte. And the remedy must never print the
# CAUSE as the cure: this file already carries that scar one leg up, where the prescribed
# ./install.sh would have erased the staged-pending state the same run had just reported.
@test "provenance: a provenance-only exit 1 names the right kind, and never prescribes another ff" {
  _provfix; _ff_raw
  run "$ASSERT"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'IS this checkout'
  if printf '%s' "$output" | grep -q 'the code running is not the code'; then false; fi
  if printf '%s' "$output" | grep -q 'merge --ff-only origin/main'; then false; fi
  # And the remedy must name a mechanism that is still TRUE. It used to cite a commit-rate diagnosis
  # ("structurally unsatisfiable") that DEPLOY_GATE_CONVERGENCE.md's own §7 withdrew 53 minutes after
  # it was written — and the negative assertion that stood here, banning "It clears when", then
  # GUARDED the dead claim: it forbade the exact sentence the corrected remedy needs, so keeping this
  # test green meant keeping the withdrawn mechanism, and the 2026-08-07 rewrite carried it forward.
  # A stale assertion never reads as stale; it reads as an ordinary red, which is how it survives a
  # fix (memory: stale-assertion-becomes-an-inverted-guard).
  #
  # Re-pointed at the surviving diagnosis. Both doc pointers are pinned HERE, together, because the
  # script's comment says both are load-bearing and a pin living somewhere else is how one of them
  # gets dropped unnoticed: §7 is why a green is withheld, GROUND_UP is the two-tier remedy. The
  # section anchor is pinned, not the bare filename — the doc's head is still a withdrawn title, so
  # citing the file alone is the defect this test now exists to catch.
  printf '%s' "$output" | grep -q 'DEPLOY_GATE_CONVERGENCE.md §7'
  printf '%s' "$output" | grep -q 'DEPLOY_LANE_GROUND_UP'
  printf '%s' "$output" | grep -q 'CHURNING red set'
  if printf '%s' "$output" | grep -q 'structurally unsatisfiable'; then false; fi
}

# The seam: this script asserts the POSTCONDITION of deploy-live's own target choice, so the two
# must agree on what "green" means. Two auditors over one population with different state models is
# how this repo's worst bugs have survived — pin the definition itself, not just the outcome.
@test "provenance: is_green is byte-identical to deploy-live's (one definition of green)" {
  a="$(sed -n '/^is_green() {/,/^}/p' "$ASSERT")"
  b="$(sed -n '/^is_green() {/,/^}/p' "$REPO_ROOT/scripts/deploy-live.sh")"
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" = "$b" ]
}

# ══ CLASS COMPLETENESS — every install.sh deploy class, not five of them (2026-08-10, P6) ════════
# docs/research/land-architecture-100p-2026-08-10.md §2.E measured the hole: the existence leg's
# pathspec was `hooks commands scripts bin skills`, deploy-live's link_refresh consumes ONLY this
# leg's output, so the tick-driven ADD-repair covered 5 of install.sh's ~19 classes. The rest —
# agents/, lib/, vendor/, bin/desk-*, hooks/*.py, scripts/lib/*.sh, the root-config SSOTs — reached
# the live layer only when install.sh ran, and install.sh runs only after a SUCCESSFUL advance, a
# lane that had refused 601 consecutive times. A file in those classes did not land degraded; it
# landed ABSENT, and every consumer guard on it (`[ -f x ] && . x`) is a silent skip.
#
# WHY THE HOLE SURVIVED FIVE SESSIONS OF READERS, and what these tests therefore have to prove: a
# per-file report over a 5-class pathspec is INDISTINGUISHABLE from one over a 19-class pathspec
# whenever both are clean. "No rows about agents/*.md" reads exactly like "agents/*.md is in
# parity". So it is not enough to assert that a clean run stays clean — each new class gets a
# fixture that makes it RED, which is the only control that can tell coverage from silence.

@test "class: every SYMLINK class install.sh globs is asserted — one RED per class" {
  _livefix
  mkdir -p "$CC_PARITY_REPO"/{hooks,agents,lib,scripts/lib,bin}
  printf 'x\n' > "$CC_PARITY_REPO/hooks/curl-gate.py"          # hooks/*.py — settings.json wires it BY PATH
  printf 'x\n' > "$CC_PARITY_REPO/agents/deep-research.md"     # agents/*.md — NAME-invoked, zero grep-able callers
  printf 'x\n' > "$CC_PARITY_REPO/lib/config-mirror.zsh"       # lib/*.zsh
  printf 'x\n' > "$CC_PARITY_REPO/lib/cc-resume-shell.sh"      # lib/*.sh — both extensions are load-bearing
  printf 'x\n' > "$CC_PARITY_REPO/scripts/lib/pane-spawn-log.sh"  # the file that PROVED the ADD gap
  # scripts/lib/*.py — a SECOND extension in the same directory, and the reason this class exists.
  # install.sh's scripts/lib loop globbed *.sh only, so pty-run.py (769ea1fca82f, 2026-08-08) was
  # never linked, and the assert scored it want=0 via scripts/*/*, whose `[ "$want" = 1 ] || continue`
  # skips a path in BOTH directions. Deployer and auditor agreed over an absence because both were
  # keyed on the same EXTENSION — the "coverage vs silence" hazard this block's header names, in the
  # one form a 1:1 mirror cannot catch: not the deployer's DRIFT, but its OMISSION.
  printf 'x\n' > "$CC_PARITY_REPO/scripts/lib/pty-run.py"
  printf 'x\n' > "$CC_PARITY_REPO/bin/desk-register"           # bin/desk-* — its own install.sh glob
  printf 'x\n' > "$CC_PARITY_REPO/model-config.yaml"           # root SSOT
  printf 'x\n' > "$CC_PARITY_REPO/providers.json"              # root SSOT
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  # Per-CLASS, not a total: a single count would go green again the moment one class regressed and
  # another gained a file. Each line is the exact remedy deploy-live's link_refresh consumes.
  for f in hooks/curl-gate.py agents/deep-research.md lib/config-mirror.zsh lib/cc-resume-shell.sh \
           scripts/lib/pane-spawn-log.sh scripts/lib/pty-run.py bin/desk-register \
           model-config.yaml providers.json; do
    [[ "$output" == *"MISSING: ln -sf $CC_PARITY_REPO/$f $CC_PARITY_LIVE/$f"* ]] || false
  done
  [ "$(printf '%s\n' "$output" | grep -c '^MISSING: ln -sf')" -eq 9 ]
}

# ── ROOT SSOT: LINK-NESS, not existence (2026-08-12, consolidation audit 02 / b13787e71c9f) ─────
# Every case above asks "is there a live counterpart?". For the two root SSOTs that question is too
# weak, and its weakness is the audit's own finding: ~/.claude/model-config.yaml was a REAL 36 KB
# file carrying the whole Opus 5 activation, drifting for four days against a repo copy that claimed
# SSOT and that no consumer read. `-e` follows a symlink, so that live real file scored `2 tracked ·
# 2 live · 0 missing`, exit 0 — from the class already NAMED `root SSOT (link)`. A symlink cannot
# drift; link-ness is the property that makes the SSOT claim true, so it is what gets asserted.
@test "root SSOT: live REAL file that DIFFERS from the repo ⇒ STALE drift, exit 1 (the audit-02 split-brain)" {
  _livefix
  printf 'opus_latest: claude-opus-4-8\n' > "$CC_PARITY_REPO/model-config.yaml"
  printf 'x\n' > "$CC_PARITY_LIVE/model-config.yaml"      # a real file, NOT a link — and drifted
  printf 'opus_latest: claude-opus-5\n' >> "$CC_PARITY_LIVE/model-config.yaml"
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]] || false
  [[ "$output" == *"split-brain is ACTIVE"* ]] || false
  # DRIFT is its own column, never folded into "missing": the file EXISTS live, so counting it as
  # missing would contradict the leg that just found it (and the "NO live counterpart" summary).
  printf '%s\n' "$output" | grep -qE '^  DRIFT +root SSOT \(link\) +1 tracked · 0 live · 0 missing · 1 drifted'
}

@test "root SSOT: live copy MATCHES today but is not a link ⇒ UNLINKED drift, exit 1 (latent split-brain)" {
  _livefix
  printf 'opus_latest: claude-opus-5\n' > "$CC_PARITY_REPO/model-config.yaml"
  cp "$CC_PARITY_REPO/model-config.yaml" "$CC_PARITY_LIVE/model-config.yaml"
  _track
  run "$ASSERT"
  # Byte-identical TODAY is still drift: it diverges on the next repo edit and nothing would say so.
  # That is precisely how the four-day drift happened, and why a content-only check is not enough.
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNLINKED"* ]] || false
  [[ "$output" == *"must be a symlink"* ]] || false
}

@test "root SSOT: un-run staged activation owns the swap ⇒ PENDING, not drift, exit 0" {
  _livefix
  printf 'opus_latest: claude-opus-5\n' > "$CC_PARITY_REPO/model-config.yaml"
  printf 'drifted\n' > "$CC_PARITY_LIVE/model-config.yaml"
  _pendfix model-config.yaml
  _track
  run "$ASSERT"
  # 20-model-config-ssot-activate.sh is the real, staged, C10 operator step that performs exactly
  # this swap. Convicting the live host for obeying a design that is waiting on the operator is the
  # false RED this leg already learned once — the new check must not re-introduce it.
  [ "$status" -eq 0 ]
  [[ "$output" == *"PENDING"* ]] || false
  [[ "$output" == *"is not the link YET"* ]] || false
  [[ "$output" != *"STALE"* ]] || false
  [[ "$output" != *"UNLINKED"* ]]
}

@test "root SSOT: a RELATIVE symlink resolving to the repo file ⇒ clean, exit 0" {
  _livefix
  printf 'opus_latest: claude-opus-5\n' > "$CC_PARITY_REPO/model-config.yaml"
  # install.sh writes an absolute link, but the resolver must not depend on that: a relative link
  # landing on the same file is correctly deployed, and calling it drift would be a false RED.
  ln -sfn "$(cd "$CC_PARITY_REPO" && pwd)/model-config.yaml" "$CC_PARITY_LIVE/model-config.yaml"
  ( cd "$CC_PARITY_LIVE" && rm -f model-config.yaml && ln -sfn "../repo/model-config.yaml" model-config.yaml )
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"STALE"* ]] || false
  [[ "$output" != *"UNLINKED"* ]] || false
  printf '%s\n' "$output" | grep -qE '^  ok +root SSOT \(link\) +1 tracked · 1 live · 0 missing$'
}

@test "root SSOT: a symlink pointing at a DIFFERENT checkout ⇒ drift, exit 1" {
  _livefix
  printf 'opus_latest: claude-opus-5\n' > "$CC_PARITY_REPO/model-config.yaml"
  mkdir -p "$BATS_TEST_TMPDIR/other"
  printf 'opus_latest: claude-opus-4-8\n' > "$BATS_TEST_TMPDIR/other/model-config.yaml"
  ln -sfn "$BATS_TEST_TMPDIR/other/model-config.yaml" "$CC_PARITY_LIVE/model-config.yaml"
  # A link is not automatically parity: the subject under assertion is THIS checkout, and a link
  # into another one is a second SSOT wearing a symlink — the same split the audit found.
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]] || false
}

@test "class: the same eight files linked live ⇒ clean, exit 0 (the RED above was not a false demand)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO"/{hooks,agents,lib,scripts/lib,bin} \
           "$CC_PARITY_LIVE"/{hooks,agents,lib,scripts/lib,bin}
  for f in hooks/curl-gate.py agents/deep-research.md lib/config-mirror.zsh lib/cc-resume-shell.sh \
           scripts/lib/pane-spawn-log.sh bin/desk-register model-config.yaml providers.json; do
    printf 'x\n' > "$CC_PARITY_REPO/$f"
    ln -sfn "$CC_PARITY_REPO/$f" "$CC_PARITY_LIVE/$f"
  done
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

# vendor/ is the one SYMLINK class that is not per-file. install.sh:546 links the DIRECTORY on
# purpose — "a per-file loop would silently fail to link every BRAND-NEW file on the next re-vendor"
# — so a per-file demand here would contradict install.sh and could never be satisfied.
@test "vendor: an unlinked plugin ⇒ ONE directory-level ln -sf, never one per file" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/vendor/codex-security/skills"
  printf 'x\n' > "$CC_PARITY_REPO/vendor/codex-security/README.md"
  printf 'x\n' > "$CC_PARITY_REPO/vendor/codex-security/skills/a.md"
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf $CC_PARITY_REPO/vendor/codex-security $CC_PARITY_LIVE/vendor/codex-security"* ]] || false
  [ "$(printf '%s\n' "$output" | grep -c '^MISSING: ln -sf')" -eq 1 ]
  [[ "$output" != *"vendor/codex-security/README.md"* ]]
}

@test "vendor: the plugin dir linked ⇒ clean, and its files are never demanded individually" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/vendor/codex-security" "$CC_PARITY_LIVE/vendor"
  printf 'x\n' > "$CC_PARITY_REPO/vendor/codex-security/README.md"
  ln -sfn "$CC_PARITY_REPO/vendor/codex-security" "$CC_PARITY_LIVE/vendor/codex-security"
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

# ══ COPY CLASSES — detected, and DELIBERATELY not repairable by the tick ═════════════════════════
# install.sh:289 records what happens when a copy class becomes a link: githooks shipped as symlinks
# for six hours and it is called "a critical bug" — a link into the working tree dangles on any
# branch switch in the shared checkout, and git fails OPEN on a dangling hook, so the gate silently
# stops existing. deploy-live's link_refresh consumes `^MISSING: ln -sf ` and creates symlinks, so
# the ONLY thing standing between it and that bug is that these findings never use that spelling.
# That is the single most important assertion in this section, and every case below re-checks it.
_copyfix() {   # a fixture whose copy classes are all present + identical, so a case isolates ONE
  _livefix
  export CC_PARITY_GITHOOKS="$BATS_TEST_TMPDIR/ghdir"
  export CC_PARITY_LAUNCHD="$BATS_TEST_TMPDIR/agents"
  mkdir -p "$CC_PARITY_GITHOOKS" "$CC_PARITY_LAUNCHD" "$CC_PARITY_REPO/githooks" \
           "$CC_PARITY_REPO/launchd" "$CC_PARITY_LIVE/bin"
  printf 'statusline v1\n' > "$CC_PARITY_REPO/statusline.sh"
  cp "$CC_PARITY_REPO/statusline.sh" "$CC_PARITY_LIVE/statusline.sh"
  printf 'it2 v1\n' > "$CC_PARITY_REPO/bin/it2-wrapper"
  cp "$CC_PARITY_REPO/bin/it2-wrapper" "$CC_PARITY_LIVE/bin/it2"
  printf '# cc-git-identity-gate\n' > "$CC_PARITY_REPO/githooks/pre-commit"
  cp "$CC_PARITY_REPO/githooks/pre-commit" "$CC_PARITY_GITHOOKS/pre-commit"
  cp "$CC_PARITY_REPO/githooks/pre-commit" "$CC_PARITY_GITHOOKS/pre-merge-commit"
  printf '<plist/>\n' > "$CC_PARITY_REPO/launchd/com.claude.thing.plist"
  cp "$CC_PARITY_REPO/launchd/com.claude.thing.plist" "$CC_PARITY_LAUNCHD/com.claude.thing.plist"
  _track
}

@test "copy: a fully-deployed set of copy classes ⇒ clean, exit 0" {
  _copyfix
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"COPYMISS"* ]] || false
  [[ "$output" != *"COPYSTALE"* ]]
}

@test "copy: an ABSENT copy ⇒ COPYMISS + drift, and NEVER an ln -sf line" {
  _copyfix
  rm "$CC_PARITY_LIVE/statusline.sh"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"COPYMISS"* ]] || false
  [[ "$output" == *"statusline.sh"* ]] || false
  # THE LOAD-BEARING HALF: link_refresh must not be handed a way to turn a copy into a symlink.
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

@test "copy: a STALE copy ⇒ COPYSTALE + drift, and still never an ln -sf line" {
  _copyfix
  printf 'it2 v0\n' > "$CC_PARITY_LIVE/bin/it2"       # the renamed dest: bin/it2-wrapper → bin/it2
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"COPYSTALE"* ]] || false
  [[ "$output" == *"it2-wrapper"* ]] || false
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

@test "copy: an absent launchd plist ⇒ COPYMISS, and nothing here ever calls launchctl" {
  _copyfix
  rm "$CC_PARITY_LAUNCHD/com.claude.thing.plist"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"COPYMISS"* ]] || false
  [[ "$output" == *"launchd/*.plist"* ]] || false
  # Activation is manifest-gated (DAEMON_FLEET_V2 §4.1) and emphatically not this script's business:
  # a parity assert able to bootout a daemon would be a far larger hazard than the drift it detects.
  # Pinned as TEXT, not as behaviour — a test that had to observe a launchctl call would have to
  # risk one. Both spellings, because `launchctl` and a $LAUNCHCTL_BIN indirection are the two ways
  # this could ever reach the real one. COMMENTS ARE STRIPPED FIRST: this assertion failed on its
  # own subject's comment (the paragraph explaining that nothing calls launchctl contains the word),
  # which is the same class as a lint aborting on a comment that opens with its own directive name.
  if sed 's/#.*//' "$ASSERT" | grep -qE 'launchctl|LAUNCHCTL_BIN'; then false; fi
}

@test "copy: a FOREIGN git hook is left alone — install.sh's own rule, so not drift" {
  _copyfix
  printf '#!/bin/sh\n# somebody else hook\n' > "$CC_PARITY_GITHOOKS/pre-commit"
  run "$ASSERT"
  # install.sh:314 refuses to clobber a hook without our content marker, so demanding parity over it
  # would be a false demand nothing could satisfy — the same rule the existence leg's first comment
  # states: never assert a deployment install.sh would not perform.
  [ "$status" -eq 0 ]
  [[ "$output" == *"FOREIGN"* ]]
}

@test "copy: SET-EMPTY seams turn a class off (a class that cannot be scoped is not seamed)" {
  _copyfix
  rm "$CC_PARITY_LAUNCHD/com.claude.thing.plist"
  # Spelled '' rather than a bare `=`: the empty value is the POINT of this test (the seam's
  # set-but-empty contract), and shellcheck reads a bare `VAR= cmd` as a probable typo.
  CC_PARITY_LAUNCHD='' run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"launchd"* ]]
}

# ══ ~/.claude/CLAUDE.md — the highest-consequence live file, previously unsensed ══════════════════
# §2.E: "no converger and no detection". Half of that is corrected by the tree — install.sh:583-587
# DOES have a cp leg — but that leg runs only on a successful advance, so it was famine-blocked with
# everything else, and nothing measured the file at all. It read in-parity when investigated only
# because a session had hand-synced it 34 minutes earlier.
_mdfix() {
  _copyfix
  printf 'global rules v1\n' > "$CC_PARITY_REPO/CLAUDE.md"
  cp "$CC_PARITY_REPO/CLAUDE.md" "$CC_PARITY_LIVE/CLAUDE.md"
  _track
}

@test "CLAUDE.md: identical ⇒ no finding, exit 0" {
  _mdfix
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"CLAUDEMD"* ]]
}

@test "CLAUDE.md: ONE diverged byte ⇒ CLAUDEMD + drift, exit 1" {
  _mdfix
  # ONE byte, and deliberately not a trailing newline: `$(cat f)` strips those, so a newline-only
  # divergence would make the non-vacuity check below pass for the wrong reason (it did, first run).
  printf 'global rules v1 \n' > "$CC_PARITY_LIVE/CLAUDE.md"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDEMD"* ]] || false
  [[ "$output" == *"DIVERGE"* ]] || false
  # DETECTION ONLY, by decision: the direction is a judgment (the project rule is that a land here
  # is followed by hand-applying the same edits live, so a divergence can equally mean "the repo
  # advanced" or "the live file holds an uncommitted edit"). A converger that guessed would destroy
  # operator work in the second case — which is also exactly why it is legitimately operator-owned.
  [[ "$output" != *"MISSING: ln -sf"* ]] || false
  [ "$(cat "$CC_PARITY_LIVE/CLAUDE.md")" != "$(cat "$CC_PARITY_REPO/CLAUDE.md")" ]
}

@test "CLAUDE.md: an ABSENT live copy ⇒ CLAUDEMD + drift (no session is reading the rules)" {
  _mdfix
  rm "$CC_PARITY_LIVE/CLAUDE.md"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDEMD"* ]] || false
  [[ "$output" == *"ABSENT"* ]]
}

# ══ FILING — a verdict that only PRINTS reaches nobody ════════════════════════════════════════════
# The UNGATED finding printed on every 600s tick for weeks and filed nothing; five sessions read
# "drift at its historical minimum" and closed over it. These cases pin the three properties the
# filing has to have, and the first one is a safety property, not a feature.
_filefix() {   # a stub cc-backlog that records its argv; nothing here can reach the real ledger
  export CC_PARITY_BACKLOG_BIN="$BATS_TEST_TMPDIR/cc-backlog"
  export CC_PARITY_FILED_DIR="$BATS_TEST_TMPDIR/filed"
  FILED_LOG="$BATS_TEST_TMPDIR/filed.log"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\necho id-0000\n' "$FILED_LOG" > "$CC_PARITY_BACKLOG_BIN"
  chmod +x "$CC_PARITY_BACKLOG_BIN"
}

@test "filing: a DECLARED fixture subject files NOTHING by default (no test can reach the real ledger)" {
  _mdfix
  _filefix
  printf 'diverged\n' > "$CC_PARITY_LIVE/CLAUDE.md"
  run "$ASSERT"                       # CC_PARITY_FILE unset, CC_PARITY_REPO declared ⇒ never files
  [ "$status" -eq 1 ]
  [ ! -f "$FILED_LOG" ]
  [[ "$output" != *"FILED"* ]]
}

@test "filing: a diverged CLAUDE.md files an operator-owned cc-backlog needs row" {
  _mdfix
  _filefix
  printf 'diverged\n' > "$CC_PARITY_LIVE/CLAUDE.md"
  CC_PARITY_FILE=1 run "$ASSERT"
  [ "$status" -eq 1 ]
  [ -f "$FILED_LOG" ]
  grep -q 'needs' "$FILED_LOG"
  grep -q 'CLAUDE.md' "$FILED_LOG"
  [[ "$output" == *"FILED"* ]]
}

@test "filing: the UNGATED provenance verdict FILES, it no longer only prints" {
  _livefix
  _filefix
  git -C "$CC_PARITY_REPO" commit -q --allow-empty -m base
  # A ref-named ff is the ungated shape: deploy-live always reflogs a resolved SHA.
  git -C "$CC_PARITY_REPO" checkout -q -b side
  git -C "$CC_PARITY_REPO" commit -q --allow-empty -m side
  git -C "$CC_PARITY_REPO" checkout -q - 2>/dev/null || git -C "$CC_PARITY_REPO" checkout -q main
  git -C "$CC_PARITY_REPO" merge --ff-only side -q
  CC_PARITY_FILE=1 CC_PARITY_PROVENANCE=1 run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNGATED"* ]] || false
  [ -f "$FILED_LOG" ]
  grep -q 'shared checkout' "$FILED_LOG"
  # No `--run`: there is no command that repairs this, and the one that LOOKS like it (another ff)
  # is the cause. The script's own remedy block states that rule; this pins it at the filing too.
  if grep -q -- '--run' "$FILED_LOG"; then false; fi
}

@test "filing: DAMPED by condition key — a second run inside the TTL does not re-file" {
  _mdfix
  _filefix
  printf 'diverged\n' > "$CC_PARITY_LIVE/CLAUDE.md"
  CC_PARITY_FILE=1 run "$ASSERT"
  CC_PARITY_FILE=1 run "$ASSERT"
  # The trigger is a standing STATE, and this assert runs on a 600s tick: an undamped filer would
  # shell out 144×/day and re-announce cc-backlog's DONE-GUARD into deploy.log every time.
  [ "$(wc -l < "$FILED_LOG" | tr -d ' ')" -eq 1 ]
}

@test "filing: the damper EXPIRES — a standing condition is re-asserted, not silenced forever" {
  _mdfix
  _filefix
  printf 'diverged\n' > "$CC_PARITY_LIVE/CLAUDE.md"
  CC_PARITY_FILE=1 run "$ASSERT"
  [ "$(wc -l < "$FILED_LOG" | tr -d ' ')" -eq 1 ]
  # Age the marker rather than zeroing the TTL: `find -mmin +0` means "older than one whole minute",
  # so a TTL of 0 does NOT expire a marker written seconds ago and the test would have proved the
  # opposite of what it claims. Backdating exercises the real TTL arithmetic instead of a
  # special-cased boundary. A damper with no expiry is indistinguishable from a detector that fired
  # once and died — the alarm-becomes-furniture failure this repo has paid for before.
  touch -t 202001010000 "$CC_PARITY_FILED_DIR/claude-md-diverged"
  CC_PARITY_FILE=1 run "$ASSERT"
  [ "$(wc -l < "$FILED_LOG" | tr -d ' ')" -eq 2 ]
}

@test "filing: a BROKEN cc-backlog fails no wider than itself — the verdict and exit code stand" {
  _mdfix
  _filefix
  printf '#!/bin/bash\nexit 7\n' > "$CC_PARITY_BACKLOG_BIN"     # the store is down
  printf 'diverged\n' > "$CC_PARITY_LIVE/CLAUDE.md"
  CC_PARITY_FILE=1 run "$ASSERT"
  # A parity leg that could take down the run would be a converger that stops convergence: the
  # finding still reports, the exit code is still the drift verdict, and no marker is written (so
  # the next tick retries rather than believing a file that never happened).
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDEMD"* ]] || false
  [[ "$output" != *"FILED"* ]] || false
  [ ! -f "$CC_PARITY_FILED_DIR/claude-md-diverged" ]
}

# ══ THE TABLE — the render that makes an unenumerated class visible ══════════════════════════════
@test "class table: renders one row per class WITH counts, on a clean run too" {
  _copyfix
  mkdir -p "$CC_PARITY_REPO/agents" "$CC_PARITY_LIVE/agents"
  printf 'x\n' > "$CC_PARITY_REPO/agents/a.md"
  ln -sfn "$CC_PARITY_REPO/agents/a.md" "$CC_PARITY_LIVE/agents/a.md"
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  # Emitted on a CLEAN run specifically: silence about a class and parity for a class looked
  # identical for the whole time the 5-of-19 hole was open, so the counts are the evidence.
  [[ "$output" == *"class parity"* ]] || false
  [[ "$output" == *"agents/*.md"* ]] || false
  [[ "$output" == *"1 tracked · 1 live · 0 missing"* ]] || false
  [[ "$output" == *"launchd/*.plist"* ]]
}

@test "class table: a missing file marks ITS class MISS and leaves the others ok" {
  _copyfix
  mkdir -p "$CC_PARITY_REPO/agents" "$CC_PARITY_LIVE/agents"
  printf 'x\n' > "$CC_PARITY_REPO/agents/a.md"          # tracked, never linked
  _track
  run "$ASSERT"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qE '^  MISS +agents/\*\.md +1 tracked · 0 live · 1 missing'
  printf '%s\n' "$output" | grep -qE '^  ok +launchd/\*\.plist'
}

# ANTI-ROT. The enumeration in the assert is a hand-maintained mirror of install.sh's own loops, and
# the previous version of that mirror went stale silently for weeks (install.sh gained a lib leg at
# 931641a4; the assert and one of these tests both went on asserting it had none). Prose cannot hold
# that invariant, so the tree holds it: every directory install.sh globs must appear in the assert's
# pathspec. Deliberately a SUBSET check on directories, not an exact class-by-class equality — the
# spellings differ legitimately (install.sh globs, the assert case-matches) and a test demanding
# identical text would just be re-typed on every edit until someone deleted it.
@test "anti-rot: every REPO_DIR directory install.sh deploys appears in the assert's pathspec" {
  spec="$(sed -n 's/.*git -C "\$REPO" ls-files -- \(.*\) 2>\/dev\/null.*/\1/p' "$ASSERT")"
  [ -n "$spec" ]
  # install.sh's own loop heads, e.g. `for agent in "$REPO_DIR"/agents/*.md`
  dirs="$(grep -oE 'for [a-z_]+ in "\$REPO_DIR"/[a-z]+' "$REPO_ROOT/install.sh" \
          | sed 's|.*/||' | sort -u)"
  [ -n "$dirs" ]
  for d in $dirs; do
    # githooks and launchd are COPY classes: they are asserted by the copy leg, which reads the repo
    # directly rather than through ls-files, and they must never enter the pathspec whose output
    # link_refresh turns into symlinks.
    # Written as `[ = ]` rather than a `githooks|launchd)` case label because
    # scripts/unattended-path-lint.sh read a label as a command position and reported "`launchd` is
    # unreachable on ... PATH (bare)" over this very line, taking the land gate red. FIXED there
    # 2026-08-13 (§ case_stack): labels are patterns in either arity, and a case BODY is now read at
    # all — it never was. The detour is no longer required; the form below is kept only because it
    # works and changing it buys nothing. Do not re-derive the old advice from this shape.
    # NOTE the claim this comment used to make — "the lint already suppresses a plain single-word
    # case label; the alternation form is the gap" — was FALSE in the reassuring direction. Nothing
    # suppressed either; `launchd)` alone leaked identically. Single-word labels merely looked safe
    # because the usual ones name no installed binary.
    if [ "$d" = githooks ] || [ "$d" = launchd ]; then
      grep -q "REPO/$d" "$ASSERT" || false
    else
      case " $spec " in *" $d "*) ;; *) false ;; esac
    fi
  done
}

# ── ORPHAN: the live link whose repo source was DELETED (backlog 456d5c61f4c8) ───────────────────
# THE FORWARD WALK CANNOT SEE THIS CLASS, BY CONSTRUCTION. Every leg above iterates the TRACKED
# listing and asks "is there a live counterpart?". When a file is deleted from the repo it leaves
# that listing, so the walk never visits it again and its live symlink — which still resolves on
# PATH via `command -v`, and then fails with ENOENT when executed — is invisible to this auditor
# forever. Measured 2026-08-23 on the operator's live layer: TWO such links, ~/.claude/bin/
# cc-cloud-watch (source deleted by 799c3282a) and ~/.claude/bin/browsermcp-wrapper.sh (deleted by
# 47cc3f279, i.e. the generator was still minting them 4 days AFTER the row was filed).
#
# The sweep's scope is DERIVED from the want-list rather than maintained beside it: a second
# directory list is exactly the "two auditors over one population with different state models"
# divergence this file has already paid for twice (see the backlog-consolidation note above). The
# price is honest and stated here — a directory whose LAST tracked file was deleted contributes no
# rel to the walk and is therefore not swept.
@test "ORPHAN: a live link whose repo source was DELETED is reported, exit 1 (RED-PROOF)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-alive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-alive.sh" "$CC_PARITY_LIVE/hooks/lib/cc-alive.sh"
  _track                                   # cc-alive.sh is tracked AND healthy ⇒ zero MISSING
  # the deleted one: a live link into this repo, with no tracked source and no file on disk
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-deleted.sh" "$CC_PARITY_LIVE/hooks/lib/cc-deleted.sh"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ORPHAN: rm -f $CC_PARITY_LIVE/hooks/lib/cc-deleted.sh"* ]] || false
  [[ "$output" != *"MISSING: ln -sf"* ]]   # it is NOT a miss — there is nothing to link it to
}

@test "ORPHAN control: a HEALTHY link in the same swept directory is never reported" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-alive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-alive.sh" "$CC_PARITY_LIVE/hooks/lib/cc-alive.sh"
  _track
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ORPHAN"* ]]
}

@test "ORPHAN control: a dangling link pointing OUTSIDE this checkout is not ours to judge" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib" "$BATS_TEST_TMPDIR/elsewhere"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-alive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-alive.sh" "$CC_PARITY_LIVE/hooks/lib/cc-alive.sh"
  _track
  # A dangling link into someone else's tree. deploy-link-parity.sh's header states the same scope
  # clause: "a link pointing anywhere else is explicitly not ours to judge".
  ln -sfn "$BATS_TEST_TMPDIR/elsewhere/gone.sh" "$CC_PARITY_LIVE/hooks/lib/foreign.sh"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ORPHAN"* ]]
}

@test "ORPHAN control: a dangling link to a STILL-TRACKED file stays MISSING and is never also ORPHAN" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-interactive.sh"
  _track
  # Same shape as the DANGLING case above: the source EXISTS, the link is simply pointed at the
  # wrong place. That is a MISS the refresh repairs with `ln -sf`. Claiming it as an ORPHAN too
  # would hand deploy-live a prune AND a relink for one file in one tick — a flap, two lines, one
  # remedy. The forward walk claims the path first; the sweep defers to it.
  ln -sfn "$CC_PARITY_REPO/hooks/lib/gone.sh" "$CC_PARITY_LIVE/hooks/lib/cc-interactive.sh"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING: ln -sf"* ]] || false
  [[ "$output" != *"ORPHAN"* ]]
}

@test "ORPHAN control: a REAL untracked file in a swept directory is not an orphan link" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-alive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-alive.sh" "$CC_PARITY_LIVE/hooks/lib/cc-alive.sh"
  _track
  # An unversioned REAL file on an executed surface is deploy-link-parity.sh's STRAY class, which
  # asks a different question and has a different remedy. This leg deletes; it may only ever claim
  # a path that is already inert.
  printf '#!/bin/bash\n' > "$CC_PARITY_LIVE/hooks/lib/hand-written.sh"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ORPHAN"* ]]
}

@test "ORPHAN control: a link to a PRESENT-but-UNTRACKED source resolves, so it is never an orphan" {
  _livefix
  mkdir -p "$CC_PARITY_REPO/hooks/lib" "$CC_PARITY_LIVE/hooks/lib"
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/cc-alive.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/cc-alive.sh" "$CC_PARITY_LIVE/hooks/lib/cc-alive.sh"
  _track                                   # cc-alive.sh is tracked; the next one deliberately is NOT
  # THE ONE CASE THE RESOLVES-GUARD ALONE DECIDES, and the reason it is a separate test: a source
  # PRESENT on disk but absent from the INDEX — a file mid-authoring, or landed and not yet added.
  # The forward walk reads `git ls-files`, so it never claims this path and the claim-check cannot
  # help; every other control here is shadowed by that check. Only `[ -e ]` stands between a live,
  # WORKING link and an ORPHAN verdict whose consumer deletes. Mutation-attributed: dropping the
  # resolves-guard reds this case and no other.
  printf '#!/bin/bash\n' > "$CC_PARITY_REPO/hooks/lib/not-added-yet.sh"
  ln -sfn "$CC_PARITY_REPO/hooks/lib/not-added-yet.sh" "$CC_PARITY_LIVE/hooks/lib/not-added-yet.sh"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ORPHAN"* ]] || false                # `|| false`: a mid-test [[ ]] is dead otherwise
  [ -L "$CC_PARITY_LIVE/hooks/lib/not-added-yet.sh" ]   # and it is still there to be linked
}

# ── COPYAHEAD: "DIFFERS" never said WHICH SIDE, and the remedy needed it (2026-08-24) ─────────────
# backlog 20aefaafb5c4. deploy-live reported CLAUDE.md and a launchd plist as ONE condition with ONE
# remedy (run install.sh). They drifted OPPOSITE ways: the plist's checkout was ahead (repair
# correct), while CLAUDE.md's LIVE copy was ahead by an operator-authored rule that had never been
# tracked — and install.sh copies repo->live, so the prescribed repair would have DELETED it.
#
# The discriminator is git: hash the LIVE bytes, ask whether that blob is anywhere in the tracked
# path's history. These cases need real COMMITS — _track only STAGES, and a path with no history is
# deliberately UNKNOWN, not `ahead` (an empty search space is not a finding).
_commitfix() {   # give the fixture repo a real history for one copy-class path
  git -C "$CC_PARITY_REPO" -c user.email=t@t -c user.name=t commit -qm "fixture" >/dev/null 2>&1 || true
}

@test "copy AHEAD: live bytes absent from the path's history ⇒ COPYAHEAD, never COPYSTALE" {
  _copyfix
  _commitfix
  printf 'statusline BYTES THAT WERE NEVER COMMITTED\n' > "$CC_PARITY_LIVE/statusline.sh"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"COPYAHEAD"* ]] || { echo "expected COPYAHEAD:"; echo "$output"; false; }
  [[ "$output" == *"statusline.sh"* ]] || false
  # THE LOAD-BEARING HALF: it must not ALSO wear staleness's token for this file, because that token
  # is what carries "run ./install.sh" — the command that destroys these bytes.
  [[ "$(printf '%s\n' "$output" | grep 'statusline.sh')" != *"COPYSTALE"* ]] || false
  [[ "$output" != *"MISSING: ln -sf"* ]]
}

@test "copy BEHIND: live bytes ARE a past revision ⇒ COPYSTALE, and install.sh stays the remedy" {
  # The control that makes the case above mean something: same fixture, same diff, opposite
  # direction. If this reported COPYAHEAD too, the probe would just be a rename of COPYSTALE.
  _copyfix
  _commitfix
  cp "$CC_PARITY_REPO/statusline.sh" "$BATS_TEST_TMPDIR/v1"      # the committed bytes
  printf 'statusline v2\n' > "$CC_PARITY_REPO/statusline.sh"     # repo moves on…
  _track; _commitfix
  cp "$BATS_TEST_TMPDIR/v1" "$CC_PARITY_LIVE/statusline.sh"      # …live still holds the OLD revision
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"COPYSTALE"* ]] || { echo "expected COPYSTALE:"; echo "$output"; false; }
  [[ "$output" != *"COPYAHEAD"* ]] || { echo "a PAST revision must not read as ahead:"; echo "$output"; false; }
  [[ "$output" == *"run ./install.sh"* ]] || false
}

@test "copy UNKNOWN: a tracked path with NO history cannot claim a direction" {
  # _track stages without committing, so git has nothing to search. "No past revision matches" is
  # then an artefact of an empty search space, not evidence — it must not fire the loud branch.
  _copyfix
  printf 'statusline edited, and the repo has no commits at all\n' > "$CC_PARITY_LIVE/statusline.sh"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" != *"COPYAHEAD"* ]] || { echo "no history ⇒ must not claim ahead:"; echo "$output"; false; }
  [[ "$output" == *"direction UNKNOWN"* ]] || { echo "expected an explicit UNKNOWN:"; echo "$output"; false; }
}

# ── CLASS COVERAGE (2026-08-31) ────────────────────────────────────────────────────────────────
# install.sh is the MAP OF RECORD and this script is one of its two auditors. A fix is scoped to
# what broke; a walk's coverage is scoped to everything it was ever taught, and NOTHING reconciles
# those two populations — which is how four classes (hooks/*.py, scripts/lib/*.py,
# scripts/backlog-consolidation/*.py, bin/ms365-*) each reached the live layer only after falling
# through the reasonless `*) want=0` default, every one recorded in a comment beside its own arm.
#
# NEITHER SIDE IS WRITTEN DOWN HERE. install.sh's classes come out of install.sh's own `for … in`
# headers; the verdict comes from EXECUTING this script's own extracted case block, never from
# re-reading it. Every class must land in EXACTLY ONE of claimed-or-declared: neither is the defect
# these arms exist to catch, and both would be a contradiction.
_classcov_runner() {   # $1=case-block file  $2=runner path to write
  {
    printf '%s\n' '#!/bin/bash'
    printf '%s\n' 'rel="$1"; want=0; cls=""'
    cat "$1"
    printf '%s\n' 'printf "%s|%s\n" "$want" "$cls"'
  } > "$2"
}

_classcov_extract() {  # $1=subject  $2=output case-block file — anchors asserted UNIQUE by caller
  local cl cs ce
  cl=$(grep -n '^    cls=""$' "$1" | cut -d: -f1)
  cs=$((cl + 1))
  ce=$(awk -v s="$cs" 'NR>=s && /^    esac$/ {print NR; exit}' "$1")
  [ -n "$ce" ] || return 1
  sed -n "${cs},${ce}p" "$1" > "$2"
}

@test "CLASS COVERAGE: every install.sh deploy class is CLAIMED or EXPLICITLY DECLARED, never left to the default" {
  MAP="$REPO_ROOT/install.sh"
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$MAP" ]
  [ -f "$SUBJ" ]

  # (1) THE MAP, derived from install.sh's own loop headers.
  CLASSES="$BATS_TEST_TMPDIR/classes.txt"
  grep -E '^[[:space:]]*for[[:space:]]+[A-Za-z_]+[[:space:]]+in[[:space:]]+"\$REPO_DIR"/' "$MAP" \
    | grep -oE '"\$REPO_DIR"/[^ ";]+' | sed 's|^"\$REPO_DIR"/||' | sort -u > "$CLASSES"
  # NON-VACUITY FLOOR: a broken anchor derives zero classes, and every assertion below would then
  # pass over an empty population. Measured 19 on 2026-08-31; the floor is deliberately loose.
  [ "$(grep -c . "$CLASSES")" -ge 15 ]

  # (2) THE SUBJECT'S OWN ARBITER. Uniqueness first — we may never execute an unknown line.
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/case.txt"
  [ "$(grep -c 'hooks/lib/\*\.sh)' "$BATS_TEST_TMPDIR/case.txt")" -eq 1 ]

  # Tag ONLY the final catch-all. "Fell to the reasonless default" is then decided by EXECUTION
  # rather than by matching patterns by eye, and the one-line diff is asserted so the mutation
  # cannot silently touch an arm.
  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/case.txt" > "$BATS_TEST_TMPDIR/caseB.txt"
  [ "$(diff "$BATS_TEST_TMPDIR/case.txt" "$BATS_TEST_TMPDIR/caseB.txt" | grep -c '^[<>]')" -eq 2 ]
  RUN="$BATS_TEST_TMPDIR/run.sh"
  _classcov_runner "$BATS_TEST_TMPDIR/caseB.txt" "$RUN"

  # CONTROLS BEFORE VERDICTS. POS: a covered class must come back CLAIMED, or the runner is mute.
  [ "$(bash "$RUN" hooks/notify.sh </dev/null | grep -c '^1|hooks/\*\.sh$')" -eq 1 ]
  # FIRE: a class present nowhere MUST reach the tagged default, or this arm cannot fail at all.
  [ "$(bash "$RUN" zzz-no-such-class/nope.txt </dev/null | grep -c '__DEFAULT__')" -eq 1 ]

  BAD="$BATS_TEST_TMPDIR/bad.txt"; : >"$BAD"
  cd "$REPO_ROOT"
  shopt -s nullglob
  while IFS= read -r cls; do
    [ -n "$cls" ] || continue
    # shellcheck disable=SC2086
    # The word-splitting and globbing ARE the mechanism here: $cls holds an install.sh glob
    # (hooks/*.sh, skills/*/) and this line is how it is expanded. Quoting it would pass one
    # literal pathspec and expand nothing — the zsh scar in reverse. Narrow, one code, deliberate.
    set -- $cls                       # pathname expansion, never eval
    [ "$#" -ge 1 ] || { printf 'EMPTY-CLASS %s\n' "$cls" >>"$BAD"; continue; }
    # A directory-shaped class (skills/*/, vendor/*/) expands WITH its trailing slash; appending to
    # that builds a double slash, and a case pattern's * matches '/', so the malformed path matches
    # a deeper exclusion arm and scores want=0 for a reason that is entirely the harness's.
    m="${1%/}"
    if [ -d "$m" ]; then set -- "$m"/*; [ "$#" -ge 1 ] && m="$1"; fi
    case "$m" in *//*) printf 'MALFORMED %s\n' "$m" >>"$BAD"; continue ;; esac
    out="$(bash "$RUN" "$m" </dev/null)"
    case "$out" in
      1\|*)          : ;;             # CLAIMED — want=1
      *__DEFAULT__*) printf 'REASONLESS-DEFAULT %s (member %s)\n' "$cls" "$m" >>"$BAD" ;;
      *)             : ;;             # declined by an EXPLICIT arm carrying its reason
    esac
  done < "$CLASSES"
  [ "$(grep -c . "$BAD")" -eq 0 ] || { echo "install.sh classes reaching the reasonless default:"; cat "$BAD"; false; }
}

@test "CLASS COVERAGE fire test: deleting a NOT-PER-FILE arm puts its class back on the default" {
  # The arm above passes only because the declarations exist. This proves that is what it measures:
  # remove ONE declared arm from the extracted block and its class must reach the tagged default
  # again. Without this, a case block that happened to claim everything would look identical to one
  # whose exclusions were doing the work.
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$SUBJ" ]
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/case.txt"

  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/case.txt" > "$BATS_TEST_TMPDIR/caseB.txt"
  _classcov_runner "$BATS_TEST_TMPDIR/caseB.txt" "$BATS_TEST_TMPDIR/intact.sh"

  # BASELINE: with the arm present, githooks/ is declared, so it must NOT read as the default.
  [ "$(bash "$BATS_TEST_TMPDIR/intact.sh" githooks/pre-commit </dev/null | grep -c '__DEFAULT__')" -eq 0 ]

  # SEED: delete exactly the githooks arm. Asserted to remove ONE line, so a reworded arm makes this
  # test refuse rather than pass vacuously over a deletion that never happened.
  grep -v '^      githooks/\*)                want=0 ;;$' "$BATS_TEST_TMPDIR/caseB.txt" > "$BATS_TEST_TMPDIR/caseC.txt"
  [ "$(( $(grep -c . "$BATS_TEST_TMPDIR/caseB.txt") - $(grep -c . "$BATS_TEST_TMPDIR/caseC.txt") ))" -eq 1 ]
  _classcov_runner "$BATS_TEST_TMPDIR/caseC.txt" "$BATS_TEST_TMPDIR/seeded.sh"

  # …and now the same path falls through to the reasonless default.
  [ "$(bash "$BATS_TEST_TMPDIR/seeded.sh" githooks/pre-commit </dev/null | grep -c '__DEFAULT__')" -eq 1 ]
}

# ── SECOND-INSTALLER COVERAGE (2026-08-31, method 238) ─────────────────────────────────────────
# The CLASS COVERAGE arm above scores install.sh's own classes, and by construction it cannot see a
# class install.sh never globs. scripts/kitty-setup.sh is a SECOND installer: it links six bin/
# files into $CFG/bin itself while install.sh merely RUNS it, and neither auditor mentions
# kitty-setup.sh anywhere — so its targets reached the reasonless `*) want=0` default, which is the
# same silent disabling that hid hooks/*.py, scripts/lib/*.py, scripts/backlog-consolidation/*.py
# and bin/ms365-*, one level further out.
#
# NEITHER SIDE IS WRITTEN DOWN HERE, for the same reason the arm above does not write its own down:
# the targets come out of kitty-setup.sh's OWN `ln -sfn` lines, and the verdict comes from EXECUTING
# the assert's extracted case block. A target list transcribed into this file would agree with
# itself forever.
@test "SECOND INSTALLER: every scripts/kitty-setup.sh link target is CLAIMED or EXPLICITLY DECLARED" {
  SETUP="$REPO_ROOT/scripts/kitty-setup.sh"
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$SETUP" ]
  [ -f "$SUBJ" ]

  TARGETS="$BATS_TEST_TMPDIR/kitty-targets.txt"
  grep -oE 'ln -sfn "\$REPO/[^"]+"' "$SETUP" | sed -e 's|.*\$REPO/||' -e 's|"$||' | sort -u > "$TARGETS"
  # NON-VACUITY FLOOR: a broken anchor derives zero targets and every assertion below would then
  # pass over an empty population. Measured 6 on 2026-08-31; the floor is deliberately loose.
  [ "$(grep -c . "$TARGETS")" -ge 4 ]
  # …and each derived target must be a REAL tracked file, or the anchor is matching prose rather
  # than a link site.
  MISSING=0
  while IFS= read -r t; do
    [ -f "$REPO_ROOT/$t" ] || MISSING=$((MISSING + 1))
  done < "$TARGETS"
  [ "$MISSING" -eq 0 ]

  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/case2.txt"
  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/case2.txt" > "$BATS_TEST_TMPDIR/case2B.txt"
  [ "$(diff "$BATS_TEST_TMPDIR/case2.txt" "$BATS_TEST_TMPDIR/case2B.txt" | grep -c '^[<>]')" -eq 2 ]
  RUN2="$BATS_TEST_TMPDIR/run2.sh"
  _classcov_runner "$BATS_TEST_TMPDIR/case2B.txt" "$RUN2"

  # CONTROLS BEFORE VERDICTS, the same pair the class-coverage arm uses. POS: a covered class must
  # come back CLAIMED, or the runner is mute. FIRE: a path in no class MUST reach the tagged
  # default, or this arm cannot fail at all.
  [ "$(bash "$RUN2" hooks/notify.sh </dev/null | grep -c '^1|hooks/\*\.sh$')" -eq 1 ]
  [ "$(bash "$RUN2" zzz-no-such-class/nope.txt </dev/null | grep -c '__DEFAULT__')" -eq 1 ]

  BAD2="$BATS_TEST_TMPDIR/bad2.txt"; : >"$BAD2"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    out="$(bash "$RUN2" "$t" </dev/null)"
    case "$out" in
      1\|*)          : ;;             # CLAIMED — want=1 (bin/cc-in-kitty is, via bin/cc-*)
      *__DEFAULT__*) printf 'REASONLESS-DEFAULT %s\n' "$t" >>"$BAD2" ;;
      *)             : ;;             # declined by an EXPLICIT arm carrying its reason
    esac
  done < "$TARGETS"
  [ "$(grep -c . "$BAD2")" -eq 0 ] || { echo "kitty-setup.sh link targets reaching the reasonless default:"; cat "$BAD2"; false; }
}

@test "SECOND INSTALLER fire test: deleting the kitty arm puts its targets back on the default" {
  # The arm above passes only because the declaration exists. This proves that is what it measures:
  # remove the one arm and a kitty target must reach the tagged default again. Without this, a case
  # block that happened to claim everything would look identical to one whose exclusion is doing
  # the work.
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$SUBJ" ]
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/case3.txt"

  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/case3.txt" > "$BATS_TEST_TMPDIR/case3B.txt"
  _classcov_runner "$BATS_TEST_TMPDIR/case3B.txt" "$BATS_TEST_TMPDIR/intact2.sh"

  # BASELINE: with the arm present, a kitty target must NOT read as the default.
  [ "$(bash "$BATS_TEST_TMPDIR/intact2.sh" bin/kitty-pane-menu </dev/null | grep -c '__DEFAULT__')" -eq 0 ]

  # SEED: delete exactly the kitty arm. Asserted to remove ONE line, so a reworded arm makes this
  # test REFUSE rather than pass vacuously over a deletion that never happened.
  grep -vxF '      bin/it2-kitty|bin/kitty-*)  want=0 ;;' "$BATS_TEST_TMPDIR/case3B.txt" > "$BATS_TEST_TMPDIR/case3C.txt"
  [ "$(( $(grep -c . "$BATS_TEST_TMPDIR/case3B.txt") - $(grep -c . "$BATS_TEST_TMPDIR/case3C.txt") ))" -eq 1 ]
  _classcov_runner "$BATS_TEST_TMPDIR/case3C.txt" "$BATS_TEST_TMPDIR/seeded2.sh"

  # …and now the same target falls through to the reasonless default.
  [ "$(bash "$BATS_TEST_TMPDIR/seeded2.sh" bin/kitty-pane-menu </dev/null | grep -c '__DEFAULT__')" -eq 1 ]
}

# --- ~/bin CLAIM COVERAGE ------------------------------------------------------------------------
#
# The two arms above ask whether the AUDITORS cover what install.sh deploys, and whether install.sh
# is the only deployer. This asks the question those cannot: does install.sh's ~/bin list cover the
# tools that EXECUTABLE SURFACES IN THIS REPO ACTUALLY NAME AT ~/bin?
#
# That gap has a measured history and install.sh's own comment above the list records TWO earlier
# instances of it: claude-bump-models and screenshot-to-clipboard.sh "were in NEITHER this list nor
# sync.sh's, so nothing reconciled them in either direction" (audit 02, 2026-07-25). A tool that no
# list names is reconciled by nothing in either direction, so it drifts silently and forever — and
# the deploy auditors cannot see it, because their ~/bin coverage is one hardcoded file
# (deploy-link-parity.sh uses $BINDIR exactly once, for bin/claude-accounts) while the STRAY leg's
# scope is the $CFG surfaces only (its own header, "STRAY SCOPE is the EXECUTED surfaces only").
#
# NEITHER SIDE IS WRITTEN DOWN HERE. The claim set comes out of install.sh's OWN `for tool in`
# headers with their continuation lines joined and the word list TAKEN WHOLE — never filtered by a
# prefix, which is the fault that once dropped screenshot-to-clipboard.sh from a census — with its
# bin/<glob> classes expanded by BASH'S OWN PATHNAME EXPANSION in the real tree rather than matched
# by eye. The referenced side comes out of the surfaces themselves.
#
# SCOPE IS STATED, because an unscoped population is a completeness claim nobody screened: bin/,
# scripts/, hooks/, launchd/, install.sh and sync.sh — the surfaces that RUN a tool. A doc or a
# skill that MENTIONS ~/bin/<x> is documentation, not a consumer; skills/browsermcp/SKILL.md
# deliberately keeps a retired wrapper's config block as history and says so at its own line 8.
_binclaim_build() {   # $1 = install.sh path, $2 = claims out, $3 = refs out
  local ins="$1" claims="$2" refs="$3" root
  root="$(dirname "$ins")"
  : >"$claims"

  # (a) every `for tool in …` header, continuation lines joined, word list taken WHOLE
  awk '/^[[:space:]]*for[[:space:]]+tool[[:space:]]+in/ {
         buf = $0
         while (buf ~ /\\[[:space:]]*$/) {
           sub(/\\[[:space:]]*$/, "", buf)
           if ((getline nxt) <= 0) break
           buf = buf " " nxt
         }
         print buf
       }' "$ins" \
    | sed -e 's/^[[:space:]]*for[[:space:]]*tool[[:space:]]*in[[:space:]]*//' -e 's/;[[:space:]]*do.*$//' \
    | tr ' ' '\n' | grep -e . > "$claims.words"

  # (b) classify: a glob class is EXPANDED in the real tree; a plain word is a literal claim
  while IFS= read -r w; do
    case "$w" in
      *'*'*)
        local pat="${w#*\"}"; pat="${pat#*/bin/}"
        local f
        for f in "$root"/bin/$pat; do
          [ -e "$f" ] && basename "$f" >>"$claims"
        done
        ;;
      '$'*|do|'') : ;;
      *) printf '%s\n' "$w" >>"$claims" ;;
    esac
  done < "$claims.words"

  # (c) explicit single-file sites naming $HOME/bin/<name>
  grep -oE '\$HOME/bin/[A-Za-z0-9._-]+' "$ins" | sed 's|.*/bin/||' >>"$claims"
  sort -u -o "$claims" "$claims"

  # (d) the referenced side, comment lines stripped, EXECUTABLE SURFACES ONLY
  ( cd "$root" && git grep -hnE '(~|\$HOME)/bin/[A-Za-z0-9._-]+' -- \
        'bin/*' 'scripts/*' 'hooks/*' 'launchd/*' 'install.sh' 'sync.sh' 2>/dev/null ) \
    | grep -vE '^[0-9]+:[[:space:]]*(#|//)' \
    | grep -oE '(~|\$HOME)/bin/[A-Za-z0-9._-]+' | sed 's|.*/bin/||' | sort -u > "$refs"
}

@test "HOME/bin CLAIM COVERAGE: every HOME/bin tool an EXECUTABLE surface names is claimed by install.sh" {
  INS="$REPO_ROOT/install.sh"
  [ -f "$INS" ]
  # ANCHOR NON-VACUITY: at least one `for tool in` header must exist, or the extractor is reading
  # a spelling this file no longer uses and every assertion below passes over an empty claim set.
  [ "$(grep -cE '^[[:space:]]*for[[:space:]]+tool[[:space:]]+in' "$INS")" -ge 1 ]

  CLAIMS="$BATS_TEST_TMPDIR/claims.txt"
  REFS="$BATS_TEST_TMPDIR/refs.txt"
  _binclaim_build "$INS" "$CLAIMS" "$REFS"

  # POS CONTROL — the glob classes must have EXPANDED. Held as literal strings the claim set is the
  # 8 literals alone; expanded it is an order of magnitude larger. This is what makes bin/cc-* claim
  # bin/cc-tlid, and without it a correctly-deployed tool reads as unclaimed.
  [ "$(grep -c . "$CLAIMS")" -ge 20 ]
  # POS CONTROL — the referenced side must be non-empty, or the scoping matched nothing at all.
  [ "$(grep -c . "$REFS")" -ge 3 ]

  UNCLAIMED="$BATS_TEST_TMPDIR/unclaimed.txt"
  comm -23 "$REFS" "$CLAIMS" > "$UNCLAIMED"
  [ "$(grep -c . "$UNCLAIMED")" -eq 0 ] || {
    echo "HOME/bin tools an executable surface names that install.sh claims nowhere:"
    cat "$UNCLAIMED"
    echo "(nothing reconciles these in either direction — install.sh's own comment above the list"
    echo " records the same defect for claude-bump-models and screenshot-to-clipboard.sh)"
    false
  }
}

@test "HOME/bin CLAIM COVERAGE fire test: a name install.sh cannot claim is reported unclaimed" {
  # The arm above passes only because every referenced tool is claimed. This proves that is what it
  # measures: a comm that silently returned empty would look identical to a tree with no gap.
  INS="$REPO_ROOT/install.sh"
  [ -f "$INS" ]
  CLAIMS="$BATS_TEST_TMPDIR/claims2.txt"
  REFS="$BATS_TEST_TMPDIR/refs2.txt"
  _binclaim_build "$INS" "$CLAIMS" "$REFS"

  # SEED a reference install.sh cannot possibly claim, through the SAME comparison.
  SEEDED="$BATS_TEST_TMPDIR/refs2seeded.txt"
  cat "$REFS" > "$SEEDED"
  echo 'zzz-no-such-bin-tool' >> "$SEEDED"
  sort -u -o "$SEEDED" "$SEEDED"
  # asserted to ADD exactly one name, so a seed that was already present cannot pass vacuously
  [ "$(( $(grep -c . "$SEEDED") - $(grep -c . "$REFS") ))" -eq 1 ]

  OUT="$BATS_TEST_TMPDIR/unclaimed2.txt"
  comm -23 "$SEEDED" "$CLAIMS" > "$OUT"
  [ "$(grep -cxF 'zzz-no-such-bin-tool' "$OUT")" -eq 1 ]
}

# ── CLAUDE.md-MANDATED SKILLS ────────────────────────────────────────────────────────────────────
# The arms above ask whether install.sh CLAIMS what an executable surface NAMES. These ask the same
# question of a different pair: does this repo CARRY what CLAUDE.md MANDATES?
#
# WHY, measured 2026-08-31. skills/outbound-drafting/SKILL.md sat live and in no checkout since
# 2026-08-29 — 13,268 bytes, authored here (7 operator-specific measured lessons, 0 vendored
# markers, 0 tracked copies in any sibling checkout) — while BOTH copies of CLAUDE.md delegate a
# binding rule to it: "Full rule -> the **outbound-drafting** skill, which auto-loads before any
# such draft". deploy-link-parity.sh's STRAY leg DID catch it and had been reporting it correctly
# the whole time. What failed is one layer up: row bb2495b098b8's evidence acquits that leg with
# "the change adds ZERO findings (the 3 the gate already reports on trunk are pre-existing:
# bin/browsermcp-wrapper.sh, bin/cc-cloud-watch, bin/it2 drifted from bin/it2-wrapper)". The gate
# still reports THREE. Not one of them is those three: all three named members resolved (two are
# gone from the live layer, and bin/it2 is now byte-identical to bin/it2-wrapper so content-matching
# recognises the renamed copy), and three different files arrived. THE COUNT IS STABLE AND THE
# MEMBERSHIP IS DISJOINT, so a reader comparing counts sees an adjudicated wall.
#
# This pair cannot see the live layer at all — deliberately, since the STRAY leg already owns that
# direction and this suite is hermetic. It compares two TRACKED artifacts, so it fires in the land
# smoke on a fresh clone: CLAUDE.md's own prose against git + config/live-only.manifest. A skill may
# be TRACKED (ours) or DECLARED (third-party, with a witness) — the defect is being NEITHER while
# CLAUDE.md tells every session to load it.
_skillclaim_build() {   # $1=repo root · $2=out claims · $3=out covered
  local root="$1" claims="$2" covered="$3"
  # (a) the CLAIM side: CLAUDE.md's own house spelling for naming a skill — a bold lowercase name
  # immediately followed by the word "skill". Taken WHOLE; never filtered by a prefix.
  grep -oE '\*\*[a-z0-9-]+\*\* skill' "$root/CLAUDE.md" \
    | sed -E 's/\*\*([a-z0-9-]+)\*\* skill/\1/' | sort -u > "$claims"
  # (b) the COVERED side, from BOTH mechanisms, each derived from its own artifact.
  ( cd "$root" && git ls-files skills/ 2>/dev/null ) \
    | sed -E 's#^skills/([^/]+)/.*#\1#' | sort -u > "$covered.tracked"
  grep -oE '^skills/[^/]+/' "$root/config/live-only.manifest" 2>/dev/null \
    | sed -E 's#^skills/([^/]+)/#\1#' | sort -u > "$covered.declared"
  cat "$covered.tracked" "$covered.declared" | sort -u > "$covered"
}

@test "CLAUDE.md MANDATED SKILLS: every skill CLAUDE.md names is tracked here or declared live-only" {
  [ -f "$REPO_ROOT/CLAUDE.md" ]
  [ -f "$REPO_ROOT/config/live-only.manifest" ]

  CLAIMS="$BATS_TEST_TMPDIR/skillclaims.txt"
  COVERED="$BATS_TEST_TMPDIR/skillcovered.txt"
  _skillclaim_build "$REPO_ROOT" "$CLAIMS" "$COVERED"

  # POS CONTROL — the claim side must be non-empty, or CLAUDE.md has been reworded out of the
  # anchor's reach and every assertion below passes over an empty set.
  [ "$(grep -c . "$CLAIMS")" -ge 5 ]
  # POS CONTROL — both coverage mechanisms must have produced members, or a single failed read
  # (a git that cannot list, a renamed manifest) would convict every mandated skill at once.
  [ "$(grep -c . "$COVERED.tracked")" -ge 20 ]
  [ "$(grep -c . "$COVERED.declared")" -ge 1 ]

  RESIDUE="$BATS_TEST_TMPDIR/skillresidue.txt"
  comm -23 "$CLAIMS" "$COVERED" > "$RESIDUE"
  [ "$(grep -c . "$RESIDUE")" -eq 0 ] || {
    echo "skills CLAUDE.md mandates that this repo neither tracks nor declares:"
    cat "$RESIDUE"
    echo "(each is a rule every session is told to load, backed by nothing a fresh clone restores."
    echo " Remedy per config/live-only.manifest: track it if it is ours, or add a declaration row"
    echo " with a witness if it is third-party. skills/outbound-drafting was the first instance.)"
    false
  }
}

@test "CLAUDE.md MANDATED SKILLS fire test: a mandated name covered by neither is reported" {
  # The arm above passes only because every mandated skill is covered. This proves that is what it
  # measures — a comm that silently returned empty would look identical to a tree with no gap.
  CLAIMS="$BATS_TEST_TMPDIR/skillclaims2.txt"
  COVERED="$BATS_TEST_TMPDIR/skillcovered2.txt"
  _skillclaim_build "$REPO_ROOT" "$CLAIMS" "$COVERED"

  SEEDED="$BATS_TEST_TMPDIR/skillclaims2seeded.txt"
  cat "$CLAIMS" > "$SEEDED"
  echo 'zzz-no-such-mandated-skill' >> "$SEEDED"
  sort -u -o "$SEEDED" "$SEEDED"
  # asserted to ADD exactly one name, so a seed that was already present cannot pass vacuously
  [ "$(( $(grep -c . "$SEEDED") - $(grep -c . "$CLAIMS") ))" -eq 1 ]

  OUT="$BATS_TEST_TMPDIR/skillresidue2.txt"
  comm -23 "$SEEDED" "$COVERED" > "$OUT"
  [ "$(grep -cxF 'zzz-no-such-mandated-skill' "$OUT")" -eq 1 ]
}

# ── LITERAL-INSTALL COVERAGE (2026-09-01, method 246 pointed at the two coverage ARMS) ──────────
# The CLASS COVERAGE arm above and tests/deploy-link-parity.bats's forward-walk arm both build
# their map from install.sh's `for … in "$REPO_DIR"/…` LOOP HEADERS, and both say so in their own
# comments. That map is install.sh's 19 GLOBS. install.sh ALSO deploys through SINGLETON
# link_file/copy_file calls with a literal source, and those are in NEITHER coverage population —
# so the population that the arms exist to protect has a second half that no arm gates.
#
# The tell was in the subject's own prose: deploy-parity-assert.sh:556 counts "its 19 globs plus
# its 18 literal installs" as two populations, while every arm scoring it knew only the first.
# Measured 2026-09-01: 8 literal-source sites, and FIVE of them reached the reasonless
# `*) want=0` — the exact state githooks/* and launchd/*.plist were in before 2026-08-31, and the
# state bin/ms365-reply-splice.py was in when it existed on trunk and in no live location.
#
# NEITHER SIDE IS WRITTEN DOWN HERE. The population comes out of install.sh's own call sites via a
# THIRD extractor — deliberately not the for-header one, because a coverage arm that reuses the
# extractor whose blind spot it is checking cannot see past it — and the verdict comes from
# EXECUTING the assert's own extracted case block, never from re-reading it.
@test "LITERAL INSTALL COVERAGE: every install.sh singleton deploy source is CLAIMED or EXPLICITLY DECLARED" {
  MAP="$REPO_ROOT/install.sh"
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$MAP" ]
  [ -f "$SUBJ" ]

  # (1) THE MAP — install.sh's literal link_file/copy_file sources. A `$REPO_DIR/<literal>` first
  # argument, i.e. every deploy site that is NOT driven by a loop variable and therefore not
  # reachable from any for-header.
  LITERALS="$BATS_TEST_TMPDIR/literals.txt"
  grep -E '^[[:space:]]*(link_file|copy_file) "\$REPO_DIR/[^"$]+"' "$MAP" \
    | grep -oE '"\$REPO_DIR/[^"$]+"' | tr -d '"' | sed 's|^\$REPO_DIR/||' | sort -u > "$LITERALS"
  # NON-VACUITY FLOOR: a broken anchor derives zero sources and every assertion below then passes
  # over an empty set. Measured 8 on 2026-09-01; the floor is deliberately loose.
  [ "$(grep -c . "$LITERALS")" -ge 6 ]
  # …and a KNOWN member, so a derivation that produced six lines of the wrong thing still fails.
  # accounts.json is the oldest of the three root-SSOT singletons and the one whose exclusion had
  # a written reason but no arm.
  [ "$(grep -cxF 'accounts.json' "$LITERALS")" -eq 1 ]

  # (2) THE SUBJECT'S OWN ARBITER, by execution. Uniqueness first — never execute an unknown line.
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/lcase.txt"
  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/lcase.txt" > "$BATS_TEST_TMPDIR/lcaseB.txt"
  # The tag must touch exactly the catch-all, or the mutation silently moved an arm.
  [ "$(diff "$BATS_TEST_TMPDIR/lcase.txt" "$BATS_TEST_TMPDIR/lcaseB.txt" | grep -c '^[<>]')" -eq 2 ]
  RUN="$BATS_TEST_TMPDIR/lrun.sh"
  _classcov_runner "$BATS_TEST_TMPDIR/lcaseB.txt" "$RUN"

  # CONTROLS BEFORE VERDICTS. POS: a GLOBBED class member must still come back CLAIMED, or the
  # runner is mute and every verdict below is an artefact.
  [ "$(bash "$RUN" hooks/notify.sh </dev/null | grep -c '^1|hooks/\*\.sh$')" -eq 1 ]
  # FIRE: a source present nowhere MUST reach the tagged default, or this arm cannot fail at all.
  [ "$(bash "$RUN" zzz-no-such-literal/nope.txt </dev/null | grep -c '__DEFAULT__')" -eq 1 ]

  BAD="$BATS_TEST_TMPDIR/badliteral.txt"; : >"$BAD"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    out="$(bash "$RUN" "$rel" </dev/null)"
    case "$out" in
      *__DEFAULT__*) printf 'REASONLESS-DEFAULT %s\n' "$rel" >>"$BAD" ;;
      *)             : ;;   # CLAIMED (want=1) or declined by an EXPLICIT arm carrying its reason
    esac
  done < "$LITERALS"
  [ "$(grep -c . "$BAD")" -eq 0 ] || { echo "install.sh literal installs reaching the reasonless default:"; cat "$BAD"; false; }
}

@test "LITERAL INSTALL COVERAGE fire test: deleting a literal-install arm puts its source back on the default" {
  # Without this the arm above is a green nobody has seen go red, and a control that has never
  # fired is indistinguishable from one that cannot. Deleting ONE declaration must put exactly its
  # own source back on the reasonless default.
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$SUBJ" ]
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/lcase.txt"
  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/lcase.txt" > "$BATS_TEST_TMPDIR/lcaseB.txt"
  _classcov_runner "$BATS_TEST_TMPDIR/lcaseB.txt" "$BATS_TEST_TMPDIR/lintact.sh"

  # BASELINE: with the arm present, accounts.json is declared and must NOT read as the default.
  [ "$(bash "$BATS_TEST_TMPDIR/lintact.sh" accounts.json </dev/null | grep -c '__DEFAULT__')" -eq 0 ]

  # SEED: delete exactly the accounts.json arm. Asserted to remove ONE line, so a reworded arm
  # makes this test refuse rather than pass vacuously over a deletion that never happened.
  grep -v '^      accounts\.json)             want=0 ;;$' "$BATS_TEST_TMPDIR/lcaseB.txt" > "$BATS_TEST_TMPDIR/lcaseC.txt"
  [ "$(( $(grep -c . "$BATS_TEST_TMPDIR/lcaseB.txt") - $(grep -c . "$BATS_TEST_TMPDIR/lcaseC.txt") ))" -eq 1 ]
  _classcov_runner "$BATS_TEST_TMPDIR/lcaseC.txt" "$BATS_TEST_TMPDIR/lseeded.sh"

  # …and now that same source falls through to the reasonless default.
  [ "$(bash "$BATS_TEST_TMPDIR/lseeded.sh" accounts.json </dev/null | grep -c '__DEFAULT__')" -eq 1 ]
  # …while a SIBLING declaration is untouched, so the seed removed one arm and not the block.
  [ "$(bash "$BATS_TEST_TMPDIR/lseeded.sh" statusline.sh </dev/null | grep -c '__DEFAULT__')" -eq 0 ]
}

# ── RAW-INSTALL COVERAGE (2026-09-01, method 247 pointed at method 246's OWN remedy) ─────────────
# The LITERAL INSTALL COVERAGE arm above closed the gap the for-header extractor left — and it did
# so with an extractor keyed on TWO VERB NAMES, `link_file` and `copy_file`. A key on a verb name is
# itself a shape claim, so ask it the same question: what places bytes WITHOUT calling either verb?
#
# Measured 2026-09-01 over the real install.sh: 8 bare `run ln`/`run cp` lines, of which 3 are
# DEPLOYS (the rest are the two verbs' own bodies, a backup, and an intra-repo seed), and those 3
# partition 1/1/1 by SOURCE — one loop-driven (reachable from a for-header), one `$REPO_DIR` literal
# (CLAUDE.md: in NEITHER existing population, reaching the reasonless `*) want=0` AND absent from the
# assert's walk-input pathspec), and one whose source is a LIVE path and therefore cannot be named in
# `$REPO_DIR` units by ANY extractor keyed on them.
#
# NEITHER SIDE IS WRITTEN DOWN HERE. The population comes out of install.sh's own byte-placing lines
# via a FOURTH extractor — keyed on the SHAPE of the line, deliberately not on either verb name,
# because an arm that reuses the extractor whose blind spot it is checking cannot see past it — and
# the verdict for the namable class comes from EXECUTING the assert's own case block.
_rawdeploy_extract() {  # $1=install.sh  $2=out TSV: line \t kind \t srcclass \t src \t dest
  : > "$2"
  grep -nE '^[[:space:]]*run (ln|cp)( |$)' "$1" | while IFS= read -r _line; do
    _no="${_line%%:*}"; _body="${_line#*:}"
    _toks="$(printf '%s\n' "$_body" | grep -oE '"[^"]*"')"
    # sed, not head/tail: a first-line read through a pipe can SIGPIPE its producer, and this file
    # is not the place to find out whether pipefail is on.
    _src="$(printf '%s\n' "$_toks" | sed -n '1p' | tr -d '"')"
    _dst="$(printf '%s\n' "$_toks" | sed -n '$p' | tr -d '"')"
    _kind=DEPLOY
    case "$_dst" in
      *.bak)        _kind=BACKUP ;;      # a migration backup, not a deploy
      '$REPO_DIR'*) _kind=INTRA-REPO ;;  # seeds a file INSIDE the checkout (accounts.json.example)
    esac
    case "$_src" in
      '$src'|'$dest') _kind=VERB-BODY ;; # link_file/copy_file's own locals — the verbs themselves
    esac
    _sc=OTHER
    case "$_src" in
      '$REPO_DIR/'*)             _sc=REPO-LITERAL ;;
      '$HOME/'*|'$CONFIG_DIR/'*) _sc=LIVE-PATH ;;
      '$'*)                      _sc=VARIABLE ;;
    esac
    printf '%s\t%s\t%s\t%s\t%s\n' "$_no" "$_kind" "$_sc" "$_src" "$_dst" >> "$2"
  done
}

@test "RAW INSTALL COVERAGE: every install.sh raw run-ln/run-cp deploy is loop-driven, claimed, or declared" {
  MAP="$REPO_ROOT/install.sh"
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$MAP" ]
  [ -f "$SUBJ" ]

  RAW="$BATS_TEST_TMPDIR/raw.tsv"
  _rawdeploy_extract "$MAP" "$RAW"
  # NON-VACUITY FLOOR: a broken anchor derives zero lines and every assertion below then passes over
  # an empty set. Measured 8 on 2026-09-01; the floor is deliberately loose.
  [ "$(grep -c . "$RAW")" -ge 6 ]
  # …and a KNOWN member, so a derivation that produced six lines of the wrong thing still fails.
  [ "$(awk -F'\t' '$4=="$REPO_DIR/CLAUDE.md"{n++} END{print n+0}' "$RAW")" -eq 1 ]

  # (2) BOTH PARTITIONS MUST SUM. A raw line is exactly one of VERB-BODY / BACKUP / INTRA-REPO /
  # DEPLOY, and a DEPLOY is exactly one of VARIABLE / LIVE-PATH / REPO-LITERAL by its source. A shape
  # that escapes the classifier lands in neither total, so the arm REFUSES rather than passing over
  # it — which is the property the for-header and verb-name extractors both lacked.
  TOT="$(awk 'END{print NR+0}' "$RAW")"
  KVB="$(awk -F'\t' '$2=="VERB-BODY"{n++}  END{print n+0}' "$RAW")"
  KBK="$(awk -F'\t' '$2=="BACKUP"{n++}     END{print n+0}' "$RAW")"
  KIR="$(awk -F'\t' '$2=="INTRA-REPO"{n++} END{print n+0}' "$RAW")"
  KDP="$(awk -F'\t' '$2=="DEPLOY"{n++}     END{print n+0}' "$RAW")"
  [ "$((KVB + KBK + KIR + KDP))" -eq "$TOT" ]
  DVAR="$(awk -F'\t'  '$2=="DEPLOY" && $3=="VARIABLE"{n++}     END{print n+0}' "$RAW")"
  DLIVE="$(awk -F'\t' '$2=="DEPLOY" && $3=="LIVE-PATH"{n++}    END{print n+0}' "$RAW")"
  DLIT="$(awk -F'\t'  '$2=="DEPLOY" && $3=="REPO-LITERAL"{n++} END{print n+0}' "$RAW")"
  [ "$((DVAR + DLIVE + DLIT))" -eq "$KDP" ]

  # (3) THE NAMABLE CLASS, decided by the SUBJECT'S OWN ARBITER rather than by re-reading it.
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/rcase.txt"
  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/rcase.txt" > "$BATS_TEST_TMPDIR/rcaseB.txt"
  # The tag must touch exactly the catch-all, or the mutation silently moved an arm.
  [ "$(diff "$BATS_TEST_TMPDIR/rcase.txt" "$BATS_TEST_TMPDIR/rcaseB.txt" | grep -c '^[<>]')" -eq 2 ]
  RRUN="$BATS_TEST_TMPDIR/rrun.sh"
  _classcov_runner "$BATS_TEST_TMPDIR/rcaseB.txt" "$RRUN"
  # CONTROLS BEFORE VERDICTS. POS: a globbed class member must still come back CLAIMED, or the
  # runner is mute and every verdict below is an artefact.
  [ "$(bash "$RRUN" hooks/notify.sh </dev/null | grep -c '^1|hooks/\*\.sh$')" -eq 1 ]
  # FIRE: a source present nowhere MUST reach the tagged default, or this arm cannot fail at all.
  [ "$(bash "$RRUN" zzz-no-such-raw-install/nope.txt </dev/null | grep -c '__DEFAULT__')" -eq 1 ]

  RBAD="$BATS_TEST_TMPDIR/rawbad.txt"; : >"$RBAD"
  awk -F'\t' '$2=="DEPLOY" && $3=="REPO-LITERAL"{sub(/^\$REPO_DIR\//,"",$4); print $4}' "$RAW" \
    | sort -u > "$BATS_TEST_TMPDIR/rawlit.txt"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    out="$(bash "$RRUN" "$rel" </dev/null)"
    case "$out" in
      *__DEFAULT__*) printf 'REASONLESS-DEFAULT %s\n' "$rel" >>"$RBAD" ;;
      *)             : ;;   # CLAIMED (want=1) or declined by an EXPLICIT arm carrying its reason
    esac
  done < "$BATS_TEST_TMPDIR/rawlit.txt"
  [ "$(grep -c . "$RBAD")" -eq 0 ] || { echo "install.sh raw deploys reaching the reasonless default:"; cat "$RBAD"; false; }

  # (4) THE TWO CLASSES NO $REPO_DIR-KEYED ARM CAN SCORE, each pinned at its measured count so a
  # SECOND one of either shape refuses here rather than arriving unannounced.
  # VARIABLE source: install.sh:776, the vendor DIRECTORY link. `ln -sfn` and not `ln -sf` is
  # load-bearing — install.sh's own comment says a re-run whose target changed would otherwise
  # create the new link INSIDE the existing dir symlink — so the spelling is what identifies it.
  [ "$DVAR" -eq 1 ]
  [ "$(awk -F'\t' '$2=="DEPLOY" && $3=="VARIABLE"{print $1}' "$RAW" \
       | while IFS= read -r n; do sed -n "${n}p" "$MAP"; done | grep -c 'ln -sfn')" -eq 1 ]
  # LIVE-PATH source: install.sh:703's ~/bin/restore-file convenience symlink. Its source is
  # $HOME/.claude/..., i.e. the LIVE layer rather than the checkout, so it is unnamable in the units
  # every other arm here uses. Pinned by DESTINATION for that reason.
  [ "$DLIVE" -eq 1 ]
  [ "$(awk -F'\t' '$2=="DEPLOY" && $3=="LIVE-PATH" && $5=="$HOME/bin/restore-file"{n++} END{print n+0}' "$RAW")" -eq 1 ]
  true
}

@test "RAW INSTALL COVERAGE fire test: deleting the CLAUDE.md declaration puts its source back on the default" {
  # Without this the arm above is a green nobody has seen go red, and a control that has never fired
  # is indistinguishable from one that cannot. Deleting ONE declaration must put exactly its own
  # source back on the reasonless default and leave its siblings alone.
  SUBJ="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  [ -f "$SUBJ" ]
  [ "$(grep -c '^    cls=""$' "$SUBJ")" -eq 1 ]
  _classcov_extract "$SUBJ" "$BATS_TEST_TMPDIR/rcase.txt"
  sed 's|^      \*)                         want=0 ;;$|      *)                         want=0; cls="__DEFAULT__" ;;|' \
    "$BATS_TEST_TMPDIR/rcase.txt" > "$BATS_TEST_TMPDIR/rcaseB.txt"
  _classcov_runner "$BATS_TEST_TMPDIR/rcaseB.txt" "$BATS_TEST_TMPDIR/rintact.sh"

  # BASELINE: with the arm present, CLAUDE.md is declared and must NOT read as the default.
  [ "$(bash "$BATS_TEST_TMPDIR/rintact.sh" CLAUDE.md </dev/null | grep -c '__DEFAULT__')" -eq 0 ]

  # SEED: delete exactly the CLAUDE.md arm. Asserted to remove ONE line, so a reworded arm makes
  # this test refuse rather than pass vacuously over a deletion that never happened.
  grep -v '^      CLAUDE\.md)                 want=0 ;;$' "$BATS_TEST_TMPDIR/rcaseB.txt" \
    > "$BATS_TEST_TMPDIR/rcaseC.txt"
  [ "$(( $(grep -c . "$BATS_TEST_TMPDIR/rcaseB.txt") - $(grep -c . "$BATS_TEST_TMPDIR/rcaseC.txt") ))" -eq 1 ]
  _classcov_runner "$BATS_TEST_TMPDIR/rcaseC.txt" "$BATS_TEST_TMPDIR/rseeded.sh"

  # …and now that same source falls through to the reasonless default.
  [ "$(bash "$BATS_TEST_TMPDIR/rseeded.sh" CLAUDE.md </dev/null | grep -c '__DEFAULT__')" -eq 1 ]
  # …while a SIBLING declaration is untouched, so the seed removed one arm and not the block.
  [ "$(bash "$BATS_TEST_TMPDIR/rseeded.sh" accounts.json </dev/null | grep -c '__DEFAULT__')" -eq 0 ]
}
