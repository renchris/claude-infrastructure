## Findings

---

### 1. The "all six event dirs" reap test only exercises five dirs; the announce-alarm dir is never checked

**Where** — line 163 (test name) and lines 164–168 / 173–177 (the cases):

```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
```
```bash
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong** — `CC_ANNOUNCE_ALARM_DIR` (line 12, drained by the tests at lines 76, 138, 310, 330, 349, 367) gets neither a reap nor a keep assertion anywhere in the file. Per the file's own doctrine at lines 156–158, that dir is therefore unprotected in both directions: if its reaper never runs the dir grows without bound, and if its horizon collapses to zero it eats live alarms — and the suite stays green either way, while claiming in its own test name to cover all six.

---

### 2. The "old shape is gone" pin matches one exact byte-string, not the class of defect it names

**Where** — lines 389, 391:

```bash
@test "the old shape is gone: the notify call is neither rc-discarded nor stderr-discarded" {
```
```bash
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
```

**Why it is wrong** — the guard is a literal search for one historical line. Any re-spelling that still discards the outcome — `"$NOTIFY" --role desk "$summary" >/dev/null 2>&1 || true`, or the same call split across two lines, or `2>&1 >/dev/null` with `|| :` — does not match, so `grep -c` prints `0` and the test passes with the exact data-loss shape (rc discarded, stderr discarded) present in the script. The name claims a class; the code covers one string.

---

### 3. The horizon assertion is an unanchored substring: it passes for a 70-day (or 7000-day) horizon

**Where** — lines 214–216:

```bash
@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```

**Why it is wrong** — the pattern matches `${CC_EVENT_TTL_DAYS:-70}`, `${CC_EVENT_TTL_DAYS:-7000}`, and any occurrence inside a comment or a dead code path. A script whose real default is 70 days satisfies a test whose stated subject is "the horizon is 7 days". (Secondarily, the arithmetic in the name is wrong: 7 days = 604 800 s against the stated 6 000 s floor is two orders of magnitude, not three; and line 344's comment puts the sweep cadence at 300 s while line 213 puts it at 600 s.)

---

### 4. The exemption/keep-only tests pass if the reaper never ran at all

**Where** — lines 181–187, and lines 206–210:

```bash
@test "decisions/ is exempt: an old decision packet survives the reap" {
```
```bash
  [ -f "$CC_DECISIONS_DIR/old.json" ]
```
```bash
@test "a YOUNG .escalated marker with no mailbox is still kept (horizon, not lifecycle)" {
```
```bash
  [ -f "$CC_INBOX_GUARD_STATE_DIR/PANE-C.escalated" ]
```

**Why it is wrong** — both runs assert only that a file survived, and nothing in either run establishes that the reaper executed. If the reaper is disabled, crashes early, or its directory list is empty, both tests are green while proving nothing about exemption or about the horizon. This is exactly the failure the file forbids at line 158 ("Asserting only the keep ... would stay green if the reaper never ran at all") — neither run contains a co-located old-file-in-a-reaped-dir control.

---

### 5. Two "never marks seen" assertions are vacuous when markers land outside `CC_SWEEP_SEEN_DIR`

**Where** — lines 352 and 370:

```bash
  [ -z "$(ls -A "$CC_SWEEP_SEEN_DIR" 2>/dev/null)" ]
```

**Why it is wrong** — `setup()` exports `CC_SWEEP_SEEN_DIR` (line 17) but never creates it, and `ls` failures are swallowed, so the test is satisfied by "the directory does not exist". If the sweep stops honoring that variable and writes markers to its `$HOME` default instead, both the REFUSED test and the UNREADABLE test pass while every record is silently forgotten — the precise loss described at lines 300–302 — and they also pollute live state, the hazard flagged at lines 21–24. Unlike the mailbox-only test, which backs the same claim with a behavioural re-surface check (lines 319–321, `[ "$(notify_count)" -eq 2 ]`), these two have no second-run check to make the claim failure-distinct.

---

### 6. `[ -s "$OSA_LOG" ]` proves only that `osascript` was invoked, not that anything reached a human

**Where** — line 333, with the stub at lines 56–57:

```bash
  [ -s "$OSA_LOG" ]                        # something was actually put in front of a human
```
```bash
cat >/dev/null
printf '%s\n' "$*" >> "$OSA_LOG"
```

**Why it is wrong** — the stub discards the script body it is handed and logs only `$*`, then unconditionally appends a newline. If the sweep passes the AppleScript on stdin (which the `cat` implies) or invokes `osascript` with an empty/malformed argument list, the log is a 1-byte newline and `-s` is true. The test then concludes "operator reached" and, on that unproven premise, asserts `"delivered":true` (line 335) and that the records may be forgotten (lines 337–339). Nothing anywhere asserts that the notification body contains the escalation.

---

### 7. The summary-distinction test has no positive control for the label it asserts is absent

**Where** — lines 401, 408:

```bash
@test "the summary distinguishes queued fires from no-change fires" {
```
```bash
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
```

**Why it is wrong** — the only evidence that "fired→backlog" is the sweep's queued-fire label is this negative grep. If that wording is renamed, removed, or was never emitted, the assertion is trivially true and the test still passes on a sweep whose summary reports a bare total ("1 item queued") — the exact misreading the comment at line 406 exists to prevent. The file uses an explicit positive control for the analogous backlog claim (line 249) but not for this one.

---

### Weaker, but pointable

**8. `notify_count` counts log lines, not invocations.** Line 64, with the stub at line 41:

```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
```bash
echo "$@" >> "$0.log"
```

Every `-eq 1` / `-eq 2` assertion in the file (lines 79, 87, 95, 108, 130, 146, 240, 313, 321, 339, 385) reads line count as call count. That holds only while the summary argument is single-line; the moment the sweep emits a multi-line summary — plausible given it must carry both the "no-change: surfaced, NOT dispatched" and queued-fire segments — one invocation counts as several and the assertions measure the wrong quantity.

**9. The `osascript` stub drains inherited stdin unconditionally.** Line 56, `cat >/dev/null`. `run` does not redirect stdin, so if the sweep invokes `osascript -e ...` (no stdin script) the stub consumes — or, when the runner's stdin is a terminal, blocks on — the test process's stdin rather than a script it was handed.

Everything else I checked held up: the reap polarities (lines 173–177), the cumulative notify-count arithmetic in the two-run tests, the `mk_old` / re-`touch` ordering in the decisions test (lines 182–184 does end with a −30d mtime), the `! … || false` negation idiom, and `[ "$output" = "0" ]` against `grep -c` under `run`.
