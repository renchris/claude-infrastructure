# The resources that exhaust while every gauge reads healthy — H-CAP-1 panel verdict

**Date:** 2026-08-09
**Hole:** `H-CAP-1` (FRONTIER_HOLES.md) — *what resource on this box exhausts while every conventional gauge reads healthy?*
**Method:** 3 Fable 5 baseline-blind derivation panelists, independent, model-first then probe-to-refute. Panelists were told the box spec, the 150-session target, and the *class* of question only. The one confirmed member of the class (compressor segment exhaustion) and the in-flight ceiling model were deliberately withheld, so a re-derivation of either counts as convergence, not echo.
**Raw returns:** `docs/research/panels/h-cap-1/{cap-kernel,cap-userspace,cap-gauges}.md`, verbatim.
**Related:** `crash-rootcause-2026-08-09.md` (the confirmed member), `session-capacity-ceiling-2026-08-09.md` (the ceiling model this corrects).

---

## 1. Verdict

> ⚠️ **PARTIALLY CORRECTED 2026-08-09 by Phase E — the finding stands, the occupancy does not.**
> The tuning-fingerprint observation is intact and was the sharpest call in this panel: `ptmx_max`
> is genuinely the only table in the hundreds, genuinely stock, genuinely unmonitored, and
> exhaustion is genuinely silent. But **the occupancy figures below are inflated by a constant 16**:
> `ls /dev/ttys* | wc -l` also counts 16 **static legacy** BSD nodes (`/dev/ttys0..ttysf`, major 64,
> root:wheel, present since boot) that are allocated to nobody and governed by nothing. So the
> "**21 of 511** at ~6 live sessions" below was **5 of 511**, and the projected **1.5–4 ptys per
> session-equivalent** is really **~1.13 — one pty per PANE plus ~2 ambient**. 150 sessions
> projects to **~152, not 300–600+**, and the wall is at **~509 panes**. Prediction 1 in §6
> ("ramp to 50, predict 60–90") is superseded: predict **52 ± 4**.
> Full correction + the allocate/release test that proves the offset:
> `docs/research/pty-ceiling-2026-08-09.md` §2. Landed gauge: `scripts/pty-census.sh`.
>
> §2's separate finding — that `capacity-admit.sh` has no pty term and no compressor term — is
> unaffected and remains true.

**The panel found a new member of the class, and all three panelists ranked it #1 independently: the pty
namespace.** `kern.tty.ptmx_max = 511` — the only kernel table on this box sized in *hundreds* while every
other is 10⁴–10⁶, and the only one still at its stock value.

Verified directly by the lead after the returns:

```
kern.tty.ptmx_max:    511      ← STOCK
kern.maxproc:       16000      (stock 4000)   ← raised
kern.maxprocperuid: 10666      (stock 2666)   ← raised
kern.maxfiles:     491520      (stock 245760) ← raised
```

`cap-userspace` called this the **tuning fingerprint**, and it is the sharpest single observation of the
panel: every ceiling this box has *already* hit has been raised. `ptmx_max` sits at stock because the fleet
has never reached it — which is exactly why it is the next wall and why nothing watches it. Occupancy at the
time of measurement: **21 of 511**, with ~6 live sessions.

Three properties make it the archetype of the class:

- **No gauge anywhere reports it.** Not `top`, not Activity Monitor, not `vm_stat`, not load, not memory
  pressure, and no sysctl reports *occupancy* — only the limit. The sole census is `ls /dev/ttys* | wc -l`,
  which nothing monitors.
- **The failure is a spawn error, not a slowdown.** `posix_openpt` returns ENXIO/EAGAIN: kitty reports "could
  not open pty", `handoff-fire --split-right` fails, teammate spawns fail — while every conventional metric
  is green. It reads as an application bug, not a capacity ceiling.
- **It cannot be tuned past ~999.** pty slaves are named `/dev/ttys%03d` — three digits — so the architectural
  ceiling is ~999 even with the sysctl raised (`cap-userspace`'s derivation from XNU `tty_ptmx.c`; the
  refusing-sysctl confirmation was correctly *not* run).

Consumption is linear in **panes, not sessions**: measured ~1.5–4 ptys per session-equivalent once
`--split-right` handoff panes, teammate panes, and notify-back panes are counted. 150 sessions under the
fleet's own visible-pane doctrine projects to 300–600+, and teaming bursts push past 511.

## 2. The gate is blind to it — and to the thing that already kills this box

`scripts/lib/capacity-admit.sh` is the live admission gate. It reads exactly two terms: `vm.loadavg` and
`head_gb` (reclaimable headroom). It has **no pty term and no compressor term**, and both of its terms
fail-open on an unreadable probe. `cap-gauges` found this by grep after deriving the gauge failures, and the
lead confirmed it.

