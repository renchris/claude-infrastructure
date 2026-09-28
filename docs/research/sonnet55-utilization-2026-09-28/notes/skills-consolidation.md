# Upgrade skills: final consolidation recommendation (2026-09-28)

Judges three design notes (`skills-design-one.md`, `skills-design-front-door.md`,
`skills-design-lifecycle.md`) against the operator's question: *"should we consolidate our skills
into one? Sometimes we upgrade Claude Code for a new harness feature (Dynamic Workflows),
sometimes for a new model (Sonnet 5.5)."* Read-only survey of `claude-infrastructure` main @
`9eb533126`. The only write is this file. Nothing was edited, moved or landed.

## 1. Verdict

**Consolidate into ONE skill, `cc-upgrade`.** It has a router `SKILL.md` and flat sibling files
organised by **trigger lane** (model / harness / both), so each lane reads only its own files.
**Conviction 80%** that one skill beats keeping three. **70%** that this exact file split is right;
the split is cheap to adjust after the first real run.

**Winner: design "one"** for its structure: files keyed to the trigger, a phase table per lane, and
a bats test plus an auto-load probe. Grafted onto it:

- from **lifecycle**: the name and description style, the one-run-directory contract, a probe per
  adopted feature, and the per-family effort ladder in check04;
- from **front-door**: `bin/cc-model-registered`, the run ledger, compaction fit as a design
  constraint, and its Case D / MANIFEST facts, which "one" got wrong.

Three corrections apply to all three designs (§4.3).

## 2. Why one skill: the evidence

1. **A model release is a binary event under our pin. Four for four now.**
   - Opus 5 needed 2.1.219.
   - Fable 5.1 needed ≥2.1.253 (`model-upgrade/SKILL.md:67-70`).
   - Opus 5.5 needed 2.1.280 (`45-opus55-cc280-activate.sh:10-13`).
   - **Sonnet 5.5 is the fourth. Measured this session** with a Python `mmap` byte count over each
     binary: 2.1.280, the live pin at `~/.zshrc:496`, holds `claude-sonnet-5-5` **0 times**, with
     the `claude-opus-5` control at 120. 2.1.284 holds it 24 times (control 139).

   So "new model" almost always means "both". The two triggers are two entry lanes into one
   pipeline, not two separate jobs.
2. **The three skills disagree on the running order.**
   - `model-upgrade/SKILL.md:137-155` makes cc-version-audit gate 1 and cc-upgrade-gate gate 3.
   - `cc-upgrade-gate/SKILL.md:133-142` says model-upgrade is "the mechanical … sweep that follows
     a GREEN activation".
   - `cc-version-audit/SKILL.md:162-171` redoes gate checks #3, #7, #10 and #11 by hand.
3. **Auto-load overlap.** "Upgrade Claude Code" or "new model" matches all three descriptions,
   and today's run loaded all three.
   - Bodies: 29,644 + 15,896 + 9,545 = **55,085 chars** (measured, python `len`). That is about
     **13.8K tokens** (estimated at chars/4).
   - Descriptions: 235 + 250 + 247 = **732 chars** of listing in every session (measured).
4. **Compaction truncates the largest body.** Per code.claude.com/docs/en/skills, re-attach after
   compaction keeps the first 5,000 tokens of each invoked skill, inside a 25,000-token shared
   budget. model-upgrade is about 7.4K tokens (estimated, chars/4), so the cut falls near **line
   271** (estimated: char 20,000). After a compaction the model keeps Steps 0-1 and loses the rest
   of Case B, Case C, Verification, the pin appendix and all seven Invariants.
5. **The operator's second question has no home.** "When to use which model at what effort" and
   "adopt harness feature X" were done by hand in `docs/research/opus55-{utilization,effort-sweep,
   synth-reprobe,feature-adoption}-2026-09-22/`. Only the facts-fetch step reached a skill
   (`model-upgrade:12-38`).

## 3. Scoring the three designs

Scale is 1-5, judged on the brief's five criteria.

