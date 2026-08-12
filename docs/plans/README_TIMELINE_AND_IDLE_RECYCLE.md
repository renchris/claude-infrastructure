---
status: complete
---

# README timeline banner + proactive idle-recycle — 2-track plan

> **COMPLETE 2026-08-11.** Track A landed `1f31117f`; Track B landed its report + the
> `idl-abstain-alarm` fix, and its one named blocker — a Stop-side carrier for the ≥35% idle
> free-win tier — is closed by `ab6d3d1e` (the arm), `57d8c4dd` (what made it reachable) and
> `3f6f1ade` (what made it fire under its own name). The three `waiting-recycle.sh` secondary items
> in the Track B report stay open as their own work; they are not this plan's scope. Full account in
> the Status log at the end.

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
  CLAUDE.md asserts an advisory `additionalContext` Stop hook is INERT; if the nudge rides that channel **[STALE as of 2026-08-08 — measured on 2.1.220, Stop `additionalContext` DOES reach the model; it forces a turn like `decision:block`, so every conclusion below still stands. See docs/research/final-response-shaping-2026-08-08.md]**
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

- **2026-08-08 — Track A DONE** (`1f31117f`). Mermaid is out of the shipped slot;
  `assets/diagrams/convergence-timeline-{dark,light}.svg` are hand-built by `tools/timeline/gen.py`
  (`npm run timeline` / `timeline:check`). The `.mmd` source and its `<details>` fence stay as the
  interactive fallback and `npm run diagrams:check` is still green — the renderer only ever walks
  `*.mmd`-derived outputs, so a hand-authored sibling in that directory is invisible to it.

  **The design decision, so a successor does not re-litigate it.** A chain — mermaid's only shape —
  can say "then, then, then" and nothing else, which throws away the section's actual claim. The
  replacement is **two lanes on one time axis**, so the distance between a repo marker and its
  Claude Code twin *is* the lead: 26 px for 4 days, 179 px for 28, and 845 px for the 7 months we
  owe. Three consequences worth keeping:
  - **The axis break is at 2026-03-24, this repo's first commit.** A linear axis over 529 days puts
    four events inside 152 px and cannot be labelled at all. Breaking there makes the compression
    *be* the 13-month head start rather than a concession to it; the month gridlines are drawn at
    both scales (27 px/month left, 194 right) and their density change is the disclosure. A ghost
    lane marks the months this repo did not exist.
  - **Direction encodes ownership.** Leads run downward, repo → Claude Code. The one gap that is
    ours runs upward, in orange, across the break.
  - **Two files, each carrying BOTH palettes**, differing only in the default. `<picture>` picks
    one, but an SVG in `<img>` also resolves `prefers-color-scheme` itself, and a single baked
    palette is wrong in exactly the case where those two mechanisms disagree.

  **Verification.** `banner-verify` 6/6 on both files (well-formed · one-animation-per-element ·
  t=0 == t=24 seam · 12/12 distinct frames · dark != light · reduced-motion still), plus screenshots
  at the measured 838 px column on both GitHub backgrounds. **Constraint 5 earned its place twice** —
  two defects passed every mechanical gate and only the render showed them: `phase_for()` ignored
  both the ignite-peak offset and the delay sign, so every marker lit ~11 s away from the light
  column it was supposed to be following; and the axis-break masking band rendered as a bright white
  stripe on GitHub light while masking nothing (no month boundary falls inside those 70 px).

  Incidental: `scripts/render-diagrams.mjs` claimed `assets/diagrams/handoff-choreography.svg` was
  the hand-authored exception. That file has never existed in this tree — the comment now names the
  real one.

