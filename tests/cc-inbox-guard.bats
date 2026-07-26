#!/usr/bin/env bats
# cc-inbox-guard — the FAIL-LOUD backstop: undelivered mail (unacked past a deadline) escalates to the
# operator's phone + a durable alarm record; a CONSUMED inbox never does. This is the "undelivered-alarms"
# proof — nothing enqueued to a session silently vanishes. Isolated via CC_MAILBOX_DIR + a stub push-send
# + a clock override + a live-uuid override (bypasses it2).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/bin/cc-inbox-guard"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_INBOX_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_INBOX_GUARD_DEADLINE_S=600
  export CC_INBOX_GUARD_URGENT_S=60
  export CC_INBOX_GUARD_RECONCILE_BIN=""
  mkdir -p "$CC_MAILBOX_DIR"
  U="AAAAAAAA-1111-2222-3333-444444444444"
  PUSHLOG="$BATS_TEST_TMPDIR/push.log"
  export CC_INBOX_GUARD_PUSH_BIN="$BATS_TEST_TMPDIR/push"
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$PUSHLOG"; } > "$CC_INBOX_GUARD_PUSH_BIN"
  chmod +x "$CC_INBOX_GUARD_PUSH_BIN"
  # DEFAULT it2 stub. The header above claims this suite is isolated from it2, but setup() installed
  # NEITHER override, so every test that did not set its own stub fell through to the REAL
  # ~/.claude/bin/it2 — which blocks forever against a saturated iTerm2. That hung the suite (1..19
  # printed, 0 completed) and, because it is in tests/, every FULL-scope landing gate on this box.
  # `[]` is a valid but EMPTY pane list, so _LIVE_STATE=ok and the synthetic U is simply not live —
  # exactly what the real binary yielded for a fake UUID, now deterministic and instant. Tests that
  # need other liveness behaviour override CC_INBOX_GUARD_IT2 / CC_INBOX_GUARD_LIVE_UUIDS after
  # setup(), as several already do; a later export wins, so this default never masks them.
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2-default"
  { printf '#!/bin/bash\n'; printf 'echo "[]"\n'; } > "$CC_INBOX_GUARD_IT2"
  chmod +x "$CC_INBOX_GUARD_IT2"

  # a fixed "now" and a helper to stamp a message N seconds in the past
  NOW=1784544000   # 2026-07-20T00:00:00Z-ish, fixed
  export CC_INBOX_GUARD_NOW="$NOW"
}
# write a message aged $1 seconds with [from] tag $2 into U's inbox (ISO from the fixed clock)
msg_aged() {
  local age="$1" from="$2" ts
  ts="$(date -u -r "$((NOW - age))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-age))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [%s] a message\n' "$ts" "$from" >> "$CC_MAILBOX_DIR/$U.md"
}
pushed() { [ -s "$PUSHLOG" ]; }
# NEGATIVE assertions must NOT be written `! pushed`: bash exempts a `!`-inverted command from set -e,
# so such a line only ever fails the test when it is the LAST line of the body — 3 of this file's were
# silently vacuous (audited 2026-07-25). These return non-zero directly, so errexit catches them anywhere.
not_pushed()   { [ ! -s "$PUSHLOG" ]; }
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }
n_alarms() { find "$CC_COMMS_ALARM_DIR" -name 'undelivered-*.json' 2>/dev/null | wc -l | tr -d ' '; }

@test "selftest passes 3/3 (a zero-check suite must not 'pass')" {
  run "$G" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 3 ]
}

@test "undelivered to a LIVE session past deadline → phone + alarm (fail-loud)" {
  msg_aged 3600 peer          # 1h old, unacked (.acked=0)
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  [ "$status" -eq 0 ]
  pushed
  [ "$(n_alarms)" -ge 1 ]
}

