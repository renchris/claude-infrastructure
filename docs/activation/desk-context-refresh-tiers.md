# desk context-refresh tiers — design + soak/go-live (waiting-recycle)

**cc-backlog `4ce6ffc0194f` (operator 2026-07-19).** Extends `hooks/waiting-recycle.sh` from a single
`used_pct ≥ 55` idle gate into a **state-tiered** policy. Recycling an IDLE desk is a FREE WIN (no work
in hand to lose; state is disk-reconstructible), so it should happen proactively — not wait for 55% and
then hit the awkward busy-and-high case. **Evidence:** this desk sat low-context for hours, then hit
**74% mid-conversation**, making the recycle awkward.

## The three tiers

| Desk state | Context | Behaviour |
|---|---|---|
| **IDLE** (SAFE — just waiting) | ≥ `eff_idle` (adaptive) | **Tier 1** — proactive recycle. `eff_idle` starts at `T_IDLE` (35, was 55) and **decays** toward `T_IDLE_FLOOR` (25) the longer the SID sits idle below it, over `IDLE_DECAY_S` (3600 s) — directly targeting "sat idle for hours". |
| **BUSY** (dirty tree / inbound coordination) | `T_IDLE` ≤ used < `T_BUSY` | **Tier 2** — don't interrupt medium work; **mark a refresh-queued** intent + hold with the specific reason. The lowered idle threshold fires it at the next idle gap (context grows monotonically, so it converges there). |
| **BUSY soft** (dirty tree / inbound wait / mailbox) | ≥ `T_BUSY` (75) | **Tier 3** — **force-recycle, DRAINING the ping queue** (mailbox tails + inbound OPEN wait-contracts naming this desk) into the successor brief so **NONE are dropped**. |
| **BUSY hard** (git sequencer / open decision / live teammate) | ≥ `T_BUSY` | **PAGE, never force** — a recycle would lose state or bury a decision. Surface out-of-band. |

`T_BUSY = 75` sits just above the observed-awkward 74%: the *primary* fix is the lowered idle threshold
(recycle while idle, before ever reaching 74%); the busy-force path is the **safety net** for when a desk
genuinely climbs while busy.

### Soft vs hard holds (the load-bearing safety line)

- **soft** = disk-DURABLE state the successor inherits: uncommitted tree (the working tree survives a pane
  recycle), an inbound wait-contract, a mailbox ping. At high context these force-recycle, carrying the
  drained pings; the brief flags "inspect `git status`/`git diff` before assuming a clean slate."
- **hard** = would LOSE state or BURY a decision: a git sequencer mid-merge/rebase, an open operator
  decision (anti-deference GENUINE carve-out), a live context-bound teammate (results route to the dying
  SID). These **never force** — they page.

## Damp-first (unchanged discipline)

Every new aggressiveness is **advisory or SHADOW+page by default** — nothing auto-execs until armed:

- **Idle Tier-1** recycle: advisory → Stage-2 exec only when `arm --live` (as before).
- **Tier-3 busy-force** exec is opt-in **beyond** `--live` (a mid-work recycle is qualitatively riskier):
  SHADOW default composes the drained brief + **PAGES** (fleet-safe, ships LIVE) but does not exec; the
  exec needs `arm … --live --busy-force`.
- **Hard-hold page** is fleet-safe → ships LIVE.

Blast radius of a wrong fire = one clean recycle (same `handoff-fire.sh --recycle` a manual `/handoff`
uses; the successor re-derives from disk). Bias stays FALSE-NEGATIVE (a missed recycle just waits).

## Knobs (env / `arm` flags)

| Knob | Default | Meaning |
|---|---|---|
| `CC_WR_T_IDLE` (or legacy `CC_WR_T`) | 35 | base IDLE recycle threshold |
| `CC_WR_T_IDLE_FLOOR` | 25 | adaptive-decay floor (== `ROT_FLOOR`; the two triggers converge here) |
| `CC_WR_IDLE_DECAY_S` | 3600 | idle-age window over which `T_IDLE → floor` (0 disables decay) |
| `CC_WR_T_BUSY` | 75 | BUSY forced-recycle ceiling |
| `arm … --busy-force` (or `CC_WR_BUSY_FORCE=on`) | off | enable the Tier-3 mid-work EXEC (requires `--live`) |

`waiting-recycle.sh status` prints the effective thresholds + the busy-force mode.

## Soak → go-live

1. **Soak SHADOW** (default once armed): the desk shadow-composes drained briefs + pages on busy+high.
   Review `~/.claude/autonomy/idl.jsonl` for `stage2-shadow` (`mode:"busy"`) and `escalated`
   (`busy-hard-hold:*`) records, and inspect the composed `/tmp/wr-fire-*.txt` briefs — confirm the drain
   captured the right pings and the hard-hold pages fired where a force would have been unsafe.
2. **Idle exec**: `desk-arm-live.sh` (or `waiting-recycle.sh arm --brief <file> --live`) — Tier-1 idle
   recycles begin executing (unchanged path).
3. **Busy-force exec** (after soaking step 1): `waiting-recycle.sh arm --brief <file> --live --busy-force`
   — Tier-3 mid-work recycles begin executing with the drained brief.

## Kill switches (unchanged)

```sh
waiting-recycle.sh clear   # per-desk opt-out (also removes the busy-force sentinel)
waiting-recycle.sh kill    # GLOBAL blanket off
```

Downgrade without disarming: `desk-arm-live.sh --shadow`, or re-`arm --live` (drops `--busy-force`).

## Tests

`tests/waiting-recycle.bats` — 76 cases (59 prior + 17 tiered): lowered/default/alias idle threshold,
adaptive decay + floor, busy-force shadow/live/drain/`--busy-force`-gate, hard-hold pages
(decision/sequencer/teammate) + page-pacing, Tier-2 queue + high-vs-medium contrast, and the CLI. Idle-path
output is byte-identical to the pre-tier hook (all busy branches are guarded), so every prior guarantee holds.
