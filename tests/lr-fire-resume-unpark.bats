#!/usr/bin/env bats
# lr-fire-resume.sh — a PARKED worktree comes back on a path match, a REMOVED one only for its own sid
# (DESIGN load-root-cause-2026-10-17 §3.5 item 4a, §3.7 item 7 "Unpark on resume"; WP-13b).
#
# THE DEFECT. lr-fire-resume has its own recreate-from-branch path. Once worktree-gc PARKS an idle tree
# (`git worktree move` to .parked/<id>, branch still checked out there), that path's
# `git worktree add "$WT" "$BR"` fails — the branch is checked out at the parked path — and the resume
# exits 1, on a tree that is sitting intact one rename away. The RED control below runs the pre-change
# script (7fa90e0c2) against the same parked fixture and records that exit.
#
# HOW THE SUBJECT IS STOPPED. Every case drives the REAL script past the worktree block and stops it at
# the first fail-closed check after `cd "$WT"`: LR_CLAUDE_BIN names no file, so it exits 1 with
# "cannot resolve the claude binary". That message is the proof the cwd step succeeded; the worktree
# block's own exits (1 and 2) print different reasons. LR_PRESEED_DONE skips the preseed, so nothing
# writes into the tree before the stop.
#
# HERMETIC: a bare origin, a clone and linked worktrees under $BATS_TEST_TMPDIR, with HOME and every WT_*
# store pointed inside it. The config dir is a fixture path, so no account map is read.

SID_ROW=11111111-aaaa-4bbb-8ccc-111111111111     # the session the park / tombstone row names
SID_OTHER=99999999-ffff-4eee-8ddd-999999999999   # a session it does not

setup() {
  T="$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"; mkdir -p "$HOME/.claude/projects"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset WT_TRUNK WT_NOW CC_WTGC_DISPOSAL_LOG _WT_TOMBSTONE_SH _WT_PARK_SH CC_RESUME_TOMBSTONE_LIB LR_RUN LR_RUN_DIR
  export WT_LEDGER="$T/ledger.jsonl" WT_TOMB_DIR="$T/tombs" WT_STATE_DIR="$T/state" \
         WT_CONFIG_ROOTS="$HOME/.claude" WT_RESUME_REAPED="$T/resume-reaped.jsonl"
  export WT_EVENTS_FILE="$WT_STATE_DIR/wt-events.jsonl" WT_WAKE_FILE="$WT_STATE_DIR/worktree-gc.wake" \
         WT_PARK_INDEX="$WT_STATE_DIR/wt-parked" WT_PARK_ROOT="$T/parked"
  export CC_ADMIT_GATE=off LR_PRESEED_DONE=1 LR_CLAUDE_BIN="$T/no-such-claude" LR_STATE_DIR="$T/lrstate"
  FIRE="$(cd "$BATS_TEST_DIRNAME/../scripts/limit-recover" && pwd)/lr-fire-resume.sh"
  WTT="$(cd "$BATS_TEST_DIRNAME/../bin" && pwd)/wt-tombstone"
  CFG="$T/cfg"; mkdir -p "$CFG"
  git init -q --bare -b main "$T/origin.git"
  git init -q -b main "$T/main"
  printf '.env*\nout/\n' > "$T/main/.gitignore"
  echo base > "$T/main/f.txt"
  git -C "$T/main" add -A && git -C "$T/main" commit -qm base
  git -C "$T/main" remote add origin "$T/origin.git" && git -C "$T/main" push -q -u origin main
  git -C "$T/main" remote set-head origin main
}

# mkwt <branch> → a linked worktree with a commit, ignored residue and a transcript for SID_ROW
mkwt() {
  local w="$T/wts/$1" slug
  git -C "$T/main" worktree add -q -b "$1" "$w" main
  echo one > "$w/one.txt"; git -C "$w" add one.txt; git -C "$w" commit -qm one
  echo 'SECRET=edited' > "$w/.env.local"
  mkdir -p "$w/out"; echo data > "$w/out/data.bin"
  slug="$(printf '%s' "$w" | sed 's#[/.]#-#g')"
  mkdir -p "$HOME/.claude/projects/$slug"
  printf '{"type":"user","cwd":"%s","gitBranch":"%s","sessionId":"%s"}\n' "$w" "$1" "$SID_ROW" \
    > "$HOME/.claude/projects/$slug/$SID_ROW.jsonl"
  printf '%s' "$w"
}

snap() { git -C "$1" status --porcelain --ignored; echo ---; git -C "$1" reflog; }   # what a park must not change
fire() { run bash "${FIRE_AT:-$FIRE}" "$CFG" "$1" "$2" --branch "$3" --repo "$T/main" --model claude-opus-5; }
reaped() { jq -r --arg o "$1" 'select(.launcher == "lr-fire-resume" and .outcome == $o) | .cwd' "$WT_RESUME_REAPED" 2>/dev/null; }

