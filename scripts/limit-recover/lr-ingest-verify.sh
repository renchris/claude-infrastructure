#!/usr/bin/env bash
# lr-ingest-verify.sh <bundle-dir>  → rc 0 the fast-path ingest is LICENSED / rc 1 fail closed.
#
# WHAT THIS REPLACES, AND WHY IT IS WORTH A SCRIPT (U12 §3-§6). `/limit-recover ingest <bundle>`
# costs 6-9 model round trips, 6-8 tool calls and ~26.5 K PERMANENTLY RESIDENT tokens per recovered
# session, and it bought ZERO information on 5/5 of the recoveries measured on 2026-09-19 — every
# bundle read `gaps_at_handoff: 0`, and the re-derivation was redundant in 3/3 of the sessions that
# actually ran it (skipped outright in 2/5). Re-measured here over ALL 24 of that day's bundles:
# 24/24 `gaps_at_handoff == 0`. So the ingest's whole job on the common path is to establish a
# precondition that is already on disk — and a precondition on disk is a shell predicate, not a
# conversation.
#
# Every clause below is machine-checkable from files that exist at relaunch time, costs 0 model
# tokens, and prints its OWN value beside its verdict. The last line of a rc-0 receipt is the
# one-line prompt the launcher substitutes for the ingest command.
#
# ── FAIL CLOSED IS THE WHOLE CONTRACT ────────────────────────────────────────────────────────────
# A clause this script cannot EVALUATE is a FAILURE, never a pass. A missing file, an absent field,
# an unparseable value, a jq that is not on PATH — each is rc 1, and rc 1 means the launcher keeps
# today's full `/limit-recover ingest` prompt with the failing clause NAMED in it. The degraded path
# is therefore the path we already ship: a false FAIL costs one expensive ingest, a false PASS costs
# the recovered session's owed work. Those are not symmetric, and this script is not a summariser —
# it is a gate whose silence must never be readable as consent.
#
# THE ABSENCE READING IS EXPLICIT, NOT INCIDENTAL (repo lesson: empty-vs-no-surface). An emptiness
# test over a rendered surface cannot separate "empty" from "the surface does not exist", and the
# two demand opposite actions. So every clause that reads a collection first asserts that the
# collection's CONTAINER exists; `null | length` is 0 in jq, and that zero would otherwise read as
# "nothing is owed" over a file whose field was renamed.
#
# ── CLAUSE D IS A WRITE, SO THE RE-DERIVE PATH IS A DIFFERENT MODE ───────────────────────────────
# Measured while building this script (2026-09-19T00:05Z): sweeping all 24 of the day's bundles to
# see which clauses passed DISARMED TWO LIVE SESSIONS' continuation sentinels — 65186f1f's had been
# armed 45 seconds earlier and was driving a wave. Both were restored from ~/.claude/autonomy/
# idl.jsonl, which records the step text and the arming sid on every `set`. The lesson is structural,
# not an operator error: the sentinel is keyed on (config-dir | cwd) and the verifier runs the clear
# from the bundle's OWN cwd under the bundle's OWN config dir, so a verification run is
# indistinguishable from the relaunch it is verifying. The launcher's single run at relaunch is the
# legitimate occasion; every other run — the paranoid re-derive the prompt itself advertises, an
# audit sweep, a test — must not write. Hence `--no-clear`, and hence the prompt's re-derive command
# carries it.
#
# Usage:   lr-ingest-verify.sh [--no-clear] <bundle-dir>
# Env:     CLAUDE_CONFIG_DIR   REQUIRED — the TARGET account's config dir (clause C1)
#          LR_SUBMIT_TOKEN     optional — the run token W3's submit probe looks for in the target
#                              transcript; appended to the fast-path line so that a prompt which
#                              REACHED the composer is distinguishable from one that did not
# Output:  one line per clause on stdout (`PASS <id> — <value>` / `FAIL <id> — <value>`), a
#          `verdict:` line, and — on rc 0 only — the composed one-line prompt as the LAST line.
#          The launcher reads `tail -1` on rc 0 and `grep -m1 FAIL` on rc 1.
# Receipt: the caller redirects stdout; the launcher writes $BUNDLE/INGEST-VERIFIED.txt.

set -uo pipefail

LRV_RC=0
LRV_FIRST_FAIL=""

