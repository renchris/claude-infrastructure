# cc-backlog pile census — 619 live rows, 2026-09-04

Source of truth: `bin/cc-backlog list --open --json` (saved once to `rows.json`) + the raw store
`~/.claude/autonomy/backlog.jsonl` for `falsify` / `claim` events. Read-only throughout; no store
was written, no `run` field executed, no process killed.

**Count correction.** The brief said ~612 (371 open + 241 blocked). The live fold is **619**:
**371 open + 242 blocked + 6 claimed**. `list --open` returns all three non-terminal states.

---

## 1. Census

### By project × status

| project | open | blocked | claimed | total | dispatchable? |
|---|---:|---:|---:|---:|---|
| claude-infrastructure | 206 | 130 | 6 | **342** | yes |
| reso-management-app | 124 | 70 | 0 | **194** | yes |
| personal | 9 | 20 | 0 | **29** | **no** |
| reso | 21 | 1 | 0 | **22** | **no** (alias of reso-management-app) |
| doc_classifier | 4 | 9 | 0 | **13** | yes |
| sevenrooms-bridge | 4 | 3 | 0 | **7** | **no** |
| reso-web-app | 1 | 2 | 0 | **3** | **no** |
| reso-qa-runner / lakehouse-lecture / agent-build-hackathon | 2 | 1 | 0 | **3** | **no** |
| `.desk-land-claude-fire-*` (6 junk labels) | 0 | 6 | 0 | **6** | **no** |

**70 of 619 rows (11.3%) sit in a project `scripts/dispatch-projects.conf` does not dispatch.**
No amount of content work closes them; `cc-dispatch` journals each one
`{verdict:"skip", reason:"project-not-dispatched"}` on every pass, forever.

### By condition

| condition | rows |
|---|---:|
| (none) | 281 |
| master-operator-gated | 173 |
| master-product-repos | 50 |
| master-convergence-deadlock | 18 |
| master-account-facts | 13 |
| master-fire-gate | 12 |
| master-enforcing-store / -fleet-footprint / -stranded-work / -session-lifecycle | 17 |
| 55 one-off condition slugs (1–2 rows each) | 55 |

### By source

`needs` 211 · (empty) 125 · `plan-open` 17 · one audit string 12 · `postland-verify` 10 ·
remaining 244 rows spread over ~90 single-use source strings.

### By age (from `firstTs`, vs 2026-09-04)

| bucket | open | blocked | claimed | total |
|---|---:|---:|---:|---:|
| ≤2 d | 28 | 26 | 2 | 56 |
| 3–7 d | 10 | 12 | 1 | 23 |
| 8–14 d | 190 | 76 | 2 | **268** |
| 15–30 d | 132 | 97 | 1 | **230** |
| >30 d | 11 | 31 | 0 | 42 |

Oldest `firstTs` 2026-07-20; 81% of the pile is 8–30 days old — one filing burst, not a steady rate.

### Claim thrash

**539 of 619 rows (87%) have never been claimed once.** 22 rows carry ≥10 claim events; the top two
(`62599dd76a60` 55 claims, `ee1ac85c6ff6` 54) are both blocked on a stale worktree, so every claim
re-blocked. The pile is not a throughput problem — it is an *admission* problem.

---

## 2. Blocked rows (242): operator-only vs agent-workable

Method: regex over `title` + `needs` for the ledger's own operator markers
(`OPERATOR (`, `VALUE CALL`, `RULING BY EYE`, credential/GUI/console/physical/money nouns),
with **50 rows hand-adjudicated** from their full `needs` text where the regex abstained.
Error bar: ±5 rows between (a) and (c) — the boundary between "operator must act" and "operator must
decide" is genuinely fuzzy in this store.

