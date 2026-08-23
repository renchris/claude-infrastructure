#!/usr/bin/env bash
# completion-assert.sh — Stop hook: catch the CONFIDENT / TELL-FREE false-done (FM1) that the
# phrasing-only anti-deference matcher structurally cannot see (p06 §thesis; a19 D-1/D-5/§KQ1).
#
# THE DEFECT (G-P6-6 / G-P11-3): a model can emit "✅ Complete — nothing to do" (or a tell-free
# scope-narrow like "that was the main ask") with in-scope work still uncommitted / unlanded /
# on the frozen-DoD remainder, and EVERY existing Stop layer waves it through — anti-deference
# needs a deference phrase, session-continue needs the model to have armed it, /goal's evaluator
# is tool-blind. Only a human re-asking "are you sure?" caught it — the literal FM1. In the 24/7
# no-human loop there is no re-ask. This hook IS the mechanical re-ask: it corroborates a done /
# soft-close assertion against the LIVE ledger and blocks-once when the facts contradict it.
#
# ── FIRE PREDICATE (P11 FM1 signature) ──
#   (done_assertion ∨ deference_tell) ∧ ledger-contradiction ∧ ¬genuine
#     ledger-contradiction := dirty ∨ unlanded-content ∨ DoD-remainder>0
#                           ∨ RUNG=🚀 (landed-but-not-live) ∨ RUNG=⛔ (blocked on the operator)
#                           (all via wrap-ledger.sh — the two RUNG terms CONSUME its verdict and
#                            never re-derive it; see the blocks at the 🚀/⛔ terms below)
#     genuine := credential/sudo/destructive-migration/external-info/value-fork ONLY.
#       ship/land of clean committed work is NOT genuine (2026-07-17 strengthening) → a
#       "park-and-ask-to-ship" close FIRES; the desk drives the land, it does not hold for it.
#   Because the matcher is broad but GATED on ground-truth facts, a TRUE-complete close (clean ∧
#   landed-by-content ∧ no remainder) abstains no matter how confidently it says "done".
#   ATTRIBUTION runs before the dirty/unlanded terms convict: `session_dirty_mine` /
#   `session_unlanded_mine` ask whether the facts are THIS session's work, and the unlanded term
#   additionally recognises LIVE-PEER-OWNED (hooks/lib/peer-owned.sh) — a still-running peer's
#   commits in a shared checkout, which this session must NOT land. Neither weakens the ledger;
#   both ask a second, independent question about ownership. See those blocks below.
#
# ── ARM 2 — OPERATOR SURFACE (2026-08-01): the close the operator cannot ACT on ──
# The ledger arm above is blind to a whole class of bad close, because git says ✅ and it IS ✅:
# the work is landed, and the close STILL hands the operator something they then have to comb
# five paragraphs of prose to find. Three real closes:
#   D1  line 1 "✅ Complete & live on trunk"; paragraph 4 of 5 "Two things remain yours". The
#       operator had already decided to close at line 1. Because the step lives in PROSE, the
#       operator block that hooks/operator-readout.sh renders BY CONSTRUCTION from disk truth
#       never sees it — filing it is what makes it renderable, and it was never filed.
#   D2  a bare unfenced `CLAUDE_CONFIG_DIR=~/.claude-next claude-latest mcp add …` inside a
#       paragraph, and a bare `cd ~/Development/claude-infrastructure && claude` followed by
#       prose. Run it or not? Unanswerable. The operator: "I had to comb through the entire
#       return body to fish out which is the command to copy and paste and not just more
#       paragraph text because our command has no syntax highlighting to visually pull it
#       apart."
#       THE COMPLIANT FORM IS NOT A FENCE (corrected 2026-08-01, measured in the operator's own
#       TUI). A ```bash fence renders the command PLAIN WHITE — syntax highlighting colours
#       syntax, and a bare command name has none — while INLINE code renders blue
#       unconditionally. The fence was strictly less visible than the prose around it, the exact
#       inversion of the rule this hook first shipped with. A blockquote gives blue AND a left
#       rule, but its `│` is selected by a click-drag and lands in the paste, corrupting the
#       command. So the form is: a marker line of its own ("▶ Run this:"), then the command as
#       an inline-code span on the next line — blue on every wrapped row, a marker that breaks
#       left-align scanning, and NO row beginning with chrome, so a drag from first character to
#       last yields exactly the command. D2 already abstains on inline-backtick spans, so this
#       form passes unchanged; what D2 still catches is the real defect above — a command sitting
#       BARE in a paragraph with no code styling at all.
#   D3  operator: "Good to close?" → "Yes — with one thing still parked." → operator: "so you want
#       me to run the command or want me to close? that is contradictory" → the agent's own
#       admission: "Ignore the command — that was me hedging on a yes/no question." Line 1 asserted
#       a verdict and withdrew it in the same sentence, and the disambiguating round-trip IS the
#       cost. The operator "shouldn't be forced to reaffirm 'are we good to close' every time".
#   D4  "✅ Done — closeable" … then two named parked items … then "Say the word and I'll pick up
#       either; otherwise this is a clean stopping point." One of those items was the worktree's
#       OWN frozen DoD — 🔧 remainder, offered as if optional. Operator's ruling: "the answer will
#       always be yes — the job is not done until the job is done." CLAUDE.md's Follow-On Gate
#       already calls re-affirming an F1-F4 PASS a defect (deference-fishing).
# PREDICATE:  (D1 handoff-prose ∧ no operator step filed for THIS session) ∨ (D2 unfenced cmd)
#             ∨ (D3 line-1 settled-verdict ∧ line-1 retraction) ∨ (D4 offer-to-continue ∧ named
#             remaining work outside the offer sentence)
# ORDERING:   evaluated BEFORE the ledger arm's `abstain "ledger-clean"` — the target case is
#             precisely the ledger-CLEAN close. Either arm can set the fire, with distinct
#             reasons and a distinct IDL `arm`; when arm 2 does not fire, the ledger arm's
#             disposition and reason are byte-identical to before this arm existed.
# CONSERVATIVE BY CONSTRUCTION: a false fire on ordinary discussion of a command is worse than a
#   miss — an advisory that cries wolf stops being read (MEMORY.md alarm-polarity-and-attention-
#   budget). So D2 requires a column-0 (or bare-fenced) line whose FIRST token is an operator
#   verb or an ENV=VAL assignment, strips inline `backtick` spans first (mentioning `cc-do` in a
#   sentence is legitimate), and disqualifies anything with a sentence-shaped tail; D1 requires a
#   disk read that AFFIRMATIVELY says "nothing filed for this session" — ANY failure to read (no
#   binary, timeout, non-zero rc, unparseable) is "cannot tell" ⇒ DO NOT FIRE; D3 is scoped to the
#   FIRST LINE only (a settled line 1 with detail below is the wanted shape, so whole-message
#   matching would fire on nearly every legitimate close); and D4's remaining-work half is
#   evaluated with the OFFER lines REMOVED, so ordinary sign-off politeness cannot fire it. A Stop
#   hook must never block the turn on its own misconfiguration.
#
# ── SAFETY (mirrors anti-deference-nudge.sh:26-41,90-104) ──
#   L one-shot latch (a fired MSG hash never re-fires) · C hard cap PER CLASS: `assert` (every
#   conviction arm) = COMPLETION_MAX (default 3), `shape` (D6) = COMPLETION_SHAPE_MAX (default 2),
#   each silent forever after — see the latch block for why one shared counter starved the terminal
#   close · F fail-safe: block ONLY via {decision:"block"}; EVERY path exits 0;
#   any read/jq/ledger failure → abstain. No `set -e` (a Stop hook exiting 2 false-blocks).
#   B-3 one IDL {fired|abstained:<reason>} line per invocation.
#
# Env seams (tests): COMPLETION_STATE_DIR · COMPLETION_IDL · COMPLETION_MAX · COMPLETION_SHAPE_MAX ·
#   WRAP_LEDGER_BIN ·
#   CC_BACKLOG_BIN (arm 2 D1 — tests stub it; the real binary is resolved when unset) ·
#   SESSION_WRITES_LIB / ORIGIN_IDENTITY_LIB / CLOSE_SHAPE_LIB / CC_FIRED_DIR / CC_CLOSE_SHAPE
#   (arm D6 — origin Pyramid-close contract; CC_CLOSE_SHAPE=0 is its R8 kill switch) ·
#   PEER_OWNED_LIB / CC_REGISTRY_DIR (LIVE-PEER-OWNED attribution — see the block at that term)
set -uo pipefail

