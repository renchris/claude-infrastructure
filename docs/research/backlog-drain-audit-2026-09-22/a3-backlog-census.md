# A3 — cc-backlog store census · 2026-09-22

Subject `~/.claude/autonomy/backlog.jsonl` · 23,348 records · 8,692,208 B · 0 malformed.
READ-ONLY: no mutating verb was run. Fold computed twice — once by `cc-backlog list --all --json`,
once by an independent Python replay of the fold semantics read out of `bin/cc-backlog:1598-1637`.
**Both agree exactly on all four state counts.**

---

## 1. Headline

**3,740 distinct items. 10 open · 340 blocked · 0 claimed · 3,390 done.**

**Convergence verdict: NOT CONVERGING. Drain-to-zero = NEVER, at +20.45 items/week.**

The live set (open+blocked) has been flat-to-rising for 14 days: 347 → 350, OLS slope
**+20.45 items/week** over the last 14 days and **+22.75/week** over the last 7. A non-negative
slope has no zero-crossing.

The one number that says otherwise — the last-28-day slope of **−80.74/week**, which would project
zero on **2026-10-22** — is an artifact of a single 5-day drain wave (2026-09-05 → 2026-09-09, live
589 → 344). That wave ended 13 days ago and has not recurred. Quoting the 28-day slope is quoting a
regime that is over.

**The composition inverted rather than drained.** Against the 2026-09-04 baseline recorded in
`docs/plans/BACKLOG_ZERO_2026-09-04.md` §1 (620 live = 371 open · 243 blocked · 6 claimed):

| | 2026-09-04 | 2026-09-22 | Δ |
|---|---|---|---|
| live | 620 | 350 | **−270** |
| open (agent-drivable) | 371 | **10** | −361 (−97%) |
| blocked (operator-gated) | 243 | **340** | **+97 (+40%)** |
| claimed | 6 | 0 | −6 |

The open stratum genuinely drained — of those 371 open rows, **319 (86%) reached done**, 47 became
blocked, 5 are still open. But **157 new blocked rows were filed since**, so the blocked stratum is
now **97.1% of everything live** and is the only stratum still growing: **+45.75 items/week** (7d),
**+48.54/week** (14d), zero down-days in 15.

Reporting "10 open" alone would read as all-done. The honest statement is: **the agent's queue is
nearly empty and the operator's queue is at its all-time high.**

**A second, smaller headline: of the 10 open rows, only 2 are dispatchable.** The dispatch set is
`{CC_DISPATCH_PROJECT} ∪ {conf rows with repo=}` = claude-infrastructure, doc_classifier,
reso-management-app (`scripts/dispatch-projects.conf`; `bin/cc-dispatch:339-341, :1921`). Six of the
ten open rows are `sevenrooms-bridge`, one `personal`, one `voiceink` — projects with **no conf row
at all**. They are journalled `verdict=skip reason=project-not-dispatched` every pass and fired
never.

---

## 2. Tables

### 2.1 State vocabulary (enumerated, not assumed)

Read out of the fold at `bin/cc-backlog:1598-1604`. The status vocabulary is **exactly four values**:

| status | n | reached by |
|---|---|---|
| `done` | 3,390 | `done` |
| `blocked` | 340 | `block` |
| `open` | 10 | `unblock`, `reopen`, and the default for a fresh `add` |
| `claimed` | **0** | `claim` |

**There is no `retracted` state.** Retraction is written as `done` (see §2.9) and is
indistinguishable from completion in the fold.

Two non-status fold fields also carry state: **`wasDone`** (the done latch; 2 items are latched and
not-done, both blocked, both excluded from the dispatch wave by `cc-dispatch:1966`) and
**`venue`/`venuePlan`**.

Event vocabulary — all 10 verbs present, none assumed:

| event | n | | event | n |
|---|---|---|---|---|
| claim | 5,033 | | link | 1,465 |
| add | 3,740 | | venue | 1,389 |
| done | 3,633 | | falsify | 987 |
| block | 3,014 | | unblock | 781 |
| reopen | 2,915 | | update | 391 |

