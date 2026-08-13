#!/bin/bash
# Stop-hook oracle — records CC's OWN background_tasks population at every Stop, verbatim.
# This is the task-registry read that decides the whole A/B; exit 0 so it never alters behaviour.
set -uo pipefail
payload="$(cat 2>/dev/null || true)"
printf '%s\t%s\n' "$(date -Is)" "$payload" >> "${PROBE_SLOG:?}"
exit 0
