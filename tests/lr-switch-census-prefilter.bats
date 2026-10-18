#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# The switch census drops rows a `sid:`/`sids:` selector cannot match BEFORE any per-row fork (2026-10-18).
# Subject: scripts/limit-recover/lr-upgrade.sh lru_switch_census.
#
# Why: the plan-time census ran 3.0-3.4 min under load (docs/research/lr-inplace-immediacy-2026-10-18
# raw/D §3d) and one census is 19-27 CPU-s (raw/F). With `--sid`, every unselected registry row still
# paid two jq forks (.paneUUID, .pid) before the sid test dropped it, and every unselected bg row paid
# lru_live_pane_of_pid — one jq per LIVE registry row — before its sid test. [RED] cases count those
# forks through a PATH-stub jq that logs each call and execs the real one.
#
# Hermetic: every store is a fixture, `ps` is a snapshot FILE (LRU_PS_SNAPSHOT); nothing live is read.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$BATS_TEST_TMPDIR/cfgroot"; mkdir -p "$LRU_CFG_ROOT"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_KITTY_LS="$BATS_TEST_TMPDIR/kitty-ls.json"; echo '[]' > "$LRU_KITTY_LS"
  export LRU_COMPOSER=off
  export LRU_SELF_SID=""
  export LRU_LR_LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  export CC_CRASH_LOG="$BATS_TEST_TMPDIR/crashes.jsonl"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/absent-kitty-socket"
  export LRU_NOTIFY_BIN="$BATS_TEST_TMPDIR/absent-cc-notify"
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/absent-cc-resume-debt"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  # The fork counter: every jq call is one line in jq.log, then the real jq answers it. It lives in
  # $HOME/.claude/bin because lr-upgrade.sh prepends that (and /opt/homebrew/bin) to PATH at start.
  JQLOG="$BATS_TEST_TMPDIR/jq.log"; JQSTUB="$HOME/.claude/bin"; mkdir -p "$JQSTUB"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %s\nexec %s "$@"\n' "$JQLOG" "$(command -v jq)" > "$BATS_TEST_TMPDIR/jq-counter"
  chmod +x "$BATS_TEST_TMPDIR/jq-counter"
  N=0
}

LST="Tue Sep 22 06:47:13 2026"
BIN="/opt/cc/.claude-280/node_modules/.bin/claude"
# sess <pane> <sid> — one idle interactive session on claude-t, pid 50000+N, at rest.
sess() {
  local pane="$1" sid="$2" pid tx
  N=$((N + 1)); pid=$((50000 + N))
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-t","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$BIN --model claude-opus-5-5" >> "$LRU_PS_SNAPSHOT"
  tx="$LRU_CFG_ROOT/.claude-t/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
    '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' > "$tx"
}
# bgsess <sid> <base-pid> <spawner-pid> — a LIVE idle bg session whose daemon the spawner launched.
bgsess() {
  local sid="$1" d="$2" sp="$3"
  {
    printf '%d 1 %s %s\n' "$d" "$LST" "/x/claude.exe daemon run --origin transient --spawned-by {\"label\":\"claude\",\"cwd\":\"/w\",\"pid\":$sp}"
    printf '%d %d %s %s\n' $((d + 1)) "$d" "$LST" 'claude bg-pty-host --bg-pty-host /tmp/a.pty.sock 200 50 -- claude.exe --bg-spare /tmp/a.claim.sock'
    printf '%d %d %s %s\n' $((d + 2)) $((d + 1)) "$LST" 'claude bg-spare --bg-spare /tmp/a.claim.sock'
  } >> "$LRU_PS_SNAPSHOT"
  mkdir -p "$LRU_CFG_ROOT/.claude-t/sessions"
  printf '{"pid":%d,"sessionId":"%s","cwd":"%s","kind":"bg","jobId":"j%d","status":"idle","procStart":"%s"}\n' \
    $((d + 2)) "$sid" "$BATS_TEST_TMPDIR" "$d" "$LST" > "$LRU_CFG_ROOT/.claude-t/sessions/$((d + 2)).json"
}
S1=aaaa0001-0000-4000-8000-000000000001
S2=aaaa0002-0000-4000-8000-000000000002
S3=aaaa0003-0000-4000-8000-000000000003
S4=aaaa0004-0000-4000-8000-000000000004
S5=aaaa0005-0000-4000-8000-000000000005
B1=bbbb0001-0000-4000-8000-000000000001
B2=bbbb0002-0000-4000-8000-000000000002
five() { sess 701 "$S1"; sess 702 "$S2"; sess 703 "$S3"; sess 704 "$S4"; sess 705 "$S5"; }
# Per-row registry reads: `jq -r .pid // empty <registry file>` (the census loop and
# lru_live_pane_of_pid). lru_live_pass reads the registry with ONE differently-shaped filter per file.
pid_forks() { grep -cF -- "-r .pid // empty $LRU_REG_DIR/" "$JQLOG" || true; }
census_with_stub_jq() {
  : > "$JQLOG"; ln -sf "$BATS_TEST_TMPDIR/jq-counter" "$JQSTUB/jq"
  run bash "$LRU" --switch-census --target claude-zz "$@"
  rm -f "$JQSTUB/jq"
}
# rows of the unfiltered census whose sid (column 2) starts with any of the given prefixes
full_rows_for() {
  printf '%s\n' "$FULL" | awk -F'\t' -v ps="$*" 'BEGIN { n = split(ps, p, " ") } { for (i = 1; i <= n; i++) if (index($2, p[i]) == 1) { print; next } }'
}

