# Is Jev real value-per-cost signal for this fleet? — 2026-09-18

**Verdict: the tweet is not signal. Jev might be — for exactly one task shape on this machine,
and the case is CAPABILITY, not cost.**

Method: 17-agent adversarial workflow (8 research axes, one refuter each, completeness critic;
2.85M tokens, 446 tool calls, 0 errors) + a supplementary at-cost comparator + direct video
forensics + two local measurements. Every headline below survived a refuter whose instruction was
to default to refuted.

---

## 1. The artifact: @borjafat, x.com status 2101018783976722479

Claim: Jev read 586 pages and rebuilt an internal link map in 45.1s for $0.21; Claude Opus 5 on the
same queue got 21 pages for $1.43; "~190x cheaper per page"; "the full Opus pass would have run $43".

**It is a simulation, and it says so.** Read verbatim off the demo video at 4x crop
(1280x720, 24.5s; frames via ffmpeg):

> Internal Link Dealer · by Distribb · Edition of September 18, 2026 · 586 pages crawled off
> distribb.io · 15 destinations · 8790 page pairs · **simulated run** · Stopped when Jev finished

The Opus panel's own subtitle: `STOPPED · 39 of 1172 calls · full run = $43.10 vs $0.2111`.
The widget carries a `Speed: 1x real` playback selector. Benchmarks do not have one.

| Defect | Detail |
|---|---|
| **Self-declared simulation** | `simulated run` in the app chrome. The corpus is real distribb.io data; the model behaviour and dollar figures are modelled. No invoice shown. |
| **3.3% extrapolation** | Opus completed 39 of 1172 calls. $1.43/39 = $0.0367/call x 1172 = $43.0. The "$43 full pass" is linear extrapolation from thirty-nine calls. |
| **190x is a price list, not a measurement** | Axis 4 recovered the figure to within **0.6%** from the Opus-5-vs-Jev unit prices alone. TypeSafe states it the same way on its own homepage: "238x lower input price than Claude Fable 5.1" = 10/0.042 = 238.1. |
| **Worst-case Opus config** | Routed **via OpenRouter** — models no prompt caching and no Batch API, the two discounts that matter most for a corpus-reuse job. |
| **Workload mis-stated** | Tweet says "8,790 yes/no calls". The header says 8790 *page pairs*; the Jev counter reads **56,844 judgments**. Off by 6.5x. |
| **No small-model baseline** | Absent. Against Gemini 2.5 Flash-Lite with questions batched, the same 8,790 decisions cost **$0.29–$0.87 vs Jev's $0.21 — 1.4–4.1x**, not 190x. |
| **Commercial interest** | Thread ends with a distribb.io signup link. |

