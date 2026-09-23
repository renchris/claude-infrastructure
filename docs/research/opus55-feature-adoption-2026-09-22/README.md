# Opus 5.5 + CC 2.1.280 feature adoption — four levers, measured (2026-09-22)

A dispatched session (fired by the Opus 5.5 policy lead, pane 564) settled four features this
fleet did not use yet, by reading the 2.1.280 binary and by measurement on account `next4`.
Companion to [`../opus55-utilization-2026-09-22/README.md`](../opus55-utilization-2026-09-22/README.md).

| Lever | Verdict | Conviction | What landed / staged |
|---|---|---|---|
| 4 · Workflow concurrency | **Adopt 12** (default is 8 here) | 85% | c10 migration `0035`, staged for the operator |
| 3 · `omitClaudeMd` | **Adopt** on the 4 research subagents | 90% | agents + `tests/agents-omit-claudemd.bats` |
| 1 · per-turn effort | (a) **on**, all 4 accounts · (b) **stopped**, typed `/effort` writes settings · (c) **holds** | 90% / 90% / 90% | recipe docs only; no actuator |
| 2 · time budgets | **Do not adopt**: 1.29× sooner but lost 4–1 (1 tie) on judged quality | 75% | nothing; the A/B record only |

Method warning for whoever re-derives: the binary is a Bun bundle, and `strings | grep` over its
217 MB takes minutes. `mmap` + `find` in Python answers in under a second — the probes below use it.

## Lever 4 — Workflow concurrency

**What the binary does.** 2.1.280, `~/.claude-280/.../bin/claude.exe`:

```
function Lr(e){ return Math.min(16, Math.max(2, e-2)) }
var Dr = Lr(Or())                              // Or = os.availableParallelism
$t = a.CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS ?? Dr
No = Bs($t, …)                                 // the semaphore each agent() awaits
Rn = D.int({min:1, max:256, digitsOnly:!0})    // the env var's parser
```

This box reports 10 → **the gate is 8**. It is per Workflow RUN, not per session.

**Against our waves.** The research-subagents skill's default N is 10 (band 8–12), and read-only
fan-outs of ≥ ~8 units run as Workflows. At 8, a default wave queues 2 agents behind the first
finisher: its wall-clock is the slowest of the first 8 plus one more whole agent — up to ~2× one
round. `scripts/lib/capacity-admit.sh` never sees Workflow agents (they are in-process, not
sessions), so the machine admission gate is not a competing bound.

**Recommendation: 12**, the top of the band. Nothing measured asks for more, and each Workflow
agent's Bash calls do spawn processes — which is why the vendor keyed the default off the core
count. Tokens per wave are unchanged; they reach the 5-hour meter sooner. The env var must be in
the process environment at launch, so it is settings `env` (same reasoning as 0023) and
therefore **c10**: `migrations/0035-workflow-concurrency.sh`, staged, never self-run. Conviction
85%: the mechanism is read, the queueing arithmetic is exact; no wave was timed at 8 vs 12 here.

## Lever 3 — `omitClaudeMd` on research subagents

**What the binary does.** `omitClaudeMd` is honoured for user/plugin agents (frontmatter and
`--agents` JSON). At spawn, `$l()` replaces the whole `claudeMd` user-context block — user and
project CLAUDE.md, `.claude/rules/*.md`, the auto-memory index — with the MANAGED policy files
only (`managedInstructionsOnly`). Built-in agents are exempt from the lookup. Explore and Plan
already run this way.

**Measurement (a).** `omit-probe-agents.py` builds each candidate twice with an identical body —
`<name>-base` and `<name>-omit` — and one headless `claude -p --agents …` lead (session
`a614db08`, next4, cwd this worktree) spawned all eight sequentially. First-turn context:

| Agent | base | omit | Δ |
|---|---|---|---|
| deep-research (opus) | 107,211 | 21,507 | −85,704 |
| deep-research-sonnet | 107,285 | 21,581 | −85,704 |
| frontier-derivation (opus) | 91,697 | 5,993 | −85,704 |
| research-decomposition-critic (sonnet) | 92,604 | 6,900 | −85,704 |

