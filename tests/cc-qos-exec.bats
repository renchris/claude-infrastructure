#!/usr/bin/env bats
# shellcheck disable=SC2016  # stub bodies carry literal $ on purpose
# cc-qos-exec — the batch-QoS PATH shim. Pinned: inside a Claude session a linked name runs its real
# tool under `taskpolicy -c <band>` with argv intact and the tool's exit code; the band comes from
# config/qos-batch.patterns matched on the NAME only; every doubt (outside a session, kill switch, no
# row, a bad band, no taskpolicy) runs the real tool verbatim; no real tool is 127; a link to another
# checkout's shim is skipped rather than looped through; every name install.sh links has a row, so
# no shim is inert; and a real clamp lands the tool at PRI 20.
#
# Hermetic: scratch shim and tool dirs, a recording taskpolicy stub, PATH pinned to them plus
# /usr/bin:/bin. Only the last case runs the real /usr/sbin/taskpolicy, on a fake tool that reads
# its own PRI.

setup() {
  bats_require_minimum_version 1.5.0
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIM="$REPO/bin/cc-qos-exec"
  S="$BATS_TEST_TMPDIR/shims"; R="$BATS_TEST_TMPDIR/real"; mkdir -p "$S" "$R"
  ln -s "$SHIM" "$S/ffmpeg"
  printf '#!/bin/bash\necho "REAL $0 $#:$*"\nexit "${FAKE_RC:-0}"\n' > "$R/ffmpeg"; chmod +x "$R/ffmpeg"
  TP="$BATS_TEST_TMPDIR/taskpolicy"
  printf '#!/bin/bash\necho "TP $1 $2" >> "%s/tp.log"\nshift 2\nexec "$@"\n' "$BATS_TEST_TMPDIR" > "$TP"; chmod +x "$TP"
  export PATH="$S:$R:/usr/bin:/bin" CLAUDECODE=1 CC_QOS_EXEC_TASKPOLICY="$TP"
  unset CC_QOS_EXEC CC_QOS_EXEC_ALWAYS CC_QOS_EXEC_PATTERNS
}

tp_log() { cat "$BATS_TEST_TMPDIR/tp.log" 2>/dev/null; }

@test "inside a session: the real tool runs under taskpolicy -c utility, argv and exit code intact" {
  FAKE_RC=7 run ffmpeg -i "a b.mov" out.mp4
  [ "$status" -eq 7 ]
  [ "$output" = "REAL $R/ffmpeg 3:-i a b.mov out.mp4" ]
  [ "$(tp_log)" = "TP -c utility" ]
}

@test "outside a session the real tool runs verbatim; CC_QOS_EXEC_ALWAYS=1 demotes anyway" {
  unset CLAUDECODE
  run ffmpeg -y
  [ "$status" -eq 0 ]; [ "$output" = "REAL $R/ffmpeg 1:-y" ]; [ -z "$(tp_log)" ]
  CC_QOS_EXEC_ALWAYS=1 run ffmpeg -y
  [ "$(tp_log)" = "TP -c utility" ]
}

@test "every doubt runs verbatim: kill switch, no row for the name, a band outside the allowlist, no taskpolicy" {
  CC_QOS_EXEC=off run ffmpeg -y
  [ "$output" = "REAL $R/ffmpeg 1:-y" ]
  printf 'utility\t(^|[[:space:]])magick([[:space:]]|$)\n' > "$BATS_TEST_TMPDIR/t1"
  CC_QOS_EXEC_PATTERNS="$BATS_TEST_TMPDIR/t1" run ffmpeg -y
  [ "$output" = "REAL $R/ffmpeg 1:-y" ]
  printf 'turbo\t(^|[[:space:]])ffmpeg([[:space:]]|$)\n' > "$BATS_TEST_TMPDIR/t2"
  CC_QOS_EXEC_PATTERNS="$BATS_TEST_TMPDIR/t2" run ffmpeg -y
  [ "$output" = "REAL $R/ffmpeg 1:-y" ]
  CC_QOS_EXEC_TASKPOLICY="" run ffmpeg -y
  [ "$output" = "REAL $R/ffmpeg 1:-y" ]
  [ -z "$(tp_log)" ]
}

@test "the band is chosen by the NAME alone: an argument that matches another row changes nothing" {
  printf 'background\t(^|[[:space:]])pytest([[:space:]]|$)\n' > "$BATS_TEST_TMPDIR/t3"
  CC_QOS_EXEC_PATTERNS="$BATS_TEST_TMPDIR/t3" run ffmpeg pytest
  [ "$output" = "REAL $R/ffmpeg 1:pytest" ]
  [ -z "$(tp_log)" ]
}

@test "no real tool beyond the shim is exit 127 with a message, never a loop" {
  rm "$R/ffmpeg"
  run -127 ffmpeg -y
  [[ "$output" == *"ffmpeg: not found on PATH beyond the QoS shim"* ]] || false
}

@test "a link to ANOTHER checkout's shim is skipped, so two shims cannot exec each other" {
  O="$BATS_TEST_TMPDIR/other"; mkdir -p "$O/bin" "$O/links"
  cp "$SHIM" "$O/bin/cc-qos-exec"; ln -s "$O/bin/cc-qos-exec" "$O/links/ffmpeg"
  PATH="$S:$O/links:$R:/usr/bin:/bin" run ffmpeg -y
  [ "$status" -eq 0 ]
  [ "$output" = "REAL $R/ffmpeg 1:-y" ]
}

@test "the explicit form: cc-qos-exec <tool> args" {
  run "$SHIM" ffmpeg -y
  [ "$output" = "REAL $R/ffmpeg 1:-y" ]
  [ "$(tp_log)" = "TP -c utility" ]
  run "$SHIM"
  [ "$status" -eq 2 ]
}

@test "every name install.sh links has a utility row in the real table, so no shim is inert" {
  n=0
  while IFS= read -r name; do
    case "$name" in ''|'#'*) continue ;; esac
    [ -e "$S/$name" ] || ln -s "$SHIM" "$S/$name"
    printf '#!/bin/bash\necho "REAL $0"\n' > "$R/$name"; chmod +x "$R/$name"
    : > "$BATS_TEST_TMPDIR/tp.log"
    run "$name"
    [ "$output" = "REAL $R/$name" ] || { echo "$name: $output"; false; }
    [ "$(tp_log)" = "TP -c utility" ] || { echo "$name: not demoted"; false; }
    n=$((n + 1))
  done < "$REPO/config/qos-shim.names"
  [ "$n" -ge 7 ]
}

@test "a real clamp: the tool reads its own PRI as 4 under a background row, and its runner's PRI with the kill switch" {
  # The background band, not utility, because this suite itself runs under cc-bats's utility clamp
  # (PRI 20), so a utility case could not tell the shim's clamp from the one it inherited.
  [ -x /usr/sbin/taskpolicy ] || skip "no taskpolicy(8)"
  base="$(ps -o pri= -p $$ | tr -d ' ')"
  [ "$base" -gt 4 ] || skip "this runner is already in the background band (PRI $base)"
  unset CC_QOS_EXEC_TASKPOLICY
  printf '#!/bin/bash\nps -o pri= -p $$ | tr -d " "\n' > "$R/ffmpeg"
  printf 'background\t(^|[[:space:]])ffmpeg([[:space:]]|$)\n' > "$BATS_TEST_TMPDIR/bg"
  export CC_QOS_EXEC_PATTERNS="$BATS_TEST_TMPDIR/bg"
  run ffmpeg
  [ "$output" = 4 ]
  CC_QOS_EXEC=off run ffmpeg
  [ "$output" -gt 4 ]
}
