#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# boot-resume.sh replayed over the RAW artifacts of the 2026-10-25 13:16:52 CDT reboot (kern.boottime
# 1792952212), unshifted and unminimized: kitty 1881's whole heartbeat dir as it stood at the cut
# (hb.roster.json `[]` at 13:09:42, hb.session.tsv 0 bytes, hb.kitty-ls.json from 03:45, hb.bg.tsv,
# census, roles) with its original mtimes (MTIMES.tsv), and the 28 shutdown tombstones written at
# 13:15:02-07. Fixture: tests/fixtures/boot-resume-2026-10-25/, copied from the evidence the reboot left.
# The live boot-resume run at 18:21:21Z logged source heartbeat, reason no-open-sessions, n_open 0
# (fixture idl-boot-resume.jsonl). boot-resume.bats pins the same burst on a shifted, minimized copy;
# this suite pins it on the bytes the machine actually had, so a change that keys on a heartbeat file
# the minimized copy lacks (session.tsv, bg.tsv, census, the tree's real mtime) cannot pass there and
# fail here unseen. Page mode for the count; resume mode, against the suite's stub launcher, for the rows.
# RED-proof: against 0de93a544's boot-resume.sh (before 1e2314fb3) case 1 logs no-open-sessions, n_open 0.

bats_require_minimum_version 1.5.0

load helpers/cc-stub
load helpers/boot-resume-env

FIX="$BATS_TEST_DIRNAME/fixtures/boot-resume-2026-10-25"
BOOT=1792952212

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # also in the helper; the hermeticity ratchet reads setup() itself
  export CC_FIRE_CAPACITY_GATE=off
  boot_resume_setup
  export CC_BOOTTIME_OVERRIDE=$BOOT CC_HB_NOW=$BOOT     # the incident's own clock: no epoch shift
  # every row INTERRUPTED, as in boot-resume-lockup.bats; the stub body's $ is the stub's own shell
  # shellcheck disable=SC2016
  cc_stub_self "$CC_RESUME_CLASSIFY_BIN" "$(printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$self.log"\nwhile IFS= read -r row; do [ -n "$row" ] && printf "%%s\\tINTERRUPTED\\n" "$row"; done\n')"
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lockwatch"; mkdir -p "$CC_LOCKWATCH_DIR"   # no boot class: the clean-boot path
  export CC_BOOT_RESUME_MODE=page
  HBD="$CC_HEARTBEAT_DIR/UUID-PREV/1881"; mkdir -p "$HBD"
  local f
  for f in "$FIX"/heartbeat/hb.*; do cp "$f" "$HBD/"; done
  gzip -dc "$FIX/heartbeat/hb.kitty-ls.json.gz" > "$HBD/hb.kitty-ls.json"; rm -f "$HBD/hb.kitty-ls.json.gz"
  cp "$FIX"/tombstones/*.json "$CC_SHUTDOWN_TOMB_DIR/"
  local m p
  while IFS=$'\t' read -r m p; do
    case "$m" in '#'*|'') continue ;; esac
    case "$p" in
      heartbeat/hb.kitty-ls.json.gz) f="$HBD/hb.kitty-ls.json" ;;
      heartbeat/*) f="$HBD/${p#heartbeat/}" ;;
      tombstones/*) f="$CC_SHUTDOWN_TOMB_DIR/${p#tombstones/}" ;;
      *) continue ;;
    esac
    touch -t "$(date -r "$m" +%Y%m%d%H%M.%S)" "$f"
  done < "$FIX/MTIMES.tsv"
}

@test "replay 2026-10-25: the raw empty heartbeat no longer answers — all 28 burst tombstones are sessions to restore" {
  [ "$(find "$CC_SHUTDOWN_TOMB_DIR" -name '*.json' | wc -l | tr -d ' ')" -eq 28 ]
  [ "$(cat "$HBD/hb.roster.json")" = "[]" ]
  [ ! -s "$HBD/hb.session.tsv" ]
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  line="$(grep '"tool":"boot-resume"' "$CC_IDL" | tail -1)"
  n_open="$(printf '%s' "$line" | jq -r '.n_open')"
  tomb="$(printf '%s' "$line" | jq -r '.tomb_joined // 0')"
  echo "# replay 2026-10-25: source=$(printf '%s' "$line" | jq -r '.source') tomb_joined=$tomb n_open=$n_open — sessions to restore: $n_open (live run: 0)" >&3
  ! grep -q 'no-open-sessions' "$CC_IDL" || false
  # the 28 come from the tombstones, either as the source (the 03:45 tree distrusts the heartbeat) or
  # joined to the empty heartbeat; nothing else on this fixture can add a row
  [ "$n_open" -eq 28 ]
}

@test "replay 2026-10-25: under resume, each of the 28 tombstoned sessions reaches the (stub) launcher once" {
  # the page names only 8 and counts the rest, so the per-session proof is the resume path: the identity
  # lr-select stub passes every candidate, and the launcher stub logs "<acct> <cwd> <sid> <branch>"
  export CC_BOOT_RESUME_MODE=resume
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  n=0
  for f in "$FIX"/tombstones/*.json; do
    sid="$(jq -r '.session_id' "$f")"
    [ "$(awk -v s="$sid" '$3 == s' "$CC_RESUME_LAUNCH_BIN.log" | wc -l | tr -d ' ')" -eq 1 ] && n=$((n + 1))
  done
  echo "# replay 2026-10-25: $n of 28 tombstoned sessions handed to the launcher ($(grep -c . "$CC_RESUME_LAUNCH_BIN.log") launch line(s))" >&3
  [ "$n" -eq 28 ]
  [ "$(grep -c . "$CC_RESUME_LAUNCH_BIN.log")" -eq 28 ]
}

@test "replay 2026-10-25: with the stale-tree distrust off, the tombstone join alone still finds all 28" {
  # Two guards on trunk each cover this cut: 5dc64d048 distrusts a heartbeat whose kitty tree is 9.5 h
  # older than it (case 1's source=tombstones), and 1e2314fb3 joins every burst tombstone newer than
  # the snapshot to it. Switching the first off proves the second holds on the raw bytes by itself.
  export CC_BOOT_RESUME_LOCKUP_DISTRUST=off
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  line="$(grep '"tool":"boot-resume"' "$CC_IDL" | tail -1)"
  echo "# replay 2026-10-25 (distrust off): source=$(printf '%s' "$line" | jq -r '.source') tomb_joined=$(printf '%s' "$line" | jq -r '.tomb_joined') n_open=$(printf '%s' "$line" | jq -r '.n_open')" >&3
  [ "$(printf '%s' "$line" | jq -r '.source')" = heartbeat ]
  [ "$(printf '%s' "$line" | jq -r '.tomb_joined')" -eq 28 ]
  [ "$(printf '%s' "$line" | jq -r '.n_open')" -eq 28 ]
}
