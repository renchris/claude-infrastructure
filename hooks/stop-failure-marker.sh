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
# Env seams (tests): STOP_FAILURE_MARKER_DIR · STOP_FAILURE_IDL · STOP_FAILURE_ACCOUNTS ·
#                    STOP_FAILURE_TTL_MIN · STOP_FAILURE_CAP · STOP_FAILURE_LIMITED_DIR ·
#                    STOP_FAILURE_BEAT · STOP_FAILURE_OSASCRIPT · STOP_FAILURE_OSA_TIMEOUT_S ·
#                    STOP_FAILURE_LAUNCHCTL
# Kill switches are FILES under $LIM, not env vars: .off (the whole arm) · .page-off (the page) ·
# .kick-on (the kick, which is OFF unless the file exists).
set -uo pipefail

MARKER_DIR="${STOP_FAILURE_MARKER_DIR:-$HOME/.claude/autonomy/stop-failure}"
ACCOUNTS="${STOP_FAILURE_ACCOUNTS:-$HOME/.claude/accounts.json}"
# The limited lane: the page latch dir and the three kill switches. FILE sentinels, not env vars,
# and that choice is load-bearing — an env var cannot reach a pane that is ALREADY RUNNING, which
# is the entire population during a mass cap. `[ -e ]` costs nothing on the death path.
LIM="${STOP_FAILURE_LIMITED_DIR:-$HOME/.claude/autonomy/limited}"
# TTL 10080 min = 7 days, and the number is not arbitrary: it is the SEVEN_DAY cap's own window.
# At the old 1440 a weekly cap's marker was GC'd four days before the cap expired, so the census
# lost the only record that the session was ever blocked while it was still blocked. A marker must
# outlive the fact it reports.
#
# CAP STAYS 500 (LIMIT_DETECT_100P § 11 #7, which AMENDS § 9 D3's 5000 and binds over it). The
# argument for 5000 was that one account capping kills ~30 sessions at once and a multi-fire sid
# re-caps repeatedly, so 500 lines is reachable inside one bad afternoon. Both halves are true and
# neither reaches the cap: the census groups PER SID at read time, so N re-caps of one session are
# one row however many lines they occupy, and 5000 is ≈350× the measured enumerate regime — a
# ceiling that far above the traffic is not a safety margin, it is an unbounded file with a number
# written next to it. The TTL argument does not transfer either, because the GC is keyed on FILE
# mtime (:197 below), so a busy account's marker never expires at ANY cap and a quiet one's is
# already covered by TTL 10080.
#
# WHAT A CAPPED FILE COSTS IS BOUNDED AND VISIBLE: cc-limited reports it in the footer and exits 6
# (DEGRADED), with the rows still printed. That is the designed disposition, not a failure — a
# capped file has stopped recording, which is exactly the fact the operator needs said out loud.
#
# AND THE PREDICTION THAT FALLS OUT OF PAIRING 500 WITH TTL 10080, stated now rather than
# discovered later: P1's "peak 271/day fleet-wide, never breached" was measured against the OLD
# 1440-minute TTL, where a file was pruned daily. At a 7-day TTL the GC is keyed on FILE mtime, so
# a busy account's marker is never pruned at all and simply accumulates — 271/day into one
# cause-keyed file reaches 500 in under two days. Expect DEGRADED to become the ORDINARY reading on
# a busy account, not an alarm. If that proves too noisy the lever is the TTL or a per-sid prune,
# never a higher ceiling: raising the cap buys silence by making the file unbounded again, which is
# the trade § 11 #7 refused.
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
       --arg cwd "$CWD" --arg tp "$TP" --arg event "$EVENT" --arg pane "$PANE" \
       --arg last "$(printf '%s' "$LAST" | cut -c1-200)" \
  '{ts:$ts,error:$err,account:$acct,config_dir:$cfg,session_id:$sid,cwd:$cwd,
    transcript_path:$tp,hook_event_name:$event,pane:$pane,last_assistant_message:$last}' \
  >> "$MARKER" 2>/dev/null || true

log_idl fired "marker-$([ "$FIRST" = yes ] && echo opened || echo appended)" \
  "$(jq -cn --arg p "$PANE" '{pane:$p}' 2>/dev/null || printf '{}')"
exit 0
