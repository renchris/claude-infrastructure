# Upgrade skills: keep three phase skills, add one front door (design note, 2026-09-28)

Angle given in the brief: keep `model-upgrade`, `cc-version-audit` and `cc-upgrade-gate`, add a thin
front door that classifies the trigger and sequences them, and fix the overlap and staleness.
Read-only analysis. The only write is this file.

## Verdict

**Do not merge the three into one skill. Add one entry point.** The three answer different
questions with different evidence: paper analysis of a CHANGELOG, live probes, and a config/doc
rewrite. Each is also run on its own: a nightly re-gate, a frontier-window lapse (Case C), a
"should we bump CC" question with no model in it. What is actually broken is:

1. **No owner for the sequence.** The order audit → install → gate → activate → SSOT flip is
   written out three times, and the copies disagree:
   - `cc-upgrade-gate/SKILL.md:129-142` (the "Typical flow")
   - `model-upgrade/SKILL.md:139-155` (the 7-gate table)
   - `cc-version-audit/SKILL.md:162-171` (Step 6 pre-flight, which re-does gate checks #3/#7/#11
     by hand)

   Nothing covers the phases that the Opus 5.5 run actually spent its effort on: facts
   extraction, the effort sweep, the synthesis re-probe and feature adoption. The only trace is
   `model-upgrade:12-38` and four research directories.
2. **The descriptions overlap.** Phrases like "new model" or "upgrade Claude Code" match all
   three descriptions, so all three load. Measured with `wc -c`: 55,624 bytes in total
   (29,926 + 16,043 + 9,655). At ~4 chars/token that is ≈ 13.9K tokens (estimated).
3. **Compaction truncates the biggest one.** Per the Claude Code skills docs
   (code.claude.com/docs/en/skills), each invoked skill is re-attached after compaction with only
   its first 5,000 tokens kept, inside a combined 25,000-token budget. `model-upgrade` is
   ≈ 7.5K tokens (estimated from 29,926 bytes / 4). So after a compaction the model keeps
   Steps 0-1 and loses roughly the last third: Case B-D steps, Verification, Invariants.
4. **About 30 stale claims** (list below). They include a gate check that describes a launcher
   deleted two months ago, and activation instructions that point at a consumed one-shot script.

## Resulting tree

```
skills/
├── cc-upgrade/                      NEW — the front door
│   ├── SKILL.md                     ~100 lines  classify → sequence → ledger
│   ├── model-utilization.md         ~90 lines   model-release intake + "which model at which effort"
│   └── harness-adoption.md          ~60 lines   harness-feature adoption (lever → measure → adopt/drop)
├── cc-version-audit/
│   ├── SKILL.md                     220 → ~150  HOLD/ADVANCE + MANIFEST (paper analysis)
│   └── binary-prompt-extraction.md  NEW ~30     moved Appendix (:195-220)
├── cc-upgrade-gate/
│   └── SKILL.md                     142 → ~110  run the probes, GREEN/RED policy
└── model-upgrade/
    ├── SKILL.md                     400 → ~200  Step 0 + classify A-D + Cases A-C + verify + invariants
    ├── case-d-default-repoint.md    NEW ~45     moved :81-117 (Case D emitters, prefix trap)
    └── keying-and-pins.md           NEW ~60     moved :173-202 (detectors/emitters) + a 10-line pin note
bin/
└── cc-model-registered              NEW ~30 lines  `strings` probe with positive control, via bin/cc-claude-bin
```

Supporting files must stay **flat** in the skill directory. `install.sh` links
`skills/<name>/<file>` one level deep only, and `scripts/deploy-parity-assert.sh:672` scores
`skills/*/*/*` as not-expected-live. A `references/` subdirectory would never deploy.
`bin/cc-*` does deploy (`deploy-parity-assert.sh:669`).

### Each file's job

