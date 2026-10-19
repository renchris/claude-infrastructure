#!/usr/bin/env bats
# shellcheck disable=SC2329  # every stub here is invoked by the functions extracted from handoff-fire.sh
# Item 2891c7ba7dd9 (2026-10-17). With kitty's remote control timing out (screen locked, kitty
# App-Napped), three `--tab` fires each printed "Nothing was launched" (rc 1) — and SIX sessions
# started ~40 min later (panes 321-326): spawn()'s bg-tab arm read the expiry as a refusal and retried,
# and kitty queued BOTH launches and ran them once it caught up. Now an expiry is UNKNOWN end to end —
# kt_launch rc 13, it2py bgtab rc 13, it2_bgtab rc 13 — and spawn says `bgtab-outcome-unknown`, names
# the >=40 min wait, never retries, keeps the worktree (FIRE_SPAWN_UNKNOWN) and exits 124.
#
# Every assertion is `[ ]`, `run`+status, or `… || false` (bats errexit exemption on `[[ ]]`).
#
# lr-wake 2026-10-18 (Wave E): kt_launch now REFUSES --type=tab outright (no kitty tabs, ever), so its
# expiry cases below launch --type=os-window — the surface that still goes through kt_launch. The
# bg-tab and tab arms of spawn() keep their UNKNOWN contract; under kitty they now PLACE through the
# policy rather than open a tab (tests/handoff-fire-no-tab.bats).

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): absent paths, sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset KITTY_WINDOW_ID KITTY_LISTEN_ON CC_TERM_KITTY_TO
  eval "$(sed -n '/^kt_launch() {/,/^}/p;/^it2_bgtab() {/,/^}/p;/^spawn() {/,/^}/p' "$HF")"
  in_kitty() { return 0; }
  it2_land() { echo "$1" > "$BATS_TEST_TMPDIR/land"; return 0; }
  CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  export SURFACE=bg-tab FIRING_SID=22 FOLLOW=0 FIRE_SPAWN_UNKNOWN=0 ANCHOR_INTENT=1 CMD="echo test"
  HF_ARGV=(); export HF_ARGV
}

# ── kt_launch: an expiry is UNKNOWN even over a readable, empty list ──────────────────────────────

@test "kt_launch: a timeout(1) expiry (rc 124) with no pane carrying the command YET ⇒ rc 13, not an empty success" {
  kt() { return 124; }
  hf_adopt_split_pane() { return 1; }          # the list READ cleanly and shows nothing — still not a verdict
  run kt_launch --type=os-window
  [ "$status" -eq 13 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"outcome UNKNOWN"* ]] || false
}

@test "kt_launch: kitty's own 'Timed out waiting for a response' (rc 1) is an expiry too ⇒ rc 13" {
  kt() { echo "Error: Timed out waiting for a response from kitty" >&2; return 1; }
  hf_adopt_split_pane() { return 1; }
  run kt_launch --type=os-window
  [ "$status" -eq 13 ] || { echo "rc=$status out=$output"; false; }
}

@test "kt_launch: an expiry whose pane IS found is ADOPTED, not UNKNOWN" {
  kt() { return 124; }
  hf_adopt_split_pane() { echo 321; }
  run --separate-stderr kt_launch --type=os-window
  [ "$status" -eq 0 ] && [ "$output" = 321 ] || { echo "rc=$status out=$output"; false; }
}

@test "kt_launch CONTROL: a warning on stderr beside a real id still yields the id" {
  kt() { echo "warning: something cosmetic" >&2; echo 77; }
  run --separate-stderr kt_launch --type=os-window
  [ "$status" -eq 0 ] && [ "$output" = 77 ] || { echo "rc=$status out=$output"; false; }
}

# ── it2_bgtab: three states, the rc is never flattened ──────────────────────────────────────────

@test "it2_bgtab: it2py rc 13 / 124 / 137 ⇒ 13 (UNKNOWN); rc 1 ⇒ 1 (refusal); success ⇒ the id" {
  for r in 13 124 137; do
    eval "it2py() { return $r; }"
    run it2_bgtab 22; [ "$status" -eq 13 ] || { echo "it2py rc $r → $status"; false; }
  done
  it2py() { return 1; }
  run it2_bgtab 22; [ "$status" -eq 1 ]
  it2py() { echo "Created new pane: 77"; }
  run it2_bgtab 22; [ "$status" -eq 0 ] && [ "$output" = 77 ]
}

