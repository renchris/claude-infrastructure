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

# CHANGED 2026-08-09 — was `-eq 3`, the class 404c832a retired for activation-watch (whose count had
# been bumped 7 → 14 → 18 → 26 by four commits that did nothing but ADD checks). An exact ok-count is
# a tripwire on the growth of the very suite it guards — the NUMBER, not a defect, is what gets
# "fixed" — and it never asserted the premise in its own name: `-eq 3` conflates "non-vacuous" with
# "exactly this many", so a reporter claiming 6 passed while rendering 3 `ok` lines sails through.
# What survives is that premise, as the two independent things that make a suite non-vacuous:
#   FLOOR — a DOWNWARD ratchet. Growth passes freely; a DELETED check reds, and lowering the floor has
#           to be a deliberate edit (memory: downward-ratchet-catches-the-over-scoped-marker).
#   TALLY — the summary's own `N passed` must equal the `  ok ` lines it actually rendered — the
#           vacuous-pass class this test is named for (memory: claimed-outcome-vs-checked-outcome).
# The count is environment-stable: 3 unconditional okp/badp sites, each emitting exactly one line.
@test "selftest passes, is non-vacuous (floor), and its tally matches what it rendered" {
  floor=3                         # raise when checks are added; LOWERING it is a deliberate act
  run "$G" --selftest
  [ "$status" -eq 0 ]
  # `|| true` normalizes grep's rc-1-on-zero-matches, which would otherwise abort the test HERE and
  # never reach the floor. It swallows no verdict — the count is data, the assertions are the verdict.
  ok_lines="$(printf '%s' "$output" | grep -c '^  ok ' || true)"
  claimed="$(printf '%s' "$output" | sed -n 's/^cc-inbox-guard --selftest: \([0-9][0-9]*\) passed,.*/\1/p')"
  [ "$ok_lines" -ge "$floor" ]
  # Two statements, never `[ -n "$claimed" ] && [ ... ]`: in an `&&` list set -e sees only the command
  # after the FINAL `&&`, so a short-circuit on the left half is ABSORBED and an unparseable summary
  # would pass vacuously (tests/bats-assert-liveness.bats classifies that shape `and-absorbed`).
  [ -n "$claimed" ]
  [ "$claimed" = "$ok_lines" ]
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

# REWRITTEN 2026-08-24 (backlog 4218bdea6601). This test used to assert ONE HALF of the invariant —
# `not_pushed` plus a `within deadline` line — on a premise written into its own name: *"BSD date
# REJECTS 1900-01-01, so the old path scored it age=0"*. That premise is a fact about the RUNNER's
# `date`, not about this guard, and it is false wherever `date` accepts a pre-1970 stamp: GNU
# `date -d '1900-01-01T00:00:00+0000' +%s` returns -2208988800, so iso_epoch yields a negative epoch,
# age comes out ~126 years, and the line escalates. That escalation is the CORRECT deferral — it is
# exactly what the ORIGINAL date-backed path produces on such a box — and the old assertions scored it
# as a defect. The suite went red at 5077964c34cf without a line of bin/cc-inbox-guard changing.
#
# What the guard actually promises here is DEFERRAL, not silence: `scan_window`'s awk declines ep<0
# (bin/cc-inbox-guard:350-353) so the original `date`-backed path decides, whatever it decides. So the
# two things asserted below are the two halves of that promise, and both hold on either kind of date:
#   MECHANISM — `date` is consulted with THIS timestamp. Mutation M5 (let the fast path do pre-1970
#               arithmetic) forks no date for the line at all, so the argv log stays empty and this
#               reds — which is the RED-proof the old shape only had by accident of the runner.
#               Unambiguous because iso_epoch is the only caller in the sweep that hands `date` an
#               arbitrary ISO string; now()/utc()/stamp() pass format strings only.
#   AGREEMENT — the sweep's verdict is the one THAT epoch implies, computed here from `date` rather
#               than restated as a constant. Rejects ⇒ ep=0 ⇒ substituted with now ⇒ within deadline;
#               accepts ⇒ ~126y overdue ⇒ escalates. Either way the guard may not disagree with the
#               path it just deferred to.
@test "P2: a pre-1970 ts is DECLINED by the fast path and decided by date, not by new arithmetic" {
  local TS='1900-01-01T00:00:00+0000'
  printf '%s [peer] the fast path must not score this itself\n' "$TS" > "$CC_MAILBOX_DIR/$U.md"
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"

  # a `date` stub that RECORDS its argv and delegates to the real one — same shape as fork_stubs()
  local d="$BATS_TEST_TMPDIR/datestub" rd log old_path
  log="$BATS_TEST_TMPDIR/date.args"
  mkdir -p "$d"; rd="$(command -v date)"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\nexec %s "$@"\n' "$log" "$rd" > "$d/date"
  chmod +x "$d/date"

  old_path="$PATH"
  PATH="$d:$PATH"
  run "$G" sweep
  PATH="$old_path"
  [ "$status" -eq 0 ]

  # MECHANISM. `|| true` normalizes grep's rc-1-on-zero-matches so the count is data and the `[ ]` is
  # the verdict (same reason as the selftest floor above); a zero count is precisely the M5 failure.
  [ "$(grep -c -- "$TS" "$log" 2>/dev/null || true)" -ge 1 ]

  # AGREEMENT. iso_epoch's own two-step resolve (BSD `-j -f`, then GNU `-d`, then 0), run here against
  # the REAL date so this arm reads the box rather than trusting the subject's copy of the answer.
  local ep
  ep="$(command date -j -f '%Y-%m-%dT%H:%M:%S%z' "$TS" +%s 2>/dev/null \
        || command date -d "$TS" +%s 2>/dev/null || printf 0)"
  if [ "${ep:-0}" = 0 ]; then
    not_pushed
    printf '%s' "$output" | grep -q 'within deadline'
  else
    pushed
  fi
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

# ── the reconcile disable-seam: set-but-EMPTY must genuinely disable the fork ──────────────────
#
# Staged into a TMP bin/ so the auto-resolve fall-through is OBSERVABLE. Resolution order is
# "$_bd/cc-reconcile" first, and _bd is the guard's own directory — running the repo copy would
# always resolve the repo's REAL cc-reconcile (which forks `it2 session list --json` and, against
# a wedged iTerm2, stalls the sweep). Copying the guard beside a MARKER-WRITING fixture makes
# "did it fall through?" a file-existence question instead of a timing one.
_stage_guard_with_fixture_reconcile() {  # → echoes the staged guard path
  local d="$BATS_TEST_TMPDIR/stage"
  mkdir -p "$d/bin" "$d/hooks/lib"
  cp "$G" "$d/bin/cc-inbox-guard"
  cp "$REPO/hooks/lib/mailbox-pending.sh" "$d/hooks/lib/mailbox-pending.sh"
  { printf '#!/bin/bash\n'; printf ': > "%s/reconcile.ran"\n' "$BATS_TEST_TMPDIR"; } > "$d/bin/cc-reconcile"
  chmod +x "$d/bin/cc-inbox-guard" "$d/bin/cc-reconcile"
  printf '%s' "$d/bin/cc-inbox-guard"
}

@test "reconcile seam: UNSET auto-resolves and FORKS (positive control for the pin below)" {
  local g; g="$(_stage_guard_with_fixture_reconcile)"
  msg_aged 3600 peer
  unset CC_INBOX_GUARD_RECONCILE_BIN
  run "$g" sweep
  [ "$status" -eq 0 ]
  # Without this control, the pin below could pass because the fork never happens for ANY reason.
  [ -f "$BATS_TEST_TMPDIR/reconcile.ran" ] || false
}

@test "reconcile seam: set-but-EMPTY genuinely DISABLES the fork (no fall-through to auto-resolve)" {
  local g; g="$(_stage_guard_with_fixture_reconcile)"
  msg_aged 3600 peer
  export CC_INBOX_GUARD_RECONCILE_BIN=""
  run "$g" sweep
  [ "$status" -eq 0 ]
  # Pre-fix this file EXISTED: `${VAR:-}` read set-empty as unset, fell into the auto-resolve loop
  # and ran cc-reconcile — the fork that hung this whole suite (and every full-scope landing gate)
  # against a wedged it2 API. RED-proven 2026-07-26 by reverting the resolution block.
  [ ! -f "$BATS_TEST_TMPDIR/reconcile.ran" ] || false
}

# ── NAME-KEYED boxes: cc-notify --role writes the role file's value verbatim as the mailbox key ────
@test "a NAME-keyed inbox with overdue unacked mail ESCALATES (it used to be skipped entirely)" {
  local N="desk-drive"
  local ts; ts="$(date -u -r "$((NOW - 3600))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-3600))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [reaper] crashed pane needs triage\n' "$ts" > "$CC_MAILBOX_DIR/$N.md"
  run "$G" sweep
  [ "$status" -eq 0 ]
  pushed
  [ "$(n_alarms)" -ge 1 ]
  run grep -q "$N" "$PUSHLOG"
  [ "$status" -eq 0 ]
}

