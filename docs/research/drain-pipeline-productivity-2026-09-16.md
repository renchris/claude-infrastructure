# Drain pipeline audit — productivity and outcomes of the two 24/7 lanes (2026-09-16)

Operator ask: *"Investigate our productivity and outcomes of our 24/7 cloud pipeline cc-backlog
drain to zero and our 24/7 local pipeline cc-backlog drain to zero."*

Method: lead measurement plus an 8-axis read-only research wave (cloud outcomes, local outcomes,
closure quality, inflow, uptime, the blocked pile, convergence arithmetic, cost). Every number below
carries the command that produced it in the per-axis notes under
`/private/tmp/…/scratchpad/drainprobe/A[1-8]-*.md`; the load-bearing ones are repeated inline.
Store snapshot: `~/.claude/autonomy/backlog.jsonl`, 20,528 events, 3,525 ids, **0 parse failures**,
**0 `compact` events** (so the done-series is complete, not truncated). All five config dirs symlink
one store — one shard, no missing denominator.

---

## Verdict

**Both lanes are stopped, and they stopped after doing real but self-directed work.** The local lane
closed its last row **2026-09-09T22:00Z** and the cloud lane **2026-09-12T04:10Z**; the repo's own
detector agrees — `scripts/drain-chain-assert.sh` returns *"the 24/7 backlog drain chain is DEAD —
343 live row(s) and nothing is working them"*.

Three facts decide the question, and they are independent:

1. **"24/7" describes the schedulers, never the work.** The local drain lane **has no scheduler at
   all** — no plist, no cron, no caller in `autonomy-sweep.sh`; it runs only when a session fires it
   by hand. Its firing histogram is diurnal (15.0% of fires in 01:00–07:59 against ~29% for uniform)
   and 10 of its 15 stalls >6 h begin between 00:00 and 05:00 and end mid-morning. The lane is
   operator-paced, not self-perpetuating.
2. **Drain-to-zero was never reachable, and the one week it looked reachable was a stock being
   harvested, not a rate.** Whole-store live count has never been zero since 2026-07-26 (floor 109).
   Exactly one sustained regime had ρ<1 — Sep 4–10, ρ=0.59, −42.7 rows/day, on track for zero on
   2026-09-24 — and **54% of that week's closes were retractions** (`moot` / `superseded` /
   `already-true`). Post-collapse (Sep 11–15) ρ=1.64, +7.8 rows/day, **time-to-zero infinite**.
3. **The pile did not drain so much as change state.** `open` genuinely collapsed 358 → 34 between
   Sep 3 and Sep 10 (735 rows closed in that window — real work). But `blocked` **rose on every one
   of the last 30 days**, 149 → **296, its all-time high**, entering 3.6× faster than it leaves
   (6.77/d in, 1.87/d out). `cc-dispatch` selects `status=="open"` only (`bin/cc-dispatch:1921`), so
   **296 of 343 live rows (86%) are structurally invisible to both lanes.** The drainable queue is
   **47 rows**, not 342.

**Productivity, stated plainly.** When running, the local lane was the most cost-effective worker on
the box: **$3.35 per closure** against the ordinary session lane's **$21.75** and cloud's **~$112**.
That 6.5× advantage is *entirely throughput* — median cost per session is statistically identical
($14.89 vs $15.86) and per message identical ($0.125 vs $0.162); a drain session closes **5.5 rows**
where a session-lane session closes **1.5**. **Rows-per-session is the only lever that has ever
mattered** — not venue, not model, not quota.

**Outcomes, stated plainly.** ~**43%** of closure volume (band 35–52%) is work a reasonable operator
would call delivered; **47.2%** is mechanically not-delivered; **19.4%** is unclassifiable and is
reported separately, never folded in. And **74% of September's 882 closures were
`claude-infrastructure`** — the machine working on itself — while five customer deliverables on the
mission board sat 8–19 days untouched.

**The cloud lane's output is far larger than its closure count and its closure count is partly
false.** It shipped **212 commits / +43,049 lines to trunk from 146 sessions** — a 19.9% yield on 708
declarations — while the backlog credits it with 29 rows, of which **21 of 29 cite evidence about a
branch their session never touched** (§2). Its failure mode is not incapability but **latency**: 52%
of its non-delivering sessions died because trunk moved past them, and the repo's own replay shows
**90% of stranded branches would have landed had they been landed an hour after their push.** That
makes landing latency, not model quality or venue capacity, the single highest-leverage cloud fix.

