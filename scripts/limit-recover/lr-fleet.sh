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
# The admit section's mutex and W5's per-sid run claim. Both are DIRECTORIES created by `mkdir`,
# which is the atomic primitive on this box — there is no flock(1) on Darwin (bin/cc-dispatch:1604
# says so in as many words, and lr-reset-poller's tick lock, lr_state_append's event lock and
# cc-lr's per-session mutex are all mkdir). The PLAN DRAFT prescribes `flock "$STATE/admit.lock"`;
# that command does not exist here, so the path is honoured and the primitive is not.
LF_ADMIT_LOCK="$STATE/admit.lock"
# THE SAME STORE lr-reset-poller.sh:167 and bin/cc-lr:48 use, by the same name, on purpose: a sid
# already being driven by the daemon or by `cc-lr recover` must not be driven a second time by a
# fleet pool worker. Three writers, one reservation.
RUN_CLAIMS="$STATE/runs/by-sid"

MODE="" TARGET="auto" DRY=0 MAX=0 SID="" SOURCE_PANE="" FROM_DAEMON=0 JSON=0 MARK_SID="" LIVE_PID="" REPORT_DIR="" DETACH=0
LF_ARGV=("$@")                  # verbatim, for the --detach re-exec (the child re-parses, never a rebuild)
while [ $# -gt 0 ]; do
  case "$1" in
    --locate) MODE=locate; shift ;;
    --recover) MODE=recover; shift ;;
    --one) MODE=one; SID="${2:?--one needs a sid}"; shift 2 ;;
    --enqueue) MODE=enqueue; shift ;;
    --duplicates) MODE=duplicates; shift ;;
    --retire-husks) MODE=retire-husks; shift ;;
    --pane) HUSK_PANE="${2:?--pane needs a pane id}"; shift 2 ;;
    --yes) ASSUME_YES=1; shift ;;
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
HUSK_PANE="${HUSK_PANE:-}"; ASSUME_YES="${ASSUME_YES:-0}"
[ -n "$MODE" ] || { echo "lr-fleet: one of --locate | --recover | --one SID | --enqueue | --duplicates | --retire-husks | --report is required" >&2; exit 2; }

lf_acct_of_cfg() { # $1=cfg dir → account name (next|next2|…) via the generated map, else the basename
  local n
  n="$(cc_acct_name_for_dir_basename "$(basename "${1%/}")" 2>/dev/null || true)"
  [ -n "$n" ] && printf '%s' "$n" || printf '%s' "$(basename "${1%/}")"
}
lf_now() { date -u +%FT%TZ; }

