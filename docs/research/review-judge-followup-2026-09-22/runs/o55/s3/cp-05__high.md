# Review: `tests/autonomy-sweep.bats`

I found four defects. All are guards that do not cover what they claim to cover.

---

### 1. The "all six event dirs" reap test only exercises five dirs

**What:** The test says it proves age-reaping across all six write-only event dirs, but it seeds and asserts only five. The announce-alarm dir (`CC_ANNOUNCE_ALARM_DIR`) is never covered.

**Where:** lines 163–177, e.g.
```
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
```
and the five seed lines 164–168:
```
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong:** Line 22 says the sweep "age-reaps six event dirs". Decisions and inbox-guard are handled as exclusions elsewhere (lines 180–211), and announce-alarms is the one drained event dir that is left out here. Two failures would stay green:
- The reaper never runs on the announce-alarm dir, so it grows without bound.
- The horizon for that dir collapses to 0 and deletes live alarms.

In both cases the suite still reports the six-dir invariant as proven.

---

### 2. The "old shape is gone" pin cannot detect the regression it names

**What:** The anti-regression test only checks for one exact literal string that the current code no longer uses. The other checks prove that some tokens are present, not that the discards are absent.

**Where:** line 392:
```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
```
and lines 394/396:
```
  run bash -c "grep -q 'notify_verdict:=unreadable' '$SWEEP'"
  run bash -c "grep -q 'CC_SWEEP_OS_CHANNEL' '$SWEEP'"
```

**Why it is wrong:**
- The sweep now addresses the desk by role (line 82 asserts `--role desk`), so `$DESK_TARGET` no longer appears in the call. Reintroducing `>/dev/null 2>&1 || true` on the new call, or on any reworded call, gives a count of `0` and the test passes.
- The comment on line 391 says "The exact three lines… pinned". The unconditional `mark_seen` line is not pinned at all.
- Lines 394 and 396 pass as long as those strings appear anywhere, even in comments, while rc and stderr are still discarded.

---

### 3. The REFUSED and UNREADABLE tests never check that cc-notify was called

**What:** Both tests say they exercise a specific cc-notify outcome, but neither asserts that the notifier was invoked. They pass just as well if the sweep never reaches the notify step.

**Where:** REFUSED, lines 343–357 (no `notify_count` assertion), e.g.
```
  [ -z "$(ls -A "$CC_SWEEP_SEEN_DIR" 2>/dev/null)" ]
  [ ! -s "$OSA_LOG" ]
```
UNREADABLE, lines 359–373, e.g.
```
  grep -q '"verdict":"unreadable"' "$CC_IDL"
```

**Why it is wrong:**
- **REFUSED:** Suppose the sweep skips or aborts before calling cc-notify but still logs undelivered. Then there are no markers, no OS post and `"delivered":false`, so the test goes green without ever testing the rc≠0 path.
- **UNREADABLE:** The sweep's default is `notify_verdict:=unreadable` (the string pinned at line 394). A sweep that never calls the notifier therefore records `"verdict":"unreadable"` and passes. The "third state" is not distinguished from "notify not attempted".

---

### 4. The horizon test is satisfied by a string that may not govern the horizon

**What:** The "event horizon is 7 days" test only checks that the literal `CC_EVENT_TTL_DAYS:-7` appears somewhere in the script.

**Where:** line 215:
```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

**Why it is wrong:** The check passes if the string exists only in a comment or in an unused expansion, while the real reap uses a different age. The functional test at lines 163–177 would not catch that either: its old records are 9 days old, so any horizon between 0 and 9 days also passes.

As a side note, the test title's claim of "three orders of magnitude above the lint floor" is false: 604,800 s ÷ 6,000 s ≈ 100×. This does not change any assertion.