@test "CONSUMED inbox (.acked advanced) → NO escalation (keys on .acked, not the eager .seen)" {
  msg_aged 3600 peer
  printf '1\n' > "$CC_MAILBOX_DIR/$U.seen"; printf '1\n' > "$CC_MAILBOX_DIR/$U.acked"
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  [ "$status" -eq 0 ]
  not_pushed
  [ "$(n_alarms)" -eq 0 ]
}

@test "within deadline → NO escalation (a fresh unread line is not overdue)" {
  msg_aged 60 peer            # 60s < 600s deadline for a peer ping
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  not_pushed
}

@test "F12: a reaper PAGE is urgent — overdue at 60s where a peer ping is not" {
  msg_aged 120 reaper         # 120s > 60s urgent deadline
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  pushed
}

@test "F8: INDETERMINATE owner (it2 unreadable) → ESCALATE (silence is not fail-loud)" {
  msg_aged 3600 peer
  # no LIVE_UUIDS override + a broken it2 → owner_liveness returns indeterminate
  export CC_INBOX_GUARD_IT2=/nonexistent/it2
  unset CC_INBOX_GUARD_LIVE_UUIDS
  run "$G" sweep
  pushed
  printf '%s' "$output" | grep -qi 'INDETERMINATE'
}

@test "dead pane with unacked mail → escalate (the target died with mail undelivered)" {
  msg_aged 3600 supervisor
  export CC_INBOX_GUARD_LIVE_UUIDS="SOMETHING-ELSE"   # U is NOT live → dead
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2ok"
  { printf '#!/bin/bash\n'; printf 'echo "[{\\"id\\":\\"SOMETHING-ELSE\\"}]"\n'; } > "$CC_INBOX_GUARD_IT2"; chmod +x "$CC_INBOX_GUARD_IT2"
  run "$G" sweep
  pushed
}

@test "damping: a second sweep of the SAME undelivered state does NOT re-escalate" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  "$G" sweep >/dev/null
  : > "$PUSHLOG"     # clear the phone log; the state marker persists
  run "$G" sweep
  not_pushed         # same (acked:lines) → damped
}

@test "damping RE-ARMS on new mail (a fresh undelivered line escalates again)" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  "$G" sweep >/dev/null
  : > "$PUSHLOG"
  msg_aged 3600 reaper        # NEW line → (acked:lines) changes → re-escalate
  run "$G" sweep
  pushed
}

@test "F11: cursor past EOF (rotation/truncation under a live cursor) → escalate" {
  msg_aged 60 peer            # 1 line, fresh
  printf '9\n' > "$CC_MAILBOX_DIR/$U.seen"   # .seen=9 > 1 line → rotated/truncated
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  pushed
  printf '%s' "$output" | grep -qi 'cursor past EOF'
}

@test "F4: an enqueue-FAILED record (cc-notify exit 5) escalates + is consumed" {
  mkdir -p "$CC_COMMS_ALARM_DIR"
  printf '{"kind":"enqueue-failed","target":"%s","msg":"could not persist"}' "$U" > "$CC_COMMS_ALARM_DIR/enqueue-fail-x.json"
  run "$G" sweep
  pushed
  [ ! -f "$CC_COMMS_ALARM_DIR/enqueue-fail-x.json" ]    # handled (moved/removed), never re-fires forever
}

@test "--dry-run escalates NOTHING (classify-only)" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep --dry-run
  [ "$status" -eq 0 ]
  not_pushed
  [ "$(n_alarms)" -eq 0 ]
  printf '%s' "$output" | grep -qi 'WOULD-ESCALATE'
}

# ── COST BOUNDING (2026-07-25) — the sweep was 96-99% of every `cc-reaper --reap` tick (52.8s, grown to
# 145s at 58 boxes / 2006 unacked lines, against a 300s launchd interval). These pin the bound so it
# cannot silently regress: the load GROWS, so an O(forks-per-message) or O(probes-per-box) shape here
# comes back as a reaper that cannot finish inside its own interval. ──────────────────────────────────