| File | Job | Owns | Must NOT contain |
|---|---|---|---|
| `cc-upgrade/SKILL.md` | Classify the trigger (MODEL / HARNESS / BOTH), run the phases in order, write one run ledger | **The only copy of the phase order.** The classification table. The ledger format. | Any phase's internals. Any version number or model id stated as current. |
| `cc-upgrade/model-utilization.md` | Model release: fetch the materials yourself (`model-upgrade:12-38` moved here), page-cited facts extraction with a re-check reader, effort sweep, re-probe of worker slots, then the role/effort table that flows into `model-config.yaml` | The "which model, at which effort, for which use" method (template: `docs/research/opus55-utilization-2026-09-22/`, `…/opus55-effort-sweep-…`, `…/opus55-synth-reprobe-…`) | SSOT edits. Those belong to model-upgrade's cases. |
| `cc-upgrade/harness-adoption.md` | Harness feature: list the levers the release adds, measure each (template: `opus55-feature-adoption-2026-09-22/README.md`, four levers), adopt or drop with evidence, and record the verdict | The adopt/drop loop for a feature like Dynamic Workflows | Risk verdicts. Those belong to cc-version-audit. |
| `cc-version-audit/SKILL.md` | Is the CC version safe? Read the CHANGELOG gap and open issues, give HOLD/ADVANCE, write MANIFEST entries | Standing-hold discharge, churn heuristic, dist-tag trap, the rollback-drops-capabilities invariant (moved from `model-upgrade:386-395`) | The pre-flight probes (Step 6 becomes "the gate does this"), the sequencing. |
| `cc-upgrade-gate/SKILL.md` | Run `scripts/cc-upgrade-gate.sh`, read the verdict. GREEN → hand over the release's activation script. RED → PARK | The 15-check table, GATE_SPAWN/GATE_RETRIES, the GREEN ⇒ `LIVE_TEST_PASSED` insight | The "Relation to sibling skills" / typical-flow section (:129-142). This is deleted. |
| `model-upgrade/SKILL.md` | Move a model id through the SSOT: Step 0 registration (calls `cc-model-registered`), Cases A-D, verification | The staged-key rule, the case split, the SSOT map, invariants | The release-materials fetch (moved out), the 7-gate sequencing table (moved to front door), the pin census (superseded) |
| `bin/cc-model-registered` | `cc-model-registered <id> [--bin PATH]` resolves the binary through `bin/cc-claude-bin`, runs `strings -a` with a `claude-opus-5` positive control, exits 0/1/2 (present/absent/instrument-broken) | The Bun-binary grep trap (`model-upgrade:51-56`) as code, not prose | — |

Estimated body sizes loaded per path, excluding supporting files that the path does not touch.
The per-file sizes are estimated at ~75 bytes/line, which is today's average across the three
files (55,624 B / 762 lines).

| Path | Loads | ≈ bytes (estimated) | vs today (measured 55,624) |
|---|---|---|---|
| (a) model, id already registered | cc-upgrade + model-utilization + gate + model-upgrade | ~7.5K + 6.8K + 8.3K + 15K ≈ 38K | −32% |
| (b) harness feature | cc-upgrade + harness-adoption + audit + gate | ~7.5K + 4.5K + 11K + 8.3K ≈ 31K | −44% |
| (c) both | all four bodies + model-utilization | ≈ 49K | −12% |

The byte saving is modest in case (c). The real gains are elsewhere:

- Every body fits under the 5,000-token compaction re-attach.
- One owner for the order of phases.
- Case D, keying and binary-prompt extraction load only on the branch that needs them.

## Description strings

These drive auto-loading, so every sibling's description opens with "Phase of /cc-upgrade". That
steers generic upgrade phrasing to the front door while leaving each sibling directly invocable.
Do **not** set `disable-model-invocation: true` on the siblings. That removes them from the
model's reach, and the front door invokes them through the Skill tool. Stay well under the
1,536-char `description`+`when_to_use` listing cap.

```yaml
# skills/cc-upgrade/SKILL.md
name: cc-upgrade
description: "Start here for any Claude Code upgrade: a new Claude model (e.g. Sonnet 5.5), a new Claude Code release or harness feature (e.g. Dynamic Workflows), or both at once. Classifies the trigger, then runs version audit, empirical gate, model-id runbook and utilization/adoption in the right order, with one run ledger."
when_to_use: "Operator pastes a model announcement, system card or prompting-guide URL; names a new CC version or feature; says upgrade Claude Code, new model, adopt <feature>, should we move to <model>, or which model at which effort after a release."
argument-hint: "[model|harness|both] [model-id] [cc-version|latest] [feature…] [urls…]"
allowed-tools: Read, Write, Edit, Bash, Skill, WebFetch, Workflow, Agent, AskUserQuestion

# skills/cc-version-audit/SKILL.md
description: "Phase of /cc-upgrade: HOLD or ADVANCE for a Claude Code binary version, from the CHANGELOG gap since the running version plus open GitHub regressions; writes MANIFEST.jsonl entries. Paper analysis, no live probes, no model changes."

# skills/cc-upgrade-gate/SKILL.md
description: "Phase of /cc-upgrade: run scripts/cc-upgrade-gate.sh headless probes on a candidate binary + model — registration, entitlement, auto-mode, effort, launcher, spawn depth, Agent Teams, Workflows, subagents, hooks, permissions, resume, MCP. GREEN/RED; GREEN hands over the activation script."

# skills/model-upgrade/SKILL.md
description: "Phase of /cc-upgrade: move a Claude model id through model-config.yaml — binary registration probe, Case A lateral / B tier-insertion / C access lapse / D default-tier repoint, id keying, lint and doc sweeps. Also standalone when frontier access lapses."
```

