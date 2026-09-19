#!/usr/bin/env bash
# lr-fleet.sh — /limit-recover fleet: every limit-blocked session located, each one continued IN ITS
# OWN PANE on an unrestricted account, no husk, no orphan, no ambiguity left behind
# (docs/plans/LIMIT_RECOVER_100P.md, operator ruling 2026-09-08).
#
# Usage: lr-fleet.sh --locate [--json]                 census: every limit-blocked session, its pane, tier, disposition
#        lr-fleet.sh --recover [--target A|auto] [--dry-run] [--max N]
#                                                     sequenced in-place recovery of every RECOVERABLE session
#        lr-fleet.sh --one SID --target A [--source-pane P] [--from-daemon] [--detach]
#                                                     one session (the unit the poller's request drain runs);
#                                                     --detach returns in ≤3s and mails the verdict back
#        lr-fleet.sh --enqueue [--target A]           hand every RECOVERABLE session to the launchd poller
#        lr-fleet.sh --duplicates [--mark SID --live PID]
#                                                     sessions held by MORE than one live process; --mark writes
#                                                     the SUPERSEDED tombstone that retires the stale copy
#        lr-fleet.sh --report [DIR]                   the fleet report for the last (or named) run
#
# THE DESIGN, in one line: one actuator, two callers. The actuator is lr-handoff.sh --in-place, which
# transplants the session and then RECYCLES ITS OWN PANE onto the target (handoff-fire.sh --recycle's
# remote form: /exit typed into the blocked TUI, the same uuid relaunched in the surviving shell — same
# window id, new account). This script is the fleet front end: it LOCATES (transcripts × registry),
# SEQUENCES (one at a time, engagement-gated, behind the NON-charging capacity probe — a pane is never
# exited unless its relaunch can be admitted, and the probe never spends the refusal budget), and
# REPORTS in a form where "which pane do I work from" cannot arise: pane before == pane after.
# When a session's own tool is refused (auto-mode classifier), --enqueue hands the same request to
# lr-reset-poller.sh, a LaunchAgent that runs outside every session and every classifier.
#
# Iron rule 7 binds: this script never pushes, ships or deploys. Exit 0 = every located session
# recovered (or nothing to do); 1 = PARTIAL, named gaps in the report; 2 = usage/refused.
set -uo pipefail

_LF_SELF="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
LR="$(cd "$(dirname "$_LF_SELF")" && pwd)"
for _lf_lib in "$LR/lr-lib.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh" "$HOME/.claude/scripts/limit-recover/lr-lib.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved library ladder
  [ -f "$_lf_lib" ] && { LR_LIB_DIR="$(cd "$(dirname "$_lf_lib")" && pwd)"; export LR_LIB_DIR; . "$_lf_lib"; break; }
done
command -v lr_registry_live_rows >/dev/null 2>&1 || { echo "lr-fleet: FATAL — lr-lib.sh not found beside $LR" >&2; exit 2; }
for _lf_cap in "$LR/../lib/capacity-admit.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh" "$HOME/.claude/scripts/lib/capacity-admit.sh"; do
  # shellcheck disable=SC1090
  [ -f "$_lf_cap" ] && { . "$_lf_cap" 2>/dev/null || true; break; }
done
for _lf_am in "${CC_ACCOUNT_MAP:-}" "$LR/../../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  # shellcheck disable=SC1090
  [ -n "$_lf_am" ] && [ -f "$_lf_am" ] && { . "$_lf_am"; break; }
