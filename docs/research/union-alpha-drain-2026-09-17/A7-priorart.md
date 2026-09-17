# A7 — Prior art & admission standard for routing the 24/7 drain to `union-alpha`

*Axis A7. Stance: default-to-refute. Every claim carries a file:line, URL or command. Written 2026-09-16.*

---

## VERDICT

**1. Does precedent permit this?** **No — and the refusal is over-determined.** Three independent
arms each block it on their own:

| Arm | Status | Why |
|---|---|---|
| **Standing rule** *"uncertified means unrouted"* | **BLOCKS** | Operator standing constraint 2026-08-10. The one prior cross-vendor candidate (`gpt-5.6-sol`) was REJECTED and the encoding of that REJECT was *to change nothing*. |
| **Data-egress posture** | **BLOCKS, and this is the decisive one** | OpenRouter's Stealth EULA, read at origin: *"your User Content will be logged in full and retained by the Stealth Provider."* The provider is **anonymous**. The drain reads a paying customer's repo. |
| **Harness mechanics** | **BLOCKS** | The drain lane is a Claude Code session fired by `handoff-fire.sh`. Its model is gated by `auto_mode_allowlist`, decompiled from `cli.js` — Anthropic IDs only. There is no seam to point at OpenRouter that is not a third-party harness, which is the **jcode** failure. |

**2. What certification is required?** The 8-point checklist in §2. Certification is **per-slot AND
per-effort**, scored by a **blind ≥3-judge default-to-refute panel** (mixed-vendor if the hypothesis
is cross-family independence), against a **frozen corpus of real briefs with anchored ground truth**.
The certifier is a **dispatched probe wave**, not a session's impression. No self-certification exists
anywhere in this file's history.

**3. What would that cost?** Using T4 as the reference: **4 waves, 3 dispatched sessions, ~2 elapsed
days, 9-brief frozen corpus, 36 arm runs + 36 judge cells**, and it consumed **~21 percentage points
of the candidate's weekly window** on the candidate side alone. A defensible certification of
`union-alpha` for **one** slot is **≥2 dispatched-session-days** plus corpus construction, and the
drain is a *code-writing* lane, so it would additionally need a behavioural gate T4 never had to build.

**Against a free window that expires in ~7 days.** `union-alpha` launched **2026-09-16** (today) and
is free for *roughly one week*. **The certification does not fit inside the asset.** You would spend
the fleet's scarcest resource certifying a model that is unmasked or priced before the verdict lands —
and T4's own closing warning is that a verdict is only valid against the incumbent it was measured
against.

> **The proposal also solves a problem the fleet does not have.** Live readout below: `next2` is at
> **100% weekly (LIMITED)** while `next3` sits at **7%** with **~47pp forecast to STRAND — to die
> unspent at reset**. The binding constraint is **distribution**, not **total capacity**. Free
> external capacity cannot fix a scheduling problem, and ~47pp of already-paid capacity evaporating
> this cycle is worth strictly more than a 7-day free window that has to be certified first.

**Recommended disposition:** REFUSE the routing. File the *gap* it exposed (§2, gate 8 — the registry
has no data-egress gate; a free model passes the dollar cost gate by construction). If routing
appetite exists, spend it on **T5**, which is already specified, unrun, and explicitly cheap.

---

## 1. PRECEDENT — has any of this been considered before?

### 1a. OpenRouter / Cloudflare AI Gateway / stealth models: **never proposed, and not absent by accident**

- **`~/.claude/providers.json`** — the SSOT for non-Claude backends — lists 6 providers
  (`codex`, `pi-codex`, `pi-claude`, `antigravity`, `gemini`, `grok`). **OpenRouter is not among them.**
- **Backlog store**: `grep -ic 'openrouter\|union-alpha\|union alpha\|ai gateway' ~/.claude/autonomy/backlog.jsonl` → **0**.
- **No credential exists**: no `OPENROUTER_API_KEY` in env, absent from keychain, no `~/.openrouter`,
  not referenced in `~/.zshrc` or any `settings*.json`. Adoption = a **new vendor relationship**, not a
  config flip.

