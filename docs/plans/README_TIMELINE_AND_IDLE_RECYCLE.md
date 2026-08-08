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
