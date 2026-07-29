#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 17-permission-beacon-wire  —  register hooks/cc-permission-beacon.sh in every settings.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: four idempotent hook registrations per config dir — `write` on PermissionRequest (catch-all),
#   `clear` on PostToolUse (catch-all) + Stop + SessionEnd. Additive: appends new groups, mutates
#   none, and a re-run is a byte-for-byte no-op. Everything outside `.hooks` stays byte-identical.
# WHY: the beacon landed (b7db06c5) with its consumer (lead-supervisor's PERMISSION-PENDING page) and
#   12 regression tests — and was then registered in ZERO settings.json, so it has never fired once.
#   /tmp/cc-permission-pending/ has never existed. On 2026-07-29 a teammate (@gu5-decide) parked on
#   "Waiting for team lead approval" — an approval routed to a lead process that had died — while
#   `cc-blockers` reported all-clear, because the one mechanism built to see that was inert rather
#   than missing (cc-backlog 1e16815bac51; memory feature-durability-mechanism-not-memory).
# WHY C10 (agent stages; operator runs): these files govern the agent's own permissions, so an agent
#   must never edit one in place — including to make itself more observable. Hence: staged here, dry
#   run by default, applied only by the operator.
# SAFETY: the beacon is a pure OBSERVER — it emits no permission decision, so this widens nothing and
#   changes no prompt. Worst case it costs one `rm -f` of an absent file per tool call.
# ROLLBACK: restore the printed *.bak-<ts> file, or set CC_PERMISSION_BEACON_DISABLED=1 (the hook
#   no-ops in both modes).  Mark done: touch <this file>.done
# VERIFY AFTER: `cc-blockers` must stop printing the APPROVAL / beacon-inert NOT-WIRED row.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HOOK_PATH="${CC_BEACON_HOOK_PATH:-~/.claude/hooks/cc-permission-beacon.sh}"
CONFIG_DIRS="${CC_BEACON_CONFIG_DIRS:-$HOME/.claude $HOME/.claude-secondary $HOME/.claude-next $HOME/.claude-tertiary $HOME/.claude-quaternary}"
W="$HOOK_PATH write"
C="$HOOK_PATH clear"

echo "== 17-permission-beacon-wire =="
command -v jq >/dev/null || { echo "✗ jq required" >&2; exit 1; }

# The hook is symlinked into every ~/.claude*/hooks/ by install.sh; if it is missing there, wiring a
# path that resolves to nothing would register a hook that silently no-ops — the same class of
# invisible inertness this activation exists to end.
LIVE_HOOK="${HOOK_PATH/#\~/$HOME}"
[ -e "$LIVE_HOOK" ] || { echo "✗ hook not deployed at $LIVE_HOOK — run install.sh first" >&2; exit 1; }

# BEFORE — prove inert, and count what is already there (idempotency is visible, not asserted).
echo "Current registrations (write@PermissionRequest / clear@{PostToolUse,Stop,SessionEnd}):"
for d in $CONFIG_DIRS; do
  f="$d/settings.json"; [ -f "$f" ] || { echo "  $d: (no settings.json — skipped)"; continue; }
  # `grep -c` PRINTS 0 and EXITS 1 on no matches, so a `|| echo 0` fallback emits a SECOND zero and
  # the line renders "0\n0 reference(s)". head -1 keeps the count; the -n test covers unreadable.
  nref="$(grep -c 'cc-permission-beacon\.sh' "$f" 2>/dev/null | head -1)"; [ -n "$nref" ] || nref=0
  echo "  $d: $nref reference(s)"
done

echo "Will do: append 4 hook groups per settings.json above (backup each to *.bak-<ts> FIRST)"
echo "         [PermissionRequest]=write  [PostToolUse,Stop,SessionEnd]=clear"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/17-permission-beacon-wire-activate.sh"
  exit 0
fi

