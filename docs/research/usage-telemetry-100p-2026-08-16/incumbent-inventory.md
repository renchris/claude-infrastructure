# A9 — The incumbent usage stack, graded

---
axis: "A9 — the incumbent: every usage instrument we already have, graded honestly"
status: complete
date: 2026-08-16
headline: >-
  The quota half of the incumbent stack is genuinely good and got better this morning — a durable
  6-day, 4-account utilization series already exists, already steers routing, and already proved the
  fleet finished its last complete week at 85–100% (not the 1–20% a point-in-time read shows) — while
  the token half is near-empty: 2 of ~90 tools read the durable per-session token record, the only
  window denominator has 0.4% coverage, and the one value-per-quota instrument joins on a git trailer
  this repo measured as extinct four days ago and never disconnected.
load_bearing_claim: >-
  `~/.claude/logs/account-utilization.jsonl` is a real, durable, 5,021-row usage time series that the
  briefing's disk search missed because it searched for *usage*/*quota* and the file is named
  "utilization" — so the rebuild's premise "no usage time-series store exists" is false, and the
  rebuild's job on the quota axis is to SURFACE an existing series, not to build one.
---

## Headline

**Stop calling this a greenfield.** The incumbent stack splits cleanly into a **quota/account side that
works** and a **token/session side that is almost entirely absent**, and the briefing's own premise is
wrong about the first half. A durable per-account time series —
`~/.claude/logs/account-utilization.jsonl`, 5,021 rows / 1,256 sweeps / 4 accounts / 2026-08-10→16,
median sample 376 s — has existed for six days, is written for free by the sweep `claude-accounts`
already pays for, is **read** by `apply_burn()` to compute burn rates that steer `--route`, and this
morning produced a landed router fix (HEAD `4d39a85c0`) quantifying **32 pp of weekly quota expired
unused across three consecutive resets**. That series says the fleet's last *completed* weekly windows
ended at **next 91% · next2 92% · next3 100% (capped out) · next4 85%** — so "every account paces
BEHIND" is an artifact of reading four staggered windows hours after they reset, and under-utilization
is a **tail** problem (the last ~10 pp before a stagger), not a level problem. The token side is the
real hole: exactly **two** code paths in the repo (`bin/cc-ctx-audit`, `hooks/lib/context-econ.sh`)
read the durable token record that every transcript carries, both only for *fill %*, never for spend;
the only window denominator lives in `/tmp/cc-telemetry` at **30 rows against 6,991 deduped
transcripts (0.43%)**; the 41 MB `session-index.db` streams every transcript and stores **zero** usage
columns; and `bin/cc-value` — the one instrument that claims a value-per-quota ratio — attributes
**0 of 470** commits because its `Session-Id:` join key was measured extinct on 2026-08-12 and two
sibling consumers were fixed while cc-value was not. One instrument is 100% dead: the
`com.claude.auth-timeseries` LaunchAgent has exited 126 on every one of ~569 fires since 2026-08-13
because its script was never deployed.

---

## Findings

### 1. Inventory

Coverage = the fraction of the population the instrument claims to describe that it actually holds.
"Invocations" = command-position matches over `~/.claude/logs/bash-commands.log`, **245,386 tool-call
lines, 2026-08-09T23:21Z → 2026-08-16T10:4xZ (~6.5 d)** — a *behavioural* reader census, not a grep of
source text (per repo memory `caller-census-keyed-on-path-misses-the-name`, mention-greps overcount 2–4×;
e.g. cc-value 55 source mentions vs **14** real invocations).

