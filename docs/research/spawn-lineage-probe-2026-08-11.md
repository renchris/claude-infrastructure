# Does a spawn stamp survive the boundary? — the probe backlog `bffbce207f12` demanded first

**Date:** 2026-08-11 · **Item:** `bffbce207f12` · **Status:** probe complete, design relocated, bound landed

The item proposed stamping `CC_SPAWN_ROOT` + `CC_SPAWN_DEPTH` on every session, incrementing depth
per child, and denying at the Agent-tool chokepoint (`hooks/agent-teams-enforce.sh`) when depth or
per-root width exceeded a budget. It then said, correctly, that **the whole design is vacuous if the
environment does not cross a spawn**, and that this was unverified.

It is now verified. The answer moved the design: **the proposed chokepoint is the wrong one, and the
proposed depth axis is unreachable there — but the carrier works across the boundary that matters.**

## The probe

Four arms, each with a positive control, on kitty 0.48.2. A probe with no passing control cannot
distinguish "the value did not cross" from "the reader is blind", and the first arm below returns
the same text in both cases.

| # | arm | result |
|---|---|---|
| a | in-process Agent subagent — its Bash `$PPID` vs the lead's | **81973 in both** — byte-identical; one OS process |
| b1 | kitty pane; the var merely **exported by the caller** | `ABSENT` — does **not** cross |
| b2 | kitty pane; the launch carries `--env K=V` | present ← **control: the reader works** |
| b3 | kitty pane; the launch carries `--copy-env` | present — crosses on demand |
| c | `--env` through the real pane shape, `zsh -l -i -c` | present — survives login+interactive zsh |
| d1 | `--source-window id:A`, source pane holds the var | `ABSENT` — **not** copied to the launched process |
| d2 | `--source-window id:A` **plus** an explicit `--env` | the `--env` value wins ← control |

Arm (d) was run because `bin/it2-kitty` carries an in-line note that `--source-window` copies "title
/ colors / env" from the source window. For the **launched process's environment**, on this version,
it does not — and had it, an incrementing stamp would have been silently overwritten by a copied one
and the cap would have shipped permanently inert. The note is accurate about placement and cwd; this
records the measured exception for env.

Reproduce: `scratchpad/probe-kitty-env.sh`, `scratchpad/probe-sourcewindow.sh` (arms b, c, d);
arm (a) is one subagent reporting `$PPID`.

## What the probe changes

**1. An in-process subagent cannot be stamped at all.** It is not a child process — it *shares the
lead's*, so its environment **is** the lead's and there is no per-child slot to write a different
generation into. A PreToolUse hook cannot mutate its caller's environment either. So `depth+1` is
unreachable on that surface by construction. This agrees, from the opposite direction, with what
`hooks/agent-teams-enforce.sh` already records: Claude Code does not expose the Agent tool to
subagents, so nothing nests there and the depth term's population is empty. **The Agent tool is the
wrong chokepoint for a lineage bound** — not because the bound is wrong, but because no lineage is
created there.

**2. Across a pane, an explicit stamp is the only carrier — because the process tree is severed.**
kitty remote-control launches a pane as a child of the kitty **daemon**, not of the caller. A pane
spawned *by* a pane is therefore indistinguishable from a top-level one in `ps`. This is visible in
the fleet's own records rather than inferred: across all 1085 rows of `logs/pane-spawns.jsonl` the
`ancestry` field contains `claude` **at most once** (distribution `{0: 671, 1: 415}`) and every chain
terminates at a kitty pid.

That last number is the trap worth naming. Reading those 324 bare-`it2-kitty` rows as
`gen==1 everywhere` invites the conclusion *"no cascade is happening"* — from an instrument that
**cannot represent** a cascade. Same shape as `cap-whose-population-is-empty`: the value is the only
one reachable, not a measurement.

## The gap the bound now covers

The existing lineage instrument is the item lease (`scripts/lib/worker-claim-gate.sh`), consumed at
three chokepoints. It keys on the cwd being `wt-<12 lowercase hex>` and abstains otherwise — correct
for a lease, since without a worktree there is no item and no claim. Measured over the same 1085
rows, that abstention is most of the fleet, and the fan-outs beyond it are the widest:

| cwd class | spawns | distinct claude spawners | max fan-out by one session |
|---|---|---|---|
| dispatch `wt-<12hex>` — lease binds | 214 | 40 | **7** |
| shared repo root — lease abstains | 303 | 23 | **21** (5 sessions ≥ 10) |

So the bound that exists works, and the population it cannot reach carries the worst shapes.
Identity remains the right instrument — a per-session **count** resets at exactly the edge a cascade
crosses — but where the ledger has no identity to offer, one has to be carried.

