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
#            CC_SUP_PAGE_DEADLINE_S · SUPERVISOR_SWEEP_MAX_S · SUPERVISOR_SWEEP
set -uo pipefail

# The sweep interval SHARES reaper-horizon-lint's constant — never fork the number (invariant 7; the
# horizon floor is 10× this, enforced there). The actual daemon loop may be faster, never slower.
SUPERVISOR_SWEEP_MAX_S="${SUPERVISOR_SWEEP_MAX_S:-600}"
SWEEP="${SUPERVISOR_SWEEP:-30}"
[ "$SWEEP" -le "$SUPERVISOR_SWEEP_MAX_S" ] 2>/dev/null || SWEEP="$SUPERVISOR_SWEEP_MAX_S"

T="${CC_SUP_T:-73}"                                    # past-threshold (used_pct) — the B-1 boundary
STALL_S="${CC_SUP_STALL_S:-1800}"                      # telemetry age past which a live pid is a STALL? candidate
DEADLINE_S="${CC_SUP_PAGE_DEADLINE_S:-900}"            # page deadline before the re-observe (15m default)
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SUPLOG="${CC_SUPERVISOR_LOG:-$HOME/.claude/autonomy/supervisor.log}"
PAGEDIR="${CC_SUPERVISOR_PAGEDIR:-$HOME/.claude/autonomy/pages}"
PAGE_TO="${CC_PAGE_TO:-}"                              # operator/desk pane uuid for cc-notify pages (best-effort)
PAGE_TO_FILE="${CC_PAGE_TO_FILE:-$HOME/.claude/cc-roles/desk}"   # fallback: live desk role file (CC_PAGE_TO wins; /dev/null disables)
# cc-notify must resolve under launchd's bare default PATH (/usr/bin:/bin:...) — env override →
# beside-script repo bin → ~/.claude/bin → PATH (the autonomy-sweep resolve_bin order)
NOTIFY_BIN="${CC_NOTIFY_BIN:-}"
if [ -z "$NOTIFY_BIN" ]; then
  for _c in "$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/bin/cc-notify" "$HOME/.claude/bin/cc-notify" "$(command -v cc-notify 2>/dev/null || true)"; do
    [ -n "$_c" ] && [ -x "$_c" ] && { NOTIFY_BIN="$_c"; break; }
  done
fi

now(){ date +%s; }
utc(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
_ensure(){ mkdir -p "$(dirname "$IDL")" "$(dirname "$SUPLOG")" "$PAGEDIR" 2>/dev/null || true; }

# ── S-4: heartbeat — one IDL line PER SWEEP (even an all-clear one), plus per-finding records. ──
idl(){ # $1=kind  $2=json-body(no braces)
  _ensure; printf '{"ts":"%s","actor":"lead-supervisor","kind":"%s",%s}\n' "$(utc)" "$1" "$2" >> "$IDL" 2>/dev/null || true
}
heartbeat(){ # $1=n_swept $2=n_findings
  idl heartbeat "\"swept\":$1,\"findings\":$2,\"sweep_s\":$SWEEP"
  printf '%s  swept=%s findings=%s\n' "$(utc)" "$1" "$2" >> "$SUPLOG" 2>/dev/null || true
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
  # only a genuine worsening to DEAD notifies again; clear_page (recovery/void) resets the marker
  [ "$last" = "ESCALATED" ] && [ "$2" != "DEAD" ] && return 0
  # target resolves per page, not at startup: an empty CC_PAGE_TO falls back to the desk role file,
  # so a pane rebind (role-file rewrite) redirects pages with no plist edit and no daemon restart
  local target="$PAGE_TO"
  [ -n "$target" ] || target="$(cat "$PAGE_TO_FILE" 2>/dev/null || true)"
  if [ -n "$target" ] && [ -n "$NOTIFY_BIN" ]; then
    "$NOTIFY_BIN" "$target" "⚠️ SUPERVISOR PAGE — session $1 is $2: $3 (operator/delegated-live-session recovers; supervisor never auto-acts)" >/dev/null 2>&1 || true
    printf '%s\n' "$2" > "$nf"                             # recorded only on an attempted send — a
  fi                                                       # later-wired channel still gets its first notify
}
clear_page(){ rm -f "$PAGEDIR/$1.page" "$PAGEDIR/$1.notified" 2>/dev/null || true; }

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
    clear_page "$sid"
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

# ── classify one telemetry row and route to a PAGE (never an action) ──
assess(){ # $1=telemetry-json-file → prints 1 if it produced a finding, else 0
  local f="$1" sid used ts cwd pid age
  sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || { echo 0; return; }
  used="$(jq -r '.used_pct // 0' "$f" 2>/dev/null)"; used="${used%.*}"; case "$used" in ''|*[!0-9]*) used=0;; esac
  ts="$(jq -r '.ts // 0' "$f" 2>/dev/null)"; ts="${ts%.*}"; case "$ts" in ''|*[!0-9]*) ts=0;; esac
  cwd="$(jq -r '.cwd // empty' "$f" 2>/dev/null)"
  pid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
  age=$(( $(now) - ts ))

  # DEAD — pid gone (effect-verified). Checkpoint-preserve, then PAGE. NEVER auto-respawn.
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "owning pid $pid gone; worktree checkpoint-preserved"; echo 1; return
  fi
  # STALL? — pid ALIVE but telemetry stale: a CANDIDATE, never an action. Page with the deadline→re-observe
  # protocol; a resolve_page on the next sweep re-reads effects. (Age alone can NEVER confirm a stall — a
  # healthy long turn renders zero times too; only the effects re-read discriminates.)
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$age" -ge "$STALL_S" ]; then
    page "$sid" "STALL?" "pid alive but telemetry ${age}s stale — CANDIDATE; re-observing effects at deadline"
    resolve_page "$sid" "$cwd"; echo 1; return
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

sweep(){
  local n=0 found=0 r
  if [ -d "$TEL_DIR" ]; then
    for f in "$TEL_DIR"/*.json; do
      [ -e "$f" ] || continue
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
    done
  fi
  # MODAL is STRUCTURALLY invisible to this bash sweep (S-3): we cannot read a modal/permission dialog or
  # the composer. We never claim a session is modal-free; a live-but-effect-dark session is PAGED as a
  # possible MODAL for the operator to eyeball. (Recorded here so the blindness is declared, not hidden.)
  heartbeat "$n" "$found"
}

case "${1:-}" in
  --selftest)   exec bash "$(dirname "$0")/supervisor-e2e.sh" ;;
  --once)       sweep ;;
  --daemon|"")  while :; do sweep; sleep "$SWEEP"; done ;;
  *)            echo "usage: lead-supervisor.sh [--once|--daemon|--selftest]" >&2; exit 2 ;;
esac