# ── LOCATE: the census, disk truth only ──────────────────────────────────────────────────────────
# One line per limit-blocked session: sid · cfg · account · pane · pid · cwd · tier · disposition.
# Dispositions: RECOVERABLE (live pane, not transplanted) · TRANSPLANTED (a successor exists elsewhere)
# · HUSK (a LIVE pane on a store the session has already LEFT — the source half of a transplant,
# retired by --retire-husks and never resumed) · NO-PANE (no live process holds it: the poller's
# spawn-at-reset domain, or --recover spawns a
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
  local cfg tx sid tail rows pane pid acct cwd tier disp n kind kinds err_age _procs _husk
  while IFS= read -r cfg; do
    [ -n "$cfg" ] || continue
    # ── the HUSK is enumerated from the `.handed-off` copy too (W10, LIMIT_RECOVER_100P § 10) ──
    # lr-transplant.sh:98 renames the source transcript `<sid>.jsonl.handed-off` the moment it has
    # copied it, so `*.jsonl` CANNOT match a transplanted session's SOURCE copy. Measured
    # 2026-09-19 against all three live husks (panes 110/126/150): the only `.jsonl` left anywhere
    # for those sids was the successor's, under the target store. THAT glob — not the
    # last-assistant-word filter below — is the first reason `--locate` listed none of them; both
    # walls are cleared here, and clearing only one would have landed an inert census arm.
    # A `.handed-off` copy is enumerated for exactly ONE purpose and is dropped again unless it is
    # a husk, so the 63 historical ones on this box (against 2,631 live transcripts) cost one lock
    # stat each and change no other row in the census.
    for tx in "$cfg"/projects/*/*.jsonl "$cfg"/projects/*/*.jsonl.handed-off; do
      [ -f "$tx" ] || continue
      sid="$(basename "${tx%.handed-off}" .jsonl)"
      case "$sid" in agent-*|wf_*) continue ;; esac
      # HUSK is decided BEFORE the last-assistant-word filter below, so a session that has already
      # moved cannot drop out of the census the moment its successor takes a real turn. A TEAMMATE
      # is never a husk: its lead ends it (the teammate close contract), not `--retire-husks`.
      _husk=0
      if lr_husk_state "$sid" "$cfg"; then
        head -c 8000 "$tx" 2>/dev/null | grep '"agentName"' >/dev/null || _husk=1
      fi
      case "$tx" in *.handed-off) [ "$_husk" = 1 ] || continue ;; esac
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
sys.exit(0 if last else 1)' || [ "$_husk" = 1 ] || continue
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
      # HUSK outranks every disposition above it FOR THE SOURCE ROW — TRANSPLANTED→ included. The
      # pane is live, the session is not here any more, and the only action the row names is
      # retiring that pane. The TARGET row is untouched: lr_husk_state is rc 1 when it is asked
      # from the successor's own store, exactly as lr_transplanted_to is.
      [ "$_husk" = 1 ] && disp=HUSK
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
# 🚨 A HUSK ROW IS NEVER THE MIRROR'S DUPLICATE (W10b, 2026-09-20). This collapses `~/.claude` and
# `~/.claude-next`, which are ONE account behind a symlink, and it is keyed on the sid alone. After a
# TRANSPLANT that is the wrong key: the session exists under TWO accounts as two objects with
# OPPOSITE dispositions — the husk on the source store and the live successor on the target — and
# preferring "any account that is not .claude" hands the slot to the SUCCESSOR and silently discards
# the husk. Measured 2026-09-20 on panes 110 and 126: `lf_locate` emitted both HUSK rows, both panes
# were live and enumerable, `lr_husk_state` said HUSK for both, and `--locate` printed NEITHER —
# a 0-HUSK census over two standing husks, which is the exact false green this wave exists to end.
# So HUSK wins the slot outright, in both directions. Everything else keeps the mirror rule verbatim.
lf_dedup_mirror() { awk -F'\t' '
  { sid=$1; acct=$3; disp=$8
    if (!(sid in seen)) { ord[++k]=sid; seen[sid]=$0; sacct[sid]=acct; sdisp[sid]=disp }
    else if (disp=="HUSK" && sdisp[sid]!="HUSK") { seen[sid]=$0; sacct[sid]=acct; sdisp[sid]=disp }
    else if (sdisp[sid]=="HUSK") { }
    else if (sacct[sid]==".claude" && acct!=".claude") { seen[sid]=$0; sacct[sid]=acct; sdisp[sid]=disp } }
  END { for (i=1;i<=k;i++) print seen[ord[i]] }' ; }

# ── THE CENSUS, DELEGATED TO ONE PROCESS (LIMIT_DETECT_100P § 3 W3) ──────────────────────────────
# `bin/cc-limited` answers the same question from the stores that already hold it, so the 35.5 s
# walk over 2,591 transcripts becomes one read. `lf_locate` is NOT retired (§ 11 #9, 88%): it stays
# permanently as `--slow-scan`, which is `--deep`'s only implementation for the no-transcript
# class, and the suite diffs the two paths on every fixture. An empty diff is what earns the
# delegation; this function exists to make that diff possible, not to assert it.
#
# `--all`, NEVER the default window. cc-limited defaults to `--since 24h`; `lf_locate` has no
# window at all. A session that capped 30 hours ago with a live pane is still recoverable and
# still in the slow scan, so anything narrower drops rows the consumer is here to act on.
lf_census() { # → the 11-field TSV on stdout; rc 0 ok · 5 instrument unreadable (stdout EMPTY) · 6 degraded
  local _cl _rows _rc _err
  _cl="${CC_LIMITED:-$LR/../../bin/cc-limited}"
  if [ "${LF_SLOW_SCAN:-0}" = 1 ] || [ ! -x "$_cl" ]; then
    [ "${LF_SLOW_SCAN:-0}" = 1 ] \
      || echo "lr-fleet: census — no executable cc-limited at $_cl; falling back to the slow scan (lf_locate)" >&2
    lf_locate | lf_dedup_mirror
    return 0
  fi
  _err="$(mktemp "${TMPDIR:-/tmp}/lf-census.XXXXXX")"
  # CAPTURED, not streamed: rc 5 means the instrument could not look, and its contract is EMPTY
  # stdout. Streaming would let a stub — or a future partial write — put bytes on stdout that a
  # caller then stores as a census, and an empty-or-partial census.tsv reads as a clean fleet.
  _rows="$("$_cl" --all --tsv 2>"$_err")"; _rc=$?
  [ -s "$_err" ] && sed 's/^/lr-fleet: /' "$_err" >&2
  rm -f "$_err"
  case "$_rc" in
    0) : ;;
    6) echo "lr-fleet: census DEGRADED (cc-limited rc 6) — rows below are incomplete; see the stderr above" >&2 ;;
    *) # 5 by contract, and any code --all --tsv cannot legally return is treated the same way:
       # refusing is the only answer that is not indistinguishable from a healthy empty fleet.
       echo "lr-fleet: census INSTRUMENT UNREADABLE (cc-limited rc $_rc) — refusing to report an empty fleet" >&2
       return 5 ;;
  esac
  [ -n "$_rows" ] && printf '%s\n' "$_rows" | lf_census_fill
  return "$_rc"
}
# TWO COLUMNS ARE FILLED HERE, and neither is cosmetic. Measured 2026-09-20 against one fixture
# carrying a marker, a live registry row and a transcript: `render_tsv` (bin/cc-limited:901-912)
# emits `-` in field 7 (TIER) because no tier exists anywhere in its model, and `pane_now` in
# field 5 (PID) — the census printed pane `616` where the slow scan printed live pid `42621`.
# TIER IS LOAD-BEARING: `lf_one` splits it into `--model`/`--effort` and hands it to
# `lf_pick_target`, so consuming a `-` would silently drop the model and effort pin on every
# transplant this driver performs. The fill is per ROW — a census returns a handful — never per
# TRANSCRIPT, so the walk the delegation removes does not come back.
# It also normalises EMPTY to `-`: the two producers spell an absent pane/pid/cwd differently, and
# for a TEAMMATE the slow scan zeroes all four columns (a teammate is lead-owned; its pane is not
# this driver's to name). Reported upstream for W2a to absorb; this stays until it does.
lf_census_fill() { # stdin: census TSV → the same rows, fields 4/5/6/7 in lf_locate's own spelling
  local sid cfg acct pane pid cwd tier disp kind kinds age _p _tx _k _ks
  # EMPTY FIELDS ARE FILLED IN awk, BEFORE any `read` SEES THEM — this repo's TSV field-collapse
  # convention (docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md, chokepoint scripts/tsv-pad-lint.sh,
  # locked by tests/tsv-field-collapse.bats). That convention pads AT THE EMITTER, because "the
  # read side cannot be repaired"; here the emitter is bin/cc-limited, which this consumer does
  # not own, so the pad happens at the only place left. TAB is IFS *whitespace*, so
  # `IFS=$'\t' read` collapses a RUN of tabs into one separator and drops leading/trailing
  # empties. The census emits empty panes and pids where the
  # slow scan emits `-`, so a NO-PANE row arrived two columns short and every field shifted left —
  # measured, the cwd rendered in the PANE column and the disposition fell off the end. `awk
  # -F'\t'` is the only reader in this file that can see an empty field at all. (This is the same
  # trap the `--json` width gate at the locate site is commented against, from the other side.)
  while IFS=$'\t' read -r sid cfg acct pane pid cwd tier disp kind kinds age; do
    [ -n "$sid" ] || continue
    if [ "$disp" = TEAMMATE ]; then pane="-"; pid="-"; cwd="-"; tier="-"
    else
      [ -n "$tier" ] && [ "$tier" != "-" ] \
        || tier="$(lr_tier_from_transcript "$cfg" "$sid" 2>/dev/null | tr ' ' '/' || true)"
      # KINDS IS THE THIRD MISSING FIELD, and it is D7's whole point. The census reads ONE marker
      # row — the last death — so it can only ever report one class, while `lf_kinds_of` reports
      # EVERY class in the tail joined by '+'. A session that hit a cap and then lost the network
      # renders `limit+network` in the slow scan and a bare `network` here, which is exactly the
      # collapse D7 added the column to make visible. Backfilled only when a transcript is
      # findable: where none is, the census's single class is the honest answer and the slow scan
      # has no row to disagree with (it enumerates transcripts).
      if [ -z "$kinds" ] || [ "$kinds" = "-" ] || [ "$kinds" = "$kind" ]; then
        for _tx in "$cfg"/projects/*/"$sid".jsonl; do
          [ -f "$_tx" ] || continue
          IFS=$'\t' read -r _k _ks <<<"$(lf_kinds_of "$(tail -c 20000 "$_tx" 2>/dev/null)")"
          [ -n "$_ks" ] && { kind="$_k"; kinds="$_ks"; }
          break
        done
      fi
      _p="$(lr_registry_live_rows "$sid" 2>/dev/null | head -1 | cut -f2 || true)"
      [ -n "$_p" ] || _p="$(lr_resume_procs "$sid" 2>/dev/null | head -1 || true)"
      pid="${_p:--}"
      [ -n "$pane" ] || pane="-"; [ -n "$cwd" ] || cwd="-"; [ -n "$tier" ] || tier="-"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$sid" "$cfg" "$acct" "$pane" "$pid" "$cwd" "$tier" "$disp" "$kind" "$kinds" "$age"
  done < <(awk -F'\t' -v OFS='\t' 'NF { for (i = 1; i <= 11; i++) if ($i == "") $i = "-"; print }')
}
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

# ── THE PHANTOM-ACTIVE CORRECTION — now lr-lib's, because a SECOND caller appeared (W2) ─────────
# The correction, its measurement and its direction rule moved VERBATIM to scripts/limit-recover/
# lr-lib.sh as `lr_phantom_actives`, inside `lr_capacity_probe_corrected`, when lr-handoff grew its
# own pre-transplant probe (W2). Two spellings of one probe is exactly how the fleet and the
# launcher came to measure different gates (U05 §3.3); this file keeps the NAME so its own callers
# and tests are unchanged, and the body has one home.
#
# THE CORRECTION DOES NOT LIVE IN THE CENSUS, and that is still deliberate: a general fix in
# cc_sp_active needs a discriminator that separates "blocked" from "mid-turn" for EVERY caller, and
# the obvious one is refuted — measured 2026-09-19, blocked sessions' transcripts are still being
# written (mtime ages 201-2711 s), so file freshness does not separate the two populations.
lf_phantom_actives() { # → count of live sessions whose mid-turn beat is a usage-limit corpse
  lr_phantom_actives "$@"
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
# THE PARK BOUND IS 120 s, NOT 600 (W2; §11.5 of the reopen draft). Measured 2026-09-19: the 600 s
# form cost one fire 658 s of wall clock in the lead's own foreground and recovered nothing (run
# one-20260919T170450Z, U14 §1). With the load term off and the phantom correction applied, the
# terms that can still refuse are headroom, segments and the reserves — states that either clear in
# a couple of minutes or are not going to clear at all, so a longer wait buys nothing and holds a
# worker. Past the bound the session is PARKED with the term named, nothing has moved, and the next
# tick re-probes.
lf_capacity_wait() { # $1=what → 0 admitted / 1 parked at the cap
  local waited=0 max="${LR_FLEET_CAP_WAIT_S:-120}" ivl="${LR_FLEET_CAP_IVL_S:-20}"
  command -v cc_capacity_probe >/dev/null 2>&1 || { echo "lr-fleet: capacity probe unavailable — proceeding UNGATED" >&2; return 0; }
  # A MISSING FUNCTION IS NOT A CAPACITY REFUSAL. lr-lib.sh is resolved through a three-path ladder
  # whose last two entries are the LIVE layer, so an lr-fleet.sh that has landed ahead of its
  # sibling finds an lr-lib with no `lr_capacity_probe_corrected` — and `if <missing>; then` is
  # simply false, which this loop would read as "the box is busy" and repeat until the park.
  # Measured while writing W2: 120 s of waiting, then `parked | capacity` with an EMPTY reason.
  # Say what is actually wrong, once, and park immediately.
  # (The remedy is a converge of the live layer; the command itself is deliberately NOT spelled
  # here — iron rule 7 forbids this file from naming a deploy verb at all, and the project
  # CLAUDE.md § Standing-converge carries the one command.)
  command -v lr_capacity_probe_corrected >/dev/null 2>&1 || {
    LF_PARK_REASON="lr-lib.sh has no lr_capacity_probe_corrected — the live layer is BEHIND this script; converge it (project CLAUDE.md § Standing-converge names the one command) and re-run"
    echo "lr-fleet: PARKED — $LF_PARK_REASON" >&2; return 1; }
  while :; do
    # ONE probe implementation, shared with lr-handoff's pre-transplant check (lr-lib.sh
    # `lr_capacity_probe_corrected`): the phantom-active subtraction and the call-scoped
    # CC_ADMIT_LOAD_TERM=off both live there now. The WAIT stays here — it is the fleet's policy,
    # not the probe's — and the behaviour of --detach (W1) is unchanged.
    if lr_capacity_probe_corrected lr-fleet "$1"; then return 0; fi
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

# ── THE ADMIT SECTION'S MUTEX (W6b) ─────────────────────────────────────────────────────────────
# rank -> assign -> capacity probe is ONE decision, and running it concurrently makes every term it
# reads stale in the SAME direction: N pool workers rank the same <=90 s-cached rows, pick the same
# winner, and N probes taken at one census all admit (D3-safety R2, "N probes mint N"). The lock is
# what makes worker 2's rank see worker 1's `--assign` phantom, and worker 2's probe see the seat
# worker 1 just took.
#
# IT SERIALIZES THE COST, IT DOES NOT HIDE IT. Warm the section is ~1-2 s; a COLD `cc_sp_active` is
# 7.2 s (U05 section 4.3), and a capacity park holds it for up to LR_FLEET_CAP_WAIT_S (120 s) —
# deliberately, because admitting a SECOND recovery while the box is refusing the first is exactly
# the over-admission this lock exists to prevent. 🚨 Do NOT "optimise" it down to the rank alone:
# the probe is the term that goes stale, and a rank-only lock would serialize the cheap half and
# leave the expensive one racing.
#
# The holder names its PID, so a dead holder is stolen AT ONCE rather than waited out — a driver
# that died mid-section must not be able to silence every later recovery (the same rule
# lr_state_append's 2 s steal and cc-lr's mutex both keep). The time-based steal is the backstop
# for a holder that is alive but wedged; it is loud, because a steal past a LIVE holder can
# double-admit and that is a fact the operator gets to read.
lf_admit_lock_take() { # → 0 this process owns $LF_ADMIT_LOCK · 1 could not take it at all
  local t=0 maxt hp
  maxt=$(( ${LR_ADMIT_LOCK_WAIT_S:-300} * 5 ))          # ticks of 0.2 s
  [ "$maxt" -gt 0 ] 2>/dev/null || maxt=1500
  mkdir -p "$STATE" 2>/dev/null || true
  while :; do
    if mkdir "$LF_ADMIT_LOCK" 2>/dev/null; then
      printf '%s\n' "$$" > "$LF_ADMIT_LOCK/pid" 2>/dev/null || true
      return 0
    fi
    hp="$(cat "$LF_ADMIT_LOCK/pid" 2>/dev/null || true)"
    case "${hp:-x}" in
      ''|*[!0-9]*) : ;;
      *) kill -0 "$hp" 2>/dev/null || {
           echo "lr-fleet: admit lock $LF_ADMIT_LOCK was held by pid $hp, which is DEAD — stealing it" >&2
           rm -rf "$LF_ADMIT_LOCK" 2>/dev/null || true; } ;;
    esac
    if [ "$t" -ge "$maxt" ]; then
      echo "lr-fleet: admit lock $LF_ADMIT_LOCK held by pid ${hp:-?} for >$(( maxt / 5 ))s — STEALING it; a second recovery may be admitted against one capacity reading" >&2
      rm -rf "$LF_ADMIT_LOCK" 2>/dev/null || true
      mkdir "$LF_ADMIT_LOCK" 2>/dev/null || return 1
      printf '%s\n' "$$" > "$LF_ADMIT_LOCK/pid" 2>/dev/null || true
      return 0
    fi
    sleep 0.2; t=$(( t + 1 ))
  done
}
# RELEASE ONLY WHAT IS STILL OURS. If a peer stole the lock from under us (the time-based steal
# above), the directory now belongs to that peer and removing it would hand a THIRD worker the
# section while two are inside it. An unconditional `rm -rf` here is the bug this guard names.
lf_admit_lock_release() {
  [ "$(cat "$LF_ADMIT_LOCK/pid" 2>/dev/null || true)" = "$$" ] || return 0
  rm -rf "$LF_ADMIT_LOCK" 2>/dev/null || true
}

# ── W5'S PER-SID RUN CLAIM, AS A POOL WORKER SEES IT ────────────────────────────────────────────
# lr-reset-poller.sh:716 and bin/cc-lr:128 both reserve `$STATE/runs/by-sid/<sid>.active` before
# driving a recovery. A fleet POOL is the third writer, and without taking the same reservation two
# processes would type into one pane. Semantics are cc-lr's, because they are the stricter pair:
#   holder pid ALIVE  → REFUSE (a live run owns this sid)
#   holder pid DEAD   → steal, loudly (a corpse must not wedge a sid out of recovery)
#   no holder file    → the poller's shape; steal only past LR_RUN_CLAIM_TTL_MIN, which is what the
#                       poller itself uses and for the same reason.
lf_run_claim_take() { # $1=sid → 0 this worker owns the run · 1 a live run already holds it
  local d="$RUN_CLAIMS/${1:?lf_run_claim_take needs a sid}.active" hp ttl
  ttl="${LR_RUN_CLAIM_TTL_MIN:-30}"; case "$ttl" in ''|*[!0-9]*|0) ttl=30 ;; esac
  mkdir -p "$RUN_CLAIMS" 2>/dev/null || true
  if mkdir "$d" 2>/dev/null; then
    printf '{"sid":"%s","pid":%d,"ts":"%s","by":"lr-fleet --recover"}\n' "$1" "$$" "$(lf_now)" \
      > "$d/holder" 2>/dev/null || true
    return 0
  fi
  hp="$(sed -n 's/.*"pid":\([0-9][0-9]*\).*/\1/p' "$d/holder" 2>/dev/null | sed -n '1p')"
  if [ -n "$hp" ]; then
    kill -0 "$hp" 2>/dev/null && return 1
    echo "lr-fleet: run claim $d was held by pid $hp, which is DEAD — stealing it" >&2
  else
    # `-maxdepth 0`, exactly as lr-reset-poller.sh:722: the claim IS the directory and nothing is
    # written inside it by the poller, so without it find descends and tests the empty contents.
    [ -n "$(find "$d" -maxdepth 0 -mmin "+$ttl" 2>/dev/null)" ] || return 1
    echo "lr-fleet: run claim $d aged past ${ttl}m with no holder — stealing it" >&2
  fi
  rm -rf "$d" 2>/dev/null || true
  mkdir "$d" 2>/dev/null || return 1
  printf '{"sid":"%s","pid":%d,"ts":"%s","by":"lr-fleet --recover"}\n' "$1" "$$" "$(lf_now)" \
    > "$d/holder" 2>/dev/null || true
  return 0
}
lf_run_claim_release() { rm -rf "$RUN_CLAIMS/${1:?lf_run_claim_release needs a sid}.active" 2>/dev/null || true; }