STATE_DIR="${COMPLETION_STATE_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/state/completion-assert}"
IDL="${COMPLETION_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
MAX="${COMPLETION_MAX:-3}"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SID="?"

input="$(cat 2>/dev/null || printf '{}')"

# B-3 writer = the SSOT lib hooks/lib/idl-log.sh (consolidation audit 02); see that file for the
# "jq-encode EVERY field" invariant this used to duplicate in four places.
_cascd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_ilib="$_cascd/lib/idl-log.sh"
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
  printf 'completion-assert: FATAL — cannot source %s (IDL writer inert).\n' "$_ilib" >&2
  exit 0
fi
idl_init "$IDL" "completion-assert"

command -v jq >/dev/null 2>&1 || abstain "no-jq"

SID="$(printf '%s' "$input" | jq -r '.session_id // "?"' 2>/dev/null || echo '?')"
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
CWD="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

[ -n "$TP" ] || abstain "no-transcript-path"
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || abstain "transcript-missing"
[ -n "$CWD" ] || abstain "no-cwd"

# ── the wrap-ledger memo's EVENT key (P0-4, scripts/wrap-ledger.sh § THE MEMO) ──
# Seven Stop-hook call sites each pay a full ~180 ms / 19-git ledger on every close. They are one
# event, so they should observe one snapshot: handing the ledger this session's transcript is what
# lets it serve one. Absent (or unreadable) ⇒ that script computes exactly as it always has. This
# hook is the one caller that passes `--session`, which is a DIFFERENT question (it counts YOURS /
# BLOCKED for that sid) — the memo keys on the session inputs too, so it is never cross-served the
# six other call sites' ledger.
export WRAP_TRANSCRIPT="$TP"

# ── Extract the LAST MAIN-agent text: skip sidechain (subagent) records, and walk back past a
#    tool_use-only / metadata tail to the last assistant record that actually carries text
#    (streaming; per-record compact-JSON keeps multi-line text on one line for tail -1). ──
LASTJSON="$(jq -c 'select(.type=="assistant" and (.isSidechain != true))
                   | ([.message.content[]? | select(.type=="text") | .text] | join("\n"))
                   | select(. != "")' "$TP" 2>/dev/null | tail -1 || true)"
MSG="$(printf '%s' "$LASTJSON" | jq -r '. // empty' 2>/dev/null || true)"
[ -n "$MSG" ] || abstain "no-assistant-text"

# ── A done-assertion or a soft/scope-narrow close (broad — the LEDGER is the discriminator). ──
CLOSE='(^|[^a-z])done([^a-z]|$)|complete([ds]|ly)?([^a-z]|$)|finished|nothing (left|more|else)?[a-z ]{0,12}to do|(^|[^a-z])landed([^a-z]|$)|shipped|pushed to (main|trunk|origin)|📦|✅|that (covers|wraps|completes|was the main ask)|main ask|remaining [a-z ]{0,20}items?|ready to implement|whenever you.?d? ?(like|want)|prioriti[sz]e|natural follow.?up|follow.?up|flagging (it|this)|for planning|larger effort|happy to (go|proceed|do|help)|either direction|let me know if|everything [a-z ]{0,20}is done|(^|[^a-z])remains?([^a-z]|$)|comes up'

# ARM 2 / D3 needs the FIRST non-empty line, and the close-tell gate needs it too — see below.
# List markers and rung glyphs are tolerated by the `^[^A-Za-z]*` prefix inside CA_SETTLED rather
# than stripped: the anchor is the only token that cares where the line starts.
CA_SETTLED='✅|safe to close|good to close|^[^A-Za-z]*yes([^a-z]|$)|complete|all done|nothing (left|more) to do'
CA_RETRACT='parked|unlanded|still (needs|to|open|parked)|remains?([^a-z]|$)|except|(^|[^a-z])but([^a-z]|$)|aside from|one thing|with one|yours|pending|caveat'
ca_first=""
while IFS= read -r ca_ln || [ -n "$ca_ln" ]; do
  ca_t="${ca_ln#"${ca_ln%%[![:space:]]*}"}"
  [ -n "$ca_t" ] || continue
  ca_first="$ca_t"; break
done <<< "$MSG"

# A SETTLED-VERDICT FIRST LINE is a close by definition, even when the body carries none of the
# CLOSE tokens: the real 2026-08-01 exchange answered "Good to close?" with "Yes — with one thing
# still parked.", which contains no CLOSE token at all and would abstain here as "no-close-tell" —
# i.e. the D3 defect was structurally unreachable behind this gate. The widening is deliberately
# TINY: everything CA_SETTLED adds beyond CLOSE is "safe to close" / "good to close" / a line-1
# leading "yes", each of which IS a close. (Consequence, stated rather than hidden: the ledger arm
# can now also see those three, which is correct — they were closes it was blind to.)
if ! printf '%s' "$MSG" | grep -iqE "$CLOSE"; then
  { [ -n "$ca_first" ] && printf '%s' "$ca_first" | grep -iqE "$CA_SETTLED"; } || abstain "no-close-tell"
fi

# ── Genuine three (ship/land explicitly EXCLUDED — it is drivable, not a hold). ──
GENUINE='your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|which account|i (do ?n.?t|do not|dont) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|(^|[^a-z])sudo([^a-z]|$)|interactive login|auth login|gcloud auth|destructive migration|drop table|delete[^.]{0,20}production|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|which direction'
printf '%s' "$MSG" | grep -iqE "$GENUINE" && abstain "genuine-blocker"

# ── Ledger contradiction from LIVE reads (the ground-truth discriminator). ──
WRAP="${WRAP_LEDGER_BIN:-}"
if [ -z "$WRAP" ]; then
  for cand in "$(dirname "$0")/../scripts/wrap-ledger.sh" "$CFG/scripts/wrap-ledger.sh" "$HOME/.claude/scripts/wrap-ledger.sh"; do
    [ -f "$cand" ] && { WRAP="$cand"; break; }
  done
fi
[ -n "$WRAP" ] && [ -f "$WRAP" ] || abstain "no-wrap-ledger"

# FEED THE SESSION ID. yours-rung resolves it `--session` > $WRAP_SESSION_ID > $CLAUDE_SESSION_ID >
# unresolvable (wrap-ledger.sh:34,120-123), and NEITHER env var is guaranteed in a Stop-hook
# environment. Without this flag the ONE place that computes the rung for a real close resolved no
# session ⇒ YOURS=0, YOURS_SRC=none ⇒ the rung silently stayed ✅ and the 👤 rung was inert — built,
# shipped, never fed, with every test green because they exercised wrap-ledger directly.
# `?` is BOTH jq's default at :64 AND yours-class's own unresolvable sentinel, so an unknown session
# passes NO flag rather than a literal "?" — passing it would assert we know the session when we do
# not. Both branches keep the `|| true`: a wrap-ledger failure must still never break the hook.
if [ -n "$SID" ] && [ "$SID" != "?" ]; then
  LED="$( cd "$CWD" 2>/dev/null && bash "$WRAP" --machine --session "$SID" 2>/dev/null || true )"
else
  LED="$( cd "$CWD" 2>/dev/null && bash "$WRAP" --machine 2>/dev/null || true )"
fi
[ -n "$LED" ] || abstain "no-ledger"
lfield() { printf '%s' "$LED" | grep -E "^$1=" | head -1 | cut -d= -f2- || true; }
RUNG="$(lfield RUNG)"
case "$RUNG" in ''|'?') abstain "ledger-uncomputable" ;; esac
DIRTY="$(lfield DIRTY)";     case "$DIRTY" in ''|*[!0-9]*) DIRTY=0 ;; esac
DIRTY_N="$(lfield DIRTY_N)"; case "$DIRTY_N" in ''|*[!0-9]*) DIRTY_N=0 ;; esac
UNLANDED="$(lfield UNLANDED)"; case "$UNLANDED" in ''|*[!0-9]*) UNLANDED=0 ;; esac
AHEAD="$(lfield AHEAD)";     case "$AHEAD" in ''|*[!0-9]*) AHEAD=0 ;; esac
REMAINDER="$(lfield REMAINDER)"; case "$REMAINDER" in ''|*[!0-9]*) REMAINDER=0 ;; esac

