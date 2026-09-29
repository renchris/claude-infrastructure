#!/usr/bin/env bats
# lr-reset-poller.sh § 1 census ingest under macOS /bin/bash 3.2 — the shell launchd runs it with.
#
# THE DEFECT. The census rows were read through `done < <(python3 - "$_cj" <<'PY' … PY)`. bash 3.2
# re-scans a process substitution's text for its closing paren without honouring heredoc
# boundaries, so the one apostrophe in the program's comments ("the parked record's") killed the
# census with `bad substitution: no closing ')'` on every tick — under 3.2 only, which is why a
# suite run by a Homebrew bash 5 never saw it. The reader is now a file (lrp_census_ingest).
#
# Both cases run under /bin/bash EXPLICITLY: the function on its own with a fixture census, and a
# whole tick with a stub cc-limited, so the call site is exercised as well as the function.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ -x /bin/bash ] || skip "no /bin/bash"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  CWD="$BATS_TEST_TMPDIR/cwd"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$CWD" "$BATS_TEST_TMPDIR/stubs"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  CJ="$BATS_TEST_TMPDIR/census.json"
  printf '{"rows":[{"sid":"c3a1","state":"RECOVERABLE","group":"next","cap":"five_hour","resets_at":1789853400,"cwd":"%s","cfg":"/x","recoverable_by_waiting":true},{"sid":"c3a2","teammate":true,"state":"RECOVERABLE","group":"next"}]}\n' \
    "$CWD" > "$CJ"
}

@test "lrp_census_ingest under /bin/bash 3.2: no bad substitution, the parked record is written" {
  local prog="$BATS_TEST_TMPDIR/ingest.sh"
  {
    printf 'STATE=%q; PARKED=%q; RESUMED=%q; LOG=%q\n' "$STATE" "$STATE/parked" "$STATE/resumed" "$STATE/poller.log"
    printf 'log() { printf "%%s\\n" "$*" >> "$LOG"; }\n'
    sed -n '/^lrp_tmpdir() {/,/^}/p;/^lrp_census_ingest() {/,/^}/p' "$POLLER"
    printf 'lrp_census_ingest %q\n' "$CJ"
  } > "$prog"
  grep -q '^lrp_census_ingest() {' "$prog"          # the function was actually extracted
  run /bin/bash "$prog"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"bad substitution"* ]] || { echo "$output"; false; }
  jq -e --arg c "$CWD" '.sid=="c3a1" and .acct=="next" and .kind=="session"
                        and .reset_at_utc=="2026-09-19T21:30:00Z" and .cwd==$c' \
    "$STATE/parked/c3a1.json" >/dev/null || { cat "$STATE/parked/c3a1.json"; false; }
  [ ! -e "$STATE/parked/c3a2.json" ]                  # the teammate row is skipped, not parked
  [ -e "$STATE/teammate-skip/c3a2" ]
  [ "$(cat "$CJ.groups")" = "$(printf 'next\tfive_hour\t1789853400')" ]
  [ -z "$(ls "$TMPDIR")" ]                            # the reader file is removed
}

@test "a whole tick under /bin/bash 3.2 reaches the census and parks from it" {
  cat > "$BATS_TEST_TMPDIR/stubs/cc-limited" <<STUB
#!/bin/bash
[ "\$1" = --reaper ] && exit 0
cat "$CJ"
STUB
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/pgrep"
  chmod +x "$BATS_TEST_TMPDIR/stubs"/*
  PATH="$BATS_TEST_TMPDIR/stubs:$PATH" LR_UPGRADE_AUTO=off LR_RESUME_DEBT_SWEEP=off \
    CC_LIMITED="$BATS_TEST_TMPDIR/stubs/cc-limited" CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg" \
    LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launch" CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty" \
    LR_SELECT_PGREP_BIN="$BATS_TEST_TMPDIR/stubs/pgrep" \
    run /bin/bash "$POLLER" --once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"bad substitution"* ]] || { echo "$output"; false; }
  grep -q "PARKED c3a1 (next, session) resets 2026-09-19T21:30:00Z" "$STATE/poller.log" \
    || { cat "$STATE/poller.log"; false; }
}
