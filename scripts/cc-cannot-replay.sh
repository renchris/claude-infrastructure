#!/bin/bash
# cc-cannot-replay.sh — score bin/cc-cannot against the frozen corpus.
# Reports BOTH weightings, because one command carries 270 of 1,376 emissions and a single
# weighted number over that distribution is meaningless.
#   $1 = corpus tsv (count<TAB>command)   $2 = optional gold tsv (command<TAB>verdict)
set -uo pipefail
CORPUS="${1:?corpus tsv}"; GOLD="${2:-}"
CC="$(dirname "$0")/../bin/cc-cannot"
out="$(mktemp)"
while IFS=$'\t' read -r n cmd; do
  case "$n" in ''|\#*) continue ;; esac
  v="$("$CC" --quiet -- "$cmd" >/dev/null 2>&1; case $? in 0) echo HUMAN;; 1) echo REFUTED;; *) echo UNRESOLVED;; esac)"
  printf '%s\t%s\t%s\n' "$n" "$v" "$cmd" >> "$out"
done < "$CORPUS"
awk -F'\t' '{d[$2]++; e[$2]+=$1; D++; E+=$1}
END{ printf "%-12s %8s %7s %8s %7s\n","VERDICT","distinct","%","emiss","%";
     for(k in d) printf "%-12s %8d %6.1f%% %8d %6.1f%%\n",k,d[k],100*d[k]/D,e[k],100*e[k]/E;
     printf "%-12s %8d %6s  %8d\n","TOTAL",D,"",E }' "$out" | sort
echo "$out"
