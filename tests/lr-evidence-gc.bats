#!/usr/bin/env bats
# lr-lock.py evidence-gc — VERIFY, THEN DELETE (decision 6d4722735677, 2026-10-11).
# An evidence dir's bytes go only when every file is proven to be in an account store (byte-prefix
# for .jsonl, identical otherwise); anything else is kept whole, stamped once and paged once.
# Hermetic: LR_STATE_DIR, LR_CONFIG_DIRS and the page command all point into $BATS_TEST_TMPDIR.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  LRLOCK="$REPO/scripts/limit-recover/lr-lock.py"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; LOCKS="$LR_STATE_DIR/locks"; mkdir -p "$LOCKS"
  S="$BATS_TEST_TMPDIR/store"; mkdir -p "$S/projects/-p"
  export LR_CONFIG_DIRS="$S"
  export PAGE_LOG="$BATS_TEST_TMPDIR/pages.log"; : > "$PAGE_LOG"
  export LR_EVIDENCE_GC_PAGE_BIN="$BATS_TEST_TMPDIR/page.sh"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$PAGE_LOG"\necho "lr-page: verdict=posted os=posted phone=skipped"\n' > "$LR_EVIDENCE_GC_PAGE_BIN"
  SID="6d472273-0000-4000-8000-0000000000ee"
  OLD="$(date -u -v-8d +%Y%m%dT%H%M%SZ)"; NEW="$(date -u -v-1d +%Y%m%dT%H%M%SZ)"
  EV="$LOCKS/$SID.aborted-$OLD"
}

teardown() { [ -z "${GCPID:-}" ] || kill "$GCPID" 2>/dev/null || true; }   # only the GC this test started
gc() { run /usr/bin/python3 "$LRLOCK" evidence-gc "$@"; }
# The 2026-10-11 live shape: a main transcript, a session dir (a subagent .jsonl and a tool result),
# the filed tombstone and a lock copy. The store holds the session as it grew after the copy.
seed() { # $1=evidence dir
  mkdir -p "$1/$SID/subagents" "$1/$SID/tool-results"
  printf 'A\nB\n' > "$1/$SID.jsonl"
  printf 'x1\n' > "$1/$SID/subagents/agent-x.jsonl"
  printf 'result' > "$1/$SID/tool-results/t1.txt"
  printf '{"tomb":1}\n' > "$1/$SID.HANDOFF.json.aborted"
  printf '{"sid":"%s"}\n' "$SID" > "$1/lock"
  mkdir -p "$S/projects/-p/$SID/subagents" "$S/projects/-p/$SID/tool-results"
  printf 'A\nB\nC\n' > "$S/projects/-p/$SID.jsonl"
  printf 'x1\nx2\n' > "$S/projects/-p/$SID/subagents/agent-x.jsonl"
  printf 'result' > "$S/projects/-p/$SID/tool-results/t1.txt"
}
digest() { (cd "$1" && find . -type f ! -name EVIDENCE-KEPT -exec shasum {} + | sort); }

@test "[RED] a covered dir past 7 days loses its bytes, keeps lock/tombstone, and its receipt rebuilds every file (a strict byte-prefix counts: the BSD cmp -n trap)" {
  seed "$EV"
  cp "$EV/$SID.jsonl" "$BATS_TEST_TMPDIR/orig-main"
  gc
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$EV/$SID.jsonl" ] || { echo "$output"; ls -R "$EV"; false; }
  [ ! -e "$EV/$SID" ] || { echo "$output"; ls -R "$EV"; false; }
  [ -f "$EV/$SID.HANDOFF.json.aborted" ]
  [ -f "$EV/lock" ]
  [ -f "$EV/GC.json" ]
  [ ! -e "$EV/GC.json.pending" ]
  [ "$(jq -r .freed_bytes "$EV/GC.json")" -eq 13 ]
  [ "$(jq '.files | length' "$EV/GC.json")" -eq 3 ]
  # rebuild the main transcript from the receipt alone
  b="$(jq -r --arg r "$SID.jsonl" '.files[] | select(.rel == $r) | .bytes' "$EV/GC.json")"
  c="$(jq -r --arg r "$SID.jsonl" '.files[] | select(.rel == $r) | .covered_by' "$EV/GC.json")"
  head -c "$b" "$c" | cmp -s - "$BATS_TEST_TMPDIR/orig-main"
  [[ "$output" == *"verdict=ok"*"freed=13"* ]] || { echo "$output"; false; }
  [ ! -s "$PAGE_LOG" ]
}

@test "an evidence line the store does not hold keeps the dir byte-identical, stamped ONCE and paged ONCE" {
  seed "$EV"; printf 'D\n' >> "$EV/$SID.jsonl"
  before="$(digest "$EV")"
  gc
  [ "$status" -eq 0 ]
  [ "$(digest "$EV")" = "$before" ]
  [ -f "$EV/EVIDENCE-KEPT" ]
  [ ! -e "$EV/GC.json" ]
  [ "$(jq -r .first "$EV/EVIDENCE-KEPT")" = "$SID.jsonl" ]
  [ "$(wc -l < "$PAGE_LOG")" -eq 1 ] || { cat "$PAGE_LOG"; false; }
  stamp="$(cat "$EV/EVIDENCE-KEPT")"
  gc
  [ "$(wc -l < "$PAGE_LOG")" -eq 1 ] || { cat "$PAGE_LOG"; false; }
  [ "$(cat "$EV/EVIDENCE-KEPT")" = "$stamp" ]
  [ "$(digest "$EV")" = "$before" ]
}

