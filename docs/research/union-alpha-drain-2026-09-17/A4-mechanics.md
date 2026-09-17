# A4 — Anatomy of one drain link, and where free third-party tokens could plug in

Measured 2026-09-16/17 from live stores. Every number carries its command. Read-only; no edits, no fires.

---

## VERDICT

**THE CHOKEPOINT IS ELIGIBLE-ROW SUPPLY, AND FREE TOKENS DO NOT TOUCH IT.**

Measured live, this hour: `drain-pick.sh --project all --top 20` returns **`eligible=12 shown=12 thrash_held=17`**.
Twelve rows is the entire drainable queue for every lane on this box. Against that:

| Test of "tokens are the constraint" | Result |
|---|---|
| Did any drain link ever die on a quota/rate limit? | **0** occurrences of `hit your…limit` / `Claude AI usage limit reached` / `Overloaded` / `overloaded_error` across all 140 drain-lane transcripts |
| Did any link hit the ~60% context-fill stop its own brief names? | **0 of 33.** Median peak context **275,445** = 27.5% of a 1M window |
| Does spending more on a link close more rows? | **corr($, rows_closed) = −0.039**; **corr(turns, rows_closed) = −0.008** (n=24 links with attributed closures) |
| Is quota scarce? | `claude-accounts`: next3 at **7% weekly**, **~47pp forecast to strand and die at reset**. `accounts.json spend.usage_credits_authorized=false` — zero dollar exposure |
| Has a free-plan third-party backend ever been unavailable? | **No.** `~/.claude/providers.json` has had **2 routable non-Claude backends passing the cost gate since 2026-08-10** (Codex CLI, Pi·Codex, both on ChatGPT Plus, `bills_outside_plan:false`). **Zero drain work has ever been routed to either.** The experiment has effectively already run for five weeks and produced zero closures |

The binding constraint is upstream of any model: **308 of 346 live rows are `blocked`**, `cc-dispatch`
selects `status=="open"` only, and **0 of 308 blocked rows carry an impossibility class** on their
`block` record. A free token cannot unblock a row whose gate is *"OPERATOR VALUE CALL"*,
*"Press Enter in kitty pane 5"*, or *"blind-rank the 9 titos draws"*.

The one honest pro-free-tokens argument — *spend them manufacturing eligible work by triaging the
blocked pile* — is addressed in §5 and **still fails**, because the triage predicate is a shell
command against this box, not a text judgement.

---

## 1 · THE ANATOMY OF ONE LINK

Source: `scripts/drain-brief.template.md` (96 lines, hard-capped at 200 by `drain-brief.sh:ratchet`),
`scripts/drain-recycle-fire.sh:122-188` (closure report + goal), `scripts/drain-pick.sh`.

| # | Phase | What it consumes | Bound by |
|---|---|---|---|
| 0 | **Brief generation** — `drain-brief.sh` substitutes 11 placeholders into the tracked template, writes `fire-drain-<lane>-recycle<N>.txt` + a <400-byte pointer | pure `bash` string substitution, zero model tokens | **tool/IO** |
| 1 | **Fire + goal arm** — `drain-recycle-fire.sh --num N` composes the goal condition (`:188`, one 1,400-char sentence) and `exec`s `handoff-fire.sh --recycle --goal` | shell + one launcher | **tool/IO** |
| 2 | **Setup** — `cd` worktree, `git fetch`, compute `$ME`, export `CC_BACKLOG_LANE=local-drain`, print closure report | ~4 tool calls; **but turn 1 establishes a 128,070-token resident context** (median, n=33) before any work | **model-token (fixed overhead)** |
| 3 | **Pick** — `drain-pick.sh --top 8` prints a ranked table (tier 0 falsifier · 1 dodRef · 2 plain · 3 umbrella) | `jq` fold over the ledger | **tool/IO** |
| 4 | **Claim** — `cc-backlog claim <id> --by "$ME" --venue local` | ledger append + `kill -0` lease proof | **tool/IO** |
| 5 | **Adjudicate** — one of four verdicts | see verdict table below | **mixed** |
| 6 | **Gate** — `gate-select.sh --direct origin/main...HEAD`, then each named suite | `bats`/`pnpm`, foreground, minutes | **tool/IO** (model waits) |
| 7 | **Commit** — one commit per row, body `Backlog: <id>` | git | **tool/IO** |
| 8 | **Land** — `SHIP_LAND_SMOKE_BUDGET_S=420 ship-land.sh`, then verify BY CONTENT (`git ls-tree` + empty `git diff`) | git + the land rail; rc 11 = verifier in flight | **tool/IO** |
| 9 | **Close** — `cc-backlog done <id> --evidence "landed <sha> — …"` *after* the land | ledger append | **tool/IO** |
| 10 | **Closure report** — `--closure-report <since> --min <N>` prints `closed/closed_pre/closed_other/filed/net/blocked/floor=MET\|UNMET`; `floor=MET` ⟺ `closed_pre >= min` | `jq` over the ledger | **tool/IO** |
| 11 | **Journal** — ≤8-line entry into `docs/plans/BACKLOG_DRAIN_24_7.md` §2.1 (a **33,885-line** file), commit, land | model writes ~8 lines; reads a large file | **model-token** |
| 12 | **Ping** — `cc-notify --role drain-lead "HANDOFF-PING recycle #N — <closure line>"` | mailbox write | **tool/IO** |
| 13 | **Fire successor** — `drain-recycle-fire.sh --num N+1 … --account auto`; last action, nothing after it runs | shell `exec` | **tool/IO** |

