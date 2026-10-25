#!/bin/bash
# lever-arm-start.sh — SessionStart child of hooks/session-start-dispatch.sh: stamps this session's
# usage-lever lineage and arms (docs/plans/USAGE_LEVERS.md § W7+ §3 row "Session stamp").
#
# One kind=session row per start, /clear and compact goes to ~/.claude/logs/lever-arms.jsonl: sid,
# lineage root and how it was resolved, account, pane, flag source, and the D1/D2 arm + u of the
# lineage (D3 and D4 are armed per event by their own hooks). The resolver also caches the lineage
# in ~/.claude/state/levers/arms/<sid>, which later bash hooks read with builtins
# (hooks/lib/lever-flags.sh lf_lineage). All of it lives in hooks/lib/lever_flags.py `stamp`.
#
# It changes nothing for any session: it prints nothing (the dispatcher merges no output from it),
# and computes arms at whatever pct the flag file says — S0 is pct 0, every arm ctrl. It never holds
# the start: the python runs in the background and this child exits at once. One python start
# measured ~15 s at load 400 (2026-10-24), past the dispatcher's 9 s deadline, where it would have
# been named "late" on every start's banner; the dispatcher only collects children still running, so
# a finished child's background helper is left to finish its one row.
# Kill switch: CC_LEVER_ARM_START=off. Registered through the dispatcher's CHILDREN list, so it
# needed no settings.json edit.
[ "${CC_LEVER_ARM_START:-on}" = off ] && exit 0
HERE="${BASH_SOURCE[0]%/*}"; [ "$HERE" = "${BASH_SOURCE[0]}" ] && HERE=.
[ -f "$HERE/lib/lever_flags.py" ] || exit 0
payload="$(cat)"
( printf '%s' "$payload" | /usr/bin/python3 -I "$HERE/lib/lever_flags.py" stamp ) </dev/null >/dev/null 2>&1 &
exit 0
