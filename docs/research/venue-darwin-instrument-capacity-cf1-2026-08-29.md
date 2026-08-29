# A Darwin kernel instrument names no local-only word, so its post-land RED was dispatched off-box

**2026-08-29.** Backlog item `f6db308ba6e6`, **project `claude-infrastructure`**, was dispatched to a
`--venue cloud` session:

> post-land RED: `tests/capacity-alarm.bats::CF1: the row records the coalition TRUE member count and
> a shared-aware footprint` @ `02926ff141ec`

The item is **unworkable on arrival** for the same end state as
`venue-foreign-subject-repo-2026-08-15.md` and `venue-foreign-project-repo-2026-08-14.md`, reached by
a **third route**: the row's project is right, the repo is attached, the subject file is in this
clone — and the subject itself is a **Darwin kernel instrument**. A Linux microVM cannot run it, so
it cannot reproduce the RED, and cannot tell a fix from a no-op.

Written from inside that VM. Trunk at the time: `a6449cebc580`.

## 1 · The trunk check first — no cure has landed, the item is genuinely open

The dispatch rails require reading what the item cites on TRUNK, because a post-land RED reproduces
faithfully in a stale tree and a correct-looking diagnosis can produce a diff that reverts trunk
(`6110fc45141e`). Done, and the answer is *not* "already fixed":

| check | result |
|---|---|
| `git rev-list --count HEAD..origin/main` / `origin/main..HEAD` | `0` / `0` — this tree **is** trunk |
| `git merge-base --is-ancestor 02926ff141ec origin/main` | yes. It is `fix(permission-audit): the survivor arm was a dead negation…` — the HEAD the verifier stamped, not a commit touching this subject |
| `git log 02926ff141ec..origin/main -- scripts/capacity-alarm.sh tests/capacity-alarm.bats` | **empty** |
| the two commits since the CF block landed (`ca6b067b`) that do touch the alarm — `824bff82`, `fc1e0674` | neither adds, removes or edits a single `CF*` line (`git show <sha> -- tests/capacity-alarm.bats \| grep -c '^[+-].*CF[0-9]'` → `0`, both) |

So the RED stands on trunk. **`f6db308ba6e6` must not be marked done on the strength of this file.**

## 2 · Why this VM cannot adjudicate it — measured, not asserted

`scripts/capacity-alarm.sh`'s coalition instrument is Darwin-only in both halves: membership is
libproc `proc_pidinfo(PROC_PIDCOALITIONINFO)` reached through `ctypes`, and the footprint is
`/usr/bin/footprint`. Neither exists on Linux. Run here (`bats` is not installed on the VM either;
this is `bats-core` 1.13.0 installed ad hoc for the measurement):

```
$ bash scripts/capacity-alarm.sh --json --no-append
… "verdict":"NO-DATA" … "coal_procs":null … "coal_true_procs":null,"coal_id":null,
  "coal_fp_mb":null,"coal_fp_src":"unavailable" …

$ bats tests/capacity-alarm.bats -f 'CF1|CF2|CF3|CF5'
not ok 1 CF1 …   `[ "$s" = "measured" ] || false' failed
not ok 2 CF2 …   `[ … coal_fp_src … ] = "measured" ] || false' failed
not ok 3 CF3 …   `case "$p" in ''|*[!0-9]*) false ;; esac' failed
not ok 4 CF5 …   `case "$p" in ''|*[!0-9]*) false ;; esac' failed
```

**The signature here is a different one, and that is the point.** The desk filed exactly one test,
`CF1`. Here `CF3` and `CF5` fail too — they fail on `coal_procs`, rung 6's *pre-existing* tree-walk
field, which is null only because the tree walk's `ps -Ao pid=,ppid=,comm=`
(`capacity-alarm.sh:815`) finds no terminal-rooted population on Linux. A VM that reds four tests where the box reds one cannot distinguish a fix from a no-op: any
patch would be graded against a failure that is not the reported one. That is the anti-goal
`bin/cc-venue` §5 names — *a wrongly-routed item improvises a plausible answer against state it
cannot read, and reports success.*

## 3 · What IS derivable off-box: the failing assertion is narrowed to one

