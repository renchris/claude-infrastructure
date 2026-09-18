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

## THE STRONGEST REMAINING JOB DOES NOT NEED THE LANE AT ALL (measured 2026-09-17)

§"Where Union Alpha CAN be used" ranks **job 2** — the false-closure audit over `done`
evidence strings — as the largest and best-oracled of the three. Measured against the
live store, it is **deterministic**, and the model was never doing the load-bearing work.

Its oracle is already `git merge-base --is-ancestor`. The only thing an LLM was being
asked for is *extracting a sha from free text* — which is a regex:

| | count | share |
|---|---|---|
| `done` rows carrying evidence | 3,410 | — |
| carry ≥1 sha-shaped token (regex, pure-digit runs excluded) | **2,811** | **82.4%** |
| carry none | 599 | 17.6% |
| distinct sha candidates | 3,563 | — |
| resolve in this repo (`git cat-file --batch-check`, one call) | 2,159 | — |

So ~82% of the job is regex + git: no model, no key, no vendor, no data-policy question,
no money, and seconds instead of 31 minutes. This is the dossier's own §"Explicitly NOT
rented to it" principle — *"Most 'bulk LLM' jobs here have deterministic solutions"* —
applying to its own job 2.

🚨 **And the naive deterministic version is WRONG in the direction that manufactures
findings, which is why this is recorded rather than shipped.** On a 400-sha sample of
shas that resolve here, **155 are not ancestors of `origin/main`**. That is an **upper
bound on false closures, not a count of them**, because this repo's own corpus already
records the mechanism: *a rebased land rewrites the object, so `--is-ancestor` rc 1 reads
as never-landed over content that is on trunk* (`cited-sha-may-not-survive-the-land`).
A further 1,404 candidates do not resolve here at all — another repo's sha, or an object
rewritten away — and that is **not** evidence of non-landing either (`absent-from-trunk-
has-two-opposite-causes`).

