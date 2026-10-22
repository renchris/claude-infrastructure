#!/usr/bin/env bats
# The kitty resolvers run kitty's app binary, not Homebrew's #! cask wrapper (REPORT §3 Phase 1,
# docs/research/kalloc-longterm-2026-10-21/REPORT.md): on macOS 15.8.1 every by-path #! exec keeps
# ~1.1 KiB of kernel memory, and /opt/homebrew/bin/kitty is `#!/bin/bash` + `exec "<app>" "$@"`.
# Three resolvers carry the same `_kitty_unwrap`: bin/cc-kitty-bin, bin/it2-kitty, bin/cc-resume-layout.sh.
#
# RED-proof: before the change cc-kitty-bin printed the wrapper's own path (the PATH hit).
#
# Hermetic: the wrapper, its cask dir and the "app binary" are fixtures; PATH holds only the fixture
# bin dir plus the stock floor, so the operator's real kitty is never resolved.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset CC_TERM_KITTY
  D="$BATS_TEST_TMPDIR"
  W="$D/Caskroom/kitty/9.9/.homebrew-command-wrappers"
  mkdir -p "$W" "$D/app" "$D/bin" "$D/stub"
  printf '#!/bin/bash\necho app\n' > "$D/app/kitty"
  # Byte-for-byte Homebrew's shape, two spaces before "$@" included.
  printf '#!/bin/bash\nexec "%s"  "$@"\n' "$D/app/kitty" > "$W/kitty"
  chmod +x "$D/app/kitty" "$W/kitty"
  ln -s "$W/kitty" "$D/bin/kitty"
  printf '#!/bin/bash\necho stub\n' > "$D/stub/kitty"; chmod +x "$D/stub/kitty"
}

unwrap_from() { # <file> — define that file's own _kitty_unwrap in this shell
  eval "$(sed -n '/^ *_kitty_unwrap() {/,/^ *}$/p' "$1")"
}

@test "cc-kitty-bin resolves a Homebrew wrapper on PATH to the app binary it execs" {
  run env PATH="$D/bin:/usr/bin:/bin" /bin/bash "$REPO/bin/cc-kitty-bin"
  [ "$status" -eq 0 ]
  [ "$output" = "$D/app/kitty" ]
}

@test "cc-kitty-bin leaves a non-wrapper on PATH (a test stub, a dev build) unchanged" {
  run env PATH="$D/stub:/usr/bin:/bin" /bin/bash "$REPO/bin/cc-kitty-bin"
  [ "$status" -eq 0 ]
  [ "$output" = "$D/stub/kitty" ]
}

@test "every resolver's _kitty_unwrap unwraps the wrapper and passes the rest through" {
  for f in bin/cc-kitty-bin bin/it2-kitty bin/cc-resume-layout.sh; do
    unset -f _kitty_unwrap
    unwrap_from "$REPO/$f"
    [ "$(_kitty_unwrap "$D/bin/kitty")" = "$D/app/kitty" ] || { echo "$f: wrapper"; false; }
    [ "$(_kitty_unwrap "$W/kitty")" = "$D/app/kitty" ] || { echo "$f: wrapper by real path"; false; }
    [ "$(_kitty_unwrap "$D/stub/kitty")" = "$D/stub/kitty" ] || { echo "$f: stub"; false; }
  done
}

@test "a wrapper whose target is gone falls back to the wrapper itself, never to nothing" {
  /bin/rm -f "$D/app/kitty"
  unwrap_from "$REPO/bin/cc-kitty-bin"
  [ "$(_kitty_unwrap "$D/bin/kitty")" = "$D/bin/kitty" ]
}

@test "the three copies are the same function" {
  a="$(sed -n '/^ *_kitty_unwrap() {/,/^ *}$/p' "$REPO/bin/cc-kitty-bin" | sed 's/^ *//')"
  for f in bin/it2-kitty bin/cc-resume-layout.sh; do
    b="$(sed -n '/^ *_kitty_unwrap() {/,/^ *}$/p' "$REPO/$f" | sed 's/^ *//')"
    [ -n "$b" ] && [ "$a" = "$b" ] || { echo "$f differs"; false; }
  done
}