**The four verdicts of phase 5 — this is where the whole question lives:**

| Verdict | What it actually is | Bound by |
|---|---|---|
| **MOOT** | run the row's falsifier, or `git show origin/main:<path> \| grep`, or `git diff origin/main <ref> -- <path>`; if the premise is gone, close with the command + its output as evidence | **tool/IO — the model is a shell wrapper.** ≤3 tool calls by brief mandate |
| **DOABLE** | a real code change: edit → gate → commit → land | **model-token-bound** (genuinely) |
| **OPERATOR-ONLY** | `cc-backlog block <id> --needs "<line>" [--run "<cmd>"]`, one turn | **human/decision-bound** |
| **TOO BIG** | first concrete step, commit, `reopen --by "$ME"` to release | model-token, truncated |

**Measured verdict mix on the two highest-yield links** (evidence strings, `closedSession` join):

- `53d951ed` — **17 rows, $12.43, 88 turns**. 14 of 17 are MOOT; **6 of those are literally
  `land-content-verify.sh <ref> --no-fetch` → rc 0**. The remaining 3 are "landed <sha>" cherry-picks.
- `d6b63f87` — **16 rows, $25.84, 162 turns**. 13 of 16 MOOT, every one a `git diff origin/main <ref> -- <path>`
  that showed trunk is a strict superset. Three real lands.
- Contrast `dfd512c4` — **6 rows, $98.83, 555 turns**: migrations, a decision packet, a version re-check. Real engineering.
- Contrast `7a4524e7` — **4 rows, $60.59, 310 turns**.

**The highest-yield closures are the ones with the least model in them.** A 22× spread in $/row
($0.73 vs $16.47) that is *uncorrelated with spend* is entirely explained by which rows the link drew.

---

## 2 · WHERE THE TIME AND THE TOKENS GO

Population: 33 drain-lane-infra sessions with ≥40 assistant turns, deduped by `message.id` across all
four config dirs. Cost is Opus-5-list-equivalence (`$0.50/MTok` cache read · `$6.25` cache write ·
`$25` output), the same basis as `docs/research/drain-pipeline-productivity-2026-09-16.md` §5.

**Per link (median):** 124 assistant turns · **26.7M cache-read tokens** · 128,070-token turn-1 context ·
**$17.39** · 6 rows closed. Wall clock ranges 42 min → 26 h (the long tail is idle-after-goal, not work).

### 2a · The cost is input, and the input is our own configuration

```
cache read  $587   81%
cache write  $71   10%
output       $64    9%
input:output ratio = 466:1   (1,185.8M in / 2.55M out across 33 links)
```

**60.3% of every input token a link pays is the turn-1 resident prefix, re-read on every turn**
(median across 33 links, computed as `t1_context × turns / total_cache_read`). Worked example,
session `db2dfaa2`:

```
turn   1  cache_read=  29,433  cache_create=110,480   out=125
turn   2  cache_read= 139,913  cache_create=  7,365
turn  60  cache_read= 242,009
turn 120  cache_read= 282,635
messages=127  total_cache_read=29,445,795
FLOOR: 139,913 × 127 = 17,768,951 = 60.3%
```

