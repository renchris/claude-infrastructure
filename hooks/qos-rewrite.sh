#!/bin/bash
# qos-rewrite.sh — PreToolUse(Bash) hook. THE QoS CHOKEPOINT, MOVED TO THE TOOL BOUNDARY.
#
# WHY THIS EXISTS (MACHINE_CAPACITY_V2.md §11.3 M7). bin/cc-bats already moved demotion from the
# CALLER to the TOOL — measured to be the right inversion. But a PATH shim only covers invocations
# that go through PATH, and two holes survived it (§11.2 live axis, 2026-07-29/30):
#
#   1. THE ABSOLUTE-PATH SPELLING. `timeout 90 /opt/homebrew/bin/bats t.bats` never consults PATH,
#      so it never meets the shim. qos-census sat at a ~69.4%-proc coverage CEILING for exactly
#      this reason — the residual is not carelessness, it is a spelling the mechanism cannot see.
#   2. EVERYTHING THAT IS NOT bats — the LARGER live term. Whole-box truth: 3.1% of CPU demoted.
#      `uv run pytest -m load` 0.67 cores at PRI 31 · a recurring `du -sh` at PRI 46 (BOOSTED
#      ABOVE default) · `npm install` 15.6% · `shellcheck` at 458 MB. One shim per tool is N shims,
#      each with its own PATH-ordering failure mode.
#
# THE INVERSION: there is exactly one boundary every agent-issued command must cross that no
# spelling can route around — the Bash TOOL call itself. A PreToolUse hook emitting `updatedInput`
# rewrites the command that actually executes. Confirmed empirically on live 2.1.219 in BOTH
# decision modes (§11.2 probe row); this file ships the NO-decision form, so the permission flow is
# untouched and every existing Bash hook still sees what it saw before.
#
# The operator's own terminal does NOT pass through this hook. Only AGENTS demote; hand-typed
# interactive work is unaffected by construction, not by a rule someone has to remember.
#
# NOT admission control. Nothing here waits, sleeps, queues, or polls load — demotion only (R1).
#
# TWO TRANSFORMS, in order; the first one that fires wins and returns:
#   (a) any-spelling `bats` token  →  cc-bats                (converge on the PROVEN artifact)
#   (b) a pattern-table match      →  nice + taskpolicy prefix, SIMPLE commands ONLY
#
# FAIL-OPEN IS THE HARD CONTRACT (row 6's standing constraint: a hook failure must never block a
# tool). Every path exits 0. Every path that cannot be SURE prints NOTHING — and no output means
# the command runs verbatim, exactly as if this file did not exist. There is no partial-JSON path.
#
# THE NON-OBVIOUS HALF OF FAIL-OPEN: a rewrite can break a command that would otherwise have
# worked. `bats` → a cc-bats that is not there is exit 127; `taskpolicy -c <bogus>` is exit 64 and
# the program NEVER RUNS (measured 2026-07-30: only utility|background|maintenance parse). So every
# binary this file names is checked EXECUTABLE and every band is checked against the allowlist
# BEFORE we rewrite. Refusing to rewrite costs one undemoted process; a bad rewrite costs the
# agent's command.
#
# Seams (set-but-EMPTY is honoured VERBATIM everywhere — the `${VAR-default}` single-dash form,
# never `${VAR:-default}`, because a seam that cannot turn a thing OFF is not a seam; cc-bats:25):
#   CC_QOS_REWRITE=off      → whole hook off, exit 0 before anything else (kill switch, R8).
#   CC_QOS_PATTERNS=<path>  → pin the pattern table; SET-BUT-EMPTY disables transform (b) ONLY.
#   CC_QOS_CC_BATS=<path>   → pin the cc-bats target; SET-BUT-EMPTY disables transform (a) ONLY.
#   CC_QOS_TASKPOLICY=<p>   → pin taskpolicy(8); set-but-empty ⇒ (b) off (no nice-only fallback).
#   CC_QOS_NICE_BIN=<p>     → pin nice(1);        set-but-empty ⇒ (b) off.
#   CC_QOS_NICE_LEVEL=<n>   → nice level, default 19.
#
# WHY NO nice-ONLY FALLBACK when taskpolicy(8) is missing: cc-bats:150-159 MEASURED that on Darwin
# `nice -n 19` alone leaves PRI at 31 — full interactive priority, i.e. not demoted at all. A
# nice-only prefix would add two forks per command and buy nothing, while LOOKING covered to a
# census. Refusing the rewrite is the honest state.
#
# bash 3.2 SAFE: no `case` inside command substitution, no IFS-on-control-char splitting
# (memory bash32-case-in-substitution-zsh-repro-trap). Runs under /bin/bash as a hook.

