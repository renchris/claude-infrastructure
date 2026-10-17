#!/usr/bin/env bats
# cc-await-ping-forks.bats — what one poll of bin/cc-await-ping costs the machine, and proof that
# cutting it changed nothing the watcher prints, returns or leaves in the mailbox.
#
# The defect this pins (W4 R3, 2026-10-17): an idle default-mode poll cost ~31 processes. The keyset
# was read twice per poll, each read a subshell chain ending in `tail -n1 | awk` over the alias file;
# each key's cursor came back through `$(_woke_get)` and a here-doc temp file; each line count went
# through three nested subshells; and both `mkdir -p` calls ran every poll.
#
# Parity is against the REAL pre-change watcher rebuilt from git (shf_old_tree). Both arms run over
# the same paths from the same blank state. Exec counts come from PATH stubs; FORKS that never exec
# (a `$( )` running a function) are invisible to a stub, so they are counted from an xtrace whose PS4
# prints $BASH_SUBSHELL: a trace line at depth >= 1 is a command run inside a forked subshell.
# Per-poll figures are the difference between a 3-poll and a 1-poll run (startup cancels out); the
# poll count is exact because `elapsed` advances by --interval per pass.

load stop-hook-forks-helpers
SHF_BASE=55d01fcd4fca631650df1dbae16e91cfa30821c5   # W4_BASE — set AFTER the load, which sets its own

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
}

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  NEW="$REPO/bin/cc-await-ping"
  OLD="$BATS_TEST_TMPDIR/old"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/alarm"
  export CC_AWAIT_IT2_BIN=               # no pane transport (never the operator's live iTerm2)
  export CC_AWAIT_PING_SIGRECORD=0       # no python side-car: its execs are not the poll's
  unset KITTY_PID KITTY_LISTEN_ON KITTY_WINDOW_ID CC_PANE_ID ITERM_SESSION_ID
  PANE="AAAAAAAA-1111-2222-3333-444444444444"
  SESS="bbbbbbbb-9999-8888-7777-666666666666"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" bin/cc-await-ping \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# blank [trail-lines] — empty mailbox + registry, the pane aliased to the session (a 2-key keyset).
blank() {
  local _
  rm -rf "$CC_MAILBOX_DIR" "$CC_REGISTRY_DIR"
  mkdir -p "$CC_MAILBOX_DIR/.alias" "$CC_REGISTRY_DIR" "$CC_BEAT_DIR"
  for _ in $(seq 1 "${1:-1}"); do
    printf '2026-10-11T00:00:00+0000 %s\n' "$SESS" >> "$CC_MAILBOX_DIR/.alias/$PANE"
  done
}

# arm <label> <watcher> [args…] — one run, then rc, wall-clock-free stderr and the mailbox's state
# (every file's name and bytes) filed beside its stdout for shf_same.
arm() {
  local label="$1" w="$2" rc=0 f
  shift 2
  shf_run "$label" "$w" "$@" < /dev/null || rc=$?
  printf '%s\n' "$rc" > "$SHF_OUT_DIR/$label.rc"
  sed -E 's/elapsed=[0-9]+s/elapsed=Ns/g' "$SHF_OUT_DIR/$label.err" > "$SHF_OUT_DIR/$label.errn"
  : > "$SHF_OUT_DIR/$label.idl"
  ( cd "$CC_MAILBOX_DIR" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '== %s\n' "$f"; cat "$f"; done ) > "$SHF_OUT_DIR/$label.state"
}
same() {   # <old label> <new label>
  local k
  for k in rc out errn state; do
    cmp "$SHF_OUT_DIR/$1.$k" "$SHF_OUT_DIR/$2.$k" \
      || { echo "--- $1.$k"; cat "$SHF_OUT_DIR/$1.$k"; echo "--- $2.$k"; cat "$SHF_OUT_DIR/$2.$k"; return 1; }
  done
}
# per_poll <label-1poll> <label-3poll> [name] → execs (of <name>, or all) per poll
per_poll() {
  local a b
  if [ -n "${3:-}" ]; then a="$(shf_calls "$1" "$3")"; b="$(shf_calls "$2" "$3")"
  else a="$(shf_total "$1")"; b="$(shf_total "$2")"; fi
  echo $(( (b - a) / 2 ))
}
# subshell_lines <watcher> <timeout> → xtrace lines run at subshell depth >= 1 over one run
subshell_lines() {
  local x="$BATS_TEST_TMPDIR/xtrace"
  PS4='+${BASH_SUBSHELL} ' PATH="$STUB" SHF_FORK_LOG=/dev/null \
    /bin/bash -x "$1" "$PANE" --interval 1 --timeout "$2" < /dev/null > /dev/null 2> "$x" || true
  grep -c '^++*[1-9]' "$x" || true
}

