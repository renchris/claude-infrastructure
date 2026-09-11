# DRAIN CIRCUIT — W9's prediction re-adjudicated four days on (2026-09-11)

**Subject:** the falsifiable prediction closing `docs/plans/DRAIN_CIRCUIT_2026-09-01.md` §4's W9
entry (2026-09-07), which stated a three-arm steady state — **fire ~25/day, retire ~25/day, land
~1/day** — and a circuit that *"no longer stalls and still discards what it produces."*

**Venue:** cloud VM, off-box. Every figure below is derived first-hand from `origin`'s refs and
`origin/main`'s commit log — the same source W9 used for its own §(2), and the only source this box
can read. The operator's IDL store, `cc-backlog` and the live `~/.claude` layer are NOT readable
from here; §5 states exactly what that costs.

**Verdict in one line:** the **land arm is CONFIRMED** (predicted ~1/day, measured 1.25/day); the
**fire arm is REFUTED** by a factor of ten (predicted ~25/day, measured 2.50/day); the **retire arm
is unreadable from this venue**. And the framing both arms sit inside — "the circuit no longer
stalls" — is refuted in a way neither arm anticipated: the stall did not end, it became
**lane-specific**. On 2026-09-08 the cloud lane fired **zero** times while trunk took **130**
commits.

---

## 1. The positive control the whole census rests on, and it holds

W9's fire counts are ref-derived, which is sound only while nothing deletes a branch — the premise
it cites (`cloud-return.sh:529`, `cloud-retire-terminal.sh:55`). That premise is cheap to falsify
and was re-checked before anything else was believed:

| | W9 (2026-09-07) | now (2026-09-11) |
|---|---|---|
| refs dated ≤ 2026-09-07 | 425 | **426** |
| of which dated 09-07 | 4 | **5** |

Exactly `+1`, and it lands on 09-07 itself — one more fire after W9 took its reading, nothing
removed. **The ref population is still complete, so an absent date is a real absence and not a
collection artifact.**

Second control, and the one this plan has its own scar from — §1.1 records the first draft's
`grep -rl cloud-reconcile` null that was real *for that name* and wrong about the world. If the lane
had merely been renamed, "the fire rate collapsed" would be an instrument artifact. It has not:

```
$ git ls-remote --heads origin 'refs/heads/claude/**' | grep -vE 'claude/fire-[0-9]{8}T[0-9]{6}Z'
(no output, exit 1)
$ git ls-remote --heads origin | sed -E 's#.*refs/heads/##' | grep -v '^claude/fire-'
ab-local-1
ab-local-2
cc-bootping-probe-tmp
main
```

Every `claude/*` ref on the remote is a well-formed fire ref, and no other prefix carries fires.
The census is keyed on the name the lane still uses.

---

## 2. The fire arm — REFUTED, 10x

Fires per UTC day, from ref names, beside trunk's own commit count for the same day:

| UTC day | cloud fires | trunk commits |
|---|---|---|
| 2026-09-05 | 0 | 34 |
| 2026-09-06 | 0 | 42 |
| 2026-09-07 | 5 | 72 |
| **2026-09-08** | **0** | **130** |
| 2026-09-09 | 1 | 152 |
| 2026-09-10 | 4 | 133 |
| 2026-09-11 *(partial, to 08:02Z)* | 7 | 27 |

Over the four complete days since W9 took its reading, **09-07 through 09-10: 10 fires / 4 days =
2.50 fires/day**, against a predicted ~25/day. The series also carries two further gaps, both
multi-day in scale:

```
2026-09-07T17:36:18Z -> 2026-09-09T00:44:25Z  = 31.14 h
2026-09-09T00:44:25Z -> 2026-09-10T12:31:01Z  = 35.78 h
```

W9 measured the deadlock it had just broken at 58 h 45 m. These are shorter — and they are the same
shape. **"No longer stalls" is false as stated; what changed is the duration, not the kind.**

### 2.1 Why the refutation does not convict the cure W9 shipped

W9's reasoning was *"headroom is 18 slots (32 of 50) against ~25 fires/day"* — i.e. it derived the
fire rate from the observed 09-03/09-04 burst (23, 26) and then argued the **cap** would no longer
bind. The cap indeed does not bind: at 2.5 fires/day nothing is near 50. So the retire pass that
reopened the lane on 09-07 did its job, and is not what holds the rate down.

What the prediction actually did was **carry a rate forward as if it were a property of the
pipeline**, when it was a property of two days. That is this repo's own
*requested rate ≠ delivered rate* lesson pointed at an observation rather than at a cron line: a
cadence read off a burst is a measurement with a timestamp, not a standing quantity.

