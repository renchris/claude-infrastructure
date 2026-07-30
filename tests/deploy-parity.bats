#!/usr/bin/env bats
# deploy-parity-assert.sh — the ~/bin deployment drift assertion.
#
# Guards the failure that motivated the script: bin/claude-accounts was deployed to ~/bin as a
# COPY, so a repo edit did not reach the running tool. It drifted for two days undetected while
# every consumer ran the old code, and sync.sh (which copies ~/bin BACK into the repo with no
# direction guard) would have clobbered the newer repo file with the stale copy.
#
# FULLY HERMETIC: every case builds a fake repo + fake bindir in BATS_TEST_TMPDIR and drives the
# script via CC_PARITY_REPO / CC_PARITY_BINDIR / CC_PARITY_STRICT / CC_PARITY_COPY. Nothing here
# reads the real ~/bin or the real checkout, so it passes on a fresh clone, a worktree and CI.
# (The live host is asserted by running the script itself, not by this suite.)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export ASSERT="$REPO_ROOT/scripts/deploy-parity-assert.sh"
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

@test "the real repo passes its own assertion (guards the live host deployment)" {
  run env -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY "$ASSERT"
  # Exit 3 is the assert's NO-VERDICT state: a `diff` or the tracked-file listing could not RUN. That
  # is a fact about the machine, not about the live layer — and it is reachable here, because
  # deploy-live.sh runs this suite post-deploy at `nice -n 19` next to a corpus (fork exhaustion at
  # loadavg 15-48 is measured in scripts/host-suites.manifest). Letting it fall through to the
  # `-eq 0` below would turn a non-verdict into a live-layer RED that PAGES and files a backlog
  # packet — the same fabricated-verdict class this suite pins one level down, re-created in its own
  # consumer. A new third state has to be taught to everything that reads the exit code.
  # Exit 1 is NOT covered by this: real drift still fails here, loudly, as it must.
  [ "$status" -ne 3 ] || skip "assert returned NO VERDICT (exit 3), no claim about the host: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-accounts"* ]]
}

# ── EXISTENCE PARITY (2026-07-25) — the bare-ff deploy hole ──────────────────────────────────────
# ~/.claude/{hooks,hooks/lib,commands,scripts,bin} are real dirs of PER-FILE symlinks, so a
# BRAND-NEW tracked file is never linked at all, however current the checkout — only ./install.sh
# links it, and the operator's documented deploy step (ff-sync) cannot. That shipped live:
# hooks/lib/cc-interactive.sh landed unlinked, collapsing all three of cc-classify's resolve
# candidates and silently disabling the operator-adoption hold (a reaper fail-OPEN).
# Still fully hermetic: a throwaway git checkout + a fake live root under BATS_TEST_TMPDIR.

_livefix() {   # real checkout + empty live root; ~/bin legs made to PASS so exit code isolates this leg
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

@test "existence: files install.sh does NOT link are never asserted (no false demands)" {
  _livefix
  mkdir -p "$CC_PARITY_REPO"/{hooks/other,commands/sub,scripts/sub,scripts/limit-recover/deep,bin/cc-dir,skills/a-skill/refs,lib}
  printf 'x\n' > "$CC_PARITY_REPO/hooks/README.md"                  # hooks/*.md — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/hooks/other/nested.sh"            # hooks/<subdir>/ — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/commands/sub/nested.md"           # commands/<subdir>/ — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/scripts/sub/nested.sh"            # scripts/ is top-level only
  printf 'x\n' > "$CC_PARITY_REPO/scripts/limit-recover/deep/x.sh"  # limit-recover is top-level only
  printf 'x\n' > "$CC_PARITY_REPO/bin/cc-dir/nested"                # bin/cc-*/ subdir — not a file link
  printf 'x\n' > "$CC_PARITY_REPO/bin/other-tool"                   # bin/ non-cc-* — not globbed
  printf 'x\n' > "$CC_PARITY_REPO/skills/a-skill/refs/deep.md"      # skills/<name>/<subdir>/ — one level only
  printf 'x\n' > "$CC_PARITY_REPO/skills/stray.md"                  # a file directly in skills/ — not a skill dir
  printf 'x\n' > "$CC_PARITY_REPO/lib/thing.sh"                     # top-level lib/ — install.sh has NO lib leg
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
@test "the assert agrees with itself through a DEPLOYED symlink (\$0 resolved, not dirname'd)" {
  # CC_PARITY_REPO must be UNSET here: it short-circuits the very derivation under test.
  # The bin/ link is what makes the two verdicts DIVERGE under the bug: without it the strict-tool
  # comparison is skipped and both invocations agree trivially, so the assertion could not fail.
  d="$BATS_TEST_TMPDIR/dep"; mkdir -p "$d/scripts" "$d/bin"
  ln -s "$REPO_ROOT/bin/claude-accounts" "$d/bin/claude-accounts"
  ln -s "$ASSERT" "$d/scripts/deploy-parity-assert.sh"
  run env -u ITERM_SESSION_ID -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY -u CC_PARITY_LIVE bash "$d/scripts/deploy-parity-assert.sh"
  via_symlink="$status"; via_out="$output"
  run env -u ITERM_SESSION_ID -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY -u CC_PARITY_LIVE bash "$ASSERT"
  [ "$via_symlink" -eq "$status" ] || false
  # NON-VACUITY (2026-07-29). Two agreeing exit codes prove nothing if NEITHER invocation compared
  # anything — and a vacuous agreement is precisely the fail-open the next test pins. So require
  # evidence that a comparison actually happened: a named verdict, and not the no-verdict state.
  # Deliberately NOT pinned to 0 — the real host legitimately reads 1 while a landed file awaits its
  # live symlink, and this test is about AGREEMENT, not about the host being clean (test above owns that).
  [ "$via_symlink" -ne 3 ] || false
  [[ "$via_out" == *"claude-accounts"* ]] || false
}

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
  [[ "$output" == *"NOVERDICT"* ]]
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
  [[ "$output" == *"NOVERDICT"* ]]
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
