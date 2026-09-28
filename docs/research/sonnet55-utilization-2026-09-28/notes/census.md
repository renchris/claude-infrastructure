# Census: Sonnet consumers + launcher binary pins (Sonnet 5 → 5.5, CC 2.1.280 → 2.1.284)

Read-only census of `/Users/chrisren/Development/claude-infrastructure` @ `9eb533126` (main, clean), plus
`~/.zshrc`, `~/bin/claude-bump-models`, `~/.claude/model-routing-freewin-probe.md`, and the installed
binaries `~/.claude-280` / `~/.claude-284`. 2026-09-28. Nothing was edited. The simulations ran under a
throwaway `HOME=/tmp/sim-sonnet55-home`, using a COPY of model-config.yaml with `sonnet_latest: claude-sonnet-5-5`
and `sonnet_prior: claude-sonnet-5`.

## 0. Facts that decide the shape of the upgrade

| # | Fact | How known |
|---|---|---|
| F1 | **No role routes to Sonnet today.** `roles.*` has 13 keys. Twelve are Opus 5.5, Fable 5.1 or Haiku 4.5. The 13th, `roles.classifier: claude-sonnet-4-6`, is a descriptive mirror of Anthropic's hardcoded classifier and is never a spawn target. `workflow_synthesis_worker` left `claude-sonnet-5` on 2026-09-22. `versions.sonnet_latest` is read by **no executable** in bin/ scripts/ hooks/ lib/. Its only readers are `claude-bump-models` (pair builder) and two test fixtures, where it is a decoy neighbour. | measured: `python3 yaml.safe_load(model-config.yaml)` walk; `grep -rnE 'sonnet_(latest\|prior)'` |
| F2 | **The `sonnet` alias moves with the BINARY, not the SSOT.** 2.1.280 `sonnet:{default:"claude-sonnet-5",…}`. 2.1.284 `sonnet:{default:"claude-sonnet-5-5",…}`, but a second `sonnet:{default:"claude-sonnet-5",per_provider:{anthropic_aws…,gateway…}}` table also exists in the 2.1.284 binary. `claude-sonnet-5-5` appears 0× in 2.1.280 and 11× in 2.1.284. **Which table is live for a first-party Max session is NOT established. A live spawn has to confirm it** (transcript `message.model`). | measured: `strings -a ~/.claude-{280,284}/…/bin/claude.exe \| grep -oE 'sonnet:\{default:"[^"]+"…'` and `grep -c` |
| F3 | So every `model: sonnet` consumer (2 agents, 1 skill spawn) goes to Sonnet 5.5 **by itself** when a session moves to 2.1.284, with no SSOT edit. On 2.1.280 the same consumers get `claude-sonnet-5` already. That contradicts the SSOT prose "alias still resolves to 4.6" (model-config.yaml:785, :805; freewin-probe :43, :97, :142), which is stale. | measured (F2) + read |
| F4 | `claude-lint-models --all` under the simulated SSOT: **`✅ All UPDATE-classified files clean.` exit 0.** | measured: `HOME=/tmp/sim-sonnet55-home bash scripts/claude-lint-models.sh --all` |
| F5 | The launcher is on 2.1.280 (`~/.zshrc:496`). `~/.claude-284` is already installed and its package.json says 2.1.284. `cc-claude-bin --explain` resolves `.claude-280` through the "zshrc claude() _bin pin" rung. | measured |

## A. SONNET CONSUMERS

Class key: **EMITTER** writes or selects a model id (incl. an alias). **DETECTOR** tests or matches one. **DOC** is a current routing or price claim. **HISTORY** is a dated measurement or provenance line.
"Rewrite?" means: should a Sonnet 5 → 5.5 lateral bump change this literal? **Y** = yes, as part of the flip. **Y-manual** = yes, but by hand, not by a blind literal swap. **N** = keep as is. **VERIFY** = the change depends on a live test on 2.1.284.

### A1. SSOT: `model-config.yaml`