| Instrument | Measures | Source | Coverage | Real readers (6.5 d) | Accurate? | Own cost |
|---|---|---|---|---|---|---|
| `statusline.sh` (telemetry writer) | live window, used_pct, input_tokens, model, effort, account, pid | harness `context_window.*` on stdin, per TUI redraw | writes 1 row per live session; store holds **30** | 73 invocations + every redraw; **20 modules read the store** | ✅ accurate; atomic tmp+rename | **83 ms wall / 56 ms CPU per render** (5-run mean) |
| `/tmp/cc-telemetry` (the store) | sid → window/fill/account/pid | statusline | **30 rows / 6,991 deduped transcripts = 0.43%**; 30/1,186 7-day transcripts = 2.5% | 20 readers — the spine of cc-context, cc-board, cc-value, supervisor, boundary hooks | ✅ per-row | ephemeral; oldest row **5.7 h old** |
| `bin/cc-context` (163 L) | live session table: age, fill, window, model, effort, cwd | telemetry store | live sessions only (30) | **46** | ✅ verified against store | ~1 s |
| `bin/cc-ctx-audit` (328 L) | wall hits, compactions, p95 fill | transcripts (`message.usage.*`) + telemetry + recycle-events | **p95 computed over n=38 of 5,284 transcripts = 0.72%** | **16** | ✅ *honest* — abstains, reports its own exclusions | ~3 min full scan |
| `bin/cc-value` (546 L) | value ÷ quota ledger, churn detector | git trailers + backlog + telemetry + claude-accounts | **0 of 470 commits attributed (0%)**; every account `+0c` | **14** | ❌ **two independent breaks** (§4) | ~1 s (TTL-cached for cc-board) |
| `bin/cc-board` (212 L) | per-session board + VAL column + per-acct 5h/WK/FABLE | cc-context ∪ cc-value ∪ claude-accounts | 24 rows rendered; **VAL = `-` on 24/24** | **11** | ⚠️ session/quota columns right; VAL column structurally inert | ~1 s warm |
| `bin/claude-accounts` (4,366 L) | live 5h / weekly / Fable %, resets, auth, credits, k, burn | `api.anthropic.com/api/oauth/usage` | 4/4 accounts, every sweep | **783** — by far the most-used instrument in the fleet | ✅ **verified live vs series** (§4) | 4 OAuth fetches, 90 s cache |
| `~/.claude/logs/account-utilization.jsonl` | **the usage time series** — per-acct session/weekly/fable %, resets, credits, auth, k, k_work | side-car on the `claude-accounts` live sweep | **5,021 rows / 1,256 sweeps × 4 acct / 6.2 d**, median interval 376 s, p90 494 s, max gap 3.4 h | `apply_burn()` (routing), `pool-floor.sh` (76), `desk-strand-replay.py` (10) | ✅ matches live read to ±1 pp | **zero marginal** — rides a sweep already paid for; rate-limited 1 batch / 300 s |
| `bin/cc-fleet` (783 L) | launchd daemon health incl. the usage daemons | `launchctl` + manifest | 29 jobs | **32** | ✅ — it *does* see auth-timeseries as FAILING | ~2 s |
| `bin/cc-cpubound` (125 L) | per-process **CPU-time** ceiling (RLIMIT_CPU) | setrlimit | not a usage instrument — machine resource | **4** (+ wired into `qos-rewrite.sh` on every Bash call) | ✅ | negligible |
| `bin/cc-offload` (803 L) | cloud-VM session board, land, gc | cc-cloud / handoff-fire | declared cloud sessions | **255** — 2nd most-used | n/a (not a usage meter) | n/a |
| `scripts/wrap-ledger.sh` (988 L) | close-state rung (⛔/📦/🚀/✅) | git + DoD + custody + live-layer | every write-turn close | **644** — the highest-frequency of all | ✅ | memoised; ~750 ms budget |
| `hooks/cache-expiry-tracker.sh` (7 L) | epoch of last response | `date +%s` → `.last-interaction` | every Stop | 1 (its warning sibling) | ✅ trivially | 1 fork |
| `hooks/cache-expiry-warning.sh` | ">5 min idle ⇒ cache expired, 10× cost" | the file above | every UserPromptSubmit | injects into **the model**, not a human | ⚠️ **policy-inverted** (§4) | 1 fork + context injection |
| `~/.claude/autonomy/idl.jsonl` | autonomy *decisions* | hooks | 67,706 rows (post-rotation) | cc-audit **3**, cc-idl **8**, cc-digest **7** | n/a | 183 MB before rotation was added |
| `~/.claude/session-index.db` | session search index | transcript sweep | **3,933 of 6,991 transcripts = 56.3%** — the highest-coverage durable per-session store | search/resume | ✅ for search | 41 MB |
| `~/.claude/autonomy/recycle-events.jsonl` | recycle outcomes + **durable sid→window** | context-econ hook | 2,604 rows, **24 sids carry a window** (46 sids total) | cc-ctx-audit denominator #2 | ✅ | small |
| `~/.claude/logs/capacity-alarm.jsonl` | RAM / swap / load / session count | sampler @60 s | 18,823 rows | capacity gate | ✅ | ~640 KB/day |
| `com.claude.auth-timeseries` | *(intended)* per-acct auth series @5 min | — | **0 rows. Store does not exist.** | none | ❌ **100% dead** (§2) | 1,138 stderr lines, ~569 wasted fires |

