#!/usr/bin/env bats
# waiting-recycle-forks.bats — hooks/waiting-recycle.sh in PostToolUse actuation mode reads stdin
# without `cat`, its three payload fields with ONE jq, and its sentinel keys from a memo; and it
# decides, logs and leaves state exactly as before.
#
# The hook polls on every Bash call. Before this it started `cat`, jq three times over the whole
# payload, and `shasum | cut` (a perl start) for a cwd key that is a pure function of (config dir,
# cwd) — plus once more for the role key on the desk. The keys now come from
# $STATE_DIR/keymemo/, and a miss computes them exactly as before. Parity is against the REAL
# pre-change hook, rebuilt from git (stop-hook-forks-helpers.bash); counts come from PATH stubs that
# log every external command. Each case runs twice per arm from the same blank state, so the first
# new-arm call is a memo MISS and the second a memo HIT, and each is compared with the old arm's
# call in the same position. The memo files themselves are the one deliberate addition to the state
# dir, so the state comparison leaves out keymemo/ and a separate case pins what it holds.
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
  export CC_WR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"
  export CC_WR_SHARED_STATE_DIR="$BATS_TEST_TMPDIR/shared"
  export CC_WR_FIRE_DIR="$BATS_TEST_TMPDIR/fire"
  export CC_WR_UUID="FORKS-TEST-UUID"
  export CC_WR_COOLDOWN_S=0 CC_WR_MAX=9 CC_WR_T_NUDGE=101
  export CC_FIRE_CAPACITY_GATE=off
  export CC_WR_NOTIFY="$BATS_TEST_TMPDIR/noop.sh"
  printf '#!/bin/bash\nexit 0\n' > "$CC_WR_NOTIFY"; chmod +x "$CC_WR_NOTIFY"
  unset CC_WR_DESK_ROLE CC_HOOK_PROFILE
  SID="forks-sid-1"
  WORK="$BATS_TEST_TMPDIR/work dir"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/waiting-recycle.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# The hook's key spelling, recomputed independently, so a memo that drifted by one byte shows.
key() { printf '%s' "$1" | shasum | cut -c1-16; }

# blank [desk] [disarm-cwd|disarm-role] — every directory the hook writes, emptied; the state dir
# exists, as it does on a live machine. `desk` makes this session the role holder.
blank() {
  local d
  for d in "$HOME" "$CC_WR_STATE_DIR" "$CC_TELEMETRY_DIR" "$CLAUDE_CONFIG_DIR" "$CC_WR_COORD_DIR" \
           "$CC_WR_SHARED_STATE_DIR" "$CC_WR_FIRE_DIR" "$WORK"; do
    rm -rf "$d"; mkdir -p "$d"
  done
  mkdir -p "$CC_WR_COORD_DIR/cc-roles"
  rm -f "$CC_WR_IDL"
  [ "${1:-}" = desk ] && printf '%s\n' "$SID" > "$CC_WR_COORD_DIR/cc-roles/desk"
  case "${2:-}" in
    disarm-cwd)  printf '2026-01-01T00:00:00Z x\n' > "$CC_WR_STATE_DIR/disarm-$(key "$CLAUDE_CONFIG_DIR|$WORK")" ;;
    disarm-role) printf '2026-01-01T00:00:00Z x\n' > "$CC_WR_STATE_DIR/disarm-$(key "$CLAUDE_CONFIG_DIR|role:desk")" ;;
  esac
  return 0
}
# keep <label> — IDL rows minus their clock, and the state, shared and telemetry trees by name.
keep() {
  shf_idl "$CC_WR_IDL" > "$SHF_OUT_DIR/$1.idl"
  local d
  for d in "$CC_WR_STATE_DIR" "$CC_WR_SHARED_STATE_DIR" "$CC_TELEMETRY_DIR" "$CC_WR_FIRE_DIR"; do
    echo "== ${d##*/}"
    [ -d "$d" ] || { echo "(absent)"; continue; }
    ( cd "$d" && find . -type f | { grep -v '^\./keymemo/' || true; } | LC_ALL=C sort )
  done > "$SHF_OUT_DIR/$1.state"
}
# arm <old|new> <label> — one PostToolUse through that arm's hook; stdin is the payload.
arm() {
  local root="$REPO" rc=0
  [ "$1" = old ] && root="$OLD"
  shf_run "$2" "$root/hooks/waiting-recycle.sh" || rc=$?
  echo "$rc" >> "$SHF_OUT_DIR/$2.out"
  keep "$2"
}
payload() { jq -cn --arg s "$SID" --arg c "${1:-$WORK}" '{session_id:$s,transcript_path:"",cwd:$c,
  hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"echo hi"},tool_response:{stdout:"hi"}}'; }