# The transform, verbatim from docs/PART-B2-PERMISSION-BEACON-WIRING.md §4 (validated there against a
# scratchpad COPY of live settings.json, never the live file). Each `index($w)`/`index($c)` guard is
# what makes a re-run a no-op rather than a fifth duplicate group.
# shellcheck disable=SC2016  # a jq PROGRAM: $write/$clear are jq's --arg bindings, not shell vars.
BEACON_JQ='
($write) as $w | ($clear) as $c |
.hooks = (.hooks // {})
| .hooks.PermissionRequest = ((.hooks.PermissionRequest // [])
    + (if ([.hooks.PermissionRequest[]?.hooks[]?.command] | index($w)) == null
       then [{"matcher":"","hooks":[{"type":"command","command":$w,"timeout":5}]}] else [] end))
| .hooks.PostToolUse = ((.hooks.PostToolUse // [])
    + (if ([.hooks.PostToolUse[]?.hooks[]?.command] | index($c)) == null
       then [{"matcher":"","hooks":[{"type":"command","command":$c,"timeout":5}]}] else [] end))
| .hooks.Stop = ((.hooks.Stop // [])
    + (if ([.hooks.Stop[]?.hooks[]?.command] | index($c)) == null
       then [{"hooks":[{"type":"command","command":$c,"timeout":5}]}] else [] end))
| .hooks.SessionEnd = ((.hooks.SessionEnd // [])
    + (if ([.hooks.SessionEnd[]?.hooks[]?.command] | index($c)) == null
       then [{"hooks":[{"type":"command","command":$c,"timeout":5}]}] else [] end))
'

rc=0
for d in $CONFIG_DIRS; do
  f="$d/settings.json"; [ -f "$f" ] || continue
  cp -p "$f" "$f.bak-$(date -u +%Y%m%dT%H%M%SZ)" || { echo "  ✗ backup failed: $f" >&2; rc=1; continue; }
  tmp="$f.tmp.$$"
  # FAIL-CLOSED: the file is replaced only if the transform ran AND its output is valid JSON. A
  # settings.json this tool half-wrote is a session that will not start.
  if jq --arg write "$W" --arg clear "$C" "$BEACON_JQ" "$f" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$f"; echo "  wired: $f"
  else
    rm -f "$tmp"; echo "  ✗ SKIP (transform did not validate — left intact): $f" >&2; rc=1
  fi
done

# AFTER — expect 4 registrations per dir. Counted from the parsed structure, not grep, so a match in
# a comment or an unrelated string cannot be mistaken for a live registration.
echo "Verify (expect write=1 clear=3 per dir):"
for d in $CONFIG_DIRS; do
  f="$d/settings.json"; [ -f "$f" ] || continue
  jq -r --arg d "$d" '"  " + $d + ": write@PermReq=" +
    ([.hooks.PermissionRequest[]?.hooks[]?.command | select(test("cc-permission-beacon.sh write"))] | length | tostring) +
    " clear@{Post,Stop,End}=" +
    ([.hooks.PostToolUse[]?.hooks[]?.command, .hooks.Stop[]?.hooks[]?.command, .hooks.SessionEnd[]?.hooks[]?.command
      | select(test("cc-permission-beacon.sh clear"))] | length | tostring)' "$f" 2>/dev/null \
    || echo "  $d: (unreadable)"
done

# LIVE SMOKE — round-trip a beacon through the real hook, then confirm the heartbeat exists. The
# heartbeat is the positive control: after this, an EMPTY beacon dir means "nothing pending" and no
# longer doubles as "never ran" (memory absence-alarm-needs-existence-evidence).
echo "Smoke:"
PERMPEND="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"
printf '{"session_id":"smoke-1","tool_name":"Bash","tool_input":{"command":"git reset --hard"},"cwd":"/w"}' \
  | "$LIVE_HOOK" write
if [ -f "$PERMPEND/smoke-1.json" ]; then echo "  beacon written ✓"
else echo "  ✗ beacon NOT written" >&2; rc=1; fi
printf '{"session_id":"smoke-1"}' | "$LIVE_HOOK" clear
if [ -f "$PERMPEND/smoke-1.json" ]; then echo "  ✗ LEAK — beacon survived clear" >&2; rc=1
else echo "  cleared ✓"; fi
if [ -f "$PERMPEND/.beacon-alive" ]; then
  echo "  heartbeat present ✓ (empty dir now means 'nothing pending', not 'never ran')"
else echo "  ✗ no heartbeat — existence evidence missing" >&2; rc=1; fi

if [ "$rc" -eq 0 ]; then
  echo "✓ done — confirm with: cc-blockers   (the APPROVAL / beacon-inert NOT-WIRED row must be gone)"
  echo "  then: touch $HOME/.claude/autonomy/pending-activation/17-permission-beacon-wire-activate.sh.done"
else
  echo "✗ completed with errors — see above" >&2
fi
exit "$rc"