**This artifact does not determine WHY the rate is 2.5/day, and must not be read as claiming to.**
Two accounts are consistent with every number here and are not separable from refs alone:
(a) the backlog genuinely drained, so there is less to dispatch — a *good* outcome; (b) the
dispatcher is only reached when an operator is present. The burst structure leans toward (b) — the
four most recent fires arrived in **13.7 minutes** (`074910Z` → `080251Z`), and one of them
(`080251Z`) landed 80 seconds after this session's own boot ping, i.e. the dispatcher is alive
*right now* — but burstiness is evidence, not proof, and §5 names the read that would settle it.

---

## 3. The land arm — CONFIRMED, and it came with a latency nobody had measured

### 3.1 The instrument, and why the obvious one is wrong

Ancestry is the wrong test here. The desk lander **replays** a branch's commits onto trunk, so a
landed branch's tip is not an ancestor of `origin/main` and `git cherry` reports `+` on a patch-id
the rebase changed — the repo's own *cherry `+` ≠ absence* and *cited sha may not survive the land*
lessons. Measured: 14 of 16 post-W9 branches read "not an ancestor", **including W9's own branch**,
whose content I read from `origin/main` in order to write this file.

The instrument that works is the commit **subject**, which a replay preserves, cross-checked against
per-path content. W9's own branch is the positive control: it reads `PARTIAL` by content (trunk has
moved past it since) and **landed** by subject — which is the discriminator separating "never
landed" from "landed, then trunk moved on", the one distinction a content diff alone cannot make.

### 3.2 The result

| branch (post-W9) | fired | landed |
|---|---|---|
| `fire-20260907T062706Z-17724-1` | 09-07 06:27Z | ✅ |
| `fire-20260907T063547Z-45873-1` | 09-07 06:35Z | ✅ |
| `fire-20260907T063702Z-97029-1` *(W9 itself)* | 09-07 06:37Z | ✅ |
| `fire-20260909T004425Z-75839-1` | 09-09 00:44Z | ✅ |
| `fire-20260910T123101Z-19701-1` | 09-10 12:31Z | ✅ |
| `fire-20260907T062332Z-4497-1` | 09-07 06:23Z | ✗ |
| `fire-20260907T173618Z-28233-1` | 09-07 17:36Z | ✗ |
| `fire-20260910T185102Z-27906-1` | 09-10 18:51Z | ✗ |
| `fire-20260910T213003Z-71267-1` | 09-10 21:30Z | ✗ (4 commits) |
| `fire-20260910T200055Z-43095-1` | 09-10 20:00Z | — boot-ping only, no commits |

**5 lands over the four complete days = 1.25 lands/day** against a predicted ~1/day. The arm is
confirmed, closely.

*(Today's five fires are excluded from the rate: fired within hours of this reading, they have had
no landing opportunity, and scoring them as stranded would be an artifact of when I looked.)*

### 3.3 The new finding: landing latency is 17–96 h, and it is batched

| branch | fired | landed on trunk | latency |
|---|---|---|---|
| `…0910T123101Z` | 09-10 12:31Z | 09-11 00:32 −05:00 | **17.0 h** |
| `…0909T004425Z` | 09-09 00:44Z | 09-11 01:24 −05:00 | **53.7 h** |
| `…0907T063702Z` *(W9)* | 09-07 06:37Z | 09-10 10:38 −05:00 | **81.0 h** |
| `…0907T063547Z` | 09-07 06:35Z | 09-11 01:24 −05:00 | **95.8 h** |
| `…0907T062706Z` | 09-07 06:27Z | 09-11 01:24 −05:00 | **96.0 h** |

Three of the five carry the **identical committer second** (`2026-09-11T01:24:35−05:00`) — one
replay operation, not three independent lands. So the return arm closes the circuit in batches
separated by days, and **W9's own report sat on a branch for 81 hours** before the trunk this
session reads it from ever had it.

This matters beyond bookkeeping: a plan whose tracker updates on a 17–96 h lag is a plan every
dispatched worker reads **stale**, which is the exact cost W9 itself paid and recorded — *"This
session was dispatched by the stale list and spent its first hour re-deriving landed cures."*

### 3.4 Conversion, and the denominator it must not be confused with

5 of the 10 eligible post-W9 fires landed = **50 %**. W9 measured **8 of 299 = 2.7 %** and set a
25 % floor.

**These are different populations and the numbers may not be compared.** W9's ratio is
`census.landed / census.retired` over a historical pile that was mostly old stranded declarations;
mine is `landed / fired` over the current working set. Same shape, different denominator — the trap
this plan already names in §1.5 (counting commits where the question was closure) and in §W9(3)
(counting pile *size* where the question was pile *disposition*). **The 50 % figure is not evidence
about W9's falsifier**, which remains unrun; it is a separate statement that the *current* circuit
converts about half of what it fires.

