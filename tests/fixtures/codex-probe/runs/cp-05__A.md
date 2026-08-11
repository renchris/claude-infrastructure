I read the whole suite — the setup/stub plumbing, the dedup and delivery-verdict tests, and the reaper tests — and found two defects, both in the age-reap section. The delivery-verdict block (the `mark_seen` gate, its positive control, the unreadable-verdict third state) is internally consistent: each negative case is paired with a control that would catch an over-broad fix, and the `! cmd || false` negations are written in the form that actually fails a bats test.

## Defect 1 — the "all six event dirs" reap test only covers five dirs

**What** — The test claims to verify reap-old/keep-young behavior for all six event dirs, but `CC_ANNOUNCE_ALARM_DIR` is never seeded or asserted, so the announce-alarms dir — one of the six, and the first dir the file header lists as drained — has no reaper coverage at all.

**Where** — Lines 163–168 (and the matching assertions at 173–177):

```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong** — That is five `mk_old`/`mk_young` pairs: pages, comms-alarms, push-records, completion, teardown. The sixth reapable dir per the setup comment ("The sweep age-reaps six event dirs", lines 21–22) and the file header ("Drains pages/ + cc-announce-alarms/ + …", line 3) is the announce-alarms dir exported at line 12 — and it appears nowhere in this test. The section header at lines 156–158 explains exactly why each dir needs the *pair*: reap-only assertions stay green if the horizon collapses to zero, keep-only assertions stay green if the reaper never runs. For announce-alarms, *neither* half is asserted, so both failure modes pass silently: a sweep that never reaps old announce alarms (unbounded growth in a write-only dir), or one that reaps *young* announce alarms — destroying live escalations before they are surfaced, which is precisely the data-loss class the rest of this suite exists to prevent (and alarms are the record type most of the delivery tests use). The test's name and comment claim coverage the code does not provide.

## Defect 2 — the 7-day-horizon pin passes for horizons that are not 7 days

**What** — The assertion that "the event horizon is 7 days" is a substring grep whose success only requires the text `CC_EVENT_TTL_DAYS:-7` to appear *somewhere* in the sweep, so it passes when the actual default is a different value.

**Where** — Lines 215–216:

```bash
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```

**Why it is wrong** — `grep -c` exits 0 on one or more matches anywhere in the file; the count is captured and then ignored. Two conditions make the assertion pass for the wrong reason. First, the pattern is an unanchored substring, so a default of `${CC_EVENT_TTL_DAYS:-75}` or `:-7000` still matches (a horizon of 75 days would additionally slip past the six-dirs test, whose `mk_old` files are only 9 days old — they'd be kept, but that test asserts keeps only for young files… it asserts `! -f` for old files, so 75 days *would* trip it; the case it cannot catch is below). Second, the match may live in a comment: if the real default shrinks — say to `${CC_EVENT_TTL_DAYS:-3}` — while a stale comment or changelog line in the sweep still contains `CC_EVENT_TTL_DAYS:-7`, this grep passes, the reaper-horizon lint at line 217 passes (3 days ≫ its 6,000-second floor), and the 9-day `mk_old` fixtures still reap — so the entire suite stays green while the horizon has silently dropped to less than half its documented value, reaping event records four days earlier than every consumer of this contract expects.

Everything else I checked out clean: the `notify_count` helper's `&&`/`||` chaining is correct, the stub heredocs are properly quoted so `$CC_STUB_VERDICT`/`$OSA_LOG` expand at stub runtime, `CC_SWEEP_PROJECT=host-proj run bash "$SWEEP"` (line 288) does propagate the variable through bats' `run` function to the child in bash, and the `[ -z "$(ls -A … 2>/dev/null)" ]` empty-seen-dir checks are backed by behavioral re-surface assertions that would catch markers written to the wrong location.