---

## 1 · Lane-by-lane throughput

`jq 'select(.event=="done") | .lane'` over the store, bucketed by ISO week:

| week | local-drain | cloud | session | land | sweep | (none) | total |
|---|---|---|---|---|---|---|---|
| 08-17 | 9 | 0 | 21 | 9 | 0 | 486 | 525 |
| 08-24 | 48 | 0 | 46 | 33 | 8 | 37 | 172 |
| 08-31 | 142 | 21 | 81 | 25 | 6 | 15 | 290 |
| 09-07 | **198** | 8 | 264 | 15 | 0 | 86 | **571** |
| 09-14 | **0** | **0** | 21 | 1 | 0 | 5 | **27** |

- **Local drain**: 397 attributed closures lifetime (a *lower bound* — the `lane` field only appears
  from 2026-08-23, and 2,306 dones carry no `closedBy` at all), peak **227/week**, last closure
  2026-09-09. 309 recycle links landed a journal entry, `#2 … #333`, with **21 numbers missing**.
  The chain ended when `#332` committed `docs(drain): recycle #332 — closed 4 rows` and **never
  landed** (still 3 commits ahead on `drain/lane-infra`); `#333` fired 17.5 h later and produced no
  entry, no commit, no closure.
- **Cloud**: the `lane` field **understates this lane by ~3.5×** and must not be used alone —
  **101 `done` events name a cloud session in their `evidence`** where only 29 carry `lane:"cloud"`
  (63 carry no lane at all). Measured from the declaration store instead
  (`~/.claude/autonomy/cloud/`: **708 `.decl`, 705 retired, 3 live**, 2026-08-08 → 2026-09-12, no
  `archive/` so the census is complete): **146 distinct cloud sessions delivered 212 commits / 360
  files / +43,049 −1,886 lines to `origin/main`** — a **19.9% yield** on declarations, verified by two
  disjoint sole-writer trailer instruments (`Cloud-session:` 151 commits/108 sessions from
  `cloud-reconcile.sh:498`; `Claude-Session:` URL 61 commits/38 sessions from `bin/cc-cloud:708-718`;
  **zero commit and zero session overlap**). True delivery is **≥150 sessions** — 9 sessions verdicted
  `landed` carry no trailer, and a cloud commit cherry-picked by a local session is invisible to both
  instruments. Terminal verdicts: `bare 360 (51.1%) · superseded 157 · conflict 144 · gone 24 ·
  landed 20 · live 3`. Work kind: docs 238 file-touches · tests 152 · scripts 72 · bin 46 · hooks 31;
  **34% of the distinct `docs/` files it wrote are about the lane's own machinery** (filename-keyed
  lower bound; the redesign doc measures 68% on content).

  **What kills a cloud session is latency, not capability.** Of the 567 non-delivering sessions,
  **296 (52%) died `superseded` (155) or `conflict` (141) — trunk simply moved past them**; 236 (42%)
  were never adjudicated at all. The repo's own replay already settled the counterfactual: **90% of
  stranded branches would have landed had they been landed an hour after their push**
  (`docs/research/cloud-lane-redesign-2026-09-10.md:94`).

## 2 · What the closures were worth

Rules classifier over `evidence` text, precision hand-checked on a fresh random 25 (exact category
68%; **binary delivered/not-delivered 15/17 = 88%** on the rows it commits to, errors one in each
direction):

```
DELIVERED     1139  33.4%   REAL_FIX 748 + SHA_ONLY 310 + DOC_ONLY 81
NOT-DELIVERED 1612  47.2%   BULK_RETRACT 387 + ALREADY_CURED 320 + RETRACTED_AT_FILING 282
                            + DISPROOF 258 + DUP_SUPERSEDED 171 + STALE_GONE 98 + NOOP_EMPTY 96
AMBIGUOUS      662  19.4%   FIX_WEAK_EVIDENCE 524 + UNCLASSIFIED 138
```

The prior rule-of-thumb ("40–55% of closures were no-ops") **reproduces and is slightly
conservative**. But the aggregate hides three separate pathologies, only one of which is a drain
defect:

