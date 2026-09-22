# L1 census — Opus 5 → Opus 5.5 lateral bump (READ-ONLY)

Repo: /Users/chrisren/Development/claude-infrastructure @ 13642295d (shared checkout, main, clean). Nothing edited.
Measured 2026-09-22 ~15:40 CDT. Work files in this dir: B-hits.txt (all 289 literal hits), bump-targets.txt / bump-hits.txt (claude-bump-models target enumeration, reproduced read-only with find+jq because the dry-run itself was classifier-denied).

## 0. State that changes how everything below reads

- **The launcher is already flipped.** `~/.zshrc:496` `_bin="$HOME/.claude-280/..."`, `:498`/`:502` `--model "${CLAUDE_NEXT_MODEL:-claude-opus-5-5}" --effort "$_eff"`, `:495` `_eff=${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}`. Done by `~/.claude/autonomy/pending-activation/45-opus55-cc280-activate.sh` (`.done` 15:06; zshrc mtime 14:59). New shells already run 2.1.280 + claude-opus-5-5 @ high.
- **The SSOT is not flipped.** `model-config.yaml:43` opus_latest=claude-opus-5, `:45` opus_staged=claude-opus-5-5, `:572` fallback, `:644` allowlist (no 5-5), `:659/:686/:708/:709/:710` roles all claude-opus-5. No `claude-opus-5-5` row in pricing_per_mtok (`:582-625`).
- `bin/cc-claude-bin --explain` → `~/.claude-280/node_modules/.bin/claude` (rung 1, zshrc `_bin` pin, `cc-claude-bin:58-67`). Every cc-claude-bin consumer already launches 2.1.280.
- ps census: 16 procs `260 claude-opus-5 high`, 2 `260 claude-fable-5-1 xhigh`, 2 `280 claude-opus-5-5 high` (wrapper+exe pairs). No 260 process started after 14:59.
- The ~/.zshrc header (`:419-446`) still documents 2.1.219 / claude-opus-5 — stale prose.

## A. Consumers of model-config.yaml

Legend — (i) value reaches a NEW process launched through the 2.1.280 resolver; (ii) value is handed by an ALREADY-RUNNING session to its own binary (a 2.1.260 session can receive claude-opus-5-5 and 400); (ii-adv) value is printed into a running session's context as advice, so the model may copy it into a spawn; (iii) accounting/detection/pricing/lint/gate; (iv) docs.

### Executable consumers

