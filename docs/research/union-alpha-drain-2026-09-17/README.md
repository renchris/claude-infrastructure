# Should the 24/7 cc-backlog drain run on free Union Alpha via Cloudflare AI Gateway / OpenRouter?

**Asked** 2026-09-17 — *"Investigate if we should set up our local 24/7 cc-backlog drain pipeline
with @CloudflareDev AI Gateway and/or OpenRouter with this week's free usage of Union Alpha … to
maximalize free tokens to outcomes (still using our own Opus 5 high reasoning effort model to
validate at the end)."*

**Answer: NO.** Conviction **96%**. Ten read-only research axes, each with its own artifact in this
directory. Five independent arms each kill it alone; the load-bearing one is not about Union Alpha
at all.

---

## THE ONE-LINE REASON

**We already ran this experiment.** `~/.claude/providers.json` has carried **two routable,
cost-gate-passing, zero-dollar non-Claude backends since 2026-08-10** — Codex CLI and Pi·Codex, both
inside ChatGPT Plus, `bills_outside_plan:false`. **Zero drain work has ever been routed to either,
and they have produced zero closures in five weeks** (A4). Free third-party capacity has been
sitting unused on this box for over a month, because capacity was never what the drain lacked.

Meanwhile this box **strands its own paid capacity**: 21 complete account-cycles = **351 pp = 3.51
account-weeks dead unused**; last 4 per account = **317 pp ≈ $9,760** of Opus-5-list-equivalent
(A8). At the time of writing, `next3` sits at **7% weekly with ~47pp forecast to die at reset**
while `next2` is at 100%. **The constraint is distribution, not capacity** (A7).

---

## THE FIVE INDEPENDENT KILLS

Any one is sufficient. They do not share a premise.

### 1 · The chokepoint is eligible-row supply, and tokens do not touch it (A4, A5)

Measured live: `drain-pick.sh --project all --top 20` → **`eligible=12 shown=12 thrash_held=17`**.
Twelve rows is the entire drainable queue for every lane on this box.

| Test of "tokens are the constraint" | Result |
|---|---|
| Drain links that ever died on a quota/rate limit | **0** across all 140 drain-lane transcripts |
| Links that hit their own brief's ~60% context stop | **0 of 33** — median peak context 275,445 = **27.5%** of a 1M window |
| corr(spend, rows_closed) | **−0.039** (n=24) |
| corr(turns, rows_closed) | **−0.008** |

**308 of 346 live rows are `blocked`**; `cc-dispatch` selects `status=="open"` only
(`bin/cc-dispatch:1921`), and `cc-dispatch` *also* filters on `dispatch-projects.conf`, so the true
drainable queue is **29 rows, 28 of them `claude-infrastructure`** (A5). Of 308 blocked rows,
**207 (67%) are `source:"needs"`** — the verb that *means* operator-only — and **228 (74%) already
carry `master-operator-gated`**. A free token cannot unblock a row whose gate is *"OPERATOR VALUE
CALL"* or *"Press Enter in kitty pane 5"*.

### 2 · There is no volume to rent (A5)

