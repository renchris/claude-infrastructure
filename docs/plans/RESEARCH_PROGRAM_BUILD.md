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
| E | E1 S (fired `fire-rp-v12-step1`); E1b S (fired `fire-rp-v12-e1b`); E1c S (fired `fire-rp-v12-e1c`); E1d S (fired `fire-rp-v12-e1d`); E1e S (fired `fire-rp-v12-e1e`); E1g S (fired `fire-rp-v12-e1g`); E1h S (fired `fire-rp-v12-e1h`, T inside for track A); E1i S (fired `fire-rp-v12-e1i`, L inside); E1j S (fired `fire-rp-v12-e1j`, L inside: one small code change, a harness edit and two ordered measurements around a pre-committed rule, nothing to fan out); E1k S (fired `fire-rp-v12-e1k`, L inside: one change in one function, one job-script line, docs, and a measurement run behind a pre-committed bar, nothing to fan out); E2 Workflow in session d8964eb2; E3 S (E3a fired `fire-rp-v12-e3a`, E3b fired `fire-rp-v12-e3b` with T inside: six teammates; E3c fired `fire-rp-v12-e3c`, L inside; E3d fired `fire-rp-v12-e3d`, L inside); E4 operator | Method v1.2 (ruling `1bf69e5c1775`): audit REPORT §3 rows 1, 2, 3, 7, plus the 9 s classifier limit (ruling `4bf73c4e55d5`) | D |

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

#### E1c — a valid instrument for row 15, read once — DONE: row 15 FAILS on v2, on labeling and on latency (2026-10-04)
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
  (research-kit-heldout + research-router-heldout: 5 of 23 not ok, the 18 older tests ok); a sixth test covers the
  uncounted line and `--record`. Green on the final code: those two suites plus research-kit-gate `1..74`, and
  with research-router `1..103`, no `not ok`.
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
- **The rule applied (2026-10-04 20:18-20:48 CDT, load 28-46; `tune-2reps.json`, 192 calls per arm).**

  | arm | recall, agreed relay rows | `other`, agreed rows | borderline relays | fallback share at 9 s | wall median · p90 |
  |---|---|---|---|---|---|
  | `on-pre` (trunk, thinking on) | 51/52 = 0.98 | 40/44 = 0.91 | 21/26 | 33/192 = 0.17 | 5.7 s · 10.9 s |
  | `on-e1b` (E1b patch, thinking on) | 52/52 = 1.00 | 42/44 = 0.95 | 21/26 | 51/192 = 0.27 | 6.1 s · 18.0 s |
  | `off-e1b` (E1b patch, thinking off) | 51/52 = 0.98 | 44/44 = 1.00 | 10/26 | 1/192 = 0.01 | 1.7 s · 2.3 s |

  Step 1: all three are eligible. Step 2: the thinking-on arms tie at 21 borderline relays; thinking-off, at 10,
  is out. Step 3: `on-pre` has the lower fallback share. **Chosen: `on-pre`, the router exactly as built on
  trunk; `router.py` is not changed for the read.** Its tuning fallback share is above the 0.10 cap (31 of its 33
  fallbacks are single route labels that arrived after 9 s), so the read is expected to fail on fallbacks, and the
  open question it answers is whether the labeling holds on the items that get an answer.
- **How the one read is run** (fixed before it starts): `heldout.py --set v2 evaluate --record <file outside the
  repo>` from this worktree, with `CC_RESEARCH_ROUTER` pointing at `router.py classify` in a `git archive`
  snapshot of the commit that records this choice, not at the worktree path the rule names. The bytes are the
  same; the snapshot keeps the router fixed for the whole read while this wave's later files are written.
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

- **The one read of v2** (2026-10-04 20:48:54-21:15:13 CDT, 1-min load 58 at the start falling to 23, 26 min;
  router snapshot of `7f8e33f1d`, rc 1). 396 sealed, 164 excluded for rater disagreement, 232 routed:

  | condition | reading | on the items that got an answer |
  |---|---|---|
  | regex-matched recall (≥ 0.95) | 24/24 = 1.00 | 24/24, none fell back |
  | regex-missed recall (≥ 0.95) | **31/34 = 0.91 FAIL** | 31/31 = 1.00; the 3 misses are all fallbacks |
  | pushback recall (≥ 0.95) | 5/5 = 1.00 | 5/5, none fell back |
  | `other` correct label (≥ 0.90) | **23/36 = 0.64 FAIL** | **23/26 = 0.88 FAIL**; 10 fell back, 3 answered wrong |
  | fallback share (≤ 0.10) | **62/232 = 0.27 FAIL** | every one a timeout at 9 s, none a bad answer |

  Uncounted line: 3 prompts carry two different relay labels (1 regex-missed, 2 pushback) and the router relayed
  all 3. Per-item record (router side only): `~/.claude/autonomy/research/router-heldout/reading-v2-2026-10-04.jsonl`;
  answered calls took 5.9 s median, 8.2 s at p90, and the fallbacks spread evenly over the run (20 · 21 · 21 by
  thirds), so the load at the start does not explain them.
- **Verdict, by the rule fixed above: FAIL (labeling), and latency as well.** Every completeness stratum meets its
  threshold on answered items, but `other` does not: 23 of 26 = 0.88 against 0.90, one prompt short. So the failure
  is not latency alone, the "pending warm-classifier activation" outcome does not apply, and **no warm classifier
  is landed on this wave's authority and no operator step is filed.** The recall half of the instrument is now
  sound where the population allows: regex-missed is judged on 34 prompts (v1: 3) and the as-built router relays
  every one it answers in time.
- **What the instrument still cannot do.** Pushback is judged on 5 prompts. 37 are sealed and the raters agree on
  7; only 2 of the 30 they split on are relay-label splits, so the same-label rule is not what thins it. The two
  stores hold no more short challenges.
- **Disclosure.** v2 has now been read once, with a configuration fixed beforehand. Any configuration chosen from
  here knows two things from that read: the as-built router is one `other` prompt short on answered items, and
  27% of its cold calls time out. A later read of v2 is biased by that much and must say so.
- **A warm classifier exists as an unlanded draft**, written while the read ran: local branch
  `rp-v12-e1c-warm-draft` (daemon `scripts/research-kit/classifier-warm.py` holding two classifier processes
  started ahead of the prompt, one prompt per process; `/bin/bash` 3.2 runner; staged plist; c10 migration
  `0057`; `router.py` asks it first and makes the cold call when it is absent; `research-classifier-warm.bats`
  `1..19`). Measured on one synthetic prompt at load 34-46: 2.6-3.3 s through the daemon (4 calls) and 1.5-2.8 s
  from a process started 8 s earlier (3 calls), against 4.1-4.9 s cold. Landing it is the lead's call, not this
  wave's.
- **What remains (decisions for the lead, then the operator).** Row 15 needs both halves fixed, and no program can
  certify until it passes:
  - Latency: the warm classifier above removes the cold start; whether it brings the 0.27 under 0.10 is unmeasured
    on real prompts.
  - `other` labeling: on the tuning set E1b's brief with thinking on scored 42/44 on `other` against the as-built
    40/44, with the same 21/26 borderline relays; the rule passed it over for its higher cold fallback share
    (0.27 against 0.17), a cost the warm classifier is meant to remove. That pairing is the candidate, chosen on
    tuning numbers that predate the read.
  - Pushback: accept 5 counted prompts as what exists, or change how a rater split is counted; either is a method
    parameter (§6.6).
- Status: **DONE 2026-10-04, landed and converged** (live layer at `3ce98732b`). On trunk, in order: `4107c141e`
  (rule, before any measurement), `835da4f84` (tooling and tests), `8b58de677` (labeled counts and the uncounted
  line, before the read), `e259b44cd` (the choice; `7f8e33f1d` before the land's rebase, the id the read's router
  snapshot carries), `3ce98732b` (this record). Author dates keep the order: rule 20:17, read started 20:48. Learnings: the transcripts are a 60-day store and the prompt history a year-deep one, so a rare
  stratum is mined from history; one rater reply in seven calls dropped a single label, so a batch is asked again
  once before the whole pass is thrown away; the shared bats slots deferred a 2-suite run for 17 minutes at load
  35-45, so a retry loop around `bats` (never a waiver) belongs at the start of a wave, not after the first
  refusal.

#### E1d — land the warm classifier, then read v2 a second time — LANDED, awaiting activation (2026-10-05)
Scope (frozen): operator ruling `2137be2c1d33` ("build-warm"). (1) Land E1c's warm-classifier draft on this wave's
own branch with a fleet.manifest row, staged under `launchd/staged/` behind a c10 migration the operator runs, the
cold call kept as the fallback when the daemon is absent; land and converge. (2) File the activation as one
operator step. (3) After activation, measure warm latency on the tuning set (n ≥ 20), confirm the classifier
configuration is E1c's pre-registered `on-pre` (thinking on), then read sealed v2 exactly once more with
`heldout.py evaluate` and record the verdict, the per-stratum numbers, the load and the second-read disclosure
here. Never change row 15's thresholds, the 9 s limit or the sealed sets; never tune against v2. Locus S (fired
`fire-rp-v12-e1d`), lead-inline (why: one commit and one ordered read around a single sealed file).