| Criterion | one | front-door | lifecycle |
|---|---|---|---|
| (1) One obvious entry per trigger | **5**: one skill, lane as an argument | 3: a front door, but three siblings stay as competing entries | **5** |
| (2) Context cost when loaded | **4**: reads are lane-precise; listing about −513 chars | 2: +1 listing entry. Its 4 descriptions measure 313/231/288/253 chars (python `len`), so **three fail `tests/skill-listing-budget.bats` DESC_MAX=250**, and it adds a 237-char `when_to_use`. Case (c) only −12% (its estimate) | 3: phase files mix lanes, so every lane reads the other lane's sections. Listing about −489 |
| (3) Auto-load precision | 4: the lane table picks the files. Its description lacks the operator's own phrase | 2: overlapping sibling descriptions still load directly; the note concedes this | 4: best description (the operator's words), but lower precision inside the body |
| (4) Keeps every hard-won rule | 3: **drops the MANIFEST lever** on a false "one track" premise, **drops the check05 Case D hazard**, "one gate run certifies both" | **5**: keeps all of it, moves invariant 6 to audit, keeps the check05 Case D residual, turns Step 0 into code | 4: scopes MANIFEST correctly, but moves Case D to an on-demand `reference.md` (the silent-failure case goes off the hot path) and misses the check05 residual |
| (5) Migration risk | 3: deletes three names with no stub; dangling live symlinks | **4**: renames nothing, but four copies must now agree (drift) | 3: same as one |
| **Total** | **19** | 16 | 19 |

It is a tie with lifecycle on points. "one" wins on (2) and (3), the criteria the operator raised,
because its files follow the trigger. Its (4) defects are wrong facts, and a graft fixes them. A
structural defect would not be fixable that way.

## 4. Grafts, rejections, corrections

### 4.1 Taken

| From | Graft |
|---|---|
| lifecycle | Name `cc-upgrade` (keeps the `cc-` prefix convention; `/cc-upg` autocompletes for someone used to typing `/cc-upgrade-gate`). A description in the operator's own words. **One run directory** `docs/research/<slug>-<date>/` with a fixed layout, instead of the four sibling dirs Opus 5.5 left. **A feature being adopted gets its own `lib/cc-upgrade-gate/checkNN_<feature>.sh` before activation**: the 15 checks prove no regression, not that the new feature works here. **check04's ladder should be per family**: today it hard-asserts high/xhigh/max (`check04_effort.sh:30-40`). Vendor notes say Sonnet 5.5 has xhigh, so it passes now, but that holds by luck, not by design. |
| front-door | **`bin/cc-model-registered <id> [--bin PATH]`**, which turns Step 0 into code. It resolves through `bin/cc-claude-bin`, byte-counts with a `claude-opus-5` positive control, and exits 0/1/2 for present/absent/instrument-broken. Use `mmap` rather than `strings` (the feature-adoption README measured `strings` over 217 MB at minutes). **A run ledger** `UPGRADE.md` in the run dir, one row per phase, written before the next phase starts; this is how the run resumes after a compaction. **Compaction fit** as a hard budget: the router must stay under 5,000 tokens. **Invariant 6** (a rollback drops binary-resident capabilities) goes to `audit.md`. **The Case D check05 residual** (below). |
| one | Lane-keyed flat files, P-numbered phase table, `holds.md` split out as the only place dated facts may live, the router bats test, and the six-phrasing auto-load probe before any old directory is removed. |
| new (this note) | **Alias stubs with `disable-model-invocation: true`** for the three old names, kept for one upgrade cycle. The docs' invocation table says such a skill's "description [is] not in context", so a stub costs the model's listing nothing. It keeps the operator's typed `/cc-upgrade-gate` working. install.sh never prunes (`install.sh:854`) and would otherwise leave dangling live `SKILL.md` links. All three designs said "no stubs" because of listing cost, and that premise is false for this flag. |

### 4.2 Rejected

- **front-door's keep-three.** It fails the repo's listing gate as written. It adds an entry
  where the others remove two. It leaves the co-loading it is meant to fix.