- **2026-08-11 — Track B's named blocker CLOSED; the plan is DONE** (`3f6f1ade`). The ≥35% idle
  free-win tier has a Stop-side carrier and it now fires under its own name.

  **The blocker was already closed when it was named.** `hooks/boundary-handoff.sh` shipped the
  ✅-ledger free-win arm (`T_FREEWIN`, default 35) on **2026-08-03** in `ab6d3d1e` — five days before
  the Track B report said the tier had "no Stop-side implementation at all". The report was not
  careless: **the arm had never fired once**, because the `gate-not-green-at-head` abstain sat
  upstream of it and only the background `postland-verify` daemon can advance that marker (1,341
  evaluations across 296 sessions, zero fires). `57d8c4dd` demoted gate-green to a reported field
  here and in `wrap-ledger.sh`, which is what made the arm reachable. **Keep this, because it is the
  transferable part: an inert mechanism is indistinguishable from an absent one.** Two sessions in a
  row read this hook's source and concluded the tier did not exist.

  **What this session found and fixed.** A positive control — the deployed hook, a synthetic
  telemetry payload at 41%, a clean ✅ worktree — fired, but *as the forecast tier*: the arm set the
  shared `early` flag, so the advisory read `context 41% BURNING toward the 88% auto-compact wall —
  forecast ≤-1min at the observed rate` and the IDL row said `axis:"forecast"`. `-1` is the sentinel
  for UNKNOWN: the advisory quoted a burn rate it had explicitly failed to measure. Three fixes,
  matching the report's spec items 2 and 3:
  - **Its own axis.** `freewin` flag, `axis:"freewin"`, and the free-win wording (`⟳ FREE WIN … 
    handoff-fire.sh --recycle`) instead of the forced-drain "before auto-compaction".
  - **S6 conversation-hold SUPPRESSES here**, rather than appending "do NOT cut it" to a recycle
    advisory — advice that retracts itself. It also protects the latch: a fire mid-exchange stamps
    it and silences the next +10% of fill, costing the genuinely-idle boundary that follows. The
    ≥73% tier still fires mid-exchange with wording only, unchanged.
  - **The silence is attributable.** The sub-`T` abstain carries `FREEWIN_RUNG`, so "the ledger said
    no" is no longer byte-identical to "the arm never ran" — 383 live evaluations sat at used ≥ 35
    recording only the 73 they were never going to meet.

  **Why the suite missed it:** the shipped free-win test asserted that the arm FIRES and never read
  what it SAID. 8 new assertions, each provably RED against the pre-fix hook; 2 more are
  counter-direction anchors (the forecast tier keeps its own axis; the ≥73 tier still fires
  mid-exchange) that pass both ways by design. 35/35 bats, shellcheck -x clean.

  **Still open, and deliberately not taken here** — the report's three secondary items, all about
  `waiting-recycle.sh` rather than this carrier: arm state is partitioned per account while the
  router picks the account; `disarm` has no TTL and no visibility; `cc-roles/desk` is absent, leaving
  two mechanisms keyed on a deleted file. Each is a migration with its own blast radius.

- **2026-08-12 — Track A, v2: the banner rebuilt ground-up, and one of its facts was wrong.**
  Operator verdict on the landed v1 (`822592338`): *"very unclear, disorganized, AI slop"*, plus a
  ruling that the asset exists to state what ran here FIRST — so the orange "7 months late — our
  gap, not theirs" arm does not belong on it whatever its sign. v2 is two full-width tracks on one
  linear May–August axis, one per capability: green disc where it was running here, blue ring at the
  Claude Code release, the span between them to scale with the lead in a pill on it. Dropping the
  self-diminishing content is what removed the axis break — 529 days became 106, so the single
  linear axis fits and the 4-day lead is a 48 px bar instead of v1's 26 px smudge. Design argument,
  in full, in the `tools/timeline/gen.py` docstring; v1's four legs are preserved there with the
  reason each was kept or dropped.

  **The fact that did not survive, recorded because it cost the session an hour and a rebuild.** The
  operator's framing was that the status-line context row is a POSITIVE — the need identified here
  before the field existed, then adopted immediately — and a three-track v2 was built on it. It is
  refuted by primary sources: `context_window.{used_percentage,remaining_percentage}` shipped in
  `2.1.6`, npm **2026-01-13**, which is THREE DAYS BEFORE the 2026-01-16 comment on Claude Code
  issue #12520; the fields that comment actually proposes (`conversation_output_tokens`,
  `effective_remaining_percentage`) have NEVER shipped and #12520 is still open; and
  `context_window_size` appears in no CHANGELOG entry at all — "CC >=2.1.207" in `1b8d671b1` is an
  observation about a payload that got read as a release note. So the row is a LAG, exactly as
  `docs/research/vendor-convergence-2026-08-07.md` §1 already measured, and it is off the chart on
  SCOPE, not because omitting it flatters us. **Two wrong intermediate readings were tried first,
  both from dating the vendor's side off this repo's own prose** — a `statusline.sh` header comment,
  then a commit message. Date both sides from a primary source or do not draw the row.

