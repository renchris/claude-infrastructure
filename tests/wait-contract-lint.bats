#!/usr/bin/env bats
# L2 — wait-contract-lint: the auditor (the keeper). The tool's own --selftest RED-proves L2-a/b/c/d;
# these bats add CLI-level regression on real files + a real sweep page-once check.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/wait-contract-lint.sh"
  NOW="$(date +%s)"
}

@test "selftest passes and runs all 13 checks (a zero-check suite must not 'pass')" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 13 ]
}

@test "L2-a: a raw cc-await-ping loop lints RED (exit 1)" {
  printf '#!/bin/bash\nwhile :; do cc-await-ping "$U" && break; done\n' > "$BATS_TEST_TMPDIR/raw.sh"
  run "$LINT" "$BATS_TEST_TMPDIR/raw.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNCONTRACTED"* ]]
}

@test "L2-a: a wait through cc-wait lints GREEN (exit 0)" {
  printf '#!/bin/bash\ncc-wait --waitee peer --signal mailbox-line --deadline 3600 --on-timeout reobserve --note "re-observe peer effect"\n' > "$BATS_TEST_TMPDIR/ok.sh"
  run "$LINT" "$BATS_TEST_TMPDIR/ok.sh"
  [ "$status" -eq 0 ]
}

@test "L2-a: a missing file is LOUD indeterminate (exit 2), never a silent pass" {
  run "$LINT" "$BATS_TEST_TMPDIR/nope.sh"
  [ "$status" -eq 2 ]
}

@test "L2-b: a contract missing deadline lints RED" {
  mkdir -p "$BATS_TEST_TMPDIR/c"
  printf '{"id":"x","waiter":"W","waitee":"X","expected_signal":"ping","on_timeout_action":"re-observe X","status":"OPEN"}\n' > "$BATS_TEST_TMPDIR/c/x.json"
  run "$LINT" --contracts "$BATS_TEST_TMPDIR/c"
  [ "$status" -eq 1 ]
}

@test "L2-d: a reap-on-timeout contract lints RED" {
  mkdir -p "$BATS_TEST_TMPDIR/c"
  printf '{"id":"x","waiter":"W","waitee":"X","expected_signal":"ping","deadline":%s,"on_timeout_action":"kill X","status":"OPEN"}\n' "$((NOW+3600))" > "$BATS_TEST_TMPDIR/c/x.json"
  run "$LINT" --contracts "$BATS_TEST_TMPDIR/c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"S-3b"* ]]
}

@test "L2-c: a dead-waiter OPEN contract is paged ONCE across two sweeps (no wolf-cry)" {
  mkdir -p "$BATS_TEST_TMPDIR/s"
  printf '{"id":"d","waiter":"WD","waiter_pid":2147483641,"waiter_start":"stale","waitee":"X","expected_signal":"ping","deadline":%s,"on_timeout_action":"re-observe X","status":"OPEN"}\n' "$((NOW+3600))" > "$BATS_TEST_TMPDIR/s/d.json"
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/pages.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/page"; chmod +x "$BATS_TEST_TMPDIR/page"
  CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page" "$LINT" --sweep "$BATS_TEST_TMPDIR/s" >/dev/null 2>&1
  CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page" "$LINT" --sweep "$BATS_TEST_TMPDIR/s" >/dev/null 2>&1
  [ "$(wc -l < "$BATS_TEST_TMPDIR/pages.log" | tr -d ' ')" -eq 1 ]
}

# <mode: skew|stranger> — a $PATH `ps` rendering ONE instant per-locale. Never /bin/ps: the real
# binary shows the skew only on a non-C-locale box, so a real-ps test silently no-ops on CI and
# certifies nothing. A SINGLE-PROCESS test cannot see this class at all — the writer (bin/cc-wait,
# a session, ambient) and the reader (this sweep, whose scheduled caller scripts/lead-supervisor.sh
# runs under launchd with no LANG ⇒ C) are different processes in different locales.
stub_locale_ps() {
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  cat > "$STUB/ps" <<PS
#!/bin/bash
q=
for a in "\$@"; do [ "\$a" = "lstart=" ] && q=1; done
[ -n "\$q" ] || exec /bin/ps "\$@"
case "$1" in
  stranger) printf 'Thu Jan  1 00:00:00 2020    \n' ;;
  *) if [ "\${LC_ALL:-}" = "C" ] && [ "\${TZ:-}" = "UTC" ]; then printf 'Fri Aug 21 15:05:57 2026    \n'
     elif [ "\${LC_ALL:-}" = "C" ];                        then printf 'Fri Aug 21 08:05:57 2026    \n'
     else                                                       printf 'Fri 21 Aug 08:05:57 2026    \n'; fi ;;
