# The inflow alarm could retract itself — `backlog-flow-assert.sh --assert`, 2026-09-17

Record for cc-backlog `40250b0f698a` (condition `backlog-inflow-net-positive`, filed by
`scripts/backlog-flow-assert.sh --file`, DoD ref `origin/main:docs/plans/BACKLOG_DRAIN_24_7.md` §6).

Run off-box on a cloud VM. The operator's store is not reachable from here, so **every number below
is from a constructed store**, and the one production fact — that the probe answered `rc 0,
(silent)` on the desk — is quoted from the dispatch brief, not re-measured.

---

## 1. What the item was, and why its closure evidence is not evidence

The row arrived pre-closed. The dispatcher had already run the item's own stored falsifier and
rendered cc-premise's exit-0 branch verbatim:

```
FALSIFIER PASSED — this item's own re-run check says the condition it was filed for is GONE.
It exited 0 just now, against today's tree, not at filing time.
  probe: bash .../scripts/backlog-flow-assert.sh --assert
  output: (silent)
```

The instruction attached to that branch is *"If you believe the probe is wrong, fix the PROBE — do
not work around it, or the next reader inherits the same false verdict."*

The probe is wrong, and `(silent)` is how you can tell. `--assert` returned exit 0 for **five
different states** and printed nothing in any of them:

| state | what it means | pre-fix `--assert` |
|---|---|---|
| `draining` | closed ≥ added — the condition really is gone | `rc 0`, silent |
| `unknown:skipped` | no store, or no jq — could not ask | `rc 0`, silent |
| `unknown:read-failed` | the store would not parse | `rc 0`, silent |
| `unknown:short-history` | the store is younger than the window | `rc 0`, silent |
| `unknown:unparsed-could-flip` | the excluded pile exceeds the margin | `rc 0`, silent |

Measured pre-fix, driving the subject exactly as `cc-premise.run_falsifier` does
(`scratchpad/rp/rp.sh`, reproduced in `tests/backlog-flow-assert.bats` case 11d):

```
  no store               rc=0  output: (silent)
  unreadable store       rc=0  output: (silent)
  short history          rc=0  output: (silent)
  unparsed-could-flip    rc=0  output: (silent)
  draining               rc=0  output: (silent)
  net-positive           rc=1  output: backlog-flow: NET-POSITIVE over 7d — 3 filed / 0 closed …
```

So the closure this item arrived with is compatible with the week genuinely draining **and** with
four states in which nothing was measured at all. Nothing in the reading separates them. That is
this corpus's `fail-safe-default-mimics-the-healthy-state`, and the cost is not a misreport: it is a
**retraction**. `bin/cc-premise:1402` treats exit 0 as the one blocking answer — THE CONDITION IS
GONE — so an abstention did not merely fail to measure the week, it retired the standing inflow
alarm on a measurement that never ran.

**I cannot say from here whether the desk's week was draining.** That is the honest verdict, and it
is why the deliverable is the probe rather than a close: after this fix the same run prints which of
the five it was, and a `draining` prints its figures.

## 2. The polarity was argued for a consumer that does not exist

The subject's header justified the fail-open explicitly:

> `--assert` therefore exits 0 on every abstention. It is a falsifier — its rc-1 direction is the
> CONVICTION — so an unknown must read exactly like a healthy week to every consumer.

Grep the tree. `--assert` has **one** consumer: the `--falsifier` string the subject's own `--file`
arm stores on the row it files. `autonomy-sweep.sh` calls `--json` and `--file`; no gate, no plist,
no test runs `--assert` as a blocker. For the consumer that does exist, "reads like a healthy week"
and "retract the alarm" are the same rc — and its forbidden direction is the opposite one.

**This is not a new policy, and the argument was already settled in this repo.** `backlog-ratchet.sh`
carried the identical defect on the identical signal and was fixed under backlog `2366f99e04a7`,
whose comment states the rule verbatim:

> `--assert` is registered as a stored falsifier … and cc-premise's `run_falsifier` reads exit 0 as
> THE CONDITION IS GONE. So an absent jq did not just fail to measure coverage: it told the currency
> pass the coverage regression had cleared, and the closer would retire the alarm on the strength of
> a measurement that never ran.

That cure chose **rc 2** because 2 is in cc-premise's `_FALSIFIER_UNASKABLE_RCS` ({2,124,126,127}),
rendered "COULD NOT ASK … UNVERIFIED, not confirmed … fix the PROBE if it is the thing that is
broken". A fourth code would fall outside that set and render "NOT REFUTED", which is a different
and weaker claim (`new-enum-member-falls-into-fail-closed-default`). `backlog-flow-assert.sh` landed
in `5000db42`, **after** that fix, and did not inherit it — it is the ratchet's sibling by
construction ("same four modes, same fail-open discipline, same condition-keyed self-retiring row").

