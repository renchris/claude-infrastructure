#!/usr/bin/env bash
# handed-off-session-guard.sh — refuse to take a prompt in a session whose transcript was
# TRANSPLANTED to another account. UserPromptSubmit; exit 2 blocks the prompt.
#
# ── THE INCIDENT THIS EXISTS FOR (2026-08-16) ───────────────────────────────────────────────────
# Six next3 sessions were transplanted off a 100%-exhausted account with lr-handoff.sh. Five source
# panes were closed; ONE (`ede6a811`, ~/Development/personal) could not be — `self-close` correctly
# REFUSED it because a live teammate would have been orphaned — and that refusal was treated as a
# note rather than a blocker. When next3's 5-hour window refilled at 18:00 the husk simply carried
# on: it re-created `<sid>.jsonl` in the RETIRED store and ran 40 assistant turns against the same
# session id while its successor ran 218 on another account. The operator typed into it, believing
# it live. Neither copy can ever see the other's turns.
#
# ── WHY THE EXISTING SAFETY DID NOT FIRE ────────────────────────────────────────────────────────
# lr-transplant.sh already writes BOTH artifacts a recovery needs: `<sid>.HANDOFF.json` beside the
# source transcript, and a split-brain lock under ~/.reso/limit-recover/locks/. Eleven scripts read
# them — cc-reaper, cc-classify, lr-audit, the lifecycle gate — and every one of them is a SWEEP or
# a REPORT. Nothing was on the path a running session actually takes, so the tombstone could only
# ever describe the split-brain after the fact. A conclusion that never reaches an enforcing store
# advises; it does not enforce. This hook is that store: it sits on the one event where the harm
# lands — an operator prompt entering a husk.
#
# ── FAIL-OPEN, DELIBERATELY ─────────────────────────────────────────────────────────────────────
# Every unknown resolves to exit 0. A guard that blocks on a parse failure would take out ordinary
# sessions repo-wide the first time a payload shape changed; the failure it prevents is rare and
# recoverable, and the failure it could CAUSE is neither.
#
# Escape hatch: CC_HANDED_OFF_GUARD_DISABLED=1 (or delete the tombstone) — for the legitimate case
# where the successor is dead and the operator is deliberately reviving the source.
set -uo pipefail

[ -n "${CC_HANDED_OFF_GUARD_DISABLED:-}" ] && exit 0

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || exit 0

# ONE jq start per read, never a python3 interpreter (docs/research/load-hook-timeouts-2026-10-11
# item 7): this runs on every prompt of every session, and the two python3 starts it used to pay
# before even looking for a tombstone were most of its cost under load. Resolved ABSOLUTELY as well
# as by PATH: hooks inherit a minimal PATH in launchd and headless contexts, which is exactly where a
# PATH-only lookup is silently unavailable. No jq ⇒ the sed fallback below.
HOG_JQ=""
for _c in "$(command -v jq 2>/dev/null || true)" /usr/bin/jq /opt/homebrew/bin/jq /usr/local/bin/jq; do
  [ -n "$_c" ] && [ -x "$_c" ] && { HOG_JQ="$_c"; break; }
done

# Split one `@tsv` row into the named variables by parameter expansion, not `read`: TAB is IFS
# whitespace, so `read` would collapse an EMPTY field and shift every later one into the wrong name.
# @tsv escapes \ TAB LF CR as \\ \t \n \r; each field is unescaped so a value prints exactly as it did
# when python3 printed it raw (the block messages quote $TP and $TOMB). A 0x02 placeholder keeps an
# escaped backslash from being read as the start of another escape (not 0x01: that is bash's own
# internal quoting byte, CTLESC, and mangles inside ${//}). No subshell, no fork.
hog_split() { # $1=row  $2...=variable names
  local row="$1" f v; shift
  for f in "$@"; do
    v="${row%%$'\t'*}"
    v="${v//\\\\/$'\002'}"; v="${v//\\t/$'\t'}"; v="${v//\\n/$'\n'}"; v="${v//\\r/$'\r'}"
    printf -v "$f" '%s' "${v//$'\002'/\\}"
    case "$row" in *$'\t'*) row="${row#*$'\t'}" ;; *) row="" ;; esac
  done
}

