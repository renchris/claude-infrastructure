#!/usr/bin/env bats
# kitty-build-swap — stage, swap and roll back the patched kitty, on FIXTURE bundles.
#
# WHY THIS SUITE EXISTS. scripts/kitty-build-swap.sh renames the operator's daily terminal. The one
# property that matters is that every path out of a swap gets back to stock: the inverse verb must
# restore the stock bundle AND the ⌘⇧B link by content, a half-finished swap must undo itself, and
# no verb may touch the live app without --confirm naming it. Real bundles cannot be swapped in a
# test, so each fixture "bundle" is a directory whose Contents/MacOS/kitty answers the same +runpy
# probe the script asks a real build ("text" = patched, "STOCK" = stock).
#
# HERMETICITY. Every path the script reads or writes is redirected into $BATS_TEST_TMPDIR through
# its KITTY_SWAP_* variables; nothing here can reach /Applications, ~/.config/kitty or
# ~/.claude/autonomy.

SCRIPT="${BATS_TEST_DIRNAME}/../scripts/kitty-build-swap.sh"

mkbundle() {  # mkbundle <dir> <probe answer>
  mkdir -p "$1/Contents/MacOS"
  printf '#!/bin/bash\necho %s\n' "$2" > "$1/Contents/MacOS/kitty"
  chmod +x "$1/Contents/MacOS/kitty"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>0.48.2</string></dict></plist>\n' > "$1/Contents/Info.plist"
}

setup() {
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  export KITTY_SWAP_APPS="$T/Applications" KITTY_SWAP_CONF_DIR="$T/conf" KITTY_SWAP_REPO="$T/repo" \
         KITTY_SWAP_STATE="$T/state" KITTY_SWAP_FROM="$T/build/kitty.app" KITTY_SWAP_TRASH="$T/trash"
  mkdir -p "$T/Applications" "$T/conf" "$T/repo/config" "$T/state"
  mkbundle "$T/Applications/kitty.app" STOCK
  mkbundle "$T/build/kitty.app" text
  printf 'stock on\n' > "$T/repo/config/kitty-title-on.conf"
  printf 'band on\n' > "$T/repo/config/kitty-title-band-on.conf"
  ln -s "$T/repo/config/kitty-title-on.conf" "$T/conf/kitty-title-on.conf"
  LIVE="$T/Applications/kitty.app"
}

@test "stage refuses a stock source and stages a patched one" {
  run bash "$SCRIPT" stage --from "$LIVE"
  [ "$status" -eq 1 ]
  [ ! -e "$T/Applications/kitty.app.staged" ]
  run bash "$SCRIPT" stage
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=STAGED"* ]] || false
  [ "$("$T/Applications/kitty.app.staged/Contents/MacOS/kitty")" = text ]
}

@test "restaging moves the old staged bundle to the trash, never deletes it" {
  bash "$SCRIPT" stage >/dev/null
  run bash "$SCRIPT" stage
  [ "$status" -eq 0 ]
  run ls "$T/trash"
  [[ "$output" == kitty.app.staged-* ]]
}

@test "arm refuses with nothing staged, then names the swap command in the marker" {
  run bash "$SCRIPT" arm
  [ "$status" -eq 1 ]
  [ ! -e "$T/state/kitty-restart-pending" ]
  bash "$SCRIPT" stage >/dev/null
  run bash "$SCRIPT" arm
  [ "$status" -eq 0 ]
  grep -q "swap --confirm $LIVE" "$T/state/kitty-restart-pending"
}

@test "swap refuses without --confirm naming the live bundle" {
  bash "$SCRIPT" stage >/dev/null
  run bash "$SCRIPT" swap
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" swap --confirm /Applications/kitty.app.other
  [ "$status" -eq 1 ]
  [ "$("$LIVE/Contents/MacOS/kitty")" = STOCK ]
}