Aligning to the sibling invents no threshold and needs no argument about polarity
(`the-blocking-gate-was-stricter-than-the-repos-own-verifier`, read in the other direction: before
tuning a gate, grep the repo for the sibling that already adjudicates the same signal).

## 3. The second defect: guard 4 weighed a pile that excluded the store's largest hole

Guard 4 exists to enforce *excluded evidence is not absent evidence* — if the records this pass
could not place outnumber the margin the verdict rests on, that pile alone could reverse the sign.
It counted `unparsed`: records that parsed but carry no readable `ts`.

The jq pass opened `[ inputs | fromjson? // empty | select(type=="object" and has("id") and
has("event")) ]`. A line that does not parse **at all** is dropped there — into neither `records`
nor `unparsed`. So the guard weighed its margin against a pile that excluded the store's dominant
exclusion channel, and that channel is measured and is this repo's own: a record longer than the
writer's 4,096-byte stdio buffer is appended as ≥2 `write()` calls, so a concurrent appender lands
between the pieces and **both halves stop parsing**. One census dropped **12.33% of this very
store** that way (W2-B17, `1550268e6`) — the note sits one screen above this detector's own call
site in `autonomy-sweep.sh`, beside the 6,953-byte emitter that caused it.

Measured, one store, one variable — 12 in-window `add` lines spliced by a concurrent append:

```
intact  : verdict=net-positive  added=12 closed=6 net=+6  unparsed=0 records=19   --assert rc=1
spliced : verdict=draining      added=0  closed=6 net=-6  unparsed=0 records=7    --assert rc=0 (silent)
```

A **sign flip of 12**, emitted confidently, with the guard built to prevent exactly this reporting
an empty pile — and then delivered to cc-premise as "the condition is GONE". The two defects
compose: (3) manufactures the false verdict, (2) delivers it with no tell.

The mirror is the other forbidden direction. Splicing `done` records instead:

```
intact  : verdict=net-positive  added=8 closed=7 net=+1  unparsed=0 records=16
spliced : verdict=net-positive  added=8 closed=0 net=+8  unparsed=0 records=9
```

net inflated 8×, which is the FALSE NET-POSITIVE that files a standing, condition-keyed row into
the store this program exists to drain.

## 4. The fix

`scripts/backlog-flow-assert.sh`, 126 insertions / 15 deletions, no behaviour change to `--file`:

1. **The jq pass counts what it drops.** A non-blank line that does not become a record is counted
   as `dropped`; guard 4 now weighs `excluded` = `unparsed + dropped`, and `why` names whichever
   channel dominates (`unparsed-could-flip` / `unreadable-lines-could-flip`). `has("id")` is the
   discriminator rather than a sentinel key: every kept record has `id` by construction and the drop
   marker has none, so they cannot collide. A **blank** line carries no record and is not evidence
   of a lost one, so it is not in the pile — otherwise a trailing newline would abstain forever
   (`acceptance-gate-must-be-monotone-in-evidence`). A spliced record counts as 2 physical lines,
   over-stating the pile; that over-statement only ever buys another abstention, and an abstention
   files nothing and now retracts nothing.
2. **`--assert` says which of the five it is.** `1` net-positive · `0` draining · `2` every unknown.
   Every verdict prints its line, so a genuine pass hands the closer *"12 filed / 18 closed
   (net −6)"* instead of `(silent)`.
3. The header sentence quoted in §2 is **struck through in place, not deleted** — it is the record
   of what was believed, and its first half (the four abstentions) is right.

**What deliberately did not change.** `--file` still files on `net-positive` alone, so no abstention
can mint a row; §6's structural false-positive — a store younger than the window, net-positive by
construction — is untouched on a healthy new box. The fail-open intent survives where it was load-
bearing; only the rc delivered to a retracting consumer moved.

## 5. What was run

Off-box, Linux, `jq-1.7`, `bats 1.14.0`, `shellcheck 0.11.0`.

