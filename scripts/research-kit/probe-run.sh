#!/bin/bash
# probe-run.sh — see lib/probe_run.py. Bash 3.2-safe wrapper.
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/env python3 "$here/lib/probe_run.py" "$@"
