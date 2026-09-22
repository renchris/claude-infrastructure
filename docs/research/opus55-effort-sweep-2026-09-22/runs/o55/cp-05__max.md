Four defects, most certain first.

### 1. The "all six event dirs" reap test covers only five

- **What:** The test named for all six age-reaped event dirs seeds and asserts old/young pairs in only five of them. The cc-announce-alarms dir (`CC_ANNOUNCE_ALARM_DIR`) is left out.
- **Where:** `tests/autonomy-sweep.bats:163`. The fixtures are at 164–168 and the assertions at 173–177.
  ```
  @test "all six event dirs: records past the horizon are reaped, young ones kept" {
  ```
- **Why:**
  - Lines 21–22 and 155 say the sweep age-reaps six event dirs.
  - Of the dirs setup creates, those six are pages, announce-alarms, completion, comms-alarms, push-records and cc-teardown. decisions/ is the exempt ledger (line 180) and inbox-guard is damping state (line 190).
  - The rows cover every one of the six except announce-alarms, and no other test ages a file there.
  - So a sweep that never reaps that dir passes every test in the file, even as alarm records pile up indefinitely. This test still reports "all six" green.

### 2. The "old shape is gone" pin cannot match the current call

- **What:** This test claims "the notify call is neither rc-discarded nor stderr-discarded". Its only check for that is a grep for one exact historical line addressed to `$DESK_TARGET`, and the current role-addressed call can never take that form.
- **Where:** `tests/autonomy-sweep.bats:392-393`
  ```
    run grep -c '"\$NOTIFY" "\$DESK_TARGET" "\$summary" >/dev/null 2>&1 || true' "$SWEEP"
    [ "$output" = "0" ]
  ```
- **Why:**
  - Per lines 80–82, the call now goes out as `--role desk`, not the `$DESK_TARGET` uuid snapshot.
  - The pattern therefore matches only if someone reverts both the addressing and the discard byte-for-byte.
  - Reintroducing the discard on the live call leaves `grep -c` at 0, so the test passes. Example: `"$NOTIFY" --role desk "$summary" >/dev/null 2>&1 || true`.
  - Lines 394–397 only prove that two strings occur somewhere in the file.
  - Line 391 says "the exact three lines" are pinned. Only one is, and in a form that cannot recur.

### 3. The REFUSED test cannot show that a non-zero rc is honored

- **What:** The "REFUSED (cc-notify rc != 0)" test makes the stub fail on both the exit code and the verdict token. Its outcome therefore does not depend on whether the sweep reads the rc at all.
- **Where:** `tests/autonomy-sweep.bats:347-348`
  ```
    export CC_STUB_RC=3
    export CC_STUB_VERDICT=unresolvable
  ```
- **Why:**
  - `unresolvable` is itself a non-delivery verdict.
  - Consider a sweep that discards cc-notify's rc (the `|| true` that line 295 names as a cause of the loss) but still parses stderr. As long as it doesn't send that unrecognized verdict to the OS channel, it satisfies every assertion at 352–356.
  - The input that would tell the two apart never appears in the file: rc ≠ 0 paired with a verdict that at rc 0 would mark seen or post. That means `delivered`, or `mailbox-only` under `auto`.
  - Together with #2, nothing in the file catches the rc discard coming back.

### 4. The data-loss regression is exercised for only one of the two dead-desk verdicts

- **What:** The section header says a dead-pane desk makes cc-notify return `verdict=mailbox-only/unverified` at rc 0. Both RECORDED tests stub only `mailbox-only`.
- **Where:** `tests/autonomy-sweep.bats:299`, against `:309` (the same line appears at `:329`)
  ```
  # verdict=mailbox-only/unverified FOREVER. The a17 S-7 guard below ("no desk role ⇒ do NOT mark
  ```
  ```
    export CC_STUB_VERDICT=mailbox-only
  ```
- **Why:**
  - Suppose a sweep classifies `unverified` as reached and marks the records seen on the desk channel.
  - It would reproduce the "PERMANENT SILENT LOSS" described at 301–303 on every sweep where cc-notify reports `unverified`.
  - No test ever emits that token, so the suite stays green.

Not counted, since it is wording rather than behavior: the title at line 214 says the 7-day horizon is "three orders of magnitude" above the 6,000 s floor. 604,800 / 6,000 ≈ 100, which is two orders of magnitude.
