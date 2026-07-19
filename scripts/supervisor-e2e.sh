#!/bin/bash
# shellcheck disable=SC2015  # `cond && ok || no` assertion idiom: ok() is a counter+echo that cannot fail
# supervisor-e2e.sh — regression guard for scripts/lead-supervisor.sh (SESSION_AUTONOMY §3.3, B-1/S-3/S-3b/S-4).
#
# Sandbox: telemetry fixtures + a real alive pid + a git repo (for the effects re-read). Asserts the
# PAGE-only routing (DEAD / STALL? / PAST-THRESHOLD / OK), the S-4 heartbeat, and the load-bearing S-3b
# law — the disposition VOIDS on fresh effects past the deadline and only ESCALATES on effects-dark, never
# on silence (the §3h near-miss: a healthy long-turn dark 69-75m that a silence-reap would have killed).
# Run from repo root. Exit nonzero on any failure (a gate).
set -u
cd "$(dirname "$0")/.." || exit 2
SUP="$PWD/scripts/lead-supervisor.sh"
P=0; F=0
ok(){ P=$((P+1)); echo "  ✓ $1"; }
no(){ F=$((F+1)); echo "  ✗ $1"; }

SBX=$(mktemp -d)
export CC_TELEMETRY_DIR="$SBX/tel";               mkdir -p "$CC_TELEMETRY_DIR"
export CC_IDL="$SBX/idl.jsonl"
export CC_SUPERVISOR_LOG="$SBX/sup.log"
export CC_SUPERVISOR_PAGEDIR="$SBX/pages";        mkdir -p "$CC_SUPERVISOR_PAGEDIR"
export CC_PAGE_TO=""                              # no cc-notify in tests
export CC_PAGE_TO_FILE=/dev/null                  # …and no role-file fallback either (T9 opts back in)
export CC_SUP_T=73
export CC_SUP_STALL_S=5
export CC_SUP_PAGE_DEADLINE_S=1

ALIVE=; cleanup(){ [ -n "$ALIVE" ] && kill "$ALIVE" 2>/dev/null; rm -rf "$SBX"; }
trap cleanup EXIT
sleep 600 & ALIVE=$!            # a genuinely-alive pid for the live-session fixtures

REPO="$SBX/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo x > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm init

mktel(){ # $1=sid $2=used $3=age_s $4=pid $5=cwd
  local ts; ts=$(( $(date +%s) - $3 ))
  jq -nc --arg sid "$1" --argjson up "$2" --argjson ts "$ts" --arg pid "$4" --arg cwd "$5" \
    '{ts:$ts,session_id:$sid,used_pct:$up,cwd:$cwd,config_dir:"/x/.claude-next",pid:($pid|tonumber)}' \
    > "$CC_TELEMETRY_DIR/$1.json"; }
