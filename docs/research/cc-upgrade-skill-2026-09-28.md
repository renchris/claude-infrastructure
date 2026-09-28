# cc-upgrade skill — auto-load probe (2026-09-28)

**Answer.** On 4 of the 6 phrasings the design named, a headless session invokes `cc-upgrade`
on its first tool call and then Reads the lane file that phase needs. The 2 misses are the two
model-lane questions that carry no new model id. Both sessions answered from `model-config.yaml`
directly and never loaded the skill. "which model at which effort now" is arguably fine as a
read-only answer. "frontier access lapsed" is a real miss, because Case C (model.md) has steps
that the direct answer skipped.

Context: `cc-upgrade` replaced `model-upgrade`, `cc-version-audit` and `cc-upgrade-gate` (landed
`e497b250c`; the design is `docs/research/sonnet55-utilization-2026-09-28/notes/skills-consolidation.md`
§7 step 6). The probe ran after the live layer converged, and `~/.claude/skills/cc-upgrade/*`
were symlinks into the shared checkout at that sha.

## Result

| # | phrasing | Skill invoked | cc-upgrade? | sibling Read after it | turns | result |
|---|---|---|---|---|---|---|
| 1 | should we upgrade Claude Code | cc-upgrade | yes | holds.md, audit.md | 7 | max-turns cap |
| 2 | Sonnet 5.5 shipped | cc-upgrade | yes | model.md | 7 | max-turns cap |
| 3 | adopt Dynamic Workflows | cc-upgrade | yes | feature.md, holds.md | 7 | max-turns cap |
| 4 | does 2.1.284 still run our ways of working | cc-upgrade | yes | holds.md, gate.md | 7 | max-turns cap |
| 5 | which model at which effort now | — | **no** | — (Grep of model-config.yaml and settings.json, then answered) | 4 | success |
| 6 | frontier access lapsed | — | **no** | — (Grep + Read of model-config.yaml `frontier_access`, then answered) | 4 | success |

The max-turns cap is the probe's own `--max-turns 6` bound, not a failure: each of rows 1-4 was
still working the phase when it stopped. Each row's sibling Reads match the router's phase table
for that lane: harness → audit + holds, model → model, feature → feature, "still runs our ways of
working" → gate. One sample per phrasing, Opus 5.5 @high only. A Sonnet 5.5 lead is plausible for
a cheap harness-only audit and is unmeasured (design §8, risk 1). Cost: $0.40–0.82 per run at list
price, ≈ $3.43 in total, drawn from plan quota.

## Method

- **Binary and model.** The launcher's binary via `cc-claude-bin`, 2.1.280, run as
  `claude -p "<phrasing>" --model claude-opus-5-5 --effort high --output-format stream-json
  --verbose --max-turns 6 --no-session-persistence --permission-mode auto`.
- **Environment.** A fresh `mktemp -d` cwd per run, so no project CLAUDE.md or project skills
  loaded. User skills, CLAUDE.md and hooks did load, as they do in production.
- **Side effects cut off.** `--disallowedTools "Bash Write Edit NotebookEdit Agent Workflow
  WebFetch WebSearch Monitor"`. The probe measures loading only, so a run cannot install a
  binary, write the MANIFEST or spawn anything.
- **Scoring.** Read off the stream-json `tool_use` blocks: a `Skill` call with
  `skill == "cc-upgrade"`, then any `Read` whose path contains `/skills/cc-upgrade/`.

**A probe defect, recorded rather than hidden.** The first run of rows 5 and 6 inherited this
pane's `ITERM_SESSION_ID`. The hooks in the headless session therefore took it for pane 919: they
told it no inbox wake path was armed, and it answered by arming three `cc-await-ping` Monitors on
pane 919's inbox. Each watcher's task notification woke the session for another turn, so a
6-turn probe ran for 24 minutes until it was killed. Rows 5-6 above come from a clean re-run with
`env -u ITERM_SESSION_ID -u TERM_SESSION_ID -u CLAUDE_CODE_TASK_LIST_ID` and `Monitor`
disallowed. The dirty run is not counted, although it also did not invoke the skill. Rows 1-4
carried the same inherited variable, but none of them armed a watcher before the turn cap.
**Lesson for any headless probe fired from a pane: unset the pane identity. Otherwise the child
joins the parent's inbox and its task notifications keep it alive past `--max-turns`.** A second,
known trap recurred as well: the child `cd`s before writing, so the out dir must be absolute (the
same fault is in the effort-sweep README).

## What would fix the two misses (not applied: the description is the design's exact text)

The description names "id/role/effort sweep" and "Use when a model ships", but neither miss
contains a new id, and neither reads as an upgrade. A candidate at 245 chars (python `len`) that
names the Case C trigger:

```
Upgrade Claude Code for a new model, a CC release or harness feature, or both: registration probe, CHANGELOG HOLD/ADVANCE, gate, activation, role/effort sweep, feature A/B. Use when a model ships or lapses, or on "should we upgrade Claude Code".
```

It is unmeasured. Re-run this probe on rows 5-6 (and 1-4 as a control) before adopting it.
"Which model at which effort now" may reasonably stay a direct SSOT read. The router's lane
classifier already routes it to the model lane when the skill does load.
