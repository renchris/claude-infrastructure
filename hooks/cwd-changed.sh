#!/bin/bash
# cwd-changed.sh — § 3e PART 3: the re-arm that keeps FileChanged's dynamic watch list alive across
# a `cd`, and the RECEIPT that makes the re-arm observable (HOOK_SURFACE_100P § 3 row 30, W3-E).
#
# WHY THIS FILE EXISTS AT ALL, stated so nobody deletes it as a duplicate of file-changed.sh.
# `FileChanged` has TWO different mechanisms and the naive reading collapses them (§ 3e, measured):
#   · ARMING   — the watcher resolves `isAbsolute(x)?x:join(cwd,x)`. An ABSOLUTE matcher arms
#                durably and survives a `cd`; a RELATIVE one silently re-bases onto the new cwd.
#   · DISPATCH — the matcher is regex-tested against `basename(file_path)` (220:430421), so an
#                absolute path can never match and never runs the hook.
# So the correct wiring is a PAIR — an absolute matcher to ARM, a `*` sibling to DISPATCH — PLUS a
# third part, and this file is that third part: `onCwdChanged` (`HJ1()`/`Sx_()`, 114:135528 and
# 220:171001+) OVERWRITES the dynamic watch list WHOLESALE with whatever the CwdChanged hooks
# return (`r = A.watchPaths`). With no CwdChanged registration that list becomes EMPTY on the first
# `cd`, and every dynamically-armed path is lost SILENTLY. Measured: after a `cd`, a `probe3.txt`
# matcher fired for a DIFFERENT file of that name while the originally-armed `dyn.txt` produced
# zero rows.
#
# 🚨 THE RECEIPT IS THE POINT, AND IT IS WHAT MAKES THIS MORE THAN A SECOND EMITTER.
# `hooks/file-changed.sh` already re-emits `watchPaths` on a CwdChanged payload (fixed 2026-09-07;
# before that its `file_path` guard sat ABOVE the emit and it returned EMPTY stdout on exactly the
# event it was registered for). But it deliberately writes NO log row for a CwdChanged payload —
# that payload names no file, so a row could attribute nothing. The consequence is that a re-arm
# leaves NO TRACE, and § 3e-FINDING is precisely the failure class of a registered no-op that reads
# GREEN: every sensor a registration has — the command string is present, the file is executable,
# it exits 0 — is satisfied by a hook that does nothing. This handler writes ONE row per transition
# carrying the COUNT of paths it re-armed, so "the CwdChanged registration fired and carried
# nothing" is distinguishable from "the CwdChanged registration never fired". Without that row the
# two are the same observation, and the second is the bug the first is supposed to prevent.
# It therefore logs on EVERY valid transition, including the count-0 case — a receipt that only
# appeared when the feature was already working could not witness the failure it exists for.
#
# 🚨 ONE WATCHLIST, ONE SSOT. This handler reads the SAME file and the SAME env seam as
# `hooks/file-changed.sh` — `CC_FILECHANGED_WATCHLIST`, default `$HOME/.claude/file-watch-paths`.
# Two hooks reading two different watchlists would be a second SSOT and it would drift. The two
# readers are separate code, so the anti-drift guarantee is made MECHANICAL rather than structural:
# `tests/cwd-changed.bats` carries an agreement arm that feeds ONE watchlist to BOTH handlers and
# requires the emitted `watchPaths` arrays to be IDENTICAL. That arm goes red the day either reader
# changes without the other (memory: sibling-auditors-must-share-the-state-model).
#
# MEASURED PAYLOAD (§ 3e, the W3-E brief):
#   {cwd, hook_event_name:"CwdChanged", new_cwd, old_cwd, session_id, transcript_path}
# `old_cwd` is read with `.cwd` as the fallback: `cwd` is present on every hook payload the harness
# builds, `old_cwd` is this event's own field, and a row that silently recorded the destination as
# the origin would invert the transition it is the only record of.
#
# ⚠️ THE REVERT PATH, and the over-generalisation that did not survive. § 3e's inherited hazard
# "new_cwd can permanently misname the session's directory" is CONDITIONAL on the REVERT path — an
# out-of-scope `cd`. An in-scope `cd` into a strict subdirectory was measured with no revert at all
# and an accurate `new_cwd`. This handler is safe under BOTH because it never uses `new_cwd` for
# anything but the log row: the emitted paths are the watchlist's own ABSOLUTE entries, re-emitted
# verbatim, never re-based onto any cwd. Re-basing is the defect this event exists to escape, so a
# relative entry is DROPPED rather than resolved — resolving it would re-create the cwd dependency.
#
# FAILS OPEN, ALWAYS. No `set -e`. Empty stdin, malformed JSON, absent jq, a wrong event name, an
# unreadable watchlist, an unwritable log — every path exits 0. A hook on the CwdChanged path that
# died noisily would make a `cd` look broken; a hook that emitted a stray byte would hand the
# harness a malformed `watchPaths` and could corrupt the very list it exists to preserve.
#
# Env seams (tests): CC_FILECHANGED_WATCHLIST · CC_CWDCHANGED_LOG_DIR · CC_CWDCHANGED_MAX_BYTES
# Kill switch: CC_CWD_CHANGED_DISABLED=1
set -uo pipefail

[ "${CC_CWD_CHANGED_DISABLED:-0}" = "1" ] && exit 0

WATCHLIST="${CC_FILECHANGED_WATCHLIST:-$HOME/.claude/file-watch-paths}"
LOG_DIR="${CC_CWDCHANGED_LOG_DIR:-$HOME/.claude/logs}"
LOG="$LOG_DIR/cwd-changed.log"
MAX_BYTES="${CC_CWDCHANGED_MAX_BYTES:-1048576}"
case "$MAX_BYTES" in ''|*[!0-9]*) MAX_BYTES=1048576 ;; esac