done
# Resolve a sid PREFIX to the one full sid it names. `--locate` renders ${sid:0:8}, so its own
# printed SID column was rejected by --one/--mark ("no transcript in any store") and the caller had
# to round-trip through --locate --json. An identifier a tool prints must be one it accepts.
# REFUSES an ambiguous prefix rather than picking: two sessions sharing 8 hex chars is rare, and
# silently recovering the wrong one is unrecoverable.
lf_resolve_sid() { # $1=sid-or-prefix -> full sid on stdout; rc 2 = ambiguous, rc 1 = no match
  local want="$1" c f b hits="" n=0
  case "$want" in *[!0-9a-fA-F-]*|"") printf '%s' "$want"; return 0 ;; esac
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    for f in "$c"/projects/*/"$want"*.jsonl; do
      [ -f "$f" ] || continue
      b="$(basename "$f" .jsonl)"
      case "$hits" in *" $b "*) continue ;; esac
      hits="$hits $b "; n=$((n+1))
    done
  done <<EOF
$(lr_config_dirs)
EOF
  [ "$n" -eq 1 ] || { [ "$n" -eq 0 ] && return 1; printf '%s' "$hits" >&2; return 2; }
  printf '%s' "$hits" | tr -d ' '
}
STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
FLEET_DIR="$STATE/fleet"; mkdir -p "$FLEET_DIR" 2>/dev/null || true
HANDOFF="${LR_HANDOFF_BIN:-$LR/lr-handoff.sh}"
ACCOUNTS="${CC_ACCOUNTS_BIN:-$HOME/bin/claude-accounts}"

MODE="" TARGET="auto" DRY=0 MAX=0 SID="" SOURCE_PANE="" FROM_DAEMON=0 JSON=0 MARK_SID="" LIVE_PID="" REPORT_DIR="" DETACH=0
LF_ARGV=("$@")                  # verbatim, for the --detach re-exec (the child re-parses, never a rebuild)
while [ $# -gt 0 ]; do
  case "$1" in
    --locate) MODE=locate; shift ;;
    --recover) MODE=recover; shift ;;
    --one) MODE=one; SID="${2:?--one needs a sid}"; shift 2 ;;
    --enqueue) MODE=enqueue; shift ;;
    --duplicates) MODE=duplicates; shift ;;
    --report) MODE=report; [ -n "${2:-}" ] && [ "${2#-}" = "$2" ] && { REPORT_DIR="$2"; shift; }; shift ;;
    --target) TARGET="${2:?--target needs an account}"; shift 2 ;;
    --source-pane) SOURCE_PANE="${2:?--source-pane needs a pane id}"; shift 2 ;;
    --from-daemon) FROM_DAEMON=1; shift ;;
    --detach) DETACH=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --max) MAX="${2:?--max needs a number}"; shift 2 ;;
    --json) JSON=1; shift ;;
    --mark) MARK_SID="${2:?--mark needs a sid}"; shift 2 ;;
    --live) LIVE_PID="${2:?--live needs a pid}"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "lr-fleet: unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$MODE" ] || { echo "lr-fleet: one of --locate | --recover | --one SID | --enqueue | --duplicates | --report is required" >&2; exit 2; }

lf_acct_of_cfg() { # $1=cfg dir → account name (next|next2|…) via the generated map, else the basename
  local n
  n="$(cc_acct_name_for_dir_basename "$(basename "${1%/}")" 2>/dev/null || true)"
  [ -n "$n" ] && printf '%s' "$n" || printf '%s' "$(basename "${1%/}")"
}
lf_now() { date -u +%FT%TZ; }

# ── LOCATE: the census, disk truth only ──────────────────────────────────────────────────────────
# One line per limit-blocked session: sid · cfg · account · pane · pid · cwd · tier · disposition.
# Dispositions: RECOVERABLE (live pane, not transplanted) · TRANSPLANTED (a successor exists elsewhere)
# · NO-PANE (no live process holds it: the poller's spawn-at-reset domain, or --recover spawns a
# visible pane for it) · TEAMMATE (lead-owned recovery) · DUPLICATE (more than one live process).
LIMIT_RE="You've (hit|reached) your (session|weekly|fast|monthly spend|Fable)? ?limit"
# 'reached'/'Fable' widen a predicate that was blind to the MODEL-SCOPED weekly cap: Fable
# exhaustion says "You've reached your Fable limit. Run /usage-credits to continue" -- a different
# VERB and a different noun from every cap above, so three live Fable/max panes on `next` sat
# blocked for 5h while --locate reported them absent (2026-09-10). Same shape as the ENOTFOUND
# miss below: the envelope was right and only the TEXT excluded them, which is what makes
# widening safe here too.
# A session can be dead-in-turn for reasons that are NOT a cap, and the census used to be blind to
# every one of them (2026-09-09, operator report: six panes killed by one DNS outage, `--locate` said
# "(no limit-blocked session anywhere)"). Measured on the real records: the ENOTFOUND death carries
# the SAME structural envelope as a cap -- type:assistant, isApiErrorMessage:true, error:"server_error",
# model:"<synthetic>" -- so only the TEXT predicate excluded it, never the shape. Keeping the envelope
# gate is what makes this safe to widen: a session merely DISCUSSING "ENOTFOUND" in prose (this repo
# does, constantly) is not a synthetic api-error record and can never match.
NET_RE="(Can't reach the API server|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|socket hang up)"
BLOCK_RE="($LIMIT_RE|$NET_RE)"
# Which class a row is decides WHICH RECOVERY IS EVEN LEGAL, so it is a column, not a footnote:
#   limit   -> the account is out of quota; the fix is a transplant to another account (--recover).
#   network -> the account is FINE and the pane is usually still alive; transplanting would spend an
#              account move to fix a problem that no longer exists. The fix is `/limit-recover resume`
#              IN PLACE. --recover therefore refuses these by default rather than "helpfully" moving them.
# D7 (NONLIMIT_RESUME_LADDER § W1.2): the CLASS IS PER UNIT, AND CLASSES MIX IN ONE SESSION.
# Measured: one workflow run held a `[security] failed: You've hit your session limit` slot INSIDE a
# network-stalled run. So this prints two fields:
#
#   kind   the class of the LAST api-error record — the DECISION key, because that is the death the
#          session is currently sitting on and it decides which recovery is legal.
#   kinds  every class present in the tail, joined by '+' — reported so a mixed row is VISIBLE
#          rather than silently collapsed to whichever class the decision picked.
#
# The old form grepped the WHOLE 20 KB tail for the limit text and answered `limit` if any line
# matched, so a session whose last death was a network drop but which had hit a cap earlier in the
# tail was classified `limit` — and `--recover`/`--enqueue` would then spend an account move to fix
# a problem that no longer exists, which is the exact error the kind column was added to prevent.
# Classifying the LAST record fixes that; `kinds` keeps the earlier class from being lost.
lf_kinds_of() { # $1=tail -> "<kind>\t<kinds>"
  printf '%s' "$1" | LF_LIMIT_RE="$LIMIT_RE" LF_NET_RE="$NET_RE" /usr/bin/python3 -c '
import json,os,re,sys
lim=re.compile(os.environ["LF_LIMIT_RE"]); net=re.compile(os.environ["LF_NET_RE"])
last=None; seen=[]
for l in sys.stdin:
    if "isApiErrorMessage" not in l: continue
    try: d=json.loads(l)
    except Exception: continue
    # The ENVELOPE gate, kept verbatim: only a synthetic api-error record counts, so a session
    # merely DISCUSSING one of these strings in prose can never be classified by it.
    if d.get("type")!="assistant" or not d.get("isApiErrorMessage"): continue
    m=d.get("message") if isinstance(d.get("message"),dict) else {}
    c=m.get("content")
    txt=c if isinstance(c,str) else " ".join(x.get("text","") for x in (c or []) if isinstance(x,dict))
    k="limit" if lim.search(txt) else ("network" if net.search(txt) else "other")
    last=k
    if k not in seen: seen.append(k)
print("%s\t%s" % (last or "network", "+".join(seen) or "network"))'
}
# The AGE of that last api-error record, in seconds. A census snapshot of "blocked" rows EXPIRES:
# all six panes measured on 2026-09-09 were re-engaged within ~40 minutes, so a row read without its
# age invites acting on a session that recovered an hour ago.
lf_err_age_s() { # $1=tail -> seconds, or "-"
  printf '%s' "$1" | /usr/bin/python3 -c '
import json,sys
from datetime import datetime,timezone
ts=None
for l in sys.stdin:
    if "isApiErrorMessage" not in l: continue
    try: d=json.loads(l)
    except Exception: continue
    if d.get("type")!="assistant" or not d.get("isApiErrorMessage"): continue
    ts=d.get("timestamp") or ts
if not ts: print("-"); raise SystemExit(0)
try:
    t=datetime.fromisoformat(ts.replace("Z","+00:00"))
    print(int((datetime.now(timezone.utc)-t).total_seconds()))
except Exception: print("-")'
}
lf_locate() { # → TSV rows on stdout
  local cfg tx sid tail rows pane pid acct cwd tier disp n kind kinds err_age _procs
  while IFS= read -r cfg; do
    [ -n "$cfg" ] || continue
    for tx in "$cfg"/projects/*/*.jsonl; do
      [ -f "$tx" ] || continue
      sid="$(basename "$tx" .jsonl)"
      case "$sid" in agent-*|wf_*) continue ;; esac
      tail="$(tail -c 20000 "$tx" 2>/dev/null || true)"
      printf '%s' "$tail" | grep -E "$BLOCK_RE" | grep -q '"isApiErrorMessage"[[:space:]]*:[[:space:]]*true' || continue
      IFS=$'\t' read -r kind kinds <<<"$(lf_kinds_of "$tail")"
      [ -n "$kinds" ] || kinds="$kind"
      err_age="$(lf_err_age_s "$tail")"; [ -n "$err_age" ] || err_age="-"
      # the limit must be the LAST assistant word — a session that took a real turn since is not blocked
      printf '%s' "$tail" | /usr/bin/python3 -c '
import json,sys
last=None
for l in sys.stdin:
    if "\"assistant\"" not in l: continue
    try: d=json.loads(l)
    except Exception: continue
    if d.get("type")!="assistant": continue
    m=d.get("message") if isinstance(d.get("message"),dict) else {}
    c=m.get("content"); txt=c if isinstance(c,str) else " ".join(x.get("text","") for x in (c or []) if isinstance(x,dict))
    if txt.strip()=="No response requested.": continue
    last=bool(d.get("isApiErrorMessage"))
