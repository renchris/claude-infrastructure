---
status: open
---

# HOOK_SURFACE_100P — measure the entire Claude Code hook surface, then adopt all of it that earns its cost

**Status:** Phase 1 partially done (7 of 15 events measured), Phase 2 not started.
**Origin:** investigating anthropics/claude-code#91870 (Function Hooks) 2026-09-03..05. That proposal
is Anthropic's, pre-decision, and **not on the critical path** — the investigation's real finding is
that we under-use the surface that already ships. Provenance record:
`docs/research/function-hooks-91870-2026-09-03.md` (sha `fbb9d52f1`).

    Scope (frozen): measure every hook event and handler type the installed binaries actually
    dispatch, decide per item whether it earns its cost, and wire everything that does — leaving
    no item in "present in the binary but never probed".

**The standard, stated so it cannot be gamed:** an item is DONE when its row in § 3 carries a
verdict from a command that was RUN, with that command quoted. "Present in `strings`" is not a
verdict — that instrument already produced one false census here (§ 5).

---

## Phase 0 — orchestration (MANDATORY FIRST SECTION)

| Wave | Locus | Why | Model / effort |
|---|---|---|---|
| **W1 · probe the unmeasured events** | **S** (dispatched session) — default | 12 events × 2 binaries × 2 invocation modes is breadth-first fan-out; findings, not code | ultracode Workflow, Opus @ high |
| **W2 · price the two unpriceable events** | **S** | needs an instrumented interactive session + a tool-call census; different rig from W1 | Opus @ high |
| **W3 · wire what earns it** | **S**, one session per event group | each wiring is an independent, self-verifiable change to a fleet-wide file | Opus @ high |
| **W4 · adversarial review of the ledger** | **T** (in-session teammates) — justification: the reviewers must be synthesised against each other immediately and their combined output is small | — | Opus @ xhigh |

**Lead context budget:** hold ≥50% of the window for deciding. **Succession point:** recycle at each
wave boundary, or at ~60% fill, whichever comes first (§ 6).

**Shared task list (belt-and-suspenders):** create one list keyed to this plan, one task per § 3 row.
The plan is the SSOT for *findings*; the task list is the SSOT for *what is left*. When they disagree,
the plan wins and the task list gets corrected — never the reverse.

---

## 1. What is settled, and how

| Fact | Method | Where |
|---|---|---|
| Canonical hook events: **27 on 2.1.114, 31 on 2.1.220** | event enum extracted from each binary; `claude doctor` also prints the valid list free (220 only — on 114 doctor is an Ink TUI and refuses without a tty) | this plan § 5 |
| `PreModelSwitch` / `PostModelSwitch` are **not hook events** on either binary | same | — |
| **`PostToolUse` never fires on a failing tool** — the harness dispatches `PostToolUseFailure` instead | positive control in one 2.1.220 run: `echo ok` → PostToolUse; `false` → PostToolUseFailure, no PostToolUse | landed fix |
| No hook payload carries **any** context/token/window field | three independent methods: raw stdin dumped across 16 events, the single shared input-builder function, a scan of all 31 schemas | — |
| `http`, `prompt`, `agent` handler types **work** on 2.1.220 | end-to-end, both allow and block arms | — |
| `prompt` / `agent` are **boolean condition evaluators** returning ok/reason — they cannot emit `additionalContext`, and they **fail OPEN** on evaluator error | same | ⚠ limits the "move judgment out of bash" idea materially |
| **A malformed hook entry silently disables every hook in that settings file**, zero log output | control/test matrix, per-file containment shown | ⚠ see § 4 adoption precondition |
| `WorktreeCreate` is a **provider** hook — a naive exit-0 observer breaks worktree creation | it fired, then `EnterWorktree` failed with "hook succeeded but returned no worktree path" | ⚠ **single-occupancy**, already correctly wired to `worktree-setup.sh` |

## 2. Implementation state

