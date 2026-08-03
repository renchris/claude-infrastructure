#!/usr/bin/env bash
# anti-deference-nudge.sh — Stop hook: catch the DEFERENCE REFLEX at the harness level.
#
# THE DEFECT (operator's #1 behavioral flag, 2026-07-17, flagged 4×): the model finishes
# DRIVABLE, pre-authorized work and then, instead of just DOING the obvious next step,
# presents it as a question/hold — "say the word", "want me to", "shall I", "should I
# proceed", "otherwise I'll hold", "your steer". Under the Session Close Protocol that work
# should AUTO-CONTINUE (G1-G4 hold); pausing to ask is the defect. A memory note kept
# slipping, so this is the STRUCTURAL fix: a Stop hook that reads the last assistant message,
# detects the tell, and blocks the stop with a corrective nudge — DRIVE it, don't defer.
#
# ── FIRE PREDICATE + THE GENUINE CARVE-OUT (P0-4 triple fix) ──
#   Fire = ( deference_tell  OR  (done_assertion AND live-ledger-contradiction)
#            OR category_not_idea )
#          AND NOT hard_genuine  AND NOT (ship_hold AND NOT drivable).
#   The third arm (2026-08-02) is LEDGER-INDEPENDENT and LAST in the chain: handing work over by
#   COUNT ("one item is yours") instead of by CONTENT is a phrasing defect regardless of what the
#   ledger says. It sits after the honest-done arm precisely so a message that is BOTH an honest
#   done-assertion AND a count-only handover still gets caught — the real-world shape that exposed it.
#   The hook must NEVER fire on a LEGITIMATE surface. Genuine, pre-authorized-to-STOP asks (⛔ /
#   G2-G3): (1) external-info only the operator has (credentials, which-account, no-access);
#   (2) an unsettled value-fork (which-do-you-prefer; a bare "your call" with NO ship verb);
#   (3) a C10 the model cannot self-execute (sudo, interactive login, destructive migration).
#   NOT genuine (2026-07-17 strengthening, G-P11-2): push·land·ship·deploy of CLEAN committed
#   work is DRIVABLE — the desk drives the land, it does not park-and-ask. So ship/land is
#   carved out ONLY when the live ledger shows the tree is DIRTY or nothing is unlanded (a real
#   hold); when clean ∧ own-commits-ahead, "say the word (/ship or push)" FIRES. A confident
#   tell-free false-done ("complete — nothing to do") FIRES only when the ledger contradicts it,
#   so an HONEST completion stays silent (a blanket done-matcher would nag every clean close).
#   Bias stays toward FALSE-NEGATIVE (miss a soft defer) over FALSE-POSITIVE (nag a real blocker):
#   a nagging hook trains the model to route around it. Corpus-validated in
#   tests/anti-deference-nudge.bats (40 assertions: every listed tell fires; clean answers,
#   genuine-STOP-ASK-with-tell, non-drivable ship-holds, honest completes, and the substring traps
#   "should i download"/"want to"/"otherwise the code…" stay silent).
#
# ── SAFETY (a runaway blocking hook is worse than the disease — RED-proofed) ──
#   L  ONE-SHOT LATCH-SET: the hash of every FIRED message is appended to a per-session set; a
#      message whose hash is already in the set NEVER re-fires (kills the block→identical-reply→
#      block infinite loop — the banned unlatched-block anti-pattern). Re-arm is a genuinely NEW
#      message (new hash) that still carries a tell.
#   C  HARD CAP (ANTIDEF_MAX, default 3): the set's size IS the session fire-count; at N fires the
#      hook goes silent forever this session — so even a model that PARAPHRASES its defer every
#      turn (new hash each time, latch can't catch it) is bounded and never wedges the session.
#   F  FAIL-SAFE: block is emitted ONLY via {decision:"block"} on stdout; EVERY path exits 0. Any
#      transcript-read / jq / parse failure → abstain → exit 0. No `set -e` (a Stop hook exiting 2
#      would FALSE-BLOCK; -e turning a stray grep-exit-2 into the script's exit code is exactly the
#      landmine the task bans). -u/pipefail are on for hygiene: a -u violation exits 1 = a
#      NON-blocking error (stop proceeds) = the safe direction; all vars are defaulted so it can't
#      misfire in normal operation.
#   B-3  Every invocation emits ONE {fired|abstained:<reason>} line to the IDL, so "didn't fire"
#      and "never evaluated" are distinguishable (boundary-handoff B-3 discipline). Alarm on
#      abstained==100% over a long window would mean the tells stopped matching reality.
#
# Env seams (tests): ANTIDEF_STATE_DIR · ANTIDEF_IDL · ANTIDEF_MAX · WRAP_LEDGER_BIN (ledger path)
set -uo pipefail

