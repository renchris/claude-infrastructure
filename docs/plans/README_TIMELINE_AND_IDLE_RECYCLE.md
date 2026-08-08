---
status: open
---

# README timeline banner + proactive idle-recycle — 2-track plan

**Created** 2026-08-08 by session `a64e4989` at 71% context, immediately before a `--recycle`.
Durable anchor for two dispatched sessions the successor must fire. Both report back by ping.

---

## Phase 0 — Orchestration

| Field | Value |
|---|---|
| **Execution locus** | **S · dispatched handoff session, one per track** (the default; no justification required). Neither track is lead-inline: A is a long design-iteration loop that would eat the lead's window, B is an investigation across hooks + transcripts. |
| **Tracks** | A (SVG timeline banner) and B (idle-recycle investigation) — fully independent: disjoint files, no ordering dependency, each self-verifiable. Fire both, serially-invoked, in one wave. |
| **Back-channel** | **BOTH tracks fire with `--notify-back <main-pane-uuid>`.** Operator requirement: each must ping the recycled main session on completion. That arms **R-PING** in the main session's disposition until both land — pair with a background `cc-await-ping` so discharge is event-driven. |
| **Accounts** | Rank once (`claude-accounts --rank general`), assign explicitly round-robin, ≤2 tracks/account. Do NOT leave both on `--account auto` — auto cannot see a track that has not started, so a rapid wave piles onto one account. |
| **Surface** | `--split-right` for both (⌘D-style, side by side). Do NOT downgrade to `--tab` at 2 tracks — that is the flagged anti-pattern. |
| **Lead's own budget** | The recycled main session fires, then holds ≥50% of its window for judging the two returns. It does not do either track's work. |

---

## Track A — a bespoke SVG timeline banner

**Objective.** Replace the README convergence diagram with a hand-authored, animated SVG timeline
whose design quality **exceeds** `assets/banner/v6c-dusk-line.svg` (the root hero). Operator verdict
on the current mermaid render: *"still dry and hard on the eyes."*

**Why mermaid cannot get there (settled — do not re-litigate).** `beautiful-mermaid` 1.1.3 supports
only `flowchart` / `stateDiagram` / `xychart`; there is no timeline primitive, no control over node
geometry, no gradients, no motion. Two mermaid iterations already landed and both failed on design:
`6c4c86d7` (two subgraphs — ELK inverted their rank, so a section headed *"this repo shipped first"*
opened with Claude Code winning) and `7691cd44` (linear chronological chain — correct, legible, still
visually flat). The ceiling is the renderer, not the source.

**The data is SETTLED — do not re-derive it.** Every date is verified and landed:

| Date | Event |
|---|---|
| 2025-02-24 | Claude Code `0.2.6` first npm publish |
| 2025-12-15 | Claude Code `2.0.70` — status-line context fields exist |
| 2026-03-24 | this repo's first commit (`aa391e46`), 13 months in |
| **2026-05-24** | **this repo — adversarial-role research team** |
| 2026-05-28 | Dynamic Workflows `2.1.154` — same idea, **4 days later** |
| **2026-07-10** | **this repo — peer session messaging** |
| 2026-07-14 | this repo reads the 2025-12 status-line fields — **7 months late, our gap** |
| 2026-08-07 | Claude Code `2.1.224` — sessions message each other, **28 days later** |

**Constraints (HARD).**
1. **GitHub-safe or it is worthless.** Inline `<style>` only; no external refs, no scripts, no
   `foreignObject`. GitHub's image proxy blocks external font `@import` — pin the system stack. CSS
   animation is permitted and is how the hero animates; JS is not.
2. **Theme-adaptive** via the existing `<picture>` + `prefers-color-scheme` pattern already in the README.
3. **Keep the mermaid source and its `<details>` fence** as the accessible/interactive fallback —
   `assets/diagrams/vendor-convergence.mmd` stays, `npm run diagrams:check` must stay green.
4. **Do not touch the hero** `assets/banner/v6c-dusk-line.svg`, and do not compete with it stylistically
   at the top of the page — this asset sits at README §"Twice, this repo shipped it first".
5. **Verify by SCREENSHOT, not by exit code.** Every mechanical check passed on the diagram whose rank
   was inverted; only a rendered image caught it. Screenshot both modes on GitHub bg
   (`--default-background-color=0d1117ff` / `ffffffff`) and LOOK.
6. Full alt text describing the chronology (a screen reader must get the same story).