| path:line | literal | class | Rewrite? |
|---|---|---|---|
| model-config.yaml:127 | `sonnet_latest: claude-sonnet-5  # LATERAL 2026-06-30 (was claude-sonnet-4-6); 1M ctx, 128K out` | EMITTER (SSOT key) | **Y** → `claude-sonnet-5-5`. Rewrite the comment too; ctx/out must come from the 5.5 docs. |
| model-config.yaml:128 | `sonnet_prior: claude-sonnet-4-6` | EMITTER (arms lint + bump) | **Y** → `claude-sonnet-5`. This arms the lint for `claude-sonnet-5`; see §C. |
| model-config.yaml:772 | `claude-sonnet-5: [2, 10]` (pricing_per_mtok) | EMITTER (read by `bin/cc-token-ledger` load_prices, exact-key) | **N**. Keep it for prior-pinned cost math. **ADD** a `claude-sonnet-5-5: [in, out]` row. Without it, `cc-token-ledger` buckets 5.5 as *unpriced*: loud, not mispriced (exact match, `base_model()` strips only `[1m]` and `-YYYYMMDD`). |
| model-config.yaml:778 | `claude-sonnet-4-6: [3, 15]` | EMITTER (price row) | N |
| model-config.yaml:784-793 | "Sonnet 5 … NOT added yet … alias still resolves to 4.6 … add claude-sonnet-5 once …" | DOC (stale) | Y-manual. Rewrite to the 2.1.284 state after the live test. |
| model-config.yaml:799, :800, :802 | `firstParty/anthropicAws/non_firstParty_non_max: […, claude-sonnet-4-6]` | DETECTOR (decompiled list; nothing in-repo reads these three) | N. Only a verified binary change moves them. |
| model-config.yaml:801 (non_firstParty_max) | *(no Sonnet present)* | DETECTOR. Read by `hooks/agent-teams-enforce.sh:535`; a bare `sonnet` teammate is denied because no `claude-sonnet-*` is listed. | **VERIFY**. Add `claude-sonnet-5-5` only if the Sonnet 5.5 teammate/lead use is adopted AND `cc-upgrade-gate` check_03 passes on 2.1.284 × claude-sonnet-5-5 (the precedent set by opus-5-5 and fable-5-1). |
| model-config.yaml:805-808 | `classifier_model: claude-sonnet-4-6` + "alias still resolves to 4.6 … re-verify on the next CC bump" | DETECTOR/DOC (Anthropic-hardcoded fact) | **VERIFY** on 2.1.284 (decompile/strings). A model bump alone does not move it. |
| model-config.yaml:893 | "Sonnet 5 is NOT teammate-allowlisted → those two surfaces stay on research_worker" | DOC (current claim) | Y-manual. Make it model-neutral, or update after the allowlist decision. |
| model-config.yaml:894-900, :921-933 | T2 probe record, "Sonnet 5 record (2026-07-01 → 2026-09-22)", "Intro $2/$10 → std $3/$15 on 2026-08-31 (win holds at std)" | HISTORY | N. Note that :931-932 "std $3/$15" is contradicted by :772-777 (increase cancelled). It is a history line that asserts a refuted price. |
| model-config.yaml:901 | `workflow_synthesis_worker: claude-opus-5-5  # FLIPPED 2026-09-22 (was claude-sonnet-5)` | HISTORY (in comment) | N. A blind swap would falsify the provenance. |
| model-config.yaml:910-913 | "Opus 5.5 @xhigh beat Sonnet 5 @max 5-1 …" | HISTORY (measurement) | N. The settle run was not re-run against 5.5, so that is a re-probe question, not a rewrite. |
| model-config.yaml:1005 | `roles.classifier: claude-sonnet-4-6  # hardcoded by Anthropic` | DOC mirror of :808 | VERIFY (same as :808) |
| model-config.yaml:1043 | "(Fable 5 → Opus 4.8 → Sonnet 5 → Haiku 4.5)" | DOC (effort ladder prose; already stale on Opus) | Y-manual (whole ladder) |
| model-config.yaml:1329 | retirement floors "`claude-sonnet-5 2027-06-30` · `claude-sonnet-4-6 2027-02-17`" | DOC (dated) | N. Add a 5.5 floor if published. |
| model-config.yaml:1322 | `deprecations: claude-sonnet-4: "2026-06-15"` | DETECTOR (lint stale list) | N |
| model-config.yaml:13, :17, :262, :354, :599, :723 | changelog / binary strings table / `tier_3_15 (Sonnet 5)` / "Sonnet-5 precedent" | HISTORY | N |
| model-config.yaml `effort_defaults` | *(no sonnet key; opus55_* exist)* | GAP | Add `sonnet55_*` rungs only if a Sonnet 5.5 role is adopted |

### A2. Classification: `templates/model-classification.json` (= `~/.claude/model-classification.json`, symlink)

