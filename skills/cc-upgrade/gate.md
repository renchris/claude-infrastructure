# gate.md — do our ways of working still work on the candidate? (phases P4, P6)

Decide whether a candidate **(binary + model)** is safe to activate by *running* every way we work
against it as headless probes, then reading the artifact. The tool is `scripts/cc-upgrade-gate.sh`;
this file is its policy.

## Why

**Operator mandate:** *"we ALWAYS upgrade immediately to a new model IF all our ways of working
continue to work."* The hard part was never the upgrade; it was knowing, without weeks of soak,
that nothing we depend on regressed. Each probe asserts on the ARTIFACT (`modelUsage` / argv /
exit code / a real spawn), never on a claim or a recalled fact. It kills the failure in both
directions:

- **False PARK** — a *presumed* demotion (an effort rung "wrong", "≈ the frontier tier at half
  cost", spawn lifecycle "probably broke") that turns out fine. Presumption costs the immediate
  upgrade the mandate demands (historical: the Opus 5 episode).
- **False GO** — flipping the SSOT while a way of working silently regressed (a demoted teammate
  spawn, an auto-mode wall, a resume regression). The gate catches it as a RED check before
  anything mutates.

A GREEN verdict is *earned*; a RED verdict *names the specific thing that broke*.

## Run it

```bash
~/.claude/scripts/cc-upgrade-gate.sh <binary-path> <model> [accounts…]
~/.claude/scripts/cc-upgrade-gate.sh ~/.claude-<NNN>/node_modules/.bin/claude <model-id> next next2 next3 next4
```

- **stdout** = machine-readable JSON (the full per-check report); **stderr** = a human summary;
  **exit 0 = GREEN, 1 = RED**. Fail-closed: any check FAIL ⇒ RED; a crashed probe that emits no
  result is scored FAIL, not skipped.
- **Env knobs:** `GATE_SPAWN=0` skips the expensive spawn probes (#7/#8/#9) for fast iteration —
  they SKIP, never FAIL, so the verdict stays honest about what ran. `GATE_RETRIES=<n>` bounds
  retries for flaky probes (the auto-mode classifier is flaky); default 3. `NO_COLOR=1` plain.
- Accounts are the auto-mode config names (`next` `next2` `next3` `next4`); `[0]` is primary. Pass
  the full sweep to prove entitlement on every account you will actually run on.

## The gate-run set — one run is not always enough

Checks 1-4 and 7-11 all run under `GATE_MODEL`, the model argument. So one run certifies the
binary move only for that model. **Run the gate once per model in
{`versions.opus_latest`} ∪ {the new id, if the model lane is on}, each on the candidate binary.**
When the new model is the lead model, that set has one member. When it is not (a worker-tier
release), the whole fleet's lead still moves binary with it, and a run under the new id alone never
tests the lead on the new binary. Record every run in the ledger.

## The 15 checks

Each is one file `lib/cc-upgrade-gate/check*.sh` defining a `check_NN`, auto-discovered — adding a
probe is a new FILE, never an edit to the orchestrator.

| # | check | what it proves (self-evidencing) |
|---|---|---|
| 1 | binary-registers | `--model X --print` exits 0 with `modelUsage` carrying X — the binary *knows* the model (the loud-fail floor; cc-model-registered is its cheap pre-read). |
| 2 | entitlement | the account is server-side entitled to X — a live completion, not a 403 / server gate. |
| 3 | auto-mode | **the crux** — X engages under `--permission-mode auto` (drives its own turns, no demotion). This IS the operator's auto-mode live-test (§ GREEN). |
| 4 | effort-ladder | every rung low · medium · high · xhigh · max is accepted for X, whatever its family; high must also register X in `modelUsage`. The SSOT routes rungs per use case, so a rejected rung would silently degrade every session routed to it. |
| 5 | launcher | the real launcher body passes the right binary / model / flags to the candidate — an effect-read on recorded argv, not a grep. Its expected `--model` is `versions.opus_latest` and its `--effort` is `effort_defaults.default`, both read from the SSOT. |
| 6 | depth-containment | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` REACHES the binary on both surfaces (delivery). |
| 7 | agent-teams † | a real teammate spawns and runs (marker `TEAMMATE_OK`) with no silent demotion — `modelUsage` still carries X (GH #43869). |
| 8 | workflows † | a 1-agent Dynamic Workflow runs and returns a non-null result (marker `WF_OK`). |
| 9 | subagents † | a fire-and-forget research subagent spawns and returns (marker `SUBAGENT_OK`). |
| 10 | hooks-fire | the binary triggers lifecycle hooks — SessionStart + Stop, injected via `--settings` so the real config is untouched — and the repo hook scripts parse clean. |
| 11 | permission-nonblock | a benign command runs WITHOUT a permission wall in auto mode (`permission_denials==[]`). |
| 12 | resume | `cc` routes a resumable session to `claude --resume <sid>` (effect-read), and `ccr`'s version→launcher routing line is intact. |
| 13 | mcp | session-connected MCP servers resolve on the candidate (`mcp list`, ≥1 `✔ Connected`); none configured ⇒ SKIP. |
| 14 | authstore-writeloss ‡ | the way of working is STAYING LOGGED IN: reads (never executes) the candidate's credential-write path and reports whether the upstream write-loss window is `FIXED` / `STATUS-QUO` / `WORSE` / `UNREADABLE`. Backed by `scripts/cc-authstore-probe.sh`; the defect is `docs/research/vendor-report-cc-authstore-write-loss.md`. |
| 15 | depth-effect | the binary still REFUSES a spawn at depth ≥ max (effect): reads the candidate's own depth gate, where an inclusive `>=` is a flat topology and an exclusive `>` is GH #84974. #6 proves delivery; only #15 proves containment. |

† #7 / #8 / #9 are the spawn probes gated by `GATE_SPAWN`.

‡ #14's *ordinary* answer is SKIP, deliberately. The defect is upstream, so a candidate that merely
matches the binary we already run is not a regression and must not park an upgrade. It goes
**FAIL** only on a change for the worse (`WORSE`, or `UNREADABLE`, fail-closed). **PASS is the
news**: the vendor closed the window, so close backlog `4adbeab56aa7` and revisit the
compensations in `f8178bfe`.

### Coupling to know about: #5 keys on `opus_latest`

check05's expected `--model` comes from `versions.opus_latest`, not from `roles.lead_default`. So
a Case D launcher repoint off Opus (model.md) turns #5 RED on a correct launcher. That RED is the
coupling, not a regression: record it, and change check05 in the same diff as such a repoint.

### A feature being adopted gets its own probe

The 15 checks prove *no regression*. They do not prove that a NEW feature works here. When a run
adopts a harness feature (feature.md), add `lib/cc-upgrade-gate/checkNN_<feature>.sh` before
activation, so the next binary move re-proves it. Update this table and the count in the same diff
(tests/cc-upgrade-skill.bats compares them to the files).

## POLICY — the decision tree

Read the verdict, then act. **The gate output already names the failing way of working** — do not
re-derive it.

### ALL GREEN ⇒ activate now (P6, binary first)

Every way of working holds. Activation is an idempotent, fail-closed script, one per release:
`docs/activation/pending-activation/NN-<slug>-activate.sh`, written on the pattern of the latest
binary-move script there (`ls docs/activation/pending-activation/ | grep activate` — take the next
free `NN`; spent scripts carry a `.done`). The pattern: a header recording WHAT / WHY / the gate
runs verbatim; idempotent `~/.zshrc` edits inside `claude()` (the `_bin` pin, and the `--model`
default sites when the lead model moves); one timestamped backup before any write; `--undo`.
**Do not reimplement it inline.**

- **A GREEN auto-mode check (#3) IS the empirical equivalent of the interactive auto-mode
  live-test** that activation scripts call the operator gate, so a GREEN gate SATISFIES
  `LIVE_TEST_PASSED=1`. The human gate shrinks to the irreducible call only (e.g. accepting a
  sub-day binary soak against audit.md's age bar); that call is where `AskUserQuestion` belongs.
- **Binary first, SSOT second.** The script moves the binary; the `model-config.yaml` flip
  (model.md P7) goes through a worktree + the project-local `/ship` + deploy-live, because
  `~/.claude/model-config.yaml` is a symlink into a shared checkout.
- **The repoint reaches NEW shells only** — take the `ps` census (audit.md Step 0) before the SSOT
  flip; model.md Case A step 0b has the hazard class.
- `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` is carried across every bump; the script never touches
  its export. #6 checks delivery and #15 checks effect.

### ANY RED ⇒ PARK — do NOT activate

At least one way of working regressed. **Do not flip the SSOT or the pin.** Relay the named
check(s) and their evidence verbatim as the reason to hold. Re-run after the upstream fix or a
later binary; a RED is a specific, reproducible regression. A green audit never overrides a RED.

## Entitlement and plan inclusion (gate #2 is only the first)

| Question | How | Record |
|---|---|---|
| Registered? | `cc-model-registered <id>` (P1) and gate #1 | count + control |
| Entitled? | gate #2 on every account, plus a live budget in `claude-accounts` | per account; entitlement can be server-date-gated |
| In plan usage, or does it spend credits? | the CURRENT plan docs | **NOT STATED is the common answer — record it as that, never as "yes"** |

Registration ≠ entitlement ≠ plan inclusion: three gates that fail differently. Never let one
stand in for another.
