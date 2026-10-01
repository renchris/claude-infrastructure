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

### A1 — prompts and standing-rule exemption
- REPORT.md §8 item 2 (cites the exact lines) and item 3; §3.1 ruling 2.
- Key the exemption on the program registry resolution (§10 item 10), not on a DoD marker no step writes.
- Status: **landed and live 2026-10-01** (`7310c4ac8` prompts, `7cca316c0` registry lib, `a08892a16` rules,
  `b1fd89b6a` hook; converged, both live copies byte-equal to trunk). §10 item 10 closed by option 1: everything
  keys on `scripts/lib/research-program.sh` (`rp_resolve_cwd`, `rp_is_active`; registry contract in its header,
  which A2's `gate.sh` writes). Also fixed the same quota in two uncited siblings (`deep-research-sonnet.md`,
  `frontier-derivation.md`). Learnings: the land gate requires `$HOME` fixtured in every new suite and refuses
  `! ( … )` assertions errexit cannot reach; the slim variant's `derived-from` stamp was already stale and was left
  alone.

### A2 — signing library, hand-run kit, registry
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
- Status: built and gate-green on branch `rp-a2-kit-signing`, held for wave A1's land (the registry test sources A1's
  resolver). 11 suites, 136 planted-input tests: `tests/operator-sign.bats` (13), `research-kit-probe` (10), `-seed` (9),
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
  - `kit.probe_level` first let a probe whose negative control RAN AND PASSED earn its level; the probe suite's first
    planted input caught it.
  - Interactive `zsh -lic` writes terminal escape sequences onto the answer line; the doctor fences answers with
    sentinels.

### A3 — calibration study
- REPORT.md §8 item 14; §6.6 lists what it measures. Output: `docs/research/research-calibration.jsonl` and a report;
  changes to the report only as priced edits to named sections (profile table, caps, seed counts).
- Status: not started.

### B1, B2, C
- Expanded with file:line detail when A2 lands.

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
