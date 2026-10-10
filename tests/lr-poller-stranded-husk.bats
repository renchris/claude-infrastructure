#!/usr/bin/env bats
# lr-reset-poller.sh — A STRANDED HUSK IS OWNED, NOT RETIRED (lr-stranded-husk, 2026-10-10, 186452ed).
# Hermetic: fixture $HOME, the lr-fleet and cc-backlog stubs, LR_MOVE_ENV_DIR standing in for
# `ps -E`, the bats process itself as the "live" holder pid. Nothing is typed. One case spawns its
# OWN `sleep` under a '--resume SID' argv and kills only that pid (teardown too).
# Spec: docs/research/lr-stranded-husk-2026-10-10/round2/C2.md (FINAL SPEC B + SKEPTIC REQUIRED CHANGES).

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/requests" "$BATS_TEST_TMPDIR/stubs"
  SID="186452ed-0000-4000-8000-0000000000aa"
  unset CLAUDE_CONFIG_DIR KITTY_WINDOW_ID CC_TERM_KITTY_TO LR_RQ_TEAMMATE_PREDICATE LR_PREDICATE_PY LR_CONFIG_DIRS LR_RQ_BG_HOLDER LR_SUCCESSOR_GATE LR_HUSK_RETIRE
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_HANDOFF_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"; : > "$CC_HANDOFF_LOG"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/env"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\ncase " $* " in *" --rank "*) echo none; exit 0 ;; esac\necho %s\n' "'{\"rows\":[{\"acct\":\"next4\",\"session_pct\":12,\"weekly_pct\":40}]}'" > "$HOME/bin/claude-accounts"
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"
  cat > "$LR_FLEET_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FLEET_LOG:?}"
echo "lr-fleet: DETACHED — driver pid ${FLEET_DRIVER_PID:-4242} is recovering; the verdict arrives as mail."
echo "run=${FLEET_RUN:-/nowhere/run} log=/nowhere/run/detached.log"
exit 0
STUB
  chmod +x "$LR_FLEET_BIN"
  export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  export FLEET_DRIVER_PID="$$"
  export LR_BACKLOG_BIN="$BATS_TEST_TMPDIR/stubs/cc-backlog" BACKLOG_LOG="$BATS_TEST_TMPDIR/backlog.log"; : > "$BACKLOG_LOG"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$BACKLOG_LOG"; echo 0123456789ab\n' > "$LR_BACKLOG_BIN"; chmod +x "$LR_BACKLOG_BIN"
  : > "$STATE/autorecover.on"
  SRC="$HOME/.claude-secondary"; TGT="$HOME/.claude-quaternary"
  mkdir -p "$SRC/projects/-p" "$TGT/projects/-p"
}