# ── ONE: the unit — one session, in place ────────────────────────────────────────────────────────
# _lf_target_holds_sid <acct> <sid> → 0 iff that account's store ALREADY holds this session.
# A destination carrying `<sid>.jsonl` — or its `.handed-off` tombstone, which is what a PREVIOUS
# transplant OUT of that account leaves behind — is refused by lr-transplant on arrival ("REFUSED —
# … already exists"). Measured 2026-09-19/20: `07e30aeb` was transplanted next3 → next2 (its 1.1 MB
# transcript lives on next2; next3 keeps a 5,339 B stub + tombstone), and every later retry routed
# next2 → next3 and died on that refusal — three times, deterministically, because the router cannot
# see what the destination holds. The refusal itself is CORRECT and protective: it stops a stub from
# shadowing the real transcript. The defect is choosing that destination at all.
_lf_target_holds_sid() {
  local cfg f
  while IFS= read -r cfg; do
    [ -n "$cfg" ] || continue
    [ "$(lf_acct_of_cfg "$cfg")" = "$1" ] || continue
    for f in "$cfg"/projects/*/"$2".jsonl "$cfg"/projects/*/"$2".jsonl.handed-off; do
      [ -e "$f" ] && return 0
    done
  done <<EOF
$(lr_config_dirs)
EOF
  return 1
}

