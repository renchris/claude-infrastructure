#!/usr/bin/env bats
# wt-park.sh — PARK / unpark, the pin predicate and the cc-pin lock sync (W2-CONTRACT.md "PARK + pins",
# DESIGN load-root-cause-2026-10-17 §3.2, §3.5, §3.7). Lab only: a bare origin, a clone and linked
# worktrees under $BATS_TEST_TMPDIR, with HOME, every WT_* store and the clock pointed into it.

bats_require_minimum_version 1.5.0

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$ROOT/scripts/lib/wt-tombstone.sh"
  T="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$T/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export WT_PARK_ROOT="$T/parked" WT_PARK_INDEX="$T/state/wt-parked" WT_LEDGER="$T/ledger.jsonl"
  export WT_TOMB_DIR="$T/tomb" WT_STATE_DIR="$T/state" WT_CONFIG_ROOTS="$T/cfg1:$T/cfg2"
  export WT_CRASH_LOG="$T/crashes.jsonl" WT_RESUME_DEBT_DIR="$T/resume-debt" WT_LR_DIR="$T/lr"
  export WT_RECYCLE_FAILED_DIR="$T/recycle-failed" WT_BOOT_RESUME_DIR="$T/boot-resume" WT_BACKLOG="$T/backlog.jsonl"
  export WT_TRUNK=origin/main WT_NOW; WT_NOW="$(date +%s)"
  mkdir -p "$T/cfg1" "$T/cfg2"
  git init -q --bare -b main "$T/origin.git"
  git clone -q "$T/origin.git" "$T/repo" 2>/dev/null
  R="$T/repo"
  printf 'node_modules/\n*.log\n' > "$R/.gitignore"; echo a > "$R/f"
  git -C "$R" add . && git -C "$R" commit -qm c1 && git -C "$R" push -q origin HEAD:main 2>/dev/null
  git -C "$R" fetch -q origin
  # shellcheck source=/dev/null
  . "$LIB"
}

age() { touch -t "$(date -r "$2" +%Y%m%d%H%M.%S)" "$1"; }   # <file> <epoch>

mkwt() { # <name> <branch> → linked worktree at $T/wt/<name>, its reflog aged past the owner window
  git -C "$R" worktree add -q "$T/wt/$1" -b "$2" 2>/dev/null
  age "$(git -C "$T/wt/$1" rev-parse --absolute-git-dir)/logs/HEAD" $((WT_NOW - 86400))
}

transcript() { # <cfg-root> <cwd> <sid> [mtime-epoch] → one transcript naming that cwd
  local d; d="$1/projects/$(wt__slug "$2")"; mkdir -p "$d"
  printf '{"type":"user","cwd":"%s","sessionId":"%s"}\n' "$2" "$3" > "$d/$3.jsonl"
  [ -z "${4:-}" ] || age "$d/$3.jsonl" "$4"
}

iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }

# ---- PARK / unpark ------------------------------------------------------------------------------

@test "park arm i: landed-clean tree moves whole, locked, detached; branch deletable; unpark is byte-identical" {
  mkwt a feat; W="$T/wt/a"
  mkdir -p "$W/node_modules/x"; echo m > "$W/node_modules/x/i.js"; echo l > "$W/debug.log"
  st0="$(git -C "$W" status --porcelain --ignored)"; rl0="$(git -C "$W" reflog)"; tip="$(git -C "$W" rev-parse HEAD)"
  run wt_park "$W" test landed-clean --arm i
  [ "$status" -eq 0 ]; P="$output"
  [ ! -e "$W" ]; [ -f "$P/node_modules/x/i.js" ]; [ -f "$P/debug.log" ]
  git -C "$R" worktree list --porcelain | grep -q "^locked parked .* from $W sids="
  ! git -C "$P" symbolic-ref -q HEAD || false
  [ "$(git -C "$P" rev-parse HEAD)" = "$tip" ]
  idx="$WT_PARK_INDEX/$(wt__sha1 "$W")"
  grep -qx "parked=$P" "$idx"; grep -qx "branch=feat" "$idx"; grep -qx "branch_tip=$tip" "$idx"
  [ "$(stat -f %Lp "$idx")" = 600 ]
  jq -e --arg p "$P" 'select(.event=="worktree-parked" and .parked_path==$p and .branch_tip!=null)' "$WT_LEDGER" >/dev/null
  run wt_parked_lookup "$W"; [ "$status" -eq 0 ]; [ "$output" = "$R	$P" ]
  git -C "$R" branch -D feat >/dev/null          # landed branch is deletable while parked
  git -C "$R" branch feat "$tip"
  run wt_unpark "$W"
  [ "$status" -eq 0 ]
  [ ! -e "$P" ]; [ ! -e "$idx" ]
  [ "$(git -C "$W" symbolic-ref HEAD)" = refs/heads/feat ]
  [ "$(git -C "$W" status --porcelain --ignored)" = "$st0" ]
  [ "$(git -C "$W" reflog)" = "$rl0" ]
  ! git -C "$R" worktree list --porcelain | grep -q '^locked' || false
  jq -e 'select(.event=="worktree-unparked")' "$WT_LEDGER" >/dev/null
  run wt_unpark "$W"; [ "$status" -eq 1 ]
}

