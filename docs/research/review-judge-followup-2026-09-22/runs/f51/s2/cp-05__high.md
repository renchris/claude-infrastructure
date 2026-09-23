I read the file in full; here is what I found.

## Defect 1: the "all six event dirs" reap test covers only five

**What:** The test asserts reap-and-keep for five directories but never seeds or checks the announce-alarms directory, so the sixth reaped dir has no coverage at all.

**Where:** lines 163–177, starting at:
```
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
```
The seed and assert blocks touch `CC_PAGES_DIR`, `CC_COMMS_ALARM_DIR`, `CC_PUSH_RECORDS_DIR`, `CC_COMPLETION_RECORDS_DIR`, and `CC_TEARDOWN_RECORDS_DIR` only.

**Why it is wrong:** Setup states the sweep age-reaps six event dirs, and the only exported event dir not in this test is `CC_ANNOUNCE_ALARM_DIR`. If the reaper stops reaping that directory, or reaps young records from it, this test stays green. That is exactly the "reaper against live state" failure the setup comment warns about, left unguarded for one of the six dirs.

## Defect 2: the "young" side of the reap pair cannot detect a shrunken horizon

**What:** Young fixtures are created at age zero, so the keep assertions only fail if the horizon collapses to essentially nothing, not if it shrinks from seven days to, say, one day or one hour.

**Where:** line 161 and its uses at lines 164–168 and 207:
```
mk_young() { mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; }
```

**Why it is wrong:** The comment at lines 156–158 claims the old/young pair is failure-distinct against a collapsed horizon. A horizon regressed to one day would still keep a file written seconds ago, so every keep assertion passes while live records under a day old are eaten. A young fixture just inside the horizon, such as six days old, would be needed to make the claim true.

## Defect 3: the "old shape is gone" pin can no longer match anything

**What:** The regression pin greps for the old call line verbatim, but the notify call has since changed shape, so the pin is satisfied regardless of whether rc or stderr are discarded.

**Where:** lines 392–393:
```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  [ "$output" = "0" ]
```

**Why it is wrong:** Line 82 establishes that cc-notify is now invoked with `--role desk`, not with `"$DESK_TARGET"`. A reintroduced `>/dev/null 2>&1 || true` on the current call line has a different prefix, matches zero times, and the test passes. The assertion passes for the wrong reason and does not pin the data-loss shape it names.

## Defect 4: the notification-center dedup check is not anchored to a first-run count

**What:** The test only asserts the notify count after the second sweep, so it cannot distinguish "one notify then marked seen" from "zero notifies then one re-surface".

**Where:** line 340, inside the test starting at line 325:
```
  [ "$(notify_count)" -eq 1 ]
```

**Why it is wrong:** If a sweep with the OS channel set to auto skipped cc-notify on the first run and went straight to osascript, then re-surfaced the unmarked record on the second run and notified once, the final count would be one and the test would pass. That is the not-marked-seen storm the test claims to rule out. Every sibling test asserts the count after the first run; this one does not.

## Defect 5: the horizon assertion accepts any value beginning with 7

**What:** The grep pattern is an unanchored substring, so a default of 70 or 700 days satisfies a test titled "the event horizon is 7 days".

**Where:** line 215:
```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

**Why it is wrong:** `:-7` is a prefix of `:-70`, `:-7000`, and `:-7d`, and the check only requires at least one match anywhere in the file. A horizon changed to 700 days, which would keep every event record for two years, passes a test whose stated purpose is to pin the horizon at seven.

I found no defects in the setup redirection, the cc-notify stub, the negation idiom with `|| false`, or the delivery-verdict tests other than the one noted above.
