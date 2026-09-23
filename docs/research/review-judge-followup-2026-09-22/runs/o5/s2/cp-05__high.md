## Findings

### D1 — The "all six event dirs" reap test only covers five of them; the announce-alarms dir is never exercised

**Where** — lines 163–177 (setup exports the dir at line 12).

```bash
@test "all six event dirs: records past the horizon are reaped, young ones kept" {
  mk_old   "$CC_PAGES_DIR/old.page";                 mk_young "$CC_PAGES_DIR/new.page"
  mk_old   "$CC_COMMS_ALARM_DIR/old.json";           mk_young "$CC_COMMS_ALARM_DIR/new.json"
  mk_old   "$CC_PUSH_RECORDS_DIR/old.json";          mk_young "$CC_PUSH_RECORDS_DIR/new.json"
  mk_old   "$CC_COMPLETION_RECORDS_DIR/old.json";    mk_young "$CC_COMPLETION_RECORDS_DIR/new.json"
  mk_old   "$CC_TEARDOWN_RECORDS_DIR/old.json";      mk_young "$CC_TEARDOWN_RECORDS_DIR/new.json"
```

**Why it is wrong** — Setup declares six reaped event dirs (`CC_PAGES_DIR`, `CC_ANNOUNCE_ALARM_DIR`, `CC_COMPLETION_RECORDS_DIR`, `CC_COMMS_ALARM_DIR`, `CC_PUSH_RECORDS_DIR`, `CC_TEARDOWN_RECORDS_DIR` — lines 11–13, 25–27) and warns at line 21 that "any one left unexported… becomes a reaper against LIVE state". Only five get an old/young pair; `CC_ANNOUNCE_ALARM_DIR` is omitted. If the sweep's horizon for cc-announce-alarms collapses to 0 (eating live alarms) or is never applied at all (unbounded growth), this test — the only behavioural reap test, and the one whose name claims complete coverage — stays green. The same dir is the one used by nearly every delivery test, so it is not an obscure path.

---

### D2 — `notify_count` counts log *lines*, not cc-notify *invocations*

**Where** — line 64 (helper) and line 41 (stub), consumed by every `-eq` assertion (e.g. lines 79, 95, 108, 130, 240, 313, 321, 339, 385).

```bash
notify_count() { [ -f "$CC_NOTIFY_BIN.log" ] && wc -l < "$CC_NOTIFY_BIN.log" | tr -d ' ' || echo 0; }
```
```bash
echo "$@" >> "$0.log"
```

**Why it is wrong** — `echo "$@"` joins the arguments with spaces but preserves any newlines *inside* an argument, so one call whose summary argument spans N lines appends N lines to the log. The sweep's summary is a multi-item digest (the file's own last test at lines 407–408 greps the log for two distinct summary phrases, `no-change: surfaced, NOT dispatched` and `fired→backlog`, which reads as line-per-class output). The moment the summary carries more than one line, `[ "$(notify_count)" -eq 1 ]` reports 2, 3, … and the count assertions measure the shape of the summary rather than the number of wakes — the dedup claims ("still exactly ONE notify total", line 87) and the re-surface claim (`-eq 2`, line 321) are then both decided by the wrong quantity.

---

### D3 — The "summary distinguishes queued fires from no-change fires" test asserts only the negative half; nothing ever proves the positive token exists

**Where** — lines 401–409, specifically:

```bash
  ! grep -q "fired→backlog" "$CC_NOTIFY_BIN.log" || false
```

**Why it is wrong** — `fired→backlog` appears nowhere else in the file: no test asserts that the summary *does* contain it when a change-effect default is actually queued (the positive-control test at lines 249–260 checks the backlog ledger, not the summary). If the sweep's summary never emits that token at all — because it was renamed, or because the queued-fire count was dropped from the summary entirely — this test passes while the summary once again "reads as '1 item queued' on a sweep that queued none", which is the exact failure the comment at line 406 says it is pinning. This is the same failure-distinct gap the file calls out for the reaper at lines 156–158, left open here.

