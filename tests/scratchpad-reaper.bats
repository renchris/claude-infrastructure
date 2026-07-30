#!/usr/bin/env bats
# scratchpad-reaper — the GC for `/private/tmp/claude-<uid>/<project>/<sessionUUID>/` (audit 03 §1d
# rank 1: 10.67 GB, +810 MB/day, bounded only by reboot).
#
# Harness laws: L1 the fixture is the REAL directory shape the harness produces (project/sessionUUID,
# some dirs-only "0 KB"); L2 assertions key on the failure-DISTINCT outcome (a live session's dir
# SURVIVES — the reaper's known scar, cc-reaper reaping live operator conversations 2026-07-24);
# L3 `[ ]` / `grep -q` only; L4 every keep-rule has a paired reap-rule so a "reap nothing" bug is RED.

setup() {
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet): fixture $HOME FIRST so every test
  # inherits it. Load-bearing here beyond the ratchet: this subject `rm -rf`s an age-reaped tree, so
  # an unfixtured $HOME is the one leak class that could reach real state.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REAPER="$REPO/scripts/scratchpad-reaper.sh"
  export CC_SCRATCHPAD_ROOT="$BATS_TEST_TMPDIR/scratch"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  export CC_PROJECT_DIRS="$BATS_TEST_TMPDIR/projects"
  export CC_SCRATCHPAD_LOG="$BATS_TEST_TMPDIR/reaper.log"
  mkdir -p "$CC_SCRATCHPAD_ROOT/-Users-x-proj" "$CC_REGISTRY_DIR" "$CC_PROJECT_DIRS"
}

SID_OLD=aaaaaaaa-1111-2222-3333-444444444444
SID_LIVE=bbbbbbbb-1111-2222-3333-444444444444
SID_YOUNG=cccccccc-1111-2222-3333-444444444444
SID_EMPTY=dddddddd-1111-2222-3333-444444444444
SID_TRANSCRIPT=eeeeeeee-1111-2222-3333-444444444444

# a session dir holding one file, backdated <days> days
mk_dir() { # <sid> <days-old>
  local d="$CC_SCRATCHPAD_ROOT/-Users-x-proj/$1"
  mkdir -p "$d/scratchpad"
  printf 'payload\n' > "$d/scratchpad/note.md"
  touch -t "$(date -v-"$2"d +%Y%m%d%H%M)" "$d/scratchpad/note.md" "$d/scratchpad" "$d" 2>/dev/null
}
# a dirs-only session dir (the 377 "0 KB" case)
mk_empty_dir() { mkdir -p "$CC_SCRATCHPAD_ROOT/-Users-x-proj/$1/scratchpad"; }

reg_row() { # <sid> <pid>
  printf '{"paneUUID":"P-%s","pid":%s,"session_id":"%s"}\n' "$1" "$2" "$1" \
    > "$CC_REGISTRY_DIR/$1.json"
}

exists() { [ -d "$CC_SCRATCHPAD_ROOT/-Users-x-proj/$1" ]; }

# ── fail-closed: no readable registry ⇒ nothing is reaped, exit 3 ──────────────────────────────
@test "unreadable registry ⇒ FAIL-CLOSED (exit 3, nothing deleted)" {
  mk_dir "$SID_OLD" 5
  rm -rf "$CC_REGISTRY_DIR"
  run bash "$REAPER" --apply
  [ "$status" -eq 3 ]
  exists "$SID_OLD"
}

# ── dry-run is the default: it names the victim but deletes nothing ────────────────────────────
@test "dry-run default names the dir but deletes nothing; --apply deletes it" {
  mk_dir "$SID_OLD" 5
  run bash "$REAPER"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "would-reap"
  echo "$output" | grep -q "$SID_OLD"
  exists "$SID_OLD"

  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  ! exists "$SID_OLD"
}

# ── liveness outranks age: a live pid keeps a 5-day-old dir ────────────────────────────────────
@test "a live registry pid KEEPS a dir far past the horizon" {
  mk_dir "$SID_LIVE" 5
  reg_row "$SID_LIVE" "$$"        # our own pid is provably alive
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  exists "$SID_LIVE"
  echo "$output" | grep -q "kept_live=1"
}

# ── a DEAD registry pid does not save it (the keep must come from liveness, not from the row) ──
@test "a dead registry pid does NOT keep an old dir" {
  mk_dir "$SID_OLD" 5
  reg_row "$SID_OLD" 99999999     # not a live pid
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  ! exists "$SID_OLD"
}