| Consumer | Lines | Keys read | Destination / type |
|---|---|---|---|
| scripts/handoff-fire.sh | :392 MODEL_CONFIG; :9485-9490 `_ssot_scalar`; :9492 fable→frontier_access.model; **:9493 opus→versions.opus_latest** (fallback literal claude-opus-5); :10480-10491 appended as `--model $MODEL`; :10139-10145 frontier_access.active warn | opus_latest, frontier_access.model/.active | **Non-recycle fire (:11001/:11152/:11154/:11164)**: typed into a NEW pane → fresh zsh sources ~/.zshrc → claude() 280 → **(i)**. **`--recycle` (:10998/:11001)**: typed into the SAME pane's existing shell, whose inline claude() body predates the 14:59 edit → `_bin=~/.claude-260` → **(ii)** whenever the caller passes `--model opus` (or any 5-5 id). With no `--model`, MODEL stays "" (:472) and the old body defaults to claude-opus-5 → safe. Mechanism-inferred (zshrc:410-412 states old panes keep the old body); no post-edit recycle sample exists to measure. NB 45-activate.sh:57-59 claims panes move off 260 "until they are recycled" — the recycle mechanism contradicts that. Probe binary `BIN` (:351-381) via cc-claude-bin → 280, haiku probe → (iii). Stale detector :10486 `!= claude-opus-4-8` (not the launcher default any more; harmless: appends). |
| bin/cc-route | :40 path; :108-117 ssot_model; :127-136 ssot_effort; :178 roles.lead_default; :186 effort_defaults.default; :197 frontier_access.model; :211-212 verify_judge/default | roles.lead_default, frontier_access.model, effort_defaults.default, .verify_judge | Emits JSON plan `{model, lead_effort}` (:163-170). Executable consumer is cc-wave-plan → **(i)**. A session that runs `cc-route` by hand and pins `.model` into Agent() → (ii-adv). |
| bin/cc-wave-plan | :604-611 resolve_lead_model; :613-641 resolve_slot; **:760** `handoff-fire.sh ... --cwd ... --model ${model} --effort ${eff}` | via cc-route | Executed by bin/cc-dispatch (:2583, :2735) as a `--cwd` (non-recycle) fire → new pane → **(i)**. Straddle fallback effort hardcoded max/xhigh (:630). |
| hooks/agent-teams-enforce.sh | :511-551 (yq :524; fallback literal claude-opus-4-8 :525; exact-id match :530-533; alias family match :534-538) | auto_mode_allowlist.non_firstParty_max | **This is the hook that enforces the auto-mode allowlist on spawns** — teammate spawns (`name`/`team_name`) that carry `model`. Gate = (iii), but it guards type-(ii) traffic: a teammate pane is launched by the lead with the LEAD's binary. If 5-5 is added to the allowlist, a 2.1.260 lead pinning `model: claude-opus-5-5` passes the hook and 400s at spawn. If roles flip but the allowlist does not, the hook DENIES claude-opus-5-5 even for 2.1.280 leads. Alias `opus` passes whenever any `claude-opus-*` is listed (:534-538) and resolves per binary → safe on both. |
| hooks/frontier-spawn-gate.sh | :36-39 CFG/block; :40 fmodel; :111-114 active/end/fallback; :117 cap (frontier_discovery_budget) ; :138, :149, :151 refusal texts | frontier_access.model/.active/.end/.fallback, max_fable_spawns_per_session, reserve_dates | Gate (iii). Refusal text → **(ii-adv)**: :138 (cap reached — LIVE path) hardcodes `--model claude-opus-5`; :149 `--model ${fallback:-claude-opus-5}` and :151 `→ ${fallback:-claude-opus-4-8}` fire only on a closed window (dormant: `permanent: true`, end 2099). Flipping `fallback` to 5-5 would tell a 260 session to fire/spawn an id its binary rejects (for Agent spawns) — dormant. tests/frontier-spawn-gate.bats:152 pins the `--model claude-opus-5` text. |
| hooks/frontier-status.sh | :12-21, :35 | frontier_access.active/.end/.model, **roles.lead_default** | SessionStart line `default=${lead}` printed into EVERY new session's context (window is permanently open) → **(ii-adv)** once lead_default = 5-5. Registered ~/.claude/settings.json:1211. |
| scripts/limit-recover/lr-fire-resume.sh | :104-116 lr_resolve_opus_model (versions-block-scoped); :290 default `effort="max"`; :301 fable acct → claude-fable-5-1/high (literal); :312-318; :365 BIN=cc-claude-bin | versions.opus_latest | Resume spawned via expect with `--model`/`--effort` on cc-claude-bin → 280 → **(i)**. |
| scripts/limit-recover/lr-handoff.sh | :24, :1132-1133 (comments) | none (delegates) | Passes `--resume-launcher` to handoff-fire (:1003 per handoff-fire:9659-9661) → lr-fire-resume → (i). |
| bin/reso-resume-one | :85; :171-178 resolve_model (unscoped `sed ... opus_latest` head -1); :150-168 binary = newest `~/.claude-NNN` by `sort -V`; :392 effort `${CC_RESUME_EFFORT:-high}` | versions.opus_latest | → 280 → **(i)**. |
| lib/cc-upgrade-gate/check05_launcher.sh | :130-135 read; :142-145 compare | versions.opus_latest, effort_defaults.default | (iii). **Prefix hazard in the detector:** `case "$argv_main" in *"--model $_g5_want_model"*)` (:142) is a substring glob, so want=claude-opus-5 matches the launcher's `--model claude-opus-5-5` — it passes TODAY while SSOT and launcher disagree. PASS text :189 hardcodes "claude-opus-5". |
| scripts/effort-parity-assert.sh | :29-49 SSOT resolution; :52-63 ssot_val; :72 settings_floor (fallback xhigh); :73 default (fallback max) | effort_defaults.settings_floor, .default | (iii), read-only. Live run: DRIFT (see D). |
| scripts/claude-lint-models.sh | :17; :33 `*_prior` values; :34 deprecations keys; :40-42 frontier_access.active/.end/.model; :82 word-boundary grep | versions.*_prior, deprecations, frontier_access | (iii). opus_staged invisible. |
| bin/claude-bump-models | :18; :65-71 pairs from versions.{frontier,opus,sonnet,haiku}_{prior,latest} | versions.*_prior/_latest | Rewrites files (see C). Its only live targets are reso team-brief manifests whose `model:` lines are teammate pins → downstream **(ii)**. |
| bin/claude-accounts | :9, :515-523, :5320 | frontier_access.active/.end | (iii) display/routing window. |
| install.sh | :597-602 | file (link) | (iii). |
| scripts/deploy-parity-assert.sh :422-925 · scripts/deploy-link-parity.sh :689, :750 | file presence/link | (iii). |
| scripts/backlog-consolidation/group.py | :210 | name regex | (iii). |
| scripts/route-safety-gate.sh :10, :43 · scripts/set-teammate-effort.sh :24 · bin/cc-premise :1488 · migrations/0029 :34 | comments/todo | (iv). set-teammate-effort reads NO SSOT key. |

