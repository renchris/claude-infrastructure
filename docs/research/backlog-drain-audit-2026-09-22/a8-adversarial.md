# A8 — Adversarial panel: attack the framing, price the cost

Read-only. No edits, no fires, no mutating commands. Every number below carries its command in §5.
Store snapshot 2026-09-22T06:0xZ: `~/.claude/autonomy/backlog.jsonl`, 23,348 records, **0 parse
failures**, 3,740 distinct ids.

---

## 1 · Headline

**The single number nobody else is computing: 1,576 landed commits on `origin/main` cite a backlog
id — 29.0% of the repo's entire 5,433-commit history. 651 of them in the last 30 days. 976 of the
1,576 are code-type commits (`fix`/`feat`/`test`/`refactor`/`perf`/`chore`), 385 of those in 30 days.
1,165 distinct backlog ids are cited by at least one landed commit.** Zero of those 1,165 tokens
resolve as a git object (`git cat-file --batch-check` → 1165 missing, 0 ambiguous), so this is not
short-sha contamination.

**And the rows DROVE the commits rather than recording them.** Median lag from the row being filed
to the citing commit is **101.1 hours (4.2 days)**; 65.9% of the 2,414 (commit, id) pairs land >24 h
after filing, 40.1% >7 days, and only 13.6% inside an hour. A receipt would cluster at zero. It does
not.

**My verdict on the framing: "drain to zero" is the wrong goal, but not for the reason the wave is
set up to find.** Three claims, in descending confidence:

1. **The goal is unreachable by construction, not by underperformance.** `cc-dispatch` selects
   `status=="open"` and nothing else (`bin/cc-dispatch:1921`, `:1818`, and its own header line 16).
   The live pile is **350 rows: 340 blocked, 10 open**. The drain lanes' addressable queue is
   therefore **10 rows — 2.9% of the pile.** Both lanes could run perfectly forever and 340 rows
   would remain. A zero target over a queue whose 97% is operator-gated is a goal that names an
   activity, not an end state.
2. **The queue is NOT growing.** Last 30 days: 1,141 `add` against 1,345 `done` — ρ = 0.85, **net
   −204 live rows.** The obvious sibling verdict ("unproductive, queue growing") is refuted on the
   store's own arithmetic. What grew is *blocked* (1,355 blocks vs 416 unblocks), which is a
   different claim and a different remedy.
3. **It is a filing defect AND a drain-capacity fact, but the filing defect is ~30%, not 90%.** The
   defensible counterfactual queue is ~250–270 rows, not ~20. Detail in §2.