clause() { # $1=PASS|FAIL  $2=id  $3=one-line value
  local v="$1" id="$2" txt="$3"
  # A clause line must be ONE line: the launcher folds a FAIL straight into a prompt that is typed
  # into a TUI composer, and an embedded newline there submits half a sentence.
  txt="$(printf '%s' "$txt" | tr '\n\r\t' '   ' | cut -c1-200)"
  printf '%s %s — %s\n' "$v" "$id" "$txt"
  if [ "$v" = FAIL ]; then
    LRV_RC=1
    [ -n "$LRV_FIRST_FAIL" ] || LRV_FIRST_FAIL="$id"
  fi
  return 0
}

fatal() { # a precondition of the CHECKER itself — report it in the clause vocabulary and stop
  clause FAIL "$1" "$2"
  printf 'verdict: rc 1 (first failure: %s)\n' "$LRV_FIRST_FAIL"
  exit 1
}

LRV_CLEAR=1
while [ $# -gt 0 ]; do
  case "$1" in
    --no-clear) LRV_CLEAR=0; shift ;;
    --) shift; break ;;
    -*) fatal argv "unknown flag $1 (accepted: --no-clear)" ;;
    *)  break ;;
  esac
done

B="${1:-}"
[ -n "$B" ] || fatal argv "usage: lr-ingest-verify.sh [--no-clear] <bundle-dir>"
B="${B%/}"
printf 'lr-ingest-verify 1 — bundle %s — %s\n' "$B" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')"

command -v jq >/dev/null 2>&1 || fatal jq "jq is not on PATH — no clause below can be evaluated"
MAN="$B/MANIFEST.json"
AUD="$B/audit.json"
[ -r "$MAN" ] || fatal A0 "MANIFEST.json is not readable at $MAN"
[ -r "$AUD" ] || fatal A0 "audit.json is not readable at $AUD"
jq -e . "$MAN" >/dev/null 2>&1 || fatal A0 "MANIFEST.json is not parseable JSON"
jq -e . "$AUD" >/dev/null 2>&1 || fatal A0 "audit.json is not parseable JSON"

mval() { jq -r "$1" "$MAN" 2>/dev/null; }
aval() { jq -r "$1" "$AUD" 2>/dev/null; }

SID="$(mval '.sid // "ABSENT"')"
TCFG_M="$(mval '.target_cfg // "ABSENT"')"
SRC_CFG="$(mval '.source_cfg // "ABSENT"')"
TARGET="$(mval '.target // "ABSENT"')"
WT="$(mval '.worktree // .cwd // "ABSENT"')"
TS="$(mval '.ts // "ABSENT"')"

# ── A — NOTHING IS OWED ──────────────────────────────────────────────────────────────────────────
_v="$(mval '.gaps_at_handoff // "ABSENT"')"
if [ "$_v" = 0 ]; then clause PASS A1 "gaps_at_handoff=0"; else clause FAIL A1 "gaps_at_handoff=$_v"; fi

_g="$(aval '.counts.gaps // "ABSENT"')"; _w="$(aval '.counts.waiting // "ABSENT"')"
# `waiting` is the audit's own name for PENDING / UNSETTLED-INFLIGHT / RUNNING units (lr-audit.py
# :2272-2278) — i.e. work that was IN FLIGHT when the bundle was cut. It is the clause that makes
# A6 below a narrow residual rather than the only guard against killing a live delegation.
if [ "$_g" = 0 ] && [ "$_w" = 0 ]; then clause PASS A2 "counts.gaps=0 counts.waiting=0"
else clause FAIL A2 "counts.gaps=$_g counts.waiting=$_w"; fi

_d="$(jq -r '
  if (.delegations | type) != "object" then "ABSENT/ABSENT/ABSENT"
  elif (.delegations | has("open") and has("spawned") and has("settled") | not) then "ABSENT/ABSENT/ABSENT"
  else ((if (.delegations.open|type)=="array" then (.delegations.open|length) else .delegations.open end)|tostring)
       + "/" + (.delegations.spawned|tostring) + "/" + (.delegations.settled|tostring) end' "$AUD" 2>/dev/null)"
_open="${_d%%/*}"; _rest="${_d#*/}"; _sp="${_rest%%/*}"; _se="${_rest#*/}"
if [ "$_open" = 0 ] && [ -n "$_sp" ] && [ "$_sp" = "$_se" ]; then
  clause PASS A3 "delegations open=0 spawned=$_sp settled=$_se"
else clause FAIL A3 "delegations open=$_open spawned=$_sp settled=$_se"; fi

# The session must have died on a QUOTA wall, not on a network error or a crash — a transplant is
# the wrong cure for anything else, and handoff-fire's own precheck refuses those before the move.
_k="$(aval '.last_api_error.kind // "ABSENT"')"
case "$_k" in
  session|weekly|monthly_spend) clause PASS A4 "last_api_error.kind=$_k" ;;
  *) clause FAIL A4 "last_api_error.kind=$_k (expected session|weekly|monthly_spend)" ;;
