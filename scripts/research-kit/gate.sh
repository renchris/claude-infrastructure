#!/bin/bash
# gate.sh — the hand-run kit's §3.10 gate and the only writer of the program registry.
# Verbs and exit codes: see lib/gate.py. Bash 3.2-safe (launchd runs the sweep in wave 2).
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/env python3 "$here/lib/gate.py" "$@"