**Sharpest single finding.** Since the lane field began (2026-08-23) the `local-drain` lane closed
397 rows and **stopped on 2026-09-09T22:00Z — 12.3 days ago**; `scripts/drain-chain-assert.sh`
agrees ("the 24/7 backlog drain chain is DEAD … newest fire-drain-recycle brief 1,063,605 s old, 0
live leases"). **The queue still shrank by 204 rows in that window.** Ordinary `session` work closed
547 and `sweep` 74. So the backlog is productive *without* the local drain pipeline. That is the
strongest available argument that the pipeline, specifically, is not what makes the store work — and
it is an argument the pro-pipeline case must answer, not the anti-pipeline case.

**Correction to a sibling's likely premise:** `docs/research/drain-pipeline-productivity-2026-09-16.md`
says "**Both** lanes are stopped." That was true of cloud on 09-16 and is **false today** — the cloud
lane has closed a row on **every day since 2026-09-16** (2,3,1,1,2,2,1), most recently
2026-09-22T02:43:35Z. Do not carry that sentence forward.

---

## 2 · Part A — is "drain to zero" the right goal? The filing audit, quantified

### 2.1 The pile, folded

| state | n | % of live |
|---|---|---|
| blocked | 340 | 97.1% |
| open | 10 | 2.9% |
| **live total** | **350** | |
| done | 3,390 | (90.6% of all 3,740 ids) |

My independent fold and `bin/cc-backlog list --open --json` agree exactly (350 / 340 / 10), so the
fold is not my artifact.

### 2.2 Against the rule's three clauses

The rule (§ Session Close Protocol, FILED row) demands (a) a named impossibility class, (b) a
why-still-true condition, (c) a named beneficiary.

| clause | instrument | live blocked rows satisfying | % |
|---|---|---|---|
| (a) named impossibility class, explicit | `whyNotNow` opens with one of the four classes | **35 / 340** | 10.3% |
| (a) class satisfied *structurally* | filed via `cc-backlog needs` (the sanctioned `needs-human` front door) | **222 / 340** | 65.3% |
| (a) **neither** — went `add`→`block` with no class | | **83 / 340** | **24.4%** |
| (b) why-still-true, as a `--falsifier` | `falsifier` field present | **31 / 340** | 9.1% |
| (c) named beneficiary | `needs` present | 340 / 340 | 100% |
| F2 number rule (`--conviction` + `--receipt`, mandatory on `needs-human` since 2026-09-08) | | **31 / 340** overall; **31 of the 144 filed AFTER the gate landed** | **21.5% post-gate** |

**The mechanism, and the machine already knows it.** The four-class gate is enforced on ONE verb —
`add --why-not-now` (`bin/cc-backlog:1120-1126`). `block --needs` and the `needs` front door validate
**non-emptiness only**. 65.3% of the live pile enters through the unenforced verb. This is not my
inference: blocked row **`12b4209cb7fc`** states it verbatim — *"block --needs validates only
non-emptiness while add --why-not-now enforces the four impossibility classes, so 281 of 296 blocked
rows (94.9%) carry no class, 68% arrived via one cc-backlog needs call, and ~105 are agent work
wearing a park that no lane reads."* **That row is itself blocked**, awaiting an operator policy
call. The fix for the filing defect is parked behind the filing defect.

### 2.3 Answering "what fraction would never have been filed"

I ran the acquittal arm honestly and it moved the number **down**, not up:

- The "needs echoes its title" signal reads at 52.4% (178/340) — and **177 of those 178 are
  `source:"needs"`**, where title and needs are the same sentence *by construction* (the front door
  files one string into both). **Zero** non-`needs` rows echo. That signal is an artifact of the
  designed API and is **not** evidence of lazy filing. A sibling computing it without the source
  join will report a defect that does not exist.
- Reading the 133 rows my operator-gate regex missed: they are overwhelmingly **genuine** —
  phone calls, physical mail, iPhone Settings panes, sign-and-send letters, blind design rankings,
  GUI-only kitty gestures, credentials in `.env.local`. My regex was too narrow, not the pile too
  loose.

What survives as genuine defect:

| class | n | evidence |
|---|---|---|
| blocked with no impossibility class at all (`add`→`block`, no `whyNotNow`) | 83 | §2.2 |
| pipeline **self-debt** — rows the drain machinery filed about its own stalls (5× "collect cloud session …", 4× "deploy lane refusing on repeat", 4× "land/converge the shared checkout", 2× "re-arm the /goal on pane 19x", 8× "answer the permission prompt freezing pane …", 6× "close/confirm-close pane …") | **36** | regex over title+needs, listed in raw notes |
| byte-adjacent duplicates the dup detector cannot see (e.g. `8c6c8bba09e1` / `8ad5731d6338`, same subject, 290 vs 297 chars) | ≥2 | `cc-backlog dups --mode all` returns **"no candidate duplicate groups"** on all four keys — the detector is blind to the `needs` population, which is 65% of the pile |
| filed post-2026-09-08 without the mandatory conviction+receipt | 113 of 144 | §2.2 |

**Verdict on the hypothesis.** "A queue of 200 that should have been ~20 is a filing defect" —
**rejected as stated.** The honest counterfactual is **~250–270 rows, not ~20**: the bulk of the pile
is real operator-gated work that a correct rule still files. The filing defect is real and is
**~24–31%** of the live pile (83 classless + 36 self-debt, with overlap). **The larger defect is
neither filing nor capacity — it is that 97% of the pile is addressed to a party the pipelines cannot
be.** Calling that a drain problem misnames it.

### 2.4 The staleness number the rule cares about

Global rule cites a p90 of 9.3 days in queue. Measured today on the live blocked pile:
**p50 age 26 d, p90 45 d, max 63 d**; days since last touch **p50 14 d, p90 36 d**. With 9.1%
carrying a falsifier, **90.9% of the pile has no self-retraction condition** and cannot go stale
safely. Clause (b) is the rule's least-observed clause and the one that would shrink the pile most.

### 2.5 Where the closures actually go — the retraction band

Of 3,390 closed rows, classified on the `evidence` field:

| evidence shape | n | % |
|---|---|---|
| names a sha / `origin/main` / "landed", no retraction word | 1,728 | 51.0% |
| **both** a sha and a retraction word (moot/superseded/already-true/refuted/duplicate) | 1,258 | 37.1% |
| retraction word only | 178 | 5.3% |
| prose, no sha | 169 | 5.0% |
| empty | 57 | 1.7% |

**Retraction band: 5.3% (strict) to 42.4% (loose).** I report the band, not a point — the 37.1%
middle class genuinely reads both ways ("superseded by landed X" is a retraction *and* a delivery).
Retraction-only is rising: 0.1% (Jul) → 7.9% (Aug) → **12.3% (Sep)**. That trend is the filing
defect's own signature and is the one number I would watch.

---

## 3 · Part B — what the pipeline costs

### 3.1 The quota-denominated cost is NOT COMPUTABLE today, and I can name the missing number exactly

The repo's only token→quota converter, `bin/cc-quota-price`, **abstains on every window I tried**
(30 d, all; 6 h and 24 h buckets):

```
cc-quota-price: ABSTAIN — insufficient movement: 0 bucket(s) with a positive Delta weekly_pct,
below the floor of 12 (8 bucket(s) formed from 19653 sample(s) at 6.0h)
```

**The missing number is the L3 price coefficients — `pp per Mtok` for `output` and `cache_creation`.**
Without them there is no join from the census (which works fine) to the quota meter, so **no
cost-per-closed-item in quota units exists for any lane, mine or a sibling's.**

**And the abstain is an instrument defect, not data absence — root-caused here.** The denominator
store is healthy: 32,778 samples, median inter-sample gap **392 s**, only **0.2% of gaps exceed the
90-minute bucket-breaker**. What kills it is `buckets()` at `bin/cc-quota-price:326`:

```python
if a["reset"] != b["reset"]:
    continue                      # a reset boundary fell inside this bucket
```

`weekly_reset_at` is written with **sub-second microseconds that are regenerated on every sample** —
`2026-09-22T12:00:00.426770+00:00`, `…12:00:00.721054+00:00`, `…12:00:00.337478+00:00` — i.e. a
median of **186 distinct `weekly_reset_at` strings per (account, day), max 232**, for a reset time
that is identical to the second. The string compare therefore fires on nearly every bucket:

| 6h bucket disposition (all 690 buckets, all accounts, whole store) | n |
|---|---|
| dropped: "reset-changed" | **625 (90.6%)** |
| dropped: gapped | 39 |
| dropped: <2 samples | 11 |
| survived, Δ = +0 | 15 |
| survived, Δ > 0 | **0** |

Comparing the reset stamp truncated to the second (or minute) would restore ~625 buckets. Until
then every quota-denominated cost claim in this repo rests on a converter that cannot produce one.

**Consequence for the wave: reject any quota cost-per-item a sibling reports unless they say which
instrument produced it.** The best existing figure — `$3.35/closure` local-drain vs `$21.75` session
vs `~$112` cloud, from `docs/research/drain-pipeline-productivity-2026-09-16.md` — is denominated in
**dollars**, and `accounts.json` carries `spend.usage_credits_authorized=false` / 
`frontier.credits_authorized=false`. **This fleet has zero dollar exposure.** That figure describes
an economy we are not billed in; it is not wrong, it is off-currency.

### 3.2 What IS measurable

Fleet-wide 30 d census (deduped on `message.id`; 55.1% of records were repeats, so summing lines
would have over-counted 2.25×):

| class | 30 d tokens |
|---|---|
| output | 142,560,901 |
| cache_creation | 1,833,881,895 |
| input | 1,535,443 |
| cache_read | 68,843,627,298 |
| | 7,878 files · 285,642 billed responses |

Closures in the same 30 d window, by lane:

| lane | 30 d closures | status |
|---|---|---|
| `session` (ordinary work, not a drain lane) | **547** | alive |
| `local-drain` | **397** | **DEAD since 2026-09-09T22:00Z** |
| `(none)` (pre-attribution) | 201 | — |
| `land` | 85 | alive |
| `sweep` | 74 | alive |
| `cloud` | **41** | **alive — closed on every day since 09-16** |
| **total** | **1,345** | |

**The drain lanes accounted for 438 of 1,345 closures (32.6%) over 30 days, and one of the two has
been dead for 12 of those 30.** I cannot convert their share of tokens into their share of quota, for
the reason in §3.1. I decline to impute it.

### 3.3 The "decaying inventory" counter-argument — tested, and it FAILS on current data

The counter-argument is sound in principle and I checked it on both arms.

**Arm 1 — the forecast.** `claude-accounts --readout` renders, verbatim:

```
weekly drain — pp that DIE at reset (nowcast at the last 48h of pace):
  next strand ~73pp of 82 · p51 of its own 24h burns · 4d left
  next4 strand ~59pp of 92 · p75 of its own 24h burns · 5d left
  next2 strand ~48pp of 65 · p59 of its own 24h burns · 4d left
  next3 strand ~5pp of 14 · p95 of its own 6h burns · 5.9h left
```

~185 pp of 253 pp forecast to die. On that reading, surplus is enormous and the pipeline's
opportunity cost is ~zero.

**Arm 2 — the realized resets. This is the arm that decides it, and it inverts the conclusion.**
`scripts/desk-strand-replay.py` replays 24 observed weekly resets since 2026-08-10. The **last seven
consecutive resets — every account, 2026-09-12 through 2026-09-20 — reset at 100% used → 0 pp
stranded**:

```
next2  2026-09-12T11:00  reset at 100% used  ->  0pp stranded
next   2026-09-13T04:02  reset at 100% used  ->  0pp stranded
next4  2026-09-13T10:57  reset at 100% used  ->  0pp stranded
next3  2026-09-15T12:12  reset at 100% used  ->  0pp stranded
next2  2026-09-19T11:05  reset at 100% used  ->  0pp stranded
next   2026-09-20T04:04  reset at 100% used  ->  0pp stranded
next4  2026-09-20T09:15  reset at 100% used  ->  0pp stranded
```

The surplus regime was real and is **over**: 2026-09-01…09-08 stranded 36/27/38/53/38 pp; everything
since strands **zero**. **Quota is currently fully consumed, so the drain pipelines' opportunity cost
is 1:1 against other work, not near-zero.** The nowcast is a 48-hour-pace extrapolation and has been
predicting strand into a regime that realizes none — **read the realized resets, never the nowcast**,
which is also what the operator's own rule says (*"the live /accounts weekly column UNDERSTATES
spend, so read the strand nowcast"* was written in the opposite regime and is now the weaker
instrument).