# an aged message into an ARBITRARY box (msg_aged only ever writes U's)
msg_aged_to() { # <uuid> <age-s> <from>
  local ts; ts="$(date -u -r "$((NOW - $2))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-$2))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [%s] a message\n' "$ts" "$3" >> "$CC_MAILBOX_DIR/$1.md"
}
# a fake it2 that reports <uuids…> live and COUNTS its own invocations into $BATS_TEST_TMPDIR/it2.calls
fake_it2() {
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2"
  { printf '#!/bin/bash\n'
    printf 'printf x >> "%s/it2.calls"\n' "$BATS_TEST_TMPDIR"
    printf 'jq -nc --args '\''[$ARGS.positional[] | {id: .}]'\'' %s\n' "$*"
  } > "$CC_INBOX_GUARD_IT2"; chmod +x "$CC_INBOX_GUARD_IT2"
  unset CC_INBOX_GUARD_LIVE_UUIDS
}
it2_calls() { local f="$BATS_TEST_TMPDIR/it2.calls"; [ -f "$f" ] && wc -c < "$f" | tr -d ' ' || echo 0; }

@test "P1: the LAST pane in the it2 list still reads LIVE (a stripped trailing \\n would kill it)" {
  # the pane list is memoized as one newline-bracketed blob; if the trailing newline is lost, the
  # final id is unmatchable and exactly one LIVE session per sweep is mis-escalated as a DEAD pane.
  msg_aged 3600 peer
  fake_it2 "OTHER-0000-0000-0000-000000000000" "$U"    # U is LAST
  run "$G" sweep
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'LIVE session'
  refute_match "$output" 'NOW-DEAD'
}

@test "P1: it2 is probed ONCE per sweep, not once per overdue inbox" {
  local B="BBBBBBBB-1111-2222-3333-444444444444" C="CCCCCCCC-1111-2222-3333-444444444444"
  msg_aged_to "$U" 3600 peer; msg_aged_to "$B" 3600 peer; msg_aged_to "$C" 3600 peer
  fake_it2 "$U"                      # all three overdue; B and C are dead
  run "$G" sweep
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'ESCALATE')" -eq 3 ]   # all three still classified
  [ "$(it2_calls)" -eq 1 ]                                    # …off ONE probe
}

@test "P1: an unreadable it2 is probed ONCE too (INDETERMINATE is memoized, still fail-loud)" {
  local B="BBBBBBBB-1111-2222-3333-444444444444"
  msg_aged_to "$U" 3600 peer; msg_aged_to "$B" 3600 peer
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2"
  { printf '#!/bin/bash\n'; printf 'printf x >> "%s/it2.calls"\nexit 1\n' "$BATS_TEST_TMPDIR"; } > "$CC_INBOX_GUARD_IT2"
  chmod +x "$CC_INBOX_GUARD_IT2"; unset CC_INBOX_GUARD_LIVE_UUIDS
  run "$G" sweep
  [ "$(printf '%s' "$output" | grep -c 'INDETERMINATE')" -eq 2 ]   # both still fail loud
  [ "$(it2_calls)" -eq 1 ]
}

# PATH stubs that COUNT the per-message fork shapes (sed to read/split a line, date to epoch it) and
# delegate to the real tools. Counting forks, not seconds: a wall-clock bound is load-dependent, and a
# 3000-line box sat close enough to any tolerable threshold to pass with the per-message shape intact.
fork_stubs() {
  local d="$BATS_TEST_TMPDIR/stub" rs rd; mkdir -p "$d"
  rs="$(command -v sed)"; rd="$(command -v date)"
  printf '#!/bin/bash\nprintf x >> "%s/forks"\nexec %s "$@"\n' "$BATS_TEST_TMPDIR" "$rs" > "$d/sed"
  printf '#!/bin/bash\nprintf x >> "%s/forks"\nexec %s "$@"\n' "$BATS_TEST_TMPDIR" "$rd" > "$d/date"
  chmod +x "$d/sed" "$d/date"; printf '%s' "$d"
}
forks() { local f="$BATS_TEST_TMPDIR/forks"; [ -f "$f" ] && wc -c < "$f" | tr -d ' ' || echo 0; }