- **Landed.** The draft (`862659ef1`, cherry-picked with `-x`) plus: migration renumbered `0057` → `0059`
  (`0057-fseventsd-watchdog.sh` and `0058-research-soak-job.sh` took the numbers on trunk); a `fleet.manifest` row
  `com.claude.research-classifier-warm | staged | 0 | - | - | 0059-research-classifier-warm.sh` (no cadence, no
  stdout sensor: the daemon writes only to stderr, so `auto` would read it STALLED; its liveness check is
  `classifier-warm.py ping`); cc-fleet's declared-label count 50 → 51 in the same land. The labeling
  configuration is untouched: the daemon builds its command line from `router.classifier_argv()`, the same one
  the cold call uses (thinking on, E1c's `on-pre`), plus the stream-json flags that let a process wait for its
  prompt.
- **Fallback.** With no socket, a socket nobody answers, a daemon with no process ready, or `CC_RESEARCH_WARM=0`,
  `router.py classify` makes the cold call it made before, inside what is left of the same 9 s. A daemon that took
  the prompt and failed yields `unavailable` (the limit is spent), never a second try.
  CORRECTED (2026-10-05): that last rule is what turned a logged-out daemon into a fallback on every prompt; wave
  E1f replaced it (a warm failure now falls through to the cold call).
- **Tests, red then green** (2026-10-04, load ~68). Red: in a snapshot of this commit with trunk's `router.py` and
  `fleet.manifest`, `research-classifier-warm.bats` + `cc-fleet.bats` ran `1..44` with 4 `not ok` (the three
  warm-answer router tests and the manifest count); the cold-path tests (no daemon, none ready,
  `CC_RESEARCH_WARM=0`) pass on both, which is the no-regression claim. Green on this branch: the same two suites
  `1..44`, and `research-router.bats` + `launchd-parity-lint.bats` `1..48`, no `not ok`; the runner and the
  migration run under `/bin/bash` 3.2.57 inside the suite. Run by hand because the land's smoke reached none of
  them before its 900 s budget ran out.
- **Landed and live, awaiting activation** (2026-10-05): trunk `6cfb02e03`, content-verified; converged (the live
  `~/.claude` links `classifier-warm.py` and its runner, and the live `router.py` is byte-identical to trunk's).
  The activation is one operator step, backlog `320091ec2edd`: `bash
  ~/Development/claude-infrastructure/migrations/0059-research-classifier-warm.sh` (it reads the daemon's ping
  back before it reports success). Until it runs, every router call takes the cold path exactly as before.
- **Still to do after activation (this wave):** warm latency on the tuning set (n ≥ 20), a check that the
  classifier's command line and brief equal `e259b44cd`'s (`on-pre`, thinking on), then the second and last read of
  v2, recorded here with its verdict, per-stratum numbers, load and the disclosure that it is biased by the first.

#### E1e — the two measurements after activation — DONE: row 15 FAILS on the second read of v2, on `other` labeling and on fallbacks (2026-10-05)
Scope (frozen): the two measurements E1d left for after activation, and nothing else. (1) Warm latency on the
tuning set only (n ≥ 20; E1d's `/tmp/e1d-warm-latency.py`): median, p90, the count over 9 s, the load, and for each
call whether the router used the warm path or the cold one. (2) One more read of sealed v2 with `heldout.py
evaluate`, as E1c ran it, recorded with its verdict, per-stratum numbers, fallback share, load and the disclosure
that it is the second read. Never tune against v2; never change row 15's thresholds, the 9 s limit, the sealed
sets or the classifier configuration. Locus S (fired `fire-rp-v12-e1e`), lead-inline (why: two ordered
measurements around one sealed file).

- **Before measuring.** The operator activated the daemon 2026-10-05 (migration `0059`; backlog `320091ec2edd`
  done). `classifier-warm.py ping` printed `ready 2`; `launchctl list` showed
  `com.claude.research-classifier-warm` running (pid 22202, started 01:35:13 CDT). The live `router.py` is
  byte-identical to this branch's, and `git diff e259b44cd HEAD -- scripts/research-kit/router.py` adds only the
  warm call path: `CLASSIFIER_BRIEF` and `classifier_argv()` are untouched, so the labeling configuration is
  E1c's `on-pre` (thinking on).
- **Measurement 1, first attempt: the activated daemon answered nothing** (2026-10-05 01:36-01:41 CDT, 1-min load 21.7-24.5; all 96
  rows of the v1 tuning file, one sequential call each through the live router's `classify`):

  | calls | answered by the warm path | answered by the cold path | fell back | wall median · p90 · max | over 9 s |
  |---|---|---|---|---|---|
  | 96 | **0** | 0 | **96 (1.00)** | 0.20 s · 0.43 s · 0.76 s | 0 |

  Every call returned no label with the reason `the warm classifier process reported an error`. The walls are
  the time to fail, not the time to classify, so **this is not a latency reading of a working warm classifier;
  that number is still unmeasured.**
- **Cause, reproduced.** launchd starts the daemon with `HOME` and the runner's `PATH` and nothing else (`ps
  eww` on pid 22202: no `CLAUDE_CONFIG_DIR`). Its `claude` processes therefore read `~/.claude`, which holds no
  login on this machine: the four accounts live in their own config directories, which a session gets from its
  launcher. The classifier's own command line run under `env -i HOME=… PATH=<the runner's>` returns `is_error:
  true`, `Not logged in · Please run /login`. E1c's and E1d's warm timings came from a daemon started inside a
  session, which inherits that session's account, so neither met this.
- **Two defects this exposes, neither fixed here (outside the frozen scope).**
  - `scripts/research-kit/jobs/classifier-warm.sh` gives the daemon no account. Which account pays for the
    classifier is a choice, so the fix is the lead's to scope.
  - `ping` counts processes that are alive, not processes that can answer: it said `ready 2` throughout, and
    migration `0059` reads that ping back as its proof of success. `router.py` then treats a warm process's
    error as the limit spent and makes no cold call. So from activation until the daemon is fixed or unloaded,
    **every re-ask classification on this machine falls back** (0 of 96 answered), which is worse than before
    activation, when the cold call answered about 73% of the time.
- **Measurement 2 was held at that point.** A read then would return 232 fallbacks and tell nothing
  about labeling or latency, and v2's reads are counted. Prepared for it, outside the repo: a `git archive` snapshot of `472ba14c4`'s `scripts/research-kit` and a wrapper that
  calls the snapshot's `router.classify` exactly as the `classify` verb does and appends the answering path
  (warm, cold or fallback), wall and load per call to a side file, so the read can show which path answered each
  item; `evaluate` itself discards the router's reason.
- **Unblocked by wave E1f** (below: the router makes the cold call after a warm failure, the runner serves under a
  logged-in account, `ping` proves an answered classification). The operator re-ran migration `0059` at 10:23 CDT
  (backlog `ac182e40e0bc`, the restart). Checked before measuring: `ping` printed `ready 2` and exited 0; the
  daemon is a new process (pid 14445, started 10:23:51) with `CLAUDE_CONFIG_DIR` set; the live `router.py` and
  `classifier-warm.py` are byte-identical to trunk `3f4ac2c03`; and `CLASSIFIER_BRIEF`, `classifier_argv()`,
  `haiku_model()` and `CLASSIFIER_TIMEOUT_S` in that `router.py` are identical, compared as parsed code, to
  `e259b44cd`'s. The labeling configuration is E1c's `on-pre`, thinking on; only the call path changed.
- **Measurement 1, warm latency on the tuning set** (2026-10-05 10:24-10:33 CDT, 1-min load 8.9-16.1; all 96 rows
  of the v1 tuning file, one sequential call each through the live router's `classify`, which reports the path
  with every answer):

  | calls | answered by the warm path | answered by the cold path | fell back | wall, answered: median · p90 · max | reached the 9 s limit |
  |---|---|---|---|---|---|
  | 96 | **83** | **0** | **13 (0.14)** | 4.62 s · 6.96 s · 8.80 s | 12 |

  Every call went to the warm path and none to the cold fallback. 12 of the 13 fallbacks are warm calls that had
  not answered at 9 s; the other is a warm answer that was not a route label (the model began to act on the
  prompt). Over all 96 the wall is 4.81 s median and 9.00 s at p90. Per call: `/tmp/e1e/warm-latency-2.json`.
  One synthetic call to the daemon from this session overlapped the first seconds of the run.
  **The warm path did not bring the fallback share under 0.10 on the tuning set** (0.14, against 0.17 cold in
  E1c's tuning run at load 28-46): it removes the process start, and the answer with thinking on still takes a
  median 4.6 s and more than 9 s about one time in eight.
- **Measurement 2, the second and last read of v2** (2026-10-05 10:35:23-10:58:47 CDT, 23 min, 1-min load
  7.5-26.9; `heldout.py --set v2 evaluate --record …`, rc 1; router snapshot of `3f4ac2c03`, called through the
  wrapper above). 396 sealed, 164 excluded for rater disagreement, 232 routed:

  | condition | this read (warm) | on the items that got an answer | first read (E1c, cold) |
  |---|---|---|---|
  | regex-matched recall (≥ 0.95) | 24/24 = 1.00 | 24/24, none fell back | 24/24 |
  | regex-missed recall (≥ 0.95) | 34/34 = 1.00 | 34/34, none fell back | 31/34 = 0.91 |
  | pushback recall (≥ 0.95) | 5/5 = 1.00 | 5/5, none fell back | 5/5 |
  | `other` correct label (≥ 0.90) | **21/36 = 0.58 FAIL** | **21/29 = 0.72 FAIL**; 7 fell back, 8 answered wrong | 23/36; 23/26 = 0.88 on answered |
  | fallback share (≤ 0.10) | **45/232 = 0.19 FAIL** | every one stopped at 9 s | 62/232 = 0.27 |

  `evaluate` printed: `stratum other: correct-label rate 21/36 = 0.58, below 0.9` and `fallback rate 0.19 (error
  or timeout at 9 s), above 0.1`. Uncounted line: 3 prompts carry two different relay labels (1 regex-missed, 2
  pushback) and the router relayed all 3. Fallbacks by stratum among the 232: regex-matched 9, regex-missed 29,
  `other` 7; none of the 38 in the completeness strata is a relay-gold prompt, which is why those recalls are
  whole. By thirds of the run: 15 · 17 · 13.
- **Which path answered, for the read.** All 190 answers (187 routed-and-counted items plus the 3 uncounted) came
  from the warm path; none came from the cold call. The 45 fallbacks have no path row: `evaluate` stops a router
  call at 9 s of its own clock, which includes starting Python, so it ended each of those calls before the
  router returned a reason. Their recorded walls are 9.00-9.01 s. Answered calls took 5.01 s median, 7.71 s at
  p90, 8.97 s at most. Per item (router side only, no prompt or rater label):
  `~/.claude/autonomy/research/router-heldout/reading-v2-2026-10-05.jsonl`; paths: `/tmp/e1e/v2-paths.jsonl`.
- **The classifier's labels are not stable between reads.** Of the 151 counted items that got an answer in both
  reads, 129 got the same label and 22 did not, with the same brief, model and thinking setting. On `other`, 4 of
  the items answered both times changed label, and the answered-wrong count went from 3 to 8 partly because this
  read answered 3 more of them. So `other` on answered items read 0.88 once and 0.72 once from one unchanged
  configuration: the first read's "one prompt short" was inside this spread.
- **Row 15 verdict: FAILS.** By E1c's pre-registered rule this is FAIL (labeling), and the fallback share fails as
  well: every completeness stratum passes outright (63 of 63 relay-gold prompts relayed), `other` misses 0.90 on
  answered items, and 0.19 of calls fall back against a cap of 0.10. No program can certify.
- **Disclosure.** This is the second read of v2 and it is biased by the first. Nothing was tuned between them
  and the labeling configuration is byte-for-byte E1c's, but the decision to build and activate the warm path
  was made knowing the first read's numbers (fallback 62/232 = 0.27; `other` 23/26 on answered). v2 has now been
  read twice and should not carry a third verdict for any configuration chosen with these numbers in hand; the
  unlabeled `tuning-v2.jsonl` (92 prompts) is the set to work on next.
- **What remains (decisions for the lead, then the operator).** Not opened here.
  - Fallbacks: the warm path alone is not enough (0.14 tuning, 0.19 on v2). The remaining time is the model's
    answer with thinking on, not the start.
  - `other` labeling: it failed on both reads, and its reading moves by 16 points between runs of one
    configuration, so a single pass over 36 prompts cannot settle it either way.
- Status: **DONE 2026-10-05.** Both measurements recorded; row 15 FAILS. The blocked first attempt landed as
  `58a3a4211`. Learnings: a liveness check that counts processes passed a daemon that could not answer, so a
  measurement's first row must be read before the rest is trusted; `evaluate` drops the router's reason, so a
  path claim needs its own record, and a harness timeout equal to the router's own leaves the slow calls
  unrecorded.

#### E1f — the activated warm classifier answered nothing; three fixes — LANDED and live, awaiting the operator's restart (2026-10-05)
Scope (frozen): three fixes, each with a red-then-green test that replays the incident's shape (a daemon that is
alive but logged out). (1) `router.py`: a warm-path error or no answer falls through to the cold call inside the
9 s limit; only a cold-path failure is a fallback. (2) The runner serves under an explicit, logged-in account
chosen from `claude-accounts --rank general`, verified by a cheap call, and exits non-zero when none is logged in;
re-checked on each restart. (3) `ping` reports answering workers (a real classification round-trip), not a process
count, and the cc-fleet check for the job uses it. Tested under `/bin/bash` 3.2.57 with launchd's minimal
environment. Land, converge, file the restart as one operator step. Never change row 15's thresholds, the 9 s
limit, the sealed sets or the classifier configuration; sealed v2 is not read here (wave E1e owns that read).
Locus S (fired `fire-rp-v12-e1f`), lead-inline (why: three small fixes in four files that share one test suite).

- **The incident** (wave E1e, 2026-10-05 01:36-01:41 CDT; evidence `/tmp/e1e/warm-latency.json`,
  `/tmp/e1e/warm-latency.out`). After the operator ran migration `0059`, the live router on the tuning set
  (n = 96) got 0 warm answers and fell back 96 times out of 96, median 0.20 s, every call "the warm classifier
  process reported an error". launchd started the daemon with no `CLAUDE_CONFIG_DIR`, so its `claude` read
  `~/.claude`, which is logged out ("Not logged in · Please run /login"). `ping` still said "ready 2", because it
  counted live processes, and 0059 read that back as success. `router.py` treated the warm error as the limit
  spent and made no cold call, so from activation every re-ask classification on this machine fell back: worse
  than before activation, with 8.8 s of the limit unspent each time. At 01:39 `launchctl print` showed the job
  still loaded and running (pid 22202, runs 1).
- **A second cause, found here.** With HOME and PATH alone `claude` 2.1.278 answers "Not logged in" under every
  account's config dir, including logged-in ones: it looks its login up in the keychain under `$USER` (measured:
  `USER` unset or wrong fails, `USER` right answers). launchd does set `USER` for a user agent today, so the
  incident needed only the missing config dir; the runner now sets `USER` and `LOGNAME` itself when they are
  absent, so it does not depend on that.
- **Fix 1, router.** `warm_classify` returns `failed` instead of `spent`, and `classify` makes the cold call on it
  with what is left of the same limit. A warm answer that is not one route label stays `unavailable` with no
  second try (that is an answer, not a failure), and a warm process that used the whole limit leaves nothing
  for a cold call. Not done, on purpose: capping the warm wait below 9 s to always leave a cold call room. With
  thinking on, a slow warm answer and a cold call cannot both fit, and a cap would turn slow warm answers into
  cold timeouts; it would also be a change to the limit's use that row 15 did not measure.
- **Fix 2, runner** (`scripts/research-kit/jobs/classifier-warm.sh`). It walks `claude-accounts --rank general`
  (absolute path, bounded at 60 s, read from a file so a killed ranking cannot hold a pipe open), puts one real
  classification through each candidate with the new `classifier-warm.py probe`, and execs the daemon under the
  first that answers with `CLAUDE_CONFIG_DIR` exported. With no ranking it tries every account in
  `accounts.json` order. With none answering it exits 1 and serves nothing. The daemon exits 1 after three
  failed round-trips in a row, so a login that lapses mid-run sends launchd back through the runner.
- **Fix 3, readiness.** The daemon puts one real classification (the router's own brief) through a worker at
  start, every 900 s, and at once when a prompt fails; `ping` exits 0 only while the last one succeeded and is
  fresh, 2 when a daemon is up but no worker has answered, 1 when no daemon answers. Each success rewrites
  `~/.claude/autonomy/research/classifier-warm/answered`. The `fleet.manifest` row moved `staged | 0 | -` to
  `run | 900 | <that stamp>` (the operator ran 0059, so `staged` had expired): cc-fleet reads a daemon that
  stopped answering STALLED and a runner with no login FAILING. Migration 0059's read-back and its
  `migration-verify` line are that `ping`, so `registration-state.sh` and `c10-batch.sh` use it too; a re-run of
  0059 on a job that is loaded but not answering restarts it once (`launchctl kickstart -k`) and waits up to
  90 s for an answered round-trip. The cost is one Haiku classification per 15 minutes plus two per start.
- **Tests, red then green** (2026-10-05, load ~18-20). Red: `tests/research-classifier-warm.bats` run against
  `git archive` of the pre-fix commit `472ba14c4` printed `1..31` with 12 `not ok`: all ten incident replays
  (ping on a logged-out daemon, the stamp, a daemon that stops answering, the exit after three failures,
  `probe`, the three runner cases, and the two router fall-throughs) plus the two migration cases. The red run
  predates one tightening of the stub (it now also needs `USER`), which can only fail more. Green on this
  branch: that suite with `cc-fleet.bats`, `research-router.bats`, `launchd-parity-lint.bats` and
  `install-staged-plist.bats` printed `1..111`, no `not ok`. The runner cases run `/bin/bash` 3.2.57 under
  `env -i` with HOME and PATH only. One test (`after a warm failure only a COLD failure is a fallback`) passes
  on both sides and is a no-regression claim, not a replay.
- **Checked against the real thing** (not sealed data; five ad-hoc prompts). The fixed runner, started with
  `env -i HOME PATH` on a private socket with the real `claude` and the real ranking, picked `next2`, reported
  ready after 20 s, and `router.classify` got five resident answers in 1.41, 5.67, 6.93, 2.98 and 4.53 s. The
  fixed `ping` pointed at the live, still-hollow daemon exits 2.
- **Unchanged:** row 15's thresholds, the 9 s limit, the sealed sets, the classifier's command line and brief
  (`router.classifier_argv()` and `CLASSIFIER_BRIEF` are untouched; the readiness round-trip reuses both).
- **Scope (grown): +two `autonomy-sweep.bats` cases pinned to one reading.** The first land was refused (exit 6)
  on `W1 · the currency pass FIRES` and `W1 · the interval gate HOLDS`, which fail identically on pristine trunk
  `7636a9b78`: `cb7b8b223` (2026-09-30) made a runtime probe close its row only after three readings 6 h apart
  and pinned three sibling suites to one reading but missed this one. The `fleet.manifest` change selects that
  suite, so the red blocked this land and would block any other that selects it. Fixed test-only, as the
  siblings were.
- **Landed and live** (2026-10-05): the three fixes are trunk `10349a46e`, the test repair `21b4bf17e`; all
  nine paths content-verified on `origin/main`; smoke green (7 suites run, 10 carried) on the third attempt
  (one rebase conflict with E1e's record in this file, one exit 6 above, two rounds lost to sibling lands).
  Converged with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`; the live `router.py`,
  `classifier-warm.py` and runner are byte-identical to trunk. Read on the live layer with the old daemon
  still loaded (pid 22202): `ping` exits 2, and the live `router.classify` returned a label in 3.78 s with the
  reason `cold call; the resident one failed`, so the regression is over before the restart.
- **The restart is one operator step**, backlog `ac182e40e0bc`: `bash
  ~/Development/claude-infrastructure/migrations/0059-research-classifier-warm.sh`. The loaded job still runs
  the pre-fix code in memory; the re-run finds it loaded and not answering, restarts it once and waits up to
  90 s for an answered classification.
- **Known gap.** Until that restart, `cc-fleet --table` reads the row HEALTHY: the old daemon writes no stamp,
  and a `run` row whose evidence file does not exist yet is not claimed STALLED. After the restart the stamp
  exists and the row is live. E1e's measurements (warm latency on the tuning set, then the second read of v2)
  wait for the restart.

#### E1g — the fast-plus-careful classifier, then a new sealed set v3 read once — DONE: row 15 FAILS on v3, on `other` labeling alone; recall and fallbacks pass (2026-10-05)
Scope (frozen): operator ruling on decision `b18c74a4f8e1` ("run-both", 2026-10-05: "Proceed with all of your
recommendations"). (1) Build the union classifier in `router.py` and `classifier-warm.py`: per prompt, a fast call
(E1b's brief, `docs/research/router-classifier-e1b-2026-10-04/e1b-classifier.patch`, thinking off) and a careful
call (the as-built brief, thinking on) run concurrently inside the one 9 s limit; a relay label from the fast call
ends it; else a relay label from the careful call within 9 s; else the fast call's label; `unavailable` only when
neither answered. The resident daemon serves both kinds; the cold path does the same with two processes. Red-then-
green tests, `/bin/bash` 3.2 for anything launchd runs. (2) Measure it live on the v1 tuning set (96 rows × 2 reps,
an in-session daemon on its own socket running this branch's code). Pre-registered pass: relay recall ≥ 0.95 and
`other` ≥ 0.90 on agreed rows, fallback ≤ 0.10 at 9 s, borderline relays ≥ 17 of 26. Fail ⇒ record and stop; no
seal. (3) Land, converge, file the daemon restart as one operator step. (4) Mint v3: add `v3` to `SETS`; candidates
= the untouched `tuning-v2.jsonl` (92) plus `heldout-candidates.py` output minus every earlier set and tuning file;
seal all of them (no tuning split); rate with `heldout-rate.py` (two vendors, as v2). (5) Read v3 once with
`heldout.py --set v3 evaluate --record …` through the landed commit's router (an in-session daemon on a `git
archive` snapshot is allowed, the bytes being the landed ones), and record the verdict. Never change row 15's
thresholds or the 9 s limit; never read v1 or v2; never tune on v3. Locus S (fired `fire-rp-v12-e1g`).
- **Why this design** (receipt `docs/research/router-classifier-union-2026-10-05/README.md`, offline replay of
  E1c's per-call tuning data): union of fast + as-built careful reads recall 52/52, `other` 43/44, borderline
  19/26, fallback 1/192; thinking-on alone 51/52 · 36/44 · 18/26 · 33/192; thinking-off alone 51/52 · 44/44 ·
  10/26 · 1/192. Careful arm = as built, by E1c's rule (union with `on-e1b` reads 44/44 · 18/26: within 2 on
  borderline, so the smaller change from trunk wins).
- **Why v3 is minted this way** (measured 2026-10-05 by the lead, counts only, no prompt read): the miner finds the
  same 49 pushback prompts as at v2 (every one already in v1, v2 or `tuning-v2`), and since v2 was mined only 5
  regex-matched, 8 regex-missed and 67 other new prompts. `evaluate` fails a stratum with no agreed item, and
  `seal` refuses a split with no pushback, so a v3 from new prompts alone cannot be sealed. `tuning-v2.jsonl`
  (29 · 42 · 9 · 12, born 2026-10-04 19:59, no labels file) was never tuned on and no tool call ever read it (one
  transcript tool call names it: E1c's `seal` that wrote it), so it is held-out by every rule here and becomes
  v3's core. Risk, stated now: 9 pushback prompts at v2's agreement rate (7 of 37) leave about a 15% chance of no
  agreed pushback item, which reads FAIL by `evaluate`'s rule; that outcome is recorded as such, not re-cut.
- **Built** (trunk `2e2d17cb5`; it was `1e4486e03` on the branch when phase 2 measured it, and `router.py` and
  `classifier-warm.py` are byte-identical in the two). `router.py` `classify` starts the two calls together and
  joins them by the rule above; each call asks the resident classifier first and makes its own cold call when
  that fails, inside what is left of the limit (E1f's guarantee, per call). `classifier-warm.py` keeps two
  processes of each kind, takes the kind in a new `classify` op, and ends the process holding a prompt when the
  asker hangs up, so a careful worker stops thinking once the fast call has settled the label. The careful
  call's brief and command line are byte-for-byte the as-built ones; the fast call adds E1b's notes, the
  delimited prompt, `--disable-slash-commands`, E1b's system prompt and `--settings
  '{"alwaysThinkingEnabled":false}'`, which is E1c's `off-e1b` arm.
  - **One rule beyond the scope's wording, approved by the lead before the measurement** (2026-10-05): with a
    label in hand, the wait for the other call stops 0.5 s before the limit (`DELIVER_MARGIN_S`). Why:
    `heldout.py` stops a router call at 9 s of its own clock, which includes starting Python, so "else the fast
    call's label" handed back at the router's 9.0 s reads as a fallback (E1e: 45 of 232 at 9.00-9.01 s). The
    limit is unchanged; the careful call gets 8.5 s of it when a fast label is waiting. A relay label from the
    careful call is also taken the moment it arrives, without waiting for a slower fast call: the prompt is
    relayed either way.
  - **`ping` and migration `0059`.** `ping` exits 0 only when each kind has answered a real classification and
    the daemon's classifier configuration (each kind's flags, model and brief, hashed) matches the code on
    disk. Until now a re-run of `0059` left a job alone when it was loaded and answering, so it would not have
    moved a running daemon onto new code; it restarts on a non-zero `ping`, so it does now. A daemon from before
    this wave declines the new op at once, so until the restart the live router makes both cold calls. Checked
    against the real loaded daemon (pid 14445, E1f's code): the new `ping` exits 2 ("it runs older code; restart
    it") and the new router's ask comes back `cold` in 17 ms.
  - **Tests, red then green** (2026-10-05, load 50-135). Green: `research-classifier-warm.bats` `1..45`, and with
    `research-router`, `research-router-heldout` and `research-kit-heldout` `1..100`. Red, on a `git archive`
    copy of `dc797dec8`: 17 `not ok` of 56, which are 13 of the 15 new cases plus 4 older cases whose counts
    moved (two calls per prompt, two processes per login probe). The two new cases that pass on both sides (a
    careful relay beats the fast call's `other`; the careful label stands when the fast call fails) are
    no-regression claims, not replays. The runner cases run `/bin/bash` 3.2.57 under `env -i` with HOME and
    PATH only; bare `shellcheck` is clean on the runner and the migration. Two older tests changed for a reason
    other than counts: the exit-after-three-failures case no longer needs to catch the daemon on its socket
    first (at load 121 it had already exited), and the "inside the limit" case reads the router's own clock,
    because the test's clock adds two interpreter starts.
- **Phase 2, the pre-registered pass rule on the v1 tuning set: PASS** (2026-10-05 21:30-21:43 CDT; 96 rows × 2
  reps, one call after another, each made as `heldout.py evaluate` makes it and stopped at 9 s of the caller's
  clock; an in-session daemon of `1e4486e03`'s code on its own socket under a logged-in account; harness and
  per-call data in `docs/research/router-classifier-e1g-2026-10-05/`). Decided before the first call: the run
  waited for the 1-min load to fall under 50 (it was 121-135; it waited 390 s), then ran whatever the load was.

  | measure (`e1c-choose.py`'s definitions) | reading | rule | |
  |---|---|---|---|
  | relay recall, agreed relay rows | 52/52 = 1.00 | ≥ 0.95 | pass |
  | `other`, agreed rows | 41/44 = 0.93 | ≥ 0.90 | pass |
  | borderline relays | 17/26 | ≥ 17 of 26 | pass, at the bar |
  | fallback share at 9 s | 0/192 = 0.00 | ≤ 0.10 | pass |

  Load 25-83 over the run. Wall: median 3.95 s, p90 8.57 s, max 8.63 s. Which call answered: the fast call 178
  times and the careful call 14 times, all 192 through the resident path, none through a cold call. In 22
  calls the careful call was still thinking when the fast label was handed back at 8.56-8.62 s; without the
  0.5 s rule those 22 are fallbacks (0.11, over the cap). The 14 careful answers are relay labels that arrived
  in 3.6-6.7 s. In 3 calls the careful call replied in prose and the fast label stood. 13 of the 96 rows got
  different labels in their two reps. Against the offline replay (52/52 · 43/44 · 19/26 · 1/192): `other` is 2
  calls lower and borderline 2 lower, at twice the load of the data the replay used. A tuning pass is not a
  forecast of a held-out pass (the as-built configuration passed tuning and then read 0.88 and 0.72 on v2).
- **Phase 3, landed and live** (2026-10-05 21:56 CDT): the build is trunk `2e2d17cb5`, the v3 tooling
  `067278db0`, the record above `55753fdc9`; 13 paths content-verified on `origin/main`. The land's smoke was
  shed at load 203, so this wave's own suite runs are the behavioral evidence. Converged with
  `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`; the live `router.py`, `classifier-warm.py`,
  `heldout.py` and migration are byte-identical to trunk, and the live `router.py` is the file the tuning run
  measured (sha1 `81f2837f3216`; only test files changed between the measured commit and the landed one). On
  the live layer with the old daemon still loaded: `ping` exits 2, and one made-up prompt got a label in 2.5 s
  from the fast call's cold path. **The restart is one operator step, backlog `8c7b2d2f4029`**: `bash
  ~/Development/claude-infrastructure/migrations/0059-research-classifier-warm.sh`.
- **Phase 4, v3's candidates, fixed before the seal** (2026-10-05 22:08 CDT; counts only, no prompt read).
  E1c's own caps (110 · 330 · 100) re-pick v2's sample, because the miner keeps the first N prompts of a
  stratum in sha order: with them the dry run sealed 98 (30 · 47 · 9 · 12), which is `tuning-v2` plus 6, and
  `other` would have rested on about 6 counted prompts. Lead ruling, before any seal: mine with larger caps
  (the pool holds 681 regex-matched, 612 regex-missed, 25,434 other and 49 pushback prompts). **Final caps:
  regex-matched 250, regex-missed 1000, other 400, pushback 1000**, with `--days 400` and the prompt history as
  E1c ran it. 7,416 transcripts and 4 history files gave 1,314 mined rows; `tuning-v2.jsonl`'s 92 rows go
  first, so its copy of a repeated prompt is the one kept. `heldout.py --set v3 seal --fraction 1.0 --exclude
  tuning.jsonl --dry-run` printed: **would seal 752 — regex-matched 144, regex-missed 326, pushback 9, other
  273**; 0 to a tuning set; 654 candidates dropped as already in v1, v2, the v1 tuning file or repeated. Every
  stratum meets the lead's floor (100 · 200 · 250, all pushback), so no cap was raised again. From the seal
  on, `tuning-v2.jsonl` holds 92 sealed v3 prompts in the clear: it is no longer a tuning set and must not be
  read by anyone who builds the classifier (E1e's "the set to work on next" is superseded by this line).
- **v3 sealed and labeled, before the read** (2026-10-05). Sealed 22:10 CDT: 752 prompts, the dry run's counts
  exactly; v1 and v2 byte-identical before and after (sha1 `97695cb083d6`, `e00d6f8969d1`); the clear-text
  candidate files deleted. Labeled 22:10-22:34 by `anthropic:claude-opus-5-5` and `openai:gpt-5.6-sol`
  through `heldout-rate.py --set v3 --batch 60`, as v2 was: every prompt has two labels and the raters agree
  on **446 — regex-matched 114 of 144, regex-missed 180 of 326, pushback 4 of 9, other 148 of 273** (v2: 53 ·
  136 · 7 · 36 of 232). `other` is judged on up to 148 prompts, four times v2's 36. Pushback stays thin, as
  stated at the outset: 4 agreed prompts, counted only if their agreed label is a relay label.
- **How the one read is run** (fixed before it starts): `heldout.py --set v3 evaluate --record
  ~/.claude/autonomy/research/router-heldout/reading-v3-2026-10-05.jsonl`, once, with `CC_RESEARCH_ROUTER`
  pointing at `router.py classify` in a `git archive` snapshot of the landed `55753fdc9`, and an in-session
  daemon of the same snapshot on its own socket (the launchd daemon still runs E1f's code until the operator's
  restart, and would leave every call to the cold path). One made-up prompt goes through the whole path first;
  if it gets no label from the resident path the sealed set is not opened. The router's trace beside the
  record says which call and path answered each item. Verdict, as E1c fixed it: PASS is `evaluate` exiting 0;
  anything else is FAIL with the numbers, and v3 is not read again in this wave under any outcome.
- **The one read of v3** (2026-10-05 22:34:09-23:10:12 CDT, 36 min, 1-min load 14-118; router and in-session
  daemon both a snapshot of `55753fdc9`, checked byte-identical to the landed and the live files before the
  first call; the made-up probe was answered by the resident fast call in 0.5 s; rc 1). 752 sealed, 306
  excluded for rater disagreement, 446 routed:

  | condition | reading | |
  |---|---|---|
  | regex-matched recall (≥ 0.95) | 47/47 = 1.00 | pass |
  | regex-missed recall (≥ 0.95) | 24/25 = 0.96 | pass |
  | pushback recall (≥ 0.95) | 2/2 = 1.00 | pass, on 2 prompts |
  | `other` correct label (≥ 0.90) | **113/148 = 0.76** | **FAIL** |
  | fallback share (≤ 0.10) | 0/446 = 0.00 | pass |

  `evaluate` printed one failure: `stratum other: correct-label rate 113/148 = 0.76, below 0.9`. No call fell
  back in any stratum, so all 35 `other` misses are wrong labels, none a timeout. Uncounted line: 4 prompts
  carry two different relay labels (2 regex-matched, 2 regex-missed) and the router relayed all 4.
- **Which path answered, and how fast.** All 450 calls (446 counted, 4 uncounted) were answered through the
  resident path and none through a cold call: the fast call's label 426 times, the careful call's relay label
  24 times. In 80 of the 426 the careful call was still thinking when the fast label was handed back at the
  8.5 s mark (27 · 33 · 26 by thirds of the run); without the 0.5 s rule those are 80 fallbacks, a share of
  0.18. Wall: median 5.42 s, p90 8.57 s, max 8.79 s, none over 9 s. Per item (router side only, no prompt, no
  rater label): `~/.claude/autonomy/research/router-heldout/reading-v3-2026-10-05.jsonl`; the trace of which
  call and path answered: `reading-v3-2026-10-05.paths.jsonl` beside it.
- **What the `other` miss is made of, as far as the router's side shows** (the rater labels were not opened).
  The router gave a relay label to 36 of the 148 counted `other` prompts: 26 from the fast call and 10 from the
  careful call. The careful call can only change an answer by adding a relay label, so it accounts for at most
  10 of the 35 misses; at least 25 are the fast call's own label, and the fast call alone could have read at
  best 123/148 = 0.83 here. So the union is not what fails `other`, and dropping the careful call would not
  pass it either. On the tuning set the same configuration read 41/44 = 0.93: as with the as-built
  configuration (tuning 0.91, then 0.88 and 0.72 on v2), the v1 tuning set overstates `other`. It holds 44
  agreed `other` prompts against 148 here, mined under caps that kept the first 100 in sha order.
- **Row 15 verdict: FAILS.** `evaluate` exited 1 on `other` labeling. For the first time every completeness
  stratum and the fallback share pass on a held-out set that was read once with a configuration fixed
  beforehand (73 of 74 relay-gold prompts relayed; 0 fallbacks against 0.27 and 0.19 on v2). No program can
  certify.
- **Disclosure.** v3 has been read once, with the configuration, the caps, the labeled counts and the way the
  read is run all committed before it (the two commits ahead of this record, author dates 22:09 and 22:33; read started
  22:34). Anyone
  choosing a configuration from here knows that `other` read 0.76 on it and that the router relays about a
  quarter of its `other` prompts; a second read is biased by that. Pushback was judged on 2 prompts.
- **What remains (decisions for the lead, then the operator). Not opened here.**
  - `other` labeling is the one failing condition, and it has now failed on three reads of two sets with two
    labeling configurations (0.88 and 0.72 as built, 0.76 fast plus careful). The fast call's own labels are most of it.
  - The 0.5 s hand-back is what removes the fallbacks; it is in the landed router and applies to the live hook.
  - A tuning set that predicts `other` does not exist: v1's has 44 agreed `other` prompts, and `tuning-v2.jsonl`
    is now sealed inside v3.
- Status: **DONE 2026-10-05.** Learnings: the miner's caps keep the first N of a stratum in sha order, so the
  same caps re-pick the same sample and a new set needs larger caps, not a later date; a land gate under load
  sheds its smoke, so the lints that still ran caught two real defects in new tests (four `! cmd` lines bats
  cannot fail on, one socket bound by absolute path) that a green local run had not; a harness that stops a
  call at the same 9 s the router waits turns every slow careful call into a fallback, and handing the label
  back half a second early is the whole fix.

#### E1h — measure first with every lever open, then one composite read; cap the cost of a false relay — DONE: STOP under RULE 1, no configuration eligible, no sealed data spent; the cost limits are live (2026-10-06)
Scope (frozen): the recommendation of `docs/research/reask-overflag-decision-2026-10-06/REPORT.md` (decision
`aba630ebe329`, workflow `wf_aa8c940c-e38`), adopted whole by the operator 2026-10-06 ("ultracode on each
/explain-decisions. then proceed with all recommendations"). Execute its "Build scope (wave E1h)" section — tracks
A (false-relay cost limits: relay notice, `--requires-gate` narrowed to the routed slug, one-word `misrouted`
override, no relay label carried into envelope turns), B (tooling: miner frame fidelity, `heldout.py draw`,
`heldout-rate.py --tuning`, `--set v2 retire`, subset seal + pinned `instrument.json`, reads ledger) and C
(draw and rate the tuning base, run every arm to completion, replay the frozen rule list, select or STOP, then
land, warm-latency check, seal v4 and one composite read) — under its RULE 1 (selection and stop) and RULE 2
(certification read) exactly as written there. Never change row 15's thresholds or the 9 s limit; never read
`tuning-v2.jsonl`; never tune on v3 or v4; no v3 stratum is read a third time; a FAIL on the composite read is
final for this wave. Locus S (fired `fire-rp-v12-e1h`); track A runs as two teammates inside it on disjoint
files, tracks B and C by its lead (ordered around sealed files).
- **Operator ruling, the five parts the report needs** (all granted by "proceed with all recommendations",
  recorded as decision packet below): (a) the REPORT §4.1 named model edit, only if a non-`haiku_latest`
  configuration wins RULE 1; (b) retiring sealed v2 to tuning data (it has been read twice and E1e already
  barred a third verdict, so the retirement forecloses nothing still available); (c) disclosed second reads of
  v3's pushback items, and of its regex-missed items if fewer than 400 unused regex-missed candidates exist at
  the v4 seal; (d) the `other` frame stays all of the operator's prompts, with only the fidelity fix for strings
  the live hook never receives; (e) the §4.2 edits for the `misrouted` override and for not carrying a relay
  label into envelope turns.
- **Why not the precision pass this lead recommended first** (both critics, independently): tuning a join rule or
  brief over the two haiku calls tops out near 0.90 on v3's own algebra (estimated 0.81-0.87), the two calls are
  wrong on the same prompts so a careful-call veto rarely fires, and haiku 4.5 has a retirement floor of
  2026-10-15, so a haiku-4.5 fix expires within weeks. Only a stronger model showed a measured precision effect
  (Sonnet 5.5 thinking off: 1 of 56 neither-relay tuning rows relayed against haiku's 8, paired 7 to 0, p ≈ 0.016,
  cold median 2.8 s), and that evidence is thin where row 15 scores — hence measure first.
  CORRECTED (2026-10-08, wave E1k): 2026-10-15 is a "not sooner than" floor, not a retirement date. The vendor's
  deprecations page, fetched 2026-10-08, lists `claude-haiku-4-5-20251001 | Active | N/A | Not sooner than October
  15, 2026` with "at least 60 days' notice": no deprecation notice exists yet, and retirement comes no earlier
  than 60 days after one (`model-config.yaml:162-163` agrees). Precedent: Sonnet 4.5 was deprecated 2026-09-30,
  about a day after its one-year floor, and retires 2026-11-30. So a Haiku 4.5 notice could follow its floor
  closely, with retirement around mid-December. Source: `docs/research/reask-e1j-rulings-2026-10-08/REPORT.md`.
- **Stated odds**: about 0.55 that any configuration clears RULE 1 (a STOP is a likely, valid outcome that spends
  no sealed data); about 35-40% that this wave ends with row 15 passing.
- **Pre-registered rules** (verbatim from the report's "Pre-registered rules" section, committed here before any
  tuning call; this commit's author date is the proof of order):

  Both rules are committed before any tuning call.

  **RULE 1**: selection and stop, on tuning data only. Agreed means both raters gave the same label. Borderline rows are those where the raters split and one said completeness or pushback.

  A configuration is eligible only if all three hold:
  - E1 'other': exact-label rate >= 0.95 on the agreed 'other' rows of the fresh sample plus retired v2 (about 220 rows).
    - Why the margin: the tuning-to-held-out drop on record; a winner's-curse allowance of 0.02-0.04; and v4 needing a true rate of about 0.92 to pass 0.90 nine times in ten at about 280 agreed.
  - E2 recall: relay recall >= 0.98 pooled over all agreed relay-gold tuning rows, and >= 0.95 within regex-missed (about 38 rows from v2 and v1).
  - E3 borderline: relay rate >= 0.50 on borderline rows. That is the raters' own relay rate on the prompts they split on.
    - This deliberately replaces E1g's 17/26 bar as a gate.
    - Disclosed: Sonnet's v1 figure, 14/26, was known when this anchor was chosen.

  Selection among eligible configurations:
  1. the highest borderline rate, ties within 0.05;
  2. then the highest 'other';
  3. then a haiku_latest model over others (no section 4.1 edit);
  4. then the lower warm median latency.

  Latency, on the selected configuration through the warm daemon (100 rows): fallback <= 0.03 at 9 s and p90 <= 7.5 s. If it fails, take the next eligible configuration.

  STOP: with no eligible configuration, nothing is landed, v4 is not sealed and no second read happens. The table goes to the operator. Rule 1 uses no v3 data. The v3 router-side splits that circulated during E1h are disclosed as known.

  **RULE 2**: one certification read, with row 15's thresholds unchanged. PASS means 'heldout.py evaluate' over the pinned instrument exits 0:
  - 'other' >= 0.90 on v4 (first read);
  - regex-matched recall >= 0.95 on v4 (first read);
  - regex-missed recall >= 0.95:
    - on v4 if at least 400 regex-missed candidates are unused by any sealed set or tuning file at the v4 seal;
    - otherwise on v3's 25 counted items, as a disclosed second read;
  - pushback recall >= 0.95 on v3's 2 counted items (disclosed second read);
  - fallback <= 0.10, and at least 40 agreed items.

  There is no re-read on FAIL. That spends the method's '1 repair and 1 re-test' (REPORT §6.5 cap row "Router recall below its threshold (gate row 15)"). No v3 stratum is read a third time.
- **Track A, the false-relay cost limits: built** (2026-10-06, two teammates on disjoint files, merged by the
  lead; shas at the land below). `router.py`: every relay turn shows the operator a one-line notice naming the
  route and the word `misrouted`; a typed `--requires-gate <slug>` is a work order only when the slug is the
  routed program's (machine envelopes unchanged); `misrouted`, typed alone right after a relay turn, relabels it
  `other` once, without the classifier, never a work order, counted per program in `route-counters.json`, and
  the Stop check still checks a reply that opens with a verdict; a relay label is no longer carried into a
  machine-envelope turn (it becomes `other`, `by: envelope`). `cc-research pending`/`verdict` and the
  `operator-readout` line show the override count. Method REPORT §4.1, §4.2 and §9 carry the three named edits
  of ruling part (e). Red then green from the lead: `research-router`, `research-relay-check`,
  `research-router-heldout`, `cc-research-core`, `operator-readout-research` `1..108`, 107 ok on the merge, and
  the one red case was the held-out contract test pinning the old any-slug marker, updated with the change.
- **Track B, the tooling: built** (2026-10-06, lead). `heldout.py` gains `draw`, `retire`, `seal --strata/--take`,
  `instrument`, `reads` and set `v4`; `evaluate` without `--set` reads a pinned instrument (each stratum from
  its own set, the item floor and fallback share pooled), writes every read to `router-heldout/reads.jsonl`,
  says in its notes how often each stratum of each set was read before, and adds two lines that cannot fail the
  row: the false-relay rate on agreed non-relay items, and `other` split by store. `heldout-rate.py --tuning`
  rates a clear tuning file; `heldout-candidates.py --live-frame` makes a history row what the hook received.
  Red then green: `research-kit-heldout` + `research-router-heldout` `1..33`, 33 ok; on a `git archive` copy
  of the commit before, 9 `not ok` (the 8 new cases, and the older `--record` key-list case, which now carries
  `set`). Row 15's thresholds and the 9 s limit are untouched.
  - **Frame fidelity, verified before the miner changed** (counts only, 42,097 history rows and 23,875
    transcript prompts): 1,301 history rows are `!` shell lines and 0 transcript prompts start with `!`, so the
    hook never receives them; 2,358 history rows show a paste as a placeholder, and of the 110 found again in a
    transcript 20 held the expanded text and 0 the placeholder. With `--live-frame` the uncapped pool is
    regex-matched 679 · regex-missed 621 · pushback 49 · other 24,173 (other was 25,459 without it).
  - **Sealed v2 retired** (ruling part b, 02:15 CDT): `heldout.py --set v2 retire` wrote its 396 prompts with
    their labels to `router-heldout/retired-v2.jsonl`; `sealed.enc`, `sealed-v2.enc` and `sealed-v3.enc` read
    sha1 `97695cb083d6`, `e00d6f8969d1`, `aabd144ce51f` before and after; `--set v2 evaluate` now exits 2. The
    ledger was first given the reads made before it existed (v1 three, v2 two, v3 one).
- **The tuning base, drawn and rated before any classifier call** (2026-10-06 02:15-02:46 CDT; counts only).
  `heldout.py draw` took 340 `other` and 150 regex-matched prompts from the live-frame pool (815 candidates
  dropped as already in a sealed set or the v1 tuning file; 23,291 `other` and 256 regex-matched fresh ones
  left for v4). Rated by `anthropic:claude-opus-5-5` and `openai:gpt-5.6-sol` through `heldout-rate.py
  --tuning` (the OpenAI rater left one prompt unlabeled in each of two whole runs, so nothing was written; a
  third run in batches of 40 came back whole, 490 of 490). With retired v2 and the v1 tuning file:

  | source | stratum | rows | agreed | agreed, relay gold | borderline |
  |---|---|---|---|---|---|
  | fresh | other | 340 | 204 | 19 | 26 |
  | fresh | regex-matched | 150 | 119 | 48 | 12 |
  | retired v2 | other | 67 | 36 | 5 | 11 |
  | retired v2 | regex-matched | 64 | 53 | 24 | 3 |
  | retired v2 | regex-missed | 228 | 136 | 34 | 33 |
  | retired v2 | pushback | 37 | 7 | 5 | 27 |
  | v1 tuning (2 calls each) | other | 30 | 22 | 1 | 4 |
  | v1 tuning | regex-matched | 29 | 26 | 20 | 2 |
  | v1 tuning | regex-missed | 33 | 19 | 4 | 5 |
  | v1 tuning | pushback | 4 | 2 | 2 | 2 |
  | all | | 982 | 624 | 162 | 125 |

  What RULE 1 is scored on, fixed here: E1 on the 240 agreed `other` rows of the fresh sample and retired v2
  (exact label); E2 on the 137 agreed relay-gold rows of the three completeness strata, and on the 38 of them in
  regex-missed; E3 on the 125 borderline rows. A v1 row counts once per call. Arms and joins as the report's
  C2 and C3 list them: `haiku-off`, `haiku-on`, `sonnet-off`, `sonnet-on` (Haiku 5.5 is not released:
  `model-config.yaml` `haiku_latest` is `claude-haiku-4-5`), and for each thinking-off arm X and thinking-on
  arm Y: X alone, union, careful-confirms, and X relays with Y a veto only, the joins being the code
  `confirm-rule-replay.md` replayed (14 configurations). Harness and scorer:
  `docs/research/router-classifier-e1h-2026-10-06/` (`e1h-tune.py`, `e1h-score.py`), committed with this
  record. 1,078 rows-times-calls × 4 arms = 4,312 calls, rows one after another.
- **Tracks A and B landed and live** (03:19 CDT): trunk `45882bfaa`, 16 paths content-verified by the lander and
  again by `git diff origin/main` (empty) on this wave's paths; the land ran no smoke (the selector answered
  FULL), so the suite runs above are the behavioral evidence. Two lands were refused first, each on a line this
  wave wrote in `research-kit-heldout.bats` (an assertion `&&` absorbed, fixed with the repo's fixer; an unquoted
  list, now an array). Converged with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`: the live layer
  is at the trunk tip. Track A does not change a classifier flag or brief, so the resident classifier's
  configuration id is unchanged (`671326bf353b`) and no restart is owed for it.
- **The tuning run** (02:48-05:01 CDT; 982 rows, 4,312 cold calls, every call to completion; 1-min load 8-75,
  median 18; per-call data `docs/research/router-classifier-e1h-2026-10-06/tune.json`, no prompt text).

  | arm | calls | not one label · timed out at 30 s | over 9 s | median · p90 wall |
  |---|---|---|---|---|
  | `haiku-off` (the live fast call) | 1,078 | 0 · 0 | 1 | 1.5 s · 1.9 s |
  | `haiku-on` (the live careful call) | 1,078 | 5 · 1 | 250 | 6.3 s · 11.9 s |
  | `sonnet-off` | 1,078 | 0 · 0 | 1 | 2.3 s · 3.7 s |
  | `sonnet-on` | 1,078 | 2 · 0 | 0 | 2.5 s · 4.0 s |

- **The replay of the frozen rule list** (`e1h-score.py tune.json`; output kept as `result.txt`). E1 is the
  exact label on the 240 agreed `other` rows of the fresh sample and retired v2; E2 is relay recall over the
  agreed relay-gold rows (163 calls) and inside regex-missed (42 calls); E3 is the relay rate on borderline rows
  (138 calls). A careful label counts only inside the 8.5 s hand-back.

  | configuration | E1 `other` ≥ 0.95 | E2 recall ≥ 0.98 | E2 regex-missed ≥ 0.95 | E3 borderline ≥ 0.50 | relayed, both raters non-relay | fallback | eligible |
  |---|---|---|---|---|---|---|---|
  | `haiku-off` alone | 188 = 0.78 | 157 = 0.96 | 36 = 0.86 | 75 = 0.54 | 42/504 | 1/1078 | no |
  | `sonnet-off` alone | 206 = 0.86 | 154 = 0.94 | 34 = 0.81 | 64 = 0.46 | 10/504 | 1/1078 | no |
  | union(`haiku-off`, `haiku-on`), the live router | 186 = 0.78 | 162 = 0.99 | 41 = 0.98 | 106 = 0.77 | 57/504 | 0 | no |
  | union(`haiku-off`, `sonnet-on`) | 190 = 0.79 | 160 = 0.98 | 39 = 0.93 | 89 = 0.64 | 44/504 | 0 | no |
  | union(`sonnet-off`, `haiku-on`) | 198 = 0.83 | 162 = 0.99 | 41 = 0.98 | 104 = 0.75 | 36/504 | 0 | no |
  | union(`sonnet-off`, `sonnet-on`) | 206 = 0.86 | 158 = 0.97 | 37 = 0.88 | 80 = 0.58 | 13/504 | 0 | no |
  | confirms(`haiku-off`, `haiku-on`) | 186 = 0.78 | 162 = 0.99 | 41 = 0.98 | 102 = 0.74 | 51/504 | 0 | no |
  | confirms(`haiku-off`, `sonnet-on`) | 199 = 0.83 | 157 = 0.96 | 36 = 0.86 | 70 = 0.51 | 6/504 | 0 | no |
  | confirms(`sonnet-off`, `haiku-on`) | 197 = 0.82 | 162 = 0.99 | 41 = 0.98 | 101 = 0.73 | 35/504 | 0 | no |
  | confirms(`sonnet-off`, `sonnet-on`) | 206 = 0.86 | 157 = 0.96 | 36 = 0.86 | 70 = 0.51 | 6/504 | 0 | no |
  | veto(`haiku-off`, `haiku-on`) | 188 = 0.78 | 157 = 0.96 | 36 = 0.86 | 71 = 0.51 | 36/504 | 0 | no |
  | veto(`haiku-off`, `sonnet-on`) | 197 = 0.82 | 154 = 0.94 | 33 = 0.79 | 56 = 0.41 | 4/504 | 0 | no |
  | veto(`sonnet-off`, `haiku-on`) | 205 = 0.85 | 154 = 0.94 | 34 = 0.81 | 62 = 0.45 | 9/504 | 0 | no |
  | veto(`sonnet-off`, `sonnet-on`) | 206 = 0.86 | 153 = 0.94 | 33 = 0.79 | 55 = 0.40 | 3/504 | 0 | no |
  | shown only: `haiku-on` alone | 151 = 0.63 | 160 = 0.98 | 40 = 0.95 | 99 = 0.72 | 34/504 | 253/1078 | not a candidate |
  | shown only: `sonnet-on` alone | 206 = 0.86 | 157 = 0.96 | 36 = 0.86 | 70 = 0.51 | 6/504 | 2/1078 | not a candidate |

- **RULE 1 outcome: STOP.** No configuration is eligible: all 14 fail E1, and the best `other` reading is
  206 of 240 = 0.86 against 0.95 (228 needed). By the rule nothing about the classifier is landed, v4 is not
  sealed, no instrument is pinned and no sealed set is read: v3's strata stay at one read each, and RULE 2 was
  not exercised. Track C steps C4 to C7 did not run. The live router is unchanged from wave E1g.
- **What the table says, for the operator's decision on the `other` floor** (measured above; no further read
  was made to get it):
  - **The `other` test is not failing on relays.** Of each configuration's misses on the 240 rows, 31 to 39
    are a wrong label among the labels that do not relay (`other`, work-order, research-order, new-idea,
    concern); no arm or join moves that number. With no relay mistake at all, a configuration would read at
    best about 0.87 here, still under both this rule's 0.95 and row 15's 0.90. On those same rows the two raters
    themselves agreed on 240 of 407.
  - **Wrong relays are what a model change fixes.** On agreed non-relay prompts the live router relays 57 of
    504 (0.11); `sonnet-off` alone relays 10 (0.02) and the Sonnet pairs under confirms or veto 3 to 6 (0.01).
    On `other` alone the live router's wrongly relayed rows are 17 of 240 and `sonnet-off`'s is 1.
  - **Recall is what the careful haiku call buys, and Sonnet alone does not hold it.** Every configuration
    without `haiku-on` as a relay voter is under 0.98 pooled or under 0.95 in regex-missed (33 to 39 of 42).
    union(`sonnet-off`, `haiku-on`) passes E2 and E3 (0.99 · 0.98 · 0.75) and cuts wrong relays from 57 to 36
    of 504, but its `other` is 0.83.
  - The live configuration reads 0.78 on these 240 rows; v3 read it at 0.76 on 148.
- **Disclosure.** Before the run finished, an interim score on the first 345 rows was read to decide whether
  to pre-build C4 (it showed every configuration at 14 or more `other` misses, with 12 the most the rule
  allows; nothing was pre-built). The rule, the base, the arms and the joins were fixed and committed before
  the first call and were not changed after it; the scorer gained one shown-only column (what an `other` miss
  is made of) during the run. The OpenAI rater's two short runs on the tuning sample are stated above.
- **What remains (the operator's, through the lead; not opened here).** Row 15's `other` condition as written
  (exact label ≥ 0.90) cannot be met by any configuration measured: the ceiling from label confusion that has
  nothing to do with relaying is about 0.87. The choices the table supports are whether `other` should be
  scored on the relay decision instead of the exact label (a method change to row 15), what floor a wrong-relay
  rate of 0.01 to 0.11 justifies now that a wrong relay costs one word, and whether recall near 0.99 with
  wrong relays at 0.07 (union of `sonnet-off` and `haiku-on`) is the trade wanted. None is a build step. The
  fresh pool is intact for a later v4: 23,291 `other` and 256 regex-matched candidates unused.
- Status: **DONE 2026-10-06 — STOP under RULE 1.** Learnings: a floor on the exact label measures the raters'
  seven-way taxonomy as much as the router, so the miss breakdown belongs in the scorer before any floor is
  argued; the land gate lints test files this wave touches line by line, so run bare `shellcheck` and the
  dead-assertion analyzer on a changed suite before the land, not after; a tuning rater needs a stated
  tolerance for one unlabeled prompt, or one stubborn prompt costs a whole run.

#### E1i — row 15's `other` scored on the relay decision; Sonnet-fast plus haiku-careful; one fresh sealed read — DONE: row 15 FAILS on the one read, on fallbacks (0.15) and recall, every recall miss a 9 s timeout; `other` passes at 0.90 (2026-10-07)
Scope (frozen): wave E1i — (1) commit the row-15 method change and its pre-registered read rule before any
classifier call; (2) router.py per-kind model key so the fast call runs Sonnet thinking off, served by the warm
daemon, red-then-green tests, landed and converged, daemon restart filed as one operator step; (3) seal v4 and make
ONE composite read; record the verdict in the plan as wave E1i. Locus S (fired `fire-rp-v12-e1i`), lead-inline
inside it: three ordered steps around sealed files, one small code change each, nothing to fan out.
- **Operator ruling** (2026-10-06, reply "flag-decision-90", decision packet `1f3b8f2d01b7`, option
  `flag-decision-90`): score gate row 15's `other` stratum on "not wrongly flagged as a re-ask" (the relay decision)
  instead of the exact label, floor 0.90; adopt Sonnet-fast (`claude-sonnet-5-5`, thinking off, the E1b brief) as the
  fast call and haiku-careful (as built, thinking on) as the careful call, under the union join (the live join); then
  ONE fresh sealed read. Tuning evidence as the packet states it: 205/216 ordinary prompts unflagged (0.949), recall
  0.99 pooled, 0.98 regex-missed, borderline 0.75; the live router 199/216 (0.921). Receipt
  `docs/research/router-classifier-e1h-2026-10-06/` (`e1h-score.py`, `tune.json`, `result.txt`); write-up
  `docs/research/reask-overflag-decision-2026-10-06/REPORT.md`. Method REPORT: named edit at gate row 15 and §6.6,
  recorded in §9 ("the edit made under decision `1f3b8f2d01b7`").
- **The `other` rule, one denominator for tuning and the read.** `other` = of the agreed `other` items (both raters
  gave the same label), the share whose relay decision matches the gold's: the router relays (completeness or
  pushback) exactly when the agreed label relays. A fallback is a miss, as in every stratum (`heldout.py evaluate`'s
  contract). The packet's 205/216 is the non-relay part of this rule (agreed non-relay items left unflagged); the
  read prints that part too, as the existing shown-only false-relay line. On the E1h tuning base the one rule reads
  (`e1h-score.py tune.json`, new column `other_decision`): adopted pair union(`sonnet-off`, `haiku-on`) **229/240 =
  0.954** (205/216 non-relay unflagged, 24/24 re-asks relayed, 0 fallbacks); the live router 223/240 = 0.929. The
  exact-label rate stays a shown-only line. Every other row-15 threshold (recall 0.95, fallback 0.10, 40 agreed
  items) and the 9 s limit are unchanged.
- **Pre-registered read rule, RULE 2'** (verbatim from the brief; committed before any classifier call, and this
  commit's author date is the proof of order): PASS = `heldout.py evaluate` over the pinned instrument exits 0 with
  `other` (relay decision) >= 0.90 on v4 first read; regex-matched recall >= 0.95 on v4 first read; regex-missed
  recall >= 0.95 on v4 only if >= 400 unused regex-missed candidates exist at the seal, otherwise v3's counted items
  as a disclosed second read; pushback recall >= 0.95 on v3's counted items (disclosed second read); fallback <=
  0.10; >= 40 agreed items. One read, no re-read on FAIL (this is the method's one re-test); no v3 stratum read a
  third time.
- **Configuration under test**: fast = `sonnet_latest` (`claude-sonnet-5-5`), thinking off, E1b brief and system
  prompt; careful = `haiku_latest` (`claude-haiku-4-5`), thinking on, the brief as built; union join; served by the
  warm daemon (migration 0059). Never tuned on v3 or v4; `tuning-v2.jsonl` is never read.
- **Disclosed: the careful call's model expires.** `claude-haiku-4-5` has a retirement floor of 2026-10-15
  (`model-config.yaml` `haiku_latest`; E1h). The careful call follows `haiku_latest`, so after the retirement it
  becomes whatever `haiku_latest` is staged to — Haiku 5.5 when it is released — which is a new configuration id
  and an unmeasured classifier: row 15's verdict from this wave does not carry to it, and it needs its own re-read.
  If haiku 4.5 is retired before Haiku 5.5 is staged, every careful call fails, the union join answers with the fast
  call alone, and `sonnet-off` alone read 0.94 pooled recall and 0.81 regex-missed on tuning (below row 15's 0.95).
  CORRECTED (2026-10-08, wave E1k): 2026-10-15 is a "not sooner than" floor. As of 2026-10-08 no deprecation
  notice is listed, and retirement comes no earlier than 60 days after one; on the Sonnet 4.5 precedent
  (deprecated 2026-09-30, a day past its floor; retires 2026-11-30) that is around mid-December at the earliest.
  Full statement under E1h's "Why not the precision pass".
- **Step 1, the pre-registration: committed before any classifier call** — `d68323586` (author date
  2026-10-06T23:13:41-05:00; it was `02cb72bb8` before the land's rebase). The first classifier call of this wave
  (the `classifier-warm.py probe` below) came after it. `heldout.py evaluate` scores `other` on the relay decision
  and prints the exact label as a shown-only line; red then green `research-kit-heldout` `1..18`, 18 ok (red on the
  commit before: the new case, and the pinned-instrument case's old wording). `e1h-score.py` gained the shown-only
  `other_decision` column; RULE 1's output is otherwise byte-identical (`result-e1i.txt`).
- **Step 2, the model key: landed and live** — `79887ba4c` (trunk `cf73e2c66..79887ba4c`, 9 paths content-verified
  by the lander and again by `git diff` against origin/main, empty; converged with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash
  scripts/deploy-live.sh`, live `router.py` and `heldout.py` byte-identical to trunk). `router.py` `MODEL_KEYS`: fast
  = `sonnet_latest`, careful = `haiku_latest`; the fast call is E1h's `sonnet-off` arm exactly (only `--model`
  differs from the haiku fast call). Configuration id `671326bf353b` → `05e87273a59c`, so the live daemon's `ping`
  exits 2 until the restart. REPORT §4.1 named edit (ruling part (a) of `aba630ebe329`), recorded in §9. Red then
  green: `research-router` `1..37`, 37 ok (on a `git archive` copy of the commit before, the new case fails at the
  fast call's model, and the configuration ids under two `sonnet_latest` values are identical there);
  `research-classifier-warm` `1..45` and `research-router-heldout` `1..16` green. A real `classifier-warm.py probe`
  answered both kinds, Sonnet through the daemon's stream-json path, in 4.5 s, with no warning on stderr. The runner
  (`jobs/classifier-warm.sh`) is unchanged, so no `/bin/bash` 3.2 re-run was owed. Canary cost: the daemon's
  readiness round-trip is one call per kind every 900 s, so about 96 Sonnet calls a day now replace 96 haiku ones.
  - **The land took two runs.** The first (exit 6) failed two wall-clock cases of `research-classifier-warm`
    (`< 1.0 s`, `< 2.0 s`, stub children, no model involved) at 1-min load ~70, and its own exoneration re-run was
    cut. Run side by side 4 times, the pre-change tree failed the `< 2.0 s` case 2 of 4 and the new tree 2 of 4; the
    `< 1.0 s` case passed 3 of 3 on both. The second run landed (smoke partial: `research-kit-heldout` cut by the
    budget; the warm suite `1..45` with no failure).
- **Restart filed as one operator step**: backlog `1eb77a3353d2` ("restart the warm classifier onto the converged
  Sonnet-fast config"), `--run 'bash ~/Development/claude-infrastructure/migrations/0059-research-classifier-warm.sh'`;
  migration 0059's re-run kickstarts a daemon whose configuration differs from disk.
- **Latency through a worktree daemon: not started.** Starting an in-session daemon from the snapshot on its own
  socket (as E1g did) was refused by the permission layer, and the lead ruled it not to be asked for. The latency
  check moves to the live daemon after the restart (below). A cold-only read was ruled out (lead, 2026-10-06 23:44):
  the careful haiku call ran past 9 s on 250 of 1,078 cold tuning calls, so a cold read would cut careful relays
  that the live router gets and bias the one read toward a recall FAIL.
- **v4 sealed and labeled, before the read** (2026-10-06). Candidate pool mined fresh with `--live-frame` and history
  (other 24,200 · pushback 49 · regex-matched 680 · regex-missed 627, against E1h's 24,173 · 49 · 679 · 621). The
  seal's dry run counted **16 unused regex-missed candidates** (< 400), so by RULE 2' regex-missed and pushback are
  read from v3 as disclosed second reads. Sealed 23:17:07 CDT: `--set v4 seal --strata other,regex-matched --take
  other=520,regex-matched=all --fraction 1.0 --exclude tuning.jsonl --exclude tuning-v4.jsonl`, 777 prompts (other
  520, regex-matched 257; 1,305 dropped as already used), sha1 `2a96bbf0d6fd`; v1, v2, v3 byte-identical before and
  after (`97695cb083d6`, `e00d6f8969d1`, `aabd144ce51f`); the clear candidate files deleted. Labeled by
  `anthropic:claude-opus-5-5` and `openai:gpt-5.6-sol` through `heldout-rate.py --set v4 --batch 60`, 777 labels
  each; agreed **other 305 of 520, regex-matched 206 of 257**. Instrument pinned 2026-10-07T04:30:33Z: other v4,
  regex-matched v4, regex-missed v3, pushback v3. Reads before this wave's read (ledger): v3 every stratum once, v4
  none. `tuning-v2.jsonl` was not read; nothing was tuned on v3 or v4.
- **The operator restarted the classifier** (2026-10-07, before 00:05 CDT): the live daemon's `ping` exits 0 and its
  socket reports configuration `05e87273a59c`.
- **Warm latency through the live daemon: FAIL on RULE 1's latency clause, at a load E1h never saw** (2026-10-07
  00:05-00:24 CDT; `e1i-latency.py`, the first 100 rows of the fresh tuning file, the router's `classify` verb
  under `heldout.py`'s 9 s limit; per-call data `docs/research/router-classifier-e1h-2026-10-06/e1i-latency.json`,
  no prompt text). Fallback **8 of 100 = 0.08** (limit 0.03), median 6.07 s, **p90 8.78 s** (limit 7.5), max 9.01 s,
  at 1-min load 41-157, median 75 (E1h's tuning run: median 18). All 8 fallbacks came at load 83-145; no row ran
  below load 41. Answering path: the resident fast call 62 + 21 (the careful call still thinking), the resident
  careful call 9. The ruling adopted this configuration, so the latency clause selects nothing here; it is
  recorded, and RULE 2' carries its own fallback ceiling (0.10).
- **When the one read starts, fixed before it starts** (this commit, before the read): the read runs once the
  1-min load is at most 40 with the 5-min average at most 50, read by `uptime` immediately before the first call,
  because the latency check above put every fallback at load 83 or more and the read has no second chance. This
  fixes only the start time; the read is not stopped, restarted or discarded for anything that happens after its
  first call, and the load is recorded per row in the router's trace. How the read runs: `heldout.py evaluate
  --record ~/.claude/autonomy/research/router-heldout/reading-v4-2026-10-07.jsonl` with no `--set` (the pinned
  instrument), once, with `CC_RESEARCH_ROUTER="python3 <snapshot>/scripts/research-kit/router.py classify"`, the
  snapshot a `git archive` of `79887ba4c`'s `scripts/research-kit` checked identical to the live files, through the
  restarted live daemon, and `CC_RESEARCH_CLASSIFY_TRACE` beside the record. One made-up prompt goes through first;
  if the resident path does not answer it, the sealed sets are not opened. Verdict: PASS is `evaluate` exiting 0;
  anything else is FAIL with the numbers, final for this wave.
- **The one read** (2026-10-07 00:26:59-01:39:45 CDT, 73 min; started at 1-min load 28.0 and 5-min 48.4 per the
  start rule; the made-up probe was answered by the resident fast call in 1.6 s; then load rose: median 53, p90
  125, max 253 over the router's 594 traced answers; **rc 1**). 1,112 sealed items, 417 excluded for rater
  disagreement, 695 routed and counted. Reads ledger: v4 `other` and regex-matched first reads, v3 regex-missed
  and pushback second reads (`reads.jsonl`, 2026-10-07T05:26:59Z); no v3 stratum has been read a third time.

  | condition (RULE 2') | reading | |
  |---|---|---|
  | `other`, relay decision (≥ 0.90), v4 first read | 275/305 = 0.90 (0.902) | pass |
  | regex-matched recall (≥ 0.95), v4 first read | 80/93 = 0.86 | **fail** |
  | regex-missed recall (≥ 0.95), v3 second read (16 unused candidates < 400) | 13/25 = 0.52 | **fail** |
  | pushback recall (≥ 0.95), v3 second read | 2/2 = 1.00 | pass |
  | fallback (≤ 0.10) | 105/695 = 0.15 | **fail** |
  | agreed items (≥ 40) | 695 | pass |

  Shown only, never a failure: `other` exact label 245/305 = 0.80; relayed although both raters gave a non-relay
  label: `other` 10/270, regex-matched 9/113, regex-missed 13/155, pushback 0/2; `other` by store, relay decision
  right: history 179/204, transcript 96/101; prompts the raters relay under two labels: regex-matched 2 of 3
  relayed (1 fell back), regex-missed 2 of 2. Record `router-heldout/reading-v4-2026-10-07.jsonl` and trace beside
  it (mode 600, no prompt text).
- **Verdict: FAIL**, final for this wave, under RULE 2' exactly as committed (`d68323586`, then the start rule in
  `9d6e8f215`). No re-read: this was the method's one re-test (REPORT §6.5 cap row "Router recall below its threshold (gate row 15)").
- **What the failure is made of** (from the tool's record, counts only; no further read was made to get it):
  - **Every recall miss is a fallback.** regex-matched missed 13, and its counted fallbacks are 13; regex-missed
    missed 12, and its fallbacks are 12. Not one relay-gold prompt in either stratum got a wrong label in time.
    `other`'s 30 misses are 19 fallbacks, 10 wrong relays and 1 missed re-ask.
  - **The fallbacks are 9 s timeouts under load.** All 105 ran 9.00-9.03 s. 82 fell in the first half of the read
    and 23 in the second, which tracks the load (it reached 253 in the first half). The router's answering paths:
    resident fast call 400 + 152 (careful still thinking), resident careful call 39 + 3. The warm latency check
    the hour before read the same at load median 75: 8 of 100 fell back, all at load 83-145.
  - So the classifier's labels held: `other` passed the relay-decision floor, wrong relays on agreed non-relay
    prompts were 32 of 540 (0.06; E1h's live router 57 of 504 on tuning), and recall on every prompt answered in
    time was 100% in both completeness strata. What failed is answering inside 9 s on a box whose load ran 2-14
    times E1h's tuning median.
- **What remains (the operator's, through the lead; not opened here).** Row 15 now fails on time, not on
  labels, and the method's re-test is spent. The choices the read supports are about the clock and the machine,
  none a build step of this wave: whether row 15's fallback ceiling and the 9 s limit are measured on a box under
  a stated load bound (the gate has none today, and this read's start rule fixed only the first call); whether
  the careful haiku call (the slow arm: E1h cold 250 of 1,078 over 9 s) stays a relay voter or gives way to a
  faster one; and what a fresh read would need now that v3's completeness strata have each been read twice and
  only 16 unused regex-missed candidates exist. The careful call's model floor (2026-10-15) still applies.
- Status: **DONE 2026-10-07 — row 15 FAILS on the one read.** Shas: pre-registration `d68323586`; router
  `79887ba4c`; pre-read record `97451c774`; start rule `9d6e8f215`; this record (see `git log`). Restart: backlog
  `1eb77a3353d2`, run by the operator before the read. Learnings: a pre-registered read needs a stated load bound
  for its whole duration, not only its start, when the row it settles has a wall-clock ceiling; a smoke suite with
  sub-2 s wall-clock assertions reds a land at load ~70 on any tree (A/B: 2 of 4 on the pre-change tree too); and
  two raters writing one sealed set concurrently is safe only because each writes once, at its end.

#### E1j — trace the fallbacks, tune Haiku 5.5 as the careful call, on tuning data only — DONE: no Haiku 5.5 arm passed (recall 159/163, regex-missed 38/42); every live fallback is an accepted warm call held to the limit (2026-10-08)
Scope (frozen): wave E1j, tuning data only, no sealed set read — (1) fallback tracing in router.py; (2) a Haiku
5.5-capable tuning harness; (3) the selection rule committed to the plan before any call; (4) the Haiku 5.5
tuning run held to 1-min load <= 40; (5) a warm-daemon latency check through the live daemon with the trace on;
(6) record results and the rule's selection in the plan as wave E1j, landed and converged. Locus S (fired
`fire-rp-v12-e1j`), lead-inline.
- **Why.** E1i's one read failed only on fallbacks (105/695 = 0.15 > 0.10), every recall miss a 9 s timeout,
  arriving as stall bursts in which both calls miss together; and `haiku_latest` has since flipped to
  `claude-haiku-5-5` (`d0ffee48a`, landed `bc7894fe2`), so the live careful call is Haiku 5.5, untuned, on
  `/opt/homebrew/bin/claude` 2.1.291 with no `--effort` (configuration id `983448663980`). Decision research:
  `docs/research/reask-haiku55-decision-2026-10-08/REPORT.md`. The operator authorized every recommendation of
  it above 90% conviction; this wave is exactly those. Not in it (below 90%): hardening the warm path (canary
  pool, strike counting, cold hedge, ProcessType) and pinning the careful model, effort or binary in router.py
  with a 0059 restart. The live router's model configuration is left exactly as it is.
- **The selection rule, RULE E1j** (committed here before any classifier call of this wave; this commit's
  author date is the proof of order):

  Scoring: union(`sonnet-off`, careful arm) — wave E1g's join, the live router's — replayed by `e1h-score.py
  tune-h55.json --rule e1j --fast sonnet-off --primary h55-medium --secondary h55-low --diagnostic h55-asbuilt`
  on the 982-row tuning base of wave E1h (1,078 rows-times-calls), the careful label counted only inside the
  8.5 s hold and every call inside the 9 s limit.

  Bars, every one required:
  - relay decision on `other` >= 228/240;
  - pooled recall >= 160/163;
  - regex-missed recall >= 40/42;
  - borderline relay rate >= 69/138;
  - warm-daemon fallback <= 0.03 and p90 <= 7.5 s. Read in this wave on the union's replayed decision
    times from the cold tuning calls (fallback = neither call labeled inside the limit; p90 of the moment the
    router would hand back), because the warm daemon serves only the live configuration and pinning an arm
    into it is outside this wave. A cold call pays a process start the warm path does not, and runs at load
    <= 40, which the warm path under real load does not get; so this reading selects, and the selected
    arm's own warm reading under real load is owed after it is pinned, before any sealed read.

  Arms, all four started at the same instant for a row, rows one after another, every call to completion
  (30 s cap), recorded in `docs/research/router-classifier-e1h-2026-10-06/tune-h55.json` (never `tune.json`):
  - `h55-medium`, the PRIMARY: careful brief and command line, `--model claude-haiku-5-5 --effort medium`,
    claude 2.1.293 by explicit path (`cc-claude-bin`: `~/.claude-293/node_modules/.bin/claude`).
  - `h55-low`: the same at `--effort low`. It counts only if `h55-medium` passes every quality bar and fails
    the latency bar alone.
  - `h55-asbuilt`, DIAGNOSTIC: the live careful call as the daemon runs it, `/opt/homebrew/bin/claude` 2.1.291,
    `--model claude-haiku-5-5`, no `--effort`. Shown, never selectable. If its preflight serves another model
    it is dropped and that is recorded.
  - `sonnet-off`, the fast partner: the live fast call's exact command line and brief, `--model
    claude-sonnet-5-5`, no `--effort`, on the primary's binary (2.1.293).

  Preflight, before the first tuning row: one `--output-format json` call per arm on a made-up prompt prints
  the model served (`modelUsage`); a selectable arm serving any other model aborts the run.

  Selection: `h55-medium` if it passes every bar; else `h55-low` if `h55-medium` fails the latency bar alone
  and `h55-low` passes every bar; else no Haiku 5.5 arm passed, and the selection is the measured Haiku 4.5
  union, union(`sonnet-off`, `haiku-on`) in `tune.json` (wave E1i's), to be pinned.

  Load: the run starts, and each row starts, only while the 1-min load is <= 40; above it the run pauses
  between rows; every call records the load at its start. Data: tuning only. `tuning-v2.jsonl` is never read;
  nothing is tuned on v3 or v4; no sealed set is opened, evaluated, drawn or sealed.

  Warm latency and trace (step 5, after the trace below is landed and converged; the configuration id is
  unchanged, so no restart): `e1i-latency.py` on the first 200 rows of `tuning-v4.jsonl` in file order, through
  the live daemon via the live `~/.claude/scripts/research-kit/router.py classify` with
  `CC_RESEARCH_CLASSIFY_TRACE` set, at whatever load the machine has. Reported, not a selection bar: the
  configuration it measures is the diagnostic one.
- **Order of record.** The rule is `0702f3920` on trunk (author date 2026-10-07T23:20:33-05:00; it was
  `d7b192de4` before the land's rebase). The wave's first classifier call was the preflight at 23:20:38 CDT.
  Preflight, all four arms: `sonnet-off` served `claude-sonnet-5-5` on 2.1.293; `h55-medium` and `h55-low` served
  `claude-haiku-5-5` on 2.1.293; `h55-asbuilt` served `claude-haiku-5-5` on 2.1.291, so no arm was dropped.
- **Step 1, the stall trace: landed and live** — `70f881599` (trunk `c3ed0a381..70f881599`, 7 paths
  content-verified by the lander; converged with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, the
  live `router.py` byte-identical to trunk). With no label in hand 0.4 s before the limit (8.6 s by the router's
  clock), `classify` appends a `stall` row to `CC_RESEARCH_CLASSIFY_TRACE`: each call's path (warm or cold), what
  the resident classifier said, when the warm path ended and the cold call started, and whether it answered.
  No flag, model or brief changed: the live `classifier_config()` still reads `983448663980`, pinned by a new
  `research-router` case, and the daemon's `ping` answered `ready 4` with no restart. Red then green:
  `research-router` `1..38`, 38 ok; `research-classifier-warm` `1..47`, 47 ok; on a `git archive` copy of the
  commit before, both new trace cases fail and the configuration-id pin passes (it pins that nothing moved).
  `research-router-heldout` `1..16` read 15 ok on the first run: the case that expects exactly 1 of 48 items to fall
  back saw one more at load ~130, and it passed on the new tree and on the commit before when they were rerun
  side by side at load 130. The land's smoke ran out of budget (partial), so the suite runs above are the
  behavioral evidence.
- **Step 2, the harness** (in the rule's commit): `e1h-tune.py --arm NAME,KIND,MODEL,EFFORT,CLAUDE_BIN` (no
  `R.haiku_model()`), the served-model preflight, INVALID reasons, binary version per arm, the load gate, and a
  refusal to write `tune.json`; `e1h-score.py` takes arm lists and `--rule e1j`, and with no arguments it still
  reprints `result-e1i.txt` byte for byte.
- **Step 5, warm latency through the live daemon with the trace on** (2026-10-08 00:05-00:21 CDT; 200 tuning
  rows; per-call data `e1j-latency.json`, router trace `e1j-latency.trace.jsonl`, no prompt text in either). The
  configuration measured is the live one (Haiku 5.5 careful call, as built). **Fallback 22/200 = 0.11, median
  4.04 s, p90 9.00 s, max 9.02 s, at 1-min load 82-373, median 154**; FAIL against 0.03 and 7.5 s, but this bar
  selects nothing here.

  | 1-min load | rows | fallbacks | median | p90 |
  |---|---|---|---|---|
  | under 100 | 27 | 0 | 3.29 s | 7.13 s |
  | 100-150 | 68 | 0 | 3.39 s | 7.45 s |
  | 150-250 | 61 | 6 | 4.01 s | 8.95 s |
  | 250 and over | 44 | 16 | 7.31 s | 9.01 s |

  **The trace names the stall.** Every one of the 22 fallbacks left a stall row (none was missing, and none
  failed early). All 22 have one shape: both calls on the warm path, each resident worker had taken the prompt
  and had not answered by 8.6 s, and no cold call was made. A warm worker that accepts a prompt holds the call
  until the limit (`warm_classify` waits the whole remaining time), so the cold fallback never gets a turn. Not
  seen once: the daemon saying no worker was ready (the canary holding the pool), a cold call running slow, or a
  logged-out answer. The fallbacks came in runs (4, 4, 2, 5, 2 and singles), every one at load 151 or more; 3
  more stall rows were rescued by a label at 8.64-8.90 s. So the stall is resident workers of both kinds going
  quiet together under heavy load. That is consistent with CPU starvation of the warm `claude` processes; an
  upstream stall is not excluded, because the daemon logs no timestamps. Answering paths: resident fast call
  130, resident careful call 48. In one row the careful call answered with an e-mail address copied out of the
  prompt instead of a label. The router's trace records a non-label answer's first 60 characters, so the
  committed trace replaces answer text with its length, redacted in place (the land's public-repo hygiene gate
  caught it).
- **Step 4, the tuning run** (2026-10-07 23:21 to 2026-10-08 02:57 CDT; 982 rows, 4,312 cold calls, every call to
  completion; per-call data `tune-h55.json`, no prompt text). It ran 41 rows, then paused through 15 load gates
  totalling 9,242 s (load reached 413 between 23:40 and 01:55), and finished in the low-load window after that.
  The 1-min load at each call's start ran 20.3-40.0 (median 31.5). The binary version is per arm. Each INVALID
  call's answer text is replaced by its category in the committed file; the raw file stays outside the repo,
  mode 600, at `router-heldout/tune-h55-raw.json`.

  | arm | binary · effort | calls | no label (of which refused) | over 9 s | median · p90 wall |
  |---|---|---|---|---|---|
  | `sonnet-off` (fast partner) | 2.1.293 · none | 1,078 | 0 | 20 | 2.5 s · 4.6 s |
  | `h55-medium` (primary) | 2.1.293 · medium | 1,078 | 19 (14) | 0 | 1.8 s · 2.9 s |
  | `h55-low` | 2.1.293 · low | 1,078 | 21 (15) | 1 | 1.7 s · 2.7 s |
  | `h55-asbuilt` (diagnostic) | 2.1.291 · none | 1,078 | 19 (13) | 3 | 1.9 s · 3.7 s |

  "Refused" is the vendor's own error, `API Error: Haiku 5.5 can't help with this` (exit 1). The other no-label
  answers are a label wrapped in formatting, or prose. Every as-built call whose stderr was recorded (its 19
  no-label calls) carried the `[claude-code:unrecognized_model]` warning there (2.1.291 does not register the
  model); its answered calls printed one label alone on stdout, so the warning does not reach stdout on `-p`.

- **The replay under RULE E1j** (`e1h-score.py tune-h55.json --rule e1j …`; output `result-e1j.txt`):

  | union(`sonnet-off`, …) | `other` relay decision ≥ 228/240 | recall ≥ 160/163 | regex-missed ≥ 40/42 | borderline ≥ 69/138 | fallback ≤ 0.03 | p90 ≤ 7.5 s | wrong relays (both raters non-relay) |
  |---|---|---|---|---|---|---|---|
  | `h55-medium` (primary) | 231 | **159** | **38** | 84 | 0/1078 | 4.15 s | 32/504 |
  | `h55-low` (counts only if the primary fails latency alone) | 234 | 160 | **39** | 80 | 1/1078 | 4.23 s | 24/504 |
  | `h55-asbuilt` (diagnostic, never selectable) | 234 | 160 | **39** | 76 | 0/1078 | 4.55 s | 29/504 |
  | for comparison, E1h `tune.json`: `haiku-on` (Haiku 4.5) | 229 | 162 | 41 | 104 | 0/1078 | **8.5 s** | 36/504 |

- **SELECTED: no Haiku 5.5 arm passed — the selection is the measured Haiku 4.5 union, union(`sonnet-off`,
  `haiku-on`) in `tune.json` (wave E1i's), to be pinned.** The primary fails pooled recall (159/163) and
  regex-missed (38/42) and passes everything else. `h55-low` does not count, because the primary did not fail
  the latency bar alone.
- **What the result is made of** (shown only; no rule was changed by it):
  - **Haiku 5.5 removes the latency problem.** No careful call ran past the 8.5 s hold at medium effort, against
    291 of 1,078 for Haiku 4.5 in E1h. The union's p90 decision time is 4.15 s against 8.5 s.
  - **It loses subtle re-asks.** All 4 of the primary's recall misses are regex-missed prompts on which both
    calls said `other`. None was a refusal, a late answer or a fallback. Haiku 4.5's one miss was a correct
    label that arrived after the hold. Haiku 5.5's 14 refusals cost no recall under the union.
  - **Under this same latency bar, the selection would fail.** The rule makes the Haiku 4.5 union the fallback
    selection whatever its latency, and that union reads p90 8.5 s against the 7.5 s bar.
  - **The selected model is about to retire.** `claude-haiku-4-5` has a retirement floor of 2026-10-15
    (`model-config.yaml`; wave E1h), seven days from this record. Pinning it buys a week at most.
    CORRECTED (2026-10-08, wave E1k): false. 2026-10-15 is a "not sooner than" floor; no deprecation notice is
    listed as of 2026-10-08, and retirement comes no earlier than 60 days after one. On the Sonnet 4.5 precedent
    (deprecated 2026-09-30, a day past its floor; retires 2026-11-30), a Haiku 4.5 notice could follow its floor
    closely, with retirement around mid-December. Pinning it buys about two months, not a week.
  - **The fast call ran slow on 2.1.293.** 20 of `sonnet-off`'s calls ran past 9 s (max 18.4 s), against 1 in
    E1h on the PATH binary. The union absorbs this when the careful call answers, but it is a regression to
    watch if the fast call moves to 2.1.293.
- **Rulings a sealed read would need** (the operator's, through the lead; none is a build step of this wave):
  1. **Frame**: is the next read REPORT §6.5's "fixed as tooling" exit (cap row "Router recall below its
     threshold (gate row 15)"), or a third attempt? The method's one re-test was spent by E1i.
  2. **Which careful call to pin**: the rule selects Haiku 4.5, which retires 2026-10-15 and fails this wave's
     latency bar. Haiku 5.5 at medium misses the recall bars by 1 and 2 calls. The rule's outcome stands as
     written, so a different pin is the operator's call, not this wave's.
     CORRECTED (2026-10-08, wave E1k): Haiku 4.5 does not retire on 2026-10-15; that is a "not sooner than"
     floor, no notice is listed yet, and retirement comes at least 60 days after a notice (around mid-December
     on the Sonnet 4.5 precedent). See the corrected line under "What the result is made of".
  3. **Regex-missed data**: a disclosed third read of v3's regex-missed and pushback items. Only 16 unused
     regex-missed candidates existed at the v4 seal, under the 400 a fresh set needs.
  4. **regex-matched**: a disclosed second read of v4's regex-matched items.
  5. **A load bound**, only if the fixed daemon still falls back more than 3% at a load median of 50 or more.
     The daemon is not fixed yet. Step 5's trace names what to fix: an accepted warm call holds the whole limit,
     so the cold call never runs (candidates: a cold hedge, and a warm deadline shorter than the limit). That
     fix was below 90% conviction and is not built here. As it stands: 0 fallbacks in 95 rows under load 150,
     22 in 105 above it.
- **Measured facts beside these rulings** (recorded 2026-10-08 by wave E1k from the decision research
  `docs/research/reask-e1j-rulings-2026-10-08/REPORT.md`; each changes how rulings 1, 2 and 5 trade off):
  - (a) **A hedge started at 4 s can rarely rescue a stalled Haiku 4.5 careful call.** Of each arm's 1,078 cold
    tuning calls, 143 of Haiku 4.5's finish within 4.5 s, against 1,022-1,060 for the Haiku 5.5 arms (python over
    `tune.json` and `tune-h55.json`).
  - (b) **10 of 178 answered rows in step 5 were held to 8.5 s with one call silent** (8 with the careful call
    silent, 2 with the fast; walls 8.50-8.64 s; 4 of them below load 150; python over
    `e1j-latency.trace.jsonl`, re-run by E1k). Each is a recall loss the fallback metric cannot see: the label
    returned was the answering call's alone.
  - (c) **The live warm workers lack `CLAUDE_CODE_CERT_STORE`** (`ps eww` on daemon 62309's 4 workers: absent on
    all 4, re-checked by E1k). A keychain query starved at worker start is therefore a second live explanation
    for the stall, beside the workers starving in the low-priority (PRI 20) band.
  - (d) **Gate row 15 is itself a sealed read, and it has no load bound** (`gate_rows_b.py:351-362` calls
    `heldout.evaluate`; `heldout.py` has no `getloadavg`).
- Status: **DONE 2026-10-08.** Shas: rule `0702f3920` (before any call); trace `70f881599`; latency record
  `49520aed3`; this record (see `git log`). The live router's model configuration is unchanged (`983448663980`).
  No sealed set was opened, and `tuning-v2.jsonl` was not read. Learnings: a model's answer can carry prompt
  text (an e-mail address here), so any field that records a non-label answer must be redacted before it is
  committed; a load-gated run has to be sized to the machine's low-load window, not to its call count (it waited
  2.5 h of 3.6 h); and a squash-landed branch is re-synced with `git rebase --skip`, which a fixup on the work
  branch turns into extra conflicts.

#### E1k — the per-kind cold hedge, the cert-store export, and a real-load A/B of the hedge, on tuning data only — IN PROGRESS
Scope (frozen): wave E1k — B1 the per-kind cold hedge in router.py classify() with its trace and off switch,
red-then-green; B2 CLAUDE_CODE_CERT_STORE=bundled exported in the warm job script (takes effect at the next
daemon start; request none); B3 dated CORRECTED lines in the plan for the Haiku 4.5 retirement claim; B4 the
measured facts recorded beside E1j's rulings; B5 the real-load A/B of hedge on vs off through the live router on
tuning rows, bar committed before the run; record all of it as wave E1k in docs/plans/RESEARCH_PROGRAM_BUILD.md,
landed and converged. Locus S (fired `fire-rp-v12-e1k`), lead-inline.
- **Why.** E1j's step 5 found every live fallback (22 of 22) is a warm worker that accepted the prompt and went
  silent under heavy load: `warm_classify` is handed the whole remaining limit (`router.py:494`, `:420`), and the
  cold call runs only after it returns (`:505-509`), so no cold call ever ran. The decision research
  `docs/research/reask-e1j-rulings-2026-10-08/REPORT.md` made five rulings for the operator (all at or below
  90%, none in this wave) and a build-now set above 90%, which the operator has standing-authorized; this wave
  is exactly that set. The live router's model configuration is left as it is (Haiku 5.5 as built,
  configuration id `983448663980`): no pin, no model change, no daemon restart requested. Not in this wave: any
  sealed set, any pin or effort change, the load bound in `heldout.evaluate` (ruling 5), the Haiku 5.5
  re-tune (ruling 2).
- **B1, the hedge** (`router.py` `classify()` only; [91]). At `HEDGE_AFTER_S` = 4.0 s, scaled by timeout/9, a
  cold twin that skips the warm path starts for each kind whose call is still pending on the warm path, also
  when the other kind already holds a non-relay label; the warm call keeps running, and for each kind the first
  label wins under the unchanged E1g join. With no label in hand, `classify` returns unavailable at a give-up
  point of about 8.7 s (after the 8.6 s stall row, before `heldout.route`'s 9 s kill), so its `finally` kills
  the hedge's process groups. Trace: a `hedge` field per kind (`fired`, `won`) and `hedge_on` on every row, and a
  `held` row when the hold fires with one kind still pending. Off switch `CC_RESEARCH_HEDGE=0`, which restores
  the router as E1j left it (no twin, no early give-up). No flag, model or brief changes, so the configuration
  id stays `983448663980` and no restart is needed.
- **B2, the cert store** ([96]): `export CLAUDE_CODE_CERT_STORE=bundled` in `jobs/classifier-warm.sh` beside the
  PATH, USER and LOGNAME exports, so the warm workers match every interactive session (`settings.json:13`); the
  workers run `--setting-sources local`, so the user settings' env block never reaches them. It takes effect at
  the next daemon start (the pin wave's 0059 restart); no restart is requested here.
- **B5, the real-load A/B: RULE E1k** (committed here before any A/B row; this commit's author date is the proof
  of order). Run after B1 is landed and converged.
  - Run: `e1i-latency.py` through the live `~/.claude/scripts/research-kit/router.py classify` with
    `CC_RESEARCH_CLASSIFY_TRACE` set, on the first 300 rows of `tuning-v4.jsonl` in file order, alternating by
    row: even rows `CC_RESEARCH_HEDGE=1`, odd rows `CC_RESEARCH_HEDGE=0`, so both arms see the same load. Each
    call records its arm, its start time and its 1-min load. Tuning data only; `tuning-v2.jsonl` is never read,
    no sealed set is opened.
  - **Bar: PASS means hedge-on fallback at most 0.03, with at least 40 hedge-on rows above load 150.** FAIL means
    hedge-on fallback above 0.03 with at least 40 hedge-on rows above load 150. p90 and the rows held with one
    call silent are shown only. If fewer than 40 hedge-on rows land above load 150, the run records "high load
    not exercised", the run is repeated in the next high-load window, and no verdict is given until then. Runs
    are not pooled: the verdict is the first run that reaches 40 hedge-on rows above load 150.
  - Reported by load band (under 100, 100-150, 150-250, 250 and over), per arm: rows, fallbacks, median, p90,
    rows held with one call silent; and per kind, hedge fire and win counts.
  - Sidecar, 1 Hz for the whole run: the warm daemon's children (pid, kind from the model on its command line,
    elapsed time, CPU time, RSS, priority, run state). Stall attribution, for each call of a kind still pending
    on the warm path at the hedge point (either arm): its worker is the oldest live worker of that kind in the
    last sample at or before the row's start (`Pool.take` hands out the oldest). It is **still starting** if
    that worker's CPU time rose by 0.5 s or more in the 3 s before the row's start (a ready worker sits idle),
    **starved mid-call** if it had finished starting and was runnable (`R`) in at least half of its samples
    during the call, **waiting, not starved** if it had finished starting and was sleeping (`S`) in more than
    half (a wait on I/O, e.g. upstream), and **unattributed** if no sample of it exists. This decides which root
    fix applies, if any: ProcessType in the plist, or a readiness check in the daemon's pool; neither is built in
    this wave.
  - This checks the hedge on today's as-built configuration. The pinned configuration gets its own check after
    its restart.

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

#### E3b — the two new mechanisms: built-artifact certification and the yield stop — DONE 2026-10-04
Scope (frozen): wave E3b — the two new method mechanisms, specified as named, priced additions to REPORT (new
sections appended, nothing deleted) and built in the kit with red-then-green planted-input tests: (1) certify the
built artifact before "done" (audit row 2); (2) stop contact and the build-to-learn skeleton on yield, tag decisions
below 90 by what blocks them, and a priced per-decision extension on the operator menu (audit row 7).
- Spec: REPORT.md §11 (Stage 9, built gate rows 20–25, registry states `build-certifying` and `build-certified`,
  the forecast split before and after implementation signoff) and §12 (yield stop, value-of-information rule,
  blocker tags, extension; research-gate rows 18 and 19). Record contract: `scripts/research-kit/RECORDS.md`
  "Method v1.2 records". Constants: `lib/kit.py` (`CAPS` v1.2 block, `YIELD_STAGES`, `AS_BUILT_*`, `BUILD_STATES`).
- Both mechanisms apply only to a frame carrying `method_version` "1.2" (`kit.is_v12`; absent reads 1.1), so the
  live pilot and every v1.1 fixture are untouched. Rows 1–17 and their thresholds are unchanged.
- Locus: S for the wave (fired session `fire-rp-v12-e3b`, worktree `rp-v12-e3b`). Inside it, planned T (six
  teammates over one contract); ran as T for two and L (lead-inline) for four. Why L: the machine-capacity gate
  refused 8 of 10 teammate spawns ("8 sessions mid-turn + 1 > active ceiling 8") and says to run the work serially
  in-session rather than retry, so the lead built the pieces it could not hand off. The lead also wrote the spec
  and the shared skeleton (`6a9aa9d2f`: stub rows and verb modules, so the pieces touch disjoint files).

| Piece | Locus | Owns | Suite |
|---|---|---|---|
| instr | L | `lib/built.py`, `lib/cli_built.py`: `cc-research built finding / mutate / contact / soak / show` | `tests/cc-research-built.bats` |
| states | T (`rp-e3b-states`) | `kit.BUILD_STATES` consumers, `gate.sh built-freeze`, the research certificate's split line (`gate_cert.py`) | `tests/research-kit-built-states.bats` |
| brows | T (`rp-e3b-brows`) | `lib/gate_rows_built.py` rows 20–25 | `tests/research-kit-built-gate.bats` |
| rounds | L | `round.sh --kind built` (`lib/round.py`, `lib/cli_cert.py` `built-round`) | `tests/research-kit-built-round.bats` |
| cert | L | `lib/built_cert.py`: the built certificate and the after-implementation forecast | `tests/research-kit-built-cert.bats` |
| yield | L | `lib/yield_stop.py`, `lib/cli_yield.py`, the `budget end` refusal, row 18 | `tests/research-kit-yield.bats` |
| blockers | L | `lib/blockers.py`, row 19, menu extension, `extend-decision` signature, decision timebox fields | `tests/research-kit-blockers.bats` |

- Status: **DONE 2026-10-04** — both mechanisms specified (REPORT.md §11, §12, recorded in §9) and built, every
  rule with a planted-input test red on the skeleton and green after. Shas after the rebase onto E3a and E1c:
  - Spec and skeleton `6a9aa9d2f`.
  - Mechanism 2, `5ac98ae35`: yield 18 of 20 red → 1..20 (the other two are 1.1 no-change controls); blockers 17 of
    20 red → 1..20 (two 1.1 controls; one test passed on the stub's own "unknown fails" text and was tightened).
  - Mechanism 1: instruments, built rounds and certificate `e0c132ba1` (cc-research-built 20 of 20 red → 1..20;
    built-round 12 of 12 → 1..12; built-cert 8 of 8 → 1..8); rows 20–25 `3242f09d7` (51 of 51 red → 1..51, 47
    mutants killed, one per rule site); states, `built-freeze` and the split line `7a977f9eb` (1..25, 26 mutants
    killed); end to end `37be57ee3` (1..4: records written by the real verbs pass the real built gate, which
    certifies and states both forecasts).
  - Existing suites after the merge: gate 1..50, requires 1..17, registry 1..10, research-program-lib 1..8, jobs 1..13,
    router 1..30, core 1..22, round 1..27, cert 1..23, records 1..11, operator-sign 1..13, courier 1..15, sweep 1..13.
- No settings.json change was needed, so there is no migration to run.
- Learnings:
  - The machine-capacity gate refused 8 of 10 spawns at an active ceiling of 8; a six-teammate wave is not
    available on a busy box. Cutting the skeleton first (stub rows and verbs, the record contract in RECORDS.md)
    is what let the lead build the refused pieces inline without touching the teammates' files.
  - Separate pieces over one written contract still need one test that runs them together: the end-to-end suite
    is the only place a verb-written record meets a row that reads it.
  - A test asserting the stub's refusal text ("unknown fails") passes before the rule exists; assert the rule's
    own words. A helper that prints `a, b` prints `a b`, not a tuple: 15 assertions were red for that alone.
  - A fixture word can satisfy the check it was meant to break (`broken` contains `ok`).
- Not built, by scope: reviewer briefs for a built round (the round runs and bundles the snapshot; what a built-round
  reviewer is told is prompt work), a scheduler entry for `cc-research built soak sample` (a launchd plist is the
  operator's to load), and the audit row 7 clause "instrument the pilot so front-end yield can be fitted": the
  stop record and `yield.jsonl` are the data, the fit needs the pilot (E4).
- Coordination with E3a (owner of `intake.py`, `estimate.py`, REPORT §1/§7/§3.12, SKILL.md), none of which E3b
  edits. Done by E3a at this wave's request: `intake.py` stamps `method_version: "1.2"` into a new frame and counts
  the two build states as registered, so a new program runs rows 18 and 19. Still open, in E3a's files: the
  contract-page ceiling does not yet add §12's yield ceiling (up to 3 extra stage budgets on each of stages 3 and 5)
  or §11's Stage 9 budget, and SKILL.md's stage walk does not yet name Stage 9 or the yield rule.
  Closed by E3c, with the briefs and the soak scheduler named under "Not built" above.

#### E3c — close E3b's four gaps so a v1.2 program runs end to end — DONE 2026-10-04
Scope (frozen): wave E3c — close those four gaps so a v1.2 program runs end to end: (1) the contract page's ceiling
includes the §12 yield ceiling and the §11 Stage 9 budget; (2) SKILL.md's stage walk includes Stage 9 and the
yield-stop rule, citing §11–§12, append-only with a dated v1.2 note; (3) reviewer, rater and verifier briefs for
`round --kind built`; (4) a soak scheduler (staged plist, `cc-research job soak`, c10 migration, activation filed);
then one end-to-end dry walk of a fixtured v1.2 program, intake → Stage 9 → certificate, by the kit's verbs only.
Scope (grown): +`cc-research ceiling` reads the same v1.2 ceiling as the contract page (it printed the §6.1 figure
alone, so the two disagreed); +a build-state render drops the research lines' "Built –" placeholder (the walk
showed the render saying "Built –" and "Built: certified" together).
- Locus: S (fired `fire-rp-v12-e3c`), L inside. Why L: four items of 25–150 lines each plus a walk that has to join
  them, and E3b measured the capacity gate refusing 8 of 10 spawns.
- **1, the ceiling.** `intake.v12_ceiling` (one computation, read by the contract page and `cc-research ceiling`):
  the §6.1 ceiling + (4 − 1) × the stage 3 and 5 budgets (§12's price: lite 5.25, standard 12, full 18) + Stage 9
  at the §6.5 overrun line (1.5 × 1, 2, 3 days, the way §6.1 counts stages 1–6). Lite reads "about 18.75 days
  (12 + 5.25 + 1.5)", standard 43; the 24 h soak is printed as elapsed time outside the ceiling. A 1.1 frame is
  unchanged. Tests: research-program-intake 2 of 3 new cases red (the third is the 1.1 control) → 1..24;
  cc-research-core's v1.2 ceiling case red → green.
- **2, the skill.** SKILL.md gains, nothing deleted (one line's full stop became a semicolon): a dated note on
  ruling `1bf69e5c1775`; the `extend-decision` signature among the rails; a section "Stages 3 and 5 end on yield;
  decisions below 90 are tagged" (§12.1–12.3 with the verbs `yield show/find`, `budget end`, `menu`); a Stage 8
  note (19 rows, the split forecast); and "Stage 9 — certify the built artifact (§11)" (built-freeze, the four
  instruments, built rounds with the new briefs, built-run, caps). The test reads K, the built-round caps and the
  ceilings from `kit.PROFILES`/`CAPS`, so a constant change turns it red.
- **3, the briefs.** `briefs/built-reviewer.md` (8 code-native lenses: acceptance, harness, as-built-env,
  time-boundary, failure-path, plan-drift, safety, operator-intent; every finding carries a `test_cmd` that fails
  on the snapshot; the panel shape is the one `courier.extract_panel` reads), `built-verifier.md` (runs the
  `test_cmd` with an empty `HOME`, `PATH=/usr/bin:/bin`, `/bin/bash` 3.2; CONFIRMED / REFUTED / NO-REPRO, NO-REPRO
  being the kit's `rejected-no-repro`), `built-rater.md` (RUBRIC.md's seven clauses verbatim, unchanged, plus "no
  failing test, never material"; a surviving mutant meets clause b). Tests: research-program-briefs 6 of 15 red
  (the signoff case now expects every `operator_sign.ACTIONS`) → 1..15, with a mutation control on the lens table.
- **4, the soak scheduler.** `cc-research job soak` (lib/cli_jobs.py): one `built soak sample` per program in
  build-certifying only; a failing sample fails the pass and names the check. The shared runner
  `research-job.sh` accepts `soak`; `launchd/staged/com.claude.research-soak.plist`, hourly at :17, declared
  `staged` in `launchd/fleet.manifest` (cc-fleet's label count 49 → 50, reason beside it). Migration
  `0058-research-soak-job.sh`, c10, 0051's shape for one label. Not a sixth job in 0051: 0051 is already run and
  ledgered (its five labels are loaded on this box), and the converger files a c10 step once, so an added job would
  never reach the operator. Activation filed: backlog **`0881ed9c8371`**
  (`bash ~/Development/claude-infrastructure/migrations/0058-research-soak-job.sh`). Tests: research-jobs 9 new
  cases all red → 1..22 under `/bin/bash` 3.2.57 (dry-run, refusal before converge, install and read-back with a
  stub launchctl, re-run no-op, shellcheck bare).
- **The dry walk** (`tests/fixtures/research-kit/walk_v12.sh`, re-run by `tests/research-kit-v12-walk.bats` 1..6;
  full output `docs/research/research-program-v12-walk-2026-10-04/WALK.md`). One fixtured registry, stub courier,
  no vendor, no live pilot. Part A, a fresh program `walk` by verbs: `intake.py init` stamps 1.2; the contract page
  and `cc-research ceiling` both print about 18.75 days; stage 3 with a failing probe reads "keep probing · 1 finds
  in the last 6 probes, 24 per day × escape cost 3 d = 72" and `budget end` refuses (exit 2); six quiet probes later
  "stop: the stage is quiet … 0 finds" and `budget end` records it. Part B: stages 2–8 cannot be walked by verbs
  without vendors and the operator's signature, so the known-good fixture `demo` stands in at a signed research
  certificate, its hand-written Stage 9 records deleted; then by verbs only: `built-freeze` → build-certifying; BF-1
  `material open` (its test failed), `finding fix` exits 1 before the fix; the fix commit, `--refreeze`, BF-1 `fixed,
  its repro passes`; BF-2 `rejected-no-repro`; `mutate` 10 killed, 0 survived; two as-built contact runs under
  `/bin/bash 3.2.57(1)-release`; `cc-research job soak` 25 times an hour apart; built rounds b1 and b2 quiet; and
  `gate.sh built-run`:

  ```
  20. Built snapshot   PASS   snapshot …; 2 build wave(s) named, all recorded done
  21. Repro            PASS   1 material finding(s), all fixed and re-run green; 1 rejected-no-repro
  22. Harness mutation PASS   kill rate 10/10 = 100%; 0 equivalent, 0 invalid
  23. As-built contact PASS   1 as-built probe(s) and 1 acceptance row(s) run as built
  24. Soak             PASS   25 sample(s) over 24.0h after 0 restart(s)
  25. Built rounds     PASS   stop quiet after 2 counted built round(s) of 3
  BUILD-CERTIFIED demo
  Before implementation signoff: 1 material change observed (forecast about 3.8)
  After implementation signoff: forecast about 0.2; at most 3 at 95% (mutant kill rate 10 of 10, lower bound 0.72; …)
  ```
- Learnings:
  - The Edit tool's format hook reflowed all of `intake.py` (the ruff learning again); edits to unformatted kit
    files go through a Bash-run Python replace so the diff stays the change.
  - The walk found what no unit suite could: each render suite fixtured one state, so "Built –" beside "Built:
    certified" only showed when one program passed through both. Keep the walk in the gate.
  - `rm -rf` is refused in fired sessions; a walk that needs a clean directory takes a fresh `mktemp -d` per run.
- Open, outside this scope: §11 says "before you sign the implementation", and the kit has no implementation
  signature (`operator_sign.ACTIONS` has none); SKILL.md says signing it is the operator's. Closed by E3d below. Rows 1–19 were not
  re-run in the walk (by §11 they are not re-run at Stage 9; the fixture's research certificate stands in).

#### E3d — the implementation signature, end to end — DONE 2026-10-05
Scope (frozen): wave E3d — add the implementation signature end to end: (1) a new signing kind in the research
namespace of `scripts/lib/operator_sign.py`, content-pinned to the built certificate (path + hash), with the same
three protections, and a `cc-research` verb that renders what is being signed and prints the exact operator command;
(2) the registry transition build-certified → implementation-signed (writer stays gate.sh/lib/kit.py), a gate
condition so a build-certified program's "done" (and `handoff-fire.sh --requires-gate` for post-signoff waves) needs
the signature, and the certificate render shows the signature state; (3) REPORT §11 and SKILL.md's Stage 9 walk gain
the signing step, appended and dated; (4) the fixtured dry walk goes through the signature by a fixture signer on
the operator path, and an agent-ancestor signature is refused.
Scope (grown): +the two existing ancestry tests in `tests/operator-sign.bats` made deterministic (they convicted
only because the suite ran under a real claude; see Learnings).
- Locus: S (fired `fire-rp-v12-e3d`), L inside. Why L: one signing kind threaded through eight small readers
  (5–40 lines each) that all share one state function; splitting it would have split that function's contract.
- **1, the signing kind** (`1d8feb56c`). `research:<slug>/implementation` in `operator_sign.ACTIONS`. It needs
  `--evidence`, refuses under a claude ancestor (exit 3, before anything else is read), refuses unless the registry
  reads build-certified or implementation-signed and a built certificate exists, and pins the newest
  `built/BUILT-CERT-v<n>.json` by records-relative path and git blob hash. One reader,
  `operator_sign.implementation_state`, returns `signed | unsigned | void | stale | superseded`; only `signed`
  authorises, and `implementation_words` prints the other four by name. `cc-research built signoff --program P`
  (read-only, lease-exempt) prints the certificate's lines, the pinned path and hash, the state and the operator's
  command. `bin/cc-signoff` accepts the row and, after a signature, runs `gate.sh built-signed` itself so the
  operator's step stays one command (a refused move is printed with the re-run command; the signature stands).
- **2, the registry and the gates** (`1d8feb56c`). `kit.STATES` gains `implementation-signed` (`kit.IMPL_SIGNED`,
  `kit.STAGE9_STATES`). `gate.sh built-signed`: build-certified → implementation-signed only on `signed`; run on an
  implementation-signed program whose signature no longer holds, it sets build-certified back and exits 1.
  `gate.sh close` refuses a build-certified (or no-longer-signed implementation-signed) program.
  `gate.sh requires` admits a wave in implementation-signed only while the signature holds, and
  `--after-signoff` (`handoff-fire.sh --gate-after-signoff`) refuses a post-signoff wave in every other state.
  `built-freeze` from implementation-signed needs `--refreeze`; `built-run` there is refused; the next certificate
  needs a new signature (the old one reads `superseded`). `gate.sh render`'s built line ends "· implementation
  signed by the operator <date>", "not signed", or the void / stale signature by name, read from the sealed log at
  every render. The state is active until close in every reader: `research-program.sh`, `completion-assert.sh`'s
  copy, the prompt nudge, the router's block, `intake.py`, the scheduled jobs.
- **3, the texts** (`1d8feb56c`). REPORT §11 gains "Signing the implementation" (dated 2026-10-05, five numbered
  steps, nothing deleted); SKILL.md gains the rail bullet and Stage 9 step 6; RECORDS.md gains the state and the
  record shape.
- **4, the walk** (`dad4e698b`; `tests/research-kit-v12-walk.bats` 1..11, the signature leg appended, dated, to
  `docs/research/research-program-v12-walk-2026-10-04/WALK.md`). After the built certificate: `built signoff`
  renders; `built-signed`, `close` and `requires --after-signoff` are refused unsigned; `cc-signoff` under a shell
  named claude is refused with exit 3 and 0 records written; the fixture signer
  (`tests/fixtures/research-kit/fixture_signer.py`: `bin/cc-signoff` itself with an operator's ancestry, refusing the
  live store, its chain starting `fixture-signer`) signs, the registry reads implementation-signed, the render says
  signed, the post-signoff wave is clear and `close` passes.
- Tests, red before the code and green after: operator-sign 1..23 (E3d cases 14–23), research-kit-built-states
  (17 E3d cases; 1..42 after one moved out), research-kit-built-e2e 1..7 (5–7): 27 red of 73 before, 73 of 73
  after. Every research and signing suite together: 1..652, 0 red. The two `handoff-fire --gate-after-signoff`
  cases landed in research-kit-requires (1..19, `5e4e6ec6c`), with a control. Two E3d cases passed
  before the code for the wrong reason (a parse refusal also exits 2) and were tightened to assert the refusal's
  text. The walk suite was run against the pre-change tree in a throwaway worktree: 7 of 11 red, then 1..11.
- Decisions made here, for the reader who would have chosen otherwise:
  - implementation-signed is **active until close** (exemption, research block, jobs), not a second closed state:
    a completeness question after signoff should still be answered by the render, which now carries the signature.
  - `close` is gated from build-certified only. From build-certifying it stays open: an abandoned Stage 9 is not a
    "done" claim, and gating it would leave the operator no way to close a program whose built gate cannot pass.
  - The registry never proves the signature. Every gate re-reads the sealed log, so a hand-edited registry state
    of implementation-signed with no valid signature closes nothing and fires nothing.
- Learnings:
  - `bash -c '<one command>'` execs the command in place, so a "fake claude shell" wrapper vanishes from the
    ancestry and the refusal test convicts only on the suite's real ancestors: green in a Claude session, red (it
    would sign) under launchd. `; exit $?` after the command keeps the shell as the parent. Measured with `ps`
    2026-10-05; the two older tests carried the flaw since wave A2.
  - The land gate found three things the suites did not: a handoff-fire case in a suite that does not pin
    handoff-fire's seams (moved to research-kit-requires, which does); `[ A ] && [ B ]` as a bats assertion, where
    a false A is absorbed; and the same shape in `walk_v12.sh`, where under `set -e` a false left side does not
    stop the script, so the walk's two state checks could not fail. One test per line in both.
  - The land's selector answered FULL, so no smoke ran at the land; the suites above were run by hand before it.
  - A command that bundled a heredoc edit, `rm -rf` of a scratch dir and the walk run was refused whole by the
    permission layer. The edit went through the Edit tool and the run took a fresh `mktemp -d`; the delete was
    dropped, not re-spelled.
- Not built: no signature exists on any real program, and the live pilot's records were not read or written.

#### E4 — re-sign the pilot contract (v1.2 (d), operator half) — after E3
- Operator: re-render TM2's contract on the measured forecast and re-sign it, with rulings 1 and 4 re-presented at
  measured numbers. Agent-side work stops at presenting the packet.