once(){ bash "$SUP" --once >/dev/null 2>&1; }
idl_has(){ grep -q "$1" "$CC_IDL" 2>/dev/null; }
reset(){ : > "$CC_IDL"; rm -f "$CC_SUPERVISOR_PAGEDIR"/*.page 2>/dev/null; }
paged(){ [ -f "$CC_SUPERVISOR_PAGEDIR/$1.page" ]; }

echo "T1 DEAD — pid gone ⇒ checkpoint-preserve + PAGE (never auto-respawn)"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json; mktel dead 40 2 999999 "$REPO"
once
idl_has '"kind":"page".*"state":"DEAD"' && ok "DEAD paged"           || no "DEAD not paged"
idl_has '"kind":"checkpoint"'           && ok "dead worktree checkpoint-preserved" || no "no checkpoint on DEAD"

echo "T2 STALL? — pid ALIVE + stale ⇒ PAGE as a CANDIDATE (never an action)"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json; mktel hang 40 100 "$ALIVE" "$REPO"
once
idl_has '"state":"STALL?"'              && ok "STALL? paged as candidate" || no "STALL? not paged"

echo "T3 B-1 — PAST-THRESHOLD ∧ NOT-STOPPING (used≥T, fresh, alive) ⇒ PAGE (the hook is blind here)"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json; mktel busy 90 1 "$ALIVE" "$REPO"
once
idl_has '"state":"PAST-THRESHOLD"'      && ok "past-threshold∧not-stopping paged (B-1)" || no "B-1 case not covered"

echo "T4 OK ANTI-TRIGGER — alive, fresh, below threshold ⇒ NO page"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json; mktel fine 40 1 "$ALIVE" "$REPO"
once
paged fine && no "paged a healthy session (false positive)" || ok "healthy session not paged"

echo "T5 S-4 — every sweep emits a heartbeat, even an all-clear one"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json; mktel fine 40 1 "$ALIVE" "$REPO"
once
idl_has '"kind":"heartbeat"' && ok "sweep heartbeat recorded (who-watches-the-watcher)" || no "no heartbeat"

echo "T6 S-3b LAW — fresh effects past the deadline ⇒ VOID (a silence-reap would kill a healthy long turn)"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json "$REPO/wip.txt"; mktel hang2 40 100 "$ALIVE" "$REPO"
printf '%s' "$(date +%s)" > "$CC_SUPERVISOR_PAGEDIR/hang2.page"   # stamp = NOW (after the init commit + all files)
sleep 2                                                           # the 1s deadline passes
echo work > "$REPO/wip.txt"                                       # FRESH effect AFTER the stamp ⇒ alive + working
once
idl_has '"kind":"page_void"' && ok "fresh-effects past deadline ⇒ VOID (not escalated)" || no "did not void a working lead (S-3b VIOLATED)"
paged hang2 && no "page not cleared after void" || ok "page cleared on void"

echo "T7 S-3b — effects-dark past the deadline ⇒ ESCALATE (disposition via re-read, not silence)"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json "$REPO/wip.txt"; mktel hang3 40 100 "$ALIVE" "$REPO"
printf '%s' "$(date +%s)" > "$CC_SUPERVISOR_PAGEDIR/hang3.page"   # stamp = NOW (newer than the init commit + all files)
sleep 2                                                           # deadline passes; NOTHING touched since ⇒ effects dark
once
idl_has '"kind":"page_escalate"' && ok "effects-dark past deadline ⇒ ESCALATE" || no "no escalation on dark effects"

echo "T8 S-3b discrimination — the disposition is NOT reachable from silence alone"
# proven statically by s3b-lint on this very file's target; assert the lint agrees at runtime too
./scripts/s3b-lint.sh "$SUP" >/dev/null 2>&1 && ok "s3b-lint GREEN on the supervisor (no silence→dispose)" || no "s3b-lint RED"

echo "T9 role-file page fallback — empty CC_PAGE_TO ⇒ target read from CC_PAGE_TO_FILE at page time"
# effect-read through a capturing cc-notify stub: the page must reach the uuid in the role FILE
mkdir -p "$SBX/bin"; cat > "$SBX/bin/cc-notify" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >> "${CC_NOTIFY_CAPTURE:?}"
STUB
chmod +x "$SBX/bin/cc-notify"
printf '%s' "ROLE-UUID-T9" > "$SBX/desk-role"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json; mktel dead9 40 100 99999999 "$REPO"   # pid gone ⇒ DEAD ⇒ page
# CC_NOTIFY_BIN (not PATH): the supervisor resolves beside-script repo bin/ BEFORE PATH, so only
# the env override keeps the sandbox hermetic against the real cc-notify
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
grep -q "ROLE-UUID-T9" "$SBX/notify.log" 2>/dev/null && ok "page routed to role-file uuid (fallback live)" || no "fallback did not route to role-file uuid"
# and the /dev/null default keeps every other test notify-silent:
[ -s "$SBX/notify.log" ] && [ "$(wc -l < "$SBX/notify.log")" -eq 1 ] && ok "exactly one capture (isolation intact)" || no "unexpected notify volume (isolation broken?)"

echo ""
echo "supervisor-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
