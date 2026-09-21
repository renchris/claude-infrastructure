# A10 — Jev prior art, and where ground-truth labels already exist

Agent 10 of 10, wave `jev-100p-2026-09-21`. Read-only; this file is the sole artifact.
**Zero Jev calls made** (`CC_JEV_ZDR=0` is classifier-refused per the brief).

**The headline, before anything else:** the fleet already holds one near-perfectly balanced,
independently-adjudicated, diff-joinable label corpus of ~4,850 rows — **`~/.claude/land.log`**
(2,597 LANDED vs 3,689 REFUSED among rows carrying both `head` and `base`; ~77% of those shas
still reachable in the checkout). It is *not* a hook's own predicate replayed back at itself,
which is the defect that made the retired arm's `arm A` uninformative. And the thing it predicts
has a measured price: **720.4 hours** of wall clock have been spent on lands that were refused.

---

## Table 1 — Prior art: what exists, was it run, is it alive

| Artifact | What it does | RUN? | Produced | State |
|---|---|---|---|---|
| `bin/cc-jev` (11,497 B) | Human-facing driver: `status` / `probe` / `ask` / `pilot` / `rank`. Resolves `$0` through symlinks before deriving `ROOT`. | **RUN** | `jev_verdict()` now renders the retirement verbatim with the receipt | **LIVE** — but its `status` is now a tombstone renderer. `CC_JEV_RETIRED=1` is the default. |
| `hooks/lib/jev.sh` (11,754 B) | The library every consumer sources: `jev_available`, `jev_ask`, `jev_reason`, `jev_bool_confident`, `jev_secret_source`, thresholds, ZDR, egress-host check. | **RUN** | The one reusable asset in the whole set | **LIVE and reusable.** 8 files source it. This is the piece a new arm inherits for free. |
| `scripts/jev/evaluate.mjs` (7,946 B) | Node bridge to Vercel AI Gateway (`@ai-sdk/gateway` 4.0.87). Exit-code contract; `providerOptions.gateway.zeroDataRetention`. | **RUN** | Verified route end-to-end (`P(passed)=0.01`, 469 ms) | **LIVE.** Not in any deploy glob by path — `install.sh:750` and `scripts/deploy-link-parity.sh:550` both carry comments pinning it to a `scripts/jev/*` glob. Fragile but currently correct. |
| `scripts/jev/pilot.sh` (12,541 B) | Arm A (recall on lexical-matcher positives, joined by the recorded `tell`) + Arm B (discovery over `no-tell`). Refuses (exit 3) if arm A has zero labels. Self-throttles. | **RUN ×2** — n=38 then n=160 | `jev-pilot-20260921T022258Z.jsonl` (38), `jev-pilot-20260921T024237Z.jsonl` (160) | **DEAD as an instrument for the deference arm** (its question is answered). **Alive as a template** — its arm-A join, its refuse-on-vacuous-positive-control, and its throttle are the reusable parts. |
| `scripts/jev/synthetic-probe.sh` (3,146 B) | 20 agent-authored closes through the production question block. | **RUN** | Found the shipped 0.98 threshold sat above Jev's entire output range → corrected to 0.90 | **DEAD, and instructively so.** Its corpus was authored by the judged party; Addendum 3 shows 0.90 was *still* above the real range. Keep the script, never trust a synthetic corpus again. |
| `scripts/jev/rank-memory.sh` (11,057 B) | The **only non-deference use**: `score` primitive over `MEMORY.md`'s indexed topic files. Ranks; never edits. | **RUN** | `jev-rank-20260921T050814Z.jsonl`, **140 rules scored** | **LIVE — the sole surviving arm.** See the class-balance warning below. |
| `tests/jev-evaluate.bats` (22,886 B) | Exit-code contract of `evaluate.mjs` + `jev.sh`; asserts the ZDR flag reaches the request body and that `CC_JEV_ZDR=0` is the only way it comes off. Uses `tests/fixtures/jev-mock-gateway.mjs`. | in suite | — | **LIVE.** Still guards the library. |
| `tests/jev-anti-deference-arm.bats` (7,579 B) | The arm's wiring in `hooks/anti-deference-nudge.sh`. | in suite | — | **ORPHAN-ADJACENT.** Tests an arm that is retired-but-still-wired. Keep only while the wiring stays. |
| `hooks/anti-deference-nudge.sh:264-311, 430, 501` | The AND-gate: `blocker_class == "drivable" AND P(defers) >= 0.90`. | RUN in production | 0 fires over 160 real closes | 🚨 **ORPHANED CODE WITH A COST.** `cc-jev status` says it out loud: *"RETIRED IS NOT OFF, AND THIS ONE COSTS YOU… still reached on every no-tell close, where it spends a doomed round-trip (~0.5 s) that can only ever return 403."* Killing it is `CC_JEV=0`, a settings change ⇒ operator's. **This is the one concrete cleanup this wave should surface.** |
| `~/.claude/autonomy/jev-rank-*.jsonl` ×8 | 2 fixture runs (3 + 2 rows), **5 zero-byte runs** (the doomed-call and non-TTY-consent failures that produced commits `5acaeea16` / `a0ceab890`), 1 real run (140 rows). | — | — | The five empty files are litter, not evidence. |
| Decision packet `c3752f5fca96` | "send closing prose under standard retention / buy Pro for ZDR / leave off" | — | **ACTIONED as `off`** by measurement, without reaching the privacy question | **CLOSED.** |