`claimed = 0` is **not a snapshot artifact.** Median claim dwell is **2.5 min** (p90 142 min, max
22.1 h, n=4,545 resolved holds; 0 unresolved at end of trail), against **44–321 claims/day** over the
last 14 days. Zero-claimed is the expected instantaneous state of a lane whose holds are minutes long.

### 2.2 Age of the OPEN set (age = now − `firstTs`, first-wins)

| stratum | n | median | p90 | max | >30d | >60d | >90d |
|---|---|---|---|---|---|---|---|
| **open** | 10 | **17.6 d** | 29.4 d | **31.2 d** | 1 | 0 | 0 |
| **blocked** | 340 | **26.4 d** | 45.7 d | **64.2 d** | 145 | 4 | 0 |
| live (open+blocked) | 350 | 26.4 d | 45.4 d | 64.2 d | 146 | 4 | 0 |

⚠️ **Max age is store-bounded, not work-bounded.** The store's earliest record is
`2026-07-18T23:23:56Z` — 65.3 days ago. `>90d = 0` in every row above is therefore a fact about the
file, not about the work.

**5 oldest OPEN items:**

| age | id | project | title (truncated) | records |
|---|---|---|---|---|
| 31d | `d6d7edef60a3` | claude-infrastructure | handoff-fire runs its payload gates on 1 of 3 fire paths: `--recycle` runs NEITHER payload_pane_id_gate NOR payl… | **774** |
| 29d | `c6d897731567` | sevenrooms-bridge | preflight-golive.sh section G2 negative control flaked once (2026-08-23) | 2 |
| 29d | `45a0073b9ea4` | sevenrooms-bridge | preflight-golive.sh flake NARROWED: REPRODUCED 1-in-13 running the full preflight | 4 |
| 29d | `1bf260340259` | sevenrooms-bridge | sevenrooms sidecar THE FLOOR: if device trust ever lapses there is no automated completion | 2 |
| 27d | `3c3bdc5be447` | sevenrooms-bridge | Root-cause the un-narrated sidecar restarts (~every 1.5-2h) | 2 |

`d6d7edef60a3` carries **774 records** — 20.7% of its project's live rows' churn in one item, and
its `lastTs` was 6 minutes before this census. It is the store's dominant claim/reopen thrash item.

**5 oldest BLOCKED** (the stratum that actually holds the age): `10eb9e8c5d0c` doc_classifier 64d ·
`6a8df00b9b52` doc_classifier 63d · `02ba4e52389a` claude-infrastructure 63d · `dcd894ef1cb5`
doc_classifier 62d · `39045277edc8` reso-management-app 58d. Four of five are at the store's floor.

### 2.3 Arrival vs closure, weekly (whole store; week starts Monday)

`arriv` = ids seen for the first time · `closed` = transitions into `done` · `undone` = transitions
back OUT of done · `net` = arriv − closed + undone · `live` = open+blocked+claimed at week end.

| week | arriv | closed | undone | net | live @ wk end |
|---|---|---|---|---|---|
| 2026-07-13 | 457 | 454 | 2 | +5 | 5 |
| 2026-07-20 | 162 | 58 | 0 | +104 | 109 |
| 2026-07-27 | 308 | 188 | 2 | +122 | 231 |
| 2026-08-03 | 553 | 328 | 4 | +229 | 460 |
| 2026-08-10 | 732 | 756 | 9 | −15 | 445 |
| 2026-08-17 | 502 | 504 | 65 | +63 | 508 |
| 2026-08-24 | 192 | 159 | 19 | +52 | 560 |
| 2026-08-31 | 202 | 259 | 0 | −57 | 503 |
| **2026-09-07** | 366 | **551** | 0 | **−185** | 318 |
| 2026-09-14 | 243 | 213 | 3 | +33 | 351 |
| 2026-09-21 (partial) | 23 | 24 | 0 | −1 | 350 |