@test "unpark with the branch deleted stays detached at the same commit and logs reattach=skipped" {
  mkwt a feat; W="$T/wt/a"; tip="$(git -C "$W" rev-parse HEAD)"
  P="$(wt_park "$W" test x --arm i)"
  git -C "$R" branch -D feat >/dev/null
  wt_unpark "$W" 2>"$T/err"
  grep -q 'reattach=skipped:branch-gone' "$T/err"
  ! git -C "$W" symbolic-ref -q HEAD || false
  [ "$(git -C "$W" rev-parse HEAD)" = "$tip" ]; [ ! -e "$P" ]
}

@test "park arm ii: an unlanded tree stays attached, so git refuses branch -D" {
  mkwt b feat2; W="$T/wt/b"
  echo x > "$W/g"; git -C "$W" add g; git -C "$W" commit -qm unlanded
  run wt_park "$W" test unlanded --arm ii
  [ "$status" -eq 0 ]; P="$output"
  [ "$(git -C "$P" symbolic-ref HEAD)" = refs/heads/feat2 ]
  run git -C "$R" branch -D feat2
  [ "$status" -ne 0 ]
  ! grep -q '^branch_tip=.' "$WT_PARK_INDEX/$(wt__sha1 "$W")"
}

@test "husk: a .claude-* husk at the path is moved aside and the unpark proceeds" {
  mkwt a feat; W="$T/wt/a"
  wt_park "$W" test x --arm i >/dev/null
  mkdir -p "$W/.claude-tasks"
  run wt_unpark "$W"
  [ "$status" -eq 0 ]
  ls -d "$W".husk-* >/dev/null
  [ -d "$(ls -d "$W".husk-*)/.claude-tasks" ]
  [ "$(git -C "$W" symbolic-ref HEAD)" = refs/heads/feat ]
}

@test "husk with any other file: rc 2 and nothing moves" {
  mkwt a feat; W="$T/wt/a"
  P="$(wt_park "$W" test x --arm i)"
  mkdir -p "$W/.claude-tasks"; echo keep > "$W/notes.txt"
  run wt_unpark "$W"
  [ "$status" -eq 2 ]
  [ -f "$W/notes.txt" ]; [ -d "$P" ]; [ -f "$WT_PARK_INDEX/$(wt__sha1 "$W")" ]
  ! ls -d "$W".husk-* 2>/dev/null
}

@test "unpark refuses when the parked dir is gone and leaves the index for a human" {
  mkwt a feat; W="$T/wt/a"
  P="$(wt_park "$W" test x --arm i)"
  mv "$P" "$T/elsewhere"
  run wt_unpark "$W"
  [ "$status" -eq 2 ]; [ -f "$WT_PARK_INDEX/$(wt__sha1 "$W")" ]
}

@test "park target already exists: rc 2, tree untouched at its path, no index, no row" {
  mkwt a feat; W="$T/wt/a"
  wt__id_new() { printf 'fixed-id'; }
  mkdir -p "$WT_PARK_ROOT/fixed-id"
  run wt_park "$W" test x --arm i
  [ "$status" -eq 2 ]
  [ -d "$W" ]; [ "$(git -C "$W" symbolic-ref HEAD)" = refs/heads/feat ]
  [ ! -e "$WT_PARK_INDEX/$(wt__sha1 "$W")" ]; [ ! -s "$WT_LEDGER" ]
}

