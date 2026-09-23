## Findings

### 1. The "all six event dirs" reap test exercises five dirs — `$CC_ANNOUNCE_ALARM_DIR` is never covered

**What** — The test that claims to pin the old-reaped/young-kept pair for all six write-only event dirs sets up and asserts only five of them; the cc-announce-alarms dir is absent from both the fixture block and the assertion block.

**Where** — lines 163–168 (fixtures) and 173–177 (assertions):
```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```
The six exported event dirs are `CC_PAGES_DIR` (11), `CC_ANNOUNCE_ALARM_DIR` (12), `CC_COMPLETION_RECORDS_DIR` (13), `CC_COMMS_ALARM_DIR` (25), `CC_PUSH_RECORDS_DIR` (26), `CC_TEARDOWN_RECORDS_DIR` (27).

**Why it is wrong** — If the announce-alarm reaper is missing, or its horizon collapses to 0 and it eats live alarms, nothing in the file fails. This test never touches that dir, and the alarm tests cannot see it either: at lines 75–88 a fresh alarm is written, the first sweep notifies, and the second sweep is asserted to leave `notify_count` at 1 — which is exactly what happens if the record was *deleted* after the first sweep rather than marked seen. The failure mode the section header at 155–158 says this test exists to catch ("would stay green if the horizon collapsed to 0 and ate live records") is live for one of the six dirs.

### 2. `grep -q 'no-desk-role\|undelivered'` does no alternation on the platform this suite targets

**What** — The "fail loud in IDL" check uses a GNU-only BRE alternation, which BSD/macOS grep treats as a literal `|`, so the check searches for a string the sweep never writes.

**Where** — line 142:
```bash
  grep -q 'no-desk-role\|undelivered' "$CC_IDL"     # loud, not silent
```

**Why it is wrong** — `mk_old` at line 160 uses `date -v-9d`, a BSD-only flag, so this suite is written to run against macOS's `/usr/bin/grep`, whose basic regex has no `\|` operator; the pattern degrades to the literal `no-desk-role|undelivered`. Whatever the sweep actually writes to the IDL — `no-desk-role` or `undelivered` — this line reports a failure, and the property it claims to verify (that the no-desk-role path is loud rather than silent) is never actually tested. The same grep would match only a literal that no producer emits.

### 3. `notify_count` counts log lines, not cc-notify invocations

**What** — The helper every delivery assertion depends on measures newlines in the stub's log, while the stub appends the whole argument list (including the summary) per call.

**Where** — line 64, with the stub at line 41:
```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
```bash
echo "$@" >> "$0.log"
```

**Why it is wrong** — If the summary argument contains a newline (line 408 greps the log for `"no-change: surfaced, NOT dispatched"` and line 409 for `"fired→backlog"`, i.e. a multi-part summary), one invocation writes several log lines. Then `[ "$(notify_count)" -eq 2 ]` at line 322 — whose entire claim is "the undelivered record re-surfaced on the **next** sweep" — is satisfied by a single sweep that emitted a two-line summary, and the data-loss regression this test exists for passes unnoticed. In the other direction, every `-eq 1` assertion fails for a reason that has nothing to do with the sweep's behaviour.

### 4. The unannotated-default test discards the sweep's exit status

**What** — The sweep's `$status` is overwritten by the next `run` before it is ever asserted, so this test reports success on a sweep that crashed.

**Where** — lines 268–269:
```bash
  run bash "$SWEEP"
  run bash "$CC_BACKLOG_BIN" list --open
```

**Why it is wrong** — If the sweep appends the backlog item and then dies non-zero (e.g. in the notify or IDL stage), line 270's grep still finds `carry this out` and the test passes, reporting a failing sweep as a success. Every sibling test in this section asserts `[ "$status" -eq 0 ]` immediately after the sweep. The same omission appears at lines 129–132, where neither sweep's status is checked.

### 5. `[ -s "$OSA_LOG" ]` cannot show that anything was put in front of a human

**What** — The osascript stub discards the payload and logs a newline for *any* invocation, so the assertion that proves the liveness-free channel "took it" is satisfied by a content-free call.

**Where** — lines 56–57 (stub) and line 334 (assertion):
```bash
cat >/dev/null
printf '%s\n' "$*" >> "$OSA_LOG"
```
```bash
  [ -s "$OSA_LOG" ]                        # something was actually put in front of a human
```

**Why it is wrong** — The stub's `cat >/dev/null` implies the sweep feeds the notification script on stdin; that content is thrown away and never asserted on. `printf '%s\n' "$*"` writes a bare newline when the argument list is empty, so the file is non-empty after an `osascript` call carrying an empty or malformed message. The sweep then records `"delivered":true` (line 336) and marks the records seen — records are forgotten on the strength of a post whose content this test never saw. This is the same "claimed outcome vs. checked outcome" shape the section header at 294–304 is written against.

### 6. The horizon check is a prefix match, so it does not establish "7 days"

**What** — The grep that pins the event TTL matches any default beginning with `7`.

**Where** — line 215:
```bash
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

**Why it is wrong** — With `${CC_EVENT_TTL_DAYS:-70}` (or `:-7000`) in the sweep, this pattern matches, `grep -c` exits 0, and the test passes while reporting that the horizon is 7 days. The horizon value is only cross-checked by the 9-day fixtures in the reap test — which, per finding 1, covers five of the six dirs, so an inflated horizon in the uncovered dir is checked by nothing at all.

### 7. The "distinguishes queued fires from no-change fires" negative is anchored to an unverified token

**What** — The test asserts the absence of `fired→backlog` in a run where no change-default exists, and nothing in the file ever proves the sweep emits that token when it does queue something.

**Where** — lines 403–409:
```bash
  bash "$CC_DECIDE_BIN" open --class B --what "nc" --default "hold it" \
    --deadline "2000-01-01T00:00:00Z" --default-effect no-change >/dev/null
...
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
```

**Why it is wrong** — If the summary is reworded so the queued-fire count is reported under any other token, the negative assertion becomes unconditionally true and the miscount it exists to catch ("reporting only the total would read as '1 item queued' on a sweep that queued none") sails through. The suite pins the positive side of every other carve-out claim (lines 250–261, 375–388) but not this one, and no test in the file ever asserts that `fired→backlog` appears on a sweep that actually queued an item.

---

**Non-behavioural notes** (not counted above): the file header at line 5 states the sweep "appends each fired class-B default as a cc-backlog item", which the carve-out at lines 232–248 makes false; the test name at line 214 says "three orders of magnitude above the lint floor" while the floor stated at line 213 is 6,000 s and 7 days is ~100× that; the sweep interval is given as 600 s at line 213 and 300 s at line 345.
