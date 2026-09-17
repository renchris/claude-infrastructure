# A8 — The arithmetic: what free tokens would be worth here, against what the same week buys otherwise

Measured 2026-09-16/17 on live stores. Every number carries the command that produced it.
Read-only throughout: no fire, no backlog mutation, no account write.

---

## VERDICT

| | |
|---|---|
| **UPPER-BOUND PRIZE** | **11–21 delivered, non-self-directed backlog-row closures in a week** — under the maximally generous assumption that union-alpha equals Opus 5 in quality, has no rate limit, and costs nothing to wire. **0 of them are customer deliverables**, structurally: `bin/cc-dispatch:1921` selects `status=="open"` only, and all five mission rows are operator-blocked (`cc-dispatch:3633` filters them out *by design*). |
| **BINDING CONSTRAINT** | Not tokens. **38 open rows** exist today, **23 of them (60.5%) self-generated exhaust** (`re-land` 10, `post-land/deploy RED` 10, `advance <plan>` 3). Only **15 are substantive**. Meanwhile **1.5 account-weeks of Opus-5-class quota is unrouted on this box right now** and the desk forecasts ~47pp of it to die at reset. |
| **COST** | **A new agent harness — the cloud-lane reference class: 50 days, 591 commits (15.5% of ALL repo activity in that window), 30,510 LOC across 73 files** — because Anthropic's own docs state Claude Code *"doesn't support routing … to non-Claude models through any gateway."* Plus a mandatory ~2-day certification probe (Codex-probe reference class), which the box's own standing rule requires: *"uncertified means unrouted."* The cheap path (Anthropic-format gateway) is worse, not cheaper: a gateway credential **replaces** the Max subscription for that session and bills per token — the exact condition `spend.usage_credits_authorized=false` forbids. |
| **CURRENT BILL FOR THE INCUMBENT** | **$0.00.** The fleet moved **19.52 B tokens in 7 days**, worth **$13,733.56 at Opus 5 list**, and was invoiced **nothing** — 4 × Claude Max, `usage_credits_authorized=false`. **Free cannot underprice free.** |
| **CONVICTION** | **94%** that a week of engineering on the free-token pipeline is net-negative and should not be built. **97%** that the same week's *operator attention* — ~20 minutes of it — should go to the five mission rows instead. |

**The one-sentence reason.** The proposal buys more of the input the box already cannot spend, to feed a queue that refills from the act of draining it at a measured **0.502 new rows per closure** (r = +0.708, t(28) = 5.31, p < 0.001) — while the five customer deliverables it would displace need no tokens at all, only one email reply, one HTML file opened, and one contact name.

---

## 1 · Current cost of the thing

### 1.1 The $3.35/closure figure — verified, and its denominator named

The audit's `$3.35` is **lifetime local-drain quota-equivalence spend ÷ lane-attributed closures**:

- Numerator ≈ **$1,306**, derived from `drain-pipeline-productivity-2026-09-16.md:§5` — *"Cloud spent ≈ $3,264 in 30 days — 2.5× what the entire local drain lane has ever spent"* ⇒ local lifetime ≈ $3,264 / 2.5.
- Denominator = **397 lane-attributed closures** (§1).
- $1,306 / 397 = **$3.29**, reproducing $3.35 to within rounding.

🚨 **397 is a LOWER bound and therefore $3.35 is an UPPER bound.** The `lane` field only exists from 2026-08-23 and **2,306 `done` events carry no `closedBy` at all** (§6). The lane's true cost per closure is *below* $3.35. It is already the cheapest worker on the box by 6.5×.

| unit | local drain | ordinary session | cloud |
|---|---|---|---|
| **$ / closure** | **$3.35** (upper bound) | $21.75 | $32–112 (denominator-dependent; §5 states the range) |
| **$ / session (median)** | $14.89 | $15.86 | — |
| **$ / message (median)** | $0.125 | $0.162 | — |
| **rows / session** | **5.5** | 1.5 | — |

**The 6.5× advantage is entirely throughput.** Per-session and per-message cost are statistically identical. The audit's own conclusion: *"Rows-per-session is the only lever that has ever mattered — not venue, not model, not quota."*

### 1.2 The box's total weekly model spend, and whether any of it is billed

```
$ ~/.claude/bin/cc-quota-price --census
deduped token census — window 7d · 3071 file(s) · 79392 billed response(s)
  output                  32,034,112
  cache_creation         553,522,146
  input                    1,005,224
  cache_read          18,936,344,513
  dedup: 115,650 of 196,175 record(s) were repeats (59.0%) — summing lines would have over-counted by 2.47x
```

Priced at Opus 5 list ($5 in / $25 out / $6.25 cache-write / $0.50 cache-read):