teardown() { [ -z "${XPID:-}" ] || kill "$XPID" 2>/dev/null || true; }
spawn_argv() { # $1=argv0 → starts OUR OWN sleep under that argv (every fd detached); XPID is its pid
  # shellcheck disable=SC2217  # the </dev/null detaches the job from bats' own stdin, not sleep's
  ( exec -a "$1" sleep 60 ) >/dev/null 2>&1 </dev/null & XPID=$!
  for _i in 1 2 3 4 5 6 7 8 9 10; do ps -o command= -p "$XPID" 2>/dev/null | grep -qF -- "$SID" && break; sleep 0.2; done
}
tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2 2>/dev/null || true; }
lim_rec() {
  printf '{"type":"assistant","timestamp":"2026-10-10T04:05:55Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets 6am"}]}}\n'
}
# the 186452ed shape: confirm tombstone, .handed-off, a non-limit /exit stub, the copy on the target
husk_disk() {
  lim_rec > "$SRC/projects/-p/$SID.jsonl.handed-off"
  printf '{"type":"user","message":{"role":"user","content":"<local-command-stdout>(no content)</local-command-stdout>"}}\n' > "$SRC/projects/-p/$SID.jsonl"
  printf '{"handed_off_to":"%s","target_transcript":"%s/projects/-p/%s.jsonl","ts":"2026-10-10T04:18:07Z","confirm_len":1}\n' "$TGT" "$TGT" "$SID" > "$SRC/projects/-p/$SID.HANDOFF.json"
  lim_rec > "$TGT/projects/-p/$SID.jsonl"
  printf '{"sid":"%s","from":"%s","to":"%s","cause":"limit"}\n' "$SID" "$SRC" "$TGT" > "$STATE/locks/$SID.lock"
}
holder() { # $1=pane $2=pid $3=account $4=cfg — a live registry row plus the pid's environment
  printf '{"session_id":"%s","pid":%s,"account":"%s","paneUUID":"%s","cwd":"/x"}\n' "$SID" "$2" "$3" "$1" > "$CC_REGISTRY_DIR/$1.json"
  printf '%s' "$4" > "$LR_MOVE_ENV_DIR/$2"
}
hook_rq() { # $1=reset epoch (default far future) → the stop-failure-marker request 186452ed carried
  printf '{"sid":"%s","target":"auto","source_pane":"99168","requested_by":"stop-failure-marker","account":"next2","transcript_path":"%s/projects/-p/%s.jsonl","reset_at_epoch":"%s"}\n' \
    "$SID" "$SRC" "$SID" "${1:-4102444800}" > "$STATE/requests/$SID.json"
}
park() {
  printf '{"sid":"%s","acct":"next2","cfg":"%s","cwd":"/x","kind":"weekly","reset_at_utc":"%s","parked_at":"2026-10-10T04:15:46Z"}\n' \
    "$SID" "$SRC" "${1:-2099-01-01T00:00:00Z}" > "$STATE/parked/$SID.json"
}

@test "[RED] (a) source-only husk: the hook request is NOT retired; the husk driver is dispatched once, attempt 1" {
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  tick
  [ "$status" -eq 0 ]
  [ ! -e "$STATE/results/$SID.retired.json" ] || { cat "$STATE/results/$SID.json"; plog; false; }
  grep -q -- "--one $SID --target auto --source-pane 99168 --from-daemon --detach" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  grep -q "STRANDED-HUSK $SID" "$STATE/poller.log" || { plog; false; }
  [ "$(jq -r .attempts "$STATE/requests/$SID.json")" = 1 ]
}

@test "[RED] (b) a recycle in flight (fresh handoffs row): kept, nothing dispatched, no attempt spent" {
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  printf '{"ts":"%s","class":"recycle-engaged","prev_sid":"%s"}\n' "$(date -u +%FT%TZ)" "$SID" >> "$CC_HANDOFF_LOG"
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  [ -f "$STATE/requests/$SID.json" ] || { plog; false; }
  [ "$(jq -r '.attempts // 0' "$STATE/requests/$SID.json")" = 0 ]
}

@test "(c) CONTROL: a live successor on the TARGET retires the request, naming it" {
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; holder 200 "$PPID" claude-quaternary "$TGT"; hook_rq
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  [ "$(jq -r .verdict "$STATE/results/$SID.json")" = retired ]
}

@test "(d) CONTROL: moved and no live holder anywhere — retired as today" {
  husk_disk; hook_rq
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  grep -q "REQUEST-RETIRED $SID — transplanted" "$STATE/poller.log" || { plog; false; }
}

@test "(e) KILL SWITCH: LR_SUCCESSOR_GATE=off retires the husk exactly as before (tombstoned)" {
  export LR_SUCCESSOR_GATE=off
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  grep -q "REQUEST-RETIRED $SID — transplanted — the source transcript is tombstoned; nothing was done" "$STATE/poller.log" || { plog; false; }
}

@test "[RED] (f) past the SOURCE reset a husk is dispatched to the husk driver, never woken in place" {
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq "$(( $(date +%s) - 3600 ))"
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { plog; false; }
  ! grep -q "REQUEST-WAKE\|NUDGE" "$STATE/poller.log" || { plog; false; }
}

