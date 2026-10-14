#!/usr/bin/env bats
# stop-hook-durations-libs.bats — hooks/lib/session-writes.sh and hooks/lib/peer-owned.sh give the
# SAME answers as before at a bounded process count (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md,
# Wave 4b).
#
# The defect: replayed on real cancelled Stops, session-continue spent 162 s in
# session_unlanded_mine (one grep per file of a large trunk..HEAD diff) and completion-assert 24 s
# in these two libs (one grep and one stat per dirty record, four `git status -uall`, sixteen reads
# of one transcript) — against 5 s timeouts, so both were cancelled and their gates failed open.
#
# PARITY is against the real pre-change libs, rebuilt from git (stop-hook-forks-helpers.bash,
# SHF_BASE below), over ONE fixture repo shaped like the incident: modified tracked files, a staged
# rename, a deletion, hundreds of untracked files inside new directories, a name with a space and a
# name with a NEWLINE (the shape that keeps the old grep), 300 commits ahead of trunk, a live peer.
# Every reader is compared on stdout and rc, with and without the per-run memo.
#
# BUDGET tests count external commands through PATH stubs, and each carries its own CONTROL: the
# same call on the pre-change lib must exceed the bound, which proves the fixture reaches the
# per-record regime (a fixture too small to show the defect would pass either way). Reverting either
# lib turns these red.

load stop-hook-forks-helpers