That 128K–140K prefix is `~/.claude/CLAUDE.md` + `~/.claude/rules/*` + the project CLAUDE.md + hooks +
skill roster + tool schemas + the brief. It is established **before the first tool call**
(`out=125` on turn 1) and is paid whether the turn does work or not. This reproduces
`docs/research/cloud-local-cost-ab-2026-08-11.md` §3's ~80K figure and shows it has grown ~60% since.

### 2b · Chain overhead is NOT where the money goes — the audit's narrative is stale

Token-weighted, attributing each turn's full cost to the phase its tool call belongs to:

```
rowwork    $578.8   80.2%
gate/land  $ 75.3   10.4%
chain      $ 53.2    7.4%     (brief-read + pick + closure-report + journal + notify + fire)
ledger     $ 14.2    2.0%
chain-overhead share per link: median 4.1%, min 0.6%, max 26.6%
positional: first-8-turns 6.2% | middle 82.6% | last-15-turns 11.3%
```

**Default-to-refute result.** `drain-brief.sh`'s own header and `DRAIN_CIRCUIT_2026-09-01` describe a
chain where "each recycle audits the recycle before it" — true of chain #1–#299 with its 3,366-line
self-derived brief. The **current** template-generated chain spends **4.1% median** on chain
ceremony. That defect is fixed. Do not budget against it.

Tool-call share (7,895 Bash calls over 60 links) agrees: `chain:*` = 12.3% of calls but 7.4% of tokens —
chain turns are *cheap* turns, because they happen early when the context is shallow.

### 2c · Throughput, cross-checked

My own join (`backlog.jsonl` `closedSession` → transcript) gives **$722 / 161 attributed closures =
$4.48/closure**, median **6 rows/link**. The audit's **$3.35/closure** and **5.5 rows/session** are the
same measurement on a slightly different denominator. **Both stand.** Caveat stated: 9 of 33 links
show 0 attributed closures despite journal entries claiming closures — `closedSession` is present on
only **656 of 3,467** `done` records fleet-wide, so the correlation in the VERDICT block runs on a
noisy denominator. The noise is not plausibly correlated with turn count, so the null survives, but
it is a null with n=24, not a proof of zero.

---

## 3 · SEPARABLE SUB-TASKS — what a tool-less LLM could in principle do

Criteria: (a) textual, (b) bounded, (c) verifiable by a cheap deterministic check.