@test "a non-.jsonl file must be IDENTICAL: a store copy that only extends it does not cover" {
  seed "$EV"; printf ' more' >> "$S/projects/-p/$SID/tool-results/t1.txt"
  gc
  [ -e "$EV/$SID.jsonl" ]
  [ -f "$EV/EVIDENCE-KEPT" ]
  [ "$(jq -r .first "$EV/EVIDENCE-KEPT")" = "$SID/tool-results/t1.txt" ]
}

@test "the session missing from every store (moved, deleted) keeps the dir" {
  seed "$EV"; rm "$S/projects/-p/$SID.jsonl"
  gc
  [ -e "$EV/$SID.jsonl" ]
  [ -d "$EV/$SID" ]
  [ -f "$EV/EVIDENCE-KEPT" ]
}

@test "set-aside and same-inode copies never cover: only a live <sid>.jsonl / .handed-off / <sid>/ does" {
  seed "$EV"; mv "$S/projects/-p/$SID.jsonl" "$S/projects/-p/$SID.jsonl.released-20261011T000000Z"
  gc
  [ -e "$EV/$SID.jsonl" ] || false
  rm -f "$EV/EVIDENCE-KEPT"; ln "$EV/$SID.jsonl" "$S/projects/-p/$SID.jsonl"
  gc
  [ -e "$EV/$SID.jsonl" ]
  [ -f "$EV/EVIDENCE-KEPT" ]
  rm -f "$EV/EVIDENCE-KEPT" "$S/projects/-p/$SID.jsonl"; printf 'A\nB\nC\n' > "$S/projects/-p/$SID.jsonl.handed-off"
  gc
  [ ! -e "$EV/$SID.jsonl" ] || { echo "$output"; false; }
  [ -f "$EV/GC.json" ] || { echo "$output"; false; }
}

@test "a dir under 7 days old is untouched, however well covered" {
  EV="$LOCKS/$SID.unconfirmed-$NEW"; seed "$EV"
  before="$(digest "$EV")"
  gc
  [ "$(digest "$EV")" = "$before" ]
  [ ! -e "$EV/GC.json" ]
  [[ "$output" == *"young=1"* ]] || { echo "$output"; false; }
}

@test "--dry-run writes nothing and prints the bytes it would free" {
  seed "$EV"; mkdir -p "$LOCKS/$SID.failed-admit-$OLD.123"; printf 'A\nZ\n' > "$LOCKS/$SID.failed-admit-$OLD.123/$SID.jsonl"
  before="$(cd "$LR_STATE_DIR" && find . | sort)"
  gc --dry-run
  [ "$status" -eq 0 ]
  [ "$(cd "$LR_STATE_DIR" && find . | sort)" = "$before" ]
  [[ "$output" == *"verdict=dry-run"*"would_free=13"*"kept=1"*"would-free=1"* ]] || { echo "$output"; false; }
  [ ! -s "$PAGE_LOG" ]
}

@test "a sid whose lock names a LIVE holder is skipped untouched" {
  seed "$EV"
  printf '{"sid":"%s","to":"%s","owner":"%s","ts":"%s","pid":999999,"holder":{"pid":%d,"lstart":"%s"}}\n' \
    "$SID" "$S" "$S" "$(date -u +%FT%TZ)" "$$" "$(TZ=UTC LC_ALL=C ps -o lstart= -p $$)" > "$LOCKS/$SID.lock"
  gc
  [ -e "$EV/$SID.jsonl" ]
  [ ! -e "$EV/GC.json" ]
  [ ! -e "$EV/EVIDENCE-KEPT" ]
  [[ "$output" == *"held=1"* ]] || { echo "$output"; false; }
  # the same lock once its holder is gone: collected
  printf '{"sid":"%s","to":"%s","owner":"%s","ts":"2026-01-01T00:00:00Z","pid":999999}\n' "$SID" "$S" "$S" > "$LOCKS/$SID.lock"
  gc
  [ ! -e "$EV/$SID.jsonl" ] || { echo "$output"; false; }
  [ -f "$EV/GC.json" ] || { echo "$output"; false; }
}

@test "crash-safe receipt: a run that died after a delete (.pending, files left) is finished and its record kept" {
  seed "$EV"
  printf '{"files":[{"rel":"%s/gone.txt","bytes":4,"covered_by":"/somewhere"}]}\n' "$SID" > "$EV/GC.json.pending"
  gc
  [ ! -e "$EV/GC.json.pending" ]
  [ -f "$EV/GC.json" ]
  [ "$(jq '.files | length' "$EV/GC.json")" -eq 4 ]
  jq -e --arg r "$SID/gone.txt" '.files[] | select(.rel == $r)' "$EV/GC.json" >/dev/null
  # and a finished dir is left alone by the next run
  r="$(cat "$EV/GC.json")"; gc
  [ "$(cat "$EV/GC.json")" = "$r" ]
  [[ "$output" == *"done=1"* ]] || { echo "$output"; false; }
}

