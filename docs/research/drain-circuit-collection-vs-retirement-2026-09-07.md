# The drain circuit closed on RETIREMENT, not on COLLECTION — and the pile cap cannot tell them apart (2026-09-07)

**Vantage:** a cloud VM, dispatched against `cc-backlog` item `c18e7ea9e6b1` (DRAIN_CIRCUIT). Every
number below is read from **`origin`'s refs and `origin/main`'s content** — sources that exist off the
operator's box. That is the point of the record: the desk's own instruments (`~/.claude/autonomy/`,
`land.log`, the IDL) are all live-store reads, and none of them was used here. Where this agrees with
the desk it is independent corroboration; where it adds something, it adds it from a source the desk
has never queried.

---

## 1. The answer first

The DRAIN CIRCUIT plan's four named-open items are all cured on trunk (§2). The lane that had been
dead is firing again — **this session is the proof, and it is fire #4 of the first cohort in 58.8
hours** (§3). But the thing that reopened it was not the repair. **The pile cap was cleared by
declaring 299 declarations terminal, of which exactly 8 were retired because they had landed.** The
other 291 were discarded. Nothing retires a *branch* — only a declaration — so **337 branches carrying
492 patch-id-novel commits are still sitting on `origin` right now**, untouched by the drain that
"drained" (§4).

That is §1.5's defect wearing a new costume. §1.5 said the telemetry counted *commits* where the
question was *closure*. Here the cap counts *pile size* where the question is *pile disposition*: a
pile that shrank because the work landed and a pile that shrank because the work was thrown away move
`pending_total` by exactly the same amount. **The instrument that would separate them did not exist,
and this session built it** (§5).

---

## 2. The plan's open list is stale — every item has a cure on trunk

`DRAIN_CIRCUIT_2026-09-01.md` § "Still open after tonight" names four. Each sha below was asserted
with `git merge-base --is-ancestor <sha> origin/main`:

| plan's open item | cure on trunk | asserted ancestor |
|---|---|---|
| **(a)** the sweep's own runtime — garbage-collected at ~1400 s | `7d72371c` the harvest leaves the sweep tick (new `scripts/cloud-return-lane.sh`, 5,400 s bound), plus `a7390066` the sweep leaves the `darwinbg` task role | ✅ ✅ |
| **(b)** ship-land's smoke budget, a false-refusal generator on the drain path | `966c092f` — the flat 120 s TOTAL becomes `suite-count × 180 s`, capped at 900 s | ✅ |
| **(c)** the dispatcher re-fire predicate, filed `96e532227df8` | built: `bin/cc-dispatch:2051-2127` — per-item `already-declared` skip **and** the `CLOUD_PENDING_MAX` pile cap | ✅ (in `origin/main`'s blob) |
| **(d)** the local lane's self-reference (§1.4) | taken by W8 and recorded in §3i; the closure-floor chokepoint `1eb128f88` was already live | ✅ (per §3i) |

Also cured and still written up as open: **§3h's "filed rather than built"** — `load` and `elapsed_s`
on the `cloud-return` IDL row — landed as `1f5385f9` (a re-land after `d1209750` reverted it on a
`cut-not-red` non-verdict). §3h's own text still reads *"neither of which the `cloud_return_rc` row
currently carries."* It does.

**So the plan's status log, not the pipeline, is the stale artifact.** This is not a bookkeeping
nit: this session was dispatched *by* that stale list, and its first hour went into re-deriving cures
that were already on trunk. That is the failure mode `cc-dispatch`'s own boot rail warns about, one
level up — a plan heading outliving the work it names.

---

## 3. The lane was shut for 58.8 hours, and it reopened 19 minutes after the retire pass landed

**Nothing in this pipeline deletes a branch.** `scripts/cloud-return.sh:529` — *"the branch is never
deleted (origin keeps…)"*; `scripts/cloud-retire-terminal.sh:55` — *"It NEVER deletes a branch, a
declaration or a byte."* Therefore `origin`'s `refs/heads/claude/fire-*` set is the **complete**
population of every cloud fire ever made, and an absent date means **no fire happened**, not that its
evidence was collected away. That property is what makes the following readable off-box at all.

425 such refs exist. Bucketed by the fire timestamp in the branch name:

```
09-01  16    09-03  23    09-05   0        ← the lane is SHUT
09-02  18    09-04  26    09-06   0        ← the lane is SHUT
                          09-07   4        ← reopened
```

The boundary is exact, and it is the largest gap in the whole 425-ref series:

```
last fire before the halt   claude/fire-20260904T193754Z-36841-1
first fire after the halt   claude/fire-20260907T062332Z-4497-1
                            ── 58 h 45 m 38 s ──
```

Against that, the cure's own landing time:

```
77184bc0  2026-09-07T06:04:19Z  docs(cloud-pipeline): §A9.5 — … the first retire pass settles
                                299 of 331; the collectable pile is 32
     ↓ 19 m 13 s
06:23:32Z  fire-…-4497    06:27:06Z  fire-…-17724
06:35:47Z  fire-…-45873   06:37:02Z  fire-…-97029   ← this session
```

`CLOUD_PENDING_MAX` defaults to **50** (`bin/cc-dispatch:438`) and above it the dispatcher *"refus[es]
ALL cloud fires"* (`:2096`). The retire pass took the pile from 331 to **32**. 32 < 50, the cap
opened, and four fires followed within 33 minutes of a 58.8-hour silence.

`CLOUD_BACKLOG_PIPELINE.md` §A9.5 predicted precisely this — *"The dispatcher's next pass reads the
pile at 32 < 50 and admits cloud fires again."* **That prediction is now observed, from a source
independent of the store it was made against.** It is the first confirmation the desk could not have
produced for itself, because the desk's version of this test is a `cc-dispatch summary` row and this
one is a set of refs on GitHub.

---

## 4. But the pile drained by discarding, and that is what the cap cannot see

The retire pass's own census, quoted in §A9.5:

```
cloud-retire-terminal: examined=331 gone=23 landed=8 superseded=142 conflict=126 young-held=0 kept=32 retired=299
```

Read as a disposition rather than as a total:

| stratum | count | share of the 299 retired | what it means for the work |
|---|---|---|---|
| `landed` | **8** | **2.7 %** | the work reached trunk |
| `superseded` | 142 | 47.5 % | a sibling attempt at the same item won; this attempt is dropped |
| `conflict` | 126 | 42.1 % | the branch rotted against a moving trunk and can no longer be replayed |
| `gone` | 23 | 7.7 % | the branch/session no longer exists |

**97.3 % of the drain was the pile being declared unrecoverable.** That is a legitimate and deliberate
adjudication — `cloud-retire-terminal.sh` exists precisely so a pile that can never return stops
gating the lane, and a rotted branch genuinely is dead work. The defect is not the retirement. **The
defect is that the number the cap reads moves identically either way.**

### The branches did not move, and that is measurable from here

A retirement settles a *declaration*. The branch and its commits stay on `origin`. Measured against
`origin/main` at `ccf59f67`, over all 425 refs, using `git cherry` (patch-id, so a commit that was
replayed onto trunk by the lander counts as landed even though its sha differs):

| | count |
|---|---|
| refs whose commits are **all** already upstream by patch-id | **88** (50 at zero-ahead, 38 more by patch-id) |
| refs carrying **genuinely new** content | **337** |
| genuinely-new commits across them | **492** |

Distribution of the 375 refs that are ahead of trunk by ancestry: 272 by one commit, 56 by two, 22 by
three, 12 by four, 9 by five, 3 by six, 1 by seven.

So: the pile the cap reads went 331 → 32. The pile of unlanded content on `origin` went essentially
nowhere. Both statements are true, and only one of them is instrumented.

**What this does NOT claim.** Whether those 492 commits are worth recovering is **not** this
document's question and not this plan's — `DRAIN_CIRCUIT` §3 says so explicitly, and task **#174**
owns adjudication. `superseded` and `conflict` are, on their face, correct verdicts for most of them:
§3b measured that the 313 branches of its day were only 72 distinct items, with 18 items accounting
for 242 branches, and that a greedy set-cover needed 52 branches to capture every novel path. The
point here is narrower and is about the *instrument*, not the *pile*: **no reader can currently tell
which of the two drains happened**, so "the lane drained" is not yet a claim anyone can check.

### The prediction this makes, stated so it can be falsified

The cap has 18 slots of headroom (32 of 50). Inflow over the three days before the halt was 23, 26
and (post-reopen) 4-in-33-minutes. Retirement is repeatable — the lane runs it every tick — so the
steady state is not a second deadlock but something the plan should name honestly: **fire ~25/day,
retire ~25/day, land ~1/day.** A circuit that no longer stalls and still discards what it produces.

**Falsifier.** If, over any 7-day window after 2026-09-07, `sum(census.landed) / sum(census.retired)`
across the `cloud-retire` IDL rows exceeds 25 %, this characterisation is wrong and should be
retracted. §5 is what makes that expression runnable; before it, the numerator existed only inside a
string.

---

## 5. What was built: the census stops being a string

`scripts/cloud-return-lane.sh` journalled the retire pass's census as one opaque `summary` field. The
comment above it was already right about why it kept it at all — *"the sweep used to send it to
/dev/null, which is how 255 retirements happened with no record of WHY"* — but a string is not a
record you can do arithmetic on, and every figure in §4 above had to be scraped out of prose by hand.

The `cloud-retire` IDL row now carries a typed `census` object beside the untouched `summary`, plus
`load1` to match the return row:

```jsonc
{"disposition":"cloud-retire","cloud_retire_rc":"0","elapsed_s":94,"load1":8.1,"bound_s":900,
 "summary":"cloud-retire-terminal: examined=331 …",
 "census":{"examined":331,"gone":23,"landed":8,"superseded":142,"conflict":126,
           "young-held":0,"kept":32,"retired":299,"failed":0,"dry_run":0}}
```

Three design choices, each RED-proved by a mutant:

1. **Added beside `summary`, never instead of it.** W2's stated principle in this same plan — the
   churn arm was added beside `value` rather than redefining a number other consumers read.

2. **Parsed as a CLASS (`key=<int>`), not as an enumeration of today's strata.** This repo's own
   `denylist-enumerates-spellings-not-the-class` lesson cost it the `cc-reaper` whitelist twice
   (`1ca324beb`, then `9f9a64bb4`) — in the very file that records the lesson. A stratum added to
   `cloud-retire-terminal.sh` appears here with no edit. The enumeration mutant also drops
   `young-held`, because a hyphen is exactly the kind of spelling an enumeration misses.

3. **Absent is `null`, never a zeroed census** — and here that is the load-bearing direction. A
   retire pass **cut by its bound** prints nothing; a census of zeros would read as *"ran, settled
   nothing"*, which is a verdict, when the truth is a machine event. That is the same
   non-verdict-read-as-verdict this lane was built to stop, and the same shape as the `cut-not-red`
   revert that stranded §3h's fix for three days.

### Proof

`tests/cloud-return-lane.bats` 7 → **11 tests, 11/11 green.** Four mutants, each anchored on the exact
line it corrupts, each RED on the assertion it should be RED on and green elsewhere:

| mutant | expected RED | observed |
|---|---|---|
| M1 the `census` field is never emitted (the pre-fix state) | 7, 9 | ✅ 7, 9 |
| M2 an absent census becomes `{}` instead of `null` | 8, 10 | ✅ 8, 10 |
| M3 the parser enumerates the known strata | 9 (and 7, via `young-held`) | ✅ 7, 9 |
| M4 `load1` dropped from the retire row | 7 | ✅ 7 |

Sibling and repo-wide suites run: `cloud-return-lane` **11/11** · `cloud-return` **63/63** ·
`cc-cloud` **44/44** · `bats-kill-guard-lint` **35/35** · `bats-shim-parity-lint` **28/28** ·
`bats-shellcheck-lint` 28/28 (every case `skip` — shellcheck is not installed on this VM, so **this
diff is NOT shellcheck-verified**; the desk's land gate is where that happens).

**Not mine — attributed before it was driven, not after.** Two suites are red on this VM and both are
red identically on a **detached worktree at `origin/main` carrying none of this change**, which is how
each was attributed rather than assumed:

| suite | red here | red on clean `origin/main` | why |
|---|---|---|---|
| `bats-assert-liveness` | 3, 4, 5, 14, 21, 36 (6 of 37) | **same 6** | its own CONTROL #3 is *"the two bashes this grid is defined over are the versions it names"* — it needs bash 3.2 beside bash 5; this Linux VM has only bash 5 |
| `autonomy-sweep` | 61, 62, 67 (3 of 67) | **same 3** | #67 asserts `load1` on the `cloud-return` row, and `load1()` reads `sysctl vm.loadavg` — Darwin-only |

Neither is a trunk red and neither is this diff's. Note the shape of #67 in particular: it is §3h's
own test, failing here for exactly the reason the new test in §5 was written *not* to fail — an
assertion on a platform-specific **value** rather than on the **invariant**. The same care was taken
with the new `load1` assertion on the retire row, which checks that the field exists and matches the
return row's nullity rather than that it is a number.

---

## 6. Dispatcher vintage

The brief that fired this session was composed from `bin/cc-dispatch` blob
`646b8a652e71dd5e5e506dffe23725437accea6b`. `origin/main:bin/cc-dispatch` is
`98ab38f51f7ac82a043e522d3a9601ff9f460528`. **DIFFERENT** — the dispatcher that fired this session is
behind trunk. Recorded as a convergence fact about the deploy layer, not as a defect in anything read
here: it means "the fix is on trunk" does not by itself answer "the fix was running when I was
fired". Every cure asserted in §2 was asserted against `origin/main`, so §2 is unaffected; §3's
observation is of the *live* dispatcher's behaviour and is likewise unaffected, since it is read from
the refs that dispatcher actually created.

---

## 7. What a next session should do with this

1. **Correct `DRAIN_CIRCUIT_2026-09-01.md`'s status log** — this session appends the entry; the four
   (a)-(d) items and §3h's "filed rather than built" are cured, with the shas in §2.
2. **Run the §4 falsifier once a week of post-fix `cloud-retire` rows exists.** The expression is now
   one line: `jq -s '[.[]|select(.disposition=="cloud-retire" and .census)|.census] | {landed: (map(.landed)|add), retired: (map(.retired)|add)}' ~/.claude/autonomy/idl.jsonl`.
3. **Do not read a falling `pending_total` as a draining lane** until that ratio is known. It is the
   §1.5 mistake, and it has now been made twice in this plan with two different numerators.
