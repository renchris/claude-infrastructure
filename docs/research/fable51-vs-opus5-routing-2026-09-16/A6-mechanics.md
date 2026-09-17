# A6 — Mechanics of a default-tier flip (Opus 5 → Fable 5.1)

**Axis:** if the operator says yes, what EXACTLY changes — the full diff surface, and the traps.
**Date:** 2026-09-16 · **Mode:** read-only · **Repo:** `/Users/chrisren/Development/claude-infrastructure` @ `7ceee6d69`

---

## HEADLINE

The flip is **not a `/model-upgrade` case**. The skill has three cases (A lateral, B tier-insertion,
C downgrade) and a default-tier flip is **none of them** — it is a role/ladder re-pointing with the
version map untouched. `claude-bump-models` is structurally incapable of executing it (it only ever
sweeps `<family>_prior → <family>_latest` pairs; a role change creates no pair), and the one way to
force it — `--from-to claude-opus-5 claude-fable-5-1` — would rewrite **64 `claude-opus-5`
occurrences across 62 reso team-brief files** through an **unanchored sed**. The SSOT's own line 586
tells you to do exactly that (*"when a role's optimal model changes, update here + run
`claude-bump-models --apply`"*) and it is wrong for this class of change.

Beyond tooling, the flip lands on **two live mechanisms that are keyed on Fable-ness and change
behaviour the moment Fable stops being exceptional**: the per-session **frontier spawn cap** and the
**Fable-scoped quota meter (coupling = 0.5 of weekly)**. Both fail *silently and in opposite
directions* — the cap disarms, the meter mis-routes.

---

## 1 · The model-upgrade skill: runbook, automation, and the missing Case D

**File:** `skills/model-upgrade/SKILL.md` (322 lines, last substantive edit 2026-09-03).

### What it is

| Step | What it does |
|---|---|
| **Step -1** | invoke `claude-api` skill for authoritative ids/pricing — never answer from memory |
| **Step 0** | **THE BINARY GATE** — `strings -a $BIN \| grep -c <id>` with `claude-opus-5` as positive control. Absent ⇒ STAGED, `--apply` prohibited absolutely |
| **Step 1** | classify: **A** lateral · **B** tier-insertion · **C** downgrade/window-end |
| then | the case's own numbered steps + § Model-id keying (detectors vs emitters) + § Verification + § Appendix (binary pins) |

### What it automates

Almost nothing. Two scripts:

- `~/bin/claude-bump-models` — literal-id sweep, driven by `versions.<family>_{prior,latest}`
- `scripts/claude-lint-models.sh` — stale-ref lint (stale set = `*_prior` values + `deprecations` keys) + a frontier-window expiry check

Everything else in the skill is a **hand-walked checklist**. `review`-classified files (which
includes `model-config.yaml` itself) are explicitly *never* auto-rewritten.

### 🚨 There is NO path for "change the DEFAULT tier"

This is the load-bearing finding of Q1. Read the three cases against the proposed change:

| Case | Signature (skill's own words) | Does a default flip match? |
|---|---|---|
| **A. Lateral** | "New model REPLACES same-family prior" — Fable 5 → 5.1, Opus 4.7 → 4.8 | **No.** Opus 5 is not being replaced by anything. `opus_latest` stays `claude-opus-5`. No family's `_prior`/`_latest` moves. |
| **B. Tier-insertion** | "New tier ABOVE the ladder; **old top STAYS in service**" | **No.** Fable is *already* inserted (2026-06-09, `frontier_access.permanent: true`). This is the inverse: collapsing an existing two-tier ladder into one. |
| **C. Downgrade / window-end** | "Access to top tier lapses; fall back" | **No.** Nothing lapses. And the skill itself notes Case C is now inapplicable to Fable at all (`permanent: true`). |

**Every prior use of this runbook was a lateral bump within a tier, or an insertion above it.** The
skill's entire mechanical apparatus — `_prior`/`_latest`, the bump sweep, the stale lint — is built
on the assumption that *a model id is being replaced by its successor in the same family*. A default
flip replaces **a role's target across families**, which:

- creates no bump pair ⇒ `claude-bump-models` is a no-op
- writes no `_prior` ⇒ `claude-lint-models --all` stays green over a fleet still full of `claude-opus-5` literals, and **cannot tell you the flip is half-done**
- leaves `versions.opus_latest` correct and current ⇒ Step 0's binary gate is trivially satisfied and tells you nothing

So the verification block at SKILL.md:228-238 — `claude-bump-models` dry-run expects 0 pending,
`claude-lint-models --all` must be green — **is green before, during, and after a botched default
flip.** The skill's own safety net does not reach this change.

**What the skill DOES still give you, and it is the valuable half:** § Model-id keying
(SKILL.md:110-139) — the DETECTOR/EMITTER split, the vacuous-selftest trap, and the glob-vs-equality
trap. Those are exactly the classes a default flip hits. The runbook needs a **Case D** written
around them.

---

## 2 · The prefix hazard — VERIFIED STILL LIVE, at these exact lines

### The hazard

| Where | Line | Code | Prefix-safe? |
|---|---|---|---|
| `~/bin/claude-bump-models` | **131** | `if grep -qF "$OLD" "$file"` | ❌ unanchored substring |
| `~/bin/claude-bump-models` | **133** | `sed -i.bump-bak "s\|$OLD\|$NEW\|g" "$file"` | ❌ **unanchored, global** |
| `scripts/claude-lint-models.sh` | **82** | `grep -qE "${literal}([^-0-9]\|\$)"` | ✅ word-boundary guarded |

MEASURED, this session. The SSOT records this at `model-config.yaml:113-124` and cites
`claude-bump-models:133` — **the line number is still exactly 133 today.** Two tools, one SSOT,
opposite safety: the CHECKER cannot flag the corruption the APPLIER creates.

### Is the pair armed today? YES.

```
$ claude-bump-models        # dry-run
=== Bump pairs ===
claude-fable-5|claude-fable-5-1          ← the hazardous pair, ARMED
claude-opus-4-8|claude-opus-5
claude-sonnet-4-6|claude-sonnet-5
```

MEASURED 2026-09-16. `frontier_prior: claude-fable-5` is set, so the pair is live. Any file in the
sweep's target set containing `claude-fable-5-1` would be corrupted to `claude-fable-5-1-1` on
`--apply`.

### Current exposure: confirmed ZERO for the fable pair, NON-zero for opus

I re-derived the effective target set rather than trusting the SSOT comment. The non-`**` globs in
`model-classification.json` (`Development/reso-management-app/docs/plans/**/*.md`,
`Development/claude-infrastructure/README.md`, `Development/claude-infrastructure/agents/*.md`, …)
are **dead**: `claude-bump-models:97` matches `find "$root" -type f -path "$root/$glob"`, and those
globs are written relative to `$HOME` while the roots already *are* those directories — so the
constructed path is e.g. `…/claude-infrastructure/Development/claude-infrastructure/agents/*.md`,
which matches nothing. The `**/memory/*` globs are all also in `preserve` and get subtracted at
`claude-bump-models:115`.

**Effective target set = `**/.claude/team-briefs/*` only. MEASURED: 62 files.**

```
$ … | xargs grep -oh 'claude-fable-5-1\|claude-fable-5\|claude-opus-5\|claude-opus-4-8\|claude-sonnet-4-6\|claude-sonnet-5' | sort | uniq -c
   1 claude-opus-4-8
  64 claude-opus-5
   1 claude-sonnet-4-6
```

- **Fable ids: 0.** The SSOT's "exposure is currently ZERO" claim **reproduces** — but it is a
  property of the target set, not of the tool, exactly as the SSOT says.
- **`claude-opus-5`: 64 occurrences across the reso team-briefs.** These are teammate model pins in
  a *second repo with its own gate and land cycle*.

### 🚨 Does a default flip newly expose files the sweep touches?

**Yes — and this is the single most dangerous mechanical trap in the whole change.**

The only way to make `claude-bump-models` execute a default flip is `--from-to claude-opus-5
claude-fable-5-1` (`claude-bump-models:40,62-63` — a `--from-to` pair bypasses the version map
entirely and is swept over the same target set). That immediately:

1. Rewrites **64 `claude-opus-5` → `claude-fable-5-1` in reso team-briefs.** Those briefs pin
   *teammate* models, which the ladder explicitly keeps on the default/allowlisted tier — not on the
   frontier tier. This silently re-tiers every historical and live team brief in another repo.
2. Mutates the **PRIMARY reso checkout's working tree** (SKILL.md invariant 5, `claude-bump-models`
   has no worktree awareness), leaving uncommitted changes in a repo the session is not in.
3. Is **irreversible only by a second `--from-to` in reverse**, which would then also rewrite any
   *legitimately* Fable-pinned brief to Opus. The inverse sweep is not the inverse function.

And the prefix hazard compounds: run `--from-to claude-opus-5 claude-fable-5-1` **first**, and the
still-armed `claude-fable-5|claude-fable-5-1` pair is evaluated in the same pass over the same files
(`claude-bump-models:128` loops all pairs per file) — the freshly-written `claude-fable-5-1` strings
match `grep -qF claude-fable-5` and become **`claude-fable-5-1-1`**. Pair ordering in
`BUMP_PAIRS_FILE` decides whether this fires; with `--from-to` only one pair exists, so it does not
— but any subsequent bare `--apply` over those now-Fable-bearing files **will**.

> **GUARD:** a default flip must not touch `claude-bump-models` at all. Do the role edits by hand in
> the SSOT (which is `review`-classified and therefore never swept anyway), and **anchor the sed at
> line 133 before anyone adds `scripts/`, `bin/` or `hooks/` to the `update` list** — the SSOT
> already carries that warning at `model-config.yaml:121-124`.

---

## 3 · The full diff surface — every site that encodes the default model or effort

### 3a · SSOT (`model-config.yaml`, symlinked live to `~/.claude/model-config.yaml`)

| Line | Key | Current | Changes on a flip? |
|---|---|---|---|
| 43 | `versions.opus_latest` | `claude-opus-5` | **NO** — Opus 5 is not replaced. Leave alone. |
| 18 | `versions.frontier_latest` | `claude-fable-5-1` | **NO** — Fable is already frontier_latest. |
| 25/32/45 | `*_prior` / `*_staged` | set / `""` | **NO.** Writing `opus_prior: claude-opus-5` would be the classic error — it arms the lint to convict a healthy, still-default model as stale. |
| **589** | `roles.lead_default` | `claude-opus-5` | ✅ **THE flip.** |
| **614** | `roles.default_teammate` | `claude-opus-5` | ✅ |
| **636** | `roles.teammate_mechanical` | `claude-opus-5` | ✅ |
| **637** | `roles.teammate_research` | `claude-opus-5` | ✅ |
| **638** | `roles.research_worker` | `claude-opus-5` | ✅ |
| **522** | `frontier_access.fallback` | `claude-opus-5` | ⚠️ **must NOT become Fable** — it is the degrade target. Leaving it is correct but makes the ladder degenerate (see §3f). |
| 597/622/664/669/686 | `frontier_discovery`, `teammate_frontier`, `research_adversarial`, `workflow_judge`, `eval_judge` | `claude-fable-5-1` | **NO** — already Fable. But they become *indistinguishable from the default*, which is what kills the tier's meaning. |
| 648 | `workflow_synthesis_worker` | `claude-sonnet-5` | NO |
| 663 | `research_retrieval` | `claude-haiku-4-5` | NO |
| **774** | `effort_defaults.default` | `high` | ⚠️ contested — see §3e |
| **811** | `effort_defaults.settings_floor` | `high` | ⚠️ must move with `default` (the key's own comment: "Floor tracks `default`; move both together") |
| 852-871 | `fable51_default/…_capability_sensitive/…_routine/…_cheap` | high/high/medium/low | these become the **live** ladder |
| 903-906 | `opus5_*` | high/xhigh/medium/low | become vestigial |
| 574 | `auto_mode_allowlist.non_firstParty_max` | `[…, claude-fable-5, claude-fable-5-1]` | **NO EDIT NEEDED** — 5.1 is already listed (added 2026-09-03). ✅ good news |
| 532-552 | `pricing_per_mtok` | both ids present | **NO EDIT NEEDED.** ⚠️ but the cache-read asymmetry (Fable 5.1 = 0.025× base input; everything else 0.1×) lives only in a **comment** (line 533-537) and no consumer reads it — every cost consumer indexes the `[input, output]` pair positionally. |
| 485-523 | `frontier_access` block | `model: claude-fable-5-1`, `active: true`, `end: "2099-12-31"`, `permanent: true` | **NO EDIT** |

### 3b · Launcher (`~/.zshrc`) — two bodies with DIFFERENT defaults

| Line | Code | Class |
|---|---|---|
| **498** | `… --model "${CLAUDE_NEXT_MODEL:-claude-opus-5}" --effort "$_eff"` (worktree arm of `claude()`) | **EMITTER** — the fleet default |
| **502** | same, non-worktree arm | **EMITTER** |
| **495** | `local _eff="${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}"` | **EMITTER**, effort. Note the legacy var name `CLAUDE_OPUS5_EFFORT` is model-named. |
| **489** | `if [[ " ${CLAUDE_NEXT_MODEL:-} $* " == *claude-fable-5* ]] && [[ -t 2 ]]; then echo "⚠️ Fable 5 session — ~2× Opus burn…"` | **DETECTOR (glob)** — 🚨 matches `claude-fable-5-1`. If Fable becomes the launcher default, **this cost warning fires on every interactive session, forever.** An always-firing alarm carries zero bits. Must be deleted or re-scoped in the same diff. |
| 80 | `CLAUDE_DEFAULT_EFFORT="${CLAUDE_DEFAULT_EFFORT:-max}"` | **EMITTER**, feeds the *other* launcher body |
| 173 / 175 | `claude-latest --permission-mode auto --effort "${CLAUDE_DEFAULT_EFFORT:-max}"` | EMITTER (legacy `claude-latest` path) |
| 191 | `claude-x() { claude --effort xhigh "$@"; }` | EMITTER — model-agnostic, but xhigh means something different on the Fable ladder |
| 192 | `claude-h() { claude --effort high "$@"; }` | EMITTER |

**Pre-existing drift, MEASURED:** `scripts/effort-parity-assert.sh` reports
`DRIFT zshrc launcher --effort default {CLAUDE_DEFAULT_EFFORT:-max} != SSOT high`. Two effort
defaults in one file (`max` at :80, `high` at :495) already disagree.

### 3c · The five per-config-dir `settings.json` — ALREADY BROKEN

MEASURED this session, `bash scripts/effort-parity-assert.sh`:

```
effort-parity-assert: SSOT floor=high launcher-default=high
  BELOW     .claude/settings.json            effortLevel=medium < floor high
  BELOW     .claude-next/settings.json       effortLevel=low    < floor high
  OK        .claude-secondary/settings.json  effortLevel=high  >= floor high
  BELOW     .claude-tertiary/settings.json   effortLevel=medium < floor high
  BELOW     .claude-quaternary/settings.json effortLevel=low    < floor high
  DRIFT     zshrc launcher                   --effort default {CLAUDE_DEFAULT_EFFORT:-max} != SSOT high
```

**4 of 5 config dirs sit BELOW the declared floor today.** Two consequences for the flip:

1. Any argument of the form "we will re-tune effort along with the model" **has no mechanism today**
   for the non-wrapped surfaces (IDE extension, teammate pane spawns, bare-binary calls). The script
   itself says realigning them is *"the operator step, not this script"* — an authority-ceiling
   (class-C) surface.
2. **A sixth site nobody in the brief's list names:** `~/.claude-quaternary/settings.json:412`
   carries `"model": "opus[1m]"` — a **settings-level model pin using the family alias**, in the
   config dir this very session runs under. It is an EMITTER in the skill's taxonomy: it never goes
   false, it just keeps that whole account on Opus after the flip. MEASURED across all five dirs:
   only quaternary has a `model` key.

   ⚠️ Secondary trap: the `[1m]` suffix. `hooks/lib/read-before-write-parity.sh:102-119` mirrors the
   binary's `bQt()` bucketing (`claude-opus-5[1m] → opus_5`). Whether `claude-fable-5-1[1m]` exists
   as a served variant is **UNVERIFIED** — do not assume the 1M pin survives a family change.

### 3d · Scripts / bin / hooks

**Already SSOT-driven — follow a flip automatically, no edit:**

| Site | What it reads |
|---|---|
| `scripts/handoff-fire.sh:8710-8712` | `_ssot_scalar frontier_access model` / `versions opus_latest` for the `fable`/`opus` aliases, with today's values as fallbacks |
| `bin/cc-route:178, 189, 196, 213-214` | `roles.lead_default`, `effort_defaults.default`, `frontier_access.model`, `effort_defaults.verify_judge` — all live reads, fail-LOUD (exit 3) on parse failure |
| `bin/cc-wave-plan:604-647` | resolves every slot through `cc-route`; never hardcodes an id |
| `hooks/agent-teams-enforce.sh:513-548` | reads `auto_mode_allowlist` from the SSOT; `claude-fable-5-1` is already listed ⇒ teammate spawns on Fable already pass |
| `hooks/frontier-spawn-gate.sh:26-38` | reads `frontier_access.model`, matches `fable\|claude-fable-5*\|"$fmodel"` |

**Prefix DETECTORS in `scripts/handoff-fire.sh` — correct today, behaviour-changing after a flip:**

| Line | Code | What fires after the flip |
|---|---|---|
| **9276** | `case "$MODEL" in claude-fable-5*) FABLE_EFFECTIVE=1 ;;` | fires on **every** fired session |
| **9284** | `echo "⚠️ Fable 5 is the frontier tier — ~2× the default model's cost…"` | printed on every fire — second always-on alarm |
| **9030** | `case "$MODEL" in claude-fable-5*) kind=fable ;;` → `claude-accounts --rank fable` | ✅ correct, but see §3f |
| **9157** | `case "$MODEL" in claude-fable-5*) probe_model="$MODEL" ;;` | the entitlement probe stops using `claude-haiku-4-5` and burns **Fable** tokens on every fire |
| **9286-9293** | checks `frontier_access.active` and warns if not true | harmless (permanently true) |

**Hardcoded-literal EMITTERS that do NOT follow the SSOT:**

| Site | Code | Note |
|---|---|---|
| `bin/reso-resume-one:402-405` | `fable\|claude-fable) … model=claude-fable-5-1` ×4 | already 5.1 — but the *opus* arms at :20/:389 still cite `claude-opus-4-8`/`claude-opus-5` in prose |
| `scripts/limit-recover/lr-fire-resume.sh:231` | `[ "$CC_ACCT_IS_FABLE" = 1 ] && { model="claude-fable-5-1"; effort="high"; }` | |
| `scripts/limit-recover/lr-handoff.sh:564` | `FIRE_ARGV+=(--model claude-fable-5-1 --effort "${EFFORT:-high}")` | |
| `scripts/meter-experiment/run.sh:65,72`, `control.sh:46` | `--model claude-opus-5` | experiment fixtures — **preserve**, they are provenance |

**Vacuously-green selftest assertions (SKILL.md:130-132's named trap) — verified inert:**
`bin/cc-route:276,333` and `bin/cc-wave-plan:866,936` assert on model ids, but all four are inside
**stub fixtures with their own temp SSOT / route-stub**, so they are decoupled from the real config
and a flip neither breaks nor is checked by them. *(Corrects the natural reading that
`cc-wave-plan:866` is a live emitter — it is inside `selftest()`'s heredoc.)*

### 3e · Docs / knowledge layer

| File:line | Text | Action |
|---|---|---|
| `CLAUDE.global.md:303` (§ Frontier Tier Routing) | *"Default model = Opus 5 @ effort high … the frontier tier (currently Fable 5) is **opt-in only** … the lead itself never runs on it"* | ✅ **must be rewritten** — the flip deletes the concept this paragraph is built on |
| `~/.claude/CLAUDE.md:303` | **byte-identical** (verified by diff) but a **REAL FILE, not a symlink** (`install.sh:883-886` copies it). MEASURED: `~/.claude/model-config.yaml` IS a symlink; `~/.claude/CLAUDE.md` is not. | edit BOTH, or land + `install.sh`/`deploy-live.sh` |
| `skills/frontier-routing/SKILL.md:9` | *"Default model = Opus 4.8 @ effort max"* | 🚨 **ALREADY TWO FLIPS STALE TODAY.** Proof that the prose layer does not track SSOT flips. |
| `skills/frontier-routing/SKILL.md:4` (description) | *"Fable 5, the tier ABOVE the Opus 4.8 default"* | also stale; descriptions gate skill auto-load |
| `skills/frontier-routing/SKILL.md:11,35` | *"opt-in"*, *"the lead itself never runs on the frontier model"* | the flip contradicts both |
| `commands/handoff.md:383-404` | the §3 Model+effort routing table — 6 rows, Opus rows vs Fable rows | full rewrite; rows 388-390 become rows 391-394 |
| `commands/handoff.md:345` | `claude-accounts --rank general\|fable` (fable when `--model fable`) | see §3f |
| `commands/research.md:85,87,89` | frontier footnote, already rewritten once to name the KEY not the model | re-check |
| `commands/accounts.md:127` | frontier refs | re-check |
| `skills/agent-teams/SKILL.md:43,223` | allowlist cited as `claude-opus-4-8 / claude-fable-5` | stale today |
| `skills/research-subagents/SKILL.md:446,583` | `claude-fable-5` cost model + "default Opus 4.8" | stale today |
| `skills/resume-sessions/SKILL.md:117`, `REFERENCE.md:215` | `claude-fable-5`, `frontier_access.end` | stale today |
| `model-config.yaml:589` comment | *"lead/orchestrator sessions — Opus 5 @ effort max"* | stale inside the SSOT itself (effort is `high` since 2026-08-01) |
| `agents/*.md` frontmatter | `deep-research: model: opus` · `deep-research-sonnet: model: sonnet` · `frontier-derivation: model: opus` (+ prose `model: "fable"` at call time) · `research-decomposition-critic: model: sonnet` | **NO EDIT** — SKILL.md Case B step 4 invariant: *"Agent frontmatter stays a family alias"*. The alias `opus` resolves through the binary, not the SSOT. ⚠️ but that means agents keep resolving to **Opus** after the flip unless the alias itself is changed — which we do not control. |

### 3f · 🚨 THE TWO MECHANISMS THAT SILENTLY CHANGE MEANING

These are not diff sites. They are live behaviours whose *premise* is that Fable is exceptional.

#### (i) The frontier spawn cap DISARMS

`hooks/frontier-spawn-gate.sh` enforces `frontier_discovery_budget.max_fable_spawns_per_session`
(6, halved on reserve dates) — the "bounded autonomy" guarantee CLAUDE.md § Frontier Tier Routing
rests on. Its entry condition is line 23:

```bash
[ -n "${req_model:-}" ] || exit 0        # no tool_input.model ⇒ ungated
```

An `Agent` spawn that names no model inherits the lead's and **never reaches the cap**. Today that
is safe: routine spawns are Opus, and anything wanting Fable must *name* it, which is exactly when
the cap applies. After a flip, the correct way to spawn on the default is to name nothing — so
**every frontier spawn becomes uncapped**, and the hook's population empties. Meanwhile any spawn
that *does* still name `fable`/`claude-fable-5*` (there are many in briefs, commands and skills) is
capped at 6 and refused on the 7th with *"Do NOT retry: park the remaining hole(s)"* — a refusal
that now hits ordinary work.

Same class as the empty-population failures already in this repo's rules corpus (the in-process
depth cap; the duplicate-worker lease emptied by auto mode's Bash-first instruction).

#### (ii) The Fable meter is HALF the weekly cap, and `cc-route` would bill the wrong one

MEASURED in `accounts.json` → `frontier.coupling: 0.5`, documented as *"fable_cap/weekly_cap per SSOT
'<=50% of weekly usage limits'"*. `bin/claude-accounts:3459-3494` `score_fable()` computes
`f_eff = min(coupling * (1 - fable_pct/100), w_rem)` and can refuse with `fable-exhausted` /
`no-fable-limit`.

**Live reading, 2026-09-16** (`claude-accounts --json`, 4 accounts):

| account | session % | weekly % | **fable %** |
|---|---|---|---|
| 1 | 0 | **94** | 7 |
| 2 | 6 | 40 | 13 |
| 3 | 2 | 6 | 0 |
| 4 | 65 | **100** | 76 |

Fable headroom looks abundant — but that is a **selection effect of Fable being opt-in**. The
general weekly meter is the binding constraint on 2 of 4 accounts *today*; making Fable the default
moves that load onto a meter with **half the ceiling**.

**And the two routers disagree about which meter to read:**

| Tool | Keyed on | After the flip |
|---|---|---|
| `scripts/handoff-fire.sh:9030` | **$MODEL** prefix → `--rank fable` | ✅ correctly bills the Fable meter |
| `bin/cc-route:184-193` | **$SLOT** — `lead\|transcription` → `route_account general` | ❌ emits a **Fable** model routed against the **general** meter. `fable_pct` never consulted; `fable-exhausted` can never fire for the default lane. |

That is the *sibling-auditors-must-share-the-state-model* class, verbatim: one population, two
readings, and the divergent one is silent.

**Third-order:** `bin/cc-route:196-221` — for `judgment-dense`/`adversarial`, when the fable route
refuses (rc 2) it emits **`$lead_model`** as "designed Opus fallback". If `lead_default` is Fable,
**the degrade path degrades from Fable to Fable.** The reason string still says "Opus fallback".
The ladder stops having a floor.

---

## 4 · Rollback

### What reverts cleanly

| Surface | Revert | Signal latency |
|---|---|---|
| `model-config.yaml` roles + effort keys | one `git revert` of the flip commit | instant — it is a **symlink** into the checkout, so a revert + land is live on the next SSOT read (no `deploy-live` needed for this file) |
| `~/.zshrc` emitters (:489/:495/:498/:502) | same revert, but zshrc is **not in the repo** — it is a hand-edited file on the box | ⚠️ **NOT covered by `git revert`.** Needs its own backup. `hooks/backup-before-write.sh` covers Write-tool edits only. |
| `~/.claude/CLAUDE.md` | **a real file copied by `install.sh:883`** — reverting `CLAUDE.global.md` does NOT revert it | needs `install.sh` or `deploy-live.sh` re-run |
| skills / commands / hooks / bin | per-file **symlinks** into the checkout ⇒ live on the trunk fast-forward | needs `bash scripts/deploy-live.sh` — and a landed diff that **ADDS** a file gets **no converge budget** (CLAUDE.md § 🚀) |
| `settings.json` × 5 | **no revert path** — these are five independent real files, operator-owned (class-C authority ceiling per `effort-parity-assert.sh`) | manual |
| `claude-bump-models --apply` sweep | `--from-to <new> <old>` (SKILL.md:107) — **not an inverse function**, it also rewrites legitimately-Fable sites | ⚠️ lossy |

### How fast is the signal that the flip was wrong?

**This is the weak half, and it is weak in the expensive direction.**

| Signal | Latency | Reliability |
|---|---|---|
| `claude-lint-models --all` | instant | ❌ **green throughout** — no `_prior` was written, so its stale set is empty for this change |
| `claude-bump-models` dry-run | instant | ❌ **0 pending throughout** — no bump pair exists |
| `effort-parity-assert.sh` | instant | ⚠️ already DRIFT on 5 of 6 surfaces — **an alarm that is already firing cannot signal a new fault** |
| `cc-upgrade-gate.sh <bin> claude-fable-5-1 next…` | ~minutes | ✅ **the only mechanical instrument that applies.** 14 self-evidencing checks; already run GREEN on 2.1.260 × claude-fable-5-1 on 2026-09-03 (13 pass/0 fail/1 skip, recorded `model-config.yaml:71`). But it proves *the harness works*, never *the routing is right*. |
| quota exhaustion on the Fable meter | **hours to days** | the real signal, and it arrives as a **fleet-wide outage**, not a warning. `score_fable` returns `fable-exhausted`; `handoff-fire` halts rather than firing blind; `cc-route` (general-keyed) does not even see it coming. |
| quality regression | **weeks, and unmeasurable without an eval** | our one measurement (§5) covers ONE task class |

**Verdict:** rollback is *mechanically* cheap (one revert + a converge + a manual zshrc/settings
pass) and *epistemically* expensive — **no shipped check can tell you the flip was wrong.** Every
green light stays green. That asymmetry is the strongest mechanical argument for §5's A/B over a
flip.

---

## 5 · The A/B: route ONE lane, don't flip the default

### Is there an existing staging pattern? Partially.

- `versions.<family>_staged` (`model-config.yaml:32,45`) — **inert by construction**: both tools key
  on `*_latest`/`*_prior` only (`claude-bump-models:66-67`, `claude-lint-models.sh:33`). It stages a
  *release*, not a *routing decision*, and there is no `roles.*_staged`.
- `cc-upgrade-gate` — a **capability** gate (does the harness work), not a **quality/economics**
  gate. Already GREEN on 5.1.
- `accounts.json` accounts carry **no `model` field** (MEASURED — only `name`, `config_dir`,
  `launcher`), so "route one ACCOUNT to Fable" has no declarative home.

So: no equivalent exists. But the **role ladder itself is the staging surface**, and it is already
per-slot. Design the A/B there.

### Concrete design: the `research_worker` arm

**What gets routed.** Move exactly ONE role — `roles.research_worker` (`model-config.yaml:638`) —
from `claude-opus-5` to `claude-fable-5-1`. Rationale, all mechanical:

- It is a **high-volume, self-verifying, same-shaped** population (N=10 research waves are the
  standing default), so a difference shows up in days rather than months.
- It is **already allowlisted** (`auto_mode_allowlist.non_firstParty_max` carries
  `claude-fable-5-1`), so `hooks/agent-teams-enforce.sh` passes with zero edits.
- It is **not** `lead_default`, so `cc-route`'s slot→meter keying (§3f-ii) is untouched and no
  routing bug is introduced by the experiment itself.
- It is **not** on the frontier-gate's path for bare spawns, so the spawn cap neither disarms nor
  over-fires.
- Reverting is a **one-line** SSOT edit with an instant live effect (symlink).

**Second arm, if one lane is not enough:** `roles.default_teammate` (:614). Teammates spawn into
worktrees with per-member effort via `scripts/set-teammate-effort.sh`, giving an effort axis for
free. Do **not** move `lead_default` in an experiment — that is the flip, not an A/B.

**What gets measured.** Three families, all already instrumented:

| Axis | Instrument | Already exists? |
|---|---|---|
| **Cost per unit of work** | `bin/cc-quota-price` + `claude-accounts --json` `fable_pct` vs `weekly_pct` deltas per wave | ✅ |
| **Meter pressure** | the ratio `Δfable_pct / Δweekly_pct` — the whole question is whether the 0.5 coupling binds | ✅ (`accounts.json` `frontier.coupling`) |
| **Quality** | the frozen codex-probe corpus + blind 3-judge anchored scoring from `docs/research/fable51-effort-sweep-2026-09-10/` | ✅ — **reuse it, do not rebuild it** |

**Two controls the design must carry, or it measures nothing:**

1. **The Opus arm must be at `high`, not `max`.** The 2026-09-10 sweep's Opus cell was `@max`
   (12/25 recall) and **our actual default was never in the grid** — the lead already spotted this.
   An A/B that reproduces that omission reproduces its conclusion.
2. **Ambient load is a covariate, not a precondition.** This repo already paid for that lesson
   (two runs of one bench read 2.90× and 5.98× because their load ranges did not overlap). Record
   1-min runnable per cell and test `Spearman(load, outcome)`, never `max/min`.

**Over what period.** Two weekly reset cycles (~14 days). Rationale: the Fable meter resets on its
own clock (`fable_reset_h` measured today at 55-128 h, i.e. **not** aligned to the weekly reset), so
one cycle cannot separate "we have Fable headroom" from "we happened to sample a fresh sub-window".

**Decision rule, stated before the data:**

| Outcome | Rule |
|---|---|
| **ADOPT** (flip `lead_default`) | Fable arm ≥ Opus@high on the anchored corpus at every vote threshold **AND** `Δfable_pct / Δweekly_pct` < 2.0 across ≥2 accounts **AND** zero `fable-exhausted` route refusals in the window |
| **PARK** | quality ties but the meter ratio ≥ 2.0 — Fable is fine and the 0.5 coupling makes it unaffordable as a default; keep it opt-in |
| **REJECT** | Fable arm below Opus@high at any threshold, or any wave halted on `fable-exhausted` |
| **INVALID** | fewer than 2 full sub-window resets observed, or load-outcome correlation p<0.05 |

**Cost of the experiment vs the flip:** the A/B spends the *Fable* meter on a lane that is already
allowed to spend it, and touches one SSOT line. The flip touches ~8 SSOT lines, 4 zshrc lines, 2
copies of CLAUDE.md, 5 operator-owned settings files, ~10 skill/command docs, and changes the
meaning of 2 live safety mechanisms — with no shipped check able to detect that it was wrong.

---

## 6 · Trap summary (execution order matters)

1. **Do not run `claude-bump-models` in any form.** No pair exists; forcing `--from-to` rewrites 64
   `claude-opus-5` literals in a *second repo's* team-briefs and mutates its primary checkout.
2. **Do not write `opus_prior: claude-opus-5`.** That is the lateral-bump reflex; it arms
   `claude-lint-models` to convict the still-default model as stale across the fleet.
3. **Anchor `claude-bump-models:133` before ever adding `scripts/`/`bin/`/`hooks/` to the `update`
   list.** The `claude-fable-5|claude-fable-5-1` pair is armed *today*.
4. **Delete or re-scope the two Fable cost alarms** (`~/.zshrc:489`, `handoff-fire.sh:9284`) in the
   same diff — otherwise both fire on every session/fire and become noise.
5. **Reconcile `cc-route`'s slot→meter keying with `handoff-fire`'s model→meter keying** *before*
   the flip, or the default lane silently bills the wrong quota.
6. **Give `frontier_access.fallback` a floor that is not the thing it falls back from** — otherwise
   `cc-route:200-217`'s "designed Opus fallback" degrades Fable→Fable while saying "Opus".
7. **Decide what the frontier spawn cap means** when the default IS the frontier tier — today the
   answer is "nothing", silently.
8. **`~/.claude/CLAUDE.md` is a copy, not a symlink.** Editing `CLAUDE.global.md` alone leaves the
   live resident instructions asserting the old default.
9. **`~/.zshrc` is not in the repo.** Back it up by hand; `git revert` cannot reach it.
10. **`~/.claude-quaternary/settings.json:412 "model": "opus[1m]"`** pins one whole account to Opus
    and is in nobody's checklist. Also: `fable-5-1[1m]` is UNVERIFIED as a served variant.
11. **`skills/frontier-routing/SKILL.md:4,9` is already two flips stale** — treat the prose layer as
    a known-unreliable follower and sweep it explicitly, not by assuming the tools did it.

---

## 7 · Provenance ledger

| Claim | Status | Evidence |
|---|---|---|
| Skill has 3 cases, none is a default-tier flip | **measured-this-session** | `skills/model-upgrade/SKILL.md:44-58,141-224` read end to end |
| Unanchored sed at `claude-bump-models:133`, unanchored grep at :131 | **measured-this-session** | file read; line numbers verified |
| Lint is prefix-SAFE at `claude-lint-models.sh:82` | **measured-this-session** | `grep -qE "${literal}([^-0-9]\|$)"` |
| `claude-fable-5\|claude-fable-5-1` pair is armed today | **measured-this-session** | `claude-bump-models` dry-run stdout |
| Effective sweep target = 62 team-brief files; 64 `claude-opus-5`, 0 fable ids | **measured-this-session** | `find … -path "*/.claude/team-briefs/*" \| xargs grep -oh … \| sort \| uniq -c` |
| Non-`**` globs in model-classification.json are dead | **measured-this-session** | `claude-bump-models:97` path construction vs `roots[]` |
| 4 of 5 `settings.json` below the SSOT effort floor; zshrc launcher DRIFT | **measured-this-session** | `bash scripts/effort-parity-assert.sh` full output |
| Only `~/.claude-quaternary` carries a settings `model` key (`opus[1m]`) | **measured-this-session** | python json read of all 5 dirs |
| `~/.claude/model-config.yaml` is a symlink; `~/.claude/CLAUDE.md` is a real file | **measured-this-session** | `ls -la` + `install.sh:883-886` |
| CLAUDE.global.md and ~/.claude/CLAUDE.md § Frontier Tier Routing are byte-identical today | **measured-this-session** | `diff` of the extracted sections → IDENTICAL |
| `frontier.coupling: 0.5` = fable_cap/weekly_cap | **measured-this-session** | `accounts.json` `frontier` block |
| Live quota: weekly 94/40/6/100, fable 7/13/0/76 | **measured-this-session** | `bin/claude-accounts --json` |
| `cc-route` keys the meter on SLOT; `handoff-fire` keys it on MODEL | **measured-this-session** | `bin/cc-route:184-201` vs `scripts/handoff-fire.sh:9030` |
| frontier-spawn-gate exits 0 when `tool_input.model` is absent | **measured-this-session** | `hooks/frontier-spawn-gate.sh:23` |
| `skills/frontier-routing/SKILL.md` says "Opus 4.8 @ max" | **measured-this-session** | lines 4, 9 |
| `cc-route:276/333`, `cc-wave-plan:866/936` are selftest stubs, not live emitters | **measured-this-session** | read `selftest()` heredocs |
| Fable 5.1 cache reads $0.25/MTok vs Opus 5 $0.50/MTok | **quoted-from-vendor** (via SSOT comment `model-config.yaml:533-537`, sourced to Anthropic pricing page 2026-09-03) | no consumer reads it; comment only |
| Fable is included at ≤50% of Max limits from 2026-07-20 | **quoted-from-vendor** | `frontier_access.source: plan-usage`, `permanent: true` |
| cc-upgrade-gate GREEN on 2.1.260 × claude-fable-5-1 (13/0/1) | **measured-by-us**, 2026-09-03 | `model-config.yaml:71` |
| Fable 5.1 recall low6/med10/high10/xhigh9/max9 vs Opus5@max 12 (/25 strict-majority, 36 anchored defects) | **measured-by-us**, 2026-09-10 | `docs/research/fable51-effort-sweep-2026-09-10/README.md`; **Opus@high never tested** |
| `claude-fable-5-1[1m]` is a served variant | **assumed-unverified** | do not rely on it |
| Whether `fable_pct` would track `weekly_pct` 1:1 under a default flip | **assumed-unverified** | today's low fable_pct is a selection effect of opt-in use; this is the A/B's primary question |

### Limitations

- `claude-bump-models` full dry-run (target-file listing) did not complete inside this session's
  bound — the `find` over `~/.claude` is slow. I derived the effective target set independently by
  reproducing its glob logic; the **pair list is measured directly** from the tool's own stdout.
- I did not execute `cc-upgrade-gate`, `cc-route`, or any spawn. All routing claims are read from
  source, not observed at runtime.
- Read-only session: no file in the repo was modified.