@test "a failure after the move (index unwritable) moves the tree back, unlocked and re-attached" {
  mkwt a feat; W="$T/wt/a"
  mkdir -p "$WT_PARK_INDEX"; chmod 500 "$WT_PARK_INDEX"
  run wt_park "$W" test x --arm i
  chmod 700 "$WT_PARK_INDEX"
  [ "$status" -eq 2 ]
  [ -d "$W" ]; [ "$(git -C "$W" symbolic-ref HEAD)" = refs/heads/feat ]
  ! git -C "$R" worktree list --porcelain | grep -q '^locked' || false
  [ -z "$(ls "$WT_PARK_ROOT")" ]; [ ! -s "$WT_LEDGER" ]
}

@test "RED control: resume after park without unpark fails — the branch is checked out at the parked path" {
  mkwt b feat2; W="$T/wt/b"
  wt_park "$W" test x --arm ii >/dev/null
  run git -C "$R" worktree add "$W" feat2          # the unpatched launcher's recreate
  [ "$status" -ne 0 ]
  [[ "$output" == *"feat2"* ]] || false
  run wt_unpark "$W"                                 # the fix
  [ "$status" -eq 0 ]; [ "$(git -C "$W" symbolic-ref HEAD)" = refs/heads/feat2 ]
}

@test "park and unpark run under /bin/bash 3.2" {
  mkwt a feat; W="$T/wt/a"
  run /bin/bash -c '. "$1" && p="$(wt_park "$2" t x --arm i)" && [ -d "$p" ] && wt_unpark "$2" && wt_pinned "$2"; echo "rc=$?"' _ "$LIB" "$W"
  [[ "$output" == "owner sid=- until="*"rc=0" ]] || false # a just-unparked tree is owner-pinned for 60 min
  [ "$(git -C "$W" symbolic-ref HEAD)" = refs/heads/feat ]
}

# ---- pins -----------------------------------------------------------------------------------------

@test "crash pin: CRASH row for a sid of this path pins; a later transcript write, age >7 d, RECYCLE do not" {
  X="$T/x/wt-a"; mkdir -p "$X"; S=11111111-aaaa
  transcript "$T/cfg1" "$X" "$S" $((WT_NOW - 7200))
  printf '{"ts":"%s","sid":"%s","pid":1,"class":"CRASH"}\n' "$(iso $((WT_NOW - 3600)))" "$S" > "$WT_CRASH_LOG"
  run wt_pinned "$X"
  [ "$status" -eq 0 ]; [ "$output" = "crash sid=$S until=$((WT_NOW - 3600 + 604800))" ]
  age "$T/cfg1/projects/$(wt__slug "$X")/$S.jsonl" $((WT_NOW - 60))
  run wt_pinned "$X"; [ "$status" -eq 1 ]
  age "$T/cfg1/projects/$(wt__slug "$X")/$S.jsonl" $((WT_NOW - 9 * 86400))
  printf '{"ts":"%s","sid":"%s","pid":1,"class":"CRASH"}\n' "$(iso $((WT_NOW - 8 * 86400)))" "$S" > "$WT_CRASH_LOG"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
  printf '{"ts":"%s","sid":"%s","pid":1,"class":"RECYCLE"}\n' "$(iso $((WT_NOW - 3600)))" "$S" > "$WT_CRASH_LOG"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
}

@test "crash pin: a sibling worktree /x/wt-a-b's transcripts never pin /x/wt-a" {
  X="$T/x/wt-a"; Y="$T/x/wt-a-b"; mkdir -p "$X" "$Y"; S=22222222-bbbb
  transcript "$T/cfg1" "$Y" "$S" $((WT_NOW - 7200))
  printf '{"ts":"%s","sid":"%s","pid":1,"class":"CRASH"}\n' "$(iso $((WT_NOW - 3600)))" "$S" > "$WT_CRASH_LOG"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
  run wt_pinned "$Y"; [ "$status" -eq 0 ]; [[ "$output" == crash* ]]
}

