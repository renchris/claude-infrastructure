#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there);
#   SC2016: the stub bodies are single-quoted on purpose, their $ is the stub's own shell.
#
# boot-resume.sh, the three residuals of the 2026-10-25 reboot (boot-resume-empty-source DESIGN.md §5):
#   1. the recycle-successor rung 1 reads the files the restored rows came from (SRC_FILES); the
#      tombstone source, and tombstones that join a stale snapshot, never put theirs there, so a
#      recycled session's successor was found only by the registry and transcript rungs;
#   2. a burst of `other` ends followed by more heartbeat ticks is a closed kitty window, not the
#      shutdown, even when it is the last burst before a boot that left no SessionEnd;
#   3. a session resumed by hand after the boot and gone since does not come back a second time: the
#      per-boot marker (same_boot) stops a re-run, and with the markers removed the sid-keyed check
#      (a transcript record after the boot, no live holder) does.
# RED-proof: against origin/main 84b8e4025's boot-resume.sh the cases marked RED fail (the old sid is
# launched beside its successor; the window's sessions are the source; the hand-resumed one is
# launched again). The same_boot pin is proved by mutation (drop the `elif same_boot` arm).

bats_require_minimum_version 1.5.0

load helpers/cc-stub
load helpers/boot-resume-env

BOOT=1784800000                      # 2026-07-23T09:46:40Z, the helper's pinned boot
setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # also in the helper; the hermeticity ratchet reads setup() itself
  export CC_FIRE_CAPACITY_GATE=off
  boot_resume_setup
  cc_stub_self "$CC_RESUME_CLASSIFY_BIN" "$(printf '#!/bin/bash\nwhile IFS= read -r row; do [ -n "$row" ] && printf "%%s\\tAT-REST\\n" "$row"; done\n')"
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lockwatch"; mkdir -p "$CC_LOCKWATCH_DIR" "$CC_TEARDOWN_DIR"
  export CC_RESTORE_GATE_POLL_S=0 CC_BOOT_RESUME_MODE=resume
}
ptomb() { # <sid> <endedAt> <pane> [cwd] — a tombstone as session-deregister.sh writes it: the registry row + endedAt
  jq -n --arg s "$1" --argjson t "$2" --arg p "$3" --arg c "${4:-/x/wt-$1}" \
    '{paneUUID:$p,session_id:$s,account:"claude-next",cwd:$c,name:("T-"+$s),pid:1,startedAt:1,
      endedAt:$t,endReason:"other",hostShutdown:false}' > "$CC_SHUTDOWN_TOMB_DIR/$1.json"
}
transcript() { # <sid> <cwd> <last user/assistant ts>
  local d; d="$HOME/.claude-next/projects/$(printf '%s' "$2" | tr -c 'A-Za-z0-9' '-')"; mkdir -p "$d"
  printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n{"type":"last-prompt"}\n' "$3" > "$d/$1.jsonl"
}
recycled() { # sid-gone recycled into a successor in pane 25, after its last activity
  touch "$CC_BOOT_RESUME_STATE_DIR/restore-v2"
  transcript sid-gone /x/wt-gone 2026-07-23T09:20:00.000Z
  printf '{"key_kind":"sid","pane":"9","sid":"sid-gone","mode":"recycle","ts":"2026-07-23T09:21:00Z"}\n' > "$CC_TEARDOWN_DIR/sid-gone.json"
  printf '{"ts":"2026-07-23T09:21:30Z","class":"recycle-engaged","gate":"recycle","engaged":true,"target_pane":"25","prev_sid":"sid-gone"}\n' > "$CC_HANDOFF_LOG"
}
launched() { cat "$CC_RESUME_LAUNCH_BIN.log" 2>/dev/null; }
boot_class() { printf '{"class":"%s","confidence":"high"}\n' "$1" > "$CC_LOCKWATCH_DIR/boot-$BOOT.json"; }
ticks() { mkdir -p "$CC_HEARTBEAT_DIR"; for t in "$@"; do printf '%s\tok\tcensus_s=1\ttick_s=1\tkittys=1\n' "$t" >> "$CC_HEARTBEAT_DIR/census.log"; done; }

# ── 1. the recycle successor, from a tombstone ─────────────────────────────────────────────────
@test "1 RED: tombstones the source ⇒ the recycled sid's successor is found in its tombstone's pane, and the old sid stays down" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; recycled
  ptomb sid-gone $((BOOT - 200)) 9 /x/wt-gone
  ptomb sid-succ $((BOOT - 199)) 25 /x/wt-gone
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '"source":"tombstones"' "$CC_IDL"
  ! launched | grep -q sid-gone || { echo "$output"; false; }
  launched | grep -q sid-succ
  [[ "$output" == *"recycled into sid-succ (in a shutdown tombstone, pane 25; recycle-engaged 2026-07-23T09:21:30Z)"* ]] || false
}

@test "1 RED: a successor that joins a stale roster from its shutdown tombstone is found there too" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; recycled
  roster pre $((BOOT - 3000)) "[$(rrow sid-gone claude-next /x/wt-gone GONE),$(rrow sid-live claude-next /x/wt-live LIVE)]"
  ptomb sid-live $((BOOT - 200)) 12 /x/wt-live
  ptomb sid-succ $((BOOT - 199)) 25 /x/wt-gone
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '"tomb_joined":1' "$CC_IDL"
  ! launched | grep -q sid-gone || { echo "$output"; false; }
  launched | grep -q sid-succ; launched | grep -q sid-live
  [[ "$output" == *"recycled into sid-succ (in a shutdown tombstone, pane 25;"* ]] || false
}

