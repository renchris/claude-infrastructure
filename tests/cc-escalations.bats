#!/usr/bin/env bats
# cc-escalations (D5) — the explicit drain + operator ack over the five escalation record stores.
#
# The load-bearing test in this file is the CROSS-CONVENTION one: an ack is only worth something if
# the CONSUMER treats it as its own. So rather than re-implement autonomy-sweep's marker key here and
# assert against a copy of it, the parity test runs the REAL sweep against the SAME fixture and reads
# its collection count. A copied key can drift; a live consumer cannot (memory:
# actuator-is-the-arbiter / control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="$REPO/bin/cc-escalations"
  SWEEP="$REPO/scripts/autonomy-sweep.sh"
  T="$BATS_TEST_TMPDIR"
  # HERMETIC $HOME: every default in this CLI (and in the sweep) is a $HOME path, so a seam left
  # unexported must land inside the tmpdir rather than in the operator's live stores. The explicit
  # exports below are the real isolation; HOME is the backstop for anything either script adds later.
  export HOME="$T/home"; mkdir -p "$HOME"
  export CC_HANDOFF_ALARM_DIR="$T/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$T/announce"
  export CC_COMPLETION_RECORDS_DIR="$T/completion"
  export CC_PAGES_DIR="$T/pages"
  # The M3 dead-letter store's seam is the WRITER's own mailbox variable (handoff-fire composes
  # $CC_MAILBOX_DIR/dead-letter), so redirecting the producer redirects this reader with it. It must
  # be exported for the same reason as the other four: unexported, `list` would read the OPERATOR's
  # live dead letters and `ack --all` would MARK THEM SEEN from inside a test run.
  export CC_MAILBOX_DIR="$T/mailbox"
  export CC_SWEEP_SEEN_DIR="$T/seen"
  mkdir -p "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
           "$CC_PAGES_DIR" "$CC_SWEEP_SEEN_DIR" "$CC_MAILBOX_DIR/dead-letter"
}

# ── fixture writers (the record shapes are the FROZEN INTERFACE's, not invented here) ─────────────
handoff_alarm() { # <basename> <class> [<verdict-sidecar-token>]
  printf '{"kind":"handoff-alarm","class":"%s","pane":"P","sid":"","successor":"","detail":"d","ts":"2026-08-07T00:00:00Z"}\n' \
    "$2" > "$CC_HANDOFF_ALARM_DIR/$1"
  [ -n "${3:-}" ] && printf '%s\n' "$3" > "$CC_HANDOFF_ALARM_DIR/$1.verdict"
  return 0
}
completion_record() { # <basename> <verdict> — PRETTY-printed, exactly as completion-push writes them
  printf '{\n  "kind": "completion-push",\n  "role": "desk",\n  "verdict": "%s",\n  "ts": "2026-08-07T00:00:00Z"\n}\n' \
    "$2" > "$CC_COMPLETION_RECORDS_DIR/$1"
}
# M3 dead letter — handoff-fire's own shape: `<closing-sid>.md` holding the raw inbox body (markdown,
# NOT json — so this record exercises the push_verdict/json_field fallbacks on a non-JSON file).
dead_letter() { # <sid>
  printf '## from desk\nthe seam ruling you asked for\n' > "$CC_MAILBOX_DIR/dead-letter/$1.md"
}
# The store's EXISTENCE EVIDENCE — an append-log, deliberately NOT a record (R4).
dead_letter_ran() { # <sid> <pending>
  printf '2026-08-13T00:00:00Z terminal-close sid=%s pending=%s\n' "$1" "${2:-2}" \
    >> "$CC_MAILBOX_DIR/dead-letter/.ran"
}

