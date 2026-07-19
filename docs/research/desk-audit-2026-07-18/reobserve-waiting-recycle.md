# Re-observe: `waiting-recycle` — VERDICT: NOT inert (false-positive flag; DORMANT by design)

**Disposes** cc-backlog `f75a196e00dc` — *"inert hook waiting-recycle: re-observe"*
(source `wiring-inert`, dodRef `~/.claude/autonomy/idl.jsonl`, filed 2026-07-19T02:40:13Z).
**Re-observed** 2026-07-19. **Evidence:** the live IDL (1,593 `waiting-recycle` eval records across
38 distinct SIDs, 2026-07-19T06:44:52Z → 2026-07-19T11:46:03Z) + `hooks/waiting-recycle.sh` +
`bin/cc-discover` (C3 critic) + the p04 audit + the in-flight C3 reason-aware fix branch.

## TL;DR

The hook is **healthy and DORMANT, not inert.** The C3 `wiring-inert` critic flagged it on a **false
positive** of the *same reason-blind defect* that produced the three sibling `re-observe` items
(`6bc2d518c8cb`, `8a5aaf4eb824`, `8b9e2b594705`). Every one of the 1,593 abstains carries reason
`not-armed` — the hook's **opt-in kill-switch** (`waiting-recycle.sh:189`; header §1: *"OFF BY
DEFAULT ⇒ a builder is never touched. This IS the primary kill-switch"*). `not-armed` is a
**DORMANT** (fire-condition-legitimately-not-met) abstain, **not** a **BLIND** (couldn't-evaluate)
one, so counting it toward the D9 "inert" signal is a category error. The hook needs **no change**;
the fix belongs on C3 and is **already in flight** (`a9fff82eafac`, branch
`fix/cc-discover-c3-reason-aware`), which reclassifies `not-armed` as DORMANT and clears this flag.

## The flag is live right now (verbatim critic reproduction)

Reproducing `critic_wiring_inert` (`bin/cc-discover:189-191`) on the live IDL flags `waiting-recycle`
(point-in-time snapshot; the live IDL appends continuously, so the `waiting-recycle` count reads
1,572 in the critic's tail window here and 1,593 full-file a few minutes later — both are the same
100%-abstained/0-fired picture):

| hook | in-horizon abstained | fired | flagged? |
|---|---:|---:|:--|
| `anti-deference-nudge` | 60 | 0 | ✗ flagged (already dispositioned — `6bc2d518c8cb`) |
| `boundary-handoff` | 59 | 1 | ✓ clear (fire in window) |
| `completion-assert` | 59 | 1 | ✓ clear (fire in window) |
| **`waiting-recycle`** | **1,572** | **0** | **✗ flagged — this item** |

The current critic (post the `e7d326caa6a7` per-hook-horizon + actor-exclusion fix) is still
**reason-blind**: it counts every `abstained` record identically, so 1,572 healthy `not-armed`
abstains and 0 fires trip `fired == 0 AND abstained >= 10`.

## Why `not-armed` is DORMANT, not BLIND (the whole case)

`waiting-recycle` fires on the desk's **monitoring cadence** (PostToolUse:Bash). Its **first** gate,
after the cheap `no-jq`/`no-session-id`/`global-kill`/`no-cwd` fail-safes, is the opt-in check:

```sh
# waiting-recycle.sh:188-189
# 1. OPT-IN: armed for this cwd? OFF by default ⇒ a builder is never recycled at 55%.
[ -f "$(arm_for "$CWD")" ] || abstain "not-armed"
```

A desk becomes eligible **only** by explicitly running `waiting-recycle.sh arm` (a cwd-keyed
sentinel). Until then the hook **correctly and deliberately** abstains `not-armed` on every poll.
That is the hook **working exactly as designed** — the analog of the siblings' `no-tell` /
`below-threshold` DORMANT abstains — not a failure to observe its guard.

Splitting the 1,593 abstains the way the D9 signal *should* (per the sibling root-cause and the
in-flight C3 fix):

- **BLIND / degraded** (`no-jq`, `no-session-id`, `no-telemetry`, `stale-telemetry`,
  `transcript-missing`, `fire-compose-empty`, …) — the hook *couldn't* evaluate. This is the true
  "inert" signal. **Count in this window: 0.**
- **DORMANT / fire-condition-not-met** (`not-armed`, `cooldown`, `capped`, `below-threshold-no-tell`,
  `dirty-tree-hold`, `open-decision-hold`, the coordination holds, `already-fired`) — the hook
  evaluated fine and correctly chose not to fire. **Count in this window: 1,593 (all `not-armed`).**

A hook that is 100% DORMANT and 0% BLIND has **not** stopped observing anything — it is observing
correctly and finding, every time, that no armed monitoring desk is present in this cwd.

## The wiring is demonstrably intact (inert-by-construction is refuted three ways)

1. **Registered + deployed, no drift.** p04 audit (`p04-wait-recycle.md:21`): *"hook-enforced —
   PostToolUse:Bash registered `~/.claude/settings.json:531`; deployed as COPY (byte-identical to
   repo, no drift). **Dormant: no desk armed.**"* The original audit already reached this verdict —
   **dormant, not inert.**
2. **Tests GREEN.** `tests/waiting-recycle.bats` **28/28** (p04, read+ran) — the fire path, the
   two-stage escalation, and every SAFE-hold are exercised.
3. **Live evaluation, at cadence.** 1,593 IDL records across **38 distinct SIDs** in a ~5-hour
   window prove the hook is invoked and logs a disposition on essentially every desk Bash poll
   (B-3: *"one IDL line per invocation… 'didn't fire' ≠ 'never evaluated'"*). A truly inert/dead
   hook emits nothing; this one is loud.

## The arm path is not merely functional — it was live-exercised during the window

One desk **armed the hook LIVE** (with a Stage-2 successor brief) at **2026-07-19T11:39:06Z**, cwd
`/Users/chrisren/Development/claude-infrastructure` (`state/waiting-recycle/arm-*`, `live-*`,
`brief-*` all present). That is the `66ba509a9d20` *"CRUX — arm the deterministic desk auto-recycle
(Stage-2 live)"* go-live in progress, ~1 minute before this very item was dispatched. So the hook is
**not** stuck in a never-can-be-armed state; arming is actively happening. The armed cwd simply
emitted no PostToolUse:Bash records inside the observed IDL span, so all 1,593 records come from the
38 *other* (unarmed) sessions correctly abstaining `not-armed`.

> Why 0 lifetime fires is expected, not alarming: `waiting-recycle` was **redesigned** (Fable panel
> 2026-07-19, header §"TWO-STAGE ACTUATION") precisely *because* its advisory-only predecessor
> *"fired 0/2419 in prod because the fire depended on the model NOTICING + complying."* The
> deterministic Stage-2 fire is the fix — but it can only fire for an **armed** desk that crosses the
> moderate threshold. With arming just now going live, "0 fires so far" is the pre-adoption baseline,
> not a wiring fault.

## Disposition

- **Hook:** no change. `waiting-recycle` is healthy — registered, byte-identical-deployed, 28/28
  GREEN, evaluating at cadence, and correctly DORMANT (`not-armed`) until a desk opts in.
- **This item (`f75a196e00dc`):** closed `done`. Durable against re-flagging by the same idempotency
  keying the sibling report documents (`cc-backlog add` is a no-op on an existing id, `bin/cc-backlog`
  — C3's re-`add` of the same (project+title+source) key cannot re-open it).
- **Root cause → already tracked + fixed in flight.** The reason-blind C3 defect is item
  `a9fff82eafac` (*"cc-discover C3 wiring-inert reason-blind: exclude healthy condition-not-met
  abstains"*), branch `fix/cc-discover-c3-reason-aware`. **Verified:** that branch's `_inert_blind`
  set (`bin/cc-discover`, reason-aware revision) **excludes** `not-armed`, and its predicate flags a
  hook only when `blind == abstained` (every abstention BLIND). With `blind = 0` for
  `waiting-recycle`, the reason-aware critic returns it **not-inert** — its own test fixture seeds a
  `not-armed`-dominated `dormant-guard` and asserts **0 adds**. Landing `a9fff82eafac` clears the
  false positive on `waiting-recycle` **and** the still-open `anti-deference-nudge` re-flag in one
  move. (`117bf1aea7b7`, the per-hook-window half, already landed.)
- **The substantive question is owned elsewhere, not dismissed here.** *Whether* `waiting-recycle`
  should arm-by-default for monitoring desks (so it stops being dormant on the desks that want it) is
  a live **design** decision tracked by `868c9271cb5f` (*"arm-by-default for monitoring desks +
  escalate/page at cap"*, open) and the Stage-2 go-live `66ba509a9d20` (claimed). This re-observe
  answers only *"is the C3 inert flag real?"* (no) — it does not pre-empt those.

## Caveat for the C3 / arming follow-up (not this item)

Two properties worth carrying forward, both out of scope here:

1. **Masking caveat (shared by every discovery candidate).** Because the candidate id keys on
   (project+title+source) and `add` is a no-op on existing ids, closing this false positive `done`
   also permanently masks a *future genuine* inertness of `waiting-recycle` under the same title.
   Noted so the C3 owner can decide whether inert candidates should carry a re-observation epoch in
   their key. (Identical to the `6bc2d518c8cb` caveat.)
2. **Cross-config arm-key mismatch (already on the arming owner's radar).** The arm sentinel is keyed
   `shasum($CLAUDE_CONFIG_DIR|$CWD)` (`waiting-recycle.sh:97`). The live arm above was written under
   `.claude-tertiary`; a desk session running the *same* cwd under a different config dir computes a
   different key and would see `not-armed`. The `fix/cc-discover-c3-reason-aware` branch already
   references this exact *"stranded arm ⇒ abstain `not-armed` under a config the live desk never
   checks"* scenario, so it is being handled in the arming/go-live work — cross-referenced, not
   re-filed.
