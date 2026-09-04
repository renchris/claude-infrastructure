# cc-backlog inflow: which generators file, what rots, what to change

Measured 2026-09-04 against `~/.claude/autonomy/backlog.jsonl` (16,058 records, 3,010 ids).
Fold: `add|reopen|unblock→open · done→done · block→blocked · claim→claimed`.
Live = open+blocked+claimed = **619** (open 371 · blocked 242 · claimed 6). Done 2,391.

---

## 0. THE HEADLINE IS NOT INFLOW

The brief's premise (7d filed 105 / closed 51) is true but its diagnosis inverts. Weekly net:

| week | filed | done | net |
|---|---|---|---|
| 08-07 → 08-13 | 891 | 718 | **+173** |
| 08-14 → 08-20 | 452 | 607 | −155 |
| 08-21 → 08-27 | 433 | 365 | +68 |
| 08-28 → 09-04 | **118** | **57** | **+61** |

Inflow is at a **4-week low** (118, down from 891). Outflow fell harder (57, down from 718). The
`+61` is an **outflow collapse**, not an inflow spike.

**The outflow number that matters** — `com.claude.dispatcher` is `state = running`, `runs = 980`,
last exit 0, and it claims steadily (15–32 rows/day). But of the **23 distinct rows claimed in the
last 7 days, 2 reached `done`** — 15 were released back to `open`, 6 are still `claimed`. A **8.7%
claim→done conversion.** No inflow change fixes that; it is the single largest lever and it is out
of this brief's scope. Flagging it because every recommendation below is worth ≤50 rows and this is
worth ~550.

**Second structural number:** **89 of 619 live rows (14.4%) carry a falsifier**, and re-running
every one of those 89 just now, **44 exit 127 — the probe cannot execute at all.** So only
**45 of 619 (7.3%)** of the live pile can self-retract. `scripts/backlog-ratchet.sh:13-27` was built
to make exactly this visible and calls coverage "the leading indicator"; it is 14.4% and the working
figure is half that.

---

## 1. RANKED INFLOW GENERATORS

### 1a. Last 14 days (2026-08-21 → 09-04), 492 adds

| # | generator | mechanism (file:line) | class | filed | %done | live | w/falsifier |
|---|---|---|---|---|---|---|---|
| 1 | ad-hoc `--source <session label>` | `hooks/dispatch-assert.sh:225` (b) · CLAUDE.md:793 | **MODEL-PROMPTED** | 167 | 32.3% | 113 | 6 |
| 2 | `needs` (non-re-land) | `hooks/completion-assert.sh:1078` (D1) · CLAUDE.md:801 | **MODEL-PROMPTED** | 98 | 59.2% | 40 | 1 |
| 3 | `re-land <branch>` | `scripts/ship-land.sh:1001` (trap) | MECHANICAL | 98 | 49.0% | 50 | 42 |
| 4 | `--source ""` (blank) free-hand | no `--source` passed to `cc-backlog add` | **MODEL-PROMPTED** | 86 | 27.9% | 62 | 0 |
| 5 | `--source <session-uuid>` | same as #1, uuid instead of label | **MODEL-PROMPTED** | 22 | 27.3% | 16 | 0 |
| 6 | `postland-verify` | `scripts/postland-verify.sh:2721-2795` | MECHANICAL | 14 | 28.6%* | 10 | 2 |
| 7 | `plan-open` | `bin/cc-discover:273` | MECHANICAL | 6 | 33.3%* | 4 | 4 |

\* age-truncated — see 1b.

### 1b. Mature cohort (filed 14–28 days ago, fully aged) — the honest done-rate

| generator | filed | %done | live residual |
|---|---|---|---|
| postland-verify | 46 | **100%** | 0 |
| ship-land re-land | 307 | **95.8%** | 13 |
| ad-hoc label free-hand | 471 | 76.9% | **109** |
| «blank» free-hand | 202 | 76.7% | 47 |
| session-uuid free-hand | 25 | 76.0% | 6 |
| **needs (non-re-land)** | 244 | **65.6%** | **84** |
| plan-open | 33 | 60.6% | 13 (n small) |