Last 12 weeks = the whole store: arrivals 3,740 · closes 3,494 · undone 104 · net **+350**.
Last 4 weeks: arrivals 834 · closes 1,047 · net **−210** — of which the single week 2026-09-07
contributes −185.

**Trend over the last 4 weeks specifically, resolved by window:**

| window | live start → end | OLS slope | arrivals | closes | net |
|---|---|---|---|---|---|
| last 28 d | 543 → 350 | **−80.74 / wk** | 874 | 1,067 | −193 |
| last 21 d | 589 → 350 | −79.04 / wk | 815 | 1,040 | −225 |
| **last 14 d** | **347 → 350** | **+20.45 / wk** | 514 | 511 | **+3** |
| **last 7 d** | **334 → 350** | **+22.75 / wk** | 220 | 211 | **+9** |

The 28d and 14d windows disagree in SIGN. They are not two estimates of one rate — they are two
regimes. The regime boundary is 2026-09-09.

### 2.4 The blocked stratum in isolation — the divergent one

| week | → blocked | blocked → | of which → done | blocked @ wk end |
|---|---|---|---|---|
| 2026-08-24 | 307 | 274 | 86 | 222 |
| 2026-08-31 | 240 | 250 | 77 | 212 |
| 2026-09-07 | 292 | 227 | 179 | 277 |
| 2026-09-14 | 126 | 68 | 65 | 335 |
| 2026-09-21 (partial) | 13 | 8 | 7 | 340 |

Last 4 weeks: **→blocked 671 · blocked→ 553 · blocked→done 328.** Blocked slope: **+35.62/wk** (28d),
**+48.54/wk** (14d), **+45.75/wk** (7d). Positive in every window — no regime disagreement here.

Daily blocked size, last 15 days: 203, 222, 267, 260, 265, 274, 277, 288, 295, 299, 315, 325, 327,
335, 340, 340. **Monotone non-decreasing.**

Since 2026-09-04, **545 `block` events converted an open or claimed row into blocked**; 0 landed on a
brand-new row in the same record. The blocked pile is fed by conversion of agent work into operator
work, plus 157 net-new `needs` filings.

### 2.5 Drain-to-zero projection

| basis | slope | verdict |
|---|---|---|
| last 28 d (spans the 09-05→09-09 drain wave) | −80.74 / wk | zero in 30 d = **2026-10-22** |
| **last 14 d (current regime)** | **+20.45 / wk** | **NEVER — net +20.45 items/week** |
| last 7 d | +22.75 / wk | **NEVER — net +22.75 items/week** |
| blocked stratum, any window | +35.6 to +48.5 / wk | **NEVER — net +45.75 items/week (7d)** |

**The answer is NEVER, and the number is +20.45 items/week** (live set, 14-day OLS). Stated on the
stratum that is actually growing: **+45.75 items/week**.

### 2.6 Duplicate / re-mint rate among live rows

Measured over the **350 live rows**, not the 10 open ones — a clustering statistic over 10 rows has
no discriminating power, and reporting a rate from it would be reporting the sample size.

