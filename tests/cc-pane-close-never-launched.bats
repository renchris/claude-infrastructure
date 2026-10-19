#!/usr/bin/env bats
# bin/cc-pane-close against the 2026-10-18 husk classes (docs/research/lr-wake-incident-2026-10-18,
# REPORT §4 Wave F; h-live-remediation-findings.md defects 1 and 7). The closer refused all 18
# overnight husks: 14 had no registration because capacity-admit refused the launch before claude
# ran (1a), pane 332's registration named expect's inner pty and read as "a different window" (1b),
# and panes 1 and 242 read the 4 KB source stub instead of the next3 transcript that said
# "Good to close: yes" (1c). A moved session closes only while cc-find shows a LIVE copy (K6), and
# every close by remote control asks kitty-fullscreen-guard --scope pane --mode refuse first (7).
# Every external is a stub: ps, kill, it2, the guard and cc-find answer from fixture files.
# RED on origin/main (7dc482f24), measured: 11 of 13 fail there — every fix case, plus the controls
# that assert the new refusal wording. The two exit-record controls (claude DID start; a previous
# kitty's record) pass on both: they pin what the new arm must NOT close.
# shellcheck disable=SC2030,SC2031,SC2016  # per-test env exports are deliberate; stub bodies are literal

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLOSE="${CC_PANE_CLOSE_UNDER_TEST:-$REPO/bin/cc-pane-close}"
  F="$BATS_TEST_TMPDIR/fix"; S="$BATS_TEST_TMPDIR/stub"; mkdir -p "$F" "$S"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset KITTY_LISTEN_ON CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  export CC_PANE_CLOSE_KITTY_PID=610 CC_PANE_CLOSE_REMOTE=on CC_PANE_CLOSE_SETTLE_S=1
  export CC_PANE_CLOSE_WATCHDOG_LOG="$F/watchdog.log" CC_PANE_CLOSE_LOG="$F/close.jsonl"
  export CC_PANE_CLOSE_STORES="$F/storeA:$F/storeB" CC_PANE_CLOSE_CUSTODY_BIN="$S/custody" FIX="$F"
  export CC_PANE_CLOSE_PS_BIN="$S/ps" CC_PANE_CLOSE_KILL_BIN="$S/kill" CC_PANE_CLOSE_IT2="$S/it2"
  export CC_PANE_CLOSE_EXIT_DIR="$F/pane-exit" CC_PANE_CLOSE_FIND_BIN="$S/cc-find"
  export CC_PANE_CLOSE_HANDOFFS_LOG="$F/handoffs.jsonl" CC_KITTY_FS_GUARD="$S/fs-guard"
  # ps: lstart= → $FIX/lstart.<pid> · stat= → $FIX/stat.<pid> (else Ss while it has an lstart) ·
  #     tty= → $FIX/ttyof.<pid> · the -t listing → $FIX/tty.<tty>
  printf '#!/bin/bash\nfor a; do prev="$a"; done\ncase "$2" in lstart=) cat "$FIX/lstart.$prev" 2>/dev/null ;; stat=) if [ -f "$FIX/stat.$prev" ]; then cat "$FIX/stat.$prev"; elif [ -f "$FIX/lstart.$prev" ]; then echo Ss; fi ;; tty=) cat "$FIX/ttyof.$prev" 2>/dev/null ;; *) cat "$FIX/tty.$prev" 2>/dev/null ;; esac\nexit 0\n' > "$S/ps"
  printf '#!/bin/bash\necho "$*" >> "$FIX/kill.log"\nrm -f "$FIX/lstart.$ROOT"\n' > "$S/kill"
  printf '#!/bin/bash\ncat "$FIX/custody.tsv" 2>/dev/null\n' > "$S/custody"
  # it2: the listing is kitty's own; a close takes the window away (its root loses its lstart)
  printf '#!/bin/bash\necho "it2 $*" >> "$FIX/it2.log"\ncase "$1 $2" in "session list") cat "$FIX/klist.json"; exit 0 ;; "session close") rm -f "$FIX/lstart.$ROOT"; exit 0 ;; esac\nexit 1\n' > "$S/it2"
  printf '#!/bin/bash\necho "$*" >> "$FIX/guard.log"\nexit "${STUB_RC:-0}"\n' > "$S/fs-guard"
  printf '#!/bin/bash\ncat "$FIX/find.$1" 2>/dev/null\nexit 0\n' > "$S/cc-find"
  chmod +x "$S"/*
  NOW=$(date +%s); K=$((NOW - 36000)); REG=$((NOW - 7200))
  lst 610 "$K"
  SID="2e9ed9f2-9e21-4161-a0f7-10b329ade8f0"; SUCC="fad30cb7-1111-2222-3333-444444444444"
  CWD="$BATS_TEST_TMPDIR/work"; mkdir -p "$CWD"; git -C "$CWD" init -q
  mkdir -p "$F/storeA/projects/p" "$F/storeB/projects/p" "$F/pane-exit"
  printf '[]\n' > "$F/klist.json"
}

lst() { date -u -r "$2" '+%a %b %d %T %Y' > "$FIX/lstart.$1"; }
wts() { date -r "$1" '+%Y-%m-%d %H:%M:%S'; }
window() { # $1=pane $2=window pid $3=tty $4=window start epoch — kitty lists it, ps shows login+zsh
  printf '[{"id":"%s","pid":%s,"cwd":"/x","title":"zsh"}]\n' "$1" "$2" > "$FIX/klist.json"
  printf '%s\n' "$3" > "$FIX/ttyof.$2"
  printf '%s 610 /usr/bin/login\n%s %s /bin/zsh\n' "$2" "$(($2 + 1))" "$2" > "$FIX/tty.$3"
  lst "$2" "$4"; lst "$(($2 + 1))" "$4"
  export ROOT="$2"
}
exit_rec() { # $1=pane $2=rc $3=claude_started $4=ts
  printf '{"rc":%s,"claude_started":%s,"launch_sha":"%s","ts":%s}\n' "$2" "$3" "abc123def4567890" "$4" > "$FIX/pane-exit/$1.json"
}
register() { # $1=sid $2=tty $3=pane $4=epoch
  printf '[%s] registered session=%s pid=7000 tty=%s pane=%s\n' "$(wts "$4")" "$1" "$2" "$3" >> "$FIX/watchdog.log"
}
tx() { # $1=store $2=sid, then jsonl body lines (CWD is filled in)
  local st="$1" s="$2"; shift 2
  printf '%s\n' "$@" | sed "s#CWD#$CWD#g" > "$FIX/$st/projects/p/$s.jsonl"
}
said_no()  { printf '{"type":"assistant","cwd":"CWD","message":{"role":"assistant","content":[{"type":"text","text":"Good to close: no — still working"}]}}'; }
said_yes() { printf '{"type":"assistant","cwd":"CWD","message":{"role":"assistant","content":[{"type":"text","text":"Good to close: yes — landed"}]}}'; }
tombstone() { # source storeA → storeB
  printf '{"sid":"%s","handed_off_to":"%s","target_transcript":"x"}\n' "$SID" "$FIX/storeB" > "$FIX/storeA/projects/p/$SID.HANDOFF.json"
}

# ── 1a: the never-launched arm ─────────────────────────────────────────────────────────────────────
@test "1a: rc 9 with claude_started=false and no registration is closed — through the pane-scope guard first" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 9 false $((NOW - 300))
  run "$CLOSE" --pane 77
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane 77: CLOSED"*"never started claude (rc 9"*"via kitty remote control"* ]] || { echo "$output"; false; }
  grep -qx -- '--window 77 --to unix:/tmp/kitty-610 --scope pane --mode refuse --tool cc-pane-close' "$FIX/guard.log" || { cat "$FIX/guard.log"; false; }
  grep -q '^it2 session close -f -s 77 ' "$FIX/it2.log"
  # the guard was asked BEFORE the close: its line exists and the close came after the listing
  ! grep -q -- '--scope os-window' "$FIX/guard.log" || false
}

@test "7: the pane-scope guard refusing (last pane of a fullscreen OS window) keeps the pane — no close is sent" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 9 false $((NOW - 300))
  STUB_RC=3 run "$CLOSE" --pane 77
  [ "$status" -eq 1 ]
  [[ "$output" == *"pane 77: REFUSED"*"fullscreen guard refused (--scope pane --mode refuse)"* ]] || { echo "$output"; false; }
  ! grep -q 'session close' "$FIX/it2.log" || { cat "$FIX/it2.log"; false; }
}

@test "7: --dry-run asks the same guard, so a verdict painted from it never promises a close the guard forbids" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 9 false $((NOW - 300))
  STUB_RC=3 run "$CLOSE" --dry-run --pane 77
  [ "$status" -eq 1 ]
  [[ "$output" != *"WOULD CLOSE"* ]] || false
  STUB_RC=0 run "$CLOSE" --dry-run --pane 77
  [ "$status" -eq 0 ]; [[ "$output" == *"WOULD CLOSE — no session"* ]] || { echo "$output"; false; }
  ! grep -q 'session close' "$FIX/it2.log" || false
}

@test "1a CONTROL: an exit record saying claude DID start is no never-launched pane — refused" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 0 true $((NOW - 300))
  run "$CLOSE" --pane 77
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session registration"* ]] || { echo "$output"; false; }
  [ ! -e "$FIX/guard.log" ]
}

@test "1a CONTROL: an exit record from a previous kitty's lifetime is ignored" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 9 false $((K - 60))
  run "$CLOSE" --pane 77
  [ "$status" -eq 1 ]
  ! grep -q 'session close' "$FIX/it2.log" 2>/dev/null || false
}

@test "1a CONTROL: never-launched with remote control down cannot name the window — refused, nothing signalled" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 9 false $((NOW - 300))
  CC_PANE_CLOSE_REMOTE=off run "$CLOSE" --pane 77
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not name this pane's window"* ]] || { echo "$output"; false; }
  [ ! -e "$FIX/kill.log" ]
}

@test "1a CONTROL: a live job in a never-launched pane's window is refused" {
  window 77 6000 ttys070 $((NOW - 600)); exit_rec 77 9 false $((NOW - 300))
  printf '6000 610 /usr/bin/login\n6001 6000 /bin/zsh\n6002 6001 vim\n' > "$FIX/tty.ttys070"
  run "$CLOSE" --pane 77
  [ "$status" -eq 1 ]
  [[ "$output" == *"a live job runs in the window: vim"* ]] || { echo "$output"; false; }
}

# ── 1c: the full transcript, across stores ─────────────────────────────────────────────────────────
@test "1c: the source stub says nothing, its HANDOFF.json leads to the target's 'Good to close: yes' — closed" {
  window 69 5000 ttys057 $((REG - 4)); register "$SID" ttys057 69 "$REG"
  tx storeA "$SID" "$(said_no)"; tombstone
  tx storeB "$SID" "$(said_no)" "$(said_yes)"
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Good to close: yes (in its full transcript on storeB)"* ]] || { echo "$output"; false; }
}

# ── K6: moved, with a LIVE copy ────────────────────────────────────────────────────────────────────
@test "K6: a tombstone with no LIVE copy anywhere is refused as STRANDED, naming lr-fleet --one" {
  window 69 5000 ttys057 $((REG - 4)); register "$SID" ttys057 69 "$REG"
  tx storeA "$SID" "$(said_no)"; tombstone; tx storeB "$SID" "$(said_no)"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"moved (to storeB) but no LIVE copy runs anywhere — STRANDED: lr-fleet --one 2e9ed9f2"* ]] || { echo "$output"; false; }
  ! grep -q 'session close' "$FIX/it2.log" || false
}

@test "K6: a moved session whose LIVE copy cc-find shows in another pane is closed, even over a dirty cwd" {
  window 69 5000 ttys057 $((REG - 4)); register "$SID" ttys057 69 "$REG"
  tx storeA "$SID" "$(said_no)"; tombstone; tx storeB "$SID" "$(said_no)"
  printf '%s\t442\tnext3\t%s\t%s\tLIVE\tLEAD\n' "$SID" "$FIX/storeB" "$CWD" > "$FIX/find.$SID"
  echo wip > "$CWD/f"
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"a LIVE copy runs in pane 442 (session 2e9ed9f2)"* ]] || { echo "$output"; false; }
}

@test "K6 CONTROL: cc-find's copy in THIS pane, or a STALE one, is not a LIVE copy elsewhere" {
  window 69 5000 ttys057 $((REG - 4)); register "$SID" ttys057 69 "$REG"
  tx storeA "$SID" "$(said_no)"; tombstone; tx storeB "$SID" "$(said_no)"
  printf '%s\t69\tnext3\tx\tx\tLIVE\tLEAD\n%s\t442\tnext3\tx\tx\tSTALE\tLEAD\n' "$SID" "$SID" > "$FIX/find.$SID"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"STRANDED"* ]] || { echo "$output"; false; }
}

# ── 1b: the registration named expect's inner pty; lineage, not a refusal ───────────────────────────
@test "1b: pane 332's registration names an inner pty now held by a newer window; kitty names the pane's own tty, and the recycle successor is LIVE — closed" {
  window 332 5000 ttys002 $((REG - 4))
  register "$SID" ttys064 332 "$REG"
  # ttys064 now belongs to a newer window (the device was reused)
  printf '8000 610 /usr/bin/login\n8001 8000 /bin/zsh\n' > "$FIX/tty.ttys064"; lst 8000 $((REG + 600))
  # the session re-registered in pane 442 later, and recycled there into SUCC, which runs
  register "$SID" ttys086 442 $((REG + 900))
  printf '{"ts":"%s","class":"recycle-engaged","target_pane":"442","prev_sid":"%s"}\n' "$(date -u -r $((REG + 1800)) +%FT%TZ)" "$SID" > "$FIX/handoffs.jsonl"
  printf '%s\t442\tnext3\tx\tx\tLIVE\tLEAD\n' "$SUCC" > "$FIX/find.442"
  tx storeB "$SID" "$(said_no)"
  run "$CLOSE" --pane 332
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane 332: CLOSED"*"a LIVE copy runs in pane 442 (session fad30cb7)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"a different window"* ]] || false
}

@test "1b CONTROL: a LIVE session in the later pane that is NOT this sid's recycle successor does not count" {
  window 332 5000 ttys002 $((REG - 4)); register "$SID" ttys064 332 "$REG"
  register "$SID" ttys086 442 $((REG + 900))
  printf '%s\t442\tnext3\tx\tx\tLIVE\tLEAD\n' "$SUCC" > "$FIX/find.442"
  tx storeB "$SID" "$(said_no)"
  run "$CLOSE" --pane 332
  [ "$status" -eq 1 ]
  [[ "$output" == *"re-registered in pane 442) but no LIVE copy"*"STRANDED"* ]] || { echo "$output"; false; }
}
