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
#     ledger-contradiction := dirty ∨ unlanded-content ∨ DoD-remainder>0   (via wrap-ledger.sh)
#     genuine := credential/sudo/destructive-migration/external-info/value-fork ONLY.
#       ship/land of clean committed work is NOT genuine (2026-07-17 strengthening) → a
#       "park-and-ask-to-ship" close FIRES; the desk drives the land, it does not hold for it.
#   Because the matcher is broad but GATED on ground-truth facts, a TRUE-complete close (clean ∧
#   landed-by-content ∧ no remainder) abstains no matter how confidently it says "done".
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
#       apart." The ```bash tag is the ONLY thing that makes the TUI highlight it.
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
#   L one-shot latch (a fired MSG hash never re-fires) · C hard cap COMPLETION_MAX (default 3;
#   silent forever after) · F fail-safe: block ONLY via {decision:"block"}; EVERY path exits 0;
#   any read/jq/ledger failure → abstain. No `set -e` (a Stop hook exiting 2 false-blocks).
#   B-3 one IDL {fired|abstained:<reason>} line per invocation.
#
# Env seams (tests): COMPLETION_STATE_DIR · COMPLETION_IDL · COMPLETION_MAX · WRAP_LEDGER_BIN ·
#   CC_BACKLOG_BIN (arm 2 D1 — tests stub it; the real binary is resolved when unset)
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

contra=0; facts=""
[ "$DIRTY" -eq 1 ]      && { contra=1; facts="${facts}dirty tree (${DIRTY_N} file(s)); "; }
[ "$UNLANDED" -eq 1 ]   && { contra=1; facts="${facts}${AHEAD} commit(s) committed-but-unlanded (/ship to land); "; }
[ "$REMAINDER" -gt 0 ]  && { contra=1; facts="${facts}${REMAINDER} frozen-DoD item(s) remain; "; }

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

# D1 — the close hands the operator work in a sentence, and nothing on disk records it.
#   The disk oracle is `cc-backlog list --blocked --json` filtered on THIS session: a peer-filed
#   `cc-backlog needs "<step>"` lands a blocked item carrying `.session`, and THAT is what
#   operator-readout.sh can render. Any failure to read ⇒ cannot tell ⇒ d1 stays 0 (fail-open).
CA_HANDOFF='remains? yours|are yours|is yours|on your (end|side)|you.?ll need to|you will need to|requires your|needs your|still needs (a|the|your|to be)|left (to|for) you|for you to (run|do)|keep an eye on|worth (watching|keeping)|i.?d recommend you|up to you|your call to|manual step'
if printf '%s' "$MSG" | grep -iqE "$CA_HANDOFF"; then
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
if printf '%s' "$MSG" | grep -iqE "$CA_OFFER"; then
  ca_rest="$(printf '%s' "$MSG" | grep -ivE "$CA_OFFER" || true)"
  printf '%s' "$ca_rest" | grep -iqE "$CA_WORKLEFT" && d4=1
fi

[ "$contra" -eq 1 ] || [ "$d1" -eq 1 ] || [ "$d2" -eq 1 ] || [ "$d3" -eq 1 ] || [ "$d4" -eq 1 ] \
  || abstain "ledger-clean"

# ── Latch-set + hard cap (RED-proofed L + C). ──
mkdir -p "$STATE_DIR" 2>/dev/null || true
# GC stale per-session .fired latch-sets — SKEY embeds SID, so each is per-session and otherwise
# never reaped (mirrors memory-nudge.sh:26). A live session recreates its own on the next fire.
find "$STATE_DIR" -name '*.fired' -mtime +7 -delete 2>/dev/null || true
SKEY="$(printf '%s|%s|%s' "$CFG" "$SID" "$CWD" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$SKEY" ] || abstain "no-skey"
HASH="$(printf '%s' "$MSG" | shasum 2>/dev/null | cut -c1-16)"
[ -n "$HASH" ] || abstain "no-hash"
FIRED="$STATE_DIR/$SKEY.fired"
if [ -f "$FIRED" ] && grep -qxF "$HASH" "$FIRED" 2>/dev/null; then abstain "latched-already-fired"; fi
N="$(grep -c . "$FIRED" 2>/dev/null || echo 0)"; case "$N" in ''|*[!0-9]*) N=0 ;; esac
[ "$N" -ge "$MAX" ] && abstain "capped:${N}>=${MAX}"