- **One string closed 387 rows** (11.3%) — `C2-unscoped flood retracted; scoped default landed
  5f3ff0c`. A producer bug minted a flood; one line retracted all of it. Those rows were never work.
- **`lane=land` is 100% no-op** (83/83) — every one is `auto-retracted at filing: land-content-verify
  reports content already on trunk`.
- **Weak evidence ≠ no value** — of 310 bare-sha closures, **28 of 30 sampled are ancestors of
  `origin/main`**. Lazy prose, real work. Separately, 20 random REAL_FIX rows verified by content:
  17 ancestors by sha, 3 rebased-but-content-present ⇒ **true-landed rate 20/20**.

Evidence discipline is **improving**: weak-evidence share fell from 38.3% (w/c 08-03) to **14.7%**
(w/c 09-07) while REAL_FIX share held 22–27%.

🚨 **One class of closure is not merely weak but FALSE, and it is still standing.** Of the 29
`lane:"cloud"` done rows, **15 cite the identical path set**
(`scripts/branch-prune-landed.sh,tests/branch-prune-landed.bats`) across 15 different sessions and 13
different backlog ids. Testing each cited session's declared `paths=` against the actual file set of
its own branch commits: **21 NOT-SUBSET, 7 SUBSET — and the split is perfectly dated**, every session
declared ≤2026-08-24 failing (21/21) and every session ≥2026-08-25 passing (7/7). All 95 filled path
sets read `paths_src=caller-derived-pre-land`, whose `PENDING_PATHS` is a **shell global**
(`scripts/cloud-reconcile.sh:740-763`); the sharp boundary is the `fill-paths --print`/`--set` split
landing on 08-25, which is the cure. Strong hypothesis, not proven: a stale global wrote one session's
path set onto its neighbours. **Consequence: 13 backlog rows are closed today on evidence naming a
deliverable their session never produced** — and the repo's own rules file already records one of
them (`e981656df348`) as closed on evidence about a different deliverable, after ~20 reopen cycles.

**A premise in the brief was wrong and the correction matters.** The 2,121 `reopen` events are *not*
closure churn: **2,078 (98%) immediately follow a `claim`** — a worker took the row and released it
(`spawn-fail` 436, `worktree-fail` 197). That is a **dispatch** pathology. Genuine closure churn is
tiny: **21 ids (0.6%) were ever closed-then-reopened**, and of today's 47 open rows exactly **one**
was ever closed before.

## 3 · The machine is its own biggest customer

Classifying every row ever filed by its title generator:

| generator | rows | share | open today |
|---|---|---|---|
| substantive work | 2,269 | 64.4% | 14 |
| `re-land <branch>` (ship-land could not complete) | **590** | **16.7%** | 19 |
| `advance <plan>` | 471 | 13.4% | 2 |
| `post-land RED` / AUTO-REVERT / post-deploy | 194 | 5.5% | 12 |

**35.6% of every row the backlog has ever held was minted by our own land/plan machinery about
itself**, and **31 of the 47 rows open today (66%)** are that class. On 30-day inflow the same shape:
the **ship-land re-land generator is the single largest producer at 28.7%** (377 of 1,313 adds),
`cc-backlog needs` is 23.9%, `postland-verify` 4.5%. Pure-script rows (no model in the loop) are
35.0%; the other 65.0% were written by a model, and **84% of those point at no plan at all**
(no `dodRef`).

The drain lanes themselves are *not* the worst offenders — September closures are 76% substantive for
`local-drain` and 72% for `cloud`; the exhaust is concentrated in `land` (100%) and unattributed rows.
But the **project** mix is the outcome that matters: **652 of September's 882 closures (73.9%) were
`claude-infrastructure`**, 164 (18.6%) `reso-management-app`.

**Trunk corroborates.** Over the chain's life (2026-08-17 → 09-09) trunk took 1,553 commits, of which
**380 (24.5%) are `docs(drain)` journal entries** — a quarter of everything landed was the lane
writing about itself. ⚠️ One sub-finding of the wave needs correcting: it reported that "the repo's
landing rate did not depend on the chain." It did. Trunk ran **~65 commits/day** during the chain's
life and **~36/day** in the 7 days after its death — roughly halved; net of the chain's own journaling
the drop is ~27%, not zero. The chain's marginal contribution was real, just far smaller than its
gross output suggests.

