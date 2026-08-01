#!/usr/bin/env bash
# worktree-gc-infra-run.sh — the launchd wrapper that finally SCHEDULES the worktree janitor for
# claude-infrastructure.
#
# WHY THIS FILE EXISTS: `scripts/worktree-gc.sh` has been a complete, safe janitor for this repo
# since 2026-07-25, and nothing has ever run it on a cadence. The ONLY scheduled reaper on this box
# is `gl.reso.worktree-gc` → `~/.reso/worktree-gc-run.sh`, which hardcodes
# REPO=/Users/chrisren/Development/reso-management-app. So claude-infrastructure was never swept:
# measured 2026-08-01, 126 worktrees and 1,193 branches. The gap was never the janitor — it was the
# cron. This file is the cron, and NOTHING ELSE: every safety gate stays in worktree-gc.sh, which
# this wrapper only parameterises and never second-guesses.
#
# CRITICAL — PATH. lsof lives in /usr/sbin, NOT /usr/bin. reso's reaper shipped a PATH without
# /usr/sbin, so under launchd `lsof` was command-not-found, EVERY liveness gate returned empty, and
# it reaped a LIVE worktree (wt-cc-233227-53597, 2026-06-19). worktree-gc.sh inherits this PATH, so
# the omission would be silently re-inherited here. System dirs first so the entitled system tools
# win; homebrew kept for git and timeout(1).
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
set -uo pipefail

# ── Seams. Defaults are production; the bats suite overrides all four to stay hermetic. ──────────
REPO="${CC_WTGC_INFRA_REPO:-/Users/chrisren/Development/claude-infrastructure}"
GC_SH="${CC_WTGC_INFRA_GC:-$REPO/scripts/worktree-gc.sh}"
GIT_BIN="${CC_WTGC_GIT:-git}"                       # same seam name worktree-gc.sh already uses
STATE="$HOME/.claude/autonomy"
LOG="${CC_WTGC_INFRA_LOG:-$HOME/.claude/logs/worktree-gc-infra.log}"
LAST="$STATE/worktree-gc-infra.last"
DISABLED="$STATE/worktree-gc-infra.disabled"
LOCK="$HOME/.claude/state/worktree-gc-infra.lock"
OBSERVE="${WTGC_OBSERVE:-0}"
FETCH_BOUND="${CC_WTGC_INFRA_FETCH_BOUND:-300}"

mkdir -p "$STATE" "$(dirname "$LOG")" "$(dirname "$LOCK")" 2>/dev/null
ts="$(date '+%Y-%m-%d %H:%M:%S')"

# ── The verdict token. ───────────────────────────────────────────────────────────────────────────
# One structured, parseable line per run — `verdict=<v>` plus k=v fields — written to $LAST and
# echoed into $LOG. NEVER `|| true` a failure into a fake success: a claimed outcome that no reader
# can distinguish from a checked one deletes the signal entirely (claimed-outcome-vs-checked-outcome).
# Every field is ASCII, unquoted, whitespace-free, so `grep -o 'verdict=[a-z-]*'` and a plain
# `awk -F= ` both work.
#
#   verdict=ok        the sweep RAN and worktree-gc.sh printed its summary. removed/disposed/
#                     branches/refusals carry that summary's numbers verbatim.        exit 0
#   verdict=disabled  kill switch present; nothing was attempted.                     exit 0
#   verdict=skipped   the sweep did NOT run, by design and harmlessly — another pass holds the
#                     janitor's own lock (worktree-gc.sh:324 exits 0 with no summary). Deliberately
#                     NOT `ok`: `ok removed=0` would be indistinguishable from a clean sweep that
#                     found nothing, which is exactly the fake success this token exists to prevent.
#                                                                                     exit 0
#   verdict=blind     worktree-gc.sh REFUSED to act (rc 3) — no liveness oracle, so it cannot prove
#                     a worktree is idle. A safe refusal, but a broken sensor: under this PATH lsof
#                     always resolves, so rc 3 here means something is genuinely wrong.  exit 3
#   verdict=nofetch   `git fetch` failed or timed out, so origin/main is stale. Landedness is
#                     measured against origin/main; a stale ref makes landed branches look unlanded
#                     (fails SAFE — a KEEP — but makes the whole sweep useless). Nothing swept.
#                                                                                     exit 3
#   verdict=error     anything else, INCLUDING an unrecognised rc. rc is carried verbatim.
#                     A new worktree-gc.sh exit code lands here rather than in a success arm
#                     (new-enum-member-falls-into-fail-closed-default).                exit = rc
verdict() { # <verdict> <exit-code> [k=v ...]
  local v="$1" rc="$2"; shift 2
  local line="$ts  verdict=$v observe=$OBSERVE"
  [ "$#" -gt 0 ] && line="$line $*"
  line="$line rc=$rc"
  printf '%s\n' "$line" > "$LAST" 2>/dev/null
  printf '%s\n' "$line" >> "$LOG" 2>/dev/null
  # Keep the log bounded in place — it is the fleet's staleness sensor, so it must stay one file.
  if [ "$(wc -l < "$LOG" 2>/dev/null || echo 0)" -gt 2000 ]; then
    tail -n 1000 "$LOG" > "$LOG.tmp" 2>/dev/null && mv "$LOG.tmp" "$LOG"
  fi
  exit "$rc"
}

# ── Kill switch. Observe mode is read-only, so it is not gated by the switch: the switch stops the
#    janitor from REMOVING things, and observe removes nothing by construction. ───────────────────
if [ "$OBSERVE" = "0" ] && [ -f "$DISABLED" ]; then
  verdict disabled 0 "switch=$DISABLED"
fi

[ -f "$GC_SH" ] || verdict error 1 "stage=preflight reason=gc-script-missing"
[ -d "$REPO" ]  || verdict error 1 "stage=preflight reason=repo-missing"