**Correction to the obvious read:** free-hand model adds are *not* structurally unworkable — they
drain at ~77%. `needs` is the worst-draining class at 65.6%, and the two MECHANICAL generators with
real falsifiers (re-land 95.8%, postland-verify 100%) are the *best*. The problem is
**volume × residual rate**, not any one generator being junk.

### 1c. The 619 live rows, by generator (this is the pile)

| generator | live | w/falsifier | median age | p90 age |
|---|---|---|---|---|
| ad-hoc label free-hand | **239** | 15 (6.3%) | 14.2 d | 26.6 d |
| needs (non-re-land) | **148** | 1 (0.7%) | 18.1 d | 31.8 d |
| «blank» free-hand | 113 | 6 (5.3%) | 12.6 d | 25.5 d |
| ship-land re-land | 63 | 48 (76%) | 10.0 d | 16.2 d |
| session-uuid free-hand | 29 | 0 | 10.4 d | 35.5 d |
| plan-open | 17 | 17 (100%) | 22.9 d | 24.4 d |
| postland-verify | 10 | 2 | 1.0 d | 10.6 d |

Free-hand model `add` (rows 1+3+5) = **381 of 619 = 61.6%**, with 21 falsifiers (5.5%).
Free-hand + `needs` = **529 of 619 = 85.5%**, with 22 falsifiers (4.2%).
The two generators that self-retract hold 80 rows (12.9%).

---

## 2. WHAT DEDUPES AND WHAT DOES NOT

**`add` (`bin/cc-backlog:1462`).** The id is `mk_id project ␟ title ␟ source` (`:962`, sha256 head
12) *unless* `--condition` is passed, in which case it is `mk_cond_id project ␟ condition` (`:1508`).
`has_id` short-circuits a re-add idempotently (`:1509`), and a done-latched row prints a loud
NOT-RE-OPENED warning plus a group fold across `(project, condition)` so a live sibling absorbs the
new measurement as an `update` (`:1560-1640`). **What it does NOT dedupe:** `--source` is *in the id
hash*. A model that passes `--source "$SID"` (which `dispatch-assert.sh:225` literally tells it to)
mints a **fresh id for the same title on every session**. Measured: 764 distinct all-time sources,
**579 used exactly once (75.8%)**; in the last 14 days, 166 distinct, **133 used once (80%)**. Title
dedup is therefore structurally unreachable for the largest generator class. `--condition` is the
only real key and it is **optional and rare** — 1 of 492 adds in 14 days carried one.

**`needs` (`bin/cc-backlog:2967`).** Composition, not a third writer: `cmd_add --source needs` then
`cmd_transition block`. It ships the only *pre-mint* dedup in the file — the **R7 recurrence brake**
(`:3084-3112`), which folds the not-yet-minted title into the mechanical grouping and re-files onto
the existing row instead of minting a sibling. It is fail-open in every direction (no jq, unreadable
store, malformed fold → ordinary mint). `--falsifier` is pass-through with **no default and no
requirement** (`:2974-2984`), documented as deliberate: an operator step has no honest oracle. That
choice is correct in principle and is why `needs` has **1 falsifier across 148 live rows**.

**`reopen` (`bin/cc-backlog:1878`/`1970`).** Not an inflow channel in practice. Last 7 days: 57
reopens, of which **1** carried `--force` (the only path that resurrects a `done` row); 9 were
`--self-release` (a claimer releasing its own claim) and 47 were plain claim releases. `unblock`
(13–53/day) moves blocked→open, which does not change the live count. Re-inflation is not the story.