sys.exit(0 if last else 1)' || continue
      acct="$(lf_acct_of_cfg "$cfg")"
      if head -c 8000 "$tx" 2>/dev/null | grep '"agentName"' >/dev/null; then disp=TEAMMATE; pane="-"; pid="-"; cwd="-"; tier="-"
      else
        pane="-"; pid="-"; cwd="-"; tier="$(lr_tier_from_transcript "$cfg" "$sid" 2>/dev/null | tr ' ' '/' || true)"; [ -n "$tier" ] || tier="-"
        if rows="$(lr_registry_live_rows "$sid")"; then
          IFS=$'\t' read -r pane pid _ cwd <<<"$(printf '%s\n' "$rows" | head -1)"
          # DISTINCT holders, via the one shared predicate — see lr_holder_count in lr-lib.sh.
          if [ "$(lr_holder_count "$sid")" -gt 1 ]; then disp=DUPLICATE; else disp=RECOVERABLE; fi
        elif _procs="$(lr_resume_procs "$sid" 2>/dev/null)"; then
          # D7 — THE REGISTRY HOLE, FILLED FROM THE ARGV LEAF. A session whose SessionStart hook
          # never wrote a row (or whose row went stale) has no registry pid, and this branch used to
          # leave pid "-" while asserting RESUMING. Measured 2026-09-09: `lr_registry_live_rows`
          # returned rc 1 for 52e35019 while pid 77720 held `claude … --resume 52e35019…`, alive
          # since Sep 8 19:51 — a live process reported with no pid at all. The argv census already
          # knows that pid; take it.
          disp=RESUMING; pid="$(printf '%s\n' "$_procs" | head -1)"; [ -n "$pid" ] || pid="-"
          cwd="$(grep -o '"cwd":"[^"]*"' "$tx" 2>/dev/null | tail -1 | cut -d'"' -f4 || true)"; [ -n "$cwd" ] || cwd="-"
        else disp=NO-PANE; cwd="$(grep -o '"cwd":"[^"]*"' "$tx" 2>/dev/null | tail -1 | cut -d'"' -f4 || true)"; [ -n "$cwd" ] || cwd="-"
          # A reaped worktree cannot host a resume. Measured 2026-09-12: a fleet --recover dry-run
          # offered 9 stale NO-PANE sessions, 3 of whose cwds no longer exist — a spawn there dies
          # in a missing directory. This is a NAMED gap, never a by-design skip: work may be
          # stranded and only a human can decide whether the tree is worth recreating.
          [ "$cwd" = "-" ] || [ -d "$cwd" ] || disp=CWD-GONE
        fi
        if _to="$(lr_transplanted_to "$sid" "$cfg")"; then disp="TRANSPLANTED→$(lf_acct_of_cfg "$_to")"; fi
      fi
      # A network-blocked session with a live pane is IDLE-AFTER-ERROR, not RECOVERABLE: the
      # distinction is the whole point of the kind column, and collapsing it is what would send a
      # transplant at it. RENAMED from RESUME-IN-PLACE (D7): the old name was an INSTRUCTION to the
      # operator ("resume this in place"), and the machine is now the one that acts — while the state
      # it actually names is "the process is alive and sitting at its prompt after an error record".
      # Naming the STATE rather than the remedy is also what stops the row reading as a standing
      # to-do after the session has already re-engaged, which every measured row did within ~40 min.
      [ "$kind" = network ] && [ "$disp" = RECOVERABLE ] && disp=IDLE-AFTER-ERROR
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$sid" "$cfg" "$acct" "$pane" "$pid" "$cwd" "$tier" "$disp" "$kind" "$kinds" "$err_age"
    done
  done <<EOF
$(lr_config_dirs)
EOF
}
# `~/.claude` and `~/.claude-next` are ONE account behind a mirror, so a live `next` session is
# enumerated TWICE and the census double-counts the exact rows an operator is about to act on
# (measured 2026-09-09: 3 of 6 network-blocked live panes appeared twice, once as acct `.claude`).
# The resume-sessions skill has always stated the rule -- "a session in BOTH = one next session" --
# and this census never applied it. Keep the row whose account is NOT the bare mirror.
lf_dedup_mirror() { awk -F'\t' '
  { sid=$1; acct=$3
    if (!(sid in seen)) { ord[++k]=sid; seen[sid]=$0; sacct[sid]=acct }
    else if (sacct[sid]==".claude" && acct!=".claude") { seen[sid]=$0; sacct[sid]=acct } }
  END { for (i=1;i<=k;i++) print seen[ord[i]] }' ; }
lf_print_census() { # stdin: TSV rows
  local sid cfg acct pane pid cwd tier disp n=0 kind kinds err_age agec
  printf '%-9s %-6s %-6s %-7s %-22s %-17s %-14s %-7s %s\n' \
    SID ACCT PANE PID TIER DISPOSITION 'KIND(S)' ERR-AGE CWD
  while IFS=$'\t' read -r sid _cfg acct pane pid cwd tier disp kind kinds err_age; do
    [ -n "$sid" ] || continue; n=$((n+1))
    # The age is rendered, not raw seconds: a row is only actionable while it is FRESH, and every
    # blocked pane measured on 2026-09-09 had re-engaged within ~40 minutes of its error record.
    case "$err_age" in
      ''|-|*[!0-9]*) agec="?" ;;
      *) if [ "$err_age" -lt 90 ]; then agec="${err_age}s"
         elif [ "$err_age" -lt 5400 ]; then agec="$((err_age / 60))m"
         else agec="$((err_age / 3600))h"; fi ;;
    esac
    printf '%-9s %-6s %-6s %-7s %-22s %-17s %-14s %-7s %s\n' \
      "${sid:0:8}" "$acct" "$pane" "$pid" "$tier" "$disp" "${kinds:-${kind:--}}" "$agec" "$cwd"
  done
  [ "$n" -gt 0 ] || echo "(no blocked session anywhere — no cap, no network/stall death)"
}

# ── THE PHANTOM-ACTIVE CORRECTION (2026-09-19) — why a recovery could never be admitted ─────────
# A usage-limit kill ends the turn WITHOUT running the Stop hook, so hooks/session-beat.sh never
# writes the `stop` beat and the session's `kind:"prompt"` beat freezes on disk. Its pid stays alive
# (the TUI is sitting at its prompt), so cc_sp_active's liveness leg — which correctly discards a
# DEAD session's frozen beat — has nothing to discard, and the blocked session is counted mid-turn
# forever. spawn-presence.sh's own header calls this shape "a gate that tightens monotonically on
# its own accidents"; the limit kill is the door its pid check cannot close.
#
# MEASURED 2026-09-19: eight panes blocked on one account's 5-hour limit held frozen `prompt` beats
# aged 2360-4168 s with live pids. cc_sp_active read 12 against a ceiling of 8, so EVERY
# `lr-fleet --recover` attempt was refused for its full 600 s budget. The census inflated BY the
# blocked sessions was gating the recovery OF those blocked sessions — a deadlock with no supported
# escape, since lr-reset-poller and `--from-daemon` take the same probe.
#
# THE CORRECTION LIVES HERE, NOT IN THE CENSUS, because this is the only caller that already knows
# which sessions are blocked — it is the tool whose whole job is to census them. A general fix in
# cc_sp_active needs a discriminator that separates "blocked" from "mid-turn" for EVERY caller, and
# the obvious one is refuted: measured the same day, blocked sessions' transcripts are still being
# written (mtime ages 201-2711 s), so file freshness does not separate the two populations. That
# design call is filed, not guessed at here.
#
# DIRECTION: this only ever SUBTRACTS sessions proven blocked — a live pid whose beat is a frozen
# `prompt` AND whose last assistant word is a usage-limit error. A session mid-retry after a network
# error is NOT subtracted (its turn may genuinely still be running, 93-101 min measured), an
# unreadable transcript is NOT subtracted, and the ceiling itself is untouched. Recovery is also
# net-zero on process count: it /exits one TUI and relaunches the same uuid in the same pane.
lf_phantom_actives() { # → count of live sessions whose mid-turn beat is a usage-limit corpse
  local dir b sid pid kind cfg tx n=0 rest ekind
  dir="${CC_BEAT_DIR:-$HOME/.claude/cc-beats}"
  [ -d "$dir" ] || { printf '0'; return 0; }
  for b in "$dir"/*.json; do
    [ -f "$b" ] || continue
    kind="$(jq -r 'if type=="object" then (.kind // "") else "" end' "$b" 2>/dev/null)" || continue
    [ "$kind" = prompt ] || continue
    pid="$(jq -r 'if type=="object" then (.pid // "") else "" end' "$b" 2>/dev/null)"
    case "$pid" in ''|*[!0-9]*) continue ;; esac
    kill -0 "$pid" 2>/dev/null || continue          # dead ⇒ the census already discards it
    sid="$(jq -r 'if type=="object" then (.sid // "") else "" end' "$b" 2>/dev/null)"
    case "$sid" in ''|*[!A-Za-z0-9-]*) continue ;; esac
    while IFS= read -r cfg; do
      [ -n "$cfg" ] || continue
      for tx in "$cfg"/projects/*/"$sid".jsonl; do
        [ -f "$tx" ] || continue
        IFS=$'	' read -r _ _ ekind rest <<<"$(lr_last_api_error "$tx" 2>/dev/null)" || ekind=""
        [ "$ekind" = limit ] && { n=$((n + 1)); break 3; }
      done
    done <<EOF
$(lr_config_dirs)
EOF
  done
  printf '%s' "$n"
}

