#!/bin/bash
# round.sh — see lib/round.py. Bash 3.2-safe wrapper.
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/env python3 "$here/lib/round.py" "$@"
