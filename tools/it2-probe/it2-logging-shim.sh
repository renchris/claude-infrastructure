#!/bin/bash
# it2-logging-shim.sh — a transparent `it2` that RECORDS the contract before delegating.
#
# WHY THIS EXISTS. docs/plans/TERMINAL_AGNOSTIC_L3_L4.md D5 makes the `it2` facade the mechanism by
# which Agent-Team panes work on ANY terminal: Claude Code shells out to an EXTERNAL `it2` CLI and
# ships 0 KittyBackend / 0 GhosttyBackend, so a faithful `it2` is the whole port. §4.3 lists the
# exact contract surface as OPEN — "reversed only partially". A facade built against a GUESSED
# contract fails in the one place that matters (a live teammate spawn), so the contract is captured
# from the real caller rather than inferred.
#
# Static reversing of claude.exe gives the argv shapes but CANNOT answer: which of the two send
# verbs is used (`send` has no newline, `run` appends \r), whether `--json` is passed to
# `session list`, the exact flag ORDER, or whether anything arrives on stdin. Those are precisely
# the details a facade gets wrong. This shim answers them by observation.
#
# TRANSPARENCY IS THE WHOLE REQUIREMENT. If the shim perturbs behaviour it has measured its own
# artefact rather than the subject. So it: preserves argv exactly, preserves stdin, preserves
# stdout and stderr AS SEPARATE STREAMS, and preserves the exit code. It delegates to the FLEET
# WRAPPER (~/.claude/bin/it2), not to the raw CLI, because the wrapper is what production actually
# runs — measuring the raw CLI would capture a path no caller takes.
#
# `monitor` streams by design and is passed through UNBUFFERED and unrecorded past its argv line;
# buffering it to log the body would hang the caller forever. That exemption is the same one the
# production wrapper makes, for the same reason.
#
# SAFETY: read-only with respect to iTerm2. It creates nothing, closes nothing, and sends no input
# of its own — every effect is the delegate's, which is what would have happened without the shim.
#
# USAGE
#   export IT2_PROBE_LOG=/path/to/probe.log
#   PATH="$(dirname this-shim-as-'it2'):$PATH" <the process under test>
# The shim must be installed under the NAME `it2` in a directory placed EARLIER on PATH than
# ~/.claude/bin, or the caller resolves the wrapper directly and the shim never runs.
set -uo pipefail

LOG="${IT2_PROBE_LOG:-${TMPDIR:-/tmp}/it2-probe.log}"

# Resolve the delegate. Deliberately NOT `command -v it2`: this shim IS named it2 and is earlier on
# PATH, so a PATH lookup would find ITSELF and fork-bomb. The delegate is therefore an explicit
# path, and the shim refuses to run rather than recurse if it cannot find one that is not itself.
# (memory self-identity-guard-must-fully-resolve: "cannot resolve" is a THIRD state, never "not me".)
SELF_REAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/$(basename "${BASH_SOURCE[0]}")"
DELEGATE="${IT2_PROBE_DELEGATE:-$HOME/.claude/bin/it2}"
if [ ! -x "$DELEGATE" ]; then
  echo "it2-shim: delegate not executable: $DELEGATE" >&2; exit 127
fi
DELEGATE_REAL="$(cd "$(dirname "$DELEGATE")" && pwd -P)/$(basename "$DELEGATE")"
while [ -L "$DELEGATE_REAL" ]; do
  _l="$(readlink "$DELEGATE_REAL")"
  case "$_l" in
    /*) DELEGATE_REAL="$_l" ;;
    *)  DELEGATE_REAL="$(cd "$(dirname "$DELEGATE_REAL")" && pwd -P)/$_l" ;;
  esac
done
if [ "$DELEGATE_REAL" = "$SELF_REAL" ]; then
  echo "it2-shim: REFUSED — delegate resolves to this shim; that is an exec loop, not a probe" >&2
  exit 127
fi

TS="$(date -u +%FT%T.%3NZ 2>/dev/null || date -u +%FT%TZ)"
PPID_COMM="$(ps -o comm= -p "$PPID" 2>/dev/null | tr -d '\n')"

# argv is recorded ONE ARGUMENT PER LINE, %q-quoted. A single joined line is ambiguous exactly where
# the contract matters: a command containing a space is indistinguishable from two arguments, and
# the facade has to know which it was (memory json-quoting-is-not-shell-quoting).
{
  printf '=== %s pid=%s ppid=%s(%s) cwd=%s\n' "$TS" "$$" "$PPID" "${PPID_COMM:-?}" "$PWD"
  printf 'argc=%s\n' "$#"
  i=0
  for a in "$@"; do printf 'argv[%s]=%q\n' "$i" "$a"; i=$((i+1)); done
} >> "$LOG" 2>/dev/null

# `monitor` streams — never buffer it.
if [ "${1:-}" = "monitor" ]; then
  printf 'stdin=<streaming, not captured>\nDELEGATED(monitor, unbuffered)\n\n' >> "$LOG" 2>/dev/null
  exec "$DELEGATE" "$@"
fi

# stdin: capture ONLY if it is not a tty, and bound it. An unbounded read here would hang any
# caller that leaves stdin open without writing — which is most of them.
STDIN_F="$(mktemp "${TMPDIR:-/tmp}/it2probe-stdin.XXXXXX")"
if [ ! -t 0 ]; then
  head -c 65536 > "$STDIN_F" 2>/dev/null || true
fi
if [ -s "$STDIN_F" ]; then
  { printf 'stdin<<EOF\n'; cat "$STDIN_F"; printf '\nEOF\n'; } >> "$LOG" 2>/dev/null
else
  printf 'stdin=<empty>\n' >> "$LOG" 2>/dev/null
fi

OUT_F="$(mktemp "${TMPDIR:-/tmp}/it2probe-out.XXXXXX")"
ERR_F="$(mktemp "${TMPDIR:-/tmp}/it2probe-err.XXXXXX")"
rc=0
"$DELEGATE" "$@" < "$STDIN_F" > "$OUT_F" 2> "$ERR_F" || rc=$?

{
  printf 'rc=%s\n' "$rc"
  printf 'stdout<<EOF\n'; cat "$OUT_F"; printf 'EOF\n'
  if [ -s "$ERR_F" ]; then printf 'stderr<<EOF\n'; cat "$ERR_F"; printf 'EOF\n'; fi
  printf '\n'
} >> "$LOG" 2>/dev/null

# Re-emit on the ORIGINAL streams. Collapsing stderr into stdout here would corrupt exactly the
# parse the caller performs on split output.
cat "$OUT_F"
cat "$ERR_F" >&2
rm -f "$STDIN_F" "$OUT_F" "$ERR_F"
exit "$rc"