## What the operator types

| Trigger | Entry | What the front door does |
|---|---|---|
| (a) New model | `/cc-upgrade model claude-sonnet-5-5 <announcement> <system-card> <prompting-guide>` | 1. Runs `cc-model-registered claude-sonnet-5-5` on the live pin. **Absent ⇒ reclassify to BOTH** (a model release is always a binary event under a pin, `model-upgrade:42-45`).<br>2. Present ⇒ model-utilization intake.<br>3. `/cc-upgrade-gate <live-bin> <id> next…`.<br>4. `/model-upgrade`, with the case chosen from the ladder.<br>5. Effort/role table into the SSOT. |
| (b) New harness feature | `/cc-upgrade harness latest "Dynamic Workflows"` (or a version number) | 1. `/cc-version-audit` → HOLD stops here, with the ledger written.<br>2. `npm i --prefix ~/.claude-<NNN>`.<br>3. `/cc-upgrade-gate <candidate-bin> <versions.opus_latest> next…`.<br>4. GREEN ⇒ the release's `NN-<slug>-activate.sh`.<br>5. harness-adoption per named feature. |
| (c) Both (today) | `/cc-upgrade <urls…>`. With no mode it classifies on its own; `both` forces it. | 1. Intake.<br>2. Audit of the binary that registers the id.<br>3. Install.<br>4. Gate on candidate bin + new model.<br>5. Activation, binary-first (the 45-opus55-cc280 order).<br>6. `/model-upgrade` SSOT flip in a worktree through /ship.<br>7. Utilization.<br>8. Adoption. |

About today's case: the worktree name `sonnet55-cc284` and `~/.claude-284` being on disk suggest
Sonnet 5.5 needs 2.1.284 while the launcher is pinned at `~/.claude-280` (`~/.zshrc:496`). That
is inferred from those two names, not measured with a probe. If it holds, case (c) is the
correct classification.

**The run ledger.** The front door writes
`docs/research/<slug>-<date>/UPGRADE.md`, with one row per phase: verdict, evidence path, sha.
Each phase hands off through that artifact rather than through context, so a compaction or a
fresh session resumes from the ledger.

## What gets deleted or moved

| From | Lines | Action |
|---|---|---|
| `cc-upgrade-gate/SKILL.md` | 129-142 "RELATION to the sibling skills" + typical flow | **Delete.** The order lives only in the front door. |
| `cc-upgrade-gate/SKILL.md` | 102-108, 110-116 (`10-opus5-activate.sh`, `REPOINT_NEXT`, "claude-next launcher", "2.1.219 track, rollback floor 2.1.217") | Replace with "run the release's `docs/activation/pending-activation/NN-<slug>-activate.sh`; template `45-opus55-cc280-activate.sh`". Keep the GREEN ⇒ `LIVE_TEST_PASSED` insight. |
| `model-upgrade/SKILL.md` | 12-38 (Step -1b release materials, OCR guidance) | **Move** to `cc-upgrade/model-utilization.md` |
| `model-upgrade/SKILL.md` | 137-155 (7-gate table + gate-1-vs-3 paragraph) | **Delete.** The front door owns it. Keep :157-171 (sizing, dist-tag, rollback) as ~12 lines. |
| `model-upgrade/SKILL.md` | 81-117 (Case D) | **Move** to `case-d-default-repoint.md`, leaving a 3-line pointer |
| `model-upgrade/SKILL.md` | 173-202 (keying) | **Move** to `keying-and-pins.md` |
| `model-upgrade/SKILL.md` | 328-367 (Appendix pin census) | **Delete the census.** Superseded by `bin/cc-claude-bin`, see the staleness list. A 5-line pointer goes into `keying-and-pins.md`. |
| `model-upgrade/SKILL.md` | 164-166 (npm `stable` tag) | **Delete.** Duplicate of `cc-version-audit:41-44`. |
| `model-upgrade/SKILL.md` | 386-395 (invariant 6, rollback drops binary capabilities) | **Move** to cc-version-audit. It is a binary-version fact. |
| `model-upgrade/SKILL.md` | 47-48, 312-314 (inline `strings` probe on `~/.claude-220`) | Replace with a `cc-model-registered` call |
| `cc-version-audit/SKILL.md` | 162-171 (Step 6 pre-flight) | Replace with "run /cc-upgrade-gate (checks 3, 7, 11 cover the smoke tests)". Keep only what the gate does not probe: the AskUserQuestion idle-timeout and the Explore re-pricing. |
| `cc-version-audit/SKILL.md` | 195-220 (binary-prompt extraction) | **Move** to `binary-prompt-extraction.md` |