STATE_DIR="${ANTIDEF_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/anti-deference}"
IDL="${ANTIDEF_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
MAX="${ANTIDEF_MAX:-3}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

input="$(cat 2>/dev/null || printf '{}')"

# ── B-3: one IDL line per invocation. Never fails the hook. ──
# Writer body = the SSOT lib hooks/lib/idl-log.sh (consolidation audit 02); see that file for the
# "jq-encode EVERY field" invariant this used to duplicate in four places.
_adscd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_ilib="$_adscd/lib/idl-log.sh"
# A BRAND-NEW hooks/lib file has no ~/.claude/hooks/lib symlink until install.sh runs — and when
# this hook executes from ~/.claude/hooks/, the CFG and $HOME tiers below resolve to that SAME
# missing path. So resolve $0's own symlink into the checkout first: the live hook IS a symlink to
# the repo, so this finds the lib on the same fast-forward that delivers this hook. Without it,
# landing would leave all five IDL hooks inert until someone remembered to re-run install.sh.
[ -f "$_ilib" ] || { _itgt="$0"; [ -L "$_itgt" ] && _itgt="$(readlink "$_itgt")"
  _ilib="$(cd "$(dirname "$_itgt")" 2>/dev/null && pwd)/lib/idl-log.sh"; }
[ -f "$_ilib" ] || _ilib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/idl-log.sh"
[ -f "$_ilib" ] || _ilib="$HOME/.claude/hooks/lib/idl-log.sh"
# shellcheck source=lib/idl-log.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ilib" 2>/dev/null; then
  # Fail LOUD but SAFE — a hook that cannot log its own disposition must not proceed silently, and
  # must never block the turn on a misconfig.
  printf 'anti-deference-nudge: FATAL — cannot source %s (IDL writer inert).\n' "$_ilib" >&2
  exit 0
fi
idl_init "$IDL" "anti-deference-nudge"

# ── (P15 T-P15-5) open_packet_B — the genuine-3 → durable-packet exit. A fork/external-info
#    genuine stop must leave a DURABLE, push-notified class-B decision packet, NEVER a bare idle
#    (G-P15-4). Best-effort: resolves cc-decide (env → beside-hook → CFG → ~/.claude/bin → PATH);
#    cc-decide absent OR failing ⇒ silent skip so the hook stays exit-0 (safe degrade). Echoes the
#    packet id on success. Uses MSG/SID/CFG at CALL time (all set by the genuine branch below). ──
open_packet_B() {
  local decide="${ANTIDEF_DECIDE_BIN:-}" cand vh deadline what proj
  if [ -z "$decide" ]; then
    for cand in "$(dirname "$0")/../bin/cc-decide" "$CFG/bin/cc-decide" "$HOME/.claude/bin/cc-decide"; do
      [ -x "$cand" ] && { decide="$cand"; break; }
    done
    [ -z "$decide" ] && command -v cc-decide >/dev/null 2>&1 && decide="$(command -v cc-decide)"
  fi
  [ -n "$decide" ] && [ -x "$decide" ] || return 0
  vh="${ANTIDEF_VETO_HOURS:-12}"
  deadline="$(date -u -v"+${vh}H" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
            || date -u -d "+${vh} hours" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  [ -n "$deadline" ] || return 0
  what="$(printf '%s' "$MSG" | tr '\n' ' ' | cut -c1-240)"
  # The two producer-declared fields the class-B ACTUATOR needs (bin/cc-decide § TWO PRODUCER-
  # DECLARED FIELDS). Both are stated HERE because only this hook knows them:
  #   --project — the stopped session's own cwd basename. Guarded: `basename ""` is ".", and a
  #     packet claiming project "." is worse than one claiming none.
  #   --default-effect no-change — this default PARKS the fork and continues; it changes nothing.
  #     Without the declaration the sweep filed it as an open backlog item, which is cc-dispatch's
  #     fire predicate, so a peer session could be spawned whose whole assignment was to park a
  #     decision that was already parked. Three such items are in the live ledger.
  proj=""; [ -n "${CWD:-}" ] && proj="$(basename "$CWD" 2>/dev/null || true)"
  "$decide" open --class B --what "$what" \
    --default "park this decision to the backlog and continue other work" \
    --default-effect no-change --project "$proj" \
    --deadline "$deadline" --session-sid "${SID:-}" \
    --recommendation "route around it; surface ONLY this fork for the operator's early-veto (anti-deference genuine-3)" \
    --route-around "anti-deference genuine-3: durable class-B packet opened instead of a bare idle" \
    2>/dev/null || return 0
}

