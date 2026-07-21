#!/bin/bash
# lead-supervisor.sh — out-of-session (bash) watchdog for multi-day UNWATCHED autonomy runs.
#
# ── RULING #1 (operator, 2026-07-14): it PAGES, never auto-recovers. ──
# It DETECTS + CHECKPOINT-preserves (pure insurance) + PAGES. The operator, or a delegated *live*
# session, performs any respawn/close. It is bash and cannot call in-session tools, so it PHYSICALLY
# CANNOT improvise a close on a live pane — and it must not try. The only auto-*acts* are the safe,
# effect-verified ones (checkpoint-preserve of a confirmed-DEAD lead's worktree); every *recovery* is paged.
#
# ── WHAT IT STRUCTURALLY CANNOT SEE (blind-check pre-mortem, audit §3i / blueprint §3.3) ──
# S-3  It cannot see IN-SESSION state AT ALL — MODAL dialogs, the composer, mid-turn reasoning are
#      invisible to an out-of-session bash sweep. This is STRUCTURAL blindness, not a policy gap: it
#      cannot be fixed by a better rule. So a suspected MODAL (a live pane emitting nothing, no work-
#      products) is PAGED, never actioned — the supervisor declares the blindness instead of papering it.
# S-3b The page path encodes deadline → RE-OBSERVATION, NEVER action on silence. reply-compliance is
#      NOT a liveness signal (a busy lead ignores pages). At a page deadline the supervisor does a fresh
#      effects-dark RE-READ; disposition (escalate) gates on THAT, never on the silence. Proven load-
#      bearing by the first live stall-page cycle (§3h): a lead ran dark 69-75m, the deadline expired with
#      no reply, and the mandatory re-read found it ALIVE + productive. Silence-reap would have killed it.
# S-4  Every sweep emits a heartbeat/outcome record to the IDL — a sweep that finds nothing records THAT
#      IT LOOKED. "Who watches the watcher": the watcher's heartbeat is an outcome record; its ABSENCE
#      is the alarm. A silently-crashed daemon must not be indistinguishable from a quiet system.
# B-1  It independently covers a session PAST-THRESHOLD ∧ NOT-STOPPING — the exact case the boundary hook
#      is blind to (the hook fires on Stop; a session hung/working-past-boundary never Stops).
#
# Modes:  --once  one sweep then exit (cron/test) · --daemon  loop (default) · --selftest  prove the logic.
# Env seams: CC_TELEMETRY_DIR · CC_IDL · CC_SUPERVISOR_LOG · CC_PAGE_TO · CC_SUP_T · CC_SUP_STALL_S ·
#            CC_SUP_PAGE_DEADLINE_S · CC_SUP_TRUNK · CC_SUP_GC_S · CC_SUP_OWNER_PAT · CC_PAGE_TO_FILE ·
#            CC_REGISTRY_DIR · SUPERVISOR_SWEEP_MAX_S · SUPERVISOR_SWEEP
set -uo pipefail

# The sweep interval SHARES reaper-horizon-lint's constant — never fork the number (invariant 7; the
# horizon floor is 10× this, enforced there). The actual daemon loop may be faster, never slower.
SUPERVISOR_SWEEP_MAX_S="${SUPERVISOR_SWEEP_MAX_S:-600}"
SWEEP="${SUPERVISOR_SWEEP:-30}"
[ "$SWEEP" -le "$SUPERVISOR_SWEEP_MAX_S" ] 2>/dev/null || SWEEP="$SUPERVISOR_SWEEP_MAX_S"

