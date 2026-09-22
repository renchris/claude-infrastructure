# Review of `tests/autonomy-sweep.bats`

I found four defects. All four are in the test suite's coverage claims, not in the setup's hermeticity.

---

### 1. The "all six event dirs" reap test only covers five

**What:** The test claims to check age-reaping in all six event dirs, but it only seeds and asserts five of them. The announce-alarm dir gets no old-reaped / young-kept pair.

**Where:** lines 162–176, for example:
- L162: `@test "all six event dirs: records past the horizon are reaped, young ones kept" {`
- L163–167: `mk_old` / `mk_young` calls only for `$CC_PAGES_DIR`, `$CC_COMMS_ALARM_DIR`, `$CC_PUSH_RECORDS_DIR`, `$CC_COMPLETION_RECORDS_DIR`, `$CC_TEARDOWN_RECORDS_DIR`
- L172–176: the matching `[ ! -f … ]; [ -f … ]` pairs for the same five dirs

**Why it is wrong:** The setup (L20–21) says the sweep age-reaps six event dirs. Six event dirs are exported. The sixth, `CC_ANNOUNCE_ALARM_DIR` (L11), appears nowhere in this test. The inbox-guard dir is a separate lifecycle reap with its own tests. So any of these sweeps passes while the test reports "all six" green:
- one that never reaps the announce-alarm dir;
- one that reaps it with a collapsed horizon and deletes live alarms;
- one that reaps it from a `$HOME` default path.

The L155–157 comment says each case must assert the failure-distinct pair. That is exactly what is missing for this dir.

---

### 2. The "old shape is gone" pin cannot detect the shape it claims to forbid

**What:** The test says it proves the notify call is neither rc-discarded nor stderr-discarded, and that it pins "the exact three lines". It actually checks that one exact literal string is absent. The current call form can never produce that string.

**Where:**
- L389: `@test "the old shape is gone: the notify call is neither rc-discarded nor stderr-discarded" {`
- L390: `  # The exact three lines that made this a data-loss bug, pinned so they cannot come back.`
- L391: `  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"`

**Why it is wrong:**
- The pattern requires the literal `"$DESK_TARGET"` argument. The sweep now addresses the desk by role (L81 requires `--role desk`).
- So a regression such as `"$NOTIFY" --role desk "$summary" >/dev/null 2>&1 || true` gives `grep -c` a count of `0`, and the test passes. The same is true for `… 2>/dev/null || true`, or any spacing change.
- The third line the comment claims to pin, the unconditional `mark_seen`, is not checked at all.
- The other assertions (L393–398) only check that two strings are present somewhere and that the syntax is valid. They say nothing about how the notify call handles rc or stderr.

---

### 3. The "horizon is 7 days" test proves only that a substring exists in the file

**What:** The test claims the event horizon is 7 days. Its only evidence is a substring match that also matches other defaults, comments, and dead code.

**Where:**
- L213: `@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {`
- L214: `  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"`

**Why it is wrong:**
- `grep -c 'CC_EVENT_TTL_DAYS:-7'` exits 0 for `${CC_EVENT_TTL_DAYS:-70}` or `:-75`.
- It also exits 0 if the text appears only in a comment or an unused variable while the actual `find` uses a different age, such as 1 day.
- The behavioral reap test (L162) only brackets the horizon between "a few seconds" (young kept) and 9 days (old reaped). So a 1-day or 8-day horizon with the string present anywhere passes both tests.
- The title's quantitative claim is also false: 7 d = 604,800 s against the 6,000 s floor (L212) is about 100×, which is two orders of magnitude, not three.

---

### 4. The OS-channel check proves only that `osascript` was run, not that anything was shown

**What:** The assertion "something was actually put in front of a human" passes on any invocation of the stub `osascript`, even one that carries no content.

**Where:**
- L55: `cat >/dev/null`
- L56: `printf '%s\n' "$*" >> "$OSA_LOG"`
- L333: `  [ -s "$OSA_LOG" ]                        # something was actually put in front of a human`

**Why it is wrong:**
- The stub throws away stdin, which is where the `cat >/dev/null` design implies the sweep sends the AppleScript.
- It then writes `"$*"` plus a newline, and that newline alone makes the file non-empty (`-s`) even with zero arguments.
- So an `osascript` call with an empty, truncated, or malformed script still satisfies L333.
- L334–335 then accept `"delivered":true` and the records get marked seen. That is exactly the "claimed outcome vs checked outcome" gap this section of the file says it guards against.
