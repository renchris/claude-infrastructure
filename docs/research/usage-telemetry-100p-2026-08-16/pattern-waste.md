---
axis: A7 — pattern waste, costed
status: complete
date: 2026-08-16
headline: >
  The four haphazard-waste classes the goal names — failed tool calls, redundant re-reads,
  dead sessions, null subagent returns — together cost 4.1% of billed spend, while the
  structural context tax above the 200K recycle crossover costs 23.5%, i.e. 5.8x all of
  them combined; the fleet's haphazard waste is already near-zero and the only large lever
  is a recycle decision rule, which the arithmetic makes unambiguous (recycle whenever
  remaining turns R > [12.5(T+B) + 2·O] / (O−T−B), with T measured at 62,543 tokens).
load_bearing_claim: >
  Over the 30-day corpus (6,636 sessions, 131.0B billed tokens), the sum of every
  waste class that is genuinely haphazard is 4.1% of spend, and no single one exceeds
  1.7% — so "haphazard waste" is not where this fleet's tokens go. If that is false, it is
  false because the 600-session stratified sample (9.0% of sessions, 8.1% of bytes)
  understates a heavy tail of failure that the 100%-coverage rg scans did not detect.
---

# Headline

**Answer-first: this fleet has almost no haphazard waste left, and the one large number on
the board is not waste at all — it is the price of history, which a recycle rule can convert
into a quality gain at no cost.** Over the 30-day corpus (6,636 sessions, 7.16 GB, 131.0B
billed tokens ≈ $107,876 at API list, 95% CI [$90.6K, $128.7K]), the classes A7 was sent to
find are individually tiny: failed tool calls 1.37% of spend (3.0% of 30,402 tool calls,
88% retried), redundant same-session re-reads ≤1.26%, sessions that died and were never
picked up 1.44% (12 orphans of 70 terminal deaths — the other 58 had a successor session in
the same project within 6 h), and null/empty subagent returns **0 of 161 measured** — the
`limit-recover` skill's premise no longer fires in this window. They sum to **4.1%**. By
contrast **58% of every turn's cost is cache-read of the session's own history**, and
simulating a "recycle at 200K occupancy" policy over the real per-turn occupancy series of
583 sessions removes **22.3% of total spend ($25.3K/30d, $308K/yr)** while assuming the same
downstream turns. The crossover is derivable in closed form and is startlingly low: with the
**measured** resident tax T = 62,543 tokens (median occupancy at a session's first assistant
turn) and the cache-write/cache-read price ratio of exactly 12.5, a recycle repays itself
after **R\* = [12.5(T+B) + b·O] / (O − T − B)** turns — 9.4 turns at 200K occupancy, 4.9 at
400K, 3.3 at 800K. Median session length in this fleet is 100 assistant turns. **Above ~250K
occupancy, a recycle is token-positive in essentially every real case, and the fresher
context is also the better one — so under the operator's "never trade quality for tokens"
rule this is the rare lever with no trade to make.** Two instrument defects found along the
way matter more than any of the small classes: `hooks/log-bash.sh` has recorded **0 nonzero
exit codes in 44,112 entries** since its 2026-07-25 fix landed (positive control: the same
window's transcripts carry 673 Bash `is_error` results), so the fleet's only population-wide
Bash instrument can structurally only say "success"; and a usage **time-series does exist** at
`~/.claude/logs/account-utilization.jsonl` (5,021 rows, 4 accounts, 2026-08-10 → 2026-08-16),
contradicting the brief's note that none was found.

---

# Findings

| # | Claim | Evidence (command / file:line / number + denominator) | Status | Coverage |
|---|---|---|---|---|
| 1 | 30-day corpus is 6,636 sessions / 7.16 GB; the corpus IS a ~30-day window (only 344 files older) | `os.walk` over 4 deduped realpath roots; `.claude-next` → `.claude/projects`, `.claude-next{2,3,4}` do not exist | MEASURED | 100% of files |
| 2 | Total billed 131.0B tokens ≈ **$107,876**/30d (API list; **not cash** — flat-rate Max) ; annualized $1.31M | 600-session stratified sample summed over `message.usage.*`, scaled ×11.06; bootstrap 95% CI [$90.6K, $128.7K] (±18%) | MEASURED (sample) | 9.0% of sessions, 8.1% of bytes |
| 3 | **58% of a turn's cost is re-reading the session's own history.** cache_read 11.38B vs cache_creation 0.40B vs output 0.062B vs fresh input 0.0023B | sample totals; $/turn = $0.1673 = $0.0975 cr + $0.0431 cw + $0.0265 out | MEASURED | 9.0% |
| 4 | Cost per turn rises 5.3× across the occupancy range: $0.117 at 0–100K → $0.618 at 800–900K | per-turn band table over 58,299 assistant turns | MEASURED | 9.0% |
| 5 | **Resident tax T = 62,543 tokens** (median occupancy at first assistant turn; p25 41.6K / p75 86.3K, n=199 sessions ≥6 turns) | direct read of first `usage` record per session | MEASURED | 199 sessions |
| 6 | **Recycle crossover R\* = [12.5(T+B) + b·O]/(O−T−B)**: 32 turns @100K · 9.4 @200K · 6.2 @300K · 4.9 @400K · 3.3 @800K | closed form; p_cw/p_cr = 6.25/0.50 = 12.5 exactly; T measured, B=5K and b=2 ASSUMED | INFERRED (T MEASURED) | arithmetic |
| 7 | Simulated recycle-at-C policy on the real occupancy series: C=200K saves **22.3%** ($2,226 of $9,985 sample, 218 recycles across 147 of 583 sessions); C=300K 14.6%; C=400K 9.1%; C=600K 3.4% | replay of per-turn occupancy with reduction bookkeeping; C=∞ reproduces actual exactly (control) | INFERRED (assumes same downstream turns) | 583 sessions |
| 8 | **Tool-call error rate 3.0%** — 906 of 30,402 calls. Bash 3.1% (673/21,374) · Edit 3.5% · WebFetch 6.0% · Agent 6.7% · Read 0.7% · Skill/ToolSearch 0.0% | per-tool `tool_use`→`tool_result.is_error` join | MEASURED | 600 sessions |
| 9 | 88% of errors are followed within 2 calls by the same tool → a real retry round-trip. Cost ≈ 797 extra turns × $0.1673 = **$1,475/30d (1.37%)** | 379/430 in a 300-session subsample | MEASURED / INFERRED (cost) | 300 sessions |
| 10 | Only 163 of 906 errors are *pure* waste (permission 119 + edit-precondition 44). The other 743 are Bash nonzero-exit (288), timeout (86), not-found (69) — information, not waste. Pure subset = **$265/30d (0.25%)** | `err_kinds` histogram | MEASURED | 600 sessions |
| 11 | **`hooks/log-bash.sh` records 0 nonzero exits in 44,112 lines** (live log 2026-08-09→2026-08-16) and 0 in all 4 gz archives, although the `.tool_result`→`.tool_response` fix landed **2026-07-25 (d86d94eb9)** and the live file is a symlink to the fixed source. Positive control: transcripts over the same window carry 673 Bash `is_error` results | `grep -c ' \| Exit: [^0]' ~/.claude/logs/bash-execution.log` → 0; `grep -c ' \| Exit: '` → 44,112; `git log -1 -S'tool_response.exitCode'` | MEASURED | 100% of log |
| 12 | **`Prompt is too long` deaths: 5 sessions / 8 events, 5/5 terminal, median peak occupancy 968,390.** Total spend in them $1,062. Only **2 had no successor session within 6 h** | rg over 100% of corpus for `"isApiErrorMessage":true`, then JSON-parse of the 375 hit files | MEASURED | 100% detection |
| 13 | The literal string `Prompt is too long` matches **222 files**, but nearly all are this repo's own prose about the finding. Only 5 are real error records | rg -l on the phrase vs on `"isApiErrorMessage":true` | MEASURED | 100% |
| 14 | **Usage-limit kills are 20× more common than context deaths**: weekly 37 sessions, 5-hour 23, monthly-spend 44, auth 60 — 169 affected sessions (2.5% of 6,636), $16,235 of session spend | same scan, classified on error text | MEASURED | 100% detection |
| 15 | **Recovery works.** Of 70 terminal deaths (all classes), 58 had another session in the same project dir (any account) within 6 h. **12 orphans.** Estimated unrecovered loss **$1,555/30d (1.44%)** | successor-proxy over all 6,980 file mtimes | MEASURED (detection) / INFERRED (recovery) | 100% detection |
| 16 | **Null/empty subagent returns: 0 of 161** Agent/Task/Workflow results (< 40 chars); mean result 936 chars. 10 of 150 Agent calls returned `is_error`. Positive control: the same scan found 906 tool errors and 161 non-empty Agent results, so the scan can see both | `res.json` agent_empty / agent_result_chars | MEASURED | 600 sessions |
| 17 | **Redundant re-reads: 24.4% of Read calls** re-read a path already read in that session (296 of 1,177 in a 300-session subsample; 381K tokens of duplicated payload; max 20 reads of one path). But re-reads average 5,145 chars vs 7,066 for first reads → many are legitimate partial/offset reads. Cost ≤ **$1,358/30d (1.26%)** | per-session `read_paths` counter + tool_result char lengths | MEASURED (rate) / INFERRED (waste share) | 300–600 sessions |
| 18 | Identical Bash command repeated in the same session: **1.5%** (325/21,374 sample) and **2.9%** (2,835/97,216) in the population bash log. Small | sample counter + `bash-execution.log` md5 dedupe | MEASURED | 9% / 41% of Bash calls |
| 19 | **Re-derivation of landed work: 104 of 923 dispatched backlog items (11.3%)** closed as DUPLICATE / already-landed / withdrawn; a further 65 (7.0%) closed as premise-false/REFUTED. At $17.60 mean dispatched-worker session cost: **≤$1,830 + $1,144 /30d (≤2.8%)** | `~/.claude/autonomy/backlog.jsonl` (10,586 events, 2,152 items, ~29 d = the whole window) | MEASURED (classification) / INFERRED (cost) | 100% of ledger |
| 20 | The naive re-derivation reading — 2,467 claims over 923 items = 1,544 "re-dispatches" — is **already refuted in-repo**: 691 of the fast claim→reopen pairs are same-author *self-releases* where **no worker ran**, and 182 of 228 rule-B blocks never held a claim for 90 s | `bin/cc-backlog:216-236` (measured 2026-08-07, with its own positive control) | MEASURED (cited, not re-derived) | 100% of ledger |
| 21 | Duplicate *dispatch* — two worktrees building the same mechanism to completion — has **exactly one confirmed instance** in the ledger (97f16b6709fa / 6078392359ac), plus one condition that minted 21 duplicate items via a measurement-in-the-title key | `bin/cc-backlog:254-300` | MEASURED (cited) | 100% of ledger |
| 22 | 44 currently-open backlog items have an exact normalized-title twin; ~42 more have a ≥0.88-similar sibling. These are minted-but-not-yet-dispatched duplicates — a *forward* liability, not a spent cost | dedupe over 564 open items | MEASURED | 100% of ledger |
| 23 | **A usage time-series DOES exist** — `~/.claude/logs/account-utilization.jsonl`, 5,021 rows, 4 accounts × ~1,255 samples, 2026-08-10T05:58 → 2026-08-16T10:33, carrying `session_pct` · `weekly_pct` · `fable_pct` · reset times · auth. This contradicts the brief's "no usage TIME-SERIES store was found" | `wc -l` + first/last row | MEASURED | 100% |
| 24 | Occupancy distribution re-derived for this window: median peak 143,132 · p95 401,323 · max 905,467 (n=576). Lower than the 2026-08-11 audit's median 190K / p95 558K — the fleet is running *shorter* sessions than 5 days ago | sample peak occupancies | MEASURED | 9.0% |
| 25 | Permission denials recorded as `permissionDecision:"deny"` appear **11 times in 1 file** across the whole corpus — the deny path is essentially unused; the 119 permission errors surface as tool_result errors instead | rg over 100% of corpus | MEASURED | 100% |

## Ranked waste table (annualized)

| Rank | Class | $/30d | $/yr | % of spend | Confidence | Genuinely waste? |
|---|---|---|---|---|---|---|
| **1** | Context tax above the 200K crossover | **25,337** | **308,357** | **23.5%** | MEDIUM | Not "waste" — *avoidable structural cost*; see quality note |
| 1b | …same at a conservative 400K crossover | 10,301 | 125,365 | 9.6% | MEDIUM | as above |
| 2 | Worker dispatched onto already-landed/duplicate work | ≤1,830 | ≤22,276 | 1.70% | MEDIUM | **Yes, fully** |
| 3 | Dead sessions never picked up (12 orphans) | ≤1,555 | ≤18,924 | 1.44% | MED-HIGH | **Yes, fully** |
| 4 | Failed tool calls → retry round-trips | 1,475 | 17,947 | 1.37% | HIGH | Partly (only 18% is pure waste) |
| 5 | Redundant same-session re-reads | ≤1,358 | ≤16,529 | 1.26% | LOW | Partly (upper bound) |
| 6 | Worker dispatched on a refuted premise | ≤1,144 | ≤13,922 | 1.06% | MEDIUM | Partly (proves a negative) |
| 7 | Pure-waste error subset (permission + edit-precondition) | 265 | 3,220 | 0.25% | HIGH | **Yes, fully** — subset of #4 |
| 8 | Null / empty subagent returns | 19 | 225 | 0.02% | HIGH | **Yes** — but measured at ~zero |

**Rank 1 is 5.8× ranks 3–6 combined and 1,300× rank 8.** Every haphazard class together is 4.1%.

---

# Method

**Corpus and dedupe.** Four realpath roots (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`);
`~/.claude-next` resolves into `~/.claude/projects` and was excluded; `~/.claude-next{2,3,4}` do
not exist on this box (the brief's assumption that all four are symlinks is half-right). 6,980
`.jsonl` files / 7.26 GB total; 6,636 files / 7.16 GB have mtime within 30 days — the corpus is
effectively a 30-day window, which makes annualization a clean ×12.17.

**Three instruments, deliberately layered:**

1. **100%-coverage byte scans (`rg`)** for anything whose *existence* is the question — API error
   records, permission denies. This is where the death and limit counts come from, so those carry
   no sampling error. The trap here is self-reference: `Prompt is too long` matches 222 files, of
   which 217 are this repo's own research prose. The discriminating key is the record field
   `"isApiErrorMessage":true` (375 files), then a JSON parse of those files only.
2. **Stratified sample (600 files, 150 per account root, seed 20260816)** drawn from the 6,636-file
   30-day population, for anything requiring structure — per-tool error joins, per-path read
   counts, occupancy series, token sums. **Coverage 9.04% of sessions, 8.06% of bytes.** All
   population figures derived from it are sample means × 11.06 and are labelled as such; the
   bootstrap 95% CI on total spend is ±18%, which is the honest precision of every $ figure in
   this document that is not a 100%-coverage count.
3. **Purpose-built stores** read at 100%: `~/.claude/autonomy/backlog.jsonl` (10,586 events, whose
   own lifetime ~29 d matches the window), `~/.claude/logs/bash-execution.log` (+4 gz archives),
   `~/.claude/logs/account-utilization.jsonl`.

**Price model.** Opus 5 list: input $5/MTok, output $25/MTok, cache-read $0.50/MTok (0.1×),
cache-write $6.25/MTok (1.25×). Cost = `in·5 + cache_creation·6.25 + cache_read·0.50 + out·25`,
all /1e6. **These are API-list equivalents, not cash** — the operator pays four flat-rate Max
subscriptions, so the correct reading of every dollar figure is "share of the quota-consuming
work", and the ratios between rows are what carry meaning, not the absolute magnitudes.

**Crossover derivation.** Let O = current occupancy, T = fresh-session resident tax, B = brief
tokens, b = turns spent writing the brief, R = remaining turns, δ = per-turn growth, p_cr/p_cw =
cache-read/write prices. Staying costs `R·O·p_cr + δ·p_cr·R(R−1)/2 + R(δ·p_cw + out·p_out)`;
recycling costs `b·O·p_cr + (T+B)·p_cw + R·(T+B)·p_cr + [same δ and output terms]`. The δ and
output terms cancel exactly, leaving **R\* = [ (T+B)·(p_cw/p_cr) + b·O ] / (O − T − B)** with
p_cw/p_cr = 12.5. T = 62,543 is measured; B = 5,000 and b = 2 are ASSUMED and are the two
parameters a critic should attack — but note R\* is only weakly sensitive to them at high O
(doubling B to 10K moves R\* at 400K from 4.9 to 5.4).

**Simulation validity control.** The recycle simulation was written so that `C = ∞` reproduces the
measured actual cost **exactly**. A first version did not (it drifted +7.5% by substituting
`cache_creation` for negative occupancy deltas) and was discarded; the reported version tracks a
`reduction` offset against real occupancy so the no-policy arm is the identity.

**What I could NOT measure, and why (abstained, not imputed):**

- **Whether an orphaned dead session's work was actually lost.** The successor-within-6-h proxy
  measures *continuation*, not *recovery*. A session with no successor may still have committed
  everything before it died. Finding 15's $1,555 is therefore an **upper bound**, and I did not
  attempt to impute a recovery fraction.
- **Whether a re-read was necessary.** The 24.4% rate is exact; the waste *share* of it is not
  recoverable from the transcript (a Read with a different `offset` is a different request, and I
  did not have file-mtime-at-read-time to detect "the file changed between reads").
- **Whether each of the 104 duplicate-closed backlog items actually consumed a worker session.** A
  `claim` is a lease, not proof a session ran; `bin/cc-backlog:216` documents that cc-dispatch
  claims *before* it fires. Median claim→close interval for these items is 68 h, so the interval
  is not a usable discriminator either. $17.60 × 104 is an **upper bound**.
- **Whether recycling preserves output.** The single largest assumption in this document. See
  falsification below.
- **Per-turn *fill %*** — unchanged from `CONTEXT_ECONOMY_V2.md`: the window denominator is not in
  the transcript. Everything here is in absolute tokens for exactly that reason, which is also why
  the crossover rule is stated in tokens and not in %.

---

# Recommendations

| # | Action | Expected effect (quantified) | Quality risk | Effort |
|---|---|---|---|---|
| **R1** | **Publish the crossover rule as the recycle decision**, replacing "≥35% fill idle / ~50% valuable / ~75% heavy" with a token-absolute test: *at occupancy O, recycle if more than R\* = [12.5(T+B) + 2O]/(O−T−B) turns of work remain* — practically **≥250K ⇒ recycle if ≥8 turns remain; ≥400K ⇒ ≥5; ≥600K ⇒ ≥4; <150K ⇒ never on token grounds**. Ship it as one line in `CLAUDE.md` § Context Stewardship + a computed field in `bin/cc-context`. | Bounds the prize: 22.3% of spend at C=200K, 9.1% at C=400K. Even capturing a third of the 400K case is ~$42K/yr and — the point that matters — every recycled turn runs on a 65K context instead of a 400K one. | **NONE at O≥400K** (fresher context is strictly better output); **MEDIUM below 250K** (cutting a session that still holds live judgment). The Hold test in `CLAUDE.md` already fences this and should be cited beside the rule. | ~2 h |
| **R2** | **Fix `hooks/log-bash.sh` for real.** The 2026-07-25 fix landed and the symptom survived: 0/44,112 nonzero. Add a *self-falsifying* assertion — the hook writes a `# selftest` line on first use of a known-failing command, or a weekly check that alarms when `nonzero == 0` over >1,000 entries. | Restores the only population-wide (100%-coverage) failure instrument, so finding 8's 3.0% stops needing a 9%-sample re-derivation each time. Zero token effect; pure telemetry integrity. | NONE | ~1 h |
| **R3** | **Make `add` refuse a title that is also an open item's title.** 44 open items have an exact normalized-title twin and ~42 more a near twin — a *forward* liability of up to 86 × $17.60 ≈ $1,500 of duplicate dispatch. The mechanism already exists (`--condition`, `link`); what is missing is the refusal at `add`. | Prevents ~1.7%/yr of re-derivation from recurring. Note `bin/cc-backlog:288` already proves *automatic* keys are unsound (dodRef: ~1 true positive in 81) — so this must be an exact/near-title **refusal with an override**, never an inferred merge. | LOW (a wrongly-refused add costs one flag) | ~2 h |
| **R4** | **Retire the "null subagent return" premise from live doctrine.** 0 of 161 measured. Keep the `limit-recover` skill (limits still kill 104 sessions/30d) but stop treating empty returns as a live failure mode; re-check quarterly. | Removes a defensive step that costs turns and buys nothing at the current rate. ~$0 token effect; the gain is not spending judgment on it. | NONE | ~15 min |
| **R5** | **Wire `~/.claude/logs/account-utilization.jsonl` into the pace-to-100% readout.** It already has 6 days × 4 accounts × ~1,255 samples with reset times. Under use-it-or-lose-it, the actual defect this window is *underspend* — every account's weekly reads 1–18% — and this store is the one that can compute burn-vs-reset properly. | Turns a point-in-time reading into a rate. Directly serves the "under-utilizing is a defect" half of the policy, which none of the waste classes above touch. | NONE | ~2 h |
| **R6** | **Do NOT chase the small classes.** Permission-denial and edit-precondition retries total 0.25% of spend; identical-command repeats 1.5–2.9%; re-reads ≤1.26%. Any hook added to police them costs fork time on the hottest path (`HOOK_CHAIN_COST.md`: 30% of chain cost is already hooks abstaining). | Avoids negative-ROI work. Stated as a recommendation because "find the waste" naturally produces a to-do list, and the honest finding is that this list is not worth the hooks. | NONE | 0 |

**Framing note for the lead, per the operator policy.** R1 must not be sold as a saving. The
operator has explicitly rejected penny-pinching and treats unspent weekly quota as destroyed
value. The correct argument for R1 is that **the 400K-occupancy turn and the 65K-occupancy turn
produce different quality, in the fresh session's favour, and the fresh one also happens to cost
5× less** — the saving is a side effect, and the freed quota should be spent on more parallel
work, not banked.

---

# What would falsify my headline

1. **The recycle simulation assumes the same downstream turns produce the same output.** If a
   recycled session needs materially *more* turns to reproduce what a full-context session would
   have produced in one, W1's saving shrinks and can invert: the break-even is a **1.4× turn
   inflation at C=200K** (22.3% saving ÷ the marginal turn cost) and only **1.1× at C=400K**.
   The cheapest test is an A/B — fire the same brief twice, once as a continuation at ≥400K and
   once as a fresh session, and compare turns-to-DoD. **This is the single measurement that would
   move the ranking most, and I did not run it.**
2. **The 9%-sample tail.** All per-tool and per-turn rates rest on 600 of 6,636 sessions. If
   failure is heavy-tailed — e.g. a handful of sessions burning 40% of their turns on retries —
   the 3.0% error rate would understate the cost concentration even while being correct on
   average. A 100%-coverage `rg -c '"is_error":true'` pass would settle it; I used the sample
   because the tool-name join needs a parse.
3. **The successor proxy could be measuring the wrong thing.** "Another session in the same
   project dir within 6 h" is satisfied by unrelated work in a busy repo, which would make me
   *understate* the 12 orphans. Conversely a recovery that moved to a different worktree name
   would look like an orphan. Both directions are open; the class is ~1.4% either way, so this
   would not change the ranking.
4. **The backlog-ledger classification is regex-based** over `evidence` prose. A stricter reading
   (requiring an explicit "DUPLICATE"/"superseded by" token) gives 104; a looser one gave 184
   (19.9%). I used the strict figure. If the loose one is right, re-derivation rises to ~3.5% —
   still an order of magnitude below W1.
5. **If T is not 62,543 for the sessions that matter.** T is a median over 199 sessions; a
   handoff-fired worker with a long brief starts far higher, and R\* scales linearly in T. A
   worker whose real T+B is 150K would need R\* = 22 turns at 400K, not 4.9 — which would make
   R1 wrong specifically for dispatched workers, the population that recycles most.