### 3.4 Box contention — still happening, but NOT caused by the pipelines

The 2026-08-11 event is in the record and the answer is nuanced, so I give both halves.

`~/.claude/logs/capacity-alarm.jsonl` (53,059 samples, 2026-07-30 → now):

| window | OK | WARN | ALARM | non-OK |
|---|---|---|---|---|
| all time | 27,597 | 16,885 | 8,577 | **48.0%** |
| last 30 d | 11,710 | 10,711 | 3,982 | **55.6%** |
| 2026-09-21 | 26 | 917 | 120 | **98%** |
| 2026-09-22 (today) | 0 | 249 | 15 | **100%** |

**Contention is not historical — it is the ambient state.** Peak 33 concurrent sessions
(2026-09-20T00:16Z, ALARM).

**But the pipelines are acquitted as the cause.** Across 47 days with both series:

- `r(pane spawns/day, non-OK %)` = **−0.276** — *negative*. The heaviest spawn days (2026-08-10: 584
  spawns) ran **25% non-OK**; a 45-spawn day (2026-09-21) ran **98%**.
- `r(concurrent sessions, non-OK)` per-sample = **+0.194** — real but explains ~3.8% of variance.

The alarm is **memory** (`headroom_gb`, `compressor_gb`), and median headroom has drifted 29.9 → 26.7
→ 26.4 GB across three periods while median sessions went 14 → 17 → 13. **Spawn volume does not
explain the saturation.** A sibling arguing "the pipelines crowd out the operator on the box" is
arguing against this correlation and needs to say why.

