# Upgrade skills: organise by lifecycle phase (design note, 2026-09-28)

**Brief:** should `model-upgrade`, `cc-version-audit` and `cc-upgrade-gate` become one skill? Design
angle: organise by lifecycle phase (evidence → gate → activate → sweep), not by trigger (model vs
harness feature). Optimise for what an agent needs at each moment and for context cost. Read-only
survey of `/Users/chrisren/Development/claude-infrastructure` at `9eb533126`.

## Verdict

**Merge the three skills into ONE skill, `cc-upgrade`.** Its `SKILL.md` becomes a thin router.
Four flat phase files hold the work (`evidence.md`, `gate.md`, `activate.md`, `sweep.md`), plus
one `reference.md` that is read only on demand. Model vs harness becomes a **track flag inside each
phase**, not a boundary between skills.

Why the trigger split is the wrong boundary:

1. **Every recent model upgrade was also a binary upgrade.**
   - `model-upgrade/SKILL.md:42-44` says so itself: "a model release is never only a model event —
     it is ALWAYS also a binary event".
   - Fable 5.1 needed ≥2.1.253 (`:69`).
   - Opus 5.5 needed 2.1.280. `45-opus55-cc280-activate.sh:10-13` records that 2.1.260 refused the
     id by name.
   - This run's worktree is `sonnet55-cc284`, and `~/.claude-284` is installed.

   So "a new model" almost always means "both at once" (case c). Case (a) alone is the exception.
2. **The three skills already form one pipeline, each describing the others as its neighbours.**
   - `cc-upgrade-gate/SKILL.md:129-142` is a "RELATION to the sibling skills" section.
   - `model-upgrade/SKILL.md:137-155` re-tabulates the whole gate sequence, and its gates 1 and 3
     *are* the other two skills.
   - Each skill restates the others' facts, and the copies have drifted apart (see § Stale claims).
     One spine removes that duplication.
3. **Today's invocation loaded all three bodies.** Size, measured with `wc -c` on the three
   `SKILL.md`: 29,926 + 16,043 + 9,655 = **55,624 bytes**. That is **≈13.9K tokens**, estimated at
   ~4 chars/token. Much of it is dated incident prose that no phase of a run needs.

**What stays separate:** the *tool*. `scripts/cc-upgrade-gate.sh` and `lib/cc-upgrade-gate/check*.sh`
are unchanged, and only the skill that wraps them goes away.

## Resulting tree

Flat on purpose. `install.sh:876-884` links nested skill files, but `scripts/deploy-parity-assert.sh:672`
scores `skills/*/*/*` as `want=0`, which means not expected live. A `references/` subdirectory would
therefore be outside the parity check. The flat multi-file precedent is `skills/launch-film/`.

```
skills/cc-upgrade/
  SKILL.md       ~110 lines  router + invariant spine            (loaded by description match)
  evidence.md    ~160 lines  phase 1: what changed, should we move (read at phase start)
  gate.md         ~90 lines  phase 2: does it still work — cc-upgrade-gate.sh + policy
  activate.md    ~140 lines  phase 3: install, repoint, SSOT flip, fleet census, rollback
  sweep.md       ~140 lines  phase 4: id keying, effort/role re-sweep, feature adoption, close-out
  reference.md   ~120 lines  on demand only: Case D detail, landmine ledger, pin history, incidents
```

Total ≈ 760 lines, the same as today's 762 (measured with `wc -l`). The saving is not in total
bytes. It comes from two things:

- **At any moment, only the router plus one phase file is live.** That is ≈ 270 lines (~15 KB,
  ≈ 3.8K tokens, estimated) instead of 762 lines (≈13.9K tokens).
- **A harness-only run never opens the model half of `sweep.md`.**

The line budgets are estimates, sized to hold the surviving content after historical prose moves
to `reference.md`.

### Each file's job

**`SKILL.md` — router (~110 lines).** This is what the agent needs *before it knows the case*.

