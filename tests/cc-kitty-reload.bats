#!/usr/bin/env bats
# cc-kitty-reload — a landed kitty config reaching an ALREADY-RUNNING kitty, unattended.
#
# The axis this suite exists for is the one a fixture is most likely to hold constant: the PS
# census must tell `kitty` from `kitten` (both live, both under the same app bundle, differing only
# in basename), and the stamp must fail CLOSED on a partial pass. A fixture whose processes all
# share one shape cannot express either.

setup() {
  REPO="${BATS_TEST_DIRNAME}/.."
  TOOL="$REPO/bin/cc-kitty-reload"
  TMP="$BATS_TEST_TMPDIR"
  # HERMETIC: every default in the subject is $HOME-relative (the stamp above all), so a missed
  # seam must land in the tmpdir and never on the operator's live ~/.
  export HOME="$TMP/home"; mkdir -p "$HOME"
  mkdir -p "$TMP/conf" "$TMP/bin"
  printf 'font_size 18\n' > "$TMP/conf/kitty.conf"
  export CC_KITTY_CONF_DIR="$TMP/conf"
  export CC_KITTY_RELOAD_STAMP="$TMP/stamp"
  export CC_KITTY_RELOAD_PS="$TMP/bin/ps"
  export CC_KITTY_RELOAD_KILL="$TMP/bin/kill"
  # production shape: the app's comm is the FULL bundle path, and a kitten sits beside it
  cat > "$TMP/bin/ps" <<'PS'
#!/bin/sh
echo "  501 /Applications/kitty.app/Contents/MacOS/kitty"
echo "  777 /Applications/kitty.app/Contents/MacOS/kitten"
echo "  888 /usr/bin/kittygrep"
PS
  cat > "$TMP/bin/kill" <<'KILL'
#!/bin/sh
echo "$@" >> "$KILLLOG"
exit 0
KILL
  chmod +x "$TMP/bin/ps" "$TMP/bin/kill"
  export KILLLOG="$TMP/killlog"
  : > "$KILLLOG"
}

@test "a changed config signals every live kitty and advances the stamp" {
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=reloaded"* ]] || false
  [[ "$output" == *"instances=1"* ]] || false
  [ -s "$CC_KITTY_RELOAD_STAMP" ]
  [[ "$(cat "$KILLLOG")" == *"-USR1 501"* ]] || false
}

@test "the census takes kitty and NOT kitten, and not a name that merely contains it" {
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  if grep -q '777' "$KILLLOG"; then echo "signalled a kitten: $(cat "$KILLLOG")"; return 1; fi
  if grep -q '888' "$KILLLOG"; then echo "signalled kittygrep: $(cat "$KILLLOG")"; return 1; fi
  [ "$(grep -c . "$KILLLOG")" -eq 1 ]
}

@test "MUTANT CONTROL: a substring census would pick up the kitten and this fixture sees it" {
  run bash -c "\"$CC_KITTY_RELOAD_PS\" -axo pid=,comm= | awk '/kitty/ { print \$1 }'"
  [ "$status" -eq 0 ]
  [[ "$output" == *777* ]] || false
  [[ "$output" == *888* ]] || false
}

@test "an unchanged config is a silent no-op that signals nothing" {
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  : > "$KILLLOG"
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=unchanged"* ]] || false
  [ ! -s "$KILLLOG" ]
}

@test "a partial pass FAILS CLOSED: rc 5 and the stamp does not move" {
  cat > "$CC_KITTY_RELOAD_KILL" <<'KILL'
#!/bin/sh
exit 1
KILL
  chmod +x "$CC_KITTY_RELOAD_KILL"
  run bash "$TOOL"
  [ "$status" -eq 5 ]
  [[ "$output" == *"verdict=partial"* ]] || false
  [ ! -f "$CC_KITTY_RELOAD_STAMP" ]
}

@test "no running kitty still advances the stamp — a later kitty parses the file itself" {
  cat > "$CC_KITTY_RELOAD_PS" <<'PS'
#!/bin/sh
echo "  123 /bin/zsh"
PS
  chmod +x "$CC_KITTY_RELOAD_PS"
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=no-instances"* ]] || false
  [ -s "$CC_KITTY_RELOAD_STAMP" ]
  [ ! -s "$KILLLOG" ]
}

@test "--would signals nothing and writes no stamp" {
  run bash "$TOOL" --would
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=would"* ]] || false
  [ ! -f "$CC_KITTY_RELOAD_STAMP" ]
  [ ! -s "$KILLLOG" ]
}