# ── THE ROUTER'S OWN REASONS, NEVER OUR PROSE (W6b) ────────────────────────────────────────────
# A park reading `no routable target` named the OUTCOME and never the CAUSE, so the one fact that
# decides the next action — shed load? re-login? wait out a 5-hour window? — lived only in a stderr
# stream nobody kept. claude-accounts already prints exactly that fact, in two shapes, and this
# lifts whichever one it printed rather than inventing a third.
#   "claude-accounts: no routable account for general: next=5h-cutoff; next2=recovery-weekly-thin"
#   "claude-accounts: general excluded — next3=kmax-concurrency"
# The FILE is read directly (never a pipe into an early-exiting reader): awk's `exit` over a file
# signals no producer, so this cannot become the pipefail-SIGPIPE shape the land gate flags.
lf_rank_why() { # $1=the rank's stderr file → the router's own reason text on stdout
  [ -s "${1:-}" ] || return 0
  awk '
    /^claude-accounts: no routable account for / {
      sub(/^claude-accounts: no routable account for [a-z]*: /, ""); print; exit }
    /^claude-accounts: [a-z]* excluded/ {
      if (ex == "") { ex = $0; sub(/^claude-accounts: [a-z]* excluded[^A-Za-z0-9]*/, "", ex) }; next }
    /^route-meta:/ { next }
    NF { if (raw == "") raw = $0 }
    END { if (ex != "") print ex; else if (raw != "") print raw }
  ' "$1" 2>/dev/null | cut -c1-300
}
# `--assign` is a WRITE to the router's ledger (bin/claude-accounts:5830, M7): it charges the chosen
# account one PHANTOM working session so the next pick inside the same <=90 s cache TTL walks DOWN
# the ranking instead of stacking every recovery onto one winner. lr-fleet is the OWNER of this
# charge on the recovery path — see the report's section on handoff-fire, which cannot reach either
# of its own `--assign` sites from here.
# Advisory, never fatal: a lost append costs one phantom, never a recovery. But it is SAID, because
# a silent loss degrades spread with nothing on disk naming why.
# 🚨 A DRY RUN CHARGES NOTHING. It launches nothing, so a charge would tell the router about a
# session that will never exist — a phantom with no body, decaying only on ASSIGN_TTL_MIN.
lf_charge_assign() { # $1=account → always 0; the stderr line IS the record when it does not land
  [ "${DRY:-0}" = 1 ] && { echo "lr-fleet: DRY — not charging --assign $1 (nothing is launching)" >&2; return 0; }
  [ -x "$ACCOUNTS" ] || return 0
  "$ACCOUNTS" --assign "$1" --src lr-fleet >/dev/null 2>&1 \
    || echo "lr-fleet: --assign $1 was NOT recorded — the router cannot see this recovery until it burns; a concurrent pick may stack onto the same account" >&2
  return 0
}
# 🚨 IT SETS A GLOBAL AND PRINTS NOTHING, and that is a BUG FIX, not a style change. The caller
# read this function as `target="$(lf_pick_target …)"` — a COMMAND SUBSTITUTION, i.e. a subshell —
# so every one of the four facts it carries OUT of the loop (`LF_PICK_SKIPPED_HOLDER` and, new in
# W6b, `LF_PICK_REJECTED` and `LF_RANK_WHY`) died with that subshell (repo memory:
# assignment-inside-command-substitution-never-escapes). Measured while writing this wave: the
# `targets already hold this sid: …` park note, landed 2026-09-20 with its own passing case over
# the direct-call harness, could NEVER fire from lf_one — every real park printed the generic
# `no routable target` instead. The house pattern is lib/account-map.generated.sh's
# `cc_acct_dir_for_name`, whose header says exactly this in exactly these words.
lf_pick_target() { # $1=source account $2=tier $3=sid → 0 and LF_PICK_TARGET set / rc 1
  local kind=general cand rdir rankerr
  case "$2" in claude-fable-*) kind=fable ;; esac
  LF_PICK_TARGET=""; LF_PICK_SKIPPED_HOLDER=""; LF_PICK_REJECTED=""; LF_RANK_WHY=""
  # An EXPLICIT --target is the caller's decision, not a pick — but the account still hosts a real
  # session, so it is charged exactly like a ranked one. The alternative is a fleet whose explicit
  # targets are invisible to the router's spread.
  [ "$TARGET" != auto ] && { lf_charge_assign "$TARGET"; LF_PICK_TARGET="$TARGET"; return 0; }
  [ -x "$ACCOUNTS" ] || { LF_RANK_WHY="claude-accounts is not executable at $ACCOUNTS"; return 1; }
  rdir="${FLEET_DIR:-${TMPDIR:-/tmp}}/${RUN:-adhoc}"; mkdir -p "$rdir" 2>/dev/null || true
  rankerr="$rdir/rank.$kind.stderr"
  : > "$rankerr" 2>/dev/null || rankerr=/dev/null
  # Walk the ranked list rather than taking its first row: the FIRST acceptable account may not be
  # the first RANKED one, because a candidate that already holds this sid cannot receive it.
  while IFS= read -r cand; do
    cand="${cand%% *}"
    [ -n "$cand" ] || continue
    # `none` is the router's SENTINEL for "nothing is routable", not an account. Taken literally it
    # passes the `!= source` test, so the caller waited out the full capacity budget and then handed
    # off to an account that does not exist -- observed 2026-09-10, the poller's own log reading
    # "in-place recovery of 2d71c6d8 onto none" for 480s. An unroutable moment must PARK immediately.
    [ "$cand" = none ] && break
    # Walk past the SOURCE account: the router may well rank the limited account first on weekly
    # headroom while its 5-hour window is what just closed.
    [ "$cand" = "$1" ] && continue
    # NEVER TRUST A BARE STRING FROM A ROUTER. Everything downstream — launcher_for, cfg_dir, the
    # transplant's destination — resolves this token through lib/account-map.generated.sh, and a
    # token the map does not declare becomes a HALTED fire minutes later, AFTER the source pane has
    # already been /exit'd. Ask the map HERE, where the answer is a cheap `continue`.
    # FAILS OPEN when the map is not loaded: an unavailable validator bounds ITSELF, never the
    # world, and refusing every candidate over a missing library would park a routable fleet.
    if command -v cc_acct_dir_for_name >/dev/null 2>&1 && ! cc_acct_dir_for_name "$cand" >/dev/null 2>&1; then
      LF_PICK_REJECTED="${LF_PICK_REJECTED}${LF_PICK_REJECTED:+ }$cand"
      echo "lr-fleet: the router named '$cand', which lib/account-map.generated.sh does not declare — walking on rather than firing at a name nothing can resolve" >&2
      continue
    fi
    if [ -n "${3:-}" ] && _lf_target_holds_sid "$cand" "$3"; then
      LF_PICK_SKIPPED_HOLDER="${LF_PICK_SKIPPED_HOLDER}${LF_PICK_SKIPPED_HOLDER:+ }$cand"
      continue
    fi
    lf_charge_assign "$cand"
    LF_PICK_TARGET="$cand"; return 0
  done <<EOF
