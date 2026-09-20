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
# The verdict line's clause count is COUNTED, never written down: a literal `13` is a second copy of
# a fact the clause list already holds, and the two drift the moment a clause is added (W3i added
# D2, and the literal would have kept saying 13 over 14 PASS lines).
LRV_PASSES=0
# …and the resume prompt's check list is ACCUMULATED at the clause calls for the same reason (W3i
# C6). It used to be a hand-written parenthetical — "(config dir, session id, transcript path, lock
# target, source tombstone, branch; pre-limit auto-continue …)" — and it had already drifted: it
# named "session id", which is no clause, and it described NONE of the six A clauses that decide
# whether anything is owed. A list written anywhere but the call site describes the clauses someone
# remembered, not the ones that ran.
LRV_SUBJECTS=""

clause() { # $1=PASS|FAIL  $2=id  $3=one-line value  [$4=the SUBJECT this clause settled]
  local v="$1" id="$2" txt="$3" subj="${4:-}"
  # A clause line must be ONE line: the launcher folds a FAIL straight into a prompt that is typed
  # into a TUI composer, and an embedded newline there submits half a sentence.
  txt="$(printf '%s' "$txt" | tr '\n\r\t' '   ' | cut -c1-200)"
  printf '%s %s — %s\n' "$v" "$id" "$txt"
  if [ "$v" = FAIL ]; then
    LRV_RC=1
    [ -n "$LRV_FIRST_FAIL" ] || LRV_FIRST_FAIL="$id"
  else
    LRV_PASSES=$(( LRV_PASSES + 1 ))
    # A clause added without a subject contributes its ID, which is visible in the prompt rather
    # than silently missing from it — the failure a hand-written list makes invisible.
    [ -n "$subj" ] || subj="$id"
    case ", $LRV_SUBJECTS," in
      *", $subj,"*) : ;;                      # two clauses may settle one subject (D1/D2, C1/C2)
      *) LRV_SUBJECTS="${LRV_SUBJECTS:+$LRV_SUBJECTS, }$subj" ;;
    esac
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
if [ "$_v" = 0 ]; then clause PASS A1 "gaps_at_handoff=0" "nothing owed at handoff"; else clause FAIL A1 "gaps_at_handoff=$_v"; fi

_g="$(aval '.counts.gaps // "ABSENT"')"; _w="$(aval '.counts.waiting // "ABSENT"')"
# `waiting` is the audit's own name for PENDING / UNSETTLED-INFLIGHT / RUNNING units (lr-audit.py
# :2272-2278) — i.e. work that was IN FLIGHT when the bundle was cut. It is the clause that makes
# A6 below a narrow residual rather than the only guard against killing a live delegation.
if [ "$_g" = 0 ] && [ "$_w" = 0 ]; then clause PASS A2 "counts.gaps=0 counts.waiting=0" "no gaps and nothing in flight"
else clause FAIL A2 "counts.gaps=$_g counts.waiting=$_w"; fi

_d="$(jq -r '
  if (.delegations | type) != "object" then "ABSENT/ABSENT/ABSENT"
  elif (.delegations | has("open") and has("spawned") and has("settled") | not) then "ABSENT/ABSENT/ABSENT"
  else ((if (.delegations.open|type)=="array" then (.delegations.open|length) else .delegations.open end)|tostring)
       + "/" + (.delegations.spawned|tostring) + "/" + (.delegations.settled|tostring) end' "$AUD" 2>/dev/null)"
_open="${_d%%/*}"; _rest="${_d#*/}"; _sp="${_rest%%/*}"; _se="${_rest#*/}"
if [ "$_open" = 0 ] && [ -n "$_sp" ] && [ "$_sp" = "$_se" ]; then
  clause PASS A3 "delegations open=0 spawned=$_sp settled=$_se" "every delegation settled"
else clause FAIL A3 "delegations open=$_open spawned=$_sp settled=$_se"; fi