This much needs only the test text and does not need Darwin. CF1's assertions are, in order:

```bash
s = coal_fp_src ;  [ "$s" = "measured" ]          # ← also CF2's first assertion
t = coal_true_procs ; integer ; [ "$t" -gt 0 ]    # ← also asserted by CF5
mb = coal_fp_mb ; integer ; [ "$mb" -gt 0 ]
```

`coal_fp_mb` cannot fail alone: `read_coalition_footprint` prints `"%.0f"` and the shell sets
`COAL_FP_SRC="measured"` **only** when that output is non-empty (`capacity-alarm.sh:1009-1011`), so
`measured` implies `mb` is a positive integer string. `t` is asserted identically by CF5. Therefore
**the only assertion whose failure is consistent with CF1 being red is the first one**: the footprint
sample did not succeed, and `coal_fp_src` read `unavailable` (or `damped`, which the per-test
`CC_CAP_COAL_FP_STAMP` in `$BATS_TEST_TMPDIR` rules out on a fresh run).

**Falsifier, and it costs one lookup.** CF2 asserts the same thing on its first run, so *CF1 red ⟹
CF2 red*. If the sweep filed `CF1` and **not** `CF2`, this narrowing is wrong and the reasoning above
should be discarded rather than repaired.

## 4 · The instrument's error channel is lossy, which is why the log alone cannot say why

Six distinguishable causes collapse into the single token `unavailable`:

| cause | where it is swallowed |
|---|---|
| no terminal process in `TERMS` (`iTerm2 kitty ghostty Ghostty`) | `read_coalition_true` → `sys.exit(0)` |
| `proc_pidinfo` refuses for a pid | `coal()` → `None`, silently dropped |
| `/usr/bin/footprint` non-zero | `if r.returncode != 0: sys.exit(0)` |
| `footprint` exceeds the 45 s bound | `subprocess.run(timeout=45)` → `TimeoutExpired` → bare `except` → `sys.exit(0)` |
| a member pid exits between the `ps` snapshot and the `footprint` call | same bare `except` / non-zero rc |
| the JSON has no `total footprint` | `except` → `sys.exit(0)` |

This is in tension with the suite's own property #1 — *"a broken instrument reports NO-DATA, never a
false OK"*. It does report its absence; it just cannot say **which** absence, so the RED is not
diagnosable from `cap.jsonl` and needs a box-side probe.

## 5 · The four probes that settle it, in cost order — all box-only

1. **Is it load-dependent at all?** Idle box: `CC_CAP_COAL_FP_STAMP=$(mktemp -u) bash
   scripts/capacity-alarm.sh --json --no-append` → if `coal_fp_src` is `measured`, the instrument
   works and the RED is a property of the *gate run*, not of the code.
2. **Reproduce under the real conditions.** Same command while the full corpus is running (the
   verifier runs it in the `utility` QoS band alongside ~12 concurrent gate runs). `unavailable`
   here plus `measured` in (1) localises it to contention.
3. **Is the 45 s bound the binding constraint?** Time `/usr/bin/footprint` over the live terminal
   coalition *during* a gate run and count the members. The feature commit (`ca6b067b`) measured
   5.4 s over 145 members on an interactive box — but the terminal coalition contains every session
   and every `bats` child the gate spawns, so both the member count and the address-space complexity
   the cost tracks are inflated by the very run that is asserting on it.
4. **Does a vanished member sink the whole sample?** One command, and it is the hypothesis worth
   killing first because it needs no load at all: run `footprint --json <tmp> -p <live> -p <dead>`
   with one already-exited pid. If that returns non-zero, the instrument is structurally unable to
   sample a churning coalition — the member list is snapshotted from `ps` and used seconds later —
   and the fix is to tolerate vanished members, **not** to widen the bound.

## 6 · The seam that would make CF1 assertable at all

