#!/bin/bash
# coldcompile-admit.sh — PreToolUse(Bash) hook. ADMISSION-SERIALISE COLD COMPILES, BOX-WIDE.
#
# Prepends `bin/cc-ignition-gate` as a SEPARATE STATEMENT to any agent command that would ignite a
# dev-toolchain cold compile:
#
#     cd X && (npx next dev … &) ; sleep 25   →   <gate> --class next-dev ; cd X && (npx next dev … &) ; sleep 25
#
# WHY (CONCURRENCY_PROGRAM.md §S6.5, the wave's non-optional crash fix; crash-rootcause-2026-08-09.md).
# Ignition in all six kernel panics is a dev-toolchain burst, never session count: 18→372 procs in
# 90 s, 700 procs / 38.9 GB, 736 / 44.7 GB. At the program's design point of 150 resident sessions
# the whole burst budget is ~19 GB against a measured 372-proc wave at ~23 GB, so there is no room
# for even ONE unbounded cold compile. The gate itself carries the mechanism and the measurements;
# this file is only the chokepoint that reaches it.
#
# WHY THE TOOL BOUNDARY IS THE CHOKEPOINT. The igniting binary is invoked from inside
# `node_modules/.bin` by a package-manager script, so a PATH shim never meets it (the hole
# hooks/qos-rewrite.sh already documents for absolute spellings, worse here). The one boundary every
# agent-issued command must cross is the Bash tool call — and unlike a launchd sampler it is an
# EVENT, so it cannot be starved by the load it exists to prevent (memory:
# enforcement-must-live-at-the-chokepoint).
#
# A SEPARATE STATEMENT, NOT A PREFIX — and this was measured, not assumed. A prefix wrapper
# (`cc-admit <cmd>`, the shape qos-rewrite.sh uses for taskpolicy and cc-cpubound) is only ever
# applied to a SINGLE SIMPLE command, because prefixing a compound is string surgery on a parse
# that is no longer ours. Over ~/.claude/logs/bash-commands.log{,.gz} (2026-07-19 → 08-09, 49,510
# agent Bash entries) **231 of the 232 entries that actually RUN an ignition tool are compound**.
# A prefix wrapper would have covered ONE of them. `gate ; <original>` does no surgery at all: it
# prepends a complete statement and a separator, so every spelling is covered by construction.
# `;` and not `&&`: a first line that is a comment turns `gate && # …` into an `&&` with no right
# operand — a syntax error — while `gate ; # …` is fine.
#
# DISJOINT FROM hooks/qos-rewrite.sh BY CONSTRUCTION, because the alternative is undetermined.
# Two PreToolUse hooks that BOTH emit `updatedInput` for one tool call have no documented
# resolution (checked against the 2.1.220 binary and the published hook docs, 2026-08-09: the
# binary carries a fallback string for an EMPTY updatedInput and nothing at all for two non-empty
# ones; order and chaining are undocumented). Depending on an undocumented merge to protect the box
# from a kernel panic is not a design. So this hook DECLINES anything qos-rewrite.sh could rewrite:
#
#   · any command carrying a `bats` token          — qos transform (a)'s exact trigger
#   · any SIMPLE command with no leading `VAR=`    — the only shape qos transforms (b)/(c) accept
#
# Measured cost of that rule on the same corpus: ZERO of the 232 ignition entries (the single
# SIMPLE one, `PW_BASE_URL=… pnpm design:gate`, carries a leading assignment, which qos-rewrite
# declines and this hook therefore keeps). tests/coldcompile-admit.bats asserts the disjointness by
# RUNNING BOTH SHIPPED HOOKS over a command corpus and requiring that at most one ever emits —
# an observation of the two artifacts, not a re-implementation of either one's rule.
#
# FAIL-OPEN IS THE HARD CONTRACT (the standing rule for every hook here). Every path exits 0. Every
# path that cannot be SURE prints NOTHING, and no output means the command runs verbatim, exactly as
# if this file did not exist. There is no partial-JSON path. The rewrite itself is checked before it
# is emitted: the gate is resolved and tested EXECUTABLE, because naming a gate that is not deployed
# would turn a working command into exit 127 — a bad rewrite costs the agent's command, while
# refusing to rewrite costs one ungated compile that the compressor sentinel still backstops.
#
# Seams (single-dash `${VAR-default}` where a set-but-EMPTY value must be honoured verbatim):
#   CC_COLDCOMPILE_ADMIT=off   → whole hook off, exit 0 before anything else (kill switch).
#   CC_COLDCOMPILE_PATTERNS=<path> → pin the ignition table; SET-BUT-EMPTY disables the hook.
#   CC_COLDCOMPILE_GATE=<path>     → pin the gate binary; SET-BUT-EMPTY disables the hook.
# The gate has its own independent kill switch (CC_IGNITION_GATE=off), so a rewritten command can
# still be made a no-op without touching this file or the registration.
#
# bash 3.2 SAFE: no `case` inside command substitution, no IFS-on-control-char splitting. Runs under
# /bin/bash as a hook.

# Kill switch is FIRST — before `set`, before stdin, before any resolution that could fail.
[ "${CC_COLDCOMPILE_ADMIT:-on}" = "off" ] && exit 0

set -uo pipefail

