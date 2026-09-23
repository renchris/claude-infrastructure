## Preliminary

Line numbers below count `#!/usr/bin/env bats` as line 1. Each entry quotes the line verbatim so the reference is unambiguous even if my count is off by one in the long comment blocks.

---

### 1. The "all six event dirs" reap test exercises only five dirs

**What** — The test that claims to cover the reap-vs-keep behaviour of all six age-reaped event dirs sets up and asserts only five; `$CC_ANNOUNCE_ALARM_DIR` is never given a reap-or-keep assertion anywhere in the file.

**Where** — lines 163–168 and 173–177:
```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```
```bash
  [ ! -f "$CC_PAGES_DIR/old.page" ];              [ -f "$CC_PAGES_DIR/new.page" ]
  [ ! -f "$CC_COMMS_ALARM_DIR/old.json" ];        [ -f "$CC_COMMS_ALARM_DIR/new.json" ]
  [ ! -f "$CC_PUSH_RECORDS_DIR/old.json" ];       [ -f "$CC_PUSH_RECORDS_DIR/new.json" ]
  [ ! -f "$CC_COMPLETION_RECORDS_DIR/old.json" ]; [ -f "$CC_COMPLETION_RECORDS_DIR/new.json" ]
  [ ! -f "$CC_TEARDOWN_RECORDS_DIR/old.json" ];   [ -f "$CC_TEARDOWN_RECORDS_DIR/new.json" ]
```

**Why it is wrong** — Five `mk_old`/`mk_young` pairs, five assertion pairs, under a name that promises six. If the announce-alarm dir is dropped from the reaper's list, or reaped with a collapsed horizon that eats live alarms, this suite stays green. That is precisely the class of failure the setup banner at lines 21–24 records as having already destroyed live records ("an unexported `CC_TEARDOWN_RECORDS_DIR` let a test run delete 6 real `~/.claude/cc-teardown` records").

---

### 2. `notify_count` counts log lines, not cc-notify invocations

**What** — The helper every notify assertion depends on measures newlines in the stub log, so a single call that carries a multi-line argument counts as several calls, and an absent log counts as zero calls.

