# `CC_HW_DEFAULT_MAX_LOAD_PER_CORE` — the derivation, and why the answer is "no number exists on this axis"

**Date:** 2026-08-25
**Item:** `e981656df348` — *"2.0 was never derived from a measured failure (capacity-admit.sh:134 cites a
section that falsifies itself) — derive it, do NOT blind-raise; blocked on the marginal-load measurement."*
**Commissioned by:** [`gc-cpu-vs-session-ceiling-2026-08-18.md`](gc-cpu-vs-session-ceiling-2026-08-18.md) §3,
which called this "the actionable finding, and it has nothing to do with the vendor."
**Method:** re-derivation from the measured record already on trunk — every population read first-hand
from the file that holds it, never from a citation. No new instrument was run (see §8).

---

## 1 · The verdict

**The constant is not derivable, and that is the derived result — not a punt.**

The measured record contains **no threshold on load-per-core that separates the box's deaths from the
loads it survived**, because the only death carrying a load reading (2026-08-05, load 25.3 on 10 cores
= **2.53/core**) sits **below 14 of the 15 survived readings** taken on the same box. A ceiling low
enough to have refused at the fatal reading refuses **93% of the survived record**; a ceiling high
enough to spare the survived record admits the fatal one. There is no value in between, so there is
nothing for a measurement to land on.

**And 2.0/core is not between them either — it is below both populations.** All 16 incident-window
readings in §2, fatal and survived alike, exceed 2.0. The constant therefore does not separate *fatal
from survived*; it separates *in use* from *idle*.

**Disposition: do not move it.** Not up (the 3.0/core → 20–22 sessions projection was refuted), not
down (2.53 would refuse 93% of the survived record). Its comment changes from a false provenance to a
true one, and the capacity decision stays where the repo has already put it — on the terms that appear
in the deaths' actual evidence chains (§4.3, §6).

**The item's stated blocker does not gate this.** It was blocked on the marginal Δload-per-session
measurement. That measurement is a **denominator**; what the constant lacks is a **numerator** — a
failure point on this axis — and §3 shows the record contains none. See §5.

---

## 2 · The measured record, read first-hand

Every row was read out of the file named in its last column on `origin/main` at `aa2d4252`.

### 2a · Deaths

| # | Date | Load at death | /core | Source |
|---|---|---|---|---|
| 1 | 2026-07-30 | **not recorded** | — | `docs/research/panic-compressor-2026-08-05.md`, `capacity-alarm.sh:413-427` |
| 2 | 2026-07-31 | **not recorded** | — | `docs/research/panic-iterm2-coalition-2026-07-31.md` |
| 3 | 2026-07-31 | **not recorded** | — | `docs/research/panic-threadprice-2026-07-31.md` |
| 4 | 2026-08-05 | **25.3** | **2.53** | `scripts/capacity-alarm.sh:141-142` |
| 5 | 2026-08-24 | **not recorded** | — | `docs/research/panic-2026-08-24-fifth-watchdog.md` |

**Five deaths of the same class; one load reading.** This is the first finding, and it is not an
archival accident. Panic #5's postmortem is 357 lines merging five independent evidence axes (jetsam
ledger, unified-log timeline, crash cluster, guard postmortem, kernel zone) and reconstructs the death
to the second — **without the string "load average" appearing anywhere in it.** The quantity this gate
thresholds is not in the evidence chain of the failure it exists to prevent.

*(The 07-31 doc does carry a "load 121" — during the **post-panic boot storm**, i.e. after the reboot.
It is not a reading at death and is not used here.)*

### 2b · Survived