# ── ATTRIBUTION: convict only for work THIS SESSION actually wrote (2026-08-02) ──
# THE DEFECT, observed live: this hook fired twice at a session whose only unlanded commit
# was `175eeb7d feat(kitty): cmd+click …` touching config/kitty.conf — a file that session
# never opened. `~/Development/claude-infrastructure` is the SHARED checkout (it is the
# ~/.claude symlink source), so a sibling's commit sits on its local `main` and every other
# session is convicted for it. Worse, the instruction it hands back ("/ship it") is one the
# project CLAUDE.md explicitly FORBIDS — landing from the shared checkout risks landing onto
# a branch you did not create (incident 2026-07-11). So the hook demanded a rule violation.
#
# The ledger reads FACTS, not authorship — correctly; that is what makes it un-fakeable. The
# fix is not to weaken the ledger but to ask a second, independent question before convicting:
# is any of this MINE? hooks/lib/session-writes.sh answers it from the transcript's own edit
# records (the same oracle session-continue.sh already uses for its mechanical 🔧 arm — this
# hook was simply never wired to it, which is the gap this closes).
#
# THREE STATES, and the asymmetry is deliberate. rc 0/1 (a definite answer) may EXONERATE.
# rc 2 (cannot tell — no jq, no transcript, unreadable) must NOT: this is a false-DONE guard,
# so an unreadable transcript has to leave it exactly as strict as before. A miss here lets a
# real false-done through; that is the expensive direction (MEMORY.md lookup-miss-is-not-absence).
# Is THIS session a confirmed Agent-Teams assignee (a background subagent)? rc 0 = yes.
# The trichotomy is read exactly as session-continue's wake floor reads it — CONFIRMED (0) and
# UNKNOWN-config (2) both count, REFUTED (1) does not — because one discriminator with two
# different policies is the same defect as two discriminators (MEMORY.md
# sibling-auditors-must-share-the-state-model). Any failure to resolve ⇒ NOT an assignee ⇒ the
# caller stays strict, so this can only ever narrow a conviction on positive evidence.
_ca_assignee() {
  local lib
  # AGENT_IDENTITY_LIB, when set, is a HARD override — it is deliberately NOT the head of the
  # fallback chain. An override folded into a fallback list stops being an override (MEMORY.md
  # path-resolved-dependency-in-daemon-code): pointing it at a missing file would silently resolve
  # the real lib from $0's directory, so the "no lib ⇒ stay strict" path could never be exercised,
  # and an untestable failure path is an untested one. Caught by its own test, which passed for the
  # wrong reason until this became an override.
  if [ -n "${AGENT_IDENTITY_LIB:-}" ]; then
    lib="$AGENT_IDENTITY_LIB"
  else
    lib="$_cascd/lib/agent-identity.sh"
    [ -f "$lib" ] || { local t="$0"; [ -L "$t" ] && t="$(readlink "$t")"
      lib="$(cd "$(dirname "$t")" 2>/dev/null && pwd)/lib/agent-identity.sh"; }
    [ -f "$lib" ] || lib="$CFG/hooks/lib/agent-identity.sh"
    [ -f "$lib" ] || lib="$HOME/.claude/hooks/lib/agent-identity.sh"
  fi
  [ -f "$lib" ] || return 1
  # shellcheck source=lib/agent-identity.sh
  # shellcheck disable=SC1091
  . "$lib" 2>/dev/null || return 1
  # The 0|2 rule and the id-grammar gate now live in the lib as agent_is_assignee (2026-08-02) —
  # five hooks ask this question and an inline copy each is how the policy rots apart. Delegating
  # also picks up the SHAPE GATE, which is strictly safer here: an argv match that yields a garbage
  # id used to reach agent_team_member_confirms, return 2 = UNKNOWN, and be TRUSTED as an assignee,
  # which is the one direction this guard must never fail (ignorance never exonerates).
  agent_is_assignee >/dev/null 2>&1
}

_ca_mine() { # $1=kind (dirty|unlanded) → rc 0 mine · 1 not mine · 2 cannot tell
  local lib rc
  lib="${SESSION_WRITES_LIB:-$_cascd/lib/session-writes.sh}"
  [ -f "$lib" ] || { local t="$0"; [ -L "$t" ] && t="$(readlink "$t")"
    lib="$(cd "$(dirname "$t")" 2>/dev/null && pwd)/lib/session-writes.sh"; }
  [ -f "$lib" ] || lib="$CFG/hooks/lib/session-writes.sh"
  [ -f "$lib" ] || lib="$HOME/.claude/hooks/lib/session-writes.sh"
  [ -f "$lib" ] || return 2
  # shellcheck source=lib/session-writes.sh
  # shellcheck disable=SC1091
  . "$lib" 2>/dev/null || return 2
  # A session that recorded NO writes at all is NOT evidence of innocence — IN GENERAL. The
  # transcript may predate the commits, or the work may have gone through Bash (`sed -i`, a
  # heredoc), which the oracle cannot see by construction. Exonerating on that would gut the guard:
  # the pre-existing suite's fixtures are exactly this shape — unlanded commits + a close message
  # with no tool_use — and treating them as "not mine" silently disabled 9 of them.
  # So EXONERATE ONLY ON POSITIVE EVIDENCE: the session demonstrably wrote things, and none of
  # them is this. No writes recorded ⇒ cannot tell ⇒ stay as strict as before.
  #
  # ── THE ONE EXCEPTION, and why it is not a hole (2026-08-02, SUBAGENT_STOP_HOOK_LOOP.md R1) ──
  # That rule, applied unconditionally, permanently convicts the one session that is write-free BY
  # CONSTRUCTION: a read-only research subagent. Measured — a background/named subagent is a REAL
  # child session (`claude.exe --agent-id … --agent-name … --team-name …`) and so runs this whole
  # main-session Stop chain, in the LEAD's worktree, reading the LEAD's dirty + unlanded ledger.
  # It cannot commit (read-only brief) and must not land, so it can never satisfy the assert: every
  # stop is blocked and it re-enters. Three such agents delivered ZERO findings on 2026-08-02.
  #
  # The fix is NOT "detect a subagent and skip the hook" — that suppresses the guard for a session
  # that genuinely can leave uncommitted work (R3). Agent-ness is used for something narrower and
  # sound: it VALIDATES THE TRANSCRIPT, it does not excuse the session. Both objections above are
  # objections about the transcript's completeness, and neither survives here — an assignee's
  # transcript is created when the harness spawns it, so it CANNOT predate the lead's commits, and
  # it is the assignee's own file, not one shared with whoever made them. So for a confirmed
  # assignee, "no writes recorded" really is what it says.
  #
  # R3 STILL BINDS, and its controls are the proof: an assignee that DID write is exonerated by
  # nothing here — it takes the normal intersection path below and is still convicted. What changes
  # is only the verdict on a PROVABLY write-free one.
  # R2 IS UNTOUCHED: a main session is never an assignee, so it can never reach this branch and the
  # 9 fixtures above stay exactly as strict as they were.
  # Detection is the SSOT in hooks/lib/agent-identity.sh — the same ancestry + team-config oracle
  # session-continue's wake floor abstains on, so the two cannot disagree about who is an assignee.
  session_writes_paths "$TP" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 2 ] && return 2
  if [ "$rc" -eq 1 ]; then
    _ca_assignee || return 2
    return 1                       # provably write-free AND a confirmed assignee ⇒ not mine
  fi
  case "$1" in
    dirty)
      session_dirty_mine "$TP" "$CWD" >/dev/null 2>&1; return $? ;;
    unlanded)
      # DELEGATED to session_unlanded_mine (CLOSE_INTEGRITY W2b) — session-continue's ship floor
      # asks the SAME question, and two inline copies of this intersection is how they drift. The
      # canonicalisation story (physical-vs-logical paths; the fail-green trap only the "a commit
      # this session DID write must still convict" control caught) moved to the lib fn with the
      # algorithm, verbatim. An absent fn (stale live lib) is cannot-tell — stay strict.
      command -v session_unlanded_mine >/dev/null 2>&1 || return 2
      local trunk; trunk="$(lfield TRUNK)"
      case "$trunk" in ''|none) return 2 ;; esac
      session_unlanded_mine "$TP" "$CWD" "$trunk" >/dev/null 2>&1; return $? ;;
  esac
  return 2
}