| path:line | literal | class | Rewrite? |
|---|---|---|---|
| templates/model-classification.json:27 | `".claude/agents/deep-research-sonnet.md"` in `review` | DETECTOR (path list; scripts ignore `review`) | N |
| :48, :50, :52 | rationale strings naming `sonnet-4-6`, `claude-sonnet-4-6`, "Sonnet 5 (2026-06-30) did not change … alias (still resolves to 4.6 at launch)" | HISTORY/DOC | N, although :50's alias clause is stale per F2 |
| :19-20 | `"Development/claude-infrastructure/README.md"`, `"Development/claude-infrastructure/agents/*.md"` in `update` | DETECTOR (sweep scope) | **Dead globs.** `roots` are absolute (`~/.claude`, reso, claude-infrastructure), so `find "$root/Development/…"` never matches. Neither `~/.claude/Development` nor `…/claude-infrastructure/Development` exists (measured `ls`). The bump and lint **never touch agents/*.md or README.md**. The same holds for the three `Development/reso-management-app/…` globs. |

### A3. Agents, commands, skills (live via `~/.claude/{agents,skills,commands}` symlinks)

| path:line | literal | class | Rewrite? |
|---|---|---|---|
| agents/deep-research-sonnet.md:4 | `model: sonnet` | EMITTER (alias; resolves per binary: F2) | N (alias). **It flips to 5.5 by itself on 2.1.284.** |
| agents/deep-research-sonnet.md:3 | description "benched: Sonnet measured no better than Opus and pricier per task …" | DOC (routing claim, measured on Sonnet 5) | Y-manual. It stays true only until a 5.5 re-probe says otherwise. |
| agents/deep-research-sonnet.md:12-24, :61-62, :138 | "You are … at Sonnet 5 tier", MALBO/X-MAS rationale, "When to use Sonnet (you)" | DOC (stale self-description) | **Y-manual** (:12 names the tier). Prose is invisible to the bump. |
| agents/research-decomposition-critic.md:4 | `model: sonnet` | EMITTER (alias) | N. It flips with the binary. It is a deliberate cheap critic (freewin-probe:78). |
| skills/frontier-campaign/SKILL.md:29 | "Sonnet agent (`model: sonnet`), ≤500-token verdict" | EMITTER (alias spawn instruction) | N (alias) |
| skills/research-subagents/SKILL.md:417-423 | "Opus 5.5 @xhigh … beat Sonnet 5 @max 5-1" | DOC+HISTORY | N (measurement). A 5.5 re-probe is owed. |
| skills/research-subagents/SKILL.md:424-431 | `agent(brief, {model: 'claude-sonnet-5', effort: 'max'})` under "*(Retired 2026-09-22.)*" | HISTORY (full-id literal) | **N.** The single-file lint flags it once prior=claude-sonnet-5 (measured: `stale refs: claude-fable-5 claude-sonnet-5`). The bump never reaches it (not UPDATE). |
| skills/research-subagents/SKILL.md:662-676 | "QUALITY-FIRST ROUTING OVERRIDE … Sonnet 5 broke that … Sonnet 5 re-enters … via probe" | DOC (current routing rule tied to a Sonnet 5 measurement) | Y-manual. Keep the measurement and re-state which Sonnet the rule applies to. |
| commands/research.md:89 | "Sonnet 5 @ max is ≤ Opus 4.8 quality … Sonnet 5 re-enters only via a probe-certified …" | DOC+HISTORY (it self-labels as deliberately measurement-tensed) | Y-manual (the "re-enters" clause only) |
| skills/model-upgrade/SKILL.md:76 | Lateral example "Sonnet 4.6 → 4.7" | DOC (stale example) | optional |
| skills/model-upgrade/SKILL.md:86, :127, :309, :379 | bump loop ref; SSOT table; `rg 'claude-(fable\|opus\|sonnet\|haiku)-[0-9]…'`; "Sonnet 5 measured ≤ Opus 4.8" as the example of a preserved measurement | DOC/DETECTOR | N |
| skills/cc-version-audit/SKILL.md:168, :177 | "2.1.197 default = Sonnet 5; bare spawns silent-demote" | HISTORY (release fact) / DOC | Y-manual if 2.1.284 changes the default model again (VERIFY) |
| skills/agent-teams/SKILL.md:43 | "`sonnet` silent-demotes to acceptEdits + breaks parallelism" | DOC (true while no sonnet is in non_firstParty_max) | VERIFY with the allowlist decision |
| CLAUDE.global.md:1080 (= ~/.claude/CLAUDE.md:1080, a separate real file) | names `agents/deep-research-sonnet.md` (omitClaudeMd example) | DOC (not routing) | N |
| commands/compact-memory.md:434 | `claude-sonnet` positive-control string | HISTORY | N |

### A4. Executables: bin/, scripts/, hooks/, lib/

| path:line | literal | class | Rewrite? |
|---|---|---|---|
| bin/claude-bump-models:65-69 (= ~/bin/claude-bump-models, a **regular-file copy**, identical today by `diff`; `command -v` resolves `~/.claude/bin/…` → repo symlink) | `for family in frontier opus sonnet haiku` → `.versions.${family}_prior/_latest` | EMITTER (sweep) | N. See §C. |
| scripts/claude-lint-models.sh:33-34, :82 | `*_prior` values + `deprecations` keys; `grep -qE "${literal}([^-0-9]\|\$)"` | DETECTOR | N. See §C. |
| bin/cc-token-ledger:61 | `CR_MULT = {"claude-fable-5-1": 0.025, "claude-mythos-5-1": 0.025, "claude-opus-5-5": 0.05}`, `CR_DEFAULT = 0.1` | EMITTER (cache-read price multiplier) | **Y-manual if Sonnet 5.5's cache-read ratio ≠ 0.1**. Otherwise 5.5 is silently priced at the default. |
| bin/cc-token-ledger:313-330 | `load_prices()` exact-key parse of `pricing_per_mtok` | DETECTOR | N (needs the A1:772 row added) |
| bin/cc-recover-safeguard:9, :116 | `FALLBACK_MODELS="${CC_RECOVER_FALLBACK_MODELS:-opus sonnet haiku}"` | EMITTER (alias) | N (alias follows the binary) |
| bin/claude-kimi:92, :309 | `ANTHROPIC_DEFAULT_SONNET_MODEL=$KIMI_MODEL` | EMITTER (alias override to Kimi) | N |
| bin/claude-kimi:255; tests/claude-kimi.bats:147-150 | `grep -E 'claude-(opus\|sonnet\|haiku\|fable)-[0-9]'` "no model id in routing code" | DETECTOR (structural guard) | N |
| hooks/agent-teams-enforce.sh:531-560 | allowlist gate. Full id must equal an entry; bare alias needs a `claude-<alias>-*` entry, so `sonnet` teammates are denied today | DETECTOR (SSOT-driven) | N. It follows A1 `non_firstParty_max` automatically. |
| hooks/agent-teams-enforce.sh:621 | `deep-research\|deep-research-sonnet\|Explore\|frontier-derivation` | DETECTOR (agent-type names) | N |
| hooks/lib/read-before-write-parity.sh:27-30 | `tengu_velvet_mallet_sonnet_4_6`, "`sonnet_5` … TRUE" | HISTORY (dated flag table); the bucket derivation is generic (`claude-sonnet-5-5` → `sonnet_5_5`; absent key ⇒ no-op by design) | N. A re-measure of the `sonnet_5_5` flag would be needed to know whether the shim enforces on 5.5. |
| bin/cc-route, bin/cc-wave-plan, bin/cc-quota-price, bin/claude-accounts, hooks/model-permission-decider.py, hooks/frontier-spawn-gate.sh | *(no sonnet reference)*. cc-route reads `roles.lead_default` + `frontier_access.model`; cc-wave-plan has Opus/Fable literals only (:860-866); cc-quota-price is model-agnostic (fits per model from transcripts); claude-accounts wire model = `claude-haiku-4-5-20251001` (:966); model-permission-decider MITL model = haiku (:129); frontier-spawn-gate is Fable-only (:52) | n/a | N. A Sonnet 5.5 role would need **new** routing code; none exists to rewrite. |
| scripts/limit-recover/lr-upgrade.sh:99-121 | pin target must equal `opus_latest` or the frontier model | DETECTOR | N |
| lib/cc-upgrade-gate/check05_launcher.sh:132 | expects `opus_latest` | DETECTOR (Opus-keyed) | N. The gate is parameterised (`scripts/cc-upgrade-gate.sh <bin> <model> <acct>`), so it can run × claude-sonnet-5-5 without edits. |

### A5. Tests / fixtures

| path:line | literal | class | Rewrite? |
|---|---|---|---|
| tests/lr-fire-resume-model-ssot.bats:52, :84, :98 | `sonnet_latest: claude-sonnet-5` (decoy neighbour of `opus_latest` in a synthetic versions block) | DETECTOR fixture | N (value-independent). The single-file lint flags it after the flip (measured). |
| tests/lr-upgrade.bats:487 | `--pin-target "$S" claude-sonnet-5` (an arbitrary non-SSOT id that must be REFUSED) | DETECTOR fixture | **N.** Still valid, since Sonnet is never an lr-upgrade target. Flagged by the single-file lint (measured). |
| tests/read-before-write-parity.bats:156, :272 | `tengu_velvet_mallet_sonnet_4_6`, `bucket_of claude-sonnet-4-6` = `sonnet_4_6` | DETECTOR fixture | N |
| tests/cc-recover-safeguard.bats:98-216; tests/lr-predicate.bats:138-144, :441; tests/fixtures/lr-predicate/red-proof.sh:53; tests/pre-session-validate.bats:40-47 | "Sonnet 4.5 safeguards", "You've hit your Sonnet limit", `{"model":"sonnet"}` | DETECTOR fixtures (message shapes) | N |
| tests/skill-listing-budget.bats:43; tests/agent-teams-lifecycle-advisory.bats:61, :95; tests/agents-omit-claudemd.bats:30, :73 | agent name `deep-research-sonnet` (+ a size budget of 885 at :73) | DETECTOR | N. If deep-research-sonnet.md is rewritten, re-check the :73 byte budget. |

### A6. Docs outside docs/research with CURRENT claims, plus the out-of-repo probe

| path:line | literal | class | Rewrite? |
|---|---|---|---|
| ~/.claude/model-routing-freewin-probe.md (a **real file, not a repo symlink**; 33 sonnet hits, measured by `grep -c`) :42-44, :88, :96-97, :141-151 | "the bare `sonnet` alias STILL resolves to 4.6 — always pin the full ID `claude-sonnet-5`" | DOC (stale per F2 on 2.1.280 and 2.1.284) | **Y-manual** |
| same :165, :387 | "Sonnet 5 intro $2/$10 ends 2026-08-31, then $3/$15" | DOC (refuted: A1:772) | Y-manual |
| same :328 | "Sonnet 5 is NOT allowlisted → ineligible" | DOC | VERIFY |
| same :3-35, :91-151, :342-381 | T1/T2/T9 probe records | HISTORY | N |
| docs/KIMI_METERED_INTEGRATION.md:81 | "equals Sonnet 5's headline rate ($3/$15)" | DOC (price comparison, already wrong) | Y-manual |
| docs/plans/HOOK_SURFACE_100P.md:696, :1300 | `PreModelSwitch:claude-sonnet-5 …`, `feed.sh claude-sonnet-5` | HISTORY (probe transcripts) | N. The single-file lint flags it after the flip (measured). |
| docs/plans/GROUND_UP_REBUILD_MAP.md:56; docs/plans/CONTEXT_ECONOMY_V2.md:226 | "refused at 170,616 tok on claude-sonnet-5" | HISTORY | N |
| docs/research/** | 460 matching lines (measured by `grep -rnE … \| awk` split: 460 research / 51 elsewhere) | HISTORY by classification | N (excluded per brief) |

## B. BINARY PINS (`\.claude-2[0-9][0-9]` and launcher-version literals)

"Resolver?": does it go through `bin/cc-claude-bin`, which reads `~/.zshrc`'s `_bin=` line? "Silent-280?": would it keep running 2.1.280 after the launcher moves to 2.1.284 without saying so?

| path:line | literal | Resolver? | Silent-280 after the move? |
|---|---|---|---|
| ~/.zshrc:496 | `local _bin="$HOME/.claude-280/node_modules/.bin/claude"` | **IS the SSOT** (cc-claude-bin rung 1, `cc-upgrade-gate` check05) | This line **is** the move. The cause of silent 280s is not this line but **live shells**: a recycle types into the same shell, so a pane stays on the binary it was exec'd with until a new shell opens (model-config.yaml § OPUS 5.5 STATUS, "fleet was split at the flip"). **YES for every live pane until it is recycled into a new shell.** |
| ~/.zshrc:424 | `binary ~/.claude-219/…` | comment | n/a |
| bin/cc-claude-bin:63, :72-84 | `_bin="\$HOME/\.claude-[0-9]+/…"` regex; rung 2 = numerically newest `~/.claude-NNN` | resolver itself | No. Caveat: when zshrc is unreadable (stripped HOME), rung 2 **already** picks `.claude-284` today, before the launcher moves. |
| **bin/cc-memory-extract:55** | `DEFAULT_CLAUDE = "/Users/chrisren/.claude-280/node_modules/.bin/claude"` (used at :521 unless `CC_MEMORY_EXTRACT_CLAUDE` is set) | **NO** | **YES: runs 2.1.280 silently, forever.** The only live-code hardcode of the current version. It runs haiku, so the model is unaffected; it is binary drift only. No launchd/bin caller was found (grep), so it is invoked by hand. |
| accounts.json:14 (= ~/.claude/accounts.json, symlink) | `"claude_bin": "~/.claude-220/node_modules/.bin/claude"` | fallback only; `claude-accounts:270 resolve_claude_bin()` tries the resolver first | No on the normal path. In a stripped env it runs **2.1.220** (already stale by two binaries). |
| **tests/mcp-no-inherit.bats:268** | `: "${CC_MCP_PROBE_BIN:=$HOME/.claude-220/node_modules/.bin/claude}"` (opt-in LIVE test) | **NO** | **YES** (already runs 2.1.220) |
| **tests/fixtures/teammate-probe/run-p1.sh:51** | `CLAUDE_BIN="${PROBE_CLAUDE_BIN:-$HOME/.claude-260/node_modules/.bin/claude}"` | **NO** | **YES** (already runs 2.1.260) |
| bin/reso-resume-one:154-167 | own resolver: highest `package.json` version across `~/.claude-*/` (`sort -V \| tail -1`) | **NO** (a rival resolver) | No, but it is **inverted**: it runs **2.1.284 today** while the launcher is on 2.1.280. |
| bin/claude-latest:227-394 | `~/.claude-versions/current` (stable track, 2.1.114) | separate track (cc-claude-bin rung 3, claude-kimi fallback) | n/a (intentionally pinned) |
| scripts/handoff-fire.sh:359-388 | `_resolve_eval_bin`: resolver, then newest `~/.claude-NNN` (no literal) | YES | No |
| scripts/limit-recover/lr-fire-resume.sh:381 | `BIN="$("$_LR_DIR/../../bin/cc-claude-bin")"` fail-closed | YES | No |
| bin/claude-kimi:_resolve_bin (~:110-125) | `CLAUDE_KIMI_CLAUDE_BIN` → resolver → claude-latest → PATH | YES | No |
| hooks/model-permission-decider.py:95-113 | `MITL_CLAUDE_BIN` → resolver | YES | No |
| scripts/mcp-modal-probe.py:26-47; scripts/mcp-modal-e2e-probe.py:13-35 | `PROBE_CLI` → resolver | YES | No |
| lib/cc-upgrade-gate/check05_launcher.sh:44-52 | derives `.claude-NNN` from the launcher body | YES (reads zshrc) | No |
| bin/cc-notify, bin/cc-lr, bin/cc-offload, bin/cc-suggest-filter, scripts/lib/cloud-create.sh, scripts/capacity-ramp.sh, scripts/autonomy-sweep.sh, scripts/limit-recover/lr-upgrade.sh, scripts/meter-experiment/{run,control}.sh, hooks/session-start.sh, scripts/{pipefail-sigpipe,unattended-path}-lint.sh | call `cc-claude-bin` (measured `grep -rl cc-claude-bin`) | YES | No |
| scripts/cc-upgrade-gate.sh:19 | usage example `~/.claude-219/…` | comment; the gate takes `<bin>` as argv | n/a |
| bin/cc-lr:1253 | `cl_short_bin` → `.claude-280`-style label | parser | n/a |
| bin/cc-eligible:209 | `.claude-219`, `.claude-220` in a classifier comment | comment | n/a |
| bin/cc-reaper:3238-3240 | `/x/.claude-220/…` selftest cells | fixture | n/a |
| comments: bin/cc-claude-bin:11, bin/claude-accounts:274-275, bin/claude-kimi:107, bin/cc-offload:87, scripts/handoff-fire.sh:355, :363, :392, scripts/limit-recover/lr-fire-resume.sh:379, scripts/lib/cloud-create.sh:116, scripts/capacity-ramp.sh:52, scripts/mcp-modal*-probe.py, hooks/model-permission-decider.py:97-98, hooks/session-start.sh:74, lib/cc-upgrade-gate/check05_launcher.sh:22, :44 | historical `.claude-183/219/220` drift notes | — | n/a |
| tests/*.bats (≈50 files; e.g. account-fact-derivation.bats 13 hits, cc-claude-bin.bats 12, lr-upgrade.bats 7), tests/fixtures/teammate-probe/captures/** | ps-line / synthetic-path fixtures `/x/.claude-220`, `/opt/cc/.claude-280`, `/opt/cc/.claude-290` | fixtures for process-shape parsers | n/a (not launch paths), except the two bolded rows above |
| model-config.yaml:103-107 | "launcher repointed to 2.1.280 (activation 45)" | DOC | Y-manual at the move (status prose) |

No launchd plist in `~/Library/LaunchAgents` names `.claude-2NN` (measured `grep -rn`).

## C. `claude-bump-models` / `claude-lint-models` on sonnet_prior=claude-sonnet-5, sonnet_latest=claude-sonnet-5-5

**Prefix hazard: handled.** Both tools anchor on the right: detection is `grep -qE "${OLD}([^-0-9]|$)"` (bump:137, lint:82), and the rewrite is `sed -e "s|${OLD}\([^-0-9]\)|${NEW}\1|g" -e "s|${OLD}$|${NEW}|g"` (bump:141). So `claude-sonnet-5-5` never matches `claude-sonnet-5`, because the next char is `-`, and a re-run on an already-bumped file cannot produce `claude-sonnet-5-5-5`. `[1m]`, `:`, `'`, backtick, space and EOL all still match the old id, which is correct. The bump's comment at :131-136 records this exact lesson from fable-5 → fable-5-1. The anchor has two residual edges, both harmless or theoretical: (a) a dated `claude-sonnet-5-YYYYMMDD` form would be *missed*, since `-` blocks it (no such id is in use); (b) the left side is unanchored, so `anthropic.claude-sonnet-5` would be rewritten too, which is semantically right.