$("$ACCOUNTS" --rank "$kind" --recovery --max-wait 3 2>"$rankerr" || true)
EOF
  # THE RANK IS ASKED IN THE RECOVERY LANE, AND THAT IS NOT A STYLE CHOICE (W6a). A recovery is not
  # a dispatch: a dispatch places a NEW unit that can be cut to fit the quota, a recovery
  # transplants an EXISTING long session that replays a cold context and keeps burning, and a
  # re-limit costs a whole second recovery cycle. `--recovery` turns on the SURVIVAL floors
  # (bin/claude-accounts `recovery_floors`), so an account with room for a fire but not for a
  # transplant is excluded HERE rather than discovered two hours later.
  # `--max-wait 3` is the ROUTER's own wall-clock bound. No outer timeout is wrapped around it: a
  # bound you guess can only convict a healthy call, and this one already bounds itself.
  LF_RANK_WHY="$(lf_rank_why "$rankerr")"
  return 1
}
# ── THE ADMIT SECTION — everything under the lock, and NOTHING ELSE ─────────────────────────────
# Returns 0 = admitted and LF_ADMIT_TARGET / LF_ADMIT_T0 are set · 1 = parked, the row is already
# written · 3 = dry run, the row is already written and the caller stops at rc 0.
# The three-way return is what lets lf_one hold the lock across the WHOLE section with exactly ONE
# release: a section with five `return` sites and a release beside each is a release site waiting
# to be missed.
lf_admit_section() { # $1=sid $2=cfg $3=acct $4=pane $5=cwd $6=tier → 0 admitted · 1 parked · 3 dry
  local sid="$1" cfg="$2" acct="$3" pane="$4" cwd="$5" tier="$6" target model="" effort=""
  LF_ADMIT_TARGET=""; LF_ADMIT_T0=""
  # CALLED DIRECTLY, never through `$( )` — see lf_pick_target's header. A subshell here is what
  # made three of its four outputs unreachable.
  lf_pick_target "$acct" "$tier" "$sid" || {
    # THE PARK CARRIES THE ROUTER'S OWN REASONS. Each clause is a different cause with a different
    # next action, so they are joined rather than collapsed: destinations that already hold the
    # session (a transplant there is refused on arrival), names the account map does not declare,
    # and the router's own exclusion text. `no routable target` alone said none of them.
    local pwhy=""
    [ -n "${LF_PICK_SKIPPED_HOLDER:-}" ] && pwhy="every candidate past $acct already holds this session ($LF_PICK_SKIPPED_HOLDER) — transplanting there is refused on arrival"
    [ -n "${LF_PICK_REJECTED:-}" ] && pwhy="${pwhy:+$pwhy; }the router named account(s) the map does not declare: $LF_PICK_REJECTED"
    [ -n "${LF_RANK_WHY:-}" ] && pwhy="${pwhy:+$pwhy; }router: $LF_RANK_WHY"
    [ -n "$pwhy" ] || pwhy="the recovery lane returned no account and printed no reason — read $FLEET_DIR/$RUN/rank.*.stderr"
    echo "lr-fleet: $sid — no routable target: $pwhy" >&2
    lf_row "$sid" "$pane" "$pane" "$acct" "-" "parked" "no routable target: $pwhy"
    return 1
  }
  target="$LF_PICK_TARGET"
  [ "$target" != "$acct" ] || { lf_row "$sid" "$pane" "$pane" "$acct" "$target" "parked" "target is the limited account"; return 1; }
  case "$tier" in */*) model="${tier%%/*}"; effort="${tier#*/}" ;; esac
  if [ "$DRY" = 1 ]; then
    echo "lr-fleet: DRY — would recover ${sid:0:8}: pane ${pane:-<new>} on $acct → $target (tier ${tier:-default}) via: $HANDOFF --sid $sid --config-dir $cfg --cwd $cwd --target $target --launch --in-place${pane:+ --source-pane $pane}${model:+ --model $model}${effort:+ --effort $effort}"
    lf_row "$sid" "$pane" "$pane" "$acct" "$target" "dry-run" "-"; return 3
  fi
  LF_ADMIT_T0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # the IDL floor: only refusals from THIS attempt count
  # The park now names the gate's own reason AND, when the launcher has already been refused for this
  # sid, the term that refused it — the two facts that decide whether to shed load, close panes, or
  # wait out a window. `capacity` alone said none of them.
  LF_PARK_REASON=""
  lf_capacity_wait "in-place recovery of ${sid:0:8} onto $target" || {
    local pnote="capacity${LF_PARK_REASON:+ — $LF_PARK_REASON}" pcause
    pcause="$(lf_idl_cause "$sid" "$LF_ADMIT_T0" || true)"; [ -n "$pcause" ] && pnote="$pnote; $pcause"
    lf_row "$sid" "$pane" "$pane" "$acct" "$target" "parked" "$pnote"; return 1; }
  LF_ADMIT_TARGET="$target"
  return 0
}
lf_one() { # $1=sid $2=cfg $3=acct $4=pane $5=cwd $6=tier → rc of the recovery; prints the result row
  local sid="$1" cfg="$2" acct="$3" pane="$4" cwd="$5" tier="$6" target rc=0 out rdir="$FLEET_DIR/$RUN" model="" effort="" arc=0
  mkdir -p "$rdir"
  # ONE TAKE, ONE RELEASE. The actuator below is DELIBERATELY outside the lock: it is the 115-658 s
  # half, and serializing it would turn the pool back into the queue this wave replaced.
  lf_admit_lock_take || {
    lf_row "$sid" "$pane" "$pane" "$acct" "-" "parked" "the admit lock $LF_ADMIT_LOCK could not be taken or stolen — nothing was ranked, charged or probed"
    return 1; }
  lf_admit_section "$sid" "$cfg" "$acct" "$pane" "$cwd" "$tier"; arc=$?
  lf_admit_lock_release
  case "$arc" in
    0) : ;;
    3) return 0 ;;              # dry run: the row is written, nothing is owed
    *) return 1 ;;
  esac
  target="$LF_ADMIT_TARGET"
  local t0="$LF_ADMIT_T0"
  case "$tier" in */*) model="${tier%%/*}"; effort="${tier#*/}" ;; esac
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
# THE RECORD IS BOUNDED AT THE WRITER, because the pool made this file CONCURRENT (W6b). O_APPEND
# is atomic only up to the writer's stdio buffer: a record longer than it goes out as several
# write() calls and a second worker's row splices into the middle of one (repo lesson:
# append-atomicity-ends-at-the-stdio-buffer, and lr_state_append keeps the same rule for the same
# reason). The note is the only unbounded field — a park now carries the router's own reason text —
# so it is cut here rather than trusted to be short. TAB and newline are stripped for the same
# class of reason: this is a TSV whose readers name eight variables, and a stray separator inside a
# value silently re-columns the row.
lf_row() { # sid pane_before pane_after acct_before acct_after mechanism/verdict note → appended to the run's results.tsv
  local note
  note="$(printf '%s' "$7" | tr '\t\n' '  ' | cut -c1-600)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" "$note" "$(lf_now)" >> "$FLEET_DIR/$RUN/results.tsv"
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

# ── THE POOL (W6b) — a pool, not a queue ───────────────────────────────────────────────────────
# `--recover` ran one lf_one at a time, so five sessions cost five SERIAL 115-658 s recoveries. A
# pool of LR_RECOVER_MAX_CONCURRENT workers runs them together and claims the next the moment ONE
# exits — deliberately NOT a group `wait`, which idles the whole pool behind its slowest member and
# is the difference this wave is buying.
#
# NO `wait -n`: /bin/bash on this box is 3.2, and 3.2 does not have it. That is not a portability
# nicety — lr-reset-poller.sh is a LaunchAgent and launchd's interpreter is /bin/bash, so anything
# this file does on the poller's path must run under 3.2 (repo lesson: the deployment interpreter is
# not the one on your PATH). The reaper therefore polls `kill -0`, which goes FALSE as soon as bash
# has reaped the child (measured on both 3.2 and 5.x; `wait` still returns the remembered status).
#
# THE POLL IS A CEILING ON CLAIM LATENCY, NEVER A FLOOR ON THE RUN. The wait loop's guard is "the
# pool is FULL", which is false whenever a slot is free, so a caller with room never enters the
# body — the shape the poll-period-as-a-cost-floor lesson warns about is the one where the guard is
# "the child is alive", and it is not this one.
#
# The ADMIT SECTION inside each worker is still serialized by $LF_ADMIT_LOCK, so the concurrency
# bought here is in the ACTUATOR — where the 115-658 s actually live — and never in the routing
# decision, which must stay one-at-a-time or every worker picks the same account.
LF_PIDS=""                 # space-separated "<pid>:<sid>" for the workers still in flight
lf_pool_max() { # → the configured concurrency, junk falling back rather than to 0 (which never runs)
  local m="${LR_RECOVER_MAX_CONCURRENT:-2}"
  case "$m" in ''|*[!0-9]*|0) m=2 ;; esac
  printf '%s' "$m"
}
lf_pool_count() { local e n=0; for e in $LF_PIDS; do [ -n "$e" ] && n=$((n+1)); done; printf '%s' "$n"; }
# Reap every worker bash has already collected, release its per-sid run claim, and fold its rc into
# $LF_POOL_WORST. The claim is released HERE and nowhere else: a worker that released its own claim
# would have to do it before its last line, leaving a window where the sid is free while the run is
# still typing into the pane.
lf_pool_reap() { # → 0 always; prunes $LF_PIDS
  local e p sd keep="" wrc
  for e in $LF_PIDS; do
    [ -n "$e" ] || continue
    p="${e%%:*}"; sd="${e#*:}"
    if kill -0 "$p" 2>/dev/null; then keep="$keep $p:$sd"; continue; fi
    wrc=0; wait "$p" 2>/dev/null || wrc=$?
    [ "$wrc" = 0 ] || LF_POOL_WORST=1
    lf_run_claim_release "$sd"
  done
  LF_PIDS="$keep"
  return 0
}
lf_pool_wait_slot() { # $1=max → returns once fewer than $1 workers are in flight
  while :; do
    lf_pool_reap
    [ "$(lf_pool_count)" -lt "$1" ] && return 0
    sleep "${LR_POOL_POLL_S:-0.2}"
  done
}
lf_pool_drain() { # → returns once every worker has exited
  while :; do
    lf_pool_reap
    [ "$(lf_pool_count)" -eq 0 ] && return 0
    sleep "${LR_POOL_POLL_S:-0.2}"
  done
}

