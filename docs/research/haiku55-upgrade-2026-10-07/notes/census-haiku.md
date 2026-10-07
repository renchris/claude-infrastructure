# Fleet census: every place Claude Haiku 4.5 is named (2026-10-07)

Worker: read-only census for the Haiku 4.5 -> Haiku 5.5 flip. Tree: `/Users/chrisren/Development/.worktrees/wt-feat-haiku55-cc-upgrade`
at `a037c0bd9`, plus the live `~/.zshrc` and `~/.claude*/settings.json` (five files). Nothing was edited
except this file. `claude-bump-models --apply` was not run.

Method (all counts below are measured with the named command unless marked estimated):

- `rg -n -i 'haiku'` over `bin scripts hooks lib agents commands skills tests config settings-templates
  CLAUDE.global.md CLAUDE.global.slim.md docs/plans model-config.yaml` (node_modules excluded):
  **153 matching lines in 48 files** (`rg -c -i haiku ... | awk` sum). Of those, 27 files carry a versioned
  form (`haiku-4-5`, `Haiku 4.5`, `claude-haiku`, `haiku_4_5`).
- `rg -n -i haiku ~/.zshrc`: **0 hits**. `~/.claude*/settings.json` (5 files): **0 hits**; `jq '{model,
  effortLevel,modelSettings}'` gives `model: null`, `effortLevel: "high"`,
  `modelSettings: {"claude-opus-5-5": {"effortLevel": "high"}}` in all five.
- `CLAUDE.global.md`, `CLAUDE.global.slim.md`, `config/`, `settings-templates/`, `lib/`: **0 hits**.
- Binary registration (measured, `bin/cc-model-registered <id> --bin <path>`):
  2.1.284 `claude-haiku-5-5` **absent** (count 0, control claude-opus-5 86) / `claude-haiku-4-5` present (32);
  2.1.293 `claude-haiku-5-5` **present** (count 21, control 85) / `claude-haiku-4-5` present (36).
  So on the live pin (2.1.284) this is a STAGED release by model.md P1.

Classes: DETECTOR / EMITTER / SELFTEST-ASSERTION / PRICING-OR-TABLE / ROUTING-PROSE / HISTORICAL / ALIAS.
"Action" = what to do in the flip diff. "none" rows are listed so the next reader does not re-derive them.

## 1. Classified table

### 1a. EMITTERS (keep launching Haiku 4.5 after the SSOT says 5.5)

None of these is reachable by the sweep: none is in `model-classification.json`'s `update` list, and five of
the seven use the DATED id, which the word-boundary regex deliberately does not match.

| # | file:line | Text | Action at flip |
|---|---|---|---|
| E1 | `scripts/handoff-fire.sh:13816` | `local dir out probe_model="claude-haiku-4-5"` (the `--probe` account liveness probe; run as `"$BIN" -p ... --model "$probe_model" --max-turns 1` at :13855) | **Change.** Highest-impact emitter: once Haiku 4.5 retires (floor 2026-10-15) every non-Fable `--probe` fails as `model-unavailable` on all accounts and a routable wave halts. Prefer the alias `haiku` (resolved by whichever binary `$BIN` is) or read `versions.haiku_latest`. |
| E2 | `scripts/handoff-fire.sh:17071` | `pm="claude-haiku-4-5"; [ "$FABLE_EFFECTIVE" = 1 ] && pm="$MODEL"` (dry-run line that reports what E1 would probe) | **Change with E1**, or the dry-run reports a different model than the probe runs. |
| E3 | `bin/claude-accounts:1255` | `WIRE_MODEL = os.environ.get("CC_ACCOUNTS_WIRE_MODEL", "claude-haiku-4-5-20251001")` (raw `/v1/messages` call, `max_tokens: 1`, to read rate-limit headers; no binary involved) | **Change.** Raw API: the alias is not resolved by a binary here, so it needs a real id. The dated id for Haiku 5.5 was not determined in this census (see section 6). After retirement the call returns an error; the code reads headers off errors too, so whether it degrades or misreads was not tested. |
| E4 | `hooks/model-permission-decider.py:129` | `MODEL = os.environ.get("MITL_MODEL", "claude-haiku-4-5-20251001")` (PreToolUse permission consult, `claude -p ... --model MODEL` via `cc-claude-bin`) | **Change.** A hook on the tool path; a dead model turns every consult into `ERROR`. Runs on the launcher pin, so a full 5.5 id needs 2.1.293 first; the alias `haiku` is safe on either. |
| E5 | `bin/cc-memory-extract:54` | `MODEL = "claude-haiku-4-5-20251001"` (used at :378 `--model`, and written into each candidate record at :431 and :606) | **Change**, together with S1 below (the test pins the same string). |
| E6 | `scripts/headless-precondition-probe.sh:26` | `MODEL="${CC_HEADLESS_PROBE_MODEL:-claude-haiku-4-5-20251001}"` | **Change** (alias `haiku` works: it is passed to `"$CLAUDE_BIN" -p --model`). |
| E7 | `tests/rig/lr-recon-canary.sh:36` | `MODEL="${LR_CANARY_MODEL:-claude-haiku-4-5-20251001}"` (launches a real session at :111) | **Change** (alias works). Rig, not production. |
| E8 | `model-config.yaml:140` | `haiku_latest: claude-haiku-4-5            # retires NOT SOONER than 2026-10-15 (a floor, not a date); Haiku 5.5` / :141 `# is announced for "the coming weeks" — stage it on release.` | **The flip itself.** While staged: leave as is, add `haiku_staged`. At flip: `haiku_latest: claude-haiku-5-5`, add `haiku_prior`. The trailing comment is now false ("announced") and needs rewriting either way. |
| E9 | `model-config.yaml:1039` | `research_retrieval: claude-haiku-4-5      # Explore tier (25% slot, codebase/file:line lookups). Its` | **Change at flip.** Advisory key: no code reads `research_retrieval` (`rg research_retrieval` finds only docs). What actually binds is the spawn's `model: "haiku"` alias. |
| E10 | `scripts/research-kit/router.py:310-311, 333-335` | `MODEL_KEYS = {"fast": "sonnet_latest", "careful": "haiku_latest"}` / `MODEL_ALIASES = {..., "haiku_latest": "haiku"}` / `def haiku_model(): return config_model("haiku_latest")` | **No edit, but it moves with E8 automatically.** The careful classifier call is `claude -p --model <versions.haiku_latest>` where `claude` is `shutil.which("claude")` (router.py:364), NOT `cc-claude-bin`. At the flip it hands the FULL id `claude-haiku-5-5` to whatever `claude` is on PATH. Verify that binary is >= 2.1.293 before the flip. The flip also changes the classifier configuration id, so a running warm daemon serves the old model until restarted (router.py:370-374, migration 0059). `haiku_staged` is invisible to it (the regex matches only `haiku_latest:`). |