| class | n | median age | 3 example ids |
|---|---:|---:|---|
| **(a) truly operator-only** — sudo / credentials / login / GUI / physical / money | **91** | 19 d | `504d0bc2fe50`, `b448ceafa0ca`, `f36bc0986c43` |
| **(b) mis-filed** — a `run` an agent could execute, no credentials needed | **31** | 12 d | `cd80e11b96b5`, `cfbfc155f429`, `2b0888bc8832` |
| **(c) decision / value judgment** | **47** | 24 d | `3e2358f03e23`, `38b79edd0e90`, `590fedde86cc` |
| **(d) dependency-hold** (a worktree / branch / another row) | **7** | 32 d | `02ba4e52389a`, `ee1ac85c6ff6`, `62599dd76a60` |
| **(e) re-land row** | **62** | 10 d | `6484a07b7221`, `547819348e19`, `271a7e692e46` |
| **(f) stale-marked / premise dead** | **4** | 31 d | `ebc271e7f303`, `24299f47405f`, `1684440567db` |

**The `master-operator-gated` condition label is NOT the operator-only set.** Of its 171 blocked
members: 61 are re-land rows, 51 operator-only, 30 agent-runnable, 25 decisions, 3 dependency-holds,
1 stale. And **40 genuinely operator-only rows do not carry the label at all.** A drain that routes
on that condition mis-routes roughly 70% of the group.

All 3 (d) rows are the same shape — a pre-existing `.worktrees/wt-<id>` that cannot fast-forward.
All three worktrees still exist and hold real content (dirty 0/8/4 files, ahead 8/0/1 commits), so
none is moot; an agent can salvage or retire each and unblock the row.

---

## 3. RE-LAND rows (63 rows, 60 distinct branches)

Branch existence, `git ls-remote --heads origin`: **29 present, 31 gone.**
Of the 31 gone, **10 still have a LOCAL ref** and 2 of those carry commits main lacks.

🚨 **Branch-shaped instruments give the wrong answer here, and this repo already knows it.**
`git rev-list --count`, `git diff`, and `git cherry` classify 35 of the 63 rows as moot.
`scripts/land-content-verify.sh` — whose own header records all three being tried and rejected
("24 of the 25 `re-land …` rows … were FALSE, and actioning four of them would have REVERTED trunk")
— classifies only **16**. The 19-row gap is stranded content sitting in `refs/land/failed/*` snapshots
that no branch points at any more. Every number below is the content instrument, never the count.

| verdict | rows | rule |
|---|---:|---|
| **CLOSABLE** | **16** | every available instrument (failed-ref, `origin/<branch>`, local head) AND the row's own stored falsifier return exit 0 |
| **REAL WORK** | **47** | at least one instrument returns exit 1 — named paths hold content `origin/main` lacks |

Real work ranges from 1 to 11 unlanded paths per ref; the largest are `96a4a9b75d65` (11 paths),
`4a0e50459ad5` (7), `7f3c1ff4a3ad`/`e8c9314024c9` (6 each).

Moot ids (all 16 in `closable.jsonl`): `547819348e19` `271a7e692e46` `0aa0bf97389d` `4fe49c9e33d7`
`2f73d4b368a0` `c673e7f2b1af` `b005bc88daca` `7b6a27c2ae61` `b8e70ba81bc6` `20dfe582a873`
`8a182940b7f0` `caca0b4d0286` `a08e5f60d881` `ae5b585138db` `34fcf30da601` `1fd6084ecc53`.

**Four rows that the branch instruments called moot are NOT** — `4ba12dfcd30e`, `b262e41b26fb`,
`62456380ccab`, `5b4a4809bcf5`. Their own falsifiers return 1 against the ref they cite. `drain/recycle-11`
alone has **84** distinct `refs/land/failed/*` snapshots since 2026-08-17: a branch that has failed to
land 84 times and files a fresh row each time.

---

## 4. PLAN-OPEN rows (17)

Every one of the 17 `source=plan-open` plan files **exists**. Frontmatter `status:` —
14 `open`, 2 `in-progress`, **1 `done`** (`a507762b0a0d` → `docs/plans/STOP_CHAIN_WAVE2.md`).
That one row is closable; the other 16 are live plans.