| Candidate sub-task | Textual? | Verification available | Does the output still need a Claude session to APPLY? | Verdict |
|---|---|---|---|---|
| **Dedupe/cluster the ledger** | yes | title-stem + `dodRef` overlap; a diff a human can eyeball | yes — `cc-backlog` writes are local | **Already done and already retired.** `docs/research/…-2026-09-16.md` §10: duplicate pressure is **5.2%**, and the 20.3% title-stem figure was **withdrawn by its own author** as a template collapse. The `cwd`-derived-project dedup hole closed 2026-08-19. Nothing left to win |
| **Triage blocked rows into the 4 impossibility classes** | **no** | the classes are `needs-credential` · `needs-human` · `not-yet-true` · `no-capacity`; deciding between the last two requires *running the premise probe* | yes | **FAILS (b)+(c).** See §5 |
| **Draft falsifier commands for the 91% of blocked rows that lack one** | partially | a falsifier is only valid if it *runs here and discriminates*; an undiscriminating falsifier is worse than none (`liveness-proxy-cannot-be-output-age`) | yes, plus a run | **Marginal.** Could draft candidates; every one needs a local execution + a discrimination check before it may be stored |
| **Summarise / compress the §2.1 journal** | yes | line count | no (a human/script could apply) | **Real but worth 3.4% of calls / ~0% of the problem** |
| **Propose closure candidates from evidence text** | yes | re-run the cited command | yes | **Redundant** — `cc-premise` already does this deterministically (below) |
| **Adjudicate the `re-land` class (7 of today's 12 eligible rows)** | **no** | `land-content-verify.sh <ref>` → rc 0 | — | **NEEDS NO LLM AT ALL.** See below |

### 3a · The load-bearing finding of §3

**Every falsifier on every live row is a shell command against this box.** All 19 of them:

```
live rows carrying a falsifier: 19   (of 346 live = 5.5%)
  [open] 0f0c1a0cf356 :: bash …/scripts/land-content-verify.sh refs/land/failed/20260911T055004Z-…
  [open] 284a211e9a83 :: bash …/scripts/land-content-verify.sh refs/land/failed/20260916T220556Z-…
  [open] ff47b427e83c :: bash …/scripts/land-content-verify.sh refs/land/failed/20260917T033409Z-…
  [open] b14c62d8c878 :: bash …/scripts/land-content-verify.sh refs/land/failed/20260917T014216Z-…
  [open] 78e8987b1306 :: bash …/scripts/land-content-verify.sh refs/land/failed/20260917T024939Z-…
  [open] 2a65b9bf722d :: bash …/scripts/propose-goal-flag-watch.sh --falsify
  [blocked] 159c2211b0f2 :: grep -q watchdog.env hooks/lead-crash-watchdog.sh
  [blocked] c2403968cbf0 :: bats tests/memory-index-drain.bats 2>&1 | grep -q '^not ok 10'
  …13 more, all grep/jq/bats/git against this repo
```

**5 of the 7 open falsifier-bearing rows are one `land-content-verify.sh` invocation each** — the
exact class that produced the single most productive link in chain history (17 rows for $12.43).
**That class requires zero model tokens.** The deterministic runner already exists:
`bin/cc-premise sweep --record --close-falsified N`, wired at `scripts/autonomy-sweep.sh:1488`,
which "retires rows a probe just proved dead."

**And it is starved.** `~/.claude/autonomy/premise-pass.stamp` is **0 bytes, mtime 2026-09-16 22:07**
— and `autonomy-sweep.sh:1375` documents that the arm **claims the stamp BEFORE the pass runs**,
precisely so a run killed by the bound is visible. A fresh, empty stamp is the signature of *fired
and killed*, not *completed*. `cc-premise sweep --json --limit 20` run by hand here exceeded 110 s and
produced no output. Its best-ever recorded run validated 43 rows and closed **5 — the cap, not the
population** (`autonomy-sweep.sh:1493`).

> ⚠️ **Correction to the audit, from live re-measurement.** §10 of `drain-pipeline-productivity-2026-09-16.md`
> says "`premise-pass.stamp` is 9 days old (~36 missed 6h passes)". It is **2.5 hours old** as of this
> read. The *effect* the audit names is unchanged and arguably worse: the arm is firing and dying
> inside its bound, so its silence is not absence of runs.

**So the single highest-yield closure class in the pipeline is already machine-decidable, already has
a shipped runner, and that runner is capped at 5 closures/pass and cannot finish inside its time
bound.** That is a scheduling defect worth more than any token supply.

---

## 4 · THE CHOKEPOINT — testing the audit's claim

> *"Rows-per-session is the only lever that has ever mattered — not venue, not model, not quota."*

**The claim holds as stated, and it is incomplete in a way that matters.**

**What holds.** Cost per closure is a near-fixed session cost divided by rows closed (§2c), and venue
/ model / quota move the numerator by ≤±6% while rows-per-session moves the denominator 3×
(5.5 vs 1.5) and within the lane 6× (2 → 17 rows/link). My independent correlations confirm the
numerator is inert: **corr($, rows) = −0.039**.

**What it omits — the second-order limiter, which is the real one.** Rows-per-session is not a dial
the pipeline can turn. It is **set by the eligible queue's composition**, and the queue is:

| | count | source |
|---|---|---|
| live rows | **346** | my fold of `backlog.jsonl` (21,025 records, **0 unparsed**) |
| `blocked` | **308 (89%)** | structurally invisible — `cc-dispatch` selects `status=="open"` (`bin/cc-dispatch:1921`) |
| `open` | **37** | |
| **eligible to a drain link right now** | **12** | live `drain-pick.sh --project all`, after the thrash ceiling |
| held at ≥5 claims (thrash) | **17** | same run |

**The second-order limiter is the `open`→`blocked` valve, and it is measurably one-way:**

- **0 of 308** blocked rows carry an impossibility class prefix on their `block` record. `block --needs`
  validates only non-emptiness; the four-class gate lives on `add --why-not-now`
  (`bin/cc-backlog:1120-1132`). *(The audit says 94.9%; my stricter literal-prefix test says 100%.
  Direction identical.)*
- **72% of the 251 rows born since the lane died (09-10) were never claimed by any worker.**
- Claim thrash is the signature of more workers than work: **194 rows claimed ≥5 times, 66 claimed ≥8,
  one claimed 55 times.** Adding capacity against a 12-row queue produces re-claims, not closures.
- `drain-recycle-fire.sh:330` already encodes this: it **refuses to fire** a lane whose project is
  "STRUCTURALLY EMPTY: eligible=0", because a successor there is "a guaranteed floor=UNMET that
  closes nothing." The pipeline's own code names supply as the terminating condition.

**Third-order, and cheapest of all to fix:** the local lane **has no scheduler** — no plist, no cron,
no caller in `autonomy-sweep.sh`. It runs only when a session fires it by hand (audit §4.1, and I
confirm: no `com.claude.drain*` in `~/Library/LaunchAgents/`). The most cost-effective worker on the
box is the only one that cannot start itself.

---

## 5 · THE HONEST ANSWER — "would more tokens from a different vendor increase closures?"

### The case FOR (steelmanned, and it is not silly)

1. **Cost structure is 81% input, and 60% of that is re-reading our own config.** A vendor whose
   tokens are free makes the dominant cost term free. $722 across 33 links is not nothing.
2. **The blocked pile is the biggest single reservoir** — 308 rows, ~28% of which the audit
   hand-judged as "agent work wearing a park" (honest band 40–135 rows). Triaging it is *textual*
   work against *stored text*, which is exactly what a tool-less model is good at. If free tokens
   could convert even 80 blocked rows to open, they would **7× the eligible queue** — attacking the
   measured chokepoint head-on, not the inert numerator.
3. **Free tokens are non-rival.** They consume no Claude quota, no pane, no worktree, no `load1`.
   Even a low hit-rate is free upside if the output is verified before it is applied.
4. **Decorrelation has value in principle** — a different family may see what ours does not.

### The case AGAINST (measured)

1. **Tokens have never once been the binding constraint.** Zero limit-deaths in 140 transcripts.
   Zero links reaching their own 60%-context stop (median peak 27.5% of window). **corr($, rows) ≈ 0.**
   A link that spent 8× more ($98.83, 555 turns) closed **fewer** rows than one that spent $12.43.
2. **The experiment has already run.** Two non-Claude backends have passed the `providers.json` cost
   gate and been routable since 2026-08-10 (`Codex CLI`, `Pi·Codex`, both `bills_outside_plan:false`
   on a ChatGPT Plus plan already held). Closures attributable to them: **zero**. `grep -rn codex
   scripts/drain-*.sh bin/cc-backlog` → **no hits.** The marginal free token has been available and
   unspent, which is what a non-binding constraint looks like.
3. **Quota — the currency this fleet actually pays in — is in surplus and decaying.** Live
   `claude-accounts`: next3 at **7% weekly with ~47pp forecast to strand and die at reset**, and the
   audit measured **3.19 account-weeks expired unused** in 30 days while the actionable backlog was
   47 rows. Adding a second free supply to an unspent first supply changes nothing. Dollars are not a
   currency here at all: `accounts.json spend.usage_credits_authorized=false`.
4. **The steelman's own premise fails on inspection of the rows.** A 12-row random sample of the
   blocked pile:
   ```
   0a9db99fee41 :: OPERATOR VALUE CALL — is local postgres used at all? …
   724a2d2682d5 :: rule on heat-v2/b size: 487 net LOC vs the brief's 400 hard cap …
   71bd004cc416 :: Decide the bs-splash exit-splash rule: carry-vs-wipe …
   1d703721515f :: Press Enter in kitty pane 5 to submit the staged ./autoformat STOP …
   9381bf26d754 :: OPERATOR RULING BY EYE (a value judgment about whether a beat reads) …
   b97c7e92aa03 :: blind-rank the 9 titos draws in the bottle review UI …
   4a4b97a2585e :: OPERATOR (C10: loads a LaunchAgent) — run migration 0004 …
   2a0121060753 :: run staged migration 0014 …
   ```
   These are **`needs-human` by construction** — value calls, physical keystrokes, staged migrations
   the operator owns. A third-party model cannot make a call that is the operator's *by definition*,
   and it must not: the machine already refuses to let an agent script its own authorization.
   The sub-population that *is* agent work is identified by **running the row's premise probe** — and
   §3a shows every stored probe is a `grep`/`bats`/`git`/`land-content-verify` against this box.
   **The triage predicate is a shell command, not a text judgement.** A tool-less model can produce a
   *guess* about it; a guess that must be locally verified before use has moved the work, not done it.
5. **The one prior head-to-head on this corpus says the findings are contained.**
   `docs/research/codex-probe-w3-verdict-2026-08-11.md`: 36 anchored ground-truth defects, 4 blind
   mixed-vendor judges, per-(judge,brief) label permutation. **Codex-only coverage = 0 at every vote
   threshold including the union ceiling**; the Claude family caught 3 the Codex arms did not. The
   biggest available decorrelation gain came from a model *already in our ladder*. **Stated limit:**
   that probe scored the *adversarial research* slot, not row adjudication, and its corpus was drawn
   from defects a Claude model already missed — so it does not settle every slot. It does refute
   "a different vendor sees what ours cannot" as a free prior on this repo.
6. **Even a perfect free triage still terminates in a Claude session.** Every converted row's actual
   work is repo-local: edit → `gate-select.sh` → `ship-land.sh` → content-verified close. Free tokens
   would produce a *longer queue for the same lane* — which is worth something, but only if the lane
   is running, and the lane **has no scheduler and last closed a row on 2026-09-09**.

### LANDING ON ONE

**No. More tokens from a different vendor would not increase closures, and the reason is not vendor
quality — it is that the pipeline has not been token-limited for a single measured hour of its life.**

The ordered list of what *would* increase closures, each attacking a measured constraint, none of
which costs a token:

| | Fix | Constraint it attacks | Evidence |
|---|---|---|---|
| 1 | **Give the local lane a scheduler** (a plist; it is the only worker that cannot start itself) | uptime — the lane is operator-paced, last closure 2026-09-09 | no `com.claude.drain*` in `~/Library/LaunchAgents/`; audit §4.1 |
| 2 | **Un-starve `cc-premise sweep` and raise `--close-falsified`** — move the 900 s arm above the 400 s self-bound, or shard it | the highest-yield closure class, **free of model tokens** | stamp 0-byte/fresh (claimed-before-run); best run closed 5 = the cap; 5 of 7 open falsifier rows are one `land-content-verify` call each |
| 3 | **Make `block --needs` as strict as `add --why-not-now`** | the one-way valve: 308 blocked, **0 with an impossibility class**, 89% of the pile invisible to every lane | `bin/cc-backlog:1120-1132` vs `cmd_transition` |
| 4 | **Cut the `re-land` generator** | 607 lifetime rows, 7 of today's 12 eligible; its closures are ~100% no-op auto-retracts | my fold: `re-land 607 · advance 472 · post-land 200 · substantive 2,303` |

If free third-party tokens are to be spent at all, spend them **off this pipeline** — on work whose
constraint genuinely is token supply. Spending them here funds a queue that is 12 rows deep and a
worker that is not running.

---

## 6 · Relayed verbatim — `claude-accounts --readout`, 2026-09-17T04:40Z

Reproduced in full because it is the rendered artifact behind the quota claims above.

| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 0 | 0% | — | 94% | 7% | Sat 22:59 (in 2d 23h) | Tue Oct 13 01:19 (in 26d 1h) |
| next4 ← you | 14 | 14% | Thu 02:00 (in 2.4h) | 42% | 13% | Sun 04:00 (in 3d 4h) | Thu Oct 08 05:42 (in 21d 6h) |
| **next3** ➤ | 2 | 2% | Thu 01:00 (in 1.4h) | 7% | 0% | Tue 07:00 (in 5d 7h) | Thu Oct 01 14:39 (in 14d 15h) |
| next2 | 1 | 66% | Thu 00:40 (in 1.0h) | 100% | 76% | Sat 06:00 (in 2d 6h) | Mon 03:07 (in 4d 3h) |

- ○ `next2` — weekly **LIMITED** (100%)

```
➤ desk (bare `claude`) → next3 — earliest weekly reset among 5h-safe accounts · weekly ↻ 5d 7h · 5h 2% · safe set
➤ general → next3 · ➤ fable → next3
weekly drain — pp that DIE at reset (K=0.203 live · nowcast at the last 48h of pace):
  next3 strand ~47pp of 93 · p76 of its own 24h burns · start by T−29h (99h slack) · 5d left
  next   no strand — on pace to fill the window · 2d left
  next4  no strand — on pace to fill the window · 3d left
  next2  no strand — on pace to fill the window · 2d left
Fable window: permanent (no expiry).
```

**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |

- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)