**The entire blocked pile is 74K tokens — one context window.** The premise "maximalize free
tokens" presumes a corpus that does not exist here. Supporting kills: classification is already
running continuously (759 link events, latest 04:00Z the same day); `cc-premise cmd_coverage`
refuses this job in writing (*"`--run` PERFORMS the operator step it would be probing — no machine
oracle by design"*); 13 live falsifiers re-run → **0 retract**; `dups` finds **2 groups total**
(ids are hash-keyed, so duplicates are structurally rare).

The only genuinely over-window corpus on the box is a **816K-token false-closure audit** of 3,180
`done` evidence strings (known 21/29 base rate of bad evidence) — a different job than the one
proposed, and the only one worth piloting.

### 3 · The free tier cannot physically carry an agentic chain (A9, A1)

Measured from 150 drain-lane transcripts, deduped on `message.id` — one link =
**130 requests · 29.0M prompt tokens · 75K output · 1.45 h** (medians, two independent denominators
agreeing within 3%). 24/7 ⇒ **255–306M prompt tokens/day**.

- **Zero prompt caching.** `supports_implicit_caching:false`, no cache price keys, no
  `cache_control` — and this holds for **all 24 zero-priced OpenRouter models**. Caching is the
  entire economics of an agentic loop, which re-sends a growing context every turn.
- **Context ceiling breached by real traffic.** **20.4% of measured requests exceed union-alpha's
  262K ceiling** (p90 = 295K, max = 440K).
- **Rate limits are *not* the binder** — resolved against a disagreement between A1 and A9: the
  documented 20 RPM / 50–1000 RPD caps are scoped to ids ending `:free`, and this model is
  `stealth/union-alpha` with no such suffix. The real published figure is the endpoint record's
  `limit_rpm: 100`. Naming this because the tempting rebuttal ("just buy $10 of credits for the
  1,000/day tier") attacks the one constraint that was never binding.

### 4 · The data policy is disqualifying, and no hook can see it (A6, A1, A2, A7)

OpenRouter's Stealth EULA, read at origin: **"User Content will be logged in full and retained by
the Stealth Provider"** — an **anonymous** party; `retainsPrompts: true` in the catalogue; **no
opt-out preserves access** (the EULA says "refrain from accessing"). Cloudflare grants a
zero-data-retention badge to 90 of 226 models and **withholds it from this one**; its ZDR switch
covers OpenAI/Anthropic only and **fails open silently** for stealth.

What would be transmitted is not hypothetical. `drain-brief.sh:94-96` already ships a
**reso-management-app** lane — a private customer repo. `backlog.jsonl` carries 909 reso / 3,100
venue / 57 heist / 26 insomniac hits and ten production hostnames. And
`~/.claude/rules/00-mission-board.md` — present in **814 of 961** instruction-recording transcripts,
in all five config dirs — carries a paying customer's Ops Manager's **name, email, office and cell
phone, street address**, plus a production `libsql://` host.

> **Correcting A6 on its own evidence:** A6 concluded a fenced infra-only lane is defensible and
> "the difference is one `--project` flag." That is wrong by A6's own measurement — the mission
> board loads **globally**, so an infra-only drain link still ships customer PII. The `--project`
> flag fences the *repo*, not the *context*. A fenced lane would additionally require suppressing
> the global rules injection, which nothing today does.

**Architecturally decisive:** all 21 wired hook events are PreToolUse-class. **None fires on the
outbound inference request.** An `ANTHROPIC_BASE_URL` repoint relocates the entire context past
every guard at once, with no audit line. Note also that `openrouter.ai/api` and
`gateway.ai.cloudflare.com` are already catalogued in `agent-egress-catalogue.md:289,381` as egress
endpoints **to detect**, and `egress-redteam.md` lists `openrouter.ai` under **"Hosts to deny."**

### 5 · "Validate at the end with Opus 5" does not recover the saving (A10)

The proposal's load-bearing assumption, tested against this box's own probe corpus:

- **Verification ≈ generation.** Apples-to-apples on one bucket: 18 generation runs = **+5.0pp**;
  18 judge runs over the same 9 briefs = **+21pp** (`codex-probe-w3-verdict:367-370`) — **1.05× per
  output judged**. Independently: output tokens are **13.1%** of an Opus-5 turn's cost, context
  **86.8%** (n=65,904). Replacing the generator can recover at most the 13% slice, and validation
  forces those tokens back into the 24% cache-creation slice. Two methods, one answer: **V ≈ G**.
- **Half the cheap tier's defect is OMISSION, which no validator catches.** `fable-5.1@low` 6/36 vs
  `opus-5@max` 12/36. Validation is a filter; it cannot recover recall.
- **Validation is a full re-grounding, not a skim.** T2's fabrications (`computePull`, a
  non-existent comment, a hallucinated diff) were caught only by opening the file. Worse, a 4-judge
  frontier panel **inverted** on the citation axis (49–69 FP vs 2–3) — one validator is not
  decisive at any price.
- **Unattended, a weak generator amplifies the existing failure mode.** `rate × duration = 28–108`
  already; the chain's measured pathologies are thrash (17 ids re-claimed 8–23 times, 1 done) and
  false closure (21 of 29 cloud closures citing a branch their session never touched). Free
  generation multiplies `rate`.

---

## MECHANICS, FOR THE RECORD (A3)

Captured on the wire rather than reasoned about — Claude Code 2.1.260 pointed at a local fake
endpoint with `--model union-alpha` logged `[claude-code:unrecognized_model]` and **sent the id
anyway**: `POST /v1/messages?beta=true`, 7 beta headers, and a **69,961-byte body for the prompt
"say hi"** — 25 tools, block-form `system`, 3 `cache_control` markers, `thinking:{type:"adaptive"}`,
`output_config:{effort:"high"}`, `context_management`.

Two corrections to assumptions worth recording:

1. **No translation proxy is needed.** OpenRouter's Anthropic skin is real and measured:
   `POST openrouter.ai/api/v1/messages` returns **401 in an Anthropic-shaped error envelope**.
2. **This is not a licence violation.** Anthropic's gateway doc says Claude Code *"doesn't support
   routing … to non-Claude models through any gateway"* — a **support statement, not a
   prohibition**. The licence bars modifying the binary and intermediating Claude.ai credentials;
   neither applies. (A8 framed this as a hard bar; A3's reading is the accurate one.)
3. **`ANTHROPIC_BASE_URL` alone preserves the Max subscription; `ANTHROPIC_AUTH_TOKEN` replaces it
   and bills per token** (A9, correcting A2's blunter claim). This is why "put AI Gateway in front
   of our own traffic" is a cost *increase*, not an observability win — and it would add exactly one
   capability we lack: per-subagent parent-child attribution.

**The operational kill for an unattended chain:** `handoff-fire --account auto` halts when no
Anthropic Max account is routable, and auto-mode's classifier plus
`model-permission-decider.py:129` both follow `ANTHROPIC_BASE_URL` and **fail toward `ask`**. A 24/7
link would **wedge**, not error.

---

## PRECEDENT AND PRICE (A7)

The admission standard is 8 gates. Union Alpha **passes the dollar cost gate** (price literally
`0`/`0`) and fails routability, allowlist (`auto_mode_allowlist` is decompiled from `cli.js`,
Anthropic ids only), pin-proof (unfillable for a stealth model), and per-slot/per-effort
certification.

**That `providers.json`'s only gate is `bills_outside_plan` — a dollar question with no
retention/training/identity field — is the real gap this investigation found.** A free anonymous
vendor passes it trivially. The one data rule that exists (`KIMI_METERED_INTEGRATION.md`: *"don't
send anything you wouldn't send to a CN endpoint"*) applies *a fortiori* here but is not mechanical.

Certifying this to house standard costs what T4 cost — 4 waves, 3 dispatched sessions, ~2 days, 36
arm runs + 36 judge cells, ~21pp of a weekly window — and the drain **writes code**, so it needs a
behavioural gate T4 never built. Union Alpha launched **the same day** with a ~1-week window and an
EULA permitting withdrawal "with or without notice". **The certification does not fit inside the
asset.** The identical probe already ran against Codex and returned **REJECT**.

---

## WHAT TO DO INSTEAD

1. **Spend the stranded Claude quota, not someone else's free tokens.** ~47pp of `next3` dies at
   reset in ~5 days; `next2` is at 100%. Routing, not capacity.
2. **The five mission-board customer rows are all operator-blocked** and need roughly **20 operator
   minutes** — one email reply to Adam Padilla (discharges three rows), one layer-3 floor-plan
   ruling, one contact name for The Key Collection. Free tokens discharge **zero** of them,
   structurally.
3. **If a bulk-LLM job is wanted, the honest one is the 816K-token false-closure audit** — the only
   over-window corpus, with a deterministic oracle (`git merge-base --is-ancestor`). It costs
   **<$80 on Opus 5 directly**, against 3.19 account-weeks expiring unused. Pilot one shard.
4. **T5 is the unrun routing experiment that is actually worth running** — Opus-5 vs Fable at
   matched effort. Self-described "highest-value", explicitly cheap (corpus and pipeline exist),
   and it has no backlog row.

---

## DEFECTS FOUND AND FIXED DURING THIS INVESTIGATION

**A customer money defect was falsely auto-closed and is now restored.** Backlog
`05f63af4e918` — *"Heist's seeded bottle prices are 6–40% UNDER its own printed menu on 20 items,
and The Key serves a 60/60 copy — the same 20 under-prices are live in TWO rooms of the paying key
tenant"* — was auto-closed 2026-09-16T21:06:15Z by `cc-premise sweep --close-falsified`.

Its stored falsifier was:

```
git -C /Users/chrisren/Development/reso-management-app fetch -q origin && ! git show origin/main:scripts/__tests__/menu-preset-parity.test.ts | grep -q "t2Mismatches: 20"
```

`git -C` applies **only to the `fetch`**. The `git show` runs in the sweep's own cwd → fails
(`invalid object name 'origin/main'` from one directory, `path … does not exist in 'origin/main'`
from another) → empty output → `grep -q` fails → `!` inverts to **exit 0 = retract**. It passes
vacuously from any directory that is not a reso checkout.

Run correctly, the string is still present —
`origin/main:scripts/__tests__/menu-preset-parity.test.ts:106: t2Mismatches: 20` — **so the defect
is real and was live the whole time.**

- **Blast radius: exactly 1 of 597** falsifiers in the store carry a bare `git` after a `git -C`.
  Not a systemic class.
- **Restored**: `unblock --force` → `falsify` with a cwd-independent probe (verified exit 1 from
  three unrelated directories, including a `cat-file -e` existence guard so a renamed file fails
  *closed*) → `block --needs "Name the contact at The Key Collection …"`, which is the row's real
  gate (the tenant has no `leadDomains`, no email thread and no SMS thread, so no agent can open
  that channel).

**The generalizable gap, surfaced not filed:** `falsify` **runs** a probe before storing it and
refuses one that exits 0 (the retracting direction, per its own help text). `add --falsifier`
**stores without running**. The one vacuous falsifier in 597 came in through the unscreened verb.
Closing that gap means executing arbitrary shell at filing time on a path automation calls in bulk —
a real design trade, named here rather than made unilaterally.

**Also observed:** `drain-chain-assert.sh` reports **`chain ALIVE (live-lease)`** against a
**626,235-second (7.25-day) old brief** — a false-alive, inconsistent with the 2026-09-16 audit's
`DEAD` verdict from the same script.

---

## DECIDED AFTER THE VERDICT (same session, 2026-09-17)

The verdict above answers "should the DRAIN run on it." The operator then asked the narrower
questions, and these are the answers, none of which are derivable from the axes alone.

**An operator correction that stands, and it weakens one of my arguments above.** §"THE ONE-LINE
REASON" leans partly on stranded quota implying abundance. That is wrong: *"we are purposely not
exhausting our usage due to our usage working backwards — i.e. having both our cloud and local
pipeline drains off."* The stranded 3.51 account-weeks are the **shadow of switching the drains
off**, not spare capacity. The verdict is unaffected because it rests on mechanics, not economics —
but do not re-use the quota argument.

**Two mechanical kills, verified in our own source rather than relayed from an axis:**

1. `hooks/model-permission-decider.py` is a PreToolUse hook that shells out to `claude -p --model
   claude-haiku-4-5-20251001` with `env = dict(os.environ)` (line ~409) — the child **inherits
   `ANTHROPIC_BASE_URL`**. Repointed, it asks OpenRouter for a Haiku id that endpoint does not
   serve → `ERROR`, and the file's own comment fixes the fail direction as **"`ask`, never
   `allow`"**. An unattended link does not error; it **hangs** waiting for a human.
2. `scripts/handoff-fire.sh:5915` REFUSES the fire when `claude-accounts --route general` finds no
   routable account, and that router knows only the four Anthropic Max accounts. **The chain cannot
   fire its own successor** on a non-Anthropic backend.

Together: the drain would wedge on its first gated command and could not perpetuate even if it
didn't. Add that the drain's measured defect is **precision** (thrash, false closure, 74–76%
self-directed) while a free model is a **throughput** lever — throughput on a precision problem is
what produced 304 commits against 30 closures.

### Where Union Alpha CAN be used — the five-condition envelope

All five must hold: **(1)** called from a standalone script, never Claude Code (a plain `POST`
carries no `CLAUDE.md`, no mission board, no 128K preamble) · **(2)** tool-less and map-shaped, so
the missing prompt cache stops mattering · **(3)** under the 262K per-call ceiling · **(4)** no
customer content · **(5)** adjudicated by a deterministic oracle, or advisory-only — the model must
never be the thing that decides.

| | Job | Oracle | Calls |
|---|---|---|---|
| **1** | Score it on the frozen 36-defect corpus (where Opus-5@max = 12/36, Fable-5.1@high = 10/36) | anchored ground truth, already built | 36 |
| **2** | False-closure audit — 3,377 `done` evidence strings, 457K tokens, **2,872 (85%) carry no customer term** (measured) | `git merge-base --is-ancestor` | 2,872 |
| **3** | Contradiction sweep of our own rules corpus | each flagged pair is two line numbers | ~60 |

**Explicitly NOT rented to it:** auditing the 597 stored falsifiers for the cwd bug found this
session — a 12-line Python regex found the 1-in-597 in seconds. Most "bulk LLM" jobs here have
deterministic solutions; that is the same reason the drain does not need it.

### Throughput: the rate limit does not bind, by two orders of magnitude

All three jobs = **2,968 calls = 29.7 minutes at OpenRouter's 100 RPM**, on ONE key. Therefore:

- **OpenRouter key only.** Cloudflare's stealth path bills through Unified Billing, whose documented
  prerequisite is loaded credits + a 5% fee, and it publishes no context window. Real setup cost for
  capacity we do not need.
- **No multiple keys per provider.** That is rate-limit evasion; OpenRouter's Stealth AUP bans
  excessive request volume by name, and the likely outcome is losing access. Legitimate levers in
  order: concurrency *within* the published limit, smaller per-record prompts, sharding.
- **Leave the OpenRouter account UNFUNDED.** Union Alpha is priced `0`/`0`, so no credits are
  needed, and an unfunded account's key is **spend-incapable by construction** — a leaked key cannot
  bill. This also means declining the $10 top-up that raises the daily cap, which the arithmetic
  says we do not need.
- **No new vendors.** Two zero-dollar non-Claude backends (Codex CLI, Pi·Codex) have been routable
  since 2026-08-10 and produced zero closures in five weeks. A third vendor does not fix whatever
  kept those idle.

## AXIS ARTIFACTS

| File | Axis |
|---|---|
| `A1-openrouter.md` | OpenRouter union-alpha: pricing, limits, EULA, capability surface |
| `A2-cloudflare.md` | Cloudflare stealth + AI Gateway: billing, ZDR, Claude Code recipe |
| `A3-drivability.md` | Can Claude Code be driven by it at all — captured on the wire |
| `A4-mechanics.md` | Anatomy of one drain link; where the chokepoint actually is |
| `A5-pile.md` | What is in the pile; 15 verbatim rows; is there a bulk job |
| `A6-exposure.md` | What would leave the machine; standing policy; mitigations |
| `A7-priorart.md` | Precedent, the 8 admission gates, cost to certify |
| `A8-economics.md` | $/closure, stranded quota, the ceiling on the prize, counterfactual |
| `A9-throughput.md` | Measured demand/hour vs published supply; the gateway decoupled |
| `A10-verify.md` | Does cheap-generate + expensive-validate hold on our own data |

## BUILT AND MEASURED AFTER THE VERDICT (2026-09-17, successor session)

The harness for the three jobs now exists and is verified, **without a key and without
sending anything**: `union-batch.py` (map-shaped batch POST) and `customer-terms.txt`
(the deny list). Building it before the key exists was free, and it bought three
findings that change the job order below.

### The harness

`union-batch.py` is the executable form of the five-condition envelope. Conditions
(1)–(4) are enforced in code; (5) is a property of the job, so the script **refuses a
real run unless `--oracle` names the deterministic check** that will adjudicate the
output. Verified refusal paths, exit codes measured in bash:

| Guard | rc |
|---|---|
| screen dropped records and `--allow-drops` absent | 2 |
| `--oracle` absent on a real run | 2 |
| `OPENROUTER_API_KEY` absent | 2 |
| deny list empty (a filter that denies nothing) | 1 |
| unreadable input (a JSON parse failure is a verdict, not a skip) | 1 |
| `--check` found drops / found none | **3** / 0 |

**A verdict and an error never share an exit code.** `--check` returning "I screened
and found customer content" is rc **3**, not rc 1 — it is an ANSWER and the tool
worked. Sharing 1 with "I could not screen at all" would let a caller read a broken
screen as a dirty corpus, or a dirty corpus as a broken screen, and the second
direction sends. Full table: `0` clean · `1` hard error · `2` refused to send ·
`3` check found drops · `4` ran, some calls failed · `64` usage error.
(`64`, not argparse's default `2`, so "you typed the flags wrong" cannot be
mistaken for "a guard refused to send".)

The key is read only from the environment (`agent-secrets run --`), never argv, and is
never written to output, log or error. A failed call is classified by **HTTP status and
error text, never by tokens or cost** — a 429 after a full stream is a quota wall, and
the two are indistinguishable on usage fields.

### Finding 1 — a substring filter is not merely noisy here, it is useless

First screen of the 36-defect corpus: **9 of 9 briefs dropped.** Measured, almost every
hit was an artifact — `reso` matched `resolve` 37×, `resolved` 18×, `resource` 9× and
the product name **once**; `the key` matched "the keystroke" and "the keychain"; all
four "phone numbers" were epoch timestamps. Word-boundary matching keeps every term and
drops the artifact. **The deny list was never pruned to quieten it** — the matcher was
fixed, not the policy. Controlled both ways before it was believed: 4/4 seeded customer
records (venue, person+email, phone, API key) drop; 2/2 artifact records pass.

### Finding 2 — job 1 cannot rank, and its clean subset cannot compare

Two independent problems, neither of which is a reason not to run it, both of which are
reasons not to report it as a ranking.

- **Power.** Its own sibling analysis already measured this corpus:
  `fable51-vs-opus5-routing-2026-09-16/A4-our-measurements.md` §1.2 — Monte-Carlo over
  20,000 trials gives **4.8% power** at the observed rates, because **21 of 36
  ground-truth defects (58%) were found by no arm at all**. A 12/36-vs-10/36 comparison
  there is `+5.6 pp, 95% CI [−15.7, +26.8]`. A third arm inherits that floor.
- **Comparability.** After the boundary fix, **4 of 9 briefs are clean**; 5 carry
  `chrisren` (the operator's own username inside `/Users/chrisren/…` paths), `turso` and
  `libsql` (public DB CLI names inside a generic DDL-guard regex, beside
  `sqlite3|psql|mysql|mariadb`), and one `t@e.com` placeholder. **None of that is
  customer data** — but it is operator identity, and it is a ruling, not a measurement.
  The trap: running only the 4 clean briefs scores against a *different denominator*,
  so the number cannot be set beside 12/36 or 10/36 at all. **A frozen comparison corpus
  cannot be redacted without destroying the comparison it exists for.**

⇒ Job 1 is still the right thing to run **first**, re-labelled: it is a **smoke test**
— does this model return parseable, on-task output over a real brief — worth ~4 calls
and ten attended minutes before committing 3,114. It is not a ranking, and its result
must not be quoted against the Opus/Fable figures.

### Finding 3 — job 2 is the strongest job, and it is the one the filter actually earns

Screened independently with the corrected matcher: **3,114 of 3,403 `done` evidence
strings are clean (91.5%)**, against this document's earlier 2,872/3,377 (85%) — the
gap is substring over-dropping, and **the 85% figure is the more conservative one, so
both support the job.** Unlike the code-review corpus the drops here are *real*:
`chrisren` 126, `reso` 98, `amplify` 23, `reso.gl` 20, `the key` 18, `studio60` 14,
`heist` 11, `turso` 10, 13 email addresses. This is the job where the content filter is
load-bearing rather than ceremonial.

End-to-end dry run, no network: **3,114 calls, ~492K prompt tokens, 31 min at the
published 100 RPM** — reproducing this document's throughput arithmetic from the real
corpus rather than an estimate.

    python3 union-batch.py --check --in <corpus> --out /dev/null    # screen only
    python3 union-batch.py --dry-run --in <corpus> --out <results>  # + build payloads

### The blocker, corrected

This session's predecessor recorded the blocker as *"`agent-secrets setup` must be run
in Terminal"*. **Setup has already been run** — `agent-secrets doctor` reads keychain
custody primary, store present, decrypt self-test canary readable, and the store already
holds two unrelated secrets. `setup` is also documented as **headless in an agent
session**, so it was never the tty-gated step. The real remaining step is one command
and one paste, because `add` reads the value hidden from a terminal:

    agent-secrets add OPENROUTER_API_KEY

Unchanged and still correct: **never store `ANTHROPIC_API_KEY`.** Doctor's two ⚠ lines
about `apiKeyHelper` are the CORRECT state — satisfying them is what moves Claude Code
off the Max subscription and onto per-token billing.

## 🚨 THE SUBJECT MODEL NO LONGER EXISTS (measured live, 2026-09-17, same day)

The key was stored and the harness run end-to-end. `stealth/union-alpha` **returns HTTP
404**, verbatim:

> *"Thank you for participating in the Stealth Union Alpha testing period. This model
> was Unbiased's Pareto. Use it now: https://openrouter.ai/unbiased/pareto"*

**This dossier's own advice predicted it and was right** — §"WHAT TO DO INSTEAD" said to
assume the model vanishes mid-run because the prior stealth model (Ox Alpha) lasted six
days. Union Alpha's window closed on the same day it was analysed.

### What replaced it is PAID, and the key cannot reach it — by design

| | Union Alpha | `unbiased/pareto` (the successor) |
|---|---|---|
| prompt | `0` | **$2.50 / MTok** |
| completion | `0` | **$7.50 / MTok** |
| context | 262,144 | 262,144 |

The free premise the three jobs rested on is gone. **The unfunded-account decision in
§Throughput then did exactly its job**: `GET /api/v1/key` returns `limit: 0`,
`limit_remaining: 0`, `is_free_tier: true`, so the paid successor is not merely
ill-advised to call, it is **mechanically uncallable**. A spend-incapable key converted
a pricing change into a clean refusal instead of a bill.

### 24 of 445 catalogue models are still free; three were verified answering

One live wire call each, through the harness:

| Model | ctx | Result |
|---|---|---|
| `nvidia/nemotron-3-ultra-550b-a55b:free` | 1,048,576 | **200**, replied exactly `READY` |
| `nex-agi/nex-n2.5-pro:free` | 262,144 | **200**, `READY` |
| `inclusionai/ling-3.0-flash-vl:free` | 262,144 | **200**, `READY` |
| `nvidia/nemotron-3.5-lightning:free` | 1,000,000 | 200, but leaked its scratchpad on a trivial instruction |
| `thinkingmachines/inkling:free` | 1,048,576 | **403** — restricted, not generally available |

### What this does and does not settle

**Unchanged:** the verdict. The drain does not go on free inference, and the five
mechanical kills stand — none of them was about *which* free model.

**Open, and it is a decision rather than a measurement.** Conditions (1)–(3) and (5) of
the envelope are model-agnostic, and the filter enforcing (4) is vendor-independent. But
**kill #4 was specifically about the data policy**, and that analysis was about
OpenRouter's stealth tier, not about DeepInfra or BaseTen serving an NVIDIA free variant.
It cannot be re-settled from here: `GET /api/v1/models/<id>/endpoints` returns the
providers and quantisation but **no `data_policy` field at all** — measured on all three
candidates. So re-pointing the jobs at a surviving free model needs that one axis
re-checked against each vendor's published terms, by a human reading them.

⇒ **Do not re-point the three jobs at a substitute model on the strength of this dossier.**
It analysed one model that no longer exists; the class is not the instance.

### Harness defects found by running it for real

1. **No CA bundle.** python.org's macOS framework Python ships none —
   `ssl.get_default_verify_paths()` returns `cafile=None` AND `capath=None`, so every
   HTTPS call died `CERTIFICATE_VERIFY_FAILED`. Fixed by handing SSL a **real** bundle
   (`certifi`), never by weakening verification: an unverified context makes a hostile
   network indistinguishable from the endpoint, on a connection carrying a bearer token.
   A/B with one variable and no `SSL_CERT_FILE` in either arm: pre-fix `http=None`
   (never reached the server), post-fix `http=404` (real response).
2. **A default model is a trap once it dies.** `--model` is now **required**; a default
   pointing at a 404 fails at call time with an error that reads like an outage.
3. `agent-secrets run` enforces an **egress allowlist** (`~/.config/secrets/egress.allow`,
   a loopback CONNECT proxy). It held one host; `openrouter.ai` was added by the operator.
   This is why the first real call returned `Tunnel connection failed: 403 Forbidden`.

**The classification rule earned itself on the first run:** every one of these failures
was reported as what it was — a network error, a TLS error, a 404, a 403 — and never as a
quota fault, because the classifier reads status and error text rather than tokens spent.