@test "the key follows a SYMLINKED config — the live path is a link into the checkout" {
  real="$BATS_TEST_TMPDIR/real.conf"
  printf 'font_size 18\n' > "$real"
  rm -f "$CC_KITTY_CONF_DIR/kitty.conf"
  ln -s "$real" "$CC_KITTY_CONF_DIR/kitty.conf"
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  first="$(cat "$CC_KITTY_RELOAD_STAMP")"
  printf 'font_size 20\n' > "$real"          # content changes THROUGH the link, link itself does not
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=reloaded"* ]] || false
  if [ "$(cat "$CC_KITTY_RELOAD_STAMP")" = "$first" ]; then
    echo "key did not follow the symlink — a landed change would deploy as unchanged"; return 1
  fi
}

@test "a dangling link is skipped, and no readable conf at all is an error not a silent pass" {
  ln -s "$BATS_TEST_TMPDIR/nowhere.conf" "$CC_KITTY_CONF_DIR/dangling.conf"
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=reloaded"* ]] || false
  rm -f "$CC_KITTY_CONF_DIR"/*.conf
  run bash "$TOOL"
  [ "$status" -eq 5 ]
  [[ "$output" == *"no readable"* ]] || false
}

@test "an unknown argument is refused rather than silently treated as a live run" {
  run bash "$TOOL" --definitely-not-a-flag
  [ "$status" -eq 2 ]
  [ ! -s "$KILLLOG" ]
}

@test "deploy-live calls it on BOTH paths, for the reason migrations_converge has two sites" {
  # The unconditional call is the catch-up: it runs even when the fetch fails or the advance
  # refuses, so a config that landed on some earlier tick still reaches a running kitty. The
  # post-advance call is the only one that can act in the SAME cycle as the merge that changed the
  # config bytes — without it the deploy is correct but always one 600s tick late.
  # `\([ ]\|$\)` keeps the DEFINITION line (`kitty_config_reload() {`) out of the count, so this
  # counts call sites and cannot be satisfied by the function merely existing.
  run grep -c '^kitty_config_reload\([ ]\|$\)' "$REPO/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
  run grep -q 'kitty_config_reload() {' "$REPO/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
}

@test "it does NOT sit between link_refresh and migrations_converge — that adjacency is pinned" {
  # tests/deploy-migrations.bats case 2 asserts migrations_converge is on the line after
  # link_refresh, as its proof that the unconditional call was not nested under the advance.
  # Inserting anything between them reddens that suite while changing nothing about this one, so
  # the constraint is pinned HERE too rather than re-learned from a land gate (it cost one).
  run bash -c "grep -A1 '^link_refresh\$' '$REPO/scripts/deploy-live.sh' | tail -1"
  [ "$status" -eq 0 ]
  [[ "$output" == "migrations_converge" ]] || false
}

@test "deploy-live's dry run goes through --would, so a platter read never relayouts a window" {
  run awk '/^kitty_config_reload\(\)/,/^}/' "$REPO/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY_RUN"* ]] || false
  [[ "$output" == *"--would"* ]] || false
}

@test "a changed config also reconciles per-window spacing overrides, and only then" {
  # `kitty @ set-spacing` is a SECOND scope that outlives load-config and SIGUSR1: a pane that was
  # ever its subject keeps its own padding forever while the config says otherwise. MEASURED on the
  # operator's live kitty — 414=46 441=46 341=47 lines, equal widths, one tab — and the extra row
  # did NOT follow the focus across three moves, so it was a stale per-window override on 341, not
  # an active/inactive difference. Reset to default equalised all three at 46.
  mkdir -p "$TMP/sockdir"
  : > "$TMP/sockdir/kitty-123"   # a regular file, not a socket — the loop must skip it
  export CC_KITTY_SOCKET_DIR="$TMP/sockdir"
  export CC_KITTY_BIN="$TMP/bin/kittystub"
  cat > "$TMP/bin/kittystub" <<'STUB'
#!/bin/sh
echo "$@" >> "$KITTYLOG"
STUB
  chmod +x "$TMP/bin/kittystub"
  export KITTYLOG="$TMP/kittylog"; : > "$KITTYLOG"
  run bash "$TOOL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spacing=reconciled"* ]] || false
  # no SOCKET present, so nothing was invoked — a plain file must not be treated as one
  [ ! -s "$KITTYLOG" ]
  # and an unchanged tick must not reconcile at all
  : > "$KITTYLOG"
  run bash "$TOOL"
  [[ "$output" == *"verdict=unchanged"* ]] || false
  [ ! -s "$KITTYLOG" ]
}