@test "resume-debt pin: open row with this cwd pins; a discharged one does not" {
  X="$T/x/wt-a"; mkdir -p "$X" "$WT_RESUME_DEBT_DIR"; D="$WT_RESUME_DEBT_DIR/abc.jsonl"
  printf '{"ts":"%s","kind":"open","cwd":"%s","marker":"resume:s1:1","slug":"s1"}\n' "$(iso $((WT_NOW - 60)))" "$X" > "$D"
  run wt_pinned "$X"; [ "$status" -eq 0 ]; [[ "$output" == "resume-debt sid=s1 until="* ]] || false
  run wt_pinned "$T/x/wt-a-b"; [ "$status" -eq 1 ]
  printf '{"ts":"%s","kind":"return","cwd":"%s","marker":"resume:s1:1","slug":"s1"}\n' "$(iso $((WT_NOW - 30)))" "$X" >> "$D"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
}

@test "limit-recover pin: an unproven sid dir pins; a 'Resumed in place' receipt does not" {
  X="$T/x/wt-a"; mkdir -p "$X"; S=33333333-cccc
  transcript "$T/cfg2" "$X" "$S" $((WT_NOW - 7200))
  mkdir -p "$WT_LR_DIR/$S/bundle-1"
  run wt_pinned "$X"; [ "$status" -eq 0 ]; [[ "$output" == "limit-recover sid=$S until="* ]] || false
  printf 'checks\nResumed in place on next4 — same pane\n' > "$WT_LR_DIR/$S/bundle-1/INGEST-VERIFIED.txt"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
}

@test "recycle-failed pin: a packet for a sid of this path pins; another sid's does not" {
  X="$T/x/wt-a"; mkdir -p "$X" "$WT_RECYCLE_FAILED_DIR"; S=44444444-dddd
  transcript "$T/cfg1" "$X" "$S" $((WT_NOW - 7200))
  echo '{}' > "$WT_RECYCLE_FAILED_DIR/other-sid.json"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
  echo '{}' > "$WT_RECYCLE_FAILED_DIR/$S.json"
  run wt_pinned "$X"; [ "$status" -eq 0 ]; [[ "$output" == "recycle-failed sid=$S until="* ]]
}

@test "boot-resume pin: an event naming the path pins until its .done appears" {
  X="$T/x/wt-a"; mkdir -p "$X" "$WT_BOOT_RESUME_DIR/1791247401"
  printf 'pane\t%s\tsid\n' "$X" > "$WT_BOOT_RESUME_DIR/1791247401/rows.tsv"
  run wt_pinned "$X"; [ "$status" -eq 0 ]; [[ "$output" == "boot-resume sid=- until="* ]] || false
  echo 1 > "$WT_BOOT_RESUME_DIR/1791247401.done"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
}

@test "backlog pin: an open row naming the path pins; its later done event releases it" {
  X="$T/x/wt-a"; mkdir -p "$X"
  printf '{"id":"b1","ts":"%s","event":"add","title":"finish %s"}\n' "$(iso $((WT_NOW - 60)))" "$X" > "$WT_BACKLOG"
  printf '{"id":"b2","ts":"%s","event":"add","title":"finish %s-b"}\n' "$(iso $((WT_NOW - 60)))" "$X" >> "$WT_BACKLOG"
  run wt_pinned "$X"; [ "$status" -eq 0 ]; [[ "$output" == "backlog sid=- until="*" id=b1" ]] || false
  printf '{"id":"b1","ts":"%s","event":"done"}\n' "$(iso $((WT_NOW - 30)))" >> "$WT_BACKLOG"
  run wt_pinned "$X"; [ "$status" -eq 1 ]
}

@test "owner pin: a worktree reflog written within 60 min pins; an older one does not" {
  mkwt a feat; W="$T/wt/a"
  run wt_pinned "$W"; [ "$status" -eq 1 ]
  touch "$(git -C "$W" rev-parse --absolute-git-dir)/logs/HEAD"
  run wt_pinned "$W"; [ "$status" -eq 0 ]; [[ "$output" == "owner sid=- until="* ]]
}

@test "--self-owned: the owner pin does not bind the tree's own owner; every other pin still does" {
  mkwt a feat; W="$T/wt/a"
  touch "$(git -C "$W" rev-parse --absolute-git-dir)/logs/HEAD"
  run wt_pinned "$W" --self-owned; [ "$status" -eq 1 ]
  sid=self-owned-sid; slug="$(printf '%s' "$(cd "$W" && pwd -P)" | sed 's#[/.]#-#g')"
  mkdir -p "$T/cfg1/projects/$slug"; echo "{}" > "$T/cfg1/projects/$slug/$sid.jsonl"
  touch -t 202001010000 "$T/cfg1/projects/$slug/$sid.jsonl"
  printf '{"ts":"%s","sid":"%s","class":"CRASH"}\n' "$(date -u -r "$(wt__now)" +%Y-%m-%dT%H:%M:%SZ)" "$sid" >> "$WT_CRASH_LOG"
  run wt_pinned "$W" --self-owned; [ "$status" -eq 0 ]; [[ "$output" == "crash sid=$sid "* ]]
}

