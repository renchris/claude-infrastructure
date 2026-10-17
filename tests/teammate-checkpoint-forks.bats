#!/usr/bin/env bats
# teammate-checkpoint-forks.bats — hooks/teammate-checkpoint.sh no longer starts `mkdir` and
# `dirname` on every tool call, and checkpoints, counts and logs exactly as before.
#
# The hook is on the match-all PostToolUse matcher, and its `mkdir -p <watchdog> $(dirname <log>)`
# ran ahead of the bulk-agent skip: two process starts on every tool call of every subagent, for
# two directories that nearly always exist. They are now tested first, and the dirname is a
# parameter expansion. Parity is against the REAL pre-change hook, rebuilt from git
# (stop-hook-forks-helpers.bash); counts come from PATH stubs that log every external command.
# Log-line timestamps and checkpoint commit ids (which carry a clock) are the only things allowed
# to differ.
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
  unset TEAMMATE_CHECKPOINT_DISABLED TEAMMATE_CHECKPOINT_EVERY CC_HOOK_PROFILE
  WT="$BATS_TEST_TMPDIR/wt-team-alice"
  NG="$BATS_TEST_TMPDIR/not-a-repo"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/teammate-checkpoint.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# blank [nodirs] — a fresh HOME (with its watchdog and log dirs unless `nodirs`) and a fresh repo
# at the same path, with one uncommitted edit: each arm starts from identical state.
blank() {
  rm -rf "$HOME" "$WT" "$NG"; mkdir -p "$HOME" "$NG"
  [ "${1:-}" = nodirs ] || mkdir -p "$HOME/.claude/watchdog" "$HOME/.claude/logs"
  mkdir -p "$WT"
  ( cd "$WT" && git init -q && printf 'seed\n' > seed.txt && git add -A \
      && git -c user.email=t@t -c user.name=t commit -qm seed && printf 'work\n' > new.txt ) >/dev/null 2>&1
}
# keep <label> — watchdog files with their contents, the log minus its clock (line timestamps, the
# checkpoint commit id and its timestamped ref name), checkpoint ref names.
keep() {
  local f
  {
    if [ -d "$HOME/.claude" ]; then ( cd "$HOME/.claude" && find . | LC_ALL=C sort ); fi
    for f in "$HOME"/.claude/watchdog/*; do
      if [ -f "$f" ]; then echo "== ${f##*/}"; cat "$f"; fi
    done
    echo "== log"
    if [ -f "$HOME/.claude/logs/teammate-checkpoint.log" ]; then
      sed -E -e 's/^\[[0-9-]{10} [0-9:]{8}\] //' -e 's/sha=[0-9a-f]{40}/sha=<sha>/g' \
        -e 's#(refs/checkpoints/[^ ]*/)[0-9]{8}T[0-9]{6}Z#\1<ts>#g' "$HOME/.claude/logs/teammate-checkpoint.log"
    fi
    echo "== refs"
    git -C "$WT" for-each-ref --format='%(refname)' refs/wip 2>/dev/null || true
  } > "$SHF_OUT_DIR/$1.state"
}
# arm <old|new> <label> — one call through that arm's hook, run from $WT; stdin is the payload.
arm() {
  local root="$REPO" rc=0
  [ "$1" = old ] && root="$OLD"
  ( cd "$WT" && shf_run "$2" "$root/hooks/teammate-checkpoint.sh" ) || rc=$?
  echo "$rc" > "$SHF_OUT_DIR/$2.rc"
  keep "$2"
}
same() { # <old label> <new label> — stdout, stderr, exit code and state all equal
  local k
  for k in out err rc state; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" || { echo "--- $1.$k"; cat "$SHF_OUT_DIR/$1.$k"; echo "--- $2.$k"; cat "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}
