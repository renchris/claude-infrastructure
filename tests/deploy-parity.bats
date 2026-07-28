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

@test "a tool absent from the checkout is skipped, not reported as drift" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  CC_PARITY_COPY="toolB toolZZ" run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"toolZZ"* ]]
}

@test "the real repo passes its own assertion (guards the live host deployment)" {
  run env -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY "$ASSERT"
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
  via_symlink="$status"
  run env -u ITERM_SESSION_ID -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY -u CC_PARITY_LIVE bash "$ASSERT"
  [ "$via_symlink" -eq "$status" ] || false
}

@test "resolving \$0 through symlinks is present (the mechanism, not just the outcome)" {
  grep -q 'while \[ -L "\$_self" \]' "$ASSERT" || false
}