esac

# `.teams` is an OBJECT keyed led/other_team_dirs/wip_refs — NOT an array (measured on today's
# bundles; U12 §6.1's `.teams[].members[]?` spelling ERRORS on the real shape). A live teammate
# belongs to its lead and must not be inherited by a recovered session.
_t="$(jq -r 'if (.teams|type) != "object" then "ABSENT"
             elif (.teams|has("led")|not) then "ABSENT"
             else ([.teams.led[]? | .members[]? | select(.verdict=="RUNNING")] | length | tostring) end' "$AUD" 2>/dev/null)"
if [ "$_t" = 0 ]; then clause PASS A5 "teams.led RUNNING members=0"; else clause FAIL A5 "teams.led RUNNING members=$_t"; fi

# A6 — killed_inflight, read from THE RUN'S OWN state log (W2's lr_state_append, $B/events.jsonl).
# THE ABSENCE OF THE FILE IS ITS OWN VERDICT AND IT IS A FAILURE. Post-W2 every admitted recovery
# writes at least one record (`lrh_state admitted gate`, lr-handoff.sh:619), so an absent log means
# either the precheck never ran, the admission token could not be minted, or the live lr-lib has no
# lr_state_append — three states in which nothing here can say what the recycle interrupted.
# Consequence, stated rather than hidden: all 24 of 2026-09-19's bundles predate the state log and
# therefore fail HERE and only here, which is exactly the fail-closed direction (they degrade to the
# ingest they already ran). A record carrying killed_inflight=0 is a positive pass.
EV="$B/events.jsonl"
if [ ! -s "$EV" ]; then
  clause FAIL A6 "no events.jsonl in the bundle — the run's state log never ran; killed_inflight is unknowable"
else
  _ki="$(jq -rs '[ .[]
      | (if (type=="object") then . else {} end)
      | ( (.killed_inflight // empty)
        , ( (.detail // "") | capture("killed_inflight=(?<n>[0-9]+)") | .n | tonumber ) ) ]
    | if length == 0 then -1 else max end' "$EV" 2>/dev/null)"
  case "$_ki" in
    0)  clause PASS A6 "killed_inflight=0 (recorded in events.jsonl)" ;;
    -1) clause PASS A6 "killed_inflight: no record in events.jsonl (state log ran; nothing reported a kill)" ;;
    ''|*[!0-9-]*) clause FAIL A6 "events.jsonl is unparseable — killed_inflight cannot be read" ;;
    *)  clause FAIL A6 "killed_inflight=$_ki — the recycle interrupted in-flight work" ;;
  esac
fi

# ── B — NOTHING CHANGED UNDER US SINCE THE BUNDLE WAS CUT ────────────────────────────────────────
# One pass over one file (0.09 s measured on a 7.1 MB transcript): no workflow globs, no git, no pid
# census. The bundle's audit is a snapshot; this is the same ledger re-derived from the transcript
# the recovered session is about to resume, so a delegation that settled — or failed — between the
# handoff and the relaunch cannot slip past as a stale PASS.
LRV_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
TX=""
if [ -r "$B/transplant.json" ]; then TX="$(jq -r '.target_transcript // empty' "$B/transplant.json" 2>/dev/null)"; fi
if [ -z "$TX" ] || [ ! -r "$TX" ]; then
  for _c in "$TCFG_M"/projects/*/"$SID".jsonl; do [ -r "$_c" ] && { TX="$_c"; break; }; done
fi
if [ -z "$TX" ] || [ ! -r "$TX" ]; then
  clause FAIL B1 "no readable target transcript for ${SID} under ${TCFG_M} — the ledger cannot be re-derived"
elif [ ! -r "$LRV_DIR/lr-audit.py" ]; then
  clause FAIL B1 "lr-audit.py is not beside this script ($LRV_DIR) — the ledger cannot be re-derived"
else
  _led="$(python3 "$LRV_DIR/lr-audit.py" --ledger-only --transcript "$TX" 2>/dev/null)"
  _res="$(printf '%s' "$_led" | jq -r '
    if (type != "object") or (has("open_delegations")|not) or (has("nonsuccess_notifications")|not)
       or (has("spawned")|not) or (has("settled")|not) then "ABSENT/ABSENT/ABSENT/ABSENT"
    else ((.open_delegations|length)|tostring) + "/" + ((.nonsuccess_notifications|length)|tostring)
         + "/" + (.spawned|tostring) + "/" + (.settled|tostring) end' 2>/dev/null)"
  _o="${_res%%/*}"; _r1="${_res#*/}"; _n="${_r1%%/*}"; _r2="${_r1#*/}"; _s1="${_r2%%/*}"; _s2="${_r2#*/}"
  if [ "$_o" = 0 ] && [ "$_n" = 0 ] && [ -n "$_s1" ] && [ "$_s1" = "$_s2" ]; then
    clause PASS B1 "re-audit open=0 nonsuccess=0 spawned=$_s1 settled=$_s2"
  else
    clause FAIL B1 "re-audit open=$_o nonsuccess=$_n spawned=$_s1 settled=$_s2"
  fi