esac
PS
  chmod +x "$STUB/ps"; PATH="$STUB:$PATH"; export PATH
}

@test "L2-c REGRESSION: a LIVE waiter is not paged as dead when the sweep runs in launchd's locale" {
  # THE BUG: cc-wait records the start time from a session, the sweep re-renders it under launchd's
  # C locale, the strings differ for the SAME live process, state becomes "dead-waiter" and the
  # watchdog pages a divergence about a waiter that is perfectly fine. Fixed on BOTH sides — the
  # record is written canonically (bin/cc-wait pid_start) and read canonically here.
  stub_locale_ps skew
  mkdir -p "$BATS_TEST_TMPDIR/s"
  /bin/sleep 30 & live=$!
  start="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$live" | sed 's/^ *//;s/ *$//')"   # what cc-wait now writes
  [ -n "$start" ]                                                              # armed, not empty
  jq -n --arg s "$start" --argjson pid "$live" --argjson dl "$((NOW+3600))" \
    '{id:"x",waiter:"WX",waiter_pid:$pid,waiter_start:$s,waitee:"X",expected_signal:"ping",deadline:$dl,on_timeout_action:"re-observe X",status:"OPEN"}' > "$BATS_TEST_TMPDIR/s/x.json"
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/pages.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/page"; chmod +x "$BATS_TEST_TMPDIR/page"
  LC_ALL=C CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page" "$LINT" --sweep "$BATS_TEST_TMPDIR/s" >/dev/null 2>&1
  kill "$live" 2>/dev/null || true
  [ ! -f "$BATS_TEST_TMPDIR/pages.log" ]
}

@test "L2-c MUTANT: a genuinely recycled pid is STILL paged dead in every locale" {
  # The reader now accepts three renderings; this pins that widening cannot launder a DIFFERENT
  # start instant alive, which would turn the recycled-pid guard off altogether.
  stub_locale_ps stranger
  mkdir -p "$BATS_TEST_TMPDIR/s"
  /bin/sleep 30 & live=$!
  jq -n --arg s 'Fri Aug 21 08:05:57 2026' --argjson pid "$live" --argjson dl "$((NOW+3600))" \
    '{id:"x",waiter:"WX",waiter_pid:$pid,waiter_start:$s,waitee:"X",expected_signal:"ping",deadline:$dl,on_timeout_action:"re-observe X",status:"OPEN"}' > "$BATS_TEST_TMPDIR/s/x.json"
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/pages.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/page"; chmod +x "$BATS_TEST_TMPDIR/page"
  LC_ALL=C CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page" "$LINT" --sweep "$BATS_TEST_TMPDIR/s" >/dev/null 2>&1
  LC_ALL=C CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page" "$LINT" --sweep "$BATS_TEST_TMPDIR/s" >/dev/null 2>&1
  kill "$live" 2>/dev/null || true
  [ -f "$BATS_TEST_TMPDIR/pages.log" ]
}

@test "L2-c: a live in-window waiter draws no page (silence)" {
  mkdir -p "$BATS_TEST_TMPDIR/s"
  start="$(ps -o lstart= -p $$ | sed 's/^ *//;s/ *$//')"
  jq -n --arg s "$start" --argjson pid "$$" --argjson dl "$((NOW+3600))" \
    '{id:"l",waiter:"WL",waiter_pid:$pid,waiter_start:$s,waitee:"X",expected_signal:"ping",deadline:$dl,on_timeout_action:"re-observe X",status:"OPEN"}' > "$BATS_TEST_TMPDIR/s/l.json"
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/pages.log"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/page"; chmod +x "$BATS_TEST_TMPDIR/page"
  CC_WAIT_PAGE_CMD="$BATS_TEST_TMPDIR/page" "$LINT" --sweep "$BATS_TEST_TMPDIR/s" >/dev/null 2>&1
  [ ! -f "$BATS_TEST_TMPDIR/pages.log" ]
}
