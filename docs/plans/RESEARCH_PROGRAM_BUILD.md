---
status: open
---

# Research program build — tooling for the no-take-backs upfront research method

Scope (frozen): build wave 1 of the method in `docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md` §8
(items 2–8) so the next greenfield program can run it, with every §10 open item closed by a failing planted-input
test; run the calibration study (§8 item 14) in parallel; then wave 2 (items 9–13, 15) alongside the pilot.

Ruled 2026-10-01 by the operator ("Proceed as you recommend with all"): REPORT.md §9 decisions 1–9 adopted, decision
packet `83adb541ea19` actioned. Method version 1.1 is frozen; it changes only from measured results (decision 8).

## Phase 0 — Agent team orchestration

**Execution locus per wave.**

| Wave | Locus | Content | Depends on |
|---|---|---|---|
| A1 | S (dispatched session) | Items 2 + 3: zero-allowed research prompts; the standing-rule exemption in both instruction variants, `hooks/completion-assert.sh` and the live copies, keyed on the program registry (§10 open item 10) | — |
| A2 | S | Items 4 + 7: operator-only signing library; the seven-script hand-run kit and the program registry with states `registered → certifying → certified` (§10 items 1, 4, 7, 9, 13, 17) | — |
| A3 | S | Item 14: calibration study over at least 10 held-out historical plans (read-only replay). Settles decision 4 and the labeled assumptions (fix-born rate, holes at freeze, Lite/Full stage budgets, point-forecast exceedance) | — |
| B1 | S | Items 5 + 6: re-ask router, research block, polarity-independent Stop check; the settings migration as a `c10` migration the operator runs (§10 items 1–3, 8, 11–13) | A2 (registry) |
| B2 | S | Item 8: `research-program` skill, `/research-program` command, intake script, briefs, rubric | A2 |
| C | S | Wave 2: items 9–13, 15, in parallel with the pilot | B1, B2 |
| D | S (fired `fire-rp-audit-bugfix`), T inside | Audit fixes: `docs/research/upfront-method-audit-2026-10-04/REPORT.md` §3 rows 4–6 | C |
| E | E1 S (fired `fire-rp-v12-step1`); E1b S (fired `fire-rp-v12-e1b`); E1c S (fired `fire-rp-v12-e1c`); E2 Workflow in session d8964eb2; E3 S; E4 operator | Method v1.2 (ruling `1bf69e5c1775`): audit REPORT §3 rows 1, 2, 3, 7, plus the 9 s classifier limit (ruling `4bf73c4e55d5`) | D |

A1, A2 and A3 touch disjoint files and fire concurrently. B1 and B2 fire when A2 lands. Each dispatched session leads
its own Agent Team where it has 2+ code-writing tasks.

**Lead budget and succession.** The lead (the session that wrote this plan) only fires waves, collects pings, and
lands nothing itself; it recycles once A1–A3 are fired and their custody is recorded. Each wave session owns its own
worktree, gates and `/ship`.

**Acceptance rule for every wave.** Each REPORT.md §10 open item a wave owns gets a planted-input test that fails
before the change and passes after it, run in the land gate. A wave is done when its tests are green on trunk and its
items are live (converged), not when the code is written.

## Waves

### A1 — prompts and standing-rule exemption — DONE
- REPORT.md §8 item 2 (cites the exact lines) and item 3; §3.1 ruling 2.
- Key the exemption on the program registry resolution (§10 item 10), not on a DoD marker no step writes.
- Status: **landed and live 2026-10-01** (`7310c4ac8` prompts, `7cca316c0` registry lib, `a08892a16` rules,
  `b1fd89b6a` hook; converged, both live copies byte-equal to trunk). §10 item 10 closed by option 1: everything
  keys on `scripts/lib/research-program.sh` (`rp_resolve_cwd`, `rp_is_active`; registry contract in its header,
  which A2's `gate.sh` writes). Also fixed the same quota in two uncited siblings (`deep-research-sonnet.md`,
  `frontier-derivation.md`). Learnings: the land gate requires `$HOME` fixtured in every new suite and refuses
  `! ( … )` assertions errexit cannot reach; the slim variant's `derived-from` stamp was already stale and was left
  alone.

### A2 — signing library, hand-run kit, registry — DONE
- REPORT.md §8 items 4 and 7; layout per `evidence/design/SYNTHESIS.md:932-1097`.
- Registry state `certifying` set at freeze so the relay test runs with the block on (§10 item 1).
- Scope (frozen): the operator-only signing library with a research namespace (frame, cert, extra round set, reopen,
  veto) factored out of `bin/cc-signoff`; the seven kit scripts under `scripts/research-kit/` over plain records;
  registry writes (registered → certifying at freeze → certified at the gate); caps enforced in `round.sh` and
  `gate.sh`; the class-B/class-C due-date sweep; a planted-input test that fails on bad input for §10 items 1, 4, 7,
  9, 13, 17 and every implemented gate row; landed and converged.
- Layout: shared contract `scripts/research-kit/lib/kit.py` (paths, profiles and caps, registry writer, record I/O);
  `gate.sh` → `lib/gate.py` dispatching rows 1–8 to `lib/gate_rows_a.py` and rows 9–16 to `lib/gate_rows_b.py`;
  signing library `scripts/lib/operator_sign.py`. Registry env `CC_RESEARCH_REGISTRY` matches wave A1's resolver.