# ── Wrapper-level singleton (atomic mkdir, dead-holder self-heal). Distinct from worktree-gc.sh's
#    own CC_WTGC_LOCK, which is deliberately left at its default so this sweep and reso's 03:15 one
#    can never mutate worktrees concurrently. Observe mode is read-only ⇒ no lock. ────────────────
LOCK_HELD=0
if [ "$OBSERVE" = "0" ]; then
  if mkdir "$LOCK" 2>/dev/null; then
    LOCK_HELD=1
  else
    lpid="$(cat "$LOCK/pid" 2>/dev/null)"
    if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
      verdict skipped 0 "reason=wrapper-lock-held holder=$lpid"
    fi
    rm -rf "$LOCK" 2>/dev/null
    mkdir "$LOCK" 2>/dev/null && LOCK_HELD=1
  fi
  [ "$LOCK_HELD" = "1" ] || verdict skipped 0 "reason=wrapper-lock-unobtainable"
  echo "$$" > "$LOCK/pid" 2>/dev/null
  trap 'rm -rf "$LOCK" 2>/dev/null' EXIT INT TERM
fi

# ── FETCH FIRST. Landedness is `git cherry origin/main <branch>`; a stale remote-tracking ref makes
#    landed branches read as unlanded. That direction fails SAFE (a KEEP, never a wrongful delete)
#    but it also makes the sweep do nothing, which is the outcome this file exists to end.
#    Bounded so a hung fetch cannot hold the wrapper lock forever. The bound is ~100x a measured
#    fetch of this repo, sized for the launchd Background band's 4-84x tax, not for a foreground
#    run (bound-must-fit-the-band-not-the-bench). rc 124 is timeout(1)'s own code and is handled
#    as its OWN state, never folded into a generic failure.
fetch_rc=0
if command -v timeout >/dev/null 2>&1; then
  timeout "$FETCH_BOUND" "$GIT_BIN" -C "$REPO" fetch --quiet origin main >/dev/null 2>&1
  fetch_rc=$?
else
  "$GIT_BIN" -C "$REPO" fetch --quiet origin main >/dev/null 2>&1
  fetch_rc=$?
fi
if [ "$fetch_rc" -eq 124 ]; then
  verdict nofetch 3 "stage=fetch reason=timeout bound=${FETCH_BOUND}s"
elif [ "$fetch_rc" -ne 0 ]; then
  verdict nofetch 3 "stage=fetch reason=git-failed git_rc=$fetch_rc"
fi

# ── The sweep. Every gate lives in worktree-gc.sh; this only chooses the flags. ───────────────────
# --prune-branches is the whole point of scheduling this: 1,193 branches, and the janitor deletes
# ONLY landed, worktree-less, unprotected ones with `git branch -d` — never -D, so git's own
# merge check is a second gate on our evidence and a refusal is a KEEP.
# --dispose-abandoned is deliberately NOT passed: the DISPOSE class needs an operator-recorded
# ownership decision, and a nightly cron is exactly the wrong place to infer one. The class is
# still CLASSIFIED and printed by the janitor, so it stays visible in this log.
export CC_WTGC_REPO="$REPO"
export CC_WTGC_TRUNK="origin/main"
# EXCLUDE — colon-separated, also covering nested worktrees.
#   · the repo ROOT: the main checkout is not a linked worktree so the janitor already skips it,
#     but ~/.claude is a symlink INTO this checkout, so a wrongful removal here would take the live
#     harness layer with it. Belt and braces on the one path whose loss is unrecoverable.
#   · ~/.claude/autonomy/postland: the post-land verifier's OWN worktrees. They are created and
#     destroyed by com.claude.postland-verify on its own cadence; reaping one mid-cycle breaks the
#     verifier that gates every deploy — and it is the one consumer whose worktrees are legitimately
#     idle-looking while genuinely in use.
export CC_WTGC_EXCLUDE="$REPO:$HOME/.claude/autonomy/postland"

if [ "$OBSERVE" = "1" ]; then
  out="$(bash "$GC_SH" --dry-run --prune-branches 2>&1)"; rc=$?
else
  out="$(bash "$GC_SH" --prune-branches 2>&1)"; rc=$?
fi

{
  echo "===== $ts  worktree-gc-infra (observe=$OBSERVE repo=$REPO) ====="
  printf '%s\n' "$out"
} >> "$LOG" 2>/dev/null

# ── Reduce the janitor's output to the verdict. The SUMMARY LINE is the evidence that a sweep
#    actually happened; rc 0 alone is not (lock contention also exits 0, printing no summary).
summary="$(printf '%s\n' "$out" | grep -m1 '^worktree-gc: removed ')"

case "$rc" in
  0)
    if [ -z "$summary" ]; then
      if printf '%s\n' "$out" | grep -q 'another pass holds'; then
        verdict skipped 0 "reason=janitor-lock-held"
      fi
      verdict error 1 "stage=parse reason=no-summary-line"
    fi
    # "removed N worktree(s) · disposed N abandoned · kept N · deleted N branch(es) · N refusal(s)"
    # Strip everything that is not a digit or a separator and take the five numbers positionally.
    # The word splitting is the POINT here, hence the disable.
    # shellcheck disable=SC2046
    set -- $(printf '%s\n' "$summary" | tr -cd '0-9 \n')
    verdict ok 0 "removed=${1:-0} disposed=${2:-0} kept=${3:-0} branches=${4:-0} refusals=${5:-0}"
    ;;
  3) verdict blind 3 "reason=no-liveness-oracle" ;;
  4) verdict error 4 "reason=disposal-preservation-unverified" ;;
  *) verdict error "$rc" "reason=unexpected-janitor-rc" ;;
esac
