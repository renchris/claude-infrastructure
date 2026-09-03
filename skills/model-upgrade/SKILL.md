---
name: model-upgrade
description: Runbook for moving the toolchain to a new Claude model — or off one when access ends. Use when Anthropic ships a model ("upgrade to Opus 4.9", "Fable 5.1 released"), when a plan-access window opens/closes ("we lost Fable access", "downgrade"), or when claude-lint-models flags stale refs / an expired frontier window. BECAUSE WE PIN CLAUDE CODE, a model release is always ALSO a binary event — Step 0 is the binary gate (does the pinned build even register the id?), and a model that shipped after our pin is a STAGED upgrade, not a sweep. Covers that gate and its escalation to /cc-version-audit + /cc-upgrade-gate, the model-id keying census (detectors vs emitters) that a flip must rewrite, doc/config reference sweeps, the dynamic model ladder, and the binary-pin census. NOT for app-code SDK migrations (reso has no Anthropic SDK; for SDK code use /claude-api migrate).
allowed-tools: Read, Edit, Write, Bash, AskUserQuestion, Skill
---

# model-upgrade — model-reference upgrade/downgrade runbook

**Step -1 (always):** invoke the `claude-api` skill first for authoritative model IDs,
pricing, and capability facts. Never answer model facts from memory.

**Step 0 — THE BINARY GATE. Run this BEFORE classifying, every time, no exceptions.**

🚨 **We pin Claude Code. Therefore a model release is never only a model event — it is ALWAYS
also a binary event.** A model that shipped after our pinned build cannot be in that build, so
the id is not dispatchable no matter what the SSOT says. Ask the binary, not the docs:

```bash
BIN=$(readlink -f ~/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe)  # ← the PINNED one
for m in <new-id> claude-opus-5; do printf '%-20s %s\n' "$m" "$(strings -a "$BIN" | grep -c -- "$m")"; done
```

🚨 **`strings` first, and NEVER report a zero without a positive control beside it.** The binary
is a Bun-compiled single-file executable: a plain `grep` on it returns **0 for every model**,
including ones the fleet demonstrably runs. The obvious probe is blind, and it fails in the
direction that looks like a finding. `claude-opus-5` is the control — if it reads 0 too, your
instrument is broken, not the binary. (Watch prefixes: `claude-fable-5` is a prefix of
`claude-fable-5-1`, so grep the LONGER id and read both counts.)

| Probe result | What this upgrade is |
|---|---|
| new id **present** | Ordinary upgrade. Continue to Step 1 and run the case normally. |
| new id **absent** | **STAGED upgrade.** Park the id in `versions.<family>_staged`, leave `<family>_latest` and `<family>_prior` alone, and do **NOT** run `claude-bump-models --apply`. Go to **§ The binary gate** below. |

Why the `--apply` prohibition is absolute: the sweep rewrites roles, the auto-mode allowlist and
every doc literal to an id the harness cannot resolve. Nothing warns you; the next `/frontier-run`
or teammate spawn simply fails. Leaving `<family>_prior` empty is what keeps the *current* model
from being convicted as stale — `claude-lint-models` collects its stale set from `_prior$` keys
and `claude-bump-models` iterates `${family}_{latest,prior}`, so a `*_staged` key is inert in both
(verified 2026-09-03). **This has now been hit twice** — Opus 5 (2026-07-24, needed 2.1.219) and
Fable 5.1 (2026-09-03, needs ≥2.1.253) — and both times it was rediscovered by hand because this
step did not exist. That is the whole reason it is Step 0.

**Step 1 — classify the event.** Three distinct cases; misclassifying is THE failure mode:

| Case | Signature | Example |
|---|---|---|
| **A. Lateral** | New model REPLACES same-family prior | Opus 4.7 → 4.8; Sonnet 4.6 → 4.7; Fable 5 → 5.1 |
| **B. Tier-insertion** | New tier ABOVE the ladder; old top STAYS in service | Fable 5 above Opus 4.8 (2026-06-09) |
| **C. Downgrade / window-end** | Access to top tier lapses; fall back | a FUTURE tier lapses (Fable 5 is now PERMANENT — Max/Team-Premium inclusion at 50% of limits from 2026-07-20, `frontier_access.permanent: true`, so it no longer applies) |