# Full seam surface for a REAL autonomy-sweep run against this fixture. ⚠️ Every dir the sweep can
# DELETE from must be redirected: it age-reaps six event dirs, and an unexported one makes the suite
# a reaper against LIVE state (that regression is why tests/autonomy-sweep.bats carries the same
# warning). CC_DECIDE_BIN/CC_BACKLOG_BIN point at a nonexistent path on purpose — resolve_bin returns
# empty for a non-executable override, so the expire-sweep branch is skipped and no live ledger is
# touched. CC_SWEEP_OS_CHANNEL=off keeps Notification Center out of a test run.
run_sweep() {
  env CC_PAGES_DIR="$CC_PAGES_DIR" \
      CC_ANNOUNCE_ALARM_DIR="$CC_ANNOUNCE_ALARM_DIR" \
      CC_COMPLETION_RECORDS_DIR="$CC_COMPLETION_RECORDS_DIR" \
      CC_SWEEP_SEEN_DIR="$CC_SWEEP_SEEN_DIR" \
      CC_DECISIONS_DIR="$T/decisions" \
      CC_ROLES_DIR="$T/roles" \
      CC_IDL="$T/idl.jsonl" \
      CC_COMMS_ALARM_DIR="$T/comms-alarms" \
      CC_PUSH_RECORDS_DIR="$T/push-records" \
      CC_TEARDOWN_RECORDS_DIR="$T/cc-teardown" \
      CC_INBOX_GUARD_STATE_DIR="$T/inbox-guard" \
      CC_MAILBOX_DIR="$T/mailbox" \
      CC_DECIDE_BIN="$T/no-such-decide" \
      CC_BACKLOG_BIN="$T/no-such-backlog" \
      CC_SWEEP_OS_CHANNEL=off \
      HOME="$HOME" \
      "$SWEEP" >/dev/null 2>&1
}
swept() { tail -1 "$T/idl.jsonl" | jq -r "$1"; }   # <jq-filter> over the sweep's last IDL row

@test "list: one row per record, class per store (handoff field · announce prefix · page)" {
  handoff_alarm alarm-h.json husk-pane refused-rc3
  printf '{"kind":"announce-alarm"}\n'   > "$CC_ANNOUNCE_ALARM_DIR/announce-alarm-1.json"
  printf '{"kind":"announce-degrade"}\n' > "$CC_ANNOUNCE_ALARM_DIR/announce-degrade-1.json"
  completion_record push-stuck.json "push-failed(cc-announce rc=5)"
  : > "$CC_PAGES_DIR/p1.page"
  run "$BIN" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'alarm-h\.json .*husk-pane'                    # class from the record FIELD
  echo "$output" | grep -q 'announce-alarm-1\.json .*announce-alarm'      # class from the FILENAME prefix
  echo "$output" | grep -q 'announce-degrade-1\.json .*announce-degrade'  # …and the other prefix
  echo "$output" | grep -q 'push-stuck\.json .*push-failed'
  echo "$output" | grep -q 'p1\.page .*page'
  echo "$output" | grep -q 'alarm-h\.json .*refused-rc3'                  # verdict SIDECAR rendered
  echo "$output" | grep -q 'push-stuck\.json .*push-failed(cc-announce rc=5)'  # …else the own field
}

@test "list: a VERIFIED completion record is excluded; a non-verified one is listed (control)" {
  # The exclusion is the whole point of reading this store — a verified push completed, it is not
  # outstanding. Both records are written in ONE fixture so the control cannot pass for the wrong
  # reason (an empty store would satisfy the absence assertion by itself).
  completion_record push-ok.json   verified
  completion_record push-bad.json  "push-failed(cc-announce rc=5)"
  run "$BIN" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'push-bad\.json'                  # positive control: the stuck one IS listed
  ! echo "$output" | grep -q 'push-ok\.json' || false        # …and the verified one is NOT
}

@test "list: nothing outstanding ⇒ 'none', rc 0 (and '[]' under --json)" {
  run "$BIN" list
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  run "$BIN" list --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c .)" = "[]" ]
}

@test "list --json: parses, and carries class/verdict/seen per record" {
  handoff_alarm alarm-j.json strand-risk reached
  run "$BIN" list --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].record')"  = "alarm-j.json" ]
  [ "$(echo "$output" | jq -r '.[0].class')"   = "strand-risk" ]
  [ "$(echo "$output" | jq -r '.[0].verdict')" = "reached" ]
  [ "$(echo "$output" | jq -r '.[0].seen')"    = "false" ]
}