### Keys with NO executable reader (prose-only today)
opus_staged, opus_prior (only via lint/bump `*_prior`), roles.default_teammate / teammate_frontier / teammate_mechanical / teammate_research / research_worker / workflow_synthesis_worker / research_retrieval / research_adversarial / workflow_judge / eval_judge / classifier, pricing_per_mtok (no code consumer; skills/model-upgrade + docs/research only), classifier_model, auto_mode_allowlist.{firstParty,anthropicAws,non_firstParty_non_max}, effort_defaults.{mundane,frontier,fable_*,fable51_*,opus5_*}. frontier_access.fallback is read only by frontier-spawn-gate's refusal text.

### Prose consumers (iv) that tell a model to copy an SSOT id into a spawn (latent ii-adv)
commands/handoff.md:385-396 (opus_latest @ high — but handoff-fire omits `--model` by default, so harmless unless the model passes it) · commands/research.md:85 (frontier_access.fallback) · skills/research-subagents/SKILL.md:563-568 (fallback), :407 (`agent(brief,{model:'claude-sonnet-5',effort:'max'})`) · skills/model-upgrade/SKILL.md:181-237 · skills/agent-teams/SKILL.md:211 (effort) · skills/frontier-routing/SKILL.md:9-17 · skills/frontier-hole/SKILL.md:8-9 · skills/frontier-run/SKILL.md:15-28 · skills/frontier-campaign/SKILL.md:44-51 · skills/resume-sessions/{SKILL.md:286-301,REFERENCE.md:178-216} · commands/accounts.md:127 · CLAUDE.global.md:334, :410-413.
Agent frontmatter uses ALIASES only (safe on both binaries): agents/deep-research.md `model: opus`, frontier-derivation.md `opus`, deep-research-sonnet.md `sonnet`, research-decomposition-critic.md `sonnet`; no `effort:` field. ~/.claude/workflows/{freewin-probe-t1-t2,pyramid-fans}.mjs: aliases + explicit effort.

## B. Literal `claude-opus-5([^-0-9]|$)` census

Scope: bin scripts hooks lib agents commands skills tests migrations docs/activation CLAUDE.global.md .claude + ~/.zshrc. **289 lines** (213 in tests/, 76 elsewhere; 0 in agents/, commands/, migrations/, .claude/).