# twice <label> <payload> [blank args…] — two calls per arm from one blank state: 1 = miss, 2 = hit.
twice() {
  local l="$1" p="$2" a
  shift 2
  for a in old new; do
    blank "$@"
    printf '%s' "$p" | arm "$a" "${a:0:1}1$l"
    printf '%s' "$p" | arm "$a" "${a:0:1}2$l"
  done
  shf_same "o1$l" "n1$l" || { echo "first call (memo miss) differs: $p"; return 1; }
  shf_same "o2$l" "n2$l" || { echo "second call (memo hit) differs: $p"; return 1; }
}

@test "a builder, a desk, and cwd- and role-keyed disarms decide as before, on a memo miss and a hit" {
  have_old
  twice a "$(payload)"
  grep -q '"reason":"not-armed' "$SHF_OUT_DIR/o1a.idl" || { echo "builder control"; cat "$SHF_OUT_DIR/o1a.idl"; false; }
  twice b "$(payload)" desk
  if grep -q '"reason":"not-armed' "$SHF_OUT_DIR/o1b.idl"; then echo "desk control"; cat "$SHF_OUT_DIR/o1b.idl"; false; fi
  twice c "$(payload)" desk disarm-cwd
  grep -q '"disarmed"' "$SHF_OUT_DIR/o1c.idl" || { echo "cwd-keyed disarm not found"; cat "$SHF_OUT_DIR/o1c.idl"; false; }
  grep -q '"disarmed"' "$SHF_OUT_DIR/n2c.idl"
  twice d "$(payload)" desk disarm-role
  grep -q '"disarmed"' "$SHF_OUT_DIR/o1d.idl" || { echo "role-keyed disarm not found"; cat "$SHF_OUT_DIR/o1d.idl"; false; }
  grep -q '"disarmed"' "$SHF_OUT_DIR/n2d.idl"
}

@test "odd payloads are parsed exactly as before (the one-jq fast path declines them)" {
  have_old
  local i=0 p
  for p in '' 'not json' '[]' '{}' 'null' \
           "$(jq -cn --arg c "$WORK" '{session_id:"a",cwd:$c}{session_id:"b",cwd:$c}')" \
           "$(jq -cn --arg c "$WORK" '{session_id:7,cwd:$c}')" \
           "$(jq -cn '{session_id:"s",cwd:{"x":1}}')" \
           "$(jq -cn --arg c "$WORK" '{session_id:"s",cwd:($c + "\n\n")}')" \
           "$(jq -cn --arg c "$WORK" '{session_id:"s",cwd:("\n" + $c)}')" \
           "$(jq -cn --arg c "$WORK" '{session_id:"s\u001fx",cwd:$c}')" \
           "$(jq -cn --arg c "$WORK" '{session_id:"s",cwd:$c,transcript_path:false}')" \
           "$(jq -cn --arg c "$WORK" '{session_id:"",cwd:$c}')" \
           "$(jq -cn '{session_id:"s",cwd:"/nonexistent/a b/c"}')"; do
    i=$((i + 1))
    twice "x$i" "$p" desk || false
  done
}

