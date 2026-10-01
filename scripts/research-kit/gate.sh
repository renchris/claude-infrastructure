#!/bin/bash
# gate.sh — the hand-run kit's §3.10 gate and the only writer of the program registry.
# Verbs and exit codes: see lib/gate.py. Bash 3.2-safe (launchd runs the sweep in wave 2).
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
# `gate.sh --render --program P` is the literal certificate read the research block whitelists
# (REPORT.md §4.2); it is the `render` verb.
if [ "${1:-}" = "--render" ]; then
  shift
  set -- render "$@"
fi
exec /usr/bin/env python3 "$here/lib/gate.py" "$@"