# Builtin read, not `$(cat)`: no fork, no exec (hooks/log-bash.sh carries the ~6 ms measurement).
# `read -d ''` returns non-zero at EOF, which is the normal case, hence the `|| true`.
IFS= read -r -d '' INPUT || true
[ -n "$INPUT" ] || exit 0

# NO `command -v jq` GUARD, DELIBERATELY — and the empty-stdin guard above IS kept, which is not
# an inconsistency. Neither is observable: without jq the call below is a not-found whose stderr is
# already redirected, and on empty stdin jq yields nothing; both leave `FIELDS` empty and exit 0
# having emitted and written nothing. Two mechanisms producing one outcome means no mutant can make
# either matter (plan § 2, W3-D: "with no writer to stdout it is un-falsifiable"). What separates
# them is COST, which is the only thing left once behaviour is identical: the empty-stdin guard
# avoids spawning a real jq process on a path that runs at every `cd`, while the jq guard would
# avoid only a failed exec. So the free one goes and the one that buys something stays — recorded
# in the red-proof table as SHADOWED rather than left to look like an untested site.

# THE EVENT GATE. It is what makes a mis-registration INERT: this handler pointed at FileChanged —
# the sibling event it is wired beside, and therefore the realistic mis-registration — must not
# re-emit a watch list on a per-file-save cadence, and must not write a transition row for a
# payload that carries no transition.
#
# `@sh` + `eval`, never `@tsv` + `read`: a tab IS an IFS whitespace character, so `read` collapses
# runs of it and strips leading ones — an absent field shifts every later field LEFT and mints a
# wrong verdict (memory: ifs-whitespace-collapses-empty-fields; measured on hooks/file-changed.sh).
FIELDS="$(printf '%s' "$INPUT" | jq -er '
  select(.hook_event_name == "CwdChanged")
  | @sh "SID=\(.session_id // "-") OLD=\(.old_cwd // .cwd // "-") NEW=\(.new_cwd // "-") EV=\(.hook_event_name)"
' 2>/dev/null)" || FIELDS=""
[ -n "$FIELDS" ] || exit 0
eval "$FIELDS"
SID="${SID:--}"; OLD="${OLD:--}"; NEW="${NEW:--}"; EV="${EV:-CwdChanged}"

# ── THE RE-ARM LIST ──────────────────────────────────────────────────────────────────────────────
# Absolute paths only. `watchPaths` is documented by the binary as "array of absolute paths", and a
# relative entry would be resolved against whatever cwd the harness happens to hold — which is the
# exact dependency this event exists to escape. Dropped, never resolved.
# The comment strip is SHADOWED by the absolute filter beside it — every comment shape it removes
# (`# x`, `   # x`, `#/Users/x`) also fails `^/`, so no mutant can redden it. It is kept for
# TEXTUAL parity with the same pipeline in hooks/file-changed.sh: the two readers must stay
# diff-able by eye, and the agreement arm pins only their OUTPUT.
PATHS=""
if [ -s "$WATCHLIST" ]; then
  PATHS="$(grep -v '^[[:space:]]*#' "$WATCHLIST" 2>/dev/null | grep '^/' | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null)" || PATHS=""
fi
# NORMALISE THE EMPTY CASE EXPLICITLY. `pipefail` is set, so a `grep` that matches nothing fails the
# whole pipeline and leaves PATHS empty rather than `[]` — which meant the "print nothing, not an
# empty array" contract was being held by a PIPELINE EXIT STATUS rather than by the guard written to
# hold it, and a mutant of that guard could not redden anything (memory:
# grep-q-under-pipefail-inverts-the-verdict, the same mechanism in its benign direction). Pinning
# PATHS to a real empty array puts the contract back where it is readable and testable.
case "$PATHS" in '') PATHS='[]' ;; esac
N="$(printf '%s' "$PATHS" | jq -r 'length' 2>/dev/null)" || N=0
case "$N" in ''|*[!0-9]*) N=0 ;; esac

# ── THE RECEIPT — one row per transition, count included, written BEFORE the emit ───────────────
# Written unconditionally on a valid transition (see the header): the count-0 row is the one that
# witnesses "the registration fired and the list it rebuilt was empty", which is the § 3e failure.
if mkdir -p "$LOG_DIR" 2>/dev/null; then
  SIZE="$(stat -f%z "$LOG" 2>/dev/null || stat -c%s "$LOG" 2>/dev/null || echo 0)"
  case "$SIZE" in ''|*[!0-9]*) SIZE=0 ;; esac
  if [ "$SIZE" -ge "$MAX_BYTES" ]; then mv -f "$LOG" "$LOG.1" 2>/dev/null || true; fi
  TS="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || echo '?')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$TS" "$SID" "$OLD" "$NEW" "$N" >> "$LOG" 2>/dev/null || true
fi

# ── THE EMIT — § 3e part 3 proper ────────────────────────────────────────────────────────────────
# `hookEventName` names the event BEING HANDLED, read from the payload rather than hard-coded: a
# constant would label the re-arm with an event that did not fire it — a claim no reader could
# falsify and the harness has no reason to honour.
#
# A list that reduces to nothing prints NOTHING rather than an empty array. The two are equivalent
# to `onCwdChanged` (it takes what the hooks return, so nothing and `[]` both leave the list empty),
# and printing nothing keeps the default posture — no watchlist file — a pure silent observer,
# byte-for-byte matching what hooks/file-changed.sh does with the same input.
if [ "$N" -gt 0 ]; then
  printf '%s' "$PATHS" | jq -c --arg e "$EV" '{hookSpecificOutput:{hookEventName:$e,watchPaths:.}}' 2>/dev/null || true
fi

exit 0
