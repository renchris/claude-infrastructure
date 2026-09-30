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

# ── SHUTDOWN TOMBSTONE: a death by signal leaves a record boot-resume can read ─────────────────
# A graceful host shutdown SIGHUPs every pane, and each session's SessionEnd lands here with
# reason=other — measured at the 2026-09-30 15:25 reboot: all 19 roster sessions logged
# `Session ended … reason=other` inside 4 seconds (15:25:27-31, ~/.claude/logs/sessions.log). This
# hook then deleted their rows, so scripts/boot-resume.sh — which looked for rows that OUTLIVED
# the boot — saw only 11 stale crash ghosts from earlier days, overlap 0 with the 20 sessions that
# were actually live. So a signal-shaped end moves the row to a tombstone instead of erasing it.
# The registry itself stays clean: the live-pane table must not carry the dead.
# Deliberate ends (prompt_input_exit = /exit or ^D, logout, resume) delete as before — those
# sessions were closed on purpose and must never come back after a reboot. `other` also covers an
# operator closing one pane; boot-resume separates the shutdown from those by taking only the LAST
# burst of tombstones before the boot (see its DETECT block), with kern.willshutdown as extra
# evidence where the kernel had already set it. The branch is recorded so reso-resume-one's
# identity check can refuse a pooled slot that was re-let while the box was down.
if [ "$reason" = "other" ]; then
  tomb_dir="${CC_SHUTDOWN_TOMB_DIR:-$HOME/.claude/autonomy/shutdown-tombstones}"
  sysctl_bin="${CC_SYSCTL_BIN:-/usr/sbin/sysctl}"
  wsd=$("$sysctl_bin" -n kern.willshutdown 2>/dev/null)
  cwd=$(jq -r '.cwd // empty' "$row" 2>/dev/null)
  br=""
  # symbolic-ref, not rev-parse: a detached HEAD yields nothing (no identity to check), never "HEAD".
  [ -n "$cwd" ] && [ -d "$cwd" ] && br=$(git -C "$cwd" symbolic-ref -q --short HEAD 2>/dev/null)
  if mkdir -p "$tomb_dir" 2>/dev/null; then
    tmp="$tomb_dir/.$sid.$$.tmp"
    if jq --argjson t "$(date +%s)" --arg r "$reason" --arg b "$br" --argjson w "$([ "$wsd" = 1 ] && echo true || echo false)" \
         '. + {endedAt:$t, endReason:$r, hostShutdown:$w} + (if $b == "" then {} else {branch:$b} end)' \
         "$row" > "$tmp" 2>/dev/null; then
      mv -f "$tmp" "$tomb_dir/$sid.json" 2>/dev/null
    fi
    rm -f "$tmp" 2>/dev/null
    # A week of tombstones is far more than the one-boot window boot-resume reads.
    find "$tomb_dir" -name '*.json' -mtime +7 -delete 2>/dev/null
  fi
fi

rm -f "$row" 2>/dev/null
exit 0
