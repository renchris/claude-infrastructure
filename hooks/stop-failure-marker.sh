#!/usr/bin/env bash
# stop-failure-marker.sh — the first consumer of the StopFailure event (HOOK_SURFACE_100P W3-A).
#
# WHY. StopFailure fires at the INSTANT a session dies, carrying `error` and
# `last_assistant_message` (measured on 2.1.114 + 2.1.220, § 3a of the plan; raw capture below).
# Today the fleet learns an account went logged-out from a POLL that runs about once an hour, so
# the median session dies ~30 minutes before anything notices. This hook makes death an EVENT.
#
# 🚨 THE CONSTRAINT THAT SHAPES EVERY LINE BELOW: IT WRITES A MARKER, NOT A PAGE.
# One account hitting its cap or its login cliff kills every session on it AT ONCE — measured, ~30
# of them. A hook that paged would emit 30 pages for ONE fact, which is the send-side flood
# hooks/lib/page-damp.sh was built after (570 near-duplicate pages in one box, three days). So the
# collapsing is done HERE, in the key: the marker is keyed on the CAUSE — the error string and the
# account it happened to — never on the session. N deaths of one cause therefore write N lines into
# exactly ONE file, and the operator-visible fact is the FILE. Paging stays with the existing
# page/alarm path, which reads these markers; this hook never notifies anyone.
#
# WHY APPEND-ONLY, and not a counter this hook increments. The 30 deaths are CONCURRENT. A
# read-modify-write of a shared counter from 30 processes loses writes and needs a lock on the one
# path where a lock is least affordable; an O_APPEND write of one short line does not. So the count
# is `wc -l` of the marker, derived by the reader, and no death can be lost to a race.
#
# MEASURED PAYLOAD (2.1.220, verbatim — /tmp/hs/log/stopfail.tsv, W1):
#   {"session_id":"…","transcript_path":"…","cwd":"/private/tmp/hs/scratch",
#    "prompt_id":"…","effort":{"level":"high"},"hook_event_name":"StopFailure",
#    "error":"authentication_failed","last_assistant_message":"Not logged in · Please run /login"}
#   `prompt_id` and `effort` were absent from the second capture in the same run ⇒ OPTIONAL.
#   Nothing in the payload names the ACCOUNT, so that is read from the hook's own inherited
#   CLAUDE_CONFIG_DIR and resolved to a launcher name through the accounts SSOT.
#
# FAIL-OPEN BY CONSTRUCTION: no `set -e`; every write `|| true`; exit is ALWAYS 0 and stdout is
# ALWAYS empty. This runs on the death path — a hook that dies noisily there, or that emits a
# stray byte a Stop-family consumer might read as a directive, is worse than the gap it fills.
#
# Env seams (tests): STOP_FAILURE_MARKER_DIR · STOP_FAILURE_IDL · STOP_FAILURE_ACCOUNTS ·
#                    STOP_FAILURE_TTL_MIN · STOP_FAILURE_CAP
set -uo pipefail

MARKER_DIR="${STOP_FAILURE_MARKER_DIR:-$HOME/.claude/autonomy/stop-failure}"
ACCOUNTS="${STOP_FAILURE_ACCOUNTS:-$HOME/.claude/accounts.json}"
TTL_MIN="${STOP_FAILURE_TTL_MIN:-1440}"
CAP="${STOP_FAILURE_CAP:-500}"
case "$TTL_MIN" in ''|*[!0-9]*) TTL_MIN=1440 ;; esac
case "$CAP"     in ''|*[!0-9]*) CAP=500 ;; esac

# ── IDL disposition writer (SSOT lib; degrades to a no-op, never to an error) ────────────────────
_sfscd="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
_sflib="$_sfscd/lib/idl-log.sh"
[ -f "$_sflib" ] || { _sft="${BASH_SOURCE[0]}"; [ -L "$_sft" ] && _sft="$(readlink "$_sft")"
  _sflib="$(cd "$(dirname "$_sft")" 2>/dev/null && pwd)/lib/idl-log.sh"; }
[ -f "$_sflib" ] || _sflib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/idl-log.sh"
[ -f "$_sflib" ] || _sflib="$HOME/.claude/hooks/lib/idl-log.sh"
SID="?"
# shellcheck source=lib/idl-log.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if [ -r "$_sflib" ] && . "$_sflib" 2>/dev/null && command -v idl_init >/dev/null 2>&1; then
  idl_init "${STOP_FAILURE_IDL:-${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}}" "stop-failure-marker" SID
