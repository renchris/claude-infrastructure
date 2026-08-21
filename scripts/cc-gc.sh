#!/usr/bin/env bash
# cc-gc.sh — the GC franchise: ONE sweeping reaper, per-store adapters.
#
# WHY THIS FILE EXISTS (infra-reliability audit 2026-07-22, root cause 2 + roadmap item 4):
# "Every session mints resources (mailbox, registry row, watchdog daemon+pidfile, worktree,
# TMPDIR, transcript, markers); almost nothing reaps them. GC exists only where an incident
# forced one." The audit's prescription was literal: *one sweeping reaper with per-store
# adapters*, not seven scripts nobody can enumerate. This is that driver.
#
# ── THE TWO ADAPTER KINDS (the load-bearing idea) ─────────────────────────────────────────────
# An adapter is EXEC or ASSERT, and which one a store gets is a statement about who owns it:
#
#   EXEC   — this franchise reaps the store, because nothing else does.
#            mailbox · watchdog       (native, below)
#            scratchpad · worktrees   (delegated to the store's own dedicated reaper)
#
#   ASSERT — the store ALREADY has an owner, so a second reaper here would be a duplicate
#            deleter racing the first. What is missing is not a reaper but a READER: root
#            cause 1 of the same audit is that reapers land and then never take effect
#            (`com.claude.log-rotation` authored, never `launchctl load`ed → idl.jsonl grew to
#            85 MB while a "FIXED" rotation sat inert). An ASSERT adapter proves the owner is
#            actually RUNNING by looking for its effect — residue older than the owner's own
#            horizon means the owner is inert, and that is reported (and under `--strict`,
#            failed) instead of silently papered over by a redundant delete.
#            events · transcripts · session-index
#
# `transcripts` is the sharpest case and worth stating plainly: the audit recorded "1.8 GB, no
# retention". MEASURED 2026-07-25 across all four config roots: 0 transcripts older than 30 d in
# ~/.claude and ~/.claude-secondary, 20 in ~/.claude-tertiary and 0 past 60 d anywhere. The CC
# harness's own `cleanupPeriodDays` is already the owner and it is working. Writing a second
# transcript deleter would put this repo's `rm` on the harness's evidence for zero measured
# benefit. So the adapter READS instead — and it still catches the real failure mode the audit
# named, an ABANDONED config dir whose cleanup never re-runs, because that root's oldest
# transcript walks straight past the horizon and the assert goes red.
#
# ── SAFETY MODEL ──────────────────────────────────────────────────────────────────────────────
# DRY-RUN BY DEFAULT; `--apply` is the only thing that deletes. Every adapter is fail-closed: an
# unanswerable liveness question is a KEEP, never a reap. Liveness ALWAYS outranks age — this
# repo has already paid once for a reaper that killed live operator conversations (2026-07-24),
# and once for `kill -0` alone as an identity oracle (pid reuse). Both scars are honoured below.
#
#   cc-gc.sh                            # dry-run every store, one line per store
#   cc-gc.sh --apply                    # reap
#   cc-gc.sh --store mailbox,watchdog   # only these stores
#   cc-gc.sh --json                     # one summary object
#   cc-gc.sh --strict                   # exit 1 if any ASSERT store's owner is provably inert
#   cc-gc.sh --list                     # print the store table and exit
#
# Env seams (all optional; the *_BIN ones exist so bats can fixture the delegates):
#   CC_MAILBOX_DIR · CC_GC_MBX_DAYS (7) · CC_GC_MBX_STRAND_DAYS (30) · CC_GC_MBX_LOCK_MIN (60)
#   CC_WATCHDOG_DIR · CC_GC_WATCHDOG_DAYS (2)
#   CC_GC_CONFIG_ROOTS · CC_GC_TRANSCRIPT_DAYS (30) · CC_GC_TRANSCRIPT_GRACE_DAYS (15)
#   CC_PAGES_DIR · CC_COMMS_ALARM_DIR · CC_PUSH_RECORDS_DIR · CC_EVENT_TTL_DAYS (7)
#   CC_GC_SESSION_INDEX_STAMP · CC_GC_SESSION_INDEX_MAX_STALE_H (24)
#   CC_REGISTRY_DIR · CC_ROLES_DIR · CC_GC_SCRATCHPAD_BIN · CC_GC_WORKTREE_BIN · CC_IDL
#
# Exit: 0 ok · 1 --strict with an inert owner · 2 usage · 3 fail-closed (oracle unreadable).
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MBX_DIR="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
MBX_DAYS="${CC_GC_MBX_DAYS:-7}"
MBX_STRAND_DAYS="${CC_GC_MBX_STRAND_DAYS:-30}"
MBX_LOCK_MIN="${CC_GC_MBX_LOCK_MIN:-60}"
WD_DIR="${CC_WATCHDOG_DIR:-$HOME/.claude/watchdog}"
WD_DAYS="${CC_GC_WATCHDOG_DAYS:-2}"
# Seconds, not `find -mtime`: the watchdog adapter's whole correctness rests on comparing the
# pidfile's mtime against a process start time, and a day-granular age gate makes the two-case
# discriminator (identity-consistent vs provably-recycled) untestable — both fixtures would need
# a multi-day-old live process. Days stay the human-facing knob; seconds are the seam.
WD_AGE_S="${CC_GC_WATCHDOG_AGE_S:-$((WD_DAYS * 86400))}"
REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
EVENT_TTL="${CC_EVENT_TTL_DAYS:-7}"
TRANSCRIPT_DAYS="${CC_GC_TRANSCRIPT_DAYS:-30}"
TRANSCRIPT_GRACE="${CC_GC_TRANSCRIPT_GRACE_DAYS:-15}"
SI_STAMP="${CC_GC_SESSION_INDEX_STAMP:-$HOME/.claude/state/session-index-sweep.last}"
SI_MAX_STALE_H="${CC_GC_SESSION_INDEX_MAX_STALE_H:-24}"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"