### The one live arm, and its problem is class balance

`jev-rank-20260921T050814Z.jsonl`, n=140:

```
level:  often 118 (84.3%) · occasionally 21 · almost-never 1
superseded:  >=0.9: 0 | 0.5-0.9: 4 | 0.25-0.5: 77 | <0.25: 59
```

**84% of the corpus is one class, and the top ordinal level is empty.** A ranker that calls 118
of 140 rules "often" cannot order an eviction queue — which was its entire purpose. This is the
same shape as the retired arm one step earlier in the funnel: the *model* is not indicted, the
*question's discrimination on our data* is. Do not ship an eviction on this output without first
re-deriving the `score` criteria to spread the population.

### What is reusable, stated plainly

`hooks/lib/jev.sh` + `evaluate.mjs` + `tests/jev-evaluate.bats` are a working, tested,
egress-allowlisted, throttle-aware, exit-code-contracted path to a bounded typed judgment. **A new
candidate inherits all of it and needs only a question block and a pilot.** The sunk cost is not
wasted; what died was one question, twice.

---

## Table 2 — Label corpora, ranked

Ranking is `class balance × n × joinability`, **times a fourth factor the brief did not name and
which dominates**: **label INDEPENDENCE.** Addendum 3 recorded the failure exactly — *"Arm A
cannot disqualify Jev, because its labels are a regex's output and some are wrong."* A label
produced by the very predicate a model would replicate scores *agreement with a known-noisy
matcher*, not accuracy. Every `idl.jsonl` hook verdict fails this test. The top three do not.