## 4 · Why it stopped — and why nothing said so

Four mechanisms, each independently sufficient:

1. **It ran out of things it is allowed to see.** Dispatch volume collapsed from **925 fires/day**
   (Sep 4) to **13–56/day** (Sep 12–16) — not because the dispatcher broke, but because it drained
   `open` to 34 rows and `cc-dispatch` cannot select a blocked row. The dispatcher is alive and
   passing its capacity gate every 300 s; it has nothing eligible to pick.
2. **The blocked pile has a cheap entrance and no exit.** `block --needs` validates only that the
   string is **non-empty** (`cmd_transition`), while the four-class impossibility gate lives on
   `add --why-not-now` (`bin/cc-backlog:1120-1132`). Result: **281 of 296 blocked rows (94.9%) carry
   no impossibility class**, 68% arrived via one `cc-backlog needs` call, **158 (53%) have `needs`
   byte-identical to `title`**, and **238 (80%) were never claimed by any worker** — they went
   straight to blocked. Judged per row on a seeded sample of 25: **~64% are genuine operator gates,
   ~28% are agent work wearing a park** (honest band 40–135 of the 296).
3. **The detectors went dark two days before the collapse.** `autonomy-sweep.sh` bounds its
   cloud-return arm at 900 s inside a tick that self-bounds at 400 s, so the pass is a prefix:
   `stopped_before` over 553 self-bound rows is **98.4% at the two earliest checkpoints**, and
   **§2b-v (drain-chain liveness) and §2b-vi (the "is draining winning?" flow report) have executed
   0 times per day since 2026-09-08** — along with §3 NOTIFY. The two instruments built to detect
   exactly this collapse were starved by it.
4. **The standing alarm's glob was broken by a rename.** `drain-chain-assert.sh:226-229` globs
   `fire-drain-recycle*.txt`; the 2026-09-04 lane split renamed briefs to
   `fire-drain-infra-recycle<N>.txt` / `fire-drain-reso-…`, which that glob cannot match. Its verdict
   is right today only by accident (both ages exceed the bound). **Exactly one
   `local-drain-chain-dead` row has ever been filed — on 2026-09-01 — and none for this death.** The
   chain's death was detected by a human.

Also live, from the dispatcher's own stderr: **2,803 claims refused at the actuator** (1,742
`ineligible for --venue cloud`, 1,061 `its premise no longer holds`), **275** `refusing ALL cloud
fires — unlanded cloud declaration(s) against a cap`, **313** `wave-plan gave NO verdict`.

## 5 · Economics — the constraint is not money

| lane | $/closure (Opus-5-list price-weighted equivalence) | rows/session |
|---|---|---|
| local drain | **$3.35** | 5.5 |
| ordinary session | $21.75 | 1.5 |
| **cloud** | **~$112** | — |

Cloud spent ≈ **$3,264 in 30 days** — 2.5× what the entire local drain lane has ever spent.
⚠️ **The $112 figure is the pessimistic end of a real attribution range and should be quoted as a
range**: it divides that spend by the 29 `lane:"cloud"` closures, and §1 shows the lane's true
closure count is ~101. On the generous denominator the figure is **~$32/closure**. Either way cloud
is **10–33× local drain**, and the direction is not in doubt.

Meanwhile **3.19 account-weeks of weekly quota expired unused** in the same window while the
actionable backlog was 47 rows. **Quota is not scarce; drainable work is.** Buying more venue
capacity buys nothing.

⚠️ `docs/research/cloud-local-cost-ab-2026-08-11.md` (parity, trending cloud-cheaper at 0.81× local)
is **still sound as written and has rotted in its denominator**: it priced a *fire*, at n=2 per arm.
Nobody buys fires. At 6.6 fires per item, cloud's per-fire cheapness is erased. Anyone quoting
"cloud is 0.81× local" as a routing argument today is quoting a true number about a unit nobody buys.

## 6 · What this measurement does not cover

- **`lane` attribution starts 2026-08-23**; 2,306 dones carry no `closedBy`. Lifetime local-drain
  output is a lower bound.