| Class | Count |
|---|---|
| EMITTER | 8 |
| DETECTOR | 2 |
| FIXTURE | 217 (213 tests/ + 4 embedded selftest data) |
| DOC-CURRENT | 9 |
| DOC-HISTORICAL | 53 |

**EMITTER (full list)**
1. scripts/handoff-fire.sh:9493 — `MODEL="${MODEL:-claude-opus-5}"` fallback when the SSOT read is empty (`--model opus`).
2. hooks/frontier-spawn-gate.sh:138 — cap-reached refusal tells the session `--model claude-opus-5` (live path).
3. hooks/frontier-spawn-gate.sh:149 — `--model ${fallback:-claude-opus-5}` (closed-window only; dormant).
4. scripts/meter-experiment/run.sh:65 — `--model claude-opus-5` on `$BIN` (= cc-claude-bin, :25 → 280).
5. scripts/meter-experiment/run.sh:72 — same, `--resume`.
6. scripts/meter-experiment/control.sh:46 — same (BIN :18).
7. scripts/limit-recover/lr-fire-resume.sh:316 — error hint `--model claude-opus-5` (advisory).
8. bin/reso-resume-one:389 — override hint `CC_RESUME_MODEL=claude-opus-5` (advisory).

**DETECTOR (full list)**
1. skills/model-upgrade/SKILL.md:20 — `strings ... | grep -c` positive control.
2. skills/model-upgrade/SKILL.md:272 — same control.
(No executable code compares against the literal. The live detector hazards are SSOT-keyed: check05_launcher.sh:142 substring glob — see A.)

**FIXTURE per file** — bin/cc-quota-price:667,669,732 (3) · scripts/limit-recover/lr_predicate.py:606 (1) · tests/read-before-write-parity.bats 27 · tests/cc-upgrade-gate.bats 11 · tests/lr-fleet.bats 9 · tests/fixtures/codex-probe/runs/index.json 9 · tests/fixtures/teammate-probe/captures/p1-run2/agents.{survivors,spawned,plus30,mine} 8 each, agents.before 4, lead-wrapper.sh.txt 1 · …/p1-run1/agents.{survivors,spawned,plus30,mine} 4 each, lead-wrapper.sh.txt 1 · …/p2/agents.{spawned,mine} 1 each · tests/fixtures/teammate-probe/run-p1.sh 1 · tests/deploy-parity.bats 8 · tests/lr-lib.bats 7 · tests/lr-fire-resume-model-ssot.bats 7 · tests/lr-audit-nonlimit.bats 7 · tests/frontier-spawn-gate.bats 6 · tests/recover-inject.bats 4 · tests/lr-predicate.bats 4 · tests/cc-lr.bats 4 · tests/{wake-floor,statusline-identity,lr-resume-tombstone-guard,lr-handoff-launcher-quoting,ctx-audit,cc-spawn-verify,cc-authstore-probe}.bats 3 each · tests/{worker-claim-gate,operator-surface-scope,lr-ingest-verify,handoff-orphaned-assignee,cc-reconcile,cc-quota-price,capacity-alarm}.bats 2 each · tests/{subagent-stop-r1,statusline-telemetry-path,session-register-reclaim,session-busy,reso-resume-one,pkill-scope,mailbox-wake-arm,lr-resume-answer-width,lr-reset-poller-inplace,handoff-selfclose-transplanted-source,cc-teardown-assignee-adopt,cc-reaper,cc-queue,cc-husk-sweep,cc-claude-bin}.bats 1 each · tests/fixtures/lr-2026-09-19/build.sh 1 · tests/fixtures/codex-probe/runs/{README.md,cp-06__D.md} 1 each. All SSOT-reading tests checked use hermetic temp configs (LR_MODEL_CONFIG, FRONTIER_GATE_CFG, CC_PARITY_REPO, CC_RESUME_MODEL); none reads the live SSOT. Coupled pin: tests/frontier-spawn-gate.bats:152 asserts the `--model claude-opus-5` refusal text.