| # | Corpus | n (joinable) | Label means | Class balance | Join | Indep? | 4-day? |
|---|---|---|---|---|---|---|---|
| **1** | **`~/.claude/land.log`** ship-land rows | **6,286 with `head`+`base`; ~4,850 with both shas still reachable (77%)** | `exit==0` ⇒ the land gate accepted this diff. Non-zero ⇒ refused, and `red` names which arm. | **2,597 LANDED / 3,689 REFUSED = 41/59.** Essentially ideal. | `git diff <base> <head>` — 82% of full diffs fit under 96 KB (~24k tok), inside Jev's 32k state ceiling; `--stat` always fits | ✅ adjudicated by a real 40-min gate RUN, never by a predicate over the input | ✅ trivially |
| **2** | `land.log` `red` field — **which arm** (the `choice`-shaped sub-corpus) | **946** | Which gate arm this diff tripped | smoke 238 · dead-assertion 218 · shellcheck 209 · bats-shellcheck 106 · hermeticity 95 · bash-n 41 · movingref 39 · +8 more | same | ✅ same | ✅ |
| **3** | `~/.claude/autonomy/postland/stamps/*.json` | **651** (323 decided) | Whole-tree suite verdict at a landed sha | **red 232 / green 91 / cut 319 / hung 9.** On the decided subset, 72/28 | filename **is** the tree sha; `.commit` is the commit | ✅ an actual suite run | ✅ |
| 4 | `postland/flakes.jsonl` | 2,452 rows, 379 distinct test files | `1-of-3` ⇒ this red was acquitted on re-run; `cut-not-red` ⇒ budget-cut, not a verdict | 🚨 `cut-not-red` 2,073 · `1-of-3` 230 · `floor-not-differential` 76 · `pass-on-retry` 72. Convicted counterpart (`postland/convictions`) is **n=11**. **Flake-vs-real is 230 : 11 = 95/5** | `.file` + `.sha` + `.signal` | ✅ re-run adjudicates | ⚠️ balance kills it |
| 5 | `~/.claude/autonomy/backlog.jsonl` — add→done | 3,728 adds | Was a filed row ever driven? | **3,379 done / 349 open = 91/9.** Poor | `.id` across `add`/`done` events | ✅ | ⚠️ balance |
| 5b | …the `whyNotNow` sub-corpus | **229** | `needs-human` rows an agent nevertheless closed ⇒ the filing was wrong | `needs-human`: **16 done / 31 open (34/66 — good!)**; `not-yet-true`: 157/9 (95/5) | same | ✅ | ❌ n=47 on the balanced half |
| 6 | `~/.claude/autonomy/decisions/*.json` | **264** (2 A · 107 B · 149 C) | The operator's actual ruling | actioned 113 · expired-actioned 76 · open 47 · vetoed 17 ⇒ **acted 92 / vetoed 8** | `.what_plain` + `.options` + `.recommendation` → `.status` | ✅ human ruling | ❌ balance + n |
| 7 | `idl.jsonl` (+`.gz`) hook verdicts | ~150,000 | The hook's own disposition | Best-balanced cells: `capacity-admit` admit 510/refuse 764 (**40/60, n=1,274**); `operator-readout` fired 998/abstained 2,377 (30/70); `session-continue` armed 2,878/fired 1,720/cleared 425. Worst: `waiting-recycle` 110,323 abstained vs 7 fired | `.sid` + `.ts` | 🚨 **NO** — the label *is* the predicate's output. `capacity-admit` is also purely structural (load/quota): a model adds nothing | ✅ but pointless |
| 8 | `git log` — reverts / fixups / corrections | 5,339 commits | A commit later reverted or fixed up | **84 reverts, 12 fixups = 1.6% / 0.2%.** 1,664 subjects match `correct` but that is mostly the word, not a retraction | sha | ✅ | ❌ balance |
| 9 | `docs/lessons/*.md` — bodies retracting a prior verdict | **8 of 121** | The earlier verdict was wrong | 8/121 = 6.6% | prose only | ✅ | ❌ n |
| — | `~/.claude/autonomy/permission-archive/*.jsonl` | 4,656 rows / 3,231 files | Was a permission prompt approved? | 🚨 **`resolved_by`: PostToolUse 4,557 · Stop 82 · SessionEnd 16 = 98/2.** Checked and **rejected** — this is the same artifact CLAUDE.md already warns about (`approved 0 · unknown 3,359`, an unpopulated join key) | — | — | ❌ |
| — | `comms-alarms/` (770), `pages/` (553), `cloud/` (3,171) | — | delivery / prune outcomes | structural, one-class-heavy | — | — | ❌ |
| — | mutation / decorative-suite records | — | which suite was decorative | 🚨 **No corpus exists.** `mutant.219.txt`, `run239-mutants.sh`, `goal-inert/m2-mutant.json` are ad-hoc scratch files from individual investigations, not a store. A hostile reviewer would ask for this; it is not there | — | — | ❌ |

### Exact commands that count each

```bash
# 1 & 2 — land.log (THE corpus)
jq -r 'select(.tool=="ship-land" and .head and .base)|(if .exit==0 then "LANDED" else "REFUSED" end)' \
   ~/.claude/land.log | sort | uniq -c
jq -r 'select(.tool=="ship-land" and .exit!=0 and (.red//"")!="" and .head and .base)|.red' \
   ~/.claude/land.log | tr ',' '\n' | sed 's/:.*//' | sort | uniq -c | sort -rn
# the value case — wall clock burned on refused lands
jq -r 'select(.tool=="ship-land" and .exit!=0 and .total_s)|.total_s' ~/.claude/land.log \
  | awk '{s+=$1;n++} END{printf "n=%d mean=%.0fs total=%.1f h\n",n,s/n,s/3600}'
# 3 — postland stamps
jq -r '.verdict' ~/.claude/autonomy/postland/stamps/*.json | sort | uniq -c
# 4 — flakes
jq -r '.outcome' ~/.claude/autonomy/postland/flakes.jsonl | sort | uniq -c
wc -l ~/.claude/autonomy/postland/convictions
# 5 — backlog
jq -r '.event' ~/.claude/autonomy/backlog.jsonl | sort | uniq -c | sort -rn
# 6 — decisions
jq -r '.status' ~/.claude/autonomy/decisions/*.json | sort | uniq -c
# 7 — idl, FULL history. gunzip -c, never zcat (BSD zcat appends .Z and returns empty)
{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } \
  | jq -rc 'select(.hook)|[.hook,(.verdict//.disposition//"-")]|@tsv' | sort | uniq -c | sort -rn
# — permission-archive (the rejected one; run it so nobody re-proposes it)
cat ~/.claude/autonomy/permission-archive/*.jsonl | jq -r '.resolved_by' | sort | uniq -c
```

---

## Adversarial self-pass — three gaps I went and checked

