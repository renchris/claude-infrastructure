# Design one: merge the three upgrade skills into `claude-code-upgrade`

Scope: `skills/model-upgrade`, `skills/cc-version-audit`, `skills/cc-upgrade-gate` (claude-infrastructure
main @ 9eb533126; the worktree copies are byte-identical, checked with `diff -q`). This note is read-only
analysis. Nothing was edited or moved.

## Verdict

**Merge them.** Make one skill, `claude-code-upgrade`: a short router `SKILL.md` plus flat sibling files
that the router tells the model to Read at the phase that needs each one. The case for merging does not
rest on line count. Line count barely moves when both changes arrive at once. The case rests on four
measured defects in the current split:

1. **Nobody agrees which skill is the entry point.** `model-upgrade` says it is. Its § The binary gate
   (model-upgrade/SKILL.md:137-155) runs `/cc-version-audit` as gate 1 and `/cc-upgrade-gate` as gate 3.
   `cc-upgrade-gate` says the reverse: model-upgrade is "the mechanical doc/config reference sweep that
   follows a GREEN activation" (cc-upgrade-gate/SKILL.md:137-142). A model loading either one gets a
   different running order.
2. **A model event is always a binary event.** model-upgrade/SKILL.md:42-44 says so itself: we pin
   Claude Code, so a new model id is dispatchable only on a newer binary. Both precedents on record
   (Opus 5 needed 2.1.219, Opus 5.5 needed 2.1.280 per activation 45:10-13) went through all three
   skills. The skills are three stages of one pipeline, not three separate tasks.
3. **Harness-feature adoption has no home.** None of the three covers "measure feature X and decide
   whether to adopt it". cc-version-audit asks whether the whole binary is safe, and cc-upgrade-gate
   asks whether the existing ways of working still run. The Opus 5.5 run did feature adoption by hand
   (`docs/research/opus55-feature-adoption-2026-09-22/`: Workflow concurrency 12, `omitClaudeMd`,
   per-turn effort, time budgets). The effort sweep (`opus55-effort-sweep-2026-09-22/`) and the
   equal-tools synthesis re-probe (`opus55-synth-reprobe-2026-09-22/`) were also by hand. Only the
   facts-extraction step made it into a skill (model-upgrade:12-38).
4. **Stale claims are duplicated across skills.** The two-track world and the MANIFEST-as-lever claim
   appear in two skills and were corrected in only one of them (see § Stale claims). One tree gives one
   place to fix.

Cost today (estimated as chars/4 via python `len()`): loading all three bodies costs about **13.8k tokens**
(7.4k + 4.0k + 2.4k; 55,624 bytes by `wc -c`). The three listing descriptions take **732 chars**
(235 + 250 + 247). One description of about 220 chars saves about 510 listing chars in every session,
whether or not the skill is used.

## Resulting tree

The layout is flat on purpose. `scripts/deploy-parity-assert.sh:672-673` scores `skills/*/*/*` as
`want=0` and `skills/*/*` as `want=1`. A `reference/` subdirectory would deploy, because install.sh:876-884
is recursive, but the parity assert would never check it. Keep every file one level down.

```
skills/claude-code-upgrade/
  SKILL.md        router + mandate + invariants + output contract          ~100 lines
  audit.md        binary HOLD/ADVANCE: live-runtime detect, CHANGELOG slice,
                  3-axis + adversary fan-out, churn/age-since-publish, MANIFEST
                  as LEDGER                                                 ~130
  holds.md        the PERISHABLE half: standing-hold issue table + reso
                  landmines ledger (edited every audit; kept apart so the
                  procedure files never restate a version)                  ~45
  gate.md         scripts/cc-upgrade-gate.sh: run line, the 15 checks,
                  GREEN => activation-script pattern, RED => PARK, rollback  ~85
  model.md        release materials fetch, registration probe (+control),
                  cases A/B/C/D, SSOT map, per-case steps, verification     ~170
  keying.md       detector/emitter rewrite, vacuous selftests, glob shape,
                  the single binary resolver (bin/cc-claude-bin)            ~55
  utilize.md      NEW: page-cited facts fan-out, effort sweep method,
                  role/effort assignment, equal-tools A/B rule              ~80
  feature.md      NEW: harness-feature adoption (read the binary, A/B,
                  adopt/do-not-adopt with conviction) + hidden-prompt
                  extraction (moved from cc-version-audit appendix)         ~75
                                                                    total ~740
```

What goes where (source → destination):