ev() { jq -nc --arg e "$1" --arg c "${2:-$WT}" '{session_id:"sid-f",hook_event_name:$e,tool_name:"Bash",cwd:$c,tool_input:{command:"ls"}}'; }
sub() { printf '{"session_id":"sid-f","agent_id":"a1b2c3","hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"ls"}}' "$WT"; }
big() {
  local s
  s="$(head -c 240000 /dev/zero | tr '\0' 'q')"
  jq -cn --arg s "$s" --arg c "$WT" '{session_id:"sid-f",hook_event_name:"PostToolUse",tool_name:"Bash",
    cwd:$c,tool_input:{command:"cat big"},tool_response:{stdout:$s,stderr:"",interrupted:false}}'
}
# pair <label> <payload> [nodirs] — the same call through both arms, each from blank.
pair() {
  blank "${3:-}"; printf '%s' "$2" | arm old "o$1"
  blank "${3:-}"; printf '%s' "$2" | arm new "n$1"
  same "o$1" "n$1" || { echo "case $1 differs: $2"; return 1; }
}

@test "every corpus payload checkpoints, counts and logs as before" {
  have_old
  local i=0 p
  local -a corpus=(
    "$(ev Stop)"
    "$(ev TeammateIdle)"
    "$(ev PostToolUse)"
    "$(ev PostToolUse "$NG")"
    "$(ev Stop "$NG")"
    "$(sub)"
    'not json'
    ''
  )
  for p in "${corpus[@]}"; do
    i=$((i + 1))
    pair "$i" "$p" || false
  done
  grep -q '^refs/wip/' "$SHF_OUT_DIR/o1.state" || { echo "the control made no checkpoint"; cat "$SHF_OUT_DIR/o1.state"; false; }
  # Five PostToolUse calls cross the every-N snapshot cadence, in both arms alike.
  for i in 1 2; do
    blank; for p in 1 2 3 4 5; do ev PostToolUse | arm "$( [ "$i" = 1 ] && echo old || echo new )" "c$i"; done
  done
  same c1 c2
}

@test "missing watchdog and log directories are still created, as before" {
  have_old
  pair 1 "$(ev Stop)" nodirs
  pair 2 "$(sub)" nodirs
  grep -qx './watchdog' "$SHF_OUT_DIR/n2.state"
  grep -qx './logs' "$SHF_OUT_DIR/n2.state"
}

@test "a subagent's call starts nothing (it started mkdir and dirname), a lead's two fewer" {
  have_old
  pair 1 "$(sub)"
  echo "# subagent PostToolUse: $(shf_census o1)-> $(shf_total n1) calls" >&3
  [ "$(shf_calls o1 mkdir)" -eq 1 ]
  [ "$(shf_calls o1 dirname)" -eq 1 ]
  [ "$(shf_total n1)" -eq 0 ]
  pair 2 "$(ev PostToolUse)"
  echo "# lead PostToolUse: $(shf_census o2)-> $(shf_census n2)" >&3
  [ "$(shf_calls n2 mkdir)" -eq 0 ]
  [ "$(shf_calls n2 dirname)" -eq 0 ]
  [ "$(shf_total n2)" -eq $(( $(shf_total o2) - 2 )) ]
}

@test "a 240 KB payload is handled as before and no slower (median of 5 interleaved runs, within 10%)" {
  have_old
  local p k t0 t1 os=() ns=() om nm
  p="$(big)"
  pair 1 "$p"
  [ -n "${EPOCHREALTIME:-}" ] || skip "this bats runs under a bash without EPOCHREALTIME"
  blank
  # On a pipe, as the harness sends it; printf is a builtin, so the feeder costs both arms the same.
  for k in 1 2 3 4 5; do
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | ( cd "$NG" && /bin/bash "$OLD/hooks/teammate-checkpoint.sh" ) >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    os+=($((t1 - t0)))
    t0=${EPOCHREALTIME/./}; printf '%s' "$p" | ( cd "$NG" && /bin/bash "$REPO/hooks/teammate-checkpoint.sh" ) >/dev/null 2>&1; t1=${EPOCHREALTIME/./}
    ns+=($((t1 - t0)))
  done
  om="$(printf '%s\n' "${os[@]}" | sort -n | sed -n 3p)"
  nm="$(printf '%s\n' "${ns[@]}" | sort -n | sed -n 3p)"
  echo "# 240 KB PostToolUse, median µs: before $om, after $nm" >&3
  [ $((nm * 10)) -le $((om * 11)) ] || { echo "slower: $om -> $nm µs (${os[*]} / ${ns[*]})"; false; }
}
