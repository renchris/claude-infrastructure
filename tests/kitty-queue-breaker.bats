#!/usr/bin/env bats
# The kitty RC circuit breaker (lockup incident 2026-10-25, ~/incident-2026-10-25/solution/DESIGN.md C4):
# cc_kitty_rc_open and the widened kq_deaf in scripts/lib/kitty-queue.sh, the breaker in bin/it2-kitty
# and in handoff-fire's kt(), and the bounded `ps` in kq_main_kitty_pids.
#
# Every kitty, kitten, netstat and sample the subjects could reach is a PATH stub that records its argv,
# so "nothing connected" is asserted as zero recorded calls, never inferred from an exit code.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KQ="$REPO/scripts/lib/kitty-queue.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lockwatch"; mkdir -p "$CC_LOCKWATCH_DIR"
  export CC_HEARTBEAT_DIR="$BATS_TEST_TMPDIR/heartbeat"
  CALLS="$BATS_TEST_TMPDIR/calls"; : > "$CALLS"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  local b
  for b in kitty kitten netstat sample; do
    printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >> "%s"\nexit 0\n' "$b" "$CALLS" > "$STUBS/$b"
    chmod +x "$STUBS/$b"
  done
  export PATH="$STUBS:$PATH"
  unset CC_KITTY_RC_BREAKER CC_KQ_NOW CC_HF_NETSTAT_FILE
}

rc_state() { # $1=kitty_rc value $2=hb age in seconds (absent = no hb)
  printf '{"v":1, "level": 2, "kitty_rc": "%s"}\n' "$1" > "$CC_LOCKWATCH_DIR/state.json"
  if [ -n "${2:-}" ]; then
    : > "$CC_LOCKWATCH_DIR/hb"
    touch -t "$(date -r $(( $(date +%s) - $2 )) +%Y%m%d%H%M.%S)" "$CC_LOCKWATCH_DIR/hb"
  fi
}

@test "01 dead + fresh hb: it2-kitty exits 75 and no kitty or kitten is ever called" {
  rc_state dead 0
  run env CC_TERM_KITTY="$STUBS/kitty" CC_TERM_KITTY_TO=unix:/tmp/kitty-1 /bin/bash "$REPO/bin/it2-kitty" session list
  [ "$status" -eq 75 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"remote control is DEAD"* ]] || false
  [ ! -s "$CALLS" ] || { echo "a stub was called: $(cat "$CALLS")"; false; }
  run env CC_TERM_KITTY="$STUBS/kitty" CC_TERM_KITTY_TO=unix:/tmp/kitty-1 /bin/bash "$REPO/bin/it2-kitty" session split -v -s 3
  [ "$status" -eq 75 ] || false
  [ ! -s "$CALLS" ] || false
}

@test "02 a stale hb disarms the breaker; the kill switch and kitty_rc ok keep it closed" {
  rc_state dead 60
  run bash -c '. "$1"; cc_kitty_rc_open' _ "$KQ"
  [ "$status" -eq 1 ] || { echo "stale hb armed the breaker"; false; }
  run env CC_TERM_KITTY="$STUBS/kitty" CC_TERM_KITTY_TO=unix:/tmp/kitty-1 /bin/bash "$REPO/bin/it2-kitty" session list
  [ "$status" -ne 75 ] || { echo "it2-kitty refused on a stale hb: $output"; false; }
  [ -s "$CALLS" ] || { echo "a disarmed breaker must let it2-kitty reach kitty — the control proves nothing"; false; }
  rc_state dead 0
  run bash -c '. "$1"; cc_kitty_rc_open' _ "$KQ"
  [ "$status" -eq 0 ] || false
  CC_KITTY_RC_BREAKER=off run bash -c '. "$1"; cc_kitty_rc_open' _ "$KQ"
  [ "$status" -eq 1 ] || false
  rc_state ok 0
  run bash -c '. "$1"; cc_kitty_rc_open' _ "$KQ"
  [ "$status" -eq 1 ] || false
  rm -f "$CC_LOCKWATCH_DIR/hb"; rc_state dead
  run bash -c '. "$1"; cc_kitty_rc_open' _ "$KQ"
  [ "$status" -eq 1 ] || false            # no hb at all is no evidence
}