@test "1: the roster rung keeps its words for a roster row" {
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; recycled
  roster pre $((BOOT - 3000)) '[{"session_id":"sid-gone","account":"claude-next","cwd":"/x/wt-gone","paneUUID":"9"},{"session_id":"sid-succ","account":"claude-next","cwd":"/x/wt-gone","paneUUID":"25"}]'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recycled into sid-succ (in the roster, pane 25;"* ]] || false
}

# ── 2. a burst the heartbeat outlived is a closed window ───────────────────────────────────────
window_closed() { # four panes closed together 5000 s before a boot that left no SessionEnd; a ghost of the lockup
  export CC_BOOT_RESUME_MODE=page
  for i in 1 2 3 4; do tomb "w$i" $((BOOT - 5000 + i)); done
  reg_entry g1 1784795000000 claude-quaternary /Users/x/wt-g GHOST-ONE
}

@test "2 RED: the last burst followed by heartbeat ticks is not the shutdown ⇒ the registry answers" {
  window_closed
  ticks $((BOOT - 4700)) $((BOOT - 300))
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '"source":"registry"' "$CC_IDL"
  grep -q 'GHOST-ONE' "$CC_NOTIFY_BIN.log"
  ! grep -q 'T-w1' "$CC_NOTIFY_BIN.log" || false
  [[ "$output" == *"is not the shutdown: the heartbeat ticked 4696s after it"* ]] || false
}

@test "2 RED: the 2026-10-25 shape — a distrusted empty heartbeat ticked after the window closed ⇒ not the shutdown" {
  window_closed
  boot_class LOCKUP_DEVFS
  hbeat UUID-PREV 4001 $((BOOT - 300)) '[]'
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '"lockup_distrust":"boot class LOCKUP_DEVFS"' "$CC_IDL"
  grep -q '"source":"registry"' "$CC_IDL"
  ! grep -q 'T-w1' "$CC_NOTIFY_BIN.log" || false
}

@test "2: the real shutdown — no tick after the burst, or one inside the afterlife — stays the shutdown" {
  export CC_BOOT_RESUME_MODE=page
  tomb s1 $((BOOT - 110)); tomb s2 $((BOOT - 105))
  ticks $((BOOT - 430)) $((BOOT - 105 + 60))           # the last tick 320 s before, one 60 s into the shutdown
  hbeat UUID-PREV 4001 $((BOOT - 430)) '[]'; boot_class LOCKUP_DEVFS
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q '"source":"tombstones"' "$CC_IDL"
  grep -q 'T-s1' "$CC_NOTIFY_BIN.log"
}

@test "2: kern.willshutdown tombstones are the kernel's word, ticks after them or not" {
  window_closed
  for i in 1 2 3 4; do tomb "w$i" $((BOOT - 5000 + i)) true; done
  ticks $((BOOT - 300))
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"source":"tombstones"' "$CC_IDL"
  grep -q 'T-w1' "$CC_NOTIFY_BIN.log"
}

@test "2: no heartbeat record at all is no evidence ⇒ the last burst stands" {
  window_closed
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"source":"tombstones"' "$CC_IDL"
}

# ── 3. a session resumed after the boot and gone since ─────────────────────────────────────────
@test "3 (pin): a re-run for a boot already handled abstains before DETECT — nothing launched" {
  export CC_BOOTUUID_OVERRIDE=UUID-THIS-BOOT
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo UUID-THIS-BOOT > "$CC_BOOT_RESUME_STATE_DIR/last-boot-uuid"
  tomb t1 $((BOOT - 100)); tomb t2 $((BOOT - 99))
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q '"reason":"already-processed"' "$CC_IDL"
  [ -z "$(launched)" ]
}

@test "3 RED: markers removed — a session resumed after the boot and no longer running is not started again" {
  tomb t1 $((BOOT - 100)); tomb t2 $((BOOT - 99))
  transcript t1 /Users/x/wt-t1 2026-07-23T10:05:00.000Z     # hand-resumed at 10:05, after the 09:46:40 boot
  transcript t2 /Users/x/wt-t2 2026-07-23T09:40:00.000Z
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! launched | awk '$3 == "t1"' | grep -q . || { launched; false; }
  launched | awk '$3 == "t2"' | grep -q .
  [[ "$output" == *"skipped retired session T-t1 (t1): already resumed after this boot (last activity 2026-07-23T10:05:00Z, boot 2026-07-23T09:46:40Z) and no longer running"* ]] || false
}

@test "3: the same session still running is left to the launcher's holder probe, not retired" {
  tomb t1 $((BOOT - 100)); tomb t2 $((BOOT - 99))
  transcript t1 /Users/x/wt-t1 2026-07-23T10:05:00.000Z
  jq -n --argjson p "$$" '{paneUUID:"40",session_id:"t1",pid:$p,startedAt:1784800300000}' > "$CC_REGISTRY_DIR/40.json"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"already resumed after this boot"* ]] || false
  grep -q '"retired_skipped":0' "$CC_IDL"
}
