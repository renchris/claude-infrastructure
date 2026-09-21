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
# THE LIMITED ARM (LIMIT_DETECT_100P W1) adds three things and only for `error == "rate_limit"`:
# a `kind:"limited"` beat through the existing writer, ONE notification per cause behind an O_EXCL
# latch, and an opt-in poller kick. Everything else above still holds — the marker is still
# cause-keyed and append-only, exit is still always 0, stdout is still always empty. What changed
# is the claim in the header above that "this hook never notifies anyone": it now does, exactly
# once per (account, message) and never once per session, which is the property that made the old
# rule necessary. The collapsing moved from "do not page" to "page on the same key the marker is
# already collapsed on".
#
# THE REQUEST ARM (LIMIT_RECOVER_100P W5-F) adds a fourth thing on the same limit path: the
# recovery REQUEST the reset poller drains. Until it landed the recovery lane had exactly one
# producer — a human running `lr-fleet.sh --enqueue` — so detection that was already right on 126
# of 128 real rate_limit deaths started nothing. See § ARM 2 below for why it is inert, by
# construction, until the operator creates `$STATE/autorecover.on`.
#
# Env seams (tests): STOP_FAILURE_MARKER_DIR · STOP_FAILURE_IDL · STOP_FAILURE_ACCOUNTS ·
#                    STOP_FAILURE_TTL_MIN · STOP_FAILURE_CAP · STOP_FAILURE_LIMITED_DIR ·
#                    STOP_FAILURE_BEAT · STOP_FAILURE_OSASCRIPT · STOP_FAILURE_OSA_TIMEOUT_S ·
#                    STOP_FAILURE_LAUNCHCTL · STOP_FAILURE_LR_STATE · STOP_FAILURE_TAIL_BYTES
# Kill switches are FILES under $LIM, not env vars: .off (the whole arm) · .page-off (the page) ·
# .kick-on (the kick, which is OFF unless the file exists) · .request-off (the request arm).
# ARM 2 also honours the env switch CC_SF_REQUEST=off, which is the WEAK form — see § ARM 2.
set -uo pipefail