# ── read the payload, BOUNDED ─────────────────────────────────────────────────────────────────
# This runs on EVERY Bash call, so its own cost is a fleet-wide term. 200 KB is ~2 orders of
# magnitude above any real command line, and a command truncated at that bound simply fails the
# match and runs verbatim (fail-open, not fail-weird). Same bound as qos-rewrite.sh:107.
INPUT=$(head -c 200000) || exit 0
[ -n "$INPUT" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# ── idempotency ───────────────────────────────────────────────────────────────────────────────
# A command already naming the gate is already serialised; a second gate would double the wait for
# no benefit. (The gate is cheap on the clear path, but "cheap" is not "free" and this file exists
# to bound a burst, not to add ceremony.)
case "$CMD" in
  *cc-ignition-gate*) exit 0 ;;
esac

# ── DISJOINTNESS WITH qos-rewrite.sh — decline anything it could rewrite ──────────────────────
# See the header. These two tests are qos-rewrite.sh's own trigger and its own refusal, restated
# from the OTHER side so that at most one hook ever emits for a given command.

# (i) a `bats` token anywhere ⇒ qos transform (a) rewrites it. Same token pattern as
# qos-rewrite.sh:150-160 (word-anchored, optional ABSOLUTE directory prefix) so the two cannot
# disagree about what counts as a bats invocation.
printf '%s' "$CMD" \
  | grep -qE '(^|[[:space:]])(/[^[:space:]]*/)?bats([[:space:]]|$)' 2>/dev/null && exit 0

# (ii) a SIMPLE command with no leading assignment is the ONLY shape qos transforms (b)/(c) will
# prefix (qos-rewrite.sh:188-200). Anything with structure — which is 231 of 232 real ignition
# commands — is ours alone. The metacharacter list is qos-rewrite.sh's, character for character.
_simple=1
case "$CMD" in
  *';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'`'*|*$'\n'*) _simple=0 ;;
esac
if [ "$_simple" -eq 1 ]; then
  # A leading `VAR=value` is what makes qos DECLINE a simple command, so such a command is ours.
  printf '%s' "$CMD" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' 2>/dev/null || exit 0
fi

# ── resolve the CHECKOUT directory, THROUGH SYMLINKS FIRST ────────────────────────────────────
# ~/.claude/hooks/<name> is a per-file symlink into the checkout, so a naive dirname yields
# ~/.claude/hooks and `../config/...` resolves to a path that does not exist and never will — a
# symlinked directory does not acquire links for NEW files. Resolving $0 physically lands us in the
# CHECKOUT, where ../config/ and ../bin/ are real, which also makes this hook work the moment it
# lands instead of leaving a window where the table matches and nothing is gated.
# bash 3.2-safe: macOS has no `readlink -f`.
_self="${BASH_SOURCE[0]:-$0}"
_hops=0
while [ -L "$_self" ] && [ "$_hops" -lt 20 ]; do
  _d=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || break
  _self=$(readlink "$_self") || break
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
  _hops=$((_hops + 1))
done
_dir=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || _dir=""

# ── the ignition table: `<class><TAB><ERE>`, first match wins ─────────────────────────────────
if [ -n "${CC_COLDCOMPILE_PATTERNS+set}" ]; then
  TABLE="$CC_COLDCOMPILE_PATTERNS"      # set-but-EMPTY ⇒ hook OFF, honoured verbatim
else
  TABLE=""
  [ -n "$_dir" ] && TABLE="$_dir/../config/coldcompile.patterns"
fi
[ -n "$TABLE" ] && [ -r "$TABLE" ] || exit 0

CLASS=""
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}                                   # tolerate a CRLF table
  case "$line" in ''|'#'*) continue ;; esac
  _f1=${line%%$'\t'*}
  _ere=${line#*$'\t'}
  [ "$_f1" != "$line" ] || continue                    # no TAB on this line ⇒ malformed, skip
  [ -n "$_f1" ] && [ -n "$_ere" ] || continue
  if printf '%s' "$CMD" | grep -qE "$_ere" 2>/dev/null; then CLASS="$_f1"; break; fi
done < "$TABLE"
[ -n "$CLASS" ] || exit 0

# CLASS ALLOWLIST — the class is interpolated into the emitted command line, so a config file must
# not be able to inject a shell metacharacter into it. Same reasoning as qos-rewrite.sh's band and
# ceiling allowlists: a config file must not be able to break a tool call.
printf '%s' "$CLASS" | grep -qE '^[A-Za-z0-9-]+$' 2>/dev/null || exit 0

# ── resolve the gate and CHECK IT EXECUTABLE ──────────────────────────────────────────────────
if [ -n "${CC_COLDCOMPILE_GATE+set}" ]; then
  GATE="$CC_COLDCOMPILE_GATE"           # set-but-EMPTY ⇒ hook OFF, honoured verbatim
else
  GATE=""
  # Normalised (`cd -P`) rather than left as `hooks/../bin/…`: this string is EMITTED, so the agent
  # reads it in its own command line and in any error it reports.
  _bindir=$(cd -P "$_dir/../bin" 2>/dev/null && pwd) || _bindir=""
  [ -n "$_bindir" ] && GATE="$_bindir/cc-ignition-gate"
fi
[ -n "$GATE" ] && [ -x "$GATE" ] || exit 0

# ── emit ──────────────────────────────────────────────────────────────────────────────────────
# Built by jq --arg so escaping is jq's problem, never ours. Compact: one line, one object.
# Deliberately NO permissionDecision field — the rewrite applies on its own, and claiming a decision
# would take the permission flow over from the hooks that own it (qos-rewrite.sh:118-121).
jq -cn --arg c "$GATE --class $CLASS ; $CMD" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$c}}}' 2>/dev/null \
  || exit 0
exit 0