# ── THE CAUSE, JOINED (W1, LIMIT_RECOVER_100P § 12.1) ────────────────────────────────────────────
# A PARTIAL's cause is already on disk at the moment it happens and nothing read it. The relaunch is
# re-gated inside the pane by `lr-fire-resume`, a process this driver cannot parameterise, and its
# refusal lands in the IDL carrying the TERM that refused (`capacity-admit.sh:418`). All 10 refusals
# on the morning of 2026-09-19 were `term=load` — a term capacity-admit's own comment (`:149-160`)
# documents as WRONG INPUT, and which is OFF for the Agent tool and for the operator's fire but ON
# for exactly this caller. Without the join, every rc-4 row read as an unexplained failure and the
# operator re-derived it by hand; with it, the note names the term and the next question is obvious.
#
# The join key is the sid inside `.what` ("resume <sid> on <acct>"), NOT `.sid`: lr-fire-resume does
# not set CC_ADMIT_SID, so `.sid` is the literal "?" on every row it writes. grep -F first keeps this
# O(matching lines) over a 91k-row ledger instead of O(ledger) through jq.
lf_idl_cause() { # $1=sid [$2=ISO floor] → "term=<t> …" for its newest lr-fire-resume refusal, else ""
  local idl row t0="${2:-}"
  idl="${CC_ADMIT_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
  [ -n "${1:-}" ] && [ -f "$idl" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  row="$(grep -F "$1" "$idl" 2>/dev/null | jq -c --arg t0 "${t0%Z}" \
           'select(.caller=="lr-fire-resume" and .verdict=="refuse")
            | select($t0 == "" or ((.ts // "")|sub("Z$";"")) >= $t0)' 2>/dev/null | tail -1)" || row=""
  [ -n "$row" ] || return 0
  printf 'launcher REFUSED %s: term=%s basis=%s — %s' \
    "$(printf '%s' "$row" | jq -r '.ts // "?"' 2>/dev/null)" \
    "$(printf '%s' "$row" | jq -r '.term // "?"' 2>/dev/null)" \
    "$(printf '%s' "$row" | jq -r '.basis // "?"' 2>/dev/null)" \
    "$(printf '%s' "$row" | jq -r '.detail // "?"' 2>/dev/null)"
}

# ── CAPACITY: wait on the NON-charging probe, never spend the budget ─────────────────────────────
lf_capacity_wait() { # $1=what → 0 admitted / 1 parked at the cap
  local waited=0 max="${LR_FLEET_CAP_WAIT_S:-600}" ivl="${LR_FLEET_CAP_IVL_S:-20}"
  command -v cc_capacity_probe >/dev/null 2>&1 || { echo "lr-fleet: capacity probe unavailable — proceeding UNGATED" >&2; return 0; }
  local raw ph corrected
  while :; do
    # Correct the ACTIVE term for limit-corpse beats before each probe (see the header above). Left
    # unset on any unreadable leg, so the probe then sees exactly what it saw before this existed.
    unset CC_SP_ACTIVE_OVERRIDE
    if [ "${LR_FLEET_PHANTOM_CORRECTION:-on}" != off ] && command -v cc_sp_active >/dev/null 2>&1; then
      raw="$(cc_sp_active 2>/dev/null || true)"
      ph="$(lf_phantom_actives 2>/dev/null || true)"
      case "${raw:-x}${ph:-x}" in
        *[!0-9]*) : ;;
        *) if [ "$ph" -gt 0 ]; then
             corrected=$(( raw - ph )); [ "$corrected" -lt 0 ] && corrected=0
             export CC_SP_ACTIVE_OVERRIDE="$corrected"
             echo "lr-fleet: active census ${raw} includes ${ph} limit-corpse beat(s) — probing at ${corrected}" >&2
           fi ;;
      esac
    fi
    if cc_capacity_probe lr-fleet "$1"; then unset CC_SP_ACTIVE_OVERRIDE; return 0; fi
    unset CC_SP_ACTIVE_OVERRIDE
    # The park's REASON, carried out of this function rather than only printed. `LF_PARK_REASON` is
    # what the caller folds into the results row: a row reading `parked | capacity` said which gate
    # refused and never which TERM, so the one fact that decides the next action (shed load? close
    # panes? wait for the 5-hour window?) was in a stderr line nobody keeps (U05 P4).
    if [ "$waited" -ge "$max" ]; then
      LF_PARK_REASON="$(cc_capacity_admit_reason 2>/dev/null || true)"
      echo "lr-fleet: PARKED on capacity after ${waited}s — $LF_PARK_REASON" >&2; return 1
    fi
    echo "lr-fleet: capacity not admitted yet — $(cc_capacity_admit_reason); waiting ${ivl}s (${waited}/${max}s)" >&2
    sleep "$ivl"; waited=$((waited + ivl))
  done
}

# ── ONE: the unit — one session, in place ────────────────────────────────────────────────────────
lf_pick_target() { # $1=source account $2=tier → account name on stdout / rc 1
  local kind=general t
  case "$2" in claude-fable-*) kind=fable ;; esac
  [ "$TARGET" != auto ] && { printf '%s' "$TARGET"; return 0; }
  [ -x "$ACCOUNTS" ] || return 1
  # --rank, then walk past the SOURCE account: the router may well rank the limited account first on
  # weekly headroom while its 5-hour window is what just closed.
  t="$("$ACCOUNTS" --rank "$kind" 2>/dev/null | awk -v s="$1" '$1 != s { print $1; exit }' || true)"
  # `none` is the router's SENTINEL for "nothing is routable", not an account. Taken literally it
  # passes the `!= source` test below, so the caller waited out the full capacity budget and then
  # handed off to an account that does not exist -- observed 2026-09-10, the poller's own log reading
  # "in-place recovery of 2d71c6d8 onto none" for 480s. An unroutable moment must PARK immediately.
  [ "$t" = none ] && t=""
  [ -n "$t" ] || return 1
  printf '%s' "$t"
}
lf_one() { # $1=sid $2=cfg $3=acct $4=pane $5=cwd $6=tier → rc of the recovery; prints the result row
  local sid="$1" cfg="$2" acct="$3" pane="$4" cwd="$5" tier="$6" target rc=0 out rdir="$FLEET_DIR/$RUN" model="" effort=""
  mkdir -p "$rdir"
  target="$(lf_pick_target "$acct" "$tier")" || { echo "lr-fleet: $sid — no routable target account (claude-accounts --rank returned nothing past $acct)" >&2; lf_row "$sid" "$pane" "$pane" "$acct" "-" "parked" "no routable target"; return 1; }
  [ "$target" != "$acct" ] || { lf_row "$sid" "$pane" "$pane" "$acct" "$target" "parked" "target is the limited account"; return 1; }
  case "$tier" in */*) model="${tier%%/*}"; effort="${tier#*/}" ;; esac
  if [ "$DRY" = 1 ]; then
    echo "lr-fleet: DRY — would recover ${sid:0:8}: pane ${pane:-<new>} on $acct → $target (tier ${tier:-default}) via: $HANDOFF --sid $sid --config-dir $cfg --cwd $cwd --target $target --launch --in-place${pane:+ --source-pane $pane}${model:+ --model $model}${effort:+ --effort $effort}"
    lf_row "$sid" "$pane" "$pane" "$acct" "$target" "dry-run" "-"; return 0
  fi
  local t0; t0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # the IDL floor: only refusals from THIS attempt count
  # The park now names the gate's own reason AND, when the launcher has already been refused for this
  # sid, the term that refused it — the two facts that decide whether to shed load, close panes, or
  # wait out a window. `capacity` alone said none of them.
  LF_PARK_REASON=""
  lf_capacity_wait "in-place recovery of ${sid:0:8} onto $target" || {
    local pnote="capacity${LF_PARK_REASON:+ — $LF_PARK_REASON}" pcause
    pcause="$(lf_idl_cause "$sid" "$t0" || true)"; [ -n "$pcause" ] && pnote="$pnote; $pcause"
    lf_row "$sid" "$pane" "$pane" "$acct" "$target" "parked" "$pnote"; return 1; }
  local args=(--sid "$sid" --config-dir "$cfg" --cwd "$cwd" --target "$target" --launch --in-place)
  [ -n "$pane" ] && [ "$pane" != "-" ] && args+=(--source-pane "$pane")
  [ -n "$model" ] && args+=(--model "$model"); [ -n "$effort" ] && args+=(--effort "$effort")
  echo "lr-fleet: recovering ${sid:0:8} — pane ${pane:-<new>} on $acct → $target (tier ${tier:-default})$([ "$FROM_DAEMON" = 1 ] && printf ' [daemon-run: lr-reset-poller request drain]')" >&2
  out="$("$HANDOFF" "${args[@]}" 2> >(tee "$rdir/$sid.stderr" >&2))" || rc=$?
  printf '%s\n' "$out" > "$rdir/$sid.stdout"
  local pane_after="$pane" mech="recycle-in-place" verdict="RECOVERED" note="-"
  if grep -q 'REPLACED in place' "$rdir/$sid.stderr" 2>/dev/null; then
    mech="replace-in-place"; pane_after="$(grep -o 'successor pane [0-9]*' "$rdir/$sid.stderr" | head -1 | awk '{print $3}')"; [ -n "$pane_after" ] || pane_after="?"
  elif grep -q 'fired split pane\|fired new kitty window' "$rdir/$sid.stderr" 2>/dev/null; then
    mech="spawn"; pane_after="new"
  fi
  local cause; cause="$(lf_idl_cause "$sid" "$t0" || true)"
  case "$rc" in
    0) : ;;
    4) verdict="PARTIAL"; note="transplanted but the relaunch did not verify — source is a tombstoned husk; ${cause:-no launcher refusal in the IDL for this attempt — read the watcher log}; see $rdir/$sid.stderr" ;;
    *) verdict="FAILED"; note="lr-handoff rc=$rc${cause:+; $cause}; see $rdir/$sid.stderr" ;;
  esac
  # A PROOF THAT CAN FAIL. `pane_after` was initialised to `pane` and only ever moved when
  # lr-handoff ANNOUNCED a new pane, so the report's headline claim — "N in place (same pane id)" —
  # was true by construction on the recycle path: a relaunch that died between `/exit` and
  # SessionStart rendered byte-identically to one that came back. The registry row is REWRITTEN on
  # every SessionStart (startup, resume, compact), so reading it back after the run is the one
  # cheap check whose failure means exactly what it says. Only the recycle path is proved this way:
  # the replace and spawn paths take the pane id from the successor's own announcement, and the
  # registry read would overwrite a correct new pane with the SOURCE's stale row.
  if [ "$mech" = recycle-in-place ]; then
    local _after
    _after="$(lr_registry_live_rows "$sid" 2>/dev/null | head -1 | cut -f1 || true)"
    if [ -n "$_after" ]; then
      pane_after="$_after"
    else
      pane_after="?"
      [ "$note" = "-" ] && note="no live registry row names this session after the run — the in-place claim is UNPROVEN; see $rdir/$sid.stderr"
    fi
  fi
  lf_row "$sid" "$pane" "$pane_after" "$acct" "$target" "$mech/$verdict" "$note"
  return "$rc"
}
lf_row() { # sid pane_before pane_after acct_before acct_after mechanism/verdict note → appended to the run's results.tsv
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$(lf_now)" >> "$FLEET_DIR/$RUN/results.tsv"
}
lf_report() { # $1=run dir
  local d="$1" f="$1/results.tsv" sid pb pa ab aa mv note n=0 inplace=0 newp=0 gaps=0 bydesign=0
  [ -f "$f" ] || { echo "lr-fleet: no results in $d"; return 1; }
  echo "FLEET RECOVERY — $(basename "$d")"
  printf '%-9s %-8s %-8s %-7s %-7s %-26s %s\n' SID "PANE→" "PANE←" "ACCT→" "ACCT←" MECHANISM/VERDICT NOTE
  while IFS=$'\t' read -r sid pb pa ab aa mv note _ts; do
    [ -n "$sid" ] || continue; n=$((n+1))
    printf '%-9s %-8s %-8s %-7s %-7s %-26s %s\n' "${sid:0:8}" "${pb:--}" "${pa:--}" "$ab" "$aa" "$mv" "$note"
    # `?` is the recycle path's UNPROVEN pane (lf_one): lr-handoff returned 0 but no registry row
    # names the session afterwards. Counting it as "replaced beside their source" would launder the
    # one state this column was made able to report into a success.
    case "$mv" in
      *RECOVERED) if [ "$pa" = "?" ]; then gaps=$((gaps+1))
                  elif [ "$pa" = "$pb" ]; then inplace=$((inplace+1))
                  else newp=$((newp+1)); fi ;;
      *by-design) bydesign=$((bydesign+1)) ;;
      *dry-run) : ;;
      *) gaps=$((gaps+1)) ;;
    esac
  done < "$f"
  echo
  if [ "$gaps" -eq 0 ]; then
    echo "RECOVERY COMPLETE — $inplace in place (same pane id), $newp replaced beside their source, 0 left over ($n session(s), $bydesign not owed: teammate/resuming/already-transplanted; evidence: $d)"
  else
    echo "RECOVERY PARTIAL — $gaps named gap(s) above ($inplace in place, $newp replaced, $bydesign not owed; evidence: $d)"
  fi
  [ "$gaps" -eq 0 ]
}