A stage-1-only tool would therefore report ~155 confident "false closures" whose true
count is unknown and much smaller — **the exact defect class the audit exists to find**.
The honest build is two-stage and still fully deterministic: ancestry first, then a
CONTENT check (patch-id, or the commit's paths against trunk) for every non-ancestor,
and a separate "not this repo" bucket that is never scored. That is real work and it was
not started here; what is settled is that **it needs no model**, so it is not blocked on
the key, the egress allowlist, a vendor's data policy, or anything in this dossier.

**Why it is worth building.** This session's predecessor found a row about a **paying
customer's bottle prices** (`05f63af4e918`) that had been *falsely auto-closed* by a
falsifier whose `git -C` bound only the `fetch`, so `git show` ran in the sweep's cwd and
retracted vacuously — blast radius 1 of 597. The audit's purpose is finding more of that
class, and it can run today.

## ⚠️ CORRECTION TO THE SECTION ABOVE — "the free premise is gone" was WRONG (2026-09-17, same day)

The operator challenged the recap ("Isn't it launched today, and free for a whole week via
OpenRouter and Cloudflare?") and he is right. Two claims in §"THE SUBJECT MODEL NO LONGER
EXISTS" are corrected here **in place; the original words stay** as the record of what was
believed and why the error was reachable.

**WRONG — "Union Alpha is dead."** What retired is the stealth **alias**, because the model
was **revealed and launched**. The 404 body says so in its own words ("This model *was*
Unbiased's Pareto. **Use it now**"). A stealth alias retiring at launch is the opposite of a
model disappearing, and the Ox Alpha precedent — a model deleted from the catalogue — primed
the wrong reading of an identical-looking 404.

**WRONG — "the free premise the three jobs rested on is gone."** There IS a free route, and
OpenRouter's own FAQ states it verbatim:

> *"Is Pareto Code Router free? Yes. The pricing shown on this page for Pareto Code Router
> is zero, so you are not charged for prompt or completion tokens."* — `openrouter/pareto-code`,
> **2,000,000** token context.

**STILL TRUE, and all of it measured rather than inferred:**

- `stealth/union-alpha` returns 404.
- The **direct** model `unbiased/pareto` is genuinely paid — $2.50/$7.50 per MTok, and its
  embedded page payload carries `"is_free": false` with `promotion_message: null`. The free
  access is via the **router**, not via that id. Reading the direct id's price and concluding
  "no free route exists" is the whole error: **one id's price is not the product's price.**
- Our key 403s on **both** pareto ids with `Key limit exceeded (total limit)`, while all three
  explicitly zero-priced `:free` models return 200 on the same key in the same minute.

### The real blocker is our own safeguard, not the price

`GET /api/v1/key` reports `limit: 0`. The 24 models priced exactly `0` are callable; both
pareto ids advertise `prompt=-1, completion=-1` — *router-determined, not provably zero at
request time* — and a zero-limit key refuses those. (That the `-1` is the mechanism is
**inference**; what is measured is the 403 on `-1`-priced ids beside 200s on `0`-priced ids.)

So the free week is real and we cannot reach it, for exactly the reason we chose: the key was
deliberately left spend-incapable *by construction*. Unlocking it means raising the key's limit
above `0`, which trades that property away — the effective charge would be ~$0, but no longer
**provably** $0. **That is a money-path decision and it is the operator's.**

### Method note — why a spend-incapable key is a BAD instrument for "is this free?"

A `limit: 0` key answers "is this id's listed price literally zero", which is *not* the
question "is this model free to use this week". It cannot see a promotion, a router whose
effective price is zero, or any billing-time discount — it refuses all of them identically,
with an error naming the KEY rather than the price. Reading that refusal as evidence about the
market is the same shape as
[[reference-a-refusal-bounds-the-tool-not-the-world]]: **a refusal bounds the instrument, and
its message names world-shaped causes, so it gets believed as a fact about the world.** The
discriminating instrument here was not the API at all — it was the vendor's own pricing page.

## ⚠️ SECOND CORRECTION — the router is NOT free either (measured with money, 2026-09-18)

The correction above said free access exists via `openrouter/pareto-code`, quoting OpenRouter's
FAQ. **That was wrong too, and this one was settled by spending real money rather than by
reading.** The operator raised the key's cap from `0` to **$1**, which is what made the
experiment possible and what bounded being wrong — the cap did exactly its job.

### What the FAQ actually means

> *"Is Pareto Code Router free? Yes. The pricing shown on this page for Pareto Code Router is
> zero, so you are not charged for prompt or completion tokens."*

It means **the ROUTER takes no markup**. The model it dispatches to bills normally. "The router
is free" and "the inference is free" are different claims, and the page only supports the first.

### Measured

| | |
|---|---|
| `openrouter/pareto-code` dispatches to | **`anthropic/claude-fable-5.1`** — 8 of 8 calls, every prompt type |
| cost per small call | **$0.00036 – $0.00242**, billed |
| total spent establishing this | **$0.00943675** of the $1 cap |
| control: 3 × `inclusionai/ling-3.0-flash-vl:free` | **$0.00000000** |

Sum of every reported per-call `usage.cost` across 13 calls = **0.00943675**; final key `usage`
= **0.00943675**. Exact match ⇒ **every reported cost is billed.** The 24 `:free` models are
genuinely free; the routers are not.

### 🚨 The instrument error, which nearly landed the opposite conclusion

**The `usage` counter is EVENTUALLY CONSISTENT, with latency > 35s — so a same-session
before/after delta attributes arm N's cost to arm N+1.** Measured, with the arms inverted:

| arm | reported cost | observed usage delta |
|---|---|---|
| 1 — three `pareto-code` calls | $0.00108 | **$0.00000000** |
| 2 — three `:free` calls (control) | $0.00000000 | **$0.00108** |

The probe printed **"=> pareto-code is FREE to us"** and the control arm looked like the thing
costing money. Both exactly backwards. Nothing in either arm was wrong except *when* the
counter was read.

⇒ **A cost/usage counter must be settled with a NO-NEW-CALLS hold before any delta is a
measurement.** The disambiguating test spends nothing: stop calling, then poll the counter until
it stops moving (here it held at `0.00943675` across 120s). Only then does a delta attribute.
And the cheapest check of all is the one that caught it — **reconcile the sum of per-response
reported costs against the account total**; they agreed to the cent, which is what proved the
lag rather than a discount.

Same family as this repo's alarm/latency rules, with a sharper edge: an eventually-consistent
counter does not merely go stale, it **transplants** a value from one window into the next, so a
control arm can be convicted of the treatment arm's cost.

### Where this leaves the lane

- Genuinely free and verified answering: the **24 `:free` models** (3 controlled at $0).
- **Not free:** `unbiased/pareto` (listed price), `openrouter/pareto-code`, and by the same
  mechanism every `-1` router (`auto-beta`, `fusion`).
- The operator's "free for a week" report is **not refuted** — it may describe a promotion not
  applied to this account, or the Cloudflare path, which remains **unmeasured**. What is refuted
  is *this* route being free.

## THE DETERMINISTIC AUDIT WAS BUILT AND RUN — AND IT FINDS NOTHING (2026-09-18)

§"THE STRONGEST REMAINING JOB DOES NOT NEED THE LANE" said the honest build was two-stage and
"was not started here". It has now been built (`scripts/backlog-closure-audit.py`) and run.
**Its mechanism claim holds and its VALUE claim does not.** Recording the negative so no future
session rebuilds it.

### It works

400 most recent `done` rows: **258 on-trunk · 1 content-landed · 4 SUSPECT · 68 foreign (not
scored) · 69 no-sha (not scored)**. Stage 2 earns its place immediately — a naive stage-1 pass
flags ~39% of resolvable shas as non-ancestors, and content-comparison clears almost all of
them, exactly as `cited-sha-may-not-survive-the-land` predicts.

### But its SUSPECT precision is 0 of 4

Every SUSPECT is a **role misattribution**, not a false closure. The tool assumes any cited sha
is a landing *claim*; these cite a sha as the **subject**:

- *"The row claimed 11 commits stranded across 4 orphaned branches"* — a sha being discussed.
- *"branch commit a0de7f605→a37feb5a9"* — progress, not a landing.
- *"The tracked test file was reverted"* — a sha in a revert.

Deciding **whether an evidence string is even making a landing claim** is the genuinely
non-deterministic part, and it is upstream of the oracle. The regex extracts the sha; nothing
extracts its *role*.

### 🚨 And the positive control FAILS — it is blind to the only known instance

The one confirmed false closure, `05f63af4e918` (a paying customer's bottle prices, the row that
motivated this whole idea), closed on evidence reading:

    falsifier passed: git -C <reso> fetch -q origin && ! git show origin/main:<path>

**No sha at all** ⇒ classified `no-sha` ⇒ **not scored**. The defect was never "a cited sha did
not land"; it was a falsifier whose `git -C` bound only the `fetch`, so `git show` ran in the
sweep's cwd and the negation passed vacuously. A sha-ancestry audit cannot see that class.

⇒ **An audit must be positive-controlled against a KNOWN instance of the defect it is built to
find, before its clean run is read as an absence of defects.** Ours reported 263 scored rows and
0 real findings, which is indistinguishable from a healthy corpus — and it could not have found
the one case we already knew about.

### The adjacent audit, also run, also negative

Falsifier vacuity is the real class. Measured: **1,001 rows carry a stored `--falsifier`, 94
were closed on `falsifier passed`**, and a deliberately over-generating scan flags 15. On
inspection nearly all are **guarded** (`grep -q X file && ! grep … file`) — the leading positive
grep proves the subject is readable before the negation runs. **Polarity is what makes the
guarded form safe:** an unrunnable `grep|grep` returns rc 1, the falsifier does NOT fire, and the
row stays open. A vacuous *pass* retracts a live row; a vacuous *fail* merely annoys. Only an
**unguarded negation** is dangerous, and the one measured instance was already cured.

### Disposition

The tool is landed and re-runnable (`--limit`, `--json`, exits 0). Treat it as a **ratchet, not a
detector**: a rising SUSPECT count is signal, a clean run is not evidence. Its blind spot is
documented in its own docstring. **The job-2 idea is closed** — not because the mechanism was
wrong, but because the defect class it targets is not the one that bites us.

## THE CLOUDFLARE ROUTE IS A DIFFERENT QUESTION, AND union-alpha IS STILL THERE (2026-09-18)

Operator challenge: *"Why are we talking about pareto instead of Union Alpha? If OpenRouter
isn't as advertised for fully free Union Alpha usage, let's go with Cloudflare?"* Both halves
are answered here, and the second one changes the state of this dossier.

**On the first: Union Alpha IS Pareto.** OpenRouter's 404 body — *"Thank you for participating
in the Stealth Union Alpha testing period. This model **was** Unbiased's Pareto"* — says the
stealth codename and the launched product are the same weights. There is no longer an
addressable `union-alpha` id **on OpenRouter**. Talking about Pareto is talking about Union
Alpha.

**On the second — and this was worth the challenge: Cloudflare is NOT the same question, and
still carries the model.** Measured today against the public catalogue, no credentials needed:

| | |
|---|---|
| `stealth/union-alpha` in Cloudflare's catalogue | **LISTED** — 1 of 161 ids |
| `unbiased/pareto` | also listed |
| negative control (`stealth/definitely-not-a-model-xyz`, `nonsense/qqqq`) | **404** — the instrument can say no |

So one vendor retired the alias at reveal and the other did not. **A model's availability is a
property of the VENDOR, not of the model** — the same error as reading one id's price as the
product's price, one level up. This dossier's §"THE SUBJECT MODEL NO LONGER EXISTS" is
OpenRouter-scoped and should be read that way.

### What A2 already settled, and the one thing it could not

`A2-cloudflare.md` did this work properly on 2026-09-16 and its findings stand:

- **Cloudflare publishes no price** for union-alpha (no Model Info table at all), while every
  generated example returns `"cost": 0`. Free **by example, not by policy**.
- **"Free for a week" is OpenCode's framing, not Cloudflare's** — *"Union Alpha Free is a
  stealth model available on OpenCode for a limited time."* Cloudflare states no end date, no
  preview, no week; the hard `2026-09-23` is a community claim from a GitHub issue. So the
  operator's recollection traces to **OpenCode Zen**, a third route this dossier has not tested.
- **The data policy remains the disqualifier** (kill #4): prompts *"may be retained by the
  provider"*, Cloudflare withholds its Zero-data-retention badge from this model specifically
  (it grants it to 90 of 226), and its ZDR switch supports only OpenAI and Anthropic, so a
  stealth request **falls back to non-ZDR**.
- **Rate ceiling** 200 req/60s per gateway, BYOK-exempt — and you cannot BYOK a stealth provider.

**The UNKNOWN A2 could not close by reading:** the REST-API doc says *"Ensure your Cloudflare
account has sufficient credits loaded before calling third-party models"*, yet union-alpha's
every example is `cost: 0`. **Is a zero-cost model actually gated on a non-zero balance?** Only
a call answers it. Do **not** assume the OpenRouter result carries over — there the answer was
*gated for variable-priced, ungated for explicitly-zero*, which is a fact about OpenRouter's
limit check, not a law.

### Built to close it

- `union-batch.py` gained `--endpoint` and `--key-env`, so the same screened, map-shaped harness
  drives Cloudflare unchanged (its API is OpenAI-compatible). All 7 guards re-proved and the
  OpenRouter path regression-tested live.
- `union-alpha-route-probe.sh <cf|zen>` — read-only, sends ONE completion, checks its own
  preconditions and names the exact remedy for each. It writes **no** credential, config or allowlist entry: those
  are the operator's, never an agent's to script. Verified it stops at rc 2 with nothing sent.

Endpoint shape, from the docs rather than guessed: `POST /accounts/{account_id}/ai/v1/chat/
completions`, `Authorization: Bearer $CLOUDFLARE_API_TOKEN`, token permission **Account >
Workers AI > Read**. Notably **no gateway id is required** on this path — an account id suffices.


## A THIRD ROUTE, AND IT IS THE ONLY ONE THAT SAYS "FREE" IN ITS OWN WORDS (2026-09-18)

A2 mentioned OpenCode Zen in passing as the source of the "free for a week" framing. It was
never tested. It is now, and it carries the model:

| route | id | state today | says free? |
|---|---|---|---|
| OpenRouter | `stealth/union-alpha` | **404** — alias retired at reveal | successor `unbiased/pareto` **BILLS** ($0.0094 measured over 13 calls) |
| Cloudflare | `stealth/union-alpha` | **LISTED**, 1 of 161 ids | by EXAMPLE only (`cost: 0` in samples); CF publishes no price |
| **OpenCode Zen** | `union-alpha` | **LISTED as "Union Alpha Free"** | **YES, in its own words** |

Negative-controlled on both live hosts (a nonsense path 404s), so the checks can fail.

🚨 **Zen speaks the ANTHROPIC MESSAGES schema** (`@ai-sdk/anthropic`,
`https://opencode.ai/zen/v1/messages`), not OpenAI chat-completions — and the two differ in ways
that fail **silently**, which is why this needed code and a test rather than a URL swap:

- `system` is a **top-level field** in Messages and a message **role** in OpenAI. Send it as a
  role and nothing errors; the instruction is simply ignored.
- A Messages reply is a **list of content blocks**. Concatenating all of them folds a thinking or
  tool block into the answer, which reads as the model rambling rather than as a bug.

`union-batch.py` gained `--schema {openai,anthropic}` and `--auth {bearer,x-api-key}`;
`test-union-batch-schema.py` pins both shapes offline (no key, nothing sent). The test has
measured power: mutating the block filter to fold **every** block turns it red, and the OpenAI
path is regression-asserted in the same run and re-verified live.

**Zen needs one credential and no account id** — *"You login to OpenCode Zen and get your API
key"*. That makes it the cheapest of the three to try, and the only one whose own price table
says Free.

**Kill #4 still governs all three.** A2 recorded that Zen and OpenRouter publish **incompatible
retention claims** about the same anonymous lab — Zen asserts zero-retention and no training,
OpenRouter says prompts *"may be retained by the provider"* — and neither is auditable because
the counterparty is undisclosed. Where two vendors disagree about a third party, the conservative
reading governs: **assume retention**, and let the content filter do its job.
