## Defects

### 1. The "all six event dirs" reap test exercises only five of them; `CC_ANNOUNCE_ALARM_DIR` is never covered

**Where** — line 163, and the five setup lines 164–168 / five assertion lines 173–177:

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

**Why it is wrong** — Setup declares six event dirs the sweep can delete from (lines 11–13, 25–27: pages, announce-alarms, completion, comms-alarms, push-records, cc-teardown), and the comment at line 21 states the sweep "age-reaps six event dirs." The test covers pages, comms-alarms, push-records, completion and teardown — `$CC_ANNOUNCE_ALARM_DIR` is absent from both halves. If the sweep stops reaping `cc-announce-alarms/` entirely, or reaps it with a collapsed horizon and eats live alarms, nothing in this file fails; the suite reports a passing test whose name asserts all six were checked. That dir is the one the file header names first as a drained escalation source (line 3), and is the exact failure-distinct pair the section's L2 rationale (lines 156–158) demands.

### 2. The "horizon is 7 days" test asserts only that a substring appears somewhere in the script, so it passes for horizons that are not 7 days

**Where** — lines 214–216:

```bash
@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
  [ "$status" -eq 0 ]
```

**Why it is wrong** — `grep -c` exits 0 on any match, and the pattern is unanchored. `${CC_EVENT_TTL_DAYS:-70}`, `${CC_EVENT_TTL_DAYS:-7000}`, or an occurrence in a usage string or commented-out line all satisfy it while the effective default differs. Nothing else in the file closes the gap: `mk_old` (line 160) ages fixtures 9 days and `mk_young` leaves them at 0, so the reap test at 163 passes for *any* horizon strictly between 0 and 9 days, and `reaper-horizon-lint.sh` (line 217) only enforces a 6,000 s floor. A script whose real default was `CC_EVENT_TTL_DAYS:-1` — 6× shorter than claimed, reaping live week-old records — passes this test, the reap test, and the lint together.

### 3. `notify_count` counts newlines in the stub log, not stub invocations

**Where** — line 64, together with the stub's logging line 41:

```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
```bash
echo "$@" >> "$0.log"
```

**Why it is wrong** — One invocation appends one line only if no argument contains a newline. The summary is a multi-item digest (line 408 and 409 grep it for two distinct phrases; it also carries page/alarm/decision detail), and nothing in the harness constrains it to a single line. If the summary ever spans two lines, a single call reads as two — which makes line 322, the assertion that carries the whole data-loss regression, pass for the wrong reason:

```bash
  [ "$(notify_count)" -eq 2 ]
```

That assertion exists to prove the un-delivered record *re-surfaced on a second sweep*; it is equally satisfied by one sweep emitting a two-line summary and a second sweep that silently forgot the record — the exact failure it guards.

### 4. The "no per-sweep notification storm" claim in the OS-channel test is never checked

**Where** — lines 334 and 337–340:

```bash
  [ -s "$OSA_LOG" ]                        # something was actually put in front of a human
```
```bash
  # marked seen ⇒ no re-surface, so the channel cannot become a per-sweep notification storm
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(notify_count)" -eq 1 ]
```

**Why it is wrong** — `[ -s ]` is a non-emptiness test taken *before* the second sweep, and after the second sweep the OS channel is not inspected at all. A sweep that marks records seen but posts to Notification Center on every run — e.g. a post emitted ahead of the dedup check, or a standing "still undelivered" reminder — appends a second line to `$OSA_LOG`, leaves `notify_count` at 1 because the desk transport is not re-invoked, and the test passes green on precisely the storm it names. Separately, the terminal `-eq 1` is a cumulative count with no baseline taken after the first sweep, so it is also satisfied by (0 notifies on run 1, 1 on run 2) — the re-surface the test exists to exclude.

### 5. The role-addressing assertion does not exclude uuid addressing

**Where** — lines 80–82:

```bash
  # addressed by ROLE, not by the uuid snapshot the sweep read: cc-notify re-reads cc-roles/desk at
  # SEND time and follows the .forward chain, so a desk recycled mid-sweep still gets the wake.
  grep -q -- '--role desk' "$CC_NOTIFY_BIN.log"
```

**Why it is wrong** — The stated property is "by ROLE, **not** by the uuid snapshot", but the check is purely positive. A sweep that logged `--role desk --target desk-pane-uuid-current` — passing the stale uuid it read at scan time alongside the role — matches this grep and the test passes, while the invariant it claims to protect (send-time re-resolution through the `.forward` chain, so a desk recycled mid-sweep still gets the wake) is violated and the wake goes to a dead pane. There is no assertion that the uuid is absent from the argument list.

## Noted, but not defects by the brief's definition

The section header at line 213 says the lint floor is a 600 s sweep while line 344's comment says records re-surface "every 300 s"; and the test name at line 214 calls 7 days (604,800 s) "three orders of magnitude" above a 6,000 s floor, when the ratio is ~100×. These are comment/name inaccuracies with no effect on what the tests check. Likewise, the comment on line 334 claims "something was actually put in front of a human," but because line 57 is `printf '%s\n' "$*"`, the log is non-empty even for a zero-argument invocation — the assertion proves invocation, not content, which is all the paired `[ ! -s "$OSA_LOG" ]` at line 354 needs.