A blind literal sweep is correct ONLY for Case A. Case B is "add alongside" (per
claude-api migration guide Step 1 Bucket 2) — rewriting `opus → fable` would
de-tier Opus references that must stay Opus.

⚠️ **Case and binary state are INDEPENDENT axes.** A lateral bump whose id is absent is still a
lateral bump; it is just gated. Classify normally, then execute the case's steps only after the
binary gate clears. The two most recent releases were both Case A **and** both staged.

## SSOT map

| File | Job |
|---|---|
| `~/.claude/model-config.yaml` | versions (latest/prior per family: frontier/opus/sonnet/haiku), `frontier_access` window, `pricing_per_mtok`, role ladder, effort defaults, deprecations |
| `~/bin/claude-bump-models` | literal-ID sweep over classified files (`--apply`, `--check`, `--from-to OLD NEW`) |
| `~/.claude/scripts/claude-lint-models.sh` | stale-ref lint (`--all`) + frontier-window expiry check (fails when window lapsed but `active: true`) |
| `~/.claude/model-classification.json` | `update` = auto-sweepable; `preserve` = historical, never touch; `review` = mixed prose/citations — THIS skill walks them by hand |
| `~/.zshrc` | launcher tracks (see Appendix) — runtime model selection, separate from doc refs |

**Known blind spot:** the sweep/lint match full IDs (`claude-opus-4-7`) only. Prose
forms ("Opus 4.7", "Opus-tier") live in `review` files and need judgment — that's
why they're not in `update`.

## The binary gate — when Step 0 says the id is absent

Seven gates, in order. Gates 1–5 are free and reversible: none of them touches the live launcher,
so all of them can be run today on any release. Only gate 6 changes what the fleet executes.

| # | Gate | Vehicle | PASS looks like | On FAIL |
|---|---|---|---|---|
| 1 | *Should* we advance the binary at all? | **`/cc-version-audit`** — CHANGELOG vs our workflow, emits HOLD/ADVANCE + MANIFEST entries | ADVANCE, with the delta's breaking changes named | HOLD: record why in the staged block; the model waits |
| 2 | Get the candidate on disk without burning the bridge | `npm i --prefix ~/.claude-<NNN> @anthropic-ai/claude-code@<ver>` | new prefix exists, **old prefix untouched** | nothing to undo |
| 3 | *Do our ways of working still work on it?* | **`/cc-upgrade-gate`** — headless self-evidencing probes | GREEN across Agent Teams, workflows, hooks, launchers, auto-mode, effort, permissions, MCP, resume | RED **names the failing way-of-working** → PARK, do not adopt |
| 4 | Are we entitled to the model? | `--model <new-id> --print "ok"` on the candidate + a live budget in `claude-accounts` | real completion returned | registered-but-unentitled → wait; entitlement can be server-date-gated |
| 5 | Is it in plan usage, or does it spend credits? | read the CURRENT plan docs | an explicit statement | **NOT STATED is the common answer — record it as that, never as "yes"** |
| 6 | Rewrite the hardcoded id sites, **in the same diff as the flip** | § Model-id keying below | both classes rewritten | a half-fix is worse than none — see below |
| 7 | The flip itself | the case's own steps (A/B/C) + effort re-sweep | `claude-lint-models --all` green, one live spawn spot-checked | revert gate 6's diff and the launcher line together |

**Gate 1 vs gate 3 is a real division of labour, not redundancy.** `cc-version-audit` tells you
what Anthropic *said* changed; `cc-upgrade-gate` tells you what actually *broke*. Over a large
version delta only the second is evidence. Run both, in that order, and never let a green audit
stand in for the gate — "the model id resolves" is not "the harness still works".

