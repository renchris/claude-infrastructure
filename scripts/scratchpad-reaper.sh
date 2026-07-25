#!/bin/bash
# scratchpad-reaper.sh — GC the per-session harness scratchpad tree.
#
# THE SURFACE (audit 03 §1d, rank 1): `/private/tmp/claude-501/<project>/<sessionUUID>/` is created
# by the CC harness once per session (`scratchpad/`, `tasks/`). Agents download models and media into
# it. MEASURED 2026-07-25: **10.67 GB across 461 session dirs (377 of them 0 KB)**, growing
# **~810 MB/day**, and its ONLY bound is a reboot — three dead sessions alone held 10.8 GB. It is
# larger than all of `~/.claude` by 5×.
#
# THE PREDICATE (liveness FIRST, age second — the reaper's own scar tissue):
#   A session dir is reaped only when ALL of:
#     (a) its sessionUUID has NO live pid — no `cc-registry` row, or the row's pid is dead; AND
#     (b) its sessionUUID has NO recently-touched transcript in any config dir's `projects/`; AND
#     (c) the dir itself is older than the horizon (default 48 h).
#   A dir holding NO regular files (the 377 "0 KB" dirs) skips (c) — there is nothing to lose — but
#   NEVER skips (a)/(b).
#
# Why (b) exists at all, when (a) already asks the registry: the registry retains only 24 h
# (`CC_REG_RETAIN_H`), so at a 48 h horizon EVERY candidate's row is gone by construction and (a)
# would degrade to "reap everything old". Worse, session registration has a known timing gap
# (`bin/cc-reconcile` exists precisely to backfill rows panes never wrote). The transcript is the
# harness's own durable liveness product: a session that took a turn inside the window bumped it.
# Deleting a LIVE session's scratchpad is the exact failure class this repo has already paid for
# once (cc-reaper reaping live operator conversations, 2026-07-24) — so liveness always outranks age.
#
# FAIL-CLOSED: an unreadable/absent registry means the liveness question cannot be answered, so
# NOTHING is reaped. A reaper that deletes when its evidence is missing is a data-loss bug.
#
# DRY-RUN BY DEFAULT. `--apply` deletes. `--json` emits one summary object.
#
# Env (tests): CC_SCRATCHPAD_ROOT · CC_REGISTRY_DIR · CC_SCRATCHPAD_AGE_PRED · CC_PROJECT_DIRS
#   · CC_SCRATCHPAD_LOG.  bash-3.2 safe, BSD find, no eval, never `set -e`.
set -uo pipefail

ROOT="${CC_SCRATCHPAD_ROOT:-/private/tmp/claude-$(id -u)}"
REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
LOG="${CC_SCRATCHPAD_LOG:-$HOME/.claude/logs/scratchpad-reaper.log}"

# The horizon is written as a LITERAL `-mmin +N` default so scripts/reaper-horizon-lint.sh §1 can
# SCORE it — that gate greps the SOURCE for `-mmin +<n>`, and a bare variable would be invisible to
# it (a check must observe the thing it guards, not prose about it). 2880 min = 48 h = 172,800 s,
# far above the lint's 6,000 s floor (SUPERVISOR_SWEEP_MAX_S 600 × 10), so a supervisor can always
# observe a session's scratchpad long before this reaper can touch it.
AGE_PRED="${CC_SCRATCHPAD_AGE_PRED:--mmin +2880}"

# Config dirs whose projects/ hold transcripts (the liveness product). Space-separated.
PROJECT_DIRS="${CC_PROJECT_DIRS:-$HOME/.claude/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"

APPLY=0; JSON=0
usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;;
    --json)  JSON=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "scratchpad-reaper: unknown arg: $a" >&2; exit 2 ;;
  esac
done

UUID_RE='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'

log_line() { # <msg>  — best-effort; never blocks the sweep
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || return 0
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true
}

# ── fail-closed gate ──────────────────────────────────────────────────────────────────────────
# No root → nothing to do (exit 0, not an error). No readable registry → the liveness predicate is
# unanswerable → refuse to delete anything and say so loudly.
if [ ! -d "$ROOT" ]; then
  [ "$JSON" -eq 1 ] && printf '{"root":"%s","status":"absent","candidates":0,"reaped":0}\n' "$ROOT"
  exit 0
fi
if [ ! -d "$REG_DIR" ] || [ ! -r "$REG_DIR" ]; then
  echo "scratchpad-reaper: registry unreadable at $REG_DIR — FAIL-CLOSED, nothing reaped" >&2
  log_line "FAIL-CLOSED: registry unreadable at $REG_DIR"
  [ "$JSON" -eq 1 ] && printf '{"root":"%s","status":"fail-closed","candidates":0,"reaped":0}\n' "$ROOT"
  exit 3
