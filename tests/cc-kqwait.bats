#!/usr/bin/env bats
# cc-kqwait — the kqueue wait helper bin/cc-await-ping uses in place of `sleep "$INTERVAL"`.
#
# Each event kind is driven by a REAL change made by the test (an append, a rename, a child sleep
# exiting), and every "returned at once" case is paired with an elapsed-time bound, because a
# helper that only ever times out would print a plausible line too. The cache lives under the bats
# tmpdirs, so no run touches the operator's ~/.cache/cc-kqwait.

bats_require_minimum_version 1.5.0

setup_file() {
  export CC_KQWAIT_CACHE="$BATS_FILE_TMPDIR/cache"
  # /bin/bash: the interpreter the warm-path cases trace; its current-$HOSTTYPE link is the one they read
  /bin/bash "$BATS_TEST_DIRNAME/../bin/cc-kqwait" --timeout 0 >/dev/null
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  T="$BATS_TEST_DIRNAME/../bin/cc-kqwait"
  D="$BATS_TEST_TMPDIR"
  F="$D/f"; echo a >"$F"
  CUR="$CC_KQWAIT_CACHE/current-$(/bin/bash -c 'echo "$HOSTTYPE"')"
}

now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }

@test "timeout: fires within tolerance of a fractional --timeout" {
  t0=$(now_ms); run "$T" --timeout 0.5; t1=$(now_ms)
  [ "$status" -eq 0 ]; [ "$output" = timeout ]
  [ $((t1 - t0)) -ge 450 ]; [ $((t1 - t0)) -lt 1500 ]
}

@test "usage: a missing --timeout is rc 2" {
  run -2 "$T" --file "$F"
}

@test "file: a >> append fires vnode extend, then a baseline line" {
  ( sleep 0.3; echo b >>"$F" ) &
  run "$T" --file "$F" --timeout 10
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "vnode $F "*extend* ]]
  [[ "${lines[1]}" =~ ^baseline\ "$F"\ @4:[0-9]+$ ]]
}

@test "file: wake latency for an append is under 1 s" {
  "$T" --file "$F" --timeout 10 >"$D/out" & w=$!
  sleep 0.3
  t0=$(now_ms); echo b >>"$F"; wait "$w"; t1=$(now_ms)
  grep -q "^vnode $F .*extend" "$D/out"
  [ $((t1 - t0)) -lt 1000 ]
}

@test "file: mv -f replacement fires delete or rename" {
  ( sleep 0.3; echo new >"$D/new"; mv -f "$D/new" "$F" ) &
  run "$T" --file "$F" --timeout 10
  [[ "${lines[0]}" =~ ^vnode\ "$F"\ .*(delete|rename) ]]
}

@test "file: a stale baseline returns changed at once, and a fresh one waits" {
  base=$("$T" --file "$F" --timeout 0 | awk '$1=="baseline"{print $3}')
  run "$T" --file "$F$base" --timeout 0.3
  [ "${lines[0]}" = timeout ]
  echo c >>"$F"
  t0=$(now_ms); run "$T" --file "$F$base" --timeout 30; t1=$(now_ms)
  [ "${lines[0]}" = "vnode $F changed" ]
  [ $((t1 - t0)) -lt 1000 ]
}

@test "appear: an unrelated entry does not wake it; PATH's creation does" {
  ( sleep 0.3; touch "$D/other"; sleep 0.7; touch "$D/target" ) &
  t0=$(now_ms); run "$T" --appear "$D/target" --timeout 10; t1=$(now_ms)
  [ "$output" = "appear $D/target" ]
  [ $((t1 - t0)) -ge 900 ]
  t0=$(now_ms); run "$T" --appear "$D/target" --timeout 10; t1=$(now_ms)
  [ "$output" = "appear $D/target" ]; [ $((t1 - t0)) -lt 1000 ]
}

@test "dir: an entry added fires vnode <dir> write" {
  mkdir "$D/box"
  ( sleep 0.3; touch "$D/box/x" ) &
  run "$T" --dir "$D/box" --timeout 10
  [ "$output" = "vnode $D/box write" ]
}

@test "pid: a child sleep exiting fires exit <pid>" {
  sleep 0.5 & p=$!
  run "$T" --pid "$p" --timeout 10
  [ "$output" = "exit $p" ]
}

@test "pid: a dead pid prints gone at once" {
  sleep 0 & p=$!; wait "$p"
  t0=$(now_ms); run "$T" --pid "$p" --timeout 30; t1=$(now_ms)
  [ "$output" = "gone $p" ]; [ $((t1 - t0)) -lt 1000 ]
}

@test "pid: a START_EPOCH mismatch prints gone; the true start epoch waits for exit" {
  sleep 1 & p=$!
  start=$(LC_ALL=C date -j -f '%a %b %d %T %Y' "$(LC_ALL=C ps -o lstart= -p "$p")" +%s)
  run "$T" --pid "$p@1" --timeout 30
  [ "$output" = "gone $p" ]
  run "$T" --pid "$p@$start" --timeout 10
  [ "$output" = "exit $p" ]
}

@test "build failure: CC=false prints unavailable, rc 4, promptly" {
  t0=$(now_ms)
  CC=false CC_KQWAIT_CACHE="$D/c" run -4 "$T" --timeout 30
  t1=$(now_ms)
  [ "$output" = "unavailable build-failed" ]; [ $((t1 - t0)) -lt 5000 ]
}

@test "build failure: an unwritable cache prints unavailable, rc 4" {
  mkdir "$D/ro"; chmod 555 "$D/ro"
  CC_KQWAIT_CACHE="$D/ro/c" run -4 "$T" --timeout 30
  chmod 755 "$D/ro"
  [ "$output" = "unavailable build-failed" ]
}

@test "warm path: no command substitution and no keying tool, one exec of the cached binary" {
  run /bin/bash -x "$T" --timeout 0
  [ "${lines[${#lines[@]}-1]}" = timeout ]
  grep -qE "^\+ exec $CUR --timeout 0$" <<<"$output"
  run ! grep -qE '^\+\+|shasum|uname' <<<"$output"
}

@test "changed source: a stale cached binary is never run; it rebuilds under a new key" {
  sed 's|^#define MAXW 64$|#define MAXW 64 /* changed */|' "$T" >"$D/cc-kqwait"
  run ! cmp -s "$T" "$D/cc-kqwait"
  old=$(readlink "$CUR")
  CC_KQWAIT_CACHE="$CC_KQWAIT_CACHE" run /bin/bash "$D/cc-kqwait" --timeout 0
  [ "$output" = timeout ]
  new=$(readlink "$CUR")
  [ "$new" != "$old" ]; [ -x "$new" ]
  # and the original wrapper, warm on the new link, detects the mismatch and returns to its own build
  run /bin/bash "$T" --timeout 0
  [ "$output" = timeout ]
  [ "$(readlink "$CUR")" = "$old" ]
}
