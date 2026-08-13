#!/usr/bin/env bats
# autonomy-sweep.sh — the ONE pull-based consumer of the write-only escalation dirs (a18 SO-5).
# Drains pages/ + cc-announce-alarms/ + completion-push/(push-failed) + decisions/(open+expiring),
# dedupes via per-record .seen markers, and: (a) cc-notifies the desk ROLE once when anything NEW
# exists, (b) runs cc-decide expire-sweep and appends each fired class-B default as a cc-backlog
# item (never acts inline), (c) writes one {fired|abstained} IDL record.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # CC_TEST_SWEEP is the RED-PROOF seam and nothing else: the D2/D4 cases below are re-run against a
  # PRISTINE tree (`git archive HEAD scripts/ | tar -x`) to prove each one FAILS without the change.
  # It has to be the real extracted artifact — a hand-edited approximation of the old script proves
  # nothing (memory: control-must-replay-the-real-artifact).
  SWEEP="${CC_TEST_SWEEP:-$REPO/scripts/autonomy-sweep.sh}"
  # ── EVERY SUBJECT INVOCATION IS BOUNDED (post-land HUNG, backlog 6b42d1f49770) ──────────────────
  # This suite executes the REAL sweep 81 times, and the sweep is not a pure read: it forks
  # backlog-consolidation-trigger, backlog-ratchet, backlog-grouping-sweep, settings-drift-assert
  # and cc-premise. Every one of those is bounded INSIDE the sweep — and every one of those bounds
  # is `_tmo`/`TIMEOUT_BIN`, i.e. `command -v timeout || command -v gtimeout`, i.e. INERT wherever
  # coreutils is not on PATH. macOS ships neither binary in /usr/bin, so the subject's whole bound
  # ladder evaporates in exactly the environments this suite is run from by machinery rather than
  # by a person. Unbounded, ONE wedged fork does not fail a test — it wedges the FILE, and a file
  # that never returns is not a red, it is a HUNG: postland-verify's 5400 s suite bound was the only
  # thing that ever came back (wedged at 231/8845 @ 0fcd4018, confirmed by a bounded 300 s re-run of
  # this file ALONE in a pristine worktree — scripts/postland-verify.sh § confirm_hang).
  #
  # THE BOUND IS RESOLVED BY ABSOLUTE PATH AS WELL AS PATH, which is the entire point: a wrapper
  # that resolves the same way the subject does would be inert in the same environments and would
  # bound nothing. Same ladder as bin/it2-wrapper, scripts/handoff-fire.sh and postland-verify's own
  # `_resolve_timeout`, and it is the remedy postland-verify's HUNG page names ("timeout-wrap the
  # un-stubbed seam"), never a peer pkill — a kill is the CUT state, which asserts nothing.
  #
  # NO `--foreground`: timeout(1) then runs the subject in its OWN process group, so the cut reaches
  # the whole fork tree rather than the top-level bash alone (the property postland-verify:92 relies
  # on for the same reason).
  #
  # FAIL-OPEN when neither binary exists — a suite that refused to run without coreutils would be a
  # new red on every box that has none, and the pre-existing behaviour is exactly "unbounded". The
  # `env` no-op keeps the prefix a valid array either way, so no call site needs a conditional.
  # 30 s is ~35x the slowest invocation measured in this file (the W1 currency-pass case, 876 ms),
  # so it cannot cut a healthy sweep; CC_SWEEP_TEST_BOUND_S re-sizes it without editing 81 lines.
  SWEEP_TO=(env)
  local _tb
  for _tb in "$(command -v timeout 2>/dev/null || true)" \
             "$(command -v gtimeout 2>/dev/null || true)" \
             /opt/homebrew/bin/timeout /usr/local/bin/timeout \
             /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    if [ -n "$_tb" ] && [ -x "$_tb" ]; then
      SWEEP_TO=("$_tb" -k 5 "${CC_SWEEP_TEST_BOUND_S:-30}"); break
    fi
  done
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECIDE_BIN="$REPO/bin/cc-decide"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  # ⚠️ EVERY dir the sweep can delete files from must be redirected here. The sweep age-reaps six event
  # dirs; any one left unexported falls back to its $HOME default and the suite becomes a reaper
  # against LIVE state. (It did: an unexported CC_TEARDOWN_RECORDS_DIR let a test run delete 6 real
  # ~/.claude/cc-teardown records, 2026-07-25. A destructive default is the harness's bug.)
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_PUSH_RECORDS_DIR="$BATS_TEST_TMPDIR/push-records"
  export CC_TEARDOWN_RECORDS_DIR="$BATS_TEST_TMPDIR/cc-teardown"
  export CC_INBOX_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/inbox-guard"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  # D2/D4 stores. CC_HANDOFF_ALARM_DIR is REAPED by the sweep, so the warning above applies to it in
  # full; CC_EXPIRED_LEDGER is APPENDED to, and an unexported one would grow the operator's real
  # ledger from a test run.
  # THE RATCHET'S STATE — unexported until 2026-08-12, so every run of this suite read the
  # OPERATOR'S LIVE high-water mark (~/.claude/autonomy/backlog-ratchet.json). That was invisible
  # while the ratchet's only effect was a journal field; the moment a red assert gained a CONSUMER
  # that files a row, a test's outcome started depending on the live store's coverage. Same rule as
  # the reaped dirs above: a default that resolves under $HOME is the harness's bug, not the
  # subject's.
  export CC_RATCHET_STATE="$BATS_TEST_TMPDIR/backlog-ratchet.json"
  export CC_BACKLOG_VALIDATED="$BATS_TEST_TMPDIR/backlog-validated.json"
  # THE LAST STORE THE SWEEP REACHED THAT THIS FIXTURE DID NOT OWN is `settings-drift-assert.sh
  # --file`, which unexported resolves the FIVE REAL config dirs — its cost and its verdict are then
  # facts about the operator's live machine, and on drift it FILES a row carrying its own falsifier
  # into the fixture backlog, which the W1 currency pass below then EXECUTES. It is fixtured with
  # CC_DRIFT_DIRS a few lines down, beside the other two live-state reads found by the same canary-
  # $HOME pass; three POPULATED dirs and not two empty ones, for the reason recorded there.
  # The currency pass is OFF by default across this suite: it costs ~106 s on a real store and this
  # file is not its subject. The three W1 cases at the bottom turn it on deliberately.
  export CC_PREMISE_PASS_STAMP="$BATS_TEST_TMPDIR/premise-pass.stamp"
  export CC_PREMISE_PASS_EVERY_S=99999
  : > "$CC_PREMISE_PASS_STAMP"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_EXPIRED_LEDGER="$BATS_TEST_TMPDIR/expired-unread.jsonl"
  export CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/watchdog-teardown"
  export CC_CLOSE_ATTRIB_LOG="$BATS_TEST_TMPDIR/close-attrib.jsonl"
  # 🚨 THE SAME RULE ONE LAYER OUT — a seam that reaches a live BINARY, not a live DIR. This one did
  # not corrupt the operator's state; it WEDGED the suite, and post-land filed it HUNG (backlog
  # 2d67e9dff07b, `tests/autonomy-sweep.bats wedged at 216/8624`).
  #
  # `cc-backlog add` force-spawns `cc-dispatch --decide` on every successful add (bin/cc-backlog
  # `dispatch_kick`), and this file drives 74 sweep invocations per run — each one able to add via a
  # class-B default, the ratchet's consumer, the grouping sweep, settings-drift, or a fixture. The
  # spawn is `( "$bin" --decide >/dev/null 2>&1 </dev/null & )`, which LOOKS detached and is not:
  # 0/1/2 are redirected and **fd 3 is not**, and fd 3 is bats' own TAP channel — so bats blocks
  # until every spawned dispatch pass exits. Measured on this file, cc-dispatch executable on the
  # box: 150 s and 9 REAL dispatch passes fired at the operator's live store, versus 29 s and 0 with
  # the switch below. postland-verify runs the file alone under POSTLAND_FILE_TIMEOUT_S (300 s), so
  # on a box where a dispatch pass is not a 120 s stub that is a hang with no verdict.
  #
  # THE REMEDY IS THE SEAM, NEVER KILLING THE SPAWNED PEERS. A `pkill cc-dispatch` from a test reaps
  # the operator's REAL dispatch workers — a strictly worse bug than the hang it would hide.
  #
  # THREE LAYERS, because the kill switch alone is one deleted line from silently re-arming — and a
  # re-arm is invisible here, since the spawn's own output goes to /dev/null:
  #   KICK=off     the documented switch (bin/cc-backlog §6)
  #   KICK_BIN     a stub, so a regressed switch still cannot reach ~/.claude/bin/cc-dispatch
  #   KICK_MARKER  the debounce stamp — unexported it is the OPERATOR'S, so whether a given test
  #                kicks at all depends on when they last filed an item by hand.
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/stub-dispatch"
  cat > "$CC_BACKLOG_KICK_BIN" <<'SH'