@test "[RED] (g) a parked record over a husk (the request already retired) files ONE stranded-husk request, and the next tick dispatches it" {
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; park
  tick
  [ "$(jq -r .requested_by "$STATE/requests/$SID.json")" = stranded-husk ] || { plog; false; }
  [ "$(jq -r .source_pane "$STATE/requests/$SID.json")" = 99168 ]
  tick
  grep -q -- "--one $SID --target auto --source-pane 99168" "$FLEET_LOG" || { plog; false; }
  # once per tombstone: a retired request is not re-filed by the next tick
  mv "$STATE/requests/$SID.json" "$BATS_TEST_TMPDIR/gone.json"
  tick
  [ ! -e "$STATE/requests/$SID.json" ] || { plog; false; }
}

@test "[RED] (h) a HELD husk recycle refunds its attempt (bounded), so it is retried instead of exhausting" {
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  run_dir="$BATS_TEST_TMPDIR/run1"; mkdir -p "$run_dir" "$STATE/results"
  echo "lr-fleet --one 186452ed: verdict=HELD:draft rc=3 pane=99168 acct=next2 mech=husk-recycle/HELD:draft — x" > "$run_dir/verdict.txt"
  printf 'run=%s log=x\n' "$run_dir" > "$STATE/results/$SID.log"
  jq '.attempts=3 | .last_attempt_epoch=1' "$STATE/requests/$SID.json" > "$BATS_TEST_TMPDIR/r" && mv "$BATS_TEST_TMPDIR/r" "$STATE/requests/$SID.json"
  tick
  grep -q "REQUEST-REFUND $SID" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/requests/$SID.json" ] || { plog; false; }
  grep -q -- "--one $SID" "$FLEET_LOG" || { plog; false; }
}

@test "(i) LR_HUSK_RETIRE=off: no husk is ever named — retired as before" {
  export LR_HUSK_RETIRE=off
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; plog; false; }
  [ "$(jq -r .verdict "$STATE/results/$SID.json")" = retired ]
}

@test "[RED] (j) an admit that never retired the source (7f5deb68 shape) is judged as the limited session it is — dispatched, never husk-recycled" {
  lim_rec > "$SRC/projects/-p/$SID.jsonl"; : > "$TGT/projects/-p/$SID.jsonl"
  printf '{"handed_off_to":"%s","ts":"2026-10-10T05:19:27Z","cause":"voluntary","phase":"admit"}\n' "$TGT" > "$SRC/projects/-p/$SID.HANDOFF.json"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SRC" "$TGT" > "$STATE/locks/$SID.lock"
  holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { plog; false; }
  ! grep -q "STRANDED-HUSK" "$STATE/poller.log" || { plog; false; }
}

@test "[RED] (k) a parked admit-phase record past its reset is not swallowed as HUSK LEFT PARKED" {
  lim_rec > "$SRC/projects/-p/$SID.jsonl"; : > "$TGT/projects/-p/$SID.jsonl"
  printf '{"handed_off_to":"%s","ts":"2026-10-10T05:19:27Z","cause":"voluntary","phase":"admit"}\n' "$TGT" > "$SRC/projects/-p/$SID.HANDOFF.json"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SRC" "$TGT" > "$STATE/locks/$SID.lock"
  holder 99168 "$$" claude-secondary "$SRC"; park 2020-01-01T00:00:00Z
  tick
  ! grep -q "HUSK $SID .*LEFT PARKED" "$STATE/poller.log" || { plog; false; }
}