Where contention *is* real is quota (§3.3) — and there the binding resource is a weekly bucket that
has run to 100% on seven consecutive resets.

---

## 4 · Part C — the strongest case FOR the pipelines

I was asked to build this honestly and it is stronger than I expected.

**C1 — 1,576 landed trunk commits cite a backlog id: 29.0% of the repo's entire history.**

| month | commits | citing a backlog id | rate |
|---|---|---|---|
| 2026-07 | 1,519 | 166 | 10.9% |
| 2026-08 | 2,360 | **972** | **41.2%** |
| 2026-09 | 1,507 | 438 | 29.1% |
| **all** | **5,433** | **1,576** | **29.0%** |

(2026-03…06 are 0/47 — the store's first row is 2026-07-18, so nothing earlier could cite one.)

By conventional-commit type — this is the discount a hostile reader will demand, so I applied it
first: **976 CODE-type** (`fix` 690, `feat` 201, `test` 49, `refactor` 8, `perf` 14, `chore` 13),
**589 docs**. Even discarding every docs commit, **976 landed code changes on trunk trace to a
backlog row**, 385 of them in the last 30 days. `fix` commits cite a row **34% of the time**.

**C2 — the rows are drivers, not receipts.** The obvious rebuttal is "sessions file a row for work
they were doing anyway." Falsified: median filing→commit lag **101.1 h**, 65.9% >24 h, **40.1% >7
days**, only 13.6% inside an hour, 0.5% negative. A receipt distribution would spike at zero.

**C3 — a third of all closures carry a trunk citation.** 1,103 of 3,390 done rows (**32.5%**) are
cited by ≥1 landed commit; 1,165 of 3,740 ids overall (31.1%). 51.0% of closures name a sha or
`origin/main` in their evidence field.

**C4 — the store's throughput is real and its lifetime closure rate is 90.6%** (3,390 of 3,740 ids
closed). Over the last 30 days ρ = 0.85 and the live pile fell 204 rows.