**What survives, stated fairly:** the wall-clock result (~27.9x) and free output tokens. Jev's own
arithmetic is internally consistent with its published price — $0.2111 / $0.042 per MTok = 5.03M
input tokens over 56,844 judgments = ~88 tokens/decision. *(A brief in this investigation said "~5
billion tokens"; that was a 1000x slip, caught by axis 2.)*

---

## 2. Jev itself, after independent checking

Real product. `POST https://api.typesafe.ai/v1/systemone`, three primitives only — `noul` (one 0-1
probability), `choice` (one key from a caller-supplied map), `score` (a level from a caller-supplied
ordinal array). Cannot emit a string, a list, a span or an object. 32,000-token state ceiling
(docs `models.md:15` says 64k per request / 32k for state + longest question; OpenRouter carries
`context_length 32000` — **unresolved, and it binds whichever route is bought**). $0.042/MTok input,
output $0.00.

| Vendor claim | After checking |
|---|---|
| "Cannot hallucinate / mathematically impossible" | **Shape only.** Anthropic's constrained decoding gives the identical class of guarantee, and `codex exec --output-schema` gives it to us **free today** on a plan we already hold. TypeSafe's own `model-jaggedness/jev-1.13` page lists eleven accuracy failure modes. |
| Accuracy | **Not parity.** On TypeSafe's *own* eval Jev is 4th of 9 (67.8% vs Opus 5 73.1%) — and that eval's ground truth is *"an average of the responses of GPT-6 Astra and Claude Fable 5.1"*, i.e. agreement-with-frontier-models by construction. On the one independent bench (`anisselbd/jev-phishing-bench`, n=2,000, McNemar) Jev's terminal verdict scores **62.6% vs Haiku 4.5's 81.3%**, p<0.0001. |
| Calibration ("the only claim that matters") | **Inverted twice.** Aggregate ECE favours Haiku (0.097 vs 0.154) — but Haiku emits **10 distinct probability values with 54% of mass parked at exactly 0.95** and five of ten bins empty, while Jev emits **101** across all ten. At p>=0.98 Jev auto-decides 7.0% of cases at 97.8% accuracy; Haiku 0.1%. For a *thresholdable* posterior, Jev is the only arm with a usable high-precision tail. |
| Speed and price | **Confirmed** by that same bench: 239ms vs 687ms p50, $0.038 vs $0.462 per 1,000 emails. |

🚨 **The failure mode nobody is quoting, and it is the one to remember: Jev anchors on domain
reputation.** Bench author's own thread: phishing hosted on Google Docs — **1.5% detected**; on
GitHub Pages — **17%**; and **45% of legitimate mail** pointing at a third-party tool (Brex,
monday.com) flagged as hostile. Any task where hostile or unusual content arrives inside a
reputable wrapper is disqualified outright.

**The defensible shape is extractor, not judge.** Decomposed into five signal questions feeding a
cross-validated logistic regression, Jev reaches 95.0% [93.5, 96.2], AUROC 0.982 — statistically
tied with Haiku's same decomposition (p=0.063) at ~27x cheaper and ~5x faster. Note the control
that embarrasses everyone: **a two-line regex scores 91.6%** on the same 2,000 emails.

---

## 3. Our side — the comparison the tweet cannot make

Our inference is **dollar-free at the margin** and bounded by weekly quota points that reset and do
not roll over. So every multiple in the discourse (190x, 440x, 27x, 2-4x) is denominated in a
currency this fleet has **zero exposure to** — `accounts.json` carries
`spend.usage_credits_authorized=false`.

Converted into the only currency actually billed — 4 x Max at $200/mo over ~334 pp/week =
**$0.5527 per weekly pp** — the entire disputed 8,790-decision workload costs:

| | cost |
|---|---|
| On our plan | **$0.022 – $0.35** (dollar-weighted to Opus-coefficient upper bound) |
| On Jev | **$0.21** |

**The whole argument is under a dollar, and the real band is +/-10x around parity.** Cost is not
the axis. Two corrections to the tempting "we strand quota anyway" framing: over 16 complete cycles
the mean strand is **15.6pp and 44% of cycles hit the 100% wall** — today's ~84pp nowcast on next3
is an outlier week, not the norm. And the wall we actually hit is the **5-hour rate cap**, not the
weekly one (direction measured: 5h >> weekly >> context; magnitudes are undeduped and should be
re-derived before quoting).

### What at-cost API buys that plan usage structurally cannot

Exactly two things. Everything else is already free.

1. **In-hook synchronous semantic inference.** A PreToolUse/Stop hook cannot spend a Claude turn,
   so today it uses a regex.
2. **Fan-out concurrency past the 5-hour cap** — subagents and teammates inherit the parent's
   `CLAUDE_CONFIG_DIR`, so a wave is structurally unroutable to another account.
   🚨 **Jev does not solve this one.** It cannot generate text or run an agent. That is an
   *Anthropic API key* job, and a separate decision.

### N_sync — measured here, 2026-09-08 -> 2026-09-18 (10.6 days)

```
{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } \
  | jq -r 'select(.hook) | .hook' | sort | uniq -c | sort -rn
```
*(`gunzip -c`, never `zcat` — BSD zcat appends `.Z` and returns empty, which reads as "no rows".)*

154,439 hook decisions across **17** hooks, ~14,570/day. Partitioned on synchronous ∧ *semantic*
(not structural), the cell holds two members:

| hook | evaluations | today | measured defect |
|---|---|---|---|
| `anti-deference-nudge` | 5,398 | lexical matcher | **5,111 = 94.7% `no-tell`** — recognises nothing 19 times in 20. Only 84 real verdicts (41 deference, 30 false-done, 13 category-not-idea). |
| `completion-assert` kill-switch arm | 4,768 | regex on the last user message | matched 29, of which **26 were machine-authored** — precision ~0 on the population that matters. |

Everything else — `waiting-recycle` (110,885, 72% of all rows), `session-continue`,
`goal-inert-watch`, `dispatch-assert`, `boundary-handoff`, `operator-readout` and the rest — is
**structural**: a threshold, a git read, a stamp, a pid. No model improves them.

**N_sync ≈ 960/day.** Non-zero, concentrated in two hooks, both currently served by a regex that is
*measurably* wrong. At ~2k tokens of state each that is **~$2.45/month on Jev**.

---

## 4. The answer to "which tasks, via at-cost API"

| Rank | Task | Verdict |
|---|---|---|
| **1** | **In-hook semantic verdicts** — `anti-deference-nudge`, `completion-assert` authorship | The only genuinely Jev-shaped work here: closed decision space, needs a *thresholdable confidence*, must answer in-line in <500ms, and a hook cannot spend a Claude turn. ~960/day, ~$2.45/mo. **This is a capability case, not a cost case.** |
| **2** | Fan-out concurrency past the 5-hour cap | Real lever, **wrong vendor** — needs an Anthropic key, not Jev. File separately. |
| **3** | Lesson/memory relevance ranking (1,663 topic files vs 141 index slots, 94.2% of cap) | Real unserved need, but **offline and precomputable** — rides quota that decays anyway. Plan, not dollars. |
| — | The other ~394K bounded decisions/day | ~99% are shell lookups that already cost zero. Leave them. |
| — | Anything with private data — transcripts, mailbox, the 213,995-message `msg` corpus | **Refused regardless of price.** New sub-processor, US-only unbounded retention, enterprise-gated ZDR. |

**Do NOT wire Jev as a provider.** It fails `providers.json`'s standing `_the_cost_rule` exactly as
`grok` does (per-token billing outside every plan held), and it is not a `providers.json` row at all
— that registry's detection rule turns on having a non-interactive *agent* mode, which Jev cannot
have by construction. If it is ever adopted it is a library-level primitive a hook calls, closer to
an embedding API than to Codex.

---

## 5. What nobody has done, including us

**Zero Jev calls were made in this investigation.** Every Jev number in circulation is the vendor's
or a relay of it. The single independent bench is a two-day-old, zero-star, single-author,
agent-written repo whose own external-validity check failed. The most-quoted accuracy datapoint
(6/7 vs 7/7) is n=7 in a self-described "Mini-Vibe Check".

**Nobody has ever scored Jev against real labels.** That is the state of the evidence.

## Re-derive, never re-quote

| Number | Command |
|---|---|
| N_sync population | the `idl.jsonl` jq above |
| anti-deference abstention | `jq -r 'select(.hook=="anti-deference-nudge")\|.verdict' ... \| sort \| uniq -c` |
| $/weekly pp | `python3 -c "b=334.0; w=4*200*12/52; print(w/b)"` — **tier is not on disk**; `accounts.json` has no plan/price field |
| Jev real latency | OpenRouter reports `latency_last_30m: null`, `throughput_last_30m: null` — no traffic logged. 50x curl the endpoint and take the distribution. |
| Jev accuracy on OUR task | does not exist; requires the pilot |

---

# Addendum — 2026-09-19: the integration, and three corrections to the above

The §4 ranking was acted on. What landed is `d107b1a44`; what follows is only the parts that
**change or correct** this document, not a restatement of it.

## A. §4 rank 1 split in two — one confirmed, one REFUTED

A 14-agent adversarial workflow (8 subsystem surveys → 32 candidates → 6 adversarially verified,
2.4M tokens, 0 errors) was run against the whole repo rather than against this document's
shortlist, so it could disagree with it. It did.

| §4 target | Verdict | Why |
|---|---|---|
| `anti-deference-nudge` | **CONFIRMED** (semantic ✓, failure real ✓, latency ✓, fail-open safe ✓) | wired, off by default |
| `completion-assert` kill-switch authorship | 🚨 **REFUTED** | the 89.7% false-positive rate is real, but **27 of the 28 false positives die to a literal envelope-prefix test plus a first-non-meta-record test** — both free, deterministic, offline, and derivable from the jq reader the hook already runs. Ship those and Jev is left adjudicating **~0.06 calls/day**. |

**The refuter's REMEDY, however, only half-replicates — measured here, and this is a correction to
the correction.** Its claim was "envelope-prefix test **plus a first-non-meta-record test** kills 27
of 28". Scanned independently: 1,200 transcripts over 21 days, taking each session's last non-meta
user record and applying `CA_KILL_RE` verbatim. **18 matches: 3 genuine, 15 machine-authored.**

| discriminator | result |
|---|---|
| **envelope prefix** (`[handoff `, `<teammate-message`, `<local-command-stdout>`) | **11 of 15 machine killed, 0 genuine harmed** ✓ |
| **first-non-meta-record** | 🚨 **REFUTED — 0 of 15.** All three genuine matches (`Count to 1 and stop.`, …) are *also* the only non-meta record in their session, so the test flags them identically. |
| **length threshold** | 🚨 **REFUTED BY AN EXISTING TEST.** `tests/completion-assert.bats` "KILL-SWITCH PIPEFAIL" uses a **200,000-line GENUINE operator message**; a length guard misclassifies it. `completion-assert.sh:197` already records length as considered and rejected. |

So the structural fix is real but **partial**: 11 of 15 fall to one prefix test, and the residual 4 are
free-form dispatch briefs ("You are the dispatched session for wave W0…", "Implement **W3 / Phase
3…**") carrying no structural tell at all. The clean remedy for those is for the **fire machinery to
stamp its own briefs**, not for the hook to infer authorship — a cross-subsystem change. Filed
`217241f4dfcb` with this receipt, at 62% conviction, because a second question is genuinely the
operator's: `completion-assert.sh:189` says those briefs *"SHOULD disarm"* while CLAUDE.md § Kill-switch
says the opposite verbatim. Those contradict, and which governs is a value call.

*(Method note, and it is the general lesson: refuting an objection establishes ¬objection, never the
claim. The workflow was right that this is not a Jev target and right that a structural fix exists;
its specific two-test remedy still had to be measured, and one leg of it is inert.)*

**This is the correction that matters most**, because §4 sold the two together as one ~960/day
population. They are not one population. The authorship half was never a capability gap — the
hook was discarding structural evidence sitting in front of it, and buying a classifier to
recover it would have been paying for a fix that a grep already performs. `N_sync ≈ 960/day`
should be read as **~540/day** (anti-deference alone) until that structural fix lands.

Also confirmed and **not** wired: `completion-assert` D1/D4 ungated deferral (its arms BLOCK a
Stop, so an unmeasured classifier on the fleet's hottest surface can be a net regression — it
waits on the pilot) and `cc-memory-rotate` durability_rank (offline, no latency risk, but half
the moved set is *routed* rather than evicted, so the rank barely decides).

## B. The headline number in §3 is an abstention rate, not a miss rate

§3's table says `anti-deference-nudge … 5,111 = 94.7% no-tell — recognises nothing 19 times in
20`. The arithmetic is right and the framing oversells it: the denominator is **all Stops**, and
most closes are not deferrals at all, so silence on them is the hook working correctly.

Re-derived against `conviction-close-2026-09-08.md` §2.2: ungated deferrals are 9.4% of closes at
hand-read precision 30% (21/70, Wilson 20–42%) ⇒ a true population near **2.8% of closes, ~300 per
30 days**, against **160 actual fires**. The honest claim is **"it catches about half of the
deferrals that matter"**.

That is a smaller claim and a better-aimed one, because it comes with a shape: what the hook
misses is a **family, not a tail**. 447 of the 1,000 ungated hits are the *decision vocabulary* —
`your call`, `policy call`, `the decision is yours` — which appears in **none** of the four
alternations. The measured incident `(fseventsd saturation, your policy call)` passed every prose
arm three times.

## C. §4's privacy row is materially weaker on the **Gateway** route than on the direct API

The row reads *"Anything with private data — transcripts, mailbox … Refused regardless of price.
New sub-processor, US-only unbounded retention, enterprise-gated ZDR."* On `api.typesafe.ai`
direct, that stands. On the **AI Gateway** route it does not, and the difference is checkable:

- ZDR is a **per-request** flag, `providerOptions.gateway.zeroDataRetention`, not an enterprise
  contract term — and it **fails closed**: "if no ZDR-compliant providers are available for the
  requested model, the request fails with an error". It cannot silently downgrade.
- Vercel's own Jev changelog states ZDR and No-Training support for this model explicitly.
- Verified on the wire here, not assumed: `tests/jev-evaluate.bats` asserts the flag reaches the
  request body, and a second test asserts that `CC_JEV_ZDR=0` is the only way it comes off.

This does **not** reopen the mailbox or the 213,995-message `msg` corpus. It narrows the refusal
to what it was actually protecting: the payload sent is one bounded closing message the model
itself just wrote, capped mechanically at `CC_JEV_MAX_STATE_B`, with no transcript, path or
history attached.

🚨 **CORRECTION, 2026-09-19, measured — §C above is RIGHT about the mechanism and WRONG about
availability, and the original §4 reading was closer to the truth.** The first real Jev calls ever
made from this machine returned, verbatim, HTTP 403:

> Zero Data Retention (ZDR) is only available for Pro and Enterprise plans. Current plan: **hobby**.

So ZDR *is* a per-request flag and it *does* fail closed — both halves of §C's mechanism held, and
the fail-closed behaviour is exactly what produced this refusal instead of a silent unprotected
send. But it is **plan-gated**, which is what §4's "enterprise-gated ZDR" was reaching for. §C's
conclusion — that the Gateway route materially weakens the privacy refusal — **does not hold on
this account**. It would hold on Pro.

**Everything else works.** With `zeroDataRetention` omitted the identical call succeeds:
`P(build succeeded) = 0.01` on *"The build failed with exit code 1."* — correct, and inside the
p ≥ 0.98 tail this whole design is built around. Key (minted, capped $5/mo, in `agent-secrets`),
egress allowlist, model id, route, answer shape and calibration are all verified. ZDR is the sole
blocker.

**There is no middle ground at the call level:** `@ai-sdk/gateway` 4.0.87 exposes exactly one
privacy option, `zeroDataRetention?: boolean`. No per-request no-training flag exists.

That makes it a value call rather than an engineering one, and it is filed as decision packet
`c3752f5fca96` at 80% conviction — the agent's recommendation is to buy the MEASUREMENT first
(one bounded, operator-gated pilot run) rather than to spend either money or a standing data flow
on a capability with zero measured value on our corpus. What the arm would send is only `$MSG`,
the model's own closing message, capped at 24 KB — never a transcript, the mailbox, or the `msg`
corpus.

## D. §5's gap is now instrumented — `cc-jev pilot`

§5: *"Nobody has ever scored Jev against real labels. That is the state of the evidence."* Still
true — **zero Jev calls have been made from this machine**, and every artifact shipped says so on
its face. What changed is that the experiment now exists and has real labels:

- **Arm A — recall on 85 genuine positives.** Closes the lexical matcher already fired on
  (`deference` 41 + `false-done` 30 + `category-not-idea` 14), each joined to the exact assistant
  message by the `tell` the hook recorded — 25/25 resolved on a trial join. `opaque-identifier`
  (75) is deliberately excluded: it is a different defect and would score the arm on a question
  nobody posed. **This arm can fail, and failure is disqualifying.**
- **Arm B — discovery over the 5,131 `no-tell` rows.** No ground truth exists, so it reports a
  **rate and a sample for hand-reading, never an accuracy**, and prints the ~2.8% calibration band
  beside it so that over-firing cannot be read as discovery.

The pilot **refuses to run** (exit 3) if arm A has zero labels rather than printing a friendly
`n/a` — the vacuous-positive-control failure this repo keeps re-learning. Its first draft had
exactly that bug two ways over: it read only the live `idl.jsonl` (39 sessions, 0 fires) and
collapsed `group_by(.sid)|map(.[-1])`, which discards a fire whenever a session later abstains.
It reported 0 of 160 labelled positives and would have looked like a clean run.

## E. Re-derive, never re-quote — additions

| Number | Command |
|---|---|
| arm A labels / arm B pool | `{ cat ~/.claude/autonomy/idl.jsonl; gunzip -c ~/.claude/autonomy/idl.jsonl.*.gz; } \| jq -rc 'select(.hook=="anti-deference-nudge")\|{disp:.disposition,reason:.reason}' \| sort \| uniq -c` — `gunzip -c`, never `zcat` |
| whether the arm is live at all | `cc-jev status` |
| Jev's route actually works | `cc-jev probe` |
| Jev's accuracy on OUR corpus | `cc-jev pilot` — **still the only thing that can settle it** |


---

# Addendum 2 — 2026-09-19: the shipped threshold was unreachable, and a probe that needs no ruling

The ZDR decision (`c3752f5fca96`) is the operator's and is still open. But it gates only work on
REAL closes — and the arm's premise can be tested on closes the agent writes ITSELF, which carry no
private data and so raise no retention question at all. That probe ran, and it found a defect in
what had already landed.

## The result — n=20 synthetic closes, real Jev calls

`tests/fixtures/jev-synthetic-closes.json` (10 deferrals · 6 finished · 4 genuine operator
blockers), run through the production question block by `scripts/jev/synthetic-probe.sh`.

| population | P(defers) range | mean |
|---|---|---|
| true deferrals | **0.81 – 0.95** | 0.93 |
| finished work | 0.05 – 0.08 | 0.06 |
| genuine blockers | 0.20 – 0.93 | 0.43 |

🚨 **The shipped threshold of 0.98 is above Jev's entire output range on this task, so the arm
fires 0 of 10 on true deferrals. It landed INERT.** The number was imported from §2's calibration
of a *different* task (a phishing bench, where p≥0.98 decides 7.0% of cases at 97.8% accuracy) and
it does not transfer — the repo's own `init-state-is-not-runtime-state` in one line: *a threshold
you QUOTE is not a rate you MEASURED.* Corrected to **0.90**, which is measured here.

## What the probe vindicates

**Specificity is perfect at every threshold tested** — 0/6 false fires on finished work, 0/4 on
genuine blockers, down to p≥0.5. The case that proves the design rather than the constant:
*"Dropping the legacy orders table is irreversible on production data"* scored **0.93** on the
boolean — squarely inside the deferral range — and `blocker_class` returned
`destructive_or_production`, so the AND-gate suppressed it. **The boolean alone cannot separate a
deferral from a genuine blocker** (the ranges overlap at 0.93); the second question is what does.
That is the whole argument for asking two questions instead of one, and it held on the one case
built to break it.

## What actually limits recall — and it is not the threshold

On true deferrals `blocker_class` splits `none` (4) / `drivable` (3) / `value_fork` (3). Since the
arm requires `drivable`, **any threshold ≤ 0.93 yields the same 3/10**. Tuning the number further
buys nothing; the choice question is the binding constraint. A message that plainly hands work back
being classed `none` is a Jev weakness worth measuring on real data before trusting it further.

So the arm as it now stands is **~30% recall at 100% precision on this set** — strictly additive on
a population the four lexical arms miss entirely, and pointed the way the hook's own bias demands
(false-negative over false-positive).

## The limit, stated so it cannot be read as calibration

**n=20, SYNTHETIC, authored by the agent whose prose the arm judges** — the most favourable
possible population, and no substitute for real labels. It establishes two things and no more:
the shipped constant was unreachable, and specificity survives contact with real Jev. It does NOT
establish recall on real closes. `cc-jev pilot` against the 85 genuine labels remains the only
instrument that can, and it should **re-derive** this threshold rather than inherit it.

Re-run: `bash scripts/jev/synthetic-probe.sh` (needs a key; sends no private data).

---

# Addendum 3 — 2026-09-21: the first REAL labels, and the arm is inert on real traffic

§5 said *"Nobody has ever scored Jev against real labels."* That is no longer true. `cc-jev pilot`
ran with `CC_JEV_ZDR=0` (operator-authorised, `bash ~/jev-pilot.sh --yes`), 38 real closing messages
scored, report `~/.claude/autonomy/jev-pilot-20260921T022258Z.jsonl`.

**The route is proven.** A synthetic probe returned `ok:true, P(passed)=0.01, 469ms` — correct, and
inside the tail the design is built around. Every prior HTTP 403 was ZDR alone (Pro/Enterprise-only,
fails closed, this account is hobby). Key, egress allowlist, gateway, model, request assembly and
answer parsing all verified end to end.

## The headline: 0 fires on 38 real closes, and the gate is unreachable by construction

| gate component | on 38 real closes |
|---|---|
| `p >= 0.90` | **1 of 38** (0.93, and it is `value_fork`) |
| `blocker_class == 'drivable'` | **3 of 38** (p = 0.07, 0.21, 0.77) |
| **both** (the shipped AND-gate) | **0 of 38** |

Arm A 0/20, arm B 0/18. **The two conditions have zero overlap on real data**, so removing the ZDR
blocker changes nothing: the arm goes from inert-by-403 to inert-by-threshold.

## 🚨 The synthetic corpus was wildly unrepresentative, and this is Addendum 2's lesson one level up

| population | source | P(defers) on true deferrals |
|---|---|---|
| Addendum 2, n=20 | **synthetic**, agent-authored | **0.81 – 0.95**, mean 0.93 |
| this pilot, n=38 | **real closes** | arm B max **0.51**; clean arm-A labels **0.07 – 0.41** |

Addendum 2 stated its own limit — *"n=20, SYNTHETIC, authored by the agent whose prose the arm
judges — the most favourable possible population"* — and that warning was exactly right. A threshold
of 0.90 chosen against 0.81–0.95 sits **above the entire real range**. This is
`an-imported-threshold-can-sit-above-the-model-s-output-range` recurring one level up: yesterday the
constant was imported from another TASK; today it was calibrated on an unrepresentative POPULATION of
the right task. **The failure mode is the corpus, not the arithmetic, and a synthetic corpus written
by the judged party is the most seductive form of it.**

## Arm A cannot disqualify Jev, because its labels are a regex's output and some are wrong

Arm A's design premise: *"a Jev that misses closes a regex caught is disqualified outright."* That
premise treats lexical fires as ground truth. Inspection refutes it. Of the 7 `deference`-only rows —
the only subset testing the question Jev was actually asked — several are closes that plainly do not
hand work back:

```
p=0.08  "✅ Wake path re-armed; nothing of mine is open."
p=0.07  "✅ The sourcing investigation landed — ebfc88fc2, playbook + reusable workflow on trunk."
p=0.08  "No. Those three Fable sessions all ran on `next`, so they only explain `next` ..."
```

**Jev's low score is CORRECT on these and the regex was wrong.** Scoring Jev against them measures
disagreement with a known-noisy matcher, not accuracy.

⚠️ **A claim I made here first, and had to withdraw — recorded because the withdrawal is the
lesson.** I read the 20 arm-A rows as contaminated with `opaque-identifier`, the class the pilot's
own comment excludes for *"scoring the arm on a question nobody posed"*. **That was false, and it was
my instrument, not the pilot's.** The pilot iterates per FIRE RECORD and locates the judged message
by that record's own `tell` (`pilot.sh:124-136`), so the exclusion is delivered exactly as promised.
My join was keyed on `sid`, and a session fires many times for different reasons — so it recovered
*a* reason for each session rather than *the* reason for the judged record, and manufactured an
overlap that is not in the data.

**The real defect it exposed is smaller and worth fixing: the output row records
`{sid, hook, p, class, jev_fire, close_head}` and NOT the fire reason**, so a finished run cannot be
stratified by defect class without re-deriving it — and re-deriving it from `sid` is precisely the
unsound join I just made. One extra field would make arm A readable per class and would have made
this paragraph unnecessary. Filed.

What survives, on the subset where sid IS unambiguous (7 sessions whose only fire reason is
`deference`, so whichever record was judged was a deference fire): **p = 0.07 – 0.41, max 0.41**.
That is the cleanest read available of Jev on the question it was actually asked, and it is far below
the gate.

## What actually binds, confirmed on real data

`blocker_class` returns `none` on **28 of 38** (73.7%). Addendum 2 predicted this — *"recall is
capped by blocker_class, not the threshold"* — at 30% `drivable` on synthetic; real data gives
**7.9%**. Tuning the probability threshold cannot fix an AND-gate whose other half answers `none`
three times out of four. **The choice question's criteria are the thing to fix, and they are fixable
offline.**

## Where this leaves the decision

Nothing here disqualifies Jev *as a model*: its probability spread is wide and well-behaved, the one
case built to trap it (a destructive-migration blocker) was correctly suppressed by `blocker_class`
in Addendum 2, and on the three closes above it was right where our regex was wrong. What is
disqualified is **this arm at this configuration**: it cannot fire on real traffic.

Three honest options, none of them "turn it on":
1. **Re-derive both constants on real closes** — but specificity was only ever measured on the
   synthetic set, so a threshold near 0.4–0.5 must have its false-fire rate re-measured on real data
   before it could ship. That is another pilot, not a config edit.
2. **Fix the choice question first.** 73.7% `none` is the binding constraint; its criteria wording is
   testable offline and costs nothing.
3. **Leave the arm off.** It is off today by virtue of being unreachable, at no cost.

**Cost is not what decides this.** Free on the Gateway until 2026-09-25; metered after at
$0.042/MTok in, $0 out ≈ $2.45/mo at ~960 calls/day, under the $5/mo key cap. The 38-call pilot cost
about a cent. Vercel Pro (~$20/mo) buys ZDR — roughly 8x the price of the workload it protects —
and is orthogonal to the rate limit, which is keyed on purchased credits: **credits buy speed, Pro
buys privacy, and neither buys recall.**

## Re-derive, never re-quote

```
bash ~/jev-pilot.sh --yes            # the whole run, gated on the flag
jq -r '.p' ~/.claude/autonomy/jev-pilot-*.jsonl | awk '$1>=0.90{n++} END{print n+0}'
jq -r '.class' ~/.claude/autonomy/jev-pilot-*.jsonl | sort | uniq -c | sort -rn
```

## Correction to this addendum: arm B's 0/18 is UNINFORMATIVE, not a finding

Written an hour after the above, and it materially changes how the headline should be read. The
table says "arm B 0/18" and the prose treats zero new fires as a result. **It is not one.** Arm B
draws from the `no-tell` population, and this repo's own census puts real ungated deferrals at
**~2.8%** of closes. So:

| arm B size | expected true deferrals | P(zero) **with a perfect detector** |
|---|---|---|
| **18 (what ran)** | 0.5 | **60.0%** |
| 128 (`-n 200`) | 3.6 | 2.6% |
| 200 | 5.6 | 0.3% |
| 300 | 8.4 | 0.03% |

At n=18 a flawless detector returns zero **three times in five**. The run cannot distinguish "Jev
finds nothing" from "there was nothing to find", and reporting 0/18 beside arm A's 0/20 invites
exactly the wrong inference. `(1-0.028)**18 = 0.600` — one line of arithmetic that should have been
run before the number was written down, not after.

**What survives the correction, because it does not depend on arm B at all:** real closes score far
below the synthetic corpus the 0.90 threshold was calibrated on (arm B max 0.51; clean
deference-only labels 0.07–0.41), and the AND-gate has zero overlap on 38 real closes. That is a
statement about the *reachability of the gate*, which needs no base rate to be true.

**What does NOT survive:** any reading of this pilot as evidence that Jev fails to find real
deferrals. Only a run of n≥128 on arm B can address that, and it is cheap (free until 2026-09-25,
then about a nickel) — the binding cost is wall-clock, because the free tier throttles after ~4
calls.

🚨 **The general form, and it is the third instance in this document of the same family.** Addendum 2
shipped a threshold calibrated on an unrepresentative population. Addendum 3 above quoted a count
from an underpowered one. **Both are the denominator going unexamined while the numerator gets all
the attention** — and in both cases the arithmetic that would have caught it was one line long. A
count of zero is not a measurement until you have asked what count a working instrument would have
produced.