command -v jq >/dev/null 2>&1 || { SID="?"; abstain "no-jq"; }

SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[ -n "$TP" ] || abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac      # expand a leading ~ if present
[ -f "$TP" ] || abstain "transcript-missing"

# ── (P0-4a) Extract the LAST MAIN-agent text: skip sidechain (subagent) records, and walk back
#    past a tool_use-only / metadata tail to the last assistant record that carries text (the
#    G-P11-1 343c6e77 shape defeated the old tail-1 → 74% no-assistant-text blind rate). Streaming
#    (no slurp); per-record compact-JSON keeps multi-line text on one line for tail -1. ──
LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
                   | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
                   | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
[ -n "$MSG" ] || abstain "no-assistant-text"

# ── (A) Deference tells on DRIVABLE work (corpus-validated; boundaries guard the substring traps:
#    "should i (do)" won't match "should i download"; the "otherwise" tell requires a first-person
#    hold, so "otherwise the code…" stays silent). ──
TELLS='say the word|on your word|want me to|shall i|should i (proceed|do|go)([^a-z0-9]|$)|let me know if you|holding for your|otherwise (i.?ll|i will|i.?d) (hold|wait|leave|hang|pause|stand)|your steer|do you want me to|awaiting your|i can [a-z]+ (it|this)( (next|now))?[[:space:]]*[—–-]+[[:space:]]*otherwise[[:space:]]+i'
# ── (P0-4c) Confident DONE-assertions (NARROW: only the "nothing-to-do"-class). Fires ONLY when
#    the live ledger contradicts the claim, so an HONEST completion stays silent (G-P11-3 / a19 D-1). ──
DONE_TELLS='nothing (left|more|else)?[a-z ]{0,12}to do|everything [a-z ]{0,20}(is|was) done|everything (requested|else|you asked)[a-z ,]{0,20}(is|was)? ?done|complete[ ,—–-]+nothing|(we.?re|we are|all)[ ,]*done[ ,.—–-]+nothing|that.?s everything'

# ── (2026-08-02) CATEGORY-NOT-IDEA: a close that hands work over by COUNT instead of by CONTENT.
#    CLAUDE.md § Session Close already forbids this in prose, citing Minto Ch 7 p. 94 ("'There are
#    three problems' tells the kind, not the idea") — and the model violated it in two CONSECUTIVE
#    closes anyway ("one item is yours.", "one item still needs your call."), while demonstrably
#    KNOWING the content: it wrote four paragraphs of the idea the moment the operator asked "huh?
#    what is it?". So the rule is not under-specified, it is UNENFORCED — the same prose-has-no-
#    chokepoint generator this hook exists to answer. Bar for silence is LOW and deliberate: name
#    the thing after a ':' or a dash and it never fires.
#    NARROW by construction — a count-noun must be joined to a HANDOVER phrase (is/are yours ·
#    needs your call/attention/decision · is for you), so ordinary prose ("I fixed one thing.")
#    stays silent, and a ':'/'—' before the sentence end means the idea IS present → silent.
CATEGORY_TELLS='(^|[^a-z])(one|two|three|four|a few|some|several|[0-9]{1,3}) (item|thing|step|task|decision)s?[^.!?:—–-]{0,30}((is|are) yours|needs? your (call|attention|decision|input|sign.?off)|(is|are) for you|remains? yours)[^.!?:—–-]{0,20}([.!?]|$)'