@test "cc-lr status counts the kept dirs; a dir resolved since (GC.json) is not counted" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  mkdir -p "$LOCKS/a.aborted-x" "$LOCKS/b.aborted-y"
  : > "$LOCKS/a.aborted-x/EVIDENCE-KEPT"; : > "$LOCKS/b.aborted-y/EVIDENCE-KEPT"; : > "$LOCKS/b.aborted-y/GC.json"
  run "$REPO/bin/cc-lr" status
  [[ "$output" == *"EVIDENCE-KEPT  1 evidence dir(s) hold bytes no account store has"*"a.aborted-x"* ]] || { echo "$output"; false; }
  rm "$LOCKS/a.aborted-x/EVIDENCE-KEPT"
  run "$REPO/bin/cc-lr" status
  [[ "$output" != *"EVIDENCE-KEPT"* ]] || { echo "$output"; false; }
}

# ── the poller starts it: once a day, detached, never inside the tick ─────────────────────────────
poller_env() {
  export LR_UPGRADE_AUTO=off LR_POLLER_NO_CENSUS=1
  export HOME="$BATS_TEST_TMPDIR/home"; PSTATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$PSTATE/parked" "$PSTATE/locks" "$BATS_TEST_TMPDIR/stubs"
  unset LR_STATE_DIR LR_CONFIG_DIRS CLAUDE_CONFIG_DIR KITTY_WINDOW_ID
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket" LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\necho none\n' > "$HOME/bin/claude-accounts"
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
}
live_layer() { # the fixture $HOME's deployed lr-lock.py IS this checkout's, as install.sh links it
  mkdir -p "$HOME/.claude/scripts/limit-recover"
  ln -s "$REPO/scripts/limit-recover/lr-lock.py" "$HOME/.claude/scripts/limit-recover/lr-lock.py"
}

@test "[RED] poller: a copy that is not the deployed layer (a worktree, a snapshot, a test) never starts the GC" {
  poller_env
  run bash "$POLLER" --once
  grep -q 'EVIDENCE-GC-SKIP .* is not the deployed layer' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
  ! grep -q 'EVIDENCE-GC started' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
  [ ! -e "$PSTATE/evidence-gc.log" ]
  [ ! -e "$PSTATE/evidence-gc.stamp" ]
}

@test "poller: a GC run still alive (evidence-gc.pid) is never joined by a second" {
  poller_env; live_layer
  printf '%s\n' "$$" > "$PSTATE/evidence-gc.pid"
  run bash "$POLLER" --once
  grep -q "EVIDENCE-GC-SKIP the previous run (pid $$) is still going" "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
  ! grep -q 'EVIDENCE-GC started' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
}

@test "poller: --dry-run only says it would start; LR_EVIDENCE_GC=off says nothing" {
  poller_env; live_layer
  run bash "$POLLER" --dry-run --once
  grep -q 'DRY   evidence GC would start' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
  [ ! -e "$PSTATE/evidence-gc.stamp" ]
  [ ! -e "$PSTATE/evidence-gc.log" ]
  : > "$PSTATE/poller.log"
  LR_EVIDENCE_GC=off run bash "$POLLER" --once
  ! grep -q 'EVIDENCE-GC\|evidence GC' "$PSTATE/poller.log" || { cat "$PSTATE/poller.log"; false; }
}

@test "poller: the live layer's tick starts ONE detached GC run that outlives the tick; the next tick does not start another" {
  poller_env; live_layer
  run bash "$POLLER" --once
  GCPID="$(sed -n 's/.*EVIDENCE-GC started pid \([0-9][0-9]*\).*/\1/p' "$PSTATE/poller.log" | head -1)"
  [ -n "$GCPID" ] || { cat "$PSTATE/poller.log"; false; }
  [ "$(cat "$PSTATE/evidence-gc.pid")" = "$GCPID" ]
  # The tick has exited. Under `taskpolicy -c utility` at high load the run can take a while, so the claim
  # is "started detached and is the GC", not "finished fast": either it already printed its verdict,
  # or it is still alive as the GC.
  for _i in $(seq 1 20); do grep -q 'evidence-gc: verdict=ok' "$PSTATE/evidence-gc.log" 2>/dev/null && break; sleep 1; done
  grep -q 'evidence-gc: verdict=ok' "$PSTATE/evidence-gc.log" 2>/dev/null \
    || ps -o command= -p "$GCPID" | grep -q 'lr-lock.py evidence-gc' \
    || { cat "$PSTATE/evidence-gc.log"; false; }
  ! grep -q Traceback "$PSTATE/evidence-gc.log" 2>/dev/null || { cat "$PSTATE/evidence-gc.log"; false; }
  run bash "$POLLER" --once
  [ "$(grep -c 'EVIDENCE-GC started' "$PSTATE/poller.log")" -eq 1 ] || { cat "$PSTATE/poller.log"; false; }
}
