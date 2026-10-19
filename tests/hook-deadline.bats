#!/usr/bin/env bats
# hook-deadline.bats — hooks/lib/hook-deadline.sh, the Stop-renderer deadline (README §2 row #27):
# an in-time body is relayed byte-identically; a late one prints one deferral line, finishes in its own
# process group and is delivered exactly once at the next boundary (session-beat's prompt front, or
# the hook's own next run). Fixtures only: HOME, the state dir and the IDL are all under the test dir.
# No wall-clock bounds: under load a bash start alone can take seconds. A late test proves lateness
# by its OUTPUT — the deferral line can only print while the body has not finished (the claim file).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$REPO/hooks/lib/hook-deadline.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HOOK_DEADLINE=on
  export CC_HOOK_DEADLINE_DIR="$BATS_TEST_TMPDIR/hd"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/no-startup-health"
  FX="$BATS_TEST_TMPDIR/fx.sh"
  # The fixture renderer: counts its starts, sleeps FX_SLEEP, prints one systemMessage carrying an
  # ESC byte (operator-readout's colour), a stderr line, and exits FX_RC.
  printf '%s\n' '#!/bin/bash' \
    ". '$LIB'" \
    'hd_wrap fx "${FX_DL:-5}" "${FX_NOTICE:-on}" "$@"' \
    'in=$(cat)' \
    'printf "start\n" >> "$FX_STARTS"' \
    '[ "${FX_SLEEP:-0}" = 0 ] || sleep "$FX_SLEEP"' \
    '[ -n "${FX_SILENT:-}" ] && exit 0' \
    "J='{\"systemMessage\":\"FX \\u001b[1mblock\\u001b[22m done\"}'" \
    'printf "%s\n" "$J"' \
    'echo "err-line" >&2' \
    'exit "${FX_RC:-0}"' > "$FX"
  chmod +x "$FX"
  export FX_STARTS="$BATS_TEST_TMPDIR/starts"
  : > "$FX_STARTS"
  P='{"session_id":"abc-1","hook_event_name":"Stop"}'
}

wait_for() { # <shell condition> — poll up to ~20 s (the fixture bodies sleep at most a few seconds)
  local i=0
  while ! eval "$1"; do i=$((i + 1)); [ "$i" -gt 200 ] && return 1; sleep 0.1; done
}

run_fx() { printf '%s' "$P" | "$FX" 2> "$BATS_TEST_TMPDIR/err"; }

@test "in time: stdout, stderr and exit code are byte-identical to the unwrapped hook; no IDL row" {
  CC_HOOK_DEADLINE=off FX_RC=3 run run_fx
  [ "$status" -eq 3 ]
  off_out="$output"; cp "$BATS_TEST_TMPDIR/err" "$BATS_TEST_TMPDIR/err.off"
  FX_RC=3 run run_fx
  [ "$status" -eq 3 ]
  [ "$output" = "$off_out" ]
  cmp "$BATS_TEST_TMPDIR/err" "$BATS_TEST_TMPDIR/err.off"
  printf '%s' "$P" | "$FX" 2>/dev/null | cmp - <(printf '%s' "$P" | CC_HOOK_DEADLINE=off "$FX" 2>/dev/null)
  [ ! -s "$CC_IDL" ]
  [ -z "$(ls -A "$CC_HOOK_DEADLINE_DIR/run")" ]
  [ -z "$(ls -A "$CC_HOOK_DEADLINE_DIR/pending")" ]
}

@test "late: one deferral line at the deadline, then the result is filed as pending exactly once" {
  FX_SLEEP=3 FX_DL=1 run run_fx
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "fx deferred under load (1s) — its result will show at your next prompt" ]
  jq -e 'select(.hook=="hook-deadline" and .disposition=="deferred" and .reason=="fx:deadline")' "$CC_IDL" >/dev/null
  pend="$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg"
  wait_for "[ -e '$pend' ]"
  wait_for "[ -z \"\$(ls -A '$CC_HOOK_DEADLINE_DIR/run')\" ]"
  head -1 "$pend" | grep -q '^↻ fx finished late ([0-9]*s) — its result from the last stop:$'
  grep -q "$(printf 'FX \033\\[1mblock')" "$pend"
  jq -e 'select(.disposition=="late-done" and .reason=="fx:late" and .pending==true)' "$CC_IDL" >/dev/null
  [ "$(grep -c . "$FX_STARTS")" -eq 1 ]
}