Missed-by-the-brief instruments found by the `usage|token|cost|quota` sweep: `account-utilization.jsonl`,
`scripts/pool-floor.sh`, `scripts/desk-strand-replay.py`, `bin/cc-eligible`, `hooks/lib/context-econ.sh`,
`capacity-alarm.jsonl`, `com.claude.auth-timeseries`. Nothing else in `bin/ scripts/ hooks/` meters
tokens, dollars, or quota.

### 2. The reader test

| Claim | Evidence | Grade | Coverage |
|---|---|---|---|
| The usage time series **has** readers that change behaviour — it is not write-only | `bin/claude-accounts:1736 apply_burn()` computes `burn_5h_ph` / `burn_wk_ppd` from the series and feeds `_su_projected` + the route pace line; `scripts/pool-floor.sh:50` reads `CC_UTIL_LOG`; `scripts/desk-strand-replay.py:43`. 76 + 10 invocations in 6.5 d | MEASURED | 3 named readers |
| …and it produced a landed behaviour change **today** | HEAD `4d39a85c0` "fix(router): the desk's weekly floor was a constant" — replayed over 1,254 sweeps / 5 resets; desk-time on an expiring account 18.5% → 49.5% | MEASURED | 1 commit |
| `com.claude.auth-timeseries` is a pure-cost instrument: **~569 fires, 0 rows** | `launchctl list` → `- 126 com.claude.auth-timeseries`; `auth-timeseries.err.log` = 1,138 lines, all `/Users/chrisren/.claude/scripts/auth-timeseries.sh: No such file or directory`; `auth-timeseries.out.log` = 0 bytes; **no `auth-timeseries.jsonl` exists** | MEASURED | 100% of fires |
| …**positive control** for that absence assertion | the same `launchctl list` shows `52298 0 com.claude.compressor-sentinel`, whose `compressor-sentinel.jsonl` is 2.1 MB and growing — so the scan can and does find live daemons and their stores | MEASURED | 1 control |
| The failure is **detected but not decided** — this is a decision-layer leak, not a blind spot | `cc-fleet --table` → `UNDECIDED com.claude.auth-timeseries · staged: FAILING; decision pending` (alongside `FAILING com.claude.dispatcher exit 3 after 395 runs`, `FAILING com.claude.capacity-alarm exit 2 after 2599 runs`) | MEASURED | 29 jobs |
| `idl.jsonl` still records **evaluations, not outcomes** — the prior-art shape survives rotation | 67,706 rows: `page` 18,149 · `checkpoint` 17,260 · `heartbeat` 531 · untyped 31,474; no outcome kind in the top 12. Readers: cc-audit 3, cc-idl 8, cc-digest 7 in 6.5 d | MEASURED | 67,706 rows |
| Mention-greps overcount readers 2–4× — the name-not-path census matters | cc-value 55 source mentions → **14** command-position invocations; cc-board 161 → **11**; cc-fleet 123 → **32**; claude-accounts 982 → **783** | MEASURED | 245,386 lines |