@test "the memo holds the independently computed key, and a stale or foreign memo is a miss" {
  have_old
  blank desk
  payload | arm new n1
  local k f
  k="$(key "$CLAUDE_CONFIG_DIR|$WORK")"
  f="$(grep -l "|$WORK" "$CC_WR_STATE_DIR"/keymemo/* | head -1)"
  [ -n "$f" ]
  [ "$(head -1 "$f")" = "$k" ]
  [ "$(tail -1 "$f")" = "$k" ]
  [ -n "$(grep -l '|role:desk' "$CC_WR_STATE_DIR"/keymemo/*)" ]
  # A memo whose stored string is another cwd's (a name collision) must not be believed.
  printf '%s\n%s\n%s' 0123456789abcdef "$CLAUDE_CONFIG_DIR|/elsewhere" 0123456789abcdef > "$f"
  printf '2026-01-01T00:00:00Z x\n' > "$CC_WR_STATE_DIR/disarm-$k"
  payload | arm new n2
  grep -q '"disarmed"' "$SHF_OUT_DIR/n2.idl"
  [ "$(head -1 "$f")" = "$k" ]
  # A torn memo (the trailing key cut short) is a miss too.
  printf '%s\n%s\n%s' "$k" "$CLAUDE_CONFIG_DIR|$WORK" 0123 > "$f"
  payload | arm new n3
  grep -q '"disarmed"' "$SHF_OUT_DIR/n3.idl"
  [ "$(tail -1 "$f")" = "$k" ]
  # No state dir, no memo: an abstain path does not create one.
  rm -rf "$CC_WR_STATE_DIR"
  payload | arm new n4
  [ ! -d "$CC_WR_STATE_DIR/keymemo" ]
}

@test "a poll starts no cat, one jq for its fields, and on a memo hit no shasum or cut" {
  have_old
  twice e "$(payload)" desk
  echo "# desk poll, before: $(shf_census o2e)" >&3
  echo "# desk poll, memo miss: $(shf_census n1e)" >&3
  echo "# desk poll, memo hit: $(shf_census n2e)" >&3
  [ "$(shf_calls o2e cat)" -ge 1 ]
  [ "$(shf_calls n2e cat)" -eq $(( $(shf_calls o2e cat) - 1 )) ]
  [ "$(shf_calls n2e jq)" -eq $(( $(shf_calls o2e jq) - 2 )) ]
  [ "$(shf_calls n2e shasum)" -eq $(( $(shf_calls o2e shasum) - 2 )) ]
  [ "$(shf_calls n2e cut)" -le $(( $(shf_calls o2e cut) - 2 )) ]
  [ "$(shf_total n1e)" -lt "$(shf_total o1e)" ]
  twice f "$(payload)"
  echo "# builder poll: $(shf_census o2f)-> $(shf_census n2f)" >&3
  [ "$(shf_calls n2f shasum)" -eq $(( $(shf_calls o2f shasum) - 1 )) ]
  [ "$(shf_total n2f)" -le $(( $(shf_total o2f) - 5 )) ]
}

@test "a 240 KB payload is handled as before and no slower (median of 5 interleaved runs, within 10%)" {
  have_old
  local s p k t0 t1 os=() ns=() om nm
  s="$(head -c 240000 /dev/zero | tr '\0' 'w')"
  p="$(jq -cn --arg s "$SID" --arg c "$WORK" --arg o "$s" '{session_id:$s,transcript_path:"",cwd:$c,
    hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"cat big"},tool_response:{stdout:$o}}')"
  twice g "$p" desk
  [ -n "${EPOCHREALTIME:-}" ] || skip "this bats runs under a bash without EPOCHREALTIME"
  blank desk
  # On a pipe, as the harness sends it; printf is a builtin, so the feeder costs both arms the same.
  for k in 1 2 3 4 5; do
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$OLD/hooks/waiting-recycle.sh" >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    os+=($((t1 - t0)))
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | /bin/bash "$REPO/hooks/waiting-recycle.sh" >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    ns+=($((t1 - t0)))
  done
  om="$(printf '%s\n' "${os[@]}" | sort -n | sed -n 3p)"
  nm="$(printf '%s\n' "${ns[@]}" | sort -n | sed -n 3p)"
  echo "# 240 KB poll, median µs: before $om, after $nm" >&3
  [ $((nm * 10)) -le $((om * 11)) ] || { echo "slower: $om -> $nm µs (${os[*]} / ${ns[*]})"; false; }
}