| class | tokens (7 d) | $ at list |
|---|---:|---:|
| output | 32,034,112 | $800.85 |
| cache_creation | 553,522,146 | $3,459.51 |
| input | 1,005,224 | $5.03 |
| **cache_read** | **18,936,344,513** | **$9,468.17** |
| **TOTAL** | **19,522,905,995** | **$13,733.56 / week** |

**Actually billed: $0.00.** `~/.claude/accounts.json` → `spend.usage_credits_authorized: false`, `frontier.credits_authorized: false`, and four Claude Max accounts. Every dollar figure in this repo's cost research is an explicit *equivalence*, not a bill — `cloud-lane-redesign-2026-09-10/C2-cost-per-landed-row.md` says so in terms: *"An equivalence, not a bill — every one of these tokens is drawn from a Max-plan weekly meter, not invoiced."*

**Derived exchange rates** (fleet burned **446 weekly pp = 4.46 account-weeks** in the same 7 days, summing positive Δ`weekly_pct` per account over `~/.claude/logs/account-utilization.jsonl`):

- **$30.79 of list-price inference per weekly percentage point**
- **$3,079 per account-week**
- Cross-check against `USAGE_TELEMETRY_100P.md §2.1`: 1 pp ≈ 261K (realised avg) – 360K (marginal) Opus-5 output tokens; a full account-week ≈ **26–36 M Opus-5 output tokens**. Consistent.

🚨 **The single most decision-relevant line in the census: 97% of the tokens this fleet moves cost ~0% of its quota** (`USAGE_TELEMETRY_100P §2.2`) — cache_read is free against the Max meter. **On a metered third-party route it is not free.** It is **69% of the list bill** ($9,468 of $13,734). The fleet's token shape is maximally hostile to any per-token gateway, and maximally favourable to the subscription it already holds.

### 1.3 The 107 K preamble, and why free tokens make it worse

The audit's §10 names *"a ~107 K-token resident preamble re-read every turn"* as **≥43% of a drain session's bill** and *"the one lever that moves the denominator and the numerator at once."*

At the measured ~119 turns/drain-session (median $14.89 ÷ $0.125/message):

| route | preamble cost / session | / closure (5.5 rows) |
|---|---|---|
| **today, on Max quota** (cache_read ≈ free) | **$0.00 · 0 pp** | **$0.00** |
| metered, with a working prompt cache @ $0.50/Mtok | $6.37 | $1.16 |
| metered, cache cold or unsupported @ $5/Mtok input | **$63.67** | **$11.58** |

A third-party route must re-warm its own cache per provider and per session. The one cost lever the audit identifies as dominant is the one a metered route degrades by 1–2 orders of magnitude.

---

## 2 · Is the box token-constrained at all?

### 2.1 Live readout (relayed verbatim, `claude-accounts --readout`, 2026-09-17 04:38 UTC)

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 0 | 0% | — | 94% | 7% | Sat 22:59 (in 2d 23h) | Tue Oct 13 01:19 (in 26d 1h) |
| next4 ← you | 14 | 14% | Thu 02:00 (in 2.4h) | 42% | 13% | Sun 04:00 (in 3d 4h) | Thu Oct 08 05:42 (in 21d 6h) |
| **next3** ➤ | 2 | 2% | Thu 01:00 (in 1.4h) | 7% | 0% | Tue 07:00 (in 5d 7h) | Thu Oct 01 14:39 (in 14d 15h) |
| next2 | 1 | 66% | Thu 00:40 (in 1.0h) | 100% | 76% | Sat 06:00 (in 2d 6h) | Mon 03:07 (in 4d 3h) |
- ○ `next2` — weekly **LIMITED** (100%)

➤ desk (bare `claude`) → **next3** — earliest weekly reset among 5h-safe accounts · weekly ↻ 5d 7h · 5h 2% · safe set
➤ general → **next3** · ➤ fable → **next3**
weekly drain — pp that DIE at reset (K=0.203 live · nowcast at the last 48h of pace):
  next3 strand ~47pp of 93 · p76 of its own 24h burns · start by T−29h (99h slack) · 5d left
  next no strand — on pace to fill the window · 2d left
  next4 no strand — on pace to fill the window · 3d left
  next2 no strand — on pace to fill the window · 2d left
Fable window: **permanent** (no expiry).

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
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

**Read off that table, three facts that bear directly on this proposal:**

1. **1.5 account-weeks of Opus-5-class capacity is unrouted on this box right now** — next3 at 7% (93 pp free, ~47 forecast to die) and next4 at 42% (58 pp free). ≈ **$4,650 of list-equivalent inference**, sitting idle, with 5 and 3 days respectively to spend it.
2. **The Fable sub-cap is idle too** — next3 at 0%, next at 7%, next4 at 13%. Even the *premium* tier is under-spent, and its window is permanent.
3. **Two non-Claude backends are already routable at zero marginal bill** (Codex CLI, Pi·Codex on ChatGPT Plus, `gpt-5.6-sol @ xhigh ✓proven`). If the goal is vendor decorrelation rather than volume, **it is already wired and idle** — no build required. See §4.3.