# ---- activity legs ------------------------------------------------------------------------------

@test "newest transcript mtime: none is rc 1 and empty; subagent transcripts and a fifth config root count" {
  X="$T/x/wt-a"; mkdir -p "$X"
  run wt_newest_transcript_mtime "$X"; [ "$status" -eq 1 ]; [ -z "$output" ]
  transcript "$T/cfg1" "$X" s1 $((WT_NOW - 9000))
  mkdir -p "$T/cfg1/projects/$(wt__slug "$X")/s1/subagents"
  echo '{}' > "$T/cfg1/projects/$(wt__slug "$X")/s1/subagents/agent-1.jsonl"
  age "$T/cfg1/projects/$(wt__slug "$X")/s1/subagents/agent-1.jsonl" $((WT_NOW - 5000))
  run wt_newest_transcript_mtime "$X"; [ "$output" = $((WT_NOW - 5000)) ]
  export WT_CONFIG_ROOTS="$T/cfg1:$T/cfg2:$T/cfg3:$T/cfg4:$T/cfg5"
  transcript "$T/cfg5" "$X" s5 $((WT_NOW - 100))
  run wt_newest_transcript_mtime "$X"; [ "$status" -eq 0 ]; [ "$output" = $((WT_NOW - 100)) ]
}

@test "recent file: a file touched 2 d ago is recent at 7 d; all ≥8 d is not; .git contents are ignored" {
  X="$T/x/wt-a"; mkdir -p "$X/src" "$X/.git"; echo a > "$X/src/a"; echo g > "$X/.git/HEAD"
  find "$X" -exec touch -t "$(date -r $((WT_NOW - 9 * 86400)) +%Y%m%d%H%M.%S)" {} +
  touch "$X/.git/HEAD"
  run wt_recent_file "$X" 7; [ "$status" -eq 1 ]
  age "$X/src/a" $((WT_NOW - 2 * 86400))
  run wt_recent_file "$X" 7; [ "$status" -eq 0 ]
}

# ---- cc-pin lock sync ---------------------------------------------------------------------------

@test "pin lock sync: pinned tree gets a cc-pin lock that blocks remove --force; released when the record closes; other locks untouched" {
  mkwt a feat; mkwt h human; mkwt p parkme
  A="$T/wt/a"; S=55555555-eeee
  transcript "$T/cfg1" "$A" "$S" $((WT_NOW - 7200))
  mkdir -p "$WT_RECYCLE_FAILED_DIR"; echo '{}' > "$WT_RECYCLE_FAILED_DIR/$S.json"
  git -C "$R" worktree lock --reason "human hold" "$T/wt/h"
  P="$(wt_park "$T/wt/p" test x --arm i)"
  wt_pin_lock_sync "$R" --observe 2>"$T/obs"
  grep -qx "wt-tombstone: would_lock $A recycle-failed" "$T/obs"
  ! git -C "$R" worktree list --porcelain | grep -q 'cc-pin:' || false
  wt_pin_lock_sync "$R"
  git -C "$R" worktree list --porcelain | grep -qx "locked cc-pin:recycle-failed sid=$S until=[0-9]*"
  run git -C "$R" worktree remove --force "$A"
  [ "$status" -ne 0 ]; [ -d "$A" ]
  rm "$WT_RECYCLE_FAILED_DIR/$S.json"
  wt_pin_lock_sync "$R" --observe 2>"$T/obs"
  grep -qx "wt-tombstone: would_unlock $A" "$T/obs"
  git -C "$R" worktree list --porcelain | grep -q 'cc-pin:'
  wt_pin_lock_sync "$R"
  ! git -C "$R" worktree list --porcelain | grep -q 'cc-pin:' || false
  git -C "$R" worktree list --porcelain | grep -qx 'locked human hold'
  git -C "$R" worktree list --porcelain | grep -q "^locked parked .* from $T/wt/p "
}