**DOC-CURRENT per file (9)** — CLAUDE.global.md:334 (says the launcher passes `--model claude-opus-5`; now false; same line in the separate real file ~/.claude/CLAUDE.md) · ~/.zshrc:425, :426 (launcher header: binary 219 / model claude-opus-5 — both stale) · lib/cc-upgrade-gate/check05_launcher.sh:12, :189 (expectation doc + PASS string) · lib/cc-upgrade-gate/common.sh:14 (example) · scripts/cc-upgrade-gate.sh:19 (usage example) · skills/cc-upgrade-gate/SKILL.md:42 (usage example) · skills/model-upgrade/SKILL.md:26.

**DOC-HISTORICAL per file (53)** — docs/activation/pending-activation/10-opus5-activate.sh 35 · …/28-cc-220-advance-activate.sh 2 (:23, :26) · …/29-launcher-consolidation-activate.sh 1 (:15) · hooks/lib/read-before-write-parity.sh 3 (:37, :102, :111 — mapping examples/provenance) · bin/reso-resume-one 2 (:20, :22) · scripts/limit-recover/lr-fire-resume.sh 2 (:94, :363) · bin/cc-claude-bin:13 · ~/.zshrc:437 · hooks/mailbox-drain.sh:25 · lib/cc-upgrade-gate/check01_binary.sh:6 · lib/cc-upgrade-gate/check05_launcher.sh:123 · scripts/handoff-fire.sh:9480 · scripts/limit-recover/lr-handoff.sh:213 · skills/cc-upgrade-gate/SKILL.md:64.

Also in the SSOT itself (not in scope list, for the flip author): value lines `model-config.yaml:43, :572, :589 (pricing key), :644, :659, :686, :708, :709, :710`.

## C. claude-bump-models

- `~/bin/claude-bump-models` is a real file byte-identical to `bin/claude-bump-models` (diff = SAME); `~/.claude/bin/claude-bump-models` is a symlink into the shared checkout.
- **Anchoring — SAFE against the prefix hazard.** Detector `bin/claude-bump-models:137` `grep -qE "${OLD}([^-0-9]|$)"`; rewrite `:141`
  `sed -i.bump-bak -e "s|${OLD}\([^-0-9]\)|${NEW}\1|g" -e "s|${OLD}$|${NEW}|g" "$file"`.
  With OLD=claude-opus-5 the character after the prefix in `claude-opus-5-5` is `-`, which is excluded, so an existing claude-opus-5-5 is never touched → no `claude-opus-5-5-5`, and a re-run is idempotent. Comment :131-136 records this was added for fable-5 → fable-5-1. Leading edge unanchored (irrelevant here). It WILL rewrite `claude-opus-5[1m]` → `claude-opus-5-5[1m]` and prose `claude-opus-5.`.
