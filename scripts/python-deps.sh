#!/bin/bash
# python-deps.sh — make the third-party Python packages that bin/ imports actually IMPORTABLE.
#
# Usage:
#   scripts/python-deps.sh            # probe, install what is missing
#   scripts/python-deps.sh --dry-run  # probe + report, install nothing
#   scripts/python-deps.sh --probe    # probe only; never installs, exit 1 if anything is missing
#
# Why this is a script and not six lines inside install.sh: the installer's dep step only runs
# on a GLOBAL install ($CONFIG_DIR == ~/.claude), and a global install also copies LaunchAgents
# and calls launchctl. A test that exercised the step through install.sh would therefore have to
# either mutate the operator's live config or fake $HOME hard enough to still touch launchd — so
# the step lives here, where tests/python-deps.bats can drive it hermetically with a stub PATH.
#
# Contract: the VERDICT is the structured token on stdout, not the exit code. One exit code
# cannot distinguish "already fine" from "installed it just now", and a caller forced to infer
# that will infer it wrong. Exit code is a coarse ok/not-ok for shell callers; parse the token.
#
#   verdict=satisfied  every dep already imports          (exit 0)
#   verdict=installed  something was missing, pip fixed it (exit 0)
#   verdict=dry-run    would have installed <names>        (exit 0)
#   verdict=missing    --probe found gaps, did not install (exit 1)
#   verdict=failed     pip ran and the module STILL does not import (exit 1)
#
# `verdict=failed` is deliberately an EFFECT read (re-probe the import), not pip's own exit
# status: pip reports on a distribution being recorded, which is not the property any caller
# cares about. A dep that pip "installed" into a python3 other than the one on PATH is failed.

set -uo pipefail

# Resolve every symlink hop BEFORE deriving the repo root. This script is reached through
# ~/.claude, which is a symlink layer over the checkout, so an unresolved $BASH_SOURCE puts
# REPO_DIR at $HOME instead of the repo and requirements.txt silently "does not exist" —
# verdict=failed reason=no-requirements-file, blamed on the operator's tree. Same shape the
# script-dir ratchet (scripts/self-path-lint.sh) exists to catch; `readlink -f` is GNU-only
# and this box is BSD, hence the loop.
_resolve_self() {  # <path> → absolute path, every symlink hop resolved (bash 3.2 / POSIX-safe)
  local p="$1" d
  while [[ -L "$p" ]]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
REPO_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
REQ_FILE="${PYTHON_DEPS_REQUIREMENTS:-$REPO_DIR/requirements.txt}"
PYTHON_BIN="${PYTHON_DEPS_PYTHON:-python3}"
PIP_BIN="${PYTHON_DEPS_PIP:-pip3}"

MODE=install
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE=dry-run; shift ;;
    --probe)   MODE=probe;   shift ;;
    -h|--help) sed -n '2,26p' "$SELF"; exit 0 ;;   # resolved: --help must work through the symlink too
    *) echo "python-deps.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done

say() { echo "$@"; }

if [[ ! -f "$REQ_FILE" ]]; then
  say "verdict=failed reason=no-requirements-file path=$REQ_FILE"
  exit 1
fi

# Probe names come from the `# import: <name>` marker, which pip cannot derive from a
# distribution name. A requirement line WITHOUT the marker is a hole — it would be installed
# but never verified — so it is reported rather than silently skipped.
missing=()      # import names that do not import
unmarked=()     # requirement lines missing their `# import:` marker
while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
  req="${line%%#*}"; req="$(echo "$req" | tr -d '[:space:]')"
  [[ -z "$req" ]] && continue
  if [[ "$line" =~ \#[[:space:]]*import:[[:space:]]*([A-Za-z0-9_.]+) ]]; then
    mod="${BASH_REMATCH[1]}"
  else
    unmarked+=("$req")
    continue
  fi
  "$PYTHON_BIN" -c "import $mod" >/dev/null 2>&1 || missing+=("$mod")
done < "$REQ_FILE"

if [[ ${#unmarked[@]} -gt 0 ]]; then
  say "verdict=failed reason=unmarked-requirement reqs=${unmarked[*]}"
  say "  add a trailing '# import: <module>' to each — see requirements.txt"
  exit 1
fi

if [[ ${#missing[@]} -eq 0 ]]; then
  say "verdict=satisfied python=$("$PYTHON_BIN" -c 'import sys;print(sys.executable)' 2>/dev/null || echo "$PYTHON_BIN")"
  exit 0
fi

if [[ "$MODE" == probe ]]; then
  say "verdict=missing modules=${missing[*]}"
  exit 1
fi

if [[ "$MODE" == dry-run ]]; then
  say "verdict=dry-run modules=${missing[*]}"
  say "  would run: $PIP_BIN install --break-system-packages -r $REQ_FILE"
  exit 0
fi

# --break-system-packages: macOS/Homebrew python3 is PEP-668 externally-managed and these are
# HOST tools, not a project venv — there is no interpreter here to put a venv in front of.
"$PIP_BIN" install --break-system-packages -r "$REQ_FILE" >/dev/null 2>&1 || true

still=()
for mod in "${missing[@]}"; do
  "$PYTHON_BIN" -c "import $mod" >/dev/null 2>&1 || still+=("$mod")
done

if [[ ${#still[@]} -gt 0 ]]; then
  say "verdict=failed modules=${still[*]}"
  say "  recovery: $PIP_BIN install --break-system-packages -r $REQ_FILE"
  exit 1
fi

say "verdict=installed modules=${missing[*]}"
exit 0