@test "parity: a ping on mail already pending — same stdout, stderr, rc and mailbox state" {
  have_old
  local a
  for a in old new; do
    blank
    printf '2026-10-11T10:00:00+0000 [peer] already pending\n' > "$CC_MAILBOX_DIR/$PANE.md"
    if [ "$a" = old ]; then arm "$a" "$OLD/bin/cc-await-ping" "$PANE" --interval 1 --timeout 3
    else arm "$a" "$NEW" "$PANE" --interval 1 --timeout 3; fi
  done
  [ "$(cat "$SHF_OUT_DIR/new.rc")" = 0 ]
  grep -qF 'already pending' "$SHF_OUT_DIR/new.out"
  same old new
}

@test "parity: a timeout — same stdout, stderr, rc and mailbox state" {
  have_old
  local a
  for a in old new; do
    blank
    if [ "$a" = old ]; then arm "$a" "$OLD/bin/cc-await-ping" "$PANE" --interval 1 --timeout 2
    else arm "$a" "$NEW" "$PANE" --interval 1 --timeout 2; fi
  done
  [ "$(cat "$SHF_OUT_DIR/new.rc")" = 2 ]
  same old new
}

@test "parity: an orphan exit (dead registry pid, pane absent) — same output, rc 5, mail unconsumed" {
  have_old
  local a d it2="$BATS_TEST_TMPDIR/it2-stub"
  printf '#!/bin/bash\nprintf %%s %s\n' "'[{\"id\":\"SOMEONE-ELSE\"}]'" > "$it2"; chmod +x "$it2"
  sleep 0.1 & d=$!; wait "$d" 2>/dev/null || true
  for a in old new; do
    blank
    printf '{"paneUUID":"%s","name":"peer","pid":%s,"startedAt":1}' "$PANE" "$d" > "$CC_REGISTRY_DIR/$PANE.json"
    printf '2026-10-11T10:00:00+0000 [peer] must stay unconsumed\n' > "$CC_MAILBOX_DIR/$PANE.md"
    if [ "$a" = old ]; then CC_AWAIT_IT2_BIN="$it2" arm "$a" "$OLD/bin/cc-await-ping" "$PANE" --interval 1 --timeout 6
    else CC_AWAIT_IT2_BIN="$it2" arm "$a" "$NEW" "$PANE" --interval 1 --timeout 6; fi
  done
  [ "$(cat "$SHF_OUT_DIR/new.rc")" = 5 ]
  same old new
}

@test "one idle poll: fewer execs than W4_BASE, and no tail/awk/mkdir at all on a short alias trail" {
  have_old
  local a t
  for a in old new; do
    for t in 1 3; do
      blank
      if [ "$a" = old ]; then arm "$a$t" "$OLD/bin/cc-await-ping" "$PANE" --interval 1 --timeout "$t"
      else arm "$a$t" "$NEW" "$PANE" --interval 1 --timeout "$t"; fi
    done
  done
  echo "per poll: old $(per_poll old1 old3) new $(per_poll new1 new3) | old: $(shf_census old3) | new: $(shf_census new3)"
  [ "$(per_poll new1 new3)" -lt "$(per_poll old1 old3)" ]
  [ "$(per_poll new1 new3 tail)" -eq 0 ]    # forward alias read by builtin `read`, not tail|awk
  [ "$(per_poll new1 new3 awk)" -eq 0 ]
  [ "$(per_poll new1 new3 mkdir)" -eq 0 ]   # both dirs exist, so neither mkdir runs
  same old3 new3
}

@test "one idle poll on a LONG alias trail reads the keyset exactly once (one tail, one awk)" {
  have_old
  local a t
  for a in old new; do
    for t in 1 3; do
      blank 70
      if [ "$a" = old ]; then arm "$a$t" "$OLD/bin/cc-await-ping" "$PANE" --interval 1 --timeout "$t"
      else arm "$a$t" "$NEW" "$PANE" --interval 1 --timeout "$t"; fi
    done
  done
  echo "per poll: old $(per_poll old1 old3) new $(per_poll new1 new3)"
  [ "$(per_poll old1 old3 tail)" -eq 2 ]    # control: the old poll read it twice
  [ "$(per_poll new1 new3 tail)" -eq 1 ]
  [ "$(per_poll new1 new3 awk)" -eq 1 ]
  same old3 new3
}

@test "one idle poll forks almost nothing: subshell work per poll is a fraction of W4_BASE's" {
  have_old
  local o1 o3 n1 n3
  blank; o1="$(subshell_lines "$OLD/bin/cc-await-ping" 1)"
  blank; o3="$(subshell_lines "$OLD/bin/cc-await-ping" 3)"
  blank; n1="$(subshell_lines "$NEW" 1)"
  blank; n3="$(subshell_lines "$NEW" 3)"
  echo "subshell trace lines per poll: old $(( (o3 - o1) / 2 )) new $(( (n3 - n1) / 2 ))"
  [ "$(( (o3 - o1) / 2 ))" -gt 20 ]          # control: the instrument sees the old chains
  [ "$(( (n3 - n1) / 2 ))" -le 3 ]           # $(_woke_get), $(mailbox_lines), $(_keys) are gone
}