Nothing outside `skills/` is deleted. No command files exist for these skills: `commands/` has
none, so there is no command layer to remove.

## Stale claims, file:line

All lines are in `/Users/chrisren/Development/claude-infrastructure/skills/…` unless noted.
Each claim was verified by reading the named evidence in this session.

**cc-upgrade-gate/SKILL.md**

- :57 "THE 14 CHECKS". There are **15**: `lib/cc-upgrade-gate/check15_depth_effect.sh` exists, the
  table has no #15 row, and `docs/README-reference.md:286` already says 15. The same stale count
  appears at `scripts/cc-upgrade-gate.sh:14` ("The 14 checks").
- :75 check 12 describes "`cc-next` routes … to the `claude-next` eval-track launcher". The check
  was retargeted on 2026-08-01 (`check12_resume.sh:13-19`) and now asserts
  `cc` → `claude --resume <sid>`, plus the `ccr` arms `claude` / `claude-prev`.
- :104, :107, :110-111, :141 `10-opus5-activate.sh`. This is a one-shot that has already run
  (`~/.claude/autonomy/pending-activation/10-opus5-activate.sh.done`). Activation is now one
  script per release (`45-opus55-cc280-activate.sh`).
- :106 "repoint the everyday claude-next launcher". `claude-next` was deleted by consolidation v2
  (`model-upgrade:330-336`).
- :114-115 "<1-day binary soak on the shared 2.1.219 track (rollback floor 2.1.217)". This is a
  perishable version stated as current. The launcher is on `~/.claude-280` (`~/.zshrc:496`).
- :42 example `~/.claude-219/... claude-opus-5`. Harmless as an example, but it reads as current.
  Replace it with `$(bin/cc-claude-bin)` and `<model>`.
- :67 check 4 rationale "opus-5's curves peak medium/xhigh and `max` over-thinks". This is a
  model-specific perishable fact inside a policy file. Opus 5.5 defaults to `medium`
  (`45-opus55-cc280-activate.sh` header).

**cc-version-audit/SKILL.md**

- :3 description "the Claude Code binary (claude-next or the pinned stable)". `claude-next` no
  longer exists.
- :9-11 "Two tracks: an eval track (`~/.claude-<NNN>` …) and a pinned stable track (`claude`/`cc`
  → `~/.claude-versions/`)". The names have moved:
  - `claude`/`cc` are now the single `~/.claude-280` pin (`~/.zshrc:496-500`).
  - The stable track is `claude-prev`/`cc-prev` → `claude-latest` → `~/.claude-versions/current`,
    held at 2.1.114 (`~/.zshrc:134-175, 298-318`).

  Two tracks do still exist, so the fix is to rename them, not delete the idea.
- :24-26 "`claude`/`cc` are shell functions resolving the stable-pinned launcher". This is wrong
  now: `claude` resolves the live pin.
- :32 a second `CLAUDE_CODE_EXECPATH` bullet naming `.claude-183` ⟹ "eval/2.1.183". It duplicates
  :30 and breaks the file's own no-current-version rule (:16-21).
- :33 "`TeamCreate` present ⟹ 2.1.114". This is a historical heuristic.
- :39 `cat ~/.claude-versions/current`. `current` is a **directory**. Measured: `cat` returns
  "Is a directory".