@test "P1 [RED] --sid <one> forks per-row jq for the selected row only, not for all five" {
  five
  run bash "$LRU" --switch-census --target claude-zz
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  FULL="$output"
  census_with_stub_jq --sid "${S3:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # RED before: 5 (every row read its .pid before the sid test dropped it).
  [ "$(pid_forks)" -eq 1 ] || { echo "forks=$(pid_forks)"; cat "$JQLOG"; false; }
  [ "$output" = "$(full_rows_for "${S3:0:8}")" ] || { echo "got: $output"; echo "want: $(full_rows_for "${S3:0:8}")"; false; }
  [ -n "$output" ]
}

@test "P2 [RED] repeated --sid (sids:) forks per-row jq for the two selected rows only" {
  five
  run bash "$LRU" --switch-census --target claude-zz
  FULL="$output"
  census_with_stub_jq --sid "${S2:0:8}" --sid "${S5:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pid_forks)" -eq 2 ] || { echo "forks=$(pid_forks)"; cat "$JQLOG"; false; }
  [ "$output" = "$(full_rows_for "${S2:0:8}" "${S5:0:8}")" ] || { echo "got: $output"; false; }
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "P3 [RED] a bg sid: unselected bg rows never pay lru_live_pane_of_pid, nor the registry rows" {
  five
  # Both bg daemons were spawned by the LAST registry row (705, pid 50005), so each bg row's pane
  # lookup walks all five LIVE rows: 5 jq forks per bg row judged.
  bgsess "$B1" 71000 50005
  bgsess "$B2" 72000 50005
  run bash "$LRU" --switch-census --target claude-zz
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  FULL="$output"
  [ "$(full_rows_for "${B1:0:8}" | awk -F'\t' '{ print $1 }')" = 705 ] || { echo "$output"; false; }
  census_with_stub_jq --sid "${B1:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # RED before: 15 (5 registry rows + 5 per bg row × 2). After: B1's own pane lookup only.
  [ "$(pid_forks)" -eq 5 ] || { echo "forks=$(pid_forks)"; cat "$JQLOG"; false; }
  [ "$output" = "$(full_rows_for "${B1:0:8}")" ] || { echo "got: $output"; false; }
}

@test "P4 --pane and no selector are unchanged: every row is read, output identical to before" {
  five
  census_with_stub_jq
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 5 ]
  [ "$(pid_forks)" -eq 5 ] || { echo "forks=$(pid_forks)"; false; }
  FULL="$output"
  census_with_stub_jq --pane 703
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(printf '%s\n' "$FULL" | awk -F'\t' '$1 == 703')" ] || { echo "got: $output"; false; }
  [ -n "$output" ]
}

@test "P5 kill switch LRU_CENSUS_PREFILTER=off: the old order, every row read, same output" {
  five
  census_with_stub_jq --sid "${S3:0:8}"
  WANT="$output"
  LRU_CENSUS_PREFILTER=off census_with_stub_jq --sid "${S3:0:8}"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pid_forks)" -eq 5 ] || { echo "forks=$(pid_forks)"; false; }
  [ "$output" = "$WANT" ] || { echo "got: $output"; false; }
}
