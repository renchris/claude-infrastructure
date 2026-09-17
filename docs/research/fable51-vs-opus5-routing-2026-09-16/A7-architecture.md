# A7 — the STRUCTURAL consequence of making Fable 5.1 the default tier

**Axis:** this fleet's architecture assumes `frontier != default`. What is defined relative to that,
and what happens to each option if the assumption is deleted.
**Method:** read-only. Every claim below is tagged **MEASURED-THIS-SESSION** (I ran the command) ·
**MEASURED-BY-US** (a prior session of ours measured it, cited) · **QUOTED** (vendor text, including
text extracted from the shipped binary) · **ASSUMED** (my arithmetic on stated inputs).

---

## 0. Headline

**The blocking objection is not intelligence and it is not dollars — it is that Fable draws a
SEPARATE plan meter hard-capped at 50% of the account's limits (`coupling: 0.5`), and the whole
fleet's capacity, routing and limit-recovery machinery is built on Fable being the thing you spend
*out of* a reserve rather than the thing you run *on*.** Making Fable the default roughly halves
per-account usable weekly capacity and deletes the down-tier that every capacity-exhaustion path
falls back to.

Second, smaller, but it inverts the operator's premise: **on the fleet's own price book (read out of
the binary's baked catalog) Fable 5.1 at LOW effort is not cheaper than Opus 5 at HIGH** once cache
*writes* and output are counted — the 4× cache-read win is offset by a 2× cache-write price and a 2×
output price that a 0.6 effort index does not erase.

---

## 1. Everything defined relative to "frontier != default"

### 1.1 The capacity model (the load-bearing one — nothing else on this list is close)

**MEASURED-THIS-SESSION.** `~/.claude/accounts.json:33-34` carries
`"scoped_display_name": "Fable"`, `"coupling": 0.5`. `bin/claude-accounts:1447` reads the
API's `weekly_scoped` limit under that display name; `bin/claude-accounts:3481` is the whole model:

```python
w_rem  = max(0.0, (0.98 if credits_on else 1.00) - r["weekly_pct"]/100.0)
f_eff  = min(F["coupling"] * max(0.0, 1 - r["fable_pct"]/100.0), w_rem)
if f_eff <= R["FABLE_FLOOR"]: return None, "fable-exhausted"
```

Two facts encoded there: (a) Fable headroom is worth **at most 0.5 of a weekly** — the scoped bucket
exhausts at roughly half the tokens the general bucket does; (b) Fable headroom is **upper-bounded by
the general weekly remainder** — spending Fable also spends `weekly_all`. So Fable is a sub-bucket,
not a parallel one.

Live fleet, **MEASURED-THIS-SESSION** (`bin/claude-accounts --json`, 2026-09-16):

| account | weekly_all | weekly_scoped (Fable) | 5h |
|---|---|---|---|
| next  |  94% |  7% | 0% |
| next2 | 100% | 76% | 65% |
| next3 |   6% |  0% | 2% |
| next4 |  40% | 13% | 3% |

Read it as the structural argument: **today the fleet burns ~94-100% of two accounts' general weekly
meter while the Fable meter sits at 7% and 76%.** That asymmetry is the entire reason the frontier
tier is affordable — it is a reserve nobody is drawing on. Route the default to Fable and every
default session charges BOTH buckets, the scoped one twice as fast, so the binding constraint moves
from `weekly_all` to `weekly_scoped` and arrives at ~half the work.

**And the failure mode changes shape.** Today `fable-exhausted` closes the escalation lane and the
default keeps running. `bin/claude-accounts:3555-3557` states the designed escape explicitly:
*"a missing scoped limit is an entitlement fact… Classifying it as data-unavailable would make
cc-route hard-refuse (RT-d) instead of taking its designed **Opus down-tier** when no account carries
Fable."* If Fable IS the default, that down-tier is no longer a degrade — it is a model change, and
there is no policy layer that says which classes may take it.

### 1.2 The limit-recovery lane has never seen a Fable-scoped limit message

**MEASURED-THIS-SESSION**, `scripts/limit-reset-safety-gate.sh:114-121`, a declared blindness:

> *"The FABLE-scoped limit message's verbatim shape has never been captured (no real fixture exists).
> lr-audit classifies by prefix ("You've hit your session|weekly limit…"); IF the Fable message
> carries the weekly prefix it parks as kind=weekly (covered). IF it has a novel shape it classifies
> `other_api_error` → NEVER PARKED → this poller is blind to it."*

That blindness is *acceptable today* precisely because Fable is ≤6 spawns/session of a reserve
nobody exhausts. As the default it becomes the **commonest** limit event on the box, feeding a
classifier that has never been shown one, with only a stall-page (page latency, not reset latency)
underneath it. This is a real prerequisite, not a footnote: capture the message before any flip.

### 1.3 Bounded-autonomy escalation policy (`CLAUDE.md` § Frontier Tier Routing + `skills/frontier-routing`)

Five standing duties, each phrased against a default it is *above*:

1. **"Never select or propose the frontier model for identified/routine work."** Vacuous if frontier
   IS routine work.
2. **Capture holes with `/frontier-hole`** — its stated purpose is *"WITHOUT burning frontier
   tokens inline"* (`skills/frontier-hole/SKILL.md:3`). If every session is already on the frontier
   model, deferral buys nothing; the ledger's economic reason to exist evaporates.
3. **Escalate autonomously but bounded** — the hook cap. See 1.4.
4. **Feed the supply side** — wrap-up seam scan, telemetry-residue sweep, exogenous triggers. This
   duty is *tier-independent*: it is a discovery discipline, and it survives any option below. It is
   the one piece worth rescuing whatever happens.
5. **Campaigns** — *"Fable thinks in bounded phases; the default tier implements"*
   (`skills/frontier-campaign/SKILL.md:11-12`). The architect/implementer split is a MODEL split. On
   a Fable default it must be re-expressed as an effort split or it collapses into "one model talks
   to itself".

### 1.4 The per-session spawn cap (`hooks/frontier-spawn-gate.sh`)

**MEASURED-THIS-SESSION.** The gate matches `fable|claude-fable-5*|$fmodel` on an Agent spawn,
checks `frontier_access.active`/`end`, then enforces
`frontier_discovery_budget.max_fable_spawns_per_session` (6, halved on reserve dates) via
`${TMPDIR}/frontier-gate-<sid>.count`. Non-frontier spawns pass untouched.

If Fable is the default, this hook **refuses the 7th ordinary subagent of every session**, with a
message telling the agent to park a hole in `FRONTIER_HOLES.md`. That is not a tuning problem; it is
a gate whose population inverts from "rare escalations" to "all spawns". Either the cap is deleted or
its predicate must be re-keyed onto something other than the model id — and the moment it is re-keyed
onto effort, it is a different mechanism with different evidence behind it.

Note the second-order cost: the gate is the *only* mechanical bound on frontier spend. Deleting it
because "everything is Fable now" removes the fleet's one hook-enforced spend brake at exactly the
moment spend stops being discretionary.

### 1.5 The hole ledger and the "named Fable strength" rule

**MEASURED-THIS-SESSION.** `docs/research/FRONTIER_HOLES.md`: **0 OPEN holes.** Four panels ever
(H-DSH-1, H-DSH-2 2026-07-19 · H-INERT-1 2026-07-30 · H-CAP-1 2026-08-09). Last ledger write
`b70e4edb0`, **2026-08-09 — 38 days ago.** Six campaign candidates, none launched.

`CLAUDE.md:303` already narrowed the trigger: *"escalate on a **named** Fable strength rather than by
default — the routing economics are open work."* Combined with the ledger being empty for 38 days,
the honest structural read is: **the escalation lane is already close to dormant.** Collapsing it
costs far less than its code volume suggests — which cuts *for* simplification and *against* the
premise that we currently have a valuable frontier tier to protect.

### 1.6 The frontier machinery has already rotted a full model generation

**MEASURED-THIS-SESSION.** All three action skills still describe the default tier as **Opus 4.8**,
which stopped being true on 2026-07-25 (`opus_latest` flip) / 2026-08-01 (`default: high`):

- `skills/frontier-routing/SKILL.md:6` — *"Default model = Opus 4.8 @ effort max"* (last touched
  2026-07-17).
- `skills/frontier-run/SKILL.md:9` — *"problems Opus 4.8 @ max is blind to"*; `:66` — *"From an
  Opus@max lead, panels run Fable@max"*.
- `skills/frontier-hole/SKILL.md:8` — *"Routine work runs on the default tier (Opus 4.8 @ max)"*.
- `skills/frontier-campaign/SKILL.md:59` — *"Implementers = default tier (Opus 4.8 teammates)"*.

A separate documented instance of the same rot: `docs/research/frontier-track-gate-2026-09-04.md` —
the frontier tier was gated on the **deleted `claude-next` eval track** in four live carriers that
the filing did not name.

⇒ The decision is being taken over machinery that is not currently being maintained *because it is
not being exercised*. Weigh the cost of "breaking the frontier architecture" accordingly: much of it
is already broken and nobody noticed, which is itself the strongest evidence about how much value it
is producing.

### 1.7 Routing/cost surfaces keyed on the model id

**MEASURED-THIS-SESSION**, `scripts/handoff-fire.sh`:

- `:8710` — `fable) MODEL="$(_ssot_scalar frontier_access model)"` — the alias resolves through the
  SSOT key that *means* "the frontier".
- `:8765` — recycle guard: `case "$MODEL" in claude-fable-5*) return 0` — **a frontier recycle is
  refused**, because Fable rides a separate entitlement and recycling could land it on an account the
  API then rejects. On a Fable default this refuses *every* recycle — and § Context Stewardship makes
  `--recycle` the cheapest and commonest succession.
- `:9030` — `case "$MODEL" in claude-fable-5*) kind=fable` — account ranking switches to
  `score_fable`. Every fire would then rank on the scoped meter (see 1.1).
- `:9276-9284` — `FABLE_EFFECTIVE=1` drives the *"~2× the default model's cost"* warning. On a Fable
  default this prints on every fire, comparing the default to itself — an alarm that always fires
  says as little as one that never does.
- `~/.zshrc` `claude()` carries a `*claude-fable-5*` glob cost warning with the same property.

### 1.8 Conditional role slots

`model-config.yaml roles`: `frontier_discovery`, `teammate_frontier`, `research_adversarial`,
`workflow_judge`, `eval_judge` are all `claude-fable-5-1` **conditional on `frontier_access`**, with
`fallback: claude-opus-5`. If Fable is the default, five roles become "the same as everything else"
and the ladder loses its top rung; `research-subagents`' *"Fable slots cost 2× Opus slots"* cost math
(`pricing_per_mtok` header) loses its denominator.

---

## 2. What IS the frontier tier, per option

### (a) Frontier collapses — one model, effort-only ladder

**Breaks:** the spawn gate's population inverts (1.4) ⇒ delete or re-key; the hole ledger loses its
economic rationale (1.5) though NOT its discovery rationale (duty 4); `/frontier-run`'s
*baseline-blind derivation panel* — which is a **method**, not a model — loses its home; campaigns'
architect/implementer split loses its axis (1.3.5); the `⇒ Opus down-tier` escape in the router
becomes undefined policy (1.1); the 2× cost warnings become permanent noise (1.7).

**Keeps:** the least machinery. Honest about 1.5/1.6 — we would be deleting something already
dormant, not something load-bearing.

**Real cost, stated plainly:** you lose the *only* structurally-enforced spend brake on the box, and
you lose the ability to say "this answer cost more because we deliberately paid more". Every routing
decision becomes an effort decision, and effort is a much weaker lever for the one thing the frontier
tier was built for (unknown-unknowns): our own sweep found **effort above medium buys no recall**
(§3.1 below), so an effort-only ladder has a measured ceiling that a model-only ladder did not.

### (b) Frontier = Fable at higher effort

The most conservative rewrite, and **the only option the binary actively favours** — see §3: Fable
5.1 is the one model in our stack whose capability list carries `per_turn_effort`.

**Breaks:** `frontier-spawn-gate.sh` must be re-keyed from `req_model` to an effort field the Agent
tool does not expose in-process (GH #25591; and see §3.3 for what *is* now exposed). The hole ledger
survives; the panels survive; campaigns become "Fable@xhigh architect over Fable@medium implementers"
which is coherent.

**Breaks harder than it looks:** our own sweep says the higher rung **does not exist** on the class we
measured. `fable51_capability_sensitive` was moved **xhigh → high** on 2026-09-10 precisely because
high ≥ xhigh at every vote threshold at 2.5× the cost, and 3 of 9 xhigh cells blew the 64K output cap.
So option (b) proposes escalating along an axis we measured as flat-to-negative above `high`. It can
still be right for *derivation panels* (generative, not anchored review — the sweep names that class
as uncovered), but that is a hypothesis, not a result.

**Also:** effort escalation does not solve the capacity problem in §1.1 at all — `xhigh` costs 1.74×
`high` on the vendor's own index, drawn from the same halved meter.

### (c) Frontier = Mythos 5.1

**MEASURED-THIS-SESSION:** the baked catalog has `claude-mythos-5-1` with
`provider_ids.first_party: "claude-mythos-5-1"` but every third-party id `null`, and
`model-config.yaml` records it as **Project Glasswing only — we are not participants.**
Not evaluable. Listing it as an option is a placeholder for "re-open when access exists", nothing
more. Do not architect against it.

### (d) Frontier = Opus 5 for the classes our sweep says it wins

This is the option the evidence actually points at, and it is the one nobody proposed.

**MEASURED-BY-US** (`docs/research/fable51-effort-sweep-2026-09-10/README.md`, 45 cells, ~$182):
strict-majority recall on 36 anchored defects — f51 low 6 · **medium 10 · high 10** · xhigh 9 ·
max 9/25 · Fable5@xhigh 9 · **Opus5@max 12**. Paired (25 GT): f51 best 9, **Opus5@max 11**. The
README's own §3: *"Opus 5 @max (12/36) beats every 5.1 effort."*

So the inversion the operator is proposing is the exact inversion our one real measurement refutes —
on the one class we measured. Option (d) says: keep a two-model ladder, but **swap which model sits
on top for which class**, with Fable the cheaper/default-ish tier and Opus 5 the escalation for
anchored, grounding-heavy work.

**Breaks:** every string in the frontier machinery that says "frontier = Fable"
(`frontier_access.model`, the spawn-gate prefix match, the `fable` alias, the `--rank fable` lane,
the cost warnings). That is a large mechanical diff, but it is *mechanical*: the SSOT already has the
indirection (`_ssot_scalar frontier_access model`), and `hooks/frontier-spawn-gate.sh` already
resolves the model from the SSOT rather than hardcoding it.

**Does NOT break:** the capacity model. Opus 5 draws only `weekly_all`; there is no scoped sub-cap on
it. This is the option that keeps the fleet's capacity headroom intact.

🚨 **The critical gap the lead already named, restated as the blocker:** the sweep's Opus arm was
`@max`, and `max` is **not our default**. `effort_defaults.default` has been `high` since 2026-08-01
(`cb7f8e3fa`). So we have **never measured our actual default configuration** against any Fable arm.
`opus5_default: high` and `opus5_coding_agentic: medium` are labelled starting points. Any option
above is being chosen against a grid with a hole where the incumbent should be.

---

## 3. Is effort the real routing axis?

### 3.1 What the vendor's own numbers say (MEASURED-THIS-SESSION, from the binary's baked catalog)

`~/.claude-260/node_modules/.bin/claude`, `strings -a … | grep default_effort` (positive controls:
`claude-opus-5` 18 hits, `claude-fable-5-1` 11; negative control `NEVER_EXISTS_CONTROL_ZZZ` 0):

| model | `default_effort` | `effort_cost_index` (low/med/high/xhigh/max) | pricing tier | `advisor_rank` |
|---|---|---|---|---|
| `claude-opus-5`    | **high** | 0.67 / 0.76 / **1** / 1.60 / 1.70 | `tier_5_25` (cache read 0.50) | 4 |
| `claude-fable-5-1` | **high** | 0.60 / 0.77 / **1** / 1.74 / 1.91 | `tier_10_50_cache_read_0_25` | 5 |
| `claude-fable-5`   | high | 0.60 / 0.77 / 1 / 1.74 / 1.91 | `tier_10_50` | 5 |
| `claude-sonnet-5`  | high | 0.47 / 0.74 / 1 / 2.41 / 5.59 | `tier_2_10` | 3 |

Two things fall out immediately.

**(i) The cost argument does not survive the full price book.** `pricing_tiers` from the same
catalog: `tier_5_25 = {input 5, output 25, cache_write_5m 6.25, cache_read 0.50}`;
`tier_10_50_cache_read_0_25 = {input 10, output 50, cache_write_5m 12.5, cache_read 0.25}`.
Fable's cache READ is 2× cheaper; its cache WRITE and its OUTPUT are 2× more expensive.
**ASSUMED** mix for one long agentic session (20M cache read · 0.5M cache write · 0.2M fresh input ·
0.3M output), applying `effort_cost_index` to the output/thinking line only:

| arm | cache read | cache write | input | output | **total** |
|---|---|---|---|---|---|
| Opus 5 @ high   | $10.00 | $3.13 | $1.00 | $7.50  | **$21.63** |
| Fable 5.1 @ med | $5.00  | $6.25 | $2.00 | $11.55 | **$24.80** |
| Fable 5.1 @ low | $5.00  | $6.25 | $2.00 | $9.00  | **$22.25** |

Fable at LOW is at rough parity with Opus at HIGH, not below it, and at MEDIUM it is ~15% dearer.
The mix is assumed and the index's exact semantics are assumed; the unit prices and the indices are
measured. **The conclusion that survives any plausible mix:** the cache-read win is real but it is
one line of four, and the other three all move against Fable. "Covers cost" is not established.

And for this fleet it is close to moot: **we do not pay dollars, we pay plan meters** (`source:
plan-usage`), and the meter that matters is the scoped one at `coupling 0.5` (§1.1). A dollar
argument cannot reach the constraint that actually binds.

**(ii) Anthropic ships `default_effort: "high"` for BOTH models.** So "Fable 5.1 defaults to High
effort in Claude Code" is not a Fable-specific judgement about agentic work — it is the same value
Opus 5, Fable 5 and Sonnet 5 all carry in the same registry. See §4.

### 3.2 Is per-message effort reachable from Claude Code? — partly, and NOT on Opus 5

**MEASURED-THIS-SESSION**, same binary:

- The beta header `mid-conversation-output-config-2026-07-01` is compiled in (1 hit), alongside
  `output_config` (19), `effort_level` (27), and the telemetry keys `api_per_turn_effort`,
  `tengu_per_turn_effort`.
- The client **sends and self-heals** it: `[effort] model <X> rejected output_config.effort; latching
  unsupported and retrying without it.` (`tengu_effort_unsupported_retry`,
  `retry:effort-unsupported`). So per-turn effort is live client behaviour, not a dormant flag.
- 🚨 **`per_turn_effort` appears in `claude-fable-5-1`'s capability list and NOT in
  `claude-opus-5`'s.** Fable 5.1: `[…,"mid_conv_tool_change","per_turn_effort","context_management",
  …]`. Opus 5: `[…,"mid_conv_tool_change","context_management","thinking_disabled_effort_cap",
  "fast_mode",…]` — no `per_turn_effort`.
  This **refutes** `model-config.yaml`'s line *"Per-message effort … Also supported on Opus 5"* as
  the harness's registry sees it on 2.1.260. (The bundled `claude-api` skill's capability table lists
  the API-level support as Fable/Mythos/Opus, beta, **first-party only**, so the two statements may
  be about different layers — API support vs. what this client will attempt. Either way, the client's
  own registry is what decides what our sessions get.)

⇒ **The honest framing inverts the question.** If we want effort to be the routing axis, the model
that supports mid-conversation effort changes **without invalidating the prompt cache** is Fable 5.1,
not Opus 5. That is a genuine, named, measured Fable strength — the kind `CLAUDE.md:303` says to
escalate on — and it is an *architectural* strength rather than a benchmark one. It is also the
single strongest argument in the operator's favour that nobody in this thread has made.

### 3.3 What is settable, per surface (MEASURED-THIS-SESSION)

| surface | model | effort |
|---|---|---|
| launcher / session | `--model` | `--effort` (seeds; `/effort` adjustable live) |
| Dynamic Workflow `agent()` | `model?` | **`effort?`** — the binary's own API string: `agent(prompt, opts?: {label?, phase?, schema?, model?, effort?, isolation?, agentType?})` |
| agent definition (`.claude/agents/*.md`) | `model:` | **`effort`** is in the harness's recognised frontmatter key list (`["name","description","model","allowed-tools","argument-hint","arguments","disable-model-invocation","user-invocable","effort","shell",…]`), and the Agent tool's own description reads *"Each agent type's model, reasoning effort, and tool access are set in its definition (`.claude/agents/*.md` frontmatter, or the SDK `agents` option)"*. |
| in-process Agent spawn (call time) | `model:` overrides the definition | no call-time field |
| teammate pane | allowlist-gated | `settings.local.json` in the worktree (caps at `xhigh`) |
| hooks / Bash | — | `CLAUDE_EFFORT` env var, **read-only** |

⚠️ The frontmatter row **contradicts `model-config.yaml`'s** *"frontmatter `effort` not parsed —
GH #25591"*. That is a string-level + doc-level measurement, not a live A/B: I did not spawn an agent
with `effort:` in its frontmatter and read back the applied level. **If effort is going to be the
routing axis, that A/B is the first experiment to run** — it decides whether per-slot effort routing
is buildable today (`agents/frontier-derivation.md` gets `effort: xhigh` and the whole model axis
becomes unnecessary) or still needs a workflow.

### 3.4 Where an effort-only ladder has a measured ceiling

**MEASURED-BY-US**, same sweep: *"Effort above medium buys no recall on this class. medium through
max cluster at 8-10 of 25 paired; only low falls below."* Findings per output: low 6.0, medium 8.7,
high 9.3, xhigh 8.7. And above `high` the **64K output cap binds** — xhigh continued in 3/9 cells (up
to 255,464 tokens), max produced *no review at all* on the 60KB brief after 256K tokens and 47
minutes.

⇒ An effort-only ladder has **two usable rungs** on the class we measured (low, and everything from
medium up), not five. That is a thinner instrument than the model ladder it would replace, and it is
why option (a) is weaker than it looks.

---

## 4. Did Anthropic choose `high` for Claude Code specifically?

**No — not on the evidence in the shipped binary.** `default_effort: "high"` is carried identically by
`claude-opus-5`, `claude-fable-5-1`, `claude-fable-5` and `claude-sonnet-5` in the same baked
catalog, and the binary has `var zwt="high"` as the pivot for "is this effort above default". There
is also a first-party **nudge in the opposite direction**: `effort_medium_nudge` /
`hasSeenEffortMediumNudge` / *"Effort set to medium and saved as your default"* — Claude Code
actively offers to move users **down** to medium, and the `max` picker carries the warning *"May use
excessive tokens resulting in long response times or overthinking. Use sparingly for the hardest
tasks."*

So the premise in the question — *"Anthropic chose high for Claude Code, that is evidence about
agentic workloads"* — is **QUOTED from marketing prose, and the binary does not corroborate it as a
Claude-Code-specific or Fable-specific choice.** It is the platform-wide default for the whole
current generation. Running Fable at medium is below a *stated* default but it is not below a
*measured, harness-specific* one, and the vendor ships a nudge toward exactly that move.

One genuinely Claude-Code-specific datum does exist and it points the other way:
`claude-fable-5-1` and `claude-fable-5` carry `fable_5_mitigations` and `fable_5_1_prompt_bundle`
capabilities — **Claude Code swaps in a Fable-specific system-prompt bundle and a set of
mitigations.** Opus 5 gets `opus_5_prompt_bundle`. The harness is doing per-family prompt work under
us, which means a Fable default changes our effective system prompt in ways we have not read.

A second one: Anthropic's own bundled `/code-review` skill carries a per-model measured budget table
(`measuredExternal:!0` cells for `claude-opus-4-8`, `claude-opus-5`, `claude-sonnet-5`) and has **no
Fable entry at all** — Fable falls through to `default`. First-party agentic tooling is tuned against
the Opus family.

---

## 5. How much of the operating manual assumes the default tier's identity?

**MEASURED-THIS-SESSION.** `CLAUDE.global.md` is 1,005 lines and always-resident. Seven passages name
Opus 5; the concentration is in **§ Communication Discipline (lines 370-420)**, which is entirely a
model-behaviour correction:

- `:372` *"Opus 5 runs long by default … Lowering effort does NOT fix it (effort governs thinking,
  not output), so it has to be prompted for."*
- `:377` *"🚨 THESE RULES ARE TUNED TO OPUS 5, AND FABLE 5.1 FAILS THE OPPOSITE WAY — so on a Fable
  session they correct a problem that is not there."*
- `:409` *"Never add verification you were not asked for. Opus 5 already checks its own work."*
- `:726` the close-message slot discipline cites the Opus 5 guide.
- `:998-1005` the trailing `<tone_preference>` exists *"Per Anthropic's Opus 5 guide"* — a
  conciseness restatement placed at the end specifically to survive distance in a long prompt.

The file has **already anticipated the flip and written the conditional**: everything stays in force
on `versions.opus_latest`; on a session running `frontier_access.model`, read the *intent*. That
conditional is currently correct because Fable sessions are rare. **If Fable becomes `opus_latest`'s
replacement as the default, the conditional inverts and ~50 lines of always-resident prose become
the exception rather than the rule — while still being written as the rule.** The cheap read is that
this is a docs edit. It is not: § Communication Discipline is what produces the close message, and
the close message is what the Session Close Protocol's mechanical arms (`close-shape.sh`,
`completion-assert.sh` D6, the `line-1-rung` matcher) *pattern-match on*. Prose tuned for the wrong
failure direction reaches enforcement.

Three mechanism-level couplings the same section already names, with their current state:

1. **"Fewer progress updates during long tool runs, more pronounced at higher effort … quiet is what
   our stall/liveness surfaces read as stuck."** Partly guarded: `bin/cc-classify:46` sets
   `IDLE_S=300`, and `:386-391` `tool_in_flight()` exists *because* "a single long Bash/build/test
   call otherwise leaves the last record an assistant tool_use timestamped at call START, so IDLE
   crosses 300s mid-call and reads `finished`". That guard covers the tool-in-flight case. The
   residual is a model that emits fewer *interstitial text* turns between tool calls — which is
   exactly the documented 5.1 delta — across `cc-classify`, `waiting-recycle.sh`,
   `lead-crash-watchdog.sh` and the supervisor page. **Fleet-wide quiet has never been measured
   against these thresholds**, and today it cannot have been: Fable sessions are a handful per week.
2. **"Whole-file rewrites for small edits"** — makes § File Update Rule (INTEGRATE-never-overwrite)
   and the `backup-before-write` OVERWRITE GUARD *more* load-bearing. Today that guard is exercised
   against Opus's edit style. As a default it would face a model documented to prefer whole-file
   rewrites, on plan docs whose whole value is accumulated history.
3. **Forced tool use → `auto`.** `model-config.yaml` § Fable 5.1 breaking change 1: thinking is
   always on for 5.1, so the client demotes `tool_choice:{type:"tool"}` to `auto` — *"the schema call
   is no longer compelled, so a schema-bearing agent leans on the Workflow layer's
   validate-and-retry."* Today that touches `workflow_judge` / `eval_judge` / `research_adversarial`.
   On a Fable default it touches **every** `StructuredOutput`-bearing slot on the box, including the
   research fan-out this fleet runs constantly.

---

## 6. What I would put in front of the operator

**The flip is not blocked on intelligence. It is blocked on three things, in this order:**

1. **The 50% scoped meter (§1.1).** This is the one that cannot be argued away and is not mentioned
   anywhere in the framing. It halves fleet capacity and deletes the down-tier. Either it is
   reckoned with, or the flip converts a capacity-rich fleet into a capacity-bound one.
2. **The missing cell in our own grid (§2d).** Opus 5 was measured `@max`, our default is `@high`.
   Nobody has ever measured the incumbent. Cost: one arm of the existing rig
   (`SWEEP_CONFIG_DIR=<acct> ./run-arms.sh` + `judge.py`), same corpus, same judges.
3. **The Fable-scoped limit-message fixture (§1.2)**, which must exist before Fable-scoped limits
   become the common case.

**And the strongest pro-Fable argument is one nobody made:** `per_turn_effort` is a **Fable-5.1-only
capability in this binary** (§3.2). If the fleet genuinely wants to route on effort instead of model,
Fable 5.1 is the only model in our stack that can change effort mid-conversation without paying the
cache. That is a named, measured, architectural strength — the exact standard `CLAUDE.md:303` asks
escalation to meet — and it is a better reason to adopt Fable than any benchmark number in the launch
post.

**Structurally, option (d) is the cheapest correct answer today and option (b) is the right long-term
shape if the per-slot-effort A/B (§3.3) comes back green.** Option (a) is the one to resist: it
deletes the fleet's only hook-enforced spend brake at the moment spend stops being discretionary, and
it replaces a ladder that measured 12-vs-10 with one our own data says is flat above medium.