@test "ack <basename>: writes the literal \$SEEN_DIR/<basename>.seen marker" {
  handoff_alarm alarm-ack.json husk-pane
  [ ! -f "$CC_SWEEP_SEEN_DIR/alarm-ack.json.seen" ]          # pre-state (the assertion is not vacuous)
  run "$BIN" ack alarm-ack.json
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'acked 1 record'
  [ -f "$CC_SWEEP_SEEN_DIR/alarm-ack.json.seen" ]            # EXACT literal path
  run "$BIN" list
  echo "$output" | grep -q 'alarm-ack\.json .*yes'           # …and the seen column flips
}

@test "ack <basename>: an unknown record is exit 5, never a silent success" {
  handoff_alarm alarm-real.json husk-pane
  run "$BIN" ack alarm-nope.json
  [ "$status" -eq 5 ]
  run "$BIN" ack alarm-real.json                             # positive control: a real one works
  [ "$status" -eq 0 ]
}

# ── the FIFTH store: M3 close-path dead letters (SESSION_LIFECYCLE_V2 R-6) ───────────────────────
# Until this landed, `grep -rn 'mailbox/dead-letter'` over bin/ hooks/ scripts/ found the WRITER
# (handoff-fire.sh:selfclose_mail_disposition) and its own suite — no consumer anywhere on the tree.
# Row 3's M3 contract requires the store be "SURFACED on the operator board with existence evidence,
# NEVER a silent file", so a store nobody read was the contract's own defect. `list` is the read and
# `ack` is the off switch WITHOUT WHICH THE SURFACING WOULD BE A PERMANENT NAG — the alarm-polarity
# defect this CLI exists to prevent, so both halves are pinned here rather than only the render.
@test "list: an M3 dead letter is an outstanding record, classed mail-deadletter" {
  dead_letter 01998f3a-dead-4beef-9c21-000000000001
  dead_letter_ran 01998f3a-dead-4beef-9c21-000000000001
  run "$BIN" list
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '01998f3a-dead-4beef-9c21-000000000001\.md .*mail-deadletter'
  echo "$output" | grep -qE 'mail-deadletter .* no$'         # unseen until acked
}

@test "list: the store's .ran EVIDENCE is never a record (R4: empty-but-ran != never-ran)" {
  # Evidence alone: the store HAS run and dead-lettered nothing. Counting `.ran` would collapse that
  # healthy state into "one outstanding dead letter" permanently, which is the exact distinction the
  # writer created that file to preserve.
  dead_letter_ran 01998f3a-dead-4beef-9c21-000000000002 0
  run "$BIN" list
  [ "$status" -eq 0 ]
  [ "$output" = "none" ]
  ! echo "$output" | grep -q '\.ran' || false
  # Positive control, SAME store and same run: the absence assertion above is not vacuous.
  dead_letter 01998f3a-dead-4beef-9c21-000000000002
  run "$BIN" list
  echo "$output" | grep -q 'mail-deadletter'
}

@test "ack: a dead letter is silenceable, in BOTH marker conventions" {
  dead_letter dl-ack
  run "$BIN" ack dl-ack.md
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'acked 1 record'
  [ -f "$CC_SWEEP_SEEN_DIR/dl-ack.md.seen" ]                             # the literal form
  [ -f "$CC_SWEEP_SEEN_DIR/$(printf '%s' "$CC_MAILBOX_DIR/dead-letter/dl-ack.md" | shasum -a 256 | cut -c1-32)" ]
  run "$BIN" list
  echo "$output" | grep -q 'dl-ack\.md .*yes'
}

@test "list --json: a dead letter carries class mail-deadletter and no fabricated verdict" {
  dead_letter dl-json
  run "$BIN" list --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.[0].class')"   = "mail-deadletter" ]
  # A markdown record has no verdict field and no `.verdict` sidecar. The renderer must say so with
  # the absent token rather than inventing one — an ABSENT verdict is never rendered as success.
  [ "$(echo "$output" | jq -r '.[0].verdict')" = "-" ]
  [ "$(echo "$output" | jq -r '.[0].seen')"    = "false" ]
}

