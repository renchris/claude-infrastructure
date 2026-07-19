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
export CC_PERMPEND_DIR="$SBX/permpend";           mkdir -p "$CC_PERMPEND_DIR"
export CC_PERMPEND_NOTICE_S=1                      # page a beacon pending ≥1s (fast tests; prod default 120)
export CC_PERMPEND_HORIZON_S=86400                # orphan-reap horizon (T16 ages a beacon past it)
export CC_REGISTRY_DIR="$SBX/registry";           mkdir -p "$CC_REGISTRY_DIR"   # paneUUID→sid map for the registered-desk exemption tests (T23-T26)
export CC_SUP_OWNER_PAT=sleep     # the live-session fixtures below are `sleep` PIDs — mark them owners (prod default: claude)

ALIVE=; cleanup(){ [ -n "$ALIVE" ] && kill "$ALIVE" 2>/dev/null; rm -rf "$SBX"; }
trap cleanup EXIT
sleep 600 & ALIVE=$!            # a genuinely-alive pid for the live-session fixtures

REPO="$SBX/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo x > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm init

mktel(){ # $1=sid $2=used $3=age_s $4=pid $5=cwd [$6=config_dir]
  local ts; ts=$(( $(date +%s) - $3 )); local cfg="${6:-/x/.claude-next}"
  jq -nc --arg sid "$1" --argjson up "$2" --argjson ts "$ts" --arg pid "$4" --arg cwd "$5" --arg cfg "$cfg" \
    '{ts:$ts,session_id:$sid,used_pct:$up,cwd:$cwd,config_dir:$cfg,pid:($pid|tonumber)}' \
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
mkbeacon(){ # $1=sid $2=age_s $3=tool_name $4=tool_input_json — a harness-authored PermissionRequest beacon
  local ts; ts=$(( $(date +%s) - $2 ))
  jq -nc --argjson ts "$ts" --arg tn "$3" --argjson ti "$4" --arg cwd "$REPO" \
    '{ts:$ts,tool_name:$tn,tool_input:$ti,cwd:$cwd}' > "$CC_PERMPEND_DIR/$1.json"; }
beacon_exists(){ [ -f "$CC_PERMPEND_DIR/$1.json" ]; }
permreset(){ rm -f "$CC_PERMPEND_DIR"/*.json "$CC_SUPERVISOR_PAGEDIR"/*.permpend.notified 2>/dev/null; }

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

echo "T14 PERMISSION-PENDING — a harness beacon past the notice threshold ⇒ a PRECISE page with the cmd attached"
# the §B2 core: a permission prompt is INVISIBLE to the bash sweep (S-3 modal blindness), but the harness
# leaves a durable beacon the supervisor CAN read → a command-attached page instead of a detail-free STALL?.
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
mkbeacon permbash 10 Bash '{"command":"git reset --hard origin/main"}'
once
idl_has '"kind":"permission_pending"'  && ok "permission_pending recorded in the IDL"           || no "no permission_pending record"
idl_has 'git reset --hard origin/main' && ok "the exact blocked command is attached to the page" || no "blocked command not attached"
beacon_exists permbash                 && ok "a still-pending beacon is retained (paged, not reaped, while alive)" || no "pending beacon wrongly removed"

echo "T15 THRESHOLD GATE — a beacon younger than the notice threshold is NOT paged (auto-approved tools clear in ms)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
mkbeacon permyoung 10 Bash '{"command":"echo hi"}'
CC_PERMPEND_NOTICE_S=99999 bash "$SUP" --once >/dev/null 2>&1
idl_has '"kind":"permission_pending"' && no "paged a below-threshold beacon (false page)" || ok "below-threshold beacon not paged"
beacon_exists permyoung               && ok "below-threshold beacon retained (it will page once it ages)" || no "below-threshold beacon wrongly removed"

echo "T16 REAP orphan — a beacon past the horizon with no telemetry ⇒ REAPED silently (hard-kill, no SessionEnd)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
mkbeacon permorphan 90000 Bash '{"command":"stale"}'
once
beacon_exists permorphan              && no "orphaned beacon NOT reaped past horizon" || ok "orphaned beacon reaped past the horizon"
idl_has '"kind":"permission_pending"' && no "an orphan was paged (must reap silently)" || ok "orphan not paged"

echo "T17 REAP dead-pid — a beacon whose owning session pid is gone ⇒ REAPED (the prompt died with the session)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
DREPO2="$SBX/permdead-repo"; mkrepo_landed "$DREPO2"; echo wip > "$DREPO2/uncommitted"  # dead+dirty ⇒ tel row survives the sweep, so the beacon's pid-reap can read it
mktel   permdead 40 5 999999 "$DREPO2"           # pid 999999 gone
mkbeacon permdead 10 Bash '{"command":"blocked"}'
once
beacon_exists permdead                && no "dead-session beacon NOT reaped" || ok "dead-session beacon reaped (prompt died with the session)"
idl_has '"kind":"permission_pending"' && no "a dead-session prompt was PERMISSION-PENDING paged (the DEAD page already covers it)" || ok "no permission_pending page for a dead session"

echo "T18 DAMPING — one notify per PENDING EPISODE (same beacon ts quiet across sweeps); a NEW prompt (new ts) re-notifies"
# uses the T9 capturing cc-notify stub + role file. keyed by the beacon ts so a re-prompt is a new episode.
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json; : > "$SBX/permnotify.log"
mkbeacon permdamp 10 Bash '{"command":"first prompt"}'
CC_NOTIFY_CAPTURE="$SBX/permnotify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/permnotify.log")" -eq 1 ] && ok "first pending episode notifies exactly once" || no "episode did not notify once (lines=$(wc -l < "$SBX/permnotify.log"))"
CC_NOTIFY_CAPTURE="$SBX/permnotify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/permnotify.log")" -eq 1 ] && ok "same episode across sweeps is composer-quiet (damped)" || no "same episode re-notified (storm)"
mkbeacon permdamp 5 Bash '{"command":"second prompt"}'    # a NEW prompt: newer ts ⇒ a new episode
CC_NOTIFY_CAPTURE="$SBX/permnotify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/permnotify.log")" -eq 2 ] && ok "a new prompt (new ts) re-notifies exactly once" || no "new episode did not re-notify (lines=$(wc -l < "$SBX/permnotify.log"))"

echo "T19 CMD RENDER — a non-Bash prompt (Write) attaches the file path, not a raw tool dump"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
mkbeacon permwrite 10 Write '{"file_path":"/x/secret.ts","content":"..."}'
once
idl_has '/x/secret.ts' && ok "a Write prompt renders its file_path" || no "file_path not rendered in the page"
echo "T20 WARM-TRANSCRIPT EXEMPTION — live pid + stale telemetry but a FRESH transcript ⇒ NOT a STALL? candidate (item 1c324d9fcc32)"
# the idle-live ROOT fix: telemetry goes stale (the statusline stops emitting for a backgrounded / long-
# turn pane) while the session keeps appending its transcript — a warm transcript ⇒ demonstrably alive ⇒
# exempt. Transcript path = <config_dir>/projects/<slug(cwd)>/<sid>.jsonl (CC '/'+'.'→'-' mangling).
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
WCFG="$SBX/warmcfg"; WSLUG="$(printf '%s' "$REPO" | sed 's|[/.]|-|g')"
mkdir -p "$WCFG/projects/$WSLUG"
: > "$WCFG/projects/$WSLUG/warm1.jsonl"                            # mtime = now ⇒ warm
mktel warm1 40 100 "$ALIVE" "$REPO" "$WCFG"                       # telemetry 100s stale (≥ STALL_S=5), pid alive
once
paged warm1 && no "paged a warm-transcript session (exemption FAILED — idle-live false positive)" || ok "warm transcript exempts STALL? candidacy"
idl_has '"state":"STALL?"' && no "STALL? finding emitted for a warm-transcript session" || ok "no STALL? finding for a warm transcript"

echo "T21 COLD-TRANSCRIPT — live pid + stale telemetry + a STALE transcript ⇒ STILL a STALL? candidate (a warmth check, not has-transcript)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
: > "$WCFG/projects/$WSLUG/cold1.jsonl"
touch -t "$(date -r "$(( $(date +%s) - 100 ))" +%Y%m%d%H%M.%S)" "$WCFG/projects/$WSLUG/cold1.jsonl"   # mtime 100s ago ⇒ cold
mktel cold1 40 100 "$ALIVE" "$REPO" "$WCFG"
once
paged cold1 && ok "cold transcript stays a STALL? candidate (exemption is warmth-specific)" || no "cold transcript wrongly exempted"

echo "T22 IDLE-LIVE OSCILLATION — STALL?→void→re-STALL? re-notifies ONCE, not per cycle (item 1c324d9fcc32 — void keeps the damping marker)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json "$SBX/notify.log" "$CC_SUPERVISOR_PAGEDIR"/osc.notified "$REPO/osc.txt"
mktel osc 40 100 "$ALIVE" "$REPO"                                 # live pid, telemetry 100s stale, NO transcript ⇒ STALL? candidate
# sweep 1 — first STALL? page ⇒ exactly one notify, marker set to STALL?
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/notify.log")" -eq 1 ] && ok "STALL? first page ⇒ one notify" || no "STALL? first page did not notify once (lines=$(wc -l < "$SBX/notify.log"))"
# sweep 2 — deadline passes + a FRESH effect in cwd ⇒ VOID; the damping marker MUST survive the void
sleep 2; echo work > "$REPO/osc.txt"
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
idl_has '"kind":"page_void","sid":"osc"' && ok "fresh effects past deadline ⇒ VOID (oscillation midpoint)" || no "did not VOID (test setup wrong)"
# sweep 3 — the same stale telemetry re-raises STALL?, but the RETAINED marker keeps it composer-quiet
CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/notify.log")" -eq 1 ] && ok "re-STALL? after void ⇒ NO re-notify (marker retained — storm fixed)" || no "void dropped the marker ⇒ re-notify storm (lines=$(wc -l < "$SBX/notify.log"))"

echo "T23 REGISTERED-DESK EXEMPTION (role=sid) — a pid-alive idle desk with STALE telemetry+transcript is NOT a STALL? candidate (item ff95faea46c8)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
printf '%s' "deskA" > "$SBX/desk-role"                            # role file holds the desk's sid DIRECTLY
mktel deskA 40 100 "$ALIVE" "$REPO"                              # live pid, telemetry 100s stale (≥ STALL_S=5), NO transcript ⇒ cold — exactly the idle-monitor false positive
CC_PAGE_TO_FILE="$SBX/desk-role" bash "$SUP" --once >/dev/null 2>&1
paged deskA && no "paged the registered desk (exemption FAILED — idle-monitor STALL? false positive)" || ok "registered desk (role=sid) exempt from STALL?"
idl_has '"sid":"deskA","state":"STALL?"' && no "STALL? finding emitted for the registered desk" || ok "no STALL? finding for the registered desk"

echo "T24 REGISTERED-DESK EXEMPTION (role=pane→registry) — a pane-uuid role file bridges to the sid via cc-registry (item ff95faea46c8)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
printf '%s' "PANE-DESK-24" > "$SBX/desk-role"                     # role file holds a PANE uuid…
jq -nc --arg u PANE-DESK-24 --arg s deskB '{paneUUID:$u,session_id:$s,pid:1,cwd:"/x"}' > "$CC_REGISTRY_DIR/PANE-DESK-24.json"   # …registry maps pane → sid deskB
mktel deskB 40 100 "$ALIVE" "$REPO"
CC_PAGE_TO_FILE="$SBX/desk-role" bash "$SUP" --once >/dev/null 2>&1
paged deskB && no "paged the registered desk via pane→registry bridge (bridge FAILED)" || ok "registered desk (role=pane→registry sid) exempt from STALL?"

echo "T25 EXEMPTION IS DESK-SPECIFIC — a NON-desk stale-live session still pages STALL? with a desk registered (identity-scoped, not a blanket disable)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
printf '%s' "deskA" > "$SBX/desk-role"                            # deskA is the registered desk…
mktel other25 40 100 "$ALIVE" "$REPO"                            # …but THIS session (other25) is a different, genuinely-stalled one
CC_PAGE_TO_FILE="$SBX/desk-role" bash "$SUP" --once >/dev/null 2>&1
# assert the durable IDL finding, not the ephemeral .page: with DEADLINE_S=1 a single sweep can cross the
# deadline and void the .page on fresh cwd-effects — the STALL? IDL row is the append-only proof it fired.
idl_has '"sid":"other25","state":"STALL?"' && ok "non-desk stale-live session still raises STALL? (exemption is identity-scoped)" || no "non-desk session wrongly exempted (blanket disable — WRONG)"

echo "T26 DEAD DESK — a registered desk whose pid is GONE still hits DEAD (the exemption never masks a real death; DEAD precedes STALL?)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json
printf '%s' "deskC" > "$SBX/desk-role"
mktel deskC 40 100 99999999 "$REPO"                              # registered desk BUT pid gone ⇒ DEAD branch (runs before STALL?)
CC_PAGE_TO_FILE="$SBX/desk-role" bash "$SUP" --once >/dev/null 2>&1
paged deskC && ok "dead registered-desk pid still pages (exemption is pid-alive-only)" || no "dead desk not paged (exemption wrongly masked a death)"
idl_has '"sid":"deskC","state":"DEAD"' && ok "DEAD state emitted for the dead registered desk" || no "DEAD not emitted for the dead desk"
echo "T27 GC — a LIVE-OWNER row stale past the horizon ⇒ row DROPPED, no STALL? page (item fdc101e8b0c7)"
# the zombie: a hung owner (silent for days) or a pid recycled to a NEWER claude reads as "alive" on a
# days-stale row, so the STALL? branch re-pages it every sweep FOREVER. gc_stale drops it past GC_S.
reset; rm -f "$CC_TELEMETRY_DIR"/*.json
mktel zombie 40 100 "$ALIVE" "$REPO"                              # alive OWNER (kill -0 ok, cmd matches OWNER_PAT); telemetry 100s stale
CC_SUP_GC_S=50 bash "$SUP" --once >/dev/null 2>&1                 # horizon 50s < age 100s ⇒ GC (age also >= STALL_S, so this proves GC PRE-EMPTS STALL?)
tel_exists zombie && no "horizon-stale live-owner row NOT dropped (zombie persists)"    || ok "horizon-stale live-owner row GC'd"
paged zombie      && no "GC'd zombie still PAGED (STALL? leaked past the horizon)"      || ok "no page for a GC'd zombie"
idl_has '"kind":"gc"'      && ok "GC recorded in IDL (S-4 auditable, not a silent delete)"           || no "GC not recorded in IDL"
idl_has '"state":"STALL?"' && no "STALL? paged for a horizon-stale row (GC must pre-empt it)"        || ok "STALL? did not fire (GC pre-empted the zombie)"

echo "T28 RECYCLED PID — alive pid that is NOT a claude owner + stale ⇒ DEAD, never STALL? (item fdc101e8b0c7)"
# kill -0 alone reads a recycled (non-claude) pid as a live session and STALL?-escalates it; the owner
# check routes it to DEAD instead — where an UNLANDED cwd (here $REPO, no origin/main) is a stranded death.
reset; rm -f "$CC_TELEMETRY_DIR"/*.json
tail -f /dev/null & NONOWNER=$!                                   # a genuinely-alive pid whose command does NOT match OWNER_PAT (sleep)
mktel recycled 40 100 "$NONOWNER" "$REPO"                         # age 100 >= STALL_S but < GC default: would be STALL? if kill -0 were trusted blindly
once
kill "$NONOWNER" 2>/dev/null
idl_has '"state":"STALL?"'              && no "a recycled (non-owner) alive pid was paged STALL? (kill -0 trusted blindly)" || ok "recycled pid NOT paged STALL?"
idl_has '"kind":"page".*"state":"DEAD"' && ok "recycled-pid death routed to DEAD (owner-identity check)"                    || no "recycled pid not classified DEAD"

echo ""
echo "supervisor-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