case "$MODE" in
  locate)
    rows="$(lf_locate | lf_dedup_mirror)"
    if [ "$JSON" = 1 ]; then
      printf '%s\n' "$rows" | /usr/bin/python3 -c '
import sys,json
out=[]
for l in sys.stdin:
    p=l.rstrip("\n").split("\t")
    # 11 fields since D7 added kinds and err_age_s beside KIND. A hard count gate here is a
    # SILENT data-loss bug: a stale width made the skip drop EVERY row and --json returned a valid
    # empty list at exit 0, which any consumer reads as "no blocked sessions". Keep it exact, and
    # keep it in step with the printf in lf_locate and every tab-split read of a locate row — TAB is
    # IFS whitespace, so a reader naming N variables over N+1 fields folds the remainder into the
    # LAST one, silently, at exit 0.
    if len(p)!=11: continue
    out.append(dict(zip(["sid","cfg","account","pane","pid","cwd","tier","disposition",
                         "kind","kinds","err_age_s"],p)))
print(json.dumps(out,indent=1))'
    else printf '%s\n' "$rows" | lf_print_census; fi
    exit 0 ;;
  recover)
    RUN="$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "$FLEET_DIR/$RUN"; : > "$FLEET_DIR/$RUN/results.tsv"
    rows="$(lf_locate | lf_dedup_mirror)"; printf '%s\n' "$rows" > "$FLEET_DIR/$RUN/census.tsv"
    printf '%s\n' "$rows" | lf_print_census >&2
    n=0; worst=0
    while IFS=$'\t' read -r sid cfg acct pane pid cwd tier disp kind kinds err_age; do
      [ -n "$sid" ] || continue
      case "$disp" in
        RECOVERABLE) : ;;
        # Both spellings: census.tsv files from earlier runs are on disk carrying the old name, and
        # a disposition this branch does not recognise falls to the `*)` arm below, which merely
        # reports it — so an unrecognised RESUME-IN-PLACE would look handled while saying nothing
        # useful. Accept the old name until no stored census carries it.
        IDLE-AFTER-ERROR|RESUME-IN-PLACE) lf_row "$sid" "$pane" "$pane" "$acct" "-" "skipped" "network/stall death, NOT a cap — this account is fine and the process is alive; recover IN PLACE (/recover, or /limit-recover) in pane $pane — error record ${err_age}s old"; continue ;;
        NO-PANE) pane="-" ;;
        DUPLICATE) lf_row "$sid" "$pane" "$pane" "$acct" "-" "parked" "DUPLICATE — more than one live process; resolve with --duplicates first"; worst=1; continue ;;
        # BY-DESIGN skips: nothing is owed by anyone. A teammate is lead-owned (this command's
        # own doc: the poller deliberately skips teammate transcripts), an already-TRANSPLANTED
        # session has been moved, and RESUMING is held by a live pid whose documented action is
        # NONE. Counting them as gaps made fleet --recover report PARTIAL on every possible run —
        # 20 teammates alone guaranteed it — so the verdict carried no information at all.
        TEAMMATE|RESUMING|TRANSPLANTED*) lf_row "$sid" "$pane" "$pane" "$acct" "-" "skipped/by-design" "$disp"; continue ;;
        CWD-GONE) lf_row "$sid" "$pane" "$pane" "$acct" "-" "skipped" "CWD-GONE — $cwd no longer exists; a resume cannot be spawned there"; continue ;;
        *) lf_row "$sid" "$pane" "$pane" "$acct" "-" "skipped" "$disp"; continue ;;
      esac
      [ "$MAX" -gt 0 ] && [ "$n" -ge "$MAX" ] && { lf_row "$sid" "$pane" "$pane" "$acct" "-" "parked" "--max $MAX reached"; worst=1; continue; }
      n=$((n+1))
      lf_one "$sid" "$cfg" "$acct" "$pane" "$cwd" "$tier" || worst=1
    done <<EOF