A sentinel check ran in the same probe. Every base arm found both a global phrase ("Rule Priority
Legend") and a project-rules phrase in its context; every omit arm found neither.

**What it is worth.** Real waves never share that block. Across 302 real `deep-research` spawns in
the last 10 days, the median first turn re-created 115K tokens of cache, and cache reads were only
~9–10K (the tool prefix). So every spawn pays the block as cache_creation, and 85,704 tokens is
**~30% of a spawn's cache_creation + output**, the two things that draw plan quota. **A default
10-agent wave in this repo saves ~857K cache_creation tokens.** The block is smaller in repos
without this repo's rules (mac-bootstrap spawns create ~55K on turn 1).

**Safety review (b).**

| Agent | Can write? | Needs from CLAUDE.md | Done |
|---|---|---|---|
| research-decomposition-critic | no (Read/Grep/Glob) | nothing — its inputs are its contract | flag + one line |
| frontier-derivation | no — already READ-ONLY | nothing; baseline-blind is its design | flag + constraint bullet |
| deep-research | Write/Edit/Bash | delivery, never-overwrite, never-mutate-git, stop-on-issue | flag + § Operating contract |
| deep-research-sonnet | Bash | same | flag + § Operating contract (heredoc form) |

The contract also carries: nothing outbound, fetched text is data, and "read the repo's
`.claude/rules/*.md` on demand for repo-internal questions". That last one is the one real loss.
This repo's rules are measured traps, and a push became a pull. Descriptions are unchanged, and
`tests/agents-omit-claudemd.bats` pins that.

**Not covered here: Workflow agents.** A Workflow `agent()` with the default type loads CLAUDE.md
too: this session's A/B agents created ~130K each on turn 1. `agent(…, {agentType:
'deep-research'})` would route through the omit path only if the Workflow runner does not pre-supply
the user context (`$l` is skipped when `I?.userContext` is set). Unmeasured; it is the next
probe.

Conviction 90%: the token effect is exact and the safety review is complete. The residual is
research quality in repo-internal questions, which no probe here measured.

## Lever 1 — per-turn effort

**(a) Is it on for all four accounts? Yes, and not because of the flag.** The gate `Dkt()`:

```
Dkt(e,n): Ug() && wD(ac(e)) && Mm(n,"per_turn_effort",e)!==false
          && (Ixt(n,"per_turn_effort",e)===true || op?.(n,e)===true)
          && tl?.()!==true