### 3. The coverage / durability test

| Store | Durability | Retention | Coverage | Note |
|---|---|---|---|---|
| `/tmp/cc-telemetry` | **ephemeral** | worse than "reboot" — oldest row is **5.7 h old**; `lead-supervisor.sh:625 gc_stale` actively drops rows past `CC_SUP_GC_S` | **0.43%** (30 / 6,991) | the **only** place the window denominator is written |
| transcripts (`message.usage.*`) | **durable** | indefinite, 7.3 GB | **100%** of the numerator | read by exactly 2 modules, both for fill only |
| `account-utilization.jsonl` | **durable** | rotated by `rotate-autonomy-logs.sh:344` | 4/4 accounts × 1,256 sweeps / 6.2 d | the quota answer |
| `recycle-events.jsonl` | **durable** | rotated | **24 sids with a window** / 46 sids | the durable-denominator path exists but is ~2% |
| `session-index.db` | **durable** | 41 MB, retention job | **56.3%** (3,933 / 6,991) | **zero usage columns** — see §5 |
| `idl.jsonl` | durable + hash-chained | 8 rotated epochs on disk | n/a | 183 MB before rotation |
| `capacity-alarm.jsonl` | durable | rotated since 2026-07-31 | 18,823 rows | machine, not tokens |
| `auth-timeseries.jsonl` | **does not exist** | — | **0%** | |

The window denominator is recoverable from *two* stores today (telemetry 0.43%, recycle-events ~2%);
neither is the store that already reads every transcript.

### 4. The accuracy test — three most-relied-on instruments, verified against disk

**(a) `bin/claude-accounts` — 783 invocations, the most-relied-on. VERDICT: ACCURATE.**
Live `--json` at 10:40Z vs the series row it wrote the same second:
next 5/3/3 vs 5/3/3 · next4 62/4/4 vs 62/4/4 · next3 22/21/5 vs 21/20/5 · next2 4/1/0 vs 4/1/0.
Max drift 1 pp, explained by the sweep second. Self-honest too: over 5,021 samples it labels
`auth` as `ok` 4,748 · `stale` 247 · `keychain-error` 19 · `healed` 10 · `logged-out` 1 — it reports
degradation rather than imputing.

**(b) `bin/cc-value` — the value-per-quota claim. VERDICT: WRONG, two independent breaks.**

