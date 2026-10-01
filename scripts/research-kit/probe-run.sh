#!/bin/bash
# probe-run.sh — compatibility shim over bin/cc-research (REPORT.md §8 item 10): `run` is
# `cc-research probe`, `doctor` is `cc-research doctor`. Bash 3.2-safe.
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
cr="$(cd "$here/../.." && pwd -P)/bin/cc-research"
verb="${1:-}"
case "$verb" in
  run) shift; exec /usr/bin/env python3 "$cr" probe "$@" ;;
  doctor) shift; exec /usr/bin/env python3 "$cr" doctor "$@" ;;
  *) echo "usage: probe-run.sh run|doctor --program P …" >&2; exit 2 ;;
esac