### 1b. DETECTORS (go silently false / wrong after the flip)

| # | file:line | Text | Action at flip |
|---|---|---|---|
| D1 | `hooks/lib/read-before-write-parity.sh:168` | `RBW_ENFORCED_MODELS=" claude-opus-4-6 claude-haiku-4-5 claude-opus-4-5 ... claude-3-5-haiku "` (exact-id mirror of binary 2.1.284's legacy set; `rbw_guard_disabled` at :178-186 compares with `*" $model "*`) | **Re-read from the 2.1.293 binary** (the file's own instruction at :165-167). `claude-haiku-5-5` is not in the list, so the shim will ENFORCE for Haiku 5.5 sessions; that is correct only if 2.1.293's native set also excludes it. Not determined here. Separate, pre-existing: the model is read from the transcript (`.message.model`, :215) and an alias spawn of Haiku 4.5 was measured as `claude-haiku-4-5-20251001` (model-config.yaml:1046); the exact compare does not strip a date suffix, so this detector may already be false for dated Haiku 4.5 ids. Inferred from reading, not run. |
| D2 | `bin/cc-token-ledger:838` | `if b.startswith("claude-haiku"):` (prices Haiku side-request usage in full) | **None.** Prefix glob: survives the flip, which is the shape keying.md recommends. But see P2: it only prices what has a `pricing_per_mtok` row. |
| D3 | `hooks/agent-teams-enforce.sh:66-83` (no Haiku literal) | `ALLOWED=$(yq -r '.auto_mode_allowlist.non_firstParty_max[]' ...)`; a full id must equal an allowlisted id, a bare alias passes only if `claude-<alias>-*` is on the list | **Blocks the teammate role today.** A teammate spawned with `model: "haiku"` or `claude-haiku-5-5` is DENIED because no Haiku id is on the allowlist. Only matters if Haiku 5.5 takes a teammate role; then add it to `auto_mode_allowlist.non_firstParty_max` after an auto-mode check. |
| D4 | `bin/cc-recover-safeguard:110-116` | `same_model()` does a lowercase substring test of the token (`haiku`) inside the blocked-model display text; `FALLBACK_MODELS="${CC_RECOVER_FALLBACK_MODELS:-opus sonnet haiku}"` | **None.** Substring on the family name; survives. |

### 1c. SELFTEST-ASSERTIONS