**Read this against the offer.** A "union-alpha" free-token supply arrives at a box that already has
two routable non-Claude backends passing the cost gate, an unspent 47pp of weekly Claude quota
decaying to zero in 5 days, and a 12-row eligible queue. `providers.json`'s own `_the_cost_rule`
also binds any new entrant: *"ASK WHAT IT BILLS, NOT WHAT IT CAN LOG INTO"* — a free tier's billing
answer must be measured, and `UNKNOWN` is documented and **SKIPPED**, never wired.

---

## 7 · ADVERSARIAL PASS — what I checked because a hostile reviewer would

| Challenge | Check run | Outcome |
|---|---|---|
| *"You measured a dead lane; a running lane sees more rows."* | inflow since lane death (09-10): **251 adds / 252 blocks / 255 dones** — near-perfectly balanced | The eligible pool is in **steady state at ~12–47**, not drained-and-refilling. Rows arrive at ~36/day and ~36/day route to `blocked`. Challenge **refuted** |
| *"Chain overhead is the real waste."* | token-weighted phase split | **7.4% total, 4.1% median per link.** The 3,366-line-brief pathology is fixed. Challenge **refuted** — and the plan docs that still assert it are stale |
| *"Context, not row supply, ends a link."* | peak context per link vs the brief's own ~60% stop | **0 of 33** links reached it; median peak 27.5% of a 1M window. Challenge **refuted** |
| *"Parallelism would raise throughput."* | claims-per-row distribution | **194 rows claimed ≥5×, one 55×.** Parallelism already exceeded supply and converted into thrash. Challenge **refuted** |
| *"A cheap model could triage the blocked pile."* | 12-row random sample + all 19 live falsifiers | Most are operator value calls / physical steps; every stored premise probe is a local shell command. Challenge **partially survives** — a drafting role exists, but the verdict needs a local run |
| *"Vendor decorrelation is free upside."* | `codex-probe-w3-verdict-2026-08-11.md` | **0 unique coverage at every vote threshold** on this repo's own corpus. Limit stated: different slot, tilted corpus |
| *"Your correlation is on a noisy denominator."* | `closedSession` coverage | **Conceded.** 656 of 3,467 `done` records carry it; 9 of 33 links attribute 0 despite journal claims. The null is n=24 and is corroborated by the independent zero-limit-deaths and zero-context-stops results, not carried alone |
| *"The audit says the premise pass is 9 days dead."* | live stamp | **Audit is wrong on the fact, right on the effect**: stamp is 2.5 h old and 0 bytes, and the arm claims the stamp before running |