| Source | Destination | Change |
|---|---|---|
| model-upgrade:9-38 (Step -1, -1b, OCR rules) | utilize.md | The fetch commands stay. The fan-out method moves beside the effort sweep that consumes it. |
| model-upgrade:40-70 (Step 0) | model.md § Registration probe | Replace `~/.claude-220` with `$(bin/cc-claude-bin)` for the live binary and `<candidate>` for the new one. |
| model-upgrade:72-135 (cases, Case D, SSOT map) | model.md | Case D item 2 drops the stale check05 bullet (see stale list). |
| model-upgrade:137-171 (§ binary gate, 7 gates) | SKILL.md phase list | This becomes the router's spine. It is not a reference file. |
| model-upgrade:173-202 (keying) | keying.md | Unchanged. |
| model-upgrade:204-301 (Cases A/B/C) | model.md | Two-track wording removed. |
| model-upgrade:303-326 (verification) | model.md | The 10-line "two corrections" paragraph is deleted and the live resolver is used. |
| model-upgrade:328-367 (pin census) | keying.md, ~8 lines | Backlog e8b753cac339 is done. The pins now read bin/cc-claude-bin (see stale list). |
| model-upgrade:369-400 (invariants) | SKILL.md (1, 1b, 4, 7 as one-liners) + gate.md (6, rollback) | |
| cc-version-audit:23-44, 82-143 | audit.md | Steps 0 and 1 are rewritten for a single track. |
| cc-version-audit:46-80, 173-186 | holds.md | Tables verbatim. |
| cc-version-audit:145-171 | audit.md § Ledger | MANIFEST becomes a record, not a lever. Step 6 pre-flight is replaced by a pointer to the gate checks that already prove it (#3, #7, #11). |
| cc-version-audit:195-220 | feature.md | |
| cc-upgrade-gate:13-90 | gate.md | Check #15 added, #12 corrected. |
| cc-upgrade-gate:92-127 | gate.md § Policy | `10-opus5-activate.sh` becomes "write `NN-<slug>-activate.sh` on the pattern of 45". |
| cc-upgrade-gate:129-142 (RELATION) | deleted | The router replaces it. |

Content that exists only in the three old skills shrinks from 762 lines to about 585. The remaining
~155 lines are new (utilize.md, feature.md) and cover work that was done by hand on 2026-09-22.

## SKILL.md router (the ~100 lines)

1. Frontmatter (below). Mandate, one line, quoted from cc-upgrade-gate:15: "upgrade immediately IF all
   our ways of working continue to work".
2. **Live facts first. The skill never restates them.** Read four things live:
   - `bin/cc-claude-bin` for the binary in service;
   - `npm view @anthropic-ai/claude-code dist-tags --json`;
   - `yq .versions ~/.claude/model-config.yaml`;
   - the last MANIFEST row that carries `REVISIT`.

   A version literal anywhere in the tree is a lint failure (see migration step 6).
3. **Classify the lane** from `$ARGUMENTS`. A keyword wins. Without one, the router infers from the
   argument shape: an anthropic.com/claude-* URL or a `claude-*` id means MODEL; a semver or a feature
   name means HARNESS; both kinds of argument mean BOTH.
4. **Phase table.** Each row names the file to Read in full before the phase starts:

| Phase | model | harness | both | Read before starting |
|---|---|---|---|---|
| P1 registration probe: new id vs live binary and candidate, with positive control | yes | no | yes | model.md § Registration |
| P2 should the binary advance? (CHANGELOG, holds, churn) | only if P1 says staged | yes | yes | audit.md, holds.md |
| P3 candidate onto disk in a new `~/.claude-<NNN>`, old prefix untouched | only if staged | yes | yes | audit.md § Install |
| P4 **one** gate run: `cc-upgrade-gate.sh <candidate> <model> next next2 next3 next4` | yes | yes (current model) | yes: **one run certifies both** | gate.md |
| P5a release facts + effort sweep + role/effort assignment | yes | no | yes | utilize.md |
| P5b feature A/B and adopt/do-not-adopt | no | yes | yes | feature.md |
| P6 activation script (`_bin` and `--model` in one reversible script, the 45 pattern) | yes | only if binary moves | yes | gate.md § Policy |
| P7 SSOT flip, case A/B/C/D, keying rewrite, lint | yes | no | yes | model.md, keying.md |
| P8 MANIFEST ledger row, memory entry, output | yes | yes | yes | audit.md § Ledger |

   P5a and P5b only read and measure. For BOTH they run in parallel as one Workflow.
5. **Invariants,** one line each:
   - never write an id the live binary cannot dispatch;
   - a staged id is not a routed id;
   - registration, entitlement and plan inclusion are three separate checks, and "NOT STATED" is a
     recorded answer;
   - a green audit never stands in for the gate;
   - never `claude-bump-models --apply` while staged;
   - a zshrc repoint reaches new shells only (census `ps` before the flip).
6. **Output contract.** Give a one-line verdict per lane, then the list of files read. The model must
   name each file it Read. That makes a skipped reference visible.

## Description strings (these drive auto-load)

Only one skill ships, so only one description ships. The frontmatter below is quoted because the text
contains `: `; F7 fixed that same strict-YAML defect in cc-upgrade-gate (listings.md:103).

```yaml
name: claude-code-upgrade
description: "Adopt a new Claude model, a new Claude Code version, or a new harness feature: CHANGELOG HOLD/ADVANCE, headless ways-of-working gate, model-id/SSOT sweep, effort rungs, feature A/B. Use when a model or CC release ships."
allowed-tools: Read, Edit, Write, Bash, WebSearch, WebFetch, Workflow, Agent, AskUserQuestion, Skill
```

The description is 219 chars, measured with python `len`. The limit is 250 per F7 (F7-listing-descriptions.review.md:18).
It carries the trigger words of all three old descriptions: "new model", "Claude Code version",
"HOLD/ADVANCE", "ways-of-working gate", "SSOT sweep". It also adds the two things the operator asked for
by name, "harness feature" and "effort". The reference files have no frontmatter and never appear in the
listing.

## The single entry, per case

- **(a) New model:**
  `/claude-code-upgrade model https://www.anthropic.com/claude-sonnet-5-5 <system-card-pdf-url> <prompting-guide-url>`
  The route is P1, then P2/P3 only if the id is absent from the live binary, then P4, P5a, P6, P7, P8.
- **(b) New harness feature:**
  `/claude-code-upgrade harness "Dynamic Workflows"`
  The same entry takes a version instead: `/claude-code-upgrade harness 2.1.284`. The route is P2, P3,
  P4 (run against the current model), P5b, P6 only if the binary moves, then P8.
- **(c) Both at once (today's case):**
  `/claude-code-upgrade both https://www.anthropic.com/claude-sonnet-5-5 <card-url> <prompting-url> -- "Dynamic Workflows"`
  The route is every phase, with one P4 gate run for the candidate binary and the new model together,
  P5a and P5b in parallel, and one activation script. Today the operator typed `/cc-upgrade-gate` and
  loaded all three skills. After the merge, one command loads the router, and the model Reads each file
  at the phase that needs it.

## What gets deleted

- **In the repo, one diff:** `skills/model-upgrade/`, `skills/cc-version-audit/`, `skills/cc-upgrade-gate/`.
  Use `git mv` of each SKILL.md to its new file so `git log --follow` keeps the history.
- **Live, outside the repo:** `~/.claude/skills/{model-upgrade,cc-version-audit,cc-upgrade-gate}/`.
  install.sh:854 only touches names present in the repo, so these directories stay behind with dangling
  `SKILL.md` symlinks. One live tree serves all five config dirs: secondary, tertiary, quaternary and
  next all symlink to `~/.claude/skills` (measured with `readlink`). Removing these directories is an
  operator-approved step outside the repo.
- **Not deleted:**
  - `scripts/cc-upgrade-gate.sh`, `lib/cc-upgrade-gate/`, `tests/cc-upgrade-gate.bats` and the
    nightly-regression unsafe declaration (nightly-regression.sh:291, 886). The script keeps its name.
  - The activation scripts, `~/.claude-versions/MANIFEST.jsonl`, and all research docs. Research docs
    are historical and preserved.

## Migration steps

1. Wait until the Sonnet 5.5 / 2.1.284 run in progress has finished. Changing a runbook while it is
   being executed is the one timing hazard.
2. In a worktree: `git mv` the three SKILL.md files to `audit.md`, `gate.md` and `model.md`. Split out
   `holds.md` and `keying.md`, write the router `SKILL.md`, and write `utilize.md` and `feature.md` from
   the opus55 research READMEs.
3. Fix every stale claim listed below during the move. Do not carry any of them into the new files.
4. Repoint live references, in the same diff:
   - `scripts/claude-lint-models.sh:47` names `model-upgrade/SKILL.md § Downgrade`. That section does
     not exist; the real one is "Case C — Downgrade / window-end". Point it at `claude-code-upgrade/model.md § Case C`.
   - `scripts/claude-lint-models.sh:117`.
   - `scripts/cc-upgrade-gate.sh:137` ("see cc-upgrade-gate skill").
   - `hooks/pre-session-validate.sh:51`.
   - `hooks/agent-teams-enforce.sh:533`.
   - `model-config.yaml:437, 699, 1342-1343`. Leave 657 and 672 alone: they are historical records.
   - The skill lists in `README.md` and `docs/README-reference.md`.
   - Leave `tools/hero-film/panes.js:374`, `skills/LOCAL_ONLY.md:73` and `docs/research/**` alone as
     historical.
   - 13 memory files in the claude-infrastructure memory store name the old skills (grep count). Those
     are session-memory records; annotate them instead of rewriting them.
5. Fix the stale gate-script comments in the same diff:
   - `scripts/cc-upgrade-gate.sh:14` says "14 checks";
   - `scripts/cc-upgrade-gate.sh:19` has a `~/.claude-219 … claude-opus-5` example;
   - `lib/cc-upgrade-gate/check05_launcher.sh:12` and `:189` label strings still say
     `claude-opus-5` / `high`, although the check has read the SSOT since :130-143.
6. Add `tests/claude-code-upgrade-skill.bats` with four checks:
   - every file the router names exists, and every sibling file is named by the router;
   - the description is 250 chars or fewer and parses as strict YAML;
   - no `\.claude-[0-9]{3}` or `2\.1\.[0-9]{3}` literal appears outside a line marked historical;
   - no `claude-next` or `cc-next` appears outside a line marked historical.

   This turns cc-version-audit:16-21 ("a hardcoded current-version anywhere below is a bug in this
   file") into a gate instead of a plea.
7. Run `/ship`, then deploy-live. install.sh links the new directory.
8. Operator step: `rm -r` the three old live skill directories (see What gets deleted).
9. Run an auto-load probe: headless `claude -p` with six phrasings, two per old skill ("should we
   upgrade Claude Code", "Sonnet 5.5 shipped", "do our ways of working still work on 2.1.284", …).
   Assert that `claude-code-upgrade` is invoked in each transcript, and that the phase-1 Read of the
   named file happens.

## Stale claims (current files, file:line)

cc-upgrade-gate/SKILL.md
- :42 — example `~/.claude-219/... claude-opus-5 next next2 next3 next4`. Both values are two binaries old.
- :57, table :62-77 — "THE 14 CHECKS". There are **15**: `lib/cc-upgrade-gate/check15_depth_effect.sh`
  exists (GH #84974 effect-side), and README.md:114 already says 15.
- :76 — check #12 "`cc-next` routes a resumable session to the `claude-next` eval-track launcher".
  check12_resume.sh:13-18 was retargeted on 2026-08-01 to `cc` → `claude --resume`, and both names are
  gone after consolidation v2.
- :104, :107 — activation uses `~/.claude/autonomy/pending-activation/10-opus5-activate.sh`. That
  script is spent: `10-opus5-activate.sh.done` exists. The latest precedent is
  `45-opus55-cc280-activate.sh`, which is model-specific, and no generic activation script exists.
- :106-107 — `REPOINT_NEXT=1` "repoint the everyday claude-next launcher". That launcher was deleted.
- :114-115 — "accepting a <1-day binary soak on the shared 2.1.219 track (rollback floor 2.1.217)" is a
  frozen version pair.
- :133-142 — the RELATION section puts model-upgrade AFTER activation, which contradicts
  model-upgrade:137-155 (see Verdict point 1).

cc-version-audit/SKILL.md
- :3 — the description names "claude-next or the pinned stable". claude-next is deleted.
- :9-11 — "Two tracks: an eval track … and a pinned stable track (`claude`/`cc` → `~/.claude-versions/`)".
  There is one track now: `claude()` runs `_bin="$HOME/.claude-280/…"` directly (~/.zshrc:496).
- :25-27 — "`claude`/`cc` are shell functions resolving the stable-pinned launcher, so `claude --version`
  reports the STABLE pin". The launcher no longer goes through the stable pin.
- :32 — duplicate of :30 with a frozen `.claude-183 ⟹ eval/2.1.183` example.
- :39 — `cat ~/.claude-versions/current` fails with "Is a directory" (measured). `current` is a symlink
  to `2.1.114`, the legacy pin, not the running 2.1.280.
- :146-158 — "Two INDEPENDENT guards hold the pin … a `candidate` entry TRIGGERS the advance". This is
  true only of legacy `bin/claude-latest`. model-upgrade:365-367 already says the live launcher bypasses
  MANIFEST, and the 2.1.280 MANIFEST rows stayed `skip` while the fleet ran 2.1.280.
  `DISABLE_AUTOUPDATER` is cited at "~line 333" of claude-latest; it is now :342, and the live export
  is ~/.zshrc:498 and :500.
- :168-171 — Step 6 points at the "Explore = Haiku" assumption "in `research-subagents.md`". That rules
  file is gone (model-upgrade:263-265). The pre-flight items at :164-168 duplicate gate checks #3, #7 and #11.
- :190 — the output verdict is "per track".

model-upgrade/SKILL.md
- :47 and :312 — hardcoded `~/.claude-220/…/claude.exe` for "the PINNED one". The live pin is
  `.claude-280` (~/.zshrc:496), `.claude-284` is on disk, and :325 concedes the path goes stale. Use
  `bin/cc-claude-bin`.
- :106-107 — says `lib/cc-upgrade-gate/check05_launcher.sh` "hardcodes both `--model` and `--effort`, so
  any repoint reds the gate". That is fixed: check05:123-143 reads `opus_latest` and `effort_defaults`
  from the SSOT.
- :249-250 — "Agent Teams run BOTH launcher tracks (eval-track teams empirically fine since 2.1.156)".
- :255-256 — the conditional template "on the <track> track". Its own :270-275 warns that a named
  deleted track reads as "tier unavailable".
- :276-279 — "definitions are shared by both launcher tracks".
- :295-296 — Case C: "remove `--model <id>` from the eval-track function (2 refs, ~lines 306/310)".
  The site is `claude()` `${CLAUDE_NEXT_MODEL:-claude-opus-5-5}` at ~/.zshrc:498 and :500.
- :339-361 — the pin census lists 6 live `.claude-220` pins "SILENT if left stale". These are fixed:
  bin/cc-offload:86-93, scripts/capacity-ramp.sh:51-56, hooks/model-permission-decider.py:95-113,
  scripts/lib/cloud-create.sh:116 and both mcp-modal probes now resolve through `bin/cc-claude-bin`. The
  remaining literals are `bin/cc-notify:754` ("2.1.220+" in a message) and `bin/cc-reaper:3238-3240`
  fixtures (the census cites :2766-2768).
- :357-361 — "Filed as backlog e8b753cac339 … the actual fix — giving them one resolver". That fix
  landed (bin/cc-claude-bin). :363-367 still says "sweep every pin above".
- Cross-repo, not in the skill: `templates/model-classification.json:24` points at
  `.claude/skills/research-subagents/SKILL.md`. None of the three upgrade skills is classified, so
  `claude-bump-models` never sweeps their prose.

## Risks

1. **Auto-load coverage.** One 219-char description has to catch three trigger families that used to
   have 732 chars. Mitigation: migration step 9's six-phrase probe, run before step 8 deletes the live
   old directories, so a miss can be rolled back.
2. **Reference skipping.** The whole design depends on the model actually Reading `audit.md` and the
   others when the router says so. Mitigation: each phase row names its file, and the output contract
   requires a list of files read, so a skip shows up in the output. This works only because recent
   models follow literal instructions. It is unmeasured for Sonnet 5.5; the probe in step 9 is the
   measurement.
3. **A pure audit loads more than before.** `/claude-code-upgrade harness <ver>` with no feature loads
   SKILL + audit + holds + gate, about 360 lines, against 220 for cc-version-audit alone (estimated from
   the budgets). That is the price of the gate becoming mandatory on that path, which model-upgrade:152-155
   already demands.
4. **BOTH barely shrinks.** Today's case loads about 740 lines against 762 (budget estimate). The win is
   ordering, one gate run and no contradictions, not tokens. Lane (a) with the id already registered
   (about 405 lines) and lane (b) with a feature (about 435 lines) are where the load drops.
5. **Old slash names disappear.** `/model-upgrade`, `/cc-version-audit` and `/cc-upgrade-gate` stop
   resolving, and the 13 memory files plus the operator's habits still use them. Do not add alias stubs:
   each stub is a new listing entry and undoes the saving. The description's trigger words carry the
   match instead.
6. **The dangling-symlink window.** Between deploy-live and the operator's `rm -r`, the three old live
   directories hold dangling `SKILL.md` links. How the harness treats a dangling SKILL.md was not
   measured. Keep the window short, or have the migration diff leave a one-line tombstone for one deploy.
7. **Nested-file parity.** If someone later moves the siblings into `reference/`, deploy-parity-assert
   silently stops checking them (deploy-parity-assert.sh:672). The bats test in step 6 should pin the
   flat layout.
8. **Moving the runbook mid-run.** Merging while the Sonnet 5.5 / 2.1.284 run is using the old skills
   would split one upgrade across two runbooks. Migration step 1 gates this.