@test "swap --dry-run passes its preconditions and changes nothing" {
  bash "$SCRIPT" stage >/dev/null
  run bash "$SCRIPT" swap --confirm "$LIVE" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=DRY-RUN-OK"* ]] || false
  [ "$("$LIVE/Contents/MacOS/kitty")" = STOCK ]
  [ ! -e "$T/Applications/kitty.app.stock" ]
  [ "$(readlink "$T/conf/kitty-title-on.conf")" = "$T/repo/config/kitty-title-on.conf" ]
}

@test "swap puts the patched bundle live, keeps stock, and points ⌘⇧B at the band" {
  bash "$SCRIPT" stage >/dev/null
  run bash "$SCRIPT" swap --confirm "$LIVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=SWAPPED"* ]] || false
  [ "$("$LIVE/Contents/MacOS/kitty")" = text ]
  [ "$("$T/Applications/kitty.app.stock/Contents/MacOS/kitty")" = STOCK ]
  [ "$(readlink "$T/conf/kitty-title-on.conf")" = "$T/repo/config/kitty-title-band-on.conf" ]
  run bash "$SCRIPT" swap --confirm "$LIVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=ALREADY"* ]]
}

@test "rollback after a swap restores stock and the ⌘⇧B link by content" {
  bash "$SCRIPT" stage >/dev/null
  bash "$SCRIPT" swap --confirm "$LIVE" >/dev/null
  run bash "$SCRIPT" rollback --confirm "$LIVE" --dry-run
  [ "$status" -eq 0 ]
  [ "$("$LIVE/Contents/MacOS/kitty")" = text ]
  run bash "$SCRIPT" rollback --confirm "$LIVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=ROLLED-BACK"* ]] || false
  [ "$("$LIVE/Contents/MacOS/kitty")" = STOCK ]
  [ ! -e "$T/Applications/kitty.app.stock" ]
  [ "$("$T/Applications/kitty.app.staged/Contents/MacOS/kitty")" = text ]
  [ "$(readlink "$T/conf/kitty-title-on.conf")" = "$T/repo/config/kitty-title-on.conf" ]
}

@test "rollback with no stock backup refuses and changes nothing" {
  run bash "$SCRIPT" rollback --confirm "$LIVE"
  [ "$status" -eq 1 ]
  [ "$("$LIVE/Contents/MacOS/kitty")" = STOCK ]
}

@test "swap with nothing staged refuses and leaves stock live" {
  run bash "$SCRIPT" swap --confirm "$LIVE"
  [ "$status" -eq 1 ]
  [ "$("$LIVE/Contents/MacOS/kitty")" = STOCK ]
  [ ! -e "$T/Applications/kitty.app.stock" ]
}

@test "verify refuses while no kitty has started from the swapped bundle" {
  bash "$SCRIPT" stage >/dev/null
  bash "$SCRIPT" swap --confirm "$LIVE" >/dev/null
  bash "$SCRIPT" arm >/dev/null || true
  run bash "$SCRIPT" verify --clear-marker
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=NOT-RESTARTED"* ]]
}

# ── build --no-band (2026-10-02, W3 P6): the talk-thread fix ships without the title band ──

mksrc() {  # mksrc <dir> <tag>: a tiny git tree standing in for the kitty checkout, never ~/ktb
  mkdir -p "$1" && printf 'x\n' > "$1/f" && git -C "$1" init -q &&
    git -C "$1" add f && git -C "$1" -c user.name=t -c user.email=t@t commit -qm base && git -C "$1" tag "$2"
  mkdir -p "$T/repo/docs/patches"
  cp "$BATS_TEST_DIRNAME"/../docs/patches/kitty-{upstream-defects,talk-thread-survives-v0.48.2,window-title-band}.patch "$T/repo/docs/patches/"
}

