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
# V3 self-check OFF by default here (T31 opts back in, like CC_PAGE_TO/T9). It compares REAL live claude
# panes against the SANDBOX's telemetry dir, and this box legitimately runs ~30 panes against 1-2
# fixtures — a permanent artificial blind spot whose page would land in notify.log and corrupt every
# test that asserts on notify VOLUME (T9/T10/T18 caught exactly that). An unreachable tolerance is the
# off switch; T31 stubs `ps` so it can assert on an exact, fabricated delta instead.
export CC_SUP_PANE_DELTA_TOL=1000000

ALIVE=; cleanup(){ [ -n "$ALIVE" ] && kill "$ALIVE" 2>/dev/null; rm -rf "$SBX"; }
trap cleanup EXIT
sleep 600 & ALIVE=$!            # a genuinely-alive pid for the live-session fixtures

REPO="$SBX/repo"; mkdir -p "$REPO"
git -C "${REPO:?repo path required}" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
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
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  local r="${1:?mkrepo_landed: repo path required}"; rm -rf "$r"; mkdir -p "$r"
  git -C "${r:?repo path required}" init -q; git -C "$r" config user.email t@t; git -C "$r" config user.name t
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

echo "T9 role-file page fallback — empty CC_PAGE_TO ⇒ target resolved from CC_PAGE_TO_FILE at page time"
# effect-read through a capturing cc-notify stub: the page must reach the uuid in the role FILE.
# The stub RESOLVES `--role` exactly as the real cc-notify does (v3 D2 moved role→uuid resolution out
# of the supervisor and into cc-notify, so the supervisor now passes `--role <name>` + CC_ROLES_DIR
# instead of a locally-cat'd uuid). A stub pinned to "$1" would capture the flag, not the target, and
# report a routing failure that never happened — fixture shape must track the real producer's argv.
mkdir -p "$SBX/bin"; cat > "$SBX/bin/cc-notify" <<'STUB'
#!/bin/bash
target=""; role=""
while [ $# -gt 0 ]; do
  case "$1" in
    --role) role="$2"; shift 2 ;;
    --role=*) role="${1#--role=}"; shift ;;
    --from) shift 2 ;;
    --*) shift ;;
    *) [ -z "$target" ] && target="$1"; shift ;;
  esac
done
[ -n "$role" ] && target="$(head -n1 "${CC_ROLES_DIR:-$HOME/.claude/cc-roles}/$role" 2>/dev/null | tr -d '[:space:]')"
# Capture is OPTIONAL (`:-/dev/null`, not `:?`): the stub is now the sandbox-wide default cc-notify, so
# tests that page without asserting on the capture must not make it fail — a stub that errors would be
# read by send_page's rc check as "the transport refused it" and change the very behaviour under test.
printf '%s\n' "$target" >> "${CC_NOTIFY_CAPTURE:-/dev/null}"
# CONTRACT (2026-07-31): send_page now PARSES the `verdict=` token and treats rc alone as
# insufficient — the real cc-notify exits 0 while reporting `verdict=mailbox-only
# reason=target-not-live`, which is how a page sat undelivered for 15.2 h. This stub must therefore
# speak the verdict too, or every page it fakes reads as undelivered. Verified against the real
# binary: a live target emits `verdict=delivered`.
# CC_NOTIFY_STUB_VERDICT lets a test script the DELIVERY outcome independently of the exit code —
# the same attempt/outcome split the rc knob already provides for T29.
echo "cc-notify: verdict=${CC_NOTIFY_STUB_VERDICT:-delivered} target=$target" >&2
# The ATTEMPT is captured above, then the scripted rc decides the OUTCOME — that split is what lets
# T29 count re-attempts of a page the transport refused. Default 0 keeps every other test unchanged.
exit "${CC_NOTIFY_STUB_RC:-0}"
STUB
chmod +x "$SBX/bin/cc-notify"
# HERMETICITY (2026-07-25): export it for the WHOLE suite, not per-invocation. The supervisor resolves
# cc-notify beside-script (repo bin/) BEFORE PATH, so any sweep that pages with a real role file and no
# override reaches the LIVE cc-notify → cc-sessions → `it2 session list`. T23-T26 (added later, for the
# registered-desk exemption) each did exactly that: with the iTerm2 API wedged, the it2 call never
# returns and the sweep — and the whole gate behind it — hangs indefinitely. Observed twice, both runs
# parked at the same test. A per-test override is a rule every future test must remember; a suite-wide
# export is one that cannot be forgotten.
export CC_NOTIFY_BIN="$SBX/bin/cc-notify"
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