has_tell=0; printf '%s' "$MSG" | grep -iqE "$TELLS"      && has_tell=1
has_done=0; printf '%s' "$MSG" | grep -iqE "$DONE_TELLS" && has_done=1
has_cat=0;  printf '%s' "$MSG" | grep -iqE "$CATEGORY_TELLS" && has_cat=1
{ [ "$has_tell" -eq 1 ] || [ "$has_done" -eq 1 ] || [ "$has_cat" -eq 1 ]; } || abstain "no-tell"

# ── DEFERRING TO A LEAD IS NOT THE DEFERENCE DEFECT (2026-08-02) ────────────────────────────────
# This hook's premise is one session ↔ one human: its reason text says "the operator cannot act on
# a count", and its prescribed discharge is to DRIVE the work or surface the genuine three TO THE
# OPERATOR. A background team assignee can do neither — its only channel is two-way with its lead.
# Worse, the hook fires on the assignee's MANDATED protocol: skills/agent-teams requires a teammate
# to report to its lead and "AWAIT explicit go-ahead", and `awaiting your` is a TELLS match verbatim.
# So the guard would block a teammate up to its cap for obeying its own brief, with a remedy it
# cannot execute. Placed after `no-tell` so only messages that would actually fire pay the `ps`.
_ad_lib="${AGENT_IDENTITY_LIB:-$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/agent-identity.sh}"
[ -f "$_ad_lib" ] || { _ad_t="$0"; [ -L "$_ad_t" ] && _ad_t="$(readlink "$_ad_t")"
  _ad_lib="$(cd "$(dirname "$_ad_t")" 2>/dev/null && pwd)/lib/agent-identity.sh"; }
[ -f "$_ad_lib" ] || _ad_lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/agent-identity.sh"
[ -f "$_ad_lib" ] || _ad_lib="$HOME/.claude/hooks/lib/agent-identity.sh"
if [ -f "$_ad_lib" ]; then
  # shellcheck source=lib/agent-identity.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  if . "$_ad_lib" 2>/dev/null; then
    _ad_aid="$(agent_is_assignee 2>/dev/null || true)"
    [ -n "$_ad_aid" ] && abstain "team-assignee:${_ad_aid}"
  fi
fi

# ── (P0-4b) Genuine carve-out, SPLIT so ship/land is CONDITIONAL, not blanket (G-P11-2 / I-3:
#    a blanket push/land carve-out trains the model to bolt a genuine-marker on to silence the hook).
#   HARD_CORE : credential/sudo/destructive-migration/external-info/value-fork — ALWAYS genuine.
#   SOFTCALL  : "your call"/"up to you"/"your approval" — genuine as a value-fork ONLY with NO ship
#               verb present; attached to a ship verb it is a (conditional) ship-hold, not genuine.
#   PUSHHOLD / ship-hold: push·land·ship·deploy of CLEAN committed work is DRIVABLE — NOT genuine —
#               when git is clean ∧ own commits are ahead of trunk (the 2026-07-17 strengthening). ──
HARD_CORE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|how would you like|which direction|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|(^|[^a-z])sudo([^a-z]|$)|interactive login|auth login|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'
SOFTCALL='your call|up to you|your approval'
PUSHHOLD='pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push'
SHIPVERB='(^|[^a-z])(push|ship|land|deploy|merge)|pull request|open (a )?pr'
# CLASS_C_GENUINE — the C10/authority-ceiling subset of HARD_CORE (credential/sudo/destructive/
# permission/login/external-access). These are class C — they WAIT and need a staged one-action
# artifact the hook cannot produce, so open_packet_B must NOT fire for them. The COMPLEMENT of this
# within HARD_CORE (which-account / which-prefer / how-would-you-like / can-you-provide) is the
# fork/external-info set → class B (T-P15-5). Credential CONTEXT (your/need <cred>), never a bare
# noun, so a design fork like "JWT vs cookies for the token store" stays class-B.
CLASS_C_GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|i (don.?t|do not) have (access|the |your |permission)|you.?ll need to (provide|give|share|tell|run|log ?in)|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|(^|[^a-z])sudo([^a-z]|$)|interactive login|auth login|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout'