**Prior art to read first:** `tools/banner/` (the hero's generator), `docs/research/prior-art.md`
(README hero survey — the class analysis and the cheap-vs-crafted tell), `scripts/render-diagrams.mjs`.

---

## Track B — why is self-recycle not proactive at idle?

**Objective.** Root-cause why no recycle advisory fired in session `a64e4989` as it climbed to **71%**
across a long session, and make the proactive path actually act. The operator's framing: it should
trigger when the agent has returned / finished its prompt and is idle waiting on the user — i.e. at
the **Stop hook**.

**The live symptom is this session.** It ran to 71% over many turns, went idle at the prompt repeatedly,
and never self-recycled. Per CLAUDE.md § Context Stewardship an idle session at ≥~35% is a "free win"
that should `/handoff` immediately. It did not.

**Named suspects — verify each against disk, do not assume.**
- `hooks/waiting-recycle.sh` — the desk's tiered free-win / forced-drain firer. **Is it desk-role-gated?**
  Memory `liveness-free-channel-never-gated-behind-liveness` records a banner that lived inside a
  desk-role arm and so was disabled by removing stale roles. If this only ever fires for the desk, a
  normal operator session can never self-recycle.
- `hooks/boundary-handoff.sh` — committed+green Stop advisory. Does it fire, and is it *inert*?
  CLAUDE.md asserts an advisory `additionalContext` Stop hook is INERT; if the nudge rides that channel
  it reaches nobody.
- **Fill measurement.** Fill is `input_tokens / window` and the **window** lives only in ephemeral
  `/tmp/cc-telemetry/<sid>.json`, wiped on reboot. If the denominator is missing the tier cannot be
  computed, and the failure direction matters: does it fail silent-open (never fires) or loud?
- `session-continue.sh` — it *does* block at Stop mechanically for uncommitted work, proving the Stop
  channel can act. Why does the recycle path not use the same actuator?

**Deliverable.** A root-cause with file:line evidence, a one-line statement of which of the four
suspects is the binding one, and either the fix or a named blocker. Report to
`docs/research/idle-recycle-not-proactive-2026-08-08.md`.

**Do NOT** widen this into a redesign of the context-economy policy — the policy is settled
(`docs/plans/CONTEXT_ECONOMY_V2.md`); this is about why its actuator is silent.

---

## Status log

- **2026-08-08** — plan created at 71% context by `a64e4989`; both tracks unstarted. Successor fires
  the wave. Related landed work this session: `7bb7526e` (research note), `14711d73` (its correction),
  `6c4c86d7` / `7691cd44` / `1be299a7` (README section + two diagram iterations).

- **2026-08-08 — Track B COMPLETE.** Report: `docs/research/idle-recycle-not-proactive-2026-08-08.md`.
  **Binding suspect = 1 (`hooks/waiting-recycle.sh`), and it is desk-role-gated as suspected — but the
  proximate gate was a different one.** Session `a64e4989` abstained `disarmed` on 85 of 88 evaluations
  (`waiting-recycle.sh:530`): a durable, never-expiring `clear` marker written `2026-07-31T17:58:44Z`,
  keyed on **(CLAUDE_CONFIG_DIR, cwd)** — so the same directory is ARM+LIVE under `~/.claude`,
  `-tertiary` and `-quaternary` but DISARMED under `-next` and `-secondary`, and the session drew a
  disarmed slot purely from account routing. Two further gates sit behind it: arm-by-default is dead
  (`cc-roles/desk` no longer exists — only `orchestrator` — and `DESK_ROLE` defaults to `desk` at
  `:205`; the `liveness-free-channel-never-gated-behind-liveness` pattern recurring, with
  `autonomy-sweep.sh:253` documenting the removal), and the hook is registered on **`PostToolUse:Bash`
  only, never `Stop`,** in all five config dirs. Reproduced live by running the deployed hook with a
  realistic payload across four (account, cwd) pairs.
  - **Suspect 2 REFUTED** — `boundary-handoff.sh:394` emits `{decision:"block"}`, not the inert
    `additionalContext` channel; it evaluated 21× for this session and abstained *correctly* every
    time (`below-threshold:NN<73`, peak 70 vs `T=73` at `:88`). It is the wrong TIER, not inert.
  - **Suspect 3 NOT CAUSAL** — telemetry was complete throughout (`window:1000000`, 27-row `.hist`).
    Direction on a genuine miss is silent-open (`:180`,`:187` abstain), which is a real post-reboot
    hole, named not fixed.
  - **Suspect 4** — the Stop actuator is proven live in this very session (IDL `session-continue
    armed/fired/cleared`), and `boundary-handoff` already uses it. Plainly: **nobody wired it.**
  - **Fix landed** (`scripts/idl-abstain-alarm.sh`): the monitor built to catch an inert hook counted
    non-evaluation `gc` housekeeping rows in its denominator, so 4 such rows made waiting-recycle read
    `HEALTHY` at 2,864 abstains / **0 fires in 14 days**. `total` now counts evaluations only. Selftest
    cases M/N provably RED before, green after; 29/29 selftest, 11/11 bats, shellcheck clean; live
    verdict is now `DORMANT-100`, exit 0 (surfaced, not paged). `tests/idl-abstain-alarm.bats:25`
    exact `-eq 25` count converted to floor+tally (it red on the suite's own growth).
  - **Named blocker (specified, NOT built)** — the ≥35% idle free-win tier has **no Stop-side
    carrier**: `waiting-recycle` owns the tier but runs mid-turn on `PostToolUse:Bash`;
    `boundary-handoff` owns Stop but starts at 73%. Between 35% and 73% an idle session at a clean
    committed boundary is seen by nothing. Proposed: a damped, env-gated `CC_BOUNDARY_T_IDLE` second
    threshold in `boundary-handoff.sh`, reusing its existing clean-tree/gate-green/no-teammates gates
    and the S6 conversation-hold suppression. Not built here because it changes Stop behaviour
    fleet-wide — larger than a safe in-actuator fix. Full spec + two secondary items in the report.