else
  log_idl() { :; }
fi
_sf_abstain() { log_idl abstained "${1:-unspecified}"; exit 0; }

input="$(cat 2>/dev/null || printf '')"
[ -n "$input" ] || _sf_abstain "no-stdin"
command -v jq >/dev/null 2>&1 || _sf_abstain "no-jq"
printf '%s' "$input" | jq -e . >/dev/null 2>&1 || _sf_abstain "unparseable-payload"

jqs() { printf '%s' "$input" | jq -r "$1" 2>/dev/null || true; }   # never fatal

SID="$(jqs '.session_id // .sessionId // "?"')"; [ -n "$SID" ] || SID="?"
ERR="$(jqs '.error // .reason // ""')"
LAST="$(jqs '.last_assistant_message // .lastAssistantMessage // ""')"
CWD="$(jqs '.cwd // ""')"
TP="$(jqs '.transcript_path // ""')"
EVENT="$(jqs '.hook_event_name // "StopFailure"')"

# An `error` is the whole cause axis. Without one there is nothing to collapse ON, and a marker
# keyed "unknown" would fold unrelated deaths into one fact — worse than no marker.
[ -n "$ERR" ] || _sf_abstain "no-error-field"

# ── the ACCOUNT — the second half of the cause, and the payload does not carry it ────────────────
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
ACCOUNT=""
if [ -r "$ACCOUNTS" ]; then
  ACCOUNT="$(jq -r --arg h "$HOME" --arg c "$CFG" \
    '.accounts[]? | select((.config_dir | sub("^~"; $h) | sub("/$"; "")) == $c) | .name' \
    "$ACCOUNTS" 2>/dev/null | head -1 || true)"
fi
[ -n "$ACCOUNT" ] || ACCOUNT="$(basename "$CFG" 2>/dev/null || echo unknown)"

# ── the cause key ────────────────────────────────────────────────────────────────────────────────
_sf_slug() { printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64; }
CAUSE_KEY="$(_sf_slug "$ERR")__$(_sf_slug "$ACCOUNT")"   # ANCHOR: cause-keyed, never session-keyed
MARKER="$MARKER_DIR/$CAUSE_KEY.jsonl"

mkdir -p "$MARKER_DIR" 2>/dev/null || _sf_abstain "marker-dir-unwritable"

# GC: a cause that stopped recurring stops being a fact. Prune whole markers untouched for the TTL,
# so a resolved login cliff self-retires instead of paging forever off a stale file.
find "$MARKER_DIR" -type f -name '*.jsonl' -mmin "+$TTL_MIN" -delete 2>/dev/null || true

# `2>/dev/null` on the wc does NOT cover this: a failed input REDIRECTION is reported by the shell
# itself, before wc ever runs, so an absent marker printed to stderr on the death path. The -f guard
# is what makes the first death silent.
FIRST="no"; LINES=0
if [ -f "$MARKER" ]; then
  LINES="$(wc -l < "$MARKER" 2>/dev/null | tr -d ' ' || echo 0)"
  case "$LINES" in ''|*[!0-9]*) LINES=0 ;; esac
else
  FIRST="yes"
fi

# Bounded: past the cap the FACT is long established and further lines only cost disk. The marker
# stays in place — capping the file must never look like the cause resolved.
if [ "$LINES" -ge "$CAP" ]; then
  log_idl passed "marker-capped"
  exit 0
fi

# One short jq-encoded line. jq-encoded for the same reason the IDL is: a value carrying a quote or
# a newline must never be able to emit a malformed line that makes a reader's slurp read as EMPTY.
jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
       --arg err "$ERR" --arg acct "$ACCOUNT" --arg cfg "$CFG" --arg sid "$SID" \
       --arg cwd "$CWD" --arg tp "$TP" --arg event "$EVENT" \
       --arg last "$(printf '%s' "$LAST" | cut -c1-200)" \
  '{ts:$ts,error:$err,account:$acct,config_dir:$cfg,session_id:$sid,cwd:$cwd,
    transcript_path:$tp,hook_event_name:$event,last_assistant_message:$last}' \
  >> "$MARKER" 2>/dev/null || true

log_idl fired "marker-$([ "$FIRST" = yes ] && echo opened || echo appended)"
exit 0
