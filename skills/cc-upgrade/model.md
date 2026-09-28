# model.md — moving to a new Claude model or off one (phases P1, P7)

Model facts (ids, pricing, capabilities, deprecations) come from the `claude-api` skill and the
release pack (utilize.md), never from memory.

## P1 — registration: does the binary know the id? Run it BEFORE classifying, every time

🚨 **We pin Claude Code, so a model release is ALWAYS also a binary event.** A model that shipped
after our pinned build cannot be in that build; no SSOT edit makes it dispatchable. Ask the binary:

```bash
cc-model-registered <new-id>                                          # the live fleet pin
cc-model-registered <new-id> --bin ~/.claude-<NNN>/node_modules/.bin/claude   # each candidate
```

It resolves the live pin through `bin/cc-claude-bin`, byte-scans with mmap, counts the id only
where it is not a prefix of a longer id (`claude-sonnet-5` inside `claude-sonnet-5-5` does not
count), and always counts the control `claude-opus-5` beside it. **Never report a bare zero**: a
plain `grep` on this Bun binary reads 0 for every model, including ones the fleet runs, so the
obvious probe is blind in the direction that looks like a finding.

| Exit | Meaning | What this upgrade is |
|---|---|---|
| 0 | present on the live pin | Ordinary model lane. Continue to Step 1. |
| 1 | absent on the live pin | **STAGED** — the both lane. Park the id in `versions.<family>_staged`, leave `<family>_latest` and `<family>_prior` alone, do **NOT** run `claude-bump-models --apply`, and run audit + gate (audit.md, gate.md) on a candidate where the id reads 0. |
| 2 | control absent / no readable binary | **STOP.** The instrument is broken, not the binary. |

Why the `--apply` prohibition is absolute: the sweep rewrites roles, the auto-mode allowlist and
every doc literal to an id the harness cannot resolve. Nothing warns you; the next `/frontier-run`
or teammate spawn simply fails. Leaving `<family>_prior` empty is what keeps the *current* model
from being convicted as stale — `claude-lint-models` collects its stale set from `_prior$` keys and
`claude-bump-models` iterates `${family}_{latest,prior}`, so a `*_staged` key is inert in both. A
family with no `_staged` key yet gets one when you stage it. Every recent release has been staged
(historical: Opus 5, Fable 5.1, Opus 5.5 and Sonnet 5.5 each needed a newer binary), and each was
rediscovered by hand until this step existed.

## Step 1 — classify the event (misclassifying is THE failure mode)

| Case | Signature | Example |
|---|---|---|
| **A. Lateral** | New model REPLACES the same-family prior | Opus 4.7 → 4.8; Fable 5 → 5.1 |
| **B. Tier-insertion** | New tier ABOVE the ladder; the old top STAYS in service | Fable 5 above Opus 4.8 |
| **C. Downgrade / window-end** | Access to a top tier lapses; fall back | a future tier's window ends (a permanent tier, `frontier_access.permanent: true`, never does) |
| **D. Role / default-tier repoint** | The ladder is unchanged and every id stays in service; what moves is WHICH model a `roles.*` key (incl. `roles.lead_default` and the launcher) points at | "should the frontier tier become the starting model?"; "move the research worker onto the new Sonnet" |

⚠️ **Case and binary state are INDEPENDENT axes.** A lateral bump whose id is absent is still a
lateral bump; it is just gated. Classify normally, then run the case's steps only after the binary
clears. A blind literal sweep is correct ONLY for Case A. Case B is "add alongside" (claude-api
migration guide, Step 1 Bucket 2): rewriting `opus → fable` would de-tier references that must
stay Opus.

🚨 **"Use the new model to the full" is mostly Case D.** The `versions` bump is Case A; the value is
in moving `roles.*` keys (`research_worker`, `workflow_synthesis_worker`, `teammate_mechanical`,
…) onto it at chosen effort rungs (utilize.md). So a model-lane run ends in the Case D emitter
census below, not in a green lint.

## Case D is not served by the sweep tooling, and the failure is silent

A, B and C move a `versions.*` key; D moves **`roles.*`** and touches `versions.*` not at all. Both
sweep tools derive their working set exclusively from `versions`:

- `~/bin/claude-bump-models` — `for family in frontier opus sonnet haiku` builds pairs from
  `versions.${family}_prior|${family}_latest`. A `roles.*` edit yields **no pair**.
- `scripts/claude-lint-models.sh` — `.versions | … select(.key | test("_prior$"))`. A `roles.*`
  edit contributes **nothing** to the stale set.

⇒ **Both tools report clean on a Case D change while checking nothing.** For Case D the
verification is these, and none is automatic:

1. **Decide in the currency that binds.** On a Max-plan fleet this is weekly plan quota, not
   $/token. The frontier tier is a **sub-cap of the same weekly bucket** (`accounts.json`
   `frontier.coupling`), so a default on it strands capacity at any quality. Read
   `docs/research/fable51-vs-opus5-routing-2026-09-16/` before re-opening this (its § Re-derive
   gives the two commands) and re-derive, never re-quote.