- :146-158 Step 5 presents MANIFEST default-deny as the thing that "holds the pin". MANIFEST
  `status` governs only the `claude-latest` auto-installer, i.e. `claude-prev`. The live launcher
  does not read it (`model-upgrade:365-367`; the MANIFEST 2.1.280 entry of 2026-09-22T19:38Z says
  the same).
- :148 "`DISABLE_AUTOUPDATER=1` is exported by the launcher (`~/bin/claude-latest`, ~line 333)".
  Measured at `bin/claude-latest:342`. The live `claude()` sets it inline at `~/.zshrc:498,500`.
- :170 "`research-subagents.md`". The rules file is gone (`model-upgrade:263-265`). The content
  now lives in `skills/research-subagents/SKILL.md`.
- :189 "VERDICT (hold vs target version, per track)". The tracks need to be named as in the
  rename above.
- :69-73 standing-hold issue table (#84974 etc.). This is a perishable list inside a file that
  says it holds none. Whether any of these issues is discharged is **unverified here**. The
  MANIFEST's three 2.1.280 entries are later than this table.
- :58 hardcoded `/Users/chrisren/.claude-versions/...`. Minor: use `~` via `os.path.expanduser`.

**model-upgrade/SKILL.md**

- :47 and :312 hardcoded `~/.claude-220` for the "PINNED" binary. The pin is `~/.claude-280`,
  and :325 admits the path goes stale. Use `bin/cc-claude-bin`.
- :106-107 says `check05_launcher.sh` "hardcodes both `--model` and `--effort`". That is stale
  since 2026-09-16: check05 reads `versions.opus_latest` and `effort_defaults.default` from the
  SSOT (`check05_launcher.sh:121-133`). The residual truth is that a Case D repoint off Opus
  still reds check05, because it keys on `opus_latest`, not `roles.lead_default`. Rewrite it to
  say that.
- :249-250 "Agent Teams run BOTH launcher tracks (eval-track teams empirically fine since
  2.1.156)". This is a two-track claim.
- :276-277 "definitions are shared by both launcher tracks". Same two-track claim.
- :295-296 Case C "remove `--model <id>` from the eval-track function (2 refs, ~lines 306/310)".
  The `--model` sites are now in `claude()` at `~/.zshrc:498,500`.
- :339-361 Appendix census of "6 live pins" at `.claude-220`. **Superseded.** Each named site now
  carries a "no version literal" comment and resolves through `bin/cc-claude-bin`:
  `bin/cc-offload:87`, `scripts/lib/cloud-create.sh:116`, `scripts/capacity-ramp.sh:52`,
  `hooks/model-permission-decider.py:97`, `scripts/mcp-modal-probe.py:28`,
  `scripts/mcp-modal-e2e-probe.py:15` (grep, this session). Only these literals remain:
  - `bin/cc-notify:754` ("2.1.220+" inside an error string)
  - `bin/cc-reaper:3238-3240` (fixtures)

  Backlog `e8b753cac339` (:357) looks resolved. Confirm before closing it.
- :357-361 "the actual fix — giving them one resolver". This is done (`bin/cc-claude-bin`).
- `scripts/claude-lint-models.sh:47` points at "model-upgrade/SKILL.md § Downgrade". Keep the
  word "Downgrade" in the Case C heading through the split, or update this pointer.

## Front-door SKILL.md skeleton (~100 lines)

1. **Classify** (≈20 lines). Inputs: mode argument, model id, CC version, feature names, URLs.
   - Model id present → `cc-model-registered <id>` on `$(bin/cc-claude-bin)`: exit 0 = MODEL,
     exit 1 = BOTH, exit 2 = STOP (the instrument is broken).
   - No model id and a version or feature named → HARNESS.
   - Ambiguous → one AskUserQuestion.
2. **Phase table** (≈30 lines). Rows are the phases; columns are MODEL / HARNESS / BOTH, with
   ✓ or — and the stop condition. Phases:
   - P0 intake → `model-utilization.md` §intake
   - P1 audit → `/cc-version-audit`
   - P2 install
   - P3 gate → `/cc-upgrade-gate`
   - P4 activate → the release's activation script
   - P5 SSOT flip → `/model-upgrade`
   - P6 utilization → `model-utilization.md` §sweep
   - P7 adoption → `harness-adoption.md`

   Stops: HOLD at P1, RED at P3, and "staged" at P5 when the id is still absent.
3. **Ledger** (≈15 lines). Format and path, plus the rule that each phase writes its row before
   the next phase starts.