@test "a NAME-keyed box is INDETERMINATE, never reported as a dead pane (it2 lists uuids, not names)" {
  local N="desk-drive"
  local ts; ts="$(date -u -r "$((NOW - 3600))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-3600))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [reaper] triage me\n' "$ts" > "$CC_MAILBOX_DIR/$N.md"
  run "$G" sweep
  echo "$output" | grep -q 'INDETERMINATE'
  echo "$output" | grep -q 'NAME-keyed box'
  run grep -q 'NOW-DEAD pane' <<<"$output"
  [ "$status" -ne 0 ]
}

@test "a CONSUMED name-keyed box does NOT escalate — the cursors work for name keys too" {
  local N="desk-drive"
  local ts; ts="$(date -u -r "$((NOW - 3600))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-3600))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [reaper] triage me\n' "$ts" > "$CC_MAILBOX_DIR/$N.md"
  printf '1\n' > "$CC_MAILBOX_DIR/$N.seen"; printf '1\n' > "$CC_MAILBOX_DIR/$N.acked"
  run "$G" sweep
  [ "$status" -eq 0 ]
  run grep -q "$N" "$PUSHLOG"
  [ "$status" -ne 0 ]
}

@test "path-unsafe basenames are still refused (traversal / dotfiles never become mailbox keys)" {
  local ts; ts="$(date -u -r "$((NOW - 3600))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-3600))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [reaper] hidden\n' "$ts" > "$CC_MAILBOX_DIR/.hidden.md"
  printf '%s [reaper] spaced\n' "$ts" > "$CC_MAILBOX_DIR/bad name.md"
  run "$G" sweep
  [ "$status" -eq 0 ]
  run grep -qE '(\.hidden|bad name)' "$PUSHLOG"
  [ "$status" -ne 0 ]
}