---

## 4. The framing is refuted in a way neither arm covered: the stall is LANE-SPECIFIC

The single most informative row in §2's table is **2026-09-08: 0 cloud fires, 130 trunk commits**.

Trunk's three highest-throughput days in this plan's entire observation window are 09-08 (130),
09-09 (152) and 09-10 (133) — well above the 09-03/09-04 era (56, 74) that the "~25/day" figure was
read off. Those commits arrive spread through the day at roughly 15–30 minute spacing, not in one
block.

So the sentence a reader would naturally carry away from W9 — *the circuit no longer stalls* —
inverts depending on which lane it is about:

- **local lane: at record throughput**, and not stalling.
- **cloud lane: at ~10 % of its predicted rate**, with a zero day and two multi-day gaps.

An aggregate over both lanes reads healthy and hides this completely, which is §1.5's defect
recurring for the third time in this plan under a third costume: §1.5 counted commits where the
question was closure; §W9(3) counted pile size where the question was disposition; **here, trunk
volume reads as pipeline health where the question is per-lane liveness.**

⚠️ **What this section does NOT establish.** 138 trunk commits/day is *also* the shape §1.4 warned
about — the local lane committing at ~10× the rate it closes rows. Whether 09-08/09/10 are
throughput or churn turns on the commits-per-closure ratio, which is exactly what W8's EFFORT arm
was built to render (`scope=repo`, ceiling 10) and which **requires the backlog store this venue
cannot read**. A high commit count is not by itself good news, and nothing here should be read as
saying it is.

---

## 5. What could not be measured from here, and the criterion that replaces the number

**W9's stated falsifier is not runnable from this venue.** It reads
`sum(census.landed)/sum(census.retired) > 25 %` over a 7-day window, and those fields live in the
`cloud-retire` IDL rows on the operator box. W9's item (4) — the typed `census` object that makes
the expression runnable at all — **is on trunk and verified by content** here
(`scripts/cloud-return-lane.sh:205-217`: `census="null"` default, `jq -Rc` parse, the
`''|'{}' → null` guard, and `census:$cen` in the `log_idl` record). So the instrument exists; only
the store is out of reach.

**The gap this re-adjudication exposes: the prediction had three arms and only one of them was made
falsifiable.** The fire arm — the one that turned out to be wrong, by 10x — had no stated falsifier,
no threshold and no instrument. It was refuted here only because ref names happen to carry
timestamps. Per this repo's own rule about stale justifications, the durable form is the criterion
plus the command, not the number:

```sh
# Cloud fire rate, per UTC day, over complete days only. Ref-derived; needs no store.
git ls-remote --heads origin 'refs/heads/claude/**' \
  | sed -E 's#.*refs/heads/claude/fire-([0-9]{8})T.*#\1#' | sort | uniq -c
```

```sh
# The retire-conversion falsifier, ON-BOX only (needs the IDL store):
#   retract W9's characterisation if, over any 7-day window after 2026-09-07,
#   sum(census.landed) / sum(census.retired) > 0.25
```

**Re-measure both before acting on either.** The fire figure in §2 is a reading taken on
2026-09-11 and will rot exactly like the "~25/day" it refutes.

---

## 6. Dispatcher vintage

The brief that fired this session was composed by `bin/cc-dispatch` blob
`9109de61dc7add48cd94809d54e591af0bfe9021`, against `origin/main`'s
`e61bcbfc657a44a20b03d7d52ab3e921fd138242` — **DIFFERENT**, so the dispatcher that fired this
session is behind trunk. Consistent with §3.3's 17–96 h return latency and with W9's own identical
observation four days ago. This is a convergence fact about the deploy layer, not a defect in
anything read here; every claim above is asserted against `origin/main` or against refs the live
dispatcher itself created.

**Cure sha asserted:** W9 landed as `140c2889b5ff09597b8b151b0d5f0f1dc908f109`
(`git merge-base --is-ancestor 140c2889b5ff09597b8b151b0d5f0f1dc908f109 origin/main` → exit 0),
committed to trunk `2026-09-10T10:38:41−05:00`.

---

## 7. What is NOT claimed

No code defect is alleged and none was fixed; the brief's scope was to advance this item, and the
measurement is the deliverable. W9's shipped work is intact and verified on trunk — the retire pass,
the typed census, and the four cures its item (1) asserted. What is refuted is one **prediction**,
refuted in place in the plan rather than deleted, because the prediction is the record of what was
believed. The cause of the 2.5/day fire rate is explicitly left open (§2.1), and the
throughput-vs-churn reading of trunk's 138/day is explicitly left open (§4) — both need reads only
the operator box can perform.