Every other external tool this script reads has a `CC_CAP_*` override so a test can stub it —
`CC_CAP_PS`, `CC_CAP_TOP`, `CC_CAP_ZPRINT`, `CC_CAP_SYSCTL`, `CC_CAP_TIMEOUT`, `CC_CAP_PYTHON`.
`/usr/bin/footprint` alone is hardcoded (`capacity-alarm.sh:976`), so CF1 has no way to assert the
recording path except against the live box, on a probe that is expensive by design and bounded so it
may give up. Compare the zprint slow lane in the same file, which is opt-in precisely because it is
expensive and can stall (`CC_CAP_SEG_SOURCE=est` by default) — the footprint lane is the same cost
class and is on by default.

Also noted while reading, not fixed: the seams header (`capacity-alarm.sh:196-209`) documents every
`CC_CAP_*` seam **except** the four the CF block introduced — `CC_CAP_COAL_FP`,
`CC_CAP_COAL_FP_MIN_S`, `CC_CAP_COAL_FP_STAMP`.

No patch is proposed here. Which of §5's four causes is live decides whether the remedy is a seam, a
bound, churn tolerance, or a test that stops asserting a live expensive probe — and this VM cannot
run the probe that chooses between them.

## 7 · The venue miss, measured — and deliberately not fixed here

`cc-eligible` promoted this row because its text names **nothing** the spelling list knows. Measured
from this VM against a fixture carrying the row's verbatim title and project:

```
$ cc-eligible why f6db308ba6e6 --json
{ "verdict": "eligible",
  "description": "repo-only work — no local-only state named",
  "tokens": [], "classes": [],
  "history": { "state": "ok", … } }
```

`eligible` is correct under every rule the file has. The row cites no sha, so the measured
history-reach arm is silent; it needs no browser, no pane, no launchd, no `~/.claude`. The BOX list
already carries `macos`/`darwin`, `sysctl`, `jetsam` and `signal` for exactly this class — but a row
can name a Darwin-kernel subject without ever spelling one of those words, and *"the coalition TRUE
member count and a shared-aware footprint"* is that row. `coalition` and `footprint(1)` are Darwin
process-coalition vocabulary and appear in no other subject in this repo.

**Not fixed here, deliberately.** `docs/plans/CLOUD_BACKLOG_PIPELINE.md` Phase 0 states it as a hard
constraint: *"W1 (the venue producer) must NOT be built by a cloud session… a cloud VM building its
own admission rule is a circular dependency."* `cc-eligible`'s own `OFFBOX_LANE` class enforces the
same thing (`tests/cc-eligible.bats` 11-12, *"the lane cannot verify a change to itself"*), and the
file's header requires a spelling to be **measured against the live store** before it is added — a
store that does not exist on this VM. Two independent reasons, one conclusion: the spelling belongs
to the desk. It is recorded here, with the id that exposed it, in the form that header asks for.

There is a stronger arm available than a spelling, and it is worth considering on the box because
this file's own header says a denylist enumerates spellings and never the class: the row names
`tests/capacity-alarm.bats`, and whether that suite's **subject** is Darwin-only is a *mechanical*
property of the tree (`grep -l 'vm_stat\|proc_pidinfo\|/usr/bin/footprint\|zprint\|pmset\|osascript\|
launchctl\|hw\.ncpu'`), the same shape as the existing measured history-reach arm rather than another
word in a list.

## 8 · The ledger disposition could not be written from here

Same as `venue-foreign-subject-repo-2026-08-15.md` §"could not be written": `~/.claude/autonomy/` does
not exist on this VM, `cc-backlog` answers `unknown id`, and `cc-notify` has no desk to reach. **A
cloud VM's only durable channel to the desk is the branch it pushes, so this file is the
notification.** The desk should:

1. `cc-backlog reopen f6db308ba6e6` — it is blocked on information (§5's probes), not on an operator
   action, so it is a reopen and not a `block --needs`;
2. re-label it `venue local` (`cc-venue`) so the next sweep does not re-dispatch it off-box;
3. claim it locally and run §5's probes, cheapest first.

## 9 · The item itself — NOT adjudicated

No claim is made here about why `CF1` reds on that box beyond §3's narrowing, and none should be
inferred from §5's candidate list: those are hypotheses with the measurement that kills each one
named beside it, not findings. The one thing established is negative and it is the useful one —
**the cure is not already on trunk**, so a future session need not re-run §1.