# ── LIVE-PEER-OWNED: the 📦 state this guard could not express (2026-08-03) ──────────────────────
# `_ca_mine unlanded` asks "did I write these paths?", and its rc 2 — "cannot tell" — is exactly
# where a read-only session in the SHARED checkout lands: it wrote nothing, so there is no
# intersection to compute, so it stays convicted. Measured: session claude-infrastructure-323 (a
# read-only research turn, clean tree, ZERO files written) was blocked 3/3 for two commits, 7h and
# 10h old, made by claude-infrastructure-234 — still alive, ~17h into its own run. Neither answer
# the guard accepts was available: "/ship to land it" is the shared-checkout land .claude/CLAUDE.md
# forbids by name (incident 2026-07-11, dfacccd — five files rebase-dropped by a concurrent land
# while `rev-list origin/main..HEAD` read 0), and GENUINE above enumerates credential / sudo /
# destructive-migration / external-info / value-fork, so peer-ownership has no spelling there
# (MEMORY.md denylist-enumerates-spellings-not-the-class). The guard was not wrong about the git
# facts — it was missing a state, and the only compliant close was a rule violation.
#
# hooks/lib/peer-owned.sh answers the SECOND question, exactly as session-writes.sh answers the
# first: not "are these facts real" but "whose are they". It never re-derives UNLANDED and never
# touches a RUNG — the ledger still computes 📦 and operator-readout still renders it, because the
# commits really are unlanded. What is withheld is only the demand that THIS session act on them.
# The discriminator is LIVENESS, not age: a `/handoff` or `--recycle` successor inherits a DEAD
# predecessor's commits and must still land them, so it is still convicted; only a still-running
# peer's work is peer-owned. See that file for the full conjunction.
#
# GATED ON rc 2 ALONE, and that is load-bearing. rc 0 means this session provably wrote a path in
# the unlanded diff — positive self-evidence must never be overridden by evidence about someone
# else, so the peer question is not even asked there. rc 1 has already exonerated. So this can only
# convert a subset of "cannot tell" into a positive verdict; it cannot weaken a conviction the
# existing attribution had already made.
# Resolution chain shared by BOTH ownership terms below. Factored rather than copied: the second
# consumer arrived 2026-08-11 and a duplicated four-fallback chain is how the two would end up
# sourcing different files on a half-deployed live layer.
_ca_po_source() {   # rc 0 sourced · rc 1 no lib
  local lib
  lib="${PEER_OWNED_LIB:-$_cascd/lib/peer-owned.sh}"
  [ -f "$lib" ] || { local t="$0"; [ -L "$t" ] && t="$(readlink "$t")"
    lib="$(cd "$(dirname "$t")" 2>/dev/null && pwd)/lib/peer-owned.sh"; }
  [ -f "$lib" ] || lib="$CFG/hooks/lib/peer-owned.sh"
  [ -f "$lib" ] || lib="$HOME/.claude/hooks/lib/peer-owned.sh"
  [ -f "$lib" ] || return 1
  # shellcheck source=lib/peer-owned.sh
  # shellcheck disable=SC1091
  . "$lib" 2>/dev/null || return 1
}

_ca_peer_owned() {   # stdout: `<peer>#<pid>` on rc 0
  _ca_po_source || return 2
  peer_owned_unlanded "$CWD" "$(lfield TRUNK)" "$SID" "$TP"
}

# ── THE SAME SECOND QUESTION, FOR THE 🔧 TERM (2026-08-11, backlog ce91e9583df1 / 9be5e66e1c34) ──
# The dirty term had no attribution escape at all. `_ca_mine dirty` answers rc 2 for every session
# that recorded no file-edit tool_use and is not a confirmed assignee — deliberately, because a
# write-free transcript is not innocence — and rc 2 convicts. So a session that correctly wrote
# nothing was told its close was a false-done over a SIBLING's in-flight dirt, and the only
# compliant answer was to commit that dirt, which CLAUDE.md G4 forbids by name. Measured twice
# (4 files / 8 files; see hooks/lib/peer-owned.sh § THE DIRTY TERM'S ORDERING PROOF).
#
# GATED ON rc 2 ALONE, exactly as the peer term above is, and for the same reason: rc 0 is positive
# self-evidence that a dirty path is this session's own, and no argument about ordering may override
# it. rc 1 has already exonerated. So this can only convert a subset of "cannot tell" into a verdict.
# A stale live lib without the function is cannot-tell, never a silent pass.
_ca_dirt_predates() {   # stdout: `paths=N,newest=…,start=…` on rc 0
  _ca_po_source || return 2
  command -v dirt_predates_session >/dev/null 2>&1 || return 2
  dirt_predates_session "$CWD" "$SID" "$TP"
}

# ── THE SECOND AXIS, for the residue the ordering proof names (2026-08-12, backlog 76e444a40188) ──
# Ordering exonerates only dirt OLDER than this session, and the measured ORIGIN case is the other
# shape: claude-infrastructure-387, zero file-edit records, blocked 3/3 over a sibling's work made
# 38 minutes INTO its run. It could not commit (this checkout's .claude/CLAUDE.md forbids it), could
# not exonerate (write-free exoneration is gated on `_ca_assignee`, which an ORIGIN session is not)
# and could not stay silent — unfalsifiable, which is a defect in the guard, not strictness.
# The lib answers the assignee carve-out's TWO objections rather than dropping it: the transcript
# must bracket the mtime (objection A, completeness) and the mtime must fall outside every Bash
# execution window (objection B, the blind spot — bounded in TIME, so no verb is ever enumerated).
# See hooks/lib/peer-owned.sh § THE SAME QUESTION ON A SECOND AXIS for the full conjunction.
# GATED ON rc 2 ALONE and ordered AFTER the ordering term, exactly as that term is gated: rc 0 is
# positive self-evidence that a dirty path is this session's own and is never overridden, rc 1 has
# already exonerated, so this can only convert a subset of "cannot tell" into a verdict.
_ca_dirt_outside_exec() {   # stdout: `paths=N,windows=…,newest=…,span=…` on rc 0
  _ca_po_source || return 2
  command -v dirt_outside_session_execution >/dev/null 2>&1 || return 2
  dirt_outside_session_execution "$CWD" "$TP"
}

contra=0; facts=""; _ca_exon=""
if [ "$DIRTY" -eq 1 ]; then
  _ca_mine dirty; _ca_d=$?
  _ca_dp=""; _ca_dx=""
  if [ "$_ca_d" -eq 1 ]; then _ca_exon="${_ca_exon}dirty-not-mine "
  elif [ "$_ca_d" -eq 2 ] && _ca_dp="$(_ca_dirt_predates)" && [ -n "$_ca_dp" ]; then
    _ca_exon="${_ca_exon}dirty-predates-session:${_ca_dp} "
  elif [ "$_ca_d" -eq 2 ] && _ca_dx="$(_ca_dirt_outside_exec)" && [ -n "$_ca_dx" ]; then
    _ca_exon="${_ca_exon}dirty-outside-session-exec:${_ca_dx} "
  else contra=1; facts="${facts}dirty tree (${DIRTY_N} file(s)); "; fi
fi
if [ "$UNLANDED" -eq 1 ]; then
  _ca_mine unlanded; _ca_u=$?
  _ca_peer=""
  # LAND IN FLIGHT (land-architecture-100p §5 P4, defect 3) — CONSUMED from the ledger, never
  # re-derived (make-the-actuator-the-arbiter). Commits mid-land are unlanded by every git read, so
  # this term convicted a session whose land was already running and pushed it toward a SECOND
  # /ship on the same worktree. Exonerating the term is the whole change: nothing here asserts the
  # land succeeded, and the moment the marker goes (verdict reached, or the writer died and its
  # pid+lstart stop matching) the conviction returns unaltered.
  _ca_landing="$(lfield LANDING)"; case "$_ca_landing" in ''|*[!0-9]*) _ca_landing=0 ;; esac
  if [ "$_ca_landing" -eq 1 ]; then
    _ca_exon="${_ca_exon}unlanded-land-in-flight:$(lfield LANDING_PID) "
  elif [ "$_ca_u" -eq 1 ]; then
    _ca_exon="${_ca_exon}unlanded-not-mine "
  elif [ "$_ca_u" -eq 2 ] && _ca_peer="$(_ca_peer_owned)" && [ -n "$_ca_peer" ]; then
    _ca_exon="${_ca_exon}unlanded-live-peer-owned:${_ca_peer} "
  else
    contra=1; facts="${facts}${AHEAD} commit(s) committed-but-unlanded (/ship to land); "
  fi
fi
[ "$REMAINDER" -gt 0 ]  && { contra=1; facts="${facts}${REMAINDER} frozen-DoD item(s) remain; "; }
# W2 CUSTODY — a done-claim over UNRETURNED dispatched work is the wave-abandonment close itself
# (generator G1): the tree can be spotless while the session's real work is mid-flight in fired
# peers. CONSUME the ledger's count, never re-derive (make-the-actuator-the-arbiter); wrap-ledger
# computes it on the ✅-eligible path, which is exactly where a clean-tree done-claim lands.
CUSTODY="$(lfield CUSTODY_OPEN)"; case "$CUSTODY" in ''|*[!0-9]*) CUSTODY=0 ;; esac
[ "$CUSTODY" -gt 0 ] && { contra=1; facts="${facts}${CUSTODY} dispatched session(s) have NOT returned (custody open — collect+synthesize+land their work then \`cc-custody return <marker|slug>\`, or \`cc-custody abandon <token> --why …\`; awaiting them ARMED via cc-await-ping is a valid non-close state, but 'done' is not); "; }