has_soft=0;     printf '%s' "$MSG" | grep -iqE "$SOFTCALL" && has_soft=1
has_shipv=0;    printf '%s' "$MSG" | grep -iqE "$SHIPVERB" && has_shipv=1
has_pushhold=0; printf '%s' "$MSG" | grep -iqE "$PUSHHOLD" && has_pushhold=1

hard=0
printf '%s' "$MSG" | grep -iqE "$HARD_CORE" && hard=1
{ [ "$has_soft" -eq 1 ] && [ "$has_shipv" -eq 0 ]; } && hard=1     # "your call" fork with NO ship verb → genuine
if [ "$hard" -eq 1 ]; then
  # (P15 T-P15-5) Genuine-3 → durable packet. A fork/external-info genuine stop leaves a durable,
  # push-notified class-B packet — never a bare idle. Credential/sudo/destructive/permission
  # reasons are class C (they need a staged one-action artifact the hook cannot produce) → NO
  # packet here; those are opened by the code path that actually hits the C10 wall. The abstain
  # disposition + empty stdout are UNCHANGED (still a legitimate STOP-ASK — the hook never blocks).
  gb_extra=""
  if ! printf '%s' "$MSG" | grep -iqE "$CLASS_C_GENUINE"; then
    gb_pid="$(open_packet_B || true)"
    [ -n "$gb_pid" ] && gb_extra="$(jq -cn --arg p "$gb_pid" '{packet:$p,packet_class:"B"}')"
  fi
  log_idl abstained "genuine-blocker" "$gb_extra"
  exit 0
fi

ship_hold=0
{ [ "$has_pushhold" -eq 1 ] || { [ "$has_soft" -eq 1 ] && [ "$has_shipv" -eq 1 ]; }; } && ship_hold=1

# ── Live ledger — read ONLY when a ship-hold or a done-assertion needs a ground-truth check.
#    drivable = clean ∧ own commits ahead (push/land is the desk's job); contradiction = the FM1
#    remainder (dirty ∨ unlanded ∨ DoD-remainder). Any read failure → drivable/contradiction stay 0. ──
drivable=0; contradiction=0
if [ "$ship_hold" -eq 1 ] || [ "$has_done" -eq 1 ]; then
  WRAP="${WRAP_LEDGER_BIN:-}"
  if [ -z "$WRAP" ]; then
    for cand in "$(dirname "$0")/../scripts/wrap-ledger.sh" "$CFG/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
      [ -f "$cand" ] && { WRAP="$cand"; break; }
    done
  fi
  if [ -n "$WRAP" ] && [ -f "$WRAP" ]; then
    LED="$( cd "$CWD" 2>/dev/null && bash "$WRAP" --machine 2>/dev/null || true )"
    lf() { printf '%s' "$LED" | grep -E "^$1=" | head -1 | cut -d= -f2- || true; }
    ld_dirty="$(lf DIRTY)"; ld_unl="$(lf UNLANDED)"; ld_rem="$(lf REMAINDER)"
    case "$ld_dirty" in ''|*[!0-9]*) ld_dirty=0 ;; esac
    case "$ld_unl"   in ''|*[!0-9]*) ld_unl=0 ;; esac
    case "$ld_rem"   in ''|*[!0-9]*) ld_rem=0 ;; esac
    { [ "$ld_dirty" -eq 0 ] && [ "$ld_unl" -eq 1 ]; } && drivable=1
    { [ "$ld_dirty" -eq 1 ] || [ "$ld_unl" -eq 1 ] || [ "$ld_rem" -gt 0 ]; } && contradiction=1
  fi
fi

# ── Decide fire (deference vs false-done), else abstain with a distinct, logged reason. ──
FIRE_KIND=""
if [ "$has_tell" -eq 1 ]; then
  { [ "$ship_hold" -eq 1 ] && [ "$drivable" -eq 0 ]; } && abstain "genuine-ship-hold"
  FIRE_KIND="deference"
elif [ "$has_done" -eq 1 ] && [ "$contradiction" -eq 1 ]; then
  FIRE_KIND="false-done"
elif [ "$has_cat" -eq 1 ]; then
  # LAST in the chain by design: the two established kinds keep precedence, so this can only fire
  # on a message nothing else caught. Ledger-INDEPENDENT — handing work over by count is a
  # phrasing defect whether or not the ledger agrees. The HARD_CORE genuine carve-out above still
  # suppresses it (bias stays toward false-negative: never nag a real blocker).
  FIRE_KIND="category-not-idea"
