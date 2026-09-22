# L2a — Model/effort POLICY SURFACES map (Opus 5.5 adoption input)

Read-only survey of `/Users/chrisren/Development/claude-infrastructure` (+ the out-of-repo live
surfaces it governs), 2026-09-22. Classes: **ROUTING-NOW** (asserts what we use now) ·
**MEASUREMENT-THEN** (dated measurement, preserve verbatim) · **MECHANISM** (how a lever works).
"Edit?" = does Opus 5.5 adoption need an edit there.

---

## 0 · Findings that change how the adoption must be sequenced

1. **The live launcher has ALREADY flipped; the SSOT has not.** `~/.zshrc:496-502` (mtime
   2026-09-22 14:59) runs `~/.claude-280` with `--model "${CLAUDE_NEXT_MODEL:-claude-opus-5-5}"
   --effort high`. `model-config.yaml:43-45` still says `opus_latest: claude-opus-5`,
   `opus_staged: claude-opus-5-5 # NOT routed … our pin is 2.1.260`. The MANIFEST 2.1.280 entry
   (2026-09-22T19:38Z) records cc-upgrade-gate **GREEN 14/0/1** on 2.1.280 × claude-opus-5-5 across
   all four accounts, the operator-run activation `45-opus55-cc280-activate.sh`, and **deliberately
   HELD** the SSOT role flip (opus_latest, lead_default, default_teammate, teammate_mechanical,
   teammate_research, research_worker, frontier_access.fallback, non_firstParty_max). Reason given:
   running panes are still on 2.1.260 and cannot dispatch 5-5. So today the fleet is **split-brain**:
   a fresh bare `claude` = Opus 5.5 @ high; anything that resolves through the SSOT
   (`handoff-fire.sh --model opus` → `versions.opus_latest`, `bin/cc-route` → `roles.lead_default`,
   `reso-resume-one`, `lr-fire-resume.sh`) = Opus 5.
2. **The `opus` alias probably already moved.** 2.1.280's CHANGELOG (quoted in MANIFEST) says Opus
   5.5 is "now the default Opus model". Every agent definition pins `model: opus` (and
   frontier-derivation/deep-research rely on the alias resolving to `versions.opus_latest`). On a
   2.1.280 pane those agents likely run 5.5 regardless of the SSOT. **Unverified** — needs one
   `modelUsage` read of a `deep-research` spawn on 2.1.280 (gate #09 "subagent ran" did not record
   which id the alias resolved to in the text read here).
3. **Opus 5.5's API default effort is `medium`** (every prior Opus: `high`), and 2.1.280 stops a
   saved `/effort` from applying to newly released models (`model-config.yaml:62-72`). Effort flows:
   lead = explicit `--effort high` (safe); teammates/assignees inherit the lead's `--effort` on argv
   (agent-teams:242-244); in-process subagents inherit lead live effort (model-config:817-819);
   **Workflow `agent()` slots with no `effort:` and any bare-binary / IDE / `-p` surface fall to the
   model default** → silently one rung lower than every ladder assumes.
4. **Effort floors have drifted and nothing in the repo knows the per-model lever.**
   `effort-parity-assert.sh` today: DRIFT — `.claude` medium, `.claude-next` low, `.claude-tertiary`
   medium, `.claude-quaternary` low, `.claude-secondary` high vs SSOT `settings_floor: high`.
   Two dirs also carry `"modelSettings": {"claude-fable-5-1": {"effortLevel": "xhigh"}}` — a
   **per-model effort setting** with zero repo consumers (`git grep modelSettings` = 0) and which
   contradicts SSOT `fable51_capability_sensitive: high`. This is the natural per-model lever for a
   5.5 effort key and should be researched before inventing another.
5. **The research-slot and teammate prose is two generations stale** (still "Opus 4.8" /
   "Fable 5" in research-subagents, agent-teams allowlist, frontier-status hook). An Opus 5.5 edit
   that only swaps "Opus 5"→"Opus 5.5" would leave these untouched; they need key-naming rewrites,
   not literal bumps.
6. **No routing-decision index exists in `docs/research/`.** The decisions live in model-config
   comments + four docs (below). `routing-policy-ruling-2026-09-22.md` is ACCOUNT routing, not model
   routing — adjacent, do not conflate.

---

## 1 · CURRENT POLICY SHAPE

### 1a · Role ladder (`model-config.yaml:653-758`, `roles:`)
Header claims a "DYNAMIC LADDER. Most-intelligent by default, stepped down per task class";
frontier roles conditional on `frontier_access` (+ a dead "eval track" condition, :655).