🚨 **`dodRef`-missing is NOT a closure lever, and believing it would have been a 47-row error.**
Resolving all 147 non-empty `dodRef`s against their project repo reports 47 missing — 45 of them in
`reso-management-app`. The cause is not deleted plans: **that checkout is 1,699 commits behind
`origin/main`** (`git -C ~/Development/reso-management-app rev-list --count HEAD..origin/main` = 1699),
and `docs/plans/FLOOR_PLAN.md` is present in `git ls-tree origin/main`. Any census that resolves a
foreign project's paths against its working tree is reading a stale disk, not the repo.

Separately, 7 live rows point at a plan whose frontmatter says `complete`/`superseded`
(`CLOUD_BACKLOG_PIPELINE.md`, `BACKLOG_CONSOLIDATION_2026-08-09.md`). They are **not** closable: only a
`source=plan-open` row's *entire* claim is "this plan is open" (`bin/cc-premise` scopes its plan-open
premise gate exactly that way). The other 7 are substantive defects filed under a finished plan.

---

## 5. FALSIFIERS — the retraction arm exists, is scheduled, and has retired 5 rows in 9 days

**Coverage: 68 of 619 live rows (11.0%) carry a falsifier.** All 68 probes are read-only (screened for
`rm|mv|cp|git push|git commit|cc-backlog|launchctl|kill|tee|>|>>|sed -i|curl -X|ssh`; the 6 flagged
were `2>/dev/null` redirects and a literal `cp` inside a grep *pattern*). All 68 were run from the repo
root under `timeout 25`.

| exit | rows | meaning |
|---:|---:|---|
| **0** | **1** | row self-retracts NOW — `b7252a3bb015` |
| 1 | 23 | condition still holds |
| 4 | 1 | `jq -e` produced no output — condition holds |
| **127** | **43** | 🚨 **the probe cannot run at all** |

🚨 **The 43 are the finding.** Every one is
`bash /path/to/<worktree>/scripts/land-content-verify.sh <ref>` where the worktree has since been
reaped. The script is gone, so the probe exits 127 — **non-zero, i.e. "the row is still real"**. The
retraction arm therefore fails in the direction that *preserves* the pile, silently, for exactly the
rows it was built to retire. Re-pointing those 43 probes at the shared checkout's copy of the same
script, same ref, flips 8 of them to exit 0.

**`bin/cc-premise`** is the consumer. `sweep --record --close-falsified ${CC_PREMISE_CLOSE_CAP:-5}` is
wired into `scripts/autonomy-sweep.sh:1071` on its own `CC_PREMISE_PASS_EVERY_S` (default 6 h) cadence,
because the pass costs ~266 s. Across the full retained IDL window (2026-08-26 → 2026-09-04, 33 recorded
ticks) it ran to completion **exactly once**: `premise_rows_validated: 43, premise_rows_closed: 5`
(its cap). Every other tick is `not-due` (24) or **`bound-exceeded`** (1, rc 124 against the 1500 s
bound — today at 06:55Z). Net: **5 rows retired in 9 days**, from an arm whose probes are 63% dead.

`bin/cc-backlog` has no `refalsify`/`recheck` verb; `falsify` runs the probe once at attach time and
refuses an exit-0 probe (rc 5) because "exit 0 is the RETRACTING direction". Nothing else re-asks.

---

## 6. DUPLICATES

`bin/cc-backlog dups --mode all --json`: `dodref` 16 clusters / 51 rows · `title` **0** ·
`family` 18 single-row join proposals · `mechanical` **0**. The `dodref` clusters are *same-plan*
groupings (e.g. 12 rows under `docs/plans/FLOOR_PLAN.md §19.7`), not duplicates.

Own exact-title scan over the 619 live rows — **3 clusters, 7 rows, 4 removable**:

| n | ids | title |
|---:|---|---|
| 3 | `547819348e19` `271a7e692e46` `0aa0bf97389d` | re-land `claude/fire-20260818T075756Z-6910-1` |
| 2 | `4fe49c9e33d7` `2f73d4b368a0` | re-land `claude/fire-20260818T080549Z-15840-1` |
| 2 | `0e4f795b3a20` `d60fd1f9c375` | next.config `turbopackPluginRuntimeStrategy` — filed **2 s apart** under two junk project labels |