# ── E13 · a HEADLESS owner's liveness comes from the beat, never from the pane list ────────────────
# `it2 session list` enumerates PANES, so for a pane-less session it can only ever MISS — and a miss
# is not absence. Before E13 every headless box with overdue mail therefore landed on the
# INDETERMINATE arm and paged the operator with a cause about a pane that never existed
# (docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md §4 A4, edit E13).
#
# THE KEY TRAP THESE PIN: the inbox is keyed on the PANE id (`hdl-<16hex>`), the beat on the SESSION
# id, and for a headless session those DIFFER. Every fixture below therefore uses a sessionId that is
# NOT the inbox key, so a `cb_last_beat "$u"` that skipped the registry join would read as a no-op.
HDL="hdl-0123456789abcdef"
HSID="9f9f9f9f-1111-2222-3333-aaaaaaaaaaaa"

hdl_env() {  # arm the registry + beat seams (both default to $HOME — never let a test touch those)
  export CC_INBOX_GUARD_REG_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  export CC_BEAT_NOW="$NOW"
  mkdir -p "$CC_INBOX_GUARD_REG_DIR" "$CC_BEAT_DIR"
}
reg_row() {  # <inbox key> <surface> <sessionId>
  printf '{"paneUUID":"%s","name":"hb","cwd":"/tmp","account":"a","pid":1,"startedAt":0,"sessionId":"%s","surface":"%s","lstart":""}\n' \
    "$1" "$3" "$2" > "$CC_INBOX_GUARD_REG_DIR/$1.json"
}
beat_row() { # <sid> <age-seconds>
  printf '{"sid":"%s","t":%s,"who":"auto"}\n' "$1" "$(( NOW - $2 ))" > "$CC_BEAT_DIR/$1.json"
}
overdue_for() { # <inbox key> — one unacked line, an hour past the 600s deadline
  local ts; ts="$(date -u -r "$((NOW - 3600))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-3600))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [reaper] triage me\n' "$ts" > "$CC_MAILBOX_DIR/$1.md"
}
# ANTI-VACUITY: assert the fixture really is the population under test before asserting anything about
# the verdict. Without this, a renamed field or a mis-set seam makes every case below pass over a box
# the sweep classified by some entirely different route.
assert_headless_fixture() { # <inbox key> <sid>
  [ "$(jq -r '.surface' "$CC_INBOX_GUARD_REG_DIR/$1.json")" = headless ] || false
  [ "$(jq -r '.sessionId' "$CC_INBOX_GUARD_REG_DIR/$1.json")" = "$2" ] || false
  [ "$1" != "$2" ] || false                                  # the join must be doing real work
  run bash -c 'case "$1" in [0-9A-Fa-f]*-*-*-*-*) exit 0;; *) exit 1;; esac' _ "$1"
  [ "$status" -ne 0 ] || false                               # …and the key must NOT be pane-shaped
}