case "$MODE" in
  locate)
    # `--json` is the machine surface, and the census's own `--json` is RICHER than the 11-field
    # projection this driver could re-emit (state, why, cap, resets_at, claims, copies, faults).
    # exec, not a pipe: there is nothing for this process to add, and a consumer reading the
    # census's schema directly cannot be desynchronised from it by a re-render here.
    if [ "$JSON" = 1 ] && [ "${LF_SLOW_SCAN:-0}" != 1 ] && [ -x "${CC_LIMITED:-$LR/../../bin/cc-limited}" ]; then
      exec "${CC_LIMITED:-$LR/../../bin/cc-limited}" --all --json
    fi
    # rc 6 IS NOT A REFUSAL. The contract says rows ARE printed at 6 — it means "this census is
    # incomplete", not "this census is absent" — so discarding them here would be the opposite
    # error to the one rc 5 guards, and just as silent. Only a refusal aborts.
    rows="$(lf_census)" || { rc=$?; [ "$rc" = 6 ] || exit "$rc"; }
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
    # THE CENSUS IS READ BEFORE census.tsv EXISTS, and that order is the whole point. An unreadable
    # instrument (rc 5) must leave NO file: an EMPTY census.tsv is indistinguishable from a clean
    # fleet to every later reader of this run dir, and this driver's own `--report` is one of them.
    rows="$(lf_census)" || { rc=$?
      [ "$rc" = 6 ] || { echo "lr-fleet: --recover REFUSED — the census could not be taken (rc $rc); $FLEET_DIR/$RUN/census.tsv left ABSENT rather than empty" >&2; exit "$rc"; }; }
    printf '%s\n' "$rows" > "$FLEET_DIR/$RUN/census.tsv"
    printf '%s\n' "$rows" | lf_print_census >&2
    n=0; worst=0; LF_POOL_WORST=0; POOL_MAX="$(lf_pool_max)"
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
      # W5'S PER-SID RUN CLAIM, TAKEN BEFORE THE FORK. lr-reset-poller and cc-lr both reserve the
      # same directory before driving a sid, so a pool worker that skipped it would be the third
      # writer typing into one pane. Refused here is a ROW, not a silent skip: a session the fleet
      # declined to touch because someone else already has it is exactly the thing a reader of the
      # report needs told.
      # A DRY RUN RESERVES NOTHING. `--dry-run` writes no state anywhere else, and a claim left in
      # $RUN_CLAIMS by a preview would block the real recovery of that sid for the claim's TTL.
      if [ "$DRY" = 0 ] && ! lf_run_claim_take "$sid"; then
        lf_row "$sid" "$pane" "$pane" "$acct" "-" "skipped" "a live run already holds $RUN_CLAIMS/$sid.active (lr-reset-poller, cc-lr, or a sibling pool worker) — not driven twice"
        continue
      fi
      n=$((n+1))
      lf_pool_wait_slot "$POOL_MAX"
      # The worker is a SUBSHELL, not a setsid'd process: this driver stays alive until every
      # worker is done (it still has a report to render), so the detach `--one` needs — surviving
      # a tool call's process group being reaped — buys nothing here and would cost the rc.
      lf_one "$sid" "$cfg" "$acct" "$pane" "$cwd" "$tier" &
      LF_PIDS="$LF_PIDS $!:$sid"
    done <<EOF