# A top-level STRING field, else "". The key is anchored on its opening quote AND a preceding
# delimiter in the sed fallback so a longer key cannot satisfy it — `"session_id"` must not be
# answered by `"parent_session_id"`, the greedy-suffix match that has cost this repo a defect before
# (jq's object lookup is exact by construction).
hog_sed_field() { # $1=key  $2=text
  printf '%s' "$2" | sed -n 's/.*[{,[:space:]]"'"$1"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

SID=""; TP=""
if [ -n "$HOG_JQ" ]; then
  hog_split "$(printf '%s' "$INPUT" | "$HOG_JQ" -rs '
    def s: if type == "string" then . else "" end;
    if length == 1 then .[0] else error("not one document") end
    | [(.session_id | s), (.transcript_path | s)] | @tsv' 2>/dev/null)" SID TP
else
  SID=$(hog_sed_field session_id "$INPUT")
  TP=$(hog_sed_field transcript_path "$INPUT")
fi
[ -n "$SID" ] && [ -n "$TP" ] || exit 0

TOMB="$(dirname "$TP")/$SID.HANDOFF.json"
[ -f "$TOMB" ] || exit 0

# Every tombstone field this hook can need, in ONE read. The per-field rules are the ones the python3
# reads applied: handed_off_to and superseded_by_pane print any truthy value (`x or ""`), phase only a
# string, superseded_by_pid only an integer — a JSON boolean included, since python's bool IS an int
# and `kill -0 True` then fails open. Unparseable, empty or multi-document ⇒ every field "".
TARGET=""; SUP_PID=""; SUP_PANE=""; PHASE=""
if [ -n "$HOG_JQ" ]; then
  hog_split "$("$HOG_JQ" -rs '
    def truthy: if . == null or . == false or . == 0 or . == "" or . == [] or . == {} then ""
                elif type == "string" then . elif . == true then "True" elif type == "number" then tostring
                else tojson end;
    def pid: if type == "boolean" then (if . then "True" else "False" end)
             elif type == "number" and . == floor then tostring else "" end;
    if length == 1 then .[0] else error("not one document") end
    | [(.handed_off_to | truthy), (.superseded_by_pid | pid), (.superseded_by_pane | truthy),
       (.phase | if type == "string" then . else "" end)] | @tsv' "$TOMB" 2>/dev/null)" \
    TARGET SUP_PID SUP_PANE PHASE
else
  TARGET=$(sed -n 's/.*[{,[:space:]]"handed_off_to"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TOMB" | head -1)
  SUP_PID=$(sed -n 's/.*[{,[:space:]]"superseded_by_pid"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$TOMB" | head -1)
  PHASE=$(sed -n 's/.*[{,[:space:]]"phase"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$TOMB" | head -1)
fi
[ -n "$TARGET" ] || exit 0

# ── SAME-ACCOUNT SUPERSESSION (LIMIT_RECOVER_100P, 2026-09-09) ──────────────────────────────────
# A duplicate on the SAME account has no transplant: on 2026-09-09 the reset poller resumed 52e35019
# into tmux while pane 616 still held the original process, and both appended to one transcript. The
# account test below cannot separate them — they ARE one account — so a SUPERSEDED tombstone names
# the live copy by PROCESS: `superseded_by_pid` (+ `superseded_by_pane` for the message). This hook
# runs as a descendant of the claude process it guards, so identity is its own ancestry: the copy
# whose claude pid IS the named successor is acquitted; every other process holding this session id
# is the stale copy and its prompts are blocked. A dead successor pid fails OPEN (nothing is carrying
# the session any more), exactly like the cross-account verdict in lr_tombstone_verdict.
if [ -n "$SUP_PID" ]; then
  if ! kill -0 "$SUP_PID" 2>/dev/null; then exit 0; fi        # successor gone ⇒ nothing else carries it
  _p="$PPID"; _n=0; _mine="${CC_HOG_SELF_PID:-}"     # CC_HOG_SELF_PID: test seam naming this hook's claude pid
  [ -n "$_mine" ] && _p=""
  while [ -n "$_p" ] && [ "$_p" != 0 ] && [ "$_p" != 1 ] && [ "$_n" -lt 16 ]; do
    _c="$(ps -o comm= -p "$_p" 2>/dev/null || true)"
    case "${_c##*/}" in claude*|node*) _mine="$_p"; break ;; esac
    _p="$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' ' || true)"; _n=$((_n + 1))
  done
  [ -n "$_mine" ] || exit 0                                     # cannot tell who I am ⇒ fail open
  [ "$_mine" = "$SUP_PID" ] && exit 0                           # I AM the live copy
  cat >&2 <<EOF
⛔ THIS PANE IS A STALE COPY — your prompt was NOT delivered.

Session ${SID:0:8} is being carried by ANOTHER process on this same account (pid $SUP_PID${SUP_PANE:+, pane $SUP_PANE}).
This process (claude pid $_mine) still holds an older view of the conversation, so anything you say
here forks the session: two writers on one transcript, neither able to see the other's turns — the
same-account split-brain the SUPERSEDED tombstone was written to prevent: $TOMB.

  · Say it in pane ${SUP_PANE:-<the live copy>} instead (it has the whole conversation).
  · Nothing here is lost: the transcript is one file and the live copy appends to it.
  · Genuinely reviving THIS side (the live copy is dead)? Delete the tombstone, or re-run with
    CC_HANDED_OFF_GUARD_DISABLED=1.

Then close this pane.
EOF
  exit 2
fi

# ── Am I the TARGET or the SOURCE? ──────────────────────────────────────────────────────────────
# The successor carries the SAME session id, so identity is the whole question. Two independent
# answers, either of which acquits:
#   (a) my transcript already sits under the target config dir, or
#   (b) my account and the target's are the same ACCOUNT.
# (b) needs the mirror: `~/.claude` and `~/.claude-next` are two directories for ONE account
# (documented in the resume-sessions skill), so a bare string compare would convict every next
# successor of being its own predecessor — the one false positive that would matter.
case "$TP" in "$TARGET"/*) exit 0 ;; esac

hog_acct() {
  case "$(basename "${1%/}")" in
    .claude|.claude-next) printf 'next' ;;
    *) printf '%s' "$(basename "${1%/}")" ;;
  esac
}
ME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
[ "$(hog_acct "$TARGET")" = "$(hog_acct "$ME")" ] && exit 0

# ── A HALF-DONE MOVE IS STILL THE SOURCE'S (D7.2a, operator ruling 28740361e7dd, 2026-09-30) ───────
# `--phase admit` copies and tombstones but never retires: the source stays the live writer until a
# `--phase confirm` asserts it has stopped. A prompt typed in that window belongs to the source, and
# refusing it strands the operator in a focused pane mid-move. So the guard steps aside only when all
# three say "not yet retired": the tombstone's phase is admit (lr-transplant writes it for a
# non-keep-source admit only; confirm rewrites the tombstone without it), <sid>.jsonl is still here,
# and no <sid>.jsonl.handed-off sits beside it. Anything else — keep-source, a legacy tombstone with no
# phase, an unasserted run — falls through to the block below. ($PHASE was read with the other
# tombstone fields above.)
SRC_JSONL="$(dirname "$TP")/$SID.jsonl"
if [ "$PHASE" = admit ] && [ -f "$SRC_JSONL" ] && [ ! -e "$SRC_JSONL.handed-off" ]; then
  _log="$HOME/.claude/logs/handed-off-guard.log"
  mkdir -p "$(dirname "$_log")" 2>/dev/null \
    && printf '%s allow-admit sid=%s target=%s tomb=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SID" "$TARGET" "$TOMB" >>"$_log" 2>/dev/null
  exit 0
fi

cat >&2 <<EOF
⛔ THIS PANE IS A RETIRED SOURCE — your prompt was NOT delivered.

Session ${SID:0:8} was transplanted to $(hog_acct "$TARGET") ($TARGET) and continues there.
This process still holds the pre-transplant conversation, so anything you say here forks the
session: two copies, neither able to see the other's turns. That is the split-brain the
transplant's tombstone was written to prevent — $TOMB.

  · Say it to the successor instead (it has this whole conversation).
  · Nothing here is lost: this side's transcript stays on disk at $TP.
  · Genuinely reviving this side (successor dead)? Delete the tombstone, or re-run with
    CC_HANDED_OFF_GUARD_DISABLED=1.

Then close this pane.
EOF
exit 2
