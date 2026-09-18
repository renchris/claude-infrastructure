# A re-land row's falsifier measures BYTES, so a superseded branch never retracts

**Measured 2026-09-17, from the dispatch of backlog row `0f0c1a0cf356`**
("re-land wt-82b87a8a2945: ship-land could not complete and its author's pane may be gone").

## The verdict on that row: PREMISE REFUTED, and acting on it would have REVERTED trunk

The row's stored falsifier is `land-content-verify.sh` against
`refs/land/failed/20260911T055004Z-65ab6c5f-…-wt-82b87a8a2945`. Re-run at dispatch it
exits 1 — *not refuted* — reporting "2 of 2 path(s) hold content origin/main LACKS":
13 lines in `bin/cc-backlog`, 1 line in `tests/cc-backlog-self-path.bats`.

That verdict is **true about the bytes and false about the work.** The ref's single
commit `6f099e0b8` ("fix(cc-backlog): the premise gate reports itself on every path")
is the **defective first cut** of work whose corrected form landed nine hours later as
**`1784b21e6`** ("fix(cc-backlog): the premise gate records what it saw, on every
path", 2026-09-11 09:36:36 -0500, ancestor of `origin/main`).

Trunk is a strict **superset** of the ref:

| | ref `6f099e0b8` | trunk `1784b21e6` |
|---|---|---|
| premise-gate reports | 3 (`unresolved`/`admitted`/`disabled`) | same 3 |
| premise-gate bats cases | 6 | **9** (the ref's 6, last one renamed, plus 3 more) |
| emission point | `printf … >&2` **inside the gate** | `pmsg=…` deferred to line 3351, **after guard (6)** |

The 13 "lines present only in the ref" are not missing features. They are
(a) the pre-refactor spelling of messages trunk already carries, and
(b) the **pre-fix** `hostname -s` form of host identity, which trunk deliberately
replaced with `host_id()`/`host_is_local()` under backlog `7e8cff2e822c`. The 1 test
line is a rename — trunk keeps the old name too, as
`PREMISE GATE CONTROL (legacy name): …`.

### Re-landing it is a measured regression, not a duplicate

A/B, one variable — trunk's `tests/cc-backlog-condition-lease.bats` run against each
arm's `bin/cc-backlog`, everything else byte-identical:

```
ARM A  bin/cc-backlog @ origin/main (1784b21e6)   21 ok, 0 failed
ARM B  bin/cc-backlog @ 6f099e0b8 (the failed ref) 19 ok, 2 failed
```

Arm B fails exactly the two cases the landed commit's body predicted:

- **case 3** — `the refusal carries verdict=sibling-held on line 1 and names the sibling`
- **case 19** — `verdict=sibling-held survives cc-dispatch's own claim_excerpt`

both with line 1 displaced to `cc-backlog claim: gate=premise-admitted verdict=clear rc=0`.
`cc-dispatch`'s `claim_excerpt` reads `head -1`, 200 chars, so the ref's in-gate
`printf` silently blinds the dispatcher's sibling-held discrimination. Landing this ref
would have reverted the host-identity fix **and** reintroduced that regression.

This is the hazard `scripts/ship-land.sh:1246-1247` already documents in prose —
*"25 re-land rows … were false — the work had landed under a different sha — and
actioning four of them would have REVERTED trunk"* — confirmed here on a live row, with
the regression measured rather than asserted.

## The population: 7 rows, and every supersession hatch needs textual lineage

All 7 live rows whose falsifier is `land-content-verify.sh`:

| row | status | ref-only commits | trunk subject match | falsifier now |
|---|---|---|---|---|
| `0f0c1a0cf356` | claimed | 1 | **yes** — `1784b21e6` | exit 1 (not refuted) |
| `fd48f546a21f` | open | **0** | n/a — ref is an ancestor | **exit 0 — LANDED** |
| `8690789f863e` | open | 3 | **yes** — `d67a81c89` | exit 1, residual 15 lines |
| `b14c62d8c878` | open | 2 | **yes** — `4fa6d3c80` | exit 1, residual 7 lines |
| `284a211e9a83` | open | 1 | no | exit 1 |
| `78e8987b1306` | open | 1 | no | exit 1 |
| `34c8de93de46` | claimed | 1 | no | — |

Three of seven have a same-subject corrected retry already on trunk, and the oracle
reports *not landed* for every one of them.

**CORRECTION to the obvious reading, and it is the sharpest thing in this document.**
The oracle is **not** naively byte-level — an earlier draft of this file said so and was
wrong. `scripts/land-content-verify.sh:326-338` already carries **three** escape hatches,
tried in order, before a path counts against the verdict:

| hatch | what it requires |
|---|---|
| `trunk_ever_carried` | trunk once held **this exact whole-file blob** → SUPERSEDED |
| `trunk_covers_every_line` | trunk holds **every ref line** as a multiset superset → RELOCATED |
| `trunk_landed_this_commit_amended` | **this commit** landed in amended form → AMENDED |

All three are tests of **TEXTUAL LINEAGE** between the ref and trunk, and the design is
sound for what it was built for. A **corrected rewrite** shares none of them: `1784b21e6`
re-implemented the same feature from scratch, so trunk never held `6f099e0b8`'s blob,
does not contain its `hostname -s` lines (it deliberately replaced them), and is not that
commit amended. The ref falls through all three hatches **correctly**.

So the verdict is *literally true of every path* and still produces the **wrong action**.
That is the whole defect, and it is much narrower than "the oracle is byte-level": the
gap is a supersession relation with **no textual lineage at all**, which no lineage test
can reach. The retraction arm fails in the direction that **preserves the pile**, for
exactly the rows it was built to retire.

## Two further live faults found while measuring

**1. A row whose falsifier already retracts it stays OPEN.** `fd48f546a21f`'s own stored
probe exits **0** — `"introduces nothing origin/main lacks (0 paths) — LANDED"`, plus
the oracle's own ancestor note. `ship-land.sh:1249-1252` defines exit 0 as *the
retracting direction*. The row was still open and dispatchable. Closed in this session
on that evidence.

**2. A live re-dispatch loop.** The premise-gate instrument that `1784b21e6` landed has
been recording for a week (`2026-09-11T22:13Z → 2026-09-18T01:16Z`), 411 gated claims:

```
396  premise=admitted:clear
 15  premise=admitted:suspect
  0  refusals
```

All 15 suspect admits fall on **3 rows**, and **12 of them are one row** —
`284a211e9a83`, claimed once an hour or two from 2026-09-16T22:26Z to 2026-09-17T17:46Z,
never completing. A trailing run of self-released claims is evidence about the
**dispatcher**, not about the item's difficulty.

This is the question `1784b21e6`'s body said was unanswerable at the time
(*"how often is a worker dispatched onto a falsified row" cannot be asked of the
store*). The instrument it landed makes it askable, and the answer is above.

## The open fork — why this is filed rather than fixed

Adding a **fourth, lineage-free** hatch is a genuine value fork on the landing gate
(the three lineage hatches above already exist and are not in question):

- **Auto-retract** on a same-subject trunk match changes `rc`, so `cc-premise` would
  close rows automatically — and a wrong match **silently drops genuinely stranded
  work**. Irreversible in the direction that loses commits.
- **Advisory-only** (print a supersession candidate, leave `rc` alone) is safe and
  changes nothing automated: `ship-land` only resolves a *path* to this oracle to store
  as a probe, and `cc-premise` reads `rc`. A line nothing reads is a detector with no
  owner.

Conviction in either specific course: **~40%** — which is why it is the operator's call
and not this session's edit.

## Method warnings

- `git diff origin/main:<path> <ref>:<path>` shows trunk-only content as `-` lines. The
  failed ref here was **behind** trunk on an unrelated feature, so the naive read is
  backwards. Filter for `+` to get what the ref actually holds.
- Grep trunk for the **feature identifiers**, never for the bytes. Every conclusion here
  came from `git log -S'<identifier>' origin/main`, not from the byte diff.
- The commit body of a corrected retry is the previous author's diagnosis. It was right
  here — but it was confirmed by *running both arms*, which is what makes the regression
  a measurement instead of a quotation.