echo "T22b SAME-SWEEP GUARD — a page created THIS sweep is never same-sweep resolved (second-boundary race: page at X.99s, resolve at X+1.00s reads deadline-passed → phantom ESCALATE, the 2026-07-25 flaky-gate incident)"
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json "$SBX/notify.log" "$REPO/osc.txt"   # T22's osc.txt can share the page-stamp second ⇒ false-fresh ⇒ VOID not ESCALATE
mktel osc2 40 100 "$ALIVE" "$REPO"
# DEADLINE_S=0 forces what the integer-second race produces sporadically: the deadline reads as
# already-passed in the very sweep that created the page. Pre-guard: page + same-sweep ESCALATE
# (2 notifies, the flake). Post-guard: the deadline clock starts AT the page; re-observe belongs
# to a LATER sweep (deadline ≥ sweep interval in prod).
CC_SUP_PAGE_DEADLINE_S=0 CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
[ "$(wc -l < "$SBX/notify.log")" -eq 1 ] && ok "first sweep: page only — no same-sweep escalate" || no "same-sweep escalate leaked (lines=$(wc -l < "$SBX/notify.log")) — the second-boundary race"
# a LATER sweep still escalates (re-observe intact — the guard defers, never drops, the disposition)
CC_SUP_PAGE_DEADLINE_S=0 CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1
{ [ "$(wc -l < "$SBX/notify.log")" -eq 2 ] && idl_has '"kind":"page_escalate","sid":"osc2"'; } && ok "next sweep past deadline ⇒ ESCALATED (disposition deferred, not lost)" || no "deadline escalation lost after the guard (lines=$(wc -l < "$SBX/notify.log"); escalate-idl=$(idl_has '"kind":"page_escalate","sid":"osc2"' && echo yes || echo no))"

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