MARKER_DIR="${STOP_FAILURE_MARKER_DIR:-$HOME/.claude/autonomy/stop-failure}"
ACCOUNTS="${STOP_FAILURE_ACCOUNTS:-$HOME/.claude/accounts.json}"
# The limited lane: the page latch dir and the three kill switches. FILE sentinels, not env vars,
# and that choice is load-bearing — an env var cannot reach a pane that is ALREADY RUNNING, which
# is the entire population during a mass cap. `[ -e ]` costs nothing on the death path.
LIM="${STOP_FAILURE_LIMITED_DIR:-$HOME/.claude/autonomy/limited}"
# TTL 10080 min = 7 days — the SEVEN_DAY cap's own window. THE RATIONALE IS NARROWER THAN IT LOOKS,
# and the narrow version is the true one (§ 11 #7): the GC below is keyed on the FILE's mtime, and
# every death APPENDS, so a busy account's marker is touched continuously and never expires at ANY
# TTL. 10080 buys exactly one thing — a QUIET account, capped once and then silent, keeps the record
# that it was blocked for as long as the block itself can last. At 1440 that one record was GC'd
# four days before the cap expired, which is the census going blank over a session still blocked.
#
# CAP STAYS 500, and this is a REVERSAL of § 9 D3's proposed 5000, ruled by § 11 #7 at 85 %. D3
# argued 500 is reachable in one bad afternoon and therefore too low. It is reachable — and that
# does not cost anything, because a capped file is NOT a lost fact: the marker stays in place, and
# per-sid grouping at READ time already dedupes the re-fires that fill it (22 of 42 sessions
# re-firing up to 30× produce 30 lines and ONE session in the census). What the cap actually bounds
# is disk for a fact that was fully established at line 1, and the census reports the capped file in
# its footer and exits 6 either way. 5000 bought ~350× the measured enumerate regime and no
# information, so the cheaper bound wins.
TTL_MIN="${STOP_FAILURE_TTL_MIN:-10080}"
CAP="${STOP_FAILURE_CAP:-500}"
case "$TTL_MIN" in ''|*[!0-9]*) TTL_MIN=10080 ;; esac
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
  # ALIAS-AWARE. The config_dir match alone cannot resolve ~/.claude, because no accounts.json row
  # names it — `next` claims ~/.claude-next, and ~/.claude is reached through its `aliases` list
  # (which already contains "claude"). So the basename fallback below fired instead and minted a
  # PHANTOM account called ".claude": five real marker rows landed in
  # `authentication_failed__.claude.jsonl`, an account no ranker, poller or transplant target knows.
  # Matching on aliases too is one clause with zero blast radius; the alternative considered and
  # dropped was a fifth accounts.json row, which would enter bin/claude-accounts, handoff-fire.sh,
  # gen-account-map.sh and the router's spend order — all unmeasured.
  ACCOUNT="$(jq -r --arg h "$HOME" --arg c "$CFG" --arg b "$(basename "$CFG" | sed 's/^\.//')" \
    '.accounts[]?
       | select(((.config_dir | sub("^~"; $h) | sub("/$"; "")) == $c)
                or (((.aliases // []) | index($b)) != null))
       | .name' \
    "$ACCOUNTS" 2>/dev/null | head -1 || true)"
fi
[ -n "$ACCOUNT" ] || ACCOUNT="$(basename "$CFG" 2>/dev/null || echo unknown)"

# ── the PANE, which no store holds and the payload does not carry ────────────────────────────────
# KITTY_WINDOW_ID first: it is the one address present on sessions the registry cannot see at all
# (measured — a lead-launched successor carried KITTY_WINDOW_ID=186 and neither of the other two,
# so session-register.sh had no address for it and wrote no row). The ITERM form carries a
# "wNtNpN:" prefix that must be stripped to the bare id.
#
# NEVER `${ITERM_SESSION_ID##*:}` on a possibly-unset variable: under `set -u` that is an unbound
# variable error, not an empty string, and this hook runs on the death path. A NESTED-DEFAULT CHAIN
# on ONE line is the bash-3.2-safe idiom session-register.sh:127 already uses — every arm carries
# its own `:-`, so no arm is ever read unset, and the strip runs once on whichever arm won.
#
# ONE LINE IS LOAD-BEARING, not cosmetic: tests/cc-pane.bats:352 ratchets that no file under
# bin/ scripts/ hooks/ may take a bare `:-` default off ITERM_SESSION_ID on a line that does not
# also name CC_PANE_ID, which is how the rename is stopped from silently un-doing itself. (That
# ratchet is a plain grep for the literal and is COMMENT-BLIND, so this note states the shape
# rather than quoting it — quoting it here was itself red, measured.) A two-step form
# (`PANE=${CC_PANE_ID:-${KITTY_WINDOW_ID:-}}` then a separate ITERM fallback) puts the ITERM read
# on a line of its own and is RED — measured here, ship-land exit 6, red=smoke:tests/cc-pane.bats.
# The per-line `cc-pane-id-lint:allow` marker is NOT the escape for it: that belongs to bin/cc-pane's
# own fallback DEFINITION, and a consumer taking it would blind the ratchet to a real bare read
# added later. Collapsing is also semantically identical here — `##*:` is a no-op on a value with
# no colon, which both CC_PANE_ID (bare id) and KITTY_WINDOW_ID (integer) are.
PANE="${CC_PANE_ID:-${KITTY_WINDOW_ID:-${ITERM_SESSION_ID:-}}}"; PANE="${PANE##*:}"
# The pane becomes a FILENAME in the registry lookup a reader does with it, so anything that is not
# a plain id is dropped rather than sanitized — a half-cleaned address that resolves to the wrong
# pane is worse than no address.
case "$PANE" in *[!A-Za-z0-9._-]*) PANE="" ;; esac

# ── the cause key ────────────────────────────────────────────────────────────────────────────────
_sf_slug() { printf '%s' "${1:-}" | tr -c 'A-Za-z0-9._-' '_' | cut -c1-64; }

# ── the page sink ────────────────────────────────────────────────────────────────────────────────
# NOT sourced from hooks/notify.sh, deliberately: that file is `set -euo pipefail` with top-level
# code that plays a sound and dispatches on $1, so sourcing it here would fire a chime and could
# exit the hook on any non-zero. What is reused is its BOUNDED-FORK LADDER (notify.sh:16-30) —
# resolving timeout(1) by absolute path as well as by PATH, because hooks and launchd jobs run
# without Homebrew on PATH, and running UNBOUNDED rather than losing the page when none is found.
# The wedge that ladder exists for is real: an unbounded AppleEvent fork inside an automated path
# turns a best-effort page into a stalled hook on the death path.
_sf_page() { # $1=account $2=last_assistant_message
  local _osa _msg _ttl _tb _c
  _osa="${STOP_FAILURE_OSASCRIPT:-/usr/bin/osascript}"
  [ -n "$_osa" ] && [ -x "$_osa" ] || return 0     # set-but-EMPTY disables the sink verbatim
  # Resolved HERE rather than at file scope so a non-limit death — the overwhelming majority of
  # this hook's traffic — pays nothing for a ladder it will never walk.
  _tb=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { _tb="$_c"; break; }
  done
  # The message NAMES THE NEXT COMMAND. A page that says only "limited" spends the operator's
  # attention and hands back no action; 2 h 37 m of idle across five sessions was bought by
  # exactly that gap, with a marker on disk the whole time.
  _msg="${1:-?}: $(printf '%s' "${2:-}" | cut -c1-80) — run: cc-limited"
  _ttl="⛔ limited: ${1:-?}"
  if [ -n "$_tb" ]; then
    "$_tb" -k 3 "${STOP_FAILURE_OSA_TIMEOUT_S:-5}" "$_osa" -e \
      "display notification \"$_msg\" with title \"$_ttl\"" >/dev/null 2>&1 || true
  else
    "$_osa" -e "display notification \"$_msg\" with title \"$_ttl\"" >/dev/null 2>&1 || true
  fi
  return 0
}
CAUSE_KEY="$(_sf_slug "$ERR")__$(_sf_slug "$ACCOUNT")"   # ANCHOR: cause-keyed, never session-keyed
MARKER="$MARKER_DIR/$CAUSE_KEY.jsonl"

mkdir -p "$MARKER_DIR" 2>/dev/null || _sf_abstain "marker-dir-unwritable"

# GC: a cause that stopped recurring stops being a fact. Prune whole markers untouched for the TTL,
# so a resolved login cliff self-retires instead of paging forever off a stale file.
find "$MARKER_DIR" -type f -name '*.jsonl' -mmin "+$TTL_MIN" -delete 2>/dev/null || true
# The page latches below are the same kind of fact and expire on the same clock. Without this they
# accumulate forever and a cause that recurs next week is latched by a file from this one — the
# latch would silently become permanent, which reads exactly like "nothing is wrong".
find "$LIM/.paged" -type f -mmin "+$TTL_MIN" -delete 2>/dev/null || true

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

# ── THE LIMITED ARM — beat, page, kick ───────────────────────────────────────────────────────────
# EVERYTHING HERE SITS ABOVE THE CAP EARLY-EXIT, and that placement is the point. The marker file
# caps at $CAP lines; the arms below must not. A session whose account has already logged 5000
# deaths is exactly the one most in need of a flipped beat, and an arm below the cap would go
# silent precisely during the mass event it exists for.
#
# Scoped to `rate_limit` ONLY. A network stall or a mid-retry death is not a capped session, and
# stamping those `limited` would un-count a session that is genuinely still working — the beat is
# a presence signal and over-claiming on it costs a real admission.
#
# Death-path budget: this adds a bounded beat fork (hard-capped at 3 s inside session-beat.sh,
# measured ~10 ms) plus one osascript on the ONE winner of the latch (~30 ms). No python fork, no
# tail read, no ancestry walk — each of those was measured and rejected at 0.19 s to 3.17 s.
if [ "$ERR" = rate_limit ] && [ ! -e "$LIM/.off" ]; then

  # (a) THE BEAT. Stop never fires on a limit turn, so `cc-beats/<sid>.json` keeps its last
  # `kind:"prompt"` forever and spawn-presence counts the corpse as ACTIVE. Measured: 12 of 14 of
  # one day's rate_limit sids, ACTIVE=10 against an admission ceiling of 8, and the poller parked a
  # real recovery at 9>8. Flipping four frozen sids to `limited` took ACTIVE to 7 and it admitted.
  # Written through the EXISTING writer, never by hand: the beat record carries a sticky operatorT
  # high-water mark and a sequence number, and a hand-rolled write would drop both.
  _sf_beat="${STOP_FAILURE_BEAT:-$_sfscd/session-beat.sh}"
  [ -f "$_sf_beat" ] || _sf_beat="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/session-beat.sh"
  [ -f "$_sf_beat" ] || _sf_beat="$HOME/.claude/hooks/session-beat.sh"
  if [ -f "$_sf_beat" ]; then
    printf '%s' "$input" | bash "$_sf_beat" limited >/dev/null 2>&1 || true
  fi

  # (b) THE PAGE, exactly once per cause.
  # THE LATCH IS O_EXCL, not check-then-write. 30 sessions die CONCURRENTLY on one cap; a
  # `[ -e ] && write` has a window between the test and the write that all 30 pass through, and
  # page-damp.sh:42-50 is exactly that shape (it also returns 0 on every failure, so a damp that
  # cannot write sends anyway). `( set -C; : > f )` is one atomic create that exactly one process
  # can win.
  # THE KEY IS DERIVED FROM THE PAYLOAD ALONE — account plus the first 64 bytes of the message —
  # so all 30 processes compute the same string with no shared read and no coordination. Keying it
  # on the sid would page 30 times for one fact, which is the flood this hook was built to avoid.
  if [ ! -e "$LIM/.page-off" ]; then
    mkdir -p "$LIM/.paged" 2>/dev/null || true
    _sf_pg="$LIM/.paged/$(_sf_slug "$ACCOUNT")__$(_sf_slug "$(printf '%s' "$LAST" | cut -c1-64)")"
    # `set -C` is scoped to the subshell so the caller's noclobber state is untouched.
    if ( set -C; : > "$_sf_pg" ) 2>/dev/null; then
      _sf_page "$ACCOUNT" "$LAST"; log_idl fired "page-sent"
    elif [ -e "$_sf_pg" ]; then
      # Someone else won the create. This is the expected path for 29 of 30.
      log_idl passed "page-latched"
    else
      # The create failed and the file does NOT exist, so it was not EEXIST — an unwritable dir, a
      # full disk, a bad mount. FAIL OPEN: send. A latch that cannot be written must never be read
      # as "already paged", because that silences the page for a cause nobody has heard about yet.
      # The IDL row names it so the fleet can see the latch is degraded.
      _sf_page "$ACCOUNT" "$LAST"; log_idl abstained "page-latch-unwritable-sent"
    fi
  fi

  # (c) THE KICK, default OFF behind a file sentinel. Waking the reset poller on every limit death
  # arms the recovery chain at roughly 60x its current rate, and the recovery chain's own
  # observability does not land until a later wave. The sentinel is how that ordering is enforced
  # in the code rather than in a plan. Bare `kickstart`, never `-k`: `-k` KILLS a running job, so
  # it would abort a tick that is already doing the work this kick is asking for.
  if [ -e "$LIM/.kick-on" ]; then
    "${STOP_FAILURE_LAUNCHCTL:-/bin/launchctl}" kickstart \
      "gui/$(id -u 2>/dev/null || echo 0)/com.reso.lr-reset-poller" >/dev/null 2>&1 || true
  fi
fi

# ── ARM 2 — THE RECOVERY REQUEST (LIMIT_RECOVER_100P W5-F) ───────────────────────────────────────
# WHY IT IS HERE AT ALL. LIMIT_RECOVER_100P:408 handed "the hook's request writer" to the sibling
# plan LIMIT_DETECT_100P, whose own § 7 then DROPPED it — so the item was ORPHANED, not owned, and
# the recovery lane kept its single human producer. This arm is the automatic one.
#
# 🚨 IT IS UNSAFE WITHOUT THE POLLER'S POLICY GATE (W5-A). ~30 sessions die at once on one cap, so
# this writes ~30 requests at once, and a poller that drained them unconditionally would transplant
# a whole fleet onto other accounts with no human in the loop. TWO things hold that shut and both
# are load-bearing:
#   · `requested_by` is the exact literal `stop-failure-marker`. W5-A's gate matches THAT STRING
#     and refuses a hook-originated request unless `$STATE/autorecover.on` exists. Renaming it
#     silently un-gates the fleet, which is why there is an ANCHOR row on the literal in the suite.
#   · the KICK below is gated on that same flag, so at the shipped default (flag ABSENT) the
#     requests accumulate as breadcrumbs and the poller meets them on its own 600 s StartInterval,
#     having already refused them at W5-A's gate.
# THIS HOOK NEVER CREATES `autorecover.on`. That file is an operator decision
# (docs/plans/LIMIT_RECOVER_100P.md:384, 85 % conviction, shipped default OFF) and nothing here may
# pre-empt it.
#
# WIDER THAN THE ARM ABOVE, deliberately: `rate_limit_error` is the second spelling of the same
# fact, and a recovery missed on a spelling is a session that stays dead. The beat/page arm keeps
# its narrower `rate_limit` gate untouched — widening a shipped, measured behaviour is not this
# wave's subject.
#
# THREE KILL SWITCHES, and the file ones are not redundant with the env one. `CC_SF_REQUEST=off` is
# honoured, but :55-56 above already records why an env var is the WEAK form here — it cannot reach
# a pane that is ALREADY RUNNING, and during a mass cap that is the entire population. `$LIM/.off`
# (inherited, whole-arm) and `$LIM/.request-off` (this arm alone) are the ones that can stop it
# mid-event.
#
# DEATH-PATH BUDGET, and what was REJECTED to hold it. NO python fork and NO process-table walk:
# the suite's own cost block already priced and rejected `agent_assignee_argv` (0.19-0.23 s
# ancestry walk), `oi_origin_class` (3.17 s full-file grep) and the transcript tier read (79 ms);
# and `lr_last_api_error` costs 50-70 ms of python while supplying NEITHER `resetsAt` NOR
# `rateLimitType`, which are two of the three fields this arm actually needs. What it does instead
# is one bounded `tail -c | jq` pass that yields all three — measured 0.01 s on a 4 MB transcript.
_SF_RQ_STATE="${STOP_FAILURE_LR_STATE:-${LR_STATE_DIR:-$HOME/.reso/limit-recover}}"

# The death record's three identifying fields in ONE bounded pass. `jq -Rr` + `fromjson?` is the
# per-line try/except a tail needs: a tail starts mid-record, and `jq -s` over a stream whose FIRST
# line is a fragment fails the WHOLE slurp, which would read as "no death record" on every long
# transcript. Shape verified in-tree: tests/lr-predicate.bats:166 and tests/cc-limited.bats:257 both
# carry `quotaLimits:{resetsAt:<epoch>, rateLimitType:"five_hour"|"seven_day"}` as a TOP-LEVEL
# sibling of `message`. `objects` guards the access so a malformed `quotaLimits` yields "" rather
# than aborting the program.
_SF_RQ_JQ='fromjson?
  | select(type == "object")
  | select(.type == "assistant" and (.isApiErrorMessage == true))
  | [ (.uuid // ""),
      (((.quotaLimits | objects | .resetsAt) // "") | tostring),
      (((.quotaLimits | objects | .rateLimitType) // "") | tostring) ]
  | @tsv'

_sf_rq_enrich() { # $1=transcript → "<uuid>\t<reset_at_epoch>\t<rate_limit_type>"; EMPTY on anything else
  local f="${1:-}" tb c
  [ -n "$f" ] && [ -f "$f" ] || return 0
  # The same bounded-fork ladder _sf_page walks, and for the same reason: hooks run without
  # Homebrew on PATH. Duplicated rather than factored out of _sf_page — that function is inherited
  # law from another wave and a refactor of it would need its own red-proof.
  tb=""
  for c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
           /opt/homebrew/bin/timeout /usr/local/bin/timeout \
           /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$c" ] && [ -x "$c" ] && { tb="$c"; break; }
  done
  if [ -n "$tb" ]; then
    # shellcheck disable=SC2016  # DELIBERATE: this is the INNER shell's program text, so
    # $1/$2/$3 must reach it unexpanded — they are the positional args passed after the `_`.
    "$tb" -k 2 "${STOP_FAILURE_ENRICH_TIMEOUT_S:-4}" /bin/bash -c \
      'tail -c "$2" "$1" 2>/dev/null | jq -Rr "$3" 2>/dev/null | tail -1' \
      _ "$f" "${STOP_FAILURE_TAIL_BYTES:-131072}" "$_SF_RQ_JQ" 2>/dev/null || true
  else
    /bin/bash -c 'tail -c "$2" "$1" 2>/dev/null | jq -Rr "$3" 2>/dev/null | tail -1' \
      _ "$f" "${STOP_FAILURE_TAIL_BYTES:-131072}" "$_SF_RQ_JQ" 2>/dev/null || true
  fi
  return 0
}

_sf_request() {
  local rqdir latchdir tmp dest enrich uuid reset rlt duuid
  rqdir="$_SF_RQ_STATE/requests"; latchdir="$_SF_RQ_STATE/requests-latch"

  # A REQUEST IS ADDRESSED BY ITS SID, so a sid that is absent, unknown, or not path-safe cannot
  # produce one: the poller passes `.sid` straight to `lr-fleet.sh --one`, and lr-reset-poller.sh
  # :674-675 DESTROYS a request with no `.sid` (renamed `.malformed.json`, never retried) rather
  # than parking it. Same shape as the PANE guard above — drop, never sanitize.
  case "$SID" in ''|'?'|*[!A-Za-z0-9._-]*) log_idl passed "request-skip-bad-sid"; return 0 ;; esac

  mkdir -p "$rqdir" "$latchdir" 2>/dev/null || { log_idl abstained "request-dir-unwritable"; return 0; }
  # The latches expire on the marker's own clock, exactly as the page latches at :209 do. Without
  # this a latch from last week permanently suppresses this week's recurrence of the same cause,
  # and a permanently latched arm reads exactly like an arm with nothing to do.
  find "$latchdir" "$_SF_RQ_STATE/teammate-skip" -type f -mmin "+$TTL_MIN" -delete 2>/dev/null || true

  # SKIP 1 — A TEAMMATE. Its lead owns its life: an assignee is woken over the teammate channel,
  # and transplanting it would put a second writer on one transcript. The test is the house idiom
  # (handoff-fire.sh:7810, lr-fleet.sh:215) — `agentName` is a top-level key on an early `user`
  # record, so the first 8 KB answers it. `grep` is DRAINED, never `-q`: an early-exiting consumer
  # under `set -o pipefail` promotes the producer's SIGPIPE to the pipeline status and the `if`
  # reads FALSE on a match (scripts/pipefail-sigpipe-lint.sh). The known false positive —
  # `"agentName":null` also matches — errs toward SKIPPING, which is the safe direction here.
  if [ -n "$TP" ] && [ -f "$TP" ] \
     && head -c 8192 "$TP" 2>/dev/null | grep '"agentName"' >/dev/null 2>&1; then
    mkdir -p "$_SF_RQ_STATE/teammate-skip" 2>/dev/null || return 0
    # `( … ) 2>/dev/null`, never `: > f 2>/dev/null`. A FAILED REDIRECTION is reported by the shell
    # BEFORE the command runs, so a trailing `2>/dev/null` on the same simple command is applied
    # too late and the error reaches the real stderr — measured here, same trap as :211-213. A
    # group or subshell redirect is applied to the whole thing and does suppress it.
    ( : > "$_SF_RQ_STATE/teammate-skip/$(_sf_slug "$SID")" ) 2>/dev/null || true
    log_idl passed "request-skip-teammate"
    return 0
  fi

  # SKIP 2 — ALREADY HANDED OFF. The tomb sits BESIDE THIS TRANSCRIPT, never at the global lock:
  # the tomb is per-session (lr-transplant writes `<sid>.HANDOFF.json` into the session's own
  # project dir), so a global path would let one handed-off session mute the whole fleet.
  if [ -n "$TP" ] && [ -e "$(dirname "$TP")/$SID.HANDOFF.json" ]; then
    log_idl passed "request-skip-handed-off"
    return 0
  fi

  # IDEMPOTENCE, before the write. StopFailure RE-FIRES for one sid (22 of 42 sessions, up to 30x —
  # the header's own measurement), and the poller DELETES a request when it drains it, so without
  # this a re-fire after a drain re-enqueues a recovery that already ran. This is not the race gate
  # — the O_EXCL create below is — and it cannot be: under concurrency both writers would produce
  # the identical per-sid request, which is benign. What it bounds is the SEQUENTIAL re-fire.
  enrich="$(_sf_rq_enrich "$TP")"
  uuid=""; reset=""; rlt=""
  IFS="$(printf '\t')" read -r uuid reset rlt <<EOF
$enrich
EOF
  duuid="$(_sf_slug "$uuid")"
  # NEVER a constant fallback: that would latch the FIRST death for the life of the session and go
  # silent on every later one (lr-lib.sh:203-206 names the same trap). The payload-derived key is
  # what the page latch at :261 already uses, and the cap message carries the reset time, so it
  # changes when the death does.
  [ -n "$duuid" ] || duuid="p-$(_sf_slug "$(printf '%s' "$LAST" | cut -c1-64)")"
  [ "$duuid" = "p-" ] && duuid="p-nokey"
  if [ -e "$latchdir/$SID.$duuid" ]; then
    log_idl passed "request-latched"
    return 0
  fi

  # THE RECORD. The four keys the consumer actually reads are `sid` `target` `source_pane`
  # `requested_by` (lr-reset-poller.sh:674,677) and all four are present and non-empty except
  # `source_pane`, which the poller itself passes conditionally (`${_rq_pane:+--source-pane …}`).
  # `tier` and `origin_class` are deliberately UNSET rather than derived — see the budget note
  # above; the poller re-derives the tier through lr-lib, which is the one spelling that may exist.
  tmp="$rqdir/.$SID.$$.tmp"; dest="$rqdir/$SID.json"
  # `$$` in the temp name, which the brief did not ask for: `.<sid>.tmp` alone is a SHARED path for
  # two concurrent re-fires of one sid, and two interleaved writers there produce a corrupt request
  # that the `mv` then publishes atomically. Still dot-prefixed and still `.tmp`, so the poller's
  # `"$REQUESTS"/*.json` glob cannot see it either way.
  # THE BRACES ARE LOAD-BEARING, exactly as at the teammate breadcrumb above: a failed OUTPUT
  # redirection is the shell's own message, emitted before jq runs, so `jq … > f 2>/dev/null`
  # leaks it to the real stderr. `{ …; } 2>/dev/null` is applied to the redirection too.
  { jq -cn --arg sid "$SID" --arg target auto --arg pane "$PANE" \
           --arg by "stop-failure-marker" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
           --arg acct "$ACCOUNT" --arg cwd "$CWD" --arg tp "$TP" --arg err "$ERR" \
           --arg reset "$reset" --arg rlt "$rlt" --arg duuid "$uuid" \
      '{sid:$sid, target:$target, source_pane:$pane, requested_by:$by, ts:$ts,
        account:$acct, cwd:$cwd, tier:"", transcript_path:$tp, error:$err,
        reset_at_epoch:$reset, rate_limit_type:$rlt, death_uuid:$duuid,
        origin_class:"unknown"}' > "$tmp"; } 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null || true; log_idl abstained "request-encode-failed"; return 0; }
  [ -s "$tmp" ] || { rm -f "$tmp" 2>/dev/null || true; log_idl abstained "request-encode-empty"; return 0; }
  mv -f "$tmp" "$dest" 2>/dev/null \
    || { rm -f "$tmp" 2>/dev/null || true; log_idl abstained "request-publish-failed"; return 0; }

  # WRITE-THEN-LATCH, in that order and not the reverse. A latch taken FIRST that is then followed
  # by a failed write is a permanent suppression of a request nobody ever made — the strongest
  # possible wrong answer on this path. Taken second, the worst case is a duplicate request for one
  # sid, which is the same file. O_EXCL, never check-then-write, for the reason :251-255 gives.
  if ( set -C; : > "$latchdir/$SID.$duuid" ) 2>/dev/null; then
    log_idl fired "request-written" \
      "$(jq -cn --arg s "$SID" --arg r "$reset" '{sid:$s,reset_at_epoch:$r}' 2>/dev/null || printf '{}')"
  else
    # A concurrent writer won the create. The request it published is ours to the byte, so there is
    # nothing to undo — we abstain from the KICK only, so one death produces at most one kick.
    log_idl passed "request-latch-lost"
    return 0
  fi

  # THE KICK, gated on the operator's flag and on nothing else. Bare `kickstart`, never `-k`: `-k`
  # KILLS a running job, and a tick that is mid-transplant is exactly the one this is asking for.
  # Never `load`/`unload` — this stays on the safe side of hooks/validate-bash.sh, which has no
  # launchctl rule at all.
  if [ -e "$_SF_RQ_STATE/autorecover.on" ]; then
    "${STOP_FAILURE_LAUNCHCTL:-/bin/launchctl}" kickstart \
      "gui/$(id -u 2>/dev/null || echo 0)/com.reso.lr-reset-poller" >/dev/null 2>&1 || true
  fi
  return 0
}

case "$ERR" in
  rate_limit|rate_limit_error)
    if [ "${CC_SF_REQUEST:-on}" != off ] \
       && [ ! -e "$LIM/.off" ] \
       && [ ! -e "$_SF_RQ_STATE/.request-off" ]; then
      _sf_request
    fi ;;
esac

# Bounded: past the cap the FACT is long established and further lines only cost disk. The marker
# stays in place — capping the file must never look like the cause resolved.
if [ "$LINES" -ge "$CAP" ]; then
  log_idl passed "marker-capped"
  exit 0
fi

# One short jq-encoded line. jq-encoded for the same reason the IDL is: a value carrying a quote or
# a newline must never be able to emit a malformed line that makes a reader's slurp read as EMPTY.
#
# THE BRACES (W5-F). `… >> "$MARKER" 2>/dev/null` does NOT silence a failed APPEND: a failed
# redirection is the SHELL's own message, emitted before jq ever runs, so the trailing `2>/dev/null`
# is applied too late — the same trap :211-213 already names for the input side. Reproduced here on
# 2026-09-20 with an EXISTING but unwritable marker dir (mkdir -p exits 0 on it, so the abstain at
# :201 never fires): the hook printed `…/authentication_failed__next.jsonl: Permission denied` to
# the real stderr on the death path, against this suite's own SILENCE contract. A group redirect is
# applied to the redirection too, which is what makes the contract true rather than merely stated.
{ jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" \
         --arg err "$ERR" --arg acct "$ACCOUNT" --arg cfg "$CFG" --arg sid "$SID" \
         --arg cwd "$CWD" --arg tp "$TP" --arg event "$EVENT" --arg pane "$PANE" \
         --arg last "$(printf '%s' "$LAST" | cut -c1-200)" \
    '{ts:$ts,error:$err,account:$acct,config_dir:$cfg,session_id:$sid,cwd:$cwd,
      transcript_path:$tp,hook_event_name:$event,pane:$pane,last_assistant_message:$last}' \
    >> "$MARKER"; } 2>/dev/null || true

log_idl fired "marker-$([ "$FIRST" = yes ] && echo opened || echo appended)" \
  "$(jq -cn --arg p "$PANE" '{pane:$p}' 2>/dev/null || printf '{}')"
exit 0