1. **"You only looked at stores whose shape you already knew."** Fair. I swept `pages/`,
   `cloud/`, `comms-alarms/`, `postland/{tap,queue,reverts}`, and `permission-archive/` — the last
   of which *looked* like the best candidate in the fleet (4,656 real permission decisions, a
   genuinely semantic judgment) and **died on class balance, 98/2.** Reporting it as checked-and-
   rejected is worth as much as reporting a winner, because it is the obvious next proposal.
2. **"Is the land.log label actually predictable, or is it circular?"** Partly circular, and the
   split matters. `shellcheck` (209), `bash-n` (41), `bats-shellcheck` (106) and `dead-assertion`
   (218) are produced by **deterministic static analyzers** — ~574 of 946 rows. Asking a model to
   predict them is paying for something `shellcheck` does free and exactly, and it is the
   `completion-assert` authorship mistake from Addendum A repeating. **The non-circular arms are
   `smoke` (238 — a real test failed) and `hermeticity` (95 — a test reached the live machine).**
   Those 333 rows are the honest semantic sub-corpus. The *binary* LANDED/REFUSED question at
   n=4,850 remains uncontaminated by this, because a pre-flight predictor is allowed to be right
   for a cheap reason — it just must be scored against a static-analyzer baseline, not against
   chance. **That baseline is mandatory and is this wave's version of "a two-line regex scores
   91.6%."**
3. **"Sha reachability — is 72% a recency artifact?"** I stratified rather than sampling the tail:
   rows 1-300 → 213/300; 1500-1800 → 230/301; 3000-3300 → 218/301; 4500-4800 → 273/301;
   6000-6286 → 269/287. **Stable 71-94%, mean ~77%, no collapse in the old stratum.** Rebased and
   pruned branch heads are the loss, as `cited-sha-may-not-survive-the-land` predicts.

Residual I could **not** close: I have no measurement of how well a model does on any of this,
because the brief forbids a Jev call. Everything above is corpus availability, never capability.

---

## The recommendation

**The best available ground truth in this fleet is `~/.claude/land.log`, and the candidate it
supports is a PRE-FLIGHT LAND-REFUSAL PREDICTOR.** It beats every alternative on all four axes at
once: n≈4,850 joinable, 41/59 balance (nothing else clears 90/10 at scale), labels adjudicated by
a 40-minute gate run rather than by a regex, and a join that is one `git diff` away. It also has
the only *measured* value case in the set — **720.4 hours across 3,130 refused lands, mean 829 s,
max 32,808 s** — against 465.2 hours of successful ones. A hook that reads the diff before `/ship`
fires and says "this will be refused on `smoke`" pays for itself in one avoided 40-minute round,
and it is exactly the shape §4 rank 1 identified: closed decision space, thresholdable confidence,
must answer in-line, and a hook cannot spend a Claude turn.

**A four-day validation, concretely.** Sample 1,200 rows stratified to preserve the real
LANDED/REFUSED ratio and to span the whole 2026-07 → 2026-09 range (recency-only would measure
today's gate config). For each, send `git diff --stat` plus the first ~20 KB of the full diff as
state; ask two questions — a `noul` on *"will the land gate refuse this?"* and a `choice` over the
fourteen arm names. At the rate actually observed on the one real run (140 calls in ~10 min ≈ 14
calls/min, and the brief's conservative 6/min) **1,200 calls is 1.4 – 3.3 hours of wall clock and
roughly a nickel** — feasibility is a non-issue, and the four days are for analysis, not for
throughput. Hold out 400 rows untouched until the thresholds are frozen.

**What counts as a pass, stated so it cannot be moved afterwards.** Three conditions, all three
required: (a) on the held-out 400, AUROC ≥ 0.75 with a 95% CI whose lower bound clears 0.65;
(b) there exists an operating point with **precision ≥ 0.85 at recall ≥ 0.20** on REFUSED — i.e.
the hook can warn on one land in five and be right five times in six, which is the shape a
fail-open advisory needs; and critically (c) **it beats the static baseline** — run `shellcheck`,
`bash -n` and the dead-assertion analyzer over the same 400 diffs and require the model's precision
at that operating point to exceed the baseline's by a margin whose CI excludes zero. Condition (c)
is the one that would have killed the deference arm a week early, and it is the one most likely to
kill this. Score the `smoke`/`hermeticity` stratum (n≈333) separately and report it beside the
whole, because that stratum is where a model can be right for a reason no analyzer can reach —
and if the headline passes only because of `shellcheck` rows, the arm is a lint with a bill.

**Before any of that, run the arithmetic Addendum 3 wishes it had run:** at the sampled REFUSED
rate, what would a *perfect* detector return, and what would a *coin* return? Write both numbers
down first. A count is not a measurement until you know what a working instrument would have
produced.