T="${CC_SUP_T:-73}"                                    # past-threshold (used_pct) — the B-1 boundary
STALL_S="${CC_SUP_STALL_S:-1800}"                      # telemetry age past which a live pid is a STALL? candidate
DEADLINE_S="${CC_SUP_PAGE_DEADLINE_S:-900}"            # page deadline before the re-observe (15m default)
TRUNK="${CC_SUP_TRUNK:-origin/main}"                   # trunk for the clean-completion landed-check (cf. cc-classify CC_CLASSIFY_TRUNK)
GC_S="${CC_SUP_GC_S:-21600}"                           # telemetry age past which a LIVE-OWNER row is GC'd — a hung/pid-recycled owner would STALL?-escalate every sweep forever (item fdc101e8b0c7). reaper-horizon-lint bounds this ≥ SUPERVISOR_SWEEP_MAX_S×10; default 6h = 12× STALL_S.
OWNER_PAT="${CC_SUP_OWNER_PAT:-claude}"               # a live pid OWNS its telemetry row only if its process command matches this — kill -0 alone reads a RECYCLED pid as the original session (the STALL? zombie)
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SUPLOG="${CC_SUPERVISOR_LOG:-$HOME/.claude/autonomy/supervisor.log}"
PAGEDIR="${CC_SUPERVISOR_PAGEDIR:-$HOME/.claude/autonomy/pages}"
PAGE_TO="${CC_PAGE_TO:-}"                              # EXPLICIT pane override (CC_PAGE_TO wins over the role)
PAGE_TO_FILE="${CC_PAGE_TO_FILE:-$HOME/.claude/cc-roles/desk}"   # the ROLE file cc-notify --role resolves (/dev/null disables)
# D7 send-damping state beside this pager's own state, so it inherits the CC_SUPERVISOR_PAGEDIR test
# isolation seam. Lives in a `damp/` SUBDIR: autonomy-sweep globs "$PAGES_DIR"/*.page at the top level
# only, so damp markers can never be mistaken for page records and wake the desk.
CC_PAGE_DAMP_DIR="${CC_PAGE_DAMP_DIR:-$PAGEDIR/damp}"
# cc-registry maps paneUUID → session_id (single shared dir across accounts). Bridges the desk role file
# (which holds a PANE uuid) to a telemetry session_id for the registered-desk STALL? exemption (item ff95faea46c8).
REGISTRY_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
# ── PermissionRequest beacon (hooks/cc-permission-beacon.sh) — desk-anti-hitl §B2 ──
# A permission prompt on an unattended session HANGS (nothing in-session can answer). The MODAL is
# invisible to this bash sweep (S-3), but the HARNESS-emitted beacon at PERMPEND_DIR/<sid>.json IS
# readable → a precise "PERMISSION-PENDING: <cmd>" page instead of a slow, detail-free STALL?/MODAL.
PERMPEND_DIR="${CC_PERMPEND_DIR:-/tmp/cc-permission-pending}"   # MUST match the hook's default + seam
PERMPEND_NOTICE_S="${CC_PERMPEND_NOTICE_S:-120}"      # page a prompt pending ≥ this (auto-approved tools clear in ms ⇒ no false page)
PERMPEND_HORIZON_S="${CC_PERMPEND_HORIZON_S:-86400}"  # reap an orphaned beacon past this (hard-kill w/o SessionEnd + no telemetry)
# cc-notify must resolve under launchd's bare default PATH (/usr/bin:/bin:...) — env override →
# beside-script repo bin → ~/.claude/bin → PATH (the autonomy-sweep resolve_bin order)
NOTIFY_BIN="${CC_NOTIFY_BIN:-}"
if [ -z "$NOTIFY_BIN" ]; then
  for _c in "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/bin/cc-notify" "$HOME/.claude/bin/cc-notify" "$(command -v cc-notify 2>/dev/null || true)"; do
    [ -n "$_c" ] && [ -x "$_c" ] && { NOTIFY_BIN="$_c"; break; }
  done
fi
# D7 send-damping (best-effort: absent lib ⇒ undamped, i.e. today's behaviour, never a lost page).
for _c in "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/hooks/lib/page-damp.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh" "$HOME/.claude/hooks/lib/page-damp.sh"; do
  # shellcheck disable=SC1090,SC1091
  [ -f "$_c" ] && { . "$_c" 2>/dev/null || true; break; }
done

# ── the ONE send path for every supervisor page (v3 D2/D7) ───────────────────────────────────────
# ROLE-addressed by default: cc-notify resolves the role file at send time AND follows a `.forward`
# chain / reroutes a dead target — none of which a locally-cat'd uuid can do. Role name + dir are
# DERIVED from PAGE_TO_FILE (dirname → CC_ROLES_DIR, basename → role), so every existing seam keeps
# working unchanged (default → cc-roles/desk; the E2E's custom path → its own dir; /dev/null → not a
# regular file ⇒ no send). CC_PAGE_TO still forces one explicit pane.
# Returns 0 = a send was ATTEMPTED (caller records its own damping marker) · 1 = no channel wired
# (marker NOT recorded, so a later-wired channel still gets its first notify — the pre-existing rule).
send_page(){ # $1=message [$2=state-fingerprint]
  local msg="$1" fp="${2:-}" target rdir rname
  [ -n "$NOTIFY_BIN" ] || return 1
  # resolved only to GATE on "is a channel wired at all" — the ADDRESS used below is the role itself
  target="$PAGE_TO"; [ -n "$target" ] || target="$(head -n1 "$PAGE_TO_FILE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$target" ] || return 1
  if [ -n "$fp" ] && command -v damp_should_send >/dev/null 2>&1; then
    damp_should_send "${PAGE_TO:-role:$PAGE_TO_FILE}" "$fp" || return 0   # suppressed, but still "handled"
  fi
  if [ -n "$PAGE_TO" ]; then
    "$NOTIFY_BIN" "$PAGE_TO" "$msg" >/dev/null 2>&1 || true
  else
    rdir="$(dirname "$PAGE_TO_FILE")"; rname="$(basename "$PAGE_TO_FILE")"
    CC_ROLES_DIR="$rdir" "$NOTIFY_BIN" --role "$rname" "$msg" >/dev/null 2>&1 || true
  fi
  return 0
}