#!/bin/bash
# Closes fd 3 FIRST: bats' TAP channel is what a background grandchild holds open, so a spawn that
# ever slips past the switch above still cannot wedge the run — it logs argv and exits.
exec 3>&- 2>/dev/null || true
echo "$@" >> "$0.log"
SH
  chmod +x "$CC_BACKLOG_KICK_BIN"
  # THE LAST TWO LIVE-STATE READS, found by running one sweep under a canary $HOME and listing every
  # path it touched. Both are pure reads, so neither can corrupt anything — they are redirected
  # because they make a test's COST and OUTCOME depend on the operator's machine, on all 74
  # invocations, which is the same defect as the ratchet's state above.
  #   CC_DRIFT_DIRS    settings-drift-assert.sh --file otherwise jq-diffs the five REAL config dirs
  #                    ($HOME/.claude{,-next,-secondary,-tertiary,-quaternary}) — and on a box where
  #                    they genuinely differ it FILES a row, i.e. one more add, i.e. one more kick.
  #   CC_POSTLAND_DIR  cc-premise's postland arm otherwise reads $HOME/.claude/autonomy/postland.
  #                    This suite runs FROM that verifier, so it would be reading the ledger of the
  #                    very run executing it.
  # Three identical dirs, not zero: the checker needs two readable ones to reach a verdict at all,
  # and an unreadable set is a NON-VERDICT (rc 3) — a different journal field from the agreement
  # this asserts, so an empty fixture would quietly move what `settings_drift_rc` means.
  # Carried as an ARRAY and joined only for the env var: CC_DRIFT_DIRS is a space-separated list by
  # the checker's own contract, so every use site would otherwise need a bare `$CC_DRIFT_DIRS` and a
  # per-site SC2086 waiver. One join, no unquoted expansions.
  local _cfg=("$BATS_TEST_TMPDIR/cfg-a" "$BATS_TEST_TMPDIR/cfg-b" "$BATS_TEST_TMPDIR/cfg-c")
  export CC_DRIFT_DIRS="${_cfg[*]}"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  # ⏱ AND THE BOUNDS THE SWEEP'S OWN ARMS RUN UNDER. The defaults (180 s per backlog-health arm,
  # 420 s for the currency pass) are sized for a live store in the Background band; against these
  # tmpdir fixtures every one of them is sub-second, so a bound that large is not a bound here — it
  # is 180 s of headroom for the next un-stubbed seam to hide in, times 74. Sized to the band this
  # actually runs in (memory: bound-must-fit-the-band-not-the-bench), and generous by ~20x.
  #
  # 🚨 THESE NEST UNDER SWEEP_TO, AND THE ORDERING IS THE WHOLE POINT. Two bounds now cover one
  # invocation and they answer different questions: the INNER pair is the SUBJECT's own, and a cut
  # there is a VERDICT — the arm returns 124 and the sweep journals it (`fold_rc:"124"`,
  # `premise_pass_note:"bound-exceeded"`), which is the signal that says re-measure the band. The
  # OUTER wrap is the HARNESS's backstop for the case the subject cannot cover: the inner ladder
  # resolves timeout(1) off PATH alone, so it is INERT wherever coreutils is not there and nothing
  # inside the sweep can bound anything at all. Set equal, the outer always fires first and the
  # inner pair can never journal — the backstop silently replaces the instrument. So every inner
  # bound stays strictly below SWEEP_TO's 30 s: a wedged ARM reads as a named red carrying its own
  # rc, and only a wedged FILE reaches the wrap. Slowest invocation measured in this file is 876 ms
  # (the W1 currency-pass case), so 10 s is ~11x headroom and 20 s ~23x — neither can cut a healthy
  # sweep, and both remain env-overridable for a slower band.
  export CC_SWEEP_BOUND_S="${CC_SWEEP_BOUND_S:-10}"
  export CC_PREMISE_PASS_BOUND_S="${CC_PREMISE_PASS_BOUND_S:-20}"
  mkdir -p "$CC_PAGES_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
           "$CC_DECISIONS_DIR" "$CC_ROLES_DIR" "$CC_COMMS_ALARM_DIR" "$CC_PUSH_RECORDS_DIR" \
           "$CC_TEARDOWN_RECORDS_DIR" "$CC_INBOX_GUARD_STATE_DIR" "$CC_MAILBOX_DIR" \
           "$CC_HANDOFF_ALARM_DIR" "$CC_TEARDOWN_DIR" "$CC_POSTLAND_DIR" \
           "${_cfg[@]}"
  # identical on purpose — the drift checker's AGREEMENT path, so settings_drift_rc stays 0
  local _d
  for _d in "${_cfg[@]}"; do
    printf '{"permissions":{"deny":["Bash(sudo:*)"],"ask":[],"allow":[]}}\n' > "$_d/settings.json"
  done
  # stub cc-notify: log every call to <stub>.log, and emit a cc-notify-SHAPED verdict token on
  # STDERR — the real binary does, and the exit code alone is NOT the outcome (measured against a
  # dead pane: `verdict=mailbox-only enqueued=1 reason=target-not-live unacked=997` at rc=0). A stub
  # that emitted nothing would let the sweep read `unreadable` on every test and prove the wrong
  # thing. CC_STUB_VERDICT / CC_STUB_RC select the outcome per test.
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/stub-notify"
  cat > "$CC_NOTIFY_BIN" <<'SH'
#!/bin/bash
echo "$@" >> "$0.log"
echo "cc-notify: verdict=${CC_STUB_VERDICT:-delivered} enqueued=1 uuid=desk-pane-uuid-current" >&2
exit "${CC_STUB_RC:-0}"
SH
  chmod +x "$CC_NOTIFY_BIN"
  export CC_STUB_VERDICT=delivered
  export CC_STUB_RC=0
  # HERMETIC osascript: the sweep's liveness-free channel is Notification Center. `auto` probes with
  # `command -v`, which no suite can un-find, so the stub goes on PATH — a test that reaches this
  # channel must never post a real notification to the operator's machine. Belt: the seam defaults
  # to `off` here, so a test that forgets to opt in cannot reach it at all.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export OSA_LOG="$BATS_TEST_TMPDIR/osascript.log"
  cat > "$BATS_TEST_TMPDIR/bin/osascript" <<'SH'
#!/bin/bash
cat >/dev/null
printf '%s\n' "$*" >> "$OSA_LOG"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/osascript"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CC_SWEEP_OS_CHANNEL=off
  echo "desk-pane-uuid-current" > "$CC_ROLES_DIR/desk"
  # HERMETIC it2: the D4 world probe defaults to the operator's REAL ~/.claude/bin/it2 against the
  # LIVE terminal. A suite that forgot this seam would probe (and be answered by) the operator's own
  # session list — the same class of destructive default as the unexported teardown dir above.
  # CC_STUB_IT2_OUT is the listing; CC_STUB_IT2_RC forces a REFUSAL (124 = cut at the bound).
  export CC_IT2_BIN="$BATS_TEST_TMPDIR/stub-it2"
  cat > "$CC_IT2_BIN" <<'SH'
