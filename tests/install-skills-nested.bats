#!/usr/bin/env bats
# install.sh --- Skills --- deploys NESTED skill files, and never destroys an unversioned real file.
#
# Pre-fix, the skills loop was `for f in "$skilldir"*` + `[[ -f "$f" ]]` — top level only. A nested
# tracked file was therefore never linked, and the 23 skills/kpmg-deck/**/* files on trunk lived as
# REAL FILES outside the converger. Tests 1-2 are RED against that loop (the paths simply do not
# exist in a fresh config dir); tests 4-5 pin the backup guard that recursion makes necessary,
# with 5 as its inertness control.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # install.sh derives IS_GLOBAL from "$CONFIG_DIR" == "$HOME/.claude" and links convenience
  # entrypoints under $HOME/bin. A tmpdir --config-dir already forces the non-global path, but
  # nothing about that is guaranteed by the subject, so fixture $HOME rather than trusting it:
  # these cases must never be able to touch the operator's live tree.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/bin"
  CFG="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$CFG"
  # A tracked skill that actually carries nested content. If this fixture ever goes flat the
  # tests below would pass vacuously, so assert its shape rather than trusting the name.
  NESTED_REL="references/brand-kit.md"
  NESTED_SRC="$REPO/skills/kpmg-deck/$NESTED_REL"
}

run_install() { run bash "$REPO/install.sh" --config-dir "$CFG"; }

@test "fixture is real: the repo skill under test carries nested tracked content" {
  [ -f "$NESTED_SRC" ]
  run bash -c "find '$REPO/skills/kpmg-deck' -mindepth 2 -type f | wc -l"
  [ "$output" -gt 0 ]
}

@test "a NESTED skill file is deployed, and as a symlink back to the repo" {
  run_install
  [ "$status" -eq 0 ]
  dest="$CFG/skills/kpmg-deck/$NESTED_REL"
  [ -L "$dest" ]
  [ "$(readlink "$dest")" = "$NESTED_SRC" ]
}

@test "nested parent directories are created as REAL dirs, not symlinks" {
  run_install
  [ "$status" -eq 0 ]
  [ -d "$CFG/skills/kpmg-deck/references" ]
  [ ! -L "$CFG/skills/kpmg-deck/references" ]
}

@test "every nested tracked file of the fixture skill is linked — no partial conversion" {
  run_install
  [ "$status" -eq 0 ]
  missing=0
  while IFS= read -r f; do
    rel="${f#"$REPO"/skills/kpmg-deck/}"
    [ -L "$CFG/skills/kpmg-deck/$rel" ] || { echo "not linked: $rel"; missing=$((missing + 1)); }
  done < <(find "$REPO/skills/kpmg-deck" -type f)
  [ "$missing" -eq 0 ]
}

@test "an unversioned real file that DIFFERS is backed up before being replaced by the link" {
  mkdir -p "$CFG/skills/kpmg-deck/references"
  dest="$CFG/skills/kpmg-deck/$NESTED_REL"
  printf 'hand-written content that exists nowhere in git\n' > "$dest"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$dest" ]
  [ -f "$dest.pre-link.bak" ]
  run cat "$dest.pre-link.bak"
  [ "$output" = "hand-written content that exists nowhere in git" ]
}

@test "CONTROL: an identical real file is NOT backed up — the guard is inert where content agrees" {
  mkdir -p "$CFG/skills/kpmg-deck/references"
  dest="$CFG/skills/kpmg-deck/$NESTED_REL"
  cp "$NESTED_SRC" "$dest"
  run_install
  [ "$status" -eq 0 ]
  [ -L "$dest" ]
  [ ! -e "$dest.pre-link.bak" ]
}

@test "idempotent: a second run creates no backups and leaves the links identical" {
  run_install
  [ "$status" -eq 0 ]
  before="$(find "$CFG/skills" -type l -exec readlink {} \; | sort)"
  run_install
  [ "$status" -eq 0 ]
  after="$(find "$CFG/skills" -type l -exec readlink {} \; | sort)"
  [ "$before" = "$after" ]
  run bash -c "find '$CFG/skills' -name '*.pre-link.bak' | wc -l"
  [ "$output" -eq 0 ]
}