@test "late result reaches the next prompt through session-beat, once, as valid JSON with its colour" {
  FX_SLEEP=2 FX_DL=1 run run_fx
  wait_for "[ -e '$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg' ]"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beat"
  run bash -c "printf '%s' '{\"session_id\":\"abc-1\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}' | '$REPO/hooks/session-beat.sh' prompt"
  [ "$status" -eq 0 ]
  msg="$(printf '%s' "$output" | jq -r .systemMessage)"
  printf '%s\n' "$msg" | head -1 | grep -q '^↻ fx finished late'
  printf '%s' "$msg" | grep -q "$(printf 'FX \033\\[1mblock')"
  [ ! -e "$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg" ]
  jq -e 'select(.disposition=="delivered" and .reason=="late-result:prompt" and .from=="fx")' "$CC_IDL" >/dev/null
  run bash -c "printf '%s' '{\"session_id\":\"abc-1\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}' | '$REPO/hooks/session-beat.sh' prompt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a pending result for ANOTHER session is not printed at this prompt" {
  mkdir -p "$CC_HOOK_DEADLINE_DIR/pending"
  printf 'other block' > "$CC_HOOK_DEADLINE_DIR/pending/zzz-9.fx.msg"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beat"
  run bash -c "printf '%s' '{\"session_id\":\"abc-1\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}' | '$REPO/hooks/session-beat.sh' prompt"
  [ -z "$output" ]
  [ -e "$CC_HOOK_DEADLINE_DIR/pending/zzz-9.fx.msg" ]
}

@test "single-flight: a run while the late body is still working starts no second body" {
  FX_SLEEP=4 FX_DL=1 run run_fx
  [ "$status" -eq 0 ]
  FX_SLEEP=4 FX_DL=1 run run_fx
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "fx still rendering the previous stop under load — it will show at your next prompt" ]
  jq -e 'select(.disposition=="busy" and .reason=="fx:single-flight")' "$CC_IDL" >/dev/null
  wait_for "[ -e '$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg' ]"
  [ "$(grep -c . "$FX_STARTS")" -eq 1 ]
}

@test "the hook's own next run: a fresh render supersedes the pending one, an empty one delivers it" {
  mkdir -p "$CC_HOOK_DEADLINE_DIR/pending"
  pend="$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg"
  printf 'OLD block' > "$pend"
  run run_fx
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "FX $(printf '\033')[1mblock$(printf '\033')[22m done" ]
  [ ! -e "$pend" ]
  jq -e 'select(.disposition=="superseded")' "$CC_IDL" >/dev/null
  printf 'OLD block' > "$pend"
  FX_SILENT=1 run run_fx
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "OLD block" ]
  [ ! -e "$pend" ]
  FX_SILENT=1 run run_fx
  [ -z "$output" ]
}

@test "a late run that finds an undelivered pending result prints it with the deferral line" {
  mkdir -p "$CC_HOOK_DEADLINE_DIR/pending"
  printf 'OLD block' > "$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg"
  FX_SLEEP=2 FX_DL=1 run run_fx
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "OLD block
fx deferred under load (1s) — its result will show at your next prompt" ]
  jq -e 'select(.disposition=="delivered" and .reason=="late-result:stop")' "$CC_IDL" >/dev/null
}

@test "notice off (teammate-auto-shutdown): a late run prints nothing at all" {
  FX_SLEEP=2 FX_DL=1 FX_NOTICE=off run run_fx
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  wait_for "[ -e '$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg' ]"
}

@test "orphaned: the wrapper is killed before its deadline, and the body still files its result" {
  ( printf '%s' "$P" | FX_SLEEP=2 FX_DL=10 "$FX" >/dev/null 2>&1 ) &
  wait_for "ls '$CC_HOOK_DEADLINE_DIR/run/'*.pid >/dev/null 2>&1"
  w="$(ls "$CC_HOOK_DEADLINE_DIR/run/"*.pid)"; w="${w%.pid}"; w="${w##*.}"
  kill -KILL "$w"
  wait_for "[ -e '$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg' ]"
  wait_for "jq -e 'select(.reason==\"fx:orphaned\")' '$CC_IDL' >/dev/null 2>&1"
}

