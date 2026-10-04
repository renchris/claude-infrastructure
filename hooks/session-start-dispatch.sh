#!/bin/bash
# session-start-dispatch.sh — ONE SessionStart registration for the nine non-gating hooks that print
# context or an operator banner (fix row 17, docs/research/concurrency-scale-2026-10-04/README.md).
#
# WHY. Every session start, /clear and compact fired 18 SessionStart hooks, each its own harness spawn,
# JSON parse and attachment; the multi-hook startup span measured p50 2.9 s, p95 10.1 s, max 35.5 s
# (j-startup-hang.md). Migration 0056 regroups them by what each one owes the session:
#   · 5 pure side-effect hooks (nothing Claude reads) become "async": true, off the critical path.
#   · these 9 fold into this one process, which runs them in PARALLEL (as the harness did) and merges
#     their outputs into one additionalContext and one systemMessage, so turn-1 delivery is kept.
#   · 4 stay separate and sync: dod-persist, desk-brief-inject and mailbox-drain are gating and large
#     (merged, they would share and blow the harness's 10,000-character per-hook context cap), and
#     mailbox-wake-arm is already asyncRewake.
# The banner hooks may NOT go async: an async hook's systemMessage reaches the model as context and the
# terminal hides it, the reverse of the channel they chose (accounts-board.sh's channel proof).
#
# BOUNDS, per child, never shared. Each child runs in its own process group under CC_SSD_BOUND_S
# (default 9 s, under the 12 s registration). An overdue child's group is killed and its output dropped;
# every other child's output survives. Under the old layout the harness killed a slow hook the same way,
# and the startup span was already the slowest sync hook (10 s registrations), so the span is unchanged.
#
# CHILD CONTRACT, unchanged. Each child gets the same stdin payload. `$PPID` would now name this
# dispatcher, so CC_HOOK_PARENT_PID carries the claude pid; the two children that read their parent
# (session-start.sh, accounts-board.sh) prefer it. Stdout that is a JSON object contributes its
# hookSpecificOutput.additionalContext and systemMessage; any other stdout is plain context, which is how
# the harness reads a plain-text SessionStart hook. Children's stderr is discarded, as the harness did
# for an exit-0 hook.
#
# FAIL-OPEN: no jq, an unreadable payload or no output at all prints nothing and exits 0.
# Env seams (tests): CC_SSD_HOOK_DIR · CC_SSD_CHILDREN (space-separated) · CC_SSD_BOUND_S · CC_SSD_CAP
set -uo pipefail
set -m        # job control: each background child leads its own process group, so a bound can kill it whole
exec 2>/dev/null   # with job control on, bash reports killed jobs on stderr; the harness needs none of it

DIR="${CC_SSD_HOOK_DIR:-${BASH_SOURCE[0]%/*}}"
CHILDREN="${CC_SSD_CHILDREN:-session-start.sh setup-plan-symlinks.sh setup-task-symlinks.sh activation-watch.sh escalation-watch.sh accounts-board.sh session-index-start.sh config-mirror-assert.sh frontier-status.sh}"
BOUND="${CC_SSD_BOUND_S:-9}"
CAP="${CC_SSD_CAP:-9500}"
case "$BOUND" in ''|*[!0-9]*|0) BOUND=9 ;; esac
case "$CAP" in ''|*[!0-9]*) CAP=9500 ;; esac

T="$(mktemp -d "${TMPDIR:-/tmp}/ssd.XXXXXX" 2>/dev/null)" || exit 0
trap 'rm -rf "$T"' EXIT
if [ -e /dev/fd/0 ]; then cat > "$T/payload" 2>/dev/null || :; else : > "$T/payload"; fi

export CC_HOOK_PARENT_PID="${CC_HOOK_PARENT_PID:-$PPID}"

pids=""; i=0
for c in $CHILDREN; do
  i=$((i + 1))
  [ -x "$DIR/$c" ] || continue
  "$DIR/$c" < "$T/payload" > "$T/o$(printf '%02d' "$i")" 2>/dev/null &
  pids="$pids $!"
done
[ -n "$pids" ] || exit 0

# One watchdog for all children: after BOUND seconds, kill the group of every child whose LEADER is
# still running. A child that already exited is skipped even if helpers it detached still share its
# group: those were spawned on purpose and outliving the hook is their job. The watchdog's own
# stdout/stderr are /dev/null so a lingering sleep can never hold the harness's pipe open.
( sleep "$BOUND"; for p in $pids; do kill -0 "$p" 2>/dev/null && kill -TERM -- "-$p" 2>/dev/null; done ) >/dev/null 2>&1 &
wd=$!
for p in $pids; do wait "$p" 2>/dev/null; done
kill -TERM -- "-$wd" 2>/dev/null

command -v jq >/dev/null 2>&1 || exit 0
set -- "$T"/o*
[ -e "$1" ] || exit 0
args=()
for f in "$@"; do args+=(--rawfile "${f##*/}" "$f"); done

# One jq for the merge: registration order (o01..o09), JSON objects split into their two channels,
# anything else is plain context. The merged context is capped under the harness's per-hook cap.
# shellcheck disable=SC2016  # jq program, not shell
OUT="$(jq -nc --argjson cap "$CAP" "${args[@]}" '
  [ $ARGS.named | to_entries | map(select(.key | test("^o[0-9]+$"))) | sort_by(.key) | .[].value
    | rtrimstr("\n") | select(length > 0)
    | (try fromjson catch null) as $j
    | if ($j | type) == "object"
      then { c: ($j.hookSpecificOutput.additionalContext // ""), s: ($j.systemMessage // "") }
      else { c: ., s: "" } end ] as $r
  | ([ $r[].c | select(length > 0) ] | join("\n")) as $c
  | ([ $r[].s | select(length > 0) ] | join("\n")) as $s
  | (if $c != "" then { hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $c[:$cap] } }
     else {} end)
    + (if $s != "" then { systemMessage: $s } else {} end)
  | select(length > 0)' 2>/dev/null)" || OUT=""
[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
