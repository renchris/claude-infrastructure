# T4 — the gate-green certification deadlock: what it is, whether it is real, what unpins it

Status: IN PROGRESS (written incrementally). Repo read-only; all evidence is delivered-run
evidence from `~/.claude/autonomy/postland/` and live `ps`/`launchctl`, not declarations.

## Headline (revised as evidence accumulates)

1. The producer is ALIVE and was running the full corpus at the moment of measurement.
2. The 321h green drought is REAL and starts at a sharp regime change on **2026-09-04**.
3. There is **no single standing blocker suite**. The failing set ROTATES. That is the finding.
4. `test-hermeticity-lint.sh --selftest` is a real defect but appears in **1 of 64** post-drought
   stamps — it is NOT the deadlock.
5. Converge is DEGRADED, not blocked (tonight's converge proves it).

---

## §1 — The producer: alive, and measured by delivered runs

### 1a. It is running right now (not a declaration — a live process tree)

```
$ launchctl list | grep postland
98260	0	com.claude.postland-verify           <- PID present, last exit 0

$ ps -axo pid=,ppid=,etime=,command= | grep postland-verify
98260     1    58:10 /bin/bash .../postland-verify.sh --run-if-needed
94900 98260   54:00 /opt/homebrew/bin/timeout -k 10 10800 nice -n 19 /usr/sbin/taskpolicy -c background bats tests/account-cliff-routing.bats ...
94903 94900   54:00 bash .../bats-core/bats tests/...
94995 94903   54:00 bash .../bats-exec-suite --dummy-flag .../postland/wt-run-98260/tests/...
```

It has a live child doing real corpus work in its disposable worktree
`~/.claude/autonomy/postland/wt-run-98260`. ship-land's "the job is alive" clause is CORRECT.

### 1b. Cadence and success rate — COUNTED, not quoted

Declared cadence: `StartInterval 300` (5 min) — `~/Library/LaunchAgents/com.claude.postland-verify.plist`.
That is a REQUEST to launchd, never an observation. Counted from the stamp store
(`~/.claude/autonomy/postland/stamps/*.json`, 629 stamps, one per completed verdict):

| verdict | all-time count |
|---|---|
| cut   | 315 |
| red   | 220 |
| green | 86  |
| hung  | 8   |
| **total** | **629** |

Delivered verdict cadence is ~5-8/day, not 288/day — because a run that actually executes the
corpus takes ~3.1h wall (`run_s` ≈ 11,200 s), so the 5-minute tick mostly finds a run in flight
and abstains. **Never quote "every 5 min" as throughput.**

### 1c. The drought has a hard edge: 2026-09-04

Stamps per day by verdict (tail):

```
2026-08-31 green 6   cut 3
2026-09-01 green 5   cut 6
2026-09-02 green 3   cut 10
2026-09-03 green 1   cut 2   red 1     <- LAST GREEN 2026-09-03T16:23:25Z
2026-09-04         cut 1   red 6
2026-09-05                 red 6
...
2026-09-16                 red 5
2026-09-17                 red 2
```

**86 greens all-time, 0 since 2026-09-03T16:23:25Z. 64 red stamps since 2026-09-04, zero green.**
`~/.claude/autonomy/postland/last-green` mtime = Sep 3 11:23 local — consistent to the minute with
ship-land's "321h old (max 24h)". The claim is REAL and independently reproduced.

---

## §2 — Why no green in 321h. The premise in the brief is REFUTED.

### 2a. There is no standing blocker. The failing cast ROTATES — and every cohort dies out.

First/last appearance of each suite in the post-drought `failing[]` lists:

| suite | first named | last named | n of 64 reds |
|---|---|---|---|
| tests/operator-readout.bats | 2026-09-06 | **2026-09-17 (current)** | 30 |
| tests/pipefail-sigpipe-lint.bats | 2026-09-12 | **2026-09-17 (current)** | 20 |
| tests/mailbox-drain.bats | 2026-09-14 | **2026-09-17 (current)** | 14 |
| tests/kitty-conf-bindings.bats | (older) | **2026-09-17 (current)** | 10 |
| tests/handoff-fire-completion-push.bats | 2026-09-03 | 2026-09-08 **(gone)** | 14 |
| tests/compressor-sentinel.bats | — | 2026-09-08 **(gone)** | 10 |
| tests/cc-reaper.bats | — | 2026-09-08 **(gone)** | 10 |
| tests/idle-slope-sweep.bats | — | 2026-09-08 **(gone)** | 9 |
| tests/goal-inert-watch.bats | — | 2026-09-08 **(gone)** | 7 |

**34 of the 64 reds name NONE of today's four.** The 09-04→09-10 cohort
(handoff-fire-completion-push · compressor-sentinel · cc-reaper · idle-slope-sweep ·
goal-inert-watch · deathwatch-watchfile · drain-brief) was fixed — every one of them stopped
failing — and the drought did not end, because a NEW cohort had already arrived.

⇒ **"fix the failing suite(s)" has been happening continuously for 13 days and has produced zero
greens.** It is a treadmill, not a blocker. 42 distinct suites have been named across the 64 reds.

### 2b. `test-hermeticity-lint.sh --selftest` is NOT the deadlock — 1 stamp of 64

It appears exactly once in a `failing[]` list (`2026-09-09T05:21:17Z red scripts/test-hermeticity-lint.sh`)
and once as a CUT that names it explicitly (`runner.log`, 2026-09-15T19:19:22Z):

```
CUT 1a1572e0780c ... (the LINT is broken, not the tree: scripts/test-hermeticity-lint.sh --selftest
does not discriminate — SELFTEST FAIL: an embedded allowlist is stale ($HOME, capacity-gate,
orphan-close, inherited-value and/or capacity-admit) — the real tree is not clean; will retry)
```

That is a real defect (a stale embedded allowlist in a META-LINT that runs STANDALONE before the
corpus and SKIPS the corpus on red — postland-verify.sh:19-22). But it cost **2 of ~66 runs** and
the runner's own path is `will retry`. **Fixing it alone changes nothing.** Conviction that it is
not the blocker: **95%**.

### 2c. What the four CURRENT reds actually are — read from the TAP, not from the stamp

`~/.claude/autonomy/postland/tap/0ca4c44d5a1c...tap` (the 2026-09-17T03:58:30Z run, 10,942 TAP
lines, 15 `not ok`; the ladder exonerated 5 suites as flakes and convicted 4):

**(1) `tests/pipefail-sigpipe-lint.bats` — a DETERMINISTIC RATCHET DRIFT. The cheapest real fix.**
Tests 8, 14 and 18 (lines 324 / 390 / 440) all fail on the same fact:
```
✗ pipefail-sigpipe-lint: NEW early-exit pipe consumer under pipefail — reads FALSE on a match.
  bin/cc-cannot  4 (was 0)
       114 if printf '%s' "$CMD" | grep -Eq "$RO_RE" && ! ...
       119 / 131 (grep -Eq)   173 head -80 "$p" | grep -Eq "$HC_BODY_RE"
  bin/cc-owner  1 (was 0)
       63 launchctl list 2>/dev/null | grep -q "[[ space ]]$label\$" && state="LOADED"
  FIX: drain the consumer — 'grep -q P' → 'grep P >/dev/null'; 'head -N' → "awk 'NR<=N'".
```
Verified read-only: `scripts/pipefail-sigpipe-allow.txt` has 41 rows, contains **neither**
`bin/cc-cannot` nor `bin/cc-owner`, and was last touched `5c9433082 2026-09-08`. Both binaries
landed AFTER it — `599d66b1c bin/cc-owner 2026-09-11`, `fd74695be bin/cc-cannot 2026-09-12` — and
`pipefail-sigpipe-lint.bats` first appears in a `failing[]` on **2026-09-12T22:07**. The dates
close exactly. This one will fail on **every run forever** until 5 lines are drained.
Note the allowlist is SHRINK-ONLY by design (`scripts/pipefail-sigpipe-lint.sh:273,513,1698`), so
`--regen >` is the WRONG cure — the sanctioned fix is draining the 5 consumers.

**(2) `tests/kitty-conf-bindings.bats` (444, 474) — an ENVIRONMENT failure, and it is TONIGHT's fix
firing.**
```
_NoFace: no usable face: none of SFNS.ttf, Monaco.ttf, Menlo.ttc could be opened
  scripts/kitty-pane-title-overlay.py line 397, in _faces
```
This is the resolver that was deliberately changed **today** to RAISE instead of silently
substituting PIL's 11px `load_default()` (recorded in the project rules: *"a silent substitution is
worse than a crash … reached for real under fd exhaustion, Errno 24, load 22"*). Under the full
corpus at load 13-30 the fonts cannot be opened, so the correct fix converts a silent degrade into
a hard red **inside the verifier**. This is a fd/resource failure of the HARNESS, not of the tree.

**(3) `tests/operator-readout.bats` (1746, 1759) — the longest-standing, 30 of 64.**
`[[ "$output" == *"⏳"* ]] || false` on the busy-notice EDGE arm, with
`# warning: You appear to have cloned an empty repository.` in the diagnostic — i.e. the fixture's
git setup is degenerate in the postland cell.

**(4) `tests/mailbox-drain.bats` (803)** — `MUTANT CONTROL: strip the relay and the fresh-crumb test
stops seeing the advisory`, `[[ "$output" == *"XX MUTANT XX"* ]] || false`. A control, not a
feature test.

⇒ Of the four, **exactly one (pipefail) is a genuine tree defect.** Two (kitty fonts, operator-
readout's empty-repo warning) carry the signature of the VERIFIER'S CELL, not of trunk; one is a
mutant control.

---

## §3 — THE DEADLOCK, NAMED. A green is STRUCTURALLY UNREACHABLE since 2026-09-12T03:07Z.

This is the finding. It is not "the failing suites", and it is not load.

### 3a. The code path

`scripts/postland-verify.sh:3784-3785` — the verdict gate:

```bash
{ [ "$PRELINT_UNPROVEN" = 1 ] || [ "$LADDER_UNPROVEN" = 1 ] || [ "$CONVICT_PENDING" = 1 ]; } \
  && [ "${#FAILING[@]}" -eq 0 ] && CUT=1
```

and its contract, `scripts/postland-verify.sh:523`:

> `PRELINT_UNPROVEN ⇒ CUT: never a red, and NEVER A GREEN either`

`PRELINT_UNPROVEN` is set when a prelint's `--selftest` exits 1
(`scripts/postland-verify.sh:1199-1202`), whose documented meaning is *"THE LINT IS BROKEN:
unproven (never red, never green) + scan SKIPPED"* (`:1184-1185`).

**⇒ With `PRELINT_UNPROVEN=1`, a perfectly clean corpus produces a CUT, not a GREEN.**

### 3b. It has fired on EVERY run since 2026-09-12. Counted.

`prelints_ran` in the stamp store (the field only exists from 2026-09-06, so it cannot speak about
the drought's first two days — stated as a limit, not hidden):

```
2026-09-12T04:23:52Z red ran=5     <- last run with all 5 instruments proven
2026-09-12T07:35:31Z red ran=4     <- and every stamp from here on:
...  23 consecutive stamps, 23 of 23 with ran=4, through 2026-09-17T03:58:30Z
```

And the runner names it, on the run that is executing at this moment
(`~/.claude/autonomy/postland/runner.log:10553`, 2026-09-17T04:08:09Z):

```
prelint INSTRUMENT-BROKEN: scripts/test-hermeticity-lint.sh --selftest exit 1 —
  SELFTEST FAIL: an embedded allowlist is stale …
prelint: scripts/git-identity-lint.sh     --selftest proven — the instrument discriminates
prelint: scripts/subshell-cleanup-lint.sh --selftest proven
prelint: scripts/test-afunix-path-lint.sh --selftest proven
prelint: scripts/test-walltime-lint.sh    --selftest proven
```

4 proven, 1 broken. **`test-hermeticity-lint.sh --selftest` IS the blocker** — the brief's
hypothesis is CORRECT, but not for the reason the brief supposed. It is not in `failing[]`
(1 of 64). It never reaches `failing[]` **by construction**: a selftest failure is routed away
from RED and its own whole-tree scan is SKIPPED, so the defect it detects can never be named as a
red. **The defect hides itself.**

### 3c. Reproduced live, read-only, at HEAD

```
$ bash scripts/test-hermeticity-lint.sh --selftest   → rc=1
SELFTEST FAIL: an embedded allowlist is stale ($HOME, capacity-gate, orphan-close,
inherited-value and/or capacity-admit) — the real tree is not clean
test-hermeticity-lint --selftest: FAILED — the ratchet does not discriminate.
```

### 3d. And the scan names the two files. THIS is the actionable root cause.

```
$ bash scripts/test-hermeticity-lint.sh              → rc=1
  LEAK     cc-owner.bats: setup() does not fixture $HOME — it runs against the live ~/
  LEAK     handoff-claim-assert.bats: setup() does not fixture $HOME — it runs against the live ~/
test-hermeticity-lint: ⛔ 2 new non-hermetic suite(s) above.
  Fix: in setup(), `export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"` …
       Do NOT add to the allowlist.
```

**Attributed to a single commit, and the timing closes exactly:**

| | |
|---|---|
| `tests/cc-owner.bats` ADDED | `599d66b1c` 2026-09-11T22:07:46-05:00 = **2026-09-12T03:07:46Z** |
| last stamp with `ran=5` | 2026-09-12T04:23:52Z (a ~3.1h run, so STARTED ~01:15Z — **before** the commit) |
| first permanent `ran=4` | 2026-09-12T07:35:31Z (STARTED ~04:25Z — **after** the commit) |
| `tests/handoff-claim-assert.bats` ADDED | `cc4925383` 2026-09-12T18:35 (a second instance, same day) |

`599d66b1c` is the **only** commit touching `tests/` in that window.

### 3e. The same commit ALSO planted the other current blocker

`599d66b1c` added `bin/cc-owner`, whose line 63
(`launchctl list | grep -q "…" && state="LOADED"`) is one of the pipefail violations of §2c(1) —
and `fd74695be` added `bin/cc-cannot`'s four, the next day. **One feature landing on 2026-09-11/12
created two independent, mutually-invisible floors:** a corpus RED (pipefail ratchet) and the
never-green prelint (hermeticity selftest).

### 3f. The misattribution, which is why 5 days passed

postland's own `CUT_WHY` reads (`runner.log`, 2026-09-15T19:19:22Z):

> `the LINT is broken, not the tree: scripts/test-hermeticity-lint.sh --selftest does not
> discriminate — SELFTEST FAIL: an embedded allowlist is stale … the real tree is not clean`

The sentence indicts the INSTRUMENT while quoting the lint saying **the real tree is not clean**.
Selftest case (e) (`scripts/test-hermeticity-lint.sh:3393-3416`) is not an instrument check at all
— it lints the **real tree** with the embedded allowlists and requires exit 0. Its failure is a
verdict ABOUT THE TREE that postland's taxonomy has no column for, so it lands in the
"instrument unproven" bucket and points every reader at the wrong producer.
(Memory: `alarm-attribution-names-the-wrong-producer`.)

---

## §4 — Does it BLOCK converge, or DEGRADE it? Mostly degrades. It blocked once, yesterday.

### 4a. Measured right now — the live layer is healthy

```
live HEAD  145c32f53  (authored 2026-09-16T23:49-05:00, ~1.2h ago)
origin/main 29a4918c3
git rev-list --count HEAD..origin/main  = 3        (budget: 25 commits / 6h)
~/.claude/autonomy/postland/deploy-last-advance → 2026-09-17T04:35:53Z  (29 min ago)
```

### 4b. How the live layer has been advancing — COUNTED

```
$ grep -c 'DEGRADED deploy' deploy.log   → 178      (T2, absence-of-evidence door)
$ grep -c 'VERIFIED\|HERMETIC' deploy.log →   1      (T1/T1H, positive evidence)
```

**178 : 1.** The green gate has been essentially decorative for the whole life of this log. The
degraded tier is not an emergency path; it IS the path. Every advance is banner'd:

```
!!!!! DEGRADED deploy — no GREEN stamp among the newest 200 commits of origin/main;
taking the newest NOT-RED commit instead, authorised by 6h04m since the live commit was authored
```

### 4c. T3 BLOCKED has fired — once, and it is filed

```
deploy-live: ESCALATED verdict=escalated culprit=trunk-red class=trunk-red n=6
             streak_h=0 last_advance_h=1 green_depth=- scan_n=200 item=e6901a1da802
```
backlog `e6901a1da802`, **added 2026-09-16T14:55:01Z, BLOCKED 14:55:25Z**: *"deploy lane refusing
on repeat: trunk is RED all the way down above the live layer."* So the deadlock CAN block: when
every commit above live HEAD carries a RED stamp, T2 has no eligible target either. That is the
sharp edge of the current state, and it is one bad night away.

Also fired, 3×: `culprit=scan-window-blind class=no-green … green_depth=235 / 257 / 278
scan_n=200` — the last green is now **235-278 commits deep**, past the 200-commit scan window, so
T1 is not merely lagging, it is **structurally invisible**.

### 4d. Separation, stated plainly

| claim | verdict |
|---|---|
| "the live layer cannot advance" | **FALSE** — 3 commits behind, advanced 29 min ago |
| "the live layer advances UNSTAMPED" | **TRUE** — 178 of 179 advances carry no positive evidence |
| "ship-land is blocked by this" | **FALSE** — ship-land's own text says the land PROCEEDS |
| "the deadlock is harmless" | **FALSE** — T3 refused yesterday (`e6901a1da802`, still blocked), and `deploy-parity-assert`'s verification leg goes red on unstamped advances |

The cost is **epistemic, not operational**: every hook, script and launchd job on this box is
running bytes that nothing has certified for 321h, and the mechanism built to say so has been
advancing anyway, loudly, 178 times.

---

## §5 — THE FAIL-SAFE THAT MIMICS HEALTH, and why 5 days passed in silence

The brief asked me to check for one. There is one, and it is the reason nobody caught this.

**`PRELINT_UNPROVEN ⇒ CUT` is the fail-safe. `CUT` renders as `will retry`** — byte-identical in
the log to a transient load cut, which is the healthy self-healing state:

```
CUT 1a1572e0780c … consecutive=1 (the LINT is broken, not the tree: … ; will retry)
```

The designers anticipated exactly this and built the **CUT_MAX ladder** (`CUT_MAX=3`,
`scripts/postland-verify.sh:631`): three consecutive CUTs on one tree pages the operator. It is the
right alarm and it has worked historically — `runner.log` carries `consecutive=` values up to 7.

🚨 **It is disarmed by the OTHER defect.** `scripts/postland-verify.sh:3822`, on the RED path:
```bash
cut_clear; conviction_clear     # a verdict was reached: streak over, candidates spent
```
Every RED zeroes the CUT streak. Since the corpus is *also* red (§2c(1), the pipefail ratchet, in
20 of the last 21 runs), almost every run stamps RED instead of CUT, and each one resets the
counter. Counted:

```
$ grep -oE 'consecutive=[0-9]+' runner.log | sort | uniq -c        # ALL TIME
 353 consecutive=1   36 consecutive=2   11 consecutive=3   5 =4   1 =5   1 =6   1 =7

# since 2026-09-12 (i.e. the whole structural-deadlock era):
   3 consecutive=1        ← and NOTHING else. Never 2. Never 3.
$ grep -c 'cut_page\|cool-off' runner.log → 0
```

**Two defects, each suppressing the other's alarm.** The pipefail ratchet keeps the run RED, which
keeps the CUT streak at 1, which keeps the never-green page from ever firing; and the never-green
condition keeps the tree from certifying, which keeps everyone reading `failing[]` — where the
hermeticity selftest, by construction, never appears. Fixing either one alone makes the other
audible. Fixing neither is indistinguishable from a busy healthy box.

**Second, milder instance** — `scripts/deploy-live.sh:2670`:
```bash
say "$UNSTAMPED un-stamped commit(s) remain above the live tip (they deploy once verified green)"
```
"they deploy once verified green" describes a mechanism that has not run in 321h; those commits in
fact deploy through T2's 6h clock. A reader of that line gets a healthy-sounding account of a
degraded one. (The `0` in tonight's quoted output is honest — it means the T2 target WAS the tip.)

**Third** — `~/.claude/autonomy/postland/last-green` is never invalidated. Any consumer asking
*"does a green exist?"* still gets YES; only a consumer asking *"how old?"* sees the problem.
ship-land does ask the age (321h vs max 24h) and is therefore the only surface in the chain that
reported this correctly. **Credit where due: the message in the brief is the one honest alarm in
the system.**

---

## §6 — What unpins it. Priced.

**There is no single change.** Two independent floors are live, and each alone is sufficient to
deny a green. Both are small. That is the honest answer to Q5.

### A — REQUIRED. Fixture `$HOME` in the two leaked suites. Unpins the NEVER-GREEN floor.

Without this, **a clean corpus stamps CUT, not GREEN** (`postland-verify.sh:3784`). Nothing else
can unpin that.

| file | cost | note |
|---|---|---|
| `tests/handoff-claim-assert.bats` (68 ln) | **~2 lines** | `setup()` already uses `$BATS_TEST_TMPDIR`; add `export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"` |
| `tests/cc-owner.bats` (48 ln) | **~15-25 lines, or a split** | Harder and genuinely so: its subject resolves launchd ownership from `~/Library/LaunchAgents`, and its tests assert the REAL `com.claude.deploy-live` (lines 11, 40). Either seed fixture plists under the fixtured HOME, **or** take the precedent recorded verbatim at `scripts/test-hermeticity-lint.sh:506-520` — `deploy-parity.bats` was SPLIT so its two live-layer tests moved to `deploy-parity-live.bats`, which inherited the allowlist slot as a **rename, not an addition**. `cc-owner.bats` is the same shape. |

Do **not** add either to `EMBEDDED_ALLOWLIST` (92 rows) — the lint's own output says
`Do NOT add to the allowlist`, and the list is delete-only by contract (`:511`).

Verification is one command, read-only: `bash scripts/test-hermeticity-lint.sh --selftest` → rc 0.

### B — REQUIRED. Drain the 5 pipefail consumers. Unpins the DETERMINISTIC CORPUS RED.

`bin/cc-cannot` lines 114 · 119 · 131 · 173, `bin/cc-owner` line 63 — all present on `origin/main`
right now (verified via `git show origin/main:…`). The lint prints the fix verbatim:
`grep -Eq P` → `grep -E P >/dev/null`; `head -80 f | grep -Eq` → capture first.
**5 one-line edits.** Hits 20 of the last 21 runs.

🚫 **Do not `--regen` the allowlist.** It is SHRINK-ONLY by design
(`scripts/pipefail-sigpipe-lint.sh:273, 513, 1698`) and test 14 diffs regen against the committed
file, so a regen that GROWS it fails the same suite from the other side.

### C — the residual three, and they may not be tree defects at all

`operator-readout` · `mailbox-drain` · `kitty-conf-bindings`. Note `runner.log:10537-10541`:
```
C30 floor UNPROVEN for tests/kitty-conf-bindings.bats: the floor probe exited 126 … conviction stands
C30 floor UNPROVEN for tests/mailbox-drain.bats:       … 126 … conviction stands
C30 floor UNPROVEN for tests/operator-readout.bats:    … 126 … conviction stands
```
Exit **126** = the differential control could not execute. All three are convicted with **no
working control**. Their TAP signatures point at the CELL, not the tree: `_NoFace: none of
SFNS.ttf, Monaco.ttf, Menlo.ttc could be opened` (fd exhaustion — and this is TONIGHT's own
deliberate change from silent substitution to RAISE), and `warning: You appear to have cloned an
empty repository`. **Price nothing here until A and B land** — the honest state is *unknown*.

### D — re-scope the selftest (a real fix, not the cheapest unpin)

Case (e) (`scripts/test-hermeticity-lint.sh:3393-3416`) is a **TREE assertion living inside an
INSTRUMENT check**. Routing its failure to the lint's SCAN verdict (RED — attributable,
revert-eligible) instead of to `PRELINT_UNPROVEN` would have made this visible as a named red on
day one instead of an invisible never-green. ~20 lines across both files. **Caveat that must be
respected:** `postland-verify.sh:521-524` deliberately separates these columns precisely so a
broken lint cannot auto-revert a commit it never touched. Case (e) is separable because it is not
about discrimination at all — but the OTHER selftest cases must keep the existing routing.

### E — change what counts as green. **REJECT.**
The gate already has its degradation path, and 178:1 shows it is already maximally degraded.
Lowering it further deletes the last evidence channel rather than repairing it.

### F — revive the T1H off-box producer. The DURABLE fix for the whole class.

**Measured dead:** `~/.claude/autonomy/postland/offbox/` holds **4 stamps, newest
2026-08-13T07:22 — 35 days old.** That is why `grep -c 'VERIFIED\|HERMETIC' deploy.log` = 1.
T1H exists exactly to be a second, contention-immune producer of positive evidence
(`deploy-live.sh:63-67`), and it has had no producer for five weeks. Had it been alive, none of the
last 13 days would have been a drought. Cost: unknown from here (the producer is off-box); this is
the item to file, not to fix tonight.

### If forced to ONE: **A.**
A is what makes certification *possible*; B only makes it *likely*. And A alone re-arms the
CUT_MAX alarm of §5, so the system starts telling you about B by itself.

---

## §7 — Adversarial pass (what a hostile reviewer would say, and what I then measured)

**(1) "Your never-green floor has never actually denied a green, because the corpus has never been
clean since it broke. That is a code-reading, not a measurement."** — **Conceded, and it is the
main limit of §3.** The gate is a conjunction: `PRELINT_UNPROVEN && FAILING empty ⇒ CUT`. Today
`FAILING` is non-empty, so the run stamps RED and the prelint floor is **latent, currently masked**.
I did not observe it binding. What I can offer instead is that **the repo asserts it in its own
words** — `scripts/postland-verify.sh:4759`, inside postland's own selftest:

> *"prelint_check turns a 2 into PRELINT_UNPROVEN — so every run would CUT and no tree could be
> stamped green again. Assert the absence of that argument, because its presence is silent and
> fleet-fatal."*

That is this exact failure mode, named by the authors as fleet-fatal, with a selftest guarding a
*different* route into it. Conviction **95%** — up from 88% on the code path alone.

**(2) "You blamed a commit from timing alone."** — The window is tight (the only `tests/` commit
between the last proven-prelint run's start and the first unproven run's start) and the *content*
matches independently (`tests/cc-owner.bats` is one of the two files the scan names). But
`prelints_ran` is per-run, not per-commit, so the resolution is ~3h. Conviction **88%**.

**(3) "The root-cause row `a6843865a2ec` says this is LOAD. You ignored it."** — I tested it and it
**does not hold for the current cohort.** Terciles over the 64 post-drought reds:

| tercile | n | mean load | mean #failing suites |
|---|---|---|---|
| LOW | 21 | 11.08 | **3.90** |
| MID | 21 | 17.37 | 2.95 |
| HIGH | 22 | 37.88 | **2.59** |

The LOW-load runs fail *more*, not less — the inverse of the load story. The quietest run measured
(load **5.92**) was still RED. And decisively, no statistic is needed for the pipefail ratchet:
the violations are on `origin/main` right now and the allowlist does not cover them, so **a
perfectly idle box cannot produce a green today.** Honest limit: with **zero** greens there is no
outcome variance, so I can only measure red *severity*, and the terciles are confounded by time
(the later cohort is both quieter and larger). Conviction that load is not the current cause: **80%**.
`a6843865a2ec` was measured 2026-09-08 against a cohort that has since been fixed; it is a
**stale published figure**, not a wrong one.

**(4) "The brief's cited blockers."** — Both are **CLOSED**, and the brief is working from stale
state. `913613b4ab57` → `done 2026-09-09T07:24:05Z`, evidence `d3dbba2b1`. `5be5f55043c4` → `done
2026-09-16T19:11:40Z`, evidence *"REFUTED by measurement 2026-09-16: the row's CAUSE is still true
but its EFFECT is dead."* No open row names the actual floor. **Nothing on this box is currently
tracking the hermeticity prelint as the never-green cause.**

**(5) "Did YOU write to the read-only repo?"** — `git status --porcelain` shows two untracked
numerically-named empty files (`./0` 23:56 local, `./5` 23:42 local); `./5` predates my session and
was in the session-start snapshot. I tested causation with a **negative control**: running both
`test-hermeticity-lint.sh` and `--selftest` with `CC_HERM_ROOT` pointed at the repo but **cwd in a
neutral scratch dir** produced **no** numeric file (`ls` → NONE, twice). The lint is exonerated;
those files belong to a sibling session in the shared checkout. My first control was *invalid* (I
compared a `ls` taken in `/tmp` against one taken in the repo) and I re-ran it rather than report
it. I created no tracked file; my writes are `/tmp` only. Conviction I did not mutate the repo: **97%**.

**(6) "Is a run being truncated by its own 10800s bound — a third floor you missed?"** — The bound
is `SUITE_TO=10800` (`postland-verify.sh:279`, *"wall BACKSTOP only"*) and `run_s` clusters at
11,130-11,360 across dozens of runs, which is the classic signature of a bound that is always hit.
But `run_s` is the WHOLE run (prelints ~77-400s + corpus + retries), and the live process tree I
sampled was **54 min** into its corpus with no sign of the bound. I did not chase this further.
**It is the largest thing I have left unmeasured** and it is exactly the warning
`MASTER_CONVERGENCE_DEADLOCK.md` C1 gives in its own words: *"A timeout that is ALWAYS hit is not a
bound, it is a fixed cost … the two cases respond oppositely to raising it."* Next session should
grep the corpus rc for 124. Conviction that this is NOT a third independent floor: **55%** — i.e.
genuinely unknown.

---

## §8 — Answers, with conviction

| Q | Answer | Conviction |
|---|---|---|
| Is the producer running? | **Yes** — pid 98260, live child bats tree in `wt-run-98260`, 58 min in. Declared cadence 300s is a *request*; delivered verdict cadence is ~5-8/day because a real run costs ~3.1h. | 99% |
| Is the 321h drought real? | **Yes.** 86 greens all-time, **0 since 2026-09-03T16:23:25Z**; 64 reds since 09-04. | 99% |
| Is `test-hermeticity-lint --selftest` the blocker? | **Yes — but not via `failing[]` (1 of 64).** Its failure sets `PRELINT_UNPROVEN`, and `postland-verify.sh:3784` + `:523` make a green **structurally unreachable** with it set. `prelints_ran=4` on **23 of 23** stamps since 2026-09-12T07:35. | 95% |
| Is that failure pre-existing / unrelated to recent diffs? | **NO — it is diff-caused**, by `599d66b1c` (2026-09-12T03:07:46Z, added `tests/cc-owner.bats`) + `cc4925383` (added `tests/handoff-claim-assert.bats`). Neither fixtures `$HOME`. | 88% |
| Is there a standing single blocker suite? | **No** — 42 distinct suites across 64 reds; the 09-04→09-10 cohort was fixed and the drought continued. But **since 09-12 there IS a deterministic one**: `pipefail-sigpipe-lint.bats`, 20 of the last 21 runs, caused by the *same* commit pair. | 90% |
| Did T1/T1H/T2/T3 cure the 2026-08 deadlock? | **The CONVERGE deadlock: yes** (178 T2 advances). **The CERTIFICATION deadlock: no — that was never what the ladder addressed.** The ladder is a *bypass* of the green gate, not a repair of it; `deploy-live.sh:57-58` says so outright. | 92% |
| Is the current symptom the same deadlock returning? | **No. Different mechanism, same shape.** 2026-08 was *"green-only tier ⇒ pointer lags by construction"*. Today is *"a selftest failure makes the green VERDICT unreachable"*. What is identical is the **generator**: a fail-safe non-verdict that renders as the healthy retry state. | 85% |
| Does it block converge? | **Mostly degrades.** 3 commits behind, advanced 29 min ago; 178 DEGRADED : 1 VERIFIED. **But it blocked once** — `class=trunk-red`, backlog `e6901a1da802`, 2026-09-16T14:55Z, still BLOCKED. And `green_depth=235..278` vs `scan_n=200` means T1 is now past the scan window. | 96% |
| What single change unpins it? | **None; two are required.** (A) fixture `$HOME` in the 2 suites — makes green POSSIBLE (~2 lines + ~15-25 or a documented split). (B) drain 5 pipefail consumers — makes green LIKELY (5 one-line edits, fix printed verbatim). **If forced to one: A**, because it also re-arms the CUT_MAX alarm so the system starts reporting B itself. | 90% |

### The one-line summary
**A feature that landed on 2026-09-11/12 (`599d66b1c` + `fd74695be`) planted two mutually-invisible
floors — a non-hermetic `setup()` that makes the GREEN VERDICT unreachable, and a pipefail ratchet
drift that keeps every run RED — and because a RED resets the CUT streak, the alarm built for
exactly this (`CUT_MAX=3`) has read `consecutive=1` for five days and never fired.**

### Filed-worthy residuals (none driven; repo is read-only)
1. **No open backlog row tracks the real cause.** Both cited rows are closed.
2. **T1H's off-box producer is dead** — newest stamp 2026-08-13, 35 days. That is why positive
   evidence has one instance against 178.
3. **`run_s` pegged at ~11,200s** — unmeasured; see §7(6).
4. **C30 floor probe exits 126** on all three of kitty/mailbox/operator-readout, so those
   convictions stand with no working differential control.
5. **Attribution defect**: `CUT_WHY` says *"the LINT is broken, not the tree"* while quoting the
   lint saying *"the real tree is not clean"*.

---

## RESOLVED — item (6), the "third floor" left at 55% conviction (2026-09-18, successor)

§(6) closed with *"the largest thing I have left unmeasured"* and prescribed: **"Next session
should grep the corpus rc for 124."** Done. The answer is **no third floor**, and the prescribed
probe could not have produced it.

**The probe was unanswerable as written.** Grepping the postland stores for an rc finds nothing:
2,303 records scanned across `$STATE/*.jsonl` and **no `rc` field exists on any of them** (the one
literal `124` in `flakes.jsonl` is a substring, not an exit code). A cut does not record its rc
there; it routes into the CUT path instead.

**The evidence that actually answers it is the `cuts` ledger, and it holds ONE entry** —
`688c1ef0…  1  1789717338` (2026-09-18T07:42:18Z). The hypothesis was that `run_s` clustering at
11,130–11,360s is "the classic signature of a bound that is always hit". A wall firing on every
run would have produced a cut per run; there is one. ⇒ **`SUITE_TO` is behaving as its own comment
claims — a backstop, not a floor.** The primary bound is the TAP-progress stall
(`POSTLAND_STALL_S`, 900s), which is what `postland-verify.sh:3735` cuts as rc 124.

⚠️ **One correction to §(6)'s own reading, worth keeping.** Line 39's *"nothing can return 124"*
is scoped by the word immediately before it — **"unbounded"**. It means an *unwrapped* command
cannot return 124, which is why bounds exist at all; it does **not** mean 124 never occurs. The
stall detector produces exactly that code. Reading the clause without its qualifier turns a
statement about one configuration into a statement about the system — the same
narrow-fact-widened-to-a-world-fact shape this repo logged three times on 2026-09-17/18.

**And the search turned up a real defect: the header's bound had drifted from the code.** Line 38
advertised `POSTLAND_SUITE_TIMEOUT_S (5400)` while line 279 sets **10800** — and line 280 documents
the change in passing (*"10800 (was 5400, was 2700)"*), so the value moved and the header did not.
Anyone reading the contract block got a number the program stopped using. Corrected in place;
`POSTLAND_FILE_TIMEOUT_S (300)` was verified to still match. That drift is very likely **why §(6)
was alarming in the first place**: `run_s` at ~11,100s sits far above a believed 5400s wall and
right at a real 10800s one, so the clustering looked like a bound always being breached rather
than a backstop rarely reached.