**C5 — the cloud lane is alive and the standing doc says it is not.** Closures on every day since
2026-09-16 (2,3,1,1,2,2,1), most recent 2026-09-22T02:43:35Z. The 2026-09-16 audit's "both lanes are
stopped" has a 6-day shelf life and has expired.

**C6 — the local lane was the cheapest closer on the box when it ran.** 397 closures in its ~18
active days, peak 227/week, 5.5 rows/session against the session lane's 1.5. I cannot re-price that
in quota (§3.1) and I will not repeat the dollar figure as if it bound.

**C7 — the local drain lane landed trunk content for 124 of its 397 closures (31.2%).** Direct
attribution via `git merge-base --is-ancestor` on each closure's own evidence sha; full table in §6.
Ordinary sessions run 48.3% by the same test, so the drain lane is roughly two-thirds as
delivery-dense as a normal session — not a rubber stamp, and not equal to one either.

**What C1–C7 do NOT establish**, stated so the pro-pipeline case is not over-read: the citations
prove the **backlog store** is load-bearing, not that the **drain pipelines** are. `local-drain` has
been dead 12 days and 651 citing commits landed in a 30-day window that contains those 12. The
strongest honest claim is: **the ledger is one of the most productive artifacts in this repo; the
autonomous drain lanes are a modest (32.6% of 30-day closures) and currently half-dead consumer of
it.**

---

## 5 · Commands that produced every number

```bash
# fold + state census (matches `bin/cc-backlog list --open --json` exactly: 350/340/10)
python3 - <<'PY'   # full script in the raw notes; folds add/done/block/unblock/reopen/claim
PY
bin/cc-backlog list --open --json | python3 -c "import sys,json,collections; d=json.load(sys.stdin); print(len(d), collections.Counter(x['status'] for x in d))"
bin/cc-backlog list --blocked | wc -l                      # 340
bin/cc-backlog dups --mode all --json                      # dodref 0 title 0 family 0 mechanical 0
bin/cc-backlog dups --project claude-infrastructure --mode all   # "no candidate duplicate groups."

# HEADLINE — landed commits citing a backlog id (12-hex), joined against the store's own id set
git log origin/main --format=$'\x01%H\x1f%ad\x1f%s\x1f%b' --date=short | python3 …   # 1576 / 5433
git rev-list --count origin/main                           # 5433
git cat-file --batch-check < /tmp/backlog-probe/_cited_ids.txt   # 1165 missing, 0 ambiguous, 0 objects
#   → per-month table, per-type table, and the filing→commit lag distribution from the same walk

# filing-rule audit
grep -n 'needs-credential\|needs-human\|not-yet-true\|no-capacity' bin/cc-backlog   # :1120-1126 gate
git log --format='%h %ad %s' --date=short -S'--conviction' -- bin/cc-backlog        # 4ddbd77d9 2026-09-08
grep -n 'status.*open' bin/cc-dispatch                     # :1818 :1921 — open-only selection

# cost
bin/cc-quota-price --census --since 30d                    # the census (works)
bin/cc-quota-price --since 30d                             # ABSTAIN
bin/cc-quota-price --since 30d --bucket-h 24               # ABSTAIN, 0 buckets formed
bin/cc-quota-price --since all --bucket-h 24               # ABSTAIN, 0 buckets formed
sed -n '299,340p' bin/cc-quota-price                       # buckets(): the a["reset"]!=b["reset"] drop
python3 …  # cadence: 392s median gap, 0.2% >5400s; 625/690 buckets dropped "reset-changed";
           # 186 distinct weekly_reset_at strings per (acct,day)
bin/claude-accounts --readout                              # strand nowcast (relayed verbatim in §3.3)
bin/claude-accounts --rank general
python3 scripts/desk-strand-replay.py                      # 24 resets; last 7 all 100% used / 0pp

# contention
python3 …  # capacity-alarm.jsonl* (53,059 samples) verdict-by-day; pane-spawns.jsonl* by day;
           # Pearson r(spawns/day, non-OK%) = -0.276 ; r(sessions, non-OK) = +0.194
bash scripts/drain-chain-assert.sh                         # DEAD, newest brief 1,063,605s old
cat ~/.claude/autonomy/.drain-health.stamp                 # 2026-09-22 rc1 drain-converting effort-productive

# lanes
python3 -c "…"  # 30d done by lane; local-drain last close 2026-09-09T22:00:17Z;
                # cloud last close 2026-09-22T02:43:35Z, daily since 09-16
```

