# wave-plan — activation snippet (T-P7-6 quota-aware wave placement)

**C10 ceiling:** the `wave-plan` agent builds + RED-proves `bin/cc-wave-plan` (placement spread, the
≤N/account concurrency cap, the Fable-window straddle guard, the quota-cliff STOP); the **operator**
(or the `wiring-author` consolidation bundle) performs the one symlink below. Nothing here edits
`settings.json` or loads a plist — `cc-wave-plan` is a **leaf CLI with NO standing daemon of its own**;
it is invoked on-demand by `cc-dispatch`. This file is the hand-off.

## What was built (repo files, on `feat/desk-wave-plan`)

| Artifact | Kind | Needs wiring? |
|---|---|---|
| `bin/cc-wave-plan` | on-demand CLI — a wave of `{id,slot}` items → a placement plan `{account,model,effort,fire_line}`, or a cliff STOP | **symlink** into `~/.claude/bin/` (Step 1) |
| `tests/cc-wave-plan.bats` + `cc-wave-plan selftest` | 20-check RED-proofs of every edge | none (CI/regression only) |

## Interface contract (what `cc-dispatch` calls)

```
cc-wave-plan --items '<json>' [--json]      # <json> = [{"id":"…","slot":"…"}, …]  (or --items - for stdin)
                                            # slot ∈ lead | judgment-dense | transcription | adversarial
  --json → JSON array [{id, slot, account, model, effort, fire_line}]
           fire_line = a ready handoff-fire.sh template string — cc-wave-plan NEVER fires; the
           dispatcher writes /tmp/fire-<id>.txt and runs the line.
  exit: 0 ok · 4 QUOTA CLIFF (every account capped → NO plan, stderr "run /limit-recover")
      · 3 config/parse-fail (LOUD) · 2 usage (bad/empty args)
```

Placement is **greedy over `claude-accounts --rank general`** (best-first), at most
`CC_WAVE_MAX_PER_ACCT` (default 2) items per account — a 3rd item to a full account spills to the next.
Per-slot model/effort come from `cc-route <slot> --json` (SSOT-parsed model ids + its own
frontier-window / cliff edges); wave-plan adds the **pre-emptive straddle guard**: a frontier slot
whose Fable window is within `CC_WAVE_FABLE_GUARD_MIN` (default 30) minutes of close — or whose route
is `none` — degrades to an explicit reason-carrying Opus fallback, and **the fable model id never
appears in a straddle plan**. All live reads; no hardcoded window (memory:
frontier-window-ssot-discipline). One IDL record per invocation → `~/.claude/autonomy/idl.jsonl`
(`action` ∈ fired | abstained | failed).

## Env knobs (all defaulted; override only to tune or to stub in tests)

| Var | Default | Purpose |
|---|---|---|
| `CC_WAVE_MAX_PER_ACCT` | `2` | per-account concurrency cap |
| `CC_WAVE_FABLE_GUARD_MIN` | `30` | straddle guard: minutes-to-close below which a frontier slot pre-empts to Opus |
| `CC_WAVE_ACCOUNTS_BIN` | `claude-accounts` | ranking + Fable-window source (test seam) |
| `CC_WAVE_ROUTE_BIN` | `cc-route` | per-slot model/effort source (test seam) |
| `CC_WAVE_IDL` | `~/.claude/autonomy/idl.jsonl` | invocation ledger (test seam) |

## Step 1 — land the branch, then symlink `cc-wave-plan`

```sh
# land feat/desk-wave-plan via the project-local /ship (content-verified) first, then:
ln -sfn ~/Development/claude-infrastructure/bin/cc-wave-plan ~/.claude/bin/cc-wave-plan
```

Depends on `~/.claude/bin/cc-route` and `~/bin/claude-accounts` already being live (both are). If the
`cc-wave-plan` link is absent, `cc-dispatch` simply cannot resolve the wave leaf — there is no daemon
to mis-fire and nothing to unload; the feature is inert until the link exists.

## Step 2 — none

No `settings.json` edit, no launchd plist, no hook insert. `cc-wave-plan` runs only when `cc-dispatch`
calls it. Regression coverage: `bats tests/cc-wave-plan.bats` (12 cases) and `cc-wave-plan selftest`
(20 checks) — both GREEN at hand-off; `shellcheck bin/cc-wave-plan` clean.
