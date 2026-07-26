#!/usr/bin/env bats
# deploy-link-parity.sh — the "landed but not live" reporter.
#
# Guards the failure that motivated it: ~/.claude/{hooks,commands,scripts,bin,skills} are real
# directories of PER-FILE symlinks, so a fast-forward updates every already-linked file and deploys
# NOTHING for a file the checkout gained. `git rev-list HEAD..origin/main` reads 0 while the new
# code does not run at all (scripts/desk-arm-live.sh, 2026-07-20; the lr-reset-poller, 2026-07-21).
#
# And the inverse, which is why the script REPORTS instead of repairing: a settings-wired hook is
# deliberately left unlinked until its staged activation script runs. Auto-linking would erase the
# only signal that the wiring is pending, so PENDING must stay a clean exit and UNLINKED must not.
#
# FULLY HERMETIC: every case builds a fake checkout + config dir + bindir + pending-activation dir
# in BATS_TEST_TMPDIR and drives the script via CC_LINKPARITY_REPO / CC_LINKPARITY_CONFIG /
# CC_LINKPARITY_BINDIR / CC_LINKPARITY_PENDING. No case reads the real ~/.claude or the real
# checkout, so this passes on a fresh clone, in a worktree and in CI. (The live host is asserted by
# running the script itself, not by this suite.)
#
# ASSERTION FORM: non-final `[[ ]]` and bare `!` are silently DEAD under bats+set -e (verified on
# bats 1.13.0). Every assertion here is a `[ ]`, a helper function call, or a pipeline — all three
# are live in any position.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LP="$REPO_ROOT/scripts/deploy-link-parity.sh"

  export CC_LINKPARITY_REPO="$BATS_TEST_TMPDIR/repo"
  export CC_LINKPARITY_CONFIG="$BATS_TEST_TMPDIR/cfg"
  export CC_LINKPARITY_BINDIR="$BATS_TEST_TMPDIR/bin"
  export CC_LINKPARITY_PENDING="$BATS_TEST_TMPDIR/pending"

  mkdir -p "$CC_LINKPARITY_REPO"/{hooks/lib,commands,scripts/limit-recover,bin,skills/demo}
  mkdir -p "$CC_LINKPARITY_CONFIG"/{hooks/lib,commands,scripts/limit-recover,bin,skills/demo}
  mkdir -p "$CC_LINKPARITY_BINDIR" "$CC_LINKPARITY_PENDING"

  # one already-correct link, so a clean run is provably non-vacuous
  printf 'old\n' > "$CC_LINKPARITY_REPO/hooks/established.sh"
  ln -sfn "$CC_LINKPARITY_REPO/hooks/established.sh" "$CC_LINKPARITY_CONFIG/hooks/established.sh"
}

# `printf | grep` and function calls are live assertions in any position; `[[ ]]` is not.
has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# A file that landed in the checkout and is named by NO staged activation script.
land_new() { printf 'new\n' > "$CC_LINKPARITY_REPO/$1"; }

# A staged activation script that names a repo-relative path, exactly as the real ones do.
stage_activation() {  # $1 = script name · $2 = repo-relative path it will link
  printf '#!/bin/bash\nSRC="$REPO/%s"\nln -sfn "$SRC" "$CFG/%s"\n' "$2" "$2" \
    > "$CC_LINKPARITY_PENDING/$1"
}

@test "everything linked ⇒ clean, exit 0, and the linked count proves it looked" {
  run "$LP"
  [ "$status" -eq 0 ]
  has "1 linked"
  has "every landed file is live"
}

@test "a NEW checkout file with no live link ⇒ UNLINKED, exit 1 (the desk-arm-live regression)" {
  land_new "scripts/desk-arm-live.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNLINKED"
  has "scripts/desk-arm-live.sh"
  has "silently inert"
}

@test "UNLINKED emits an exact runnable ln -sfn command, not a description" {
  land_new "hooks/brand-new.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ln -sfn \"$CC_LINKPARITY_REPO/hooks/brand-new.sh\" \"$CC_LINKPARITY_CONFIG/hooks/brand-new.sh\""
}

@test "REPORT-ONLY: a dirty run creates no link and removes nothing" {
  land_new "hooks/brand-new.sh"
  ln -sfn "$CC_LINKPARITY_REPO/hooks/vanished.sh" "$CC_LINKPARITY_CONFIG/hooks/vanished.sh"
  before="$(find "$CC_LINKPARITY_CONFIG" | sort)"
  run "$LP"
  [ "$status" -eq 1 ]
  after="$(find "$CC_LINKPARITY_CONFIG" | sort)"
  [ "$before" = "$after" ]
  [ ! -e "$CC_LINKPARITY_CONFIG/hooks/brand-new.sh" ]
}

@test "unlinked BUT named by a staged activation ⇒ PENDING, exit 0 (by design, not a gap)" {
  land_new "hooks/dispatch-assert.sh"
  stage_activation "11-dispatch-assert-activate.sh" "hooks/dispatch-assert.sh"
  run "$LP"
  [ "$status" -eq 0 ]
  has "PENDING"
  has "11-dispatch-assert-activate.sh"
  has "1 staged-pending"
  lacks "UNLINKED"
}

@test "PENDING never proposes a link — the activation script owns that step" {
  land_new "hooks/dispatch-assert.sh"
  stage_activation "11-dispatch-assert-activate.sh" "hooks/dispatch-assert.sh"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "ln -sfn"
}