| Load | /core | Box state | Source |
|---|---|---|---|
| 21.55 | **2.155** | 13 sessions, 24 GB free, **0 B compressor** — "a perfectly healthy box" | `MACHINE_CAPACITY_V2.md` §12.2 |
| 27 | **2.72** | the 2026-07-29 lag incident **the constant was picked from**; 8% idle, 54/64 GB, 0 swap | `0fc3a3d33` commit body |
| 29.15 | 2.915 | ⎫ | |
| 37.66 | 3.766 | ⎪ | |
| 44.35 | 4.435 | ⎪ | |
| 45.96 | 4.596 | ⎪ **13 consecutive samples over ~100 s at a CONSTANT 31–32 sessions.** | |
| 47.01 | 4.701 | ⎪ A 2.05× swing while session count changed by at most 1. | `MACHINE_CAPACITY_V2.md` §8.5.7 |
| 49.94 | 4.994 | ⎪ The box lived. | (verbatim list) |
| 50.43 | 5.043 | ⎪ | |
| 54.74 | 5.474 | ⎪ | |
| 55.56 | 5.556 | ⎪ | |
| 56.04 | 5.604 | ⎪ | |
| 56.24 | 5.624 | ⎪ | |
| 56.96 | 5.696 | ⎪ | |
| 59.80 | **5.980** | ⎭ | |

Corroborating, not counted in §3 (different instruments/windows): load **8.35–46.39** on this box in
one day (`B3-ambient-load.md`, 4 censuses); **1.55/core** admits after the fleet drained to 8 sessions
(§9.5); **40.9** measured hours after the origin incident (§8.5.2); reso reports 42 h at load 25
(2.5/core) with no panic (cross-repo, unverifiable from here).

---

## 3 · The separation test

Survived set **S** (n=15, §2b) against fatal set **F** = {2.53} (n=1).

| Candidate ceiling | Catches the death? | Refuses of the 15 survived | Verdict |
|---|---|---|---|
| **T ≤ 2.53** (any value that would have refused at the fatal reading) | yes | **14** (93.3%) | unusable |
| **T > 5.980** (any value that spares the whole survived record) | **no** | 0 | blind |
| **T = 2.0** (shipped) | yes | **15** (100%) | separates nothing |

- **P(a survived reading exceeds the fatal reading) = 14/15 = 93.3%.** A discriminator at chance scores
  50%. As a fatal-detector the axis scores **AUC ≈ 0.067** — on the measured record it ranks the death
  as *safer* than 93% of the survivals.
- **No separating threshold exists.** min(S ∪ F above 2.155) ordering puts the fatal value second-lowest
  of 16. This is a statement about the observed set and needs no distributional assumption.
- **2.0 is below both populations.** It refuses every incident-window reading in §2, the fatal one and
  all fifteen survivals. A threshold that fires on 16 of 16 events carries zero bits about which two
  outcomes they had.

The fleet has already priced this. Of gated fires, **242 gate-off vs 271 measured (~47%) run with the
gate switched off**; **25 of 49 historic refusals fall below 3.0/core, p50 exactly 3.00**
(`gc-cpu-vs-session-ceiling-2026-08-18.md` §2, both ✅ reproduced). And the repo's own instrument states
the conclusion verbatim at `scripts/capacity-alarm.sh:141-147`: *"load-per-core does not separate fatal
from survived, and no setting of these two numbers can make it."*

---

## 4 · Why it cannot separate — three mechanisms, each measured

### 4.1 The gate refuses the 4–13% it controls because of the 87% it does not

Load1 counts runnable threads **box-wide**. Two independent censuses attribute the numerator:

| Class | Share | Source |
|---|---|---|
| macOS / third-party | 33.6% | `B3-ambient-load.md` run4, 240 samples, per-thread R+U joined to full ppid/argv ancestry |
| **our own automation** (hooks · pollers · CLI) | **25.9%** | same — and `cc-backlog` alone is 17.5% of the whole box |
| **CLAUDE** (sessions + everything they spawn) | **12.7%** | same; `claude.exe` itself only **4.2%** |
| unattributable / devserver / terminal / browser / Cursor | 27.8% | same |

The gc-cpu wave measured the same thing with an independently written parser and replicated it:
`claude.exe` = **1.075 of 22.95 runnable threads (4.7%)**, finder 0.950/19.27 (4.9%). *Deleting 100% of
Claude's runnable threads removes ~5% of the load average.*

### 4.2 The variance exceeds the entire signal