#!/bin/bash
echo "$@" >> "$0.log"
[ -n "${CC_STUB_IT2_RC:-}" ] && exit "$CC_STUB_IT2_RC"
printf '%s\n' "${CC_STUB_IT2_OUT:-}"
SH
  chmod +x "$CC_IT2_BIN"
}
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
osa_count()    { [ -f "$OSA_LOG" ] && wc -l < "$OSA_LOG" | tr -d ' ' || echo 0; }
# `.seen` (forgotten) and `.bannered` (posted once) share SEEN_DIR — deliberately, so the existing
# 7-day age-compaction reaps both with no second reaper. That makes `ls -A "$CC_SWEEP_SEEN_DIR"` a
# WIDER span than the subject every data-loss assertion here is about, so those assertions count the
# marker CLASS instead: a seen key is a bare 32-char hash, a banner marker ends in `.bannered`.
# (memory: assertion-span-must-equal-its-subject — a count spanning a mechanism the test does not
# test is a tripwire for that mechanism's next change, not a guard on this one.)
# Counted by GLOB, not `ls | grep | wc` — and emphatically not by shellcheck SC2126's suggested
# `grep -c`, which is the trap this helper already fell into once: grep exits 1 on ZERO matches, so
# the `|| echo 0` guard that looks like prudence fires ON TOP of the 0 grep already printed, the
# helper returns the two-line string "0\n0", and `[ … -eq 0 ]` rejects it as "integer expression
# expected". That breaks precisely on the empty case every data-loss assertion here is about. The
# glob form has no such edge: the `[ -e ]` guard absorbs a non-matching pattern and the count is a
# plain arithmetic variable. (memory: prescribed-remedy-worse-than-the-bug — a lint's one-liner is a
# suggestion about style, not a proof about behaviour; run it where it executes before adopting it.)
# D4 adds a THIRD suffixed store (`.orphan-checked`), so the class filter names both: a seen key is
# a bare hash, and every suffixed marker is something other than a proven read.
seen_count() {   # `.seen` keys are bare 32-char hashes; the suffixed stores are not read receipts
  local f n=0
  for f in "$CC_SWEEP_SEEN_DIR"/*; do
    [ -f "$f" ] || continue
    case "$f" in *.bannered|*.orphan-checked) continue ;; esac
    n=$((n + 1))
  done
  printf '%s' "$n"
}
bannered_count() {
  local f n=0
  for f in "$CC_SWEEP_SEEN_DIR"/*.bannered; do
    [ -e "$f" ] || continue
    n=$((n + 1))
  done
  printf '%s' "$n"
}
osa_posts() {
  local n=0
  [ -f "$OSA_LOG" ] && n=$(wc -l < "$OSA_LOG" | tr -d ' ')
  printf '%s' "$n"
}
ha_count()       { local f n=0; for f in "$CC_HANDOFF_ALARM_DIR"/*.json; do [ -f "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }
mk_marker() { # <file> <pane> <mode> [young]  — aged 1 h by default (> the 900 s join deadline)
  printf '{"key_kind":"pane","pane":"%s","sid":"S-1","mode":"%s","ts":"2026-08-07T00:00:00Z"}\n' \
    "$2" "$3" > "$CC_TEARDOWN_DIR/$1"
  [ "${4:-}" = young ] || touch -t "$(date -v-1H +%Y%m%d%H%M)" "$CC_TEARDOWN_DIR/$1"
}

# ── nothing-new → abstain, no notify ───────────────────────────────────────────
@test "nothing new → abstain, zero notifies" {
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]
  grep -q '"disposition":"abstained"' "$CC_IDL"
}

# ── new alarm → exactly one notify, once (dedup on the second run) ──────────────
@test "a new alarm → one notify to the desk role; a second run (nothing new) abstains" {
  echo '{"kind":"alarm","detail":"never-stuck gate red"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  # addressed by ROLE, not by the uuid snapshot the sweep read: cc-notify re-reads cc-roles/desk at
  # SEND time and follows the .forward chain, so a desk recycled mid-sweep still gets the wake.
  grep -q -- '--role desk' "$CC_NOTIFY_BIN.log"
  grep -q '"disposition":"fired"' "$CC_IDL"
  # second run: the alarm is now .seen → nothing new → abstain, still exactly ONE notify total
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
}

# ── a new page surfaces ────────────────────────────────────────────────────────
@test "a new page triggers one notify" {
  echo "1784370726" > "$CC_PAGES_DIR/$(uuidgen 2>/dev/null || echo p1).page"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
}

# ── completion-push: only push-failed records surface, not verified ────────────
@test "completion-push: a push-failed record surfaces; a verified one does not" {
  echo '{"kind":"completion-push","verdict":"verified","event":"ok"}'   > "$CC_COMPLETION_RECORDS_DIR/good.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]                     # verified-only ⇒ nothing stuck ⇒ no notify
  grep -q '"disposition":"abstained"' "$CC_IDL"
  echo '{"kind":"completion-push","verdict":"push-failed(cc-announce rc=5)","event":"terminal"}' > "$CC_COMPLETION_RECORDS_DIR/bad.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]                     # the push-failed one wakes the desk
}

# ── fired class-B default → a backlog item is appended (never acted inline) ────
@test "a past-deadline class-B default fires → cc-backlog item appended, packet expired-actioned" {
  id=$(bash "$CC_DECIDE_BIN" open --class B --what "which account to continue on" \
        --default "continue cross-account on next2" --deadline "2000-01-01T00:00:00Z")
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  # the sweep is the default-ACTUATOR: it appends a backlog item rather than acting inline
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "continue cross-account on next2"
  # and the packet transitioned (expire-sweep) — never deleted
  [ "$(jq -r '.status' "$CC_DECISIONS_DIR/$id.json")" = "expired-actioned" ]
  grep -q '"disposition":"fired"' "$CC_IDL"
}

# ── an open decision packet is surfaced in the summary (once) ──────────────────
@test "an open (future-deadline) class-B packet surfaces once, then is deduped" {
  bash "$CC_DECIDE_BIN" open --class B --what "a pending fork" \
    --default "park + continue" --deadline "2099-01-01T00:00:00Z" >/dev/null
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]      # deduped on the second run
}

# ── missing desk role → do NOT mark seen (retry next sweep), fail loud in IDL ──
@test "no desk role → notify is not delivered and the record is NOT marked seen (retry)" {
  rm -f "$CC_ROLES_DIR/desk"
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]                       # nothing delivered
  grep -q 'no-desk-role\|undelivered' "$CC_IDL"     # loud, not silent
  # restore role: the SAME alarm must still surface (it was never marked seen)
  echo "desk-pane-uuid-current" > "$CC_ROLES_DIR/desk"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
}

# ── launchd/supervisor-callable: runs standalone, exit 0, no args ──────────────
@test "runs standalone with no args and exits 0" {
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
}

# ══ age-reap of the six write-only event dirs (audit 03 §1b/§1c fix 5) ═════════════════════════
# L2: each case asserts the failure-DISTINCT pair — OLD reaped AND YOUNG kept. Asserting only the
# reap would stay green if the horizon collapsed to 0 and ate live records; asserting only the keep
# would stay green if the reaper never ran at all.

mk_old()   { mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; touch -t "$(date -v-9d +%Y%m%d%H%M)" "$1"; }
mk_young() { mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; }

@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"

  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]

  [ ! -f "$CC_PAGES_DIR/old.page" ];              [ -f "$CC_PAGES_DIR/new.page" ]
  [ ! -f "$CC_COMMS_ALARM_DIR/old.json" ];        [ -f "$CC_COMMS_ALARM_DIR/new.json" ]
  [ ! -f "$CC_PUSH_RECORDS_DIR/old.json" ];       [ -f "$CC_PUSH_RECORDS_DIR/new.json" ]
  [ ! -f "$CC_COMPLETION_RECORDS_DIR/old.json" ]; [ -f "$CC_COMPLETION_RECORDS_DIR/new.json" ]
  [ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]
}

# ── the durable ledgers are NEVER age-reaped (they are the exclusion, not an oversight) ────────
@test "decisions/ is exempt: an old decision packet survives the reap" {
  mk_old "$CC_DECISIONS_DIR/old.json"
  printf '{"status":"open"}\n' > "$CC_DECISIONS_DIR/old.json"
  touch -t "$(date -v-30d +%Y%m%d%H%M)" "$CC_DECISIONS_DIR/old.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_DECISIONS_DIR/old.json" ]
}

# ── inbox-guard is DAMPING state: age alone must not clear it (that re-fires the page it damps) ─
@test "an old .escalated marker whose mailbox still exists is KEPT (damping preserved)" {
  mk_old "$CC_INBOX_GUARD_STATE_DIR/PANE-A.escalated"
  printf 'msg\n' > "$CC_MAILBOX_DIR/PANE-A.md"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_INBOX_GUARD_STATE_DIR/PANE-A.escalated" ]
}

@test "an old .escalated marker whose mailbox is gone IS reaped (it can damp nothing)" {
  mk_old "$CC_INBOX_GUARD_STATE_DIR/PANE-B.escalated"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_INBOX_GUARD_STATE_DIR/PANE-B.escalated" ]
}

@test "a YOUNG .escalated marker with no mailbox is still kept (horizon, not lifecycle)" {
  mk_young "$CC_INBOX_GUARD_STATE_DIR/PANE-C.escalated"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_INBOX_GUARD_STATE_DIR/PANE-C.escalated" ]
}

# ── the horizon must outlive the reaper-horizon-lint floor (600 s sweep × 10 = 6,000 s) ────────
# Assert THIS sweep's own horizon against the floor the lint PUBLISHES — never the lint's whole-tree
# exit code. The lint scans every file in the repo, so the bare `[ "$status" -eq 0 ]` that stood on
# the last line made this test answerable for debt it did not create and could not name: at
# 9899aabef9ec it went RED because `bin/cc-queue` was UNDECLARED (§3), post-land filed the failure
# under THIS test's title, and the title sent two workers at a 7-day horizon that was healthy the
# whole time — the item sat blocked 7 days (backlog 2490e355832e; the lint's own fix, 24ba1cbc,
# landed one commit later). tests/scratchpad-reaper.bats:148 had already reached this conclusion and
# scoped its assertion; that suite was NOT filed by the same scan. This is the same remedy for the
# file that still carried the whole-tree form.
#
# The scoping had to be DERIVED, not copied: the sibling greps the lint for its own `ok` line, which
# works because it writes a LITERAL `-mmin +2880` that §1 can score. This sweep writes
# `-mtime +"$EVENT_TTL"` — a variable — so NO scorer in the lint can read it and no per-file verdict
# about it is ever printed. Declaring it in $DECLARED would therefore be exactly the rubber stamp the
# lint forbids in its own §1b ("passes BY BEING LISTED rather than by being checked"). So the three
# facts are asserted directly, and the floor is READ from the lint rather than restated — two copies
# of that constant is the drift the lint's §4 exists to forbid.
@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
  # (a) the 7 GOVERNS the reaping — the premise the whole-tree exit code never checked at all.
  #     Two assertions, because the file-wide grep alone is not per-site: the sweep passes
  #     $EVENT_TTL to TWO finds (the event dirs, and the .escalated markers), so mutating either
  #     one to a literal left the other to satisfy the grep. The second line closes that by
  #     forbidding the literal form outright — a hardcoded `-mtime +N` here bypasses the knob,
  #     which is precisely how a horizon regresses without the name in this test's title changing.
  grep -qF -- '-mtime +"$EVENT_TTL"' "$SWEEP"
  run grep -cE -- '-mtime \+[0-9]' "$SWEEP"
  [ "$status" -ne 0 ]
  # (b) the floor, from the lint's own mouth. Its exit code is deliberately NOT asserted: another
  #     file's undeclared reaper is still caught by §3 where it is reported against ITS name.
  run bash "$REPO/scripts/reaper-horizon-lint.sh"
  floor=$(printf '%s\n' "$output" | sed -nE '1s/.*= ([0-9]+)s$/\1/p')
  [ -n "$floor" ]
  # (c) three orders of magnitude above it — the claim in this test's own name
  ttl=$(sed -nE 's/^EVENT_TTL="\$\{CC_EVENT_TTL_DAYS:-([0-9]+)\}"$/\1/p' "$SWEEP")
  [ -n "$ttl" ]
  [ "$(( ttl * 86400 ))" -ge "$floor" ]
}

# ══ fired-default triage: subject project + the no-change carve-out (item f32588a73993) ═════════
# The sweep is the class-B default ACTUATOR. Two things it could not previously know, both now
# declared by the PRODUCER on the packet and reported on the fired line:
#   (a) WHICH project the decision is about — this sweep runs from launchd with cwd=/;
#   (b) whether firing the default CHANGES anything — a no-change default ("hold (no change
#       without ruling)", "disclose-only", "park and continue") actuates NOTHING, yet an OPEN
#       backlog item is exactly cc-dispatch's fire predicate, so one could spawn a peer session
#       whose entire assignment was to change nothing. Three such rows are in the live ledger.
# Neither is ever recovered by reading the default's WORDING — that shape-classifier is the thing
# that must not be built (memory: fixture-vs-real-classifier-needs-a-producer).

@test "a fired NO-CHANGE default is surfaced but NEVER queued as a dispatch candidate" {
  id=$(bash "$CC_DECIDE_BIN" open --class B --what "rearchitect the program?" \
        --default "hold (no change without ruling)" --deadline "2000-01-01T00:00:00Z" \
        --default-effect no-change)
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  # the packet DID fire (the trail is intact — this is not a no-op path)
  [ "$(jq -r '.status' "$CC_DECISIONS_DIR/$id.json")" = "expired-actioned" ]
  # ...and the desk was still woken: surfaced, not swallowed
  [ "$(notify_count)" -eq 1 ]
  grep -q '"fired_nochange":1' "$CC_IDL"
  # ...but NOTHING dispatchable was queued. `list --open` is cc-dispatch's own predicate.
  run bash "$CC_BACKLOG_BIN" list --open
  ! echo "$output" | grep -q "hold (no change without ruling)" || false
  # belt: not merely absent from the OPEN view — never written to the ledger at all
  ! grep -q "hold (no change without ruling)" "$CC_BACKLOG_FILE" 2>/dev/null || false
}

@test "POSITIVE CONTROL: a fired CHANGE default in the same run IS still queued" {
  # Without this, a carve-out that suppressed EVERY fired default would pass the test above.
  bash "$CC_DECIDE_BIN" open --class B --what "no-change one" --default "hold it" \
    --deadline "2000-01-01T00:00:00Z" --default-effect no-change >/dev/null
  bash "$CC_DECIDE_BIN" open --class B --what "change one" --default "land the lossless fix" \
    --deadline "2000-01-01T00:00:00Z" --default-effect change >/dev/null
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "land the lossless fix"
  ! echo "$output" | grep -q "hold it" || false
}

@test "an UNANNOTATED fired default is still queued (fail-open: no silent drop)" {
  # Every legacy producer omits --default-effect. Absent must mean "change", or landing this fix
  # would silently stop draining the class-B queue.
  bash "$CC_DECIDE_BIN" open --class B --what "legacy shape" --default "carry this out" \
    --deadline "2000-01-01T00:00:00Z" >/dev/null
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  run bash "$CC_BACKLOG_BIN" list --open
  echo "$output" | grep -q "carry this out"
}

@test "the item is filed against the packet's DECLARED subject project" {
  bash "$CC_DECIDE_BIN" open --class B --what "whose project?" --default "do the thing" \
    --deadline "2000-01-01T00:00:00Z" --project doc_classifier --default-effect change >/dev/null
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  run jq -r 'select(.source=="autonomy-sweep") | .project' "$CC_BACKLOG_FILE"
  [ "$output" = "doc_classifier" ]
}

@test "no declared project → the host-project fallback, and the default still lands in the title" {
  # The consumer-side half of the TSV collapse control: an unpadded emitter would put the EFFECT in
  # the project slot (filing the item against project "change") and the DEFAULT in the effect slot
  # (so `no-change` would never match and the title would go empty).
  bash "$CC_DECIDE_BIN" open --class B --what "no project" --default "carry this out" \
    --deadline "2000-01-01T00:00:00Z" >/dev/null
  CC_SWEEP_PROJECT=host-proj run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  run jq -r 'select(.source=="autonomy-sweep") | .project + "|" + .title' "$CC_BACKLOG_FILE"
  [ "$output" = "host-proj|class-B default fired: carry this out" ]
}

# ══ DELIVERY IS A VERDICT, NOT AN EXIT CODE (task #120) ═══════════════════════════════════════════
# The sweep used to discard cc-notify's rc (`|| true`), route its stderr to /dev/null, and then
# mark_seen UNCONDITIONALLY on the strength of the desk role file merely being NON-EMPTY. On this
# machine no desk orchestrator runs: cc-roles/desk holds an iTerm2 pane uuid whose pane self-closed
# and whose .forward successor is equally dead, so cc-notify returns rc 0 with
# verdict=mailbox-only/unverified FOREVER. The a17 S-7 guard below ("no desk role ⇒ do NOT mark
# seen") keys on the target being EMPTY, and a DEAD uuid is not empty — so it was structurally
# unreachable in exactly the configuration it exists for. Every page, comms alarm, push-failure and
# open decision was therefore written into a box no drain will run and then forgotten: PERMANENT
# SILENT LOSS. 964 markers were sitting in ~/.claude/autonomy/sweep-seen when this was found.
# memory: claimed-outcome-vs-checked-outcome.

@test "RECORDED (rc 0, verdict=mailbox-only) with no liveness-free channel does NOT mark seen" {
  # THE data-loss regression. A dead-pane desk is the machine's steady state, and rc 0 says nothing
  # about whether a reader exists — so nothing here may be forgotten.
  export CC_STUB_VERDICT=mailbox-only
  export CC_SWEEP_OS_CHANNEL=off
  echo '{"kind":"alarm","detail":"comms gate red"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  # nothing may be FORGOTTEN — no reader was proven (the banner store is a different subject)
  [ "$(seen_count)" -eq 0 ]
  grep -q '"delivered":false' "$CC_IDL"
  # …and the SAME record re-surfaces on the next sweep. This is the whole point: an escalation that
  # nobody read must keep asking.
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 2 ]
}

@test "RECORDED but the liveness-free channel TAKES it → operator bannered, records still NOT seen" {
  # RE-ORACLED to the D2 contract. The pre-D2 shape marked these records .seen on the strength of the
  # banner — but a banner proves only that something was PUT IN FRONT OF a human, never that one READ
  # it, so spending `mark_seen` on it re-created the very data-loss task #120 fixed one layer over.
  # D2 splits the two: `.bannered` bounds the POST (storm control), `.seen` still requires a PROVEN
  # reader. The storm argument is satisfied without forgetting anything.
  export CC_STUB_VERDICT=mailbox-only
  export CC_SWEEP_OS_CHANNEL=auto          # resolves the stub osascript on PATH (hermetic)
  echo '{"kind":"alarm","detail":"comms gate red"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(osa_posts)" -eq 1 ]                 # something was actually put in front of a human
  grep -q '"channel":"notification-center-advisory"' "$CC_IDL"
  [ "$(bannered_count)" -ge 1 ]            # damped
  [ "$(seen_count)" -eq 0 ]                # …but NOT forgotten — no reader was ever proven
  # the record keeps asking, and yet the banner does NOT repeat: exactly one post, ever.
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 2 ]
  [ "$(osa_posts)" -eq 1 ]
}

@test "REFUSED (cc-notify rc != 0) never marks seen, but DOES banner once (r2 is independent)" {
  # RE-ORACLED to the D2 contract. The pre-D2 comment justified withholding the OS post here on
  # storm grounds — "there is no damping store" — which was true then and is false now: `.bannered`
  # is that store. Withholding it was how a fleet whose transport permanently refuses got NOTHING at
  # all, which is strictly worse than one bounded post. The data-loss half of this test's intent is
  # untouched: rc 3 proves no reader, so nothing may be forgotten.
  export CC_STUB_RC=3
  export CC_STUB_VERDICT=unresolvable
  export CC_SWEEP_OS_CHANNEL=auto
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(seen_count)" -eq 0 ]                       # THE data-loss guard — unchanged
  [ "$(osa_posts)" -eq 1 ]                        # …and the operator is no longer told nothing
  echo "$output" | grep -q 'UNDELIVERED'          # loud, never silent (a17 S-4)
  grep -q '"delivered":false' "$CC_IDL"
  # bounded: a transport that refuses forever still posts exactly once per record
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(osa_posts)" -eq 1 ]
}

# ══ D2 · THE ABSENT-ROLE RUNG (backlog f887a7a507db) ══════════════════════════════════════════════
# STALE-desk and ABSENT-desk are different states selecting different code paths, and only the stale
# one was ever fixed. Task #120 taught the sweep to reach the operator on a liveness-free channel
# when the desk push is RECORDED-not-read — but it wired that rung INSIDE the `[ -n "$DESK_TARGET" ]`
# arm, so removing the role files (the operator's deliberate state since 2026-08-07) disabled the
# banner too. Surfacing became strictly WORSE than the dead-uuid state it replaced.
# Measured on this box before the fix: 1,009 records re-collected and re-dropped every 300 s for four
# days, all-time `notification-center` deliveries ZERO, newest .seen marker frozen at the hour the
# role went away. memory: liveness-free-channel-never-gated-behind-liveness.

@test "D2: NO desk role at all → the liveness-free rung STILL fires (the 4-day blackout)" {
  # THE regression. Pre-D2 this posted nothing whatsoever: r2 was unreachable without r1's precondition.
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto
  echo '{"kind":"alarm","detail":"comms gate red"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]              # r1 correctly did not run — no role is a NORMAL config
  [ "$(osa_posts)" -eq 1 ]                 # …and the operator was reached anyway
  grep -q '"notified":"os-banner"' "$CC_IDL"
  grep -q '"notified":"no-desk-role"' "$CC_IDL"   # r3 still loud, and still names the real state
  [ "$(seen_count)" -eq 0 ]                # a banner is not a read — nothing forgotten
}

@test "D2: the absent-role banner is DAMPED — one post per record, not one per sweep" {
  # Without `.bannered` this fix would be a 300 s notification storm against a permanently role-less
  # fleet, which is the reason the pre-D2 code gave for withholding the post at all.
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"; [ "$(osa_posts)" -eq 1 ]
  run "${SWEEP_TO[@]}" bash "$SWEEP"; [ "$(osa_posts)" -eq 1 ]
  run "${SWEEP_TO[@]}" bash "$SWEEP"; [ "$(osa_posts)" -eq 1 ]
  # a genuinely NEW record still gets its own post — damping must not become deafness
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a2.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"; [ "$(osa_posts)" -eq 2 ]
}

@test "D2 CONTROL: re-nesting r2 under r1's precondition FAILS the absent-role test" {
  # The mutant is the PRE-FIX shape itself — r2 reachable only when a role is wired. Without this,
  # a change that quietly restored the nesting would leave the test above passing on some other path.
  # memory: control-must-replay-the-real-artifact — anchor a naive mutant, do not hand-edit an
  # approximation of one.
  local mutant="$BATS_TEST_TMPDIR/sweep-mutant.sh"
  sed 's/^  unbannered="\$(count_unbannered)"$/  unbannered=0/' "$SWEEP" > "$mutant"
  # THE MUTANT MUST RESOLVE ITS LIBS THE WAY THE REAL SCRIPT DOES (added 2026-08-12, backlog
  # b7252a3bb015). autonomy-sweep.sh:103-113 resolves lib/cc-common.sh on a three-rung ladder —
  # beside-script → $CLAUDE_CONFIG_DIR → $HOME/.claude — and FATALs with `exit 1` if all three miss.
  # Copying the mutant into BATS_TEST_TMPDIR breaks rung 1, so the copy resolved on rung 3 against
  # the developer's LIVE ~/.claude. This suite pins no HOME, so that worked on a dev Mac and could
  # not work on a CI runner, where ~/.claude does not exist: off-box the mutant died at :112 before
  # reaching ladder_v2 at all, and `[ "$status" -eq 0 ]` below went RED for a reason that has
  # nothing to do with the property this control defends. It cost the off-box green, and with it
  # T1H and the whole deploy lane, for two days. Symlinking lib/ beside the mutant pins rung 1 —
  # the same rung the real script takes — so the control now depends on the repo and not on the
  # machine. Note the SECOND assertion was the quieter casualty: a script that dies at :112 also
  # posts nothing, so `osa_posts -eq 0` passed VACUOUSLY off-box, certifying silence it never
  # observed. memory: hermetic-in-stubs-not-in-interpreter · control-must-replay-the-real-artifact.
  ln -sfn "$REPO/scripts/lib" "$BATS_TEST_TMPDIR/lib"
  # The mutation guard asserts the SPECIFIC edit landed — never merely that the two files differ.
  # TWO defects were in this guard's first form, and the second one is the general lesson:
  #   1. `! cmp -s "$SWEEP" "$mutant"` only asks "do they differ", which a no-op sed can satisfy for
  #      reasons that have nothing to do with the mutation. It must name the EDIT.
  #   2. …but that is not why it passed against the pristine script. A bare `! cmd` is EXEMPT from
  #      errexit — bash does not exit "if the command's return value is being inverted with !" — so
  #      a negated assertion in a bats test is UNREACHABLE: it cannot fail the test no matter what
  #      it finds. The `|| false` is what gives it a reachable failure edge (scripts/
  #      bats-assert-liveness-fix.py; the land gate's dead-assertion ratchet refuses the bare form).
  # The first is a bad predicate; the second is a predicate that never runs. Only the second explains
  # a control that passed against a subject where the mutation cannot apply — and a plausible-but-
  # wrong first diagnosis is exactly what a control exists to catch (memory:
  # wrong-cause-corroborated-by-true-metric · verification-harness-vacuous-pass-traps).
  grep -q '^  unbannered=0$'                  "$mutant"   # the mutation is present…
  ! grep -q '^  unbannered="\$(count_unbannered)"$' "$mutant" || false # …and the original line is gone
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$mutant"      # bounded like every other subject run — it IS the subject
  [ "$status" -eq 0 ]
  [ "$(osa_posts)" -eq 0 ]                 # the mutant is silent — which is what the fix removes
}

@test "D2 KILL SWITCH: CC_SWEEP_LADDER=legacy restores the pre-D2 silence exactly" {
  # The revert must be a genuine revert of THIS change, reachable without editing code.
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto
  export CC_SWEEP_LADDER=legacy
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(osa_posts)" -eq 0 ]
  grep -q 'no-desk-role' "$CC_IDL"
}

@test "an UNREADABLE verdict is a THIRD state — never promoted to success" {
  # A cc-notify that prints nothing parseable (a future version, a wrapper, a truncated stream) has
  # not proven a reader. Absence of evidence is not delivery.
  cat > "$CC_NOTIFY_BIN" <<'SH'
#!/bin/bash
echo "$@" >> "$0.log"
SH
  chmod +x "$CC_NOTIFY_BIN"
  export CC_SWEEP_OS_CHANNEL=off
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(seen_count)" -eq 0 ]
  grep -q '"verdict":"unreadable"' "$CC_IDL"
}

@test "POSITIVE CONTROL: REACHED (verdict=delivered) DOES mark seen — the gate is not just off" {
  # Without this, a change that simply never marked anything seen would pass every test above while
  # re-paging the desk with the same records forever.
  export CC_STUB_VERDICT=delivered
  export CC_SWEEP_OS_CHANNEL=off
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -n "$(ls -A "$CC_SWEEP_SEEN_DIR" 2>/dev/null)" ]
  grep -q '"channel":"desk"' "$CC_IDL"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
  grep -q '"disposition":"abstained"' "$CC_IDL"
}

@test "the old shape is gone: the notify call is neither rc-discarded nor stderr-discarded" {
  # The exact three lines that made this a data-loss bug, pinned so they cannot come back.
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  [ "$output" = "0" ]
  run bash -c "grep -q 'notify_verdict:=unreadable' '$SWEEP'"
  [ "$status" -eq 0 ]
  run bash -c "grep -q 'CC_SWEEP_OS_CHANNEL' '$SWEEP'"
  [ "$status" -eq 0 ]
  run bash -n "$SWEEP"
  [ "$status" -eq 0 ]
}

@test "the summary distinguishes queued fires from no-change fires" {
  bash "$CC_DECIDE_BIN" open --class B --what "nc" --default "hold it" \
    --deadline "2000-01-01T00:00:00Z" --default-effect no-change >/dev/null
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  # reporting only the total would read as "1 item queued" on a sweep that queued none
  grep -q "no-change: surfaced, NOT dispatched" "$CC_NOTIFY_BIN.log"
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
}

# ══ THE SEEN KEY IS DUAL (lead interface correction 2026-08-07) ═══════════════════════════════════
# The sweep's own key is a hash of the record's full path — collision-proof, but no other tool can
# write or grep it, so nothing outside this file could ever ack a record. D3's render and D5's
# `cc-escalations` name records by BASENAME. Both keys are therefore written, and EITHER suppresses.

@test "seen markers are written under BOTH keys, and EITHER one alone suppresses re-surfacing" {
  export CC_STUB_VERDICT=delivered
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  [ -f "$CC_SWEEP_SEEN_DIR/a1.json.seen" ]   # the literal key the render/CLI side can grep and write
  [ "$(seen_count)" -eq 2 ]                  # …and the legacy hash key beside it, still valid
  # the HASH key alone still damps (every marker written before today looks like this)
  rm -f "$CC_SWEEP_SEEN_DIR/a1.json.seen"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
  # the LITERAL key alone still damps (this is exactly what `cc-escalations ack` leaves behind)
  rm -f "$CC_SWEEP_SEEN_DIR"/*
  : > "$CC_SWEEP_SEEN_DIR/a1.json.seen"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
  # POSITIVE CONTROL: with NEITHER key the same record surfaces again — the gate is not just off
  rm -f "$CC_SWEEP_SEEN_DIR"/*
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(notify_count)" -eq 2 ]
}

# ══ D2 — THE LADDER UN-NESTED (plan §D2, acceptance A2) ═══════════════════════════════════════════
# The defect is STRUCTURAL: the OS banner — the only channel here with no liveness dependency — sat
# INSIDE the `[ -n "$DESK_TARGET" ]` arm. With cc-roles/ empty (the operator's deliberate state as
# of 2026-08-07) that arm never runs, so the no-role branch logged one IDL row, retried forever, and
# never bannered; every record then aged out at CC_EVENT_TTL_DAYS having been read by nobody. A
# fallback that only fires when a DIFFERENT rung's precondition holds is the same single point of
# failure spelled twice.

@test "rung 2 · roles EMPTY: the banner fires anyway, .bannered is written, .seen is NOT" {
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto          # resolves the stub osascript on PATH (hermetic)
  printf '{"kind":"handoff-alarm","class":"husk-pane","pane":"289","sid":"S-1","successor":"","detail":"pane close failed 4/4","ts":"2026-08-07T09:00:00Z"}\n' \
    > "$CC_HANDOFF_ALARM_DIR/alarm-1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 0 ]              # no role ⇒ rung 1 does not run at all…
  [ "$(osa_count)" -eq 1 ]                 # …and the operator is reached regardless. The whole fix.
  [ "$(bannered_count)" -eq 1 ]
  [ "$(seen_count)" -eq 0 ]                # a toast carries no read receipt
  grep -q '"channel":"notification-center-advisory"' "$CC_IDL"
  grep -q '"delivered":false' "$CC_IDL"
  # DAMPED: the record re-surfaces every tick (it is not .seen), and must never banner twice
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(osa_count)" -eq 1 ]
  [ "$(seen_count)" -eq 0 ]
}

@test "CONTROL: the LEGACY ladder in the same fixture never reaches the banner at all" {
  # The kill switch must restore the OLD behaviour, defect included — otherwise it is not a kill
  # switch but a second implementation. This is also the A2 control: it proves the case above is
  # testing the ladder change and not merely the presence of an osascript stub.
  export CC_SWEEP_LADDER=legacy
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto
  printf '{"kind":"handoff-alarm","class":"husk-pane","pane":"289","detail":"d","ts":"t"}\n' \
    > "$CC_HANDOFF_ALARM_DIR/alarm-1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(osa_count)" -eq 0 ]                 # nested inside the desk arm ⇒ structurally unreachable
  [ "$(seen_count)" -eq 0 ]
  grep -q 'no-desk-role' "$CC_IDL"
}

@test "rung 2 · a REFUSED transport still banners — once — and still marks nothing seen" {
  # The old code refused to post on this path for a real reason: no damping store existed, so a
  # permanently refusing transport would post every 300 s forever. `.bannered` IS that store, so the
  # trade is no longer forced — the record is surfaced once and the storm is impossible.
  export CC_STUB_RC=3
  export CC_STUB_VERDICT=unresolvable
  export CC_SWEEP_OS_CHANNEL=auto
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(osa_count)" -eq 1 ]
  [ "$(seen_count)" -eq 0 ]
  echo "$output" | grep -q 'UNDELIVERED'   # rung 3 is still loud (a17 S-4)
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(osa_count)" -eq 1 ]                 # …and damped
}

@test "POSITIVE CONTROL: rung 1 REACHED short-circuits — no banner, records seen" {
  # Without this, a ladder that simply bannered on every sweep would pass every case above.
  export CC_STUB_VERDICT=delivered
  export CC_SWEEP_OS_CHANNEL=auto
  echo '{"kind":"alarm"}' > "$CC_ANNOUNCE_ALARM_DIR/a1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(seen_count)" -gt 0 ]
  [ "$(osa_count)" -eq 0 ]
  [ "$(bannered_count)" -eq 0 ]
}

# ══ D2 — handoff-alarm records are collected, classed, and reaped like every other event dir ══════

@test "collect · handoff-alarm records surface, and the summary carries their CLASS" {
  for c in husk-pane husk-pane recycle-dead; do
    printf '{"kind":"handoff-alarm","class":"%s","pane":"p","sid":"s","detail":"d","ts":"t"}\n' "$c" \
      > "$CC_HANDOFF_ALARM_DIR/alarm-$c-$RANDOM.json"
  done
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
  grep -q '3 handoff-alarm(s)' "$CC_NOTIFY_BIN.log"
  # the class is the idea; "3 handoff-alarm(s)" alone names the kind and says nothing
  grep -q '2 husk-pane' "$CC_NOTIFY_BIN.log"
  grep -q '1 recycle-dead' "$CC_NOTIFY_BIN.log"
  grep -q '"new_handoff_alarms":3' "$CC_IDL"
}

@test "collect · an aged handoff-alarm record is TTL-compacted, a young one is kept" {
  mk_old   "$CC_HANDOFF_ALARM_DIR/old.json"
  mk_young "$CC_HANDOFF_ALARM_DIR/new.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_HANDOFF_ALARM_DIR/old.json" ]
  [ -f "$CC_HANDOFF_ALARM_DIR/new.json" ]
}

# ══ D2 rung 4 — LOUD EXPIRY (acceptance A4) ═══════════════════════════════════════════════════════

@test "expiry · a record aging out UNREAD is counted out loud, never quietly unlinked" {
  mk_old "$CC_PAGES_DIR/old.page"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q '"store":"pages"' "$CC_EXPIRED_LEDGER"
  grep -q '"kind":"expired-unread"' "$CC_IDL"
  grep -q '"n":1' "$CC_IDL"
  [ ! -f "$CC_PAGES_DIR/old.page" ]        # the horizon itself is unchanged — it just says so now
}

@test "CONTROL: a record aging out that WAS read expires silently" {
  # The failure-distinct half. A ledger line on every drained record would be the alarm that always
  # fires, and it would carry exactly as many bits as one that never fires.
  export CC_STUB_VERDICT=delivered
  mk_young "$CC_PAGES_DIR/p.page"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(seen_count)" -gt 0 ]                # PROVEN delivered ⇒ it carries a .seen marker
  touch -t "$(date -v-9d +%Y%m%d%H%M)" "$CC_PAGES_DIR/p.page"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PAGES_DIR/p.page" ]          # reaped…
  [ ! -s "$CC_EXPIRED_LEDGER" ]            # …silently
  ! grep -q 'expired-unread' "$CC_IDL" || false
}

@test "expiry · a record acked via the LITERAL key alone (cc-escalations) expires silently" {
  # The D5 integration point. `cc-escalations ack` can only name a record by BASENAME, so the ack it
  # leaves is the literal key with no hash beside it. If the expiry scan read only the hash, every
  # explicitly-acked record would age out reported as never-read — the nag would come back louder
  # for exactly the records the operator had already dealt with.
  mkdir -p "$CC_SWEEP_SEEN_DIR"
  mk_old "$CC_PAGES_DIR/old.page"
  : > "$CC_SWEEP_SEEN_DIR/old.page.seen"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PAGES_DIR/old.page" ]        # still reaped on the horizon…
  [ ! -s "$CC_EXPIRED_LEDGER" ]            # …and silently, because it WAS read
  ! grep -q 'expired-unread' "$CC_IDL" || false
}

@test "expiry · a record that was only BANNERED still counts as unread" {
  # banner ≠ read is the whole reason .bannered is a separate store from .seen. If the expiry scan
  # accepted either marker, the D2 revision would have re-created the silent loss it removed.
  rm -f "$CC_ROLES_DIR/desk"
  export CC_SWEEP_OS_CHANNEL=auto
  mk_young "$CC_PAGES_DIR/p.page"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(bannered_count)" -eq 1 ]
  [ "$(seen_count)" -eq 0 ]
  touch -t "$(date -v-9d +%Y%m%d%H%M)" "$CC_PAGES_DIR/p.page"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q '"kind":"expired-unread"' "$CC_IDL"
}

# ══ D4 — AUTHOR-DEATH JOIN (plan §D4, acceptance A5) ══════════════════════════════════════════════
# INTENT (teardown marker) + no OUTCOME (close-attrib row) + WORLD (pane still listed) ⇒ the watcher
# itself died. Every other combination is benign and must stay silent.

@test "D4 · aged marker + no close outcome + pane STILL PRESENT ⇒ exactly one orphan record" {
  mk_marker m1.json 289 terminal
  export CC_STUB_IT2_OUT="240
289
7"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 1 ]
  grep -q '"class":"handoff-orphan"' "$CC_HANDOFF_ALARM_DIR"/*.json
  grep -q '"pane":"289"' "$CC_HANDOFF_ALARM_DIR"/*.json
  grep -q 'teardown mode=terminal armed' "$CC_HANDOFF_ALARM_DIR"/*.json
  grep -q 'no close outcome; pane still open' "$CC_HANDOFF_ALARM_DIR"/*.json
  [ -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]
  grep -q '"join":"orphan"' "$CC_IDL"
  # the record is a first-class escalation: surfaced in the SAME sweep that raised it
  grep -q '1 handoff-alarm(s) (1 handoff-orphan)' "$CC_NOTIFY_BIN.log"
  # IDEMPOTENT — a marker is adjudicated once, ever
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 1 ]
}

@test "D4 · a marker younger than the deadline is not yet due" {
  mk_marker m1.json 289 terminal young
  export CC_STUB_IT2_OUT="289"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  [ ! -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]
  # POSITIVE CONTROL: the same marker, aged past the deadline, DOES alarm
  touch -t "$(date -v-1H +%Y%m%d%H%M)" "$CC_TEARDOWN_DIR/m1.json"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(ha_count)" -eq 1 ]
}

@test "D4 · a close OUTCOME row for the same id is benign — no alarm" {
  mk_marker m1.json 289 terminal
  export CC_STUB_IT2_OUT="289"
  printf '{"ts":"2026-08-07T09:00:00Z","site":"self-close","mode":"self","terminal":"kitty","id_requested":"289","owner":"operator-or-unknown","verdict":"closed"}\n' \
    > "$CC_CLOSE_ATTRIB_LOG"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  [ -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]
  grep -q '"closed":1' "$CC_IDL"
  # POSITIVE CONTROL beside the absence: same fixture, outcome row removed, marker re-armed
  : > "$CC_CLOSE_ATTRIB_LOG"
  rm -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(ha_count)" -eq 1 ]
}

@test "D4 · a BLIND world probe (rc 124) never alarms AND never acquits — it retries" {
  mk_marker m1.json 289 terminal
  export CC_STUB_IT2_RC=124                # cut at the bound: we learned nothing about the world
  export CC_STUB_IT2_OUT="289"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  [ ! -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]   # withholding the marker IS the retry
  grep -q '"no_data":1' "$CC_IDL"
  # POSITIVE CONTROL: the retry is real — the next tick, with a probe that answers, alarms
  unset CC_STUB_IT2_RC
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(ha_count)" -eq 1 ]
}

@test "D4 · pane ABSENT from the listing is benign (vendor close / fail-open attrib)" {
  mk_marker m1.json 289 terminal
  export CC_STUB_IT2_OUT="240
7"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  [ -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]
  grep -q '"benign_gone":1' "$CC_IDL"
}

@test "D4 · the pane id is matched as a WHOLE TOKEN, never as a substring" {
  # Measured against the live fleet 2026-08-07: `it2 session list` returns SHORT NUMERIC ids on this
  # box (kitty-normalised — `240 7 263 261 …`), so a substring predicate matched 40 of the 1,013
  # aged teardown markers, every one a false orphan. Exact-token matched 0. A blob match counts the
  # wrong thing (memory: pgrep-f-matches-agent-briefs).
  mk_marker m1.json 4 terminal             # `4` is a substring of `240` and of nothing that is live
  export CC_STUB_IT2_OUT="240
263"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  # POSITIVE CONTROL: the very same id, now genuinely in the listing, DOES alarm
  rm -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked"
  export CC_STUB_IT2_OUT="240
4"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(ha_count)" -eq 1 ]
}

@test "D4 · a marker with no pane key is closed out, and the world is never probed for it" {
  printf '{"key_kind":"sid","pane":"","sid":"S-1","mode":"recycle","ts":"2026-08-07T00:00:00Z"}\n' \
    > "$CC_TEARDOWN_DIR/m1.json"
  touch -t "$(date -v-1H +%Y%m%d%H%M)" "$CC_TEARDOWN_DIR/m1.json"
  export CC_STUB_IT2_OUT="240"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  [ -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]
  grep -q '"no_pane_key":1' "$CC_IDL"
  [ ! -f "$CC_IT2_BIN.log" ]               # the bounded probe is not even forked
}

@test "D4 · the kill switch (CC_HANDOFF_JOIN=0) suppresses the join entirely" {
  mk_marker m1.json 289 terminal
  export CC_STUB_IT2_OUT="289"
  CC_HANDOFF_JOIN=0 run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(ha_count)" -eq 0 ]
  [ ! -f "$CC_SWEEP_SEEN_DIR/m1.json.orphan-checked" ]
  # POSITIVE CONTROL: without the switch, the identical fixture alarms
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$(ha_count)" -eq 1 ]
}

# ── W1 · THE CURRENCY PASS IS ACTUALLY CALLED (backlog b585e86ea4e4) ─────────────────────────────
# `cc-premise sweep`/`screen` were built, documented and invoked by NOTHING — the fourth zero-caller
# in this subsystem. Wiring them and not asserting the CALL would reproduce the defect one layer up:
# a caller that exists in the file and never fires reads exactly like no caller at all. These cases
# assert the fire, the interval gate that keeps it off the 5-minute path, and the journal fields a
# reader would use to tell "held back" from "ran and found nothing".

@test "W1 · the currency pass FIRES and journals what it did" {
  export CC_PREMISE_PASS_STAMP="$BATS_TEST_TMPDIR/premise-pass.stamp"
  export CC_BACKLOG_VALIDATED="$BATS_TEST_TMPDIR/validated.json"
  export CC_PREMISE_PASS_EVERY_S=0                      # due now
  export CC_PREMISE_REPO="$REPO"
  # One row carrying a probe that PASSES, so the pass has something real to record and retire.
  local id; id="$("$CC_BACKLOG_BIN" add --title "w1 currency fixture" --project probe \
                    --source test --falsifier "true")"
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q '"premise_pass_rc":"0"' "$CC_IDL"
  grep -q '"premise_pass_note":"ok"' "$CC_IDL"
  [ -f "$CC_PREMISE_PASS_STAMP" ]
  # KEYED ON THIS TEST'S OWN ROW, never on an absolute count. Other arms of this same sweep FILE
  # ROWS — `settings-drift-assert` files one carrying its own falsifier, and whether it fires depends
  # on the real config dirs on the box — so `premise_rows_validated:1` asserts over a population the
  # subject perturbs and the environment decides. It read 2 on this machine
  # (memory: exact-count-assertion-tripwires-its-own-subject, span-must-equal-its-subject).
  run "$CC_BACKLOG_BIN" list --all --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "done" ]
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.evidence')" != "" ]
  # …and the row's currency stamp exists, which is the fact the pass is FOR.
  [ "$(jq -r --arg i "$id" '.rows[$i].verdict // "MISSING"' "$CC_BACKLOG_VALIDATED")" = "falsified" ]
}

@test "W1 · the interval gate HOLDS the pass off the 5-minute path" {
  # The sweep fires at StartInterval 300; the pass costs 106 s measured. Without this gate it would
  # spend a third of the box's sweep budget re-asking questions that move on the scale of a landing.
  export CC_PREMISE_PASS_STAMP="$BATS_TEST_TMPDIR/premise-pass.stamp"
  export CC_BACKLOG_VALIDATED="$BATS_TEST_TMPDIR/validated.json"
  export CC_PREMISE_PASS_EVERY_S=99999
  export CC_PREMISE_REPO="$REPO"
  local id; id="$("$CC_BACKLOG_BIN" add --title "w1 gate fixture" --project probe --source test \
    --falsifier "true")"
  : > "$CC_PREMISE_PASS_STAMP"                          # a pass just ran
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q '"premise_pass_note":"not-due"' "$CC_IDL"
  # The held-back proof is that this row — whose probe PASSES, so a running pass would retire it —
  # is untouched and unstamped. Asserted on the row, not on a count, for the reason in the case above.
  run "$CC_BACKLOG_BIN" list --all --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "open" ]
  [ ! -s "$CC_BACKLOG_VALIDATED" ]
  # POSITIVE CONTROL: the identical fixture DOES fire once the interval has elapsed, so this test
  # cannot pass merely because the block is broken or absent.
  #
  # `export` on its own line, NOT a `VAR=x run …` prefix. A one-shot assignment in front of bats'
  # `run` does not reach the subshell it forks, so the prefixed form left EVERY_S at 99999 and the
  # control "failed" while the subject was working perfectly — a harness defect that reads exactly
  # like a real red (memory: verification-harness-vacuous-pass-traps).
  : > "$CC_IDL"
  export CC_PREMISE_PASS_EVERY_S=0
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  grep -q '"premise_pass_note":"ok"' "$CC_IDL"
  run "$CC_BACKLOG_BIN" list --all --json
  [ "$(printf '%s' "$output" | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = "done" ]
}

@test "W1 · a RED ratchet files one self-falsifying row instead of only a JSON field" {
  # ratchet_rc read RED on every recorded run and its only consequence was being written down.
  export CC_PREMISE_PASS_EVERY_S=99999                   # keep this case about the ratchet alone
  export CC_PREMISE_PASS_STAMP="$BATS_TEST_TMPDIR/premise-pass.stamp"; : > "$CC_PREMISE_PASS_STAMP"
  export CC_RATCHET_STATE="$BATS_TEST_TMPDIR/ratchet.json"
  # A high-water the current store cannot meet ⇒ --assert returns 1, which is the real red path.
  printf '{"coverage_high_water":"99.0","denominator_version":2,"recorded":"2020-01-01T00:00:00Z"}\n' \
    > "$CC_RATCHET_STATE"
  "$CC_BACKLOG_BIN" add --title "w1 ratchet fixture" --project probe --source test >/dev/null
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q '"ratchet_filed":"filed"' "$CC_IDL"
  run "$CC_BACKLOG_BIN" list --open --json
  [ "$(printf '%s' "$output" | jq -r '[.[]|select(.condition=="backlog-ratchet-coverage-regression")]|length')" = "1" ]
  # …and it carries its OWN falsifier, so it retires itself when coverage recovers.
  [ "$(printf '%s' "$output" | jq -r '[.[]|select(.condition=="backlog-ratchet-coverage-regression")][0]|.falsifier|length>0')" = "true" ]
}

# ── THE HANG'S OWN GUARD (backlog 2d67e9dff07b) ─────────────────────────────────────────────────
# Asserting the setup() export would only assert that a line exists. What wedged the suite was a
# BEHAVIOUR — an add spawning a live dispatch pass that holds bats' fd 3 — so this asserts the
# behaviour, on the one arm that reliably reaches `cc-backlog add`: the ratchet's consumer.
#
# THE CONTROL IS NOT OPTIONAL. Without it "the stub was never called" passes just as well when the
# add path is broken, when the ratchet never files, or when the stub is unreachable — three ways to
# green with the mechanism absent, which is precisely this file's recorded trap
# (memory: verification-harness-vacuous-pass-traps). The control re-runs the identical fixture with
# the switch flipped and requires the kick to LAND, so this case can only pass while the spawn is
# real and the switch is what stops it.
@test "the suite never fires the live dispatcher — cc-backlog's kick is stubbed AND switched off" {
  export CC_PREMISE_PASS_EVERY_S=99999
  export CC_PREMISE_PASS_STAMP="$BATS_TEST_TMPDIR/premise-pass.stamp"; : > "$CC_PREMISE_PASS_STAMP"
  export CC_RATCHET_STATE="$BATS_TEST_TMPDIR/ratchet.json"
  printf '{"coverage_high_water":"99.0","denominator_version":2,"recorded":"2020-01-01T00:00:00Z"}\n' \
    > "$CC_RATCHET_STATE"
  "$CC_BACKLOG_BIN" add --title "kick guard fixture" --project probe --source test >/dev/null

  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q '"ratchet_filed":"filed"' "$CC_IDL"          # the add really happened…
  [ ! -f "$CC_BACKLOG_KICK_BIN.log" ]                  # …and nothing was spawned

  # The kick bin must be OURS, never the operator's — the belt that survives a deleted switch.
  case "$CC_BACKLOG_KICK_BIN" in "$BATS_TEST_TMPDIR"/*) ;; *) return 1 ;; esac

  # POSITIVE CONTROL: same fixture, switch on ⇒ the kick lands, in the stub and not in ~/.claude/bin.
  # `export` on its own line, not a `VAR=x run …` prefix — the prefixed form does not reach the
  # subshell bats forks (the harness defect recorded on the W1 interval-gate case above).
  rm -f "$CC_RATCHET_STATE"
  printf '{"coverage_high_water":"99.0","denominator_version":2,"recorded":"2020-01-01T00:00:00Z"}\n' \
    > "$CC_RATCHET_STATE"
  : > "$CC_IDL"
  export CC_BACKLOG_KICK=on
  run "${SWEEP_TO[@]}" bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$CC_BACKLOG_KICK_BIN.log" ]
}

# ── THE BOUND ITSELF (post-land HUNG, backlog 6b42d1f49770) ──────────────────────────────────────
# A wrapper that is present in the file and never fires reads exactly like no wrapper at all — this
# subsystem's own recurring defect, and the reason the W1 cases above exist. So the bound gets the
# same treatment: one case proving the resolved binary really cuts a wedging subject, and one
# proving no call site escaped the wrap. Together they are what stops this file returning to HUNG,
# where postland-verify's 300 s file bound was the only thing that ever came back.

@test "THE BOUND IS LIVE: a wedging subject is CUT into a named red, never a wedged file" {
  # Skipped rather than red where neither timeout(1) nor gtimeout(1) exists: setup()'s ladder is
  # fail-open there by design (a suite that refused to run without coreutils would be a new red on
  # every box that has none), and a skip says that out loud instead of certifying a bound that
  # cannot exist. `env` is the no-op prefix the ladder falls back to.
  [ "${SWEEP_TO[0]}" != "env" ] || skip "no timeout(1)/gtimeout(1) resolvable — the bound is fail-open here"
  local wedge="$BATS_TEST_TMPDIR/wedge.sh"
  # A subject that never returns, standing in for the un-stubbed fork that produced the real HUNG.
  # Bounded at 1 s HERE rather than at the suite default, so this case costs a second and not 30.
  printf '#!/bin/bash\nsleep 600\n' > "$wedge"
  run "${SWEEP_TO[0]}" -k 1 1 bash "$wedge"
  [ "$status" -eq 124 ]                    # timeout(1)'s contract — the cut, not a signal-shaped death
}

@test "NO UNBOUNDED SUBJECT RUN survives in this file" {
  # The wrap is worth nothing if the next case added here copies the old shape, and a hang is the
  # one failure that cannot report itself. Keyed on the EXECUTION form (`run bash "$SWEEP"`), never
  # on the string $SWEEP, which the static-read cases above use legitimately.
  run grep -cE '^[^#]*run bash "\$SWEEP"' "$BATS_TEST_FILENAME"
  [ "$output" = "0" ]
  # POSITIVE CONTROL: the pattern DOES match the shape it is meant to catch, so a green here cannot
  # merely mean the regex rotted (memory: verification-harness-vacuous-pass-traps).
  run grep -cE '^[^#]*run bash "\$SWEEP"' <(printf '  run bash "$SWEEP"\n')
  [ "$output" = "1" ]
}

@test "THE LADDER NESTS: every inner bound is strictly below the harness wrap" {
  # The two halves of this fix were authored independently against the same wedge, and merging them
  # put the subject's per-arm bound and the harness wrap at the SAME 30 s. Equal is not a detail:
  # the outer cut lands first on every wedge, so `fold_rc` / `premise_pass_note` can never carry a
  # 124 and the one instrument that says "re-measure the band" goes permanently silent while
  # reading healthy. Asserted rather than commented, because the failure is invisible — both bounds
  # still exist, both still fire, and only the ORDER is wrong.
  #
  # Read from the environment setup() actually exported, never from the literals above: a defaulted
  # `${VAR:-n}` means an operator override is what is live, and an assertion over the literal would
  # certify a ladder the run is not using (memory: assertion-span-must-equal-its-subject).
  [ "${SWEEP_TO[0]}" != "env" ] || skip "no timeout(1)/gtimeout(1) resolvable — the wrap is fail-open here"
  local outer="${SWEEP_TO[${#SWEEP_TO[@]}-1]}"          # the seconds argument of `<tmo> -k 5 <n>`
  [ "$outer" -gt 0 ] || false                            # positive control: we read a number, not ""
  [ "$CC_SWEEP_BOUND_S" -lt "$outer" ] || false
  [ "$CC_PREMISE_PASS_BOUND_S" -lt "$outer" ] || false
}
