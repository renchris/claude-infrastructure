#!/usr/bin/env bash
# wrap-ledger-memo-bench.sh — the CONCURRENT benchmark for the `--machine` memo (P0-4).
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A NUMBER IN A COMMIT MESSAGE. The first memo (9adc5120) was
# benchmarked by calling `--machine` six times IN SEQUENCE — 60 → 27 git subprocesses, a clean
# 2.22× — and shipped as a REGRESSION. The seven Stop consumers do not arrive in sequence: they are
# dispatched CONCURRENTLY, 8-9 hooks in flight inside one ~45 ms window. Measured in THAT shape the
# same memo read 72 git against 60 uncached — 20% WORSE on the first Stop after any tree change,
# i.e. the common case. So the arrival pattern is the measurement, and there is deliberately NO
# sequential arm here. Re-run this, do not quote it.
#
#   bash scripts/wrap-ledger-memo-bench.sh          # N=6
#   N=7 bash scripts/wrap-ledger-memo-bench.sh      # the real call-site count
#
# Four arms, all N-concurrent, git subprocesses counted by a PATH shim:
#   WRAP_CACHE=off            the control — what a close costs today
#   memo COLD                 a new event: one caller computes, the rest are served
#   memo WARM                 the same event again: nothing computes
#   MUTANT, lock neutered     the MUTATION CONTROL — single-flight disabled and nothing else.
#                             If this does not regress to the control's cost, the cold arm proves
#                             nothing: a memo that never engaged looks identical to a perfect one.
#
# Everything lives in a throwaway tree under $BENCH_ROOT; nothing reads the operator's repos.
set -uo pipefail

# RESOLVE the symlink chain before traversing `..` — everything in ~/.claude is reached through a
# per-file symlink into the checkout, so an unresolved $0 makes the parent-dir hop land in ~/.claude
# and this bench would then silently measure a DIFFERENT tree than the one under test. The manual
# loop is the portable form (`readlink -f` is GNU-only; this fleet is BSD). Idiom: bin/cc-offload.
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _t="$(readlink "$_self")"
  case "$_t" in /*) _self="$_t" ;; *) _self="$(cd -- "$(dirname -- "$_self")" && pwd -P)/$_t" ;; esac
done
REPO="${REPO:-$(cd -- "$(dirname -- "$_self")/.." && pwd -P)}"
ROOT="${BENCH_ROOT:-${TMPDIR:-/tmp}/wrap-ledger-memo-bench.$$}"
N="${N:-6}"

command -v git >/dev/null 2>&1 || { echo "bench: git not found"; exit 2; }

rm -rf "$ROOT"; mkdir -p "$ROOT"
trap 'rm -rf "$ROOT"' EXIT

WORK="$ROOT/work"; ORIGIN="$ROOT/origin.git"; LIVE="$ROOT/live"
TP="$ROOT/transcript.jsonl"; CACHE="$ROOT/cache"; COUNT="$ROOT/gitcount"

git init -q --bare "$ORIGIN"
git clone -q "$ORIGIN" "$WORK" 2>/dev/null
(
  cd "$WORK" || exit 1
  git config user.email bench@example.com; git config user.name bench
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main
) || { echo "bench: fixture repo failed"; exit 2; }
# A live layer sharing $WORK's origin, so the live-layer arm (ledger calls 12-19) actually RUNS.
# Against a different origin the ledger reads LIVE_SRC=n-a and spends 12 git instead of 19, which
# would understate the control by a third.
git clone -q "$ORIGIN" "$LIVE" 2>/dev/null
( cd "$LIVE" && git checkout -q -B main origin/main ) 2>/dev/null
printf 'turn 0\n' > "$TP"

# ── the mirror: both arms must resolve their sibling libs IDENTICALLY ──────────────────────────
# wrap-ledger.sh sources ../hooks/lib/{land-inflight,dod-path}.sh relative to $0, and those cost git
# calls. A mutant parked anywhere else resolves neither and reads 66 git where the real script reads
# 84 — a difference with nothing to do with the mutation.
MIRROR="$ROOT/mirror"; mkdir -p "$MIRROR/scripts"
ln -s "$REPO/hooks" "$MIRROR/hooks"
ln -s "$REPO/bin"   "$MIRROR/bin"
cp "$REPO/scripts/wrap-ledger.sh" "$MIRROR/scripts/wrap-ledger.sh"
REAL="$MIRROR/scripts/wrap-ledger.sh"
MUTANT="$MIRROR/scripts/wrap-ledger-NOLOCK.sh"
# shellcheck disable=SC2016  # the \$WL_LOCK here is the TARGET's source text, not ours to expand
sed 's|if mkdir "\$WL_LOCK" 2>/dev/null; then|if true; then|' "$REAL" > "$MUTANT"
if cmp -s "$REAL" "$MUTANT" || ! grep -q 'if true; then' "$MUTANT"; then
  echo "bench: the lock mutation did not apply — the control arm would be meaningless. Abort."
  exit 2
fi

mkdir -p "$ROOT/shim"
{ printf '#!/bin/sh\n'
  # shellcheck disable=SC2016  # $WLB_COUNT is expanded by the SHIM at run time, not written here
  printf 'printf "g\\n" >> "$WLB_COUNT"\n'
  printf 'exec %s "$@"\n' "$(command -v git)"
} > "$ROOT/shim/git"
chmod +x "$ROOT/shim/git"

export WLB_COUNT="$COUNT"
export PATH="$ROOT/shim:$PATH"
export WRAP_TRUNK=origin/main
export WRAP_LIVE_REPO="$LIVE"
export WRAP_CACHE_DIR="$CACHE"
export WRAP_DOD_DIR="$ROOT/dod"
export CC_CUSTODY_DIR="$ROOT/custody"
export CC_MIGRATIONS_STATE="$ROOT/migrations"
export CC_BACKLOG_BIN="$ROOT/absent-cc-backlog"
export CC_DECIDE_BIN="$ROOT/absent-cc-decide"

run_wave() {  # $1 = label · $2 = script
  local label="$1" script="$2" i p pids=() t0 t1 g
  : > "$COUNT"
  t0="$(date +%s%N)"
  for (( i=0; i<N; i++ )); do
    ( cd "$WORK" && bash "$script" --machine --transcript "$TP" > "$ROOT/out.$i" 2>/dev/null ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
  t1="$(date +%s%N)"
  g="$(grep -c . "$COUNT" 2>/dev/null)" || g=0
  printf '  %-30s git=%-5s wall=%sms\n' "$label" "$g" "$(( (t1 - t0) / 1000000 ))"
  for (( i=1; i<N; i++ )); do
    cmp -s "$ROOT/out.0" "$ROOT/out.$i" || printf '    !! caller %s DISAGREES with caller 0\n' "$i"
  done
  grep -q '^RUNG=' "$ROOT/out.0" 2>/dev/null || printf '    !! caller 0 produced no ledger\n'
}

new_event() { printf 'turn %s\n' "$(date +%s%N)" >> "$TP"; }

printf 'wrap-ledger memo — %s CONCURRENT callers, git subprocesses counted by a PATH shim\n' "$N"
rm -rf "$CACHE"; new_event
WRAP_CACHE=off run_wave "WRAP_CACHE=off (control)" "$REAL"
rm -rf "$CACHE"; new_event
run_wave "memo COLD (new event)" "$REAL"
run_wave "memo WARM (same event)" "$REAL"
rm -rf "$CACHE"; new_event
run_wave "MUTANT — lock neutered" "$MUTANT"
