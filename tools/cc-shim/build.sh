#!/usr/bin/env bash
# Build, prove and publish cc-shim (tools/cc-shim/cc-shim.c; why: docs/research/kalloc-longterm-2026-10-21/shim.md).
#   build.sh  →  stdout: the published LINK path; exit 4 + `cc-shim: unavailable (<reason>)` on stderr.
# The binary is keyed by sha256(source)+arch, so a rerun with an unchanged source is a no-op and an
# edited source never reuses a stale build (the cache shape of bin/cc-kqwait). It is published 0555:
# test stubs are symlinks to it, so a test that writes or chmods a stub must hit EACCES rather than
# corrupt the one shared binary.
#   CC_SHIM_CACHE  cache root     (default ~/.cache/cc-shim)
#   CC_SHIM_LINK   published link (default ~/.claude/libexec/cc-shim)
#   CC             compiler       (default clang)
set -euo pipefail

_tmpd=""
_smoke_dir=""
cleanup() {
  if [ -n "$_tmpd" ]; then
    rm -f "$_tmpd/cc-shim" "$_tmpd/build.log"
    rmdir "$_tmpd" 2>/dev/null || true
  fi
  smoke_cleanup
}
smoke_cleanup() {
  if [ -n "$_smoke_dir" ]; then
    rm -f "$_smoke_dir/stub/probe" "$_smoke_dir/.stub-real/probe"
    rmdir "$_smoke_dir/stub" "$_smoke_dir/.stub-real" "$_smoke_dir" 2>/dev/null || true
    _smoke_dir=""
  fi
}
trap cleanup EXIT
unavailable() { printf 'cc-shim: unavailable (%s)\n' "$1" >&2; exit 4; }

[ "$#" -eq 0 ] || { printf 'usage: %s\n' "${0##*/}" >&2; exit 64; }

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P) || unavailable no-source-dir
SRC="$here/cc-shim.c"
[ -r "$SRC" ] || unavailable "no source $SRC"

# Asserted, not trusted: an empty or short key would be one cache dir SHARED across source versions.
sha=""
CC_SHA256=/sbin/sha256sum; [ -x "$CC_SHA256" ] || CC_SHA256=sha256sum   # Mach-O here; coreutils on Linux
sha=$("$CC_SHA256" <"$SRC" 2>/dev/null) || sha=""
sha=${sha%% *}
case "$sha" in *[!0-9a-f]* | '') unavailable degenerate-hash ;; esac
[ "${#sha}" -eq 64 ] || unavailable degenerate-hash
arch=$(uname -m) || arch=""
[ -n "$arch" ] || unavailable no-arch

cache="${CC_SHIM_CACHE:-$HOME/.cache/cc-shim}"
dir="$cache/${sha:0:16}-$arch"
LINK="${CC_SHIM_LINK:-$HOME/.claude/libexec/cc-shim}"
mkdir -p "$dir" 2>/dev/null || unavailable "cannot create $dir"
# Absolute, because the smoke runs the binary through a symlink from another directory.
dir=$(cd "$dir" && pwd -P) || unavailable "cannot resolve $dir"
bin="$dir/cc-shim"

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1" 2>/dev/null; }

# End to end through the stub path: stub/probe → candidate, target .stub-real/probe a real #! file.
smoke() {
  local rc=0
  smoke_run "$1" || rc=1
  smoke_cleanup
  return "$rc"
}
smoke_run() {
  local t="${TMPDIR:-/tmp}" out
  _smoke_dir=$(mktemp -d "${t%/}/cc-shim-smoke.XXXXXX") || return 1
  mkdir "$_smoke_dir/stub" "$_smoke_dir/.stub-real" || return 1
  ln -s "$1" "$_smoke_dir/stub/probe" || return 1
  # shellcheck disable=SC2016 # the "$@" is the probe script's own, written literally
  printf '#!/bin/sh\necho ok "$@"\n' >"$_smoke_dir/.stub-real/probe" || return 1
  chmod +x "$_smoke_dir/.stub-real/probe" || return 1
  out=$("$_smoke_dir/stub/probe" a b 2>&1) || return 1
  [ "$out" = "ok a b" ]
}

if ! { [ -f "$bin" ] && [ "$(mode_of "$bin")" = 555 ] && smoke "$bin"; }; then
  cc="${CC:-clang}"
  command -v "$cc" >/dev/null 2>&1 || unavailable "no compiler $cc"
  # Built under its final NAME in a private dir: cc-shim picks its mode from its own basename, so a
  # cc-shim.<pid> temp file would take the stub path instead of running --selftest.
  _tmpd="$dir/.build.$$"
  mkdir "$_tmpd" || unavailable "cannot create $_tmpd"
  if ! "$cc" -Os -Wall -Werror "-DCC_SHIM_HASH=\"$sha\"" -o "$_tmpd/cc-shim" "$SRC" 2>"$_tmpd/build.log"; then
    tail -n 20 "$_tmpd/build.log" >&2 || true
    unavailable build-failed
  fi
  "$_tmpd/cc-shim" --selftest >&2 || unavailable selftest-failed
  smoke "$_tmpd/cc-shim" || unavailable smoke-failed
  chmod 0555 "$_tmpd/cc-shim" || unavailable chmod-failed
  mv -f "$_tmpd/cc-shim" "$bin" || unavailable "cannot place $bin"
fi

# Atomic swap: a new link renamed over the old, so an exec in flight resolves one or the other.
if [ -d "$LINK" ] && [ ! -L "$LINK" ]; then unavailable "$LINK is a directory"; fi
mkdir -p "$(dirname "$LINK")" 2>/dev/null || unavailable "cannot create $(dirname "$LINK")"
if [ "$(readlink "$LINK" 2>/dev/null || true)" != "$bin" ]; then
  if ! { ln -s "$bin" "$LINK.$$" && mv -f "$LINK.$$" "$LINK"; }; then
    rm -f "$LINK.$$"
    unavailable "cannot publish $LINK"
  fi
fi
smoke "$LINK" || unavailable "published $LINK fails smoke"
printf '%s\n' "$LINK"