Artifacts written by this pass (data only, no repo writes):
`/tmp/backlog-probe/_citing_commits.tsv` (1,576 rows: date, sha, ids, subject),
`/tmp/backlog-probe/_cited_ids.txt` (1,165 ids).

---

## 6 · Adversarial self-pass — what I checked because a hostile reviewer would ask

1. **"Your 12-hex tokens are git short shas."** Checked: `git cat-file --batch-check` over all 1,165
   → 1,165 missing, 0 objects, 0 ambiguous. Clean.
2. **"The rows are receipts for work already done."** Checked and refuted: p50 lag 101 h, 40.1% >7 d.
3. **"`needs` echoing its title proves lazy filing."** Checked and *self*-refuted: 177 of 178 echoes
   are `source:"needs"`, where the API writes one string into both fields. I withdrew the finding.
4. **"The pipelines crowd out the operator on the box."** Checked and refuted at the daily level:
   r = **−0.276**. I report this against my own adversarial brief.
5. **"Unused quota is decaying inventory so the cost is ~0."** Checked on BOTH arms — the forecast
   says 185 pp will strand, the realized resets say 7 consecutive 100%-used / 0 pp. I take the
   realized arm and the counter-argument fails.
6. **"Your cost table is missing."** It is, and I name the exact missing quantity (pp/Mtok) and
   root-cause the instrument rather than imputing around it.

**Residual, partly closed after the self-pass.** I could not join the 651 recent citing commits to
lanes directly — `git log` carries no lane field, and `~/.claude/logs/close-attrib.jsonl` turns out
to attribute **pane** closes (`site`/`mode`/`terminal`/`id_requested`), not row closes, so it cannot
carry this join despite its name. The reachable substitute is the closing row's own `evidence` field,
tested for trunk ancestry:

| lane | closures | evidence names a sha | that sha is an **ancestor of origin/main** | landed-share of its closures |
|---|---|---|---|---|
| `session` | 547 | 427 | 264 | **48.3%** |
| `local-drain` | 397 | 295 | **124** | **31.2%** |
| `sweep` | 74 | 74 | 20 | 27.0% |
| `cloud` | 41 | **3** | 3 | **7.3%** |
| `land` | 85 | 64 | 1 | 1.2% |
| `(none)` (pre-attribution) | 2,489 | 2,079 | ≥400 (sampled at 400, a floor) | ≥16.1% |

**So the local drain lane demonstrably landed content on trunk for 124 of its 397 closures.** That is
the concrete pro-pipeline number and it is not small. It also isolates the cloud lane's real defect:
**only 3 of its 41 closures cite a sha at all** — its closures are overwhelmingly evidence-free in the
one dimension that proves delivery, which corroborates the 2026-09-16 audit's independent finding
that 21 of 29 cloud closures cited evidence about a branch their session never touched. The
`land` lane's 1.2% is expected, not a defect — it closes rows *about* landing, whose evidence names
the branch, not a trunk ancestor.

**What remains genuinely unanswered:** the split of the 976 code-type citing commits between drain
lanes and ordinary sessions. The table above bounds it from the store's side (124 + 3 = 127 confirmed
drain-lane trunk landings) but cannot see closures whose row predates the 2026-08-23 `lane` stamp —
2,489 rows, the largest stratum. Any lane-share percentage quoted from this store is therefore a
**lower bound on the drain lanes and an unknown on the `(none)` stratum**; do not let it be reported
as a share.
