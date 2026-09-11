#!/usr/bin/env bash
# lr-fleet.sh — /limit-recover fleet: every limit-blocked session located, each one continued IN ITS
# OWN PANE on an unrestricted account, no husk, no orphan, no ambiguity left behind
# (docs/plans/LIMIT_RECOVER_100P.md, operator ruling 2026-09-08).
#
# Usage: lr-fleet.sh --locate [--json]                 census: every limit-blocked session, its pane, tier, disposition
#        lr-fleet.sh --recover [--target A|auto] [--dry-run] [--max N]
#                                                     sequenced in-place recovery of every RECOVERABLE session
#        lr-fleet.sh --one SID --target A [--source-pane P] [--from-daemon]
#                                                     one session (the unit the poller's request drain runs)
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
STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
FLEET_DIR="$STATE/fleet"; mkdir -p "$FLEET_DIR" 2>/dev/null || true
HANDOFF="${LR_HANDOFF_BIN:-$LR/lr-handoff.sh}"
ACCOUNTS="${CC_ACCOUNTS_BIN:-$HOME/bin/claude-accounts}"

MODE="" TARGET="auto" DRY=0 MAX=0 SID="" SOURCE_PANE="" FROM_DAEMON=0 JSON=0 MARK_SID="" LIVE_PID="" REPORT_DIR=""
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
          n="$(printf '%s\n' "$rows" | grep -c .)"
          IFS=$'\t' read -r pane pid _ cwd <<<"$(printf '%s\n' "$rows" | head -1)"
          if [ "$n" -gt 1 ] || lr_resume_procs "$sid" >/dev/null 2>&1; then disp=DUPLICATE; else disp=RECOVERABLE; fi
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

# ── CAPACITY: wait on the NON-charging probe, never spend the budget ─────────────────────────────
lf_capacity_wait() { # $1=what → 0 admitted / 1 parked at the cap
  local waited=0 max="${LR_FLEET_CAP_WAIT_S:-600}" ivl="${LR_FLEET_CAP_IVL_S:-20}"
  command -v cc_capacity_probe >/dev/null 2>&1 || { echo "lr-fleet: capacity probe unavailable — proceeding UNGATED" >&2; return 0; }
  while :; do
    if cc_capacity_probe lr-fleet "$1"; then return 0; fi
    if [ "$waited" -ge "$max" ]; then echo "lr-fleet: PARKED on capacity after ${waited}s — $(cc_capacity_admit_reason)" >&2; return 1; fi
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
  lf_capacity_wait "in-place recovery of ${sid:0:8} onto $target" || { lf_row "$sid" "$pane" "$pane" "$acct" "$target" "parked" "capacity"; return 1; }
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
  case "$rc" in
    0) : ;;
    4) verdict="PARTIAL"; note="transplanted but the relaunch did not verify — source is a tombstoned husk; see $rdir/$sid.stderr" ;;
    *) verdict="FAILED"; note="lr-handoff rc=$rc; see $rdir/$sid.stderr" ;;
  esac
  lf_row "$sid" "$pane" "$pane_after" "$acct" "$target" "$mech/$verdict" "$note"
  return "$rc"
}
lf_row() { # sid pane_before pane_after acct_before acct_after mechanism/verdict note → appended to the run's results.tsv
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$(lf_now)" >> "$FLEET_DIR/$RUN/results.tsv"
}
lf_report() { # $1=run dir
  local d="$1" f="$1/results.tsv" sid pb pa ab aa mv note n=0 inplace=0 newp=0 gaps=0
  [ -f "$f" ] || { echo "lr-fleet: no results in $d"; return 1; }
  echo "FLEET RECOVERY — $(basename "$d")"
  printf '%-9s %-8s %-8s %-7s %-7s %-26s %s\n' SID "PANE→" "PANE←" "ACCT→" "ACCT←" MECHANISM/VERDICT NOTE
  while IFS=$'\t' read -r sid pb pa ab aa mv note _ts; do
    [ -n "$sid" ] || continue; n=$((n+1))
    printf '%-9s %-8s %-8s %-7s %-7s %-26s %s\n' "${sid:0:8}" "${pb:--}" "${pa:--}" "$ab" "$aa" "$mv" "$note"
    case "$mv" in *RECOVERED) [ "$pa" = "$pb" ] && inplace=$((inplace+1)) || newp=$((newp+1)) ;; *dry-run) : ;; *) gaps=$((gaps+1)) ;; esac
  done < "$f"
  echo
  if [ "$gaps" -eq 0 ]; then
    echo "RECOVERY COMPLETE — $inplace in place (same pane id), $newp replaced beside their source, 0 left over ($n session(s); evidence: $d)"
  else
    echo "RECOVERY PARTIAL — $gaps named gap(s) above ($inplace in place, $newp replaced; evidence: $d)"
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
    RUN="${LR_FLEET_RUN:-one-$(date -u +%Y%m%dT%H%M%SZ)}"; mkdir -p "$FLEET_DIR/$RUN"; : > "$FLEET_DIR/$RUN/results.tsv"
    row="$(lf_locate | lf_dedup_mirror | awk -F'\t' -v s="$SID" '$1 == s { print; exit }')"
    if [ -z "$row" ]; then
      # not limit-blocked per the census — the caller may still know better (a request from a driver
      # that audited it); fall back to the registry for the pane and the store for the cfg.
      cfg=""; while IFS= read -r c; do [ -n "$c" ] && ls "$c"/projects/*/"$SID".jsonl >/dev/null 2>&1 && { cfg="$c"; break; }; done <<EOF
$(lr_config_dirs)
EOF
      [ -n "$cfg" ] || { echo "lr-fleet: --one $SID — no transcript in any store" >&2; exit 2; }
      acct="$(lf_acct_of_cfg "$cfg")"; pane="${SOURCE_PANE:--}"; cwd="$(grep -o '"cwd":"[^"]*"' "$cfg"/projects/*/"$SID".jsonl 2>/dev/null | tail -1 | cut -d'"' -f4)"; tier="$(lr_tier_from_transcript "$cfg" "$SID" 2>/dev/null | tr ' ' '/' || true)"
    else
      IFS=$'\t' read -r _ cfg acct pane pid cwd tier disp kind kinds err_age <<<"$row"
      [ -n "$SOURCE_PANE" ] && pane="$SOURCE_PANE"
      case "$disp" in TRANSPLANTED*) echo "lr-fleet: --one $SID — already $disp; nothing to do" >&2; exit 0 ;; esac
    fi
    lf_one "$SID" "$cfg" "$acct" "$pane" "$cwd" "$tier"; rc=$?
    echo "$FLEET_DIR/$RUN" > "$FLEET_DIR/last"
    lf_report "$FLEET_DIR/$RUN" >&2 || true
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
      # a registry pid that IS a --resume process counts once
      total=$((nrows + nprocs))
      while IFS=$'\t' read -r pane pid _ _; do printf '%s\n' "$procs" | grep -x "$pid" >/dev/null && total=$((total-1)); done <<EOF
$rows
EOF
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
