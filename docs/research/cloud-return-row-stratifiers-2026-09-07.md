# The cloud-return row already carries `load1` and `elapsed_s` — it landed, was auto-reverted, and was re-landed

**Row:** backlog `2b0888bc8832` — *"add `load` (1-min avg) and the pass's own `elapsed_s` to the
cloud-return IDL row (scripts/autonomy-sweep.sh log_idl cloud-return) — today the row carries only
rc, so 'did the drain fix work' cannot be stratified by load, and a single rc=0 is satisfiable by a
quiet box (evidence: DRAIN_CIRCUIT_2026-09-01.md §3g — an rc=0 at 17:58Z on the OLD reader, with
load falling ~23→~8 across the same window)."* Filed 2026-09-03T20:56:39Z.

**Verdict: DONE, cured on trunk, no code work performed.** Every `cloud-return` row written on trunk
today carries `elapsed_s` and `load1`. The condition the row states is satisfied by **two** writers,
not one, and neither can emit a bare-rc row.

## The cure, and why it looked missing when the row was re-read

The fix landed **the same day the row was filed**, was taken back out by an automated post-land
veto, and was re-landed the next day. A reader checking only the newest bytes of the file the row
cites would also find the fix moved to a *different* file two days later. All four commits are
ancestors of `origin/main` (asserted with `git merge-base --is-ancestor`):

| sha | date | what it did |
|---|---|---|
| `2c6b8cdfa777` | 2026-09-03 | **the fix** — *"the cloud-return row could not tell a fixed pass from a quiet box"*. Added `elapsed_s` + `load1` to `log_idl cloud-return` in `scripts/autonomy-sweep.sh`, plus the 3h test. |
| `d12097506` | 2026-09-04 | **auto-revert** of the above by the post-land veto. |
| `1f5385f9b` | 2026-09-04 | **re-land**, with the veto's conviction refuted: every `autonomy-sweep` row in `flakes.jsonl` is `outcome:"cut-not-red"` (2026-08-25 @ load 13.30, 09-01 @ 31.69, twice on 09-04 @ 22.76 and 23.42, the last two `exit 75 / notok=0` — the suite was KILLED with zero failing tests, a non-verdict, not a red). |
| `7d72371ca` | 2026-09-06 | **the move** — the return pass left the sweep tick for `scripts/cloud-return-lane.sh`; the two fields went with it, and the sweep kept the keys. |

So the row's premise (*"today the row carries only rc"*) was true when written and false ~0 hours
later. It is a **stale-premise** close, not a refutation: nothing in the row was wrong, and the
remedy it asked for is the remedy that shipped.

## Where the fields live now, and why the file swap is not new work

The dispatch brief's caveat — *"if the condition is still live but against a DIFFERENT set of files,
that different set IS the work"* — is the right question here and the answer is no. After
`7d72371ca` the pass runs in a detached lane, and **both** writers journal the same keys:

- `scripts/cloud-return-lane.sh:145-149` — the real row. `load1()` reads `sysctl -n vm.loadavg`
  field 2, **after** the pass and **only if it ran**; `elapsed_s` is `date +%s` deltas around the
  bounded child. Emits `{cloud_return_rc, elapsed_s, load1, bound_s, note}` under
  `tool: "cloud-return-lane"`.
- `scripts/autonomy-sweep.sh:442-444` — the residual row, written only when the lane is still
  running past the 20 s grace (`detached`) or was never spawned (`skipped*`). It carries
  `elapsed_s: null, load1: null` **explicitly**, with a note naming the lane as the writer of the
  real ones.

The keys are present on every path. A `cloud-return` row with rc alone cannot be produced.

## The fail-safe direction is the one the row cared about

Both writers fail to **empty → JSON `null`**, never to `0`. That is the whole point: a `0` on a
not-run path reads as *"ran instantly on an idle box"* — the exact reading `§3h` exists to make
impossible, and the same failure the row's own evidence describes (an `rc=0` satisfiable by a quiet
box). `load1` also fails to null when `sysctl` is unreadable: unmeasured is not quiet.

## What I actually ran

`bats` is not installed on this cloud VM, so `tests/autonomy-sweep.bats` could not be executed here.
The pinning test exists and names this row's evidence verbatim —
`tests/autonomy-sweep.bats:1587`, *"3h: the cloud-return IDL row carries elapsed_s + load1, and a
NOT-RUN pass is null not 0"*, three arms (A: pass runs, both numeric · B: pass absent, lane journals
nulls · B′: lane absent, sweep journals nulls). `1f5385f9b`'s message records it green on the desk
at `1..67`, producer rc=0, 0 `not ok`.

What I could execute, I did: the three `jq` row-construction expressions lifted verbatim from
`origin/main`, against the fixtures the three arms use.

```
ARM A  {"cloud_return_rc":"0","elapsed_s":137,"load1":22.76,"bound_s":5400,…}   both numeric   PASS
ARM B  {"cloud_return_rc":"skipped","elapsed_s":null,"load1":null,…}            null, not 0    PASS
ARM B′ {"cloud_return_rc":"skipped-no-detach","elapsed_s":null,"load1":null,…}  null, not 0    PASS
```

## Two facts about the dispatch itself

**Dispatcher vintage: EQUAL.** `git rev-parse origin/main:bin/cc-dispatch` is
`98ab38f51f7ac82a043e522d3a9601ff9f460528`, the same blob that composed this brief. The dispatcher
that fired this pass IS trunk, so there is no landed-not-live gap to explain the re-dispatch.

**The supersession adjudication the brief asked for.** Sibling `65e7b6542009` (done
2026-09-05) is the row that *carried the re-land* — its evidence line cites `1f5385f9b` and the
refuted `cut-not-red` conviction. It did not merely touch a shared file; it discharged this row's
condition as a side effect of restoring the auto-reverted commit. This row and that one were two
views of the same change, and closing that one left this one open over bytes already on trunk.

**Generalisable:** a row filed against a defect that is fixed *within hours* survives the fix, and a
post-land auto-revert makes the fix look absent for a day in between. The re-read that would have
caught it is `git log <filed-ts>..origin/main -- <cited path>`, which the brief's EVIDENCE AGE block
now prints — it listed `d12097506` and `1f5385f9b` adjacently, and that pair is the whole story.