# Trunk just before Wave 4b.
SHF_BASE=4b1224be5f1319ae68d0a50e021e0309bd21b34c

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO
  OLD="$BATS_FILE_TMPDIR/old"
  export OLD
  shf_old_tree "$OLD" "$REPO" hooks/lib/session-writes.sh hooks/lib/peer-owned.sh || true
  local T="$BATS_FILE_TMPDIR" i d
  T="$(cd "$T" && pwd -P)"
  W="$T/w"; export W
  git init -q --bare "$T/o.git"
  git -c init.defaultBranch=main clone -q "$T/o.git" "$W" 2>/dev/null
  (
    cd "${W:?fixture repo path required}" || exit 1
    git symbolic-ref HEAD refs/heads/main
    mkdir -p tracked
    for i in $(seq 1 40); do i="$(printf %03d "$i")"; echo "t$i" > "tracked/t$i.txt"; done
    echo src > ren-src.txt; echo del > del.txt; echo sp > "sp ace.txt"
    # A TRANSIENT identity (-c) — nothing is written to any repo config.
    git add -A; git -c user.email=t@e.com -c user.name=t commit -qm base; git push -q -u origin main
    mkdir -p ahead
    for i in $(seq -w 1 300); do echo "a$i" > "ahead/a$i.txt"; done
    git add -A; git -c user.email=t@e.com -c user.name=t commit -qm "unlanded work"
    for i in $(seq 1 30); do i="$(printf %03d "$i")"; echo mod >> "tracked/t$i.txt"; done
    git mv ren-src.txt ren-dst.txt
    rm del.txt
    for d in 1 2 3 4 5 6 7 8 9 10; do
      mkdir -p "assets/deep/d$d"
      for i in $(seq 1 25); do echo x > "assets/deep/d$d/f$i.bin"; done
    done
    mkdir -p "new dir"; echo n > "new dir/with space.txt"
    printf 'nl\n' > "nl
name.txt"
  ) > "$T/fixture.log" 2>&1 || { echo "fixture build failed:"; cat "$T/fixture.log"; } >&2
  ln -s "$W" "$T/link"
  export NOW; NOW="$(date +%s)"
  local iso_a iso_b iso_c iso_d
  iso_a="$(date -u -r $(( NOW - 3600 )) +%Y-%m-%dT%H:%M:%S.000Z)"
  iso_b="$(date -u -r $(( NOW + 3600 )) +%Y-%m-%dT%H:%M:%S.000Z)"
  iso_c="$(date -u -r $(( NOW + 7200 )) +%Y-%m-%dT%H:%M:%S.000Z)"
  iso_d="$(date -u -r $(( NOW + 9000 )) +%Y-%m-%dT%H:%M:%S.000Z)"
  # A: a session that WROTE things — some dirty, some unlanded, one outside the repo, one spelled
  # through a symlink. B: a write-free session bracketing every mtime. C: one that starts after them.
  TA="$T/a.jsonl" TB="$T/b.jsonl" TC="$T/c.jsonl"; export TA TB TC
  {
    jq -cn --arg ts "$iso_a" '{type:"user",timestamp:$ts,message:{role:"user",content:"go"}}'
    for p in "$W/tracked/t001.txt" "$W/tracked/t007.txt" "$W/ahead/a150.txt" "$W/ren-dst.txt" \
             "$W/del.txt" "$W/new dir/with space.txt" "/tmp/elsewhere.txt" "$T/link/tracked/t011.txt" \
             $(for i in $(seq 1 25); do printf '%s ' "$W/assets/deep/d3/f$i.bin"; done); do
      jq -cn --arg ts "$iso_a" --arg p "$p" \
        '{type:"assistant",timestamp:$ts,message:{content:[{type:"tool_use",name:"Edit",input:{file_path:$p}}]}}'
    done
    jq -cn --arg ts "$iso_b" '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:"done"}]}}'
  } > "$TA"
  {
    jq -cn --arg ts "$iso_a" '{type:"user",timestamp:$ts,message:{role:"user",content:"look"}}'
    jq -cn --arg ts "$iso_b" '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:"read only"}]}}'
  } > "$TB"
  {
    jq -cn --arg ts "$iso_c" '{type:"user",timestamp:$ts,message:{role:"user",content:"later"}}'
    jq -cn --arg ts "$iso_d" '{type:"assistant",timestamp:$ts,message:{content:[{type:"text",text:"ok"}]}}'
  } > "$TC"
  # A LIVE peer (this test runner's pid) whose own transcript edit-recorded every dirty path.
  export CC_REGISTRY_DIR="$T/reg" PEER_OWNED_HOMES="$T/acct"
  mkdir -p "$CC_REGISTRY_DIR"
  local slug pd
  slug="$(printf '%s' "$W" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g')"
  pd="$PEER_OWNED_HOMES/projects/$slug"; mkdir -p "$pd"
  {
    jq -cn --arg ts "$iso_a" '{type:"user",timestamp:$ts,message:{role:"user",content:"peer"}}'
    ( cd "$W" && git -c core.quotePath=false status --porcelain -uall ) | cut -c4- | sed 's/^"//; s/"$//' |
      while IFS= read -r p; do
        jq -cn --arg ts "$iso_a" --arg p "$W/$p" \
          '{type:"assistant",timestamp:$ts,message:{content:[{type:"tool_use",name:"Write",input:{file_path:$p}}]}}'
      done
  } > "$pd/peerS.jsonl"
  jq -nc --arg c "$W" --argjson p "$$" --argjson t "$(( (NOW - 7200) * 1000 ))" \
    '{paneUUID:"peerS",name:"claude-peer",cwd:$c,account:"a",pid:$p,startedAt:$t,session_id:"peerS"}' \
    > "$CC_REGISTRY_DIR/peerS.json"
}

setup() {
  [ -f "$OLD/hooks/lib/session-writes.sh" ] && [ ! -L "$OLD/hooks/lib/session-writes.sh" ] \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"; mkdir -p "$TMPDIR"
  unset SW_RUN_MEMO SESSION_WRITES_LIB
}

# ask <lib dir> <memo:on|off> <shell code> — run the code with both libs sourced; stdout + "rc=N".
ask() {
  local libdir="$1" memo="$2" code="$3"
  /bin/bash -c '
    set -uo pipefail
    . "$1/session-writes.sh"; . "$1/peer-owned.sh"
    [ "$2" = on ] && sw_run_memo_init 2>/dev/null
    eval "$3"
  ' _ "$libdir" "$memo" "$code" 2>/dev/null
}