$rows
EOF
    lf_pool_drain
    [ "${LF_POOL_WORST:-0}" = 0 ] || worst=1
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
      # CC_PANE_ID FIRST, ITERM_SESSION_ID only as the fallback — the shape tests/cc-pane.bats
      # ratchets ("no production file reads a BARE $ITERM_SESSION_ID without the CC_PANE_ID
      # fallback"), and the one its class-B cases describe: a STALE ITERM_SESSION_ID can sit beside
      # a live CC_PANE_ID after a transplant, and preferring the stale one addresses the wrong pane.
      # The `##*:` strip is safe for either: a bare CC_PANE_ID carries no colon and survives it.
      [ -n "$_lf_req" ] || { _lf_req="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _lf_req="${_lf_req##*:}"; }
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
      # THE CENSUS IS ASKED ABOUT ONE SID FIRST. `--sid` is a prefix query answered from the
      # marker/parked stores without a transcript walk, and rc 4 is its "no match" — the ONLY code
      # that earns the full census below. rc 5/6 are the instrument's, and are propagated verbatim.
      _cl="${CC_LIMITED:-$LR/../../bin/cc-limited}"; row=""; _q=4
      if [ "${LF_SLOW_SCAN:-0}" != 1 ] && [ -x "$_cl" ]; then
        row="$("$_cl" --all --sid "$SID" --tsv 2>/dev/null)"; _q=$?
        case "$_q" in
          3) echo "lr-fleet: --one $SID — the census calls this prefix AMBIGUOUS; pass the full uuid" >&2; exit 2 ;;
          5|6) echo "lr-fleet: --one $SID — census instrument rc $_q; not falling through to the slow scan over a broken instrument" >&2; exit "$_q" ;;
        esac
        [ "$_q" = 4 ] && row=""
        [ -z "$row" ] || row="$(printf '%s\n' "$row" | lf_census_fill | head -1)"
      fi
      # rc 4 (no match) is the ONE code that earns the full census: `--sid` is answered from the
      # marker and parked stores, and the slow scan additionally reads `.handed-off` copies and the
      # mirror dedupe, so its miss — not the query's — is the one that refuses.
      [ -n "$row" ] || row="$(lf_census | awk -F'\t' -v s="$SID" '$1 == s { print; exit }')"
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
    # READ BEFORE THE LOOP. `done <<EOF\n$(lf_census)\nEOF` discards the census's exit status
    # entirely, so an unreadable instrument would drain zero rows and print "nothing to enqueue" —
    # the healthy answer, from a census that never happened.
    _eq_rows="$(lf_census)" || { rc=$?
      [ "$rc" = 6 ] || { echo "lr-fleet: --enqueue REFUSED — the census could not be taken (rc $rc); nothing was enqueued" >&2; exit "$rc"; }; }
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
$_eq_rows
EOF
    if [ "$n" -gt 0 ]; then
      echo "lr-fleet: $n request(s) written. The poller drains them on its next tick (≤10 min); to run it now:"
      # NO `-k`: kickstart -k KILLS a running poller first, and a tick that is mid-transplant is
      # exactly the one a caller has just enqueued work for. Plain kickstart starts it if idle and
      # is a no-op if it is already draining — which is the behaviour this line is asking for.
      echo "  launchctl kickstart gui/$(id -u)/com.reso.lr-reset-poller"
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
      # THE CHECK IS OVER EVERY STORE, never only the one the transcript search stopped in. A
      # session TRANSPLANTED to another account keeps its `handed_off_to` tombstone in the TARGET
      # root, so a check keyed on `$tomb` alone cannot see it and --mark writes a SECOND one.
      # Downstream that is worse than doing nothing: hf_transplant_evidence
      # (scripts/handoff-fire.sh:2068-2078) REFUSES outright on finding two, so the stale pane the
      # mark was supposed to retire becomes unretirable. Same shape as that block, resolved-path
      # dedupe included — `~/.claude-next/projects` is a SYMLINK onto `~/.claude/projects`, so
      # counting PATHS reads one physical tombstone as two and would mis-report a same-store
      # tombstone as a transplant to somewhere else.
      # `$tx` exists, so its resolved form is exact; `$tomb` may not exist yet, and `readlink -f`
      # on an absent path prints NOTHING (rc 1) here, which would leave it unresolved and make a
      # mirrored store read as a different one.
      _mk_tomb_rp="$(readlink -f "$tx" 2>/dev/null || printf '%s' "$tx")"; _mk_tomb_rp="${_mk_tomb_rp%.jsonl}.HANDOFF.json"
      _mk_seen=""; _mk_list=""; _mk_n=0; _mk_cross=0
      # A heredoc, never a pipe: a `while` on the right of `|` runs in a subshell and none of these
      # assignments would escape it (memory: assignment-inside-command-substitution-never-escapes).
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        for t in "$c"/projects/*/"$MARK_SID".HANDOFF.json; do
          [ -f "$t" ] || continue
          _mk_rp="$(readlink -f "$t" 2>/dev/null || printf '%s' "$t")"
          case " $_mk_seen " in *" $_mk_rp "*) continue ;; esac
          _mk_seen="$_mk_seen $_mk_rp"; _mk_n=$((_mk_n + 1)); _mk_list="${_mk_list}${t}
"
          [ "$_mk_rp" = "$_mk_tomb_rp" ] || _mk_cross=1
        done
      done <<EOF
$(lr_config_dirs)
EOF
      if [ "$_mk_n" -gt 0 ]; then
        if [ "$_mk_cross" -eq 0 ]; then
          echo "lr-fleet: $tomb already exists — refusing to overwrite a tombstone" >&2
        else
          { echo "lr-fleet: --mark ${MARK_SID:0:8} REFUSED: a transplant tombstone for this session already exists:"
            printf '%s' "$_mk_list" | sed 's/^/lr-fleet:   /'
            echo "lr-fleet:   a TRANSPLANTED session is already disambiguated — that tombstone names where it went, so there is nothing for a duplicate-marker to decide. Retire the stale pane with: handoff-fire.sh self-close --transplanted-source --source-session $MARK_SID"
          } >&2
        fi
        exit 2
      fi
      jq -n --arg to "$cfg" --arg pid "$LIVE_PID" --arg pane "$live_pane" --arg ts "$(lf_now)" --arg by "${CLAUDE_CODE_SESSION_ID:-lr-fleet}" \
        '{handed_off_to:$to, superseded_by_pid:($pid|tonumber), superseded_by_pane:$pane, ts:$ts, reason:"same-account duplicate — the stale copy is retired; the guard blocks its prompts", written_by:$by}' > "$tomb"
      echo "lr-fleet: SUPERSEDED tombstone written: $tomb (live copy pid $LIVE_PID${live_pane:+, pane $live_pane}). Every OTHER process holding ${MARK_SID:0:8} now has its prompts blocked by handed-off-session-guard; retire its pane with: handoff-fire.sh self-close --transplanted-source --source-pane <stale pane> --source-session $MARK_SID --successor ${live_pane:-<live pane>}"
      exit 0
    fi
    # census: every sid held by more than one live process (registry rows + --resume argv + tmux)
    found=0; _dup_seen=""
    for f in "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"/*.json; do
      [ -f "$f" ] || continue
      sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || continue
      # ONE BLOCK PER SID, never one per registry ROW. This loop iterates registry FILES, and a
      # session with two rows is precisely the population the mode exists to report — so it was
      # reached twice and printed its whole DUPLICATE block, panes and prescription included,
      # twice (measured: sid 7f533f05). `found` counts DISTINCT sids, so the empty-census line
      # below still fires when there are none. The arithmetic stays lr_holder_count's alone.
      case " $_dup_seen " in *" $sid "*) continue ;; esac
      _dup_seen="$_dup_seen $sid"
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
  retire-husks)
    # ══ RETIRE A HUSK — a LIVE pane whose session has already MOVED (W10, § 10) ══════════════════
    # POSITIVE PROOF, never absence of evidence. A husk looks exactly like live work in the
    # operator's window, so closing one on a weak signal retires a session somebody is using. Four
    # things must all be true, and each is READ, not assumed:
    #   1. the census calls it HUSK (live row on this store + the move is recorded + nothing in
    #      flight — lr_husk_state, which carries the in-flight conjunct)
    #   2. the successor copy has a REAL assistant turn AFTER the move (lr_engaged_after) — the
    #      successor is not merely present, it has spoken
    #   3. a successor PROCESS is alive (registry row, or a --resume argv leaf)
    #   4. the husk window still exists, read from the terminal itself
    # Then the close is read back from a FRESH `kitty @ ls`, never from the close call's own return
    # value: an action that destroys its target returns "invalid" ON SUCCESS
    # (memory: action-return-read-off-a-destroyed-handle).
    if [ "${LR_HUSK_RETIRE:-on}" = off ]; then
      echo "lr-fleet: LR_HUSK_RETIRE=off — census only, nothing will be closed." >&2
    fi
    rows="$(lf_locate | lf_dedup_mirror | awk -F'\t' '$8 == "HUSK"')"
    if [ -z "$rows" ]; then echo "(no HUSK — every live pane still holds its own session)"; exit 0; fi
    n=0; closed=0; skipped=0
    while IFS=$'\t' read -r sid cfg acct pane pid cwd tier disp kind kinds err_age; do
      [ -n "$sid" ] || continue
      [ -z "$HUSK_PANE" ] || [ "$HUSK_PANE" = "$pane" ] || continue
      n=$((n+1))
      echo "HUSK ${sid:0:8}  pane $pane  pid $pid  ($acct)  $cwd"
      # (2)+(3): where did it go, has it spoken there, and is that process alive?
      tgt=""; tgt="$(lr_transplant_target "$sid" "$cfg" 2>/dev/null || true)"
      if [ -z "$tgt" ]; then echo "   SKIP — no transplant target on record"; skipped=$((skipped+1)); continue; fi
      ts=""
      for _t in "$cfg"/projects/*/"$sid".HANDOFF.json; do
        [ -f "$_t" ] || continue
        ts="$(sed -n '/"ts":"/{s/.*"ts":"\([^"]*\)".*/\1/p;q;}' "$_t")"; break
      done
      [ -n "$ts" ] || ts="1970-01-01T00:00:00Z"
      if ! lr_engaged_after "$tgt" "$sid" "${ts%Z}" 2>/dev/null; then
        echo "   SKIP — the successor under $(lf_acct_of_cfg "$tgt") has taken no turn since $ts; it is not proven to be carrying this session"
        skipped=$((skipped+1)); continue
      fi
      suc_pane=""
      suc_rows="$(lr_registry_live_rows "$sid" 2>/dev/null || true)"
      while IFS=$'\t' read -r _p _pid _a _c; do
        [ -n "$_p" ] || continue
        [ "$_p" = "$pane" ] && continue          # that is the husk itself
        suc_pane="$_p"; break
      done <<ROWS