@test "[RED] the stranded-husk lane runs under /bin/bash 3.2: tick 1 files the request, tick 2 dispatches it" {
  # launchd runs this poller under /bin/bash 3.2 (agent-operating-lessons: the deployment interpreter
  # is not yours), so BOTH halves — the § 2 filer and the request lane's husk dispatch — run under it.
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; park
  LR_POLLER_AUTOFIRE=1 run /bin/bash "$POLLER" --once
  [ "$status" -eq 0 ]
  [ "$(jq -r .requested_by "$STATE/requests/$SID.json")" = stranded-husk ] || { plog; false; }
  LR_POLLER_AUTOFIRE=1 run /bin/bash "$POLLER" --once
  [ "$status" -eq 0 ]
  grep -q -- "--one $SID --target auto --source-pane 99168 --from-daemon --detach" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
}

@test "[RED] a FALSE successor read costs one tick: the stranded-husk request retires, and the next tick re-files it while the husk lives" {
  # lr_resume_procs matches ANY argv carrying '--resume SID'; a non-claude process whose env names
  # another store reads as a successor. The retire must clear the once-per-tombstone marker, or that
  # one false read strands the husk again — the incident's own shape (C2 skeptic, P3).
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; park
  tick
  [ "$(jq -r .requested_by "$STATE/requests/$SID.json")" = stranded-husk ] || { plog; false; }
  spawn_argv "zsh -c grep -n -- --resume $SID notes.txt"
  printf '%s' "$TGT" > "$LR_MOVE_ENV_DIR/$XPID"
  tick
  kill "$XPID" 2>/dev/null || true; XPID=""
  grep -q "REQUEST-RETIRED $SID — transplanted — a live successor holds it" "$STATE/poller.log" || { plog; false; }
  tick
  [ "$(jq -r .requested_by "$STATE/requests/$SID.json" 2>/dev/null)" = stranded-husk ] || { echo "the husk is live and no request was re-filed"; plog; false; }
}

@test "(l) CONTROL: an admit-phase record whose source pane is DEAD is never handed to the spawn arm" {
  # P10 sends an unmoved admit record to the nudge arm only while its source pane is alive: past the
  # reset with no holder, lr-fire-resume's tombstone verdict would refuse the spawn while this poller
  # logged RESUMED and moved the record (C2 skeptic, P10).
  lim_rec > "$SRC/projects/-p/$SID.jsonl"; : > "$TGT/projects/-p/$SID.jsonl"
  printf '{"handed_off_to":"%s","ts":"2026-10-10T05:19:27Z","cause":"voluntary","phase":"admit"}\n' "$TGT" > "$SRC/projects/-p/$SID.HANDOFF.json"
  printf '{"sid":"%s","from":"%s","to":"%s"}\n' "$SID" "$SRC" "$TGT" > "$STATE/locks/$SID.lock"
  park 2020-01-01T00:00:00Z
  tick
  ! grep -q "RESUMED $SID\|LISTED $SID" "$STATE/poller.log" || { plog; false; }
  [ -f "$STATE/parked/$SID.json" ] || { plog; false; }
}

@test "[RED] an EXHAUSTED husk request files an agent-side owner row, never the unsent-draft page" {
  # Operator ruling 2026-10-10 (ROOT-CAUSE.md): zero human in the loop, zero asks. A husk's failed
  # recoveries are the rail's to finish, so they go to an agent-owned backlog row, not a page that
  # blames a draft.
  husk_disk; holder 99168 "$$" claude-secondary "$SRC"; hook_rq
  jq '.attempts=3 | .last_attempt_epoch=1' "$STATE/requests/$SID.json" > "$BATS_TEST_TMPDIR/r" && mv "$BATS_TEST_TMPDIR/r" "$STATE/requests/$SID.json"
  tick
  grep -q "REQUEST-EXHAUSTED $SID" "$STATE/poller.log" || { plog; false; }
  grep -q -- "--project claude-infrastructure" "$BACKLOG_LOG" || { cat "$BACKLOG_LOG"; plog; false; }
  grep -q "${SID:0:8}" "$BACKLOG_LOG" || { cat "$BACKLOG_LOG"; false; }
  ! grep -q "recovery exhausted\|unsent draft" "$STATE/poller.log" || { plog; false; }
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
}