2. **Enumerate the default-model EMITTERS by hand** — they are not a `versions` sweep:
   `roles.*` in the SSOT · `~/.zshrc` `claude()` `--model`/`--effort` · the per-config-dir
   `settings.json` files (incl. any `"model"` key — they need not agree) · `agents/*.md`
   frontmatter · `commands/handoff.md` · `hooks/frontier-spawn-gate.sh` (keyed by PREFIX — under a
   frontier default it throttles ORDINARY work) · `lib/cc-upgrade-gate/check05_launcher.sh`
   (expects `--model` = `versions.opus_latest`, so a lead repoint off Opus reds it; gate.md).
3. **Widening `model-classification.json`'s `update` list is not the fix.** Both tools are now
   word-boundary anchored (a prefix id no longer corrupts to `…-1-1`), but the sweep still only
   rewrites `_prior → _latest` pairs; a roles move produces none.
4. **There is no staging surface for a routing decision.** `*_staged` stages a RELEASE and is
   invisible to both tools; `accounts.json` accounts carry no model field. The **role ladder is the
   only A/B surface** — move ONE role, measure, revert in one line.

## SSOT map

| File | Job |
|---|---|
| `~/.claude/model-config.yaml` | `versions` (latest/prior/staged per family: frontier/opus/sonnet/haiku), `frontier_access`, `pricing_per_mtok`, `roles`, `effort_defaults`, `auto_mode_allowlist`, deprecations |
| `~/bin/claude-bump-models` | literal-id sweep over classified files (`--apply`, `--check`, `--from-to OLD NEW`) |
| `scripts/claude-lint-models.sh` | stale-ref lint (`--all`) + frontier-window expiry check (fails when the window lapsed but `active: true`) |
| `~/.claude/model-classification.json` | `update` = auto-sweepable; `preserve` = historical, never touch; `review` = mixed prose/citations, walked by hand here |
| `~/.zshrc` `claude()` | runtime selection: the `_bin` pin and the `--model`/`--effort` defaults, separate from doc refs |

**Known blind spot:** the sweep and lint match full ids (`claude-opus-4-7`) only. Prose forms
("Opus 4.7", "Opus-tier") live in `review` files and need judgment.

## P7 — the flip. Keying first (keying.md), then the case

### Case A — Lateral bump

0. **Registration cleared?** If NOT: write ONLY `<family>_staged: <new-id>` plus the pricing row
   and any deprecation change, leave `_latest`/`_prior` alone, and stop — the rest is gated.
0b. **The repoint clears for NEW shells only — census the fleet before the flip.** A `~/.zshrc`
   repoint reaches shells started after it. A `--recycle` types into the pane's EXISTING shell,
   which keeps its old `claude()` body, so recycling does not move a pane to the new binary
   (historical, the Opus 5.5 move: hours after the repoint, 14 sessions still ran a binary that
   refused the new id by name).
   - **Census:** `ps -axo pid=,command= | awk '$2 ~ /\.claude-[0-9]+\//'`.
   - **Hazard class:** any consumer that hands the NEW full id to a process started by an old shell.
     The family alias (`opus`, `fable`) is resolved by whichever binary runs, so it is safe across
     the split — prefer it at such sites, and hold step 2's `--apply` while the split lasts.
   - Record in the SSOT which consumers are safe and why.
1. `model-config.yaml`: `<family>_prior` = old latest, `<family>_latest` = new id, CLEAR
   `<family>_staged`. Update `pricing_per_mtok` + `deprecations` from claude-api facts.
   ⚠️ `pricing_per_mtok` pairs are `[input, output]` BASE rates and consumers index them
   positionally — do not change the arity. Cache-read multipliers are a real third dimension
   (standard 0.1× base input, but some models differ — read the claude-api skill) and go in
   comments; a base-rate-only comparison misprices any model with a non-standard cache rate.
2. `claude-bump-models` (dry-run) → review the pair list → `--apply`. **Setting `_prior` is what
   arms this**: the lint builds its stale set from `_prior$` keys, so writing `_prior` before the
   binary can run the new id is exactly how a healthy model gets convicted as stale.
3. `~/.claude/scripts/claude-lint-models.sh --all` → green.
4. Walk every `review`-classified file: fix prose refs **except** historical citations
   (benchmarks, incident records, provenance lines). Test: does the sentence claim "what we use
   NOW" (update) or "what happened THEN" (preserve)?
5. Project-side files: edit in a session worktree + commit. `claude-bump-models --apply` DOES edit
   the primary checkout's working tree and leaves uncommitted changes there; surface that.
6. Check `auto_mode_allowlist`: new models can lag before entering Max-plan auto mode.

### Case B — Tier-insertion (new top tier)