# ── LANDED ≠ LIVE — the 🚀 rung this guard could not see (2026-08-07) ────────────────────────────
# Face 4 landed the rung in scripts/wrap-ledger.sh, but this hook was never taught it, and every
# term above reads a fact about a GIT REF. So a close saying "✅ Complete & live on trunk" passed
# cleanly with DIRTY=0, UNLANDED=0, REMAINDER=0 while the live layer — the store behaviour is
# actually taken from — was past its converge budget and still running the old bytes. That is the
# generator's own §2.1 partition missing a member: this hook enforces nothing about the machine, but
# it decides what a session may CALL done, so a conclusion could reach the ledger and still not
# reach the guard. Eight correct analyses each closed green through exactly that gap.
#
# CONSUME THE LEDGER'S VERDICT, DO NOT RE-DERIVE IT. Breach is a function of the converge budget
# (WRAP_LIVE_BUDGET_COMMITS / _MIN) and of MIG_FAILED, and wrap-ledger already owns that predicate.
# Re-implementing it here would give two auditors over one population with no shared state model —
# the shape that lets this class of bug survive (MEMORY.md make-the-actuator-the-arbiter,
# sibling-auditors-must-share-the-state-model). RUNG=🚀 IS the verdict; nothing else infers it.
# In particular LIVE_SRC=behind is NOT sufficient — inside the budget that is the normal, expected
# state for the first minutes after a land, and convicting on it would fire at nearly every close.
#
# Bounded, so it cannot become a standing gate: this hook's own per-session cap (MAX, default 3)
# already converts a converger that genuinely cannot advance into an event — file it, close on 👤 —
# rather than an unbounded refusal. That is §9's narrowed law applied to the guard itself.
if [ "$RUNG" = "🚀" ]; then
  _ca_miglost="$(lfield MIG_FAILED)"; case "$_ca_miglost" in ''|*[!0-9]*) _ca_miglost=0 ;; esac
  _ca_livelag="$(lfield LIVE_LAG)";   case "$_ca_livelag" in ''|*[!0-9]*) _ca_livelag="?" ;; esac
  # LIVE_ADDS names the THIRD cause (2026-08-09): the lag contains files that are ABSENT from the
  # live layer, not merely stale. Same consume-don't-re-derive law as the rung itself — the ledger
  # decided the breach, this only picks which true sentence to say. Non-numeric ⇒ 0 ⇒ the budget
  # wording, which is what the ledger fell back to as well, so the two auditors cannot disagree.
  _ca_adds="$(lfield LIVE_ADDS)";     case "$_ca_adds"    in ''|*[!0-9]*) _ca_adds=0 ;; esac
  contra=1
  if [ "$_ca_miglost" -gt 0 ]; then
    facts="${facts}LANDED BUT NOT LIVE — ${_ca_miglost} migration(s) could not reach the enforcing store, so the machine is not running this yet; "
  elif [ "$_ca_adds" -gt 0 ]; then
    facts="${facts}LANDED BUT NOT LIVE — ${_ca_adds} NEW file(s) in the landed diff are ABSENT from the live layer (~/.claude is per-file symlinks, so an added file has no link and every \`command -v\`/\`[ -f ]\` consumer guard silently skips it — the feature is a no-op, not a stale one), and no converge budget covers an add (converge: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh); "
  else
    facts="${facts}LANDED BUT NOT LIVE — the live layer is ${_ca_livelag} commit(s) behind and PAST its converge budget, so the machine still runs the old bytes (converge: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh); "
  fi
fi

# ── BLOCKED ON THE OPERATOR — the ⛔ rung this guard could not see (2026-08-07) ───────────────────
# A close rendered "✅ SAFE TO CLOSE — nothing of mine is open" — TRUE over every git fact — while
# the model was holding a blocking operator decision it had buried in paragraph 4 of its own prose.
# Every arm abstained, and each for a structural reason, not an accident: D1 enumerates handoff
# SPELLINGS and the sentence was "G-A is the one thing I need from you", which is not one of them
# (MEMORY.md denylist-enumerates-spellings); D3 is FIRST-LINE-scoped by design and the retraction
# had moved to ¶4; D4 needs an offer phrase and there was none; and the ledger arm was right — the
# tree really was clean and landed.
#
# CONSUME THE LEDGER'S VERDICT, DO NOT RE-DERIVE IT — the same law the 🚀 term above states, and
# for the same reason. The tempting fix here is another prose matcher ("I need from you", a
# question mark, a decision-shaped sentence), and that is EXACTLY the D1 failure mode repeated one
# denylist later. The open class-C decision packets are a STORE, wrap-ledger already owns the
# predicate over them, and RUNG=⛔ IS the verdict; nothing else infers it and this hook never reads
# the cc-decide store itself (MEMORY.md make-the-actuator-the-arbiter,
# sibling-auditors-must-share-the-state-model).
#
# This cannot become a standing gate on the CORRECT close: a close whose line 1 actually IS the ⛔
# rung carries no done-assertion, so it abstains at the close-tell gate above and never reaches
# here — and one that names an irreducible operator-only blocker abstains earlier still at GENUINE.
# What is left is precisely the target: a close asserting done while a decision it filed is open.
# Bounded by this hook's own per-session cap (MAX), like every other term.
if [ "$RUNG" = "⛔" ]; then
  _ca_blocked="$(lfield BLOCKED)"; case "$_ca_blocked" in ''|*[!0-9]*) _ca_blocked="?" ;; esac
  contra=1
  facts="${facts}BLOCKED ON YOU — ${_ca_blocked} decision(s) filed this session are open and only you can settle them; the close asserted done while holding them (cc-decide list --open); "
fi

# ── ARM 2 (operator surface) — see the contract block above. MUST precede the ledger-clean
#    abstain: the whole point is the close that is ledger-CLEAN yet still unactionable. ──
d1=0; d2=0; d3=0; d4=0

# D2 — a runnable command shown outside a ```bash-tagged fence. Pure bash, no forks.
#   A fence line opens/closes; a fence opened WITH any language tag is correct by construction
#   and its body is skipped. Everything else — unfenced text and BARE-fenced bodies — is
#   scanned for a command-shaped line.
CA_FENCE_RE='^[[:space:]]{0,3}```[[:space:]]*([A-Za-z0-9_.+-]*)'
CA_CMD_RE='^([A-Z_][A-Z0-9_]*=[^[:space:]]*[[:space:]]+[^[:space:]]|(cc-do|cc-backlog|cc-decide|cc-sessions|cc-context|cc-audit|claude|claude-latest|claude-next[0-9]*|claude-accounts|git|bash|sh|zsh|cd|launchctl|npm|pnpm|npx|make|open|osascript|it2|/ship|/wrap|/handoff|/accounts)([[:space:]]|$))'
CA_PROSE_TAIL_RE='[.?!:,;]$'
ca_infence=0; ca_lang=""
while IFS= read -r ca_ln || [ -n "$ca_ln" ]; do
  if [[ $ca_ln =~ $CA_FENCE_RE ]]; then
    if [ "$ca_infence" -eq 1 ]; then ca_infence=0; ca_lang=""
    else ca_infence=1; ca_lang="${BASH_REMATCH[1]}"; fi
    continue
  fi
  # A LANGUAGE-TAGGED fence is the compliant form — never fire inside one.
  if [ "$ca_infence" -eq 1 ] && [ -n "$ca_lang" ]; then continue; fi
  # Strip inline `code` spans BEFORE matching: "`cc-do` is the driver" is legitimate prose.
  ca_s="$ca_ln"; ca_o=""
  while [[ $ca_s == *'`'*'`'* ]]; do
    ca_o="${ca_o}${ca_s%%\`*}"; ca_s="${ca_s#*\`}"; ca_s="${ca_s#*\`}"
  done
  ca_o="${ca_o}${ca_s}"
  # Column 0 is required OUTSIDE a fence (prose is indented, commands are not); inside a BARE
  # fence, indentation is ordinary formatting, so trim it first.
  if [ "$ca_infence" -eq 1 ]; then ca_o="${ca_o#"${ca_o%%[![:space:]]*}"}"; fi
  [[ $ca_o =~ $CA_CMD_RE ]] || continue
  [[ $ca_o =~ $CA_PROSE_TAIL_RE ]] && continue   # sentence-shaped tail ⇒ prose, not a paste-line
  d2=1; break