# Kill switch is FIRST — before `set`, before stdin, before any resolution that could fail.
[ "${CC_QOS_REWRITE:-on}" = "off" ] && exit 0

set -uo pipefail

# ── read the payload, BOUNDED ─────────────────────────────────────────────────────────────────
# A hook runs on EVERY Bash call, so its own cost is a fleet-wide term (§8.5.4). An unbounded read
# of an attacker-or-accident-sized command is a memory term we refuse to take: 200 KB is ~2 orders
# of magnitude above any real command line, and a command truncated at that bound simply fails the
# match and runs verbatim (fail-open, not fail-weird).
INPUT=$(head -c 200000) || exit 0
[ -n "$INPUT" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# ── emit the envelope, or nothing at all ──────────────────────────────────────────────────────
# Built by jq --arg so escaping is jq's problem, never ours (a hand-rolled quote here is how a hook
# ships malformed JSON to a parser that then has to guess). Compact: one line, one object.
# Deliberately NO permissionDecision field — the rewrite applies on its own (§11.2 probe), and
# claiming a decision would take the permission flow over from the hooks that own it.
emit() { # <rewritten command>
  jq -cn --arg c "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",updatedInput:{command:$c}}}' 2>/dev/null \
    || exit 0
  exit 0
}

# ── idempotency: never wrap what is already wrapped ───────────────────────────────────────────
# Both transforms are skipped, not just (a). A command already naming cc-bats self-demotes; one
# already carrying `taskpolicy -c` is already in a band. Re-wrapping is harmless in effect and
# costs a fork pair — and this file exists to reduce load, not to add it (cc-bats:97-104).
case "$CMD" in
  *cc-bats*|*'taskpolicy -c'*) exit 0 ;;
esac

# ══ TRANSFORM (a) — any-spelling `bats` token → cc-bats ═══════════════════════════════════════
# The target is resolved and CHECKED EXECUTABLE first: rewriting to a cc-bats that is not deployed
# would turn a working gate run into exit 127.
if [ -n "${CC_QOS_CC_BATS+set}" ]; then
  CC_BATS_TARGET="$CC_QOS_CC_BATS"      # set-but-EMPTY ⇒ transform (a) OFF, honoured verbatim
else
  CC_BATS_TARGET="${HOME:-}/.claude/bin/cc-bats"
fi

if [ -n "$CC_BATS_TARGET" ] && [ -x "$CC_BATS_TARGET" ]; then
  # Escape the replacement for sed: `\` and `&` are special in a replacement, `%` is our delimiter.
  # Verified 2026-07-30 against targets containing each of the three.
  REPL=$(printf '%s' "$CC_BATS_TARGET" | sed -e 's/[\\&%]/\\&/g') || REPL=""
  if [ -n "$REPL" ]; then
    # THE TOKEN PATTERN, and why each piece is load-bearing (all four verified on BSD sed):
    #   (^|[[:space:]])      the token starts a word — `my.bats.file` and `t.bats` never match
    #   (/[^[:space:]]*/)?   an optional ABSOLUTE directory prefix that must END in `/`. This is
    #                        the guard that keeps `bats /abs/path/tests/foo.bats` from rewriting
    #                        its own ARGUMENT: the prefix cannot end mid-component, so `.../x.`
    #                        + `bats` is not a match. A relative prefix is deliberately NOT
    #                        matched — `bats -r tests/bats` must leave `tests/bats` alone.
    #   bats                 the literal, and nothing else
    #   ([[:space:]]|$)      the token ends a word; `$` inside the group anchors correctly here
    # /g so a wrapper form (`timeout 90 <path>/bats`, `env FOO=1 <path>/bats`) is covered without
    # having to know the wrapper. Accepted narrowing: a bare `bats` used as DATA (`echo bats`)
    # is rewritten too. The result is still a valid command naming a real executable, so the
    # blast radius is a surprising echo, never a broken tool call.
    NEWCMD=$(printf '%s' "$CMD" \
      | sed -E "s%(^|[[:space:]])(/[^[:space:]]*/)?bats([[:space:]]|\$)%\\1${REPL}\\3%g" 2>/dev/null) \
      || NEWCMD=""
    if [ -n "$NEWCMD" ] && [ "$NEWCMD" != "$CMD" ]; then
      emit "$NEWCMD"
    fi
  fi
fi

