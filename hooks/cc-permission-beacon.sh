#!/bin/bash
# cc-permission-beacon.sh — the PermissionRequest BEACON for lead-supervisor.sh (desk-anti-hitl §B2).
#
# WHY: an UNATTENDED autonomous session that hits a permission prompt HANGS until a human answers
# (the 133-min `git reset --hard` incident, desk-anti-hitl-2026-07-19.md §B). Nothing IN-session can
# answer the prompt, and the out-of-session supervisor is STRUCTURALLY blind to modal/permission
# dialogs (lead-supervisor.sh S-3 — a bash sweep cannot read a modal). Today that block only surfaces
# ~30 min later as a generic STALL?/MODAL page with no detail; resolution took 2h13m.
#
# THIS beacon makes the block VISIBLE, ATTRIBUTED, and FAST: on a permission prompt the HARNESS (not a
# worker) writes an unspoofable record {ts, tool_name, tool_input, cwd} to CC_PERMPEND_DIR/<sid>.json.
# lead-supervisor.sh's sweep reads the dir and pages "PERMISSION-PENDING: <cmd> since <ts>" within
# minutes, with the exact blocked command attached — a precise escalation instead of a silent hang.
#
# CONTRACT (mode = $1, from the hook wiring):
#   write  — PermissionRequest event: the harness is showing a permission prompt ⇒ persist the beacon.
#   clear  — PostToolUse | Stop | SessionEnd: the prompt is RESOLVED ⇒ remove the beacon.
#
# WHY THE CLEARS ARE COMPLETE (no missed-clear leak, and no dependence on a PermissionDenied event —
# this harness has none):
#   • A permission prompt is ALWAYS mid-turn — the turn cannot Stop until the human answers. So the
#     turn's Stop fires after EVERY resolution, GRANT or DENY, guaranteeing a clear even on the deny
#     path (which never runs PostToolUse). Stop is the universal clearer.
#   • PostToolUse is the FASTER clear on the grant path (fires the instant the tool runs, before the
#     turn ends), narrowing the stale window.
#   • SessionEnd is the backstop for a session that closes without a Stop.
#   • A hard-killed session (kill -9 / OOM, no SessionEnd) cannot strand a forever-pending beacon:
#     the supervisor independently REAPS a beacon whose owning session is provably dead (pid gone via
#     telemetry) and any beacon past a long orphan horizon.
#
# SAFETY: the payload is HARNESS-AUTHORED (session_id/tool_name/tool_input/cwd arrive on the hook's
# stdin from the harness, NOT worker-influenced content) ⇒ unspoofable. This hook is a pure OBSERVER:
# it emits NO permission decision, so the prompt proceeds exactly as before. Fail-open + fail-quiet:
# any parse/IO error exits 0 with no decision and no partial file.
#
# Kill switch: CC_PERMISSION_BEACON_DISABLED=1  (no-op, both modes).
# Seam: CC_PERMPEND_DIR (default /tmp/cc-permission-pending) — MUST match lead-supervisor.sh; E2E isolation.

[[ "${CC_PERMISSION_BEACON_DISABLED:-0}" == "1" ]] && exit 0
set -uo pipefail

MODE="${1:-}"
DIR="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"

# Read the harness payload once (fail-open on empty/malformed — never block the prompt).
INPUT="$(cat 2>/dev/null || true)"
SID="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
[[ -z "$SID" ]] && exit 0                       # no session id ⇒ nothing to key a beacon on
# Defense-in-depth: a session id is a uuid; reject anything that isn't a safe basename so the
# path can never escape DIR (harness sids are already clean — this is belt-and-suspenders).
case "$SID" in *[!A-Za-z0-9._-]*|''|.|..) exit 0 ;; esac

BEACON="$DIR/$SID.json"

case "$MODE" in
  clear)
    rm -f "$BEACON" 2>/dev/null || true
    exit 0
    ;;
  write)
    mkdir -p "$DIR" 2>/dev/null || exit 0
    TS="$(date +%s)"
    # Atomic write (temp in the SAME dir + mv) so the supervisor never reads a half-written beacon.
    TMP="$(mktemp "$DIR/.$SID.XXXXXX" 2>/dev/null)" || exit 0
    if printf '%s' "$INPUT" | jq -c \
         --argjson ts "$TS" \
         '{ts:$ts, tool_name:(.tool_name // ""), tool_input:(.tool_input // {}), cwd:(.cwd // "")}' \
         > "$TMP" 2>/dev/null; then
      mv -f "$TMP" "$BEACON" 2>/dev/null || rm -f "$TMP" 2>/dev/null || true
    else
      rm -f "$TMP" 2>/dev/null || true         # never leave a partial/garbage beacon behind
    fi
    exit 0
    ;;
  *)
    exit 0                                       # unknown/absent mode ⇒ no-op (fail-quiet)
    ;;
esac