done <<< "$MSG"

# QUOTED SPANS ARE MENTION, NOT USE — FP found 2026-08-01 by this hook firing on the very close
# that shipped it. D1 and D4 match PROSE: a close that QUOTES a defect is discussing it, not
# committing it. That close carried a table of the operator's own examples — "two things remain
# yours" and "Say the word and I'll pick up either" — and both matched, so the guard convicted the
# change that fixes the thing it names. That is the denylist-blocks-its-own-fix class (MEMORY.md
# denylist-enumerates-spellings: the same family of guard once denied the commit message describing
# its own rule). Not hypothetical here — every future review, doc or post-mortem of these four
# defects re-triggers it, and each costs exactly the round-trip this arm exists to remove.
#
# So D1/D4 match a view with backtick, ASCII-double-quoted and curly-quoted spans REMOVED. D2
# already did this for inline-backtick command mentions; this extends the same rule to the two
# prose arms. It cannot launder a REAL handoff: a genuine "two things remain yours" is written as
# a bare statement — wrapping it in quotes is precisely what marks it as a citation.
# D3 is deliberately NOT stripped: it scopes to line 1, where a quoted verdict is still the verdict.
# shellcheck disable=SC2016  # the backticks are LITERAL markdown being stripped, not a subshell —
# single quotes are exactly right here, and double-quoting would make shellcheck's suggestion true.
MSG_UNQ="$(printf '%s' "$MSG" | sed -E 's/`[^`]*`//g; s/"[^"]*"//g; s/“[^“”]*”//g' 2>/dev/null || true)"
[ -n "$MSG_UNQ" ] || MSG_UNQ="$MSG"     # a strip that ate everything ⇒ fall back, never a silent 0

# D1 — the close hands the operator work in a sentence, and nothing on disk records it.
#   The disk oracle is `cc-backlog list --blocked --json` filtered on THIS session: a peer-filed
#   `cc-backlog needs "<step>"` lands a blocked item carrying `.session`, and THAT is what
#   operator-readout.sh can render. Any failure to read ⇒ cannot tell ⇒ d1 stays 0 (fail-open).
CA_HANDOFF='remains? yours|are yours|is yours|on your (end|side)|you.?ll need to|you will need to|requires your|needs your|still needs (a|the|your|to be)|left (to|for) you|for you to (run|do)|keep an eye on|worth (watching|keeping)|i.?d recommend you|up to you|your call to|manual step'
#   NEGATED HANDOFFS ARE THE OPPOSITE OF A HANDOFF (FP #3 of this family, 2026-08-01). The close
#   "✅ … nothing for you to run" was BLOCKED: `for you to run` matched, and the matcher cannot see
#   the `nothing` two words to its left. The sentence asserts there is nothing to hand over — the
#   exact state the arm wants — so convicting it inverts the guard. Same shape as the quoted-span
#   FP and the placeholder FP before it: a phrase matcher reading a fragment, blind to the
#   operator that governs it.
#   Negated occurrences are DELETED before the match, the technique D4 already uses on its offer
#   lines. Lowercased first because BSD sed has no case-insensitive flag, and the test is a
#   boolean so the fold costs nothing.
CA_NEG='(nothing|none|no|not|never|zero)[[:space:]]+([a-z]{1,10}[[:space:]]+){0,2}('"$CA_HANDOFF"')'
CA_D1SRC="$(printf '%s' "$MSG_UNQ" | tr '[:upper:]' '[:lower:]' | sed -E "s/$CA_NEG//g" 2>/dev/null || true)"
[ -n "$CA_D1SRC" ] || CA_D1SRC="$(printf '%s' "$MSG_UNQ" | tr '[:upper:]' '[:lower:]')"
if printf '%s' "$CA_D1SRC" | grep -iqE "$CA_HANDOFF"; then
  CCB="${CC_BACKLOG_BIN:-}"
  if [ -z "$CCB" ]; then
    for cand in "$(dirname "$0")/../bin/cc-backlog" "$CFG/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog"; do
      [ -x "$cand" ] && { CCB="$cand"; break; }
    done
  fi
  if [ -n "$CCB" ] && [ -x "$CCB" ]; then
    if command -v timeout >/dev/null 2>&1; then
      BJ="$(timeout 5 "$CCB" list --blocked --json 2>/dev/null)"; brc=$?
    else
      BJ="$("$CCB" list --blocked --json 2>/dev/null)"; brc=$?
    fi
    # `[]` (rc 0, valid array, no row for this session) is the ONLY affirmative "not filed".
    if [ "$brc" -eq 0 ] && printf '%s' "$BJ" | jq -e 'type=="array"' >/dev/null 2>&1; then
      printf '%s' "$BJ" | jq -e --arg s "$SID" 'any(.[]?; .session == $s)' >/dev/null 2>&1 || d1=1
    fi
  fi
fi

# D3 — line 1 both asserts a verdict and withdraws it. "Yes — with one thing still parked" is two
#   rungs in one sentence; the operator then HAS to ask "so do you want me to run the command or
#   close?", and the round-trip is the entire cost. FIRST NON-EMPTY LINE ONLY: a settled line 1
#   followed by detail below is the WANTED shape, and matching the whole message would fire on
#   nearly every legitimate close — an alarm that always fires carries no bits.
#   The settled-verdict set deliberately excludes a bare rung glyph, so the rung-CONSISTENT
#   "📦 Done, on a branch only — /ship to land it" (where the remainder IS the rung) does not fire.
#   CA_SETTLED / CA_RETRACT / ca_first are defined at the close-tell gate above, which needs the
#   same first line — see the note there on why a settled line 1 counts as a close.
if [ -n "$ca_first" ] \
   && printf '%s' "$ca_first" | grep -iqE "$CA_SETTLED" \
   && printf '%s' "$ca_first" | grep -iqE "$CA_RETRACT"; then
  d3=1
fi

# D4 — the close NAMES remaining work it has already researched, then asks permission to continue
#   instead of continuing. CLAUDE.md's Follow-On Gate already settles this: asking the operator to
#   re-affirm an F1-F4 PASS is deference-fishing, and the operator's ruling is that "the answer
#   will always be yes — the job is not done until the job is done". The ledger arm structurally
#   cannot see it (the tree was clean and landed; the remaining work lived in ANOTHER worktree and
#   an older DoD), which is why it belongs here, before the ledger-clean abstain.
#   (b) is evaluated with the OFFER lines removed, so ordinary sign-off politeness with no named
#   remaining work ("let me know if you hit anything") cannot fire.
CA_OFFER='say the word|if you want (me|a|another)|want me to|shall i|let me know if you.?d? ?(like|want)|happy to (pick|take|go|proceed|do|continue)|i can pick (it|these|either) up|clean stopping point|otherwise (this|that) is a|for a next (thread|session)|if you.?d? ?like me to|ready when you are'
CA_WORKLEFT='^[[:space:]]*([-*+•]|[0-9]+[.)])[[:space:]]+|remaining|parked|stranded|still open|not done|left to do|next thread|older frozen dod|unlanded|outstanding'
# Both halves read the quote-stripped view (see QUOTED SPANS above): a close QUOTING an offer is
# citing the defect, not making one. Stripping before the (b) pass matters as much as before (a) —
# a cited bullet list of someone else's remaining work is not this session's remaining work.
if printf '%s' "$MSG_UNQ" | grep -iqE "$CA_OFFER"; then
  ca_rest="$(printf '%s' "$MSG_UNQ" | grep -ivE "$CA_OFFER" || true)"
  printf '%s' "$ca_rest" | grep -iqE "$CA_WORKLEFT" && d4=1
fi

# D5 — a command offered for copy-paste that STILL CONTAINS A PLACEHOLDER.
#   Found the only way it gets found: the operator pasted one and their shell answered
#   `(eval):1: no such file or directory: checkout`. The close had handed over
#   `git -C <checkout> pull --rebase origin main && <checkout>/install.sh` under a run marker —
#   correctly styled, correctly single, and guaranteed to fail. Every other arm passed it: D2 sees
#   code styling and abstains, and nothing else looks INSIDE the command. But "one thing to select
#   and paste" is the whole contract, and a template is not pasteable — it is homework.
#
#   Scope: only a command the close is telling the operator to RUN — an inline-code span alone on
#   its line (the mandated form), or a line under a `▶`/"Run this" marker. A placeholder inside a
#   mid-sentence mention is legitimate documentation and must NOT fire, which is what keeps this
#   from convicting every doc paragraph that names a command shape.
#
#   ANGLE-BRACKET SHAPE ONLY, plus the two conventional literals. `<word>` cannot be confused with
#   a shell redirect (`cmd < file` has spaces; `<<EOF` is doubled), and $VAR / ~ / $(cmd) are all
#   things a shell RESOLVES on paste — they are not placeholders and are deliberately excluded.
#
#   THE SHAPE MOVED TO hooks/lib/placeholder.sh (2026-08-22) and is SOURCED here, unchanged. It is
#   now also the RENDER-time rule for hooks/operator-readout.sh and bin/cc-do, which can refuse to
#   platter a stored command with a hole in it — the only half of this defect that is prevention
#   rather than apology. Two copies of the regex would be two answers to "is this pasteable", and
#   the drift would be silent in the direction that plates the bad command.
#   The literal below is the FALLBACK, not a second definition: this arm must survive a missing lib
#   (an assert that stops asserting is worse than one that duplicates six tokens), and
#   tests/completion-assert.bats pins the two against each other so they cannot diverge unnoticed.
CA_PLACEHOLDER='<[A-Za-z][A-Za-z0-9_.-]*>|PASTE_[A-Z_]*|YOUR_[A-Z_]+|<your-|xxxxx'
_ca_plib="${PLACEHOLDER_LIB:-$_cascd/lib/placeholder.sh}"
[ -f "$_ca_plib" ] || _ca_plib="$CFG/hooks/lib/placeholder.sh"
[ -f "$_ca_plib" ] || _ca_plib="$HOME/.claude/hooks/lib/placeholder.sh"
# shellcheck source=lib/placeholder.sh
# shellcheck disable=SC1090,SC1091
if [ -f "$_ca_plib" ] && . "$_ca_plib" 2>/dev/null && [ -n "${CC_PLACEHOLDER_RE:-}" ]; then
  CA_PLACEHOLDER="$CC_PLACEHOLDER_RE"
fi
d5=0
ca_prev=""
while IFS= read -r ca_l; do
  ca_t="${ca_l#"${ca_l%%[![:space:]]*}"}"          # left-trim
  ca_is_run=0
  # the mandated form: an inline-code span ALONE on its line
  case "$ca_t" in '`'*'`') ca_is_run=1 ;; esac
  # or a marked line: `▶ <cmd>` / a line following a "Run this"-style marker
  case "$ca_t" in '▶'*) ca_is_run=1 ;; esac
  printf '%s' "$ca_prev" | grep -qiE '(^|[^a-z])run (this|it)\b|▶' && [ -n "$ca_t" ] && ca_is_run=1
  if [ "$ca_is_run" -eq 1 ] && printf '%s' "$ca_t" | grep -qE "$CA_PLACEHOLDER"; then d5=1; break; fi
  ca_prev="$ca_t"
