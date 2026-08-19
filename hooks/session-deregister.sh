#!/bin/bash
# session-deregister.sh — SessionEnd hook; removes this pane's cc-registry entry, but ONLY when
# the row belongs to the session that is ending.
#
# Pairs with session-register.sh (see it for the registry rationale). Fail-safe:
# always exit 0. Skips reason=clear — a cleared session keeps the SAME pane and
# re-registers on the immediately-following SessionStart, so removing here would
# only briefly drop a live pane from the registry (matches session-save-id.sh).
# A session that dies WITHOUT SessionEnd self-heals: cc-sessions sweeps the stale
# entry (pane gone per `it2 session list`, or owning pid dead per `kill -0`).
#
# ── TENANCY GATE: a SessionEnd does not prove the ender owns the row ──────────────────────────
# A pane id is not a tenancy. Measured 2026-08-05: `hooks/session-start.sh:63` runs
# `claude mcp list` on EVERY SessionStart, and that subprocess emits a SessionEnd of its own —
# reason "other", a fresh random session_id, and no matching SessionStart — while inheriting the
# live pane's CC_PANE_ID/ITERM_SESSION_ID from the environment. This hook then deleted the row
# the session had just written, ~1s later: pane 99, row written 14:54:04.169, gone 14:54:05.324,
# owning pid alive throughout; 5360 of 6208 `MCP Status` lines in ~/.claude/logs/sessions.log are
# immediately preceded by that phantom's "Session ended". Until cc-reconcile healed it minutes
# later the pane had NO addressable row — cc-notify could not reach it, cc-board read it absent,
# and cc-backlog's `claimer_live` answered PROVEN NOT-LIVE for a claim held by a perfectly healthy
# worker: a false death. Evidence + repro: docs/research/registry-row-removal-2026-08-05.md.
#
# So: remove only on a PROVEN match. Every unprovable case — no session_id on either side, a
# sid-less provisional row (handoff-fire's ensure_registration), an unreadable row — KEEPS the
# row, because the two errors are not symmetric. A wrongly-KEPT row is a dead row, which every
# consumer already tolerates by construction (cc-sessions retains dead rows 24h for forensics and
# then sweeps them; cc-reconcile prunes; both gate on `kill -0`, not on presence) and which the
# self-close orphan gate actually reads as its evidence ("row present, pid gone" ⇒ lead dead,
# handoff-fire.sh:2797). A wrongly-REMOVED row erases a LIVE pane from the fleet's only
# cross-account addressing table. This is the comparison the sibling live-session-registry.sh:33-38
# has always made against the same hazard — and the reason that hook never had this bug.
# bash 3.2-safe.
set -uo pipefail

input=$(cat 2>/dev/null)
command -v jq >/dev/null 2>&1 || exit 0

reason=$(printf '%s' "$input" | jq -r '.reason // empty' 2>/dev/null)
[ "$reason" = "clear" ] && exit 0

# The address predicate MIRRORS hooks/session-register.sh's — they are one keyspace, and a remover
# narrower than its writer does not fail, it ORPHANS: the row is written, nothing can ever remove
# it, and it survives to CC_REG_RETAIN_H as a confident corpse. That is why this moved in the same
# diff as the writer (backlog 4b9d5e93b40a) rather than after it. Safe filename component only —
# the rationale, and why "hex-shaped" was the wrong proxy, is written out at the writer's copy.
pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; pane="${pane##*:}"
case "$pane" in
  ''|.|..) exit 0 ;;
  .*) exit 0 ;;
  *[!A-Za-z0-9._-]*) exit 0 ;;
esac

reg_dir="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
row="$reg_dir/$pane.json"
[ -f "$row" ] || exit 0

# Both sids must be present AND equal. `// empty` collapses a JSON null (register() writes
# session_id:null when the hook input carried none) into the same unprovable case as a missing key,
# and a jq failure on a corrupt row yields empty too — all of which fall through to exit 0.
sid=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
have=$(jq -r '.session_id // empty' "$row" 2>/dev/null)
[ -n "$sid" ] && [ -n "$have" ] && [ "$sid" = "$have" ] || exit 0

rm -f "$row" 2>/dev/null
exit 0