| Role | Model now | Use case |
|---|---|---|
| lead_default | claude-opus-5 | lead/orchestrator @ `effort_defaults.default` (high) |
| frontier_discovery | claude-fable-5-1 | /frontier-run derivation panels (agent-initiated, capped) |
| default_teammate / teammate_mechanical / teammate_research | claude-opus-5 | Agent-Team members; effort differentiates |
| teammate_frontier | claude-fable-5-1 | judgment-dense members (arch/security/review gates) |
| research_worker | claude-opus-5 | in-process / teammate synthesis worker (60% slot) |
| workflow_synthesis_worker | claude-sonnet-5 | Workflow bulk synthesis ONLY, effort **max** + saturation bound (certified free win 2026-07-01) |
| research_retrieval | claude-haiku-4-5 | Explore tier (25% slot) |
| research_adversarial / workflow_judge / eval_judge | claude-fable-5-1 | adversarial/red-team/judge slots (10-15%); fallback → `frontier_access.fallback` = claude-opus-5 (:572) |
| classifier | claude-sonnet-4-6 | Anthropic-hardcoded |
Cross-tier axis stated at :791-793 as "Fable 5 → Opus 4.8 → Sonnet 5 → Haiku 4.5" (stale names).

### 1b · Per-model effort keys (`effort_defaults`, :841-971)
- **Model-agnostic keys (de facto Opus-5-derived):** `default: high` (:842) · `verify_judge: xhigh`
  (:863, certified on Opus 4.8) · `mundane: xhigh` (:871, known-target edits only) ·
  `frontier: max` (:875) · `settings_floor: high` (:886, "floor tracks default; move both together").
- **fable_\*** (Fable 5, :906-908): default high · capability_sensitive xhigh · routine medium.
- **fable51_\*** (Fable 5.1, :936-949, MEASURED 2026-09-10): default high · capability_sensitive
  high (was xhigh) · routine medium · cheap low; "max is NOT a key".
- **opus5_\*** (:968-971, STARTING POINTS, never swept per class): default high ·
  capability_sensitive xhigh · coding_agentic medium · routine low.
- **No `opus55_*` keys exist.** Precedent (fable51 block): new model ⇒ new key family, starting
  points from the vendor guide, then a sweep; never inherit the prior model's values.
- Consumers: `bin/cc-route` `ssot_effort()` reads `default` / `verify_judge` live (:127-214);
  `scripts/effort-parity-assert.sh` reads `settings_floor`; handoff.md §3 names keys in prose.

### 1c · Frontier ladder (`CLAUDE.global.md:334`, frontier-routing skill, NONLIMIT_RESUME_LADDER §W3)
Frontier = third branch of Follow-On Gate F2 ("escalate the MODEL before the HUMAN"). Fire when all
hold, self-evaluated: **T-a** conviction <90% after exhaustive research AND residue is a framing
question · **T-b** an implementation exists for the answer to feed · **T-c** `claude-accounts` shows
weekly-Fable headroom on a routable account (else stage-1 doc is the deliverable). Three same-pane
recycles: `--recycle --model claude-fable-5-1 --effort xhigh --prompt-file <stage-1 doc>` → back to
`--model claude-opus-5` → Agent Teams. Fable writes documents, never edits. Bounded by
`frontier_discovery_budget.max_fable_spawns_per_session: 6` (both carriers; session arm live only
after migration 0029). R3 (auto-fire vs recipe) is the operator's, open at 72%.
Note the stage-1 literal `--effort xhigh` disagrees with `fable51_capability_sensitive: high`.

### 1d · Research slot mix (`commands/research.md:77-91`; `skills/research-subagents/SKILL.md:612-623`)
| Slot | % | Model (research.md) | Model (research-subagents skill) |
|---|---|---|---|
| `deep-research` breadth worker | 60% | Opus 5 (`opus_latest`) | **Opus 4.8** (stale) |
| `Explore` | 25% | Haiku 4.5 (inherits lead, capped opus, on ≥2.1.198) | same |
| `deep-research` adversarial | 10% | frontier (`fable`) else fallback | Fable 5 (stale) |
| `deep-research` multi-hop depth-coord | 5% | frontier else fallback | same |
Canonical-retrieval exception: Explore 25→20%, worker 60→65%. Adversarial floor 15-20% (25-33%
under irreversibility). Workflow variant (skill :405-419): inferential axes → Sonnet-5@max.
N default 10 (band 8-12).