The 5 re-land duplicates are already class-A closable on content. The next.config pair is the only
independent duplicate: close `0e4f795b3a20`, and re-file the survivor under a dispatchable project —
`agent-build-hackathon` and `reso-qa-runner` are both undrainable labels.

---

## 7. WORKABLE-NOW ranking

`worklist.jsonl` — all **369** open rows that are neither moot nor duplicate, scored
`+2` dispatchable project · `+1` has `dodRef` or falsifier · `+1` claim-count < 5, oldest first.
Score histogram: 4→112, 3→207, 2→14, 1→36.

| # | id | project | age | claims | title |
|---:|---|---|---:|---:|---|
| 1 | `5fc734347de1` | reso-management-app | 39 d | 0 | Land platform-page work (25 commits, cc-010333-23674) |
| 2 | `150c50055e1c` | claude-infrastructure | 27 d | 4 | MEMORY.md index at 24284/25000 chars |
| 3 | `07ac6d58d88d` | claude-infrastructure | 27 d | 1 | `bin/cc-pane` `send` raw-sends caller text |
| 4 | `ed724250a9cb` | reso-management-app | 27 d | 2 | provisioner scripts have ZERO eslint coverage |
| 5 | `26d4010f1b22` | claude-infrastructure | 26 d | 1 | corpus assertions carry wall-clock bounds sized on an idle box |
| 6 | `159c2211b0f2` | claude-infrastructure | 26 d | 1 | `lead-crash-watchdog.sh` should source `watchdog.env` itself |
| 7 | `65818e38e36b` | reso-management-app | 26 d | 1 | heat: page behind the door morph goes near-black |
| 8 | `7ad624a26153` | reso-management-app | 26 d | 1 | `pnpm lint` unusable as a gate in a fresh worktree |
| 9 | `1e6814a4ecdf` | reso-management-app | 26 d | 1 | provision-venue: a1probe tenant orphaned by the manifest gate |
| 10 | `6e86209ae6bc` | reso-management-app | 26 d | 1 | tenant-drift.ts:199 validates dbName against live Turso |
| 11 | `1b00d62958a6` | claude-infrastructure | 25 d | 1 | W4 WAVE: the spawn economy (57 rows) |
| 12 | `eed2530a4165` | claude-infrastructure | 24 d | 0 | flip `WTGC_DISPOSE_LANDED_DIRT=1` |
| 13 | `11fdba2b3148` | claude-infrastructure | 24 d | 0 | Stop-keyed recycle rails never fire in goal-armed sessions |
| 14 | `4e6a51df2a84` | claude-infrastructure | 24 d | 0 | wrap-ledger `LIVE_ADDS` counts paths the live layer cannot carry |
| 15 | `b8bafc270955` | reso-management-app | 24 d | 0 | `land-status.sh` STRANDED double-over-reports |
| 16 | `0052d5105b00` | claude-infrastructure | 23 d | 0 | PROBE: does `git fetch --deepen` work inside a cloud VM |
| 17 | `d73a772a8468` | claude-infrastructure | 23 d | 0 | READINESS wave one: admission-seam conjunction |
| 18 | `79e7c3cb7357` | claude-infrastructure | 23 d | 0 | W4 WAVE: the operator's actual products (58 rows) |
| 19 | `1c20dc1e92db` | claude-infrastructure | 23 d | 0 | cc-wave-plan capacity excludes poll-throttled accounts |
| 20 | `44f6b579248d` | claude-infrastructure | 23 d | 0 | dispatcher cloud session NOT-STARTED past its boot budget |

Ranks 21–369 are in `worklist.jsonl` (ranks 21–40 are all score-4 claude-infrastructure /
reso-management-app rows aged 15–22 d, claim-count 0).

---

## Adversarial pass — what I checked because it would have inverted the answer

1. **`git cherry` / `rev-list` on re-land branches.** Would have declared 35 rows moot; the content
   instrument says 16. Closing the 19 difference would have discarded stranded work — the exact
   incident `land-content-verify.sh`'s header documents.