- **Classify the trigger into one of three rows.** Each row lists the phases it runs and which
  sections to skip:

  | Track | Evidence | Gate | Activate | Sweep |
  |---|---|---|---|---|
  | model | release pack + registration probe | yes | SSOT flip (Case A-D) | ids + effort/roles |
  | harness | CHANGELOG + binary read | yes, **plus a new probe for the feature** | launcher pin | feature levers |
  | both | both | one run: new binary × new model | pin first, SSOT after | both |

  The registration probe (phase 1) auto-promotes "model" to "both" when the pinned binary lacks
  the id.
- **The invariant spine.** One line each; the bodies live in the phase files:
  - Binary first. Use `strings` plus a positive control, and never report a bare zero.
  - A staged id is not a routed id.
  - Registration ≠ entitlement ≠ plan inclusion. Record "NOT STATED" as itself.
  - Read perishable facts live: `bin/cc-claude-bin`, `model-config.yaml`, `npm view`. Never restate
    them in this skill.
  - A GREEN gate means upgrade immediately (the operator mandate). Any RED means PARK.
  - `claude-bump-models --apply` mutates the primary checkout.
  - `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` carries across every bump.
  - A zshrc repoint reaches new shells only.
  - A rollback drops capabilities that live in the binary.
- **A phase table:** "Read `<file>` when you reach phase N". The file is read, never inlined.
- **The run artefact contract.** One `docs/research/<slug>-<date>/` directory, with a fixed layout:
  - `README.md` for the verdicts;
  - `facts.json`, `notes/` and `census/`;
  - `gate-<ver>-<model>.json` (the gate's stdout);
  - an `adoption.md` per harness lever.

  The Opus 5.5 run spread these over four sibling directories (`opus55-{utilization,effort-sweep,
  synth-reprobe,feature-adoption}`). One directory per run is easier to find.
- **A delegation table:** which steps fan out to `workflow-lean` readers (page ranges, CHANGELOG
  axes, adversary) and which stay on the lead (the gate verdict, activation, the SSOT flip).

**`evidence.md` — phase 1 (~160 lines).** Answers "what changed, and should we move at all?"

- **E1. Running runtime and target.**
  - Read the running runtime from `ps -o command= -p $PPID` and `bin/cc-claude-bin`.
  - Read the target from `npm view … version dist-tags time`.
  - Keep the dist-tag trap and the age-since-publish rule; the soak jq recipe goes to `reference.md`.
- **E2. Model track.**
  - Fetch the release pack yourself (`model-upgrade:12-38`) and invoke `claude-api` for facts.
  - Tools: `pdftotext`, `pdfimages` and vision on native-resolution charts. Do not OCR a
    born-digital card.
  - Page-range readers with a verifier per range, feeding `facts.json`.
- **E3. Harness track.**
  - Slice the CHANGELOG from the version we actually run.
  - Discharge the standing HOLD *from the MANIFEST row*, not from a table copied into the skill.
  - Fan out the three axes plus an adversary (`cc-version-audit:93-110`).
  - Apply the churn heuristic: set the floor at the last fix in a cluster.
  - Read the binary for any feature the changelog paraphrases. Use the Python `mmap` probe noted in
    `opus55-feature-adoption/README.md`, not a minutes-long `strings | grep`.
- **E4. Registration probe.** Moved from `model-upgrade:40-70`.
  - Its answer (`present` / `absent`) decides whether a model run becomes "both".
  - The id is parked in `<family>_staged`.
- **E5. Verdict line.** ADVANCE / HOLD, plus the MANIFEST row. The MANIFEST row governs only the
  legacy `claude-prev` lane, so say so explicitly.

**`gate.md` — phase 2 (~90 lines).** Answers "do our ways of working still work on the candidate?"

- The invocation, with the candidate path given explicitly and the accounts sweep.
- A compact table of all **15** checks.
- `GATE_SPAWN`, `GATE_RETRIES`, and how to read the JSON.
- GREEN/RED policy, and entitlement and plan inclusion (old gates 4-5).
- **New rule for the harness track: a feature you are adopting gets its own `checkNN_<feature>.sh`
  before activation.** The existing 15 checks prove we did not *regress*; they do not prove the new
  feature works here. That is exactly what the opus55 feature-adoption doc had to measure by hand.
  Adding a check is a new file only (`cc-upgrade-gate.sh:14-16`).

**`activate.md` — phase 3 (~140 lines).** Answers "move the fleet, reversibly."

- **Install the candidate into a new prefix.** `npm i --prefix ~/.claude-<NNN>`, leaving the old
  prefix as the rollback floor.
- **Write `NN-<slug>-activate.sh` from a template.** `45-opus55-cc280-activate.sh` is the reference
  shape, because it covers the whole contract:
  - fail-closed preflight;
  - anchor counts;
  - a smoke check on `modelUsage`;
  - a backup, then an artifact self-assert;
  - `zsh -n`;
  - `--undo`;
  - the `CONFIRM=1` gate.
- **The SSOT flip.** It goes through a worktree and `/ship`, never through the `~/.claude` symlink
  (`45…:41-45`). It carries the Case A/B/C classification and its `versions.*` edits. Case D is one
  paragraph here that points to `reference.md`.
- **Staging rules.**
- **Split-fleet census.** Moved from `model-upgrade:209-222`.
- **Rollback.**

**`sweep.md` — phase 4 (~140 lines).** Answers "make the rest of the fleet agree, and use what we
bought."

- **Model half:**
  - detector/emitter keying (`model-upgrade:173-202`);
  - the `claude-bump-models` dry-run, then `--apply`, then the lint;
  - the `review` walk with the tense test;
  - the conditional frontier doc template;
  - the effort/role re-sweep method: paired judges; the equal-tools trap from
    `opus55-synth-reprobe/README.md`; rungs are advisory until code reads them.
- **Harness half:** the feature-adoption method from `opus55-feature-adoption/README.md`:
  - read the binary;
  - A/B one lever at a time;
  - adopt or don't at a stated conviction;
  - wire through settings `env` or migration, not a restated constant.
- **Close-out:** memory entry, MANIFEST note, backlog rows.

**`reference.md` — on demand (~120 lines).** Nothing in it is needed on the hot path:

- Case D in full (`model-upgrade:81-113`);
- the "standing landmines" ledger, dated (`cc-version-audit:173-186`);
- the hidden-prompt extraction appendix (`cc-version-audit:195-220`);
- the pin-drift history and the 2.1.170→2.1.114 rollback incident;
- the soak/tenure jq recipe.

## Description string (drives auto-load)

Only one listing entry remains. The limit is 250 chars, enforced by `tests/skill-listing-budget.bats:38`
(`DESC_MAX=250`). This string measures 243 chars (`printf … | wc -c`):

```
Upgrade Claude Code for a new model, a new harness feature, or both: release evidence, the headless gate, activation, then the id/effort/feature sweep. Use when a model ships, a CC release adds a feature, or on "should we upgrade Claude Code".
```

- The phase files carry no frontmatter and are never listed.
- Net listing change: −2 entries, roughly −500 chars of the 30,000-char listing (estimated from
  three descriptions of ~250 chars each, 32e8553b8).

## Operator entry (one skill, three forms)

| Case | Types | What the router does |
|---|---|---|
| (a) new model | `/cc-upgrade model <announcement-url> [card-url] [prompting-url]` | E2 + E4. If E4 reads `absent`, it announces "this is (c)" and continues as (c), without asking. |
| (b) new harness feature | `/cc-upgrade harness <feature-or-version>` (e.g. `harness "Dynamic Workflows"`) | E1 + E3, then the gate with a new feature probe, a pin-only activation, and the harness half of the sweep. |
| (c) both (today) | `/cc-upgrade <urls> <feature-or-version>`, or just `/cc-upgrade` plus free text | Both tracks run through one gate run on (new binary × new model). The pin moves before the SSOT flip (binary-first, as in `45…:47-49`). |

The `model` and `harness` words are hints. The router classifies free text, and E4 can always
upgrade (a) to (c).

## What gets deleted

- **In the repo:** `skills/model-upgrade/`, `skills/cc-version-audit/` and `skills/cc-upgrade-gate/`
  (their `SKILL.md` files).
- **Live:**
  - The three dirs `~/.claude/skills/{model-upgrade,cc-version-audit,cc-upgrade-gate}/`. Each holds
    one per-file symlink into the repo (verified with `ls -la`).
  - **`install.sh:854` never prunes**: "Only touches skill NAMES present in the repo". Deleting a
    repo skill therefore leaves a **dangling `SKILL.md` symlink** live. It must be removed by hand
    at deploy.
  - `~/.claude-secondary/skills` and `~/.claude-tertiary/skills` are dir symlinks to the same tree
    (`skills/LOCAL_ONLY.md:67-70`), so one removal covers them.
- **Historical prose that does not move:** "used to read…" paragraphs, superseded wording and
  corrected-claim narratives. Examples: `model-upgrade:317-326`, `:330-337`, `:372-374`, and
  `cc-version-audit:16-21`. Their facts survive in git history and in `reference.md` where they are
  still load-bearing.

## Migration steps

1. **Worktree branch.** Write the six files under `skills/cc-upgrade/`, moving content section by
   section.
   - Fix every stale claim below during the move; do not copy it.
   - Replace every hardcoded `~/.claude-NNN` with `$(bin/cc-claude-bin)` or an explicit `<candidate>`
     placeholder.
2. **Repoint the references to the old names:**
   - `scripts/claude-lint-models.sh:47` names `~/.claude/skills/model-upgrade/SKILL.md § Downgrade`.
     That section is titled "Case C — Downgrade" today, so the anchor is already inexact. Point it
     to `cc-upgrade/activate.md § Case C`.
   - `scripts/claude-lint-models.sh:117`.
   - `hooks/pre-session-validate.sh:51`.
   - `hooks/agent-teams-enforce.sh:533`.
   - `templates/model-classification.json:2` (`_doc` names "the model-upgrade skill").
   - Leave these as history: `skills/LOCAL_ONLY.md:73`, `agents/deep-research.md:116` (a research
     doc name) and the `docs/plans/*`.
3. **Fix the gate's own stale strings in the same diff:**
   - `scripts/cc-upgrade-gate.sh:14` ("14 checks") and `:19` (the `~/.claude-219` example);
   - `lib/cc-upgrade-gate/check05_launcher.sh:189` (the PASS text hardcodes `claude-opus-5` and
     `high`, although the check reads the SSOT at `:121-131`);
   - `check04_effort.sh:4-7,30` ("Opus 5's ladder… high (its own default)").
4. **Tests:**
   - `tests/skill-listing-budget.bats` must pass (one entry, 243 chars).
   - `deploy-parity-assert` should now list 6 `skills/cc-upgrade/*` files expected live.
   - Add one bats assertion that `SKILL.md` names each phase file and that each file exists. A
     router pointing to a missing file is the silent failure here.
5. **Land with `/ship`, then deploy-live**, which re-runs `install.sh` and links the new dir. **Then
   remove the three stale live dirs by hand.** They sit outside what the installer manages.
6. **Dry run on the live case:** start `/cc-upgrade` on the Sonnet 5.5 × 2.1.284 run in progress
   and check that the router picks (c) and loads only the files it needs.

## Risks

- **Habit and muscle memory.**
  - `/cc-upgrade-gate`, `/model-upgrade` and `/cc-version-audit` stop resolving after the delete.
  - Mitigation: the description carries the phrases people actually type ("should we upgrade
    Claude Code", "model ships"). Do not keep stub skills: each costs a listing entry and splits
    description matching.
  - A residual risk is accepted: a slash command typed by its old name will fail loudly. That is
    the good failure mode.
- **Router under-reads.**
  - An agent may act from the `SKILL.md` spine without opening the phase file. The spine then
    becomes a lossy copy, which is today's drift in a new place.
  - Mitigation: the spine holds rules only, with no procedures and no commands. Each phase opens
    with a "you must have read this file" line. The bats test in step 4 pins that the pointers
    resolve.
- **Phase files read cumulatively.** A full (c) run reads all four, about 530 lines (≈ 8-9K tokens,
  estimated). That is below today's 13.9K, but not by much. The real win is relevance and one
  copy of each fact, not raw bytes. Do not oversell it as a context saving on (c).
- **Nested-dir temptation.** A `references/` subdirectory would pass `install.sh` but be scored
  `want=0` by `deploy-parity-assert.sh:672`, so it would sit outside the parity check. Keep the
  skill flat.
- **Merge window.**
  - The Sonnet 5.5 run is in flight on `sonnet55-cc284` and may be following the old skills.
  - Land the consolidation after that run's activation, or have the run use the new skill from the
    start. Do not do both halfway.
- **A gate rung the model may not have.**
  - `check04` asserts `xhigh` and `max` are accepted. If a new model family (e.g. Sonnet 5.5) lacks
    a rung, the gate goes RED on a non-regression.
  - Fix: drive `gate.md` from E2's facts, so the expected ladder comes from `facts.json`.
    Alternatively, give check04 a per-family expected ladder. Not verified for Sonnet 5.5; this is
    a hazard to check, not a finding.

## Stale claims found (file:line)

"Live" means read on this box today. Current pin: `~/.zshrc:496` `_bin="$HOME/.claude-280/…"`.

**`skills/model-upgrade/SKILL.md`**

| Line | Claim | Reality |
|---|---|---|
| :47, :312 | The binary probe hardcodes `~/.claude-220/…/claude.exe` "← the PINNED one". | The pin is `.claude-280`. `:325-326` admits the path goes stale. Use `bin/cc-claude-bin`. |
| :105-107 | "`check05_launcher.sh` hardcodes both `--model` and `--effort`, so any repoint reds the gate". | Fixed 2026-09-16. check05 reads `opus_latest` and `effort_defaults.default` from the SSOT (`check05:121-131`); only its PASS message literal at `:189` is stale. |
| :249, :276-277 | "Agent Teams run BOTH launcher tracks"; "definitions are shared by both launcher tracks". | The two-track world is gone. The file's own `:330-337` says so. |
| :255-256 | The conditional-doc template ends "AND on the `<track>` track". | `:270-275` in the same file names exactly that conjunct as the defect. |
| :263-265 | `model-classification.json` "still lists [rules/research-subagents.md] in review, … a dead path". | `templates/model-classification.json:24` lists `.claude/skills/research-subagents/SKILL.md`, which exists. The claim is stale. |
| :295-296 | Case C: "remove `--model <id>` from the eval-track function (2 refs, ~lines 306/310)". | There is no eval-track function. `--model` sits at `~/.zshrc:498,502` inside `claude()`. |
| :298-299 | Case C example `--from-to claude-fable-5 claude-opus-4-8`. | The fallback is Opus 5.5 now. The example teaches the wrong target. |
| :339-350 | Appendix census lists `bin/cc-offload:87`, `scripts/lib/cloud-create.sh:116`, `scripts/capacity-ramp.sh:51`, `hooks/model-permission-decider.py:93` and the two mcp probes as **SILENT `.claude-220` pins**. | All were converted to the `bin/cc-claude-bin` resolver. Their own comments say "This line read ~/.claude-220". Still literal: `bin/cc-notify:754` ("2.1.220+" in an error string) and the `bin/cc-reaper:3238-3240` fixtures. Backlog `e8b753cac339` looks discharged. |
| :335-337 | "There is no second lane still running the old binary". | `claude-prev` / `cc-prev` still launch 2.1.114 via `claude-latest` (`~/.zshrc:133-150`). It is not the fleet lane, but it exists. |
| :363-367 | The bump procedure omits the resolver. | `bin/cc-claude-bin` reads the `_bin` line, so only `~/.zshrc` needs the repoint now. |

**`skills/cc-version-audit/SKILL.md`**

| Line | Claim | Reality |
|---|---|---|
| :3 | Description: "(claude-next or the pinned stable)". | `claude-next` was deleted by consolidation v2 (`check05:162-164` asserts it is absent). This string is in the listing, so it pollutes description matching. |
| :9-11 | "Two tracks: eval (`~/.claude-<NNN>`) and pinned stable (`claude`/`cc` → `~/.claude-versions/`)". | `claude`/`cc` → `~/.claude-280` directly. `~/.claude-versions` backs only `claude-prev`/`cc-prev`. |
| :25-26 | "`claude --version` reports the STABLE pin's number even inside an eval-track session". | The premise is two-track. `claude` *is* the fleet pin now. |
| :32 | `.claude-183 ⟹ eval/2.1.183`. | A hardcoded version, which the file's own `:16-21` calls "a bug in this file". |
| :39 | `cat ~/.claude-versions/current` as the target baseline. | That only reads the legacy lane. The fleet version is `bin/cc-claude-bin`. |
| :58 | Absolute `/Users/chrisren/.claude-versions/MANIFEST.jsonl`. | Should be `$HOME`-relative. |
| :67-73 | Static held-open issue table (#84974, #85264, #85015, …). | A perishable list copied into the runbook. The 2.1.280 MANIFEST rows record the revisit legs as discharged or open, so the table should be read from MANIFEST. |
| :147-150 | `DISABLE_AUTOUPDATER=1` "exported by the launcher (`~/bin/claude-latest`, ~line 333)". | The fleet launcher sets it inline in `claude()` (`~/.zshrc:498`). `claude-latest` is the legacy lane. |
| :151-158 | MANIFEST `candidate` "TRIGGERS the advance". | True only for `claude-latest`. The 2.1.280 MANIFEST row itself says status stayed `skip` while the fleet advanced, so MANIFEST no longer gates the fleet. `model-upgrade:365-367` agrees. |
| :162-171 | Step 6 pre-flight: a hand smoke of TeammateIdle/SessionStart/shutdown; "update Explore = Haiku ~70× in `research-subagents.md`". | Superseded by gate checks #7/#10/#11. The Explore line is also outdated: `opus55-utilization/README.md` pins Explore to Haiku explicitly, and `research-subagents.md` as a rules file is gone. |
| :189-193 | Output "VERDICT … per track"; "Never advance a track without the Step 6 gate". | Two-track framing, and Step 6 is superseded by `/cc-upgrade-gate`. |

**`skills/cc-upgrade-gate/SKILL.md`**

| Line | Claim | Reality |
|---|---|---|
| :42 | Example `~/.claude-219/… claude-opus-5`. | Two pins stale. |
| :57-77 | "THE 14 CHECKS". The table stops at #14. | There are **15** files; `check15_depth_effect.sh` is missing from the table. `45…:22` reports "14 pass · 0 fail · 1 skip" = 15. The script header `cc-upgrade-gate.sh:14` repeats "14". |
| :67 | #4 rationale: "opus-5's curves peak medium/xhigh". | Model-specific. Opus 5.5 defaults to `medium` (`45…:51-55`). The rung set should come from the model's facts. |
| :75 | #12: "`cc-next` routes a resumable session to the `claude-next` eval-track launcher". | `check12_resume.sh:13-18` was retargeted 2026-08-01 to `cc` → `claude --resume`; `cc-next`/`claude-next` are deleted. |
| :102-108 | Activation is `10-opus5-activate.sh`, with `REPOINT_NEXT=1` "repoint the everyday claude-next launcher". | That script is spent (`10-opus5-activate.sh.done`) and targets the deleted `claude-next` (`10-opus5-activate.sh:11-13,89,228-229`). The live precedent is `45-opus55-cc280-activate.sh`. There is no generic activation script: each run writes its own. |
| :113-115 | "accepting a <1-day binary soak on the shared 2.1.219 track (rollback floor 2.1.217)". | Dated literal. |
| :133-142 | Sibling relation: "GREEN activation via `10-opus5-activate.sh` → `model-upgrade` sweeps". | Both halves are stale, as above. |

**Outside the skills, noted because the merge touches them:**

- `scripts/cc-upgrade-gate.sh:14,19`.
- `check05_launcher.sh:189`.
- `check04_effort.sh:4-7,30`.
- The MANIFEST 2.1.280 notes still say "the EVAL TRACK is advancing". That is data, so leave it.
