#!/usr/bin/env bash
# replay-operator-readout.sh <tree> <case-dir> <label> — replay ONE recorded operator-readout Stop.
#
# <case-dir> is one directory `cutreplay.py operator-readout.sh <n> <outdir>` wrote (stdin.json + the
# cut transcript); the account dir is read from <outdir>/index.txt (cutreplay's stdout, saved there).
# <tree> is a checkout or an extracted tree holding hooks/, scripts/ and bin/ — e.g. trunk-before via
# `git archive <sha> hooks scripts bin | tar -x -C <dir>`, or the live checkout.
#
# Sandboxed: the hook's state dir, IDL, the ledger memo and TMPDIR point at a fresh dir under
# ${REPLAY_SB_ROOT:-/tmp}, so a replay is never damped by, and never damps, a live session. Shared on
# purpose: the backlog-fold cache (exact-keyed and read-mostly), so both arms see the warm reads a real
# Stop sees. Siblings: three BUSY-off ledger asks start beside the hook, as session-continue,
# boundary-handoff and completion-assert make them. Nothing is timed out, killed or signalled.
# TRACE=1 runs the hook under `set -x` with PS4=$EPOCHREALTIME, exported to its children.
#
# Prints: <label> <case> <ms> <rc> <sandbox>   (the sandbox keeps out, err, idl.jsonl)
# Wave 4c (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md) measured with it; percentiles over the
# printed ms column, nearest-rank.
set -u
tree="$1"; case_dir="${2%/}"; label="$3"
blg="${TMPDIR%/}/cc-orb-blg-cache.${UID}"
sb="$(mktemp -d "${REPLAY_SB_ROOT:-/tmp}/or-replay.XXXXXX")"
mkdir -p "$sb/state" "$sb/memo" "$sb/tmp"
stdin="$case_dir/stdin.json"
sid="$(jq -r .session_id "$stdin")"; cwd="$(jq -r .cwd "$stdin")"; tp="$(jq -r .transcript_path "$stdin")"
acct="$(awk -v d="$case_dir/stdin.json" '$NF == d {print $3}' "${case_dir%/*}/index.txt" 2>/dev/null | head -1)"
run_env=(env -u CC_PANE_ID -u ITERM_SESSION_ID -u KITTY_WINDOW_ID
  CLAUDE_CODE_SESSION_ID="$sid" CLAUDE_CONFIG_DIR="${acct:-$HOME/.claude}"
  CC_OPREADOUT_STATE_DIR="$sb/state" CC_IDL="$sb/idl.jsonl" WRAP_CACHE_DIR="$sb/memo" TMPDIR="$sb/tmp/"
  CC_ORB_BLG_CACHE_DIR="$blg" WRAP_BACKLOG_CACHE_DIR="$blg")
sibs=()
for _ in 1 2 3; do
  ( cd "$cwd" 2>/dev/null && "${run_env[@]}" WRAP_TRANSCRIPT="$tp" WRAP_BUSY=off \
      bash "$tree/scripts/wrap-ledger.sh" --machine > /dev/null 2>&1 ) &
  sibs+=($!)
done
t0=$EPOCHREALTIME
if [ -n "${TRACE:-}" ]; then
  # shellcheck disable=SC2016  # PS4 and the inner script expand in the traced shell
  ( cd /tmp && "${run_env[@]}" PS4='+${BASH_SOURCE##*/}:${LINENO}@${EPOCHREALTIME}| ' \
      bash -c 'set -o xtrace; export SHELLOPTS; exec bash "$0"' "$tree/hooks/operator-readout.sh" \
      < "$stdin" > "$sb/out" 2> "$sb/err" )
else
  ( cd /tmp && "${run_env[@]}" bash "$tree/hooks/operator-readout.sh" < "$stdin" > "$sb/out" 2> "$sb/err" )
fi
rc=$?
t1=$EPOCHREALTIME
wait "${sibs[@]}" 2>/dev/null
ms=$(( (${t1/./} - ${t0/./}) / 1000 ))
printf '%s %s %s %s %s\n' "$label" "${case_dir##*/}" "$ms" "$rc" "$sb"