# ── FIRE: record hash, log, block with the contradicting FACTS. ──
printf '%s\n' "$HASH" >> "$FIRED" 2>/dev/null || true
facts="${facts%; }"
# WHICH arm fired, legible after the fact: ledger | hedge | handoff | offer | fence, `+`-joined in
# that fixed order (so a combination is one canonical string, not five orderings of the same set).
arm=""
[ "$contra" -eq 1 ] && arm="ledger"
[ "$d3" -eq 1 ] && arm="${arm:+$arm+}hedge"
[ "$d1" -eq 1 ] && arm="${arm:+$arm+}handoff"
[ "$d4" -eq 1 ] && arm="${arm:+$arm+}offer"
[ "$d2" -eq 1 ] && arm="${arm:+$arm+}fence"
log_idl fired "false-done" \
  "$(jq -cn --arg facts "$facts" --arg rung "$RUNG" --arg arm "$arm" --argjson count "$((N+1))" --argjson max "$MAX" \
      '{facts:$facts,rung:$rung,arm:$arm,count:$count,max:$max}')"

# Reason = one sentence-group per firing arm, in arm order. The ledger group is byte-unchanged.
reason=""
[ "$contra" -eq 1 ] && reason="Completion-assert: your close reads as done/complete, but the LIVE ledger contradicts it — ${facts}. Ship/land of verified net-positive work is DRIVABLE (not a genuine blocker). Re-answer by DRIVING the remainder to done (📦 ⇒ /ship it; finish the open items; commit with explicit paths) — or name the ONE irreducible blocker (credential / sudo / destructive-migration / external-info only the operator has)."
[ "$d3" -eq 1 ] && reason="${reason:+$reason }Your line 1 both asserts and withdraws a verdict, so the operator has to ask a follow-up to learn which it is. Pick the ONE rung that actually governs — if something is parked or is the operator's, that IS the rung (📦 / 👤); if it is immaterial, leave it out of line 1 entirely. Line 1 answers 'is it safe to close?' with no qualifier."
[ "$d1" -eq 1 ] && reason="${reason:+$reason }Your close hands the operator work in prose, so the operator-readout block cannot render it and it stays buried in a paragraph. File each operator-only step — \`cc-backlog needs \"<step>\" [--run \"<exact command>\"]\` — then re-close: line 1 states the rung (👤 when steps are yours), and the steps come from the rendered block, not your prose."
[ "$d4" -eq 1 ] && reason="${reason:+$reason }Your close names remaining work and then offers it instead of driving it — the operator's standing ruling is that the answer is always yes, so the question costs a round-trip and yields nothing. Every open item resolves to exactly one of three dispositions, never a fourth: DRIVEN (you do it now), FILED (\`cc-backlog needs\` for an operator-only step, \`cc-backlog add\` for agent work — so it renders as one counted line), or BLOCKED on a genuine operator-only gate (credential / sudo / destructive migration / a real value fork), which then IS your line-1 rung. 'Say the word' is not a disposition. Drive it, or file it — then re-close."
[ "$d2" -eq 1 ] && reason="${reason:+$reason }Your close shows a command outside a bash-tagged fence, so the TUI cannot highlight it and the operator cannot tell prose from the thing to paste. Put the ONE command in a \`\`\`bash fence with at most one line of why before it. A close shows a command ONLY if you are asking the operator to run it — a command you would then tell them to ignore must not appear at all, neither fenced nor bare."
[ "$contra" -eq 1 ] || reason="Completion-assert: $reason"
reason="$reason (completion-assert $((N+1))/${MAX})"

jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
exit 0