| key | clusters | rows covered | rate |
|---|---|---|---|
| A: identical first-6 significant tokens (digits→`#`, shas stripped) | 2 | 4 / 350 | **1.1%** |
| B: Jaccard ≥ 0.60 on normalized title tokens | 3 | 10 / 350 | **2.9%** |
| `cc-backlog dups --json` (the tool's own 4 keys: dodref/title/family/mechanical) | **0** | 0 | **0%** |

Top clusters:

| n | shape | verdict |
|---|---|---|
| 5 | `collect cloud session session_<id> — it finished, pushed, and is waiting` | **family, not duplicate** — each names a distinct cloud session |
| 3 | `cloud session session_<id> is blocked on a permission grant in its own w…` | **family, not duplicate** |
| 2 | `~/.claude/CLAUDE.md holds rules that are in NO tracked revision…` (`8c6c8bba09e1`, `8ad5731d6338`) | **true near-duplicate** — same title, same project, same source `needs` |
| 2 | `deploy lane refusing on repeat: the shared checkout …` (`3fe2c31b6fb5`, `75fe1032bbc2`) | two causes of one symptom; arguably one item |

**Re-mint is essentially solved, and the mechanism is visible: 329 of 350 live rows (94.0%) carry a
`condition` key**, which re-keys the id on project+condition and drops the title from the hash
(`bin/cc-backlog` § CONDITION KEY). That is why `dups` returns four empty arrays. The residual ~1
true duplicate is a row pair that predates or escaped the condition join.

### 2.7 Composition of the live set — by project

| project | live | open | blocked | dispatch status |
|---|---|---|---|---|
| claude-infrastructure | **197** | 2 | 195 | DISPATCHABLE |
| reso-management-app | 85 | 0 | 85 | DISPATCHABLE |
| personal | 37 | 1 | 36 | **no conf row — never dispatched** |
| sevenrooms-bridge | 11 | **6** | 5 | **no conf row — never dispatched** |
| doc_classifier | 9 | 0 | 9 | DISPATCHABLE |
| reso | 5 | 0 | 5 | declared `skip=NOT` |
| voiceink | 4 | 1 | 3 | **no conf row — never dispatched** |
| lakehouse-lecture | 1 | 0 | 1 | **no conf row — never dispatched** |
| reso-qa-runner | 1 | 0 | 1 | declared `skip=no` |

**Live rows in a dispatchable project: 291 / 350. OPEN rows in a dispatchable project: 2 / 10.**

### 2.8 Composition of the live set — by producer (`source`)

| producer class | live rows | share |
|---|---|---|
| **`needs` verb (a session filing an operator-only step)** | **223** | **63.7%** |
| other / named (plan-open, audit slugs, ad-hoc) | 50 | 14.3% |
| (empty — no `source` field) | 36 | 10.3% |
| session uuid (a session close) | 16 | 4.6% |
| session close, prose-tagged | 9 | 2.6% |
| audit sweep | 8 | 2.3% |
| backlog-id (spawned from another row) | 6 | 1.7% |
| census sweep | 1 | 0.3% |
| postland-verify hook | 1 | 0.3% |

**The dominant producer is `cc-backlog needs` — a session handing work to the operator.** Not
cc-discover critics (0 live rows), not hooks (1). The pile is made of hand-offs.

`needs`-sourced rows over time — filed vs closed:

| week | filed | closed | net | cumulative live |
|---|---|---|---|---|
| 2026-08-24 | 90 | 80 | +10 | 108 |
| 2026-08-31 | 98 | 84 | +14 | 122 |
| 2026-09-07 | 255 | 253 | +2 | 124 |
| 2026-09-14 | 162 | 138 | **+24** | 148 |
| 2026-09-21 (partial) | 13 | 13 | 0 | 148 |

All time: **1,304 `needs` rows filed, 1,081 closed (82.9%), 223 live.** Last 4 weeks: filed 528,
closed 488, **net +40**. The operator lane closes 92% of what it is handed and still loses ground.

### 2.9 `--why-not-now` impossibility class on the blocked rows

| class | on the 340 blocked | on all 350 live | all-time (3,740 items) |
|---|---|---|---|
| **(no `--why-not-now` field at all)** | **305 (89.7%)** | 312 (89.1%) | 3,445 |
| `needs-human` | 32 | 32 | 48 |
| `not-yet-true` | 3 | 6 | 176 |
| `needs-credential` | **0** | 0 | 0 |
| `no-capacity` | **0** | 0 | 4 |
| unrecognized prose in the field | 0 | 0 | 59 |

**90% of the blocked pile carries no impossibility class.** This is not a discipline failure — it is
a door asymmetry: `cc-backlog add --why-not-now` **requires and validates** the class (rc 2 on
anything else), while `cc-backlog needs "<step>"` files a row **already blocked with no class field
at all**. 223 of 350 live rows came through `needs`. The FILED test's field (a) is therefore
unanswered on the producer that files two thirds of the pile.

Where the class IS present it is well-formed: **31 of the 32 live `needs-human` rows carry both
`--conviction` and `--receipt`** (the F2 conviction protocol, enforced at `cc-backlog:needs`).

Blocked rows by actionability: **340 carry `needs` prose · 160 carry a `run` command (cc-do-able) ·
152 carry neither a `run` nor a class** — i.e. 44.7% of the blocked pile is prose with no executable
handle and no stated impossibility.

### 2.10 Store hygiene

| metric | value |
|---|---|
| records | **23,348** (0 blank, 0 malformed — verified by independent parse, matching `valid_records`) |
| **malformed lines** | **0** |
| distinct items | **3,740** |
| bytes | 8,692,208 (8.29 MiB) |
| span | 2026-07-18 → 2026-09-22 (67 days) |
| growth, whole store | **129,352 B/day · 348.5 records/day** |
| growth, last 14 d | 120,128 B/day · 341.4 rec/day |
| growth, last 7 d | **125,598 B/day · 408.6 rec/day** |
| records per item | **median 4** · mean 6.24 · p90 10 · p99 39 · **max 774** |
| top record-heavy items | `d6d7edef60a3` 774 · `b262e41b26fb` 154 · `62599dd76a60` 120 · `ee1ac85c6ff6` 117 · `01ab05685857` 110 |
| **has `compact` ever run?** | **NO** |
| terminal rows still in the store | **3,390 / 3,740 = 90.6%** |

**`compact` has never run, and the evidence is structural, not an absent log.** `compact` drops
terminal rows, which would leave an item whose remaining trail begins with something other than
`add`. **All 3,740 item trails begin with `add`** — zero truncation signatures. There is also no
`.bak`, no compact marker record, and the store's first line is itself an `add`. So the 67-day span
is the store's true age, and **90.6% of the file is completed work that `compact --older-than-days
30` is built to drop.** At the current 129 KB/day the file adds ~3.9 MB/month with no reclamation.

**Closure quality caveat, which changes the meaning of the closure rate in §2.3:** of 3,633 `done`
events, **1,286 (35.4%) carry falsifier/premise-retraction evidence** ("falsifier passed: …"), i.e.
the row was closed because its premise stopped being true, not because work was delivered. Last 4
weeks: **394 of 1,213 (32.5%)**. 96 done events carry no evidence string at all. Since the
vocabulary has no `retracted` state, **roughly a third of the measured "closure rate" is
retraction**, and the fold cannot separate the two except by string-matching the evidence field.

---

## 3. Commands and scripts that produced each number

All read-only. No mutating verb (`add`/`claim`/`close`/`done`/`block`/`unblock`/`compact`/`reap`/
`link`/`falsify`/`venue`/`backfill`/`reclaim`) was invoked. Every command's rc was checked; none was
run with stderr suppressed into a count.

```bash
# help + fold semantics (source of the state vocabulary)
~/.claude/bin/cc-backlog --help
sed -n '1560,1680p' ~/.claude/bin/cc-backlog     # the fold: status, wasDone, lastTs, firstTs
grep -n 'cmd_list()' -A 60 ~/.claude/bin/cc-backlog   # --all/--open/--blocked predicates

# §1, §2.1 state counts — arm 1, the tool
~/.claude/bin/cc-backlog list --all --json > /tmp/backlog-probe/all.json   # rc 0, stderr empty
jq -r 'group_by(.status)[] | "\(.[0].status)\t\(length)"' /tmp/backlog-probe/all.json
~/.claude/bin/cc-backlog list --open    --json | jq 'length'   # 350
~/.claude/bin/cc-backlog list --blocked --json | jq 'length'   # 340
jq '[.[]|select(.status=="open" and (.wasDone|not))]|length' /tmp/backlog-probe/all.json  # 10

# §1, §2.1, §2.10 — arm 2, the independent fold (the control on arm 1)
python3 /tmp/backlog-probe/a3/fold.py      # → fold.json; prints event vocab, status fold, malformed
# §2.2 age distribution + oldest
python3 /tmp/backlog-probe/a3/stats.py
# §2.3 weekly arrival/closure replay + live-set daily series
python3 /tmp/backlog-probe/a3/weekly.py
# §2.4 blocked-stratum flow + claim dwell   (inline heredoc, saved below)
# §2.5 projections (OLS over 28/14/7-day daily live series)
# §2.6 near-dup clustering (two keys + the tool's own)
~/.claude/bin/cc-backlog dups --json       # rc 0 → {"dodref":[],"title":[],"family":[],"mechanical":[]}
# §2.7 dispatchability
grep -vE '^\s*#|^\s*$' ~/Development/claude-infrastructure/scripts/dispatch-projects.conf
grep -n 'THE SET =' -A 3 ~/.claude/bin/cc-dispatch        # :339-341
grep -n 'select(.status=="open" and (.project' ~/.claude/bin/cc-dispatch   # :1921, :1931
# §2.10 compact-never-ran proof
python3 -c "…count first event of every item id…"   # {'add': 3740}, 0 non-add
```

The working scripts are retained at `/tmp/backlog-probe/a3/`: `fold.py`, `stats.py`, `weekly.py`,
`fold.json`, `weekly.txt`, `dups.json`. The census used `now = 2026-09-22T06:00:00Z`.

**Fold semantics replicated (from `bin/cc-backlog:1598-1637`)**: status = last-transition-wins over
`done→done · block→blocked · unblock→open · claim→claimed · reopen→open`, default `open`; `wasDone`
latches on `done` and clears only on `reopen --force`; `lastTs` advances on every event **except
`venue`**; `firstTs` is **first-wins**. Age is computed from `firstTs`, never `lastTs` — `lastTs` is
corrupted as an age signal by link/venue bookkeeping sweeps (the file says so itself at :3470).

---

## 4. What I could not measure

1. **Work older than the store.** The earliest record is 2026-07-18T23:23:56Z. Every `>90d = 0` in
   §2.2 is bounded by the file, not by the work. Whether these items existed in an earlier store is
   not answerable from this file, and no predecessor store or backup exists in `~/.claude/autonomy/`.
2. **Completion vs retraction, exactly.** There is no `retracted` state; both fold to `done`. §2.10's
   35.4% retraction share is a **string match on the `evidence` field** ("falsifier passed" /
   premise / retract), which is a lower bound on retractions and will miss a retraction closed with a
   sha in the evidence slot. A precise split needs `cc-premise`'s own log, which I did not read.
3. **Whether a blocked row's premise is still true.** Only **34 of 350 live rows carry a
   `falsifier`** (9.7%), so 90% of the pile has no self-retraction probe and its premise has never
   been re-checked since filing. The `>30d = 145` blocked rows are *asserted* live, not *measured*
   live. This is the single largest unknown in the census: if premise decay runs at the same ~35% the
   closure stream shows, a material share of the 340 is already moot.
4. **Closure value.** A `done` with an evidence sha proves a commit exists, not that the row's work
   was delivered. I did not adjudicate any evidence body. (Prior measurement in this repo —
   `docs/lessons/closure-count-is-not-value-delivered.md` — found 40–55% of closures were no-ops;
   that finding is neither confirmed nor refuted here.)
5. **Cloud-lane state.** 14 `done` events since 09-08 carry `lane: cloud`, but this store cannot see
   pending cloud fires that never returned. `docs/plans/BACKLOG_ZERO_2026-09-04.md` §1.1a recorded
   pending 543 at +23.5/day; whether that is still true needs `cloud-reconcile`, not this file.
6. **Why the 09-05→09-09 wave happened and whether it is repeatable.** Its closes are real (lane
   attribution: local-drain 198, session 264, land 15, cloud 8, none 86, across 6 named closers), but
   what *caused* the burst — and therefore whether it can be re-fired — is outside this store.
7. **`source` for 36 live rows is empty**, so 10.3% of the producer attribution in §2.8 is unknown
   rather than "other". Those rows predate the source discipline or were filed by a caller that
   passes none.