**`dups` (`bin/cc-backlog:3796`, DUP KEYS at `:412`).** Three keys since 2026-08-11 — `dodref`,
`title` (normalised), `mechanical`, plus `family`. Run just now over the live store: **dodref 16
clusters / 51 rows · family 18 clusters · title 0 · mechanical 0.** Exact-title duplicates among
live rows: **3 groups / 7 rows / 4 excess** — 3 of the 4 are `re-land` siblings for one branch (the
sandbox-project-label bug `ship-land.sh:985-995` documents), the 4th is a reso-web-app pair. **The
store has essentially no exact duplicates**, exactly as `backlog-consolidation-trigger.sh:8-15`
predicts (identical titles collide into one id by construction). The 51 dodref-clustered rows are
the real consolidation surface: 12 live rows share `docs/plans/FLOOR_PLAN.md §19.7`, 6 share
`CLOUD_BACKLOG_PIPELINE.md`, 4 share `ACCOUNT_AGNOSTIC_AGENT_STATE.md`.

---

## 3. PRODUCER CENSUS — MECHANICAL vs MODEL-PROMPTED

**MECHANICAL** (fires from a hook/launchd/script, no model judgment):

| producer | file:line | fires | self-retracts? |
|---|---|---|---|
| ship-land failure inbox | `scripts/ship-land.sh:1001` (`land_failure_inbox`, EXIT/TERM trap) | per failed land | **yes, but broken** — §5.3 |
| postland-verify | `scripts/postland-verify.sh:2721-2795`, `--condition` via `cond_slug` `:740-784` | per RED suite | yes (`:3293`) |
| cc-discover `plan-open` | `bin/cc-discover:273` `add_candidate "advance $title" … "plan-open"` (launchd `com.claude.discovery`, pid 66510) | per open plan | **yes** — `bin/cc-dispatch:2057-2080` + `bin/cc-premise:1865-1940` retract on frontmatter flip |
| autonomy-sweep ratchet arm | `scripts/autonomy-sweep.sh:1129-1131` `--condition backlog-ratchet-coverage-regression` | on coverage fall | condition-keyed (1 row max) |
| grouping sweep | `scripts/backlog-grouping-sweep.sh:119,192` | on ungrouped-count floor breach | condition-keyed |
| consolidation trigger | `scripts/backlog-consolidation-trigger.sh` | on cluster threshold | condition-keyed |
| custody deathwatch | `scripts/custody-deathwatch.sh:73,355` | one aggregated `needs` row | no |
| deploy-live / deploy-migrations / deploy-parity | `scripts/deploy-live.sh:175,505` etc. | per refusal | partial |

**MODEL-PROMPTED** (a hook or doc instructs the model to file, and the model writes the row):

| producer | file:line | fires (14 d) | can the model discharge WITHOUT filing? |
|---|---|---|---|
| `dispatch-assert.sh` | **`:225`** (fresh) / `:191` (re-check), `MAX=2` `:54`, `MAX_TOTAL=6` `:55` | **131** | **No.** All four offered remedies write a record: (a) fire a pane, (b) `cc-backlog add --source "$SID"`, (c) add+block, (d) `cc-decide open`. **DROP is not an option**, and `discharged_since()` (`:147-156`) can only see a written artifact. Its stated escape is "close again" — i.e. eat another block. |
| `completion-assert.sh` D1 | reason `:1078`, predicate `:774` | 95 total fires | Only by rewriting the close to stop naming operator work. The remedy text names **filing alone**: *"File each operator-only step — `cc-backlog needs "<step>"` — then re-close"*. Discharge is `any(.[]; .session == $SID)` — a row with this session id must exist. |
| `completion-assert.sh` D4 | reason `:1079` | — | **Yes, and this text is already correct.** It carries *"FILING IS THE EXCEPTION, NOT A CO-EQUAL CHOICE — measured 2026-08-25, 432 of 526 live backlog rows (82.1%) exist because a session wrote something down instead of finishing or dropping it"* and offers DRIVEN/DROPPED/BLOCKED. |
| global `CLAUDE.md` § Three dispositions | `~/.claude/CLAUDE.md:793` | always resident | **Yes.** The FILED row already reads *"the EXCEPTION — it carries the burden of proof, and it is NOT co-equal with DRIVEN… Cannot answer all three ⇒ DROP IT."* |
| global `CLAUDE.md` operator-steps clause | `:801` *"Operator-owned steps are FILED, never prosed."* | always resident | This is the sentence that makes filing a **close requirement**, and it is the one `needs` obeys. |