@test "activation already .done ⇒ no longer an excuse, back to UNLINKED exit 1" {
  land_new "hooks/dispatch-assert.sh"
  stage_activation "11-dispatch-assert-activate.sh" "hooks/dispatch-assert.sh"
  touch "$CC_LINKPARITY_PENDING/11-dispatch-assert-activate.sh.done"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNLINKED"
  lacks "PENDING"
}

@test "PENDING matches the repo-relative PATH, not a bare basename (no false all-clear)" {
  land_new "hooks/watcher.sh"
  # names only the basename, and for a DIFFERENT surface — must not launder hooks/watcher.sh
  printf '#!/bin/bash\n# mentions watcher.sh and scripts/watcher.sh only\n' \
    > "$CC_LINKPARITY_PENDING/99-decoy-activate.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "UNLINKED"
  lacks "PENDING"
}

@test "a real file where a symlink belongs ⇒ SHADOW (repo edits never reach it)" {
  printf 'repo\n' > "$CC_LINKPARITY_REPO/scripts/drifted.sh"
  printf 'stale\n' > "$CC_LINKPARITY_CONFIG/scripts/drifted.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "SHADOW"
  has "NOT live"
}

@test "a live link pointing outside this checkout ⇒ MISLINKED" {
  printf 'repo\n' > "$CC_LINKPARITY_REPO/scripts/hijacked.sh"
  printf 'other\n' > "$BATS_TEST_TMPDIR/elsewhere.sh"
  ln -sfn "$BATS_TEST_TMPDIR/elsewhere.sh" "$CC_LINKPARITY_CONFIG/scripts/hijacked.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "MISLINKED"
}

@test "a live link whose checkout target was renamed away ⇒ ORPHAN + an rm command" {
  ln -sfn "$CC_LINKPARITY_REPO/scripts/renamed-away.sh" "$CC_LINKPARITY_CONFIG/scripts/renamed-away.sh"
  run "$LP"
  [ "$status" -eq 1 ]
  has "ORPHAN"
  has "rm \"$CC_LINKPARITY_CONFIG/scripts/renamed-away.sh\""
}

@test "a link into a FOREIGN repo is not ours to judge — never reported as an orphan" {
  # ~/.claude/bin carries live links into other checkouts (claude-session-search); a dangling one
  # there is that repo's business, and flagging it would train the operator to ignore this report.
  ln -sfn "$BATS_TEST_TMPDIR/other-repo/bin/tool" "$CC_LINKPARITY_CONFIG/bin/cc-foreign"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "ORPHAN"
}

@test "--quiet is silent when clean but still speaks up when actionable" {
  run "$LP" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  land_new "hooks/brand-new.sh"
  run "$LP" --quiet
  [ "$status" -eq 1 ]
  has "UNLINKED"
}

@test "--all lists correctly-linked files too" {
  run "$LP" --all
  [ "$status" -eq 0 ]
  has "LINKED"
  has "hooks/established.sh"
}

@test "every per-file symlink surface install.sh deploys is actually covered" {
  land_new "hooks/s1.sh"
  land_new "hooks/lib/s2.sh"
  land_new "commands/s3.md"
  land_new "scripts/s4.sh"
  land_new "scripts/limit-recover/s5.sh"
  land_new "bin/cc-s6"
  land_new "skills/demo/SKILL.md"
  land_new "accounts.json"
  land_new "bin/claude-accounts"
  run "$LP"
  [ "$status" -eq 1 ]
  for f in hooks/s1.sh hooks/lib/s2.sh commands/s3.md scripts/s4.sh \
           scripts/limit-recover/s5.sh bin/cc-s6 skills/demo/SKILL.md accounts.json; do
    has "$f"
  done
  # claude-accounts is the one link that lands in BINDIR, not the config dir
  has "$CC_LINKPARITY_BINDIR/claude-accounts"
}

@test "non-symlink surfaces stay out of scope (deploy-parity-assert.sh owns COPY drift)" {
  land_new "statusline.sh"
  land_new "CLAUDE.md"
  mkdir -p "$CC_LINKPARITY_REPO/launchd"; land_new "launchd/com.example.plist"
  run "$LP"
  [ "$status" -eq 0 ]
  lacks "statusline.sh"
  lacks "CLAUDE.md"
  lacks "com.example.plist"
}

@test "invoked VIA ITS OWN LIVE SYMLINK it still resolves a real checkout, never ~/.claude" {
  # The deploy-parity-assert.sh defect class: BASH_SOURCE is the symlink path, so an unresolved
  # dirname puts the repo root at ~/.claude — not a checkout — and every leg exits 0 vacuously.
  ln -sfn "$LP" "$BATS_TEST_TMPDIR/live-link.sh"
  land_new "hooks/brand-new.sh"
  run "$BATS_TEST_TMPDIR/live-link.sh"
  [ "$status" -eq 1 ]
  has "UNLINKED"
}

@test "a missing config dir is a prerequisite failure (3), never a vacuous pass" {
  export CC_LINKPARITY_CONFIG="$BATS_TEST_TMPDIR/no-such-dir"
  run "$LP"
  [ "$status" -eq 3 ]
}

@test "a missing checkout is a prerequisite failure (3), never a vacuous pass" {
  export CC_LINKPARITY_REPO="$BATS_TEST_TMPDIR/no-such-repo"
  run "$LP"
  [ "$status" -eq 3 ]
}