That matters because of the second finding, which explains an anomaly the capacity work has been sitting on
for a day — **127/127 admission refusals came from the load term while the memory floor never fired once**,
reading ~29.79 GB headroom on a box with ~6.4 GB actually free:

> `head_gb` = free + speculative + inactive + purgeable. **`inactive` conflates evictable file-backed pages
> with anonymous pages reclaimable only by compressing or swapping — and `vm_stat` has no inactive-anon line,
> so the conflation is structural, not a tuning error.** At 150 near-idle sessions, nearly all their anonymous
> working sets age onto the inactive queue, so `head_gb` reads tens of GB "takeable without swapping" that is
> 100% compress-to-take. — `cap-gauges`

The gate's own inline comment asserts `head_gb` is "what a new session can take WITHOUT swapping". That is the
exact opposite of the mechanism. The memory floor is not merely unfired: **it is built on a quantity that
cannot bind**, and it over-reads worst precisely at the target scale, because many idle sessions is the
condition that maximises inactive-anon.

## 3. NEW — beyond the pty ceiling

| # | Finding | Why no gauge sees it |
|---|---|---|
| N1 | **Sum-of-RSS inverts under pressure.** As pressure rises, pages migrate into the compressor and *leave* RSS — so the fleet's footprint metric **improves as the box approaches death**. `ps` cannot show `phys_footprint`. | The metric moves in the wrong direction; a monitor watching it reads recovery during collapse. |
| N2 | **Darwin load average excludes vm_fault waits.** Threads parked in the compressor path are not runnable, so load reads *low* during the exact thrash that kills this box. Measured live: load 6.5 with **3 runnable** — the number is churn residue, not demand. | The gate's primary term is structurally blind to the box's confirmed failure mode. |
| N3 | **`vm.swapusage` total = 0.00M — no swapfile exists yet.** Reading 0 is compatible with being minutes from the cliff, and the first pressure event pays a one-time swapfile-creation stall nobody has budgeted. | An integral of the *last* stage, alarmed on level rather than rate. |
| N4 | **Blocked-on-flock sessions are invisible.** A session waiting on `land-lock.sh` or the accounts flock is *sleeping*; load counts only runnable threads. 100 queued sessions render as an idle box while throughput has collapsed to 1/(critical-section time). | Aggregate wait is Θ(N²·T) and no gauge aggregates lock-retry or queue depth. |
| N5 | **402 worktree registrations behind one `.git`.** Every ref write takes the shared `packed-refs.lock`; any `git gc --auto` from one worktree locks the object store for all. Failures present as per-session "cannot lock ref 'HEAD'" flakes, never attributed to the shared store. | No gauge aggregates lock-retry counts across sessions. |
| N6 | **Vnode table is already pinned at max** — `num_vnodes == maxvnodes == 263,168`, 160.6M lifetime recycles, i.e. steady-state allocation is 100% recycle. It never *fails*; it binds as namecache-miss latency during fleet-wide git churn. | Presents as "git got slow" + elevated sys%; only `kern.num_recycledvnodes` rate tells. |

`cap-gauges`'s burst walkthrough (several hundred small near-idle processes in 1–3 minutes) reached the same
place from the instrument side: the 1-minute load EWMA has not reached 63% of its target before a 30-second
spawn burst is over, so the gauge whose job is to catch bursts is slower than the bursts.

## 4. CONFIRMED — independently re-derived, without being told

`cap-kernel` and `cap-gauges` both re-derived, from mechanism alone, that this box's binding memory failure is
compressor thrash rather than space, that the visible symptom is exploding **sys%** which an operator misreads
as a CPU problem, and that the kill surfaces only as a diagnostic report while the session simply vanishes.
That is the crash root-cause doc's conclusion, reached by a different route by panelists who were never shown
it. Convergence raises confidence in the existing verdict; it is not a new finding.

## 5. REFUTED — derived, then killed by measurement

Every panelist ran its own refutations, which is the half of this method that pays for itself:

- **Per-uid process table** — 10,666 limit, ~446 occupancy; ~1,200 projected at N=150. Not binding.
- **Thread table** — 3,460 of 81,920 (per-task 16,384); ~12k projected. Not binding.
- **System file table** — 6,772 of 491,520; ~20k projected. Not binding. (Per-proc soft limit here is
  1,048,576, not the 256 default two panelists initially derived.)
- **Swap-file space** — 4.9 TB free on the VM volume. Never binds; the memory term is thrash, not space.
- **Ephemeral ports / mbufs** — ~600 of 16,383 projected. Not binding.

**This is the direct answer to "the load is 200 GB of worktrees".** The disk is not the ceiling and the inode
tables are not the ceiling; the worktree count binds through *shared-lock contention* (N5) and *vnode cache
working set* (N6), not through space.