- Locus inside the wave: L (lead-inline). Why: the six teammate spawns were refused at the tool ("it2 CLI is not
  reachable") because kitty pid 610's remote-control socket `/tmp/kitty-610` accepted connections and never answered
  (`kitty @ ls` → i/o timeout, 2026-10-01 02:12), so no pane backend existed; code-writing subagents are not allowed.
- Status: DONE — landed `68261da7c` (rebased onto A1's land; the registry test runs against A1's resolver) and
  converged; the kit's `~/.claude/scripts/research-kit/` links follow in the install.sh class landed after it.
  11 suites, 136 planted-input tests: `tests/operator-sign.bats` (13), `research-kit-probe` (10), `-seed` (9),
  `-courier` (12), `-round` (15), `-estimate` (6), `-gate` (44), `-sweep` (13), `-heldout` (6), `-index` (3),
  `-registry` (5).
- Learnings:
  - `estimate.py simulate` is random-call faithful to `evidence/final/profile_sim.py`: lite/base/N0=10 reproduces
    `profile_sim.out` exactly (5/6 rounds, 21.8% cap, 1.43 desk, 0.54 invisible, P(any) 0.83, take-back 1.2%).
  - Real vendor preflight on this machine (2026-10-01): Anthropic and frontier live through the launcher's pinned
    binary (`~/.claude-284`; Homebrew's 2.1.278 `claude` refuses claude-opus-5-5), OpenAI live (`gpt-5.6-sol`, model id
    read from codex's session rollout, since `codex exec --json` never names it), **Google DEAD**: `gemini`'s cached
    OAuth needs interactive consent. Gemini's read-only plan mode needs `experimental.plan`, passed per call through
    `GEMINI_CLI_SYSTEM_SETTINGS_PATH`, so the operator's gemini settings are never edited.
    CORRECTED (2026-10-01): a re-login does not restore that lane. After the operator signed in, `gemini` answered
    `IneligibleTierError: UNSUPPORTED_CLIENT … migrate to the Antigravity suite`: Google retired the CLI for
    individual accounts. The Google lane is now the Antigravity CLI, `agy` (installed to `~/.local/bin` from
    antigravity.google/cli/install.sh without its shell-edit step), run `--print --output-format json --mode plan
    --sandbox`; its model id comes from its own process log (the JSON names none). A second `agy` on PATH is the
    Antigravity editor's launcher and is skipped. Live preflight after the operator's `agy` sign-in: all four
    lanes live at their pins (Google `gemini-3.8-flash-high`). The research block's vendor list gained `agy`.
  - `kit.probe_level` first let a probe whose negative control RAN AND PASSED earn its level; the probe suite's first
    planted input caught it.
  - Interactive `zsh -lic` writes terminal escape sequences onto the answer line; the doctor fences answers with
    sentinels.

### A3 — calibration study — DONE
- REPORT.md §8 item 14; §6.6 lists what it measures. Output: `docs/research/research-calibration.jsonl` and a report;
  changes to the report only as priced edits to named sections (profile table, caps, seed counts).
- Status: **DONE — landed 2026-10-01** (`72bcaf42` report draft and per-plan pooling, `21a58590` calibration over 16
  held-out plans, `72ee29cb` REPORT.md priced edits to §3.9, §3.12, §6.1 and decision 4). Output:
  `docs/research/research-calibration.jsonl` (16 rows) and `docs/research/research-calibration/REPORT.md`.
  Headline: false material calls ~1.1 per reviewer-read (assumed 0.01) and rater downgrades ~0.2 (assumed 0.05), so
  the quiet-round stop never fires at measured inputs; the 95% bound holds; Lite is the default for every size and
  Full stays off. Still uncalibrated: the router (B1), Google, multi-round behaviour (its §6).

### B1 — re-ask router, research block, Stop check, settings migration (REPORT.md §8 items 5 + 6)
Owns §10 items 1 (deny half), 2, 3, 8, 11, 12, 13 (populating the set). Reads, never writes, the registry.
- **First, before any router code (§10 item 13): seal the held-out set.** Build candidates from
  `docs/research/upfront-research-exhaustion-2026-09-30/evidence/adversary/llm/ask_turns.out`, `regex_recall.out` and
  `evidence/adversary/opscope/adv_opscope_bypass.py` (the 77 post-done prompts the regex missed), one row each
  `{prompt, stratum: regex-matched|regex-missed|pushback|other, source}`; then
  `scripts/research-kit/heldout.py seal --candidates … --tuning-out <tuning set>` (`heldout.py:1-23`; refuses fewer than
  40 sealed or a missing stratum, seals once), `rater-sheet`, and `label --rater` for two raters (two different
  vendors through `courier.sh run --role rater`). The router's builder works only from the tuning set.
- **Router** (item 5): a UserPromptSubmit branch in `hooks/research-precognition-nudge.sh` (25 lines today, advisory).
  Resolve state with `rp_resolve_cwd`/`rp_is_active` (`scripts/lib/research-program.sh`, wave A1) by working directory,
  then a program's name or alias in the prompt (aliases are in the registry, `kit.py` `registry_set`); NO single-active
  fallback (§10 item 2). Labels are exactly `heldout.py:39` `ROUTES`; `completeness` and `pushback` relay
  (`heldout.py:48`). Contract gate row 15 calls: prompt on stdin, ONE label on stdout, within 6 s
  (`heldout.py:50`, `route()` at `:173`); anything else is a fallback that routes as completeness. Point
  `CC_RESEARCH_ROUTER` at the router's classifier command to make `gate.sh run` row 15 measure it (`gate_rows_b.py`
  row 15 → `heldout.evaluate`, `heldout.py:191`).
- **Block** (item 6): PreToolUse deny keyed on `rp_is_active` AND state `certifying|certified` (§10 item 1 — `gate.sh
  freeze` already sets `certifying`, `gate_cert.py:33`; proven by `tests/research-kit-registry.bats`). The only
  whitelisted tool in a completeness turn is `scripts/research-kit/gate.sh --render --program <slug>` (`gate.sh:6-11`,
  a pure read, `gate_cert.py:237`). Allow route for contract-listed post-certificate activities (§10 item 8).
  Classifier-unavailable is distinct from a completeness label (§10 item 3): deny only the research verbs, retry on
  the next genuine prompt, kill switch.
- **§10 item 1 test (B1's half):** a completeness prompt in a `certifying` program denies Agent, Workflow,
  `handoff-fire.sh` and the vendor CLIs.
- **Stop check**: a new arm in `hooks/completion-assert.sh` (1,323 lines; the D4 offer arm is documented at `:61-81`,
  and wave A1 made it abstain inside an active program) that blocks a reply naming a row the relayed certificate
  lines do not carry.
- **Settings migration** as a `c10` migration (next free number after `migrations/0049-*`), operator-run: one
  PreToolUse entry matching every tool, Workflow included; the router hook's timeout raised to 10 s.
- Status: **landed 2026-10-01** (`19ddcc36`, plus `18fe93ba` reviving mid-test assertions; parked on-box steps
  recorded in `c047a316`). Built off-box (branch `claude/fire-20261001T094944Z-86287-1`). What exists:
  - `scripts/research-kit/router.py` — `classify` (gate row 15's contract), `prompt` (UserPromptSubmit), `tool`
    (PreToolUse), `relay-check` (Stop), `status`. Labels are `heldout.ROUTES` plus `unavailable` (§10 item 3).
    Per-session route records in `$CC_RESEARCH_HOME/route-state/` (7-day reaper, `growth-coverage.conf` row).
  - `hooks/research-precognition-nudge.sh` — the router branch: cwd, then slug/alias in the prompt
    (`rp_resolve_prompt`, added to `scripts/lib/research-program.sh` with `rp_program_state`); no single-active
    fallback (§10 item 2). Routes only in `certifying|certified`.
  - `hooks/research-block.sh` (+ `hooks/lib/research-router.sh`) — the deny; `hooks/completion-assert.sh` ARM R —
    the relay check, its own `relay` latch class, cap 2.
  - `migrations/0050-research-block-registration.sh` — the c10 migration.
  - `scripts/research-kit/heldout-candidates.py` (mines the four strata from transcripts; prints counts, never a
    prompt) and `heldout-rate.py` (one rater per vendor family through `courier.resolve`/`call`).
  - Suites: `research-router` (23), `research-relay-check` (15), `research-router-heldout` (9),
    `migration-0050-research-block` (6) — §10 items 1 (deny), 2, 3, 8, 11, 12, 13 each with a planted input.
- Decisions made in the build (no ruling needed; each is the narrower reading of the report):
  - A `research-order` while `certifying` allows the kit's own `round.sh`/`courier.sh`: certification IS the
    scheduled research of that state, and §10 item 1 turns the block on at the freeze. Agent/Workflow/vendor CLIs
    stay denied. While `certified` it allows nothing.
  - A concern, `other` and `unavailable` deny the research verbs only; completeness/pushback deny every tool but
    `gate.sh --render --program <slug>` (or `cc-research verdict <slug>`). A session with no routed prompt in a
    blocking state counts as completeness (§4.2).
  - Open activities (§10 item 8) live in `$CC_RESEARCH_HOME/activities.json`, not the registry, because
    `kit.registry_set` keeps only its four keys. Tag: `CC_RESEARCH_ACTIVITY=<id>` on the Bash clause,
    `[activity:<id>]` in an Agent description or prompt. Its writer is wave C (triage).
  - Program resolution by alias is per prompt: a pane that named the program once is ordinary again on its next
    prompt that does not.
  - Kill switches, all launch-environment only (no tool call can set them): `CC_RESEARCH_BLOCK=0`,
    `CC_RESEARCH_ROUTER=off`, `CC_RESEARCH_RELAY_CHECK=0`.
  - The router was written from the route table in REPORT.md §4.1, never from candidate prompts: the evidence
    files carry counts, and the off-box session could not mine transcripts. So the held-out set is uncontaminated.
- **On-box steps left (the cloud VM has no transcripts, keychain or vendor logins):**
  1. Operator: after the land converges, `bash ~/Development/claude-infrastructure/migrations/0050-research-block-registration.sh --confirm settings.json`.
  2. Any on-box session: `python3 scripts/research-kit/heldout-candidates.py --out /tmp/cands.jsonl`, then
     `scripts/research-kit/heldout.py seal --candidates /tmp/cands.jsonl --tuning-out ~/.claude/autonomy/research/router-heldout/tuning.jsonl` (operator prompts: kept out of the repo),
     then `scripts/research-kit/heldout-rate.py --vendor anthropic` and `--vendor openai` (Google is down until
     its login is restored), then `CC_RESEARCH_ROUTER="python3 $PWD/scripts/research-kit/router.py classify"
     scripts/research-kit/heldout.py evaluate` — row 15's first real reading of the classifier.
  - Step 2 DONE 2026-10-01 (wave C session): mined 183 candidates over 6,784 transcripts (pushback is rare: 3 mined,
    plus the 4 literal relay-test phrasings of REPORT.md:535-537, source recorded); sealed 91 (all four strata) in
    `~/.claude/autonomy/research/router-heldout/sealed.enc`, 96 in the tuning set beside it (0600, outside the
    repo); labeled by `anthropic:claude-opus-5-5` and `openai:gpt-5.6-sol` (69 agreed). **Row 15 FAILS today**:
    fallback 0.96 at load ~295 and 0.51 at load ~45-80 against the 6 s limit; correct labels on `other` 0.12 then
    0.62; completeness recall 14/14 · 3/3 · 1/1 only because a fallback routes as completeness. Cause measured: a
    cold `/opt/homebrew/bin/claude -p` on haiku takes ~2 s at load 45 and ~5 s at load 295 before the classifier
    brief; `--bare` cannot use the OAuth login; `--strict-mcp-config --disable-slash-commands` saves ~0.4 s. The
    fix changes §4.1's time limit or classifier path — a method parameter, raised to the plan's lead.

### B2 — `research-program` skill, `/research-program` command, intake (REPORT.md §8 item 8)
- Intake script: the two §3.1 rulings into `frame.json` `rulings` (`scripts/research-kit/RECORDS.md`), the contract
  page (its time into `frame.contract_page_at`, which gate row 13 requires to follow `courier.sh preflight`), and
  registration through `scripts/research-kit/gate.sh register --program <slug> --root <deliverable repo> --alias …`
  (`lib/gate.py` `cmd_register`). Run `research-index.py` before mining (`docs/research/INDEX.jsonl`).
- Program packets only through `gate.sh file-packet` (`lib/gate_sweep.py:144`), never a bare `cc-decide open`: it adds
  `--project` and class-B `--default-effect no-change` (§10 item 4), and row 12 fails any packet without them.
- Briefs: reviewer brief returns the panel JSON `courier.py` `extract_panel` reads (`{lenses:[{lens,result}], rows,
  findings}`, all 11 `kit.LENSES`, or gate row 13 fails the slot); rater, verifier and seed-author briefs.
- Operator verbs to document, all `cc-signoff research:<slug>/{frame|cert|extra-round|reopen|veto/<D>}`
  (`bin/cc-signoff` usage; namespace at `scripts/lib/operator_sign.py:143-160`).
- Restore the Google lane first: `gemini` needs one interactive login (filed as an operator step at A2's close).
  CORRECTED (2026-10-01): done; the lane is the Antigravity CLI, `agy`, signed in and live (see A2's learnings).
- Status: **landed 2026-10-01** (`0fb32f50`, plus `b5085b18` reviving mid-test assertions). Built off-box
  (branch `claude/fire-20261001T113129Z-26618-1`). What exists:
  - `scripts/research-kit/intake.py` — `init` (refuses a numberless superlative, checks the research index,
    registers through `gate.sh register`, writes the frame skeleton with FAC-01..FAC-33 and the three historical
    frames unmapped, starts the stage-1 clock), `ruling` (`--show`; `--adopt` records `{at, quote}`; `--decline`
    records no `at`, so row 1 keeps failing, and closes the program), `map` (checklist rows and historical frames),
    `set` (escape cost must be a finite number; release gap; reference days), `contract-page`, `lint` (gate row 1
    minus the signature), `status`.
  - `contract-page` refuses before both rulings, before the escape cost, and before a STRICTLY earlier vendor
    preflight (row 13's predicate); a dead lane exits 3. It writes `CONTRACT.md` (definition, signed activity list,
    profile with `estimate.py simulate` forecast and the §6.1 ceiling, escape cost, responding model ids, release
    chance, §6.3 override), pins the responding ids into `reviewer_pins`, and stores the page's sha256 in
    `frame.json`, so the operator's frame signature covers the page.
  - `skills/research-program/` — `SKILL.md` (the protocol by stage, the rails, every `cc-signoff research:` verb),
    `RUBRIC.md` (§3.11), `checklist.jsonl` (the 33 rows, generated from §3.2 step 5), `briefs/{reviewer,rater,
    verifier,seed-author}.md`. `commands/research-program.md` loads the skill.
  - Suites: `research-program-intake` (15), `research-program-briefs` (9: the reviewer brief's JSON is what
    `courier.extract_panel` reads with exactly `kit.LENSES`, with a dropped-lens mutation control; seed records
    carry what `seed.validate` checks; the checklist equals row 1's `FAC_IDS` and the report's wording; every
    signoff verb parses in `operator_sign`), and `research-zero-allowed-prompts` now scans the new briefs. Four
    intake guards mutated one at a time (strict ordering, dead lane, declined ruling, infinite cost): each mutant
    killed by its case.
- Decisions made in the build: the contract page is a file beside the frame and is pinned through its hash in
  `frame.json` (the signing library pins only `frame.json`); the §6.1 typical totals and ceilings are copied as
  printed rather than recomputed, because the report's own ceiling arithmetic is not reproducible from its formula;
  a stale `docs/research/INDEX.jsonl` is reported with its command, never rewritten by the intake (it may run from
  the shared checkout). Trunk's index was 5 entries stale at this build.

### C — wave 2: REPORT.md §8 items 9–13, 15 (in parallel with the pilot)
Depends on B1 and B2, both landed. Each item replaces a wave-1 tool or hand step named in REPORT.md §8's pilot
coverage table, keeping the kit's record formats (`scripts/research-kit/RECORDS.md`).
- **Item 9 — `bin/cc-research` core.** Does not exist on trunk. Absorbs the kit verbs over the same records: index
  (`research-index.py`), frame (`intake.py`), census, premise, source, decision, trace, reconcile, lint, freeze
  (`lib/gate_cert.py`), estimate and forecast (`estimate.py`), gate (`lib/gate.py`), verdict (B1's block already
  whitelists `cc-research verdict <slug>` beside `gate.sh --render`), concern, park, reopen, budget and ceiling.
  Caps stay in `lib/kit.py` (`CAPS`, `r_max`); records stay append-only.
- **Item 10 — probe runner, doctor, harness self-test as `cc-research` verbs**, replacing
  `scripts/research-kit/probe-run.sh` (`lib/probe_run.py`).
- **Item 11 — certification machinery as Workflows** (round, frame-critique, rehearsal), replacing `round.sh` /
  `courier.sh` (`lib/round.py`, `lib/courier.py`); raters and the responding-model check enforced in code.
- **Item 12 — scheduled launchd jobs**: the sweep (`gate.sh sweep`; `lib/gate_sweep.py:2` names launchd as its
  wave-2 runner), freshness re-checks (gate row 10), daily concern triage (also the writer of B1's
  `$CC_RESEARCH_HOME/activities.json`), rule drift, market refresh — each tested under `/bin/bash` 3.2.57.
  Loading a plist is the operator's (C10).
- **Item 13 — close integration.**
  - DONE (built off-box 2026-10-01, branch `claude/fire-20261001T141134Z-30157-1`; the desk lands it):
    `handoff-fire.sh --requires-gate <program> [--gate-wave W]` over a new kit verb
    `gate.sh requires --program P [--wave W] [--json]` (`scripts/research-kit/lib/gate_requires.py`). It refuses
    (exit 2, refusal reason `research-gate`, its own `_fire_gate_of` denominator) before any side effect, dry runs
    included, unless the registry reads `certified`, the newest certificate has no FAIL row, no valid reopen is
    signed after it, and the wave's closure holds no unresolved class-C row, carried set (exempt for the wave that
    owns its narrowing probe), open frame-omission known row, or descoped wave. It reads the LIVE decision and
    known-row records, so a sweep conversion or a closed frame-delta cycle clears the block without a reopen (§10
    item 9). Without `--gate-wave` any block refuses (fail closed). An admitted fire appends the
    `--requires-gate <slug>` marker to the fired brief, which `router.py` labels work-order without the classifier
    (§10 item 3). Suite `tests/research-kit-requires.bats` (17): red 17/17 on trunk `72ee29cb`, green 17/17 here;
    two mutants (narrowing-probe exemption dropped, descoped check dropped) each killed by its case.
    `tests/handoff-fire-capacity-gate.bats` case 31's ENUM guard maps the new reason.
  - Remaining: a program-verdict field in `scripts/wrap-ledger.sh` (its existing `GOAL_*` fields at `:154-185` are
    `/goal` liveness, a different thing; name the new one so the two cannot be confused), and an absent DoD reading
    "unknown" rather than ✅ (REPORT cites `:2286-2288`, which is now the no-trunk arm: re-locate before editing);
    a Goal line in `commands/are-we-done.md`; pending concerns and the priced menu in `hooks/operator-readout.sh`.
- **Item 15 — calibration log.** `docs/research/research-calibration.jsonl` exists (A3, 16 replayed plans).
  Remaining: reference-class timing per project type, appended as programs run.
- Status: **DONE 2026-10-01** — items 9, 10, 11, 12, 13 and 15 landed (shas per item below), B1's on-box step 2
  done (row 15 reads FAIL; see B1). Operator step left: `migrations/0051-research-jobs.sh` (loads the five jobs).
  Learnings: the land gate refuses assertions errexit cannot reach (`scripts/bats-assert-liveness-fix.py`),
  absolute future dates in fixtures (seed with `date -u -v+NH`) and a path derived from an unresolved `$0` —
  brief teammates on all three; the ruff post-edit hook reflows whole files, so shared files (`cli.py`) collide
  unless each teammate reverts the reflow.
- Landed per item:
  - Item 12 — `1f37dffbd`: `cc-research job sweep|freshness|triage|drift|market` (`lib/cli_jobs.py`), one bash 3.2
    runner `scripts/research-kit/jobs/research-job.sh`, five plists in `launchd/staged/` (install.sh would load
    anything in `launchd/`), c10 `migrations/0051-research-jobs.sh`; `tests/research-jobs.bats` 1..11, red 10/11
    on the skeleton (the 11th asserts `/bin/bash` is 3.2.57). Freshness re-validates a premise once, then carries it.
  - Item 11 — `dd4fe7050`: `lib/cli_cert.py` verbs `slots`, `open-round`, `slot` (vendor, strategy and role looked
    up in code; reruns capped by `CAPS`), `raters` (rater 1 non-Anthropic, three families; two-vendor default makes
    rater 3 a fresh rater-1-vendor process), `check-round` (voids a responding-model mismatch, a wrong-vendor rater
    or an integrity hit, exit 4; writes `matrix.json` in round.py's shape), `round`, `frame-critique`,
    `rehearse frames|record` (≥ 20 trials, zero relay violations, cert read only, one trial outside every root; a
    failed retest records "relay unstable", a third record is refused). `scripts/research-kit/workflows/
    {round,frame-critique,rehearsal}.workflow.js` call only `cc-research` verbs; a trial's cwd is orchestrated, not
    enforced (stated in the header). Rounds still close through `round.sh close`. `tests/cc-research-cert.bats`
    1..17, red 17/17. A bare `node --check` rejects every Workflow script (top-level return/await), so the suite
    compiles each body the way the runtime wraps it.
  - Item 9 — `70378a573` (skeleton `023d63d61`): `bin/cc-research` over `lib/cli.py`. State verbs (`lib/cli_core.py`):
    pass-throughs `index frame estimate gate`, `forecast`, `freeze`, single-row `trace reconcile lint`, `verdict`
    (pure read; render lines plus pending concerns, "waiting on you since", priced menu), `pending`, `menu`
    (extra round quoted as a change to the bound, never a yield), `budget start|end` (refuses the next stage while
    the last is over budget with no overrun packet — §10 item 17 in code), `ceiling`, `reopen` (refused under a
    claude ancestor). Record verbs (`lib/cli_records.py`, `lib/activities.py`): `census add|critic`, `premise`,
    `source`, `decision add|tally|rule|show` (no conviction flag; rule refused below 90), `concern add|list`, `park`,
    `triage` (blind rater, §5.2 buckets, counted buckets append `changes.jsonl`; the writer of `activities.json`,
    §10 item 8). Suites `cc-research-core` 1..22 (red 22/22), `cc-research-records` 1..10 (red 10/10).
    `waiting_since` is "unknown", not null, when cc-decide is unreadable (null would read as nothing waiting).
  - Item 10 — `34704af00`: `lib/cli_probe.py` `probe` (probe_run's own parser, so `probes.jsonl` keeps one writer),
    `doctor` (adds per-tool visible|hidden|agent-only|absent — a tool only the interactive shell sees is hidden,
    never absent — and credential expiry from `frame.json`), `self-test` (each acceptance row's check over
    known_good as the probe and known_bad as its negative control, env `FIXTURE` as gate row 6 runs it).
    `probe-run.sh` is now a bash 3.2 shim. `cc-research-probe` 1..11 (red 11/11); `research-kit-probe` 1..10
    unchanged through the shim.
  - Item 15 — `71a9643fd`: `docs/research/research-reference-class.jsonl` seeded with the 8 measured greenfield cases
    (`evidence/internal/greenfield-cases.md:29-36`, median 1.5 research days); `cc-research reference-class
    record|show|check` (`lib/cli_refclass.py`): `record` appends a certified program's stage 1–6 days per
    `frame.json project_type`, once per certificate; `check` exits 1 and prints both figures when a typical total
    exceeds 3× the type's median (§6.3), "uncalibrated" with no rows. `cc-research-refclass` 1..8 (red 8/8).
  - Item 13 remainder — `454f88340`: `scripts/wrap-ledger.sh` `SCOPE=met|open|unknown` (absent DoD keeps RUNG=✅
    and reads "completeness UNKNOWN") and `RESEARCH_PROGRAM / RESEARCH_VERDICT / RESEARCH_PENDING` beside, never
    inside, the rung (bounded `cc-research verdict --json`; kill switch `WRAP_RESEARCH=off`);
    `hooks/operator-readout.sh` withholds `✅ SAFE TO CLOSE` (and the in-block ✅ header) on unknown scope
    (`cert-scope-unknown`) and renders one counted `◆ research <slug>` line per program with pending concerns or an
    open menu; `commands/are-we-done.md` reads the program verdict separately. Suites `wrap-ledger-research`
    1..11 (red 11/11), `operator-readout-research` 1..9 (red 9/9); `self-certifying-close.bats` case A now plants a
    DoD (its old fixture was exactly the case the ruling withholds).
- Locus inside the wave: T (six teammates, one worktree each: `rp-c-{core,records,probe,cert,jobs,close}`), lead
  inline only for the shared skeleton (`023d63d61`: `bin/cc-research`, `lib/cli.py` verb table, one module per
  teammate, cross-module contracts in `RECORDS.md`), B1's on-box step 2, merges and lands. Fired session
  `rp-c-wave2`, 2026-10-01. Why T and not six dispatched sessions: the brief asked this session to lead its own team,
  and each teammate returns one short report while the lead lands every item through one serialized queue.
- Ruled 2026-10-01 by the wave's originator (asked at the decision gate): an absent DoD keeps RUNG=✅ for the git
  state (a new rung glyph would edit the operator's global rung list, outside this wave's authority); a separate
  `SCOPE=met|open|unknown` field reads unknown, the readout says "completeness UNKNOWN", and `operator-readout.sh`
  withholds the `✅ SAFE TO CLOSE` certificate whenever scope is unknown.

### D — audit fixes (REPORT rows 4-6)
Scope (frozen): implement rows 4, 5 and 6 of `docs/research/upfront-method-audit-2026-10-04/REPORT.md` §3 (landed
11602aaa8): the code fixes that make the research-program kit match its own specification (re-ask layer, round
robustness, statistical core). Each fix gets a planted-input bats test that fails before the change and passes after;
all landed via the project-local /ship and converged.
- Constraints: the method text (`docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md`,
  `skills/research-program/SKILL.md`) is frozen by ruling 8; the classifier time limit is open decision
  `4bf73c4e55d5`; the live pilot `truememory-2-0` and its records are read-only; tests use fixtured
  `CC_RESEARCH_REGISTRY`/`CC_RESEARCH_HOME` and stubbed vendors; no settings.json migration.
- Locus: S for the wave (this fired session), T inside it: one teammate per item group, each in its own worktree
  `~/Development/.worktrees/rp-d-<name>` on branch `rp-d-<name>`; the lead merges into `rp-audit-fixes`, runs every
  touched suite and lands once. Batch 1 (six, disjoint files): router, registry, cert, slots, seed, estimate.
  Batch 2 after batch 1 merges (they share `lib/round.py`, `kit.py` and `seed.py` with batch 1): close, ops.
- Items and targets (paths under `scripts/research-kit/` unless shown):
  - **4a classifier off a cold `claude -p`** — NOT built: every way of doing it is an option of open decision
    `4bf73c4e55d5` (raise to 9 s · slimmer start · warm classifier process); building one pre-empts the
    operator's choice, and the warm process is a new launchd daemon whose load is operator-only. Row 15 keeps
    failing until it is ruled.
  - **4b relay check on `unavailable`** (rp-d-router) — `router.py:639-660` `cmd_relay_check` returns early unless
    the label is relayed; run `relay_violations` on an `unavailable` turn whose reply opens with a verdict
    (`OPENS_NO` / a yes-verdict opener, `router.py:581-602`).
  - **4c honest fallback score** (rp-d-router) — `heldout.py:214-219` scores a fallback as `completeness`, so it
    counts toward completeness recall; score it as a miss and report the fallback share.
  - **4d machine-envelope first prompt** (rp-d-router) — `router.py:82-85` `MACHINE_ENVELOPE`, `:345` `genuine`
    skip, `:529-532` unlabeled ⇒ completeness ⇒ deny every tool. A fired/recycled successor whose first prompt is
    a machine brief gets a deterministic label (`--requires-gate` ⇒ work-order; otherwise inherit the
    predecessor's label) instead of "deny every tool".
  - **4e program roots** (rp-d-registry) — `lib/gate.py:114-118` `cmd_register` writes `cwd_roots=[a.root]` and
    replaces the list; add a repeatable `--root` and an `add-root` verb that appends (build and sibling worktrees).
  - **4f D4 prompt-alias key** (rp-d-registry) — `hooks/completion-assert.sh:1087-1110` keys the D4 exemption on
    cwd only; also resolve the last genuine prompt with `rp_resolve_prompt` (`scripts/lib/research-program.sh:149`),
    the router's second key.
  - **4g live certificate** (rp-d-cert) — `lib/gate_cert.py:191-232` `lines_for`: the after-signoff count from
    `changes.jsonl`/`challenges.jsonl`, no literal "take-backs 0" (:213), no frozen "uncalibrated" (:230), lines for
    residuals, scheduled checks and Built/Live per method REPORT:815-816.
  - **5a re-run dead, missing and partial slots** (rp-d-slots) — `lib/cli_cert.py:258-310` `cmd_check` skips dead
    panels (:273); `workflows/round.workflow.js:67-75` re-runs only voided ones.
  - **5b lane liveness / preflight / R_max** (rp-d-slots) — a lane is live if any one slot completed
    (`lib/cli_cert.py:330-335`); `cmd_open` (`:104-148`) opens without a fresh preflight and spends a round number on
    an infrastructure-lost round.
  - **5c close refuses a non-complete planned slot; resumable re-entry** (rp-d-close, batch 2) — `lib/round.py:337`
    `cmd_close`, `:270` `cmd_run`.
  - **5d gate row: stop is "dry" or "cap reached by counted rounds"** (rp-d-cert) — new row in `lib/gate_rows_b.py`.
  - **5e sweep registered programs with open packets** (rp-d-ops, batch 2) — `lib/cli_jobs.py:44` `ACTIVE`.
  - **5f program lease; locked id minting; seed-vault lock** (rp-d-ops, batch 2) — `lib/kit.py`, `seed.py:44-60`.
  - **6a `seed_match` written before quiet, matched by defect identity** (rp-d-seed) — `lib/round.py:345-380`
    computes quiet before `seed.py match` runs and nothing writes `seed_match`; `seed.py:154` `overlaps` is line
    overlap.
  - **6b seed pre-screen and realism statistic** (rp-d-seed) — method REPORT §3.9; none exists (`kit.py:166` only).
  - **6c deflate `found` by a measured false-material rate; 6d shadow found count; 6e U_HI to the measured
    bracket; 6f bound sharpness and rank skill** (rp-d-estimate) — `estimate.py:36-38`, `:305-372` `forecast`
    (`:324` passes 0 for the shadow stratum), `heldout`-free; calibration `docs/research/research-calibration.jsonl`.
- Evidence: `docs/research/upfront-method-audit-2026-10-04/evidence/{lens-as-built,lens-internal-soundness,
  lens-operator-interface,lens-critic-end-to-end-live-behavior,lens-critic-long-horizon-continuity-and-capacity}.md`
  (the last one's §5 lists the round and lease fixes).
- Status: **DONE 2026-10-04** — every row-4/5/6 item fixed with a planted-input test red before and green after,
  except 4a (not built, reason above: decision `4bf73c4e55d5`; gate row 15 still FAILS until it is ruled, so no
  program can certify yet). Landed per item (red → green, from the item's suite):
  - 4b `3cb00ec08` relay-check 1 of 17 red → 17/17 · 4c `8b531dd34` router-heldout 2 of 11 → 11/11 · 4d `da9da7a18`
    router 3 of 30 → 30/30 (docs `a2f39ff84`, revive `f050bc99f`).
  - 4e + 4f (rp-d-registry) and the alias follow-on land in the same land as this plan edit ("a program covers more
    than one root", "completion-assert D4 research exemption reads the prompt key too", "re-register keeps the program's
    stored aliases"): registry 3 of 9 → 9/9, completion-assert 1 of 148 → 148/148, alias case red → registry 10/10.
  - 4g `fa06657b8` and 5d `65b3713cf` (row 17, ROW_COUNT 17; fixture `ff67f47e8`, `533c539d9`): gate 7 of 50 → 50/50.
  - 5a `bc17af96d`, 5b `fb345896a`: cc-research-cert 5 of 23 → 23/23.
  - 5c `2fae4d7b5` (close refuses) · `20b8d9cbc` (resume) · `3bbefd668` (R_max counts counted rounds, uncounted cap
    2, round.sh preflight): round 4 of 26 → 26/26; lead follow-on `7e67e96a2` (round.sh re-runs partial slots and
    counts a lane live only when every slot completed — without it 5c-1 turned a partial read into a counted round
    no verb could close): red → round 27/27.
  - 5e `e0f390797` jobs 1 of 13 → 13/13 · 5f lease `4a511e3fb` lease 5 of 6 → 6/6 · 5f locks `eb7653f57` records 1 of
    11 → 11/11, seed 1 of 13 → 13/13.
  - 6a `da5eea40e`, 6b `0d8dfbd12`: round 2 of 17 and seed 3 of 12 red → green · 6c-6f `d1048d356`, `dc51b2368`,
    `c18ccd4bd`, `d69121e0a`: estimate 5 of 10 → 10/10. Records contract `9d011c6f0`, `3b4a9f0d7`.
  - Final integration (this land): all 30 research suites + completion-assert green, plan lines printed in the
    session that landed it.
- Learnings:
  - Briefing "no assertion errexit cannot reach" was not enough: 4 of 8 teammates still wrote dead `[[ … ]]` lines
    and the land gate refused twice. Tell teammates to run `scripts/bats-assert-liveness-fix.py` on every changed
    suite before reporting, and assert a fixture's date by reading it back, never as a literal (time-bomb lint).
  - Shipping mid-wave rewrites the shas later teammate branches were cut from; the next rebase then replays the
    old copies as duplicates. Either land once at the end or drop the duplicate picks (`git range-diff` proves them
    identical) — never resolve them by hand.
  - Two teammates editing one file's imports produced a semantic merge break (ops removed `import os` from gate.py,
    registry's add-root needs it) that no textual conflict showed; only the suite run caught it.
  - Load sat at 30+ on 10 cores the whole wave, so cc-bats shed every run; focused suites ran under its logged
    waiver (`CC_BATS_WAIVER_REASON=… CC_BATS_MAX_ROOTS=0`), serially, never `--jobs`.
  - Not done, outside this scope (each named by its teammate): the simulator still pools its own false alarms
    into `found_total`, and the round-1 R_max simulation seeds n0 from undeflated `new_material`
    (`estimate.py program()`); 4b's lexical relay matcher still passes "No - escape." (audit §1(b), the content
    problem is a method question); the workflow re-run loop has no harness test
    (`tests/fixtures/research-kit/run-workflow.mjs` always returns exit 0 for check-round).

### E — method v1.2 (ruling `1bf69e5c1775`, 2026-10-04)
Scope (frozen): adopt method v1.2, which overrides ruling 8's freeze for four named changes from
`docs/research/upfront-method-audit-2026-10-04/REPORT.md` §3, and implement ruling `4bf73c4e55d5` (the 9 s
classifier limit). Both rulings are recorded in the method's own text, REPORT.md §9 "Ruled 2026-10-04". Each v1.2
change lands as a named, priced edit after E2's measurement, never before it.
- The four v1.2 changes (audit §3 rows):
  - (a) row 1 — measure triage precision first, then fix it: blind, vendor-diverse re-adjudication of the 129 + 31
    ground-truth items; A/B the candidate filters; the winner goes in code ahead of the raters; re-run `calib_sim`.
  - (b) row 2 — certify the built and tested result before "done": a stage after the last build wave, before
    implementation signoff, with code-native instruments (failing-test repro, harness mutation testing, as-built
    contact re-run, soak); the forecast split before and after implementation signoff.
  - (c) row 7 — stop contact and build-to-learn on yield (K quiet probes) instead of a calendar box;
    `escape_cost_days` drives a value-of-information rule.
  - (d) row 3 — re-sign the pilot contract on the measured forecast: `estimate.py` loads measured parameters, the
    stale REPORT/SKILL numbers are fixed, TM2's contract is re-rendered and rulings 1 and 4 re-presented.
- Constraints: the live pilot `truememory-2-0` and its records (`~/.claude/autonomy/research/truememory-2-0`,
  `~/Development/.worktrees/tm2-plan`) stay read-only until E4; no change to triage, the rubric or any v1.2 mechanism
  before E2 reports.

#### E1 — 9 s classifier limit and row 15 re-measured — DONE 2026-10-04
- `router.py` `CLASSIFIER_TIMEOUT_S` 6.0 → 9.0 and `heldout.py` `ROUTER_TIMEOUT_S` 6 → 9; the hook's 10 s timeout is
  migration 0050's, verified live in `~/.claude/settings.json` (10), not re-done. Test: research-router-heldout
  "ruling 4bf73c4e55d5: a classifier answering in 6.5 s is labeled…" — red at the router site, then red at the
  heldout site with the router fixed (one mutant per site), then research-router-heldout + research-kit-heldout 18/18.
- Gate row 15 at 9 s — **FAILS, narrowly** (2026-10-04 16:22-16:29 CDT, load 24 rising to 40, 427 s;
  `CC_RESEARCH_ROUTER="python3 <worktree>/scripts/research-kit/router.py classify" heldout.py evaluate`, rc 1):
  fallback 7 of 69 routed = 0.101 against the ≤ 0.10 cap (printed as "0.10, above 0.1"); correct labels on `other`
  23/26 = 0.88 against ≥ 0.90; completeness recall 14/14 regex-matched · 3/3 regex-missed · 1/1 pushback, now
  honest (fallbacks score as misses since D's 4c); 22 of 91 excluded for rater disagreement. Against the 6 s
  reading (fallback 0.51 and `other` 0.62 at load 45-80) the limit removed most fallbacks, and what remains is
  load-bound: one fewer fallback, or one more `other` label right, flips each condition. Thresholds stay assumed
  inputs (§6.6); a re-read at lower load, or the classifier-path options left in decision `4bf73c4e55d5`, are the
  levers. No program can certify while row 15 fails.

#### E1b — make row 15 pass with the two allowed levers — EXHAUSTED, row 15 still FAILS (2026-10-04)
Scope (frozen): make gate row 15 PASS honestly, without changing its thresholds, its sealed held-out set or the 9 s
limit; levers in order: (1) a slimmer classifier start, (2) better labeling tuned on the tuning set only, (3)
re-measure as E1 did. Locus S (fired `fire-rp-v12-e1b`). Harness, raw numbers and the tried patch:
`docs/research/router-classifier-e1b-2026-10-04/`.
- **What costs the time.** Haiku thinks before its one label (200-500 output tokens, ~4-5 s of API time). The cold
  start itself costs ~2-4 s at load 40-100 before any token. `--disable-slash-commands` alone: median 7.68 → 6.29 s.
  Thinking off (`--settings '{"alwaysThinkingEnabled":false}'`): median 2.88 s, 0 of 12 over 9 s (load 54-128,
  n = 12 per arm, four arms interleaved). A short `--system-prompt` adds nothing to latency. `--json-schema` costs
  2-4 internal turns, so it was rejected; `--bare` cannot use the OAuth login (B1).
- **Lever 2, tuning set only.** The tuning set had no gold labels, so it was rated with `heldout-rate.py`'s brief and
  courier path by `anthropic:claude-opus-5-5` and `openai:gpt-5.6-sol`: 69 of 96 agreed (labels beside the tuning
  set, outside the repo). The tried brief (`e1b-classifier.patch`): a router system prompt that forbids following
  the labeled prompt (an embedded "read this file and follow it" made haiku answer in prose, a fallback), the
  prompt delimited as data, and classifier-only reading notes including the list-order tie-break.
  `ROUTE_DEFINITIONS` stay the raters' word for word. On the agreed tuning rows with thinking off: `other` 65/66,
  relay recall 78/78, 0 fallbacks (3 repeats).
- **Readings of row 15** (all `CC_RESEARCH_ROUTER="python3 <worktree>/scripts/research-kit/router.py classify"
  heldout.py evaluate`, rc 1, 22 of 91 excluded for rater disagreement, as in E1):

  | # | config | when (CDT), load | fallback (cap ≤ 0.10) | `other` (≥ 0.90) | recall matched · missed · pushback (≥ 0.95) |
  |---|---|---|---|---|---|
  | E1 | pre-E1b, thinking on | 16:22-16:29, 24 → 40 | 7/69 = 0.10 FAIL | 23/26 = 0.88 FAIL | 14/14 · 3/3 · 1/1 |
  | 2 | E1b brief, thinking off | 18:52-18:57, 40 → 39 | 0/69 = 0.00 | 25/26 = 0.96 | 14/14 · **1/3 FAIL** · 1/1 |
  | 3 | E1b brief, thinking on | 19:27-19:34, 45 → 29 | 16/69 = 0.23 FAIL | 23/26 = 0.88 FAIL | 14/14 · 2/3 FAIL · 1/1 |

- **Why both levers are exhausted.** Thinking carries the completeness sensitivity: on the 13 tuning rows where the
  raters split and one said completeness or pushback, the pre-E1b path relays 18/26, the brief with thinking off
  11/26, and the same brief with thinking on 17/26. Two cost-asymmetry notes ("when unsure, answer completeness")
  left it at 10/26 and 12/26, so wording does not replace thinking. And with thinking on, the slimmer start buys
  nothing: same-moment A/B, pre-E1b median 5.03 s (2 of 10 over 9 s) against the E1b config's 5.88 s (3 of 10,
  max 54.8 s), load 27-40.
- **Landed: nothing in the router.** The change (commit "feat(research-router): slimmer classifier start and
  data-delimited brief", reverted by the next commit; the diff is `e1b-classifier.patch`) was committed before reading 3, so the configuration
  choice was fixed ahead of the result. Since it read worse than baseline, it was reverted. No row-15 reading is
  selected: all three are above. Disclosure: choosing thinking-on for reading 3 used one bit of reading 2 (the
  regex-missed drop), and the sealed set has now been read three times since sealing.
- **What remains (decisions for the lead, then the operator).** Row 15 cannot pass on a cold `claude -p` haiku under
  the 9 s limit with these thresholds. Thinking-on is accurate enough but its cold call runs 5-6 s median with a
  p90 of 11-19 s at load 27-45. Thinking-off fits easily (34 cold calls across load 31-128, none over 9 s) but misses
  subtly worded completeness questions. The open options:
  - **(a) A warm classifier.** A resident haiku process that drops the 2-4 s cold start and keeps thinking on. This
    is the option decision `4bf73c4e55d5` left open; it needs a daemon and a fail-closed path when that daemon is down.
  - **(b) Thinking off, plus a deterministic completeness pre-check ahead of the model.** This is a router design
    change, and the sensitivity gap above has to be closed by measurement, not assumed.
  - **(c) A different classifier model or thinking budget.** This is a §4.1 method parameter.
  - **(d) The thresholds themselves.** These stay assumed inputs (§6.6) and are the operator's call.

  Until one is chosen, no program can certify.

#### E1c — a valid instrument for row 15, read once — RUNNING (2026-10-04)
Scope (frozen): make row 15 a valid instrument and read it once. (1) Mint a new sealed held-out set v2, big enough
to judge each stratum, beside v1 (never overwritten); (2) pre-register here, on the tuning set only and before any
read of v2, the rule that picks the classifier configuration, then read v2 exactly once with the chosen
configuration; (3) if v2 fails only because thinking-on fallbacks exceed the cap, build the warm (resident)
classifier as a staged launchd job with a c10 migration the operator runs, and leave the final reading pending its
activation. Never change row 15's thresholds or the 9 s limit. Locus S (fired `fire-rp-v12-e1c`), lead-inline inside
(why: the steps are strictly ordered around one sealed file, and no second writer may hold its key path).

- **Why v1 cannot carry a verdict.** Its sealed strata hold 31 regex-matched, 27 regex-missed, 3 pushback and 30
  other prompts, of which row 15 counts 14 · 3 · 1 as relay-gold: one prompt moves regex-missed recall by 33 points.
  It has also been read three times while the configuration was being chosen (E1b's disclosure).
- **Tooling (red, then green).** `heldout.py --set v1|v2`: each set is sealed once in its own file and keychain
  account (`sealed.enc` / `sealed`, `sealed-v2.enc` / `sealed-v2`); `seal --set v2` drops every candidate that an
  earlier sealed set or an `--exclude` file (the v1 tuning set) already holds, matched on the first 200 characters
  with case and whitespace folded; `seal --dry-run` prints the per-stratum counts and writes nothing. With `--set`
  omitted `seal` means v1, and every other verb and gate row 15 read the newest sealed set. `evaluate` now names
  the set and counts fallbacks per stratum, so a slow classifier can be told from a wrong one.
  `heldout-candidates.py --history` reads the prompt history (`~/.claude*/history.jsonl`, a year deep) as a second
  store, counts a short challenge as pushback wherever it sits in the prompt, and takes `--cap-for STRATUM=N`.
  `heldout-rate.py --set --batch N` sends the same brief N prompts per call, asks a batch whose reply skips a
  prompt again once (the OpenAI rater's first pass returned 395 of 396 and recorded nothing), and records nothing
  unless every batch came back whole from one model. The five new tests failed against the pre-change scripts
  (research-kit-heldout + research-router-heldout: 5 of 23 not ok, the 18 older tests ok); the green run is in
  this wave's status line.
- **v2 sealed 2026-10-04.** The transcripts hold 3 pushback prompts in all (the same 3 v1 used), so pushback could
  not grow from them; the prompt history holds 44 more. Mined from 7,360 transcripts and 4 history files with caps
  110 regex-matched, 330 regex-missed, 100 other and every pushback prompt found (49): 589 candidates, 101 dropped
  as already in v1's sealed or tuning set, the rest split 0.8 under the same HMAC secret. **Sealed: 396 prompts —
  64 regex-matched, 228 regex-missed, 37 pushback, 67 other** (v1: 31 · 27 · 3 · 30). 92 more went to a new
  tuning file (`tuning-v2.jsonl`, 29 · 42 · 9 · 12, unlabeled, outside the repo) for whoever builds next. v1's file
  is byte-identical before and after (sha1 `97695cb0…`). Row 15 counts a completeness-stratum prompt only when both
  raters agree it is a re-ask, so the counted sizes are known after labeling and are recorded below.
- **Pre-registered configuration rule (committed before the tuning measurement and before any read of v2).**
  Decided on the v1 tuning set only (96 rows; 69 with two agreeing raters, 13 "borderline" rows where the raters
  split and one said completeness or pushback). Harness `docs/research/router-classifier-e1c-2026-10-04/`:
  `e1c-tune.py 2 <out>` runs every tuning row twice per arm, the arms started at the same instant, one cold call
  each with 30 s to answer; `e1c-choose.py <out>` is the rule below as code.
  - Arms: `on-pre` (the router as built on trunk, thinking on); `on-e1b` (E1b's patch, thinking on); `off-e1b`
    (E1b's patch, thinking off). No other configuration is a candidate in this wave.
  - Measures per arm: relay recall on the agreed relay-gold rows of the three completeness strata; exact-label
    rate on the agreed `other` rows; relays on the borderline rows (completeness sensitivity, which the agreed
    rows cannot show); fallback share at 9 s (a call over 9.0 s wall, or one that returns anything but a single
    route label).
  - Step 1, labeling: an arm is eligible when recall ≥ 0.95 and `other` ≥ 0.90 (row 15's own thresholds) on the
    labels it gives with time to answer. If none is eligible, take the highest recall, then `other`.
  - Step 2, sensitivity: among eligible arms, the most borderline relays; arms within 2 calls of the best are tied.
  - Step 3, latency: among tied arms, the lowest fallback share at 9 s; then the smaller change from trunk
    (`on-pre`, `on-e1b`, `off-e1b`).
  - Labeling ranks ahead of latency on purpose: E1b measured that wording does not replace thinking, while a cold
    start is an engineering cost that decision `4bf73c4e55d5` option 3 (a warm classifier) removes.
  - The read: `CC_RESEARCH_ROUTER="python3 <worktree>/scripts/research-kit/router.py classify" heldout.py --set v2
    evaluate`, once, with the chosen arm committed in `router.py` first, whatever its tuning fallback share.
  - The verdict, fixed now. PASS: `evaluate` exits 0. Otherwise, with `fell` the fallbacks among a stratum's
    counted items: if every stratum meets its threshold on the items that got an answer (`ok / (n − fell)`) and
    the fallback share is above 0.10, the failure is latency alone, the verdict is "pending warm-classifier
    activation", and step (3) of the scope is built. If any stratum misses its threshold on answered items, the
    verdict is FAIL (labeling) with the numbers, and no warm classifier is built on this wave's authority.
  - No second read of v2 follows in this wave under any outcome. The later reading after the operator activates a
    warm classifier uses the same committed labeling configuration and changes only the call path.
- **v2 labeled 2026-10-04, before the read** (`heldout.py --set v2 status`), by `anthropic:claude-opus-5-5` and
  `openai:gpt-5.6-sol` through `heldout-rate.py --set v2 --batch 60`: every one of the 396 has two labels, and
  the raters agree on 232 — regex-matched 53 of 64, regex-missed 136 of 228, pushback 7 of 37, other 36 of 67
  (v1: 23 · 18 · 2 · 26 of 91). **Pushback is still thin and the population is spent:** every short challenge
  the two stores hold is in v1 or v2 (49 found, 37 sealed here, 9 in the v2 tuning file), and the raters agree on
  7 of the 37. Row 15 counts an item only when both raters give the same label, so a prompt one rater calls
  completeness and the other pushback is dropped though either label relays.
- **Added to the read before it ran, verdict untouched** (committed with this note, ahead of the read):
  `evaluate` also routes those dropped completeness-stratum prompts whose two labels are both relay labels and
  prints them on a line of their own (relayed / items / fell back per stratum). They enter no recall, no fallback
  share and no verdict; the line only shows what the same-label rule costs, so that question can be judged later
  without reading v2 again. `evaluate --record F` keeps one row per routed item (`id`, `stratum`, `counted`, the
  label the router gave, wall seconds; no prompt, no rater label) outside the repo.

#### E2 — triage precision study (v1.2 (a), measurement half) — RUNNING
- Locus: a Workflow in session d8964eb2, started 2026-10-04. Results: `docs/research/triage-precision-study-2026-10-04/`.
- Delivers the re-adjudicated ground truth and the filter A/B that E3's triage fix and its pricing rest on.

#### E3 — build the v1.2 changes — after E2
- Locus: S (one dispatched session per change group, fired after E2 lands its report).
- Builds (a) the triage fix E2 selects, (b) the built-artifact certification stage, (c) the yield stop and the
  value-of-information rule, and the code and text half of (d) (`estimate.py:36-38` measured parameters by default,
  the stale REPORT §1/§7/§3.12 and SKILL.md:65 numbers). Each is a named, priced edit to the sections it changes,
  recorded in REPORT.md §9 per ruling 8's rule; each code change gets a planted-input test red before, green after.

#### E3a — the honest forecast and the triage record — DONE 2026-10-04
Scope (frozen): (1) `estimate.py` loads `params-measured.json` by default, BASE kept as a labeled contrast, red-then-green
test; (2) the stale REPORT §1/§7/§3.12 and SKILL.md numbers fixed as dated notes, with the triage study's verdict
recorded; (3) `intake.py` warns on a non-lite profile with the measured reason; (4) the pilot's contract re-rendered as
a draft beside the signed one, and the re-sign filed as one operator step; (5) the triage study's one reversing
measurement run and its decision rule's outcome recorded.
Scope (grown): +`intake.py` stamps `method_version: "1.2"` in the frame and counts `build-certifying` /
`build-certified` as registered in `status` (asked by the wave lead for E3b's gate rows 18 and 19).
- Locus: S (fired `fire-rp-v12-e3a`), with the code written L, lead-inline: the machine's capacity gate refused
  teammate and worker spawns for most of the session (8-9 sessions mid-turn against a ceiling of 8), and its own
  instruction for that case is to run the step in-session.
- **Item 1, estimator.** `simulate` and `forecast` read `docs/research/research-calibration/evidence/params-measured.json`
  by default: `u_plan_mean` 0.121, `fpp` 1.1266, `q` 0.223, `omit_plan_mean` 0.577, `fixborn_plan_median` 0.211, `u_hi`
  0.234. `CC_RESEARCH_PARAMS` or `--params` points at another file; an unreadable or incomplete file exits 2. `--base`
  is the assumed contrast, and `--published` still reproduces `profile_sim.out` byte for byte. At the measured inputs
  and 20 holes at freeze (modeled, 500 programs): Lite 10.11 desk + 3.96 invisible, Standard 15.28 + 7.45, Full
  24.69 + 13.2; the cap is reached in 100% and the chance of a change after signoff is 1.00 in each. Tests: 5 new cases
  in `tests/research-kit-estimate.bats`, all 5 red on the old file.
- **Item 3, intake.** `init` warns on stderr when the chosen profile leaves no fewer holes than Lite at the measured
  inputs (Standard 22.73 against Lite's 14.07 at 20 holes; both simulated at call time, so the warning follows the
  measured file and a planted file with no false calls silences it). The contract page prints the measured forecast,
  the assumed one as a contrast, and the warning. Tests: 6 new cases in `tests/research-program-intake.bats`, 4 red on
  the old file (the two that pass there are the lite and planted-file controls).
- Test receipts (2026-10-04, `CC_BATS_MAX_ROOTS=0` with a recorded waiver after 7 deferrals at load 55-90): the two
  suites `1..36`, 0 not ok; cc-research-core, cc-research-records, cc-research-cert, research-program-briefs,
  research-kit-round and research-kit-gate `1..142`, 0 not ok.
- **Item 2, text.** Dated "Updated 2026-10-04 (v1.2)" notes, nothing deleted: REPORT §1 (bound exceeded in at most 2.2%;
  chance of a change after signoff 1.00, about 9 changes per program on the operator-strict line), the §3.12 column
  header (measured median 20.6 holes at freeze), §7 (6.5-7.6 desk holes, or 9.4-21.4 counting every false call), §9
  (the list of v1.2 edits and the triage verdict), and SKILL.md's default profile (lite for every size).
- **Item 4, pilot contract.** Draft at
  `~/Development/claude-private/docs/research/triage-precision-study-2026-10-04/contract-draft/` (private: it carries
  the operator's rulings verbatim): `CONTRACT.draft.md`, `NOTE.md`, `resign.sh`. Rendered from a temporary copy of the
  pilot's `frame.json` and `preflight.json`; the signed page's sha256 is unchanged (`54ccaf73…`). Against the signed
  page only the forecast differs: desk left 1.57 → 15.28, invisible 1.12 → 7.45, chance of a change after signoff
  0.87 → 1.00. At the pilot's measured 145 holes at freeze Lite and Standard are level (71.3 against 72.2 total,
  modeled, 200 programs). Operator step filed: backlog `01e7de9219c0`
  (`bash …/contract-draft/resign.sh --confirm truememory-2-0`). This is E4's packet.
- **Item 5, the reversing measurement: F3 after the triage FAILS the decision rule; build no filter.** Recorded as
  appendix A of `docs/research/triage-precision-study-2026-10-04/REPORT.md`. On S4 unannounced changes (modeled):
  triage as run 8.83 Lite / 8.85 Standard; F3 after triage 9.12-9.24 / 8.61-8.90. Plan-bootstrap 95% interval of the
  difference (100 draws): Lite −0.23 to +0.88 and −0.06 to +1.05; Standard −1.78 to +0.77 and −1.52 to +1.02. Total
  changes rise to 13.9-15.9. Clause f: 0 of 70 exempt items lost. Holm-corrected null tests: smallest p 0.107.
  - Coverage: symmetric panel 17 of 17 jobs (Anthropic re-rated on 16 plans through the clean prompt, the missing
    Google job sent). F3 verdicts on 214 of 237 items; this pass probed 65 (45 new, 20 re-runs on the 3 blocked plans:
    11 passed, 3 ran and did not reproduce, 48 not runnable, 3 blocked again).
  - Known gap: the last 20 items (9 plans) were never dispatched, because the capacity gate refused the worker. With
    the 3 blocked items they are bounded both ways (all pass, all disputed), and the rule fails under both bounds.
  - Nothing is added to E3b's list: change (a) closes with the triage as calibrated.
- Landed 2026-10-04, content-verified on `origin/main` (9 paths present, diff empty): `d4045400a` estimator and
  `08eed0851` its test fixup (a dead assertion the land gate named), `e44627831` intake, `dfbfb1784` method text,
  `4c83f9ea6` study appendix A, `4556688a3` this record. The land's smoke was cut by its time budget under load
  (`smoke:"partial"`), so the behavioral proof is the test receipts above, not the land.

#### E4 — re-sign the pilot contract (v1.2 (d), operator half) — after E3
- Operator: re-render TM2's contract on the measured forecast and re-sign it, with rulings 1 and 4 re-presented at
  measured numbers. Agent-side work stops at presenting the packet.