- **Pairs are built only from `*_prior`/`*_latest`** (:65-71). The opus pair claude-opus-5→claude-opus-5-5 exists only after opus_prior=claude-opus-5 AND opus_latest=claude-opus-5-5; today it is claude-opus-4-8→claude-opus-5. `--apply` also re-applies claude-fable-5→claude-fable-5-1 and claude-sonnet-4-6→claude-sonnet-5. opus_staged is ignored.
- **Targets** (`templates/model-classification.json`, symlinked as ~/.claude/model-classification.json): roots :4-8 = ~/.claude, ~/Development/reso-management-app, ~/Development/claude-infrastructure; update globs :9-21; preserve :31-45 subtracted. Effective set = **76 files, all `~/Development/reso-management-app/.claude/team-briefs/**`**; 42 carry `claude-opus-5` (64 lines), mostly teammate pins such as `exhaust/manifest.yaml:14 model: claude-opus-5`. The relative globs (`Development/reso-management-app/docs/plans/**/*.md`, `Development/claude-infrastructure/README.md`, `Development/claude-infrastructure/agents/*.md`) are DEAD: the script joins them as `$root/$glob` (:97), so they resolve to paths like `…/claude-infrastructure/Development/claude-infrastructure/README.md`. Every `~/.claude` update match (MEMORY.md, auto-mode-setup.md, feedback-agent-team-models.md) is also in preserve. `review` (:22-30, which lists model-config.yaml) is never read by the script.
- **In-place edits:** yes, `sed -i` straight into the root checkouts, with no worktree and no branch. In practice it does NOT touch the claude-infrastructure checkout; it edits the **reso main checkout** (detached HEAD, `## HEAD (no branch)`). `find -type f` skips symlinks, so it cannot replace a ~/.claude symlink with a real file. Rewriting those team-brief pins to claude-opus-5-5 makes any 2.1.260 reso lead that spawns from them 400 → downstream (ii).
- The dry-run could not be executed here (auto-mode classifier denied it as "Modify Shared Resources"); the target set above was reproduced with the script's own find/jq logic.
- Precedent hazard: re-running `10-opus5-activate.sh` today would hit the `in`-substring check at :161/:164 on `  opus_staged: claude-opus-5-5` and write `""-5`; its self-assert (:189-201) catches that and restores the backup (:204-207).

## D. Effort surfaces

