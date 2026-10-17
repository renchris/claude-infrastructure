#!/usr/bin/env bats
# pr-gate-forks.bats — hooks/pr-gate.sh reads its stdin without starting `cat`, and decides exactly
# as it did before.
#
# pr-gate sits on the global PreToolUse/Bash chain, so nearly every Bash call reaches its fast path
# and leaves. That path used to start one process (`cat`) to read the payload; `$(</dev/stdin)`
# starts none. Parity is against the REAL pre-change hook, rebuilt from git
# (stop-hook-forks-helpers.bash); counts come from PATH stubs that log every external command.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

load stop-hook-forks-helpers
SHF_BASE=55d01fcd4fca631650df1dbae16e91cfa30821c5

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
}

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  unset CC_PR_PYRAMID PR_REVIEWER CC_PR_MAX_WORDS
  W="$BATS_TEST_TMPDIR/w"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/pr-gate.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# arm <old|new> <label> — one PreToolUse through that arm's hook; stdin is the payload.
arm() {
  local root="$REPO" rc=0
  [ "$1" = old ] && root="$OLD"
  shf_run "$2" "$root/hooks/pr-gate.sh" || rc=$?
  echo "$rc" > "$SHF_OUT_DIR/$2.rc"
}
same() { # <old label> <new label> — stdout, stderr and exit code all equal
  local k
  for k in out err rc; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" || { echo "--- $1.$k"; cat "$SHF_OUT_DIR/$1.$k"; echo "--- $2.$k"; cat "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}
pre() { jq -cn --arg c "$1" --arg w "${2:-$W}" \
  '{session_id:"sidP",hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c},cwd:$w}'; }
big() { # a 240 KB PostToolUse payload; $1 lands inside its stdout
  local s
  s="$(head -c 180000 /dev/zero | tr '\0' 'x')"
  jq -cn --arg s "$s$1$s" '{session_id:"sidP",hook_event_name:"PostToolUse",tool_name:"Bash",
    tool_input:{command:"cat big.log"},tool_response:{stdout:$s,stderr:"",interrupted:false}}' | head -c 245760
}
solo_repo() {
  git init -q "$W"
  ( cd "$W" && git config user.email solo@e.com && git config user.name solo \
      && echo a > a && git add a && git commit -qm a ) >/dev/null 2>&1
}

@test "every corpus payload decides as before: same stdout, stderr and exit code" {
  have_old; solo_repo
  local i=0 p
  local -a corpus=(
    "$(pre 'ls -la')"
    "$(pre $'cd /tmp && make\nfor i in 1 2; do echo "$i"; done\n')"
    "$(pre 'gh pr create --title t --body "Short answer first."')"
    "$(pre 'gh pr create --reviewer bob --title t --body "# Summary
the change"')"
    "$(pre 'gh pr edit 7 --body "## Heading first"' /nonexistent)"
    "$(pre 'echo "gh pr create is mentioned, not run"')"
    "$(jq -cn '{session_id:"s",tool_name:"Read",tool_input:{file_path:"gh pr create"}}')"
    '{"tool_name":"Bash","tool_input":{"command":"gh pr create'
    'not json gh pr edit'
    '[]'
    ''
  )
  for p in "${corpus[@]}"; do
    i=$((i + 1))
    printf '%s' "$p" | arm old "o$i"
    printf '%s' "$p" | arm new "n$i"
    same "o$i" "n$i" || { echo "payload $i differs: $p"; false; }
  done
  # Positive controls: the corpus reaches the ask paths, so parity is not two empty outputs.
  grep -q 'PR necessity' "$SHF_OUT_DIR/o3.out" || { echo "solo-author ask not reached"; cat "$SHF_OUT_DIR/o3.out"; false; }
  grep -q '"permissionDecision"' "$SHF_OUT_DIR/o4.out" || { echo "pyramid ask not reached"; cat "$SHF_OUT_DIR/o4.out"; false; }
}

@test "a 240 KB payload decides as before, and the fast path starts nothing (it started cat)" {
  have_old
  big 'plain output' > "$BATS_TEST_TMPDIR/big1"
  big 'gh pr create in the output' > "$BATS_TEST_TMPDIR/big2"
  [ "$(wc -c < "$BATS_TEST_TMPDIR/big1")" -ge 240000 ]
  arm old o1 < "$BATS_TEST_TMPDIR/big1"; arm new n1 < "$BATS_TEST_TMPDIR/big1"; same o1 n1
  arm old o2 < "$BATS_TEST_TMPDIR/big2"; arm new n2 < "$BATS_TEST_TMPDIR/big2"; same o2 n2
  echo "# fast path: $(shf_total o1) external calls before ($(shf_census o1)), $(shf_total n1) after" >&3
  [ "$(shf_calls o1 cat)" -eq 1 ]
  [ "$(shf_calls n1 cat)" -eq 0 ]
  [ "$(shf_total n1)" -eq 0 ]
  [ "$(shf_total n2)" -lt "$(shf_total o2)" ]
}

@test "empty stdin and the kill switch: same as before, and nothing started" {
  have_old
  arm old o1 < /dev/null; arm new n1 < /dev/null; same o1 n1
  [ "$(shf_total n1)" -eq 0 ]
  pre 'gh pr create --body "# H"' | CC_PR_PYRAMID=off arm old o2
  pre 'gh pr create --body "# H"' | CC_PR_PYRAMID=off arm new n2
  same o2 n2
}

@test "the 240 KB payload is read no slower than by cat (median of 5 interleaved runs, within 10%)" {
  have_old
  [ -n "${EPOCHREALTIME:-}" ] || skip "this bats runs under a bash without EPOCHREALTIME"
  local p k t0 t1 os=() ns=() om nm
  p="$(big 'plain output')"
  # The payload arrives on a pipe, as the harness sends it; printf is a builtin, so the feeder
  # costs both arms the same fork and no exec.
  for k in 1 2 3 4 5; do
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$OLD/hooks/pr-gate.sh" >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    os+=($((t1 - t0)))
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$REPO/hooks/pr-gate.sh" >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    ns+=($((t1 - t0)))
  done
  om="$(printf '%s\n' "${os[@]}" | sort -n | sed -n 3p)"
  nm="$(printf '%s\n' "${ns[@]}" | sort -n | sed -n 3p)"
  echo "# 240 KB read, median µs: before $om, after $nm" >&3
  [ $((nm * 10)) -le $((om * 11)) ] || { echo "slower: $om -> $nm µs (${os[*]} / ${ns[*]})"; false; }
}