echo "T29 SEND-RC HONORED — a cc-notify-REFUSED page is IDL-loud and RETRIED, never damping-marked (comms truthfulness)"
# The defect: send_page `|| true`'d the cc-notify call and always returned 0, so page() wrote the
# .notified damping marker for a send the transport REFUSED (rc 3 unresolvable / rc 5 unwritable
# inbox). The page was then damped forever — the supervisor's ONE operator-facing act, silent for the
# life of the incident, while the IDL showed a page. An ATTEMPT is not a send.
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json "$SBX/notify.log" "$CC_SUPERVISOR_PAGEDIR"/*.notified
rm -rf "$CC_SUPERVISOR_PAGEDIR/damp"                              # fresh D7 state for this scenario
sendrc(){ CC_NOTIFY_STUB_RC="$1" CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" \
          CC_NOTIFY_BIN="$SBX/bin/cc-notify" bash "$SUP" --once >/dev/null 2>&1; }
ncap(){ wc -l < "$SBX/notify.log" 2>/dev/null | tr -d ' '; }
mktel refused 40 100 99999999 "$REPO"                             # pid gone + unlanded cwd ⇒ DEAD ⇒ page every sweep
sendrc 3                                                          # sweep 1 — the transport refuses it
[ -f "$CC_SUPERVISOR_PAGEDIR/refused.notified" ] && no "a REFUSED send wrote the damping marker (page damped out of existence)" || ok "refused send leaves NO damping marker"
idl_has '"kind":"page_send_failed"' && ok "refused send is IDL-recorded (never silent)"                || no "refused send left no IDL record (silent failure)"
sendrc 3                                                          # sweep 2 — must RE-ATTEMPT, not stay damped
[ "$(ncap)" -eq 2 ] && ok "refused page RETRIED on the next sweep (D7 marker dropped, not burned)"     || no "refused page was not retried (attempts=$(ncap), expected 2)"
sendrc 0                                                          # sweep 3 — channel recovers ⇒ a CONFIRMED enqueue
[ -f "$CC_SUPERVISOR_PAGEDIR/refused.notified" ] && ok "a CONFIRMED (rc 0) send DOES record the marker" || no "a confirmed send did not record the damping marker"
[ "$(ncap)" -eq 3 ] && ok "the recovered send went out exactly once"                                    || no "recovered send count wrong (attempts=$(ncap), expected 3)"
sendrc 0                                                          # sweep 4 — same state, now genuinely sent ⇒ quiet
[ "$(ncap)" -eq 3 ] && ok "DISCRIMINATES: confirmed⇒damped vs refused⇒retried (damping intact, only the lie removed)" || no "damping broke after a confirmed send (attempts=$(ncap), expected 3)"

echo "T30 BOUNDED EXTERNALS — a HUNG external fork must not end all supervision (audit root cause 4, S1)"
# The defect: zero timeout guards anywhere. The sweep loop is STRICTLY SEQUENTIAL, so one fork that never
# returns stops every later sweep FOREVER — and silently, because the pager is the thing that hung (the
# observed −9 last-exit with 0-byte logs). These checks are RED-provable: run each against the pre-fix
# tree and the outer bound below expires instead of the inner one.
#
# Method: PATH-inject a hanging `git` / `find` (the two hang classes the finding names) ahead of the real
# ones, then assert the sweep still COMPLETES and still writes its S-4 heartbeat. The outer `timeout` is
# the test's own escape hatch — WITHOUT the fix the inner call never returns, the outer bound cuts the
# sweep, no heartbeat is written, and every assertion below fails. It is never the thing being asserted.
HANGBIN="$SBX/hangbin"; mkdir -p "$HANGBIN"
printf '#!/bin/bash\nexec sleep 600\n' > "$HANGBIN/git";  chmod +x "$HANGBIN/git"
printf '#!/bin/bash\nexec sleep 600\n' > "$HANGBIN/find"; chmod +x "$HANGBIN/find"
# resolve a real timeout(1) for the OUTER test bound the same way the subject does (launchd PATH excludes
# Homebrew). No timeout(1) at all ⇒ SKIP rather than hang the gate or fake a pass.
TMO=""; for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
                  /opt/homebrew/bin/timeout /usr/local/bin/timeout /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
  [ -n "$_c" ] && [ -x "$_c" ] && { TMO="$_c"; break; }
done
if [ -z "$TMO" ]; then
  echo "  ⊘ SKIP T30 — no timeout(1) on this box (the subject degrades to unbounded by design; nothing to prove)"
else
  # ── T30a: a hung `git` (work_landed's 5 calls + the effects re-read) does not wedge the sweep ──
  reset; rm -f "$CC_TELEMETRY_DIR"/*.json
  mktel hunggit 40 2 999999 "$REPO"                       # pid gone ⇒ DEAD path ⇒ work_landed forks git
  "$TMO" -k 3 25 env PATH="$HANGBIN:$PATH" CC_SUP_GIT_TIMEOUT_S=1 CC_SUP_CKPT_TIMEOUT_S=1 \
      bash "$SUP" --once >/dev/null 2>&1; rc30a=$?
  [ "$rc30a" -ne 124 ] && ok "sweep COMPLETES with a hung git (bounded; pre-fix this never returns)" \
                       || no "sweep hung on a hung git (rc 124 at the outer bound — the S1 is not fixed)"
  idl_has '"kind":"heartbeat"' && ok "S-4 heartbeat still written despite the hung git (supervision survived)" \
                               || no "no heartbeat after a hung git — the sweep died silently"
  # A git we could not run must never read as "landed": that would reap a live session's row as a clean
  # completion. Unprovable ⇒ PAGE is the safe direction, and the row must survive.
  idl_has '"kind":"reap"' && no "a CUT git read as clean+landed and REAPED the row (unprovable must never mean landed)" \
                          || ok "cut git does NOT satisfy work_landed (no false clean-completion reap)"

  # ── T30b: a hung `find` in the effects re-read yields the INDETERMINATE third state, never an escalate ──
  # Folding a cut probe into `dark` would let a slow-but-healthy repo manufacture the escalation this
  # protocol exists to prevent; folding it into `fresh` would exonerate a genuinely hung lead. Neither is
  # observed, so neither is claimed. Only `find` hangs here — git must stay real so the verdict reaches
  # the find step at all (a hung git would short-circuit to unknown before find is ever called).
  reset; rm -f "$CC_TELEMETRY_DIR"/*.json "$CC_SUPERVISOR_PAGEDIR"/*.notified
  mktel indet 40 100 "$ALIVE" "$REPO"                     # alive OWNER + stale ⇒ STALL? candidate
  # Pre-stamp the page and let the deadline pass (the T7 pattern) — assess()'s SAME-SWEEP GUARD only
  # resolves a page that ALREADY existed when the sweep started, so a two-sweep dance would need reset()
  # to preserve the .page file it deliberately deletes. Stamp = NOW, which is newer than $REPO's only
  # commit, so the git leg reads not-fresh and the verdict reaches the (hung) find leg.
  printf '%s' "$(date +%s)" > "$CC_SUPERVISOR_PAGEDIR/indet.page"
  sleep 2                                                 # the 1s deadline passes ⇒ resolve_page re-observes
  "$TMO" -k 3 25 env PATH="$HANGBIN:$PATH" CC_SUP_FIND_TIMEOUT_S=1 \
      bash "$SUP" --once >/dev/null 2>&1; rc30b=$?
  [ "$rc30b" -ne 124 ] && ok "sweep COMPLETES with a hung find (the admitted ~5-min walk is now bounded)" \
                       || no "sweep hung on a hung find (rc 124 — the -prune mitigation is not a bound)"
  idl_has '"kind":"page_indeterminate"' && ok "a CUT effects re-read records the INDETERMINATE non-verdict" \
                                        || no "cut re-read left no page_indeterminate record"
  idl_has '"kind":"page_escalate"' && no "a CUT re-read ESCALATED (an unobserved state was treated as dark — silence-reap)" \
                                   || ok "cut re-read does NOT escalate (never acts on an unobserved state)"
  idl_has '"why":"fresh-effects-after-deadline"' && no "a CUT re-read was logged as FRESH effects (the audit trail lies)" \
                                                 || ok "cut re-read is not laundered as fresh (honest record)"

  # ── T30c: NO timeout(1) ⇒ UNBOUNDED, never BROKEN (the fail-closed-as-amplifier trap) ──
  # If a missing timeout binary turned `git` into rc 127, work_landed could never prove a clean
  # completion and the supervisor would page on every healthy landed session. The wrapper must degrade to
  # running the command directly. Proven POSITIVELY: with the seam emptied, a genuinely landed worktree
  # must still be auto-reaped — the outcome that requires all 5 git calls to actually run.
  reset; rm -f "$CC_TELEMETRY_DIR"/*.json
  LANDED="$SBX/repo-landed-t30"; mkrepo_landed "$LANDED"
  mktel nobin 40 2 999999 "$LANDED"                       # dead pid + shipped+clean ⇒ clean-completion reap
  CC_SUP_TIMEOUT_BIN='' bash "$SUP" --once >/dev/null 2>&1  # set-but-EMPTY = disable the wrap verbatim
  tel_exists nobin && no "no-timeout-binary broke git (row not reaped — a missing bound must not fail the call)" \
                   || ok "no timeout(1) ⇒ commands run UNBOUNDED, not broken (clean completion still reaped)"
  idl_has '"kind":"reap"' && ok "work_landed still proves landed with the wrap disabled (5 git calls ran)" \
                          || no "work_landed could not prove landed without timeout(1)"
fi

echo "T31 V3 SELF-CHECK — live panes OUTSIDE the telemetry world-view must page, damped (audit V3)"
# The blind spot: every pager path here iterates $TEL_DIR, whose only writer is the statusline (it stops
# emitting on a backgrounded/long-turn pane) and which lives in reboot-cleared /tmp. So the world can be
# EMPTY while sessions are live, and an empty world emits a CLEAN all-clear heartbeat — identical to a
# genuinely quiet fleet. `ps` is stubbed to report a fixed number of interactive claude panes, so the
# delta is exact and the assertions do not depend on what is really running on this box.
reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json "$SBX/notify.log" "$CC_SUPERVISOR_PAGEDIR"/selfcheck.state
rm -rf "$CC_SUPERVISOR_PAGEDIR/damp"
PSBIN="$SBX/psbin"; mkdir -p "$PSBIN"
mkps(){ # $1=how many interactive claude panes `ps` should report
  { echo '#!/bin/bash'
    echo 'case " $* " in *" -wwEo "*) : ;; *) exec /bin/ps "$@" ;; esac'   # only the self-check form is faked
    echo "for i in \$(seq 1 $1); do echo '/Users/x/.claude-versions/2.1.219/claude --model opus'; done"
  } > "$PSBIN/ps"; chmod +x "$PSBIN/ps"; }
selfsweep(){ CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" \
             CC_NOTIFY_BIN="$SBX/bin/cc-notify" CC_SUP_PANE_DELTA_TOL=0 PATH="$PSBIN:$PATH" \
             bash "$SUP" --once >/dev/null 2>&1; }
# Count SENDS, not message text: the shared cc-notify stub captures the resolved TARGET only (one line
# per attempt), which is what T9/T10/T18/T29 already assert on — so a content grep here could never
# match, and widening that fixture for this one test would touch four others. Attribution comes from the
# fixture instead: these sweeps run against an EMPTY telemetry dir, so no DEAD/STALL?/PAST-THRESHOLD page
# is reachable and every captured line IS a self-check page. The `"kind":"selfcheck_page"` IDL assertions
# below pin the identity independently.
# The `-f` guard is load-bearing: `< missing-file` fails in the SHELL before wc runs, so `2>/dev/null`
# on wc cannot suppress it — the redirect error would print on every no-sends assertion.
scap(){ local n=0
  [ -f "$SBX/notify.log" ] && { n=$(wc -l < "$SBX/notify.log" 2>/dev/null) || n=0; }
  printf '%s' "$(( ${n:-0} + 0 ))"; }

mkps 3                                                            # 3 live panes, 0 telemetry rows ⇒ Δ3, fully blind
selfsweep                                                         # sweep 1 — must NOT page yet (persistence gate)
[ "$(scap)" -eq 0 ] && ok "Δ does not page on its FIRST sweep (a pane spawned mid-sweep is not a blind spot)" \
                    || no "self-check paged on sweep 1 (persistence gate missing — races will page)"
selfsweep                                                         # sweep 2 — persisted ⇒ page
[ "$(scap)" -eq 1 ] && ok "a PERSISTED blind spot pages exactly once (Δ3 live vs 0 enumerated)" \
                    || no "persisted blind spot did not page once (sends=$(scap))"
idl_has '"kind":"selfcheck_page"' && ok "self-check page is IDL-recorded (S-4 auditable)" \
                                  || no "self-check page left no IDL record"
selfsweep                                                         # sweep 3 — SAME delta ⇒ damped
[ "$(scap)" -eq 1 ] && ok "an unchanged blind spot stays DAMPED (no per-sweep composer storm)" \
                    || no "standing blind spot re-paged every sweep (sends=$(scap) — the 07-19 storm)"
mkps 5; selfsweep                                                 # WORSENED (Δ3→Δ5) ⇒ breaks through
[ "$(scap)" -eq 2 ] && ok "a WORSENING blind spot breaks through the damping (Δ3→Δ5)" \
                    || no "worsening delta stayed damped (sends=$(scap)) — damping hides escalation"
# RECOVERY: the statusline resumes / telemetry repopulates ⇒ enumerated catches up ⇒ silence + re-arm.
reset; rm -f "$CC_TELEMETRY_DIR"/*.json
mkps 2; mktel sc1 40 2 "$ALIVE" "$REPO"; mktel sc2 40 2 "$ALIVE" "$REPO"   # 2 live, 2 enumerated ⇒ Δ0
selfsweep
[ "$(scap)" -eq 2 ] && ok "Δ0 does not page (a fully-visible fleet is silent)" \
                    || no "self-check paged with no blind spot (sends=$(scap) — false alarm)"
idl_has '"kind":"selfcheck_page"' && no "Δ0 emitted a selfcheck_page (false alarm in the ledger)" \
                                  || ok "no selfcheck_page in the IDL for a visible fleet"
# ABSTAIN, never a phantom Δ: an unreadable `ps` yields no count, so there is no verdict to page on.
# (`enum` is real here, so treating an empty count as 0 would compute a NEGATIVE delta and, worse, a
# broken `ps` on a busy box would read as "everything is visible" — a silent detector failure.)
reset; rm -f "$CC_TELEMETRY_DIR"/*.json "$SBX/notify.log"
printf '#!/bin/bash\nexit 1\n' > "$PSBIN/ps"; chmod +x "$PSBIN/ps"
selfsweep
[ "$(scap)" -eq 0 ] && ok "an unreadable ps ABSTAINS (no count ⇒ no verdict, never a phantom page)" \
                    || no "broken ps produced a self-check page (a non-observation was treated as data)"
idl_has '"kind":"heartbeat"' && ok "the sweep still completes and heartbeats with ps unreadable" \
                             || no "a broken ps broke the sweep"
rm -rf "$PSBIN"                                                   # never leave the stub on PATH for later tests

echo "T32 DESK-LESS DELIVERY — no desk registered is a SUPPORTED configuration, not a permanent failure"
# The 2026-08-01 incident: this machine runs no desk orchestrator, com.claude.desk-invariant (the only
# organ that can create one) is not loaded, and cc-roles/desk still names a self-closed iTerm2 pane whose
# .forward successor is equally dead. So every page returns rc 0 + verdict=mailbox-only FOREVER.
# e6d789a8 routed every non-delivered verdict down the failure path, which damp_forgets the marker so the
# next sweep re-sends — measured 8,025 `page SEND FAILED` lines and up to 1,519 OS notifications in one
# hour, 14 per 30 s sweep. The fix splits RECORDED (enqueued, no live reader — the desk-less steady
# state, delivered on the liveness-free channel and DIGESTED) from REFUSED (rc != 0, nothing took it —
# still retried, T29's law). These assertions are the discriminator: pre-fix, the send counts below
# grow every sweep and the notification count tracks the FINDING count.
#
# NOTE the fixture shape: CC_NOTIFY_STUB_VERDICT=mailbox-only is what makes this the desk-less case —
# the rest of this suite runs the stub's default `delivered`, i.e. the live-desk case, which must stay
# untouched. osascript is stubbed on PATH so the suite never posts a real notification (the pre-fix
# code would have posted one per finding, on the operator's actual desktop, during every gate run).
OSBIN="$SBX/osabin"; mkdir -p "$OSBIN"
# A quoted heredoc, not `echo` lines: the stub body carries both a `$` expansion and a `\n`, which
# `echo` has shellcheck flagging (SC2016/SC2028) and which some shells would expand for real.
cat > "$OSBIN/osascript" <<'OSASTUB'
#!/bin/bash
printf '%s\n' "post" >> "${CC_OSA_CAPTURE:-/dev/null}"
exit 0
OSASTUB
chmod +x "$OSBIN/osascript"
ocap(){ local n=0
  [ -f "$SBX/osa.log" ] && { n=$(wc -l < "$SBX/osa.log" 2>/dev/null) || n=0; }
  printf '%s' "$(( ${n:-0} + 0 ))"; }
ndreset(){ reset; permreset; rm -f "$CC_TELEMETRY_DIR"/*.json "$SBX/notify.log" "$SBX/osa.log" \
             "$CC_SUPERVISOR_PAGEDIR"/*.notified "$CC_SUPERVISOR_PAGEDIR/digest.pending" 2>/dev/null; rm -rf "$CC_SUPERVISOR_PAGEDIR/damp"; }
ndsweep(){ # the desk-less case: enqueued to a box with no live reader
  CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" \
  CC_NOTIFY_STUB_VERDICT=mailbox-only CC_OSA_CAPTURE="$SBX/osa.log" PATH="$OSBIN:$PATH" \
  bash "$SUP" --once >/dev/null 2>&1; }

ndreset; mktel nd1 40 2 999991 "$REPO"                            # pid gone + unlanded ⇒ a DEAD page
ndsweep
[ "$(scap)" -eq 1 ] && ok "a desk-less page is still RECORDED to the mailbox (it survives for a desk registered later)" \
                    || no "desk-less page not enqueued (sends=$(scap))"
[ "$(ocap)" -eq 1 ] && ok "…and the operator IS reached, on the channel with no liveness dependency" \
                    || no "nobody was reached in the desk-less case (posts=$(ocap))"
ndsweep                                                            # same state, next sweep
[ "$(scap)" -eq 1 ] && ok "an unchanged RECORDED page is NOT re-sent every sweep (the 8,025-line storm)" \
                    || no "RECORDED page re-sent (sends=$(scap)) — storm regression"
[ "$(ocap)" -eq 1 ] && ok "…and no second notification for news that has not changed" \
                    || no "notification re-posted for unchanged state (posts=$(ocap))"

# DIGEST: the volume knob. 14 findings a sweep must cost ONE notification, not 14.
ndreset
mktel nda 40 2 999992 "$REPO"; mktel ndb 40 2 999993 "$REPO"; mktel ndc 40 2 999994 "$REPO"
ndsweep
[ "$(scap)" -eq 3 ] && ok "three findings ⇒ three mailbox records (no finding is dropped)" \
                    || no "findings lost on the mailbox path (sends=$(scap))"
[ "$(ocap)" -eq 1 ] && ok "…but exactly ONE notification for the sweep (digested, never one-per-finding)" \
                    || no "one notification PER FINDING (posts=$(ocap)) — the 14-per-sweep storm"
# Asserted HERE and not at the end of T32: ndreset truncates the IDL, and the CC_SUP_OS_CHANNEL=off
# block below deliberately posts nothing — so an end-of-block check would read the absence of a
# record this sweep genuinely wrote and call it a missing one. Audit the claim against the sweep
# that made it.
idl_has '"kind":"page_digest"' && ok "the digest is IDL-recorded (S-4: the delivery claim is itself a record)" \
                               || no "digest left no IDL record"
ndsweep
[ "$(ocap)" -eq 1 ] && ok "an unchanged cause set stays quiet across sweeps" \
                    || no "digest re-posted unchanged news (posts=$(ocap))"
# …and a genuinely NEW cause class must still break through the damping on the next sweep.
mkbeacon ndperm 10 Bash '{"command":"blocked on a prompt"}'
ndsweep
[ "$(ocap)" -eq 2 ] && ok "a NEW cause class (permission-pending) breaks through the digest damping" \
                    || no "new cause class stayed damped (posts=$(ocap)) — damping hiding escalation"

# REFUSED is the OTHER class and keeps T29's law: nothing took the page ⇒ no marker ⇒ genuine retry.
ndreset; mktel ndr 40 2 999995 "$REPO"
for _i in 1 2; do
  CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" \
  CC_NOTIFY_STUB_RC=3 CC_OSA_CAPTURE="$SBX/osa.log" PATH="$OSBIN:$PATH" \
  bash "$SUP" --once >/dev/null 2>&1
done
[ "$(scap)" -ge 2 ] && ok "a transport-REFUSED page is still RETRIED next sweep (T29's law intact)" \
                    || no "refused page was not retried (sends=$(scap)) — regression on 60b28d8c/e6d789a8"

# NO liveness-free channel at all ⇒ RECORDED must NOT be laundered as handled; it reverts to retry.
# A capability we cannot use must never be assumed present (this is why the seam exists — a suite
# cannot un-find /usr/bin/osascript via PATH, so without it this branch would ship unproven).
ndreset; mktel ndo 40 2 999996 "$REPO"
for _i in 1 2; do
  CC_NOTIFY_CAPTURE="$SBX/notify.log" CC_PAGE_TO_FILE="$SBX/desk-role" CC_NOTIFY_BIN="$SBX/bin/cc-notify" \
  CC_NOTIFY_STUB_VERDICT=mailbox-only CC_SUP_OS_CHANNEL=off CC_OSA_CAPTURE="$SBX/osa.log" PATH="$OSBIN:$PATH" \
  bash "$SUP" --once >/dev/null 2>&1
done
[ "$(scap)" -ge 2 ] && ok "with NO liveness-free channel, a RECORDED page retries (never silently 'handled')" \
                    || no "RECORDED laundered as delivered with no channel (sends=$(scap)) — silent page loss"
[ "$(ocap)" -eq 0 ] && ok "…and nothing is posted to a channel that is switched off" \
                    || no "posted despite CC_SUP_OS_CHANNEL=off (posts=$(ocap))"

# The operator must be able to read WHY from the log, not infer it — the desk-less state is named.
grep -q 'page RECORDED (no live desk)' "$CC_SUPERVISOR_LOG" 2>/dev/null \
  && ok "the log names the desk-less state explicitly (not a bare 'SEND FAILED')" \
  || no "desk-less state not named in the supervisor log"
grep -q 'digest POSTED' "$CC_SUPERVISOR_LOG" 2>/dev/null \
  && ok "the digest post is auditable in the supervisor log" \
  || no "no digest record in the supervisor log"
rm -rf "$OSBIN"                                                   # never leave the stub on PATH

echo ""
echo "supervisor-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