@test "E13: a beat-fresh HEADLESS owner reads LIVE, not INDETERMINATE (no fabricated pane cause)" {
  hdl_env; reg_row "$HDL" headless "$HSID"; beat_row "$HSID" 30; overdue_for "$HDL"
  assert_headless_fixture "$HDL" "$HSID"
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$HDL"           # the sweep actually reached this box
  echo "$output" | grep -q 'LIVE session'
  refute_match "$output" 'INDETERMINATE'
  refute_match "$output" 'NOW-DEAD pane'
}

@test "E13: the beat is joined through the row's sessionId — a beat under the INBOX key is not read" {
  hdl_env; reg_row "$HDL" headless "$HSID"; overdue_for "$HDL"
  beat_row "$HDL" 30                          # fresh, but filed under the PANE key — the wrong join
  beat_row "$HSID" 4000                       # the session's own beat is stale
  assert_headless_fixture "$HDL" "$HSID"
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INDETERMINATE'
  refute_match "$output" 'LIVE session'
}

@test "E13: a beat-STALE headless owner still escalates, and its cause names HEADLESS not NAME-keyed" {
  hdl_env; reg_row "$HDL" headless "$HSID"; overdue_for "$HDL"
  beat_row "$HSID" 4000                       # this session lapsed…
  beat_row "someone-else" 30                  # …while the beat WORLD is demonstrably alive
  assert_headless_fixture "$HDL" "$HSID"
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INDETERMINATE'
  echo "$output" | grep -q 'HEADLESS owner'
  refute_match "$output" 'NAME-keyed box'
  pushed
}

@test "E13: a PANE row is NOT rescued by a fresh beat — the surface gate holds the population" {
  hdl_env; reg_row "$U" pane "$HSID"; beat_row "$HSID" 30; overdue_for "$U"
  [ "$(jq -r '.surface' "$CC_INBOX_GUARD_REG_DIR/$U.json")" = pane ] || false
  # it2 UNREADABLE on purpose, so owner_liveness actually REACHES the second E13 site. That is the
  # only path on which a canonical-shaped row consults the beat at all: with a readable pane list the
  # row is adjudicated and returns before the gate. An earlier version of this case used the default
  # `[]` stub, and its surface mutant (M3) came back GREEN — the case pinned nothing, because the
  # population it meant to exclude was already excluded one branch earlier.
  export CC_INBOX_GUARD_IT2=/nonexistent/it2
  unset CC_INBOX_GUARD_LIVE_UUIDS
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INDETERMINATE'
  refute_match "$output" 'LIVE session'
}