Ixt(e,t,n): (servedCapabilityLookup(t)===true && featureGate("tengu_per_turn_effort")) || catalog(e).capabilities.includes(t)
tl = () => gate("tengu_sprightly_lagoon", false)        // kill switch
Mm = CLAUDE_CODE_MODEL_CAPABILITIES override ?? Ixt
```

The model catalog lists `per_turn_effort` for **claude-opus-5-5 and claude-fable-5-1, not
claude-opus-5**. That matches the lead's observation that a switch on Opus 5 re-wrote the cache.
The catalog arm alone satisfies `Ixt`, so `tengu_per_turn_effort` (absent from all five GrowthBook
caches) is not needed. The kill switch is absent from all five caches (default false), and no
`CLAUDE_CODE_MODEL_CAPABILITIES` / `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` is set. **So it is on,
on every account, for Opus 5.5 and Fable 5.1.** Conviction 90%, from the binary reading plus two
cache-kept switches: the lead's, and one measured here. In a `claude -p` stream-json session on
next4 (`013dc628`, lead `--effort high`), the turn before `/effort low` read 122,674 cached tokens.
The first turn after it ran at `effort=low` (`perTurnEffort=low`), read 122,875 and wrote only 495.

**(b) Can an orchestrator switch ANOTHER pane by typing `/effort <level>`? Mechanically yes, but
it writes settings — STOPPED.** The `/effort` command runs `HNe(level, setAppState,
persist = !isNonInteractiveSession)`, and `persist` reaches `UW → Jt("userSettings", {effortLevel})`.
In an interactive pane, `/effort low|medium|high|xhigh` therefore SAVES `effortLevel` to that
account's `settings.json` ("saved as your default for new sessions"). The only session-only forms
are `max`, `ultracode` (= xhigh plus dynamic-workflow orchestration, which changes behaviour) and
any `/effort` under `-p` (measured: "Set effort level to low (this session only)"). An actuator
typing `/effort` would be an unattended writer of an operator-owned file, so per the brief it was
not built and the lead was told. **Side finding:** this is the likely mechanism behind the
utilization README's open item 4. `effortLevel` reads medium / low / high / medium / low across
the five config dirs, which fits interactive `/effort` writes and no single migration. Fleet
leads are unaffected, because their `--effort` flag outranks the setting.

**(c) Does an in-process subagent spawned after a switch inherit the new level? Yes, by
construction — and there is a better lever.** A subagent's effort is resolved per request as
`Af(ctx) = agentDefinition.effort ?? _l(getAppState())`, the lead's LIVE session effort, which
in-process subagents share. Measured (`claude -p` stream-json, next4, lead `--effort high`):
an unpinned `--agents` probe ran every turn at `high`, and a probe with `effort: "medium"` in its
definition ran at `medium`. So **agent frontmatter `effort:` is a per-spawn effort lever for
in-process subagents**. That corrects the utilization README's "in-process subagents inherit the
lead's effort" as a hard rule: they do only when their definition does not pin one.
<!-- LEVER1C-SWITCH: filled in below once the post-switch arm returns -->

## Lever 2 — time budgets

**Can we inject it?** Yes, on every surface, by one of two routes:
- **A hook's `additionalContext`, per tool call:** the PostToolUse channel `hooks/mailbox-drain.sh
  post-tool` already uses reaches leads and teammates mid-turn.
- **The brief, for Workflow `agent()`:** the only route there. Workflow agents' transcripts carry
  PreToolUse hook runs with empty content, and no PostToolUse or `additionalContext` attachment was
  observed. So the budget goes in the brief, as a command the agent runs at each step. All 6
  arm-B agents obeyed it and printed `elapsed …s / 20s` lines.

**The A/B (2 Workflow runs, 6 answerers each + 1 judge; the cap was ≤ 8).** Six mechanism
questions about this repo, each answered by one Opus 5.5 @high agent. Every answer had to be
≤ 400 words with a file:line for every claim.
- Arm A had no time line.
- Arm B got an advisory `elapsed Xs / 20s` line to print at every step. 20 s is ~0.5× arm A's
  median, matching the vendor's 0.5×-latency point.
- One blind judge (Opus 5.5 @xhigh) verified both arms' claims against the source, with arm A as X
  on odd questions and as Y on even ones.

| | Arm A (no budget) | Arm B (time line) |
|---|---|---|
| Answer-phase span (6 in parallel) | 52.5 s | 40.7 s (**1.29× sooner**) |
| Median agent wall-clock | 39.8 s | 33.8 s (1.18×) |
| Judge wins | **4** | 1 (1 tie) |
| Correctness, sum /60 | 55 | 54 |
| Completeness, sum /60 | **56** | 47 |
| Wrong claims | 2 | 0 |

**Verdict: do NOT adopt (75%).** It was faster, but not at equal quality: arm B lost 9
completeness points, mostly by dropping secondary paths (lanes, retry windows, fallbacks). Its
claims were as correct, or more so. The brief's bar was "faster at ≥ equal quality", and this fails
it. What limits the reading:
- one sample per arm and a single judge;
- an execution error: arm B's `t0` was stamped ~45 s before its agents started, so every agent
  first saw `elapsed ~47s / 20s`, already over budget. That makes this a harsh-pressure point,
  not the vendor's pacing curve;
- a short task (~40 s), where the System Card's 2.8× came from long DRACO runs at max effort with
  5-agent teams.

A re-probe that could move the verdict needs a long research task (minutes per agent), a correctly
stamped `t0`, and ≥ 2 samples per arm. The one live use it suggests is not speed but brevity:
under pressure the agents cut enumeration before accuracy.