**But both names DO appear on this box — on the wrong side of the ledger.** In
`~/.claude/plan-history/plans/agent-egress-catalogue.md:289` and `:381`, `openrouter.ai/api` and
**`gateway.ai.cloudflare.com`** are catalogued as **egress endpoints to detect**, in a document whose
sibling `egress-redteam.md` opens: *"Two paths send local data to a public cloud AI endpoint of exactly
the kind the operator is afraid of."* The `egress-redteam.md` remediation list names
`openrouter.ai` verbatim under **"Hosts to deny."**

> This is the sharpest precedent finding: **the two vendors in this proposal are already on this box's
> deny/detect list.** They have been considered — as a threat surface, not as capacity.

### 1b. The closest true analogue is **jcode** (2026-08-11), and it FAILED the gate

`docs/research/jcode-due-diligence-2026-08-11/cost-gate.md` — a third-party harness offering cheaper/
freer routing:

> **"Verdict.** jcode FAILS the cost gate… the exposure is not a bill but **the loss of the four Max
> subscriptions the entire fleet runs on.**"

The transferable half is **not** the ToS finding (union-alpha involves no Anthropic OAuth
impersonation — that specific reasoning does **not** carry over, and saying it does would be the drift).
The transferable half is the **shape**: a proposal whose headline is "free/cheaper capacity" was
refused because the *real* price was paid in a **non-dollar currency** the naive gate could not see.
For jcode that currency was account forfeiture. For `union-alpha` it is **data**.

### 1c. T4 — the one time a foreign vendor was actually evaluated

`gpt-5.6-sol` for `roles.research_adversarial`. **REJECTED** 2026-08-11.

> *"Over 36 anchored ground-truth defects there is **not one** that a Codex arm caught and neither
> Claude arm caught — at every vote threshold."*

Two lines from that probe bind this proposal directly:

> *"**Certified per-slot AND per-effort** — nothing here licenses Codex for any other slot."*

> *"**uncertified means unrouted**… a mostly-idle Codex window is the plan's stated correct resting
> state, not a failure."*

And the operator's own framing, `CODEX_ADVERSARIAL_SLOT_PROBE.md:26-28`:

> *"We don't want to exhaust usage for the sake of usage… **The $20 is not there to be spent**; it is
> there to buy independence at the two or three moments independence is worth more than raw
> capability."*

**Read that against this proposal.** The argument for `union-alpha` is *"free capacity exists, use
it."* That is precisely the argument the operator pre-emptively refused. Availability is not a reason
to route.

### 1d. The ONE genuine carve-out — state it, because it is the only honest path in

Not every cheap model on this box went through a probe. `model-routing-freewin-probe.md` T3:

> `research-decomposition-critic.md` `model: sonnet` — **DECISION: KEEP sonnet** (deliberate cheap
> ≤500-tok advisory decomposition gate; **the lead independently ratifies its APPROVE/REVISE output**
> → the framework's **cheap-classifier/advisory-gate carve-out** applies; not a quality-for-cost trade).

**The carve-out's condition is ratification**: the cheap model's output is *advisory* and a certified
model independently re-derives the decision. If any `union-alpha` use is proposed, this is the only
doorway with a lower evidentiary burden — and the drain does **not** fit through it, because the drain
**lands commits**. Its output is not ratified by anything; it *is* the artifact.

---

## 2. THE ADMISSION STANDARD — as a checklist

Assembled from `providers.json` (`_the_detection_rule`, `_the_cost_rule`, `_pin_proof_rule`,
`_stale_catalog_rule`), `model-config.yaml`, and the probe file's § Purpose.

| # | Gate | Standard | `union-alpha` |
|---|---|---|---|
| **1** | **Routability** | *"ROUTABILITY IS NOT PRESENCE."* Needs a **non-interactive agent mode** — not just a binary + auth. `headless: null` ⇒ not a backend. | ⚠️ An API endpoint is not an agent harness. Needs a harness; the sanctioned ones are Claude Code (allowlist-gated) and `codex`/`pi`. **No wired path.** |
| **2** | **Cost gate** | *"ASK WHAT IT BILLS, NOT WHAT IT CAN LOG INTO."* `bills_outside_plan` true **or UNKNOWN** ⇒ *"documented and SKIPPED — never wired, never signed up for."* Cross-check `accounts.json spend.usage_credits_authorized` (measured: **`false`**). | ✅ **PASSES** — price is `{"prompt":"0","completion":"0"}`, measured at `api/v1/models`. **This is the gap; see gate 8.** |
| **3** | **Allowlist (mechanical)** | `auto_mode_allowlist.non_firstParty_max` gates **all auto-mode leads AND all teammate spawns**. Derived from decompile of `cli.js`. Current: `[claude-opus-4-8, claude-opus-5, claude-fable-5, claude-fable-5-1]`. | ❌ **Cannot be listed.** The harness resolves IDs against Anthropic's API. Not a policy refusal — a mechanical one. |
| **4** | **Pin proof** | *"A CONFIG WRITE IS NOT A PIN."* Counts as proven only when the agent **ran and reported its own model id back**. `proven_by: null` renders UNPROVEN. | ❌ Unprovable for a **stealth** model — the id is a codename for an undisclosed model. `proven_by` is structurally unfillable. |
| **5** | **Per-slot certification** | ONE named slot per probe. *"nothing here licenses Codex for any other slot."* | ❌ Not run. "The drain" is not one slot. |
| **6** | **Per-effort certification** | Effort is **load-bearing** and does not transfer across models (T1/T2/T6). Anthropic: effort names do *not* mean the same thing across models. | ❌ Not run. `union-alpha` exposes no comparable effort ladder. |
| **7** | **The scoring rule — and it INVERTS by slot** | **Substitution slots**: panel TIE + cheaper ⇒ ADOPT; **any** reliable edge to the incumbent, *even ~1%*, ⇒ REJECT. **Verification/second-opinion slots**: score **NON-OVERLAP** — a tie is *redundancy* ⇒ REJECT; a head-to-head loss can still ADOPT if misses are uncorrelated. | ❌ Not run. Note the drain is a **substitution** slot ⇒ the strict rule applies: any reliable quality edge to Opus 5 rejects it. |
| **8** | **Data-egress gate** | 🚨 **DOES NOT EXIST IN THE REGISTRY.** `providers.json` asks what a backend *bills*, never what it *retains*. | ❌ **FAILS on the merits even though no gate encodes it** — see below. |

**Who certifies.** A **dispatched probe wave** with waves W1(corpus)→W2(grid)→W3(panel)→W4(encode),
strictly serial, W3 isolated from whoever produced the outputs. The verdict is recorded in
`~/.claude/model-routing-freewin-probe.md`. **`model-config.yaml` is flipped only on a certified
result** — and on a REJECT, *"the encoding IS the written rejection."* No session self-certifies.

### Gate 8 — the finding the lead most needs

Measured at origin, `https://openrouter.ai/terms/stealth`:

> *"your User Content will be **logged in full and retained by the Stealth Provider** for Stealth Model
> Training"* · *"User Content may be collected by us and **shared with the Stealth Provider**"* ·
> *"to **train, evaluate, and improve** those Stealth Model(s)"*

Confidentiality is **user-anonymity only**, not content confidentiality:

> *"User Content provided to Stealth Providers will contain a hashed identifier, such that each
> individual **user** will not be identified or identifiable."*

And per `openrouter.ai/provider/stealth`: *"developed and operated by a **third-party provider who has
chosen to remain anonymous**"*; *"OpenRouter routes requests to it and is **not its developer, owner,
or provider**."*

**Honest qualification (default-to-refute, applied to my own case):** the provider page also carries a
narrower line — *"Prompts and completions may be retained by the provider but are **not used for
training**"* — which is a per-listing carve-out over the EULA's default. **The carve-out is about
training, not about retention.** Under *either* reading the content is **logged in full and retained by
an anonymous party**. The retention is the problem; the training clause only makes it worse.

**What the drain would feed it.** Not toy briefs — `reso-management-app`: a **paying customer's**
(The Key Collection; Insomniac Denver) venue geometry, bottle-service pricing, tenant configs, and
SSM-token code paths. This is precisely the class `egress-redteam.md` calls *"the operator's exact
fear."* The public guidance on stealth listings is unambiguous: *"Do not send private code, client
material, credentials, personal data… or anything else you would not put into a logged evaluation
corpus."*

**Additional party:** routing via **Cloudflare AI Gateway** *adds* a logging intermediary rather than
removing one — CF AI Gateway's product function is request/response logging and caching. It makes the
egress posture worse, not better.

---

## 3. THE PRICE OF CERTIFYING `union-alpha`, benchmarked on T4

**What T4 actually consumed** (`CODEX_ADVERSARIAL_SLOT_PROBE.md` status log + W1/W2/W3 outcomes):

| Component | T4 actual |
|---|---|
| Waves / locus | 4 — W1, W2, W3 each a **dispatched session**; W4 lead-inline |
| Elapsed | **2026-08-10 → 2026-08-11** (~2 days), strictly serial (W1→W2→W3→W4) |
| Corpus | **9 briefs** (7 defective + 2 clean), **36 anchored ground-truth entries**, every `pre_fix_ref` resolving, gated by a `.bats` suite |
| Arm runs | **36** (4 arms × 9 briefs), each in a **fresh context**, tools hard-denied |
| Judge cells | **36**, blind **4-judge mixed-vendor** panel, 144 label→arm bindings verified byte-identical |
| Candidate-side quota | Codex weekly `used_percent` **22.0 → 27.0** (W2) → **~43%** (W3) ⇒ **~21pp of a weekly window** |
| Anthropic-side quota | **Never measured** — *"cost stays DIRECTIONAL and no $/finding figure was computed"* |
| Scars | orchestrator killed 3× mid-grid; a missing `timeout` binary manufactured 25 false results in ~40s |

**Extrapolating to `union-alpha`, honestly:**

- **Floor: ~2 dispatched-session-days + ~21pp of a weekly window**, and that is the *optimistic* read,
  because T4 reused an existing judging pipeline and W1's corpus construction still *"cost more than
  controls 1 and 2 combined."*
- **The drain is harder to certify than T4's slot was.** T4 scored a **read-only** slot on text
  outputs against anchored defects. The drain **writes code and lands commits** — certifying it needs a
  *behavioural* gate (does its diff pass the repo's gates; does it land the right thing) that T4 never
  had to build. Add corpus + harness work T4 did not pay.
- **Prior probes in this file ran 2.9M–13M subagent tokens** (T2: 21 agents / ~2.9M tokens / 252
  tool-uses / ~21 min for *one* A/B; the T2 effort grid: *"~13M subagent tokens across the 5 probe runs"*).

**Compare to the asset.** `union-alpha` is free for **~1 week from 2026-09-16**. A 2-day serial
certification consuming ~21pp of a weekly window would return a verdict with **~4 days of validity
remaining**, on a model that is by design about to be unmasked, renamed and priced. T4's own closing
caution — *"a probe against a different incumbent could legitimately reach a different answer"* — means
the verdict would not even survive the model's re-release under its real name.

**And the free capacity is thinner than it sounds.** OpenRouter free-tier limits: **50 free-model
requests/day** under $10 lifetime credits, **1,000/day** once ≥$10 is purchased, with a hard **20
req/min** ceiling on `:free` IDs, and **429s still consume the daily quota**.
*Named uncertainty, not asserted:* `union-alpha`'s ID is `stealth/union-alpha` with **no `:free`
suffix**, so whether the `:free` caps bind it is **unmeasured**. If the 50/day figure applies, the
entire free window is worth **~350 requests** — not a 24/7 drain. If it does not, the cap is unknown,
and *unknown* is what gate 2 already says to SKIP on.

> Note the trap in the 1,000/day tier: it requires **purchasing $10 of credits**. This fleet runs
> `spend.usage_credits_authorized: false` with the note *"flip to true only on an explicit operator
> decision, and say why in the commit."* The cheap path to usable throughput is an authorized spend.

---

## 4. T5 — the higher-value routing experiment that is already specified and unrun

The probe file names it itself:

> **"Raised by T4, and it is the highest-value open routing question in this file."**

**T5 = `claude-opus-5` vs `claude-fable-5(.1)` at MATCHED effort on `roles.research_adversarial`.**

The evidence that it matters:

| Measure (T4, 36 anchored defects) | `claude-opus-5` @max | `claude-fable-5` @xhigh |
|---|---|---|
| Ground-truth recall | **13** | 9 |
| Pairwise non-overlap | **5** | 1 |
| Unique hits | **2** | 0 |
| Citation accuracy (exact) | **96%** | 93% |
| Price | **$5/$25** | $10/$50 |

T6 (2026-09-10) strengthened it on the same corpus: Opus-5@max's 12/36 **beats `claude-fable-5-1` at
every effort** (low 6 · med 10 · high 10 · xhigh 9 · max 9/25), and 5.1's recall is **flat from medium
upward** — so *"Fable at higher effort would close it"* is no longer the open reading it was.

**Why this is the better spend, in the operator's own currency.** Fable is not a separate budget: it is
a **sub-cap of the same weekly bucket at 50%** (`frontier.coupling: 0.5`), drawn **~3.2–3.7× faster per
token**. Live readout: `next2` has burned **76% Fable**, `next4` 13%, `next` 7%. If T5 shows the
frontier premium is unearned in that slot, reseating it on Opus 5 **recovers real weekly capacity that
is being spent today** — and removes a live failure mode (the slot's in-window and window-shut
behaviour become identical).

**And it is cheap, by the file's own assessment:**

> *"The corpus, the harness and the judging pipeline all already exist, so **this is cheap**."*

**Status: filed in the routing ledger as `## Target T5`, unrun.** It has **no `cc-backlog` row** —
it lives only in `~/.claude/model-routing-freewin-probe.md`, which is a live dotfile, untracked. That
is itself a small finding: the highest-value open routing question on the box is invisible to every
drain selector, which is a plausible reason it has sat unrun since 2026-08-11.

**Other unfinished routing work:** `effort_defaults.fable51.default: high` — *"medium a candidate,
uncertified"* (T6 measured medium ≈ high at roughly half the cost; another free win sitting one probe
away).

---

## 5. THE STRUCTURAL LESSON from T1/T2/T4/T6, applied to the drain

### The mechanism, in the file's own corrected words

> *"It's not 'frontier tier beats cheaper model on open-ended grounding' — it's **'MAX effort holds the
> grounding floor, and Sonnet-5@max has enough reasoning to reach it.'**"*

The discriminating axis is **bounded vs open-ended repo grounding**:

- **BOUNDED** (extract ONE well-defined predicate, verify ONE claim) → cheaper configs **tie**. Every
  tie in T1/T2 sits here.
- **OPEN-ENDED** (exhaustive synthesis, find-the-site, root-cause) → cheaper configs **fail in a
  specific, diagnosable way**: they *"relied on the rule-doc"* instead of opening source, *"mis-cited
  line numbers,"* *"left the sub-question ungrounded."*

**The failure mode is confabulation, not shallowness** — and that is what makes it dangerous in a
write-lane. Measured instances: Sonnet-5@xhigh produced **systematic wrong-file citations**
(attributed `resolveGroupConfig` to `databaseActions.ts`; it lives in `drizzle/db.ts`) — caught by
**all four judges**. Opus@medium **fabricated a code comment** at `MobileListSwitcher.tsx:119`.
Opus@low **fabricated the function `computePull`** (grep-confirmed absent). **Every reduced-effort
config failed hard briefs regardless of tier.**

### Now classify the drain-link workload

From `docs/plans/BACKLOG_DRAIN_24_7.md` § Scope (frozen): *"root-cause the false 'drained to zero'
reading; **reconcile the ledger to disk truth with zero lost work**; then design, implement, verify and
START a 24/7 two-lane pipeline… with **claim-time freshness re-validation** and consolidation-before-
fire."*

Every one of those is **open-ended repo grounding**, and worse:

| Drain sub-task | Class | Verdict under the measured mechanism |
|---|---|---|
| Root-cause a false ledger reading | open-ended | **Below the floor** for any uncertified config |
| Reconcile ledger ↔ disk truth | open-ended, high-stakes | Below the floor — the failure mode is *silent wrong reconciliation* |
| Premise/freshness re-validation | open-ended | Below the floor — already at **0 rows validated in production** |
| Implement + land the fix | open-ended **+ WRITE** | Worst case: confabulation lands on trunk |
| Row triage / classification | **bounded** | The **only** plausible candidate — and see the carve-out below |

**The drain is the T2 synthesis-worker slot with commit rights.** T2's whole finding is that this slot
is **floor-pinned on BOTH axes** — model *and* effort:

> *"The reasoning WORKER slot is floor-pinned on BOTH axes… So the per-agent tier cannot be cheapened;
> **quota is a WAVE-level problem**."*

**That sentence is the direct answer to this proposal.** The box already asked *"can we make the
expensive worker slot cheaper?"*, measured it properly, and answered **no** — and then named the three
levers that *do* work: decomposition discipline, tier-mix down, and preferring Workflows above ~10
agents. The `union-alpha` proposal is a fourth attempt at the lever that was measured shut.

**The substitution/non-overlap inversion also cuts against it.** T4's rule exists because a
*verification* slot profits from decorrelation. The drain is a **substitution** slot — union-alpha
would do work Opus 5 would otherwise do. So the **strict** rule governs: *any* reliable quality edge to
the incumbent, **even ~1%**, ⇒ REJECT. A frontier-claimed stealth model with **zero public evals, an
undisclosed identity, and a one-week life** cannot clear a bar that rejected `gpt-5.6-sol`.

**The narrow steelman, stated fairly.** *Row triage* is bounded, and T3's advisory-gate carve-out
would cover a cheap model that only proposes a classification a certified model ratifies. Two things
kill it anyway: (a) the ratifier must then read every row, so the saving is marginal; (b) **gate 8
still binds** — row titles are the customer content, and triage means sending *all* of them.

---

## 6. ADVERSARIAL PASS — what I checked that cuts the other way

1. **"Is there real quota pressure, or are you inventing scarcity?"** — There IS pressure: `next2` at
   **100% weekly (LIMITED)**, `next` at 94%. I state that as the strongest fact for the proposal.
   **But it is a distribution failure, not a capacity failure**: `next3` is at 7% weekly with a
   measured **~47pp forecast to strand** (die unspent at reset, `p76` of its own 24h burns). The fleet
   is simultaneously at the wall and wasting ~half an account-week. External capacity does not fix that.
2. **"Does the jcode ToS reasoning actually transfer?"** — **No, and I do not claim it.** union-alpha
   involves no Anthropic OAuth impersonation, so the account-forfeiture argument does **not** carry.
   Only the *shape* transfers (non-dollar price invisible to the dollar gate). Importing jcode's
   conclusion wholesale would be the error.
3. **"Does union-alpha pass the cost gate as written?"** — **Yes.** Price is literally `0`/`0`. I
   surface this as gate 8's **gap** rather than pretending the existing gate catches it.
4. **"Is the stealth data claim overstated?"** — Partly, and I corrected it. My secondaries said
   "used to train"; the origin provider page carries a **no-training carve-out**. I read the EULA at
   origin and narrowed the claim to **retention by an anonymous party**, which holds under both readings.
5. **"Has any cheap model ever been adopted without a probe?"** — **Yes** — `research-decomposition-critic`
   under the advisory-gate carve-out. Named in §1d as the only honest doorway, and shown not to fit the drain.
6. **"Is `union-alpha` even subject to the free-tier caps?"** — **Unmeasured.** Its ID has no `:free`
   suffix. Flagged as an uncertainty rather than asserted in either direction.

---

## Blockers & uncertainties

- **Unmeasured:** whether `stealth/union-alpha` (no `:free` suffix) is bound by the 50/1,000-per-day
  free-tier caps. Resolvable only by creating an OpenRouter account — itself a gate-2 action.
- **Unmeasured:** `union-alpha`'s actual capability. Zero independent evals exist; it is <24h old.
  Every capability claim in circulation traces to the anonymous provider's own listing copy.
- **Not verified at origin:** Cloudflare AI Gateway's current default log-retention settings. I assert
  only that it is an *additional* logging party, which follows from its product function.
- **Structural gap worth filing:** `providers.json` has no data-egress/retention field. A zero-priced
  backend passes `bills_outside_plan` by construction, so the registry's own gate is blind to exactly
  this proposal class. Suggested field: `retains_user_content` / `provider_identity_known`, with the
  same *"UNKNOWN ⇒ SKIP"* polarity the cost rule already uses.

---

## Appendix — live `claude-accounts --readout`, relayed verbatim

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 0 | 0% | — | 94% | 7% | Sat 22:59 (in 2d 23h) | Tue Oct 13 01:19 (in 26d 1h) |
| next4 ← you | 14 | 14% | Thu 02:00 (in 2.4h) | 42% | 13% | Sun 04:00 (in 3d 4h) | Thu Oct 08 05:42 (in 21d 6h) |
| **next3** ➤ | 2 | 2% | Thu 01:00 (in 1.4h) | 7% | 0% | Tue 07:00 (in 5d 7h) | Thu Oct 01 14:39 (in 14d 14h) |
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
_Cache ≤90s old; `--fresh` forces a live sweep._

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

**Note the last two rows of that registry.** `gemini` is skipped for `plan tier UNKNOWN` — *"SKIP per
the cost rule, **not because it looks expensive**."* A backend is refused here for being
**unmeasurable**, not for being costly. `union-alpha` is a model whose **operator is anonymous by
design**. It is less measurable than the backend this box already skipped on measurability grounds.

---

## Sources

- [OpenRouter — Stealth Models](https://openrouter.ai/provider/stealth)
- [OpenRouter — Stealth Program Terms](https://openrouter.ai/terms/stealth)
- [OpenRouter — Union Alpha](https://openrouter.ai/stealth/union-alpha) · `GET /api/v1/models` (pricing `0`/`0`, ctx 262144)
- [OpenRouter announcement (X)](https://x.com/OpenRouter/status/2100235351575191751)
- [OpenRouter Rate Limits](https://openrouter.zendesk.com/hc/en-us/articles/39501163636379-OpenRouter-Rate-Limits-What-You-Need-to-Know)
- [OpenRouter stealth-model census](https://www.digitalapplied.com/blog/openrouter-stealth-model-census-who-they-turned-out-to-be)
- [Union Alpha coverage](https://www.progressiverobot.com/2026/09/16/union-alpha-stealth-coding-model-free-opencode-openrouter/)

**On-box:** `~/.claude/model-routing-freewin-probe.md` (T1–T6) · `~/.claude/providers.json` ·
`~/Development/claude-infrastructure/model-config.yaml:614-618, 631-671, 555-586` ·
`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:26-28, 240-353` ·
`docs/research/codex-probe-w3-verdict-2026-08-11.md` ·
`docs/research/jcode-due-diligence-2026-08-11/cost-gate.md` ·
`docs/plans/BACKLOG_DRAIN_24_7.md` · `~/.claude/plan-history/plans/agent-egress-catalogue.md:289,381` ·
`~/.claude/plan-history/plans/egress-redteam.md` · `accounts.json` (`spend.usage_credits_authorized=false`)