- **lifecycle's phase files.** A harness-only run would read the model-release sections of
  `evidence.md`, the Case A-C flip in `activate.md` and the model half of `sweep.md`. Its claim
  "only the router plus one phase file is live" is also wrong: a Read result stays in context
  until compaction.
- **"one"'s "MANIFEST becomes a record, not a lever".** The `claude-prev` / `cc-prev` lane still
  exists (`~/.zshrc:151`, `:298`) and runs `claude-latest` against `~/.claude-versions/current` →
  2.1.114. For that lane, a `candidate` / `stable` row is still a default-deny lever. It is only
  the *fleet* pin that bypasses it.
- **"one"'s "drop the check05 bullet".** `check05_launcher.sh:132` sets the expected `--model`
  from `versions.opus_latest`, not from `roles.lead_default`. A Case D launcher repoint off Opus
  therefore still turns the gate RED. Rewrite the bullet; do not delete it.
- **`context: fork`** for the audit (front-door's next lever). The audit writes MANIFEST and can
  ask questions, and a forked subagent cannot answer a prompt. Leave it for later.

### 4.3 Corrections that apply to all three designs

1. **When the new model is not the lead model, one gate run does not certify the binary move.**
   Checks 1-4 and 7-11 all run under `GATE_MODEL` (measured, `grep -c GATE_MODEL` over the check
   files). Opus 5.5 was the lead model, so one run covered it. Sonnet 5.5 is a worker-tier lateral
   move, and the whole fleet's lead moves to 2.1.284 with it. The rule:

   > the gate runs once per model in {`versions.opus_latest`} ∪ {new id, if the model lane is on},
   > each on the candidate binary.

   Case (c) as all three wrote it would have certified 2.1.284 × Sonnet 5.5 and never tested the
   Opus 5.5 lead on 2.1.284.
2. **"Use Sonnet 5.5 to the full" is mostly a Case D.** The versions bump for Sonnet is Case A
   (`sonnet_latest`). The value is in moving `roles.*` keys (`research_worker`,
   `workflow_synthesis_worker`, `teammate_mechanical`, …) onto it at chosen effort levels. Neither
   `claude-bump-models` nor `claude-lint-models` sees a `roles.*` move (`model-upgrade:81-92`). So
   the model lane's utilization phase must end in the Case D manual emitter census, not in a green
   lint. Note also that `versions` has no `sonnet_staged` key (measured, `yq .versions`); staging
   Sonnet 5.5 creates one.
3. **A new live pin appeared today that no census has.** `bin/cc-memory-extract:55`
   `DEFAULT_CLAUDE = "/Users/chrisren/.claude-280/…"` landed in a7558326b on 2026-09-28. The
   ratchet in `tests/cc-claude-bin.bats:152-179` exists to catch exactly this. Its own `git grep`
   pattern matches the line (measured, re-running the ratchet's grep). So `keying.md` should point
   at that ratchet instead of restating a pin census, and this line needs a fix of its own.

## 5. Final file tree and descriptions

Keep it flat. `install.sh:855-883` links skill files recursively (since 2026-08-16), but
`scripts/deploy-parity-assert.sh:672` scores `skills/*/*/*` as `want=0`, so the parity check would
never see a nested file.

```
skills/cc-upgrade/                 NEW
  SKILL.md       ~110 lines  router: mandate, live facts, lane classifier, phase table, invariant spine,
                             ledger + run-dir contract, delegation, output contract   (< 5K tokens)
  audit.md       ~130        HARNESS evidence: runtime detection (fleet pin via cc-claude-bin; claude-prev =
                             legacy MANIFEST lane), target + dist-tag trap, slice floor, CHANGELOG 3 axes +
                             adversary fan-out, churn + age-since-publish, MANIFEST default-deny (scoped to
                             claude-latest), rollback-drops-capabilities invariant, install into ~/.claude-<NNN>
  holds.md        ~45        the ONLY file allowed dated facts: standing-HOLD discharge (read from the latest
                             MANIFEST REVISIT row first; table is an index) + reso landmine classes
  gate.md         ~95        scripts/cc-upgrade-gate.sh: run line, the 15 checks, GATE_SPAWN/RETRIES, gate-run
                             set rule (§4.3.1), GREEN => NN-<slug>-activate.sh on the 45 pattern (GREEN #3
                             discharges LIVE_TEST_PASSED), RED => PARK, entitlement + plan inclusion,
                             per-feature probe rule, check04 per-family ladder, check05 Case D residual
  model.md       ~165        MODEL: registration (cc-model-registered on live pin AND candidate), staged ids,
                             Cases A-D (+ "a role move is Case D"), SSOT map, per-case steps, split-fleet
                             census, verification
  keying.md       ~45        detectors vs emitters in the flip diff, vacuous selftests, glob shape, pins =
                             bin/cc-claude-bin + the tests/cc-claude-bin.bats ratchet (no census)
  utilize.md      ~85        MODEL: fetch release pack yourself, claude-api facts, no OCR on born-digital
                             cards, page-cited reader+verifier fan-out, effort sweep, equal-tools re-probe,
                             role x effort table -> SSOT (ends in the Case D emitter census)
  feature.md      ~75        HARNESS: lever list -> binary read (mmap) -> A/B one lever -> adopt/drop with
                             conviction -> wire via settings env / migration; hidden-prompt extraction
skills/cc-upgrade-gate/SKILL.md    STUB (one upgrade cycle), disable-model-invocation: true
skills/model-upgrade/SKILL.md      STUB (one upgrade cycle), disable-model-invocation: true
skills/cc-version-audit/SKILL.md   STUB (one upgrade cycle), disable-model-invocation: true
bin/cc-model-registered            NEW  ~40 lines + tests/cc-model-registered.bats
tests/cc-upgrade-skill.bats        NEW  router<->file closure, lint tokens, check count, router size
```

Total is about 750 lines of skill against 762 today (estimated from the line budgets). The saving
is not in total size. It comes per lane (estimated at chars/4 with ~73 chars/line):

| Lane | Reads | Estimate |
|---|---|---|
| harness only | router + audit + holds + gate + feature | ≈ 475 lines ≈ 8.7K tokens |
| model, id already registered | router + model + keying + gate + utilize | ≈ 500 lines ≈ 9.1K tokens |
| both | everything | ≈ 13.7K tokens, about today's 13.8K |

Other gains:

- **Listing:** −486 chars in the model's listing, from 732 to 246 (measured, python `len`).
- **Compaction:** the router, which carries every invariant, fits under the 5K-token re-attach cap.
- **Order:** it is written down once.

### Frontmatter (exact)

```yaml
# skills/cc-upgrade/SKILL.md   (description 246 chars, measured python len; single-quoted = strict YAML)
name: cc-upgrade
description: 'Upgrade Claude Code for a new model, a CC release or harness feature, or both: registration probe, CHANGELOG HOLD/ADVANCE, headless gate, activation, id/role/effort sweep, feature A/B. Use when a model ships or on "should we upgrade Claude Code".'
argument-hint: "[model|harness|both] [model-id|cc-version|feature…] [urls…]"
allowed-tools: Read, Edit, Write, Bash, WebSearch, WebFetch, Workflow, Agent, AskUserQuestion, Skill

# skills/cc-upgrade-gate/SKILL.md   (stub; body: "Renamed. Invoke Skill cc-upgrade with $ARGUMENTS; lane hint: gate phase.")
name: cc-upgrade-gate
description: "Renamed: now /cc-upgrade (gate phase). Stub kept one upgrade cycle for typed habit."
disable-model-invocation: true
allowed-tools: Skill

# skills/model-upgrade/SKILL.md     (stub; lane hint: model)
name: model-upgrade
description: "Renamed: now /cc-upgrade (model lane). Stub kept one upgrade cycle for typed habit."
disable-model-invocation: true
allowed-tools: Skill

# skills/cc-version-audit/SKILL.md  (stub; lane hint: harness, audit phase)
name: cc-version-audit
description: "Renamed: now /cc-upgrade (harness lane, audit phase). Stub kept one upgrade cycle for typed habit."
disable-model-invocation: true
allowed-tools: Skill
```

The sibling `.md` files carry no frontmatter and never appear in the listing.

### Router outline (SKILL.md)

1. **Mandate** (1 line, from `cc-upgrade-gate:15`): upgrade immediately IF every way of working
   still works.
2. **Live facts, read and never restated:**
   - `bin/cc-claude-bin --explain`;
   - `yq '.versions,.roles,.effort_defaults' ~/.claude/model-config.yaml`;
   - `npm view @anthropic-ai/claude-code dist-tags time --json`;
   - the latest MANIFEST `REVISIT` row.
3. **Lane classifier.** A keyword wins; otherwise the argument's shape decides: a `claude-*` id or
   anthropic.com URL means model, a semver or feature name means harness. With a model id present,
   **always** run `cc-model-registered <id>` on the live pin:
   - exit 0 → model;
   - exit 1 → **both** (staged);
   - exit 2 → STOP (the instrument is broken).
4. **Phase table.** Each row lists the lanes it runs in and names the file to Read in full first:

   | Phase | Lanes | Read first |
   |---|---|---|
   | P1 registration | model, both | model.md |
   | P2 audit + holds | harness, both | audit.md, holds.md |
   | P3 install `~/.claude-<NNN>` | harness, both | audit.md |
   | P4 gate, run set §4.3.1 | all | gate.md |
   | P5a utilize | model, both | utilize.md |
   | P5b feature | harness with a feature, both | feature.md |
   | P6 activation script, binary first | any lane that moves the binary | gate.md |
   | P7 SSOT flip A-D + keying + lint | model, both | model.md, keying.md |
   | P8 ledger/MANIFEST/memory | all | audit.md |

   P5a and P5b only read and measure, so in the both lane they run as one Workflow.
5. **Invariant spine**, one line each, full text in the files:
   - Binary gate before classifying, with a positive control; never report a bare zero.
   - A staged id is not a routed id. Park it in `<family>_staged`; never
     `claude-bump-models --apply` while staged; `_prior` arms the lint.
   - Case and binary state are independent. A `roles.*` move is Case D and invisible to both sweep
     tools.
   - Detectors and emitters are rewritten in the same diff as the flip; prefer the glob shape.
   - One binary resolver; a new pin literal turns the ratchet RED.
   - MANIFEST default-deny guards the `claude-prev` lane; HOLD means `skip`. The fleet pin moves
     only through the activation script's `_bin` edit.
   - GREEN means activate now; any RED means PARK and relay the named check. A green audit never
     stands in for the gate.
   - Registration ≠ entitlement ≠ plan inclusion. NOT STATED is recorded as NOT STATED.
   - Binary first, SSOT second, through a worktree and /ship.
   - A zshrc repoint reaches new shells only; take a `ps` census before the flip.
   - `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` carries across every bump (#6 checks delivery, #15
     checks effect).
   - A rollback drops binary-resident capabilities.
   - Model facts come from the `claude-api` skill and the release pack.
   - This skill names no version or id as current.
6. **Ledger and run dir:**
   - `docs/research/<slug>-<date>/UPGRADE.md`, one row per phase: verdict, evidence path, sha. A
     skip gets a row with its reason.
   - **After any compaction, re-read UPGRADE.md and the current phase's file.** Read results are
     not re-attached; only this router is.
7. **Delegation.** `workflow-lean` fan-outs handle page-range readers, the CHANGELOG axes plus
   adversary, and the effort-sweep arms. The gate verdict, activation and SSOT flip stay on the
   lead.
8. **Output:** one verdict line per lane, plus the list of files Read (makes a skipped file
   visible).

### Source → destination

| Source | Goes to |
|---|---|
| model-upgrade:9-38 | utilize.md |
| model-upgrade:40-121 | model.md |
| model-upgrade:123-135 | model.md (SSOT map) |
| model-upgrade:137-171 | the router's phase table. The "sizing / dist-tag / rollback" text (:157-171) goes to audit.md, with the dist-tag trap kept as a single copy |
| model-upgrade:173-202 | keying.md |
| model-upgrade:204-301 | model.md, two-track wording removed |
| model-upgrade:303-326 | model.md verification. The "two corrections" paragraph is deleted |
| model-upgrade:328-367 | keying.md, ≤8 lines pointing at the resolver and the ratchet |
| model-upgrade:369-400 | router spine, with the long forms in model.md, gate.md and audit.md (#6) |
| cc-version-audit:23-44, 82-171 | audit.md. Step 6 becomes "gate #3/#7/#10/#11 prove this"; keep only the AskUserQuestion idle-timeout and the Explore re-pricing |
| cc-version-audit:46-80, 173-186 | holds.md |
| cc-version-audit:195-220 | feature.md |
| cc-upgrade-gate:7-127 | gate.md |
| cc-upgrade-gate:129-142 | deleted (the router replaces it) |

## 6. Stale claims to fix (file:line, each checked this session)

**skills/cc-upgrade-gate/SKILL.md**

- :42 — example `~/.claude-219/… claude-opus-5`. The live pin is `.claude-280` (`~/.zshrc:496`),
  and `.claude-284` is on disk.
- :57 and the table at :62-77 — "THE 14 CHECKS". There are 15 check files (`ls
  lib/cc-upgrade-gate/check*.sh`). The #15 depth-effect row is missing.
- :67 — the #4 rationale is Opus-5-specific ("curves peak medium/xhigh, `max` over-thinks"): a
  model fact that expires, sitting in a policy file.
- :75 — #12 "`cc-next` routes … to the `claude-next` eval-track launcher". `check12_resume.sh:13-19`
  was retargeted on 2026-08-01 to `cc` → `claude --resume`.
- :104, :107 — `~/.claude/autonomy/pending-activation/10-opus5-activate.sh` is spent (`.done` dated
  2026-07-25). The precedent is now `docs/activation/pending-activation/45-opus55-cc280-activate.sh`;
  each release gets its own `NN-<slug>-activate.sh`, and the next free number is 47.
- :106-107 — `REPOINT_NEXT=1` "repoint the everyday claude-next launcher". That launcher was deleted.
- :110-116 — "10-opus5-activate.sh's header"; "shared 2.1.219 track (rollback floor 2.1.217)" is a
  frozen version pair.
- :133-142 — the RELATION / typical-flow section puts model-upgrade after activation, which
  contradicts `model-upgrade:137-155`.

**skills/cc-version-audit/SKILL.md**

- :3 — the description names "claude-next or the pinned stable". claude-next no longer exists.
- :9-11 — the "two tracks" wording. The names have moved:
  - `claude`/`cc` now run `_bin=~/.claude-280` directly;
  - `claude-prev`/`cc-prev` (`~/.zshrc:151`, `:298`) → `claude-latest` → `~/.claude-versions/current`
    → 2.1.114.

  Rename the tracks; do not delete the idea.
- :24-26 — "`claude --version` reports the STABLE pin's number". The premise is inverted now.
- :32 — a duplicate EXECPATH bullet with a frozen `.claude-183 ⟹ eval/2.1.183`. This breaks the
  file's own rule at :16-21.
- :33 — the `TeamCreate` ⟹ 2.1.114 heuristic. Historical only.
- :39 — `cat ~/.claude-versions/current`. `current` is a symlink to a directory (2.1.114), so `cat`
  errors, and it only ever read the legacy lane.
- :58 — hardcoded `/Users/chrisren/...` path.
- :67-73 — a static held-open issue table. The latest REVISIT row (2.1.280, 2026-09-22T19:00Z)
  records later discharges.
- :148 — `claude-latest` "~line 333". It is now :342, and the live export sits inline at
  `~/.zshrc:498,500`.
- :146-158 — "Two INDEPENDENT guards hold the pin" / "`candidate` TRIGGERS the advance". That is
  true only of the `claude-prev` lane. The 2.1.280 row at 19:38Z says `skip` while the fleet
  advanced.
- :162-171 — Step 6 duplicates gate checks. :170 points at a `research-subagents.md` rules file that
  is gone; the content now lives in `skills/research-subagents/SKILL.md`.
- :189-193 — "per track" and "never advance a track without the Step 6 gate".

**skills/model-upgrade/SKILL.md**

- :47, :312 — the probe hardcodes `~/.claude-220/…/claude.exe`, "the PINNED one". **For Sonnet 5.5
  this probes the wrong binary.** The pin is `.claude-280`, and :325 concedes the path goes stale.
- :105-107 — "check05 hardcodes both `--model` and `--effort`". This was fixed on 2026-09-16
  (`check05_launcher.sh:122-133` reads the SSOT). The residual truth: check05 keys on `opus_latest`,
  so a Case D launcher repoint still turns it RED.
- **:108-110 — "anchor `claude-bump-models:133` first; its `sed` is unanchored → `claude-fable-5-1-1`".
  FIXED:** `~/bin/claude-bump-models:130-141` is now word-boundary anchored in both the detector and
  the rewrite. None of the three designs caught this.
- :249-250 — "Agent Teams run BOTH launcher tracks (eval-track … since 2.1.156)".
- :255-256 — the template "on the `<track>` track". The same file's :270-275 names that conjunct as
  a defect.
- :263-269 — "model-classification.json still lists [rules/research-subagents.md] … dead path".
  `templates/model-classification.json:24` now lists `.claude/skills/research-subagents/SKILL.md`.
- :276-277 — "definitions are shared by both launcher tracks".
- :295-296 — Case C "eval-track function (2 refs, ~lines 306/310)". The `--model` sites are
  `~/.zshrc:498` and `:502` inside `claude()`.
- :298-299 — the example `--from-to claude-fable-5 claude-opus-4-8` teaches a fallback that has since
  moved.
- :335-337 — "There is no second lane still running the old binary". `claude-prev` still runs 2.1.114.
- :339-350 — the census of 6 SILENT `.claude-220` pins. All six now resolve through
  `bin/cc-claude-bin`. What remains:
  - `bin/cc-notify:754`, a string;
  - `bin/cc-reaper:3238-3240` fixtures (the census cites :2766-2768);
  - **NEW: `bin/cc-memory-extract:55`**, a live pin of `.claude-280` (§4.3.3).
- :357-367 — backlog `e8b753cac339`, "the actual fix — one resolver". That fix landed as
  `bin/cc-claude-bin`. "Sweep every pin above" now means only `~/.zshrc` `_bin`.
- :317-326, :330-337, :372-374 — "used to read" history paragraphs. Delete them; git keeps the
  history.

**Outside the skills; repoint or fix in the same diff**

- `scripts/cc-upgrade-gate.sh`:
  - :14 "The 14 checks";
  - :19 the example `~/.claude-219 … claude-opus-5`;
  - :137 "see cc-upgrade-gate skill".
- `lib/cc-upgrade-gate/check05_launcher.sh:12`, `:189` — labels say `claude-opus-5` / `high`.
- `lib/cc-upgrade-gate/check04_effort.sh:4-7`, `:30` — "Opus 5's ladder … high (its own default)".
- `scripts/claude-lint-models.sh:47` — "§ Downgrade"; the real heading is "Case C — Downgrade /
  window-end". Same file, :117.
- `hooks/pre-session-validate.sh:51` and `hooks/agent-teams-enforce.sh:533` — name the model-upgrade
  skill.
- `model-config.yaml`:
  - :437 names the cc-upgrade-gate skill;
  - **:1342-1346** "/model-upgrade … distinguishes the three cases" (there are four, A-D; its
    downgrade line "drop zshrc --model" is stale);
  - :657, :672, :699 are historical, so leave them.
- `templates/model-classification.json:2` — `_doc` names "the model-upgrade skill".
- `docs/README-reference.md:288` — "15 skills … cc-upgrade-gate".
- `scripts/deploy-parity-assert.sh:672` — the comment "install.sh links skills/<name>/<file>, one
  level only" is stale against `install.sh:855-883`, which has been recursive since 2026-08-16. That
  comment is why front-door concluded that a nested file "would never deploy".
- `bin/cc-memory-extract:55` — route it through `cc-claude-bin`, as the ratchet demands.

## 7. Migration

1. **Do not switch runbooks mid-run.** Finish the in-flight Sonnet 5.5 × 2.1.284 activation on the
   current skills, but apply the three facts this run needs:
   - probe `.claude-280` and `.claude-284`, not `.claude-220`;
   - write `47-sonnet55-cc284-activate.sh` on the pattern of script 45, not the spent script 10;
   - run the gate twice on 2.1.284: × `claude-opus-5-5` and × `claude-sonnet-5-5` (§4.3.1).
2. In a worktree:
   - add `bin/cc-model-registered` and its bats, covering present → 0, absent → 1, control absent →
     2, and a fixture where a naive reading would give 0;
   - `git mv` the three `SKILL.md` files to `cc-upgrade/{model,audit,gate}.md` so history follows;
   - split out `holds.md` and `keying.md`;
   - write `utilize.md` and `feature.md` from the four opus55 READMEs, keeping the method and
     dropping the numbers;
   - write the router.
3. Fix every §6 item during the move, and do not copy any of them forward. Write the three stubs.
4. Add `tests/cc-upgrade-skill.bats` with these checks:
   - the router names every sibling, and every sibling exists;
   - none of `\.claude-[0-9]{3}`, `2\.1\.[0-9]{3}`, `claude-next`, `cc-next` or `10-opus5` appears
     outside `holds.md` or a line tagged historical;
   - the check count in `gate.md` equals `ls lib/cc-upgrade-gate/check*.sh | wc -l`;
   - the router is ≤16,000 chars, a margin under 5K tokens at chars/4.

   `tests/skill-listing-budget.bats` already covers the ≤250-char description and strict YAML.
5. Land with `/ship`, then deploy-live. `install.sh` links `skills/cc-upgrade/*`, and the stubs
   overwrite the old live `SKILL.md` links, so there is no dangling-link window.
6. **Auto-load probe.** Run headless `claude -p` with these phrasings, and assert that `cc-upgrade`
   is invoked and that the Read at the first phase follows:
   - "should we upgrade Claude Code";
   - "Sonnet 5.5 shipped";
   - "adopt Dynamic Workflows";
   - "does 2.1.284 still run our ways of working";
   - "which model at which effort now";
   - "frontier access lapsed".

   This probe spawns sessions, so run it as a harness-measurement session.
7. After one full upgrade cycle on `cc-upgrade`, delete the three stubs. As an operator step, `rm -r`
   the three live `~/.claude/skills/<old>/` dirs, which install.sh never prunes.

## 8. Risks that remain

- **Sonnet 5.5 skipping reference files.** The design depends on the model Reading the named file
  at each phase. The output contract makes a skip visible, and step 6 measures it. It is
  unmeasured for Sonnet 5.5, and a Sonnet lead is plausible for a cheap harness-only audit.
- **Case (c) context is about equal to today** (≈13.7K against 13.8K tokens, estimated). Do not sell
  this as a context saving on the both-lane. The wins are ordering, the listing, compaction fit and
  a single copy of each rule.
- **A harness-only audit now loads more than cc-version-audit alone did.** That is the price of
  making the gate mandatory, and `model-upgrade:152-155` already demands it.
- **check05 still keys on `opus_latest`.** A Case D lead repoint turns it RED. This note documents
  the coupling and does not fix it.

## Measurement labels

**Measured:**

- body chars and description lengths: python `len`;
- the Sonnet 5.5 registration counts: a python `mmap` byte count over each `claude.exe`;
- `GATE_MODEL` use: `grep -c` over the check files;
- the new pin: the ratchet's own `git grep` pattern;
- the MANIFEST REVISIT row: a python read of MANIFEST.jsonl;
- `current`: `readlink`;
- the pin locations: `sed -n` on `~/.zshrc`.

**Estimated:**

- tokens: chars/4;
- per-lane loads: line budgets × ~73 chars/line;
- the compaction cut at line 271: char 20,000 ≈ 5K tokens.

**Vendor doc quotes** (compaction budget, `disable-model-invocation` context behaviour) come from
code.claude.com/docs/en/skills, fetched this session.
