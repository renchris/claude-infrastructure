#!/usr/bin/env bats
# cc-wt-restore.bats — restore a REMOVED worktree from its tombstone (DESIGN load-root-cause-2026-10-17
# §3.5, the DETACHED row's Reversal; WP-13a).
#
# WHAT IS LOAD-BEARING. The restore must survive the worst realistic history: the branch landed by
# REBASE (so trunk holds it only by patch-id), the branch was deleted, and the repo was gc'd with every
# reflog expired. Only then does "HEAD == the tombstone head, residue byte-identical, the old reflog
# back" prove that the tombstone ref and the copied logs/HEAD are what carried it, not a branch that
# happened to survive. The refusal cases pin that nothing at an occupied path is ever deleted.
#
# HERMETIC: a bare fixture origin, a clone and linked worktrees, all under $BATS_TEST_TMPDIR, with HOME
# and every WT_* store pointed inside it.

bats_require_minimum_version 1.5.0   # `run --separate-stderr`

SID=22222222-bbbb-4ccc-8ddd-222222222222

setup() {
  T="$(cd -P "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"; mkdir -p "$HOME/.claude/projects"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  unset WT_TRUNK WT_NOW CC_WTGC_DISPOSAL_LOG _WT_TOMBSTONE_SH _WT_PARK_SH CC_WT_RESTORE_REPOS_GLOB
  export WT_LEDGER="$T/ledger.jsonl" WT_TOMB_DIR="$T/tombs" WT_STATE_DIR="$T/state" \
         WT_CONFIG_ROOTS="$HOME/.claude" WT_RESUME_REAPED="$T/resume-reaped.jsonl"
  export WT_EVENTS_FILE="$WT_STATE_DIR/wt-events.jsonl" WT_WAKE_FILE="$WT_STATE_DIR/worktree-gc.wake" \
         WT_PARK_INDEX="$WT_STATE_DIR/wt-parked" WT_PARK_ROOT="$T/parked"
  BIN="$(cd "$BATS_TEST_DIRNAME/../bin" && pwd)"
  export PATH="$BIN:$PATH"
  git init -q --bare -b main "$T/origin.git"
  git init -q -b main "$T/main"
  cd "$T/main" || return 1
  printf '.env*\nout/\n.next/\n' > .gitignore
  echo base > f.txt
  git add -A && git commit -qm base
  git remote add origin "$T/origin.git" && git push -q -u origin main
  git remote set-head origin main
  echo 'SECRET=1' > .env.local
}

# mkwt <name> → a linked worktree on branch <name> with two commits, residue, and a session transcript
mkwt() {
  local w="$T/wts/$1"
  git -C "$T/main" worktree add -q -b "$1" "$w" main
  echo one > "$w/one.txt"; git -C "$w" add one.txt; git -C "$w" commit -qm one
  echo two > "$w/two.txt"; git -C "$w" add two.txt; git -C "$w" commit -qm two
  echo 'SECRET=edited' > "$w/.env.local"
  mkdir -p "$w/out"; head -c 2048 /dev/urandom > "$w/out/data.bin"
  printf '#!/bin/sh\necho hi\n' > "$w/out/run.sh"; chmod 755 "$w/out/run.sh"
  local slug; slug="$(printf '%s' "$w" | sed 's#[/.]#-#g')"
  mkdir -p "$HOME/.claude/projects/$slug"
  printf '{"type":"user","cwd":"%s","gitBranch":"%s","sessionId":"%s"}\n' "$w" "$1" "$SID" \
    > "$HOME/.claude/projects/$slug/$SID.jsonl"
  printf '%s' "$w"
}

# land_by_rebase <branch> → trunk gains the branch's commits as NEW objects (patch-id equal, not ancestors)
land_by_rebase() {
  local base; base="$(git -C "$T/main" merge-base main "$1")"
  echo trunk > "$T/main/trunk.txt"; git -C "$T/main" add trunk.txt; git -C "$T/main" commit -qm trunk
  git -C "$T/main" cherry-pick "$base..$1" >/dev/null
  git -C "$T/main" push -q origin main
  git -C "$T/main" fetch -q origin
}