What they would actually do:

1. **lint `--all`: clean, exit 0** (measured, F4). The UPDATE set carries no `claude-sonnet-5` literal. Reso team-briefs have 0 `claude-sonnet-5` and 0 `claude-opus-5` (measured by `grep -rlE` with the same anchor).
2. **lint `<file>`** (the pre-commit form, although no githook, launchd job or settings entry calls it; measured by `grep`) flags, after the flip: model-config.yaml, skills/research-subagents/SKILL.md, tests/lr-fire-resume-model-ssot.bats, tests/lr-upgrade.bats, docs/plans/HOOK_SURFACE_100P.md (measured). All are HISTORY or fixtures and **must not** be "fixed". model-config.yaml and research-subagents already fail today on other priors (measured under the current SSOT).
3. **bump pairs are ALL families, not just Sonnet.** Measured dry-run header under the sim SSOT: `claude-fable-5|claude-fable-5-1`, `claude-opus-5|claude-opus-5-5`, `claude-sonnet-5|claude-sonnet-5-5`. A bare `--apply` would also execute the Opus sweep that model-config.yaml § OPUS 5.5 records as **deliberately not run**. To scope it, use `--from-to claude-sonnet-5 claude-sonnet-5-5`.
4. **bump reach is narrow.** The effective UPDATE globs are only the `**/…` ones: team-briefs, and three memory files, two of which are also PRESERVE. The `Development/…` globs are dead (A2), so agents/*.md and README.md are never swept. The REVIEW files (model-config.yaml, research-subagents, research.md, both research agents) and every Sonnet mention in prose ("Sonnet 5 tier") are invisible to it by design. **Net: for this flip the bump is ~a no-op on literals. The real edits are all Y-manual rows in §A.**
5. **Dry-run result (measured: `HOME=/tmp/sim-sonnet55-home bash bin/claude-bump-models`): `=== 76 target file(s) ===` · `Dry-run complete. 0 rewrite(s) would apply.` · exit 0**, across all three pairs. It is slow: about 30 min wall, almost all of it `find` over `~/.claude` (measured by elapsed `ps` etime), so do not put it inside a foreground gate step.
6. Deploy drift: `~/bin/claude-bump-models` is a regular-file copy (identical today by `diff`). `command -v` resolves the `~/.claude/bin` symlink first, but the copy can rot.