@test "P2: a 3000-message unacked window is scanned in one pass, not one fork per message" {
  # measured: the per-message loop spends 12000 sed+date forks (and 97s) on exactly this input; the
  # single awk pass spends 0. 50 is far above anything the one-pass shape can reach and 240x below
  # what the per-message one costs, so this cannot flake in either direction.
  local i; i=0
  while [ "$i" -lt 3000 ]; do printf '2026-07-19T04:08:27-0700 [peer] msg %s\n' "$i" >> "$CC_MAILBOX_DIR/$U.md"; i=$((i+1)); done
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  local stub old_path n; stub="$(fork_stubs)"; old_path="$PATH"
  PATH="$stub:$PATH"
  run "$G" sweep
  n="$(forks)"
  PATH="$old_path"
  [ "$status" -eq 0 ]
  pushed                    # still the correct verdict…
  [ "$n" -lt 50 ]           # …off a bounded number of processes
}

@test "P2: a ts awk declines still gets the ORIGINAL date-backed verdict (FB fallback lives)" {
  # 2026-02-30 is out of range for the fast path but `date` NORMALISES it to Mar 2 — an ancient,
  # overdue message. If the fallback is dropped and the line silently scored age=0, this goes quiet.
  printf '2026-02-30T00:00:00+0000 [peer] normalised by date, not by awk\n' > "$CC_MAILBOX_DIR/$U.md"
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  pushed
}

@test "P2: a pre-1970 ts keeps the OLD (date-rejects → treat as now) verdict, not new arithmetic" {
  # BSD date REJECTS 1900-01-01, so the old path scored it age=0 → no alarm. Arithmetic would make it
  # ~126 years overdue and alarm. The fast path must decline ep<0 and let `date` decide.
  printf '1900-01-01T00:00:00+0000 [peer] date rejects this\n' > "$CC_MAILBOX_DIR/$U.md"
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  not_pushed
  printf '%s' "$output" | grep -q 'within deadline'
}

@test "P4: mail that lands DURING a sweep still gets its own alarm (not pre-damped)" {
  # escalate used to RE-READ the cursors instead of using the ones the verdict was computed from, so a
  # message appended mid-sweep moved the damp key forward onto a state no verdict had ever been raised
  # for — and the next sweep saw a matching marker and went quiet. The mail is never lost, but its
  # alarm is, which is the same failure for a fail-loud backstop.
  #
  # it2 runs BETWEEN the scan and the escalate, so the fake it2 is a deterministic stand-in for a
  # concurrent producer. It appends exactly once, so sweep 2 sees a genuinely new, never-alarmed line.
  msg_aged 3600 peer                                  # line 1
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2"
  { printf '#!/bin/bash\n'
    printf 'if [ ! -f "%s/appended" ]; then\n' "$BATS_TEST_TMPDIR"
    printf '  printf "2026-07-19T04:08:27-0700 [peer] arrived mid-sweep\\n" >> "%s/%s.md"\n' "$CC_MAILBOX_DIR" "$U"
    printf '  : > "%s/appended"\nfi\n' "$BATS_TEST_TMPDIR"
    printf 'jq -nc --args '\''[$ARGS.positional[] | {id: .}]'\'' %s\n' "$U"
  } > "$CC_INBOX_GUARD_IT2"; chmod +x "$CC_INBOX_GUARD_IT2"
  unset CC_INBOX_GUARD_LIVE_UUIDS

  "$G" sweep >/dev/null                               # alarms for line 1; line 2 lands mid-sweep
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$U.md")" -eq 2 ]    # the injection really happened
  : > "$PUSHLOG"
  run "$G" sweep                                      # line 2 has never been alarmed for
  pushed
}
