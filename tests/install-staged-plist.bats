#!/usr/bin/env bats
# install.sh — STAGED plists must never be installed by running the installer.
#
# The failure this guards is silent and expensive: `install.sh` bootstraps every plist in
# launchd/, so landing a staged one there activates it the next time anyone runs the installer.
# For com.claude.relogin that means unattended credential re-auth starting because someone
# ran a setup script — the exact thing its own header forbids.
#
# These tests read BOTH sides off disk (the needle out of install.sh, the marker out of the
# plists) so nothing here restates the constant it is checking. That is the point: the realistic
# regression is a reworded plist header that the guard silently stops matching, and a test
# carrying its own copy of the string cannot see it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INSTALL="$REPO/install.sh"
  # The needle install.sh ACTUALLY greps for, extracted from the guard itself.
  NEEDLE_RAW="$(sed -n "s/.*grep -q '\([^']*\)' \"\$plist\".*/\1/p" "$INSTALL" | head -1)"
  # FAIL CLOSED on a failed extraction. An empty needle is not "no marker" — `grep -q ""`
  # matches EVERY file, which would invert the two census tests below into declaring every job
  # staged. Substitute a pattern that matches nothing so a missing guard reads as "nothing is
  # staged" (assertions fail cleanly) instead of "everything is". Learned from this suite's own
  # RED-proof run.
  NEEDLE="${NEEDLE_RAW:-__STAGED_GUARD_NOT_FOUND__}"
}

@test "the guard exists and its needle is extractable from install.sh" {
  [ -n "$NEEDLE_RAW" ]
}

@test "the staged plist carries the marker install.sh greps for (round-trip, both off disk)" {
  local staged="$REPO/launchd/com.claude.relogin.plist"
  [ -f "$staged" ]
  grep -q "$NEEDLE" "$staged"
}

@test "the guard SKIPS before it copies — a guard after copy_file is a no-op" {
  # Anchored on the MARKER grep specifically, not on any `continue`: the loop already opens with
  # `[[ -f "$plist" ]] || continue`, so a bare continue-before-copy search passes even with the
  # staged guard deleted (it did, on this suite's RED-proof run — a dead assertion).
  local body guard_line copy_line
  body="$(awk '/^# --- LaunchAgents \(global only\) ---/,/^  # --- Version directory ---/' "$INSTALL")"
  guard_line="$(printf '%s\n' "$body" | grep -n 'grep -q .*"\$plist"' | head -1 | cut -d: -f1)"
  copy_line="$(printf '%s\n' "$body" | grep -n 'copy_file "\$plist"' | head -1 | cut -d: -f1)"
  [ -n "$guard_line" ]
  [ -n "$copy_line" ]
  [ "$guard_line" -lt "$copy_line" ]
}

@test "no OTHER plist carries the marker — the guard must not silently disable a real job" {
  local p n=0
  for p in "$REPO"/launchd/*.plist; do
    [ -f "$p" ] || continue
    case "$(basename "$p")" in com.claude.relogin.plist) continue ;; esac
    if grep -q "$NEEDLE" "$p"; then echo "unexpectedly staged: $p"; n=$((n + 1)); fi
  done
  [ "$n" -eq 0 ]
}

@test "positive control: the marker is absent from at least one real plist" {
  # Guards against a needle so loose it matches everything (which would disable every job
  # while every other assertion above still passed).
  local p hits=0 total=0
  for p in "$REPO"/launchd/*.plist; do
    [ -f "$p" ] || continue
    total=$((total + 1))
    grep -q "$NEEDLE" "$p" && hits=$((hits + 1))
  done
  [ "$total" -gt 1 ]
  [ "$hits" -lt "$total" ]
}

@test "behaviour: the extracted loop skips a staged fixture and installs a normal one" {
  # Runs install.sh's OWN loop text — not a paraphrase — with copy/launchctl stubbed.
  local d="$BATS_TEST_TMPDIR"
  mkdir -p "$d/launchd" "$d/out"
  printf '<plist>%s</plist>\n' "$NEEDLE" > "$d/launchd/com.staged.plist"
  printf '<plist>ordinary</plist>\n' > "$d/launchd/com.normal.plist"

  awk '/for plist in "\$REPO_DIR"\/launchd\/\*\.plist; do/,/^  done$/' "$INSTALL" > "$d/loop.sh"
  [ -s "$d/loop.sh" ]

  cat > "$d/harness.sh" <<EOF
REPO_DIR="$d"
HOME="$d"
DRY_RUN=false
copy_file() { echo "COPIED:\$(basename "\$1")" >> "$d/out/actions"; }
launchctl() { echo "LAUNCHCTL:\$*" >> "$d/out/actions"; }
mkdir -p "$d/Library/LaunchAgents"
. "$d/loop.sh"
EOF
  run bash "$d/harness.sh"
  [ "$status" -eq 0 ]
  grep -q 'COPIED:com.normal.plist' "$d/out/actions"
  run grep -c 'com.staged.plist' "$d/out/actions"
  [ "$output" -eq 0 ]
}