## 6. Falsifiable predictions

Run by the lead, this session:

- ✅ `sysctl kern.tty.ptmx_max` = **511** while `maxproc`/`maxprocperuid`/`maxfiles` are all raised — the
  tuning-fingerprint prediction holds exactly.
- ✅ `capacity-admit.sh` contains no `ptmx`/`ttys`/compressor read — gate blindness confirmed by grep.
- ✅ 21 ptys at ~6 sessions, 739 procs — consumption ratio consistent with the 1.5–4/session model.

Outstanding, cheap, and worth running before any scale-up:

1. **Pty census tracks pane count 1:1.** Ramp to 50 sessions; predict 60–90 ptys. At 150 + teaming, ≥230.
2. **`head_gb` inflation on an idled fleet.** After ≥30 min idle, from one `vm_stat` compute
   A = free+speculative+purgeable and B = A+inactive (the gate's sum). **Predict B ≥ 2×A.** If B ≈ A the
   inactive-anon model is wrong and §2 is refuted.
3. **Sum-RSS inversion.** Once `vm.compressor_bytes_used` > 8 GB, `ps -axo rss=` summed reads *lower* than the
   same fleet at compressor=0. Monotonic rise refutes N1.
4. **Vnode churn.** Two reads of `kern.num_recycledvnodes` 60 s apart during a concurrent `git status` sweep:
   predict delta > 100k while `free_vnodes` dips below 50k and no conventional gauge moves.
5. **Lock queue.** p95 land latency at k concurrent shippers ≈ k × solo-land time, with zero CPU growth. A flat
   p95 at k≥5 refutes N4's choice of binding lock.

Prediction 2 is the load-bearing one: it decides whether the admission gate's memory term is repairable by
tuning or must be replaced.

## 7. Campaign candidates

Both emitted independently by two panelists, and they are the same idea at two altitudes:

- **C-CAP-1 — Occupancy-table admission.** Replace rate and level *proxies* with one probe that reads every
  finite table as a fraction of its limit (`ttys/511`, `procs/16000`, `procs-uid/10666`, `threads/81920`,
  `files/491520`, `compressor_bytes/limit`) and gates on the max fraction. The pty blind spot becomes a no-op —
  it is simply the fullest row. The loadavg-ceiling debate the gate's own header documents (§8.5.2 retraction,
  boot-storm 346) becomes a no-op, because saturation proxies stop being load-bearing. Compressor blindness
  becomes a no-op — it is a row, not a separate sentinel that gates nothing. **Tables lie far less than
  proxies: they *are* the resource.** Generator-class.
- **C-CAP-2 — A pty-less session substrate.** The visible-pane doctrine has a hard numeric ceiling of ≤999 on
  this box, ever. Sessions running detached with panes as *views attached on demand* dissolves the pty cliff,
  the terminal-emulator fd slope, orphaned-pane reaping, and the pane-anchor fragility class in the handoff
  machinery — because a session stops *being* a pane. This is the only finding that cannot be tuned away: at
  150 sessions with teams, the doctrine itself is the ceiling.

## 8. The panel's own delivery defect — and why this doc exists

**All three panelists completed their work and returned nothing to the lead.** They spent real Fable tokens,
produced the reports above, signalled `idle`, and the lead received no value.

Cause, from `~/.claude-tertiary/teams/session-03515ee3/config.json`: passing `name:` to the `Agent` tool
registers the agent as a **team member** — `backendType: "iterm2"`, an assigned `tmuxPaneId`, `isActive: false`
— not as an in-process subagent. A named teammate's deliverable channel is `SendMessage` back to the lead;
there is **no Agent-tool return value**. Nothing was ever going to come back. Compounding it, `backendType`
was `iterm2` on a box running **kitty**, so panes 8/9/10 were never created: the panelists were headless,
invisible to the operator, and unreachable by the pane tooling.

The work was recovered by reading the teammates' own session transcripts directly and persisting the final
assistant blocks verbatim to `docs/research/panels/h-cap-1/`. That recovery is manual and would not have
happened if nobody had gone looking — which is the actual risk: **completed frontier work, silently
discarded.** Filed as its own defect; the durable fix is a harvester that pulls a member's final block from
its transcript on idle rather than trusting a return channel that does not exist for this spawn shape.

Contamination note, recorded because two panelists volunteered it: ambient `CLAUDE.md`/`MEMORY.md` auto-load
into every agent and contain prior findings, so baseline-blindness is *approximate*, not enforced. Both
affected panelists flagged which of their derivations were independent of it and cited the rest only as
corroboration. The pty finding is independent of ambient context — nothing in the repo mentions `ptmx_max`.