| Surface | How effort is set | Opus 5.5 with nothing passed |
|---|---|---|
| (1) Shell-launched lead | ~/.zshrc:495 `_eff=${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}` → `--effort "$_eff"` :498/:502 (last-wins over user args). Legacy claude-prev :173/:175 `${CLAUDE_DEFAULT_EFFORT:-max}` (2.1.114, cannot run 5.5). No SSOT read. | **high** (explicit flag). |
| (2) Fired session | handoff-fire appends `--effort` only when given (:10413); else the typed launcher injects zshrc high. No SSOT key read (help text :56-62). cc-wave-plan:760 always passes `--effort` from cc-route: lead=effort_defaults.default (cc-route:186), transcription=hardcoded high, adversarial=verify_judge (:211), judgment-dense fallback=default (:212), straddle=max/xhigh hardcoded (cc-wave-plan:630). lr-fire-resume default `effort="max"` (:290; fable acct high :301) → explicit. reso-resume-one `${CC_RESUME_EFFORT:-high}` (:392). | **high** (launcher) / explicit everywhere; no path relies on the API default. |
| (3) Teammate pane | set-teammate-effort.sh:6-13 says (verified 2.1.170 only) the pane argv carries no `--effort` and CLAUDE_CODE_EFFORT_LEVEL is not forwarded, so effort = worktree `.claude/settings.local.json` effortLevel (written :41-51) else user settings.json effortLevel. **Live effortLevel:** ~/.claude=medium, ~/.claude-next=low, ~/.claude-secondary=high, ~/.claude-tertiary=medium, ~/.claude-quaternary=low. effort-parity-assert (run now) → DRIFT: 4/5 BELOW floor high. The pane's binary is the lead's binary. | **Below high either way.** If 2.1.280 ignores saved/settings effort for new models → API default **medium**. If it honours settings → low/medium on 4 of 5 accounts. Not measured on 280: cc-upgrade-gate #04 only checks that `--effort` flags are accepted on a headless call, and #07 checks modelUsage, not effort. |
| (4) In-process subagent | Inherits the lead's live effort (GH #25591; set-teammate-effort.sh:15-19; SSOT :711-713). No `effort:` in agents/*.md frontmatter. | high if inheritance still holds on 280; medium if the subagent resolves the per-model default. Unmeasured. |
| (5) Dynamic Workflow agent() | Per-call `effort` option (e.g. ~/.claude/workflows/freewin-probe-t1-t2.mjs:131/146/210; SSOT :720-724 `effort:'max'`). | Explicit → honoured (#04/#08 GREEN on 280). Omitted → unknown (inherit vs model default medium). Unmeasured. |

**effort_defaults keys READ by code:** `default` (cc-route:186, :212; check05_launcher.sh:133-134; effort-parity-assert.sh:73), `verify_judge` (cc-route:211), `settings_floor` (effort-parity-assert.sh:72). **Prose-only:** mundane, frontier, fable_default/capability_sensitive/routine, fable51_default/capability_sensitive/routine/cheap, opus5_default/capability_sensitive/coding_agentic/routine. There are no opus55_* keys. Stale code fallbacks: effort-parity-assert.sh:72-73 (xhigh / max).
The operator's two claims (5.5 API default medium; 2.1.280 does not apply a saved /effort to new models) come from the operator's materials and model-config.yaml:62-70. There is no CHANGELOG in ~/.claude-280/node_modules/@anthropic-ai/claude-code/, so they were not re-verified here.

## E. Activation precedents

**10-opus5-activate.sh (precedent, done 2026-07-25; repo copy docs/activation/pending-activation/10-opus5-activate.sh)**
- Preflight (:70-121): SSOT/bump/lint present; 2.1.219 version; SPAWN_DEPTH guard in both launchers; `LIVE_TEST_PASSED=1` operator attestation (:104-109); modelUsage smoke (:112-121). CONFIRM gate :124-128.
- Backup SSOT to ~/.claude/backups/opus5-activate-<ts>/ (:130-131).
- Phase A edit (:135-202, python): key-anchored `(prefix, old, new)` list (:141-151) covering opus_latest, opus_prior, opus_staged→`""`, `  fallback:` (first 2-space match = frontier_access.fallback :572), lead_default, default_teammate, teammate_mechanical, teammate_research, research_worker. Edits only the pre-`#` half (:163-164). Idempotency is a substring `new in head` check (:158); drift refusal `old not in head` (:161).
- Allowlist: adds claude-opus-5 ALONGSIDE 4-8 by string-splicing `[claude-opus-4-8, ` (:167-178).
- Self-assert on the written artifact (:182-201): exact values for all 9 keys + allowlist membership.
- Rollback: python rc≠0 → restore SSOT backup (:203-208). Then `claude-bump-models --apply` (:213) and `claude-lint-models --all` (:217); lint red → restore SSOT only and print manual `git checkout` for downstream repos (:220-225). Phase B (zshrc, REPOINT_NEXT) :228-262. Printed rollback :282-286.
- Porting caveat: `in`/`replace(old,new,1)` is prefix-unsafe when old=claude-opus-5 (see C); the idempotency check runs first so the 5→5-5 keys are safe, but any key whose current value is already 5-5 and whose `new` differs trips the substring match.

**45-opus55-cc280-activate.sh (live; .done 2026-09-22 15:06)**
- Deliberately makes **no SSOT edit** (:41-45): the SSOT is a symlink into the shared checkout, so that half must go through worktree + /ship + deploy-live. Order is binary-first (:47-49).
- It edits ~/.zshrc only. Preflight (:87-111): ~/.claude-280 is exactly 2.1.280; the rollback floor ~/.claude-260 exists; smoke passes with modelUsage carrying claude-opus-5-5.
- Anchors (:113-123) are full literal strings: `local _bin="$HOME/.claude-260/node_modules/.bin/claude"` exactly 1× and `--model "${CLAUDE_NEXT_MODEL:-claude-opus-5}"` exactly 2×. The closing `}"` makes them prefix-safe. Already-activated → exit 0 (:119-121). CONFIRM gate :126.
- Backup → ~/.claude/autonomy/backups/opus55-cc280-<ts>/zshrc (:128-130). The python edit (:132-157) asserts the artifact: new counts 1/2, old counts 0, and the SPAWN_DEPTH=1 export still present.
- Restores the backup on python failure (:158-161) or on `zsh -n` failure (:163-169). `--undo` restores the newest backup (:74-82).
- Its effort claim (:51-55) covers only the lead launcher and effort_defaults.default. It does not cover teammate panes or subagents (see D).
