#!/usr/bin/env bats
# log-bash-forks.bats — hooks/log-bash.sh reads its five payload fields with ONE jq, and writes the
# same audit line, lesson output and exit code as before.
#
# log-bash fires on every Bash PostToolUse and PostToolUseFailure, and its payload can be 240 KB
# (the command's whole output). It started jq four times on that payload (five on a failure), plus
# `mkdir -p` for a log directory that nearly always exists. Parity is against the REAL pre-change
# hook, rebuilt from git (stop-hook-forks-helpers.bash); counts come from PATH stubs that log every
# external command. The audit line's leading timestamp is the only field allowed to differ.
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
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/log-bash.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# arm <old|new> <label> — one call through that arm's hook from a blank HOME (logs dir present, as
# it always is on a live machine); stdin is the payload. Files the audit log, minus its timestamps.
arm() {
  local root="$REPO" rc=0
  [ "$1" = old ] && root="$OLD"
  rm -rf "$HOME" "$CC_IDL"; mkdir -p "$HOME/.claude/logs"
  shf_run "$2" "$root/hooks/log-bash.sh" || rc=$?
  echo "$rc" > "$SHF_OUT_DIR/$2.rc"
  sed -E 's/^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z\] //' "$HOME/.claude/logs/bash-execution.log" \
    > "$SHF_OUT_DIR/$2.log" 2>/dev/null || : > "$SHF_OUT_DIR/$2.log"
  shf_idl "$CC_IDL" > "$SHF_OUT_DIR/$2.idl"
}
same() { # <old label> <new label> — stdout, stderr, exit code, audit line and IDL rows all equal
  local k
  for k in out err rc log idl; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" || { echo "--- $1.$k"; cat "$SHF_OUT_DIR/$1.$k"; echo "--- $2.$k"; cat "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}
post() { jq -cn --arg c "$1" '{session_id:"sidL",hook_event_name:"PostToolUse",tool_name:"Bash",
  tool_input:{command:$c},tool_response:{stdout:"x",stderr:"",interrupted:false,isImage:false}}'; }
fail() { jq -cn --arg c "$1" --arg e "$2" '{session_id:"sidL",hook_event_name:"PostToolUseFailure",
  tool_name:"Bash",tool_use_id:"tu1",tool_input:{command:$c},error:$e}'; }
big() { # a 240 KB PostToolUse payload
  local s
  s="$(head -c 240000 /dev/zero | tr '\0' 'y')"
  jq -cn --arg s "$s" '{session_id:"sidL",hook_event_name:"PostToolUse",tool_name:"Bash",
    tool_input:{command:"cat big.log"},tool_response:{stdout:$s,stderr:"",interrupted:false}}'
}

@test "every corpus payload logs as before: same audit line, stdout, stderr, exit code and IDL" {
  have_old
  local i=0 p
  local -a corpus=(
    "$(post 'ls -la')"
    "$(post $'cd /tmp && make\nfor i in 1 2; do echo "$i"; done\n\n')"
    "$(post 'printf "a  b\tc"  ;  echo   spaced')"
    "$(post "$(head -c 30000 /dev/zero | tr '\0' 'c')"$'\nsecond line\n\n')"
    "$(jq -cn '{session_id:"sidL",hook_event_name:"PostToolUse",tool_input:{command:"exit 3"},tool_response:{exitCode:3}}')"
    "$(jq -cn '{session_id:"sidL",hook_event_name:"PostToolUse",tool_input:{command:"true"},tool_response:{exitCode:0}}')"
    "$(fail 'false' 'Exit code 1')"
    "$(fail 'make test' $'Exit code 2\nline two of the error\nline three\n')"
    "$(fail 'sleep 999' 'Interrupted')"
    "$(fail 'boom' '')"
    "$(jq -cn '{session_id:"sidL",hook_event_name:"PostToolUseFailure",tool_input:{command:"x"}}')"
    "$(jq -cn '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"git status"}}')"
    "$(jq -cn '{session_id:"",tool_input:{command:"a"}}')"
    "$(jq -cn '{session_id:false,tool_input:{command:false}}')"
    "$(jq -cn '{session_id:7,tool_input:{command:"n"}}')"
    "$(jq -cn '{session_id:"s",tool_input:{command:"has \u001f a unit separator"}}')"
    "$(jq -cn '{session_id:"s",tool_input:{command:"has \u0000 a nul"}}')"
    "$(jq -cn '{session_id:"s",tool_input:"not an object"}')"
    "$(jq -cn '{session_id:"s",hook_event_name:"PostToolUseFailure",error:{"code":2}}')"
    '{"session_id":"a","tool_input":{"command":"one"}}{"session_id":"b","tool_input":{"command":"two"}}'
    '{"session_id":"a"} [1]'
    'not json'
    '[]'
    'null'
    '{}'
    ''
  )
  for p in "${corpus[@]}"; do
    i=$((i + 1))
    printf '%s' "$p" | arm old "o$i"
    printf '%s' "$p" | arm new "n$i"
    same "o$i" "n$i" || { echo "payload $i differs: $p"; false; }
  done
  # Positive controls: the corpus reaches the exit-code derivations, so parity is not two blanks.
  grep -q 'Exit: 3$' "$SHF_OUT_DIR/o5.log"
  grep -q 'Exit: 2 line two of the error line three$' "$SHF_OUT_DIR/o8.log"
  grep -q 'Exit: Interrupted$' "$SHF_OUT_DIR/o9.log"
  grep -q 'Exit: fail$' "$SHF_OUT_DIR/o10.log"
  grep -q '^second line | Exit: 0$' "$SHF_OUT_DIR/n4.log"
}