$suc_rows
ROWS
      if [ -z "$suc_pane" ] && ! lr_resume_procs "$sid" >/dev/null 2>&1; then
        echo "   SKIP — the successor has no live pane and no --resume process; nothing is proven to be carrying it"
        skipped=$((skipped+1)); continue
      fi
      # (4) the husk window exists, per the terminal
      sock="$(lr_kitty_socket 2>/dev/null || true)"
      if [ -z "$sock" ]; then echo "   SKIP — no kitty control socket answered; the window cannot be read, so it must not be closed"; skipped=$((skipped+1)); continue; fi
      kb="$(lr_kitty_bin 2>/dev/null || echo kitty)"
      before="$("$kb" @ --to "$sock" ls 2>/dev/null | W="$pane" /usr/bin/python3 -c 'import json,sys,os
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
w=os.environ["W"]
print("yes" if any(str(x["id"])==w for o in d for t in o["tabs"] for x in t["windows"]) else "no")' 2>/dev/null || true)"
      if [ "$before" != yes ]; then echo "   SKIP — the terminal does not list window $pane (already gone, or not a kitty pane)"; skipped=$((skipped+1)); continue; fi
      if [ "${LR_HUSK_RETIRE:-on}" = off ] || [ "${DRY:-0}" = 1 ]; then
        echo "   WOULD RETIRE (successor ${suc_pane:-<resume process>} under $(lf_acct_of_cfg "$tgt"), engaged after $ts)"
        continue
      fi
      if [ "$ASSUME_YES" != 1 ]; then
        echo "   would retire — re-run with --yes to close it (successor ${suc_pane:-<resume process>} under $(lf_acct_of_cfg "$tgt"))"
        continue
      fi
      # THE CLOSE. Prefer the sanctioned self-close, which announces into the successor and keeps the
      # succession legible; the raw close-window is the fallback for a successor with no pane id.
      hf=""
      for c in "$(dirname "$0")/../handoff-fire.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/handoff-fire.sh" "$HOME/.claude/scripts/handoff-fire.sh"; do
        [ -x "$c" ] && { hf="$c"; break; }
      done
      if [ -n "$suc_pane" ] && [ -n "$hf" ]; then
        "$hf" self-close --transplanted-source --source-pane "$pane" --source-session "$sid" --successor "$suc_pane" >&2 || true
      else
        "$kb" @ --to "$sock" close-window --match "id:$pane" >/dev/null 2>&1 || true
      fi
      # READ BACK FROM A FRESH LS. Never the close's own return.
      after="$("$kb" @ --to "$sock" ls 2>/dev/null | W="$pane" /usr/bin/python3 -c 'import json,sys,os
try: d=json.load(sys.stdin)
except Exception: sys.exit(1)
w=os.environ["W"]
print("yes" if any(str(x["id"])==w for o in d for t in o["tabs"] for x in t["windows"]) else "no")' 2>/dev/null || true)"
      if [ "$after" = no ]; then echo "   RETIRED — window $pane is gone (verified by a fresh kitty @ ls)"; closed=$((closed+1))
      else echo "   STILL OPEN — window $pane survived the close; NOT counting it retired"; skipped=$((skipped+1)); fi
    done <<HUSKS
$rows
HUSKS
    echo "lr-fleet: $n husk(s) examined, $closed retired, $skipped left standing"
    [ "$skipped" -eq 0 ]
    exit $? ;;
  report)
    d="${REPORT_DIR:-$(cat "$FLEET_DIR/last" 2>/dev/null || true)}"
    [ -n "$d" ] && [ -d "$d" ] || { echo "lr-fleet: no run to report" >&2; exit 2; }
    lf_report "$d" ;;
esac