fi

# ── 1. the LIVE set: sessionUUIDs whose registry row carries a living pid ─────────────────────
# Newline-separated; matched with a bounded `case` (bash-3.2 has no associative arrays).
LIVE_SIDS=""
for row in "$REG_DIR"/*.json; do
  [ -f "$row" ] || continue
  # One jq per row keeps this readable; the registry is ~66 rows, not a hot loop.
  line=$(jq -r '[(.pid // ""), (.session_id // "")] | @tsv' "$row" 2>/dev/null) || continue
  [ -n "$line" ] || continue
  IFS=$'\t' read -r rpid rsid <<< "$line"
  [ -n "$rpid" ] && [ -n "$rsid" ] || continue
  kill -0 "$rpid" 2>/dev/null || continue
  LIVE_SIDS="$LIVE_SIDS
$rsid"
done

# ── 2. the RECENT set: sessionUUIDs whose transcript was touched inside the horizon ───────────
# The registry only retains 24 h, so at a 48 h horizon it is empty by construction for every
# candidate — the transcript scan is what actually keeps a long-running session's scratchpad.
RECENT_SIDS=""
# shellcheck disable=SC2086  # PROJECT_DIRS (list of roots) and AGE_PRED (multi-word find
# predicate) are BOTH intentionally word-split here; quoting either would break the find.
for pdir in $PROJECT_DIRS; do
  [ -d "$pdir" ] || continue
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    b=$(basename "$t" .jsonl)
    # Subdir layout `<uuid>/transcript.jsonl` → the UUID is the parent dir.
    [ "$b" = "transcript" ] && b=$(basename "$(dirname "$t")")
    RECENT_SIDS="$RECENT_SIDS
$b"
  done < <(find "$pdir" -maxdepth 3 -name '*.jsonl' -type f ! $AGE_PRED 2>/dev/null)
done

is_live()   { case "$LIVE_SIDS"   in *"
$1"*) return 0 ;; esac; return 1; }
is_recent() { case "$RECENT_SIDS" in *"
$1"*) return 0 ;; esac; return 1; }

# ── 3. sweep the session dirs ─────────────────────────────────────────────────────────────────
cand=0; reaped=0; kept_live=0; kept_young=0; empty=0
while IFS= read -r d; do
  [ -n "$d" ] || continue
  sid=$(basename "$d")
  # Only harness-shaped session dirs. A non-UUID dir under <project>/ is someone else's; leave it.
  [[ "$sid" =~ $UUID_RE ]] || continue
  cand=$((cand + 1))

  if is_live "$sid" || is_recent "$sid"; then
    kept_live=$((kept_live + 1)); continue
  fi

  # "empty" = holds no regular file anywhere beneath it (the 377 dirs-only, 0 KB case). Those skip
  # the age wait — there is nothing to lose — but they have already passed the liveness gate above.
  if [ -z "$(find "$d" -type f -print 2>/dev/null | head -1)" ]; then
    empty=$((empty + 1))
  else
    # Non-empty → must ALSO be older than the horizon.
    # shellcheck disable=SC2086  # AGE_PRED is an intentional multi-word find predicate
    [ -n "$(find "$d" -maxdepth 0 -type d $AGE_PRED 2>/dev/null)" ] || { kept_young=$((kept_young + 1)); continue; }
  fi

  if [ "$APPLY" -eq 1 ]; then
    rm -rf "$d" 2>/dev/null && reaped=$((reaped + 1))
  else
    reaped=$((reaped + 1))
    [ "$JSON" -eq 1 ] || printf 'would-reap  %s\n' "$d"
  fi
done < <(find "$ROOT" -mindepth 2 -maxdepth 2 -type d 2>/dev/null)

case "$APPLY" in 1) mode=apply ;; *) mode=dry-run ;; esac
summary="mode=$mode root=$ROOT candidates=$cand reaped=$reaped kept_live=$kept_live kept_young=$kept_young empty=$empty"
if [ "$JSON" -eq 1 ]; then
  jq -nc --arg root "$ROOT" --arg mode "$mode" --argjson c "$cand" --argjson r "$reaped" \
         --argjson kl "$kept_live" --argjson ky "$kept_young" --argjson e "$empty" \
    '{root:$root,mode:$mode,status:"ok",candidates:$c,reaped:$r,kept_live:$kl,kept_young:$ky,empty:$e}'
else
  echo "scratchpad-reaper: $summary"
fi
# Only an APPLY run that actually changed the tree is worth a log line (a 288×/day dry-run must not
# become the growth surface it exists to bound).
[ "$APPLY" -eq 1 ] && [ "$reaped" -gt 0 ] && log_line "$summary"
exit 0
