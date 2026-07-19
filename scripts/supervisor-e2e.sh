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
tel_exists(){ [ -f "$CC_TELEMETRY_DIR/$1.json" ]; }              # T11-T13: a clean-completion reap drops the row
mkrepo_landed(){ # $1=dir — a shipped+clean repo: clean tree, HEAD == origin/main (0 ahead, no network)
  local r="$1"; rm -rf "$r"; mkdir -p "$r"
  git -C "$r" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t
  echo x > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm init
  git -C "$r" update-ref refs/remotes/origin/main HEAD          # fabricate the landed trunk (no remote)
}

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

echo "T10 notify damping — a re-sweep of the same state is composer-quiet; a state CHANGE re-notifies"
# same dead fixture, second sweep: page re-fires in IDL but the capture must NOT grow (storm fix)
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/notify.log")" -eq 1 ] && ok "re-sweep same state ⇒ no re-notify (damped)" || no "re-sweep re-notified (storm regression)"
# a state transition re-notifies exactly once. Escalation is only reachable from the STALL? branch
# (alive pid), so: alive fixture + aged page + already-notified STALL? state + dark effects ⇒ the
# ESCALATED transition must produce exactly one new send (capture 1→2)
mktel hang10 40 100 "$ALIVE" "$REPO"
# stamp now-3: past DEADLINE_S=1 but NEWER than the init commit (the suite's sleeps guarantee ≥4s
# elapsed), else the effects re-read counts the commit as fresh and VOIDs instead of escalating
printf '%s' "$(( $(date +%s) - 3 ))" > "$CC_SUPERVISOR_PAGEDIR/hang10.page"
printf '%s\n' "STALL?" > "$CC_SUPERVISOR_PAGEDIR/hang10.notified"
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
# (the stub captures the TARGET per send, so growth 1→2 lines = exactly one new notify)
[ "$(wc -l < "$SBX/notify.log")" -eq 2 ] && ok "state change (→ESCALATED) re-notified exactly once" || no "state change did not re-notify once (lines=$(wc -l < "$SBX/notify.log"))"
# sticky escalation: the next sweep re-fires the STALL?→ESCALATED pair for the same zombie — with
# nf=ESCALATED both must be suppressed (the 2-notifies-per-sweep oscillation leak)
printf '%s' "$(( $(date +%s) - 3 ))" > "$CC_SUPERVISOR_PAGEDIR/hang10.page"
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/notify.log")" -eq 2 ] && ok "escalated is sticky (STALL?/ESCALATED oscillation quiet)" || no "oscillation leaked notifies (lines=$(wc -l < "$SBX/notify.log"))"

echo "T11 CLEAN COMPLETION — DEAD pid + shipped-clean worktree ⇒ AUTO-REAP (telemetry+page gone), NEVER page"
# the fix (item 9b183d78c723): a dead worker that landed its work leaves NOTHING stranded — reap it as a
# clean lifecycle end instead of DEAD-paging the desk every 30s sweep (~68% of dead-pid rows, the toil).
reset; rm -f "$CC_TELEMETRY_DIR"/*.json
LREPO="$SBX/landed"; mkrepo_landed "$LREPO"
mktel donesid 40 2 999999 "$LREPO"                              # pid gone ⇒ DEAD; worktree shipped+clean ⇒ clean completion
once
tel_exists donesid && no "telemetry NOT reaped (clean completion still pending)" || ok "telemetry row reaped (clean lifecycle end)"
paged donesid      && no "clean completion was PAGED (the bug this fixes)"        || ok "clean completion not paged"
idl_has '"kind":"reap"'                 && ok "reap recorded in IDL (S-4 auditable outcome, not a silent delete)" || no "reap not recorded in IDL"
idl_has '"kind":"page".*"state":"DEAD"' && no "a DEAD page was emitted for a clean completion"                    || ok "no DEAD page for a clean completion"
idl_has '"kind":"checkpoint"'           && no "checkpoint-preserved a clean completion (nothing to preserve)"     || ok "no checkpoint on a clean completion"

echo "T12 STRANDED (dirty) — DEAD pid + UNCOMMITTED work ⇒ PAGE + checkpoint, NOT reaped (no silent loss)"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json
DREPO="$SBX/dirty"; mkrepo_landed "$DREPO"; echo wip > "$DREPO/uncommitted"   # dirty tree ⇒ stranded
mktel dirtysid 40 2 999999 "$DREPO"
once
paged dirtysid      && ok "stranded (dirty) death PAGED"                     || no "dirty death not paged — stranded work unsurfaced"
tel_exists dirtysid && ok "dirty telemetry NOT reaped (stranded ⇒ surfaced)" || no "dirty telemetry WRONGLY reaped (silent stranded-work loss)"
idl_has '"kind":"reap"' && no "a dirty/stranded death was reaped (must never happen)" || ok "no reap for a dirty/stranded death"

echo "T13 STRANDED (unlanded) — DEAD pid + committed-but-UNLANDED commits ⇒ PAGE, NOT reaped"
reset; rm -f "$CC_TELEMETRY_DIR"/*.json
UREPO="$SBX/unlanded"; mkrepo_landed "$UREPO"
echo more > "$UREPO/g"; git -C "$UREPO" add g; git -C "$UREPO" commit -qm ahead   # clean tree, 1 commit ahead of origin/main
mktel unlandsid 40 2 999999 "$UREPO"
once
paged unlandsid      && ok "stranded (unlanded) death PAGED"                     || no "unlanded death not paged — committed work stranded"
tel_exists unlandsid && ok "unlanded telemetry NOT reaped"                       || no "unlanded telemetry WRONGLY reaped (silent loss of unlanded commits)"
idl_has '"kind":"reap"' && no "an unlanded death was reaped (must never happen)" || ok "no reap for an unlanded death"

echo ""
echo "supervisor-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