$rows
EOF
    echo "$FLEET_DIR/$RUN" > "$FLEET_DIR/last"
    lf_report "$FLEET_DIR/$RUN" || worst=1
    exit "$worst" ;;
  one)
    # ── --detach: the invoking session gets its turn back (W1, LIMIT_RECOVER_100P § 12.1) ─────────
    #
    # THE DEFECT. `--one` is a 115–658 s call (U14 §2.1) and it was always made in the FOREGROUND of
    # a session's Bash tool. On 2026-09-19 that cost the lead 24.4 turn-minutes across 17 polls —
    # every one of which exited 1–5 s AFTER a task-notification that would have woken it anyway —
    # and queued 86 min 52 s of operator-visible screenshots behind those turns (U11 §2).
    #
    # THE FIX IS A PROCESS BOUNDARY, NOT A SHORTER WAIT. The driver is re-exec'd under setsid
    # (scripts/lib/detach.sh, lifted from handoff-fire's own `detach`), so it survives the caller's
    # tool-call process group being reaped, and the verdict comes back as MAIL — the transport that
    # reaches a session at a safe boundary instead of racing its input line. The caller is handed the
    # run dir and the log path and is expected to END ITS TURN (commands/limit-recover.md § The fast
    # path); a foreground `until` poll over this log re-creates the very defect it closes.
    #
    # The child re-parses the SAME argv (LF_ARGV) with LR_FLEET_DETACHED=1 and an inherited RUN, so
    # there is exactly one copy of the option semantics. Everything expensive — the census, the
    # capacity park, the actuator — happens on the far side of this branch.
    if [ "$DETACH" = 1 ] && [ "${LR_FLEET_DETACHED:-0}" != 1 ]; then
      RUN="${LR_FLEET_RUN:-one-$(date -u +%Y%m%dT%H%M%SZ)}"; mkdir -p "$FLEET_DIR/$RUN"
      _lf_log="$FLEET_DIR/$RUN/detached.log"; : > "$_lf_log"
      _lf_det=""
      for _d in "$LR/../lib/detach.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/detach.sh" "$HOME/.claude/scripts/lib/detach.sh"; do
        # shellcheck disable=SC1090  # runtime-resolved library ladder, as everywhere else in this file
        [ -f "$_d" ] && { . "$_d"; _lf_det="$_d"; break; }
      done
      [ -n "$_lf_det" ] || { echo "lr-fleet: --detach cannot reach scripts/lib/detach.sh — refusing to run BLOCKING under a flag that promises not to" >&2; exit 2; }
      # The REQUESTER is resolved HERE, in the invoking session's own environment — the child has no
      # way to re-derive it. Empty is legal: the notifier falls back to the desk ROLE, which
      # cc-notify resolves at SEND time (a frozen uuid is a stale address the moment a pane recycles).
      _lf_req="${LR_FLEET_NOTIFY_PANE:-}"
      [ -n "$_lf_req" ] || { _lf_req="${ITERM_SESSION_ID:-}"; _lf_req="${_lf_req##*:}"; }
      [ -n "$_lf_req" ] || _lf_req="${KITTY_WINDOW_ID:-}"
      _lf_pid="$(detach "$_lf_log" /usr/bin/env \
                   LR_FLEET_DETACHED=1 "LR_FLEET_RUN=$RUN" "LR_FLEET_REQUESTER=$_lf_req" LR_INPLACE_AWAIT=0 \
                   bash "$_LF_SELF" "${LF_ARGV[@]}" || true)"
      [ -n "$_lf_pid" ] || { echo "lr-fleet: --detach failed to spawn the driver — nothing was started" >&2; exit 2; }
      echo "lr-fleet: DETACHED — driver pid $_lf_pid is recovering ${SID:0:8}; the verdict arrives as mail. END YOUR TURN; do not poll."
      echo "run=$FLEET_DIR/$RUN log=$_lf_log"
      exit 0
    fi
    if _full="$(lf_resolve_sid "$SID")"; then
      [ "$_full" = "$SID" ] || echo "lr-fleet: --one ${SID} resolves to $_full" >&2
      SID="$_full"
    elif [ $? -eq 2 ]; then
      echo "lr-fleet: --one $SID is AMBIGUOUS — it names more than one session; pass the full uuid" >&2; exit 2
    fi
    RUN="${LR_FLEET_RUN:-one-$(date -u +%Y%m%dT%H%M%SZ)}"; mkdir -p "$FLEET_DIR/$RUN"; : > "$FLEET_DIR/$RUN/results.tsv"
    # ── REGISTRY AND STORE FIRST; THE CENSUS IS THE FALLBACK ────────────────────────────────────
    # `--one` is HANDED the sid and then ran the full `lf_locate` census to find it — measured
    # 40.3 / 64.5 / 86.1 s over 2,158 transcripts against a 0.007 s registry read and a 0.012 s
    # store glob (U14 §0, 2026-09-19), i.e. 99.8% of the identification cost, unconditionally, on
    # the path a driver takes when it has ALREADY audited the session. The cheap resolver below is
    # not new: it sat a few lines further down as the census's own MISS path. Only the order is
    # inverted, so the census now runs exactly when the store glob finds nothing.
    #
    # What the census contributed and how it is kept: `disp`, of which `--one` read only
    # TRANSPLANTED — so lr_transplanted_to is called here directly (one file read), which is what
    # lf_locate itself calls. `kind`/`kinds`/`err_age` were read by nobody on this path.
    cfg=""; while IFS= read -r c; do [ -n "$c" ] && ls "$c"/projects/*/"$SID".jsonl >/dev/null 2>&1 && { cfg="$c"; break; }; done <<EOF
$(lr_config_dirs)
EOF
    if [ -n "$cfg" ]; then
      acct="$(lf_acct_of_cfg "$cfg")"
      pane="-"; cwd=""
      # The registry is the pane's own store — `paneUUID` IS the filename and the row is rewritten
      # on every SessionStart. An explicit --source-pane still wins: the caller may be driving a
      # pane whose row is stale or was never written (the D7 registry hole).
      _rrow="$(lr_registry_live_rows "$SID" 2>/dev/null | head -1 || true)"
      [ -n "$_rrow" ] && IFS=$'\t' read -r pane _ _ cwd <<<"$_rrow"
      [ -n "$SOURCE_PANE" ] && pane="$SOURCE_PANE"
      [ -n "$pane" ] || pane="-"
      [ -n "$cwd" ] || cwd="$(grep -o '"cwd":"[^"]*"' "$cfg"/projects/*/"$SID".jsonl 2>/dev/null | tail -1 | cut -d'"' -f4)"
      tier="$(lr_tier_from_transcript "$cfg" "$SID" 2>/dev/null | tr ' ' '/' || true)"
      if _to="$(lr_transplanted_to "$SID" "$cfg")"; then
        echo "lr-fleet: --one $SID — already TRANSPLANTED→$(lf_acct_of_cfg "$_to"); nothing to do" >&2; exit 0
      fi
    else
      # No store holds the transcript under that name. The census reads the same stores, so this is
      # a near-certain miss too — but it also reads `.handed-off` copies and the mirror dedup, so it
      # is run rather than guessed at, and its miss is the one that refuses.
      row="$(lf_locate | lf_dedup_mirror | awk -F'\t' -v s="$SID" '$1 == s { print; exit }')"
      [ -n "$row" ] || { echo "lr-fleet: --one $SID — no transcript in any store" >&2; exit 2; }
      IFS=$'\t' read -r _ cfg acct pane pid cwd tier disp kind kinds err_age <<<"$row"
      [ -n "$SOURCE_PANE" ] && pane="$SOURCE_PANE"
      case "$disp" in TRANSPLANTED*) echo "lr-fleet: --one $SID — already $disp; nothing to do" >&2; exit 0 ;; esac
    fi
    lf_one "$SID" "$cfg" "$acct" "$pane" "$cwd" "$tier"; rc=$?
    echo "$FLEET_DIR/$RUN" > "$FLEET_DIR/last"
    lf_report "$FLEET_DIR/$RUN" >&2 || true
    # ── THE VERDICT REACHES SOMEONE ───────────────────────────────────────────────────────────────
    # A detached run whose only record is a `results.tsv` under $HOME/.reso is a run nobody reads. The
    # verdict is mailed to the requester as ONE line carrying a `verdict=` token, which is the token a
    # consumer matches on (memory: claimed-outcome-vs-checked-outcome — a parseable verdict= is what
    # makes a claim checkable). The token is derived from the ROW that was actually written, never
    # from rc alone, so a `parked` row cannot read as a failure of the actuator.
    if [ "${LR_FLEET_DETACHED:-0}" = 1 ]; then
      _lf_mv="$(awk -F'\t' -v s="$SID" '$1 == s { m=$6; n=$7 } END { print m }' "$FLEET_DIR/$RUN/results.tsv" 2>/dev/null || true)"
      _lf_note="$(awk -F'\t' -v s="$SID" '$1 == s { n=$7 } END { print n }' "$FLEET_DIR/$RUN/results.tsv" 2>/dev/null || true)"
      case "$_lf_mv" in
        *RECOVERED) _lf_v=RECOVERED ;;
        *PARTIAL)   _lf_v=PARTIAL ;;
        parked*)    _lf_v=PARKED ;;
        '')         _lf_v=FAILED; _lf_note="${_lf_note:-no results row was written — the driver died before lf_one returned}" ;;
        *)          _lf_v=FAILED ;;
      esac
      # HONEST QUALIFIER, not a fourth token. Under --detach the actuator is called WITHOUT --await
      # (lr-handoff.sh:621 honours LR_INPLACE_AWAIT=0), so rc 0 means the recycle was ARMED — the
      # /exit landed and the watcher took over — not that a turn was taken. W3 makes RECOVERED mean
      # "submitted, then engaged"; until it does, the mail says which question was answered rather
      # than letting the token overclaim.
      _lf_qual=""
      [ "${LR_INPLACE_AWAIT:-1}" = 0 ] && [ "$_lf_v" = RECOVERED ] && _lf_qual=" engagement=UNAWAITED (armed; the watcher's outcome lands in ~/.claude/logs/handoffs.jsonl)"
      _lf_msg="lr-fleet --one ${SID:0:8}: verdict=$_lf_v rc=$rc pane=${pane:--} acct=$acct mech=${_lf_mv:-none}$_lf_qual — ${_lf_note:--}; evidence: $FLEET_DIR/$RUN"
      printf '%s\n' "$_lf_msg" > "$FLEET_DIR/$RUN/verdict.txt"
      _lf_notify="${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"
      if [ -x "$_lf_notify" ]; then
        if [ -n "${LR_FLEET_REQUESTER:-}" ]; then "$_lf_notify" "$LR_FLEET_REQUESTER" "$_lf_msg" || echo "lr-fleet: cc-notify to ${LR_FLEET_REQUESTER} FAILED — the verdict is on disk only: $FLEET_DIR/$RUN/verdict.txt" >&2
        else "$_lf_notify" --role desk "$_lf_msg" || echo "lr-fleet: no requester pane and the desk role did not take it — the verdict is on disk only: $FLEET_DIR/$RUN/verdict.txt" >&2
        fi
      else
        echo "lr-fleet: cc-notify unreachable at $_lf_notify — the verdict is on disk only: $FLEET_DIR/$RUN/verdict.txt" >&2
      fi
    fi
    exit "$rc" ;;
  enqueue)
    mkdir -p "$STATE/requests"
    n=0
    while IFS=$'\t' read -r sid cfg acct pane pid cwd tier disp kind kinds err_age; do
      [ -n "$sid" ] || continue
      # enqueue hands the poller a TRANSPLANT request; only a real cap earns one.
      case "$disp" in RECOVERABLE|NO-PANE) : ;; *) continue ;; esac
      # `kind` is the class of the LAST api-error record, which is the death the session is sitting
      # on — so this stays an EXACT match even though `kinds` may read `network+limit`. A session
      # whose latest death is a network drop must not be transplanted however many caps it hit
      # earlier: the account is fine and the move would be spent on a problem that no longer exists.
      [ "$kind" = limit ] || continue
      jq -n --arg sid "$sid" --arg target "$TARGET" --arg pane "$([ "$pane" != "-" ] && printf '%s' "$pane")" --arg by "${CLAUDE_CODE_SESSION_ID:-lr-fleet}" --arg ts "$(lf_now)" \
        '{sid:$sid, target:$target, source_pane:$pane, requested_by:$by, ts:$ts}' > "$STATE/requests/$sid.json"
      echo "lr-fleet: enqueued ${sid:0:8} (pane ${pane}, $acct → $TARGET) for the reset poller: $STATE/requests/$sid.json"; n=$((n+1))
    done <<EOF