# The eleven questions, each printed with its rc, asked twice in one shell (the second answer is the
# memo's when it is on).
QUESTIONS='
for t in "$TA" "$TB" "$TC" /nonexistent.jsonl; do
  for r in 1 2; do
    out="$(session_dirty_mine "$t" "$W")"; echo "dirty $t rc=$? [$out]"
    out="$(session_unlanded_mine "$t" "$W" origin/main)"; echo "unlanded $t rc=$? [$out]"
    out="$(session_writes_paths "$t")"; echo "paths $t rc=$? [$out]"
    out="$(session_writes_paths_turn "$t")"; echo "turn $t rc=$? [$out]"
    out="$(session_wrote_here_this_turn "$t" "$W")"; echo "here $t rc=$? [$out]"
    out="$(dirt_predates_session "$W" mineS "$t")"; echo "predates $t rc=$? [$out]"
    out="$(dirt_outside_session_execution "$W" "$t")"; echo "outside $t rc=$? [$out]"
    out="$(dirt_unreachable_by_session "$W" mineS "$t")"; echo "unreach $t rc=$? [$out]"
    out="$(dirt_edited_by_live_peer "$W" mineS "$t")"; echo "peer $t rc=$? [$out]"
  done
done'

@test "D1 the fixture reaches the regime: hundreds of dirty records, hits in every class" {
  tail -15 "$BATS_FILE_TMPDIR/fixture.log"
  run ask "$REPO/hooks/lib" off 'session_dirty_mine "$TA" "$W"; echo "rc=$?"'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'tracked/t001.txt'
  echo "$output" | grep -qx 'tracked/t011.txt'          # reached through the symlinked spelling
  echo "$output" | grep -qx 'assets/deep/d3/f25.bin'    # an untracked file in a NEW directory
  echo "$output" | grep -qx 'new dir/with space.txt'
  echo "$output" | grep -qx 'rc=0'
  n="$(cd "$W" && git status --porcelain -z -uall | tr -cd '\0' | wc -c | tr -d ' ')"
  [ "$n" -ge 280 ]
}

@test "D2 PARITY: every reader answers byte-identically to the pre-change libs (memo off)" {
  ask "$OLD/hooks/lib" off "$QUESTIONS" > "$SHF_OUT_DIR/old"
  ask "$REPO/hooks/lib" off "$QUESTIONS" > "$SHF_OUT_DIR/new"
  [ "$(grep -cE '^(dirty|unlanded|paths|turn|here|predates|outside|unreach|peer) .* rc=[0-9]+ \[' "$SHF_OUT_DIR/old")" -eq 72 ]
  diff "$SHF_OUT_DIR/old" "$SHF_OUT_DIR/new"
}

@test "D3 PARITY with the per-run memo on: the second ask of every question gets the first answer" {
  ask "$OLD/hooks/lib" off "$QUESTIONS" > "$SHF_OUT_DIR/old"
  ask "$REPO/hooks/lib" on "$QUESTIONS" > "$SHF_OUT_DIR/new"
  diff "$SHF_OUT_DIR/old" "$SHF_OUT_DIR/new"
}

@test "D4 the memo dir is removed when the shell that made it exits" {
  run /bin/bash -c '. "$1/session-writes.sh"; sw_run_memo_init; echo "$SW_RUN_MEMO"; session_writes_paths "$2" >/dev/null' \
    _ "$REPO/hooks/lib" "$TA"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ ! -e "$output" ]
}

# budget <lib dir> <label> <shell code> — the code under the stub PATH, /bin/bash, memo on.
budget() {
  export SHF_FORK_LOG="$SHF_OUT_DIR/$2.forks"; : > "$SHF_FORK_LOG"
  PATH="$STUB" /bin/bash -c '
    . "$1/session-writes.sh"; . "$1/peer-owned.sh"; sw_run_memo_init 2>/dev/null
    eval "$2"' _ "$1" "$3" >/dev/null 2>&1 || true
}