- **176 of 748 REAL_FIX rows (23.5%) are other repos** and unverifiable from this checkout; `rc 1`
  there would prove nothing.
- **Operator-asked vs self-noticed inflow is unmeasurable from this store** — no `add` record carries
  a field distinguishing them. The honest bound is *operator-asked ≤ 65%*, and the 84%-no-`dodRef`
  figure indicates far below.
- **Land-lock livelock counts: BLIND** — ship-land writes per-run logs, not a standing store.
- `handoffs.jsonl` rotates ~4 d and `idl.jsonl` ~1 d, so no sweep-phase or fire data exists before
  Sep 5/Sep 12 respectively. Absence there is not absence of runs.

## 7 · The four things that would change the outcome

Stated as measurements, not as a plan — none of these is started.

1. **Give the local lane a scheduler.** It is the cheapest worker on the box ($3.35/closure) and the
   only one with no way to start itself. Everything else about its productivity is downstream of this.
2. **Make `block --needs` as strict as `add --why-not-now`.** One gate, one verb, and the cheapest
   entrance to a state no lane reads stops being free. Retrofit is ~105 rows of agent work currently
   wearing a park.
3. **Fix the two starved detectors before trusting any future "the drain is healthy" reading.** The
   900 s arm inside the 400 s tick makes §2b onward unreachable by construction; re-measuring the
   arms above it cannot help — only ordering can.
4. **Cut the re-land generator or stop counting its rows.** At 28.7% of inflow and 16.7% of the
   store's lifetime population, it is the largest single producer, and its closures are ~100% no-op
   auto-retracts.
5. **Land cloud branches on a clock, not on a sweep that starves.** 52% of cloud sessions delivered
   nothing because trunk moved past them, against a measured counterfactual of 90% landing at +1 h.
   This is the one change that converts already-paid-for compute into delivered work — and it is
   currently gated behind the same starved `autonomy-sweep` arm as the detectors in §4.3.

---

## 8 · Per-axis evidence

Eight read-only axes, each with its own commands, denominators and named exclusions, were written to
`/private/tmp/…/scratchpad/drainprobe/`: `A1-cloud-outcomes` · `A2-local-outcomes` ·
`A3-closure-quality` · `A4-inflow` · `A5-uptime` · `A6-blocked` · `A7-convergence` · `A8-cost`.
Where this synthesis disagrees with an axis, the disagreement is stated in place (the trunk-rate
correction in §3, the cloud cost-denominator range in §5).

---

## 9 · Addendum — the cloud lane's proximate cause, found after this doc first landed

§4 attributed the cloud lane's stop to latency and to the starved sweep. Both hold, but the
**proximate** cause is narrower, and it is a one-line reader bug rather than anything about
credentials, capacity or the model.

**Measured.** Two macOS generic-password items share the service
`Claude Code-credentials-136fa815`:

| `acct` | payload top-level keys |
|---|---|
| `chrisren` | `claudeAiOauth`, `mcpOAuth` — the real credential (`accessToken` present, 108 chars, full scopes) |
| `unknown` | `mcpOAuth` only |

`scripts/cloud-create-api.py:183` called `security find-generic-password -s <service> -w` **with no
`-a`**, so it got the `unknown` item, `json.loads` succeeded, and `["claudeAiOauth"]` raised
`KeyError`. The handler reported that as *"keychain item … holds no OAuth access token"* — a
**WORLD-shaped cause** (the credential is broken, go re-login) for a fact about the **READER**. The
cloud return lane emitted that abstain **719 times from 2026-09-11T23:20:56Z** and returned nothing
for four days, which is exactly the window §1 measures as the lane's death.

The prescribed remedy was refuted the whole time by the box's own tool:
`cc-relogin --dry-run --json next4` → `"result":"refused"`, `"detail":"no re-auth needed — healthy
(auth=ok, login_expires_h=533.2)"`, and `--relogin-info next4` reports `keychain_state: present`,
`has_refresh_token: true`, `refresh_token_expired: false`. Anyone following the error message would
have re-logged in a healthy account and changed nothing.