@test "build --no-band lists exactly the two fix patches, in order, never the title band" {
  run bash "$SCRIPT" build --no-band --list-patches
  [ "$status" -eq 0 ]
  [ "$output" = "$T/repo/docs/patches/kitty-upstream-defects.patch
$T/repo/docs/patches/kitty-talk-thread-survives-v0.48.2.patch" ]
  mksrc "$T/src" v0.48.2
  run bash "$SCRIPT" build --no-band --src "$T/src" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=DRY-RUN-OK"* ]] || false
  [ "$(grep -c '^patch: ' <<<"$output")" -eq 2 ]
  [[ "$output" != *title-band* ]] || false
  [ -z "$(git -C "$T/src" status --porcelain)" ]
  run bash "$SCRIPT" build --src "$T/src" --dry-run
  [ "$status" -eq 2 ]
}

@test "build refuses a src tree that is dirty or not at v0.48.2" {
  mksrc "$T/wrong" v0.49.0
  run bash "$SCRIPT" build --no-band --src "$T/wrong" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git tree at v0.48.2"* ]] || false
  mksrc "$T/dirty" v0.48.2
  printf 'y\n' > "$T/dirty/f"
  run bash "$SCRIPT" build --no-band --src "$T/dirty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"tracked changes"* ]] || false
  [ "$(cat "$T/dirty/f")" = y ]
}

@test "a no-band build probes patched-noband, stages, swaps without touching ⌘⇧B, rolls back" {
  NB="$T/nb/kitty.app"
  mkbundle "$NB" STOCK
  mkdir -p "$NB/Contents/Resources/kitty/kitty"
  printf 'accept() on talk socket failed, still serving\n' > "$NB/Contents/Resources/kitty/kitty/fast_data_types.so"
  run bash "$SCRIPT" stage --from "$NB"
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" stage --no-band --from "$NB"
  [ "$status" -eq 0 ]
  [[ "$output" == *"patched-noband"* ]] || false
  run bash "$SCRIPT" swap --confirm "$LIVE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=SWAPPED"* ]] || false
  [ -e "$LIVE/Contents/Resources/kitty/kitty/fast_data_types.so" ]
  [ "$(readlink "$T/conf/kitty-title-on.conf")" = "$T/repo/config/kitty-title-on.conf" ]
  run bash "$SCRIPT" rollback --confirm "$LIVE"
  [ "$status" -eq 0 ]
  [ ! -e "$LIVE/Contents/Resources/kitty/kitty/fast_data_types.so" ]
  [ "$(readlink "$T/conf/kitty-title-on.conf")" = "$T/repo/config/kitty-title-on.conf" ]
}

# Static check on the patch TEXT, not a build. What it proves: in the patched accept_peer the only
# `return false` lines (the returns that send talk_loop to `goto end`) are the shutdown one and the
# one inside the EBADF/ENOTSOCK/EINVAL branch; the old unconditional `return false` and its perror
# are removed; the patch adds no `goto end`. It does not prove the C compiles; the build does that.
@test "talk-thread patch: accept_peer returns false only for shutdown and the three listener errnos" {
  P="$BATS_TEST_DIRNAME/../docs/patches/kitty-talk-thread-survives-v0.48.2.patch"
  hunk="$(awk '/^diff --git a\/kitty\/child-monitor.c/{on=1; next} /^diff --git/{on=0} on' "$P")"
  run awk '/^\+/ && /err == EBADF \|\| err == ENOTSOCK \|\| err == EINVAL/ {inb=1; next}
           inb && /^\+ *}/ {inb=0; next}
           /^\+.*return false;/ { if (inb) listener++; else if (/if \(shutting_down\) return false;/) shut++; else stray++ }
           END { printf "%d %d %d", listener, shut, stray }' <<<"$hunk"
  [ "$output" = "1 1 0" ]
  ! grep -qE '^\+.*goto end' <<<"$hunk" || false
  grep -qE '^-.*perror\("accept\(\) on talk socket failed!"\);' <<<"$hunk"
  grep -qE '^-        return false;$' <<<"$hunk"
  grep -qE '^\+.*still serving' <<<"$hunk"
  ! grep -qE '^\+.*perror' <<<"$hunk"
}