ALL_STORES='mailbox watchdog scratchpad worktrees events transcripts session-index'

APPLY=0; JSON=0; STRICT=0; VERBOSE=0; WANT=''
usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)   APPLY=1 ;;
    --dry-run) APPLY=0 ;;
    --json)    JSON=1 ;;
    --strict)  STRICT=1 ;;
    --verbose|-v) VERBOSE=1 ;;
    --store)   shift; WANT="${1:-}" ;;
    --store=*) WANT="${1#--store=}" ;;
    --list)    for s in $ALL_STORES; do echo "$s"; done; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "cc-gc: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

wanted() { # <store> → 0 if this run should include it
  [ -z "$WANT" ] && return 0
  case ",$WANT," in *",$1,"*) return 0 ;; esac
  return 1
}
note(){ [ "$VERBOSE" -eq 1 ] && [ "$JSON" -eq 0 ] && printf '    %s\n' "$1"; return 0; }

UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
INERT=0                       # count of ASSERT stores whose owner is provably not running
ROWS=''                       # newline-joined "store<TAB>kind<TAB>status<TAB>reaped<TAB>kept<TAB>detail"
# PADDED at the emitter, because tab is IFS-WHITESPACE: an empty cell does not read back as empty,
# it shifts every later column LEFT — silently, exit 0. Both readers below (`while IFS=$'\t' read`)
# would then mis-name a store after its own verdict, or read a count into `detail`. The read side
# cannot be repaired, so every non-LAST cell defaults to `-`; `detail` is last and may be empty.
row() { local s="${1:-}" k="${2:-}" st="${3:-}" r="${4:-}" kept="${5:-}"
        ROWS="$ROWS${s:--}	${k:--}	${st:--}	${r:--}	${kept:--}	${6:-}
"; }

# ── the LIVE set ──────────────────────────────────────────────────────────────────────────────
# Registry rows are keyed by paneUUID (the filename) and carry session_id + pid. A mailbox key is
# a paneUUID; a watchdog pidfile is keyed by session_id. Collect BOTH identifiers for every row
# whose pid is alive, plus every role pointer's target. Over-matching is safe by construction: a
# false entry here can only ever cause a KEEP.
LIVE_KEYS=''
collect_live() {
  [ -d "$REG_DIR" ] && [ -r "$REG_DIR" ] || return 1
  local row_f line rpane rsid rpid
  for row_f in "$REG_DIR"/*.json; do
    [ -f "$row_f" ] || continue
    line=$(jq -r '[(.paneUUID // ""), (.session_id // ""), (.pid // "")] | @tsv' "$row_f" 2>/dev/null) || continue
    IFS=$'\t' read -r rpane rsid rpid <<< "$line"
    [ -n "$rpid" ] || continue
    kill -0 "$rpid" 2>/dev/null || continue
    [ -n "$rpane" ] && LIVE_KEYS="$LIVE_KEYS
$rpane"
    [ -n "$rsid" ] && LIVE_KEYS="$LIVE_KEYS
$rsid"
  done
  # Role pointers (desk/operator/orchestrator) name a box that must never be reaped.
  if [ -d "$ROLES_DIR" ]; then
    local rf
    for rf in "$ROLES_DIR"/*; do
      [ -f "$rf" ] || continue
      LIVE_KEYS="$LIVE_KEYS
$(tr -d ' \t\n\r' < "$rf" 2>/dev/null)"
    done
  fi
  return 0
}
is_live() { case "$LIVE_KEYS" in *"
$1"*) return 0 ;; esac; return 1; }

if ! collect_live; then
  echo "cc-gc: registry unreadable at $REG_DIR — FAIL-CLOSED, nothing reaped" >&2
  [ "$JSON" -eq 1 ] && printf '{"tool":"cc-gc","status":"fail-closed","registry":"%s"}\n' "$REG_DIR"
  exit 3
fi

# ══ EXEC · mailbox ════════════════════════════════════════════════════════════════════════════
# Layout (hooks/lib/mailbox-pending.sh): <key>.md append-only inbox · <key>.seen surfaced
# watermark · <key>.acked consumed watermark · <key>.forward successor pointer · .<key>.lock dir.
#
# Reap ONLY a UUID-shaped per-session box — the measured leak class (39 dead boxes / 1,401
# unacked). A NAME-keyed box (deskC, PANE-DESK-24) is a durable role inbox and is never reaped by
# age; it is counted and reported instead.
#
# Two dispositions, because deleting the two cases alike would destroy evidence:
#   FULLY-ACKED, dead, aged  → delete the triple. Every line was provably consumed by a turn; the
#                              durable record is that session's transcript, which we never touch.
#   UNACKED, dead, stranded  → ARCHIVE to mailbox/archive/. Unacked mail in a dead box IS the
#                              audit's 78%-unacked finding: it is evidence of a lost message and
#                              deleting it would erase the only proof the comms layer dropped it.
# `.forward` is NEVER removed: mailbox-pending.sh:44 makes it the D6 tombstone that keeps a
# forward chain resolvable long after the box it points from is gone.
gc_mailbox() {
  local reaped=0 archived=0 kept_live=0 kept_named=0 kept_young=0 kept_unacked=0 locks=0
  local f key lines acked
  if [ ! -d "$MBX_DIR" ]; then row mailbox EXEC absent 0 0 "no mailbox dir"; return 0; fi

  for f in "$MBX_DIR"/*.md; do
    [ -f "$f" ] || continue
    key=$(basename "$f" .md)
    if ! [[ "$key" =~ $UUID_RE ]]; then kept_named=$((kept_named + 1)); note "keep(named)   $key"; continue; fi
    if is_live "$key"; then kept_live=$((kept_live + 1)); note "keep(live)    $key"; continue; fi

    lines=$(wc -l < "$f" 2>/dev/null | tr -d ' '); [ -n "$lines" ] || lines=0
    # `2>/dev/null <file` not `<file 2>/dev/null`: redirections apply left to right, so a missing
    # .acked (the common "never consumed" case) must be silenced BEFORE the read is attempted.
    acked=$(tr -dc '0-9' 2>/dev/null < "$MBX_DIR/$key.acked"); [ -n "$acked" ] || acked=0

    if [ "$acked" -ge "$lines" ] 2>/dev/null; then
      # fully consumed → the short horizon applies
      if [ -z "$(find "$f" -maxdepth 0 -mtime +"$MBX_DAYS" 2>/dev/null)" ]; then
        kept_young=$((kept_young + 1)); continue
      fi
      if [ "$APPLY" -eq 1 ]; then rm -f "$MBX_DIR/$key.md" "$MBX_DIR/$key.seen" "$MBX_DIR/$key.acked" 2>/dev/null
      else note "would-reap    $key (acked=$acked/$lines)"; fi
      reaped=$((reaped + 1))
    else
      # unacked in a dead box → evidence; only the LONG horizon, and archive rather than delete
      if [ -z "$(find "$f" -maxdepth 0 -mtime +"$MBX_STRAND_DAYS" 2>/dev/null)" ]; then
        kept_unacked=$((kept_unacked + 1)); continue
      fi
      if [ "$APPLY" -eq 1 ]; then
        mkdir -p "$MBX_DIR/archive" 2>/dev/null || true
        mv -f "$MBX_DIR/$key.md" "$MBX_DIR/archive/$key.md" 2>/dev/null || true
        [ -f "$MBX_DIR/$key.seen" ] && mv -f "$MBX_DIR/$key.seen" "$MBX_DIR/archive/$key.seen" 2>/dev/null
        [ -f "$MBX_DIR/$key.acked" ] && mv -f "$MBX_DIR/$key.acked" "$MBX_DIR/archive/$key.acked" 2>/dev/null
      else note "would-archive $key (acked=$acked/$lines, stranded)"; fi
      archived=$((archived + 1))
    fi
  done

  # abandoned mkdir locks: the lib self-breaks at CC_MBX_LOCK_STALE_S (10 s), so a lock dir still
  # standing an hour later is debris no live taker is waiting on.
  local ld
  while IFS= read -r ld; do
    [ -n "$ld" ] || continue
    [ "$APPLY" -eq 1 ] && rm -rf "$ld" 2>/dev/null
    locks=$((locks + 1))
  done < <(find "$MBX_DIR" -maxdepth 1 -type d -name '.*.lock' -mmin +"$MBX_LOCK_MIN" 2>/dev/null)

  row mailbox EXEC ok "$((reaped + archived))" "$((kept_live + kept_named + kept_young + kept_unacked))" \
      "deleted=$reaped archived=$archived locks=$locks kept(live=$kept_live named=$kept_named young=$kept_young unacked=$kept_unacked)"
}

# ══ EXEC · watchdog ═══════════════════════════════════════════════════════════════════════════
# hooks/lead-crash-watchdog.sh writes <sid>.pid (the lead pid) + <sid>.id at registration and
# removes both only on its own guarded exit paths — so a lead that dies without the daemon
# noticing strands the pair forever (audit measured 93 files / 83 stale).
#
# IDENTITY, NOT `kill -0`: this box runs ~30 concurrent `claude` processes, so a recycled pid
# landing on ANOTHER claude is likely, and both `kill -0` and a comm=claude check would call a
# dead session live. Measured 2026-07-25: all 28 pairs pass both — the naive oracles cannot
# distinguish. The pin that CAN: a process whose START TIME is LATER than the pidfile's mtime
# cannot be the process that wrote it. That is a provable recycle, and it is the only reap
# reason accepted here besides an outright dead pid.
# Ambiguity (unreadable lstart, unparseable date, no pid file) is always a KEEP.
gc_watchdog() {
  local reaped=0 kept_live=0 kept_young=0 recycled=0 dead=0 orphan=0
  local f sid pid fm ls pstart now
  if [ ! -d "$WD_DIR" ]; then row watchdog EXEC absent 0 0 "no watchdog dir"; return 0; fi
  now=$(date +%s)

  for f in "$WD_DIR"/*.pid; do
    [ -f "$f" ] || continue
    sid=$(basename "$f" .pid)
    if is_live "$sid"; then kept_live=$((kept_live + 1)); note "keep(live)    $sid"; continue; fi
    fm=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    # age guard mirrors the +2 d convention session-end.sh already uses for cp-*.count
    if [ -z "$fm" ] || [ "$((now - fm))" -le "$WD_AGE_S" ] 2>/dev/null; then
      kept_young=$((kept_young + 1)); continue
    fi
    pid=$(tr -dc '0-9' 2>/dev/null < "$f")
    if [ -z "$pid" ]; then kept_young=$((kept_young + 1)); continue; fi

    local why=''
    if ! kill -0 "$pid" 2>/dev/null; then
      why='dead-pid'; dead=$((dead + 1))
    else
      # THE LOCALE PIN FOR THIS PARSE IS `export LC_ALL=C` AT LINE 59 — file scope, not this line.
      # Do not "fix" this site by adding an inline pin, and do not read a bare `ps` here as a bug:
      # a LINE-scoped grep for LC_ALL reports this pair as ambient and it is not. That misreading
      # has been re-derived repeatedly. Ambient here renders `Fri 21 Aug 14:37:09 2026`, which the
      # US-order format below cannot parse at all; LC_ALL=C normalises it to `Fri Aug 21 …`.
      # Deleting line 59 kills the whole recycled-pid path SILENTLY via the KEEP arm below — the
      # hermetic runner exports LC_ALL=C itself (scripts/offbox-run.sh:134), so the land gate cannot
      # see it. tests/cc-gc.bats ratchets line 59 structurally for exactly that reason.
      ls=$(ps -o lstart= -p "$pid" 2>/dev/null)
      pstart=''
      [ -n "$ls" ] && pstart=$(date -j -f '%a %b %e %T %Y' "$ls" +%s 2>/dev/null || date -d "$ls" +%s 2>/dev/null)
      if [ -n "$pstart" ] && [ "$pstart" -gt "$((fm + 120))" ] 2>/dev/null; then
        why='recycled-pid'; recycled=$((recycled + 1))
      else
        kept_live=$((kept_live + 1)); note "keep(pinned)  $sid pid=$pid"; continue   # ambiguity ⇒ KEEP
      fi
    fi
    if [ "$APPLY" -eq 1 ]; then rm -f "$WD_DIR/$sid.pid" "$WD_DIR/$sid.id" 2>/dev/null
    else note "would-reap    $sid ($why pid=$pid)"; fi
    reaped=$((reaped + 1))
  done

  # a .id with no .pid is the residue of a half-cleaned pair; same age guard, no liveness claim
  # to answer because the pid the pair described is already gone.
  for f in "$WD_DIR"/*.id; do
    [ -f "$f" ] || continue
    sid=$(basename "$f" .id)
    [ -f "$WD_DIR/$sid.pid" ] && continue
    is_live "$sid" && { kept_live=$((kept_live + 1)); continue; }
    fm=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    { [ -z "$fm" ] || [ "$((now - fm))" -le "$WD_AGE_S" ]; } 2>/dev/null && { kept_young=$((kept_young + 1)); continue; }
    [ "$APPLY" -eq 1 ] && rm -f "$f" 2>/dev/null
    orphan=$((orphan + 1)); reaped=$((reaped + 1))
  done

  row watchdog EXEC ok "$reaped" "$((kept_live + kept_young))" \
      "dead=$dead recycled=$recycled orphan-id=$orphan kept(live=$kept_live young=$kept_young)"
}

# ══ EXEC · delegates ══════════════════════════════════════════════════════════════════════════
# The store's own reaper is the adapter. Both already default to dry-run and take --apply, so the
# franchise flag passes straight through and there is exactly one implementation per store.
run_delegate() { # <store> <bin> <extra-arg...>
  local store="$1" bin="$2"; shift 2
  if [ ! -x "$bin" ]; then row "$store" EXEC missing 0 0 "delegate not executable: $bin"; return 0; fi
  local out rc
  if [ "$APPLY" -eq 1 ]; then out=$("$bin" "$@" --apply 2>&1); rc=$?
  else out=$("$bin" "$@" 2>&1); rc=$?; fi
  [ "$VERBOSE" -eq 1 ] && [ "$JSON" -eq 0 ] && printf '%s\n' "$out" | sed 's/^/    /'
  local tail_line; tail_line=$(printf '%s' "$out" | tail -1 | cut -c1-160)
  if [ "$rc" -ne 0 ]; then row "$store" EXEC red 0 0 "delegate rc=$rc: $tail_line"; return 0; fi
  row "$store" EXEC ok - - "$tail_line"
}

# ══ ASSERT · the owner-is-running probes ══════════════════════════════════════════════════════
# Each of these stores HAS a reaper. The failure mode is that the reaper never runs (root cause
# 1). Residue older than the owner's own declared horizon is the proof, and it is the only thing
# these adapters look at. They never delete.
assert_events() {
  local dirs="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}
${CC_COMMS_ALARM_DIR:-$HOME/.claude/autonomy/comms-alarms}
${CC_PUSH_RECORDS_DIR:-$HOME/.claude/autonomy/push-records}"
  local d over=0 total=0 n worst=''
  while IFS= read -r d; do
    [ -d "$d" ] || continue
    n=$(find "$d" -maxdepth 1 -type f -mtime +"$EVENT_TTL" 2>/dev/null | wc -l | tr -d ' ')
    total=$((total + n))
    [ "$n" -gt 0 ] && { over=$((over + 1)); worst="$worst $(basename "$d")=$n"; }
  done <<< "$dirs"
  if [ "$total" -gt 0 ]; then
    INERT=$((INERT + 1))
    row events ASSERT inert 0 0 "autonomy-sweep.sh has not reaped:$worst (>${EVENT_TTL}d)"
  else
    row events ASSERT ok 0 0 "autonomy-sweep.sh owns these; 0 files past ${EVENT_TTL}d"
  fi
}

assert_transcripts() {
  local roots="${CC_GC_CONFIG_ROOTS:-$HOME/.claude $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-next}"
  local horizon=$((TRANSCRIPT_DAYS + TRANSCRIPT_GRACE))
  local r n total=0 worst=''
  # shellcheck disable=SC2086  # CC_GC_CONFIG_ROOTS is a space-separated root list by contract
  for r in $roots; do
    [ -d "$r/projects" ] || continue
    n=$(find "$r/projects" -name '*.jsonl' -type f -mtime +"$horizon" 2>/dev/null | wc -l | tr -d ' ')
    total=$((total + n))
    [ "$n" -gt 0 ] && worst="$worst $(basename "$r")=$n"
  done
  if [ "$total" -gt 0 ]; then
    INERT=$((INERT + 1))
    row transcripts ASSERT inert 0 0 "cleanupPeriodDays not running for:$worst (>${horizon}d) — abandoned config root?"
  else
    row transcripts ASSERT ok 0 0 "CC cleanupPeriodDays owns these; 0 transcripts past ${horizon}d"
  fi
}

assert_session_index() {
  if [ ! -f "$SI_STAMP" ]; then
    INERT=$((INERT + 1))
    row session-index ASSERT inert 0 0 "no sweep stamp at $SI_STAMP — session-index-sweep never ran"
    return 0
  fi
  if [ -n "$(find "$SI_STAMP" -maxdepth 0 -mmin +"$((SI_MAX_STALE_H * 60))" 2>/dev/null)" ]; then
    INERT=$((INERT + 1))
    row session-index ASSERT inert 0 0 "sweep stamp older than ${SI_MAX_STALE_H}h — retention+VACUUM not running"
    return 0
  fi
  row session-index ASSERT ok 0 0 "session-index-sweep.sh ran within ${SI_MAX_STALE_H}h (retention+VACUUM live)"
}

# ── run the wanted stores ─────────────────────────────────────────────────────────────────────
wanted mailbox        && gc_mailbox
wanted watchdog       && gc_watchdog
wanted scratchpad     && run_delegate scratchpad "${CC_GC_SCRATCHPAD_BIN:-$SCRIPT_DIR/scratchpad-reaper.sh}"
wanted worktrees      && run_delegate worktrees  "${CC_GC_WORKTREE_BIN:-$SCRIPT_DIR/worktree-gc.sh}"
wanted events         && assert_events
wanted transcripts    && assert_transcripts
wanted session-index  && assert_session_index

case "$APPLY" in 1) MODE=apply ;; *) MODE=dry-run ;; esac
TOTAL_REAPED=0
while IFS=$'\t' read -r _s _k _st r _kept _d; do
  [ -n "${r:-}" ] || continue
  case "$r" in ''|*[!0-9]*) continue ;; esac
  TOTAL_REAPED=$((TOTAL_REAPED + r))
done <<< "$ROWS"

if [ "$JSON" -eq 1 ]; then
  printf '%s' "$ROWS" | jq -R -s --arg mode "$MODE" --argjson inert "$INERT" --argjson reaped "$TOTAL_REAPED" '
    { tool:"cc-gc", mode:$mode, reaped:$reaped, inert:$inert,
      stores: [ split("\n")[] | select(length>0) | split("\t")
                | {store:.[0], kind:.[1], status:.[2], reaped:.[3], kept:.[4], detail:.[5]} ] }'
else
  printf 'cc-gc: %s  (reaped=%s, inert-owners=%s)\n' "$MODE" "$TOTAL_REAPED" "$INERT"
  printf '%s' "$ROWS" | while IFS=$'\t' read -r s k st r kept d; do
    [ -n "$s" ] || continue
    printf '  %-14s %-6s %-7s reaped=%-4s kept=%-4s %s\n' "$s" "$k" "$st" "$r" "$kept" "$d"
  done
fi

# One IDL line per APPLY run that changed something, or per run that found an inert owner. A
# dry-run that found nothing must not become the growth surface this script exists to bound.
if [ "$TOTAL_REAPED" -gt 0 ] || [ "$INERT" -gt 0 ]; then
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg mode "$MODE" \
         --argjson reaped "$TOTAL_REAPED" --argjson inert "$INERT" \
    '{ts:$ts,tool:"cc-gc",mode:$mode,reaped:$reaped,inert_owners:$inert}' >> "$IDL" 2>/dev/null || true
fi

[ "$STRICT" -eq 1 ] && [ "$INERT" -gt 0 ] && exit 1
exit 0
