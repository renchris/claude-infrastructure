#!/usr/bin/env bash
# branch-prune-pass.sh — ONE pass of scripts/branch-prune-landed.sh, run OUTSIDE the sweep's tick.
#
#   scripts/branch-prune-pass.sh --repo DIR --manifest PATH   one pass, then exit
#
# WHY (2026-10-24, backlog b6fb791b88fa). autonomy-sweep ran the pruner INLINE, under a 240 s bound,
# inside a tick whose self-bound is 400 s. The pruner runs one `git cherry` per remote ref BEFORE it
# deletes anything, and at ~350 refs on a box at load ~35 that loop no longer fits 240 s: the bound
# cut it (rc 124) on 685 of 1,058 ticks journaled 2026-10-13..24, and on all but 44 of ~525 since
# 2026-10-18. A cut pass is the worst of both worlds — it spends the tick's 240 s AND deletes
# nothing, so the ref population never shrinks and the next pass is slower. With 60% of the budget
# gone before the first checkpoint, 90% of ticks self-bounded at `0b`/`1`, and the arms at
# 2b-iii..2b-v (drain-revival, strand-fill, freeze, ...) ran on 2 ticks in 6 days. Same shape as
# the retire pass (moved into the cloud lane 2026-09-06) and the land-failed pin gc: the unit gets
# its own process and a bound sized to IT, and the tick only spawns it.
#
# THE LICENCE TO DELETE MOVED HERE WITH THE PASS. The first pass on a box is a DRY RUN that only
# writes the manifest; the marker `<state>/.prune.applied-once` that promotes every later pass to a
# deleting one is written ONLY by a dry run that COMPLETED (rc 0). A cut or failed first pass leaves
# it absent, so the next pass dry-runs again (memory: claimed-outcome-vs-checked-outcome).
#
# SINGLE-FLIGHT. A lock dir (mkdir, pid, TTL = bound + 60) makes a second pass exit 4 and journal it.
#
# THE ROW CONTRACT. Every pass journals ONE `branch-prune` row (tool: branch-prune-pass) carrying
# branch_prune_rc (the pruner's rc: 0 ran · 1 a delete batch failed · 124/137 cut by the bound ·
# 4 another pass held the lock · skipped-absent), mode (dry|apply), elapsed_s, load1 and bound_s.
#
# Env seams: CC_PRUNE_PASS_BOUND_S (1800) · CC_CLOUD_STATE · CC_IDL · CC_PRUNE_PASS_TIMEOUT_BIN
# Exits: the pruner's rc · 4 lock held · 2 usage
# bash 3.2-safe (launchd runs /bin/bash). NO `set -e`.
set -uo pipefail

_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
DIR="$(cd "$(dirname "$_self")" && pwd)"
PRUNE_SH="$DIR/branch-prune-landed.sh"

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; CFG="${CFG%/}"
STATE="${CC_CLOUD_STATE:-$CFG/autonomy/cloud}"
IDL="${CC_IDL:-$CFG/autonomy/idl.jsonl}"
BOUND="${CC_PRUNE_PASS_BOUND_S:-1800}"; case "$BOUND" in ''|*[!0-9]*) BOUND=1800 ;; esac
TMO="${CC_PRUNE_PASS_TIMEOUT_BIN:-$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)}"
LOCK="$STATE/.prune.lock"
LOCK_TTL=$(( BOUND + 60 ))
FIRST="$STATE/.prune.applied-once"

REPO="" MANIFEST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)     REPO="${2:?--repo needs a dir}"; shift 2 ;;
    --manifest) MANIFEST="${2:?--manifest needs a path}"; shift 2 ;;
    *) echo "branch-prune-pass: unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$REPO" ] && [ -n "$MANIFEST" ] || { echo "branch-prune-pass: --repo and --manifest are required" >&2; exit 2; }

now() { date +%s; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
load1() { sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}'; }

# jq-encoded end to end: one malformed line aborts every `jq -rs` slurp of the journal.
log_idl() { # <jq-built object>
  mkdir -p "$(dirname "$IDL")" 2>/dev/null || true
  jq -cn --arg ts "$(now_iso)" --argjson extra "$1" \
    '{ts:$ts, tool:"branch-prune-pass", disposition:"branch-prune"} + $extra' >>"$IDL" 2>/dev/null || true
}

lock_acquire() {
  mkdir -p "$STATE" 2>/dev/null || return 1
  if mkdir "$LOCK" 2>/dev/null; then printf '%s\n' "$$" >"$LOCK/pid"; now >"$LOCK/at"; return 0; fi
  local pid at
  pid="$(head -1 "$LOCK/pid" 2>/dev/null)"; case "$pid" in ''|*[!0-9]*) pid="" ;; esac
  at="$(head -1 "$LOCK/at" 2>/dev/null)";   case "$at"  in ''|*[!0-9]*) at=0 ;; esac
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ $(( $(now) - at )) -lt "$LOCK_TTL" ]; then return 1; fi
  rm -rf "$LOCK" 2>/dev/null; mkdir "$LOCK" 2>/dev/null || return 1
  printf '%s\n' "$$" >"$LOCK/pid"; now >"$LOCK/at"
  return 0
}
# shellcheck disable=SC2329  # invoked through the EXIT/INT/TERM trap below
lock_release() { [ "$(head -1 "$LOCK/pid" 2>/dev/null)" = "$$" ] && rm -rf "$LOCK" 2>/dev/null; return 0; }

mode=dry; flags=(--dry-run)
[ -f "$FIRST" ] && { mode=apply; flags=(); }

if ! lock_acquire; then
  log_idl "$(jq -cn --arg m "$mode" --argjson b "$BOUND" \
    '{branch_prune_rc:"4", mode:$m, elapsed_s:null, load1:null, bound_s:$b, note:"another prune pass holds the lock; nothing ran"}')"
  exit 4
fi
trap 'lock_release' EXIT INT TERM

if [ ! -x "$PRUNE_SH" ]; then
  log_idl "$(jq -cn --arg m "$mode" --argjson b "$BOUND" \
    '{branch_prune_rc:"skipped-absent", mode:$m, elapsed_s:null, load1:null, bound_s:$b}')"
  exit 0
fi

mkdir -p "$(dirname "$MANIFEST")" 2>/dev/null
t0="$(now)"
if [ -n "$TMO" ] && [ -x "$TMO" ]; then
  ( cd "$REPO" && "$TMO" -k 10 "$BOUND" bash "$PRUNE_SH" ${flags[@]+"${flags[@]}"} --manifest "$MANIFEST" )
else
  ( cd "$REPO" && bash "$PRUNE_SH" ${flags[@]+"${flags[@]}"} --manifest "$MANIFEST" )
fi
rc=$?
took=$(( $(now) - t0 ))

if [ "$mode" = dry ] && [ "$rc" = 0 ]; then
  printf 'first_dry_run_at=%s\nmanifest=%s\n' "$(now_iso)" "$MANIFEST" >"$FIRST" 2>/dev/null || true
fi

log_idl "$(jq -cn --arg c "$rc" --arg m "$mode" --argjson e "$took" --arg l "$(load1)" --argjson b "$BOUND" \
  '{branch_prune_rc:$c, mode:$m, elapsed_s:$e, load1:($l|tonumber? // null), bound_s:$b}')"
exit "$rc"
