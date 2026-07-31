# Pyramid worklog — README §6 (the next ceiling)

## Session 0 — Intake, classification, routing

**Mode: C** (Communication). The message is already established by measurement
(`docs/research/l3-l4-terminal-and-workflow-2026-07-31.md`, landed `be8780a0` / `288974d9` /
`67112b01`); the job is to render it rigorously into the root `README.md`. Route: 3 → 4 → 5 → 6 → 7
→ 8 → 9 → 10.

**Bounded input body** — the two *governing* documents only, not the research corpus that produced
them:

| file | words | ≈ tokens |
|---|---|---|
| `README.md` (voice, structure, the 5 existing properties) | 5,658 | ~7,921 |
| `docs/research/l3-l4-terminal-and-workflow-2026-07-31.md` (the message) | 3,114 | ~4,359 |
| **total** | **8,772** | **~12,280** |

**Tier A** (≤30K tokens) ⇒ run inline, no subagents at either boundary.

**Reader.** Two at once: engineers reading the repo cold (wide circulation), and the operator, who
needs the state and the roadmap. **Medium:** short message + many readers ⇒ dot-dash / tabular
section in the existing README idiom, not prose.

**What the reader should KNOW after reading:** the system's current ceiling is the *interface* —
displaying 30 sessions — not the machine, not memory, and not agent count; and the route to Boris
Cherny's Step 3→4 is to stop rendering what is not being read.

**Correction carried deliberately.** The commissioning framing named "memory pressure". The
measurements refute that three separate ways, so the section says what is true and names the
refutation explicitly — a README that repeated the intuitive diagnosis would be wrong on its
load-bearing claim.

---

## Session 3 — Build the pyramid

**S-C-Q introduction** (Ch 4 — reminds, never informs; every element is something the reader already
accepts):

- **Situation.** This repo already makes ~30 Claude Code sessions open, message and retire one
  another unattended — properties 1–5 above.
- **Complication.** At that concurrency the machine lags, freezes, and has hard-crashed twice; and
  every pane must stay visible, because a blocked permission prompt is found by eye.
- **Question.** What is actually the ceiling, and what removes it?

**Governing thought.** *The ceiling is the interface, not the machine* — running 30 sessions is not
what lags this box; **displaying** them is.

**Key line** — deductive (Ch 5), because the conclusion is alien to expectation and must be *argued*
before it is acted on:

1. **The machine is not the constraint.** (major premise)
2. **The interface is.** (minor premise — it comments on the subject of 1)
3. **Therefore: stop rendering what you do not read.** (the therefore)

Each key-line point is supported inductively by same-kind measurements:

| Key line | Support (all measured on this box) |
|---|---|
| 1. machine not the constraint | 31 live sessions ⇒ 93% memory free, `Pageouts: 0` · each session ~215 MB · whole fleet ≈ 0.75 cores · both panics were non-memory (compressor **segments** with 20 GB free; a spinlock from a probe's 8,368 threads) |
| 2. the interface is | iTerm2 122.1% + WindowServer 49.0% ≈ **1.7 cores = 2.3× the fleet** · **+76 mach ports/hr at frozen layout** while RSS *falls* · perf-parity `match=9 drift=0` yet still 1.2 cores at half load ⇒ tuning exhausted · windows cost **2.35×** panes |
| 3. stop rendering what you don't read | kitty holds 48 panes in 1 window at 10 threads · the permission beacon already exists and is unrendered · 88.3% of prompting calls are compound ⇒ allow-lists cap ~2.4% |

**Rule check.** Same kind (each is a claim about where cost lives) · summarizing idea above each
grouping · logical order = deductive. ≤4 per grouping. No category headings, no blank assertions.

**Exit checklist:** ✅ governing thought states a judgment, not a topic ✅ key line is one logic type
(deductive), not mixed ✅ every support is a citation to a measurement, not an opinion ✅ 30-second
test: intro + governing thought + 3 key-line points readable in 30 s.

---

## Sessions 4–8 — Introductions, logic, order, summaries, gate

- **S4 (intro).** The S-C-Q above uses only facts the reader already holds (the repo runs many
  sessions; it lags). No exhibit in the introduction. Action deferred to the roadmap because the
  message contradicts expectation (Ch 5 pp. 65–66 licenses argument-first here).
- **S5 (horizontal logic).** Deductive at the key line; inductive within each support set. Never
  both in one grouping — checked.
- **S6 (order).** Key line is deductive order (premise → premise → therefore). The roadmap grouping
  is **time order** (now / next / then). The candidate table is **degree order** (ranked by the
  discriminator, threads-per-pane).
- **S7 (summaries).** No "there are three findings"-class assertions. Each heading carries the
  judgment: "The machine is not the constraint", not "Findings".
- **S8 (pre-writing gate).** PASS — 30-second test met; every number traceable to the landed
  research doc; the one framing correction is stated rather than smoothed over.

---

## Session 9 — Draft

Rendered as README §6 in the existing idiom: bold lead sentence, a property table, measured tables,
and a time-ordered roadmap. Written into `README.md` after §5, before `Install`.

## Session 10 — Post-output critique

Round 1 defects found and fixed in place:
- "memory pressure" survived in one transition sentence ⇒ removed (owning session: 3).
- Roadmap item "migrate to kitty" was an action without its cost ⇒ added the 22-file / 3-primitive
  / 175-line chokepoint figure so the reader can size it.
- Candidate table originally ranked by memory ⇒ re-ordered by the actual discriminator
  (threads-per-pane), per S6 degree order.

Residual risk logged, not looped (rule 4): Ghostty's row is from source reading plus a live
thread count, not a pane-scaled run — labelled as such in the table rather than presented as
measured parity.