### 2.2 Stranded quota per cycle — 21 complete account-cycles measured

Method: group `~/.claude/logs/account-utilization.jsonl` (28,634 samples, 2026-08-10 → 2026-09-17) by `(acct, weekly_reset_at` rounded to the hour`)`; a cycle's **peak `weekly_pct`** is what it ever reached; **strand = 100 − peak**. Cycles with <100 samples (partial observation) excluded; in-flight cycles excluded.

| reset (UTC) | acct | peak % | **strand pp** | | reset | acct | peak % | **strand pp** |
|---|---|---:|---:|---|---|---|---:|---:|
| 2026-08-11 | next3 | 100 | **0** | | 2026-08-30 | next4 | 84 | **16** |
| 2026-08-15 | next2 | 92 | **8** | | 2026-09-01 | next3 | 64 | **36** |
| 2026-08-16 | next | 91 | **9** | | 2026-09-05 | next2 | 49 | **51** |
| 2026-08-16 | next4 | 85 | **15** | | 2026-09-06 | next | 31 | **69** |
| 2026-08-18 | next3 | 98 | **2** | | 2026-09-06 | next4 | 21 | **79** |
| 2026-08-22 | next2 | 100 | **0** | | 2026-09-08 | next3 | 49 | **51** |
| 2026-08-23 | next | 99 | **1** | | 2026-09-12 | next2 | 100 | **0** |
| 2026-08-23 | next4 | 92 | **8** | | 2026-09-13 | next | 100 | **0** |
| 2026-08-25 | next3 | 94 | **6** | | 2026-09-13 | next4 | 100 | **0** |
| 2026-08-29 | next2 | 100 | **0** | | 2026-09-15 | next3 | 100 | **0** |
| 2026-08-30 | next | 100 | **0** | | | | | |

**Totals.** 21 complete account-cycles · **351 pp stranded = 3.51 account-weeks** over ~5 fleet-weeks.
**Last 4 complete cycles per account:** next 70 · next2 51 · next3 93 · next4 103 = **317 pp = 3.17 account-weeks**, independently reproducing the audit's *"3.19 account-weeks of weekly quota expired unused"* from a different fold of a different store.

**Converted:**

| unit | value |
|---|---|
| stranded, last 4 cycles/account | **317 pp** |
| = account-weeks | **3.17** |
| = Opus-5 output-token equivalent (261–360 K/pp) | **83 M – 114 M tokens** |
| = list-price equivalence @ $30.79/pp | **$9,760** |
| = actually billed | **$0.00** |

### 2.3 🚨 The finding that decides the question: strand is a SYMPTOM, not a resource

Quota does not die because the box lacks capacity. It dies because the box has **nothing to point at it**.

| fleet-week | strand (pp) | = account-weeks | mean backlog closures in the cycle |
|---|---:|---:|---:|
| R1 Aug 11–18 | 32 | 0.32 | 617 |
| R2 Aug 18–25 | 11 | 0.11 | 682 |
| R3 Aug 25–Sep 1 | 22 | 0.22 | 295 |
| **R4 Sep 1–6** | **235** | **2.35** | **205** |
| R5 Sep 6–15 | 51 | 0.51 | 535 |