**The asymmetry is the finding.** The *policy* layer (CLAUDE.md:793, completion-assert D4) was fixed
on 2026-08-25 to make DROP first-class. The two *mechanical* gates that actually block a stop —
`dispatch-assert:225` and `completion-assert:1078` — were not, and they fire **226 times in 14 days**
against 275 free-hand + 98 `needs` adds. The gates outrank the prose because the gate ends the turn.

---

## 4. THE THREE HOUSEKEEPING SCRIPTS

| script | effect on inflow | scheduled? |
|---|---|---|
| `scripts/backlog-ratchet.sh` | **None directly** — census only. Reports falsifier coverage (leading) + age-at-close median/p75 (lagging); `--assert` reds only on a *downward* move. Deliberately not a gate (`:26-30`: an always-firing alarm carries no bits). | Yes — `scripts/autonomy-sweep.sh:779,1129`, launchd `com.chrisren.autonomy-sweep` (**pid 99613, running**). Files ONE condition-keyed row on regression. |
| `scripts/backlog-grouping-sweep.sh` | **Reduces dispatch cost, not row count.** Links rows into condition groups so N rows cost 1 dispatch (`:9-15`: the pile is ~93-95% genuinely distinct, so row count is not shrinkable). Adds ≤1 row. | Yes — `autonomy-sweep.sh:780`. |
| `scripts/backlog-consolidation-trigger.sh` | **Detects** digit/sha-varying title clusters and files ONE row when a cluster crosses threshold. Adds ≤1 row. | Yes — `autonomy-sweep.sh:778`. |

All three are alive and all three are net-neutral-to-positive. None of them is the pump.

---

## 5. THE FIVE CHANGES, RANKED BY ROWS PREVENTED

### 5.1 `dispatch-assert.sh:225` — add DROP as a fifth, discharging option (≈120 rows/14d)

The gate that produces the largest live class (239 ad-hoc + 29 uuid rows) offers four remedies, all
of which write. Change the reason text to make DROP explicit and self-discharging:

- **Edit:** `hooks/dispatch-assert.sh:225`, insert before *"Then close normally"*:
  `(e) NOT WORTH DOING → say so in one line in your close ("dropping X: <why>") and close; a dropped item needs no record.`
  and add a fifth arm to `discharged_since()` (`:147`) that matches a drop-phrase in the turn text
  (`grep -iqE 'dropping|not worth|letting (this|that|it) go'` on `$TURN_TEXT`) — the same broad-
  matcher/fact-gate doctrine the file already uses at `:213`.
- **Also delete `--source "$SID"` from the (b) template.** That flag is what makes the id
  per-session and defeats title dedup: 579 of 764 sources used once. Replace with
  `--condition "<lowercase-hyphen-state>"` guidance, which is the only stable key `cmd_add` has.
- **Proof:** `jq 'select(.event=="add" and .ts>=<D>) | .source' | sort | uniq -c | awk '$1==1' | wc -l`
  — the used-once source count must fall below 40% of 14-day adds (today 133/166 = 80%).

### 5.2 `completion-assert.sh:1078` — make D1's remedy match D4's (≈40 rows/14d)

D4's text (`:1079`) already carries the three-disposition rule and the 82.1% measurement; D1's
(`:1078`) still says only "File each operator-only step". D1 produces the worst-draining class
(`needs`, 65.6% mature done-rate, 148 live, 1 falsifier, p90 age 31.8 d).

- **Edit:** `hooks/completion-assert.sh:1078` — prepend D4's gate sentence:
  *"An operator-only step is not an escape hatch from work you could have done: file it only if you genuinely cannot (credential / sudo / GUI / a value judgment). If you can run it, run it now."*
- **Evidence it is needed:** **68 of the 148 live non-re-land `needs` rows carry a `--run` command**,
  and the commands include `/ship`, `git worktree prune --dry-run`, `/compact-memory`,
  `bash ~/.../cloud-websetup-drive.sh --all`, `python3 .../emote-review.py --open` — things the
  filing agent could have executed. Separately, **195 rows in 30 days were filed and closed within
  the hour by a non-mechanical filer** (308 total minus 113 ship-land auto-retracts; 115 of the 308
  closed in **under 5 minutes**) — file-then-do, i.e. the row was pure ceremony.