**Sizing the jump honestly.** Registration is ONE axis. Hooks, Stop-hook semantics, auto mode, the
effort ladder, spawn depth, permissions, settings-schema keys and MCP are all unmeasured by the
Step 0 probe. Precedent: 2.1.219 changed the nested-subagent spawn-depth default to 3, which
re-opens GH #68619 (4M tok/5min runaway) on this spawn-heavy box — carry
`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` across any bump. The dangerous shape is a settings key or
hook field that is silently *dropped* rather than loudly rejected.

⚠️ **The npm `stable` dist-tag is not a route to a new model.** Measured 2026-09-03: `stable`
(2.1.236) did not carry `claude-fable-5-1`; only `latest` did. Check the tag you are actually
about to install rather than assuming "stable is safer, and safe enough".

**Rollback.** Gate 6+7 is one revert: put the launcher's binary path back to the prior
`~/.claude-<NNN>` and revert the keying diff **together**. What does NOT come back with it: any
`claude-bump-models --apply` sweep already run (re-run it `--from-to <new> <old>`), and anything a
session wrote while running the new binary.

## Model-id keying — the gate-6 rewrite, and why a half-fix is worse than none

Grep the fleet for the OLD id before flipping. Sites split into two classes that fail in opposite
directions, and **a check that finds only one class produces a flip that looks complete and is not**:

- **DETECTORS** test `$MODEL` against the literal (`[ "$MODEL" = "claude-fable-5" ]`). After a flip
  they evaluate FALSE — no error, no log — so the new model runs while nothing accounts it as that
  tier. Under-counting, silent.
- **EMITTERS** *write* the literal (`fable) MODEL="claude-fable-5" ;;`, `--model claude-fable-5`,
  `model=claude-fable-5`). They are keyed on an alias or on a flag, so they never "go false" — they
  just keep launching the OLD model while the SSOT claims the new one. The config reads adopted and
  the fleet is not.

```bash
# detectors                                   # emitters
grep -rnE '=[[:space:]]*"?<old-id>"?' bin scripts    grep -rnE '(model=|--model )<old-id>' bin scripts
```

Two more traps, both measured on the Fable 5 → 5.1 census (2026-09-03):

1. **Selftest assertions pinned to the old id go VACUOUSLY GREEN** (`bin/cc-route`,
   `bin/cc-wave-plan` both assert `.model=="claude-fable-5"`). A green suite is not evidence that
   the keying survived; it may be asserting the very thing you failed to change.
2. **Glob-matchers survive the flip while equality-matchers do not.** `~/.zshrc`'s cost warning
   uses `== *claude-fable-5*`, which still matches `claude-fable-5-1`. Fix only the detectors and
   you get the worst split available: the human is still warned about the tier's cost while every
   mechanical arm that counts it reads "not that tier". Warned about the money, not counting it.

**Prefer the glob's shape** — a prefix or `case` test covering both ids — over swapping one literal
for another, so the *next* bump in that family does not re-create the whole problem.

## Case A — Lateral bump

0. **Binary gate cleared?** (Step 0). If NOT: write ONLY `<family>_staged: <new-id>` plus the
   pricing row and any deprecation change, leave `_latest`/`_prior` alone, and stop here — the rest
   of this case is gated. Everything below assumes the id is dispatchable.
1. `model-config.yaml`: set `<family>_prior` = old latest, `<family>_latest` = new ID, and CLEAR
   `<family>_staged`. Update `pricing_per_mtok` + `deprecations` from claude-api skill facts.
   ⚠️ `pricing_per_mtok` pairs are `[input, output]` BASE rates and consumers index them
   positionally — do not change the arity. Cache-read multipliers are a real third dimension
   (standard 0.1× base input, but **0.025× on Fable 5.1 / Mythos 5.1**) and go in comments. A
   base-rate-only comparison systematically misprices any model with a non-standard cache rate.
2. `claude-bump-models` (dry-run) → review the pair list → `--apply`. **Setting `_prior` is what
   arms this**: the lint builds its stale set from `_prior$` keys, so writing `_prior` before the
   binary can run the new id is exactly how a healthy model gets convicted as stale.