---

## 8 · What this does not cover

- **`lane` attribution begins 2026-08-23**; 2,462 of 3,467 `done` records carry no lane. Lifetime
  local-drain output is a lower bound, as the audit also states.
- **The reso lane** (`wt-drain-lane-reso`, 134 transcripts across four config dirs) was **not**
  measured here — this analysis is the infra lane only. Its project rail differs (`land-status.sh`
  first, `/ship` free, never `/deploy`), so its land-phase cost may differ.
- **Cost is list-price equivalence, not a bill.** This fleet has zero dollar exposure; the figures
  are a common unit for comparing lanes, exactly as the audit uses them.
- **`cc-premise sweep` could not be made to produce output inside 110 s here**, so its current
  falsified-row count is not independently re-measured — only the stamp's shape is.
- **Wall-clock per link is unusable as a work measure**: the range is 42 min → 26 h because a link
  that has fired its successor sits idle under its goal. Turn count and token count are the honest
  units.

---

*Commands reproduced in `/private/tmp/…/57c0d094…/scratchpad/{drain_anat,floor,join,tokphase,fill,phase}.py`.
Stores read: `~/.claude/autonomy/backlog.jsonl` (21,025 records, 0 unparsed), 140 drain-lane transcripts
deduped by `message.id` across four config dirs, `~/.claude/providers.json`, `~/.claude/accounts.json`,
`~/Library/LaunchAgents/`, live `drain-pick.sh` / `drain-chain-assert.sh` / `claude-accounts --readout`.*
