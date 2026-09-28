#!/usr/bin/env bash
# bench-all.sh "<arms>" "<tasks|all>" "<reps>" — run a #35 matrix, at most BENCH_JOBS (default 4) at once.
# Launch it DETACHED (a tool-call nohup is reaped with its process group):
#   . scripts/lib/detach.sh; detach "$RUNROOT/_logs/all.log" bash bench-all.sh "1 2" all "1 2"
# Verifies the frozen store against its manifest first and refuses on any mismatch. Writes
# $RUNROOT/_logs/<task>-a<arm>-r<rep>.log per run and one pid per running job under _pids/.
set -u
[ $# -eq 3 ] || { echo 'usage: bench-all.sh "<arms>" "<tasks|all>" "<reps>"' >&2; exit 2; }
ARMS=$1; TASKS=$2; REPS=$3
H=$(cd "$(dirname "$0")" && pwd)
RUNROOT=${BENCH_ROOT:-$HOME/.claude/autonomy/memory-eval/bench-runs}
SRC=${BENCH_STORE:-$HOME/.claude/autonomy/memory-eval/storecopy-infra-2026-09-28}
JOBS=${BENCH_JOBS:-4}
[ "$JOBS" -le 4 ] || JOBS=4
[ "$TASKS" = all ] && TASKS=$(awk -F'\t' 'NR>1 {print $1}' "$H/tasks.tsv")
mkdir -p "$RUNROOT/_logs" "$RUNROOT/_pids"

if ! ( cd "$SRC" && shasum -a 256 -c "$SRC.MANIFEST.sha256" >/dev/null 2>&1 ); then
  echo "bench-all: frozen store FAILS its manifest; refusing" >&2; exit 3
fi
echo "bench-all: store manifest OK; arms=[$ARMS] reps=[$REPS] jobs=$JOBS start=$(date -u +%FT%TZ)"

running() {
  local n=0 f
  for f in "$RUNROOT"/_pids/*.pid; do
    [ -e "$f" ] || continue
    if kill -0 "$(cat "$f")" 2>/dev/null; then n=$((n + 1)); else rm -f "$f"; fi
  done
  echo "$n"
}

for rep in $REPS; do
  for task in $TASKS; do
    for arm in $ARMS; do
      while [ "$(running)" -ge "$JOBS" ]; do sleep 5; done
      tag="$task-a$arm-r$rep"
      bash "$H/run-bench.sh" "$arm" "$task" "$rep" > "$RUNROOT/_logs/$tag.log" 2>&1 &
      echo $! > "$RUNROOT/_pids/$tag.pid"
      echo "bench-all: started $tag pid $!"
    done
  done
done
while [ "$(running)" -gt 0 ]; do sleep 10; done
echo "bench-all: done $(date -u +%FT%TZ)"