# The session must have died on a QUOTA wall, not on a network error or a crash — a transplant is
# the wrong cure for anything else, and handoff-fire's own precheck refuses those before the move.
_k="$(aval '.last_api_error.kind // "ABSENT"')"
case "$_k" in
  session|weekly|monthly_spend) clause PASS A4 "last_api_error.kind=$_k" "died on a quota wall, not a crash" ;;
  *) clause FAIL A4 "last_api_error.kind=$_k (expected session|weekly|monthly_spend)" ;;
esac

# `.teams` is an OBJECT keyed led/other_team_dirs/wip_refs — NOT an array (measured on today's
# bundles; U12 §6.1's `.teams[].members[]?` spelling ERRORS on the real shape). A live teammate
# belongs to its lead and must not be inherited by a recovered session.
_t="$(jq -r 'if (.teams|type) != "object" then "ABSENT"
             elif (.teams|has("led")|not) then "ABSENT"
             else ([.teams.led[]? | .members[]? | select(.verdict=="RUNNING")] | length | tostring) end' "$AUD" 2>/dev/null)"
if [ "$_t" = 0 ]; then clause PASS A5 "teams.led RUNNING members=0" "no running teammate"; else clause FAIL A5 "teams.led RUNNING members=$_t"; fi

# A6 — killed_inflight, read from THE RUN'S OWN state log (W2's lr_state_append, $B/events.jsonl).
# THE ABSENCE OF THE FILE IS ITS OWN VERDICT AND IT IS A FAILURE. Post-W2 every admitted recovery
# writes at least one record (`lrh_state admitted gate`, lr-handoff.sh:619), so an absent log means
# either the precheck never ran, the admission token could not be minted, or the live lr-lib has no
# lr_state_append — three states in which nothing here can say what the recycle interrupted.
# Consequence, stated rather than hidden: all 24 of 2026-09-19's bundles predate the state log and
# therefore fail HERE and only here, which is exactly the fail-closed direction (they degrade to the
# ingest they already ran).
#
# ── AND A PRESENT-BUT-SILENT LOG IS THE SAME VERDICT (W3i D2) ────────────────────────────────────
# This clause used to PASS when the log EXISTED and no record carried the field ("state log ran;
# nothing reported a kill"). That is the fail-open the whole file is written against, and it fails
# open on exactly the state every bundle is in: NOTHING in the tree writes killed_inflight yet
# (`grep -rn killed_inflight scripts hooks bin` finds only this reader), so the moment W2's
# events.jsonl is being written, present-and-silent IS the shape of every bundle and A6 would clear
# all of them having measured nothing. A log that never recorded the value does not say the value
# was zero; it says the value is UNRECORDED — and this file's own contract settles the polarity: a
# clause it cannot EVALUATE is a FAILURE, never a pass. Only an explicit killed_inflight=0 record
# passes, because only that is a positive statement by a writer.
#
# The cost is named rather than hidden: until a writer lands (residual 1 of the W3i report — one
# line in lrh_precheck, W2's function), A6 refuses every real recovery and the fast path stays
# unreachable. That is the same direction the absent-file arm already took, and the alternative is a
# gate that says yes on no evidence.
#
# ── THE WRITER NOW EXISTS (W3i B3, lr-handoff.sh lrh_precheck) ───────────────────────────────────
# The paragraph above described a gate that could not be passed by any real recovery, and a sweep of
# all 69 bundles under ~/.reso/limit-recover proved it: rc 1 on 69 of 69, A6 failing on 68 of the 68
# that reached it and being the SOLE failure on one. `lrh_precheck` now records the read-only
# probe's own `live_subagents` count as `killed_inflight=<n>` the moment the probe succeeds, so a
# recovery cut by today's lr-handoff carries the positive statement this clause asks for. It cannot
# retroactively reach the 69 bundles already on disk — their state logs were written before the
# writer existed — so the sweep's numbers change only for bundles cut from here on, and this comment
# says so rather than letting a later reader mistake an unchanged sweep for an unfixed gate.
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
    0)  clause PASS A6 "killed_inflight=0 (recorded in events.jsonl)" "the recycle interrupted nothing" ;;
    -1) clause FAIL A6 "events.jsonl carries no killed_inflight record — the value was never written, so what the recycle interrupted is UNRECORDED, not zero" ;;
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
  # ── THE NONSUCCESS TEST IS RELATIVE TO THE BUNDLE, NOT TO ZERO (W3i B3) ────────────────────────
  # This clause's job is in its own heading: NOTHING CHANGED UNDER US SINCE THE BUNDLE WAS CUT. It
  # asked `nonsuccess_notifications == 0` — an ABSOLUTE test — over a re-derivation of the WHOLE
  # transcript, so every failed delegation the session ever had counted against a recovery that had
  # not changed anything at all. Measured over the 33 current-schema bundles under
  # ~/.reso/limit-recover: B1 failed 19, and in every failing case `open=0` and `spawned==settled`
  # held, so `nonsuccess` was the sole discriminator — while the bundle's OWN audit snapshot already
  # recorded the same notifications (a99681dc: 8 at bundle time, 8 now; 4101dbdf: 1 and 1;
  # c0f857b6: 1 and 1). Those three are the clause refusing a state it was cut from.
  #
  # The baseline is in the bundle, so no new store is needed: `audit.json .delegations.notifications`
  # is the same map `--ledger-only` derives `nonsuccess_notifications` from, and a notification
  # already terminal-but-not-completed there is not a change. What B1 must still catch — and this is
  # its whole purpose — is a delegation that FAILED between the handoff and the relaunch, which is
  # exactly an id absent from that baseline.
  #
  # A bundle whose audit predates the `delegations` field has NO baseline. That is unevaluable, not
  # zero (this file's contract), so it fails — but only when there is something to compare: a
  # re-audit with no nonsuccess at all needs no baseline to clear.
  _led="$(python3 "$LRV_DIR/lr-audit.py" --ledger-only --transcript "$TX" 2>/dev/null)"
  _res="$(printf '%s' "$_led" | jq -r --slurpfile snap "$AUD" '
    def baseline:
      (($snap[0] // {}) | .delegations) as $d
      | if ($d | type) != "object" or ($d | has("notifications") | not) then null
        else [ $d.notifications | to_entries[]
               | select(((.value.status // "") != "running") and ((.value.status // "") != "completed"))
               | .key ] end;
    if (type != "object") or (has("open_delegations")|not) or (has("nonsuccess_notifications")|not)
       or (has("spawned")|not) or (has("settled")|not) then "ABSENT/ABSENT/ABSENT/ABSENT/ABSENT"
    else
      baseline as $b
      | [ .nonsuccess_notifications[]? | .tool_use_id ] as $now
      | ( if $b == null then (if ($now|length) == 0 then "0" else "NO-BASELINE" end)
          else ([ $now[] | select( . as $i | ($b | index($i)) == null ) ] | length | tostring) end ) as $new
      | ((.open_delegations|length)|tostring) + "/" + $new + "/" + (.spawned|tostring)
        + "/" + (.settled|tostring) + "/" + (($now|length)|tostring)
    end' 2>/dev/null)"
  _o="${_res%%/*}"; _r1="${_res#*/}"; _n="${_r1%%/*}"; _r2="${_r1#*/}"; _s1="${_r2%%/*}"
  _r3="${_r2#*/}"; _s2="${_r3%%/*}"; _nall="${_r3#*/}"
  if [ "$_o" = 0 ] && [ "$_n" = 0 ] && [ -n "$_s1" ] && [ "$_s1" = "$_s2" ]; then
    clause PASS B1 "re-audit open=0 spawned=$_s1 settled=$_s2, no NEW nonsuccess notification since the bundle ($_nall already recorded in its audit)" "the ledger re-derived now still agrees"
  else
    clause FAIL B1 "re-audit open=$_o NEW-nonsuccess=$_n (of $_nall total) spawned=$_s1 settled=$_s2"
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
  clause PASS C1 "config dir $TCFG_M agrees across env, manifest and the account map ($TARGET)" "config dir"
fi

_hits=0; _tx_seen=""
for _c in "$TCFG_M"/projects/*/"$SID".jsonl; do [ -r "$_c" ] || continue; _hits=$((_hits+1)); _tx_seen="$_c"; done
if [ "$_hits" = 1 ]; then clause PASS C2 "transcript $_tx_seen" "transcript path"
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
  if [ "$_to" = "$TCFG_M" ]; then clause PASS C3 "lock $LOCK → $_to" "lock target"
  else clause FAIL C3 "lock $LOCK says to=$_to, manifest target_cfg=$TCFG_M"; fi
fi

TOMB=""
[ -r "$B/transplant.json" ] && TOMB="$(jq -r '.tombstone // empty' "$B/transplant.json" 2>/dev/null)"
if [ -z "$TOMB" ]; then
  for _c in "$SRC_CFG"/projects/*/"$SID".HANDOFF.json; do [ -r "$_c" ] && { TOMB="$_c"; break; }; done
fi
if [ -n "$TOMB" ] && [ -r "$TOMB" ]; then clause PASS C4 "source tombstoned at $TOMB" "source tombstone"
else clause FAIL C4 "no source tombstone for $SID under $SRC_CFG — the source may still be live"; fi

# A pool worktree is a FLEET slot, not a session's own tree: resuming into one would hand the
# recovered session a checkout another recovery is entitled to reclaim.
# ── AND AN UNEVALUABLE GIT IS A FAILURE, NOT A PASS (W3i D5) ─────────────────────────────────────
# `rev-parse --git-dir` returns ONE non-zero rc for two opposite worlds — "this genuinely is not a
# repo" and "git could not answer" (no binary on PATH, an unreadable .git, a corrupt object store) —
# and passing on that rc contradicts this file's own contract three lines from where it is stated.
# The MANIFEST settles it without asking git a second question: lr-handoff records `.branch` only
# when the cwd WAS a git checkout, emitting no --branch flag otherwise
# (tests/lr-handoff-launcher-quoting.bats case 5), so an ABSENT branch field is the bundle's own
# statement that this tree never was a repo. Two sources agreeing is what earns the pass; one
# source's ambiguous rc never did.
MAN_BR="$(mval '.branch // "ABSENT"')"
if [ -z "$WT" ] || [ "$WT" = ABSENT ]; then
  # An EMPTY path is not a missing directory, and `[ ! -d "" ]` renders the two identically —
  # "worktree  does not exist" is what 4 of the 69 live bundles printed, a sentence with a hole in
  # it where the subject belongs (empty-vs-no-surface, applied to the message rather than the test).
  clause FAIL C5 "the manifest records neither worktree nor cwd — there is no tree to check against pool/*"
elif [ ! -d "$WT" ]; then
  clause FAIL C5 "worktree $WT does not exist"
elif ! command -v git >/dev/null 2>&1; then
  clause FAIL C5 "git is not on PATH — whether $WT is a fleet pool slot cannot be evaluated"
elif ! git -C "$WT" rev-parse --git-dir >/dev/null 2>&1; then
  if [ "$MAN_BR" = ABSENT ] || [ -z "$MAN_BR" ]; then
    clause PASS C5 "$WT is not a git repo and the manifest recorded no branch — the two agree, there is no pool slot to be" "branch"
  else
    clause FAIL C5 "the manifest recorded branch $MAN_BR but git cannot read $WT as a repo — C5 is unevaluable"
  fi
else
  _br="$(git -C "$WT" branch --show-current 2>/dev/null || true)"
  case "$_br" in
    pool/*) clause FAIL C5 "branch $_br is a fleet pool slot" ;;
    "")     clause FAIL C5 "$WT is on a detached HEAD — no branch to check against pool/*" ;;
    *)      clause PASS C5 "branch $_br" "branch" ;;
  esac
fi

# ── D — THE ONE SIDE EFFECT THE INGEST STEP PERFORMED, MOVED TO THE SHELL ────────────────────────
# `/limit-recover ingest` step 1 clears the auto-continue sentinel: a pre-limit armed continuation
# would otherwise re-drive a step the recovered session has no context for.
#
# ── AND THE CONFIG DIR IT RUNS UNDER IS *NOT* THE TARGET'S (W3i D1) ──────────────────────────────
# The sentinel is keyed on (config-dir | cwd) — hooks/lib/continue-sentinel.sh:23-27 — and the
# config dir that keyed the PRE-LIMIT arm is the one the session was running under WHEN IT ARMED:
# the SOURCE account's, because that is the account the limit was hit on. The transplant then moves
# the session to the target, so the recovered session's own Stop hook reads a DIFFERENT key
# entirely. Running the clear under $TCFG therefore discharges nothing this clause exists to
# discharge, and the only sentinel it CAN reach at that key was armed by whoever else works in this
# cwd on the target account — which is exactly the steal measured on 2026-09-19, when a read-only
# sweep disarmed two live sessions' continuations, one armed 45 s earlier and driving a wave.
#
# So D is TWO clauses, and neither is satisfiable by the other:
#   D1 — the PRE-LIMIT sentinel, under the SOURCE config dir, as this session's OWN sid. Ours to
#        remove, and the `clear` verb's ownership guard lets it through precisely because it is ours.
#   D2 — the sentinel the RECOVERED session will actually read, under the TARGET config dir. NEVER
#        cleared from here: an armed one there belongs to another session and the launcher is not
#        entitled to it. hooks/session-continue.sh already clears-and-ignores a foreign sentinel
#        on the recovered session's own first Stop, so nothing is owed — but a live sibling armed in
#        the very cwd this session is about to resume into is a state this gate must not license.
#
# ── ONE RULE, AND THE KEY SUPPLIES THE CONSEQUENCE (W3i C4) ──────────────────────────────────────
# D1 and D2 used to take OPPOSITE verdicts on one state: a foreign sentinel at the source key read
# `PASS D1 — NOTHING WAS CLEARED`, the identical state at the target key read `FAIL D2`. Two clauses
# disagreeing about the same fact is a gate that cannot be reasoned about, so the rule is stated
# once and the difference is derived:
#
#   THE RULE      never clear a sentinel this session did not arm. Both clauses obey it; that is why
#                 D1 passes `--if-mine` and why D2 never clears a stranger at all.
#   THE VERDICT   is a property of the KEY, not of the rule: FAIL iff the key is one the RECOVERED
#                 session's own Stop hook will read. The target key always is. The source key is NOT
#                 — the transplant moves the session to $TCFG and its Stop resolves the sentinel
#                 under that config dir — so a stranger armed at the source key is neither our
#                 business nor our risk, and D1 says so instead of claiming a clear.
#   THE OVERLAP   when source_cfg == target_cfg the two keys are THE SAME FILE (measured: 1 of the
#                 69 live bundles under ~/.reso/limit-recover). There the source key IS the key the
#                 recovered session reads, so D1 applies the target verdict and the two agree by
#                 construction rather than by coincidence.
#
# An ABSENT source_cfg is not a pass: it means the dir that keyed the arm is unknowable, and a
# "cleared" printed over a directory we guessed is the false claim this whole script exists to
# prevent. FAIL, and say which field was missing.
SC="$HOME/.claude/hooks/session-continue.sh"
_scwd="${WT:-$PWD}"
# THE OWNERSHIP GUARD IS A FLAG THE CALLER PASSES (W3i B1). `clear` alone is the verb trunk has
# always shipped — unconditional — because CLAUDE_CODE_SESSION_ID is inherited by every descendant
# of a session and so cannot distinguish "the session is clearing" from "something the session ran
# is clearing". This caller is the one that genuinely acts FOR another session, so it is the one
# that says `--if-mine`.
sc_run() { # $1=config dir  $2…=verb and flags → the hook's own line on stdout, the hook's rc
  local _cfg="$1"; shift
  ( cd "$_scwd" 2>/dev/null || exit 97
    CLAUDE_CONFIG_DIR="$_cfg" CLAUDE_CODE_SESSION_ID="$SID" "$SC" "$@" 2>&1 )
}
# The owner recorded at the key, read off `status`'s parenthesised HEADER — never off the line.
# `status` prints `ARMED (<n> continuations, sid=<sid>): <step text>` and the step text is arbitrary
# operator prose, so a greedy `.*sid=` would take the LAST occurrence, i.e. one the step supplied.
# `unrecorded` is a real state, not a session (W3i C3): `set` stamps ${f}.sid only when the arming
# session HAS an id, so the operator's own park records none.
sc_owner_of() { printf '%s' "$1" | sed -n 's/^ARMED (\([^)]*\)).*/\1/p' | sed -n 's/.*sid=\(.*\)$/\1/p'; }
_d_same_key=0
[ -n "$SRC_CFG" ] && [ "$SRC_CFG" = "$TCFG_M" ] && _d_same_key=1
D1_STATE="unknown"
if [ ! -x "$SC" ]; then
  clause FAIL D1 "session-continue.sh is not executable at $SC — the armed continuation cannot be cleared"
  clause FAIL D2 "session-continue.sh is not executable at $SC — the target-side sentinel cannot be read"
else
  # ── D1 — the pre-limit sentinel, under the SOURCE config dir ──────────────────────────────────
  _verb=(clear --if-mine); [ "$LRV_CLEAR" = 1 ] || _verb=(status)
  if [ -z "$SRC_CFG" ] || [ "$SRC_CFG" = ABSENT ]; then
    clause FAIL D1 "the manifest records no source_cfg — the config dir the pre-limit continuation was armed under is unknowable"
  else
    _cl="$(sc_run "$SRC_CFG" "${_verb[@]}")"
    _clrc=$?
    if [ "$_clrc" -eq 97 ]; then
      # RC 97 IS THIS SCRIPT'S OWN `cd` FAILING, NOT THE HOOK'S EXIT (W3i C7). It fires on 10 of the
      # 69 live bundles — every one whose worktree has since been removed — and it used to print a
      # bare number with an empty tail, which names an exit code where a cause belongs.
      clause FAIL D1 "the worktree $_scwd no longer exists — the (config dir | cwd) key the pre-limit continuation was armed under cannot be entered, so what is armed there is unreadable"
    elif [ "$_clrc" -ne 0 ]; then
      clause FAIL D1 "session-continue.sh ${_verb[*]} under $SRC_CFG exited $_clrc: $_cl"
    else
      # THE LABEL IS READ OFF THE VALUE, NEVER ASSUMED (W3i D7). This line used to say
      # "auto-continue cleared: <value>" for every non-error outcome, so the receipt could read
      # "auto-continue cleared: refused — … nothing was cleared" — a label contradicting its own
      # value is how a false claim survives review.
      _d1_owner="$(sc_owner_of "$_cl")"
      case "$_cl" in
        "cleared → "*)
          D1_STATE="cleared"
          clause PASS D1 "pre-limit auto-continue CLEARED under $SRC_CFG: $_cl" "pre-limit auto-continue: $D1_STATE" ;;
        "nothing to clear"*|inactive*)
          D1_STATE="was not armed"
          clause PASS D1 "no pre-limit auto-continue was armed under $SRC_CFG: $_cl" "pre-limit auto-continue: $D1_STATE" ;;
        "ARMED "*)
          # Only reachable under --no-clear, where D1 asks `status` instead of clearing.
          if [ "$_d1_owner" = "$SID" ]; then
            D1_STATE="not touched (--no-clear)"
            clause PASS D1 "this session's own pre-limit sentinel is armed at $SRC_CFG, NOT touched (--no-clear): $_cl" "pre-limit auto-continue: $D1_STATE"
          elif [ "$_d_same_key" = 1 ]; then
            clause FAIL D1 "source_cfg == target_cfg, so this IS the key the recovered session reads, and it is not this session's: $_cl"
          else
            D1_STATE="left to its owner (nothing of ours is armed at the source key)"
            clause PASS D1 "NOTHING WAS CLEARED — the source key is NOT the key the recovered session reads; ${_d1_owner:-an armer that recorded no sid} has one armed at $SRC_CFG|$_scwd: $_cl" "pre-limit auto-continue: $D1_STATE"
          fi ;;
        refused*)
          if [ "$_d_same_key" = 1 ]; then
            clause FAIL D1 "source_cfg == target_cfg, so this IS the key the recovered session reads, and the sentinel armed there is not this session's: $_cl"
          else
            D1_STATE="left to its owner (nothing of ours is armed at the source key)"
            clause PASS D1 "NOTHING WAS CLEARED — the source key is NOT the key the recovered session reads, and the sentinel at $SRC_CFG|$_scwd is not this session's: $_cl" "pre-limit auto-continue: $D1_STATE"
          fi ;;
        *)
          clause FAIL D1 "session-continue.sh ${_verb[*]} under $SRC_CFG returned an outcome this gate cannot classify: $_cl" ;;
      esac
    fi
  fi

  # ── D2 — the key the RECOVERED session will actually read, under the TARGET config dir ────────
  if [ -z "$TCFG_M" ] || [ "$TCFG_M" = ABSENT ]; then
    clause FAIL D2 "the manifest records no target_cfg — the key the recovered session will read is unknowable"
  else
    _tg="$(sc_run "$TCFG_M" status)"
    _tgrc=$?
    _tgsid="$(sc_owner_of "$_tg")"
    if [ "$_tgrc" -eq 97 ]; then
      clause FAIL D2 "the worktree $_scwd no longer exists — the (config dir | cwd) key the recovered session will read cannot be entered, so what is armed there is unreadable"
    elif [ "$_tgrc" -ne 0 ]; then
      clause FAIL D2 "session-continue.sh status under $TCFG_M exited $_tgrc: $_tg"
    else
      case "$_tg" in
        inactive*)
          clause PASS D2 "nothing armed at the key the recovered session reads ($TCFG_M | $_scwd)" "the key the recovered session's Stop hook reads" ;;
        "ARMED "*)
          # THE PASS NEEDS POSITIVE PROOF OF OWNERSHIP, AND `unrecorded` IS NOT IT (W3i C3). An
          # armer that wrote no sid is refused for the same reason a DIFFERENT sid is — unknown
          # ownership is not consent (the D6 rule) — but it is not a session, and saying
          # "session ? has an armed continuation" invented one.
          if [ "$_tgsid" = "$SID" ] && [ "$LRV_CLEAR" = 1 ]; then
            _tgc="$(sc_run "$TCFG_M" clear --if-mine)"
            case "$_tgc" in
              "cleared → "*) clause PASS D2 "this session's OWN stale sentinel at the target key was cleared: $_tgc" "the key the recovered session's Stop hook reads" ;;
              *)             clause FAIL D2 "the target-key sentinel is this session's but would not clear: $_tgc" ;;
            esac
          elif [ "$_tgsid" = "$SID" ]; then
            clause PASS D2 "this session's own sentinel is armed at the target key, NOT touched (--no-clear): $_tg" "the key the recovered session's Stop hook reads"
          elif [ -z "$_tgsid" ] || [ "$_tgsid" = unrecorded ]; then
            clause FAIL D2 "an armer that recorded NO sid has a continuation at the key the recovered session reads — ownership is unknown, and it would be inherited and silently disarmed: $TCFG_M | $_scwd"
          else
            clause FAIL D2 "session $_tgsid has an armed continuation at $TCFG_M | $_scwd — the recovered session would inherit and silently disarm it"
          fi ;;
        *)
          clause FAIL D2 "session-continue.sh status under $TCFG_M returned an unclassifiable line: $_tg" ;;
      esac
    fi
  fi
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

printf 'verdict: rc 0 (%s clauses PASS)\n' "$LRV_PASSES"
# `%s` for the auto-continue half, never the word "cleared": D1 has four honest outcomes and only
# one of them is a clear (W3i D7). A prompt the recovered session READS must not assert a side
# effect that did not happen. The check list is $LRV_SUBJECTS — accumulated at the clause calls, so
# it names the clauses that actually PASSED and nothing else (W3i C6).
printf 'Resumed in place on %s — same pane, same session %s, after a %s-limit %s on %s. lr-ingest-verify rc 0 over %s: %s. The audit says gaps %s, waiting %s, %s open delegations — nothing is owed and nothing re-runs. Continue the interrupted work from where you left off. Full check list and receipt: cat %s/INGEST-VERIFIED.txt — re-derive with: bash ~/.claude/scripts/limit-recover/lr-ingest-verify.sh --no-clear %s — %s\n' \
  "$TARGET" "$SID8" "$_k" "$STATUS" "$SRC_ACCT" "$LRV_PASSES clauses" "$LRV_SUBJECTS" "$_g" "$_w" "$_open" "$B" "$B" "$RUNTOK"
exit 0
