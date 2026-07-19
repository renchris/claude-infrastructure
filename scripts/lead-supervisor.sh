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
TRUNK="${CC_SUP_TRUNK:-origin/main}"                   # trunk for the clean-completion landed-check (cf. cc-classify CC_CLASSIFY_TRUNK)
TEL_DIR="${CC_TELEMETRY_DIR:-/tmp/cc-telemetry}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SUPLOG="${CC_SUPERVISOR_LOG:-$HOME/.claude/autonomy/supervisor.log}"
PAGEDIR="${CC_SUPERVISOR_PAGEDIR:-$HOME/.claude/autonomy/pages}"
PAGE_TO="${CC_PAGE_TO:-}"                              # operator/desk pane uuid for cc-notify pages (best-effort)
PAGE_TO_FILE="${CC_PAGE_TO_FILE:-$HOME/.claude/cc-roles/desk}"   # fallback: live desk role file (CC_PAGE_TO wins; /dev/null disables)
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
  # only a genuine worsening to DEAD notifies again; the OK-branch clear_page resets the marker on a
  # true recovery, but a VOID keeps it (void_page, item 1c324d9fcc32) so a STALL?→void→re-STALL?
  # oscillation stays composer-damped — the stale-telemetry situation that triggered it still persists.
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
  local target="$PAGE_TO"; [ -n "$target" ] || target="$(cat "$PAGE_TO_FILE" 2>/dev/null || true)"
  if [ -n "$target" ] && [ -n "$NOTIFY_BIN" ]; then
    "$NOTIFY_BIN" "$target" "⛔ PERMISSION-PENDING — session $sid blocked ${age}s on a permission prompt: ${cmd} (since $(fmt_since "$ts")). Nothing in-session can answer; operator/live-session must approve or deny." >/dev/null 2>&1 || true
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

  # DEAD — pid gone (effect-verified). CLEAN COMPLETION vs STRANDED death (item 9b183d78c723).
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
    # A dead worker whose worktree is shipped+clean (clean tree AND content landed on trunk) finished its
    # dispatched item and exited — a normal lifecycle end, ~68% of dead-pid rows (13/19, 2026-07-19) and the
    # dominant source of desk wake-toil. Auto-reap and NEVER page. Only an UNFINISHED/stranded death (dirty
    # tree, unlanded commits, or a cwd we cannot prove clean) is checkpoint-preserved + PAGED, as before.
    if work_landed "$cwd"; then reap_clean "$sid" "$cwd"; echo 0; return; fi
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "owning pid $pid gone; worktree checkpoint-preserved"; echo 1; return
  fi
  # STALL? — pid ALIVE but telemetry stale: a CANDIDATE, never an action. Page with the deadline→re-observe
  # protocol; a resolve_page on the next sweep re-reads effects. (Age alone can NEVER confirm a stall — a
  # healthy long turn renders zero times too; only the effects re-read discriminates.) WARM-TRANSCRIPT
  # EXEMPTION (item 1c324d9fcc32): telemetry staleness alone is a FALSE stall signal, so require the
  # transcript ALSO stale before treating a live pid as a candidate. A warm transcript ⇒ the session is
  # demonstrably alive (still appending messages/tool events) ⇒ fall through to OK, page nothing — this is
  # what stops the idle-live STALL?→void→re-STALL? oscillation at its ROOT (the void-damping fix above is
  # the backstop for the residual cold-transcript-but-ambient-cwd-churn case).
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ "$age" -ge "$STALL_S" ]; then
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
  local n=0 found=0 r pp
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
  heartbeat "$n" "$found"
}

case "${1:-}" in
  --selftest)   exec bash "$(dirname "$0")/supervisor-e2e.sh" ;;
  --once)       sweep ;;
  --daemon|"")  while :; do sweep; sleep "$SWEEP"; done ;;
  *)            echo "usage: lead-supervisor.sh [--once|--daemon|--selftest]" >&2; exit 2 ;;
esac