now(){ date +%s; }
utc(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
# JSON-encode an arbitrary string for safe embedding in an IDL line (quotes/backslashes/newlines) —
# never raw-%s a worker/command string into JSON (the malformed-IDL class, cc-backlog 666c6a64c45e).
json_str(){ jq -cn --arg s "${1:-}" '$s' 2>/dev/null || printf '""'; }
fmt_since(){ date -r "${1:-0}" +%H:%M 2>/dev/null || printf '%s' "${1:-?}"; }   # epoch → local HH:MM for the page
_ensure(){ mkdir -p "$(dirname "$IDL")" "$(dirname "$SUPLOG")" "$PAGEDIR" 2>/dev/null || true; }

# ── S-4: heartbeat — one IDL line PER SWEEP (even an all-clear one), plus per-finding records. ──
idl(){ # $1=kind  $2=json-body(no braces)
  _ensure; printf '{"ts":"%s","actor":"lead-supervisor","kind":"%s",%s}\n' "$(utc)" "$1" "$2" >> "$IDL" 2>/dev/null || true
}
heartbeat(){ # $1=n_swept $2=n_findings $3=n_gc(optional)
  idl heartbeat "\"swept\":$1,\"findings\":$2,\"gc\":${3:-0},\"sweep_s\":$SWEEP"
  printf '%s  swept=%s findings=%s gc=%s\n' "$(utc)" "$1" "$2" "${3:-0}" >> "$SUPLOG" 2>/dev/null || true
}

# ── PAGE — the only operator-facing act (besides safe checkpointing). Records a durable page + best-
#    effort cc-notify. NEVER reaps/closes anything. Deadline-stamped so resolve_page can re-observe. ──
page(){ # $1=sid $2=state $3=detail
  _ensure
  local pf="$PAGEDIR/$1.page" nf="$PAGEDIR/$1.notified"
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
  # composer damping: ONE notify per sid per STATE — a re-sweep of an already-notified state stays
  # IDL/mailbox-quiet; a state CHANGE (DEAD→ESCALATED) re-notifies (2026-07-19 page-storm fix: every
  # ~30s sweep re-notified every known-dead session, flooding the desk composer)
  local last; last="$(cat "$nf" 2>/dev/null || true)"
  [ "$last" = "$2" ] && return 0
  # ESCALATED is STICKY: the STALL?→ESCALATED pair re-fires every sweep for a zombie (stale telemetry
  # + reused pid), so equality damping alone still leaks 2 notifies/sweep — after an ESCALATED send,
  # only a genuine worsening to DEAD notifies again; the OK-branch clear_page resets the marker on a
  # true recovery, but a VOID keeps it (void_page, item 1c324d9fcc32) so a STALL?→void→re-STALL?
  # oscillation stays composer-damped — the stale-telemetry situation that triggered it still persists.
  [ "$last" = "ESCALATED" ] && [ "$2" != "DEAD" ] && return 0
  # Addressing resolves per page, not at startup (send_page): a pane rebind (role-file rewrite)
  # redirects pages with no plist edit and no daemon restart. D7 fingerprint = sid+state ONLY —
  # $3 (detail) carries volatile text that would change every sweep and silently defeat damping.
  if send_page "⚠️ SUPERVISOR PAGE — session $1 is $2: $3 (operator/delegated-live-session recovers; supervisor never auto-acts)" "page:$1:$2"; then
    printf '%s\n' "$2" > "$nf"                             # recorded only on an attempted send — a
  fi                                                       # later-wired channel still gets its first notify
}
clear_page(){ rm -f "$PAGEDIR/$1.page" "$PAGEDIR/$1.notified" 2>/dev/null || true; }
# ── void a page WITHOUT resetting the notify-damping marker (item 1c324d9fcc32). ──
# A VOID means "alive + working, no escalation" — NOT "incident cleared, re-arm the alarm". The
# telemetry-staleness that raised the STALL? still persists, so the very next sweep re-pages the SAME
# candidate; dropping .notified here (as clear_page does) let every STALL?→void→re-STALL? cycle re-notify
# the desk (one composer ping per DEADLINE_S — the idle-live oscillation). Reset only the deadline clock
# (.page); keep .notified so the ongoing situation stays damped until it genuinely CHANGES (DEAD/ESCALATED
# break through; a true recovery clears it via the OK-branch clear_page).
void_page(){ rm -f "$PAGEDIR/$1.page" 2>/dev/null || true; }

# ── PERMISSION-PENDING page — a SEPARATE namespace (.permpend.*) from the telemetry-liveness pages so
#    assess()'s clear_page (fired every sweep for a below-threshold session) can NEVER clobber it. A
#    prompt-blocked session has stale telemetry, so assess would otherwise clear a permpend page. ──
page_permpend(){ # $1=sid $2=cmd $3=beacon_ts $4=age_s
  _ensure
  local sid="$1" cmd="$2" ts="$3" age="$4" nf="$PAGEDIR/$1.permpend.notified"
  idl permission_pending "\"sid\":\"$sid\",\"since\":$ts,\"age_s\":$age,\"cmd\":$(json_str "$cmd")"
  # Composer damping: ONE notify per PENDING EPISODE (keyed by the beacon ts). A NEW prompt (new ts)
  # re-notifies; the SAME prompt across sweeps stays quiet. clear_permpend resets on resolution.
  local last; last="$(cat "$nf" 2>/dev/null || true)"
  [ "$last" = "$ts" ] && return 0
  # D7 fingerprint = the EPISODE (sid + beacon ts): a new prompt is a new ts ⇒ new fingerprint ⇒ sends.
  # ${age} is excluded — it grows every sweep and would defeat damping while looking wired.
  if send_page "⛔ PERMISSION-PENDING — session $sid blocked ${age}s on a permission prompt: ${cmd} (since $(fmt_since "$ts")). Nothing in-session can answer; operator/live-session must approve or deny." "permpend:$sid:$ts"; then
    printf '%s\n' "$ts" > "$nf"                             # recorded only on an attempted send
  fi
}
clear_permpend(){ rm -f "$PAGEDIR/$1.permpend.notified" 2>/dev/null || true; }

# ── effect RE-READ (S-3b core): is a session emitting WORK-PRODUCTS, independent of whether it replied? ──
# "fresh" = new commits OR worktree file mtimes OR a live cpu delta since the page. "dark" = none.
reobserve_effects(){ # $1=sid $2=cwd $3=since_epoch → prints "fresh" | "dark"
  local cwd="$2" since="$3" fresh=dark
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    # a commit after the page = unambiguous liveness
    local last_commit; last_commit="$(git -C "$cwd" log -1 --format=%ct 2>/dev/null || echo 0)"
    [ "${last_commit:-0}" -gt "$since" ] 2>/dev/null && fresh=fresh
    # any tracked/untracked file touched after the page = work in flight. Use `-newer <ref>` (portable);
    # BSD find rejects `-newermt @epoch` ("Can't parse date/time"), which would make EVERY re-read read
    # dark and escalate a healthy lead — the exact silence-reap this protocol exists to prevent.
    if [ "$fresh" = dark ]; then
      local ref; ref="$(mktemp 2>/dev/null)"
      if [ -n "$ref" ]; then
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
        [ -n "$(find "$cwd" -type f -newer "$ref" -not -path '*/.git/*' -print -quit 2>/dev/null)" ] && fresh=fresh
        rm -f "$ref"
      fi
    fi
  fi
  printf '%s' "$fresh"
}

# ── S-3b: at a page deadline, RE-OBSERVE; disposition (escalate) gates on the effects re-read ONLY. ──
resolve_page(){ # $1=sid $2=cwd
  local sid="$1" cwd="$2" pf="$PAGEDIR/$1.page"
  [ -f "$pf" ] || return 0
  local paged_at; paged_at="$(cat "$pf" 2>/dev/null || echo 0)"
  [ "$(( $(now) - ${paged_at:-0} ))" -ge "$DEADLINE_S" ] || return 0   # deadline not up yet — keep waiting
  # reply-compliance is NOT liveness: we do not read any reply. Only the fresh effects re-read decides.
  local effects; effects="$(reobserve_effects "$sid" "$cwd" "$paged_at")"
  if [ "$effects" = dark ]; then
    escalate_page "$sid" "$cwd"                 # effects-dark ⇒ disposition (never reached from silence alone)
  else
    idl page_void "\"sid\":\"$sid\",\"why\":\"fresh-effects-after-deadline\""   # alive + working ⇒ VOID
    void_page "$sid"                            # reset the deadline clock but KEEP notify damping (item 1c324d9fcc32)
  fi
}
escalate_page(){ # $1=sid $2=cwd — page LOUDER (still page-only; the operator recovers). Never a reap.
  idl page_escalate "\"sid\":\"$1\",\"detail\":\"effects-dark past deadline — operator action needed\""
  page "$1" ESCALATED "no work-products across the page deadline; supervisor re-read confirms dark (still not auto-acting)"
}

# ── safe insurance: checkpoint a confirmed-DEAD lead's worktrees before anyone removes them (D-B). ──
checkpoint_preserve(){ # $1=sid $2=cwd
  local cwd="$2"
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || true
  fi
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
}

# ── CLEAN-COMPLETION detection (item 9b183d78c723): is a dead worker's worktree shipped+clean? ──
# 0 IFF clean tree AND the branch's content is landed on trunk — mirrors cc-classify / cc-reaper
# work_landed and cc-teardown-safety-gate G-a (the codebase-canonical shipped+clean gate). P0-17
# landed-by-CONTENT (incident dfacccd): a squash/cherry-pick land (different sha, same content) leaves
# HEAD "N ahead" by COUNT though the work is durably on trunk, so a bare count check would strand a
# finished session forever. A missing / non-git / unresolved-trunk worktree returns 1 — we cannot PROVE
# it clean, so the caller PAGES (the safe direction); work is never silently reaped unless verified landed.
work_landed(){ # $1=cwd → 0 clean+landed, 1 otherwise
  local cwd="$1"
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 1
  git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || return 1
  [ -z "$(git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
  local ahead; ahead="$(git -C "$cwd" rev-list --count "$TRUNK"..HEAD 2>/dev/null)" || return 1
  [ "${ahead:-1}" = 0 ] && return 0                                 # fast path: 0 ahead by COUNT → landed
  # content path (squash/cherry-pick-tolerant): `git cherry` marks a HEAD commit '+' only when NO patch-id
  # equivalent is on trunk; zero '+' ⇒ every ahead commit is durably landed. tree-diff-0 = squash backstop.
  local cherry_out
  if cherry_out="$(git -C "$cwd" cherry "$TRUNK" HEAD 2>/dev/null)"; then
    printf '%s\n' "$cherry_out" | grep -q '^+' || return 0
  fi
  git -C "$cwd" diff --quiet "$TRUNK" HEAD 2>/dev/null && return 0
  return 1
}

# ── auto-reap a clean completion — the clean lifecycle end of a dispatched worker, NEVER a page. ──
# A dead worker whose worktree is shipped+clean left NOTHING stranded; the DEAD page exists to surface
# LOST/unlanded work, so this is a normal exit, not an incident. Reap = drop the telemetry row + clear any
# standing page/notify marker (autonomy/pages/<sid>.{page,notified}); recorded to the IDL (S-4 auditable —
# the reap is an outcome record, never a silent deletion).
reap_clean(){ # $1=sid $2=cwd
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
  rm -f "$TEL_DIR/$1.json" 2>/dev/null || true
  clear_page "$1"
  printf '%s  reap sid=%s (clean+landed — dispatched-worker lifecycle end)\n' "$(utc)" "$1" >> "$SUPLOG" 2>/dev/null || true
}

# ── transcript liveness (item 1c324d9fcc32): the session's own JSONL is appended on EVERY message / ──
# tool event, so its mtime is a FAR fresher liveness signal than telemetry `ts`. The telemetry writer is
# the statusline, which stops emitting when a pane is not actively rendering (statusline.sh:48 — "a
# session inside ONE long operation, or genuinely hung, renders ZERO times"): a healthy BACKGROUNDED /
# long-turn / idle-interactive session goes telemetry-stale for hours while its transcript stays warm
# (measured 2026-07-19: a live session at 3.5-DAY-stale telemetry with a 5-min-warm transcript). Prints
# the transcript's age in seconds; a huge sentinel when it cannot be resolved (no config_dir / missing
# file) so the caller treats "unprovable" as COLD — fail-safe: we never exempt a stall we cannot disprove.
transcript_age(){ # $1=cwd $2=config_dir $3=sid → prints age_s (999999999 = unresolved ⇒ cold)
  local cwd="$1" cfg="$2" sid="$3" slug tp mt
  { [ -n "$cwd" ] && [ -n "$cfg" ] && [ -n "$sid" ]; } || { printf '%s' 999999999; return; }
  slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'
  tp="$cfg/projects/$slug/$sid.jsonl"
  [ -f "$tp" ] || { printf '%s' 999999999; return; }
  mt="$(stat -f %m "$tp" 2>/dev/null || stat -c %Y "$tp" 2>/dev/null || echo 0)"   # BSD stat, then GNU fallback
  printf '%s' "$(( $(now) - ${mt:-0} ))"
}

# ── registered-desk identity (item ff95faea46c8): is this telemetry sid THE monitoring desk? ──
# The desk is a legitimately-idle MONITOR — it watches quietly between pages, so during a normal quiet
# window (30m+) its telemetry AND its transcript both go stale while the session is fully ALIVE (cc-reaper
# classifies it [active]; its pid is real, not reused). Telemetry-freshness is therefore a FALSE liveness
# proxy for the desk, and the warm-transcript exemption above cannot save it — an idle monitor emits no
# transcript messages between pages either, so BOTH ages exceed STALL_S and it false-flags STALL?→ESCALATED
# every deadline. A pid-identity check (does the pid run claude?) does NOT help: the desk's pid legitimately
# runs claude. The fix is IDENTITY-based, keyed on the correct liveness signal (pid alive), not staleness:
# desk liveness is authoritatively owned by desk-invariant.sh (assistant-turn recency + owned wait-contracts,
# launchd every 300s) plus cc-reaper's [active] surface, so lead-supervisor must NOT double-count it with a
# structurally-wrong staleness heuristic. Coverage is not lost: a DEAD desk pid still hits the DEAD branch
# above (effect-verified), and a genuinely-hung (pid-alive) desk is caught by desk-invariant + the permission
# beacon. Identity bridge mirrors is_monitoring_desk (waiting-recycle.sh) / desk-invariant.sh: the desk role
# file (PAGE_TO_FILE) holds the desk's PANE uuid OR its sid; map a pane via cc-registry/<pane>.json.session_id.
is_registered_desk(){ # $1=telemetry session_id → 0 iff it is the registered monitoring desk
  local sid="$1" ref rsid
  [ -n "$sid" ] || return 1
  ref="$(head -1 "$PAGE_TO_FILE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$ref" ] || return 1
  [ "$ref" = "$sid" ] && return 0                        # role file holds the sid directly
  rsid="$(jq -r '.session_id // .sessionId // empty' "$REGISTRY_DIR/$ref.json" 2>/dev/null)"  # else ref is a pane uuid → registry-bridge
  [ -n "$rsid" ] && [ "$rsid" = "$sid" ]
}

# ── pid-identity: does this pid still OWN its telemetry row, or was it recycled? (item fdc101e8b0c7) ──
# kill -0 proves only that SOME process holds the pid — after a session exits, the OS recycles its pid to
# an unrelated process (or a NEWER claude), so a days-dead row's pid reads as "alive" and the STALL? branch
# re-escalates it every sweep (the zombie: 266841ba 14h-stale, 5277b63a 3d-stale, 2026-07-19). A live pid
# is the ORIGINAL owner only if its process command still marks it a claude session. This resolves the
# recycled-by-NON-claude case in assess() (route it to DEAD, insurance intact); the recycled-by-claude and
# genuine-hung-owner cases (command still matches) are dropped by gc_stale once the row ages past GC_S.
pid_alive_owner(){ # $1=pid → 0 iff alive AND its process command marks it a claude session owner
  local p="$1"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null || return 1
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
}

# ── GC — drop a LIVE-OWNER telemetry row that has been stale past the horizon (item fdc101e8b0c7). ──
# The statusline re-exports a row every turn boundary, so cc-context's own contract is "rows older than
# ~15m are idle or closed". Past GC_S (default 6h = 12× STALL_S) the owning claude has not emitted for
# hours — hung, or its pid recycled to another claude — yet its command still matches, so the STALL?
# branch would re-page it EVERY sweep forever. GC drops the row (+ any standing page) so the zombie stops
# re-paging; recorded to the IDL (S-4 auditable). GUARD: only a still-ALIVE OWNER is GC'd here — a GONE or
# recycled-NON-owner pid is left to assess(), whose DEAD path reap_clean's a clean completion and
# checkpoint-preserves + PAGES a stranded death (dirty/unlanded); GC must never silently drop that
# insurance. Self-healing: a still-live idle owner re-exports a fresh row on its next turn boundary.
gc_stale(){ # → prints the count of horizon-stale live-owner rows dropped
  local f sid ts pid age g=0
  [ -d "$TEL_DIR" ] || { echo 0; return; }
  for f in "$TEL_DIR"/*.json; do
    [ -e "$f" ] || continue
    ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
    age=$(( $(now) - ts ))
    [ "$age" -ge "$GC_S" ] || continue
    pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    pid_alive_owner "$pid" || continue                              # GONE / recycled-non-owner → leave for assess()
    sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"
    rm -f "$f" 2>/dev/null || true
    [ -n "$sid" ] && clear_page "$sid"
    idl gc "\"sid\":\"${sid:-unknown}\",\"age\":$age,\"horizon\":$GC_S,\"pid\":\"${pid:-}\",\"why\":\"live-owner pid on telemetry ${age}s stale >= ${GC_S}s horizon — hung or pid-recycled owner; dropped the row so it stops re-paging every sweep\""
    g=$((g+1))
  done
  echo "$g"
}

# ── classify one telemetry row and route to a PAGE (never an action) ──
assess(){ # $1=telemetry-json-file → prints 1 if it produced a finding, else 0
  local f="$1" sid used ts cwd cfg pid age
  sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || { echo 0; return; }
  used="$(jq -r '.used_pct // 0' "$f" 2>/dev/null)"; used="${used%.*}"; case "$used" in ''|*[!0-9]*) used=0;; esac
  ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
  cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
  cfg="$(jq -r '.config_dir // empty' "$f" 2>/dev/null)"
  pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
  age=$(( $(now) - ts ))

  # DEAD — the owning pid is GONE, or was RECYCLED to a non-claude process (kill -0 lies: it proves only
  # that SOME process holds the pid, item fdc101e8b0c7). Either way the original session has exited, so it
  # is classified exactly like pid-gone. CLEAN COMPLETION vs STRANDED death (item 9b183d78c723).
  if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then
    # A dead worker whose worktree is shipped+clean (clean tree AND content landed on trunk) finished its
    # dispatched item and exited — a normal lifecycle end, ~68% of dead-pid rows (13/19, 2026-07-19) and the
    # dominant source of desk wake-toil. Auto-reap and NEVER page. Only an UNFINISHED/stranded death (dirty
    # tree, unlanded commits, or a cwd we cannot prove clean) is checkpoint-preserved + PAGED, as before.
    if work_landed "$cwd"; then reap_clean "$sid" "$cwd"; echo 0; return; fi
    local why="owning pid $pid gone"
    kill -0 "$pid" 2>/dev/null && why="owning pid $pid recycled to a non-claude process (session gone)"
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
  fi
  # STALL? — pid ALIVE and still a claude OWNER but telemetry stale: a CANDIDATE, never an action. Page with
  # the deadline→re-observe protocol; a resolve_page on the next sweep re-reads effects. (Age alone can NEVER
  # confirm a stall — a healthy long turn renders zero times too; only the effects re-read discriminates. A
  # recycled/non-owner pid took the DEAD branch above; a genuinely-hung owner ages out via gc_stale.)
  # WARM-TRANSCRIPT EXEMPTION (item 1c324d9fcc32): telemetry staleness alone is a FALSE stall signal, so
  # require the transcript ALSO stale before treating a live owner as a candidate — a warm transcript ⇒ the
  # session is demonstrably alive ⇒ fall through to OK (stops the idle-live STALL?→void→re-STALL? oscillation).
  # REGISTERED-DESK EXEMPTION (item ff95faea46c8): a pid-alive registered monitoring desk is legitimately idle
  # between pages — BOTH telemetry and transcript go stale by design, so `! is_registered_desk` drops it to OK;
  # its liveness is owned by desk-invariant.sh, not this staleness proxy (see is_registered_desk).
  if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then
    local tage; tage="$(transcript_age "$cwd" "$cfg" "$sid")"
    if [ "$tage" -ge "$STALL_S" ]; then
      page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"
      resolve_page "$sid" "$cwd"; echo 1; return
    fi
  fi
  # B-1 — PAST-THRESHOLD ∧ NOT-STOPPING: fill ≥ T but the session is live and fresh (still working, never
  # Stopped) so the boundary hook cannot fire for it. Advise via a page; the live session's own model acts.
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
    page "$sid" PAST-THRESHOLD "used ${used}% ≥ ${T}% and still running (not Stopping) — the boundary hook is blind here; advise /handoff"
    echo 1; return
  fi
  # OK — clear any stale page (fresh + below threshold + alive).
  clear_page "$sid"; echo 0
}

# ── a human-legible one-liner for the blocked command, from the harness-authored tool_input ──
# Bash → the command; Write/Edit/etc → the file path; anything else → tool_name + compact input.
beacon_cmd(){ # $1=beacon-file → single-line, ≤160 chars
  local f="$1" c
  c="$(jq -r '
        .tool_input.command
        // .tool_input.file_path
        // .tool_input.path
        // ((.tool_name // "tool") + " " + ((.tool_input // {}) | tostring))' "$f" 2>/dev/null)"
  [ -n "$c" ] && [ "$c" != "null" ] || c="$(jq -r '.tool_name // "?"' "$f" 2>/dev/null)"
  c="$(printf '%s' "$c" | tr '\n\t' '  ' | sed 's/  */ /g')"   # collapse to one line
  [ "${#c}" -gt 160 ] && c="${c:0:157}..."
  printf '%s' "${c:-?}"
}

# ── PERMISSION-PENDING beacons: harness-emitted, UNSPOOFABLE. Unlike the MODAL blindness (S-3) the
#    supervisor CANNOT see, a permission prompt leaves a durable beacon it CAN read → a precise,
#    command-attached page (minutes-latency) instead of a slow detail-free STALL?/MODAL. ──
sweep_permission_pending(){ # prints the number of PERMISSION-PENDING pages produced this sweep
  local dir="$PERMPEND_DIR" found=0 bf sid ts age tel pid cmd
  [ -d "$dir" ] || { echo 0; return; }
  for bf in "$dir"/*.json; do
    [ -e "$bf" ] || continue
    sid="$(basename "$bf" .json)"
    case "$sid" in *[!A-Za-z0-9._-]*|''|.|..) continue ;; esac      # ignore stray/unsafe filenames
    ts="$(jq -r '.ts // 0' "$bf" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
    age=$(( $(now) - ts ))
    # REAP 1 — owning session provably DEAD (pid gone via its telemetry): the prompt died with it. No page.
    tel="$TEL_DIR/$sid.json"
    if [ -f "$tel" ]; then
      pid="$(jq -r '.pid // empty' "$tel" 2>/dev/null)"
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
        rm -f "$bf" 2>/dev/null; clear_permpend "$sid"; continue
      fi
    fi
    # REAP 2 — orphan past the long horizon (hard-kill with no SessionEnd AND no telemetry to pid-check).
    # A ts=0 (malformed) beacon has age≈now ≥ horizon ⇒ reaped, never paged (fail-safe on garbage).
    if [ "$age" -ge "$PERMPEND_HORIZON_S" ]; then
      rm -f "$bf" 2>/dev/null; clear_permpend "$sid"; continue
    fi
    # PAGE — genuinely pending past the notice threshold.
    if [ "$age" -ge "$PERMPEND_NOTICE_S" ]; then
      cmd="$(beacon_cmd "$bf")"
      page_permpend "$sid" "$cmd" "$ts" "$age"
      found=$((found+1))
    fi
  done
  echo "$found"
}

sweep(){
  local n=0 found=0 gc r pp
  gc="$(gc_stale)"                 # GC horizon-stale live-owner zombies FIRST — they are resolved, not a per-sweep finding
  if [ -d "$TEL_DIR" ]; then
    for f in "$TEL_DIR"/*.json; do
      [ -e "$f" ] || continue
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
    done
  fi
  # MODAL is STRUCTURALLY invisible to this bash sweep (S-3): we cannot read a modal/permission dialog or
  # the composer. We never claim a session is modal-free; a live-but-effect-dark session is PAGED as a
  # possible MODAL for the operator to eyeball. (Recorded here so the blindness is declared, not hidden.)
  # But a permission prompt DOES leave a harness-emitted beacon — read it for a precise page (§B2).
  pp="$(sweep_permission_pending)"; found=$(( found + ${pp:-0} ))
  heartbeat "$n" "$found" "$gc"
}

case "${1:-}" in
  --selftest)   exec bash "$(dirname "$0")/supervisor-e2e.sh" ;;
  --once)       sweep ;;
  --daemon|"")  while :; do sweep; sleep "$SWEEP"; done ;;
  *)            echo "usage: lead-supervisor.sh [--once|--daemon|--selftest]" >&2; exit 2 ;;
esac