**A second site had the same bug, and a comment asserting the belief that caused it.**
`bin/cc-relogin:318` also omitted `-a`, under: *"the service string already embeds
sha256(config_dir)[:8], so it is unique on its own."* It embeds the hash and is still not unique —
the hash keys the **config dir**, not the item. Its `-a` branch was guarded on
`info["keychain_account"]`, which `--relogin-info` does not emit, so the branch was unreachable in
production. Consequence: `read_refresh_token()` returned `None`, phase 1 reported *"refresh token
unreadable from keychain"*, and the tool fell through to a **browser** login on an account whose
refresh grant is valid for another three weeks. Same family as this repo's own
`checker-population-rests-on-an-untested-belief`: the belief lived in a comment and nothing executed
it.

**Fixed, with an A/B and two mutants.** Both readers now narrow by `accounts.json`'s top-level
`keychain_account` (the field its own `_secrets` note names as the item's account); the two readers
that always worked — `bin/claude-accounts:455` and `scripts/handoff-fire.sh:6942` — already passed
`-a`, so the repo held the correct pattern at two of four sites. Live A/B on the real keychain:
patched reads the token (len 108), pre-fix sees `['mcpOAuth']` only.
`tests/keychain-account-narrowing.bats` pins it 6/6 with a `security` stub that **distinguishes
`-a`-present from `-a`-absent** — a stub blind to that axis would hold constant the one thing the
suite exists for — plus a mutant per site that must go red.

🚨 **Operational note from writing that test: it leaked a live credential.** `cc-relogin` resolves
`SECURITY_BIN` to the **absolute** `/usr/bin/security`, so a PATH-only stub is silently bypassed;
the first run reached the real keychain and printed a live `next4` refresh token into the run log.
Two lessons, both now encoded in the suite: stub through the **documented seam**
(`CC_RELOGIN_SECURITY_BIN`), never PATH alone, when the subject resolves an absolute path; and a
test helper must **never print a secret even on its happy path**, because the day a stub is bypassed
is the day that print emits a real one. The suite now prints a classified marker and carries case 6,
which fails if anything `sk-ant-`-shaped appears.

## 10 · Late corrections to figures in this file and in the plan record

Arrived from the wave after the first land; recorded rather than silently edited.

- **`BACKLOG_DRAIN_24_7.md:42`'s "+426 rows over 5 days (1,129 filed / 503 closed)" does not
  reproduce.** The maximum 5-day add window in the whole store is 762 filed / 581 closed = **+181**.
  Treat the plan's figure as **UNRECONCILED**, not as a baseline.
- **Duplicate pressure is 5.2%, not the 20.3% title-stem figure**, which was a template collapse and
  was withdrawn by its own author; the `cwd`-derived-`project` dedup hole that caused it closed
  2026-08-19.
- **The conviction protocol is 8 days old.** "14 of 3,525 rows carry `conviction`" is 99.4% of the
  pile filed *before the rule existed*, not 99.6% non-compliance; in-population compliance is
  **14/20 = 70%**. §4's 94.9%-no-impossibility-class figure is unaffected — that gate is older.
- **The premise re-validation lane is dead too**: `premise-pass.stamp` is 9 days old (~36 missed 6 h
  passes), starved below the same 400 s self-bound as the detectors in §4.3. 4 of 23 runnable
  falsifiers exit 0 today with their rows still blocked, and ~47% of 17 hand-checked blocked rows are
  stale — worked case `ae3fdca64013` ("trunk RED blocking every land") passes today, cure `8460f5ac9`
  is on `origin/main`.
- **91% of the 296 blocked rows carry no falsifier** — 171 can neither self-retract nor be read by
  any lane. Only 4 of 296 exist as decision packets, so a parked operator value call never becomes a
  `⛔`.
- **`no-capacity` is measurably false as a filing class**: `general → next4` sits at 0% of its 5 h
  window while next3 strands ~99pp this cycle.
- **The largest controllable local cost is not the model**: a ~107K-token resident preamble re-read
  every turn is **≥43% of a drain session's bill**. Since §5 shows cost-per-closure is a fixed
  session cost divided by rows closed, this is the one lever that moves the denominator and the
  numerator at once.
- **A2's "the repo's landing rate did not depend on the chain" is withdrawn** (already corrected in
  §3): trunk ran ~65 commits/day during the chain's life and ~36/day in the 7 days after, roughly
  halved; net of the chain's own `docs(drain)` journaling the drop is ~27%.
