# Review of `tests/autonomy-sweep.bats`

Line numbers are counted from the `#!/usr/bin/env bats` line as line 1.

---

### 1. The "all six event dirs" reap test seeds and checks only five directories

- **What:** The test says it covers all six event dirs, but it only seeds and asserts pages, comms-alarms, push-records, completion and teardown. `CC_ANNOUNCE_ALARM_DIR` (`cc-announce-alarms/`) has no old/young pair.
- **Where:** lines 162–176, for example
  `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`
  and `  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"` (the five `mk_old` lines, followed by the five `[ ! -f … ]; [ -f … ]` lines).
- **Why it is wrong:**
  - The file header lists `cc-announce-alarms/` as one of the write-only escalation dirs the sweep drains. The setup comment says the sweep "age-reaps six event dirs".
  - If the sweep stopped reaping the announce-alarm dir, the test would stay green.
  - If the sweep reaped that dir with a collapsed horizon that deletes live alarms, the test would also stay green.
  - The section's own L2 rule (assert both "OLD reaped" and "YOUNG kept") is therefore not applied to one of the six directories the test claims to cover.

### 2. The "old shape is gone" guard only matches one exact historical string

- **What:** The regression guard for the rc-discarded and stderr-discarded notify call is a literal grep for one exact line. It cannot detect the same bug in any other form.
- **Where:** lines 391–392
  `  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"`
  `  [ "$output" = "0" ]`
- **Why it is wrong:**
  - The sweep now addresses cc-notify by `--role desk` (asserted at line 81, `grep -q -- '--role desk' "$CC_NOTIFY_BIN.log"`), so the pinned `"$DESK_TARGET"` argument shape no longer exists.
  - Reintroducing the bug in the current shape would not match the grep, and the count would stay `0`. Examples that would pass:
    - `"$NOTIFY" --role desk "$summary" >/dev/null 2>&1 || true`
    - a version with only `2>/dev/null`
    - a version with only `|| true`
    - different quoting or spacing
  - The test name claims "neither rc-discarded nor stderr-discarded", but the check is effectively vacuous.
  - The comment says "the exact three lines" are pinned, but the third element (unconditional `mark_seen`) is not pinned at all. The other two checks only prove that some new strings are present.

### 3. The "7-day horizon" test only proves a string appears somewhere in the script

- **What:** The horizon check is a text grep for `CC_EVENT_TTL_DAYS:-7` anywhere in the file. It does not show that the reaper actually uses that value.
- **Where:** line 214
  `  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"`
- **Why it is wrong:**
  - A comment, a dead assignment, or a variable the reap `find` never reads would all satisfy `grep -c`, which exits 0 on one or more matches.
  - The behavioral reap test (9-day-old records reaped, freshly created records kept) only bounds the horizon between "a few seconds" and "9 days".
  - So a reaper running on, say, a 1-hour horizon passes both tests while the name asserts "the event horizon is 7 days".

### 4. The horizon test's name overstates the margin by 10×

- **What:** The test title claims the horizon is three orders of magnitude above the lint floor. It is about two.
- **Where:** line 213
  `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {`
- **Why it is wrong:**
  - 7 days is 604,800 s, and the stated floor (line 212 comment) is 6,000 s. The ratio is about 101×, which is two orders of magnitude.
  - Nothing asserts the claimed margin, so the test passes regardless.
  - The comments also disagree about the sweep period: line 212 says 600 s, while the REFUSED test (line 344) says the sweep re-surfaces records "every 300 s". At 300 s the floor would be 3,000 s.

### 5. The "second run abstains" claim is never asserted

- **What:** The test name says the second run abstains, but after that run the test only checks the notify count. It never checks for an `abstained` disposition.
- **Where:** lines 74 and 84–86
  `@test "a new alarm → one notify to the desk role; a second run (nothing new) abstains" {`
  `  [ "$(notify_count)" -eq 1 ]`
- **Why it is wrong:** Suppose the second run wrote another `"disposition":"fired"` record, or wrote no IDL record at all, while simply not calling cc-notify. The test would still pass, even though its stated property (abstain) does not hold.

### 6. The OS-channel check proves only that osascript was invoked, not that anything was posted

- **What:** `[ -s "$OSA_LOG" ]` is claimed to show "something was actually put in front of a human". The stub makes it true on any invocation, whatever the content.
- **Where:** lines 55–56 (stub) and line 333
  `cat >/dev/null`
  `printf '%s\n' "$*" >> "$OSA_LOG"`
  `  [ -s "$OSA_LOG" ]                        # something was actually put in front of a human`
- **Why it is wrong:**
  - The stub discards stdin, which is where a piped AppleScript would arrive.
  - It logs only argv, and `printf '%s\n' ""` writes one newline even with zero arguments.
  - As a result, an invocation with an empty or broken script still makes the log non-empty. The test then records `"delivered":true` as proven even though no notification content was shown to the operator.

---

I found no other defects. The remaining assertions (the RECORDED/REFUSED/UNREADABLE/REACHED delivery pairs, the no-change carve-out with its positive control, and the project fallback) test what they claim.