residue_sums() { (cd "$1" && for f in .env.local out/data.bin out/run.sh; do shasum "$f"; done); }

# reap <path> → tombstone, remove, delete the branch, expire every reflog and gc: nothing but the tombstone keeps the head
reap() {
  local w="$1" br="$2"
  TOMB_ID="$(wt-tombstone tombstone "$w" lab test)" || return 1
  git -C "$T/main" worktree remove "$w" || return 1
  git -C "$T/main" branch -q -D "$br"
  git -C "$T/main" reflog expire --expire=now --all
  git -C "$T/main" gc -q --prune=now
}

@test "restore after rebase-land + branch -D + gc: HEAD, residue, reflog and the restored row all come back" {
  w="$(mkwt feat)"
  land_by_rebase feat
  head="$(git -C "$w" rev-parse HEAD)"
  ! git -C "$T/main" merge-base --is-ancestor "$head" origin/main   # premise: trunk has it by patch-id only
  sums="$(residue_sums "$w")"
  git -C "$w" reflog --format='%H %gs' | LC_ALL=C sort > "$T/reflog.before"
  reap "$w" feat
  [ ! -e "$w" ]
  ! git -C "$T/main" rev-parse -q --verify refs/heads/feat
  [ "$(git -C "$T/main" for-each-ref --format='%(objectname)' "refs/wt-tombstone/$TOMB_ID/head")" = "$head" ]

  run --separate-stderr cc-wt-restore "$w" --sid "$SID"
  [ "$status" -eq 0 ] || { echo "$stderr"; false; }
  [ "$output" = "$w" ]
  [ "$(git -C "$w" rev-parse HEAD)" = "$head" ]
  [ -z "$(git -C "$w" symbolic-ref -q HEAD)" ]               # detached: no branch was re-created
  ! git -C "$T/main" rev-parse -q --verify refs/heads/feat
  [ "$(residue_sums "$w")" = "$sums" ]
  [ -x "$w/out/run.sh" ]
  [ ! -e "$WT_TOMB_DIR/$TOMB_ID/residue/out/data.bin" ]       # moved back, not copied
  git -C "$w" reflog --format='%H %gs' | LC_ALL=C sort > "$T/reflog.after"
  [ -s "$T/reflog.before" ]
  [ -z "$(LC_ALL=C comm -23 "$T/reflog.before" "$T/reflog.after")" ]   # every old entry is back
  [ -z "$(git -C "$w" status --porcelain)" ]
  row="$(tail -1 "$WT_LEDGER")"
  [ "$(printf '%s' "$row" | jq -r .event)" = restored ]
  [ "$(printf '%s' "$row" | jq -r .id)" = "$TOMB_ID" ]
  [ "$(printf '%s' "$row" | jq -r .head)" = "$head" ]
  [ "$(printf '%s' "$row" | jq -r .path)" = "$w" ]
  [ "$(printf '%s' "$row" | jq -r .repo)" = "$T/main" ]
}

@test "an occupied path that is not a husk is refused with rc 2 and left untouched" {
  w="$(mkwt occ)"
  reap "$w" occ
  mkdir -p "$w"; echo mine > "$w/notes.md"
  run --separate-stderr cc-wt-restore "$w" --sid "$SID"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *occupied* ]] || return 1
  [ "$(cat "$w/notes.md")" = mine ]
  [ "$(ls -A "$w")" = notes.md ]
  [ "$(tail -1 "$WT_LEDGER" | jq -r .event)" = worktree-disposed ]   # no restored row
}