3. `claude-lint-models.sh --all` → must be green.
4. Walk every `review`-classified file: fix prose refs ("Opus 4.7" → "Opus 4.8")
   **except** historical citations (benchmarks "Opus 4.6 76% at 1M", incident records
   "GH #52522 Opus 4.7 auto-compact", provenance lines "--model claude-opus-4-8").
   Test: does the sentence claim "what we use NOW" (update) or "what happened THEN" (preserve)?
5. Project-side files: edit in the session worktree + commit (never edit the primary
   checkout directly — note `claude-bump-models --apply` DOES edit the primary checkout's
   working tree, leaving uncommitted changes there; surface that to the user).
6. Launcher tracks usually unchanged (auto-mode picks the model). Check
   `auto_mode_allowlist` — new models lag ~2 weeks before entering Max-plan auto mode.

## Case B — Tier-insertion (new top tier)

1. `model-config.yaml`: set `frontier_latest`; fill `frontier_access` (model, tracks,
   source, start, end, `active: true`, fallback). Add pricing row. Update roles that
   should ride the new tier (`lead_default`, `research_adversarial`, `workflow_judge`,
   `eval_judge`) — teammate roles stay on the auto-mode-allowlisted model. Agent
   Teams run BOTH launcher tracks (eval-track teams empirically fine since 2.1.156);
   the teammate gate is `auto_mode_allowlist` in the SSOT, not the track — once the
   new tier is verified to hold auto mode (one test spawn; `claude auto-mode config`
   does NOT print allowModels), append it to `non_firstParty_max` and the
   enforce-hook follows automatically.
2. **Write all doc references conditionally** so the downgrade needs zero doc edits:
   > "frontier: <Model> via call-time `model: "<alias>"` override while
   > `frontier_access.active` AND on the <track> track; otherwise <fallback>"
3. Canonical reference list (re-walk these for any insertion; verified present 2026-09-03):
   - `~/.claude/commands/research.md` — type-mix table + the frontier footnote
   - `~/.claude/agents/deep-research.md` + `deep-research-sonnet.md` — descriptions only
   - `~/.claude/model-config.yaml` — roles/comments
   - project `.claude/commands/project-pass.md`, `docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md`
     (reso — a SECOND repo with its own gate and land cycle; scope that deliberately)
   - ~~`~/.claude/rules/research-subagents.md`~~ — **GONE.** `~/.claude/rules/` does not load on
     this machine and the file no longer exists; `model-classification.json` still lists it in
     `review`, which is a dead path a walk will silently find nothing in.
   🚨 **Name the SSOT KEY, not the model.** Write "`versions.frontier_latest`, currently Fable 5"
   rather than "Fable 5". Measured 2026-09-03: this footnote had accumulated THREE false claims
   (a window that ended two windows earlier, an `AND on the claude-next eval track` conjunct no
   session could satisfy after consolidation v2, and a fallback that had moved to Opus 5) — and a
   conditional that names a deleted track reads as "the tier is unavailable". A doc that restates
   a perishable fact has no path to learn the fact changed.
4. **Agent frontmatter stays a family alias (`model: opus`)** — definitions are shared
   by both launcher tracks; the new tier exists only where its CC version runs. The
   upgrade is always a call-time `model` override (Agent tool: `"fable"`; Workflow
   `agent()` opts.model) from a lead that has checked `frontier_access`.
5. Launcher: sweep every binary pin (Appendix census) — there is no longer an "eval track only"
   option to hide behind. ⚠️ The old text here read "bump the EVAL track only, NEVER the stable
   track", which was safe advice in the two-track world and is unrunnable now: consolidation v2
   deleted the eval track, so a bump is fleet-wide by construction. That is what makes gate 3
   (`/cc-upgrade-gate`) load-bearing rather than optional.
6. Verify (below) + write a memory entry. Record the **access terms**, not a window end date —
   `frontier_access.permanent: true` is the current shape and a hardcoded end date was the thing
   that rotted last time.

## Case C — Downgrade / window-end

Because Case B wrote conditional references, this is config-only:

1. `model-config.yaml`: `frontier_access.active: false` (leave the block — historical
   record + reusable for the next window).
2. `~/.zshrc`: remove `--model <id>` from the eval-track function (2 refs, ~lines
   306/310); keep the version pin unless also rolling back CC.
3. Roles: conditional roles auto-degrade via `fallback` — no edit. If any doc hard-pinned
   the frontier ID outside the conditional pattern: `claude-bump-models --from-to
   claude-fable-5 claude-opus-4-8` (dry-run first).
4. `claude-lint-models.sh --all` → expiry warning clears (active is false).
5. Memory: note the window closed + actual end date.

## Verification (every case)

```bash
yq -e '.versions' ~/.claude/model-config.yaml >/dev/null && echo yaml-ok
claude-bump-models            # dry-run: expect 0 pending
~/.claude/scripts/claude-lint-models.sh --all
rg -n 'claude-(fable|opus|sonnet|haiku)-[0-9]|Opus [45]\.[0-9]|Fable [0-9]' \
  ~/.claude/commands ~/.claude/agents ~/.claude/model-config.yaml
# the binary actually in service, and whether it knows the id you just wrote:
BIN=$(readlink -f "$HOME/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe")
strings -a "$BIN" | grep -c -- "$(yq -r '.versions.frontier_latest' ~/.claude/model-config.yaml)"
strings -a "$BIN" | grep -c -- claude-opus-5     # positive control; 0 here means the PROBE is broken
```

