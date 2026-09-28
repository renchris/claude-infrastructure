#!/bin/bash
# lib.sh — shared helpers for the autonomy-core hooks. Sourced, never run.
#
# Portability contract: bash 3.2 (macOS /bin/bash), GNU or BSD userland. JSON goes through jq when it
# is installed, else python3 (Ubuntu and WSL ship python3 but not jq; macOS 15+ ships jq).

AC_HOME="${AC_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC2034  # read by the hooks that source this file
AC_STATE="$AC_HOME/state"

# ac_json_get <json> <dotted.path> → prints the value ("" when absent or null). Never fails.
ac_json_get() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -r ".${2} // empty | if type==\"string\" then . else tojson end" 2>/dev/null || true
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
    for k in sys.argv[1].split("."):
        v = v.get(k) if isinstance(v, dict) else None
    if v is not None:
        print(v if isinstance(v, str) else json.dumps(v))
except Exception:
    pass' "$2" 2>/dev/null || true
  fi
}

# ac_json_str <text> → the text as a JSON string literal, quotes included.
ac_json_str() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs . 2>/dev/null
  else
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null
  fi
}

# ac_block <reason> → the Stop-hook JSON that keeps the session working, with <reason> as its next prompt.
ac_block() {
  printf '{"decision":"block","reason":%s}\n' "$(ac_json_str "$1")"
}

# ac_key <text> → a short filesystem-safe key (cksum is POSIX; no md5/sha tool differences).
ac_key() {
  printf '%s' "$1" | cksum | awk '{print $1}'
}
