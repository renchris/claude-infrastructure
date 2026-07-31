#!/usr/bin/env bash
# hook-chain-bench.sh — re-derive the hook-chain cost model instead of quoting it.
#
# Every number in MACHINE_CAPACITY_V2.md §12.7 came from this script. It exists because the FIRST
# cost model was wrong in a specific, repeatable way, and a reader who quotes a stale figure will
# rebuild the same dead end:
#
#   THE TRAP. Timing `bash -c 'exit 0'` from a wrapper bills the WRAPPER's own fork as well as the
#   child's. That reads ~11-15 ms and looks like "interpreter startup", which makes collapsing an
#   N-member chain look like an N x 11 ms win. The MARGINAL cost of one more exec of a page-cached
#   binary inside an already-running shell is ~2-4 ms. The `--marginal` probe below measures the
#   difference directly, so the artifact cannot be mistaken for the quantity again.
#
#   THE SECOND TRAP. Wall clock cannot adjudicate this on a loaded box: §8.5.7 measured a 2x load
#   swing at CONSTANT session count, and every collapse delta is inside that band. So this script
#   REFUSES to print a verdict without reporting the load at the start and end of the run; if they
#   differ materially the comparison is not evidence, and it says so rather than printing a number
#   that reads like a result.
#
#   THE THIRD TRAP. This script's verdict certifies stability WITHIN one run only. Comparing a
#   number from one run against a number from an earlier run is invalid: two runs 20 minutes apart
#   read 163 ms and 216 ms for the SAME chain purely because load moved 16.4 -> 20.4. To compare a
#   change against its baseline, INTERLEAVE both sides inside a single run so load hits them
#   equally -- that is how the 18 ms/call cat-fork saving (c957df9e) was established.
#
#   THE FOURTH TRAP. Run this under bash, not zsh. zsh does not word-split unquoted `$VAR`, so
#   `for m in $MEMBERS` iterates ONCE over the whole string, every hook path is invalid, and the
#   loop reports ~0 ms -- a vacuous pass that looks like a spectacular win.
#
# Usage:  hook-chain-bench.sh [reps]        default 11
#         hook-chain-bench.sh --marginal    just the artifact demonstration

set -uo pipefail
# Resolve $0 through its symlinks BEFORE deriving the root: ~/.claude/scripts/ are per-file
# symlinks into the checkout, so `dirname "$0"/..` through the LIVE path is ~/.claude — no tests/,
# no docs/, no .git — and this script would silently benchmark the wrong tree. Canonical loop from
# scripts/ship-land.sh `_resolve_self` (no `readlink -f`: GNU-only, this box is BSD).
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
REPO="$(cd "$(dirname "$_self")/.." && pwd)"
REPS="${1:-11}"
[ "$REPS" = "--marginal" ] && REPS=15

ncpu="$(sysctl -n hw.ncpu 2>/dev/null || echo 1)"
load_now() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}'; }
LOAD_START="$(load_now)"

now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'; }
median() { printf '%s\n' "$@" | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'; }

bench() { # <label> <shell-snippet>
  local label="$1" snip="$2" t=() t0 t1
  for _ in $(seq "$REPS"); do
    t0="$(now_ms)"; eval "$snip" >/dev/null 2>&1; t1="$(now_ms)"
    t+=( $((t1 - t0)) )
  done
  printf '  %-46s %5s ms\n' "$label" "$(median "${t[@]}")"
}

PAY="$(jq -nc --arg cwd "$REPO" \
  '{session_id:"bench",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",
    tool_name:"Bash",tool_input:{command:"echo hello"}}')"
PF="${TMPDIR:-/tmp}/hook-chain-bench.$$.json"; printf '%s' "$PAY" > "$PF"
trap 'rm -f "$PF"' EXIT

echo "hook-chain-bench — reps=$REPS  ncpu=$ncpu  load@start=$LOAD_START"
echo