$(lf_locate | lf_dedup_mirror)
EOF
    if [ "$n" -gt 0 ]; then
      echo "lr-fleet: $n request(s) written. The poller drains them on its next tick (≤10 min); to run it now:"
      echo "  launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller"
      echo "lr-fleet: results land in $STATE/results/<sid>.json"
    else echo "lr-fleet: nothing to enqueue"; fi
    exit 0 ;;
  duplicates)
    if [ -n "$MARK_SID" ]; then
      if _full="$(lf_resolve_sid "$MARK_SID")"; then MARK_SID="$_full"
      elif [ $? -eq 2 ]; then echo "lr-fleet: --mark $MARK_SID is AMBIGUOUS; pass the full uuid" >&2; exit 2; fi
      [ -n "$LIVE_PID" ] || { echo "lr-fleet: --mark needs --live <pid> naming the copy that CARRIES the session" >&2; exit 2; }
      kill -0 "$LIVE_PID" 2>/dev/null || { echo "lr-fleet: --live $LIVE_PID is not alive; a SUPERSEDED tombstone must name a live successor" >&2; exit 2; }
      cfg=""; tx=""
      while IFS= read -r c; do [ -n "$c" ] || continue; for f in "$c"/projects/*/"$MARK_SID".jsonl; do [ -f "$f" ] && { cfg="$c"; tx="$f"; break 2; }; done; done <<EOF
$(lr_config_dirs)
EOF
      [ -n "$tx" ] || { echo "lr-fleet: --mark $MARK_SID — no transcript in any store" >&2; exit 2; }
      live_pane="$(lr_registry_live_rows "$MARK_SID" 2>/dev/null | awk -F'\t' -v p="$LIVE_PID" '$2 == p { print $1; exit }' || true)"
      tomb="${tx%.jsonl}.HANDOFF.json"
      [ -f "$tomb" ] && { echo "lr-fleet: $tomb already exists — refusing to overwrite a tombstone" >&2; exit 2; }
      jq -n --arg to "$cfg" --arg pid "$LIVE_PID" --arg pane "$live_pane" --arg ts "$(lf_now)" --arg by "${CLAUDE_CODE_SESSION_ID:-lr-fleet}" \
        '{handed_off_to:$to, superseded_by_pid:($pid|tonumber), superseded_by_pane:$pane, ts:$ts, reason:"same-account duplicate — the stale copy is retired; the guard blocks its prompts", written_by:$by}' > "$tomb"
      echo "lr-fleet: SUPERSEDED tombstone written: $tomb (live copy pid $LIVE_PID${live_pane:+, pane $live_pane}). Every OTHER process holding ${MARK_SID:0:8} now has its prompts blocked by handed-off-session-guard; retire its pane with: handoff-fire.sh self-close --transplanted-source --source-pane <stale pane> --source-session $MARK_SID --successor ${live_pane:-<live pane>}"
      exit 0
    fi
    # census: every sid held by more than one live process (registry rows + --resume argv + tmux)
    found=0
    for f in "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"/*.json; do
      [ -f "$f" ] || continue
      sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || continue
      rows="$(lr_registry_live_rows "$sid" 2>/dev/null || true)"; [ -n "$rows" ] || continue
      procs="$(lr_resume_procs "$sid" 2>/dev/null || true)"
      nrows="$(printf '%s\n' "$rows" | grep -c .)"; nprocs="$(printf '%s' "$procs" | grep -c . || true)"
      # a registry pid that IS a --resume process counts once — ONE predicate, shared with --locate
      total="$(lr_holder_count "$sid")"
      [ "$total" -gt 1 ] || continue
      found=$((found+1))
      echo "DUPLICATE ${sid:0:8}: $nrows registry pane(s) + $nprocs --resume process(es)"
      printf '%s\n' "$rows" | while IFS=$'\t' read -r pane pid acct cwd; do echo "   pane $pane pid $pid ($acct) $cwd  ← started $(TZ=UTC ps -o lstart= -p "$pid" 2>/dev/null | tr -s ' ')"; done
      printf '%s\n' "$procs" | while read -r p; do [ -n "$p" ] && echo "   --resume pid $p  ← started $(TZ=UTC ps -o lstart= -p "$p" 2>/dev/null | tr -s ' ') tty $(ps -o tty= -p "$p" 2>/dev/null)"; done
      echo "   rule: the LATER process took the conversation over (Claude Code hands Remote Control to it); the earlier one is stale."
      echo "   mark: lr-fleet.sh --duplicates --mark $sid --live <pid of the later process>"
    done
    [ "$found" -gt 0 ] || echo "(no session is held by more than one live process)"
    exit 0 ;;
  report)
    d="${REPORT_DIR:-$(cat "$FLEET_DIR/last" 2>/dev/null || true)}"
    [ -n "$d" ] && [ -d "$d" ] || { echo "lr-fleet: no run to report" >&2; exit 2; }
    lf_report "$d" ;;
esac
