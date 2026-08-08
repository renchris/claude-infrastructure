---
name: cc-upgrade-gate
description: Empirically verify — with headless, self-evidencing probes — whether a NEW Claude model + binary is safe to activate NOW: do all our ways of working (Agent Teams, Dynamic Workflows, subagents, hooks, launchers, auto-mode, the effort ladder, permissions, resume, MCP) still WORK on the candidate? Produces a per-check PASS/FAIL/SKIP + one overall GREEN/RED verdict; GREEN ⇒ upgrade immediately via the one-command activation, RED ⇒ PARK and name the exact failing way-of-working. Use on "a new Claude model/binary released — is it safe to activate our ways of working?", "run the upgrade gate", "is opus-5 safe to turn on yet". NOT for CHANGELOG / binary-version safety (use cc-version-audit) or model-ref doc sweeps after deciding (use /model-upgrade).
allowed-tools: Read, Bash, Edit, Skill, AskUserQuestion
---

# cc-upgrade-gate — the empirical CC-upgrade regression gate

Decide whether a candidate **(binary version + model)** is safe to activate by *running* every way
we work against it as headless probes, then reading the artifact. The tool is
`scripts/cc-upgrade-gate.sh`; this skill wraps it with the upgrade **policy**.

## WHAT / WHY

**Operator mandate:** *"we ALWAYS upgrade immediately to a new model IF all our ways of working
continue to work."* The hard part was never the upgrade — it was knowing, without weeks of soak,
that nothing we depend on regressed. This gate replaces hand-waved soak + presumption with
**evidence**: each probe asserts on the ARTIFACT (`modelUsage` / argv / exit code / a real spawn),
never on a claim or a recalled fact.

**The failure mode it kills — in BOTH directions:**