@test "B1 session_dirty_mine: no grep per record, no full untracked walk (control: the old lib forks hundreds)" {
  budget "$REPO/hooks/lib" new 'session_dirty_mine "$TA" "$W"'
  budget "$OLD/hooks/lib" old 'session_dirty_mine "$TA" "$W"'
  echo "new: $(shf_census new)"; echo "old: $(shf_census old)"
  [ "$(shf_calls old grep)" -ge 250 ]
  [ "$(shf_calls new grep)" -le 1 ]
  [ "$(shf_total new)" -le 40 ]
}

@test "B2 session_unlanded_mine over 300 commits ahead: no grep per file (control: the old lib forks one each)" {
  budget "$REPO/hooks/lib" new 'session_unlanded_mine "$TB" "$W" origin/main; session_unlanded_mine "$TC" "$W" origin/main'
  budget "$OLD/hooks/lib" old 'session_unlanded_mine "$TB" "$W" origin/main; session_unlanded_mine "$TC" "$W" origin/main'
  echo "new: $(shf_census new)"; echo "old: $(shf_census old)"
  [ "$(shf_calls old grep)" -eq 0 ] || true   # B/C wrote nothing: rc 1 before the loop in both
  budget "$REPO/hooks/lib" new2 'session_unlanded_mine "$TA" "$W" origin/main'
  budget "$OLD/hooks/lib" old2 'session_unlanded_mine "$TA" "$W" origin/main'
  echo "new2: $(shf_census new2)"; echo "old2: $(shf_census old2)"
  [ "$(shf_calls old2 grep)" -ge 100 ]
  [ "$(shf_calls new2 grep)" -eq 0 ]
}

@test "B3 the peer-owned readers over every dirty record: one snapshot, batched stat, no grep (control: old)" {
  local q='dirt_predates_session "$W" mineS "$TC"; dirt_unreachable_by_session "$W" mineS "$TB"
           dirt_outside_session_execution "$W" "$TB"; dirt_edited_by_live_peer "$W" mineS "$TB"'
  # A deleted file has no mtime, so it ends every per-record walk at its record (cannot-tell): put it
  # back for this test so each walk covers the whole tree, and delete it again afterwards.
  git -C "$W" checkout -q -- del.txt
  budget "$REPO/hooks/lib" new "$q"
  budget "$OLD/hooks/lib" old "$q"
  local p='out="$(dirt_predates_session "$W" mineS "$TC")"; echo "p rc=$? [$out]"
           out="$(dirt_unreachable_by_session "$W" mineS "$TB")"; echo "u rc=$? [$out]"
           out="$(dirt_outside_session_execution "$W" "$TB")"; echo "o rc=$? [$out]"
           out="$(dirt_edited_by_live_peer "$W" mineS "$TB")"; echo "e rc=$? [$out]"'
  ask "$OLD/hooks/lib" off "$p" > "$SHF_OUT_DIR/b3old"
  ask "$REPO/hooks/lib" on "$p" > "$SHF_OUT_DIR/b3new"
  rm -f "$W/del.txt"
  cat "$SHF_OUT_DIR/b3new"
  grep -q '^p rc=0 \[paths=2' "$SHF_OUT_DIR/b3new"     # the walk covered the whole tree
  diff "$SHF_OUT_DIR/b3old" "$SHF_OUT_DIR/b3new"
  echo "new: $(shf_census new)"; echo "old: $(shf_census old)"
  [ "$(shf_calls old stat)" -ge 250 ]
  [ "$(shf_calls new stat)" -le 20 ]
  [ "$(shf_calls new grep)" -le 4 ]
  # four whole-tree questions, ONE `git status`: the snapshot is shared through the run's memo
  [ "$(shf_total new)" -le 80 ]
  [ $(( $(shf_total new) * 10 )) -le "$(shf_total old)" ]
  [ "$(shf_calls new git)" -le 8 ]
}

@test "B4 the transcript is read once per scope per run however many readers ask" {
  budget "$REPO/hooks/lib" new 'for i in 1 2 3 4 5; do session_writes_paths "$TA"; session_writes_paths_turn "$TA"; done'
  [ "$(shf_calls new jq)" -le 2 ]
}
