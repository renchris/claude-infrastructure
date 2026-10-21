#!/usr/bin/env bats
# shellcheck disable=SC2016  # stub bodies carry a literal $* on purpose
# com.claude.accounts-local (docs/plans/ACCOUNTS_BOARD_FRESHNESS.md D9) — the staged plist that runs
# `claude-accounts --local-refresh` every 20 s. The shape of accounts-board.bats tests 26-27: the
# plist's OWN command line is executed, with only its 120 s bound shrunk, so what is pinned is the
# string launchd will run, not a paraphrase of it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PLIST="$REPO/launchd/staged/com.claude.accounts-local.plist"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  command -v plutil >/dev/null 2>&1 || skip "plutil is Darwin-only"
}

key() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST"; }

@test "the plist lints and lives in launchd/staged/, never the auto-installed glob dir" {
  run plutil -lint "$PLIST"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$REPO/launchd/com.claude.accounts-local.plist" ]
  [ "$(key Label)" = "com.claude.accounts-local" ]
}

@test "the plist's own command kills a tick stalled before the interpreter arms an alarm (exit 142)" {
  cmd="$(key ProgramArguments:2)"
  short="${cmd/ 120 / 1 }"                         # the real command, bound shrunk to 1 s
  [ "$short" != "$cmd" ] || { echo "the 120 s bound moved — mutation did not apply: $cmd"; false; }
  printf '#!/bin/bash\nexec /bin/sleep 30\n' > "$HOME/.claude/bin/claude-accounts"
  chmod +x "$HOME/.claude/bin/claude-accounts"
  s=$SECONDS; run /bin/bash -c "$short"; el=$(( SECONDS - s ))
  [ "$status" -eq 142 ] || { echo "not killed by SIGALRM: rc=$status $output"; false; }
  [ "$el" -lt 10 ] || { echo "took ${el}s — the bound did not fire"; false; }
}

@test "a tick that finishes inside the bound runs exactly claude-accounts --local-refresh" {
  [ "$(key ProgramArguments:0)" = "/bin/bash" ]
  [ "$(key ProgramArguments:1)" = "-c" ]
  printf '#!/bin/bash\necho "args:$*"\n' > "$HOME/.claude/bin/claude-accounts"
  chmod +x "$HOME/.claude/bin/claude-accounts"
  run /bin/bash -c "$(key ProgramArguments:2)"
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [ "$output" = "args:--local-refresh" ] || { echo "a healthy tick ran: $output"; false; }
}

@test "cadence keys: StartInterval 20 floor, keychain WatchPaths accelerator, Interactive priority" {
  [ "$(key StartInterval)" = 20 ]
  [ "$(key ThrottleInterval)" = 10 ]
  [ "$(key RunAtLoad)" = true ]
  # Interactive since 2026-10-20: Standard read 20T live, not the 31 it was meant to give (G2 R6)
  [ "$(key ProcessType)" = Interactive ]
  [ "$(key WatchPaths:0)" = /Users/chrisren/Library/Keychains/login.keychain-db ]
  run key WatchPaths:1
  [ "$status" -ne 0 ] || { echo "a second WatchPaths entry appeared: $output"; false; }
  run key LowPriorityIO
  [ "$status" -ne 0 ] || { echo "LowPriorityIO is back: $output"; false; }
  [ "$(key StandardOutPath)" = /Users/chrisren/.claude/logs/accounts-local.out.log ]
  [ "$(key StandardErrorPath)" = /Users/chrisren/.claude/logs/accounts-local.err.log ]
}

@test "both router-cache producers declare ProcessType Interactive (PRI 31), the band their readers run at" {
  # D1, G2, cc-wave-plan and recycle_repick read what keepwarm and accounts-local write; at 20 the
  # producers ran the utility band under a load their readers do not feel (LR_SUSTAINED_LOAD W7).
  local p
  for p in com.claude.accounts-local com.claude.accounts-keepwarm; do
    run /usr/libexec/PlistBuddy -c "Print :ProcessType" "$REPO/launchd/staged/$p.plist"
    [ "$status" -eq 0 ] || { echo "$p ProcessType is '$output'"; false; }
    [ "$output" = Interactive ] || { echo "$p ProcessType is '$output'"; false; }
    run /usr/libexec/PlistBuddy -c "Print :LowPriorityIO" "$REPO/launchd/staged/$p.plist"
    [ "$status" -ne 0 ] || { echo "$p has LowPriorityIO: $output"; false; }
  done
}