@test "a PostToolUse starts jq once (it started four) and no mkdir; a failure starts jq once (five)" {
  have_old
  post 'ls -la' | arm old o1; post 'ls -la' | arm new n1; same o1 n1
  echo "# PostToolUse: $(shf_census o1)-> $(shf_census n1)" >&3
  [ "$(shf_calls o1 jq)" -eq 4 ]
  [ "$(shf_calls n1 jq)" -eq 1 ]
  [ "$(shf_calls o1 mkdir)" -eq 1 ]
  [ "$(shf_calls n1 mkdir)" -eq 0 ]
  fail 'false' $'Exit code 1\nmore' | arm old o2; fail 'false' $'Exit code 1\nmore' | arm new n2; same o2 n2
  echo "# PostToolUseFailure: $(shf_census o2)-> $(shf_census n2)" >&3
  [ "$(shf_calls n2 jq)" -le $(( $(shf_calls o2 jq) - 4 )) ]
  [ "$(shf_total n2)" -lt "$(shf_total o2)" ]
}

@test "a missing logs directory is still created, and the line still lands" {
  have_old
  local rc=0
  rm -rf "$HOME"; mkdir -p "$HOME"
  post 'echo first' | PATH="$STUB" SHF_FORK_LOG=/dev/null /bin/bash "$REPO/hooks/log-bash.sh" || rc=$?
  [ "$rc" -eq 0 ]
  grep -q '\[sidL\] echo first | Exit: 0$' "$HOME/.claude/logs/bash-execution.log"
}

@test "a 240 KB payload logs as before, with one jq and no slower (median of 5 interleaved runs, within 10%)" {
  have_old
  local p k t0 t1 os=() ns=() om nm
  p="$(big)"
  [ "${#p}" -ge 240000 ]
  printf '%s' "$p" | arm old o1; printf '%s' "$p" | arm new n1; same o1 n1
  [ "$(shf_calls n1 jq)" -eq 1 ]
  [ -n "${EPOCHREALTIME:-}" ] || skip "this bats runs under a bash without EPOCHREALTIME"
  # On a pipe, as the harness sends it; printf is a builtin, so the feeder costs both arms the same.
  for k in 1 2 3 4 5; do
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$OLD/hooks/log-bash.sh" >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    os+=($((t1 - t0)))
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$REPO/hooks/log-bash.sh" >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    ns+=($((t1 - t0)))
  done
  om="$(printf '%s\n' "${os[@]}" | sort -n | sed -n 3p)"
  nm="$(printf '%s\n' "${ns[@]}" | sort -n | sed -n 3p)"
  echo "# 240 KB payload, median µs: before $om, after $nm" >&3
  [ $((nm * 10)) -le $((om * 11)) ] || { echo "slower: $om -> $nm µs (${os[*]} / ${ns[*]})"; false; }
  # The old read stripped trailing newlines with `${INPUT%$'\n'}`, quadratic under bash 3.2 in a
  # UTF-8 locale: measured 11-16 s here against ~0.05-0.1 s for `$(</dev/stdin)`. A 4x margin
  # pins the fix without riding the load.
  [ $((nm * 4)) -le "$om" ] || { echo "the quadratic read is back? $om -> $nm µs (${os[*]} / ${ns[*]})"; false; }
}