@test "E13: a NAME-keyed box with no registry row keeps its original INDETERMINATE cause" {
  hdl_env; overdue_for "desk-drive"
  [ ! -f "$CC_INBOX_GUARD_REG_DIR/desk-drive.json" ] || false
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INDETERMINATE'
  echo "$output" | grep -q 'NAME-keyed box'
  refute_match "$output" 'HEADLESS owner'
}

@test "E13: a stale beat WORLD is not live even under a generous per-session bound (existence gate)" {
  hdl_env; reg_row "$HDL" headless "$HSID"; overdue_for "$HDL"
  beat_row "$HSID" 3000                       # inside the generous bound below…
  export CC_INBOX_GUARD_BEAT_MAX_S=86400      # …but no beat ANYWHERE is fresh: the producer is gone
  assert_headless_fixture "$HDL" "$HSID"
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'INDETERMINATE'
  refute_match "$output" 'LIVE session'
}

# ── TRUNCATION LEGIBILITY + STARVATION ORDER ────────────────────────────────────────────────────
# This sweep is a ride-along under cc-reaper's 60s bound (cc-reaper:1909) and is cut ~96% of the
# time — measured 2026-08-25: `bound-fired inbox-guard` fired on 123 of 123 ticks in 24h, and only
# 65 of 1621 sweeps in the log's 12-day span ever reached the summary. Under a FIXED glob order that
# cut is a PERMANENT exclusion of a fixed suffix, not graceful degradation: scored against an
# isolated sweep of the same store, 142 of the 362 boxes that must escalate were not examined once
# in 24h. Two guarantees follow, and the first is what makes the second checkable.
mkbox() {   # $1 = key — a box holding one 2h-old unacked message, i.e. always overdue
  local ts
  ts="$(date -u -r "$((NOW - 7200))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW - 7200))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [reaper] undelivered\n' "$ts" > "$CC_MAILBOX_DIR/$1.md"
}

@test "W1: the worklist size is ANNOUNCED BEFORE the loop, so a cut sweep is arithmetic not silence" {
  mkbox aaa; mkbox bbb; mkbox ccc
  run "$G" sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'worklist 3 box(es)'
  # ORDER OF EMISSION is the property under test, not mere presence: the summary at the end of
  # sweep() is the FIRST thing a SIGTERM eats, which is why the count has to precede the work.
  # Separate statements, never an `&&` list — set -e sees only the command after the final `&&`.
  ann="$(printf '%s\n' "$output" | grep -n 'worklist 3 box(es)' | head -1 | cut -d: -f1)"
  first="$(printf '%s\n' "$output" | grep -nE '^  (ESCALATE|keep|ok) ' | head -1 | cut -d: -f1)"
  [ -n "$ann" ]
  [ -n "$first" ]
  [ "$ann" -lt "$first" ]
  # a COMPLETED sweep still says so, so announce and summary are directly comparable in the log
  echo "$output" | grep -q 'sweep done — all 3 box(es) examined'
}

@test "W2: the worklist is ordered OLDEST-ESCALATED FIRST, not lexicographically" {
  # The fixture INVERTS marker age against lexicographic order, so the two candidate orderings are
  # exact REVERSES of one another. An ordering test whose two candidate orders agree proves nothing.
  for k in aaa bbb ccc ddd eee; do mkbox "$k"; done
  mkdir -p "$CC_INBOX_GUARD_STATE_DIR"
  n=0
  for k in eee ddd ccc bbb aaa; do            # eee oldest … aaa newest
    n=$((n + 1))
    printf '0:1' > "$CC_INBOX_GUARD_STATE_DIR/$k.escalated"
    touch -t "202${n}01010000" "$CC_INBOX_GUARD_STATE_DIR/$k.escalated"
  done
  run "$G" sweep
  [ "$status" -eq 0 ]
  order="$(printf '%s\n' "$output" | grep -oE '^  (ESCALATE|keep|ok) +[^ ]+' | awk '{print $2}' | tr '\n' ' ')"
  [ "$order" = "eee ddd ccc bbb aaa " ]
  # stated explicitly, so a regression to the pre-fix order is unambiguous rather than merely "not equal"
  [ "$order" != "aaa bbb ccc ddd eee " ]
}