2. **`dodRef` file-existence.** Reported 47 missing; 45 were a 1,699-commit-stale reso checkout.
3. **Ref-slug matching.** `grep -F drain-recycle-11` matches 84 refs. Anchoring to `-<slug>$` is
   required, and even then the newest ref is a *later* land attempt whose verdict can disagree with the
   one the row cites — which is why class A requires the row's own probe to agree.
4. **`land-content-verify` on a *branch* vs on the *failed ref*.** They disagree on 6 rows
   (`6484a07b7221`, `36798ddce9bd`, `8f00d10ca134`, `6cc4981886d5` …). Class A takes the conjunction.
5. **Falsifier exit codes.** 43 of 68 exit 127 — a dead probe reads as "row is real". A census that
   only counted `exit == 0` would have reported "1 row self-retracts" and missed that 63% of the
   instrument is broken.

Not checked, named as gaps: whether each (b) row's stored `run` command is still *valid* (I read them,
I did not execute them); whether `firstTs` on a `--condition`-keyed row dates *this* instance or the
first sighting of the condition; and the 6 `claimed` rows' leases are all <2 h old and live, so their
holders may already be working them.

---

## Closing — where the 619 actually sit, and the fastest path to zero

**(A) Mechanically closable today, with a stated check: 19.** 16 re-land rows whose content
`land-content-verify.sh` puts on `origin/main` on every instrument *and* on their own falsifier;
1 row whose stored falsifier exits 0 right now (`b7252a3bb015`); 1 `plan-open` row whose plan reads
`status: done` (`a507762b0a0d`); 1 exact duplicate (`0e4f795b3a20`). All 19 with their proving command
are in `closable.jsonl`. This is a *3%* dent — the pile is not mostly rot.

**(B) Agent-workable: 462.** 369 open rows + 5 live-claimed + 46 re-land rows holding genuinely
stranded content + 31 blocked rows mis-filed as operator-gated + 7 worktree dependency-holds + 4
stale-marked rows whose blocking premise is already discharged in their own text.

**(C) Genuinely operator-only: 91.** Credentials, `/login`, a real TTY, a GUI console, a phone call, a
physical device, money. Median age 19 days, oldest 45.

**(D) Decisions: 47.** One value judgment each, nothing to run. Median age **24 days** — the oldest
class in the pile and the one that compounds, because 25 of them gate agent work behind them.

**Fastest path to zero, in dependency order:**

1. **Fix the falsifier, not the rows** (~1 h, unblocks everything else). Re-point the 43 dead probes at
   `~/Development/claude-infrastructure/scripts/land-content-verify.sh` — a worktree-independent path —
   and raise `CC_PREMISE_CLOSE_CAP` off 5. Today the arm can retire at most 5 rows per 6 h *and* is
   blind to 63% of its own population. Nothing else in this list scales until a probe survives its
   worktree.
2. **Close the 19 in `closable.jsonl`.** Each carries its own re-runnable proof.
3. **Land the 46 real re-land rows.** They are 1–11 paths each, all in one repo with standing-land
   authorization. This is the largest single block of *finished* value in the pile, and it decays:
   `drain/recycle-11` has already failed 84 times.
4. **Route the 70 undrainable rows.** Add `personal`, `sevenrooms-bridge`, `reso-web-app` to
   `dispatch-projects.conf`, or re-file them; and normalise the 6 `.desk-land-*` + 2 junk labels. These
   rows cannot be worked at all today, whatever their content.
5. **Re-classify the 31 mis-filed blocked rows to open** and let the dispatcher take them.
6. **Batch the 47 decisions into one operator sitting.** They are one-line-each value calls; asked
   individually they will keep aging at 24 d median. This is the only step that needs the operator's
   attention rather than their credentials.
7. **The 91 operator-only rows are the floor.** No pipeline reaches them. They should leave the drain
   queue entirely and live in the `cc-do` / `OPERATOR ▸` surface, so the queue's depth stops reporting
   work no agent can ever take.

Zero is reachable for **481 of 619 (78%)** by an agent pipeline. The residual 138 (91 operator + 47
decisions) is a *human* backlog wearing an agent backlog's clothes, and the single highest-leverage
change is step 1 — every other step is bounded by how fast a dead probe can be replaced.