@test "a parked tree is unparked on a path match with a sid the park row does not name: status and reflog unchanged" {
  w="$(mkwt feat)"; before="$(snap "$w")"
  "$WTT" park "$w" lab test --arm ii >/dev/null
  [ ! -e "$w" ]
  fire "$w" "$SID_OTHER" feat
  [ "$status" -eq 1 ] && [[ "$output" == *"cannot resolve the claude binary"* ]] || { echo "status $status: $output"; false; }
  [[ "$output" == *"unparked $w"* ]] || { echo "$output"; false; }
  [ "$(snap "$w")" = "$before" ] || { diff <(echo "$before") <(snap "$w"); false; }
  [ "$(git -C "$w" symbolic-ref --short HEAD)" = feat ]
  [ "$(reaped unparked)" = "$w" ] || { cat "$WT_RESUME_REAPED"; false; }
}

@test "RED control: the pre-change script exits 1 on the same parked tree (the branch is checked out at the parked path)" {
  w="$(mkwt feat)"
  "$WTT" park "$w" lab test --arm ii >/dev/null
  mkdir -p "$T/old/scripts/limit-recover"
  git -C "$BATS_TEST_DIRNAME/.." show 7fa90e0c2:scripts/limit-recover/lr-fire-resume.sh > "$T/old/scripts/limit-recover/lr-fire-resume.sh"
  for f in lr-lib.sh lr-team.sh; do ln -s "$(dirname "$FIRE")/$f" "$T/old/scripts/limit-recover/$f"; done
  FIRE_AT="$T/old/scripts/limit-recover/lr-fire-resume.sh" fire "$w" "$SID_OTHER" feat
  [ "$status" -eq 1 ] || { echo "status $status: $output"; false; }
  [[ "$output" != *"cannot resolve the claude binary"* ]] || { echo "the old script got past the worktree: $output"; false; }
  [ ! -e "$w" ]
}

@test "a .claude-* husk at the parked path is moved aside and the unpark proceeds" {
  w="$(mkwt feat)"; before="$(snap "$w")"
  "$WTT" park "$w" lab test --arm ii >/dev/null
  mkdir -p "$w/.claude-tasks"
  fire "$w" "$SID_OTHER" feat
  [ "$status" -eq 1 ] && [[ "$output" == *"cannot resolve the claude binary"* ]] || { echo "status $status: $output"; false; }
  [ "$(snap "$w")" = "$before" ]
  compgen -G "$w.husk-*/.claude-tasks" >/dev/null || { ls -la "$T/wts"; false; }
}

@test "a husk holding any other file is refused: exit 1, the tree stays parked, the outcome is logged" {
  w="$(mkwt feat)"
  "$WTT" park "$w" lab test --arm ii >/dev/null
  mkdir -p "$w/.claude-tasks"; echo mine > "$w/notes.txt"
  fire "$w" "$SID_OTHER" feat
  [ "$status" -eq 1 ] && [[ "$output" == *"could not be unparked"* ]] || { echo "status $status: $output"; false; }
  [ "$(cat "$w/notes.txt")" = mine ] && [ ! -e "$w/.git" ]
  "$WTT" parked "$w" >/dev/null
  [ "$(reaped exit-1)" = "$w" ] || { cat "$WT_RESUME_REAPED"; false; }
}

# reap <path> <branch> → tombstone, remove, delete the branch: the exit-2 shape, with a tombstone behind it
reap() {
  "$WTT" tombstone "$1" lab test >/dev/null || return 1
  git -C "$T/main" worktree remove "$1" || return 1
  git -C "$T/main" branch -q -D "$2"
}

@test "a removed tree whose tombstone names this sid is restored at the recorded head, residue back" {
  w="$(mkwt feat)"; head="$(git -C "$w" rev-parse HEAD)"
  reap "$w" feat
  fire "$w" "$SID_ROW" feat
  [ "$status" -eq 1 ] && [[ "$output" == *"cannot resolve the claude binary"* ]] || { echo "status $status: $output"; false; }
  [ "$(git -C "$w" rev-parse HEAD)" = "$head" ]
  [ "$(cat "$w/.env.local")" = 'SECRET=edited' ] && [ "$(cat "$w/out/data.bin")" = data ]
  [ "$(reaped restored)" = "$w" ] || { cat "$WT_RESUME_REAPED"; false; }
  [ -z "$(ls -A "$LR_STATE_DIR/locks" 2>/dev/null)" ] || { echo "a git lock was left behind"; ls "$LR_STATE_DIR/locks"; false; }
}

@test "a removed tree whose tombstone names another sid keeps today's exit-2 refusal" {
  w="$(mkwt feat)"
  reap "$w" feat
  fire "$w" "$SID_OTHER" feat
  [ "$status" -eq 2 ] && [[ "$output" == *"missing and no --branch to recreate it"* ]] || { echo "status $status: $output"; false; }
  [ ! -e "$w" ]
  [ "$(reaped exit-2)" = "$w" ] || { cat "$WT_RESUME_REAPED"; false; }
}

@test "no library: CC_RESUME_TOMBSTONE_LIB naming no file keeps the pre-change behaviour (parked ⇒ exit 1, no row)" {
  w="$(mkwt feat)"
  "$WTT" park "$w" lab test --arm ii >/dev/null
  export CC_RESUME_TOMBSTONE_LIB="$T/none.sh"
  fire "$w" "$SID_OTHER" feat
  [ "$status" -eq 1 ] && [[ "$output" != *"cannot resolve the claude binary"* ]] || { echo "status $status: $output"; false; }
  [ ! -e "$WT_RESUME_REAPED" ]
}