⚠️ Two corrections to what this block used to say (2026-09-03). It ran `claude-next --version` —
that launcher was deleted by consolidation v2 and the command silently does nothing. And it grepped
`~/.claude/rules`, which **does not load on this machine and no longer exists** (probe-verified on
2.1.114 and 2.1.220; the content moved to reso's `.claude/rules/`). A verification step that greps
an absent directory returns clean and proves nothing — swap the paths, keep the intent.
**Update `.claude-220` above to whatever the launcher pin currently is** — see the Appendix census;
that path is itself one of the pins that goes stale.

## Appendix — the binary pins (runtime, distinct from doc refs)

⚠️ **REWRITTEN 2026-09-03. This section used to describe TWO launcher tracks — a held-at-2.1.114
"stable" `claude`/`cc` via `claude-latest`, and an "eval" `claude-next`/`cc-next` — with the rule
"bump the EVAL track only, NEVER the stable track". That world is gone.** Launcher consolidation v2
deleted `claude-next`, `cc-next`, `claude-fable*` and `claude-opus5`; the survivors are `claude`,
`cc`, `claude-prev`, `cc-prev` and the account/effort variants (`claude2/3/4`, `claude-x`,
`claude-h`, …). Every one of them resolves to a single pin. **There is no second lane still running
the old binary**, which is precisely why the binary gate now has to be Step 0: a bump is fleet-wide
and simultaneous, not a track you can try things on.

**The pins are plural and cannot check each other** (census 2026-09-03; `.claude-220` was current):

| Where | Shape | If left stale |
|---|---|---|
| `~/.zshrc:496` | `local _bin="$HOME/.claude-220/node_modules/.bin/claude"` — inside `claude()` | LOUD. The path is gone, the launcher errors. |
| `bin/cc-offload:87` | `CLOUD_CLAUDE="${CC_CLOUD_CREATE_BIN:-$HOME/.claude-220/…}"` | **SILENT.** Old dir still on disk ⇒ cloud offload keeps running the OLD binary. |
| `scripts/lib/cloud-create.sh:116` | `: "${CC_CLOUD_CREATE_BIN:=$HOME/.claude-220/…}"` | **SILENT**, same shape. |
| `scripts/capacity-ramp.sh:51` | `BIN="${CC_RAMP_BIN:-$HOME/.claude-220/…}"` | **SILENT.** |
| `hooks/model-permission-decider.py:93` | `"MITL_CLAUDE_BIN", "/Users/chrisren/.claude-220/…"` — absolute | **SILENT**, and it decides permissions. |
| `scripts/mcp-modal-probe.py:28`, `scripts/mcp-modal-e2e-probe.py:12` | probe paths | probe measures the OLD binary and reports it as current. |
| `bin/cc-notify:754` | error text: "Point `CC_CLAUDE_BIN` at a **2.1.220+** binary" | a version ASSERTION inside a string; goes quietly wrong. |
| `bin/cc-reaper:2766-2768` | `/x/.claude-220/…` selftest stubs | fixtures, not live — but they rot as fixtures. |

**The `${VAR:-default}` ones are the dangerous class**, and for the same reason the model-id
EMITTERS are: they do not fail, they keep working against the previous version, which is still
sitting on disk precisely because we keep it for rollback. The rollback artefact is what makes the
stale pin invisible.

📌 Filed as backlog `e8b753cac339` with this census. It supersedes the older task-board item
("claude_bin is pinned in 2 places that must agree but cannot check each other"), which
**undercounts** — measured, it is 6 live pins plus 2 probes and a version assertion inside a
string. Bumping the binary means sweeping all of them, or — better, and the actual fix — giving
them one resolver to read.

**Bump procedure:** `npm install --prefix ~/.claude-<NNN> @anthropic-ai/claude-code@<ver>` →
run the binary gate's gates 1–3 → sweep every pin above → `source ~/.zshrc` → keep the prior
`~/.claude-<NNN>` for rollback. `~/.claude-versions/` + `bin/claude-latest` + MANIFEST default-deny
still exist and still guard the legacy `claude-latest` path; the live launcher no longer goes
through them, so a MANIFEST entry is no longer sufficient to move the fleet.

## Invariants

1. **Never write a model id the LIVE binary cannot dispatch** — that is Step 0, and it is the
   invariant this skill most recently lacked. (Superseded wording: "never pin a model the stable
   track doesn't know". The stable/eval split is gone; the constraint survives and got stricter,
   because there is now only one track and no parallel lane to fail safe into.)
1b. **A staged id is not a routed id.** While `<family>_staged` is set, every doc, role and
   allowlist keeps naming the OLD model, and `claude-bump-models --apply` stays unrun. The staged
   key exists so the SSOT can record a release without claiming it.
2. Never rewrite historical citations, benchmarks, incident records, or provenance lines.
   The test is tense: "the worker slot defaults to X" is a routing claim (update); "Sonnet 5
   measured ≤ Opus 4.8 quality" is a measurement (preserve, and annotate as not-re-run).
3. Frontier docs are conditional-by-construction; if you catch yourself writing a bare
   "use Fable 5" without the window condition, rewrite it.
4. Model facts come from the claude-api skill, not memory.
5. `claude-bump-models --apply` mutates the PRIMARY checkout working tree — project-side
   fixes go through a session worktree + commit instead.
6. **A CC-version ROLLBACK silently drops capabilities that live in the binary, not in our
   config.** Recorded instance (still the canonical example): rolling 2.1.170 → 2.1.114 dropped the
   long-horizon harness — the autonomous-loop preamble, the "check your last paragraph before
   ending the turn" early-stop instruction, and the `SendUserMessage` verbatim tool all lived in
   the newer binary. The specific version pair is historical (the eval track it described is gone),
   but the CLASS is permanent and now matters MORE: with one track, a rollback moves the whole
   fleet. A model-only change (Case C) keeps the version pin and is unaffected. After any
   CC-version rollback, re-verify that autonomous `/loop`, `/frontier-run` and `/schedule`
   still self-terminate and report correctly — and prefer re-running `/cc-upgrade-gate` on the
   rolled-back build over assuming the old one still behaves as remembered.
7. **Registration ≠ entitlement ≠ plan inclusion.** Three separate gates that fail differently:
   the id missing from the binary (Step 0, silent non-dispatch), the account not entitled
   (server-side, can be date-gated — Fable 5 was), and the model not being in plan usage (a
   billing fact no probe on this box can see). Never let one stand in for another, and record
   "NOT STATED" as itself rather than resolving it to "yes".
