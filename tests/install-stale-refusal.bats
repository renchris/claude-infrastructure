#!/usr/bin/env bats
# install-stale-refusal.bats — install.sh must refuse a GLOBAL install from a STALE checkout.
#
# THE DEFECT (observed live 2026-08-01, and it reported SUCCESS while committing it): a sibling
# session left a local commit on main in the shared checkout, so `git merge-base --is-ancestor
# origin/main HEAD` was false — trunk held a commit the tree did not. install.sh had never been
# trunk-aware, so it deployed that tree, printed "✓ CLAUDE.md (554 lines)" and exited 0 while
# copying a version WITHOUT the rule that had just landed; every hooks/ symlink kept resolving to
# the stale content. Land verified green, deploy verified green, live layer wrong. The failure is
# invisible exactly because both halves report success.
#
# PREDICATE IS CONTAINMENT, NOT EQUALITY. Ahead-of-trunk is normal (every pre-land state) and must
# NOT refuse; behind-trunk is what silently ships yesterday's tree. Tests 5 and 6 are the
# false-positive guards for that distinction and must pass both before and after the change.
# Test 9 is the positive control: it proves the guarded mechanism is REAL (a stale deploy really
# does write pre-trunk content), so the refusals cannot be passing vacuously.

# THE SEEDED SSOT NAME IS DERIVED FROM install.sh, NEVER HARDCODED. 367e42f2 renamed the repo-side
# global SSOT `CLAUDE.md` -> `CLAUDE.global.md` and its commit body lists "every reader of the old
# path, audited and repointed" — this file was not among them, because it does not READ a repo path,
# it WRITES a synthetic one ("$TDIR/seed/CLAUDE.md"), which matches no grep for the old reader. The
# seed then lacked the file install.sh copies out, its `cp` aborted the run, and SIX tests went red
# on `[ "$status" -eq 0 ]` while the real cause ("cp: cannot stat .../CLAUDE.global.md") appeared
# only in captured output no TAP reader prints (cc-backlog cde8a9e450bc convicted a commit 32 later,
# whose diff touches neither install.sh nor this file — record:
# docs/research/install-fixture-ssot-drift-2026-09-11.md). Deriving the name means the next rename cannot
# silently drift this fixture; the derivation FAILS CLOSED (a broken match aborts with a named
# message) because a default here would restore exactly the mute failure it replaces.
# NOTE THE ASYMMETRY, which is load-bearing: repo side CLAUDE.global.md, live side CLAUDE.md. While
# both sides shared one name a subject reading the WRONG side still found a file, so no fixture
# could tell the two identifier spaces apart. Do NOT also seed a root CLAUDE.md to "be safe" — it
# re-collapses the two spaces, and a root CLAUDE.md is the very thing 367e42f2 exists to forbid.
# NON-EMPTY IS NOT THE GUARD — measured, a mutant that respelled the cp source as an unexpanded
# "$REPO_DIR/$GLOBAL_SSOT" made the capture non-empty (`[^"]*` matches a variable reference just as
# happily as a filename), so the first draft of this derivation failed OPEN straight back into the
# six mute `status -eq 0` reds it exists to replace. The load-bearing check is therefore that the
# derived token is a PLAIN filename AND names a real file in the real repo: a derivation that
# produced garbage then cannot be mistaken for one that produced an answer.
derive_ssot_name() {
  local src="$1" n
  n="$(sed -n 's|^ *run cp "\$REPO_DIR/\([^"]*\)" "\$CONFIG_DIR/CLAUDE\.md".*|\1|p' "$src" | head -1)"
  case "$n" in
    ''|*'$'*|*/*) return 1 ;;
  esac
  [ -f "$(dirname "$src")/$n" ] || return 1
  printf '%s' "$n"
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TDIR="$(cd "$(mktemp -d)" && pwd -P)"; export TDIR
  ORIGIN="$TDIR/origin.git"; CLONE="$TDIR/clone"

  if ! SSOT="$(derive_ssot_name "$REPO/install.sh")"; then
    echo "FIXTURE: cannot derive the global-SSOT filename from install.sh — the line that copies" >&2
    echo "  \$REPO_DIR/<name> to \$CONFIG_DIR/CLAUDE.md has changed shape. Repoint derive_ssot_name;" >&2
    echo "  do NOT hardcode a name here, that is what drifted at 367e42f2." >&2
    return 1
  fi

  git init -q --bare "$ORIGIN"
  mkdir -p "$TDIR/seed/agents"
  cp "$REPO/install.sh" "$TDIR/seed/install.sh"
  printf 'TRUNK-V1\n' > "$TDIR/seed/$SSOT"
  printf '#!/bin/bash\necho fixture-statusline\n' > "$TDIR/seed/statusline.sh"
  printf 'fixture agent\n' > "$TDIR/seed/agents/fixture-agent.md"
  git init -q "$TDIR/seed"
  git -C "$TDIR/seed" -c user.email=t@t -c user.name=t add -A
  git -C "$TDIR/seed" -c user.email=t@t -c user.name=t commit -q -m base
  git -C "$TDIR/seed" branch -M main
  git -C "$TDIR/seed" remote add origin "$ORIGIN"
  git -C "$TDIR/seed" push -q -u origin main
  # -b main is load-bearing: `git init --bare` leaves HEAD on refs/heads/master, so a bare
  # `git clone` of a main-only repo checks out NOTHING and install.sh is absent (exit 127).
  git clone -q -b main "$ORIGIN" "$CLONE"
  git -C "$CLONE" config user.email t@t; git -C "$CLONE" config user.name t

  STUB="$TDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/launchctl"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/defaults"
  chmod +x "$STUB/launchctl" "$STUB/defaults"
  export PATH="$STUB:$PATH"
}
teardown() { rm -rf "$TDIR"; }

has()   { printf '%s' "$output" | grep -qF -- "$1"; }
lacks() { if printf '%s' "$output" | grep -qF -- "$1"; then return 1; fi; return 0; }

# advance origin/main past the clone, so the clone is BEHIND trunk
advance_origin() {
  printf 'TRUNK-V2-LANDED\n' > "$TDIR/seed/$SSOT"
  git -C "$TDIR/seed" -c user.email=t@t -c user.name=t commit -q -am "trunk moves on"
  git -C "$TDIR/seed" push -q origin main
}
# the EXACT 2026-08-01 shape: a local commit of our own AND trunk ahead of us
make_stale_with_local_commit() {
  advance_origin
  printf 'local sibling work\n' > "$CLONE/sibling.txt"
  git -C "$CLONE" add sibling.txt; git -C "$CLONE" commit -q -m "a sibling's local commit"
}

@test "global install from a STALE checkout is REFUSED and writes nothing" {
  make_stale_with_local_commit
  run bash "$CLONE/install.sh"
  [ "$status" -eq 1 ]
  has "REFUSING a global install from a STALE checkout"
  [ ! -e "$HOME/.claude" ]
}

@test "the refusal names the behind-count and hands over the exact reconcile + re-run" {
  make_stale_with_local_commit
  run bash "$CLONE/install.sh"
  has "behind     : 1 commit(s)"
  has "git -C $CLONE pull --rebase origin main"
  has "$CLONE/install.sh"
}

@test "the refusal states WHICH answer it has about the ref's own freshness" {
  make_stale_with_local_commit
  run bash "$CLONE/install.sh"
  has "ref state  :"
}

@test "CC_INSTALL_ALLOW_STALE=1 overrides the refusal, loudly" {
  make_stale_with_local_commit
  CC_INSTALL_ALLOW_STALE=1 run bash "$CLONE/install.sh"
  [ "$status" -eq 0 ]
  has "CC_INSTALL_ALLOW_STALE=1"
}

# ---- false-positive guards: these must pass BEFORE and AFTER the change -----------------------

@test "FP GUARD: a checkout AHEAD of trunk installs normally (every pre-land state)" {
  printf 'local unlanded work\n' > "$CLONE/ahead.txt"
  git -C "$CLONE" add ahead.txt; git -C "$CLONE" commit -q -m "ahead of trunk"
  run bash "$CLONE/install.sh"
  [ "$status" -eq 0 ]
  lacks "REFUSING a global install from a STALE checkout"
}

@test "FP GUARD: a checkout EQUAL to trunk installs with no staleness noise" {
  run bash "$CLONE/install.sh"
  [ "$status" -eq 0 ]
  lacks "STALE"
}

@test "FP GUARD: --config-dir from a stale checkout WARNS but does not refuse (automated lane)" {
  make_stale_with_local_commit
  run bash "$CLONE/install.sh" --config-dir "$TDIR/altcfg"
  [ "$status" -eq 0 ]
  has "STALE checkout"
}

@test "no origin/main ref ⇒ reported as CANNOT-VERIFY, never a silent pass" {
  git -C "$CLONE" remote remove origin
  run bash "$CLONE/install.sh"
  [ "$status" -eq 0 ]
  has "cannot verify this checkout is current"
}

@test "--dry-run is NOT exempt — previewing a stale tree previews the wrong tree" {
  make_stale_with_local_commit
  run bash "$CLONE/install.sh" --dry-run
  [ "$status" -eq 1 ]
  has "REFUSING a global install from a STALE checkout"
}

# ---- positive control: the guarded harm is REAL ------------------------------------------------

@test "POSITIVE CONTROL: a stale deploy really does write pre-trunk content (refusal is not vacuous)" {
  make_stale_with_local_commit
  CC_INSTALL_ALLOW_STALE=1 run bash "$CLONE/install.sh"
  [ "$status" -eq 0 ]
  # trunk says TRUNK-V2-LANDED; the stale tree ships V1 — exactly the silent-wrong-live-layer bug
  grep -q 'TRUNK-V1' "$HOME/.claude/CLAUDE.md"
  ! grep -q 'TRUNK-V2-LANDED' "$HOME/.claude/CLAUDE.md" || false
}