echo "── the measurement artifact (why the first cost model was 4x too big) ──"
bench "wrapper-timed 'bash -c exit 0' (THE ARTIFACT)" "bash -c 'exit 0'"
bench "guard preamble: \$(cat) + printf|jq" \
      "bash -c 'INPUT=\$(cat); CMD=\$(printf \"%s\" \"\$INPUT\" | jq -r \".tool_input.command // empty\" 2>/dev/null); :' < '$PF'"
bench "  same, builtin read (no cat fork)" \
      "bash -c 'IFS= read -r -d \"\" INPUT || true; CMD=\$(printf \"%s\" \"\$INPUT\" | jq -r \".tool_input.command // empty\" 2>/dev/null); :' < '$PF'"
bench "  same, pre-parsed (no cat, no jq)" \
      "env CC_HOOK_PARSED=1 CC_HOOK_CMD='echo hello' bash -c 'CMD=\$CC_HOOK_CMD; :' < '$PF'"
echo "  ^ the spread between rows 2 and 4 is the REAL per-guard preamble saving."
echo

if [ "${1:-}" = "--marginal" ]; then
  printf 'load@end=%s (start=%s)\n' "$(load_now)" "$LOAD_START"; exit 0
fi

echo "── the real chain: serial (today) vs collapsed ──"
MEMBERS="curl-gate.py validate-bash.sh git-worktree-guard.sh keychain-guard.sh rm-safe-allowlist.sh ship-rail-push-allow.sh"
bench "SERIAL 6 guards (today's settings.json)" \
      "for m in $MEMBERS; do cat '$PF' | '$REPO/hooks/'\$m; done"
bench "DISPATCHER exec mode" \
      "env CC_HOOK_CHAIN_DIR='$REPO/config/hook-chains.d' CC_HOOK_CHAIN_MEMBER_DIR='$REPO/hooks' CC_HOOK_CHAIN_MODE=exec '$REPO/hooks/hook-chain.sh' pretooluse-bash < '$PF'"
bench "DISPATCHER source mode" \
      "env CC_HOOK_CHAIN_DIR='$REPO/config/hook-chains.d' CC_HOOK_CHAIN_MEMBER_DIR='$REPO/hooks' CC_HOOK_CHAIN_MODE=source '$REPO/hooks/hook-chain.sh' pretooluse-bash < '$PF'"
echo

echo "── per-guard cost, and the curl-gate finding ──"
for m in $MEMBERS; do bench "$m" "cat '$PF' | '$REPO/hooks/$m'"; done
bench "chain WITHOUT curl-gate.py (5 guards)" \
      "for m in validate-bash.sh git-worktree-guard.sh keychain-guard.sh rm-safe-allowlist.sh ship-rail-push-allow.sh; do cat '$PF' | '$REPO/hooks/'\$m; done"
echo "  ^ curl-gate.py self-scopes to reso-management-app (curl-gate.py:409) but is registered"
echo "    GLOBALLY in settings.json — outside that one project every ms above is unconditional waste."
echo

LOAD_END="$(load_now)"
printf 'load@start=%s  load@end=%s  (ncpu=%s)\n' "$LOAD_START" "$LOAD_END" "$ncpu"
awk -v a="$LOAD_START" -v b="$LOAD_END" 'BEGIN{
  hi = (a>b)?a:b; lo = (a<b)?a:b;
  if (lo <= 0) { print "VERDICT: UNUSABLE — could not read loadavg."; exit }
  if (hi/lo > 1.25)
    printf "VERDICT: NOT EVIDENCE — load moved %.2fx during the run (%.2f -> %.2f).\n\
         §8.5.7 measured a 2x swing at CONSTANT session count, so these deltas are inside\n\
         the noise band. Re-run on a quiet box, or compare fork COUNTS instead of wall time.\n", hi/lo, a, b;
  else
    printf "VERDICT: comparable — load stable within %.2fx across the run.\n", hi/lo;
}'
