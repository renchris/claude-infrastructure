#!/bin/bash
# cc-cannot-replay.sh — score bin/cc-cannot against the frozen corpus.
# Reports BOTH weightings, because one command carries 270 of 1,376 emissions and a single
# weighted number over that distribution is meaningless.
#   $1 = corpus tsv (count<TAB>command)
set -uo pipefail
CORPUS="${1:?corpus tsv}"
# Resolve $0 through its symlinks first: via the live layer's per-file link, dirname/.. is ~/.claude.
self="$0"; while [ -L "$self" ]; do
  d="$(cd "$(dirname "$self")" && pwd)"; self="$(readlink "$self")"
  case "$self" in /*) ;; *) self="$d/$self" ;; esac
done
CC="$(cd "$(dirname "$self")/.." && pwd)/bin/cc-cannot"
out="$(mktemp)"
# Split on the FIRST tab by hand: IFS=<tab> collapses an empty cell and shifts the command left.
while IFS= read -r line; do
  [[ "$line" == *$'\t'* ]] || continue
  n="${line%%$'\t'*}"; cmd="${line#*$'\t'}"
  case "$n" in ''|\#*) continue ;; esac
  v="$("$CC" --quiet -- "$cmd" >/dev/null 2>&1; case $? in 0) echo HUMAN;; 1) echo REFUTED;; *) echo UNRESOLVED;; esac)"
  printf '%s\t%s\t%s\n' "$n" "$v" "$cmd" >> "$out"
done < "$CORPUS"
awk -F'\t' '{d[$2]++; e[$2]+=$1; D++; E+=$1}
END{ printf "%-12s %8s %7s %8s %7s\n","VERDICT","distinct","%","emiss","%";
     for(k in d) printf "%-12s %8d %6.1f%% %8d %6.1f%%\n",k,d[k],100*d[k]/D,e[k],100*e[k]/E;
     printf "%-12s %8d %6s  %8d\n","TOTAL",D,"",E }' "$out" | sort
echo "$out"
