#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# A stray com.reso.* LaunchAgent pages (lr-wake 2026-10-18, REPORT §5 Q9 provenance half; Wave G).
#
# At 06:35Z a lead session installed com.reso.drain-to-next3, whose program it had just written to
# ~/.reso/limit-recover/listeners/drain-v2.sh; it ran 12 h and 30+ rotates unseen.
# scripts/checks/launchagent-provenance.sh must:
#   · page once on a com.reso.* agent whose program is in no git checkout and whose plist this repo
#     does not ship (the drain's exact shape), exit 1, and name it;
#   · stay silent on the repo's own plists and on agents whose program lives in a checkout (the
#     operator's product repos install theirs from their own trees);
#   · page again only for a re-installed plist with new bytes; never load or unload anything.
# [RED] cases fail on the tree before the check exists.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  CHECK="$REPO/scripts/checks/launchagent-provenance.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  LA="$BATS_TEST_TMPDIR/LaunchAgents"; mkdir -p "$LA"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LR_PAGE_ONCE_BIN="$STUBS/lr-page"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.log"\necho "lr-page: verdict=posted"\n' "$BATS_TEST_TMPDIR" > "$LR_PAGE_ONCE_BIN"
  printf '#!/bin/bash\necho "launchctl $*" >> "%s/launchctl.log"\n' "$BATS_TEST_TMPDIR" > "$STUBS/launchctl"
  chmod +x "$STUBS/"*
  export PATH="$STUBS:$PATH"
  # the drain's shape: a program under ~/.reso, outside any checkout
  mkdir -p "$HOME/.reso/limit-recover/listeners"
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.reso/limit-recover/listeners/drain-v2.sh"
  # a product repo's agent: its program inside a git checkout
  PROD="$BATS_TEST_TMPDIR/reso-qa-runner"; mkdir -p "$PROD/scripts"
  git -C "$PROD" init -q
  printf '#!/bin/bash\nexit 0\n' > "$PROD/scripts/qa-nightly-run.sh"
  plist "$LA/com.reso.qa-nightly.plist" com.reso.qa-nightly "$PROD/scripts/qa-nightly-run.sh"
  # this repo's own plist, copied in as install.sh would
  cp "$REPO/scripts/limit-recover/com.reso.lr-reset-poller.plist" "$LA/"
}
plist() { # $1=path $2=label $3=program
  cat > "$1" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$2</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$3</string></array>
</dict></plist>
EOF
}
pages() { [ -f "$BATS_TEST_TMPDIR/pages.log" ] && wc -l < "$BATS_TEST_TMPDIR/pages.log" | tr -d ' ' || echo 0; }

@test "1 [RED] the drain-shaped stray plist pages once, exits 1 and is named" {
  plist "$LA/com.reso.drain-to-next3.plist" com.reso.drain-to-next3 "$HOME/.reso/limit-recover/listeners/drain-v2.sh"
  run bash "$CHECK" --dir "$LA"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "${lines[0]}" == "launchagent-provenance: verdict=unshipped n=1 "* ]] || { echo "$output"; false; }
  [ "${lines[1]}" = "UNSHIPPED com.reso.drain-to-next3 program=$HOME/.reso/limit-recover/listeners/drain-v2.sh" ] || { echo "$output"; false; }
  [ "$(pages)" = 1 ] || { cat "$BATS_TEST_TMPDIR/pages.log"; false; }
  grep -q 'com.reso.drain-to-next3' "$BATS_TEST_TMPDIR/pages.log"
  # a second run is still RED but does not page again
  run bash "$CHECK" --dir "$LA"
  [ "$status" -eq 1 ]
  [ "$(pages)" = 1 ]
  # nothing was loaded or unloaded
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.log" ]
}

@test "2 [RED] a re-installed stray plist with new bytes pages again" {
  plist "$LA/com.reso.drain-to-next3.plist" com.reso.drain-to-next3 "$HOME/.reso/limit-recover/listeners/drain-v2.sh"
  run bash "$CHECK" --dir "$LA"
  printf '<!-- v2 -->\n' >> "$LA/com.reso.drain-to-next3.plist"
  run bash "$CHECK" --dir "$LA"
  [ "$status" -eq 1 ]
  [ "$(pages)" = 2 ] || { cat "$BATS_TEST_TMPDIR/pages.log"; false; }
}

@test "3 CONTROL the repo's own plist and a checkout's agent are clean; --no-page never pages" {
  run bash "$CHECK" --dir "$LA"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "launchagent-provenance: verdict=clean dir=$LA" ]
  plist "$LA/com.reso.tmp-launcher.plist" com.reso.tmp-launcher "$BATS_TEST_TMPDIR/launcher.sh"
  printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/launcher.sh"
  run bash "$CHECK" --dir "$LA" --no-page
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(pages)" = 0 ]
}

@test "4 no verdict on an unreadable dir (rc 2), never a clean read" {
  run bash "$CHECK" --dir "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=no-verdict"* ]]
}

@test "5 the reconciler daemon, run from the ~/.claude symlink farm, still reaches this check" {
  # its launchd job cds into ~/.claude/scripts/limit-recover, where scripts/checks/ is not deployed
  run bash -c 'cd "$1/scripts/limit-recover" && python3 -m unittest lr_recon.tests.test_wave_g.ProvenanceReach 2>&1' _ "$REPO"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