1. `model-config.yaml`: set `frontier_latest`; fill `frontier_access` (model, source, start, end
   or `permanent`, `active: true`, fallback). Add the pricing row. Move the roles that should ride
   the new tier (`lead_default`, `research_adversarial`, `workflow_judge`, `eval_judge`) — teammate
   roles stay on an auto-mode-allowlisted model. The teammate gate is `auto_mode_allowlist` in the
   SSOT: once the new tier is verified to hold auto mode (one test spawn; `claude auto-mode config`
   does NOT print allowModels), append it to `non_firstParty_max` and the enforce hook follows.
2. **Write every doc reference conditionally**, so the downgrade needs zero doc edits:
   > "frontier: `versions.frontier_latest` via call-time `model: "<alias>"` override while
   > `frontier_access.active`; otherwise `frontier_access.fallback`"
3. Canonical reference list (re-walk for any insertion; `ls` each before trusting it):
   - `~/.claude/commands/research.md` — type-mix table + the frontier footnote
   - `~/.claude/agents/deep-research.md` + `deep-research-sonnet.md` — descriptions only
   - `~/.claude/model-config.yaml` — roles/comments
   - `.claude/skills/research-subagents/SKILL.md` (the `review` entry in model-classification.json)
   - reso `.claude/commands/project-pass.md`, `docs/research/CONTEXT_EXHAUSTION_GUARDRAILS.md` —
     a SECOND repo with its own gate and land cycle; scope that deliberately
   🚨 **Name the SSOT KEY, not the model.** Write "`versions.frontier_latest`" rather than a model
   name. A footnote that restated the model once accumulated three false claims (a window that had
   ended, a launcher conjunct no session could satisfy, a fallback that had moved), and a
   conditional that names a deleted launcher reads as "the tier is unavailable" (historical).
4. **Agent frontmatter stays a family alias (`model: opus`).** The new tier is a call-time `model`
   override (Agent tool: `"fable"`; Workflow `agent()` opts.model) from a lead that has checked
   `frontier_access`.
5. The binary moves fleet-wide through the activation script (gate.md); every other consumer reads
   `bin/cc-claude-bin`. There is no second lane to trial it on, which is what makes the gate
   load-bearing.
6. Verify (below) + a memory entry. Record the **access terms**, not a window end date — a
   hardcoded end date is what rotted last time.

### Case C — Downgrade / window-end

Because Case B wrote conditional references, this is config-only:

1. `model-config.yaml`: `frontier_access.active: false` (leave the block — historical record,
   reusable for the next window).
2. `~/.zshrc` `claude()`: if a `--model` default names the frontier id, point it at
   `frontier_access.fallback`; keep the binary pin unless also rolling back CC.
3. Roles: conditional roles auto-degrade via `fallback` — no edit. If a doc hard-pinned the
   frontier id outside the conditional pattern:
   `claude-bump-models --from-to <frontier-id> <fallback-id>` (dry-run first; read both ids from the SSOT).
4. `~/.claude/scripts/claude-lint-models.sh --all` → the expiry warning clears.
5. Memory: note the window closed + the actual end date.

### Case D — Role / default-tier repoint

Move ONE role at a time, at the rung utilize.md chose; run the § Case D emitter census above;
spot-check one live spawn of that role (its `modelUsage`); revert in one line if it regresses.

## Verification (every case)

```bash
yq -e '.versions' ~/.claude/model-config.yaml >/dev/null && echo yaml-ok
claude-bump-models            # dry-run: expect 0 pending
~/.claude/scripts/claude-lint-models.sh --all
rg -n 'claude-(fable|opus|sonnet|haiku)-[0-9]|Opus [45]\.[0-9]|Fable [0-9]' \
  ~/.claude/commands ~/.claude/agents ~/.claude/model-config.yaml
# every id the SSOT now routes is registered in the binary actually in service:
for k in frontier_latest opus_latest sonnet_latest haiku_latest; do
  id=$(yq -r ".versions.$k // \"\"" ~/.claude/model-config.yaml); [ -n "$id" ] && cc-model-registered "$id"
done
```

A Case D change also needs its emitter census and a live spawn; the block above cannot see it.

## Invariants (long form)

1. **Never write a model id the live binary cannot dispatch** — P1, every time.
1b. **A staged id is not a routed id.** While `<family>_staged` is set, every doc, role and
   allowlist keeps naming the OLD model, and `claude-bump-models --apply` stays unrun.
2. Never rewrite historical citations, benchmarks, incident records, or provenance lines. The test
   is tense: "the worker slot defaults to X" is a routing claim (update); "X measured ≤ Y" is a
   measurement (preserve, and annotate as not re-run).
3. Frontier docs are conditional by construction; a bare "use <frontier model>" without the window
   condition gets rewritten.
4. Model facts come from the claude-api skill, not memory.
5. `claude-bump-models --apply` mutates the PRIMARY checkout's working tree — project-side fixes
   go through a session worktree + commit instead.