---

## 2 · Surface inventory

### 2a · `model-config.yaml` (SSOT; `~/.claude/model-config.yaml` is a symlink to it)
| path:line | claim (≤30 words) | class | edit? | why |
|---|---|---|---|---|
| :5-15 | Header "Last updated 2026-09-03 … Fable 5.1 adopted"; Opus 5 adoption history | MEASUREMENT-THEN | yes (append) | add the 5.5 adoption line; keep history |
| :43 | `opus_latest: claude-opus-5` | ROUTING-NOW | **yes** | the flip; launcher already runs 5-5 |
| :44 | `opus_prior: claude-opus-4-8` | ROUTING-NOW | yes | → claude-opus-5; arms lint stale-literal sweep for every opus-5 literal |
| :45-73 | `opus_staged: claude-opus-5-5 # NOT routed`; binary gate holds it; $4/$20, cache $0.20; effort default medium; 2.1.280 drops saved /effort | ROUTING-NOW + MEASUREMENT-THEN | yes | clear slot; keep pricing/effort facts as history; "pin is 2.1.260" now false |
| :226-233 | per_turn_effort exists only on Fable 5.1 tier; "re-measure at next binary bump; if tier_5_25 gains it…" | MEASUREMENT-THEN + MECHANISM | conditional | 2.1.280 is that bump and 5.5 is a new $4/$20 tier — re-read the binary |
| :445-506 | § OPUS 5 ADOPTION: staged steps; ROUTING NOTE "Opus 5 ≈ Fable at half cost" | MEASUREMENT-THEN | no (append a § OPUS 5.5 sibling) | template for the 5.5 section |
| :572 | `frontier_access.fallback: claude-opus-5` | ROUTING-NOW | yes | frontier roles degrade to it |
| :582-596 | pricing rows; opus-5 parity-vs-Fable analysis 2026-09-16; "state the currency" | MEASUREMENT-THEN | yes (add row) | add `claude-opus-5-5: [4, 20]`, cache 0.05×; do not rewrite the Opus 5 row |
| :644 | `non_firstParty_max` allowlist lists opus-4-8/5, fable-5/5-1 | ROUTING-NOW / MECHANISM | yes | add claude-opus-5-5 (gate #03 evidence exists); teammate/assignee model resolution depends on it |
| :653-657 | ladder header; frontier roles conditional on "eval track" | ROUTING-NOW | yes | dead track clause; restate |
| :659-668 | `lead_default: claude-opus-5 @ high` | ROUTING-NOW | **yes** | read by cc-route, cc-wave-plan |
| :686-693 | `default_teammate: claude-opus-5` (comment says "stays Opus 4.8") | ROUTING-NOW | yes | model + stale comment |
| :694-707 | `teammate_frontier: fable-5-1`; CursorBench Fable@high vs Opus@max 2026-06-11 | ROUTING-NOW + MEASUREMENT-THEN | conditional | re-justify vs 5.5 (cheaper default narrows the delta) |
| :708-709 | teammate_mechanical/research: claude-opus-5 | ROUTING-NOW | yes | flip |
| :710-719 | `research_worker: claude-opus-5`; T2 history (Sonnet loses floor) | ROUTING-NOW + MEASUREMENT-THEN | yes (model) | keep T2 history verbatim; comment still says "stay Opus 4.8" |
| :720-734 | workflow_synthesis_worker Sonnet-5@max ties Opus-4.8@max, ~2-3× lighter | MEASUREMENT-THEN | conditional | free win certified vs Opus 4.8; 5.5 is cheaper than Opus 5 — re-probe before assuming it still wins |
| :736-758 | research_adversarial/workflow_judge/eval_judge: fable-5-1 | ROUTING-NOW | conditional | freewin T5 (Opus vs Fable matched effort) never run; 5.5 is the new comparator |
| :763-782 | frontier_discovery_budget (cap 6, window-era comments) | MECHANISM | no | model-agnostic |
| :791-840 | effort block comment: ladder "Fable 5 → Opus 4.8…", launcher `:-max`, settings floor xhigh, per-spawn effort mechanics | MECHANISM (partly stale) | yes | names/levers stale; per-spawn mechanics must be re-verified on 2.1.280 (+ modelSettings) |
| :842-862 | `default: high` + Opus-4.8 max certification history | ROUTING-NOW + MEASUREMENT-THEN | conditional | high is explicit via launcher; decide if `default` stays model-agnostic or becomes per-model |
| :863-875 | verify_judge xhigh / mundane xhigh / frontier max | ROUTING-NOW (4.8-certified) | conditional | model-scoped certifications; do not transfer by rule |
| :886 | `settings_floor: high` | ROUTING-NOW | conditional | 2.1.280 ignores saved effort for new models → floor may not bind for 5.5 |
| :956-971 | opus5_* keys + rationale | ROUTING-NOW (starting points) | **yes** | add `opus55_*` sibling block; keep opus5_* |
| :985-989 | retirement floors list | MEASUREMENT-THEN | yes (append) | add claude-opus-5-5 ≥2027-09-22 |

### 2b · `CLAUDE.global.md` (SSOT for `~/.claude/CLAUDE.md`, byte-identical today; 4 config dirs symlink it)
| path:line | claim | class | edit? | why |
|---|---|---|---|---|
| :166 | spawn via `Agent({ name, team_name, model: opus\|fable-5 })` | MECHANISM | yes | `team_name` absent on ≥2.1.220; `fable-5` stale; alias semantics shift on 2.1.280 |
| :296 | Workflow is the only surface with per-slot `effort` | MECHANISM | no | still the key lever (makes the medium-default hazard fixable there) |
| :334 | "Default model = Opus 5 @ effort high … launcher passes `--model claude-opus-5 --effort high`"; frontier ladder T-a/T-b/T-c; `--effort xhigh`; back to `--model claude-opus-5`; Fable parity analysis 2026-09-16 | ROUTING-NOW + MEASUREMENT-THEN | **yes** | launcher literal now false; name the SSOT key instead; ladder stage-3 model; keep 09-16 measurement dated |
| :403-406 | "Opus 5 runs long by default"; source "Prompting Claude Opus 5" guide | ROUTING-NOW (model-behaviour premise) | conditional | the prompting guide for 5.5 decides whether the concision levers still apply |
| :408-422 | rules tuned to Opus 5; Fable 5.1 fails the opposite way; `versions.opus_latest` | ROUTING-NOW | conditional | keyed on the SSOT key (good); verbosity claim per 5.5 guide |
| :440 | "Opus 5 already checks its own work" | ROUTING-NOW | conditional | re-source from 5.5 guide/system card |
| :798 | Opus 5 guidance quote (readable ≠ concise) | MEASUREMENT-THEN | no | dated vendor quote |
| :1070 | end-of-file restatement "per Anthropic's Opus 5 guide" | MECHANISM | conditional | same |

### 2c · `skills/frontier-routing/SKILL.md`
| :4 | "frontier (Fable 5.1) the tier ABOVE the Opus 5 default"; "frontier is opt-in" | ROUTING-NOW | yes | default name; "opt-in" contradicts CLAUDE.global "not opt-in and not a default" |
| :9-11 | "Default = Opus 5 @ high (`roles.lead_default`)"; "frontier (currently Fable 5) opt-in only" | ROUTING-NOW | yes | stale twice |
| :15-17 | frontier only in SSOT conditional slots | ROUTING-NOW | no | key-named |
| :27-29, :35-42 | ≤2 panelists `model: "fable"`; lead never on frontier except ladder stage 2 | MECHANISM | no | model-agnostic |

### 2d · `skills/research-subagents/SKILL.md`
| :46-61 | Opus 5 guide: delegates more readily; numbers not re-swept (cc-decide 264154f10d1a) | ROUTING-NOW + MECHANISM | conditional | re-state against 5.5 guide |
| :389-419 | Quota-aware sizing; worker floor-pinned effort=max, Opus 4.8 in-process; Sonnet-5@max Workflow free win | MEASUREMENT-THEN (probe 07-01) + ROUTING-NOW (stale) | yes | "Opus 4.8"/"effort max" contradict SSOT default high |
| :446-448 | cost table at Opus 4.8 $5/$25, Fable 5 $10/$50 | MEASUREMENT-THEN | conditional | dollars are not the binding currency; don't re-price in place |
| :515, :526, :804 | "`deep-research` (Opus 4.8)"; lead "Fable 5 / Opus 4.8" | ROUTING-NOW (stale) | yes | name the role key |
| :552-568 | `deep-research` frontmatter `opus`; frontier = `versions.frontier_latest` via call-time `fable` | MECHANISM | conditional | alias target moves with binary |
| :581-595 | teammate default Opus 4.8; fable-5 allowlisted | ROUTING-NOW (stale) | yes | |
| :597-610 | QUALITY-FIRST OVERRIDE 2026-06-30 (worker = Opus 4.8) | MEASUREMENT-THEN + ROUTING-NOW | yes | keep measurement; routing line → role key |
| :612-623 | **type-mix pin** 60/25/10/5 with Opus 4.8/Fable 5 | ROUTING-NOW | yes | diverges from research.md |
| :629-649 | escalation triggers; Sonnet-worker re-spawn signals | ROUTING-NOW | conditional | Sonnet-era; fine once key-named |

### 2e · `skills/agent-teams/SKILL.md`
| :17-18 | eval track = 2.1.219 | MECHANISM (stale) | yes | now 2.1.280 |
| :42-45 | teammate model must be on allowlist (`claude-opus-4-8`/`claude-fable-5`) | ROUTING-NOW (stale) | yes | add 5-5 once allowlisted |
| :105-112 | never spawn to verify own output (Opus 5 guide) | ROUTING-NOW | conditional | re-source |
| :200-216 | per-teammate effort via set-teammate-effort.sh; mechanical→high, frontier→xhigh; floor xhigh | MECHANISM + ROUTING-NOW | yes | floor now high (and drifted); fable51 capability key is high |
| :218-255 | model pinning: assignee honors `model`; allowlist fallback; effort inherited on argv, no per-call field | MECHANISM | conditional | re-verify on 2.1.280 (medium default + modelSettings) |

### 2f · agents/*.md (frontmatter — none sets `effort`)
| deep-research.md:3-4 | `model: opus` → opus_latest; "as of 2026-09-03 … Opus 5 and Fable 5, 5.1 parked" | ROUTING-NOW | yes | description stale; alias semantics per binary |
| frontier-derivation.md:3,5 | `model: opus`, call-time `fable` | MECHANISM | conditional | same alias question |
| deep-research-sonnet.md:3-4 | `model: sonnet`; benched; re-enters only via certified Workflow | ROUTING-NOW + MEASUREMENT-THEN | no | Sonnet not affected (confirm `sonnet` alias target on 2.1.280) |
| research-decomposition-critic.md:4 | `model: sonnet` | ROUTING-NOW | no | |

### 2g · Commands
| commands/research.md:80-91 | type-mix table (Opus 5 60% / Haiku 25% / frontier 10+5%); footnotes ¹² dated | ROUTING-NOW + MEASUREMENT-THEN | yes | ¹ still says 5.1 "parked … NOT routed" (false since 09-03); ² "Opus 5" |
| commands/handoff.md:3 | "right account launcher (claude-nextN / claude-fableN)" | MECHANISM (stale) | yes | launchers deleted |
| commands/handoff.md:385-396 | **model×effort×use-case table**, right column names SSOT keys | ROUTING-NOW | yes | add Opus-5.5 rows keyed on `opus55_*`; "certified: xhigh regresses" is Opus-4.8-scoped |
| commands/handoff.md:398-403 | fable51_* "NOT probed against 5.1" | ROUTING-NOW (stale) | yes | probed 2026-09-10 |
| commands/handoff.md:405-408 | `--effort/--model` appended last-wins; `--probe` for Fable | MECHANISM | no | |
| commands/handoff.md:497 | "typical: … Opus@max" | ROUTING-NOW (stale) | yes | |

### 2h · `~/.claude/model-routing-freewin-probe.md` (NOT in the repo — untracked live file)
| :3-4 | Status CERTIFIED; "Governs" role ladder + effort_defaults + research type-mix | MEASUREMENT-THEN | no | preserve |
| :17-31 | T1/T2/T4/T6 decision table (Opus 4.8 xhigh vs max; Sonnet 5@max tie; T6 Fable 5.1 sweep) | MEASUREMENT-THEN | no | model-scoped |
| :225-248 | T5 open: Opus vs Fable at matched effort on adversarial slot | ROUTING-NOW (open question) | **yes (reframe)** | comparator becomes Opus 5.5; cheapest high-value probe for the 10-15% slots |
| :250-270 | lexicographic decision rule (quality first; free-win) | MECHANISM | no | the rule any 5.5 effort sweep must use |
| :272-302 | quota-constrained refinement; worker floor effort=max | MEASUREMENT-THEN | no | |
| :304-311 | harness reality table (Workflow = only per-unit model×effort) | MECHANISM | yes | allowlist names stale; add modelSettings + 2.1.280 behaviour |

### 2i · Code consumers / launch surfaces (MECHANISM; the "enforcing store")
| ~/.zshrc:424-428 | header: binary 2.1.219, model claude-opus-5 | stale comment | yes (operator file) |
| ~/.zshrc:496-502 | `_bin=~/.claude-280`, `--model ${CLAUDE_NEXT_MODEL:-claude-opus-5-5} --effort high` | ROUTING-NOW | done | already flipped |
| bin/cc-route:14-24,178-214 | lead = `roles.lead_default` @ `effort_defaults.default`; adversarial @ verify_judge | MECHANISM | via SSOT | follows the flip |
| scripts/handoff-fire.sh:9491-9494 | `--model opus` → `versions.opus_latest`, fallback literal claude-opus-5 | MECHANISM | yes (fallback literal) | |
| lib/cc-upgrade-gate/check05_launcher.sh:12,123,189 | expects `--model claude-opus-5 --effort high` | MECHANISM | conditional | gate passed on 280 so it may already read SSOT/launcher; verify |
| scripts/limit-recover/lr-fire-resume.sh:316, bin/reso-resume-one:171-176 | resume model = SSOT opus_latest | MECHANISM | via SSOT | |
| hooks/frontier-status.sh:4-5 | "default model is Opus 4.8" | stale comment | yes | |
| hooks/lib/read-before-write-parity.sh:102 | model→GrowthBook bucket `opus_5` | MECHANISM | conditional | `opus_5_5` is a new bucket; flag may differ |
| settings.json ×5 `effortLevel` + `modelSettings` | medium/low/low/medium/high; fable-5-1 xhigh | ROUTING-NOW (drifted) | conditional/operator | class-C surface |

### 2j · docs/research routing records (MEASUREMENT-THEN; preserve, cite, do not edit)
- `OPUS5_ADOPTION_AND_PROMPTING_2026-07-24.md` — §2 effort, §9 routing, §10 "7 changes" — **the template** for an Opus 5.5 adoption doc.
- `opus5-adaptation-2026-08-01.md` — §D3 effort re-tier (per-class sweep still owed), §D6 frontier delta.
- `fable51-effort-sweep-2026-09-10/` — only per-effort measurement with per-cell cost.
- `fable51-vs-opus5-routing-2026-09-16/` — "keep Opus 5 @ high", 93%, quota-currency argument.
- `routing-policy-ruling-2026-09-22.md` — ACCOUNT routing (KWORK_BUDGET_S), not model routing.
- No index file exists.

---

## 3 · Single best home for a model × effort × use-case table

**`model-config.yaml § effort_defaults` (:841-971), restructured as per-model key families
(`opus55_*` beside `opus5_*`, `fable51_*`) with each key's comment naming its use case — and
`commands/handoff.md §3` (:385-403) as the one rendered view, whose right-hand column already names
SSOT keys rather than models.**

Why: (1) it is the only surface with code consumers (`cc-route ssot_effort`, `effort-parity-assert`,
handoff-fire's SSOT reader), so a table there is enforced, not advisory; (2) it already holds the
per-model precedent (fable51 block: new model ⇒ new keys, starting points, then a measured sweep);
(3) roles:(model axis) sits directly above it in the same file, so model×effort×use-case is one
read; (4) prose tables that spell model names are exactly the surfaces that went two generations
stale (research-subagents, agent-teams, frontier-routing) — they should POINT at these keys, per the
"resident rule must not restate perishable facts" lesson. Do not create a parallel doc table.

---

## 4 · Suggested coherent edit order (for the adoption lead)
1. Verify on 2.1.280: `opus` alias target; Workflow `agent()` effort default; whether
   `modelSettings.<id>.effortLevel` is the per-model lever; `per_turn_effort` on the 5.5 tier.
2. SSOT flip in one diff: versions (latest/prior/staged), roles (the 8 MANIFEST names),
   fallback, allowlist, pricing, retirement floor, new `opus55_*` block (starting points from the
   5.5 guide; mark unswept), stale comment names.
3. Rewrite prose surfaces to name keys: CLAUDE.global:166/:334, frontier-routing :4/:9-11,
   research-subagents type-mix + override, agent-teams allowlist/floor, research.md footnotes,
   handoff.md §3 + :3/:398-403/:497, agents/deep-research.md description, frontier-status hook.
4. Reframe freewin T5 with Opus 5.5 as the comparator; schedule the 5.5 effort sweep (fable51 recipe).
5. Operator items: settings.json effortLevel realignment; zshrc header comment.
