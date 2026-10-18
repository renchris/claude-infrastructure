#!/bin/bash
# a2-forkbench.sh — read-only per-spawn cost probe for the A2-child-cost axis.
# Spawns only side-effect-free commands (true, jq -n, python3 -c pass, git --version, ps, date,
# sqlite3 -version) N times each and prints the wall-clock ms per spawn. Executes NO hook.
# Usage: bash a2-forkbench.sh [N]   (default N=10)
N="${1:-10}"
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }
bench() {
  local label="$1"; shift
  local s e i
  s=$(now_ms)
  for ((i = 0; i < N; i++)); do "$@" >/dev/null 2>&1; done
  e=$(now_ms)
  printf '%-28s n=%-3s total=%6dms per=%5dms\n' "$label" "$N" "$((e - s))" "$(((e - s) / N))"
}
printf 'load: %s\n' "$(sysctl -n vm.loadavg)"
bench "perl timer (baseline)"  perl -e 1
bench "/usr/bin/true"          /usr/bin/true
bench "date +%s"               date +%s
bench "jq -n 1"                jq -n 1
bench "python3 -c pass"        python3 -c pass
bench "python3 -S -c pass"     python3 -S -c pass
bench "git --version"          git --version
bench "ps -o command= -p 1"    ps -o command= -p 1
bench "stat -f %m /tmp"        stat -f %m /tmp
bench "sqlite3 -version"       sqlite3 -version
bench "zsh -fc :"              zsh -fc :
bench "bash -c :"              /bin/bash -c :
printf 'load: %s\n' "$(sysctl -n vm.loadavg)"