| # | file:line | Text | Action at flip |
|---|---|---|---|
| S1 | `tests/cc-memory-extract.bats:146` | `[ "$output" = "candidate good-1111 ... claude-haiku-4-5-20251001 12 300 sign-off-first" ]` | **Change with E5.** This one fails RED when E5 changes (good), and stays green while E5 is forgotten (it asserts the old id is still emitted). |
| S2 | `tests/read-before-write-parity.bats:147` | `t="$(tx "$W/tx2.jsonl" claude-haiku-4-5 "Read:$W/unrelated.txt")"` then asserts allow (model in enforced set) | **Vacuously green.** It keeps proving the 4.5 arm and says nothing about 5.5. Add a `claude-haiku-5-5` case (and at :177-185, where 5.5-generation ids are asserted rc 0) once D1 is re-read. |
| S3 | `tests/cc-token-ledger.bats:151` (+ :153) | `d["by_model"]["claude-haiku-4-5"]["delta_tokens"]["input"]')" -eq 2000000` / `# Haiku 2,000,000 x \$1 + Opus 5 1,000 x \$5` | **Vacuously green for the new id.** It prices Haiku from a fixture price list (`tests/fixtures/token-ledger/model-config.yaml:7`) and fixture transcripts keyed `claude-haiku-4-5-20251001`. It stays green even if the live `pricing_per_mtok` has no Haiku 5.5 row, in which case live Haiku 5.5 side usage is silently unpriced (`rate()` returns None). Add a 5.5 fixture row/case, or accept and note it. |
| S4 | `tests/cc-model-registered.bats:40` | `blob "$F/bin" claude-haiku-4-5` | **None.** Used as "a binary that lacks the control id"; any non-opus id works. |
| S5 | `scripts/limit-recover/lr_recon/tests/test_facts.py:72`, `:113` | `self.assertFalse(F.covers(f, "general", "claude-haiku-4-5-20251001"))` / `F.contradict(facts, [("next2", "claude-haiku-4-5", "x", NOW)])` | **None.** Haiku stands for "some model that is not Opus"; the assertion is about scope, not the id. |
| S6 | `tests/research-router.bats:456,472,476`; `tests/research-classifier-warm.bats:514` | synthetic ids `claude-haiku-test-9`, `claude-haiku-old` | **None.** Not real ids. `tests/research-classifier-warm.bats:402` computes the expected `--model` from `router.haiku_model()`, so it follows the SSOT. |
| S7 | `tests/cc-recover-safeguard.bats:92,94,95` | `run "$C" "$BPANE" --model haiku --dry-run` | **None.** ALIAS. |

### 1d. PRICING-OR-TABLE

| # | file:line | Text | Action at flip |
|---|---|---|---|
| P1 | `model-config.yaml:866` | `  claude-haiku-4-5: [1, 5]` | **Add a `claude-haiku-5-5: [in, out]` row** (base rates from the release sources; keep the 2-element arity). Keep the 4.5 row while any transcript still carries it. This is needed at STAGING already, per model.md Case A step 0. |
| P2 | `bin/cc-token-ledger:61` (no Haiku literal) | `CR_MULT = {"claude-fable-5-1": 0.025, "claude-mythos-5-1": 0.025, "claude-opus-5-5": 0.05}` (cache-read multiplier by id, default 0.1) | **Add an entry only if Haiku 5.5's cache-read multiplier is not 0.1x.** Not determined here. `base_model()` at :333-335 strips `[1m]` and a `-YYYYMMDD` suffix, so a dated 5.5 id maps to the `claude-haiku-5-5` row. |
| P3 | `tests/fixtures/token-ledger/model-config.yaml:7` | `  claude-haiku-4-5: [1, 5]` | Fixture for S3; change only if S3 gains a 5.5 case. |
| P4 | `model-config.yaml:1464-1481` | `deprecations:` has only `claude-3-haiku: "2026-04-20"`; Haiku 4.5 appears in the comment block: `#   claude-haiku-4-5  2026-10-15  ← NEAREST. Haiku 4.5 is research_retrieval ...` and `# ... there is no Haiku 5 to move to yet.` / `# and the announcement says Haiku 5.5 follows "in the coming weeks" — stage it on release` | **Rewrite the comment** (5.5 exists; add its retirement floor). Do NOT add `claude-haiku-4-5` as a `deprecations:` KEY before the flip: the lint collects stale literals from deprecations keys as well as `_prior` (claude-lint-models.sh:34). |
| P5 | `skills/research-subagents/SKILL.md:576-577` | `on the pinned retrieval model (\`roles.research_retrieval\`, \`claude-haiku-4-5\`)` / `the whole context window is **200K**, so budget **≤150K**` | **Update** id and the window/budget numbers from the Haiku 5.5 sources. |

`model-config.yaml` has **no context-window or output-cap table**; windows and caps appear only in comments
(for example :92-93, :127-128) and there is none for Haiku.

### 1e. ROUTING-PROSE (claims about what we use now)