| Item | State |
|---|---|
| `hooks/log-bash.sh` real exit codes | **LANDED** (`2d003a521`, content-verified on trunk). Live layer converges on its own — 13 behind, inside the 25/6h budget |
| `PostToolUseFailure` registration | **WIRED** in `~/.claude/settings.json`, 90 registrations, binary validator accepts |
| `settings-templates/settings.example.json` | carries `PostToolUseFailure`; also already carried `SubagentStop`, which the live file had never picked up |
| Everything else in § 3 | **not started** |

**Net capability change so far: one repair.** Nothing else has been adopted.

## 3. THE LEDGER — every event, and what it still owes

Verdicts: `FIRES` (measured) · `HOSTILE` (measured, do not wire naively) · `NOT-EXERCISED` (probe
never issued the real trigger — *not* a refutation) · `UNMEASURED`.
Dispositions from the value review: **WIRE** · **DROP** · **HOLD** (unpriceable until a number exists).

| Event | 114 | 220 | Verdict | Disposition | What it still owes |
|---|:--:|:--:|---|---|---|
| `PostToolUseFailure` | ✓ | ✓ | FIRES | **WIRE — done** | — |
| `SubagentStop` | ✓ | ✓ | FIRES | **WIRE** | carries `agent_id` + `agent_transcript_path`; closes task #192. Hook already written, must stay non-blocking |
| `StopFailure` | ✓ | ✓ | FIRES | **WIRE** | carries `error:"authentication_failed"` at the moment of death vs a 1h relogin poll. Must write a marker, not a page — 30 sessions hit one cap together |
| `SubagentStart` | ✓ | ✓ | FIRES | consider | pairs with SubagentStop |
| `TaskCreated` | ✓ | ✓ | FIRES | **DROP** | exact duplicate of our `PostToolUse` `TaskCreate\|TaskUpdate` matcher |
| `InstructionsLoaded` | ✓ | ✓ | FIRES | consider | only non-redundant if it names the files loaded — **unverified** |
| `Setup` | ✓ | ✓ | FIRES via `--init/--init-only/--maintenance` | **DROP** | fires only on hidden CLI flags no automation issues |
| `PostToolBatch` | ✗ | ✓ | FIRES | **HOLD** | the only match-all point that fires even on a DENIED call — potentially the cheapest complete repair. Blocked on the all-tool-call rate (`f6cc5c79885b`) |
| `MessageDisplay` | ✗ | ✓ | FIRES | **HOLD** | **largest cost risk.** 10 s harness timeout where command hooks get 600 s. Probe n=1 in `-p`, where nothing displays. If per-delta: ~0.25 cores fleet-wide, ~5× the whole current chain |
| `WorktreeCreate` | ✓ | ✓ | **HOSTILE** | **PROHIBITION** | single-occupancy. Never append a second observer |
| `PermissionDenied` | ✓ | ✓ | NOT-EXERCISED | probe | real trigger is an **auto-mode classifier denial**, not an allowlist miss. Must test on the **interactive** path |
| `FileChanged` | ✓ | ✓ | NOT-EXERCISED | probe | the `matcher` field **is** the watch-path list (split on `\|`, joined to cwd, handed to chokidar with a 500 ms `awaitWriteFinish`). `**/*` becomes a literal nonexistent path. Blocks tasks #58/#74 |
| `UserPromptExpansion` | ✗ | ✓ | NOT-EXERCISED | probe | keys on slash-command expansion, not `@file` |
| `DirectoryAdded` | ✗ | ✓ | NOT-EXERCISED | probe | `source` enum is `slash_command` / `register_repo_root`; a startup `--add-dir` is neither |
| `PermissionRequest` | ✓ | ✓ | UNMEASURED | probe **carefully** | binary contains a guard that negates on this hook's existence — suspected provider-class foot-gun |
| `Elicitation` / `ElicitationResult` | ✓ | ✓ | UNMEASURED | probe **carefully** | `hookSpecificOutput` schema requires an action/content shape ⇒ provider class |
| `ConfigChange` | ✓ | ✓ | UNMEASURED | probe | maps to task #70 |
| `CwdChanged` | ✓ | ✓ | UNMEASURED | **DROP** | `cwd` is already in all 31 payloads |
| `PostCompact` | ✓ | ✓ | UNMEASURED | probe | we currently count compactions by scraping |
| `WorktreeRemove` | ✓ | ✓ | UNMEASURED | **DROP** | sibling is a provider; `worktree-gc-infra` covers it |
| `TeammateIdle` | ✓ | ✓ | wired already | — | — |