| check | result |
|---|---|
| `tests/backlog-flow-assert.bats` | **25/25 ok**, plan line `1..25`, 0 skips |
| same suite vs. the **pre-fix** subject (`git show origin/main:`) | **9 red** — every changed/new case: 2, 8, 9, 10, 12, 14, 15, 16, 17 |
| `shellcheck scripts/backlog-flow-assert.sh` | rc 0 (rc read from the producer, not through a pipe) |
| `scripts/bats-assert-liveness.py tests/backlog-flow-assert.bats` | rc 0 |
| `scripts/test-hermeticity-lint.sh` on the changed suite | clean, **0 new leaks** |
| `tests/autonomy-sweep.bats` | 80/81 — the 1 red is **identical on pristine trunk** (A/B'd) |
| `tests/bats-assert-liveness.bats` | 31/37 — the 6 reds are **identical on pristine trunk** (no bash 3.2 on this VM; its own CONTROL case says so) |
| `tests/bats-shellcheck-lint.bats` | 27/28 — the 1 red is **identical on pristine trunk** |
| `scripts/unattended-path-lint.sh` | rc 1, output **byte-identical on pristine trunk** (macOS plist targets, absent on this VM) |
| `tests/bats-kill-guard-lint.bats`, `utc-stamp-lint`, `test-walltime-lint` | 35/35, 12/12, 16/16 |

Every red was A/B'd against a detached `origin/main` worktree before being called pre-existing — a
"pre-existing red" is a claim, not a measurement.

### Mutants, because a case that is green in both arms tests nothing

Each mutant is the implementation a later edit would plausibly reach for. All three die, and each
dies on exactly the cases that own the property — nothing else moves:

| mutant | dies on |
|---|---|
| M1 blank lines counted as lost records (drops the carve-out) | 16 (11c) only |
| M2 guard 4 weighs `UNPARSED` again, not `EXCLUDED` (the pre-fix threshold) | 14, 15 (11a, 11b) only |
| M3 abstention exits 0 again (the pre-fix falsifier polarity) | 8, 9, 10, 12, 14, 17 |

One instrument scar worth the line: the splice helper's first version matched every `add` record,
which includes `seed_history`'s anchor — splicing it destroys the store's history depth, so the
subject abstained at **guard 3** (`short-history`) instead of guard 4. Both are abstentions and both
exit 2, so the case would have stayed green while exercising a different guard from the one it
names. It was caught only by asserting `why` rather than `verdict`
(`fixture-identifier-shape-collapses-two-spaces` — the axis under test held constant by the
fixture). The helper now holds the anchor out, and says why.

Second scar, found by running rather than reading: the first draft put this file's prose *inside*
the single-quoted jq program, where one apostrophe in a comment ends the shell string. It died at
`line 295: syntax error near unexpected token '|'` — and, note the polarity, through `--assert` that
read as `rc=2` with the bash error as its output, i.e. the new code correctly reported "could not
ask" about its own breakage. The prose now lives above the quote with a comment saying why
(`fixture-stub-cannot-carry-an-apostrophe`).

## 6. Disposition

**The item is NOT closed on "the condition is gone"** — that is precisely the reading this session
found to be unsupported. It is closed on the instruction its own falsifier rendering carries: the
probe was wrong, and the probe is fixed.

Whether the desk's week was actually draining is now **answerable and was not before**. Re-run
`bash scripts/backlog-flow-assert.sh --assert` on the operator box and read the line it prints:

* `DRAINING over 7d — N filed / M closed (net −X)` → rc 0, the condition really is gone; close the
  row citing those figures rather than `(silent)`.
* `NET-POSITIVE …` → rc 1, the row was retired wrongly; it needs reopening and §6 routes the next
  fix to the INFLOW list C1-C4.
* `CANNOT TELL (<why>) …` → rc 2; nothing was measured. If `why` is `unreadable-lines-could-flip`
  the store is carrying spliced records and the W2-B17 writer-side size bound is the work.

## 7. Facts about the dispatch, recorded because the brief asked

* Checkout arrived **shallow at depth 50**; `git fetch --unshallow` run before any trunk read.
* `git rev-list --count HEAD..origin/main` = **0** — this tree IS trunk, so every read above is a
  trunk read.
* `git rev-parse origin/main:bin/cc-dispatch` = `27c461a5f1a4de551fdfbe2a619e28e696c13aaa`, **equal**
  to the blob that composed this brief. The dispatcher that fired this session IS trunk; there is no
  landed-vs-live gap to account for on that path.
* The C1–C4 INFLOW list §6 prescribes was audited as **done on trunk** in the plan's own §2.1 entry
  (C1 `46a86deb7`/`ship-land.sh:953`, C2 at the mint site `bin/cc-discover:268`, C3 first ratchet
  stage `bin/cc-backlog:2618` with the REFUSE stage still owed, C4 wired in `autonomy-sweep.sh`).
  Nothing here re-opens that; this fix is to the detector that decides *when* §6 fires, not to the
  remedy it routes to.