@test "a NOGIT husk (.claude-* and .next only) is moved aside, never deleted, and the restore proceeds" {
  w="$(mkwt husk)"
  head="$(git -C "$w" rev-parse HEAD)"
  reap "$w" husk
  mkdir -p "$w/.next/cache"; echo s > "$w/.claude-session"; echo c > "$w/.next/cache/x"
  run --separate-stderr cc-wt-restore "$w" --sid "$SID"
  [ "$status" -eq 0 ] || { echo "$stderr"; false; }
  [ "$(git -C "$w" rev-parse HEAD)" = "$head" ]
  set -- "$w".husk-*
  [ -d "$1" ]
  [ "$(cat "$1/.claude-session")" = s ]
  [ "$(cat "$1/.next/cache/x")" = c ]
}

@test "an empty directory at the path (a previous mkdir -p resume) is reused" {
  w="$(mkwt empty)"
  head="$(git -C "$w" rev-parse HEAD)"
  reap "$w" empty
  mkdir -p "$w"
  run cc-wt-restore "$w" --sid "$SID"
  [ "$status" -eq 0 ]
  [ "$(git -C "$w" rev-parse HEAD)" = "$head" ]
}

@test "no matching tombstone ⇒ rc 1 and nothing created; a different sid or branch does not match" {
  w="$(mkwt nomatch)"
  reap "$w" nomatch
  run cc-wt-restore "$w" --sid 99999999-0000-4000-8000-000000000000 --branch other
  [ "$status" -eq 1 ]
  [ ! -e "$w" ]
  run cc-wt-restore "$T/wts/never"
  [ "$status" -eq 1 ]
}

@test "legacy row (no repo): repo inferred from the one repo holding head; tracked tree only, and it says so" {
  w="$(mkwt legacy)"
  head="$(git -C "$w" rev-parse HEAD)"
  git -C "$T/main" worktree remove --force "$w"
  git init -q -b main "$T/other"; git -C "$T/other" commit -q --allow-empty -m other
  printf '{"ts":"2026-01-01T00:00:00Z","event":"worktree-disposed","path":"%s","branch":"legacy","head":"%s","sids":["%s"]}\n' \
    "$w" "$head" "$SID" >> "$WT_LEDGER"
  export CC_WT_RESTORE_REPOS_GLOB="$T/other/ $T/main/"
  run --separate-stderr cc-wt-restore "$w" --sid "$SID"
  [ "$status" -eq 0 ] || { echo "$stderr"; false; }
  [ "$(git -C "$w" rev-parse HEAD)" = "$head" ]
  [[ "$stderr" == *"tracked tree only"* ]] || return 1
  [[ "$stderr" == *"do not come back"* ]] || return 1
  [ ! -e "$w/.env.local" ]
  [ "$(tail -1 "$WT_LEDGER" | jq -r .repo)" = "$T/main" ]
}

@test "legacy row whose head is in two repositories is refused (exactly one match or nothing)" {
  w="$(mkwt legacy2)"
  head="$(git -C "$w" rev-parse HEAD)"
  git -C "$T/main" worktree remove --force "$w"
  git clone -q "$T/main" "$T/clone2"
  git -C "$T/clone2" fetch -q "$T/main" legacy2
  printf '{"event":"worktree-disposed","path":"%s","head":"%s","sids":["%s"]}\n' "$w" "$head" "$SID" >> "$WT_LEDGER"
  export CC_WT_RESTORE_REPOS_GLOB="$T/main/ $T/clone2/"
  run --separate-stderr cc-wt-restore "$w" --sid "$SID"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"in 2 repositories"* ]] || return 1
  [ ! -e "$w" ]
}

@test "--log-reaped writes one resume-reaped row and never fails" {
  run cc-wt-restore --log-reaped cc-resume-shell "$T/wts/x" "$SID" recreated-empty
  [ "$status" -eq 0 ]
  [ "$(jq -r .outcome "$WT_RESUME_REAPED")" = recreated-empty ]
  [ "$(jq -r .launcher "$WT_RESUME_REAPED")" = cc-resume-shell ]
}