# ── spawn bg-tab: the incident, and its controls ────────────────────────────────────────────────

@test "spawn bg-tab: an UNKNOWN launch is NOT retried, says bgtab-outcome-unknown + the 40 min wait, exits 124" {
  it2_bgtab() { echo x >> "$CALLS"; return 13; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 124 ] || { echo "rc=$rc"; cat "$BATS_TEST_TMPDIR/err"; false; }
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 1 ] || { echo "launched $(wc -l < "$CALLS") times — the retry queues a SECOND session"; false; }
  [ "$FIRE_SPAWN_UNKNOWN" = 1 ] || false
  grep -q 'bgtab-outcome-unknown' "$BATS_TEST_TMPDIR/err"
  grep -q '40 min' "$BATS_TEST_TMPDIR/err"
  ! grep -qi 'nothing was launched' "$BATS_TEST_TMPDIR/err" || { cat "$BATS_TEST_TMPDIR/err"; false; }
  [ ! -f "$BATS_TEST_TMPDIR/land" ] || false
}

@test "spawn bg-tab: a refusal then an UNKNOWN retry ⇒ still UNKNOWN (124), never 'Nothing was launched'" {
  it2_bgtab() { echo x >> "$CALLS"; [ "$(wc -l < "$CALLS")" -ge 2 ] && return 13; return 1; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 124 ] || { echo "rc=$rc"; cat "$BATS_TEST_TMPDIR/err"; false; }
  ! grep -qi 'nothing was launched' "$BATS_TEST_TMPDIR/err" || false
}

@test "spawn bg-tab CONTROL: a plain refusal is retried once and still says 'Nothing was launched' (rc 1)" {
  it2_bgtab() { echo x >> "$CALLS"; return 1; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 1 ] || { echo "rc=$rc"; false; }
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 2 ] || false
  [ "$FIRE_SPAWN_UNKNOWN" = 0 ] || false
  grep -q 'Nothing was launched' "$BATS_TEST_TMPDIR/err"
}

@test "spawn bg-tab CONTROL: a created tab lands as before" {
  it2_bgtab() { printf 77; }
  rc=0; spawn 2>/dev/null || rc=$?
  [ "$rc" -eq 0 ] && [ "$(cat "$BATS_TEST_TMPDIR/land")" = 77 ] || { echo "rc=$rc"; false; }
}

# ── spawn tab (--follow): the same defect one arm over ──────────────────────────────────────────

@test "spawn tab: as_tab UNKNOWN or ERR(124) is NOT retried and exits 124; NOTFOUND is retried and refuses" {
  export SURFACE=tab FOLLOW=1
  as_tab() { echo x >> "$CALLS"; echo UNKNOWN; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 124 ] || { echo "rc=$rc"; cat "$BATS_TEST_TMPDIR/err"; false; }
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 1 ] || false
  grep -q 'bgtab-outcome-unknown' "$BATS_TEST_TMPDIR/err"
  : > "$CALLS"; FIRE_SPAWN_UNKNOWN=0
  as_tab() { echo x >> "$CALLS"; return 124; }
  rc=0; spawn 2>/dev/null || rc=$?
  [ "$rc" -eq 124 ] || { echo "rc=$rc"; false; }
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 1 ] || false
  [ "$FIRE_SPAWN_UNKNOWN" = 1 ] || false
  : > "$CALLS"; FIRE_SPAWN_UNKNOWN=0
  as_tab() { echo x >> "$CALLS"; echo NOTFOUND; }
  rc=0; spawn 2> "$BATS_TEST_TMPDIR/err" || rc=$?
  [ "$rc" -eq 1 ] || { echo "rc=$rc"; false; }
  [ "$(wc -l < "$CALLS" | tr -d ' ')" = 2 ] || false
  grep -q 'Nothing was launched' "$BATS_TEST_TMPDIR/err"
}