`lr-reset-poller.sh` (296 rows) is excluded: its ppid is always launchd and it logs `pane: null`, so
it cannot recurse.

### Which surface those spawns actually cross — and why this bound has two sites

While this work was in flight, `d8b720c6` (backlog `6f24f9c49e3e`) landed a correction: the bare
`chain:"it2-kitty"` rows are **not** Bash-invoked splits. Claude Code's teammate-pane backend
invokes `it2-kitty` **directly** for any Agent call carrying a `name`/`team_name`, so no Bash tool
call exists on that path to gate.

Re-derived here independently before building on it, since a bound on the wrong surface is the
defect this thread keeps repeating — the discriminating leg with its own control, same log:

| chain | n | `ppid_comm` |
|---|---|---|
| bare `it2-kitty` | 324 | **claude 319**, bash 5 |
| `kitty-split-launch.sh` (session-invoked control) | 16 | **zsh 16** |
| the 131 non-worktree rows above | 131 | **claude 127**, bash 4 |

A Bash tool call necessarily runs its command under the tool's own shell, which would sit between.
It does not. **Confirmed** — including for the 131 rows this bound was sized on, which means a
Bash-surface term alone would have been blind to its own motivating population.

Hence two enforcement sites, on two populations, not one term written twice:

- **`hooks/agent-teams-enforce.sh`** — named Agent calls, the surface the cascade crossed. Scoped to
  pane-minting calls only: an *unnamed* call is an in-process subagent, which mints no session, has
  no environment of its own, and cannot nest, so it cannot begin a generation. Capping it would
  refuse read-only research fan-out — this tool's largest legitimate use — for something it is
  incapable of doing.
- **`hooks/validate-bash.sh`** — session-invoked pane spawns (the `ppid_comm=zsh` shape, 16 rows).
  A real but smaller population. It is kept, and it is *not* cited as bounding the cascade.

## What landed

- `scripts/lib/spawn-lineage.sh` — derives the lineage identically at both sites: inherit when
  stamped, else mint `p<claude-ancestor-pid>`. Emits the child's `--env` argv.
- `bin/it2-kitty` — stamps `CC_SPAWN_ROOT` + `CC_SPAWN_GEN` onto the launch, **above** the three
  launch branches so the pre-delivered, armed, and legacy-typed paths all carry it. This is the one
  site every pane arrival converges on, including the backend-invoked ones.
- `hooks/agent-teams-enforce.sh` — the generation cap on named Agent calls (the cascade's surface).
- `hooks/validate-bash.sh` — the same cap on session-invoked pane spawns, reusing the pre-filter and
  the `self-close` exemption the lease term already computes.
- `tests/spawn-lineage.bats` — 22 cases. Every refusal is paired with an admitting control differing
  in exactly one axis, and six naive mutants (stamp removed · generation never increments · cap
  unreachable · either deny dropped · unnamed subagents wrongly capped) each turn it red.

**Only generation is enforced.** The ladder is desk(0) → wave lead(1) → dispatched phase session(2)
→ that session's own teammates(3) → refused; `CLAUDE.md` § Agent Teams sanctions every rung through
3, so the cap sits one rung past the deepest sanctioned shape. Per-root **width is counted and never
refused**: the widest legitimate observation (21) and the pathological one are not separated by any
threshold this data supports, and a bound sitting inside the survived band can only manufacture
false refusals. The counter ships so the next reader has the distribution the threshold needs.

Every undecidable path admits and writes an IDL row with its own `basis`, so "unstamped" and "could
not read the stamp" are never the same value.

## Known limits — stated, not discovered later

- **The carrier is partial.** Only `bin/it2-kitty`'s split surface stamps. `kt launch --type=tab` /
  `--type=os-window` in `scripts/handoff-fire.sh` (lines ~7153, ~7579, ~7645) do not, so a pane
  created there starts a fresh lineage. That is today's behaviour, so a miss is a smaller
  improvement rather than a regression — but it is a miss, and it is where the next increment goes.
- **The cap is unproven against a live cascade.** Every arm above is measured, and the two enforcing
  terms are red-proofed by mutation — but no runaway has occurred since they landed, so the claim
  "this would have stopped generation 4" is a derivation from the ladder, not an observation. The
  IDL rows (`gate:"spawn-lineage"`, carrying `root`, `gen`, `basis`) are what will settle it; the
  first real fan-out after this lands writes the distribution nobody has yet.
- **The cap cuts the tail of a runaway, not its head.** Against the 2026-08-07 shape (worker → 6 →
  6 → 5), a cap of 3 stops generation 4. It does not bound the width of generations 1–3; the lease
  does that where an item exists, and nothing does where one does not.
- **Width is unenforced on purpose.** Until the bands separate, the honest artifact is a counter.