@test "03 kq_deaf returns DEAF on lockwatch's passive evidence without running netstat or sample" {
  rc_state dead 0
  run bash -c '. "$1"; kq_deaf unix:/tmp/kitty-610 610' _ "$KQ"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"kitty_rc=dead"* ]] || false
  [ ! -s "$CALLS" ] || { echo "passive verdict still probed: $(cat "$CALLS")"; false; }
}

@test "04 kq_deaf returns DEAF when the heartbeat ticks but its kitten @ ls tree goes 2+ ticks stale" {
  local now d
  now="$(date +%s)"; d="$CC_HEARTBEAT_DIR/BOOT-A/610"; mkdir -p "$d"
  printf '%s\n' "$now" > "$d/hb.start"
  printf '[]\n' > "$d/hb.kitty-ls.json"
  touch -t "$(date -r $(( now - 700 )) +%Y%m%d%H%M.%S)" "$d/hb.kitty-ls.json"
  export CC_HF_NETSTAT_FILE="$BATS_TEST_TMPDIR/netstat.txt"; : > "$CC_HF_NETSTAT_FILE"
  run bash -c '. "$1"; kq_deaf unix:/tmp/kitty-610 610' _ "$KQ"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"over 2 ticks"* ]] || false
  # control: a tree one tick old is not evidence, and the old queue path answers instead
  touch -t "$(date -r $(( now - 100 )) +%Y%m%d%H%M.%S)" "$d/hb.kitty-ls.json"
  run bash -c '. "$1"; kq_deaf unix:/tmp/kitty-610 610' _ "$KQ"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"queue=0 under 128"* ]] || false
  # a heartbeat that itself stopped says nothing about kitty
  printf '%s\n' "$(( now - 4000 ))" > "$d/hb.start"
  touch -t "$(date -r $(( now - 4700 )) +%Y%m%d%H%M.%S)" "$d/hb.kitty-ls.json"
  run bash -c '. "$1"; kq_deaf unix:/tmp/kitty-610 610' _ "$KQ"
  [ "$status" -eq 1 ] || false
}

@test "05 handoff-fire's kt() returns 75 without connecting while the breaker is open" {
  local kt_src
  kt_src="$(sed -n '/^kt() {$/,/^}$/p' "$REPO/scripts/handoff-fire.sh")"
  [ -n "$kt_src" ] || { echo "kt() moved — this case asserts over nothing"; false; }
  rc_state dead 0
  CALLS="$CALLS" run bash -c '. "$1"; hf_bounded() { printf "hf_bounded %s\n" "$*" >> "$CALLS"; }; eval "$2"; kt ls' _ "$KQ" "$kt_src"
  [ "$status" -eq 75 ] || { echo "rc=$status $output"; false; }
  [ ! -s "$CALLS" ] || { echo "kt connected: $(cat "$CALLS")"; false; }
  rc_state ok 0
  CALLS="$CALLS" run bash -c '. "$1"; hf_bounded() { printf "hf_bounded %s\n" "$*" >> "$CALLS"; }; eval "$2"; kt ls' _ "$KQ" "$kt_src"
  [ "$status" -eq 0 ] || false
  grep -q 'hf_bounded kitty @ ls' "$CALLS" || false
}

@test "06 kq_main_kitty_pids is bounded: a ps that never returns costs its bound, not the caller" {
  printf '#!/bin/bash\nsleep 60\n' > "$STUBS/slowps"; chmod +x "$STUBS/slowps"
  local t0 t1
  t0="$(date +%s)"
  run bash -c '. "$1"; CC_KQ_PS_BIN="$2" CC_KQ_PS_TIMEOUT_S=1 kq_main_kitty_pids' _ "$KQ" "$STUBS/slowps"
  t1="$(date +%s)"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
  [ $(( t1 - t0 )) -lt 20 ] || { echo "took $(( t1 - t0 ))s"; false; }
  # and a ps that answers still yields the main kitty, not its helpers
  printf '#!/bin/bash\nprintf "%%s\\n" " 610 /Applications/kitty.app/Contents/MacOS/kitty" " 611 /Applications/kitty.app/Contents/MacOS/kitty +kitten x" " 612 kitty --instance-group q"\n' > "$STUBS/fastps"
  chmod +x "$STUBS/fastps"
  run bash -c '. "$1"; CC_KQ_PS_BIN="$2" kq_main_kitty_pids' _ "$KQ" "$STUBS/fastps"
  [ "$output" = 610 ] || { echo "got: $output"; false; }
}
