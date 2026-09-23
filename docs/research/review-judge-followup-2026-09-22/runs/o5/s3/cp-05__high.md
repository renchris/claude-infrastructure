Line numbers below are counted with `#!/usr/bin/env bats` as line 1; each entry also quotes the line verbatim so it can be located if my count is off by one somewhere in a comment block.

## Defects

### 1. The "all six event dirs" reap test only exercises five of them

**What** — The test that claims to prove the age-reap over all six write-only event dirs never sets up a record in `$CC_ANNOUNCE_ALARM_DIR`, so that dir's reap behaviour is entirely unasserted.

**Where** — lines 163–177, the setup block of the test:
```
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```
and the matching assertion block, lines 173–177, which likewise has five pairs.

**Why it is wrong** — The six event dirs exported by `setup()` are pages, announce-alarms (line 12: `export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"`), completion, comms-alarms, push-records and teardown. Announce-alarms is the one omitted. The L2 rationale on lines 156–158 ("asserting only the reap would stay green if the horizon collapsed to 0… asserting only the keep would stay green if the reaper never ran") is applied to five dirs. If the sweep never reaps `cc-announce-alarms/` — or reaps it with a collapsed horizon that eats live alarms — this test stays green, and no other test in the file touches announce-alarm file ages (the alarm tests on lines 76 and 309 create only fresh records).

### 2. The "old shape is gone" pin can never match the current call shape, so it asserts nothing

**What** — The regression pin for the rc-discarding/stderr-discarding notify call greps for a call form the sweep provably no longer uses, so `grep -c` returns `0` unconditionally and the assertion is a tautology.

**Where** — lines 392–393:
```
  run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
  [ "$output" = "0" ]
```

**Why it is wrong** — Line 82 (`grep -q -- '--role desk' "$CC_NOTIFY_BIN.log"`) and its comment establish that the sweep now invokes cc-notify as `--role desk <summary>`, not with a positional `"$DESK_TARGET"`. The pinned pattern requires `"$NOTIFY" "$DESK_TARGET" "$summary"` adjacent on one line, which cannot occur in the current call shape regardless of what follows it. So if someone re-added `>/dev/null 2>&1 || true` to the *current* line — the exact data-loss bug the test exists to prevent — `grep -c` still prints `0` and the test still passes. The two follow-up checks in the same test (lines 394 and 396, `grep -q 'notify_verdict:=unreadable'` and `grep -q 'CC_SWEEP_OS_CHANNEL'`) match anywhere in the file, including inside the script's own comments, so they do not compensate.

### 3. `\|` alternation in the "fail loud" assertion is a GNU grep extension

**What** — The assertion that the missing-desk-role case is recorded loudly uses BRE alternation, which BSD/macOS grep does not implement; there the pattern is the literal string `no-desk-role|undelivered`.

**Where** — line 142:
```
  grep -q 'no-desk-role\|undelivered' "$CC_IDL"
```

**Why it is wrong** — The suite targets macOS (`mk_old`/the decisions test use `date -v-9d` / `date -v-30d`, BSD-only flags, lines 160 and 184), where `/usr/bin/grep` treats `\|` as a literal `|` rather than alternation. The IDL will contain e.g. `"reason":"no-desk-role"` and never the literal `no-desk-role|undelivered`, so the test fails even when the sweep behaves exactly as specified — a failure for the wrong reason. Equivalently, on a GNU-grep host it passes, so the check's result depends on which grep is installed rather than on the sweep.

### 4. `notify_count` counts log lines, not cc-notify invocations

**What** — The helper that every dedup assertion in the file depends on reports the number of newlines in the stub's log, which equals the number of calls only if no argument the sweep passes contains a newline.

**Where** — line 64:
```
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
with the stub that produces the log, line 41:
```
echo "$@" >> "$0.log"
```

**Why it is wrong** — `echo "$@"` writes the summary argument verbatim, newlines included. The summary is structured — line 408 greps it for `no-change: surfaced, NOT dispatched` while line 409 requires `fired→backlog` to be absent, i.e. it carries per-class reporting lines. If that summary spans *n* lines, a single notify is counted as *n*, and every `[ "$(notify_count)" -eq 1 ]` (lines 79, 87, 95, 108, 130, 132, 146, 241, 340, 386) fails or, worse, a run that notified twice with a one-line and a two-line summary reads as three and a run that notified once with a two-line summary reads as two — the counter cannot distinguish "one call, multi-line" from "several calls". The dedup property these tests exist to prove is asserted through a quantity that is not the number of calls.

## Lesser defects

### 5. The 7-day horizon assertion matches a prefix and matches comments

**What** — The horizon check passes on any value beginning with `7` and on a commented-out occurrence.

**Where** — lines 215–216:
```
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```

**Why it is wrong** — `grep -c` exits 0 on one or more matches, and the pattern is an unanchored substring: `CC_EVENT_TTL_DAYS:-70`, `CC_EVENT_TTL_DAYS:-7000`, or the string appearing only inside a comment all satisfy it. The test named "the event horizon is 7 days" therefore does not pin the horizon to 7 days; it pins it to "starts with 7, somewhere in the file". (Related, in the same test's title: 7 days is 604,800 s against the stated 6,000 s floor — two orders of magnitude, not three.)

### 6. The hermetic `osascript` stub reads stdin, unlike the binary it stands in for

**What** — The stub blocks on stdin before logging, which the real `osascript -e …` invocation does not do.

**Where** — line 56, inside the stub heredoc:
```
cat >/dev/null
```

**Why it is wrong** — The sweep is launched as `run bash "$SWEEP"` with bats' inherited stdin; bats does not redirect test stdin from `/dev/null`. When the sweep reaches the Notification Center channel (tests at lines 325 and 343 set `CC_SWEEP_OS_CHANNEL=auto`) and calls `osascript` without redirecting its stdin, `cat` reads from whatever the test inherited — consuming it, or hanging until EOF when run interactively. Nothing in the hermeticity argument on lines 48–51 requires the stub to drain stdin.

### 7. The "cannot become a per-sweep notification storm" claim is not asserted

**What** — After the second sweep in the liveness-free-channel test, only the cc-notify count is re-checked; the OS-channel log is not.

**Where** — lines 336–340:
```
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
```
against the comment on line 337 (`# marked seen ⇒ no re-surface, so the channel cannot become a per-sweep notification storm`) and the only `OSA_LOG` assertion, line 334 (`  [ -s "$OSA_LOG" ]`).

**Why it is wrong** — A sweep that marks records seen but still posts a notification on every run (an unconditional post rather than one gated on new records) leaves `notify_count` at 1 and leaves `$OSA_LOG` non-empty, so both assertions pass while the storm the comment rules out is occurring. `-s` is also never compared against its earlier size, so a second, third, … post is invisible to this test.