done <<< "$MSG"

# ── D6 — ORIGIN PYRAMID-CLOSE CONTRACT (CLOSE_INTEGRITY W1; operator /goal 2026-08-09) ──────────
# The operator's two standing close questions — Pyramid complication/solution/outcome + an explicit
# good-to-close verdict — existed only as prose discipline, and the IDL shows 58% of stops assert
# nothing at all (no-close-tell, 13.5h window), so the one close that mattered could end without
# them. This arm fires ONLY on the terminal states where every other arm has nothing left to
# demand: a close-shaped message (the gate above), ledger ✅/👤, no contradiction, POSITIVE write
# evidence, in an ORIGIN session. Everything else abstains, each for a stated reason:
#   · confirmed assignee   → a teammate pane has no operator reading its close
#   · fired peer           → its close is the notify-back ping; this contract is the operator's
#   · write-free session   → research/Q&A must never be forced into a work-close shape (the
#                            dispatched-wave lead with an empty write footprint is W2 custody's
#                            business — a ledger fact, not a shape demand)
#   · contra=1 / worse rung → the ledger arm already blocks with the drivable action; the shape
#                            demand belongs at the TRUE close, not stacked before it
# Matcher + template + reason live in hooks/lib/close-shape.sh (ONE code path; /wrap pulls the
# same — final-response-shaping M4), and the reason deliberately does not restate D1/D3/D4.
# Origin verdict: hooks/lib/origin-identity.sh oi_origin_class — contract polarity (unproven peer
# ⇒ origin), pane-id first with the by-cwd+marker fallback that survives the measured
# resume-loses-$ITERM_SESSION_ID case. Bounds: shares the latch-set with every other arm, but NOT
# the cap — this arm is the `shape` CLASS and draws on COMPLETION_SHAPE_MAX, because a shared
# counter let mid-wave convictions spend the budget before the terminal close it exists for ever
# arrived (item 3b464e94b3ff; full derivation at the latch block). CC_CLOSE_SHAPE=0 disables the
# arm outright (R8).
d6=0; _d6_missing=""
if [ "${CC_CLOSE_SHAPE:-1}" != 0 ] && [ "$contra" -eq 0 ] \
   && { [ "$RUNG" = "✅" ] || [ "$RUNG" = "👤" ]; } && ! _ca_assignee; then
  _d6_ok=1
  # POSITIVE write evidence only (rc 0). rc 1 (none recorded) and rc 2 (cannot tell) both skip:
  # unlike the conviction arms, a shape DEMAND must not rest on ignorance.
  _d6_swl="${SESSION_WRITES_LIB:-$_cascd/lib/session-writes.sh}"
  [ -f "$_d6_swl" ] || { _d6_t="$0"; [ -L "$_d6_t" ] && _d6_t="$(readlink "$_d6_t")"
    _d6_swl="$(cd "$(dirname "$_d6_t")" 2>/dev/null && pwd)/lib/session-writes.sh"; }
  [ -f "$_d6_swl" ] || _d6_swl="$CFG/hooks/lib/session-writes.sh"
  [ -f "$_d6_swl" ] || _d6_swl="$HOME/.claude/hooks/lib/session-writes.sh"
  # shellcheck source=lib/session-writes.sh
  # shellcheck disable=SC1090,SC1091
  { [ -f "$_d6_swl" ] && . "$_d6_swl" 2>/dev/null && session_writes_paths "$TP" >/dev/null 2>&1; } || _d6_ok=0
  if [ "$_d6_ok" -eq 1 ]; then
    _d6_oil="${ORIGIN_IDENTITY_LIB:-$_cascd/lib/origin-identity.sh}"
    [ -f "$_d6_oil" ] || { _d6_t="$0"; [ -L "$_d6_t" ] && _d6_t="$(readlink "$_d6_t")"
      _d6_oil="$(cd "$(dirname "$_d6_t")" 2>/dev/null && pwd)/lib/origin-identity.sh"; }
    [ -f "$_d6_oil" ] || _d6_oil="$CFG/hooks/lib/origin-identity.sh"
    [ -f "$_d6_oil" ] || _d6_oil="$HOME/.claude/hooks/lib/origin-identity.sh"
    # shellcheck source=lib/origin-identity.sh
    # shellcheck disable=SC1090,SC1091
    if [ -f "$_d6_oil" ] && . "$_d6_oil" 2>/dev/null; then
      _d6_pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _d6_pane="${_d6_pane##*:}"
      [ "$(oi_origin_class "$_d6_pane" "$CWD" "$TP")" = origin ] || _d6_ok=0
    else
      _d6_ok=0
    fi
  fi
  if [ "$_d6_ok" -eq 1 ]; then
    _d6_shl="${CLOSE_SHAPE_LIB:-$_cascd/lib/close-shape.sh}"
    [ -f "$_d6_shl" ] || { _d6_t="$0"; [ -L "$_d6_t" ] && _d6_t="$(readlink "$_d6_t")"
      _d6_shl="$(cd "$(dirname "$_d6_t")" 2>/dev/null && pwd)/lib/close-shape.sh"; }
    [ -f "$_d6_shl" ] || _d6_shl="$CFG/hooks/lib/close-shape.sh"
    [ -f "$_d6_shl" ] || _d6_shl="$HOME/.claude/hooks/lib/close-shape.sh"
    # shellcheck source=lib/close-shape.sh
    # shellcheck disable=SC1090,SC1091
    if [ -f "$_d6_shl" ] && . "$_d6_shl" 2>/dev/null; then
      if ! close_shape_ok "$MSG"; then d6=1; _d6_missing="$(close_shape_missing "$MSG")"; fi
    fi
  fi
fi

# An exoneration is a REAL decision, not a non-event: it is the difference between "the ledger
# was clean" and "the ledger was dirty but none of it was mine". Distinguish them in the IDL or
# the next person debugging a missed conviction cannot tell which happened.
[ "$contra" -eq 1 ] || [ "$d1" -eq 1 ] || [ "$d2" -eq 1 ] || [ "$d3" -eq 1 ] || [ "$d4" -eq 1 ] \
  || [ "$d5" -eq 1 ] || [ "$d6" -eq 1 ] || abstain "ledger-clean${_ca_exon:+:exonerated:${_ca_exon% }}"

