#!/usr/bin/env bats
# iterm2-appname-lint — the RATCHET that stops AppleScript from addressing iTerm2 by NAME.
#
# THE DEFECT, measured 2026-07-31. The bundle on disk is /Applications/iTerm.app; "iTerm2" is only
# its CFBundleName. AppleScript resolves a CFBundleName ONLY while that app is already running — for
# a not-running app it matches the bundle's FILE name. Measured side by side that day:
#   id of application "iTerm"  -> com.googlecode.iterm2      (file name, always resolves)
#   id of application "iTerm2" -> -1728 Can't get application (CFBundleName, only while running)
# and the same split on a control pair with the identical shape: "Chrome" (running, file is
# Google Chrome.app) resolved, "Excel" (not running, file is Microsoft Excel.app) did not.
#
# So `tell application "iTerm2"` worked for months purely because iTerm2 was always running. When
# the fleet moved to kitty and iTerm2 stopped running, the name resolved to nothing: AppleScript
# loaded no terminology, every iTerm2 verb in the block parsed as a class name (-2740/-2741), and on
# a desktop LaunchServices put up a "Choose Application — Where is iTerm2?" MODAL. A launchd job or
# hook cannot dismiss that modal, so it sat open and blocked its caller: the dispatcher (300 s) and
# the limit-reset poller (600 s) re-armed it all day. One was found open on this machine before
# anyone knew what had opened it.
#
# THE FIX HAS TWO HALVES, and shipping only the first would trade a modal for something worse:
#   1. `application id "com.googlecode.iterm2"` — resolves through LaunchServices whether or not the
#      app runs, so the chooser modal becomes unreachable.
#   2. `is running` FIRST at every site that merely INSPECTS panes — because `application id` also
#      succeeds at LAUNCHING, and a bare id swap would have every 5-minute timer silently start
#      iTerm2: the app whose window objects saturated WindowServer on 2026-07-30, on a fleet that
#      deliberately left it. `is running` is the one iTerm2 reference that never launches it.
# boot-resume-launch.sh is the sole exempt caller: it launches iTerm2 EXPLICITLY (`open -a iTerm`)
# one line earlier, so there the launch is the intent.
#
# SCOPE — scripts/ bin/ hooks/ only. docs/ and tools/terminal-bench/window-census.swift quote the
# broken form as PROSE, on purpose (the census file exists to explain why it does NOT use
# AppleScript); widening the scan to them would ship a standing-red lint, which is rot.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCAN_DIRS=(scripts bin hooks)
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # never read the operator's live ~/
  # This suite READS handoff-fire.sh; pinning the capacity gate keeps it red-by-subject, never
  # red-by-load, on a box that lives above handoff-fire's 2.0/core refusal threshold.
  export CC_FIRE_CAPACITY_GATE=off
}

# ── 1. the ratchet ────────────────────────────────────────────────────────────────────────────────
@test "no AppleScript in scripts/ bin/ hooks/ addresses iTerm2 by NAME" {
  cd "$REPO" || { echo "unusable repo root"; false; }
  local hits
  # --exclude this file: a ratchet must be able to QUOTE the form it forbids.
  hits="$(grep -rn --exclude="$(basename "$BATS_TEST_FILENAME")" \
            'application "iTerm2"' "${SCAN_DIRS[@]}" 2>/dev/null || true)"
  [ -z "$hits" ] || {
    echo "name-based iTerm2 lookup found — use: tell application id \"com.googlecode.iterm2\""
    echo "$hits"
    false
  }
}

