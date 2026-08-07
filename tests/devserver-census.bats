#!/usr/bin/env bats
# devserver-census — the census + idle-reaper for per-worktree `next dev` servers (backlog
# 2b1045b13b03). The tool's own --selftest RED-proves D-a/b/c/d with DISCRIMINATOR PAIRS; this suite
# pins the properties the selftest cannot assert about itself:
#
#   - the selftest actually RUNS its checks (a zero-check suite must not "pass" — reap-guard.bats:21)
#   - the DEFER causes carry DISTINCT exit codes, so a caller can tell owner from busy from young
#   - `census` and `--reap --dry-run` are READ-ONLY: neither may signal anything
#   - the ps `etime`/`time` parsers survive every width ps emits (mm:ss · hh:mm:ss · dd-hh:mm:ss)
#
# Every oracle is shimmed (CC_DEVGC_PS / CC_DEVGC_LSOF / CC_DEVGC_RECORDS_DIR), so the suite never
# reads the host's real process table — which, on this machine, contains live dev servers whose
# reaping would destroy an operator's work.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/scripts/devserver-census.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$BATS_TEST_TMPDIR"
  mkdir -p "$T/wt" "$T/bin"
  export CC_DEVGC_RECORDS_DIR="$T/records"
  export CC_DEVGC_SAMPLE_S=0 CC_DEVGC_GRACE_S=1800 CC_DEVGC_CPU_EPS=1

  echo "0:00" > "$T/cpu"; echo "99:00" > "$T/etime"; echo "" > "$T/owners"; : > "$T/conns"
  : > "$T/kills"

  cat > "$T/bin/ps" <<PSEOF
#!/usr/bin/env bash
case "\$*" in
  *"-eo pid=,command="*) echo "  100 next-server (v16.2.12)" ;;
  *"-o rss="*)   echo " 500000" ;;
  *"-o time="*)  cat $T/cpu ;;
  *"-o etime="*) cat $T/etime ;;
  *"-o ppid="*)  echo " 1" ;;
  *"-o command="*) echo "next-server (v16.2.12)" ;;
esac
PSEOF
  chmod +x "$T/bin/ps"

  cat > "$T/bin/lsof" <<LSEOF
#!/usr/bin/env bash
case "\$*" in
  *"-d cwd -c claude"*) sed 's/^/n/' $T/owners ;;
  *"-d cwd"*)           echo "n$T/wt" ;;
  *"-iTCP:"*)           cat $T/conns ;;
  *"-i"*)               echo "node 100 chrisren 29u IPv4 0x0 0t0 TCP *:3033 (LISTEN)" ;;
esac
LSEOF
  chmod +x "$T/bin/lsof"

  # a kill(1) that RECORDS instead of signalling — so a read-only claim is proven, not assumed
  cat > "$T/bin/kill" <<KEOF
#!/usr/bin/env bash
echo "\$*" >> $T/kills
KEOF
  chmod +x "$T/bin/kill"

  export CC_DEVGC_PS="$T/bin/ps" CC_DEVGC_LSOF="$T/bin/lsof"
}

@test "selftest is green AND runs all 14 checks (a zero-check suite must not 'pass')" {
  run env -u CC_DEVGC_PS -u CC_DEVGC_LSOF bash "$C" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"14 passed · 0 failed"* ]] || false
  # count the rendered check lines too — the summary and the body cannot desynchronise silently
  n="$(printf '%s\n' "$output" | grep -c '^  ✅')"
  [ "$n" -eq 14 ]
}

@test "D-a: a live owner session DEFERs with exit 10, distinct from every other cause" {
  echo "$T/wt" > "$T/owners"
  run bash "$C" decide --pid 100
  [ "$status" -eq 10 ]
  [[ "$output" == *"live-owner-session"* ]]
}

@test "D-c: a young server DEFERs with exit 12 — NOT the generic activity code" {
  echo "$T/unowned" > "$T/owners"
  echo "16:00" > "$T/etime"
  run bash "$C" decide --pid 100
  [ "$status" -eq 12 ]
  [[ "$output" == *"birth-grace"* ]]
}

@test "D-b: a browser attached on the dev port DEFERs with exit 11" {
  echo "$T/unowned" > "$T/owners"
  echo "node 100 chrisren 29u IPv4 0x0 0t0 TCP 127.0.0.1:3033->127.0.0.1:9 (ESTABLISHED)" > "$T/conns"
  run bash "$C" decide --pid 100
  [ "$status" -eq 11 ]
  [[ "$output" == *"browser-attached"* ]]
}

@test "the three DEFER causes are mutually distinct codes (a caller can act on each)" {
  echo "$T/wt" > "$T/owners";  run bash "$C" decide --pid 100; owner=$status
  echo "$T/x"  > "$T/owners"; echo "16:00" > "$T/etime"
  run bash "$C" decide --pid 100; young=$status
  echo "99:00" > "$T/etime"
  echo "node 100 chrisren 29u IPv4 0x0 0t0 TCP 127.0.0.1:3033->127.0.0.1:9 (ESTABLISHED)" > "$T/conns"
  run bash "$C" decide --pid 100; busy=$status
  [ "$owner" -ne "$young" ]; [ "$young" -ne "$busy" ]; [ "$owner" -ne "$busy" ]
}

@test "POSITIVE CONTROL: with every gate clear the SAME fixture REAPs (exit 0) — the defers are not vacuous" {
  echo "$T/unowned" > "$T/owners"
  run bash "$C" decide --pid 100
  [ "$status" -eq 0 ]
  [[ "$output" == *"REAP"* ]]
}

@test "census is READ-ONLY: it renders a verdict and signals nothing" {
  echo "$T/unowned" > "$T/owners"
  PATH="$T/bin:$PATH" run bash "$C" census
  [ "$status" -eq 0 ]
  [[ "$output" == *"REAP"* ]] || false
  [ ! -s "$T/kills" ]
}

@test "--reap --dry-run names the chain it WOULD kill and signals nothing" {
  echo "$T/unowned" > "$T/owners"
  PATH="$T/bin:$PATH" run bash "$C" --reap --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would TERM"* ]] || false
  [ ! -s "$T/kills" ]
}

@test "D-d: census writes an outcome record for EVERY decision, reap and defer alike" {
  echo "$T/wt" > "$T/owners"
  run bash "$C" census
  [ -s "$CC_DEVGC_RECORDS_DIR/decisions.jsonl" ]
  grep -q '"verdict":"DEFER"' "$CC_DEVGC_RECORDS_DIR/decisions.jsonl"
}

@test "etime parses every width ps emits: mm:ss, hh:mm:ss and dd-hh:mm:ss" {
  echo "$T/unowned" > "$T/owners"
  # 10:00 = 600 s → under the 1800 s grace → DEFER 12
  echo "10:00" > "$T/etime";       run bash "$C" decide --pid 100; [ "$status" -eq 12 ]
  # 01:00:00 = 3600 s → past grace → REAP
  echo "01:00:00" > "$T/etime";    run bash "$C" decide --pid 100; [ "$status" -eq 0 ]
  # 2-03:00:00 = 2 days+ → past grace → REAP (a day-width that parsed as minutes would still pass,
  # so the mm:ss case above is what makes this row load-bearing)
  echo "2-03:00:00" > "$T/etime";  run bash "$C" decide --pid 100; [ "$status" -eq 0 ]
}

@test "an unknown argument is a usage error (exit 2), never a silent no-op census" {
  run bash "$C" --wat
  [ "$status" -eq 2 ]
}

@test "decide without --pid is a usage error, not a verdict" {
  run bash "$C" decide
  [ "$status" -eq 2 ]
}