# ── W3 (recycle #228): the summary's escalation count MERGED two arms that mean opposite things ────
# escalate() returns early on a damped repeat, but all four call sites incremented n_esc regardless,
# so `sweep done — N escalation(s)` reported "escalated" for boxes that paged nobody. Measured on the
# live reaper log: 67 summaries, all in a stable 211-225 band; an isolated dry-run over the real
# 782-box store scored 360 of which 357 were damped and 3 real. Assertions use `grep -c … -eq N`
# rather than `grep -q`: under pipefail a `producer | grep -q` fails on the input it just matched.
@test "W3: a REAL escalation is counted as an escalation, not damped" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'examined, 1 escalation(s), damped=0')" -eq 1 ]
}

@test "W3: a DAMPED repeat is counted as damped, NOT as an escalation" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  "$G" sweep >/dev/null          # sweep 1 escalates for real and writes the (acked:lines) marker
  run "$G" sweep                 # sweep 2 sees the same key → damped, and must say so
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'examined, 0 escalation(s), damped=1')" -eq 1 ]
}

@test "W3: escalations and damped PARTITION the boxes that reached escalate()" {
  # Two arms in ONE sweep, so this cannot pass by both counters tracking the same population.
  mkbox aaa; mkbox bbb; mkbox ccc
  mkdir -p "$CC_INBOX_GUARD_STATE_DIR"
  for k in aaa bbb; do printf '0:1' > "$CC_INBOX_GUARD_STATE_DIR/$k.escalated"; done
  run "$G" sweep
  [ "$status" -eq 0 ]
  e="$(printf '%s\n' "$output" | grep -oE 'examined, [0-9]+ escalation' | grep -oE '^examined, [0-9]+' | grep -oE '[0-9]+')"
  d="$(printf '%s\n' "$output" | grep -oE 'damped=[0-9]+' | grep -oE '[0-9]+')"
  [ "$e" = "1" ]
  [ "$d" = "2" ]
  [ "$((e + d))" -eq 3 ]         # …and the parts sum to the worklist (control 24)
}

@test "W3: the cursor-past-EOF call site attributes its own damped repeat (site 2 of 2)" {
  # The F11 site increments a DIFFERENT n_esc line from the liveness arms, so a fix applied at one
  # site and not the other passes every test above. One assertion per SITE, deliberately.
  msg_aged 60 peer
  printf '9\n' > "$CC_MAILBOX_DIR/$U.seen"   # .seen=9 > 1 line → rotated/truncated → F11 escalates
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  "$G" sweep >/dev/null
  run "$G" sweep
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'examined, 0 escalation(s), damped=1')" -eq 1 ]
}

# ── C1–C4: THE CLOCK IS A SENSOR, AND ITS FAILURE VALUE WAS ITS HEALTHIEST READING ────────────────
# now() was `${CC_INBOX_GUARD_NOW:-$(date +%s 2>/dev/null || echo 0)}`. An unreadable clock therefore
# scored 0, every `now - ep` came out negative, every negative age was clamped to 0 — and `oldest 0s`
# is EXACTLY what a message that arrived this instant renders as. Nothing downstream could tell the
# two apart. Measured against the unfixed subject: ONE fixture, ONE variable moved, and the verdict
# inverted from `ESCALATE … the target died with mail undelivered` (1 alarm, phone fired) to
# `ok … 1 unacked but within deadline (oldest 0s)` (0 alarms, nothing phoned) at rc 0 both times.
#
# Neither of this file's two anti-silence arms can see it, and the reason is structural: the worklist
# announce and `sweep done — all N box(es) examined` are BOTH keyed on INCOMPLETENESS, and a dead
# clock produces a sweep that is perfectly COMPLETE. The subsystem whose entire contract is fail-loud
# reports its healthiest possible line while every overdue box in the fleet goes unpaged.
#
# The law this restores is the one owner_liveness already states and enforces three times over its
# own oracles (`:258-260`, `:268-271`, `:292-296`): an unresolvable sensor may not fabricate a
# verdict. It may not BREACH and it may not CLEAR — it abstains, loudly, and every sentence
# downstream stops claiming a comparison it never made.
broken_clock_path() {   # a PATH prefix in which date(1) fails and nothing else changes
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  { printf '#!/bin/bash\n'; printf 'exit 1\n'; } > "$BATS_TEST_TMPDIR/shim/date"
  chmod +x "$BATS_TEST_TMPDIR/shim/date"
  printf '%s' "$BATS_TEST_TMPDIR/shim:$PATH"
}