- **r(strand, closures) = −0.541** at the account-cycle level (n = 21); **−0.707** at the fleet-week level (n = 5).
- ⚠️ **Honest limit: n = 5 fleet-weeks gives t(3) = −1.73, p > 0.05 — directionally clear, statistically underpowered.** Account-cycles are not independent (four accounts share one fleet-week's closure count), so the account-level n = 21 is not the real n. Do not quote the correlation as significant.
- **The distribution carries the argument the correlation cannot.** **R4 alone is 235 of 351 pp — 67% of every point ever stranded in the observed period** — and it is the lowest-throughput week in the series. In the most recent complete round, **three of four accounts stranded exactly 0 pp.**
- **The one week the ceiling genuinely bound (Sep 6–15, all four accounts at 100%), both drain lanes were already dead** — local's last closure was 2026-09-09, cloud's 2026-09-12. That week's quota went to ordinary sessions and research waves, not to throughput.

**So what does a free third-party token buy?** On the measurement: it buys the fifth wheel on a box that cannot spend its fourth. The binding resource has never been tokens in any observed week — it has been **eligible work** (§3) and, in the saturated week, **a living lane**.

---

## 3 · The ceiling on the prize

### 3.1 The drainable queue, live

`~/.claude/autonomy/backlog.jsonl`, 20,528+ events, 3,582 ids, 0 parse failures:

| state | rows |
|---|---:|
| done | 3,236 |
| **blocked** | **308** |
| **open / claimed** | **38** ← the only rows any lane can select |
| dropped | 0 |

`bin/cc-dispatch:1921` — `jq '[ .[] | select(.status=="open" and …) ]'`. `bin/cc-dispatch:3633` documents the consequence in its own comment: *"(k) blocked-on-operator item → filtered out (dispatch keeps ONLY status=="open")"*. **308 of 346 live rows (89%) are structurally invisible to every lane, free or paid.**

**And the 38 are mostly the machine's own exhaust:**

| class | rows | share |
|---|---:|---:|
| `re-land <branch>` (ship-land could not complete) | 10 | 26.3% |
| `post-land RED` / `post-deploy HOST RED` / AUTO-REVERT | 10 | 26.3% |
| `advance <plan>` | 3 | 7.9% |
| **substantive** | **15** | **39.5%** |

By project: claude-infrastructure 29 · sevenrooms-bridge 6 · reso-management-app **1** · personal 1 · voiceink 1.
**Rows touching the mission board: 0 of 38.** (The single reso row is *"BytePlus ModelArk US-territory subscription — ask sales whether a US entity can hold one"* — itself an operator-owned ask.)

### 3.2 🚨 The treadmill, measured: the queue refills from the act of draining it

Daily `done` vs daily `add` over 2026-08-18 → 2026-09-17 (n = 30 days):

- **r = +0.708 · t(28) = 5.31 · p < 0.001**
- **slope = 0.502 new rows minted per closure**
- lag +1 (closures today → new rows tomorrow) r = **+0.473** — so it is not pure simultaneity
- Mechanistic floor, independent of the correlation: the `re-land` generator is **28.7% of 30-day inflow** and `postland-verify` **4.5%** — **≥33% of inflow is *mechanically caused by closures landing*.** The observed 0.502 is the correlational total; 0.33 is the causal floor.

The historical consequence is already on record (`backlog-drain-netpositivity-2026-08-25.md §1`): *"the agent-facing board specifically sat at **287 ± 38 for 19 days while 1,635 items were closed inside it** — sixteen hundred closures moved the actionable board **+40, in the wrong direction**."*

### 3.3 The upper bound, computed explicitly

**Assume the most generous case possible**: union-alpha = Opus 5 quality, infinite rate limit, zero setup cost, and it can drive the existing lane. Then in one week:

```
stock cleared, accounting for self-minting (geometric, m = 0.502):
    38 / (1 − 0.502)                       =  76 closures
exogenous OPEN inflow over 7 days:
    adds/day 31 × (1 − 0.484 blocked-at-filing)  ≈ 16/day drainable
    minus the ~0.502·C already counted        ≈ 8.9/day exogenous
    8.9 × 7 / (1 − 0.502)                  = 125 closures
────────────────────────────────────────────────────────────────
ABSOLUTE CEILING                           ≈ 201 closures / week
```

Now discount, two ways (the brief's chain and a sharper one that avoids double-counting exhaust):

| chain | arithmetic | result |
|---|---|---|
| **Brief's** (raw ceiling × delivered × non-infra) | 201 × 0.43 × 0.248 | **21 rows** |
| **Substantive-first** (strip the ~100 self-minted exhaust rows first — `lane=land` closures are **100% no-op, 83/83**) | 101 × 0.43 × 0.248 | **11 rows** |

> **THE PRIZE: 11–21 delivered, non-self-directed backlog-row closures per week — and 0 customer deliverables, structurally.**

*(The 24.8% non-infra share is measured live: September closures joined to their `add` record's project = claude-infrastructure **704/936 = 75.2%**, reso **186/936 = 19.8%**. This reproduces the audit's 74%. ⚠️ It is a **lower bound on infra** — `backlog-drain-netpositivity §7` records that `project` stores the worktree basename, not the repo, so ~100 rows filed under `.desk-land-…` slugs undercount claude-infrastructure by an unknown margin.)*

### 3.4 The second, independent bound — and why it does NOT bind

| offer | measured limit | fleet requirement | verdict |
|---|---|---|---|
| **OpenRouter `:free` models** | **50 req/day** (<$10 lifetime credit) or **1,000 req/day** (≥$10); **20 req/min**; open-weight models only | fleet moves **79,392 billed responses / 7 d = 11,342/day**; at ~22 requests per closed row, 1,000/day ≈ **318 rows/week of request budget** | request budget (318) is **looser** than the queue bound (201) → **the queue binds, not the free tier** |
| **Cloudflare AI Gateway** | supplies **zero free inference** — *"inference pricing from providers is passed through with no markup"*; free tier = 100,000 logs/month; Workers AI = 10,000 Neurons/day | — | **not a token source at all**; it is a proxy/observability layer |

**This is the robustness result.** Even granting an infinitely generous free tier, the answer does not move — because the constraint was never capacity. Conversely, if the realistic tier is 50 req/day, the prize is ~2 rows/week before any discount.

**And model quality cuts the realistic figure toward zero.** `:free` variants are open-weight models. This box has already measured a *frontier-class* non-Claude model in the same decision: `codex-probe-w3-verdict-2026-08-11.md` — over 36 anchored ground-truth defects, **not one was caught by a Codex arm that neither Claude arm caught**, at every vote threshold. An open-weight free model is categorically weaker than the model that already returned zero unique coverage.

---

## 4 · The cost side

### 4.1 🚨 Anthropic's own documentation forecloses the cheap path

From `https://code.claude.com/docs/en/llm-gateway`, verbatim:

> *"Any gateway that exposes a supported API format works. Anthropic doesn't endorse, maintain, or audit third-party gateway products, and **doesn't support routing Claude Code to non-Claude models through any gateway.**"*

> *"While a gateway credential variable or `apiKeyHelper` is active, a developer's claude.ai subscription isn't used: **the credential replaces the subscription login for that session, and the subscription's usage limits don't apply. That traffic is billed per token to whoever owns the credential** …"*

> *"Setting only `ANTHROPIC_BASE_URL`, without a gateway credential, doesn't replace the subscription. Requests still route through the gateway, but a saved claude.ai login remains the active credential, so its usage limits and billing apply."*

**Three arms, all closed:**

| path | consequence | verdict |
|---|---|---|
| union-alpha serves **non-Claude** models | Claude Code cannot be routed to them. The entire drain lane (`cc-dispatch` → `handoff-fire.sh` → `claude`) cannot consume the tokens. **A new agent harness is required.** | cost = cloud-lane reference class (§4.2) |
| union-alpha serves **Claude** models, gateway credential set | The credential **replaces** the Max subscription — it does not *add* capacity, it *substitutes* for it — and bills per token to the credential owner. When the free window closes, the box is silently billing outside a plan we hold. | **fails `spend.usage_credits_authorized=false`** and `providers.json _the_cost_rule` |
| `ANTHROPIC_BASE_URL` only, no credential | No free tokens at all — subscription quota still burns. The gateway becomes a pure man-in-the-middle over the fleet's OAuth traffic. | zero prize + `jcode`-class ToS exposure |

**Confirmed: no such wiring exists on this box today.** `env | grep ANTHROPIC` → only `CLAUDE_CODE_EXECPATH`. `grep ANTHROPIC_BASE_URL ~/.zshrc ~/.claude*/settings*.json` → nothing. This has been a deliberate abstention, not an oversight: `~/.claude/providers.json` carries a standing `_the_cost_rule` — *"ASK WHAT IT BILLS, NOT WHAT IT CAN LOG INTO … Any provider whose answer here is true, or UNKNOWN, is documented and SKIPPED — never wired, never signed up for."*

### 4.2 Reference class — what this box's comparable builds actually took

| build | span | commits | LOC | outcome |
|---|---|---:|---:|---|
| **Cloud lane** — a new inference venue, *same vendor, official API, no translation layer needed* | **50 d** (2026-07-29 → 09-17) | **591 = 15.5% of ALL 3,818 repo commits in the window** | **30,510 across 73 files** | 19.9% declaration yield (212 commits from 708 declarations); **died on a one-line keychain reader bug** (`cloud-create-api.py:183`, missing `-a`) that emitted a world-shaped error 719 times over 4 days; $32–112/closure; **21 of 29 lane closures cite evidence about a branch their session never touched**; its death was **detected by a human**, not by either of the two detectors built to detect it |
| **sevenrooms-bridge** — third-party authenticated integration | **54 d** (2026-07-20 → 09-12) | 195 | 49,879 | 6 rows still open, 2 blocked on operator; the re-login driver still cannot recognise the login page |
| **Codex certification probe** — *the exact analog: should anything route to a non-Claude backend?* | **2 d** (2026-08-10 → 08-11) | 8 | 9 briefs, 36 arm runs, 4 blind mixed-vendor judges, 144 judgments; **"~$20"** of candidate quota | **REJECT** — zero unique findings; *"uncertified means unrouted"* |
| **providers.json** — multi-provider registry | **1 d** (2026-08-10) | 5 | 1 JSON + renderer | **4 of 6 backends SKIPPED** on the cost gate |

**Estimate for union-alpha, built from that reference class:**

| component | estimate | basis |
|---|---|---|
| certification probe (**mandatory** — standing rule) | **2 days / ~8 commits / ~$20 candidate quota** | Codex probe, an exact analog |
| proxy + translation + a harness that can drive a non-Claude model through cc-dispatch | **30–50 days / 20–30 K LOC** | cloud lane, which needed 50 days *without* a translation layer or a foreign vendor |
| ongoing breakage | **~15% of all repo commits, sustained** | cloud lane's measured share of repo activity across its life |
| operator attention | **non-trivial and unbudgetable** | the cloud lane's death was found by the operator; its two purpose-built detectors had executed **0 times/day since 2026-09-08** |

⚠️ **And the operating exhaust compounds the §3.2 treadmill.** During the local chain's life, **367 of 1,561 trunk commits (23.5%) were `docs(drain)` journal entries** — the lane writing about itself. A second lane adds a second journal.

### 4.3 The steelman, and why it also fails

**Steelman:** the prize is not volume, it is **decorrelation** — a different vendor's model catching what Claude misses.

This is real and this box has measured it: `codex-probe-w3-verdict-2026-08-11.md` found that *"Codex judges refute 49–69 citation claims per Codex arm where Anthropic judges refute 2–3"* — genuine, certified, and it survived the REJECT.

**But it needs no build.** `claude-accounts --readout` reports **2 of 2 non-Claude backends already routable at zero marginal bill**: Codex CLI (`gpt-5.6-sol @ xhigh ✓proven`) and Pi·Codex, both on a ChatGPT Plus plan already held, `bills_outside_plan: no`. The decorrelation prize is wired, proven, and idle today. A week of engineering buys nothing that a `codex exec` call does not already buy.

---

## 5 · The counterfactual, in the operator's terms

`cc-mission list` (2026-09-17):

```
STALE | blocked-operator  | insomniacdenver.church.live-url               | YOUR MOVE — blocks everything below 9d
STALE | needs-source      | insomniacdenver.church.bottle-menu            | ask UNSENT — NEEDS-SOURCE ASK UNSENT
STALE | drafted           | insomniacdenver.church.balcony.floor-plan     | untouched 20d
STALE | drafted           | insomniacdenver.church.main-floor.floor-plan  | untouched 17d
STALE | drafted           | fleet.bottle-menu-cross-contamination         | untouched 13d
```

**What each of the five actually needs — and not one of them needs a token:**

| # | row | what is genuinely missing | who | est. operator time |
|---|---|---|---|---|
| 1 | Church · **bottle-menu** | **One field**: which guestlist link + access info to send Adam Padilla (Ops Manager, Vinyl Nightclub / Insomniac Denver, `adam@vinylnightclub.com`). He emailed us 2026-08-20 asking for it; **read, never answered, 27 days**. Our half of the reply is already drafted. | **operator** | **~5 min** |
| 2 | Church · **main-floor floor-plan** | The 19 table capacities. **Rides on the same reply as #1** — wording already drafted. Geometry already exceeds Heist (11 paths / 282 commands / 19 tables vs 8 / 160 / 10). | (discharged by #1) | **$0 marginal** |
| 3 | Church · **live-url** | Nothing. *"NEXT: nothing on this row."* Unblocks automatically when #1 and #2 land. The board's dependency arrow is inverted. | — | **$0** |
| 4 | Church · **balcony floor-plan** | **One ruling**: is a deck a TRACED OBJECT or an EDITORIAL SEATING REGION? Evidence regenerated and waiting at `/tmp/church-layer3.html` (487 KB, self-contained). Decision packet `2462a68c80c8` carries both options and their costs. The rule forbids agents pre-empting it. | **operator** | **~10 min** |
| 5 | Live fleet · **3 tenants bottle-menu** | **One name**: who to ask at The Key Collection. No `leadDomains`, no email thread, no SMS thread. Everything else on the row is already measured. | **operator** | **~2 min** |

> **~20 minutes of operator attention discharges 4 of the 5 rows directly and the 5th by dependency. A week of free tokens discharges 0 of 5 — structurally, because `cc-dispatch` cannot select a blocked-on-operator row by design.**

**And row 5 is money.** Backlog `05f63af4e918`, verbatim: *"Heist's seeded bottle prices are 6–40% UNDER its own printed menu on 20 items, and The Key serves a 60/60 copy — the same 20 under-prices are live in TWO rooms of the paying key tenant."* A measured under-pricing, live, at a paying customer.

🚨 **Two defects found in that row while checking it, both worth surfacing:**
1. **It was auto-closed on a falsifier that does not test the claim** — `done | falsifier passed: … ! git show origin/main:scripts/__tests__/menu-preset-parity.test.ts | grep -q "t2Misma" … (auto-closed by cc-premise sweep --close-falsified)`. The falsifier tested for a string in a test file; the money defect is in seeded price data. The row is closed; the under-pricing is not.
2. **Its block reason rests on a fact that has been false since 2026-08-02** — *"landing/deploying in reso also spends money by that repo's own CLAUDE.md."* reso cut over to LAND_SHIP_V2 (`fb76c35bb`); `/ship` is free there and `/deploy` is the only money-spender. The mission board's own live-url row says so in terms: *"landing is free."*

---

## 6 · Adversarial pass — what a hostile reviewer would say

| challenge | answer |
|---|---|
| **"You measured strand and found 3.17 account-weeks idle. That IS spare capacity."** | It is spare *because there is nothing to point at it*, not because work is waiting. 67% of all strand ever observed came from ONE week (R4, Sep 1–6) — the **lowest-throughput** week in the series. Three of four accounts stranded **0 pp** in the most recent complete round. Idle quota here is a demand artifact. |
| **"The ceiling DID bind in the last complete cycle — all four accounts hit 100%."** | True, and it is the strongest counter-fact in this document. But in that week **both drain lanes were already dead** (local's last closure 09-09, cloud's 09-12) and closures fell from ~94/day to ~17/day. The quota went to ordinary sessions and research waves — including the audit that produced this question. Adding capacity to a week that burns 100% while closing 17 rows/day adds volume to the wrong thing. |
| **"Wiring it is a one-line `ANTHROPIC_BASE_URL`, so the cost side is fiction."** | Anthropic's docs, verbatim: Claude Code *"doesn't support routing … to non-Claude models through any gateway."* And the Claude-model path *replaces* the subscription rather than adding to it, billing per token. Both arms are closed by the vendor, not by our policy. §4.1. |
| **"Maybe free tokens should go somewhere other than the drain."** | The highest-value target on the box is the mission board, and **5 of 5 rows are operator-blocked**. No capacity reaches them. §5. |
| **"More capacity → more closures → faster to zero."** | Refuted by the box's own data: **0.502 new rows minted per closure** (p < 0.001), and **1,635 closures moved the actionable board +40**. Doubling throughput roughly halves the marginal benefit per closure and doubles the journal exhaust. §3.2. |
| **"The real prize is vendor decorrelation, not volume."** | Certified real at the *judging* layer — and **already available at zero build cost**: 2 of 2 non-Claude backends routable, `bills_outside_plan: no`, idle. §4.3. |
| **"Free tokens would let us stop worrying about the 107 K preamble."** | Inverted. The preamble is **$0 today** (cache_read is free against the Max meter) and **$6.37–$63.67 per session** on any metered route. The audit's single largest controllable cost lever is the one a gateway degrades. §1.3. |
| **"Your $ figures prove the fleet is expensive."** | They prove the opposite: **$13,733/week of list-price inference, $0.00 invoiced.** The incumbent's marginal cost is already zero. Free cannot underprice free — it can only add volume, and volume is not the constraint. |
| **What I could not check** | (a) I do not have union-alpha's actual terms — model list, rate limit, cache pricing, window length. Every number here is parameterised so the conclusion survives any generous value (§3.4). (b) `cc-quota-price` **ABSTAINED** on the price fit at every window I tried (`--since 30d --bucket-h 24` → *"0 bucket(s) with a positive Δ weekly_pct"*), so the $30.79/pp rate is my own fold of the same two stores, not the tool's certified output; it agrees with `USAGE_TELEMETRY_100P §2.1`'s independent 261–360 K/pp to within the range. (c) Agent-hours are estimated from commits and calendar days — this box records neither session-hours nor operator-minutes anywhere I could find. |

### 6.1 One live defect found en route

`scripts/drain-chain-assert.sh` now reports **`chain ALIVE (live-lease) · 346 live row(s) · newest brief 626417s old`** — a brief **7.25 days old**, reported as ALIVE. The audit (§4.4) predicted exactly this: the alarm's glob `fire-drain-recycle*.txt` was broken by the 2026-09-04 lane rename to `fire-drain-infra-recycle<N>.txt`, and its verdict *"is right today only by accident."* It has now flipped to a **FALSE ALIVE** without any work resuming. **Do not read a healthy drain-chain assert as evidence the lane is running.**

---

## 7 · What the week should buy instead — ranked by measured leverage

Every one of these is larger than the 11–21-row free-token prize, and none needs a new vendor.

| # | action | measured size | cost |
|---|---|---|---|
| **1** | **The five mission rows** — supply the guestlist link, open `/tmp/church-layer3.html` and rule, name a contact at The Key Collection | **4 of 5 rows discharged directly, the 5th by dependency**; unblocks a paying customer's under-priced menu live in two rooms | **~20 operator-minutes · 0 engineering** |
| **2** | **Make `block --needs` as strict as `add --why-not-now`** and let dispatch see impossibility-classed blocked rows | **40–135 rows** currently *"agent work wearing a park"* (audit §7.2; 281 of 296 blocked rows carry no impossibility class, 158 have `needs` byte-identical to `title`) — **3–9× the entire free-token prize** | **~1 day, one verb** |
| **3** | **Cut the `re-land` generator** | 28.7% of inflow; its closures are ~100% no-op auto-retracts (83/83). Drops the mint rate from 0.502 toward the 0.33 causal floor | ~1 day |
| **4** | **Give the local lane a scheduler** | It is the cheapest worker on the box (≤$3.35/closure) and *"the only one with no way to start itself"* — it has no plist, no cron, no caller | hours |
| **5** | **Land cloud branches on a clock (+1 h)** | **90% of 296 stranded branches would have landed**; converts already-paid-for compute into delivered work | ~1 day |
| **6** | **Shrink the 107 K resident preamble** | **≥43% of a drain session's bill**, and *"the one lever that moves the denominator and the numerator at once"* | ~1 day |

---

## 8 · Conviction, and what would move it

> **94%** — a week of engineering on the free-token pipeline is net-negative and should not be built.
> **97%** — the same week's *operator attention* (~20 minutes of it) belongs on the five mission rows.

**Why not higher than 94%:** I do not hold union-alpha's actual terms. If it turned out to serve Claude models in Anthropic format, free-forever with no post-window billing, with working prompt caching, the *wiring* cost collapses toward zero — and then the question reduces to §2 and §3, which it still loses, but on one argument instead of three.

**What would move it above 94% (toward "never build"):**
- Union-alpha's free window is finite and post-window traffic bills per token → `spend.usage_credits_authorized=false` closes it outright, no further analysis needed.
- The `:free` model list is open-weights only → the Codex-probe precedent (a *frontier* non-Claude model returning zero unique findings) becomes an a-fortiori argument.

**What would move it below 90% (toward "probe it"):**
- **Three consecutive fleet-weeks at 100% on all four accounts *with* a non-empty substantive drainable queue.** Today: 1 of 5 weeks saturated, and in that week the lanes were dead and the queue was 34 rows.
- **The substantive drainable queue at 300+ rows rather than 15**, i.e. the §7.2 blocked-pile retrofit lands first and the board genuinely has more work than capacity. *This ordering matters: fix the queue, then re-ask the capacity question. Never the reverse.*
- **A certification probe showing the free model closing rows at ≥ the local lane's 43% delivered rate.** That probe is 2 days and it is the *only* part of this proposal worth running on its own — and it should be run against the already-routable, already-paid-for Codex CLI first, because that arm costs nothing and is idle today.

---

## 9 · Commands that produced every number

```bash
# §1.2 token census + fleet burn
~/.claude/bin/cc-quota-price --census
python3 -c "…"   # sum positive Δweekly_pct per acct over last 7d from account-utilization.jsonl
~/.claude/bin/cc-quota-price --since 30d --bucket-h 24     # → ABSTAIN (0 positive-Δ buckets)

# §2.1 live readout
claude-accounts --readout

# §2.2/2.3 strand per cycle
python3 -c "…"   # group account-utilization.jsonl by (acct, weekly_reset_at rounded to hour); strand = 100 − peak weekly_pct

# §3.1 live queue + exhaust classification
python3 -c "…"   # fold backlog.jsonl add/done/block/reopen/claim → terminal state; classify open titles
sed -n '1915,1930p' bin/cc-dispatch ; grep -n 'status=="open"' bin/cc-dispatch

# §3.2 treadmill
python3 -c "…"   # daily add/done counters over backlog.jsonl, Pearson r + slope, 2026-08-18..09-17

# §3.4 free-tier reality
WebSearch "OpenRouter free tier rate limits requests per day 2026 :free models"
WebSearch "Cloudflare AI Gateway pricing free tier token limits 2026"

# §4.1 vendor constraint
WebFetch https://code.claude.com/docs/en/llm-gateway
env | grep -i ANTHROPIC ; grep -n ANTHROPIC_BASE_URL ~/.zshrc ~/.claude*/settings*.json

# §4.2 reference class
git log --oneline --since=2026-07-29 --until=2026-09-17 | wc -l        # 3818
git log --oneline --since=2026-07-29 --until=2026-09-17 --grep=cloud -i | wc -l   # 591
git ls-files | grep -iE cloud | xargs wc -l                            # 30510 / 73 files
git -C ~/Development/sevenrooms-bridge log --oneline | wc -l           # 195

# §5 mission board
cc-mission list ; cc-mission next
python3 -c "…"   # grep backlog.jsonl for 05f63af4e918

# §6.1 the false-ALIVE alarm
bash scripts/drain-chain-assert.sh
```

**Sources (web):**
- [OpenRouter Rate Limits](https://openrouter.zendesk.com/hc/en-us/articles/39501163636379-OpenRouter-Rate-Limits-What-You-Need-to-Know) · [OpenRouter API Credit & Rate Limits](https://openrouter.ai/docs/api_reference/limits) · [OpenRouter Free Tier 2026](https://pricepertoken.com/endpoints/openrouter/free)
- [Cloudflare AI Gateway pricing](https://developers.cloudflare.com/ai-gateway/reference/pricing/) · [Cloudflare AI Gateway Pricing Explained For 2026](https://www.truefoundry.com/blog/cloudflare-ai-gateway-pricing)
- [Claude Code — Other LLM gateways](https://code.claude.com/docs/en/llm-gateway)
