#!/bin/bash
# courier.sh — see lib/courier.py. Bash 3.2-safe wrapper.
set -u
here="$(cd "$(dirname "$0")" && pwd -P)"
exec /usr/bin/env python3 "$here/lib/courier.py" "$@"