- **Proof:** the `with_run` fraction of live `needs` rows falls, and the <1 h self-close count for
  non-`re-land` rows falls below 3/wk.

### 5.3 `scripts/ship-land.sh:1032` — store a DURABLE probe path (≈50 rows, biggest single win)

This is a real bug with a clean fix. The falsifier is stored as
`bash ${REPO_ROOT}/scripts/land-content-verify.sh <ref>`, and `REPO_ROOT` (`:698`) is
`git rev-parse --show-toplevel` — **the dying land's worktree**. When the worktree is reaped the
probe path vanishes.

Measured on the 48 live re-land rows that carry a probe: **43 exit 127** (`bash: no such file`);
5 exit 1. `bin/cc-premise:261-269` treats 126/127 as "the probe never ran" and **fails open**, so
those 43 rows can never self-retract — correctly, and forever. Sample:
`/Users/chrisren/Development/.worktrees/{r3-land,blockbrake-rootcause,foldfix-orphan}/scripts/land-content-verify.sh`.

Re-running the **same oracle from the durable checkout** against the same refs: **8 of 48 exit 0**
(content already on trunk ⇒ retract). And of the **15 probe-less rows** (the `falsify` rc≠0 arm at
`:1051`), reconstructing the ref from the `--run` field's `head pinned at <ref>` and running the
oracle gives **10 of 13 judgeable rows exit 0**. So **18 of 63 live re-land rows (28.6%) are moot
today** and none of them can say so.

- **Edit:** `scripts/ship-land.sh:1032` →
  `oracle="${HOME}/.claude/scripts/land-content-verify.sh"` with a fallback to `"$land_root/scripts/…"`
  (`land_root` is already resolved at `:995` as the durable checkout, *precisely because* the same
  worktree-ephemerality bug was already fixed for the `--project` label one line earlier — the fix
  stopped one line short).
- **Second edit, same block:** in the `frc≠0` arm (`:1049-1055`), fall back to storing the probe
  anyway using the durable path rather than leaving the row probe-less. 15 rows are probe-less today
  and 10 of them are moot.
- **Proof:** `for each live re-land row: bash -c "$falsifier"; echo $?` — the count of `127` must be
  **0** (today 43/48).

### 5.4 `bin/cc-backlog:1462` — require a falsifier OR a condition at `add` time (structural)

Coverage is 14.4% and *working* coverage is 7.3%. `backlog-ratchet.sh:26-30` explicitly declined to
gate on this in 2026-08 because "no generator emits one yet" — that premise is now stale: ship-land,
postland-verify, deploy-live and cc-discover all emit one. The remaining zero-coverage classes are
exactly the model-authored ones (free-hand 21/381; `needs` 1/148).

- **Edit:** `cmd_add` (`bin/cc-backlog:1480`, beside the `--title` required check) — WARN (not
  refuse) when `--falsifier`, `--condition` and `--dod-ref` are **all** absent, naming the p90 age
  (31.8 d for `needs`, 26.6 d for ad-hoc) and the three-part FILED test from CLAUDE.md:793. Keep it
  advisory: `cmd_needs:2974-2984` documents why a fabricated probe is worse than none, and that
  reasoning is right.
- **Then flip `backlog-ratchet.sh --assert` from "reds only on a downward move" to a floor** once
  coverage clears ~35%.
- **Proof:** falsifier coverage on rows filed *after* the change, measured by `backlog-ratchet.sh`,
  exceeds 35%; and the 127-rate on those probes stays 0.

### 5.5 `bin/cc-dispatch:2057` — widen the plan-open retractor to `claimed` (≈1 row, but free)

