#!/usr/bin/env bats
# cc-permission-beacon-forks.bats — hooks/cc-permission-beacon.sh reads its stdin without starting
# `cat`, and writes, clears and archives beacons exactly as before.
#
# The beacon's `clear` arm fires on every tool call, so the `cat` that read its payload was one
# process start on every tool call of every session; `$(</dev/stdin)` starts none. Parity is
# against the REAL pre-change hook, rebuilt from git (stop-hook-forks-helpers.bash); counts come
# from PATH stubs that log every external command. Wall-clock fields (ts, resolved_ts, waited_s)
# are the only ones allowed to differ.
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
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/permpend"
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/permarchive"
  unset CC_PERMISSION_BEACON_DISABLED CC_PERMARCHIVE_MAXLEN
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/cc-permission-beacon.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

blank() { rm -rf "$CC_PERMPEND_DIR" "$CC_PERMARCHIVE_DIR"; }
# keep <label> — the beacon and archive trees: every file name, and each JSON row minus its clock.
keep() {
  local d f
  for d in "$CC_PERMPEND_DIR" "$CC_PERMARCHIVE_DIR"; do
    [ -d "$d" ] || { echo "(no ${d##*/})"; continue; }
    ( cd "$d" && find . -type f | LC_ALL=C sort ) | while IFS= read -r f; do
      echo "== ${d##*/}/$f"
      case "$f" in
        *.json|*.jsonl) jq -cS 'del(.ts, .resolved_ts, .waited_s)' "$d/$f" 2>&1 ;;
      esac
    done
  done > "$SHF_OUT_DIR/$1.state"
}
# arm <old|new> <label> <mode> — one call through that arm's hook; stdin is the payload.
arm() {
  local root="$REPO" rc=0
  [ "$1" = old ] && root="$OLD"
  shf_run "$2" "$root/hooks/cc-permission-beacon.sh" "$3" || rc=$?
  echo "$rc" > "$SHF_OUT_DIR/$2.rc"
  keep "$2"
}
same() { # <old label> <new label> — stdout, stderr, exit code and beacon/archive state all equal
  local k
  for k in out err rc state; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" || { echo "--- $1.$k"; cat "$SHF_OUT_DIR/$1.$k"; echo "--- $2.$k"; cat "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}
req() { jq -cn --arg c "$1" '{session_id:"sidB",hook_event_name:"PermissionRequest",tool_name:"Bash",
  tool_use_id:"tu1",tool_input:{command:$c},cwd:"/w/repo"}'; }
post() { jq -cn --arg c "$1" --arg ev "${2:-PostToolUse}" '{session_id:"sidB",hook_event_name:$ev,
  tool_name:"Bash",tool_use_id:"tu1",tool_input:{command:$c},cwd:"/w/repo",
  tool_response:{stdout:"ok",stderr:"",interrupted:false}}'; }
big() { # a 240 KB PostToolUse payload for the same invocation
  local s
  s="$(head -c 240000 /dev/zero | tr '\0' 'z')"
  jq -cn --arg s "$s" --arg c "$1" '{session_id:"sidB",hook_event_name:"PostToolUse",tool_name:"Bash",
    tool_use_id:"tu1",tool_input:{command:$c},cwd:"/w/repo",tool_response:{stdout:$s,stderr:"",interrupted:false}}'
}

# pair <label> <write payload|-> <mode> <payload> — the same sequence through both arms, from blank.
pair() {
  local l="$1" w="$2" mode="$3" p="$4" a
  for a in old new; do
    blank
    [ "$w" = - ] || printf '%s' "$w" | arm "$a" "${a:0:1}w$l" write
    printf '%s' "$p" | arm "$a" "${a:0:1}$l" "$mode"
  done
  [ "$w" = - ] || same "ow$l" "nw$l" || { echo "write before case $l differs"; return 1; }
  same "o$l" "n$l" || { echo "case $l differs: $mode $p"; return 1; }
}

