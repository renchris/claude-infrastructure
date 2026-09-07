#!/bin/bash
# file-changed.sh — FileChanged observer: one greppable line per watched-file change.
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
  M="${2-}"
  if [ -z "$M" ]; then
    echo "file-changed: empty matcher — no filenames are watched, the hook can never fire" >&2
    exit 1
  fi
  RC=0
  # Alternation-separated, per the binary's own example ".envrc|.env". Every element must be a
  # filename in the current directory; one bad element is enough to make that element dead.
  OLDIFS="$IFS"; IFS='|'
  for ELEM in $M; do
    case "$ELEM" in
      /*)
        # MEASURED, not derived: three simultaneous registrations in ONE 2.1.220 run, absolute
        # `/private/tmp/hs/fc/abs.txt` → 0 rows while `*` → 3 rows saw that same file change.
        echo "file-changed: '$ELEM' is an absolute path — measured to match 0 changes (silent no-op); the matcher takes filenames in cwd" >&2
        RC=1
        ;;
      */*)
        # DERIVED from the binary's description ("filenames to watch in the current directory"),
        # not measured. Stated as derived so a future reader does not inherit it as a measurement.
        echo "file-changed: '$ELEM' contains a path separator — the matcher takes filenames in cwd, so this is expected never to match (derived from the binary's description, not measured)" >&2
        RC=1
        ;;
    esac
  done
  IFS="$OLDIFS"
  if [ "$RC" -ne 0 ]; then
    echo "file-changed: to watch a path outside cwd, emit hookSpecificOutput.watchPaths from the hook instead (see $WATCHLIST)" >&2
  fi
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
FIELDS=$(printf '%s' "$INPUT" | jq -er '@sh "FILE_PATH=\(.file_path // "") EVENT=\(.event // "") SID=\(.session_id // "-") CWD=\(.cwd // "-")"' 2>/dev/null) || exit 0
eval "$FIELDS"

# `file_path` is the whole payload's point. Without it there is nothing to record, and writing a
# row with an empty subject would pollute the log with lines no later query can attribute.
[ -n "${FILE_PATH:-}" ] || exit 0
[ -n "${EVENT:-}" ] || EVENT="unknown"
[ -n "${SID:-}" ] || SID="-"
[ -n "${CWD:-}" ] || CWD="-"

TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Every write is guarded. A read-only HOME, a full disk or a directory someone chmod'd must not
# turn a file save into a visible hook failure.
if mkdir -p "$LOG_DIR" 2>/dev/null; then
  printf '%s\t%s\t%s\t%s\t%s\n' "$TS" "$SID" "$EVENT" "$FILE_PATH" "$CWD" >> "$LOG" 2>/dev/null || true
fi

# Dynamic watch list — the only supported way to watch a path outside cwd. Emitted ONLY when the
# operator has created the file, so the default posture is silent observation. Absolute paths only:
# a relative entry here would re-create the cwd dependency this exists to escape, so they are
# dropped rather than passed through, and a list that reduces to nothing prints nothing at all.
if [ -s "$WATCHLIST" ]; then
  PATHS=$(grep -v '^[[:space:]]*#' "$WATCHLIST" 2>/dev/null | grep '^/' | jq -Rn '[inputs | select(length > 0)]' 2>/dev/null) || PATHS=""
  if [ -n "$PATHS" ] && [ "$PATHS" != "[]" ]; then
    printf '%s' "$PATHS" | jq -c '{hookSpecificOutput:{hookEventName:"FileChanged",watchPaths:.}}' 2>/dev/null || true
  fi
fi

exit 0