# ── the transcript belt: registry retention is 24 h, so at 48 h the transcript is the only ─────
#    liveness signal a long-running session still has.
@test "a transcript touched inside the horizon KEEPS an old scratchpad (registry row absent)" {
  mk_dir "$SID_TRANSCRIPT" 5
  mkdir -p "$CC_PROJECT_DIRS/-Users-x-proj"
  printf '{}\n' > "$CC_PROJECT_DIRS/-Users-x-proj/$SID_TRANSCRIPT.jsonl"
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  exists "$SID_TRANSCRIPT"
}

@test "a transcript OLDER than the horizon does not keep it" {
  mk_dir "$SID_OLD" 5
  mkdir -p "$CC_PROJECT_DIRS/-Users-x-proj"
  printf '{}\n' > "$CC_PROJECT_DIRS/-Users-x-proj/$SID_OLD.jsonl"
  touch -t "$(date -v-5d +%Y%m%d%H%M)" "$CC_PROJECT_DIRS/-Users-x-proj/$SID_OLD.jsonl"
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  ! exists "$SID_OLD"
}

# ── age gate: a young non-empty dir survives ───────────────────────────────────────────────────
@test "a dir younger than the horizon survives" {
  mk_dir "$SID_YOUNG" 0
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  exists "$SID_YOUNG"
  echo "$output" | grep -q "kept_young=1"
}

# ── the 377 "0 KB" dirs: no regular file anywhere ⇒ reaped without the age wait ────────────────
@test "a dirs-only session dir is reaped without waiting out the horizon" {
  mk_empty_dir "$SID_EMPTY"
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  ! exists "$SID_EMPTY"
  echo "$output" | grep -q "empty=1"
}

@test "a dirs-only dir belonging to a LIVE session is still kept" {
  mk_empty_dir "$SID_LIVE"
  reg_row "$SID_LIVE" "$$"
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  exists "$SID_LIVE"
}

# ── non-UUID dirs under a project are not ours ─────────────────────────────────────────────────
@test "a non-UUID dir is never a candidate" {
  mkdir -p "$CC_SCRATCHPAD_ROOT/-Users-x-proj/some-other-tool"
  printf 'x\n' > "$CC_SCRATCHPAD_ROOT/-Users-x-proj/some-other-tool/f"
  touch -t "$(date -v-9d +%Y%m%d%H%M)" "$CC_SCRATCHPAD_ROOT/-Users-x-proj/some-other-tool"
  run bash "$REAPER" --apply
  [ "$status" -eq 0 ]
  [ -d "$CC_SCRATCHPAD_ROOT/-Users-x-proj/some-other-tool" ]
  echo "$output" | grep -q "candidates=0"
}

# ── the horizon must clear the reaper-horizon-lint floor (6000s) and be lint-VISIBLE ───────────
@test "the horizon is a literal -mmin +N ≥ the 6000s lint floor" {
  run grep -cE -- '-mmin \+2880' "$REAPER"
  [ "$status" -eq 0 ]
  run bash "$REPO/scripts/reaper-horizon-lint.sh"
  # Assert THIS reaper's own verdict, not the whole tree's exit code. The lint scans every file in
  # the repo, so a bare `[ "$status" -eq 0 ]` made this suite fail on violations it did not create:
  # origin/main's own tree reds this lint with 5 UNDECLARED reapers (cc-await-ping,
  # dispatch-assert.sh, desk-invariant.sh, context-econ.sh, cc-recover-safeguard — the last two now
  # declared here). Holding a new suite answerable for pre-existing trunk debt is a lint nobody can
  # ever turn green; the scoped assertion below is what this test actually means, and it still fails
  # loudly if scratchpad-reaper's own horizon regresses or stops being lint-VISIBLE.
  echo "$output" | grep -qE '^  ok  scripts/scratchpad-reaper\.sh:[0-9]+  horizon 172800s'
  # `[ ]`, not `! grep`: a non-final `!` is errexit-EXEMPT in bats and would be a DEAD assertion.
  [ "$(echo "$output" | grep -c "⛔ scripts/scratchpad-reaper.sh")" -eq 0 ]
}

# ── the staged plist parses and is NOT wired to RunAtLoad (activation is C10/operator) ─────────
@test "the staged plist parses and does not self-activate" {
  run plutil -lint "$REPO/launchd/com.claude.scratchpad-reaper.plist"
  [ "$status" -eq 0 ]
  run plutil -extract RunAtLoad raw -o - "$REPO/launchd/com.claude.scratchpad-reaper.plist"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}