`plan-open` is the model to copy: **96.3% all-time done, 100% falsifier coverage**, retracted by two
independent arms on frontmatter flip. Its one live miss: row `a507762b0a0d`
(`docs/plans/STOP_CHAIN_WAVE2.md`, frontmatter `status: done`) is `status=claimed`, and the selector
at `:2057` (`select((.source//"") == "plan-open")`) is reached only on the open/blocked path.
Low value alone — listed because it is the **template** the re-land fix (5.3) should be written
against, and because it proves the pattern works when the probe path is durable.

---

## 6. MECHANICAL BULK-CLOSE — 22 candidate rows TODAY

Written to `inflow-closable.jsonl` (one `{id, class, evidence}` per row). **Nothing was closed.**

| class | count | verifiable check |
|---|---|---|
| `reland-content-already-on-trunk` | **18** | `bash scripts/land-content-verify.sh <ref> --no-fetch` exits 0 from the durable checkout. 8 from probe-bearing rows, 10 from probe-less rows whose ref was reconstructed from `--run`'s `head pinned at <ref>`. |
| `stored-falsifier-exits-zero` | 2 | the row's own stored probe re-run now exits 0 (`02d53c4b4078` drain-chain-assert, `c92cbba78fc2` postland-verify AUTO-REVERT). |
| `plan-open-plan-status-terminal` | 1 | `STOP_CHAIN_WAVE2.md` frontmatter `status: done`; row is `claimed` so `cc-dispatch:2057` misses it. |
| `exact-title-duplicate-excess` | 1 | 3 live groups / 7 rows / 4 excess; 3 of the 4 are already in class 1, leaving the reso-web-app `next.config` pair — keep the older id. |

**Classes deliberately NOT proposed:**
- The other **40 live re-land rows are REAL** — the oracle says their content is genuinely not on
  trunk (rc 1). Bulk-closing re-land as "probably moot" would strand real work; that was the
  2026-08-12 incident `ship-land.sh:1012-1014` records (24 of 25 false *in the other direction*).
- **25+ live rows whose `dodRef` file does not exist** in this checkout — almost all are cross-repo
  paths (`reso-management-app`, `doc_classifier`) resolving against the wrong root. Missing-here is
  not missing; not a safe class.
- The **51 dodref-clustered rows** are a *consolidation* surface (one dispatch instead of 12), not a
  close surface — `backlog-grouping-sweep.sh` already owns it.

---

## 7. ADVERSARIAL PASS — what a hostile reviewer gets right

1. **"You blamed inflow; the outflow broke."** Correct, and §0 leads with it. Claim→done is 2/23 in
   7 days. Every fix in §5 combined prevents ~200 rows/14 d; the drain failure is worth ~550.
2. **"Your 14-day done-rates are age-truncated."** They were. §1b re-runs the comparison on a fully
   aged cohort and it **reverses the naive read**: free-hand adds drain at 77%, `needs` at 66%, and
   the mechanical generators are the best in the store, not the worst.
3. **"Are re-land rows actually moot?"** Mostly **no** — 40 of 48 hold genuinely unlanded content.
   The defect is that the *self-retraction* is dead (43/48 probes exit 127), not that the rows lie.
   That flipped the recommendation from "bulk-close re-land" to "repair one path assignment".
4. **"Is `reopen` re-inflating?"** No. 57 reopens in 7 days, **1** with `--force`; the rest are claim
   releases. `unblock` moves blocked→open, which does not change the live count.
5. **"Are the housekeeping scripts inert?"** No — `com.chrisren.autonomy-sweep` is pid 99613 running
   and calls all three (`autonomy-sweep.sh:778-780`). `com.claude.discovery` (66510) and
   `com.claude.postland-verify` (44815) are running too.
6. **Unresolved.** I attribute the 239 ad-hoc free-hand rows to `dispatch-assert` by shape and rate
   (131 fires / 14 d, and its remedy text is the literal `--source "$SID"` form those rows carry),
   **not by a join** — `add` records carry no `by` field (all 108 7-day adds have `by: null`) and the
   IDL log records only `hook` + `sid`, never the id it caused. A joinable attribution would need
   `dispatch-assert` to stamp its `$SKEY` into the row it demands. That is the one measurement this
   report could not make.