@test "write, then every kind of clear, leaves the same beacons and archive rows as before" {
  have_old
  local cmd='git reset --hard origin/main'
  pair 1 - write "$(req "$cmd")"
  grep -q 'git reset' "$SHF_OUT_DIR/o1.state" || { echo "no beacon written"; cat "$SHF_OUT_DIR/o1.state"; false; }
  pair 2 "$(req "$cmd")" clear "$(post "$cmd")"
  grep -q 'permarchive/' "$SHF_OUT_DIR/o2.state" || { echo "clear archived nothing"; cat "$SHF_OUT_DIR/o2.state"; false; }
  pair 3 "$(req "$cmd")" clear "$(post "$cmd" PostToolUseFailure)"
  pair 4 "$(req "$cmd")" clear "$(post 'a different command')"
  pair 5 "$(req "$cmd")" clear "$(jq -cn '{session_id:"sidB",hook_event_name:"UserPromptSubmit",prompt:"next"}')"
  pair 6 - clear "$(post "$cmd")"
  pair 7 "$(req "$cmd")" clear "$(big "$cmd")"
  pair 8 "$(req $'line one\nline two\n')" clear "$(post $'line one\nline two\n')"
}

@test "odd payloads are handled as before: empty, malformed, unsafe or missing session ids" {
  have_old
  local i=0 p m
  for m in write clear; do
    for p in '' 'not json' '[]' '{}' '{"session_id":"../escape"}' '{"session_id":""}' \
             '{"session_id":"s1"}{"session_id":"s2"}' "$(req 'echo hi')"; do
      i=$((i + 1))
      pair "x$i" - "$m" "$p" || false
    done
  done
}

@test "a clear starts no cat (it started one), and the same number of everything else" {
  have_old
  local cmd='git reset --hard origin/main'
  pair 1 "$(req "$cmd")" clear "$(post "$cmd")"
  echo "# clear: $(shf_census o1)-> $(shf_census n1)" >&3
  [ "$(shf_calls o1 cat)" -eq 1 ]
  [ "$(shf_calls n1 cat)" -eq 0 ]
  # The hasher now runs as /sbin/sha256sum by absolute path (not a #! exec), which this PATH-stub
  # census cannot see: the old arm's shasum calls drop out of the count, not out of the code.
  [ "$(shf_calls n1 shasum)" -eq 0 ]
  [ "$(shf_total n1)" -eq $(( $(shf_total o1) - 1 - $(shf_calls o1 shasum) )) ]
  pair 2 - clear "$(big "$cmd")"
  [ "$(shf_calls n2 cat)" -eq 0 ]
  [ "$(shf_total n2)" -eq $(( $(shf_total o2) - 1 )) ]
}

@test "the 240 KB payload is read no slower than by cat (median of 5 interleaved runs, within 10%)" {
  have_old
  [ -n "${EPOCHREALTIME:-}" ] || skip "this bats runs under a bash without EPOCHREALTIME"
  local p k t0 t1 os=() ns=() om nm
  p="$(big 'echo hi')"
  blank
  # On a pipe, as the harness sends it; printf is a builtin, so the feeder costs both arms the same.
  for k in 1 2 3 4 5; do
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$OLD/hooks/cc-permission-beacon.sh" clear >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    os+=($((t1 - t0)))
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$REPO/hooks/cc-permission-beacon.sh" clear >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    ns+=($((t1 - t0)))
  done
  om="$(printf '%s\n' "${os[@]}" | sort -n | sed -n 3p)"
  nm="$(printf '%s\n' "${ns[@]}" | sort -n | sed -n 3p)"
  echo "# 240 KB clear, median µs: before $om, after $nm" >&3
  [ $((nm * 10)) -le $((om * 11)) ] || { echo "slower: $om -> $nm µs (${os[*]} / ${ns[*]})"; false; }
}