4. **Invariants** (≈15 lines):
   - Binary first, SSOT second.
   - No phase skipped silently: a skip is written into the ledger with its reason.
   - The front door states no version or id as current.
   - The SSOT flip goes through a worktree + /ship, never through the shared symlinked checkout
     (the `45-…` header's rule).
5. **Pointers** (≈10 lines). One line per sibling and per supporting file.

## Migration steps

1. In a worktree (not the primary checkout), add `bin/cc-model-registered` plus a bats test:
   - present id → 0
   - absent id → 1
   - control absent → 2
   - a plain `grep` would give 0 for every id, so assert that `strings` is used
2. Create `skills/cc-upgrade/{SKILL.md,model-utilization.md,harness-adoption.md}`. Build them
   from `model-upgrade:12-38` and the four `opus55-*` READMEs, keeping the method and dropping
   the numbers.
3. Split model-upgrade into SKILL.md + `case-d-default-repoint.md` + `keying-and-pins.md`. Delete
   the census and the 7-gate table. Replace the inline probes with `cc-model-registered`.
4. cc-version-audit: rename the tracks (`claude` = live pin, `claude-prev` = MANIFEST-governed
   stable). Fix the Step 0 bullets, the :39 command, the Step 5 scope and the :170 path. Collapse
   Step 6 into a gate pointer. Move the Appendix out. Move invariant 6 in.
5. cc-upgrade-gate:
   - Add the #15 row and fix #12.
   - Make activation release-generic.
   - Delete :129-142.
   - Fix `scripts/cc-upgrade-gate.sh:14` "14 checks" (a script comment, `lib/`-adjacent, so it
     needs a bats/shellcheck pass).
6. Change all four descriptions as above.
7. Add a staleness lint, which is the durable fix. Run it in the land gate: fail on
   `claude-next|cc-next|\.claude-[0-9]{3}|10-opus5` in `skills/{cc-*,model-upgrade}/*.md`,
   except on lines tagged as historical. Every stale item above is one of those four tokens,
   except the check count. For that, assert that the number in the gate skill equals
   `ls lib/cc-upgrade-gate/check*.sh | wc -l`.
8. Deploy: install.sh links the new `skills/cc-upgrade/*` one level deep. Run deploy-parity; the
   `skills/*/*` arm expects them live. Also fix `docs/README-reference.md:288` ("15 skills",
   already inaccurate).
9. Acceptance: in a fresh session, type "Sonnet 5.5 is out, upgrade" with the three URLs, and
   check which skills load.
   - Pass: `cc-upgrade` loads first and the siblings load only at their phase.
   - Fail: a sibling auto-loads directly. If that happens, tighten its description.
10. Land through /ship. Then run `/cc-upgrade` for real on the Sonnet 5.5 case as the first user.

## Risks

- **Siblings still auto-load directly.** A description match on "gate" or "model id" can bypass
  the front door. The "Phase of /cc-upgrade" prefix reduces this but cannot guarantee it.
  Step 9 measures it. `disable-model-invocation` is not the fix: it blocks the front door's own
  Skill calls.
- **The front door becomes the fourth stale copy.** It is safe only if it states no versions or
  ids and the siblings keep no ordering text. Lint step 7 enforces the first condition; review
  enforces the second.
- **Misclassifying a model release as model-only.** This is the documented Opus 5 / Fable 5.1
  failure (`model-upgrade:67-70`). The classifier must run the registration probe, never trust
  the docs, and exit 2 on a broken instrument rather than reading 0 as "absent".
- **Case (c) context barely shrinks** (≈ −12%, estimated). The win is sequencing, compaction fit
  and staleness, not bytes. If context in (c) matters more, the next lever is
  `context: fork` for cc-version-audit, so its body never enters the lead's context. That only
  works once its AskUserQuestion and MANIFEST writes are made prompt-free, because a forked
  subagent cannot answer prompts.
- **Case D check05 coupling survives the fix.** check05 still keys on `opus_latest`, so a
  default-tier repoint reds the gate. That is noted, not fixed, here.
- **One track means any harness upgrade moves the whole fleet.** The gate is mandatory on path
  (b) too, and a "feature-only" upgrade is never a paper exercise.
- **Standing-hold table accuracy is unverified.** Moving it into the audit's live Step 1b read of
  MANIFEST, instead of a table in the skill, removes that perishability.
