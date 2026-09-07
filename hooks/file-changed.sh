#!/bin/bash
# file-changed.sh — the handler for BOTH halves of the § 3e wiring: a FileChanged observer that
# writes one greppable line per watched-file change, AND the CwdChanged RE-ARM that keeps the
# dynamic watch list alive across a `cd`. Registered on both events by
# migrations/0017-filechanged-cwdchanged-registration.sh; which job it does on a given invocation
# is decided by the payload's own `hook_event_name`, never assumed.
#
# WHAT THE HARNESS SENDS (measured 2026-09-05 on 2.1.220, /tmp/hs/log/fs2-*.tsv, and confirmed
# against the binary's own hook metadata registry):
#   {session_id, transcript_path, cwd, prompt_id, hook_event_name:"FileChanged",
#    file_path (ABSOLUTE, already resolved), event}
# The binary documents `event` as one of change | add | unlink. Only `change` was observed in the
# W1 probe, so the other two are handled but not proven — this script must not assume `change`.
#
# 🚨 THE PRECONDITION THAT DECIDES WHETHER THIS SCRIPT EVER RUNS AT ALL, and it is a property of
# the REGISTRATION, not of this file. From the binary's own description string for this event:
#
#     "The matcher field specifies filenames to watch in the current directory (e.g. \".envrc|.env\")."
#
# So the matcher is a FILENAME IN CWD, alternation-separated — not a path. An ABSOLUTE path in the
# matcher does not error and does not warn; it simply never matches, and the hook is a silent
# no-op. Measured by a three-way A/B in ONE run (HOOK_SURFACE_100P § 3a rows 28/29): absolute
# `/private/tmp/hs/fc/abs.txt` → 0 rows, `*` → 3 rows, bare `probe.txt` → 1 row. The `*` arm saw
# abs.txt change, so the file was genuinely being written — the absolute matcher alone was blind.
# tests/file-changed.bats pins that negative arm; it is the only arm that can see this bug.
#
# 🚨 BUT THAT MEASUREMENT IS ABOUT **DISPATCH ONLY**, AND § 3e OF THE PLAN CORRECTS THE ADVICE THIS
# SCRIPT ORIGINALLY DERIVED FROM IT. Arming and dispatch are two different mechanisms, and 0 rows
# can only ever observe the second:
#   · ARMING   — the watcher resolves `isAbsolute(x)?x:join(cwd,x)`, so an ABSOLUTE matcher arms
#                durably and SURVIVES a `cd`; a relative one silently re-bases onto the new cwd.
#   · DISPATCH — the matcher is regex-tested against `basename(n.file_path)` (corroborated at
#                220:430421), so an absolute path can never match and never runs the hook.
# So the correct wiring is a PAIR: an absolute matcher to ARM, a `*` sibling to DISPATCH, and a
# `CwdChanged` hook re-emitting `watchPaths` (its handler OVERWRITES the dynamic list wholesale, so
# with no CwdChanged registration the list is empty after the first `cd`). A bare basename alone is
# the actively dangerous case — it keeps firing, for a DIFFERENT file.
# `--check-matcher` therefore judges by ROLE and refuses to reject a correct arming registration:
# an unconditional absolute-path refusal would block the very wiring § 3e prescribes.
#
# 🚨 SECOND CONSEQUENCE OF "in the current directory": the watch list is resolved RELATIVE TO CWD,
# so a `cd` silently disarms it. `CwdChanged` is the only re-arm point, which is why that event is
# a keep rather than a drop (§ 3, disposition change). A handler must never assume a stable arm
# across a directory change.
#
# THE SUPPORTED ROUTE TO AN ABSOLUTE PATH is not the matcher — it is this hook's own output. The
# same binary description continues:
#
#     "Hook output can include hookSpecificOutput.watchPaths (array of absolute paths) to
#      dynamically update the watch list."
#
# That is why WATCHLIST below exists. It stays OFF unless the operator creates the file, so this
# script is a pure observer by default and cannot surprise the registration the desk composes.
#
# 🚨 AND THAT EMIT MUST BE REACHABLE ON A CwdChanged PAYLOAD, WHICH UNTIL 2026-09-07 IT WAS NOT.
# `onCwdChanged` overwrites the dynamic list wholesale with whatever the CwdChanged hooks return,
# so the re-emit below IS § 3e's part 3. A CwdChanged payload carries no `file_path`, and the
# file_path guard used to be an early `exit 0` sitting ABOVE the emit — so this script returned
# EMPTY stdout on exactly the event it was meant to re-arm on, while the FileChanged arm looked
# healthy. Measured on both arms with CC_FILECHANGED_WATCHLIST set. The guard is now scoped to the
# LOGGING path alone: a CwdChanged payload still writes no row (nothing to attribute it to) but it
# does re-arm. tests/file-changed.bats pins both directions.
#
# FAILS OPEN, ALWAYS. Missing args, empty stdin, malformed JSON, an unwritable log — every path
# exits 0 with nothing on stdout. An observer that can break its host is not an observer, and the
# fleet has already paid for that lesson once on WorktreeCreate (§ 3a, the core.bare incident).

