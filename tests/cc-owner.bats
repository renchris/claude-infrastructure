#!/usr/bin/env bats
# cc-owner — the resolver that answers "who ALREADY runs this" before a command is handed over.
# The two tests that matter are the POLARITY ones: this script must never convert its own ignorance
# into a finding, in either direction.

setup() {
  OWNER="${BATS_TEST_DIRNAME}/../bin/cc-owner"
  # FIXTURE $HOME — and it fixes a second defect on the way.
  #
  # cc-owner:55 globs "$HOME"/Library/LaunchAgents/*.plist with NO env override, so an unfixtured
  # run reads the OPERATOR'S live agent set. These cases were therefore passing for the wrong
  # reason: they asserted the resolver works, but what they actually depended on was him happening
  # to own com.claude.deploy-live.plist. Seeding the plist makes the suite hermetic AND
  # self-contained — it now proves the RESOLVER, not the box's launchd inventory.
  #
  # WHY THIS MATTERS BEYOND HYGIENE: an unfixtured $HOME here made
  # `scripts/test-hermeticity-lint.sh --selftest` exit 1, which routes postland-verify to CUT
  # instead of GREEN (postland-verify.sh:3784-3785, contract at :523 — "never a red, and NEVER A
  # GREEN either"). No green stamp has existed since 2026-09-12T03:07Z, the commit that added this
  # file. A green-only deploy tier then pins the live layer. Two unfixtured suites held the whole
  # certification chain shut.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/Library/LaunchAgents"
  # PlistBuddy must parse it and the text must CONTAIN the token cc-owner greps for
  # (`deploy-live.sh`), because surface 1 is a substring match against the printed plist.
  cat > "$HOME/Library/LaunchAgents/com.claude.deploy-live.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claude.deploy-live</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-lc</string>
    <string>exec "$HOME/.claude/scripts/deploy-live.sh"</string>
  </array>
  <key>StartInterval</key><integer>600</integer>
</dict>
</plist>
PLIST
}

@test "a launchd-owned script resolves to its agent, whatever spelling names it" {
  # Keyed on BASENAME, not path: the measured corpus hands the same script over as an absolute
  # path, a ~-path and a repo-relative path, and the plist names it a fourth way.
  run bash "$OWNER" "bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "OWNED"
  printf '%s' "$output" | grep -q "com.claude.deploy-live"

  run bash "$OWNER" "bash ~/Development/claude-infrastructure/scripts/deploy-live.sh --force"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "com.claude.deploy-live"
}

@test "POLARITY: an unowned script is rc 1 and says so WITHOUT asserting a human is needed" {
  run bash "$OWNER" "bash /tmp/no-such-script-$$.sh"
  [ "$status" -eq 1 ]
  # The wording is the test. "no owner" must never render as "the operator must run this" — that
  # inference is the defect this tool exists to interrupt, and re-emitting it here would close the
  # loop in the wrong direction.
  printf '%s' "$output" | grep -q "NOT proof a human is needed"
}

@test "POLARITY: a command naming NO script is 'cannot resolve', never 'unowned'" {
  # 48.7% of measured emissions are this shape (/deploy, cc-blockers, open tel:…). Reporting them
  # as unowned would be a confident answer over a question this tool cannot see.
  run bash "$OWNER" "cc-blockers"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "cannot resolve"
  ! printf '%s' "$output" | grep -q "OWNED"
}

@test "--quiet is rc-only (the form a producer calls)" {
  run bash "$OWNER" --quiet "bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no argument is a usage error (rc 2), never a silent 'unowned'" {
  run bash "$OWNER"
  [ "$status" -eq 2 ]
}