@test "hard bound: a late body is terminated at CC_HD_HARD_S and leaves no run files" {
  CC_HD_HARD_S=1 FX_SLEEP=30 FX_DL=1 run run_fx
  [ "$status" -eq 0 ]
  wait_for "jq -e 'select(.disposition==\"late-done\" and .rc!=0)' '$CC_IDL' >/dev/null 2>&1"
  wait_for "[ -z \"\$(ls -A '$CC_HOOK_DEADLINE_DIR/run')\" ]"
  [ ! -e "$CC_HOOK_DEADLINE_DIR/pending/abc-1.fx.msg" ]
}

@test "the in-time path runs exactly one external command (rm)" {
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  for c in rm mkdir mv jq date sleep cat; do
    printf '#!/bin/bash\necho %s >> "%s"\nexec /bin/%s "$@"\n' "$c" "$BATS_TEST_TMPDIR/forks" "$c" > "$stub/$c"
    [ -x "/bin/$c" ] || printf '#!/bin/bash\necho %s >> "%s"\nexec /usr/bin/%s "$@"\n' "$c" "$BATS_TEST_TMPDIR/forks" "$c" > "$stub/$c"
    chmod +x "$stub/$c"
  done
  mkdir -p "$CC_HOOK_DEADLINE_DIR/run" "$CC_HOOK_DEADLINE_DIR/pending"
  printf '%s\n' '#!/bin/bash' ". '$LIB'" 'hd_wrap fx 5 on' 'printf "{\"systemMessage\":\"x\"}\n"' > "$BATS_TEST_TMPDIR/bare.sh"
  : > "$BATS_TEST_TMPDIR/forks"
  run bash -c "printf '%s' '$P' | PATH='$stub' /bin/bash '$BATS_TEST_TMPDIR/bare.sh'"
  [ "$output" = '{"systemMessage":"x"}' ]
  [ "$(cat "$BATS_TEST_TMPDIR/forks")" = "rm" ]
}

@test "default: under bats with CC_HOOK_DEADLINE unset the wrapper stays out of the way" {
  unset CC_HOOK_DEADLINE
  FX_SLEEP=2 FX_DL=1 run run_fx
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "FX $(printf '\033')[1mblock$(printf '\033')[22m done" ]
  [ ! -e "$CC_HOOK_DEADLINE_DIR" ]
}

@test "operator-readout is wired: a slow render defers at its deadline and arrives as pending" {
  stub="$BATS_TEST_TMPDIR/wl"
  printf '%s\n' '#!/bin/bash' 'sleep 3' 'exec "$REAL_WL" "$@"' > "$stub"; chmod +x "$stub"
  export REAL_WL="$REPO/scripts/wrap-ledger.sh" WRAP_LEDGER_BIN="$stub"
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/or" CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/none"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl" CC_BACKLOG_KICK=off CC_RESUME_DEBT_BIN=none
  : > "$CC_BACKLOG_FILE"
  CC_OPREADOUT_DEADLINE_S=1 run bash -c "printf '%s' '{\"session_id\":\"abc-1\",\"cwd\":\"$BATS_TEST_TMPDIR\"}' | '$REPO/hooks/operator-readout.sh'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "operator-readout deferred under load (1s) — its result will show at your next prompt" ]
  wait_for "[ -z \"\$(ls -A '$CC_HOOK_DEADLINE_DIR/run')\" ]"
  jq -e 'select(.disposition=="late-done" and .reason=="operator-readout:late")' "$CC_IDL" >/dev/null
}

@test "operator-readout: --render never engages the wrapper" {
  run "$REPO/hooks/operator-readout.sh" --render --cwd "$BATS_TEST_TMPDIR" </dev/null
  [ "$status" -eq 0 ]
  [ ! -e "$CC_HOOK_DEADLINE_DIR" ]
}

@test "teammate-auto-shutdown is wired: in time its output is byte-identical to the unwrapped hook" {
  export TEAMMATE_SHUTDOWN_DISABLED=1
  CC_HOOK_DEADLINE=off run bash -c "printf '%s' '$P' | '$REPO/hooks/teammate-auto-shutdown.sh'"
  off="$output"; off_rc="$status"
  run bash -c "printf '%s' '$P' | '$REPO/hooks/teammate-auto-shutdown.sh'"
  [ "$status" -eq "$off_rc" ]
  [ "$output" = "$off" ]
  [ -d "$CC_HOOK_DEADLINE_DIR/run" ]
  [ -z "$(ls -A "$CC_HOOK_DEADLINE_DIR/run")" ]
}
