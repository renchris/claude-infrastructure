#!/usr/bin/env bats
# hooks/lib/shasum-direct.sh resolves "$CC_SHA256" / "$CC_SHA1" to the Mach-O /sbin/sha256sum and
# /sbin/sha1sum (coreutils on Linux), and scripts/shasum-lint.sh refuses new `shasum` calls at the
# land gate (docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W1). /usr/bin/shasum is a #! perl
# script whose every exec keeps ~1.1 KiB of kernel memory on macOS 15.8.1.
#
# The byte-identity cases are what make the swap safe: the hashes are persisted as file names and
# record fields (waiting-recycle sentinels, dod store, backlog ids), so a single differing byte would
# orphan live state. RED-proof for the lint: its --selftest runs a call fixture that must read RED.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  F="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$F"
  : > "$F/empty"
  printf 'abc\n' > "$F/small"
  head -c 1048576 /dev/zero | tr '\0' 'x' > "$F/mib"
}

# Runs "$CC_<alg>" on the input, after sourcing the lib exactly as the Stop-path libs do.
_direct() { # $1=SHA256|SHA1 $2=stdin|<file>
  /bin/bash -c '. "$1/hooks/lib/shasum-direct.sh"; v="CC_$2"; if [ "$3" = stdin ]; then "${!v}"; else "${!v}" "$3"; fi' \
    _ "$REPO" "$1" "$2"
}
_perl() { # $1=256|1 $2=stdin|<file> → the old /usr/bin/shasum output
  if [ "$2" = stdin ]; then /usr/bin/shasum -a "$1"; else /usr/bin/shasum -a "$1" "$2"; fi
}

@test "shasum-direct: CC_SHA256/CC_SHA1 resolve to the Mach-O tools, and no shasum function is left" {
  run /bin/bash -c '. "$1/hooks/lib/shasum-direct.sh"; printf "%s\n%s\n" "$CC_SHA256" "$CC_SHA1"; type -t shasum || echo none' _ "$REPO"
  [ "$status" -eq 0 ]
  if [ -x /sbin/sha256sum ]; then
    [ "${lines[0]}" = /sbin/sha256sum ]
    [ "${lines[1]}" = /sbin/sha1sum ]
    [ "$(head -c 2 /sbin/sha256sum)" != '#!' ]
  else
    [ "${lines[0]}" = sha256sum ]
    [ "${lines[1]}" = sha1sum ]
  fi
  [ "${lines[2]}" != function ]
}

@test "shasum-direct: re-sourcing is a no-op and safe under set -u" {
  run /bin/bash -c 'set -u; . "$1/hooks/lib/shasum-direct.sh"; CC_SHA1=sentinel; . "$1/hooks/lib/shasum-direct.sh"; printf "%s\n" "$CC_SHA1"' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = sentinel ]
}

@test "shasum-direct: byte-identical to shasum on stdin (empty, small, 1 MiB)" {
  [ -x /usr/bin/shasum ] || skip "no /usr/bin/shasum to compare against"
  local f
  for f in empty small mib; do
    [ "$(_direct SHA256 stdin < "$F/$f")" = "$(_perl 256 stdin < "$F/$f")" ]
    [ "$(_direct SHA1 stdin < "$F/$f")" = "$(_perl 1 stdin < "$F/$f")" ]
  done
}

@test "shasum-direct: byte-identical to shasum on a file argument (empty, small, 1 MiB)" {
  [ -x /usr/bin/shasum ] || skip "no /usr/bin/shasum to compare against"
  local f
  for f in empty small mib; do
    [ "$(_direct SHA256 "$F/$f")" = "$(_perl 256 "$F/$f")" ]
    [ "$(_direct SHA1 "$F/$f")" = "$(_perl 1 "$F/$f")" ]
  done
}

@test "shasum-direct: the Stop-path libs pull the resolver in" {
  run /bin/bash -c 'set -u; . "$1/hooks/lib/continue-sentinel.sh"; continue_sentinel_for /x' _ "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" =~ /continue-[0-9a-f]{16}$ ]] || false
}

@test "shasum-lint: --selftest discriminates" {
  run "$REPO/scripts/shasum-lint.sh" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"selftest: ok"* ]] || false
}

@test "shasum-lint: a call goes RED with file:line, a comment-only file stays clean" {
  local w=sha; w="${w}sum"
  # shellcheck disable=SC2016  # the fixture's own $( ), written literally
  printf '#!/bin/bash\nk="$(printf x | %s -a 256)"\n' "$w" > "$F/call.sh"
  printf '#!/bin/bash\n# printf x | %s\n' "$w" > "$F/comment.sh"
  run "$REPO/scripts/shasum-lint.sh" --file "$F/call.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"$F/call.sh:2:"* ]] || false
  run "$REPO/scripts/shasum-lint.sh" --file "$F/comment.sh"
  [ "$status" -eq 0 ]
  run "$REPO/scripts/shasum-lint.sh" --file "$F/nope.sh"
  [ "$status" -eq 2 ]
}

@test "shasum-lint: the real tree reads clean" {
  run "$REPO/scripts/shasum-lint.sh"
  [ "$status" -eq 0 ]
}