# ── 2. the mechanism, as a control that cannot decay ──────────────────────────────────────────────
# Keyed on a NOT-RUNNING app with CFBundleName != file name — the same shape as iTerm2, but NOT
# iTerm2 itself. Keying this on iTerm2 would make the control pass or fail depending on whether some
# other session happened to have iTerm2 open, which is exactly how the first run of this control was
# silently invalidated (a sibling relaunched iTerm2 mid-run and every pre-fix block then resolved).
@test "the NAME form is what loses terminology; the id+guard form does not" {
  if pgrep -x "Microsoft Excel" >/dev/null 2>&1; then skip "Excel is running — the control needs it down"; fi
  [ -d "/Applications/Microsoft Excel.app" ] || skip "control app absent"

  # PRE-FIX shape: name lookup + app-specific vocabulary ⇒ no terminology ⇒ -2740/-2741.
  run osascript -e 'tell application "Excel" to get name of active workbook'
  [ "$status" -ne 0 ] || { echo "control did not fail — it can no longer discriminate"; false; }
  [[ "$output" == *-2740* || "$output" == *-2741* ]] || {
    echo "expected a terminology miss (-2740/-2741), got: $output"; false; }

  # POST-FIX shape: bundle id + is-running short-circuit ⇒ clean, quiet, and no launch.
  run osascript -e 'if not (application id "com.microsoft.Excel" is running) then return ""' \
                -e 'tell application id "com.microsoft.Excel" to get name of active workbook'
  [ "$status" -eq 0 ] || { echo "guarded form should exit 0, got $status: $output"; false; }
  [ -z "$output" ] || { echo "guarded form should be silent, got: $output"; false; }
  pgrep -x "Microsoft Excel" >/dev/null 2>&1 && { echo "the guard LAUNCHED the app"; false; } || true
}

# ── 3. every real block still compiles ────────────────────────────────────────────────────────────
# osacompile, not osascript: compiling proves terminology loads without EXECUTING blocks that would
# create windows. Blocks are extracted from the shipping files, never retyped — a hand-copied
# approximation passes vacuously (memory: control-must-replay-the-real-artifact).
@test "every shipped iTerm2 AppleScript block loads terminology (no -2740/-2741)" {
  command -v osacompile >/dev/null 2>&1 || skip "osacompile unavailable"
  cd "$REPO" || { echo "unusable repo root"; false; }
  local n=0 f body out
  for f in scripts/handoff-fire.sh scripts/handoff-selfclose-e2e.sh scripts/limit-recover/lr-handoff.sh; do
    [ -f "$f" ] || { echo "expected file missing: $f"; false; }
    while IFS= read -r body; do
      [ -n "$body" ] || continue
      n=$((n + 1))
      # %b, not %s: the extractor escapes newlines so one block survives as one `read` line.
      printf '%b\n' "$body" \
        | sed 's/\$OWN_PANE/DUMMY/g; s|\$LAUNCHER|/bin/true|g' \
        > "$BATS_TEST_TMPDIR/blk.applescript"
      out="$(osacompile -o "$BATS_TEST_TMPDIR/blk.scpt" "$BATS_TEST_TMPDIR/blk.applescript" 2>&1 || true)"
      [[ "$out" != *-2740* && "$out" != *-2741* && "$out" != *"class name"* ]] || {
        echo "terminology miss in $f block $n: $out"; false; }
    done < <(python3 - "$f" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
for m in re.finditer(r"<<'?(AS|OSA)'?[^\n]*\n(.*?)\n\1\n", s, re.S):
    b = m.group(2)
    if "com.googlecode.iterm2" in b:
        print(b.replace("\n", "\\n"))
PY
    )
  done
  [ "$n" -ge 5 ] || { echo "expected >=5 extracted blocks, got $n — the extractor stopped matching"; false; }
}

# ── 4. no site may launch iTerm2 implicitly ───────────────────────────────────────────────────────
@test "every inspecting caller short-circuits on is-running; the launcher is explicit" {
  cd "$REPO" || { echo "unusable repo root"; false; }
  local f
  for f in scripts/handoff-fire.sh scripts/handoff-selfclose-e2e.sh scripts/render-census.sh \
           scripts/limit-recover/lr-handoff.sh scripts/limit-recover/lr-reset-poller.sh; do
    grep -q 'application id "com.googlecode.iterm2" is running' "$f" || {
      echo "$f reaches iTerm2 with no is-running short-circuit — it can LAUNCH it"; false; }
  done
  # The one deliberate exception: it launches iTerm2 itself, so a guard there would be wrong.
  grep -q 'open -a iTerm' scripts/boot-resume-launch.sh || {
    echo "boot-resume-launch.sh no longer launches iTerm2 explicitly — re-check its exemption"; false; }
}