- **2026-08-12 — Track A, v3: the craft pass, after v2 traded slop for inertness.** Operator verdict
  on v2: *"REGRESSED … just as unreadable with the large varying texts and LESS visualization and
  beautiful complexion."* Correct on all three counts, and they are separable defects:
  **TYPE** — v2 carried EIGHT sizes between 16 and 26 px, which at the 0.599 README scale all land
  inside 9.6–15.6 px: eight sizes, no hierarchy. v3 has THREE (36/24/18 → 21.6/14.4/10.8), 1.5×
  apart, everything mono except the two capability names — which is the hero's own type system.
  **VISUALIZATION** — v2 was four dots, two 3.5 px hairlines and two pills on a 1400×524 plate;
  measured as ink it was prose with rules under it. v3 gives the leads MASS (a 26 px band with a
  green ramp, capped by its markers) and adds a real second data layer: this repo's own commit
  volume as an amber stepped ridge on the same axis, 7-day trailing, sqrt-scaled. It is not filler —
  both "here first" moments land BEFORE the climb (2026-05-24 on the flat of the zero-commit May
  this plan's own README section calls "the plateau between two"; 2026-07-10 on the first rise),
  which is the section's thesis drawn to scale.
  **COMPLEXION** — v2's plate was a near-flat two-stop wash. v3 is built the way `prior-art.md`
  §B1/§B2/§B8 says the hero is: depth from colour bands before any shape, a four-stop dusk ramp
  warming to the horizon, light scatter above it, and ONE warm source (amber, the repo's badge gold)
  against a cool surround. Three hues, one job each — green a capability running here, blue the
  Claude Code release, amber this repo's own work over time.

  **The measurement that made this diagnosable, and the process lesson.** The gap was not a matter
  of taste: the hero `assets/banner/v6c-dusk-line.svg` is the stated standard for this asset (this
  plan, Track A objective) and it was never once opened while v1 and v2 were designed. Rendering it
  and reading `prior-art.md` took one tool call each and produced the whole v3 brief. **Read the
  house standard before designing against it** — two rejected iterations is what skipping it costs.

  **Also fixed, all one root cause:** v3 sets the asset in mono while every width estimate still
  used SANS metrics (0.505 vs 0.600/char, a 19% under-estimate), so the overflow guard could not
  fire — the legend's two entries overlapped and a date block ran 26 px past the right margin. The
  4-day band was additionally 100% hidden under its own two r=13 end caps. Both are now asserted
  against the canvas edge rather than a guessed budget.

- **2026-08-12 — Track A, v4: v1's structure restored on a closed design system.** Operator: *"I
  like the structure of v1 but just make it better with more concise design system and consistent
  fonts."* So the two lanes come back — this repo above, Claude Code below, a drop from each
  capability to the release that shipped it — and v1's *execution* is what gets replaced. **v1's
  structure was never the defect**, which is worth stating plainly because three iterations were
  spent finding that out: v2 and v3 both dissolved the lanes into isolated per-capability rows, and
  the two-parties claim went from structural to inferred. Two lanes make it in the geometry.

  **The design system, as an enforceable budget rather than an adjective.**
  *Elements — SIX types, and nothing may be added without deleting one:* LANE ×2 · MARKER ×4 ·
  DROP ×2 · CHIP ×2 · STACK ×4 · GROUND ×1. v1 carried thirteen (two lane styles, ghost rule, halo,
  ring, dot, specular, chip, leader, stem, axis-cut, bloom, head-start note). The fixed inventory is
  the point: the next edit has to argue against the budget instead of quietly appending to it.
  *Type — ONE family, THREE sizes.* Everything is mono, so "consistent fonts" is enforced by there
  being only one; 34/22/17 render 20.4/13.2/10.2 at the 838 px column, ~1.5× apart at each step. L
  is chip numerals only, M is the four names, S is everything else. v1 had eight sizes between 16
  and 26 px — all landing inside 9.6–15.6 px after the downscale — plus sans and mono mixed with no
  rule about which meant what. Eight sizes four points apart are not a hierarchy.
  *Colour — THREE hues, one job each:* green this repo · blue Claude Code · amber this repo's own
  work over time. v1's fourth hue, orange, existed solely to carry the lag and went with it.

  **Two rules make the layout collision-free by construction rather than by tuning.** Each lane's
  STACKs sit on its OUTBOARD side (repo above its lane, Claude Code below its), so the inner band
  belongs entirely to the drops and chips and the two label sets can never contend — v1's four
  alternating label rows joined by leader lines were the whole readability failure. And the chip
  rides its drop's midpoint *by construction*: with control points at `DROP_MID` the cubic's t=0.5
  is exactly `((ox+tx)/2, DROP_MID)`, so no chip position is ever hand-tuned against a curve.

  Kept from the discarded middle versions because each was earned: the commit ridge and the dusk
  material (v3), ours-above/theirs-below (v2), and the single unbroken axis (v2) — the axis break
  existed only to reach content that has since been cut, so it went with it.