**Where** — line 64, with the stub at line 41:
```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
```bash
echo "$@" >> "$0.log"
```

**Why it is wrong** — `echo "$@"` puts all arguments on one line *only* if no argument contains a newline. The summary the sweep passes is multi-line by the evidence of lines 408–409, which grep the log for two distinct summary phrases (`"no-change: surfaced, NOT dispatched"` and `"fired→backlog"`). If that summary spans k lines, one call reads as k, and every `[ "$(notify_count)" -eq 1 ]` (lines 79, 87, 95, 108, 130, 132, 146, 241, 314, 340, 386) fails for a reason that has nothing to do with the sweep's notify behaviour. In the other direction, the `|| echo 0` branch makes "the stub was never created / was invoked under a different `$0` so the log landed elsewhere" indistinguishable from "no notify happened", so the `-eq 0` assertions at lines 70, 103 and 141 can be satisfied by a broken seam rather than by correct abstention. Note the contrast with osascript, which the setup deliberately stubs *on PATH* (lines 48–51) precisely because a name lookup "no suite can un-find"; the cc-notify seam is env-var-only.

---

### 3. The horizon test pins the value with an unanchored source grep, and its stated margin is wrong by 10×

**What** — The only check that the event horizon is 7 days is an unanchored substring grep of the script's text, which also matches `70`, `7000`, etc., and which passes even if the variable is never used; the test's stated safety margin is also arithmetically false.

**Where** — lines 213–215:
```bash
# ── the horizon must outlive the reaper-horizon-lint floor (600 s sweep × 10 = 6,000 s) ────────
@test "the event horizon is 7 days — three orders of magnitude above the lint floor" {
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

**Why it is wrong** — With a script containing `${CC_EVENT_TTL_DAYS:-70}` the grep still matches and the test passes while the horizon is ten times the asserted value; with the assignment present but dead (the reaper hard-coding a different TTL) it also passes. Separately, 7 days is 604,800 s against the 6,000 s floor named on line 213 — a factor of ~100, two orders of magnitude, not three. The interval feeding that floor is itself contradicted inside the file: line 213 says a 600 s sweep, line 345 says records "re-surface … every 300 s", so at most one of the two margin computations can be right.

---

### 4. The REFUSED and UNREADABLE tests never establish that the transport was attempted

**What** — Both tests assert only the *absence* of effects, so "cc-notify refused" is indistinguishable from "cc-notify was never called", and the stub configuration each test exists to exercise may be entirely inert.

**Where** — lines 347–356 and 369–372:
```bash
  export CC_STUB_RC=3
```
```bash
  [ -z "$(ls -A "$CC_SWEEP_SEEN_DIR" 2>/dev/null)" ]
  [ ! -s "$OSA_LOG" ]
  echo "$output" | grep -q 'UNDELIVERED'          # loud, never silent (a17 S-4)
  grep -q '"delivered":false' "$CC_IDL"
```
```bash
  [ -z "$(ls -A "$CC_SWEEP_SEEN_DIR" 2>/dev/null)" ]
  grep -q '"verdict":"unreadable"' "$CC_IDL"
```

**Why it is wrong** — A sweep that bailed before the notify step (decided nothing was new, or errored into its undelivered path early) produces exactly this observable state: no markers, no OS post, `UNDELIVERED` on stdout, `"delivered":false`. `CC_STUB_RC=3` would then be untested, and the specific claim in the REFUSED test title — that a *refusing transport* does not fall through to the OS channel — would be proven by nothing, because a sweep that never reached the transport never reaches the channel either. The sibling test at line 314 does assert `[ "$(notify_count)" -eq 1 ]` for exactly this reason; these two omit it.

---

### 5. `[ -z "$(ls -A "$CC_SWEEP_SEEN_DIR" …)" ]` is satisfied by a directory that does not exist

**What** — The "nothing was marked seen" guards assert emptiness of one named path, and `ls -A` on a missing directory yields empty output with stderr discarded, so the guard also passes when the sweep wrote its markers somewhere else entirely.

**Where** — lines 316, 353, 371 (and setup lines 17, 30–32):
```bash
  [ -z "$(ls -A "$CC_SWEEP_SEEN_DIR" 2>/dev/null)" ]
```
```bash
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/seen"
```
```bash
  mkdir -p "$CC_PAGES_DIR" "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" \
```

**Why it is wrong** — `CC_SWEEP_SEEN_DIR` is the one redirected path that `setup()` exports but never creates, so its non-existence is the *normal* state at assertion time. If the sweep stopped honouring the variable and fell back to its `~/.claude/autonomy/sweep-seen` default (the same failure mode the banner at lines 21–24 documents, and the very store the header at line 303 says held 964 stale markers), all three "must not forget" tests pass while records are being forgotten in the operator's live state. Only the positive control at line 383 (`[ -n "$(ls -A …)" ]`) proves the variable is honoured at all, and it is in a different, independently-run test.

---

### 6. `[ -s "$OSA_LOG" ]` proves an invocation, not a message

**What** — The assertion that "something was actually put in front of a human" is satisfied by an osascript invocation carrying no message at all, because the stub discards stdin and logs a bare newline for empty arguments.

**Where** — lines 56–57 and 334:
```bash
cat >/dev/null
printf '%s\n' "$*" >> "$OSA_LOG"
```
```bash
  [ -s "$OSA_LOG" ]                        # something was actually put in front of a human
```

**Why it is wrong** — If the sweep feeds its AppleScript to osascript on stdin (`osascript <<EOF`, or a pipe) rather than via `-e`, `cat >/dev/null` throws the entire notification text away and `"$*"` is empty; `printf '%s\n' ""` still writes one byte, so `-s` is true. The test then reports a delivered operator notification, marks the records seen on that basis (line 336, `"delivered":true`), and the second-sweep check at line 340 confirms the records are now forgotten — a success reported for an empty notification. The stub also blocks in `cat` until EOF, so an osascript call that does not redirect or close stdin will hang the suite on an inherited terminal stdin rather than fail.

---

### 7. The "loud, not silent" IDL check uses a GNU-only BRE alternation

**What** — The only assertion that the missing-desk-role path is reported loudly relies on `\|` alternation in a basic regular expression.

**Where** — line 142:
```bash
  grep -q 'no-desk-role\|undelivered' "$CC_IDL"     # loud, not silent
```

**Why it is wrong** — `\|` is a GNU extension. On any grep whose BRE follows POSIX (BSD grep, as shipped on the darwin platform this suite targets), `\|` is an escaped ordinary character, so the pattern is the literal string `no-desk-role|undelivered`, which no IDL record can contain. The assertion then fails on a correct sweep and cannot ever be satisfied by a correct one — it reports failure for a reason unrelated to the behaviour under test.

---

### 8. The launchd-callability test does not test launchd callability

**What** — The test named for supervisor invocation runs with the fully populated hermetic environment and bats' cwd, so it cannot observe the configuration it names.

**Where** — lines 149–152:
```bash
# ── launchd/supervisor-callable: runs standalone, exit 0, no args ──────────────
@test "runs standalone with no args and exits 0" {
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
```

**Why it is wrong** — Under launchd none of the eleven `CC_*` variables `setup()` exports are set and cwd is `/` (the file itself states this at line 224). This body is effect-identical to the "nothing new" test at lines 67–72: every dir is redirected into `$BATS_TEST_TMPDIR`, so the sweep never exercises a single `$HOME` fallback. The one condition the section claims to cover — the sweep behaving correctly, and non-destructively, with an empty environment — is asserted nowhere in the file, even though the banner at line 24 calls a destructive default "the harness's bug".

---

### 9. The summary guard is pinned to one literal token, not to the condition it describes

**What** — The check that a no-change sweep does not misreport a queued fire tests for the absence of one exact string, which neither covers the described failure nor tolerates honest reporting.

**Where** — lines 407–409:
```bash
  # reporting only the total would read as "1 item queued" on a sweep that queued none
  grep -q "no-change: surfaced, NOT dispatched" "$CC_NOTIFY_BIN.log"
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
```

**Why it is wrong** — A summary that reports a misleading total in any other wording (`fired: 1`, `queued 1 item`) passes the negative grep while committing exactly the error the comment names. Conversely, a summary that honestly reports `fired→backlog: 0` fails, because the token is present regardless of the count that follows it. The guard keys on spelling, not on the claim.

---

### 10. Two tests discard the sweep's exit status

**What** — A sweep that exits non-zero after doing part of its work is reported as a pass.

**Where** — lines 129 and 268:
```bash
  run bash "$SWEEP"
```
```bash
  run bash "$SWEEP"
```
(at line 129, `$status` is next referenced nowhere; at line 268 it is overwritten by the `run` on line 269 before any check.)

**Why it is wrong** — `run` swallows the exit code, so if the sweep queues the backlog item at line 268 and then dies — on the IDL write, on the reap step, on `cc-decide` — the following grep still finds the item and the test is green. The same sweep failure is caught by every other test in the file via `[ "$status" -eq 0 ]`; here a failure is reported as a success.

---

### 11. The "old shape is gone" test proves text, not behaviour

**What** — Two of its four checks are bare substring greps of the script, which a comment or a dead code path satisfies.

**Where** — lines 394 and 396:
```bash
  run bash -c "grep -q 'notify_verdict:=unreadable' '$SWEEP'"
```
```bash
  run bash -c "grep -q 'CC_SWEEP_OS_CHANNEL' '$SWEEP'"
```

**Why it is wrong** — The test title asserts that the notify call is neither rc-discarded nor stderr-discarded. A script that mentions `CC_SWEEP_OS_CHANNEL` only in a comment, and contains `${notify_verdict:=unreadable}` in an unreached branch, while discarding rc and stderr at the actual call site with any spelling other than the one literal pinned on line 392, passes all three greps. The property is genuinely covered by the behavioural tests at lines 306, 343, 359 and 375; the greps in this test add a pass that does not depend on it.
