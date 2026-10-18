#!/bin/bash
# a8_exec_cost.sh — axis A8: wall cost of the PRIMITIVES startup hooks spawn, under the live load.
# READ-ONLY: every command below is a no-op or a pure read (no hook script is executed).
# Prints, per primitive, the min / median / max wall ms over N runs, plus the load at start/end.
# Usage: bash a8_exec_cost.sh [N]   (default 7)
N="${1:-7}"
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }
measure() {  # <label> <cmd...>
  local label="$1"; shift
  local _ t0 t1 xs=()
  for _ in $(seq "$N"); do
    t0=$(ms); "$@" >/dev/null 2>&1; t1=$(ms)
    xs+=($((t1 - t0)))
  done
  printf '%s\n' "${xs[@]}" | sort -n | awk -v l="$label" '{a[NR]=$1} END{printf "%-44s min=%5d med=%5d max=%5d ms (n=%d)\n", l, a[1], a[int((NR+1)/2)], a[NR], NR}'
}
echo "load start: $(sysctl -n vm.loadavg)  $(date '+%FT%T')"
measure "perl timer overhead (2 perl execs)"       true
measure "/usr/bin/true"                            /usr/bin/true
measure "bash -c :"                                /bin/bash -c :
measure "zsh -fc :"                                /bin/zsh -fc :
measure "jq -n 1"                                  jq -n 1
measure "python3 -I -c pass"                       python3 -I -c pass
measure "python3 -c 'import json,subprocess'"      python3 -c 'import json,subprocess,pathlib'
measure "perl -MDigest::SHA -e 1"                  perl -MDigest::SHA=sha256_hex -e 1
measure "launchctl list (read)"                    launchctl list
measure "git rev-parse --show-toplevel"            git -C "$HOME/Development/claude-infrastructure" rev-parse --show-toplevel
measure "stat -f %m (one file)"                    stat -f %m /tmp/claude-accounts-board.txt
measure "cat board file"                           cat /tmp/claude-accounts-board.txt
measure "sysctl -n vm.loadavg"                     sysctl -n vm.loadavg
echo "load end:   $(sysctl -n vm.loadavg)  $(date '+%FT%T')"