@test "C1: an UNREADABLE clock neither CLEARS nor ESCALATES an overdue box — it is UNSCORED" {
  mkbox aaa
  run env -u CC_INBOX_GUARD_NOW PATH="$(broken_clock_path)" "$G" sweep
  [ "$status" -eq 0 ]
  # may not CLEAR — the unfixed subject scored this exact box `ok … within deadline (oldest 0s)`
  [ "$(printf '%s\n' "$output" | grep -c 'within deadline')" -eq 0 ]
  # may not BREACH either — an unreadable sensor is not evidence that a deadline was missed
  [ "$(printf '%s\n' "$output" | grep -c 'ESCALATE')" -eq 0 ]
  # ANCHORED to the per-box line. The announce line legitimately contains the word UNSCORED too (it
  # says what the sweep is about to do), so a bare token count answers a different question than the
  # one being asked — the failure mode that reds C4's negative control if you leave it unanchored.
  [ "$(printf '%s\n' "$output" | grep -cE '^  UNSCORED aaa ')" -eq 1 ]
  not_pushed
  [ "$(n_alarms)" -eq 0 ]
}

@test "C2: the clock verdict is ANNOUNCED BEFORE the worklist, and the summary carries the count" {
  mkbox aaa
  run env -u CC_INBOX_GUARD_NOW PATH="$(broken_clock_path)" "$G" sweep
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'clock=UNREADABLE')" -eq 1 ]
  # ORDER, not mere presence. The summary is the first thing a SIGTERM eats — which is precisely why
  # the worklist size is announced BEFORE the loop — so the clock verdict has to precede it too.
  a="$(printf '%s\n' "$output" | grep -n 'clock=UNREADABLE' | head -1 | cut -d: -f1)"
  w="$(printf '%s\n' "$output" | grep -n 'worklist' | head -1 | cut -d: -f1)"
  [ -n "$a" ]
  [ -n "$w" ]
  [ "$a" -lt "$w" ]
  [ "$(printf '%s\n' "$output" | grep -c 'unscored=1')" -eq 1 ]
}

@test "C3: a NON-NUMERIC CC_INBOX_GUARD_NOW is UNREADABLE, not silently coerced to 0" {
  # `:-` only catches unset/empty, so a garbage value reached the arithmetic verbatim and bash scored
  # it 0 — the identical silent clear, through a second door, with no failed fork anywhere.
  mkbox aaa
  export CC_INBOX_GUARD_NOW="not-a-clock"
  run "$G" sweep
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'within deadline')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'clock=UNREADABLE')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^  UNSCORED aaa ')" -eq 1 ]
}

@test "C4: the abstention is SCOPED to verdicts that needed the clock (negative control)" {
  # Without this, a fix could pass C1–C3 by unscoring the whole worklist unconditionally. A fully
  # consumed box never asks the clock anything, so it must stay silent exactly as it was.
  mkbox aaa
  printf '1\n' > "$CC_MAILBOX_DIR/aaa.seen"
  printf '1\n' > "$CC_MAILBOX_DIR/aaa.acked"
  run env -u CC_INBOX_GUARD_NOW PATH="$(broken_clock_path)" "$G" sweep
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^  UNSCORED ')" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'clock=UNREADABLE')" -eq 1 ]   # the announce still fires
  [ "$(printf '%s\n' "$output" | grep -c 'unscored=0')" -eq 1 ]
}