- **The numerator's attribution key is extinct.** cc-value attributes a commit to an account *only*
  via a `Session-Id:`/`Land-Session:` trailer (`bin/cc-value:15`). Measured: **0 of the last 500
  commits on `origin/main`** carry it; 0 of the 76 landed in the last 24 h. Live output confirms:
  `470 commits landed (470 unattributed)`, and `next +0c · next3 +0c · next4 +0c`.
  **Positive control:** the same grep finds 379 commits whose *message body* contains the string —
  and they are the fix commits themselves (`d3ac3a37` "fix(stranded-sweep): --mine keyed on a git
  trailer nothing writes", `01ccddeb`/`a2de71b9` ship-land). So the repo **already measured this on
  2026-08-12**, wrote it into `scripts/ship-land.sh:123` verbatim ("0 of the last 500 commits …"),
  and re-keyed `stranded-sweep.sh` and `ship-land.sh` off it — **and left `cc-value`, the one
  instrument whose whole purpose is the ratio, still joined to the dead key.**
- **The denominator is a sum of percentages of four different rolling windows.**
  `bin/cc-value:257` `[ $active_accts[] | ($q[.].s // 0) ] | add` → live `spend ~85% (Σ5h)` =
  5+18+62. `:277` `ratio = fleet_value / fleet_spend` → `v/spend 6.4` = 543/85. The numerator is
  fleet-wide {commits + tasks} from 12 repos; the denominator is Σ of unrelated 5-hour windows.
  This is the repo's own `aggregate-ratio-is-not-a-marginal` defect, in the instrument named
  "value ledger". The `churn` detector gates on `fleet.value`, which is dominated by the
  unattributable 470 — so it is structurally near-unfireable.
- **Downstream:** `cc-board`'s VAL column reads `-` on **24 of 24** rows.

**(c) `bin/cc-ctx-audit` — VERDICT: ACCURATE *and* the model for the rebuild.**
`--summary --since 7d` returns `p95=72.1% (p50=38.7%) over n=38` and prints, unprompted,
`EXCLUDED for no recoverable denominator: 5246 of 5284 transcripts` — a **0.72% coverage** figure it
volunteers rather than imputing, with a distinct exit 3 for "no recoverable denominator". Also
measured: 1 hard wall-hit and **0 compactions** in 7 days, consistent with CONTEXT_ECONOMY_V2.

**(d) Bonus — `hooks/cache-expiry-warning.sh`. VERDICT: policy-inverted, should be deleted.**
Its entire output is `additionalContext` telling *the model* that after 5 min idle "full context will
be reprocessed at uncached rate. Consider /clear (fresh session) or /compact (compress history) to
reduce token cost." Under the operator policy — *never cut quality for token savings; under-using the
allowance is itself a defect* — this instrument's only actuation is the forbidden action, injected
into the model's context on every prompt after an idle gap. It is the one instrument whose cost is
paid in **quality**, not tokens.

### 5. The gap statement — what the incumbent can and cannot answer

| Operator question | Answerable today? | By what |
|---|---|---|
| **Am I maximising the weekly allowance?** | **YES, but only by hand.** The data is complete; no instrument renders the answer. | `account-utilization.jsonl` + a hand-written groupby. Measured this session: last completed weekly windows ended **next 91% · next2 92% · next3 100% (ceiling) · next4 85%**; Fable-window peaks 60/39/64/33%. `R9-desk-weekly-strand.md` quantified the residue at **32 pp stranded / 3 resets** and HEAD fixed the largest cause. **No CLI prints any of this** — `claude-accounts --readout` shows the *current* window, which reads 1–20% for hours after each staggered reset and systematically understates. |
| **Am I spending tokens well?** | **NO.** Not by any instrument, and not by hand at reasonable cost. | The numerator is durable in 6,991 transcripts; **2 of ~90 tools read it**, both for fill only. Nothing computes tokens-per-session, per-account, per-model, per-outcome, or per-dollar. The one instrument that claims to (`cc-value`) attributes 0/470 and divides by a summed percentage. `session-index.db` already parses every transcript at **56.3% coverage** and stores **no usage column** — the cheapest possible fix is a schema addition to a sweep that already runs. |
| **Is the telemetry itself bloat?** | **PARTLY, and it is measurable.** | Cheap and earning: `account-utilization` (zero marginal cost, 3 readers, 1 landed fix), `statusline` (56 ms CPU/render for the only window record). Pure cost: `com.claude.auth-timeseries` (~569 fires, 0 rows), `cc-value`'s attribution half (14 invocations of a 0%-coverage join), `cache-expiry-warning` (context injection whose advice violates policy). Unquantified: `idl.jsonl` at 67,706 evaluation rows vs 18 total reads in 6.5 d. |

**The specification the gap implies:** the rebuild's quota axis is a **renderer over an existing
durable series** (plus a stagger-aware "% of the *completed* window" statistic that a point-in-time
read cannot express) — not a new collector. The rebuild's token axis is a **new durable per-session
usage record**, and its natural home is the sweep that already opens every transcript.

---

## Method

Read-only throughout. One file written (this one).

- **Reader census:** command-position regex over `~/.claude/logs/bash-commands.log` — 245,386 tool-call
  lines, 2026-08-09T23:21Z → 2026-08-16. Script at
  `…/scratchpad/cens.py`. Chosen over source-grep per repo memory
  `caller-census-keyed-on-path-misses-the-name`; both are reported where they diverge.
- **Store census:** `ls -la ~/.claude/logs ~/.claude/autonomy /tmp/cc-telemetry`; schema via
  `sqlite3 ~/.claude/session-index.db .schema`; JSONL shapes via streaming `python3`/`jq` (no file
  read into context).
- **Transcript denominator:** `find` over all four `*/projects` roots → `realpath` → `sort -u` =
  **6,991** deduped `.jsonl` (the symlinked `~/.claude-next{,2,3,4}` double-count trap was avoided by
  realpath, per memory `token-usage-from-transcripts`).
- **Instruments executed live:** `cc-value`, `cc-context`, `cc-board`, `cc-ctx-audit --summary
  --since 7d`, `cc-fleet --table`, `claude-accounts --json`, `statusline.sh` (5-run timing with
  `CC_TELEMETRY_DIR` redirected to a probe dir so no live row was touched).
- **Utilization series:** all 5,021 rows parsed; grouped by `(acct, weekly_reset_at)`. **Caveat:** the
  API's reset timestamp jitters across the minute boundary (`03:59:59` vs `04:00:00`), which splits
  one window into two groups; both halves of every split agree within 1–4 pp, and the max is reported.

**Not measured, and why:**
- **Per-session token totals across the corpus.** Deliberately out of scope for this axis and
  expensive (7.3 GB); axes measuring spend own it. This artifact asserts only that *no instrument
  computes it*, evidenced by the 2-module reader census over `message.usage`.
- **Marginal hook-chain cost of each usage instrument.** `HOOK_CHAIN_COST.md` owns the model; I
  measured only `statusline.sh` (the per-render hot path) directly. **ABSTAIN** on the rest.
- **Whether `credits_used` is truly always 0.** All 5,021 rows read 0.0, but `cc-value:31` records a
  Max account carrying $176.91 of extra-usage spend on 2026-07-26. The series may simply not have
  spanned a billing event. Reported as *0 observed in 6.2 d*, **not** as "dollars are never spent".
- **`k` / `k_work` concurrency ceilings.** Only 8 of 5,021 rows carry `k_src` (the field landed at
  HEAD, ~1 h ago). Too thin for any claim; HEAD's own message flags next4's 15 pp strand as an upper
  bound for exactly this reason.

---

## Recommendations

| # | Action | Expected effect (quantified) | Quality risk | Effort |
|---|---|---|---|---|
| 1 | **Render the completed-window statistic.** Add `claude-accounts --weekly-history` (or a `◆` line in the readout) computing, from the existing series, per-account *peak weekly % at reset* for the last N windows + pp stranded. | Converts a 6-day, 5,021-row asset with 3 machine readers into the operator's answer to question #1. Today that answer requires a hand-written groupby; the default readout understates by up to **89 pp** in the hours after a stagger (next: shows 3%, last window ended 91%). | **NONE** — pure read of existing data | S (~80 LOC, one file) |
| 2 | **Disconnect `cc-value` from the extinct trailer.** Either re-key attribution onto the live-telemetry sid→account join `ship-land.sh:1113` already uses, or delete the per-account column and the `v/spend` ratio and keep only the honest fleet counts. | Removes a 0%-coverage instrument that renders `+0c` on every account and `-` on 24/24 cc-board rows, and a ratio (543 ÷ Σ-of-four-5h-percentages) that has no units. | **NONE** (it produces no correct number today) | S–M |
| 3 | **Bury `com.claude.auth-timeseries`** — `launchctl bootout` + remove the plist, or deploy `tools/auth/auth-timeseries.sh`. Then resolve the 3 other `FAILING`/`UNDECIDED` daemons `cc-fleet` already names. | Ends ~569 wasted fires and 1,138 stderr lines producing 0 rows; the series it intended is already superseded by `account-utilization.jsonl`'s `auth` field (4,748 ok / 247 stale / 19 keychain-error / 10 healed / 1 logged-out). | **NONE** | XS |
| 4 | **Add usage columns to `session-index.db`.** The sweep already streams every transcript: persist `sid, account, model, peak_input_tokens, cache_read, cache_creation, output_tokens, window`. | Lifts durable per-session usage coverage from **0.43%** (telemetry) to the index's **56.3%**, and gives `cc-ctx-audit` a third denominator source that would have taken n=38 toward n≈2,900 on the same 7-day window. Marginal cost ≈ 0: the file is already open and parsed. | **NONE** | M |
| 5 | **Delete `hooks/cache-expiry-warning.sh`** (keep the 7-line tracker if anything else uses the stamp). | Removes the only instrument whose sole actuation is to advise `/clear` or `/compact` for token savings — the exact action the operator policy forbids — injected into model context on every post-idle prompt. | **NONE** (removing it *raises* the quality floor) | XS |
| 6 | **Make the tail the routing target, per HEAD's finding.** HEAD fixed `DESK_W_FLOOR`; the same horizon-scaling question applies to the general and Fable lanes, and next4's 15 pp strand is still open as an exclusion. | Addresses the residue of the measured **32 pp / 3 resets**. Under the use-it-or-lose-it policy this is the largest *quantified* loss in the whole stack. | **LOW** — routing changes can concentrate load; HEAD's replay harness (`desk-strand-replay.py`) already exists to bound it | M |
| 7 | **Do not build a new collector for the quota axis.** Fold this into the rebuild spec explicitly. | Prevents the rebuild from duplicating a zero-marginal-cost series and re-creating the second renderer the repo keeps deleting. | NONE | XS (a paragraph) |

---

## What would falsify my headline

1. **`account-utilization.jsonl` is not durable.** If `rotate-autonomy-logs.sh` prunes it to a horizon
   shorter than one weekly window (7 d), the "completed-window" statistic is unrecoverable and it is a
   *ring buffer*, not a series. I verified it is **listed** for rotation and holds 6.2 d spanning 5
   resets; I did **not** read the rotation's retention parameter. *Check:* the retention constant in
   `scripts/rotate-autonomy-logs.sh`, and whether any archived `account-utilization.jsonl.*.gz` exists.
2. **The weekly percentages are not monotone within a window.** I took `peak == end` because a weekly
   counter should only rise until reset. If the API's `weekly_pct` can *fall* mid-window (partial
   expiry, credit grant, plan change), then "ended at 91%" is wrong and the fleet may be further from
   the ceiling than I claim. *Check:* scan each window for a negative delta.
3. **`Session-Id:` trailers exist on a ref I did not scan.** I checked `origin/main` (last 500) and
   `--all` in *this* repo only. cc-value scans 12 repos; if the fleet's other repos emit the trailer,
   its attribution is not 0% fleet-wide, only 0% here. *Check:* run the same 500-commit grep in each
   repo `cc-value` reports scanning.
4. **`message.usage` has more readers than I found.** My census grepped `bin/ scripts/ hooks/
   statusline.sh` for `cache_read_input_tokens|message.usage`. A reader written in Python with a
   different field spelling, or living outside those dirs (`tools/`, `~/.claude/bin/`), would be
   invisible — the same name-vs-path failure this artifact cites elsewhere. *Check:* grep the whole
   deployed `~/.claude` tree for `output_tokens` and for `usage` field access.
5. **The 6.5-day bash log is unrepresentative.** All invocation counts rest on one rotation epoch. If
   an instrument is invoked seasonally (a weekly review, a monthly audit), a 6.5-day window reports it
   as dead when it is periodic. *Check:* repeat the census against the four rotated
   `bash-commands.log.*.gz` archives back to 2026-07-19.