| # | file:line | Text | Action at flip |
|---|---|---|---|
| R1 | `skills/research-subagents/SKILL.md:446` | `\| retrieval (file:line lookups) \| \`claude-haiku-4-5\` \| — (no effort param) \| \`roles.research_retrieval\` \|` | **Update** id and the effort cell (see section 5). This file is in `review` (hand-walked), not `update`. |
| R2 | `model-config.yaml:1040-1041` | `# retirement floor is 2026-10-15 (see deprecations) and Haiku` / `# 5.5 is announced for "the coming weeks" — stage it on release.` | **Update.** |
| R3 | `model-config.yaml:1145` | `# (Fable 5 → Opus 4.8 → Sonnet 5 → Haiku 4.5).` | Review: the whole ladder line is already two generations stale. |
| R4 | `skills/research-subagents/SKILL.md:526` | `> 200K-window model such as Haiku. Reasoning quality degrades long before` | Review against the 5.5 window. |
| R5 | `skills/research-subagents/SKILL.md:605` | `→ Haiku-tier (~70× cheaper); the live launcher ...` | Review: the ratio was computed for Haiku 4.5 against an older Opus. |
| R6 | `commands/research.md:91`; `skills/research-subagents/SKILL.md:707`; `agents/deep-research-sonnet.md:42` | `... not \`Explore\` (Haiku lacks reasoning to disambiguate version-drift in canonical sources)` / `Haiku's pure retrieval can miss canonical anchors` | Review: a capability claim about Haiku 4.5; this is exactly the kind of row the role decision re-opens. No id to change. |
| R7 | `scripts/automode-land-probe.sh:28` | `#        AUTOMODE_PROBE_MODEL (default opus — auto mode silently falls back to default on haiku)` | Review: an assumption about Haiku and auto mode that a Haiku 5.5 teammate role depends on. Re-measure on 2.1.293. |
| R8 | `commands/handoff.md:217` | `> model (Haiku by default) that re-runs after every turn ...` (the binary's own small/fast evaluator) | None; family name only. Its concrete model is whatever the binary picks. |
| R9 | `skills/cc-upgrade/holds.md:90`; `commands/research.md:81`; `skills/research-subagents/SKILL.md:610, 668` | `pin \`model: "haiku"\` where retrieval is the job` / `spawn with \`model: "haiku"\`` | None (ALIAS, see 1g). |
| R10 | `scripts/headless-precondition-probe.sh:20`; `scripts/handoff-fire.sh:145`; `tests/rig/lr-recon-canary.sh:14` | `# Cost: a handful of small Haiku turns.` / `--probe ... (haiku, or fable-5` | None; family name only. |

### 1f. HISTORICAL (measurements and incident records: preserve)

| file:line | Text | Note |
|---|---|---|
| `model-config.yaml:1042-1047` | `# ⚠️ BINDS ONLY WHEN THE SPAWN PASSES \`model: "haiku"\` ... measured 2026-09-22 on 2.1.280 under an Opus 5.5 lead: unpinned → claude-opus-5-5, \`model: "haiku"\` → claude-haiku-4-5-20251001.` | Preserve; append the 2.1.293 re-measurement beside it. |
| `skills/research-subagents/SKILL.md:611-612` | `measured 2026-09-22 on 2.1.280 ...: unpinned Explore ran \`claude-opus-5-5\`, \`model: "haiku"\` ran \`claude-haiku-4-5\`` | Preserve; annotate as not re-run. |
| `hooks/lib/read-before-write-parity.sh:17`, `:50` | `claude-opus-4-6 and claude-haiku-4-5 refused` / `\`sonnet_5\`, \`fable_5\`, \`haiku_4_5\` and \`opus_4_6\` are TRUE as well` | Preserve. |
| `bin/cc-jev:14`; `hooks/lib/jev.sh:42-43`; `scripts/jev/pilot.sh:7`; `hooks/anti-deference-nudge.sh:299` | `Jev's terminal verdict LOSES to Haiku 4.5 (62.6% vs 81.3%)` | Preserve (a third-party bench result). |
| `docs/plans/RESEARCH_PROGRAM_BUILD.md:1069-1071, 1163-1164, 1279-1285` and the E1h/E1i tables at :1181-1207 | `haiku 4.5 has a retirement floor of 2026-10-15, so a haiku-4.5 fix expires within weeks` / `(Haiku 5.5 is not released: model-config.yaml haiku_latest is claude-haiku-4-5)` / `careful = haiku_latest (claude-haiku-4-5), thinking on` / `after the retirement it becomes whatever haiku_latest is staged to — Haiku 5.5 when it is released — which is a new configuration id` | Preserve the record. But :1281-1285 is a disclosed dependency that the flip now triggers: the careful call's measured recall/latency (E1h/E1i) was on Haiku 4.5 and is not evidence for 5.5. Follow-up, not an edit. |
| `docs/plans/INSTRUCTION_BUDGET.md:124`; `docs/plans/NONLIMIT_RESUME_LADDER.md:147`; `docs/plans/LIMIT_RECOVER_FLEET_V2.md:700`; `docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md:182` | counts and design notes naming "haiku" / "the Haiku wire probe" | Preserve. |
| `tests/fixtures/lr-recon/screens/composer-empty-2.1.284.txt:2`, `composer-resumed-2.1.284.txt:2` | `▝▜██████▀  Haiku 4.5 · Claude Max` | Captured screens; preserve. |
| `tests/fixtures/lr-recon/jsonl/stub-after-handoff.jsonl:7`; `tests/fixtures/token-ledger/home/dotclaude-{secondary,tertiary}/projects/proj/aaaaaaaa-...jsonl:10` | `"claude-haiku-4-5-20251001":{"inputTokens":...` | Captured/synthetic transcripts; preserve (`**/*.jsonl` is in `preserve`). |
| `hooks/frontier-spawn-gate.sh:30`; `scripts/handoff-fire.sh:13941` | `... while the probe still ran haiku.` | Preserve (incident narrative). |

### 1g. ALIAS (family alias `haiku`; safe across the flip)

What the alias will mean: it is resolved by whichever binary runs. On 2.1.284 `claude-haiku-5-5` is absent
(measured above), so `haiku` there can only resolve to Haiku 4.5; on 2.1.293 the id is present, so `haiku`
is expected to resolve to Haiku 5.5. The actual resolution on 2.1.293 was not measured in this census (no
spawn was run); model.md says to re-measure the alias at every bump.

| file:line | Text |
|---|---|
| `commands/research.md:81` | `\| \`Explore\` (\`roles.research_retrieval\` — spawn with \`model: "haiku"\`; unpinned it runs the lead's model) \| 25% \|` |
| `skills/research-subagents/SKILL.md:610, 668`; `skills/cc-upgrade/holds.md:90` | `pass \`model: "haiku"\` on the spawn` |
| `model-config.yaml:252` | `Agent-tool \`model\` is an enum [sonnet, opus, haiku, fable] on both builds, so an in-session spawn can never name the full id.` |
| `bin/cc-recover-safeguard:116` | `FALLBACK_MODELS="${CC_RECOVER_FALLBACK_MODELS:-opus sonnet haiku}"` |
| `scripts/research-kit/router.py:311` | `MODEL_ALIASES = {"sonnet_latest": "sonnet", "haiku_latest": "haiku"}` (fallback when the SSOT cannot be read) |
| `tests/cc-recover-safeguard.bats:92-95`; `tests/memory-fleet-sweep.bats:232` | `--model haiku` / `"tengu_sepia_cormorant":["haiku"]` |
| `bin/claude-bump-models:65`; `skills/cc-upgrade/model.md:62, 92, 190, 193`; `bin/claude-kimi:255`; `tests/claude-kimi.bats:147,150` | family name in loops and regexes (`for family in frontier opus sonnet haiku`, `claude-(opus\|sonnet\|haiku\|fable)-[0-9]`) |
| `bin/claude-kimi:93, 310` | `ANTHROPIC_DEFAULT_HAIKU_MODEL=$KIMI_MODEL` (the Kimi lane maps the Haiku slot to Kimi; unaffected) |

There is **no** `agents/*.md` with `model: haiku` (measured: frontmatter is `deep-research-sonnet` sonnet/medium,
`deep-research` opus, `frontier-derivation` opus, `research-decomposition-critic` sonnet/medium, `workflow-lean`
no model). There is **no** Workflow `agent()` call or launcher flag in the searched tree that names Haiku.

## 2. model-config.yaml

`versions.haiku_*` (the only one):

```
140:  haiku_latest: claude-haiku-4-5            # retires NOT SOONER than 2026-10-15 (a floor, not a date); Haiku 5.5
141:                                            # is announced for "the coming weeks" — stage it on release.
```

`roles.*` naming Haiku (one of 13 role keys; the others are Opus 5.5, Fable 5.1, or `classifier: claude-sonnet-4-6`):

```
1039:  research_retrieval: claude-haiku-4-5      # Explore tier (25% slot, codebase/file:line lookups). Its
```

`pricing_per_mtok`: `866:  claude-haiku-4-5: [1, 5]` (no comment, no cache-read note).

`deprecations` keys: `claude-3-haiku: "2026-04-20"`, `claude-opus-4`, `claude-sonnet-4`, `claude-opus-4-1`.
Haiku 4.5 is NOT a key; its floor `2026-10-15` is in the comment block at :1475-1481.

`effort_defaults` keys (26, measured by `rg` on lines 1197-1463): `default, verify_judge, mundane, frontier,
settings_floor, fable_default, fable_capability_sensitive, fable_routine, fable51_default,
fable51_capability_sensitive, fable51_routine, fable51_cheap, opus5_default, opus5_capability_sensitive,
opus5_coding_agentic, opus5_routine, opus55_default, opus55_coding_scoped, opus55_capability_sensitive,
opus55_research, opus55_visual, opus55_cheap, sonnet55_default, sonnet55_agentic_scoped, sonnet55_review,
sonnet55_cheap`. **No `haiku*` key.**

`auto_mode_allowlist`:

```
firstParty: [claude-opus-4-7, claude-opus-4-6, claude-sonnet-4-6]
anthropicAws: [claude-opus-4-7, claude-opus-4-6, claude-sonnet-4-6]
non_firstParty_max: [claude-opus-4-8, claude-opus-5, claude-opus-5-5, claude-fable-5, claude-fable-5-1]
non_firstParty_non_max: [claude-opus-4-7, claude-opus-4-6, claude-sonnet-4-6]
```

No Haiku id in any list. `classifier_model: claude-sonnet-5` (descriptive only).

Context-window / output-cap table: **none exists** as data.

Keys that exist for other families but not Haiku:

| Key | frontier | opus | sonnet | haiku |
|---|---|---|---|---|
| `versions.<f>_latest` | yes | yes | yes | yes |
| `versions.<f>_prior` | `claude-fable-5` | `claude-opus-5` | `claude-sonnet-5` | **missing** |
| `versions.<f>_staged` | `""` | `""` | `""` | **missing** |
| `effort_defaults.<f>55_*` / `fable51_*` | 4 keys | 6 keys | 4 keys | **none** |
| `auto_mode_allowlist.non_firstParty_max` entry | 2 ids | 3 ids | none | **none** |
| a `§ <MODEL>` adoption section in the header comments | yes | yes | yes | **none** |
| `pricing_per_mtok` row for the new model | yes | yes | yes | **missing (`claude-haiku-5-5`)** |

To stage the release (binary still on 2.1.284): add `versions.haiku_staged: claude-haiku-5-5` and the
`pricing_per_mtok` row; leave `haiku_latest`, do not add `haiku_prior`, do not run `--apply`. `haiku_staged`
is inert in both tools (bump iterates `${family}_{latest,prior}`; lint selects `test("_prior$")`) and in
`router.py` (its regex is anchored on `haiku_latest:`).
To flip (after the launcher is on 2.1.293): `haiku_latest: claude-haiku-5-5`, `haiku_prior: claude-haiku-4-5`,
`haiku_staged: ""`, `roles.research_retrieval`, plus any new `effort_defaults.haiku55_*` keys the role
decision produces, plus the allowlist entry if a teammate role is chosen.

## 3. model-classification.json

It lives at `templates/model-classification.json` (live `~/.claude/model-classification.json` is a symlink to
the primary checkout's copy; `diff` against the worktree copy: identical). `_last_updated: 2026-06-30`.

Where the files holding Haiku literals fall:

| Bucket | Files with a Haiku literal |
|---|---|
| `update` | **None that survive.** The only Haiku id inside any `update` glob is `reso-management-app/.claude/team-briefs/routines-v1/platform-scaffolding.md:63` (`model: "claude-haiku-4-5" \| "claude-sonnet-4-6"` (enum)), and that file is also in `preserve`. `routines-v1/state-backend.md:138` has only the prose form `Haiku 4.5: $1/MTok input ...`, which neither tool matches. The `README.md` and `agents/*.md` globs are dead (matched as `$root/Development/claude-infrastructure/...` under roots that already are those dirs), and neither file set holds a Haiku id anyway. |
| `preserve` | `team-briefs/routines-v1/platform-scaffolding.md` (rationale in the file: it documents a shipped enum `haiku-4-5 \| sonnet-4-6`); every `**/*.jsonl` fixture (`tests/fixtures/lr-recon/jsonl/stub-after-handoff.jsonl`, the two token-ledger transcripts). |
| `review` | `model-config.yaml` (E8, E9, P1, P4, R2, R3 and the historical lines); `skills/research-subagents/SKILL.md` (R1, R4, R5, P5, historical :611-612); `commands/research.md` (R6, alias :81); `agents/deep-research-sonnet.md` (R6); `agents/deep-research.md` (no Haiku hit). All hand-walked; the scripts ignore this key. |
| **unclassified** | Every code emitter and detector: `scripts/handoff-fire.sh`, `bin/claude-accounts`, `hooks/model-permission-decider.py`, `bin/cc-memory-extract`, `scripts/headless-precondition-probe.sh`, `tests/rig/lr-recon-canary.sh`, `hooks/lib/read-before-write-parity.sh`, `bin/cc-token-ledger`, `scripts/research-kit/router.py`; every test (`tests/*.bats`, `test_facts.py`, the fixture `model-config.yaml`); `docs/plans/*.md`; `bin/cc-jev`, `hooks/lib/jev.sh`, `scripts/jev/pilot.sh`, `commands/handoff.md`, `skills/cc-upgrade/*.md`, `scripts/automode-land-probe.sh`. |

So the entire action list in section 1a-1c is outside the sweep. That is by design (the SSOT comment warns
against adding `bin/ scripts/ hooks/` to `update`), and it means the flip is a hand edit.

## 4. Sweep and lint simulation (`haiku_prior: claude-haiku-4-5`, `haiku_latest: claude-haiku-5-5`)

`~/bin/claude-bump-models` (byte-identical to the worktree's `bin/claude-bump-models`, `cmp`):

- Pair: the `for family in frontier opus sonnet haiku` loop (line 65) would add `claude-haiku-4-5|claude-haiku-5-5`.
  It also re-emits the existing armed pairs (`claude-fable-5|claude-fable-5-1`, `claude-opus-5|claude-opus-5-5`,
  `claude-sonnet-5|claude-sonnet-5-5`), so an `--apply` for Haiku is also an `--apply` for those. The SSOT
  records that the Opus pair was deliberately not swept (reso team-briefs); that decision would be overridden.
- Detector, line 138: `grep -qE "${OLD}([^-0-9]|$)"`. Rewrite, line 142:
  `sed -e "s|${OLD}\([^-0-9]\)|${NEW}\1|g" -e "s|${OLD}$|${NEW}|g"`.
- **Dated id is safe.** In `claude-haiku-4-5-20251001` the character after the id is `-`, which `[^-0-9]`
  excludes, and the id is not at end of line. Measured by running both expressions on sample lines (pipe only,
  no file touched): `claude-haiku-4-5-20251001` unchanged; `claude-haiku-4-5 d`, `"claude-haiku-4-5"`,
  `claude-haiku-4-5: [1, 5]`, `claude-haiku-4-5[1m]` and an end-of-line occurrence all became `claude-haiku-5-5`.
  No `-5-5-5`-style corruption is possible here either: `claude-haiku-4-5` is not a prefix of `claude-haiku-5-5`.
- Target set (update minus preserve). Effective targets are reso's team-brief files: 69 files matched by the
  three `team-briefs` globs (measured with `find` on `/Users/chrisren/Development/reso-management-app/.claude/team-briefs`).
  `rg -l 'claude-haiku-4-5([^-0-9]|$)'` over that directory: 1 file, `routines-v1/platform-scaffolding.md`,
  which `preserve` subtracts. **Files the Haiku pair would rewrite: 0** (simulated by hand from the tool's
  globs and regex).
  Caveat on that number: the tool's own dry-run (`claude-bump-models --from-to claude-haiku-4-5 claude-haiku-5-5`,
  no `--apply`) was started twice and did not finish target collection (killed by a 240 s timeout the first
  time; still running after more than 15 minutes the second). It runs 2 x 3 roots x 11 globs `find` passes,
  including over all of `~/.claude`. I did not confirm that `~/.claude` holds no `.claude/team-briefs` directory
  beyond checking `~/.claude/team-briefs` and `~/.claude/.claude/team-briefs` (both absent). The dry-run is
  also slow enough that anyone running it at the flip should expect a long wait, not a hang.

`scripts/claude-lint-models.sh` (worktree copy; the live `~/.claude/scripts/` path is a symlink to the primary checkout):

- Stale set: line 33 `select(.key | test("_prior$"))` would add `claude-haiku-4-5`; line 34 adds every
  `deprecations` key.
- Match, line 82: `grep -qE "${literal}([^-0-9]|\$)"`, same boundary as the sweep, so the dated id is not flagged.
- `--all` walks `update` globs and skips preserved files by substring (`is_preserved`). The one Haiku-bearing
  target is preserved, so **the Haiku pair adds 0 lint failures**. The lint would stay exactly as red or green
  as it is today (the SSOT says it currently lists reso's `claude-opus-5` briefs as stale).
- Single-file mode (the pre-commit entry point, `claude-lint-models.sh <file>`) checks ANY file handed to it
  that is not preserved. Once `haiku_prior` is set, a commit touching `scripts/handoff-fire.sh` (E1/E2),
  `hooks/lib/read-before-write-parity.sh` (D1), `skills/research-subagents/SKILL.md` (R1, P5, :612),
  `model-config.yaml` itself (:866 pricing row, :1475 comment), `tests/read-before-write-parity.bats`,
  `tests/cc-token-ledger.bats`, `tests/cc-model-registered.bats`, `tests/fixtures/token-ledger/model-config.yaml`,
  `test_facts.py`, or `docs/plans/RESEARCH_PROGRAM_BUILD.md` would be flagged if the pre-commit hook runs the
  lint on them. Whether the hook does that for these paths was not checked.

Net: **both tools report clean for Haiku while fixing nothing.** Every real 4.5 site is either unclassified
code or a dated id. A green lint after this flip is not evidence.

## 5. Effort on a Haiku spawn

Spawn sites that pass an effort TOGETHER with a Haiku model: **none found.**

| Site | Model | Effort passed? |
|---|---|---|
| `scripts/handoff-fire.sh:13852-13855` probe | `claude-haiku-4-5` | No `--effort`; `--setting-sources ""` so no saved level either. |
| `hooks/model-permission-decider.py:411-432` | dated 4.5 | No. `--setting-sources ""`. |
| `bin/cc-memory-extract:372-386` | dated 4.5 | No. `--setting-sources ""`. |
| `scripts/headless-precondition-probe.sh:121-128` | dated 4.5 | No (`--settings` is a probe-local file). |
| `tests/rig/lr-recon-canary.sh:111` | dated 4.5 | No flag; an interactive session under `~/.claude-next`, whose settings carry `effortLevel: "high"`. |
| `scripts/research-kit/router.py:343-357` careful call | `versions.haiku_latest` | No effort. Thinking is left ON for the careful call (only the fast Sonnet call adds `--settings '{"alwaysThinkingEnabled":false}'`, :196-202). |
| `bin/claude-accounts:1290-1293` wire probe | dated 4.5 | Raw API body: `model`, `max_tokens: 1`, one message. No effort, no thinking. |
| Agent-tool `Explore` with `model: "haiku"` | alias | The tool has no effort field; the subagent inherits the LEAD's effort (model-config.yaml:270). |
| `agents/*.md` frontmatter | none is Haiku | `effort: medium` exists only on the two Sonnet agents. |
| Workflow `agent()` opts | none names Haiku in the tree | n/a |

Places that assume Haiku has no effort levels:

1. `skills/research-subagents/SKILL.md:446`: the retrieval row's effort cell is `— (no effort param)`. The only explicit statement.
2. `model-config.yaml` `effort_defaults`: no `haiku*` key at all (implicit).
3. `~/.claude*/settings.json` `modelSettings`: only `claude-opus-5-5` is pinned. model-config.yaml:267-269 records
   that top-level `effortLevel` is ignored for 5.5-generation ids (applied only to a legacy list). If that holds
   for `claude-haiku-5-5`, a headless Haiku 5.5 call with no `--effort` runs at the model's own default, and the
   Opus migration that pinned `modelSettings` (c10 0044) has no Haiku counterpart.
4. The inherited-effort path is the one that changes behavior without any edit. Today a lead at `high`/`xhigh`/`max`
   that spawns `Explore` with `model: "haiku"` sends its effort to a model that rejects it; the client is recorded
   as latching "unsupported" and retrying without it (model-config.yaml:439-441, a note about the 2.1.260 client).
   If Haiku 5.5 accepts effort, the same spawn starts running retrieval at the lead's rung (the launcher default
   is high or above), which is a quota change on the highest-volume slot. Not measured here; it is the first thing
   to measure on 2.1.293.

## 6. Must change in the same diff as the flip

1. `model-config.yaml`: `versions.haiku_latest` -> `claude-haiku-5-5`; add `versions.haiku_prior: claude-haiku-4-5`
   and `versions.haiku_staged: ""`; `roles.research_retrieval`; add `pricing_per_mtok.claude-haiku-5-5`; rewrite the
   comments at :140-141, :1040-1041, :1475-1481. (Before the launcher moves to 2.1.293, only `haiku_staged` plus
   the pricing row.)
2. `scripts/handoff-fire.sh:13816` and `:17071` (probe model, and its dry-run mirror): alias or SSOT read.
3. `bin/claude-accounts:1255` (`WIRE_MODEL`): a real id, since no binary resolves an alias on this path.
4. `hooks/model-permission-decider.py:129` (`MITL_MODEL` default).
5. `bin/cc-memory-extract:54` together with `tests/cc-memory-extract.bats:146`.
6. `scripts/headless-precondition-probe.sh:26`, `tests/rig/lr-recon-canary.sh:36`.
7. `hooks/lib/read-before-write-parity.sh:168`: re-read the enforced set from the 2.1.293 binary; add a
   `claude-haiku-5-5` case to `tests/read-before-write-parity.bats` (:147 and :177-185).
8. `tests/cc-token-ledger.bats:151` / `tests/fixtures/token-ledger/model-config.yaml:7`: add a 5.5 pricing case
   (or record why not); `bin/cc-token-ledger:61` `CR_MULT` only if the cache-read multiplier is non-standard.
9. `skills/research-subagents/SKILL.md:446` (id and effort cell) and `:576-577` (id, window, budget); review
   `:526`, `:605`, `:707`, `commands/research.md:91`, `agents/deep-research-sonnet.md:42`, `scripts/automode-land-probe.sh:28`.
10. Before the flip, not an edit: confirm the `claude` that `scripts/research-kit/router.py:364` finds on PATH is
    >= 2.1.293, and restart the warm classifier daemon after it (the configuration id changes).
11. Only if Haiku 5.5 takes a teammate role: `auto_mode_allowlist.non_firstParty_max` (else
    `hooks/agent-teams-enforce.sh:66-83` denies the spawn), plus new `effort_defaults.haiku55_*` keys.

Count of hits needing action (an edit or a mandatory verification): **24** line-level sites, tallied from the
tables above: E1-E9 (9), E10 verify (1), D1 (1), S1-S3 (3), P1, P4, P5 (3), R1-R7 (7). D3 and P2 are
conditional and not counted.

## 7. Not determined

- The dated API id for Haiku 5.5 (needed for E3; the others can use the alias).
- What `--model haiku` actually resolves to on 2.1.293 (registration measured; resolution not).
- Whether 2.1.293's native read-before-write enforced set contains `claude-haiku-5-5` (D1).
- Whether Haiku 5.5 accepts the effort parameter, its default effort, and whether an Agent-tool Explore spawn
  now inherits the lead's effort in practice (section 5, item 4).
- Haiku 5.5's price, cache-read multiplier, context window, output cap and retirement floor (P1, P2, P5, P4):
  these belong to the source-extraction workers.
- Whether Haiku 5.5 holds auto mode as a teammate model (D3, R7).
- Whether D1 already misses dated Haiku 4.5 ids from transcripts (read, not run).
- The tool's own sweep dry-run did not complete; the "0 files" result is a hand simulation of its globs and regex.
- `docs/research/` was skipped as instructed. Outside the named scope, `rg -c -i haiku` also finds one line each in
  `docs/lessons/symlinked-auto-memory-dir-prompts-on-every-write.md`,
  `docs/lessons/a-cost-premise-is-per-arm-and-is-usually-false.md`, `docs/KIMI_METERED_INTEGRATION.md`,
  `docs/activation/pending-activation/20-model-config-ssot-activate.sh:55` (lists `haiku_latest` among compared
  keys) and `templates/model-classification.json`; none is an emitter. Other repos (reso) were checked only
  inside `.claude/team-briefs`.