At a **constant** 31–32 sessions the load swings **2.05×** (29.15 → 59.80, §8.5.7). At a constant
N=15–16 it reads **11.21 / 19.06 / 27.26 / 29.67 / 32.14 / 36.07**. Same box, same day: **8.35 → 46.39**.
The within-constant-N swing is larger than the whole session-attributable term, so a single-sample read
of load1 cannot tell "one more session" from "XProtect woke up".

### 4.3 The death is invisible to the instrument, by construction

The failure mode is **compressor segment exhaustion**, and a starving box's threads are *blocked*, not
*runnable*:

- Panic #5 (2026-08-24), the kernel's own verdict mid-peak: `System is unhealthy… {"compressor_exhausted": 1,
  swap_low: 0, zone: 0}` with **16.4 GB** available pages — segment exhaustion at 100% of 1,629,615
  slots reached at only **33%** of the pages limit (thrash fragmentation), never free-RAM shortage.
- `capacity-alarm.sh:147-149`: *"A thread blocked on a page-in is not on a run queue"*, and at death
  **90.3% of backtraces were truncated because userspace was paged out.** Load average sees the burst
  that precedes the wedge; the terminal starvation itself is invisible to this axis.
- `panic-threadprice-2026-07-31.md:11-12` reached the identical conclusion from the other direction
  four weeks earlier: *"it was enforced only by a `loadavg` guard, which cannot see thread creation.
  8,368 parked threads contribute ~nothing to loadavg (they are blocked, never runnable), so the one
  guard in place was blind"* — and drew the rule this item is an instance of: **"guards must bind the
  resource actually being consumed."**

---

## 5 · Why the blocking measurement could not have answered this

The item was parked on *"marginal Δload from adding exactly one active session"*
(`gc-cpu-vs-session-ceiling-2026-08-18.md` §5, "the one next measurement"). Call that coefficient **m**.

A gate needs a **ceiling T** and consumes **m** only to reason about how many sessions fit beneath it.
§3 shows the record supports no T. **m is a denominator; the missing quantity is the numerator** — so
no value of m unblocks the constant, and the measurement was gating an answer it cannot produce.

Worth stating because it is the second-order version of the same defect: **m is not identified either.**
The commissioning wave produced four values spanning **30×** — `0.172` (pooled OLS), `0.566` (in-band
bucket median), `1.89` (delta-marginal from the axis-09 pair), `2.5–5` (published, and refuted as an
aggregate÷N rather than a marginal). Running the experiment would sharpen m. It would not produce T.

**This is what unblocks item `e981656df348`** — not the measurement, but the finding that the
measurement is on the wrong term. The experiment remains worth running for the things that *do* divide
by m (`CC_ADMIT_ACTIVE_CEILING`, `MACHINE_CAPACITY_V2`'s model, every "+N sessions" figure); it is
filed separately and is no longer this item's blocker.

---

## 6 · Disposition

1. **Leave `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0`.** Nothing measured licenses a number here, in either
   direction — and "do not blind-raise" cuts both ways: a *lower* value derived from the single fatal
   reading would refuse 93% of the survived record.
2. **Restate what it is.** Not a failure ceiling: a **busy-box speed bump**, whose cost is bounded to
   one round-trip by `CC_FIRE_ADMIT_BUDGET=1` (after one consecutive refusal the next fire is admitted,
   `basis: budget-expired`). That bound is why an axis this weak is affordable at all, and it is the
   reason to leave it rather than rip it out unilaterally.
3. **The load-bearing decision has already moved**, and to terms that appear in §2a's evidence chains:
   `segments` (the quantity that actually killed the box, five times), `active` (concurrency), and
   `headroom`. All three ship in this same library. The **highest-volume spawn surface already runs with
   `CC_ADMIT_LOAD_TERM=off`** (`hooks/agent-teams-enforce.sh:229`), for the reason recorded at
   `capacity-admit.sh:614-621`.
4. **Filed, not driven here** — each changes admission behaviour at the universal spawn chokepoint,
   which is an escalation surface and the operator's call:
   - **Default the load term off in `capacity_gate()` too**, as `B3-ambient-load.md` §1 independently
     recommends from live data (at load 37.17 ⇒ REFUSE, the `active` term read 4 of a ceiling of 8 ⇒
     ADMIT; prize ≈10 of 19 refusals in 9 days become admits).
   - **`CC_ADMIT_ACTIVE_CEILING=8` inherits this constant *and* a refuted coefficient.** Its comment
     (`capacity-admit.sh:726-728`) derives 8 from "the load-20 gate" × "2.5–5 runnable threads per
     active session" — i.e. from the number this doc just showed is arbitrary, times the figure §5 lists
     as refuted. Re-derive it when m is measured; do not touch it before (it refuses real work).
   - **`CC_HW_DEFAULT_MIN_HEADROOM_GB=4` has the same shape of citation defect.** The comment credits
     "M10's reclaimable floor"; M10 (`MACHINE_CAPACITY_V2.md:1040`) names `CC_FIRE_MIN_HEADROOM_GB` and
     **states no value**. Not audited here — this item derived the load constant only — but the term is
     separately recorded as having *"fired 0 times in 127 refusals"* and being unable to bind
     (`capacity-admit.sh:234-236`), so it deserves the same treatment.

---

## 7 · What changed on disk

- `scripts/lib/capacity-admit.sh` — the provenance comment above the two literals. It read *"2.0/core is
  §9.5's measured ceiling"*; **§9.5 contains no derivation.** What §9.5 actually records is that the gate
  ADMITS at 1.55/core and REFUSES at 2.92/core — a demonstration that a threshold thresholds, which is
  what makes the citation self-falsifying. The number was **picked** at `0fc3a3d33`, whose own body
  measures the motivating incident at 2.72/core and states no rule; the 2026-08-07 extraction
  (`a27a4d9485da`, `MACHINE_CAPACITY_V2.md` §RESIDUE CLOSED) carried the literal forward verbatim. The
  comment now says what the number is, what it is not, and where the derivation lives.
  **Comment-only — no executable line changed** (§8).
- `docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md` §3 — a RESOLVED pointer here.
- This file.

---

## 8 · Limits — what this derivation does NOT establish

Stated explicitly, because a negative result is exactly where an unstated limit becomes an overclaim.

- **n_fatal = 1 on this axis.** The AUC in §3 describes the observed set; it is not an estimate of a
  population quantity and carries no confidence interval. Four of five deaths contribute nothing to it.
- **The 13 survived samples are autocorrelated** — ~100 s at constant session count, i.e. effectively
  **one** independent window, not thirteen. Deflated honestly, the survived-above-fatal evidence is
  **two independent windows** (§8.5.7's 2.92–5.98 band, and the 2.72/core lag incident). That is still
  enough: one survived window lying entirely above the only fatal reading forbids a separating
  threshold, which is all §3 claims.
- **This does not say high load is safe.** It says load-per-core does not *order* these events by
  outcome, so it cannot be thresholded — a different and weaker claim.
- **No new measurement was taken.** This is a re-derivation from populations already on trunk. The
  marginal-Δload experiment is still unrun and still worth running for §5's other consumers.
- **The code change was verified on Linux, where the Darwin instruments are absent.** 13 of 58 cases in
  the three `capacity-admit*` suites fail identically before and after the edit (`sysctl -n hw.ncpu`,
  `vm.loadavg` and `vm_stat` do not exist here, so the gate fails open and `basis` reads `fail-open`
  instead of `measured`). Baseline and post-change RED sets are identical, the diff touches comment
  lines only, and `bash -n` passes — sound for a comment-only change, and **not** a substitute for a
  Darwin run of the suites.

---

## 9 · Re-derive, don't quote

```sh
# the survived population (13 samples, verbatim)
awk '/^#+ *8\.5\.7/,/^#+ *8\.5\.3/' docs/plans/MACHINE_CAPACITY_V2.md

# the fatal reading + the repo's own statement that this axis cannot separate
sed -n '139,147p' scripts/capacity-alarm.sh

# the section the old comment cited — check for yourself that it derives nothing
awk '/^#+ *9\.5 /,/^#+ *9\.6/' docs/plans/MACHINE_CAPACITY_V2.md

# the fifth death, reconstructed across five axes without ever reading a load average
grep -c 'load average' docs/research/panic-2026-08-24-fifth-watchdog.md   # 0
```