fi

# ── C — IDENTITY: the session is where the handoff says it is ────────────────────────────────────
# C1 is deliberately a THREE-way agreement, not the two-way `$CLAUDE_CONFIG_DIR == .target_cfg` of
# U12 §6.1: read from inside the launcher, that comparison is tautological (the launcher sets the
# variable from the same $TCFG the manifest recorded) and a tautology in a fail-closed gate is a
# clause cleared by construction. The third leg re-derives the config dir from the ACCOUNT NAME
# through the LIVE account map, so a renamed or regenerated map — the same live-layer skew class the
# parser preflight exists for — is caught here instead of at the pane.
_mapped=""
for _am in "${CC_ACCOUNT_MAP:-}" "$LRV_DIR/../../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_am" ] && [ -r "$_am" ] || continue
  # shellcheck source=/dev/null
  . "$_am" 2>/dev/null || true
  break
done
if command -v cc_acct_dir_for_name >/dev/null 2>&1 && cc_acct_dir_for_name "$TARGET" 2>/dev/null; then
  _mapped="${CC_ACCT_DIR:-}"
fi
if [ -z "${CLAUDE_CONFIG_DIR:-}" ]; then
  clause FAIL C1 "CLAUDE_CONFIG_DIR is unset — run this from the launcher, or from inside the recovered session"
elif [ "$CLAUDE_CONFIG_DIR" != "$TCFG_M" ]; then
  clause FAIL C1 "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR ≠ manifest target_cfg=$TCFG_M"
elif [ -z "$_mapped" ]; then
  clause FAIL C1 "the account map cannot resolve target '$TARGET' — its config dir is unverifiable"
elif [ "$_mapped" != "$TCFG_M" ]; then
  clause FAIL C1 "account map says $TARGET → $_mapped, manifest says $TCFG_M"
else
  clause PASS C1 "config dir $TCFG_M agrees across env, manifest and the account map ($TARGET)"
fi

_hits=0; _tx_seen=""
for _c in "$TCFG_M"/projects/*/"$SID".jsonl; do [ -r "$_c" ] || continue; _hits=$((_hits+1)); _tx_seen="$_c"; done
if [ "$_hits" = 1 ]; then clause PASS C2 "transcript $_tx_seen"
elif [ "$_hits" = 0 ]; then clause FAIL C2 "no transcript $SID under $TCFG_M/projects"
else clause FAIL C2 "$_hits copies of $SID under $TCFG_M/projects — ambiguous"; fi

# The split-brain lock records the transplant OWNER. Its field is `to`, not `target_cfg`
# (lr-transplant.sh:70-72) — U12 §6.1's spelling reads null against every lock on disk and its
# `jq -e` would then FAIL every bundle, which is why the anchor is re-derived here.
LOCK=""
[ -r "$B/transplant.json" ] && LOCK="$(jq -r '.lock // empty' "$B/transplant.json" 2>/dev/null)"
[ -n "$LOCK" ] || LOCK="$HOME/.reso/limit-recover/locks/$SID.lock"
if [ ! -r "$LOCK" ]; then clause FAIL C3 "no transplant lock at $LOCK"
else
  _to="$(jq -r '.to // "ABSENT"' "$LOCK" 2>/dev/null)"
  if [ "$_to" = "$TCFG_M" ]; then clause PASS C3 "lock $LOCK → $_to"
  else clause FAIL C3 "lock $LOCK says to=$_to, manifest target_cfg=$TCFG_M"; fi
fi

TOMB=""
[ -r "$B/transplant.json" ] && TOMB="$(jq -r '.tombstone // empty' "$B/transplant.json" 2>/dev/null)"
if [ -z "$TOMB" ]; then
  for _c in "$SRC_CFG"/projects/*/"$SID".HANDOFF.json; do [ -r "$_c" ] && { TOMB="$_c"; break; }; done
