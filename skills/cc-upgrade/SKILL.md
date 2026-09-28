---
name: cc-upgrade
description: 'Upgrade Claude Code for a new model, a CC release or harness feature, or both: registration probe, CHANGELOG HOLD/ADVANCE, headless gate, activation, id/role/effort sweep, feature A/B. Use when a model ships or on "should we upgrade Claude Code".'
argument-hint: "[model|harness|both] [model-id|cc-version|feature…] [urls…]"
allowed-tools: Read, Edit, Write, Bash, WebSearch, WebFetch, Workflow, Agent, AskUserQuestion, Skill
---

# cc-upgrade — one runbook for a new model, a new Claude Code, or both

**Mandate (operator):** *"we ALWAYS upgrade immediately to a new model IF all our ways of working
continue to work."* This skill is how we know they do. It replaces `model-upgrade`,
`cc-version-audit` and `cc-upgrade-gate`; those names are alias stubs that forward here.

The sibling files hold the full rules. **Read a phase's file in full before running that phase.**

## 1. Live facts — read, never restated

This skill names no version or model id as current. Read them:

```bash
cc-claude-bin --explain                                        # the binary the fleet runs
yq '.versions,.roles,.effort_defaults' ~/.claude/model-config.yaml # what the SSOT routes
npm view @anthropic-ai/claude-code dist-tags time --json           # what has shipped, and when
cc-model-registered <id> [--bin PATH]                          # does a binary know the id
```

…and the latest MANIFEST `REVISIT` row (holds.md § 1 has the reader).

## 2. Pick the lane

A keyword argument wins (`model`, `harness`, `both`). Otherwise the argument's shape decides: a
`claude-*` id or an anthropic.com URL means **model**; a semver, "Claude Code", or a feature name
means **harness**.

With a model id present, **always** run `cc-model-registered <id>` on the live pin:

| exit | lane |
|---|---|
| 0 — registered | **model** |
| 1 — absent (staged) | **both**: the model needs a binary move first |
| 2 — control absent | **STOP**: the instrument is broken, not the binary |

"Frontier access lapsed" or "which model at which effort now" is the model lane with no new id.

## 3. Phases

Each row lists the lanes it runs in and the file to Read first. Skip a row outside your lane, and
write its skip into the ledger.

| Phase | Lanes | Read first |
|---|---|---|
| P1 registration (live pin AND each candidate) | model, both | model.md |
| P2 audit: standing HOLD, CHANGELOG, churn | harness, both | audit.md, holds.md |
| P3 install the candidate into `~/.claude-<NNN>` | harness, both | audit.md |
| P4 gate, once per model in the run set | all | gate.md |
| P5a utilize: facts, effort sweep, role × effort | model, both | utilize.md |
| P5b feature: binary read, A/B, adopt/drop | harness with a feature, both | feature.md |
| P6 activation script, binary first | any lane that moves the binary | gate.md |
| P7 SSOT flip, Cases A-D, keying, lint | model, both | model.md, keying.md |
| P8 MANIFEST, ledger, memory | all | audit.md |

P5a and P5b only read and measure, so in the both lane they run as one Workflow. The gate's run set
(gate.md) is {`versions.opus_latest`} ∪ {the new id, if the model lane is on}: a worker-tier model
does not certify the lead model on the new binary.

## 4. Invariants — the spine (full text in the named file)

1. **Registration before classification**, with a positive control; never report a bare zero. (model.md)
2. **A staged id is not a routed id.** Park it in `<family>_staged`; never `claude-bump-models
   --apply` while staged; writing `_prior` is what arms the lint. (model.md)
3. **Case and binary state are independent.** A `roles.*` move is Case D and invisible to both
   sweep tools; a model-lane run ends in the Case D emitter census. (model.md)
4. **Detectors and emitters are rewritten in the same diff as the flip**; prefer the glob shape. (keying.md)
5. **One binary resolver**, `bin/cc-claude-bin`; a new versioned pin turns the
   `tests/cc-claude-bin.bats` ratchet red. (keying.md)
6. **MANIFEST default-deny guards only the legacy `claude-prev` lane**; HOLD means `skip`. The
   fleet pin moves only through the activation script's `_bin` edit. (audit.md)
7. **GREEN means activate now; any RED means PARK** and relay the named check. A green audit never
   stands in for the gate. (gate.md)
8. **Registration ≠ entitlement ≠ plan inclusion.** NOT STATED is recorded as NOT STATED. (gate.md)
9. **Binary first, SSOT second**, the SSOT through a worktree and the project-local `/ship`. (gate.md)
10. **A `~/.zshrc` repoint reaches new shells only**; take a `ps` census before the flip. (model.md)
11. **`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` carries across every bump** (#6 checks delivery,
    #15 checks effect). (gate.md)
12. **A rollback drops binary-resident capabilities**; re-gate the rolled-back build. (audit.md)
13. **Model facts come from the `claude-api` skill and the release pack**, never memory. (utilize.md)
14. **Dated facts live only in holds.md.** Everywhere else, name the command that reads the value.

## 5. Ledger and run directory

One run, one directory: `docs/research/<slug>-<date>/`, holding `UPGRADE.md` plus each phase's
evidence (`notes/`, `facts.json`, gate JSON, sweep runs). `UPGRADE.md` has one row per phase —
phase · verdict · evidence path · sha — written **before the next phase starts**. A skipped phase
gets a row with its reason.

**After any compaction, re-read `UPGRADE.md` and the current phase's file.** Only this router is
re-attached; earlier Read results are not.

## 6. Delegation

Read-only fan-outs go to `workflow-lean` Workflow slots with self-contained briefs that name their
output file: the page-range readers and verifiers (utilize.md), the three CHANGELOG axes plus the
adversary (audit.md), the effort-sweep and A/B arms (utilize.md, feature.md). The gate verdict, the
activation, the SSOT flip and every commit stay on the lead.

## 7. Output

One verdict line per lane (e.g. `harness: ADVANCE to <ver> — gate GREEN ×2`,
`model: Case A staged → routed; 2 roles moved (Case D census clean)`), then the list of sibling
files you Read. A missing file in that list is a skipped rule, made visible.