---

### D4 — Two tests discard the sweep's exit status, so a sweep that fails is scored as a pass

**Where** — lines 267–268, and lines 129/131.

```bash
  run bash "$SWEEP"
  run bash "$CC_BACKLOG_BIN" list --open
```
```bash
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]
  run bash "$SWEEP"
  [ "$(notify_count)" -eq 1 ]      # deduped on the second run
```

**Why it is wrong** — `run` overwrites `$status`, and neither site checks it before the next command. In the unannotated-default test (line 267) the sweep can append the backlog item and then die on the IDL write, the seen-marker write, or the reap pass, and `grep -q "carry this out"` still succeeds — the test reports the fail-open behaviour as verified while the sweep is crashing. In the open-packet test (lines 129–133), a sweep that exits non-zero after its single notify satisfies both `-eq 1` assertions, so "deduped on the second run" is indistinguishable from "the second run aborted before it looked at anything". Every sibling test asserts `[ "$status" -eq 0 ]` immediately after the sweep; these two do not.

---

### D5 — The "loud, not silent" assertion uses BRE alternation, which is not alternation in the platform's grep

**Where** — line 142.

```bash
  grep -q 'no-desk-role\|undelivered' "$CC_IDL"
```

**Why it is wrong** — On this harness's platform (macOS; the file already depends on `date -v`, `osascript`, `uuidgen`), `grep` is BSD grep and `\|` is not an alternation operator in a POSIX basic regular expression — the pattern degrades to the literal string `no-desk-role|undelivered`, which no IDL record contains. The test then fails regardless of whether the sweep correctly wrote `no-desk-role` or `undelivered`, i.e. it reports the outcome for the wrong reason; conversely, the day the IDL happens to contain that literal it passes for the wrong reason. Only `grep -E` (or two greps) expresses the intended "either token" check.

---

### D6 — The horizon test's pattern is an unanchored prefix, so it accepts horizons that are not 7 days

**Where** — line 215.

```bash
  run bash -c "grep -c 'CC_EVENT_TTL_DAYS:-7' '$SWEEP'"
```

**Why it is wrong** — The match is a substring with no terminator, so `${CC_EVENT_TTL_DAYS:-70}`, `${CC_EVENT_TTL_DAYS:-7000}` or `${CC_EVENT_TTL_DAYS:-0.7}`-style values all satisfy it. A change of the default horizon to 70 days leaves the test named "the event horizon is 7 days" green, and the behavioural reap test (D1) cannot catch it either, because its only old fixture is 9 days (line 160) — a 70-day horizon would make *that* test fail, but a 7000-second-style typo that still begins with `7` would not be caught anywhere. (Separately, the companion claim in the name is arithmetically off: 604 800 s against the stated 6 000 s floor is two orders of magnitude, not three.)

---

### D7 — The hermetic `osascript` stub unconditionally drains stdin

**Where** — lines 54–57.

```bash
cat >/dev/null
```

**Why it is wrong** — bats does not redirect a test's stdin. If the sweep invokes the OS channel as `osascript -e '…'` (message in the argv, nothing piped in) — which is what the stub's own `printf '%s\n' "$*"` logger assumes, since it logs the *arguments* — then `cat` inherits the bats runner's stdin and either blocks until the runner's input closes or consumes input belonging to the harness. The affected tests are the ones that opt into `CC_SWEEP_OS_CHANNEL=auto` (lines 329 and 348), i.e. precisely the two that exist to prove the liveness-free channel works.

---

No other defects found; the delivery-verdict block (lines 305–399), the inbox-guard damping trio (lines 191–211) and the decisions-exemption test (lines 181–188) each assert their failure-distinct pair correctly, and the `! cmd || false` negation idiom used at lines 244, 246, 259 and 408 has the precedence its authors intended.