fi
if [ -n "$TOMB" ] && [ -r "$TOMB" ]; then clause PASS C4 "source tombstoned at $TOMB"
else clause FAIL C4 "no source tombstone for $SID under $SRC_CFG — the source may still be live"; fi

# A pool worktree is a FLEET slot, not a session's own tree: resuming into one would hand the
# recovered session a checkout another recovery is entitled to reclaim.
if [ ! -d "$WT" ]; then
  clause FAIL C5 "worktree $WT does not exist"
elif ! git -C "$WT" rev-parse --git-dir >/dev/null 2>&1; then
  clause PASS C5 "$WT is not a git repo — no branch to be a pool slot"
else
  _br="$(git -C "$WT" branch --show-current 2>/dev/null || true)"
  case "$_br" in
    pool/*) clause FAIL C5 "branch $_br is a fleet pool slot" ;;
    "")     clause FAIL C5 "$WT is on a detached HEAD — no branch to check against pool/*" ;;
    *)      clause PASS C5 "branch $_br" ;;
  esac
fi

# ── D — THE ONE SIDE EFFECT THE INGEST STEP PERFORMED, MOVED TO THE SHELL ────────────────────────
# `/limit-recover ingest` step 1 clears the auto-continue sentinel: a pre-limit armed continuation
# would otherwise re-drive a step the recovered session has no context for. Run it HERE, under the
# TARGET config dir and the session's OWN sid, from the session's worktree — the sentinel is keyed
# on (config-dir|cwd), so running it from anywhere else clears nothing and says "cleared" anyway.
SC="$HOME/.claude/hooks/session-continue.sh"
_verb=clear; [ "$LRV_CLEAR" = 1 ] || _verb=status
if [ ! -x "$SC" ]; then
  clause FAIL D1 "session-continue.sh is not executable at $SC — the armed continuation cannot be cleared"
else
  _cl="$(cd "${WT:-$PWD}" 2>/dev/null && CLAUDE_CONFIG_DIR="$TCFG_M" CLAUDE_CODE_SESSION_ID="$SID" "$SC" "$_verb" 2>&1)"
  _clrc=$?
  if [ "$_clrc" -ne 0 ]; then clause FAIL D1 "session-continue.sh $_verb exited $_clrc: $_cl"
  elif [ "$LRV_CLEAR" = 1 ]; then clause PASS D1 "auto-continue cleared: $_cl"
  else clause PASS D1 "auto-continue NOT touched (--no-clear); sentinel reads: $_cl"; fi
fi

# ── VERDICT + THE ONE LINE THAT REPLACES THE INGEST ──────────────────────────────────────────────
if [ "$LRV_RC" -ne 0 ]; then
  printf 'verdict: rc 1 (first failure: %s) — the launcher keeps the full /limit-recover ingest prompt\n' "$LRV_FIRST_FAIL"
  exit 1
fi

SID8="${SID:0:8}"
STATUS="$(aval '.last_api_error.status // "429"')"
SRC_ACCT=""
if command -v cc_acct_name_for_dir_basename >/dev/null 2>&1; then
  SRC_ACCT="$(cc_acct_name_for_dir_basename "${SRC_CFG##*/}" 2>/dev/null || true)"
fi
[ -n "$SRC_ACCT" ] || SRC_ACCT="${SRC_CFG##*/}"
# The run token is what makes SUBMITTED observable: W3's submit probe looks for it in a `type:"user"`
# record of the target transcript, so a prompt that reached the composer is distinguishable from one
# that was typed into a pane nobody was reading. Without LR_SUBMIT_TOKEN (a standalone re-derive) the
# manifest's own run coordinates stand in, so the line is still self-identifying.
RUNTOK="${LR_SUBMIT_TOKEN:-run:$SID8:$TS}"

printf 'verdict: rc 0 (13 clauses PASS)\n'
printf 'Resumed in place on %s — same pane, same session %s, after a %s-limit %s on %s. lr-ingest-verify rc 0 (config dir, session id, transcript path, lock target, source tombstone, branch, auto-continue cleared) and the audit says gaps %s, waiting %s, %s open delegations — nothing is owed and nothing re-runs. Continue the interrupted work from where you left off. Full check list and receipt: cat %s/INGEST-VERIFIED.txt — re-derive with: bash ~/.claude/scripts/limit-recover/lr-ingest-verify.sh --no-clear %s — %s\n' \
  "$TARGET" "$SID8" "$_k" "$STATUS" "$SRC_ACCT" "$_g" "$_w" "$_open" "$B" "$B" "$RUNTOK"
exit 0