- **False PARK** — the opus-5 episode: a *presumed* demotion (`max` effort "wrong", "≈ Fable at
  half cost", spawn-lifecycle "probably broke") that turned out to be fine. Presumption cost us the
  immediate-upgrade the mandate demands.
- **False GO** — flipping the SSOT while a way-of-working silently regressed (a demoted teammate
  spawn, an auto-mode wall, a resume-prompt regression). The gate would have caught it as a RED
  check before anything mutated.

Because every check is self-evidencing and fail-closed, a GREEN verdict is *earned* and a RED
verdict *names the specific thing that broke* — no soak, no vibes.

## RUN IT

```bash
scripts/cc-upgrade-gate.sh <binary-path> <model> [accounts…]
```

Concrete (the opus-5 shape):

```bash
scripts/cc-upgrade-gate.sh ~/.claude-219/node_modules/.bin/claude claude-opus-5 next next2 next3 next4
```

- **stdout** = machine-readable JSON (the full per-check report); **stderr** = a human summary;
  **exit 0 = GREEN, 1 = RED**. Fail-closed: any check FAIL ⇒ RED; a crashed probe that emits no
  result is scored FAIL, not skipped.
- **Env knobs:**
  - `GATE_SPAWN=0` — SKIP the expensive spawn probes (#7 Agent Teams / #8 Workflows / #9 subagents)
    for fast iteration. They SKIP (never FAIL) so the verdict stays honest about what ran.
  - `GATE_RETRIES=<n>` — bounded retry for transiently-flaky probes (the auto-mode classifier is
    flaky); default 3.
  - `NO_COLOR=1` — plain reporters.
- Accounts are the auto-mode config names (`next` `next2` `next3` `next4`); `[0]` is primary. Pass
  the full sweep to prove entitlement across every account you'll actually run on.

## THE 14 CHECKS

Each is one file `lib/cc-upgrade-gate/check*.sh` defining a `check_NN` — adding a probe is a new
FILE, never an edit to the orchestrator (collision-free multi-author build).

| #  | check               | what it proves (self-evidencing) |
|----|---------------------|----------------------------------|
| 1  | binary-registers    | `--model X --print` exits 0 with `modelUsage` carrying X — the binary *knows* the model (the loud-fail floor; the exact reason CC 2.1.215 could not run claude-opus-5). |
| 2  | entitlement         | the account is server-side entitled to X — a live completion, not a 403 / server gate. |
| 3  | auto-mode           | **the crux** — X engages under `--permission-mode auto` (drives its own turns, no demotion). This IS the operator's auto-mode live-test (see POLICY). |
| 4  | effort-ladder       | each effort rung is accepted + routed — matters because opus-5's curves peak medium/xhigh and `max` over-thinks (a wrong default would silently degrade every session). |
| 5  | launcher            | the real launcher body passes the right binary / model / flags to the candidate — an effect-read on recorded argv, not a grep of the script. |
| 6  | depth-containment   | `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` is honored (2.1.219 flips nested-spawn depth 1→3; the still-open #68619 runaway makes containment mandatory on our spawn-heavy binary). |
| 7  | agent-teams †       | a real teammate spawns and runs (unique marker `TEAMMATE_OK` in the result) with no silent demotion — `modelUsage` still carries X (GH #43869). |
| 8  | workflows †         | a 1-agent Dynamic Workflow runs and returns a non-null result (marker `WF_OK`) on the candidate. |
| 9  | subagents †         | a fire-and-forget research subagent spawns and returns (marker `SUBAGENT_OK`) on the candidate. |
| 10 | hooks-fire          | the binary triggers CC lifecycle hooks — SessionStart + Stop, injected via `--settings` so the real config is untouched — and the repo hook scripts (`session-start`/`dod-persist`/`operator-readout`/`completion-assert`) parse clean. |
| 11 | permission-nonblock | a benign command runs WITHOUT a permission wall in auto-mode (`permission_denials==[]`; 216/219 moved dangerous ops onto the classifier — benign must still pass). |
| 12 | resume              | `cc-next` routes a resumable session to the `claude-next` eval-track launcher (the right binary track). |
| 13 | mcp                 | session-connected MCP servers resolve on the candidate (`mcp list`, ≥1 `✔ Connected`); none configured ⇒ SKIP. |
| 14 | authstore-writeloss ‡ | the way-of-working is STAYING LOGGED IN: reads (never executes) the candidate's credential-write path and reports whether the upstream write-loss window is `FIXED` / `STATUS-QUO` / `WORSE` / `UNREADABLE`. Backed by `scripts/cc-authstore-probe.sh`; the defect itself is `docs/research/vendor-report-cc-authstore-write-loss.md`. |

† #7 / #8 / #9 are the spawn probes gated by `GATE_SPAWN` — they SKIP (not FAIL) when
`GATE_SPAWN=0`, so a fast run's GREEN honestly reads "everything that ran passed", never a false
all-clear.

‡ #14 is the one check whose *ordinary* answer is SKIP, deliberately. The defect is upstream and we
cannot fix it, so a candidate that merely matches the binary we already run is not a regression and
must not park an upgrade — an alarm that fired on every candidate forever would carry no
information. It goes **FAIL** only on a real change for the worse: the plaintext fallback removed
(`WORSE`), or the credential-storage layer no longer introspectable (`UNREADABLE`, fail-closed —
every auth-health compensation we run assumes that layer's shape). **PASS is the news**: it means
the vendor closed the window, so close backlog `4adbeab56aa7` and revisit the compensations in
`f8178bfe`.

## POLICY — the decision tree

Read the verdict, then act. **The gate output already names the failing way-of-working** — do not
re-derive it.

### ALL GREEN ⇒ upgrade immediately (the mandate)

Every way of working holds on the candidate. Surface the **one-command activation** and run it —
reuse the existing, fail-closed, idempotent activation script; **do NOT reimplement it**:

```bash
# phase A — SSOT flip (routing adoption; fully reversible)
LIVE_TEST_PASSED=1 CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-opus5-activate.sh

# phase A + B — ALSO repoint the everyday claude-next launcher onto the new binary+model
LIVE_TEST_PASSED=1 REPOINT_NEXT=1 CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-opus5-activate.sh
```

**KEY INSIGHT — the automation win.** The gate's GREEN **auto-mode check (#3)** IS the empirical
equivalent of the interactive auto-mode live-test that `10-opus5-activate.sh`'s header calls the
"operator gate." So **a GREEN gate SATISFIES `LIVE_TEST_PASSED=1`** — the one human step the script
warned an agent could not self-verify is now discharged by evidence. The human gate then shrinks to
the *irreducible* call only: e.g. accepting a <1-day binary soak on the shared 2.1.219 track
(rollback floor 2.1.217), or the optional teammate-lifecycle smoke on the new binary. That
irreducible call is where `AskUserQuestion` belongs — not the whole activation.

The script itself stays the gatekeeper of the mutation (backs up the SSOT, self-asserts every edit,
lint-gates, auto-rolls-back on red, idempotent) and prints the remaining land-into-repo steps. This
skill's job ends at: GREEN ⇒ hand over that exact command.

### ANY RED ⇒ PARK — do NOT activate

At least one way of working regressed on the candidate. **Do not flip the SSOT.** The summary already
names the failing check(s) and their evidence — relay that verbatim as the reason to hold, and leave
the toolchain on the current model/binary. Re-run the gate after the upstream fix (or a later
binary); a RED is a specific, reproducible regression, not a vibe.

## RELATION to the sibling skills

Three skills, three distinct questions — this one is the empirical gate *between* the other two:

- **cc-version-audit** — *"is the BINARY VERSION safe?"* Judges the CHANGELOG + open-issue churn for
  a CC binary bump; produces a HOLD/ADVANCE verdict + MANIFEST entry. Paper analysis, no live probe.
- **cc-upgrade-gate** *(this)* — *"do our ways of working actually still WORK on candidate
  binary + model?"* Runs them and reads the artifacts. Live evidence, GREEN/RED.
- **model-upgrade** — *"sweep the model refs after we've decided."* The mechanical doc/config
  reference sweep that follows a GREEN activation.

Typical flow: `cc-version-audit` clears the binary → **`cc-upgrade-gate` proves the ways of working
on that binary + the new model** → GREEN activation via `10-opus5-activate.sh` → `model-upgrade`
sweeps any lingering refs.