### The four highest-value unknowns

1. **`MessageDisplay`'s real fire rate in an interactive TUI** — per delta, per message, or per turn.
   One instrumented interactive session answers it, and it alone decides wire-vs-never-wire.
2. **Provider-hook semantics** — does a provider run *all* registered hooks and take the first
   non-empty stdout, or fail if any returns nothing? Highest blast radius on the board.
3. **Does anything here reproduce on 2.1.114?** Every probe so far ran on 2.1.220 only.
4. **Do `prompt`/`agent` hooks attach to `Stop`/`SessionStart`?** The bundled doc says tool-events-only;
   a measurement on `UserPromptSubmit` contradicts it. Unresolved, and it gates the close-integrity idea.

## 4. Adoption preconditions (non-negotiable)

- **Experimental events go in a SEPARATE settings file**, never `~/.claude/settings.json`. One malformed
  entry silently disables all 90 registrations there, including every fact-bound Stop gate and the land
  gate, with no log line.
- **Assert the expected registration count at SessionStart** — `hooks/config-mirror-assert.sh` is the
  natural home.
- **Never wire an event whose `hookSpecificOutput` schema you have not read.** `WorktreeCreate` is the
  proof; `PermissionRequest` and `Elicitation` are the same class.
- **Probe in a throwaway `CLAUDE_CONFIG_DIR`**, reached only via env prefix; use `--settings` when the
  probe needs real auth.

## 5. Learnings that outlive this plan

- **A green test can certify a bug.** `tests/bash-audit-attrib.bats` synthesises `tool_response.exitCode`
  — a field the harness never sends. It was green for months while all 37,319 logged exit codes read `0`.
  That is *why* nobody looked. The fixture is kept (the contract is worth defending) but now carries a
  header saying it is hypothetical.
- **`strings` produced a false census.** A 6-character length floor hid `Stop` and `Setup`, and it landed
  on 27 by coincidence — right number, wrong derivation. Use the binary's own event enum, or `claude doctor`.
- **"Did not fire" ≠ "does not fire".** Four of five original MEASURED-FALSE verdicts were wrong-trigger
  false negatives. Read the dispatcher's trigger before spending a probe.
- **A sweep must refuse rather than pass vacuously.** Two sweep runs reported ALL-GREEN having executed
  one suite and zero suites (`bats` eats loop stdin; the Bash tool is zsh, so no `mapfile`). The sweep now
  asserts `RAN == TOTAL` and a discovery floor.
- **`git worktree` on the shared checkout can set `core.bare=true`**, killing `deploy-live` fleet-wide
  while every file stays on disk. Memory: `worktree-ops-can-bare-the-shared-checkout`; backlog `693ee60c0885`.

## 6. Self-management protocol for the driving session

1. **Recycle proactively at wave boundaries or ~60% context fill**, whichever comes first — never ride to
   the wall. `handoff-fire.sh --recycle --goal '<end state> — proven by <check>; do not <constraint>'`.
   A goal dies with its session, so **every recycle re-arms one**.
2. **Update this plan BEFORE recycling.** The successor inherits the plan, not the context. A ledger row
   without its command quoted is not a finding.
3. **Never widen a verdict beyond its population.** Every row states which binary and which invocation
   mode produced it.
4. **Run the full related-suite sweep before every land** — the first attempt at the exit-code fix was
   auto-reverted for skipping exactly this.

## Status log

- **2026-09-05** — Plan created. Phase 1 at 7/15 events measured, 1 hostile, 12 owing work. Exit-code
  repair landed (`2d003a521`) after a first attempt (`a53632ae1`) was auto-reverted for breaking
  `bash-audit-attrib.bats`; the re-fix reads `.tool_response.exitCode` when present and derives from the
  event otherwise, so both contracts hold. 23/23 related suites green with a vacuity guard.