set -u

LOG_DIR="${CC_FILECHANGED_LOG_DIR:-$HOME/.claude/logs}"
LOG="$LOG_DIR/file-changed.log"
WATCHLIST="${CC_FILECHANGED_WATCHLIST:-$HOME/.claude/file-watch-paths}"

# ── `--check-matcher <matcher>` ────────────────────────────────────────────────────────────────
# The silent no-op above is a property of the REGISTRATION, not of this script, so no runtime
# behaviour of this hook can ever detect it — by the time the hook would notice, it has already
# failed to be called. The only place the bug is catchable is the moment the matcher is written.
# This mode is that check, kept here rather than in a new file so the rule and the payload reader
# cannot drift apart, and so whoever composes the registration has the predicate in the same file
# as the evidence for it.
#
# Exit 0 = this matcher can fire. Exit 1 = it is a shape measured or documented never to fire,
# with the reason on stderr. Only the exact literal `--check-matcher` takes this path; any other
# argument falls through to the observer, which must stay fail-open whatever it is handed.
if [ "${1:-}" = "--check-matcher" ]; then
  M=""; ROLE="dispatch"
  shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --role) ROLE="${2-}"; shift 2 || shift ;;
      *)      [ -n "$M" ] || M="$1"; shift ;;
    esac
  done

  if [ -z "$M" ]; then
    echo "file-changed: empty matcher — nothing is named, so this registration decides nothing" >&2
    exit 1
  fi

  RC=0
  # 🚨 `set -f` IS LOad-BEARING, and its absence made the `*` case a VACUOUS PASS. Splitting $M on
  # `|` requires it UNQUOTED, and an unquoted expansion is also subject to PATHNAME expansion — so
  # the single most important matcher this checker judges, `*`, globbed to the caller's cwd and the
  # loop then judged 36 filenames instead. It still exited 0, because bare basenames are accepted,
  # so the check passed for entirely the wrong reason and could never have rejected a bad `*`.
  # Caught 2026-09-07 by migrations/0017 asserting its own dispatch matcher and printing 36 NOTICE
  # lines naming this repo's files. `set +f` is restored with IFS below.
  set -f
  OLDIFS="$IFS"; IFS='|'
  for ELEM in $M; do
    case "$ROLE:$ELEM" in
      arm:/*)
        : ;;                                   # correct: an absolute path arms durably across a cd
      arm:*)
        echo "file-changed: '$ELEM' is RELATIVE, so it re-bases onto the new cwd on the first cd and stops watching the file it was wired for — an arming matcher must be absolute (§ 3e)" >&2
        RC=1 ;;
      dispatch:/*)
        echo "file-changed: '$ELEM' is an absolute path — it will never DISPATCH (the matcher is tested against basename(file_path), measured 0 rows against '*''s 3). This is correct ONLY as the § 3e ARMING half; pair it with a '*' registration to dispatch and a CwdChanged hook re-emitting watchPaths, or this hook never runs" >&2
        RC=1 ;;
      dispatch:*/*)
        echo "file-changed: '$ELEM' contains a path separator but is not absolute — it can neither arm durably nor match a basename, so it is dead in both roles" >&2
        RC=1 ;;
      dispatch:'*')
        : ;;                                   # the dispatch half of the pair
      dispatch:*)
        echo "file-changed: NOTICE '$ELEM' is a bare basename — it dispatches, but a cd RE-BASES it onto the new cwd, so it silently starts matching a same-named file elsewhere (§ 3e, measured). Prefer the pair: an absolute arm + a '*' dispatch + a CwdChanged re-arm" >&2 ;;
    esac
  done
  IFS="$OLDIFS"; set +f
  exit "$RC"
fi

# Builtin read, not `$(cat)`: no fork, no exec, and it preserves the trailing newline that command
# substitution strips (hooks/log-bash.sh carries the measurement — ~6 ms per hook on the hot path).
# `read -d ''` returns non-zero at EOF, which is the normal case, hence the `|| true`.
IFS= read -r -d '' INPUT || true
while [ "${INPUT%$'\n'}" != "${INPUT}" ]; do INPUT="${INPUT%$'\n'}"; done

# Empty stdin is a legitimate way to be invoked (a smoke test, a hand call). Not an error.
[ -n "$INPUT" ] || exit 0