@test "ack --all: leaves zero unseen across all FIVE stores, and is idempotent" {
  handoff_alarm alarm-1.json husk-pane
  printf '{"kind":"announce-degrade"}\n' > "$CC_ANNOUNCE_ALARM_DIR/announce-degrade-2.json"
  completion_record push-stuck.json "push-failed(rc=5)"
  completion_record push-ok.json    verified
  : > "$CC_PAGES_DIR/p2.page"
  dead_letter dl-all
  dead_letter_ran dl-all
  run "$BIN" ack --all
  [ "$status" -eq 0 ]
  # 5, not 6: the verified completion record is not outstanding, and `.ran` is not a record.
  echo "$output" | grep -q 'acked 5 record'
  run "$BIN" list
  ! echo "$output" | grep -qE ' no$' || false                # zero unseen…
  echo "$output" | grep -qE ' yes$'                          # …with a positive control that rows exist
  run "$BIN" ack --all                                       # second pass changes nothing
  echo "$output" | grep -q 'acked 0 record'
}

# ── CROSS-CONVENTION: the ack must be the SWEEP's own marker ─────────────────────────────────────
@test "cross-convention: after an ack the REAL autonomy-sweep no longer collects the record" {
  : > "$CC_PAGES_DIR/cross.page"
  # 1. un-acked → collected.  2. STILL collected on a second run (the sweep does not self-damp with
  #    no desk role, so step 3's zero is attributable to the ack and to nothing else).
  run_sweep; [ "$(swept .new_pages)" -eq 1 ]
  run_sweep; [ "$(swept .new_pages)" -eq 1 ]
  run "$BIN" ack cross.page
  [ "$status" -eq 0 ]
  # 3. the sweep now treats OUR marker as its own
  run_sweep
  [ "$(swept .new_pages)" -eq 0 ]
  [ "$(swept .disposition)" = "abstained" ]
}

@test "cross-convention: EITHER marker form damps the v2 sweep; dual-write is for LEGACY markers" {
  # RE-ORACLED at integration (this suite's original form pinned the PRE-D2 sweep: literal-only ⇒
  # still collected, which justified ack's dual write. D2's is_new() now honours either key, so the
  # old oracle inverted the moment the sweep landed — the stale-assertion class, resolved for the
  # design side.) What still holds, and is pinned here: (a) a literal-only .seen damps the v2 sweep
  # — an operator ack in EITHER convention silences re-surfacing; (b) the HASH key alone also damps
  # — the 1,193 pre-D2 markers on live disk stay valid, which is why ack keeps writing BOTH rather
  # than "simplifying" to the literal form; (c) an unmarked record is collected (positive control,
  # so neither suppression can pass vacuously).
  : > "$CC_PAGES_DIR/unmarked.page"
  run_sweep
  [ "$(swept .new_pages)" -eq 1 ]                            # (c) collected when nothing marks it
  : > "$CC_PAGES_DIR/literal.page"
  : > "$CC_SWEEP_SEEN_DIR/literal.page.seen"                 # (a) the literal form, alone
  run_sweep
  [ "$(swept .new_pages)" -eq 1 ]                            # unmarked still counted…
  run bash -c "'$BIN' list | grep 'literal\.page'"
  [[ "$output" == *yes* ]] || false                          # …and literal.page reads SEEN to list
  [[ "$output" != *$'\n'* ]] || false                        # row-scoped: exactly one line matched
  : > "$CC_PAGES_DIR/hashed.page"
  printf '%s' "$CC_PAGES_DIR/hashed.page" | shasum -a 256 | cut -c1-32 | while read -r k; do
    : > "$CC_SWEEP_SEEN_DIR/$k"; done                        # (b) the legacy hash form, alone
  run_sweep
  [ "$(swept .new_pages)" -eq 1 ]                            # still just unmarked.page
  run "$BIN" ack unmarked.page                               # full ack damps the last one
  run_sweep
  [ "$(swept .new_pages)" -eq 0 ]
}

@test "--selftest passes and runs all 15 checks (a zero-check selftest must not 'pass')" {
  run "$BIN" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 15 ]
  ! printf '%s' "$output" | grep -q '^  FAIL' || false
}

@test "unknown verb → exit 2 (fail-loud); --help → exit 0" {
  run "$BIN" bogus
  [ "$status" -eq 2 ]
  run "$BIN" --help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'cc-escalations'
}
