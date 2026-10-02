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