# ── Latch-set + hard cap, PER CLASS (RED-proofed L + C). ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
# GC stale per-session .fired latch-sets — SKEY embeds SID, so each is per-session and otherwise
# never reaped (mirrors memory-nudge.sh:26). A live session recreates its own on the next fire.
find "$STATE_DIR" -name '*.fired' -mtime +7 -delete 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$SKEY" ] || abstain "no-skey"
HASH="$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$HASH" ] || abstain "no-hash"
FIRED="$STATE_DIR/$SKEY.fired"
# THE STARVATION this splits (item 3b464e94b3ff, 2026-08-17). ONE counter served every arm, so a
# wave lead's MID-WAVE done-claims — each correctly convicted by the ledger arm (custody open,
# unlanded commits) — spent the entire budget, and the TERMINAL close, the one the D6 origin
# contract exists for, arrived at `capped:3>=3` and was never asserted against at all. The two are
# different demands with different subjects: a conviction says the LIVE LEDGER contradicts your
# done-claim; the shape demand says the operator's two standing questions are UNANSWERED. And the
# order is structural, not incidental — D6 requires contra=0, so the shape demand only becomes
# reachable AFTER the conviction arms stop firing. A shared budget therefore guarantees the wrong
# order of spending: the cheap mid-wave assertions always get it first.
#   So the budget is per CLASS. `assert` (every conviction arm) keeps COMPLETION_MAX verbatim —
# same reason string, same numbers, so nothing about a conviction session changes. `shape` (D6)
# draws on its own COMPLETION_SHAPE_MAX (default 2: one demand, plus one re-close that still
# misses it). Both remain HARD caps and each is latched by message hash, so the worst case is
# their sum, bounded and small, under the harness's own consecutive-block cap.
#   Latch lines are `<hash> <class>`; the dedup key is field 1 alone, so an identical message
# never re-fires whatever class it fired as. A LEGACY bare-hash line counts as `assert`, which is
# what every fire written before this change was.
CLASS=assert; CLASS_MAX="$MAX"
if [ "$d6" -eq 1 ]; then CLASS=shape; CLASS_MAX="${COMPLETION_SHAPE_MAX:-2}"; fi
case "$CLASS_MAX" in ''|*[!0-9]*) CLASS_MAX=2 ;; esac
if [ -f "$FIRED" ] && awk -v h="$HASH" '$1 == h { hit = 1 } END { exit(hit ? 0 : 1) }' "$FIRED" 2>/dev/null
then abstain "latched-already-fired"; fi
N=0
[ -f "$FIRED" ] && N="$(awk -v c="$CLASS" '{ k = ($2 == "" ? "assert" : $2); if (k == c) n++ } END { print n+0 }' "$FIRED" 2>/dev/null || printf 0)"
case "$N" in ''|*[!0-9]*) N=0 ;; esac
if [ "$N" -ge "$CLASS_MAX" ]; then
  # The assert-class reason is byte-identical to the pre-split one (its consumers, and the RED
  # proof of the cap itself, key on that exact string); a shape cap names its own class.
  case "$CLASS" in
    assert) abstain "capped:${N}>=${CLASS_MAX}" ;;
    *)      abstain "capped:${CLASS}:${N}>=${CLASS_MAX}" ;;
  esac
fi

# ── FIRE: record hash + class, log, block with the contradicting FACTS. ──
printf '%s %s\n' "$HASH" "$CLASS" >> "$FIRED" 2>/dev/null || true
facts="${facts%; }"
# WHICH arm fired, legible after the fact: ledger | hedge | handoff | offer | fence, `+`-joined in
# that fixed order (so a combination is one canonical string, not five orderings of the same set).
arm=""
[ "$contra" -eq 1 ] && arm="ledger"
[ "$d3" -eq 1 ] && arm="${arm:+$arm+}hedge"
[ "$d1" -eq 1 ] && arm="${arm:+$arm+}handoff"
[ "$d4" -eq 1 ] && arm="${arm:+$arm+}offer"
[ "$d2" -eq 1 ] && arm="${arm:+$arm+}fence"
[ "$d5" -eq 1 ] && arm="${arm:+$arm+}placeholder"
[ "$d6" -eq 1 ] && arm="${arm:+$arm+}shape"
log_idl fired "false-done" \
  "$(jq -cn --arg facts "$facts" --arg rung "$RUNG" --arg arm "$arm" --arg class "$CLASS" \
            --argjson count "$((N+1))" --argjson max "$CLASS_MAX" \
      '{facts:$facts,rung:$rung,arm:$arm,class:$class,count:$count,max:$max}')"

# Reason = one sentence-group per firing arm, in arm order. The ledger group is byte-unchanged.
reason=""
[ "$contra" -eq 1 ] && reason="Completion-assert: your close reads as done/complete, but the LIVE ledger contradicts it — ${facts}. Ship/land of verified net-positive work is DRIVABLE (not a genuine blocker), and so is converging the live layer. Re-answer by DRIVING the remainder to done (📦 ⇒ /ship it; 🚀 landed-but-not-live ⇒ run the converger named above, then re-read; finish the open items; commit with explicit paths) — or name the ONE irreducible blocker (credential / sudo / destructive-migration / external-info only the operator has)."
[ "$d3" -eq 1 ] && reason="${reason:+$reason }Your line 1 both asserts and withdraws a verdict, so the operator has to ask a follow-up to learn which it is. Pick the ONE rung that actually governs — if something is parked or is the operator's, that IS the rung (📦 / 👤); if it is immaterial, leave it out of line 1 entirely. Line 1 answers 'is it safe to close?' with no qualifier."
[ "$d1" -eq 1 ] && reason="${reason:+$reason }Your close hands the operator work in prose, so the operator-readout block cannot render it and it stays buried in a paragraph. File each operator-only step — \`cc-backlog needs \"<step>\" [--run \"<exact command>\"]\` — then re-close: line 1 states the rung (👤 when steps are yours), and the steps come from the rendered block, not your prose."
[ "$d4" -eq 1 ] && reason="${reason:+$reason }Your close names remaining work and then offers it instead of driving it — the operator's standing ruling is that the answer is always yes, so the question costs a round-trip and yields nothing. Every open item resolves to exactly one of three dispositions, never a fourth: DRIVEN (you do it now), FILED (\`cc-backlog needs\` for an operator-only step, \`cc-backlog add\` for agent work — so it renders as one counted line), or BLOCKED on a genuine operator-only gate (credential / sudo / destructive migration / a real value fork), which then IS your line-1 rung. 'Say the word' is not a disposition. Drive it, or file it — then re-close."
[ "$d5" -eq 1 ] && reason="${reason:+$reason }You handed over a command that still contains a placeholder, so it cannot be pasted — it has to be filled in first, which is the opposite of the one-thing-to-select-and-paste contract (an operator pasted exactly such a line and got \`no such file or directory\`). Substitute every <angle-bracketed> token with the real value NOW, from a live read, and hand over the literal command. If you cannot resolve a value, that is not a command to hand over at all: DELETE the command from your close and do ONE of two things instead — if the value is the operator's to give, ask for it as your line-1 rung in one sentence naming what the value IS (\"the email address the alarms should go to\", never \"<your-address>\"), or file the step with \`cc-backlog needs \"<step, naming the value>\" --run \"<the command>\"\`, which renders as a ✎ SUPPLY row the operator cannot mistake for something to paste. Re-close with the placeholder line GONE, not restyled."
[ "$d6" -eq 1 ] && reason="${reason:+$reason }$(close_shape_reason "$RUNG" "$_d6_missing")"
[ "$d2" -eq 1 ] && reason="${reason:+$reason }Your close shows a command as bare prose, with no code styling, so the operator cannot tell it from the paragraph around it. Put a marker line of its own first (\"▶ Run this:\"), then the ONE command as an inline-code span on the next line — that renders blue on every wrapped row and starts no row with chrome, so a drag-copy yields exactly the command. Do NOT use a \`\`\`bash fence (renders plain white — a bare command has no syntax to colour) or a blockquote (its rule character lands in the paste). A close shows a command ONLY if you are asking the operator to run it — one you would then tell them to ignore must not appear at all."
[ "$contra" -eq 1 ] || reason="Completion-assert: $reason"
reason="$reason (completion-assert ${CLASS} $((N+1))/${CLASS_MAX})"

jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