elif [ "$has_done" -eq 1 ]; then
  # An HONEST done-assertion over a clean ledger, carrying no category handover → still silent
  # (unchanged behaviour; this arm exists so the has_cat check above is REACHABLE for a message
  # that is BOTH a done-assertion and a count-only handover — the real-world shape that exposed it).
  abstain "done-ledger-clean"
fi
[ -n "$FIRE_KIND" ] || abstain "no-fire"

# ── Latch-set + hard cap (RED-proofed L + C). ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
# GC stale per-session .fired latch-sets — SKEY embeds SID, so each is per-session and otherwise
# never reaped (mirrors memory-nudge.sh:26). A live session recreates its own on the next fire.
find "$STATE_DIR" -name '*.fired' -mtime +7 -delete 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$SKEY" ] || abstain "no-skey"
HASH="$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$HASH" ] || abstain "no-hash"
FIRED="$STATE_DIR/$SKEY.fired"     # newline-separated set of already-fired message hashes

# L: identical (or any previously-fired) content → never re-fire.
if [ -f "$FIRED" ] && grep -qxF "$HASH" "$FIRED" 2>/dev/null; then
  abstain "latched-already-fired"
fi
# C: the set's size is the session fire-count; at the cap, go silent (never wedge).
N="$(grep -c . "$FIRED" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge "$MAX" ] && abstain "capped:${N}>=${MAX}"

# ── FIRE: record the hash (re-arm baseline + cap increment), log, block with the corrective. ──
printf '%s\n' "$HASH" >> "$FIRED" 2>/dev/null || true
if [ "$FIRE_KIND" = "false-done" ]; then
  TRIGGER="$(printf '%s' "$MSG" | grep -ioE "$DONE_TELLS" 2>/dev/null | head -1 | tr -d '\n')"
elif [ "$FIRE_KIND" = "category-not-idea" ]; then
  TRIGGER="$(printf '%s' "$MSG" | grep -ioE "$CATEGORY_TELLS" 2>/dev/null | head -1 | tr -d '\n')"
else
  TRIGGER="$(printf '%s' "$MSG" | grep -ioE "$TELLS" 2>/dev/null | head -1 | tr -d '\n')"
fi
log_idl fired "$FIRE_KIND" \
  "$(jq -cn --arg tell "$TRIGGER" --argjson count "$((N+1))" --argjson max "$MAX" \
      '{tell:$tell,count:$count,max:$max}')"

if [ "$FIRE_KIND" = "category-not-idea" ]; then
  reason="Category-not-idea: you handed work over by COUNT, not by CONTENT (matched: \"${TRIGGER}\"). That is the blank assertion CLAUDE.md § Session Close bans, citing Minto Ch 7 p. 94 — \"'There are three problems' tells the kind, not the idea\". The operator cannot act on a count; they have to spend a round-trip asking \"which one?\". You almost certainly already know the answer — say it. Re-close with line 1 naming the THING: not \"one item is yours\" but \"the Fly deploy trigger still points at main, so every /ship deploys\". Name it after a ':' or a dash and this never fires. (category-not-idea nudge $((N+1))/${MAX})"
else
  detail=""
  { [ "$ship_hold" -eq 1 ] && [ "$drivable" -eq 1 ]; } && detail=" Ship/land of clean committed work is DRIVABLE — /ship it, don't park it."
  [ "$FIRE_KIND" = "false-done" ] && detail=" The LIVE ledger contradicts 'done' (uncommitted / unlanded / DoD-remainder) — it is NOT done."
  reason="Anti-deference: you presented drivable / complete-looking work as a question / hold / false-done (matched: \"${TRIGGER}\").${detail} If it's drivable + pre-authorized, DRIVE it now — only surface the genuine three (external-info the operator alone has / an unsettled value-fork / a C10 you can't self-execute like sudo·credential·destructive-migration; push·land·deploy of verified work is NOT one). Re-answer by DOING it, or by naming the ONE specific irreducible blocker. (anti-deference nudge $((N+1))/${MAX})"
fi

jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
