#!/usr/bin/env bash
# kitty-upstream-defects.sh — is either of the two recorded upstream kitty defects still in a source tree?
#
# THE TWO DEFECTS (record + drafted upstream issues: docs/research/kitty-upstream-defects-2026-09-30.md)
#   fonts_data  backlog 7e067b9377ff. kitty/fonts.c restore_window_font_groups() sets
#               os_window->fonts_data = NULL on a font-group lookup miss, and kitty/state.c
#               dereferences it with no NULL check in viewport_for_window / cell_size_for_window
#               (both exported to Python, so a kitten, a watcher or `kitty @` can reach them) and in
#               dpi_for_os_window.
#   tick_lock   backlog a205ef0a3659. glfw/cocoa_init.m _glfwPlatformPostEmptyEvent() runs on the
#               child-monitor thread and does `else if (tick_lock) { [tick_lock lock] … }`, while
#               _glfwPlatformRunMainLoop() releases the global NSLock and sets tick_lock = NULL at
#               shutdown: an unsynchronised check-then-use of a global ObjC pointer.
#
# WHY THIS REPLACES THE OLD FALSIFIERS. The rows carried `CFBundleShortVersionString != 0.48.2` and a
# pinned `sed -n 1047p` of a local stock tree. The first flips on ANY upgrade, including 0.49.0-0.49.2,
# which all still carry both defects, so it would have closed the rows over a live defect. The second
# reads a frozen checkout and can never flip at all. This reads the SOURCE of a release and tests the
# STRUCTURE of each defect (function bodies, not line numbers), so it flips only when the code changes.
#
# Usage:  kitty-upstream-defects.sh [--src DIR] [--ref TAG] [--defect fonts_data|tick_lock|all]
#   --src DIR  read DIR/kitty/state.c, DIR/kitty/fonts.c, DIR/glfw/cocoa_init.m (no network)
#   --ref TAG  fetch that tag's files from GitHub (default: the latest release)
# Output: one `defect=<name> state=present|fixed|unknown site=<functions>` line per defect, then
#         `verdict=PRESENT|FIXED|UNKNOWN ref=<tag|src>`.
# Exit:   1 PRESENT (a requested defect is still in the source: the row is still live)
#         0 FIXED   (every requested defect is gone: the row's premise is gone)
#         2 UNKNOWN (could not fetch, a file or function is missing: abstain, never "fixed")
set -uo pipefail

SRC="" REF="" DEFECT=all
while [ $# -gt 0 ]; do
  case "$1" in
    --src)    SRC="${2:-}"; shift 2 ;;
    --ref)    REF="${2:-}"; shift 2 ;;
    --defect) DEFECT="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,29p' "$0"; exit 0 ;;
    *) echo "usage: ${0##*/} [--src DIR] [--ref TAG] [--defect fonts_data|tick_lock|all]" >&2; exit 2 ;;
  esac
done
case "$DEFECT" in fonts_data|tick_lock|all) ;; *) echo "unknown --defect: $DEFECT" >&2; exit 2 ;; esac

TMP=""
cleanup() { [ -n "$TMP" ] && rm -f "$TMP/kitty/state.c" "$TMP/kitty/fonts.c" "$TMP/glfw/cocoa_init.m" && rmdir "$TMP/kitty" "$TMP/glfw" "$TMP" 2>/dev/null; return 0; }
trap cleanup EXIT

if [ -z "$SRC" ]; then
  if [ -z "$REF" ]; then
    REF="$(curl -fsSL --max-time 20 https://api.github.com/repos/kovidgoyal/kitty/releases/latest 2>/dev/null \
           | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))' 2>/dev/null)"
    [ -n "$REF" ] || { echo "verdict=UNKNOWN ref=? reason=latest-release-unreadable"; exit 2; }
  fi
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/kitty-defects.XXXXXX")" || exit 2
  mkdir -p "$TMP/kitty" "$TMP/glfw"
  for f in kitty/state.c kitty/fonts.c glfw/cocoa_init.m; do
    curl -fsSL --max-time 30 "https://raw.githubusercontent.com/kovidgoyal/kitty/$REF/$f" -o "$TMP/$f" 2>/dev/null \
      || { echo "verdict=UNKNOWN ref=$REF reason=fetch-failed:$f"; exit 2; }
  done
  SRC="$TMP"; LABEL="$REF"
else
  LABEL="src:$SRC"
fi

python3 - "$SRC" "$DEFECT" "$LABEL" <<'PY'
import re
import sys
from pathlib import Path

src, want, label = Path(sys.argv[1]), sys.argv[2], sys.argv[3]


def body(text: str, name: str) -> str | None:
    """Return the brace-matched body of C function `name` (plain or PYWRAPn(name)), or None."""
    m = re.search(r'(?:PYWRAP\d\(\s*%s\s*\)|\b%s\s*\([^;{)]*\))\s*\{' % (name, name), text)
    if not m:
        return None
    i, depth = m.end() - 1, 0
    for j in range(i, len(text)):
        if text[j] == '{':
            depth += 1
        elif text[j] == '}':
            depth -= 1
            if depth == 0:
                return text[i + 1:j]
    return None


def read(rel: str) -> str | None:
    p = src / rel
    return p.read_text(errors='replace') if p.is_file() else None


def fonts_data() -> tuple[str, str]:
    state, fonts = read('kitty/state.c'), read('kitty/fonts.c')
    if state is None or fonts is None:
        return 'unknown', 'file-missing'
    restore = body(fonts, 'restore_window_font_groups')
    if restore is None:
        return 'unknown', 'restore_window_font_groups-missing'
    nullable = re.search(r'fonts_data\s*=\s*NULL', restore) is not None
    unguarded = []
    for fn in ('viewport_for_window', 'cell_size_for_window', 'dpi_for_os_window'):
        b = body(state, fn)
        if b is None:
            return 'unknown', f'{fn}-missing'
        first = b.find('fonts_data->')
        # A guard is any mention of fonts_data that is not itself a dereference, before the first one.
        if first >= 0 and not re.search(r'fonts_data(?!\s*->)', b[:first]):
            unguarded.append(fn)
    if nullable and unguarded:
        return 'present', ','.join(unguarded)
    if not nullable:
        return 'fixed', 'restore-never-nulls'
    return 'fixed', 'all-guarded'


def tick_lock() -> tuple[str, str]:
    cocoa = read('glfw/cocoa_init.m')
    if cocoa is None:
        return 'unknown', 'file-missing'
    post, run = body(cocoa, '_glfwPlatformPostEmptyEvent'), body(cocoa, '_glfwPlatformRunMainLoop')
    if post is None or run is None:
        return 'unknown', 'function-missing'
    racy_use = re.search(r'if\s*\(\s*tick_lock\s*\)\s*\{?\s*\[\s*tick_lock\s+lock\s*\]', post) is not None
    nulled = re.search(r'tick_lock\s*=\s*(NULL|nil)\b', run) is not None
    if racy_use and nulled:
        return 'present', '_glfwPlatformPostEmptyEvent'
    return 'fixed', '_glfwPlatformPostEmptyEvent'


checks = {'fonts_data': fonts_data, 'tick_lock': tick_lock}
states = []
for name in (checks if want == 'all' else [want]):
    state, site = checks[name]()
    states.append(state)
    print(f'defect={name} state={state} site={site}')
if 'unknown' in states:
    print(f'verdict=UNKNOWN ref={label}')
    sys.exit(2)
if 'present' in states:
    print(f'verdict=PRESENT ref={label}')
    sys.exit(1)
print(f'verdict=FIXED ref={label}')
sys.exit(0)
PY