# One jq pass, and `-e` so malformed JSON is DETECTED rather than silently yielding empty strings.
# A parse failure is a verdict, not noise — but the verdict for an observer is "say nothing and get
# out of the way", never a nonzero exit that the harness would surface to the user as stderr.
#
# 🚨 `@sh` + `eval`, NOT `@tsv` + `read -d $'\t'`. The first draft of this script used the TSV form
# and it was WRONG in the exact way memory `ifs-whitespace-collapses-empty-fields` records: a tab
# IS an IFS whitespace character, so `read` collapses runs of it and strips leading ones. A payload
# with no `file_path` therefore produced a LEADING empty field that vanished, every later field
# shifted LEFT, and the guard below read `EVENT` as the filename — logging a row that claimed a
# file named "change" instead of skipping the payload. Caught by this suite's own no-file_path arm
# on the first green run; the arm is kept precisely because it is the only thing that sees it.
# `@sh` emits properly single-quoted assignments, so an empty value stays an empty value.
FIELDS=$(printf '%s' "$INPUT" | jq -er '@sh "FILE_PATH=\(.file_path // "") EVENT=\(.event // "") SID=\(.session_id // "-") CWD=\(.cwd // "-") HOOK_EVENT=\(.hook_event_name // "")"' 2>/dev/null) || exit 0
eval "$FIELDS"

# The event this invocation is actually handling. It is read from the payload rather than assumed,
# because this script is registered on TWO events (§ 3e) and the answer decides what it emits.
# Absent ⇒ FileChanged: the only callers without one are hand tests and smoke calls, and that is
# the shape every fixture in tests/file-changed.bats predating the CwdChanged arm carries.
[ -n "${HOOK_EVENT:-}" ] || HOOK_EVENT="FileChanged"

# ── LOGGING — file_path-gated, and ONLY the logging ──────────────────────────────────────────────
# `file_path` is the whole LOG ROW's point. Without it there is nothing to record, and writing a
# row with an empty subject would pollute the log with lines no later query can attribute. So a
# CwdChanged payload — which carries no file_path — must still write no row.
#
# 🚨 THIS GUARD USED TO BE AN `exit 0`, AND THAT MADE § 3e's PART 3 UNIMPLEMENTED. The re-arm
# emit below is the whole reason this hook is registered on CwdChanged at all: `onCwdChanged`
# OVERWRITES the dynamic watch list wholesale with whatever the CwdChanged hooks return, so with
# no re-emit the list is EMPTY after the first `cd` and every dynamically-armed path is lost
# silently. A CwdChanged payload has no file_path, so the early exit fired FIRST and this script
# emitted nothing — measured on both arms 2026-09-07 with CC_FILECHANGED_WATCHLIST set:
#   CwdChanged  → stdout EMPTY (cannot re-arm)     FileChanged → {"hookSpecificOutput":{…}}
# The registration would have read GREEN over a hook that could not do the one job it was wired
# for. Narrowing the guard to the logging path is the fix; the emit is now reachable for EVERY
# payload, which is exactly what makes the pair in 0017 a working wiring rather than a present one.
if [ -n "${FILE_PATH:-}" ]; then
  [ -n "${EVENT:-}" ] || EVENT="unknown"
  [ -n "${SID:-}" ] || SID="-"
  [ -n "${CWD:-}" ] || CWD="-"

  TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # Every write is guarded. A read-only HOME, a full disk or a directory someone chmod'd must not
  # turn a file save into a visible hook failure.
  if mkdir -p "$LOG_DIR" 2>/dev/null; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$TS" "$SID" "$EVENT" "$FILE_PATH" "$CWD" >> "$LOG" 2>/dev/null || true
  fi
fi

# ── THE RE-ARM — reachable for every payload, FileChanged and CwdChanged alike ───────────────────
# Dynamic watch list — the only supported way to watch a path outside cwd. Emitted ONLY when the
# operator has created the file, so the default posture is silent observation. Absolute paths only:
# a relative entry here would re-create the cwd dependency this exists to escape, so they are
# dropped rather than passed through, and a list that reduces to nothing prints nothing at all.
#
# `hookEventName` names the event BEING HANDLED, not a constant. It was hard-coded "FileChanged",
# which on the CwdChanged registration would have labelled the re-arm with an event that did not
# fire it — a payload the harness has no reason to honour, and a claim no reader could falsify.
if [ -s "$WATCHLIST" ]; then
  PATHS=$(grep -v '^[[:space:]]*#' "$WATCHLIST" 2>/dev/null | grep '^/' | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null) || PATHS=""
  if [ -n "$PATHS" ] && [ "$PATHS" != "[]" ]; then
    printf '%s' "$PATHS" | jq -c --arg e "$HOOK_EVENT" '{hookSpecificOutput:{hookEventName:$e,watchPaths:.}}' 2>/dev/null || true
  fi
fi

exit 0
