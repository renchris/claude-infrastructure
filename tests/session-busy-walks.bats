#!/usr/bin/env bats
# session-busy-walks.bats — hooks/lib/session-busy.sh's awk walks (`_sb_ancestors`,
# `_sb_descendants`) print EXACTLY what proc-scope.sh's `ps_scope_ancestors` / `ps_scope_descendants`
# print, on adversarial process tables, in a bounded number of processes
# (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Wave 4b).
#
# Why the copies exist: the bash walks were ~1.2 s of the BUSY probe's 1.65 s inside
# operator-readout's ledger (36k traced lines over a ~1,300-row table), on the Stop hook's critical
# path. proc-scope.sh is not changed because it is also gate-cleanup's SIGKILL selector; so the two
# implementations now exist side by side, and THIS file is what keeps them the same function.
#
# The tables are generated, not captured (no `ps` here): leading blanks, tab separators, rows with
# no ppid (the empty-ppid set-membership quirk), non-numeric pids, ppid 0/1, Claude/node/claude-*
# sessions and look-alikes (`claudeX`), trailing blanks, a cycle, and a 30-hop chain listed CHILD
# FIRST so the 12-pass fixed point truncates it — every rule the awk restates is exercised.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  LIB="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/hooks/lib"
}

table() { # <seed> <rows> → a process table on stdout
  awk -v seed="$1" -v n="$2" 'BEGIN {
    srand(seed)
    c[0]="/bin/zsh -c source x"; c[1]="claude --resume abc"; c[2]="node /x/node_modules/.bin/claude"
    c[3]="/opt/homebrew/bin/claude-next foo"; c[4]="bash /wt/scripts/ship-land.sh"; c[5]="sleep 25"
    c[6]="node server.js"; c[7]="/usr/bin/claudeX y"; c[8]="python3\t-I  x.py  "; c[9]="/a/b/claude"
    for (i = 1; i <= n; i++) {
      pid = 100 + int(rand() * n * 2)
      r = rand()
      if (r < 0.03) ppid = ""; else if (r < 0.06) ppid = "1"; else if (r < 0.08) ppid = "0"
      else ppid = 100 + int(rand() * n * 2)
      sep = (rand() < 0.1) ? "\t" : " "; lead = (rand() < 0.5) ? "  " : ""
      if (rand() < 0.02) pid = "x" pid
      if (ppid == "") printf "%s%s\n", lead, pid
      else printf "%s%s%s%s %s\n", lead, pid, sep, ppid, c[int(rand() * 10)]
    }
    for (i = 30; i >= 1; i--) printf "%d %d bash step%d\n", 90000 + i, 90000 + i - 1, i
    printf "80001 80002 a\n80002 80001 b\n"
  }'
}

# compare <seed> <rows> under <interpreter>: every start/root/exclude combination, both walks.
compare() {
  "$3" -c '
    . "$1/proc-scope.sh"; . "$1/session-busy.sh"
    snap="$(cat "$2")"; bad=0; n=0
    starts="90000 90015 80001 $(printf "%s\n" "$snap" | awk "NR%23==0{print \$1}" | head -40)"
    ex=" $(printf "%s\n" "$snap" | awk "NR%11==0{printf \"%s \", \$1}")"
    for s in $starts; do
      a="$(ps_scope_ancestors "$s" "$snap")"; b="$(_sb_ancestors "$s" "$snap")"
      n=$((n+1)); [ "$a" = "$b" ] || { echo "ANC $s [$a] [$b]"; bad=1; }
      for e in "" "$ex"; do
        a="$(ps_scope_descendants "$s " "$snap" "$e")"; b="$(_sb_descendants "$s " "$snap" "$e")"
        n=$((n+1)); [ "$a" = "$b" ] || { echo "DESC $s [$a] [$b]"; bad=1; }
      done
    done
    a="$(ps_scope_descendants "90000 80001 " "$snap" "")"; b="$(_sb_descendants "90000 80001 " "$snap" "")"
    [ "$a" = "$b" ] || { echo "DESC multi-root"; bad=1; }
    echo "compared=$n chain=$(printf "%s" "$b" | wc -w | tr -d " ")"
    exit $bad
  ' _ "$LIB" "$BATS_TEST_TMPDIR/table.$1"
}

@test "W1 identical strings to proc-scope on four adversarial tables, under /bin/bash 3.2" {
  local s
  for s in 1 2 3 4; do
    table "$s" 400 > "$BATS_TEST_TMPDIR/table.$s"
    run compare "$s" 400 /bin/bash
    echo "$output"
    [ "$status" -eq 0 ]
  done
}

@test "W2 identical under the PATH bash (the one a hook's shebang may resolve to)" {
  table 7 600 > "$BATS_TEST_TMPDIR/table.7"
  run compare 7 600 bash
  echo "$output"
  [ "$status" -eq 0 ]
}

@test "W3 the 12-pass cap is REACHED and truncates identically (the child-first chain)" {
  printf '' > "$BATS_TEST_TMPDIR/chain"
  local i; for i in $(seq 30 -1 1); do printf '%d %d bash step%d\n' $((90000 + i)) $((90000 + i - 1)) "$i"; done > "$BATS_TEST_TMPDIR/chain"
  run /bin/bash -c '. "$1/proc-scope.sh"; . "$1/session-busy.sh"; s="$(cat "$2")"
    a="$(ps_scope_descendants "90000 " "$s" "")"; b="$(_sb_descendants "90000 " "$s" "")"
    if [ "$a" != "$b" ]; then echo "MISMATCH"; exit 1; fi; printf "%s" "$b" | wc -w' _ "$LIB" "$BATS_TEST_TMPDIR/chain"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | tr -d ' ')" -eq 13 ]   # the root plus one hop per pass, 12 passes
}

@test "W4 sessions are never descendants, look-alikes are (claudeX, a bare claude path segment)" {
  printf '%s\n' '10 1 bash root' '11 10 claude --x' '12 10 /usr/bin/claudeX y' '13 10 node a' \
    '14 10 /opt/claude-next z' '15 10 python /n/node_modules/.bin/claude' '16 10 sleep 1' > "$BATS_TEST_TMPDIR/s"
  run /bin/bash -c '. "$1/proc-scope.sh"; . "$1/session-busy.sh"; s="$(cat "$2")"
    a="$(ps_scope_descendants "10 " "$s" "")"; b="$(_sb_descendants "10 " "$s" "")"
    if [ "$a" != "$b" ]; then echo "MISMATCH"; exit 1; fi; printf "%s" "$b"' _ "$LIB" "$BATS_TEST_TMPDIR/s"
  [ "$status" -eq 0 ]
  [ "$output" = "10 12 16 " ]
}

@test "W5 one process per walk, however large the table (the bash walk interprets every row)" {
  table 9 1500 > "$BATS_TEST_TMPDIR/big"
  run /bin/bash -c '. "$1/proc-scope.sh"; . "$1/session-busy.sh"; s="$(cat "$2")"
    t0=$SECONDS; for i in 1 2 3 4 5; do _sb_descendants "90000 " "$s" "" >/dev/null; _sb_ancestors 90020 "$s" >/dev/null; done
    echo "awk_s=$((SECONDS - t0))"' _ "$LIB" "$BATS_TEST_TMPDIR/big"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "${output#awk_s=}" -le 3 ]
}