# ══ TRANSFORM (b) — pattern table → demotion prefix ═══════════════════════════════════════════
# ── resolve the table, THROUGH SYMLINKS FIRST ─────────────────────────────────────────────────
# ~/.claude/hooks/<name> is a per-file symlink into the checkout, so a naive
# `dirname "$BASH_SOURCE"` yields ~/.claude/hooks and `../config/...` resolves to
# ~/.claude/config/... — which does not exist and never will, because a symlinked directory does
# not acquire links for NEW files (memory deploy-lag-checkout-behind-origin,
# shared-lib-source-ladder-collapses-when-deployed: the top-level dirs do not auto-deploy).
# Resolving $0 physically lands us in the CHECKOUT's hooks/, where ../config/ is real.
# bash 3.2-safe: macOS has no `readlink -f`.
if [ -n "${CC_QOS_PATTERNS+set}" ]; then
  TABLE="$CC_QOS_PATTERNS"              # set-but-EMPTY ⇒ transform (b) OFF, honoured verbatim
else
  _self="${BASH_SOURCE[0]:-$0}"
  _hops=0
  while [ -L "$_self" ] && [ "$_hops" -lt 20 ]; do
    _d=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || break
    _self=$(readlink "$_self") || break
    case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
    _hops=$((_hops + 1))
  done
  _dir=$(cd -P "$(dirname "$_self")" 2>/dev/null && pwd) || _dir=""
  TABLE=""
  [ -n "$_dir" ] && TABLE="$_dir/../config/qos-batch.patterns"
fi
[ -n "$TABLE" ] && [ -r "$TABLE" ] || exit 0

# ── only a SINGLE SIMPLE command may be prefixed ──────────────────────────────────────────────
# A prefix is string surgery, and string surgery on a compound line is how you demote the wrong
# half: `nice … taskpolicy -c background du -s x | sort` would demote `du` but the pipeline's
# parse is no longer ours to reason about, and `a && pytest` would put the prefix on `a`.
# Conservative by design — anything with structure is left ALONE (fail-open, §11.3 M7: "never wrap
# compounds by string surgery"). `(`/`)` cover the brief's `$(` and command grouping in one test.
# The single-quoted metacharacters are LITERALS to match, mirroring rm-safe-allowlist.sh:53-56.
case "$CMD" in
  *';'*|*'&'*|*'|'*|*'<'*|*'>'*|*'('*|*')'*|*'`'*|*$'\n'*) exit 0 ;;
esac

# A leading `VAR=value` assignment cannot be prefixed: `taskpolicy -c background VAR=1 pytest`
# tries to EXEC `VAR=1` and dies. The env is the caller's, so we decline rather than re-order it.
printf '%s' "$CMD" | grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' && exit 0

# ── walk the table: `<band><TAB><ERE>`, first match wins ───────────────────────────────────────
# `|| [ -n "$line" ]` so a final line with no trailing newline is still read. No IFS splitting on
# a control character anywhere (memory bash32-case-in-substitution-zsh-repro-trap); the fields come
# out by parameter expansion, which cannot silently no-op.
BAND=""
while IFS= read -r line || [ -n "$line" ]; do
  line=${line%$'\r'}                                   # tolerate a CRLF table
  case "$line" in ''|'#'*) continue ;; esac
  _band=${line%%$'\t'*}
  _ere=${line#*$'\t'}
  [ "$_band" != "$line" ] || continue                  # no TAB on this line ⇒ malformed, skip
  [ -n "$_band" ] && [ -n "$_ere" ] || continue
  if printf '%s' "$CMD" | grep -qE "$_ere" 2>/dev/null; then BAND="$_band"; break; fi
done < "$TABLE"
[ -n "$BAND" ] || exit 0

# BAND ALLOWLIST — measured 2026-07-30: taskpolicy(8) parses ONLY these three, and on anything else
# exits 64 WITHOUT RUNNING THE PROGRAM. An unvalidated band in a config file would therefore turn
# every matching command into a no-op failure. A config file must not be able to break a tool call.
case "$BAND" in
  utility|background|maintenance) ;;
  *) exit 0 ;;
esac

# ── resolve the two prefix binaries; missing either ⇒ no rewrite ──────────────────────────────
# Single-dash `${VAR-default}`: the default applies only when the var is UNSET, so a set-but-EMPTY
# seam is honoured verbatim and turns transform (b) off. Hooks run without Homebrew on PATH, so
# these are absolute (the lesson lead-crash-watchdog.sh:23 records for timeout(1)).
NICE_BIN="${CC_QOS_NICE_BIN-/usr/bin/nice}"
TP_BIN="${CC_QOS_TASKPOLICY-/usr/sbin/taskpolicy}"
NICE_LEVEL="${CC_QOS_NICE_LEVEL-19}"
[ -n "$NICE_BIN" ] && [ -x "$NICE_BIN" ] || exit 0
[ -n "$TP_BIN" ] && [ -x "$TP_BIN" ] || exit 0
[ -n "$NICE_LEVEL" ] || exit 0

emit "$NICE_BIN -n $NICE_LEVEL $TP_BIN -c $BAND $CMD"
