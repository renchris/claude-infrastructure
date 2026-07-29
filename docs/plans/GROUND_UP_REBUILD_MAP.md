---
status: open
---

# GROUND-UP REBUILD MAP — MECE decomposition of claude-infrastructure

**Scope (frozen):** maintain the MECE subsystem map of claude-infrastructure and track each
subsystem's from-first-principles rebuild (methodology: the `ground-up` skill; exemplar:
docs/plans/LAND_PIPELINE_V2.md). One subsystem per session; ≤2 rebuilds in flight fleet-wide.

**MECE basis:** partition by *operational responsibility* (who answers when it breaks), not by
file layout. Seams between subsystems are named per-row — a seam is an interface contract two
rebuilds must not both redesign; the row that owns it is marked.

| # | Subsystem (owns) | Core surfaces | Seams (owner) | Standing constraint to design against | Status |
|---|---|---|---|---|---|
| 1 | **Landing & deploy pipeline** — commit→trunk→live | ship-land, land-lock, postland-verify, deploy-live, host-suites.manifest, cc-blockers alarms | verifier stamps (1); deploy ff (1) | no quiet period; 12+ writers 24/7 | **DONE 2026-07-28** — LAND_PIPELINE_V2.md; 9 lands; exemplar |
| 2 | **Session lifecycle & succession** — open/recycle/close | handoff-fire, /handoff, self-close, engagement verification, warm worktree claim | mailbox delivery (3); registry truth (4) | a watched pane must never vanish illegibly | open |
| 3 | **Cross-session comms** — messages between peers | cc-notify, mailbox+ack cursor, .forward chains, cc-await-ping, mailbox-drain | wake path (2); desk inbox (5) | ~~delivery must survive recycles; exactly-once ack~~ **cell CONFIRMED-BUT-RENAMED — exactly-once ack was already built and sound (split `.seen`/`.acked` under mkdir lock); the binding constraint is at-least-once delivery to a LIVE READER, and the root cause is ADDRESSING (inbox keyed on pane, not session)** | **REBUILDING 2026-07-29** — [CROSS_SESSION_COMMS_V2.md](CROSS_SESSION_COMMS_V2.md) (410 ln, four load-bearing sections); design 5dd65159 · build landing continuously (99164d48 · fea9f7a8 · 2db449d0 · 9075b347 · 0688dc5e · 66a43076 · a8b3a093 "address the session, PULL from a dead predecessor"), branch 0 ahead of trunk. Row **2 is BLOCKED on this row** (strict 4→3→2) |
| 4 | **Session registry & reaping** — who is alive, who gets closed | session-register, cc-reconcile, cc-reaper, cc-teardown, liveness oracles (cwd/lsof) | teardown of (2)'s panes | never reap a live operator conversation | **DONE 2026-07-29** — SESSION_REGISTRY_V2.md; landed 7db74a76 (c834b705 design · acddb319 beat+lease · 5816968a fail-closed belts · +hermeticity fix); activation 16-session-beat staged — ⚠ **ORACLE INERT UNTIL ACTIVATED: consume it FAIL-SOFT, never assume it produces** (verified 2026-07-29: `~/.claude/cc-beats` absent, `session-beat.sh` in no live settings.json, activation has no `.done`) |
| 5 | **Autonomy dispatch & discovery** — what gets worked on | cc-dispatch, cc-backlog, cc-discover, cc-wave-plan, desk loop, launchd dispatcher/discovery | fires via (2); reads (10); consumes (7) | ~~backlog > concurrency is normal, not a cliff~~ **cell falsified — real cause was no fleet concurrency ceiling** | **DONE 2026-07-29** — [AUTONOMY_DISPATCH_V2.md](AUTONOMY_DISPATCH_V2.md); 11 lands: design 7400c614 · map bf796c57 · acceptance reader 0a8a2976+361675e8+5257d457 · activation ruling c87ca381 · seam rulings e0356664 · ceiling correction 15cc1f4f · **build: cadence 21d8e869 · verdict 6c73429f · decide f16c37ee**. Live metric ACCRUING — **C10 activation DONE 2026-07-29 (dispatcher + discovery both flipped enabled; verified by row 12's Phase-1 re-derive and by the coordinator via `launchctl print-disabled`), so the ≤5-min metric is now MEASURABLE rather than 0-by-construction. Still awaiting DEPLOY** (checkout 33 behind trunk — `cc-backlog 4e0038a19faf`) |
| 6 | **Guardrail/hook layer** — what a session may do | 69 hook entries / 12 events, validate-bash, permission rails, Stop asserts, OVERWRITE guard | every subsystem's enforcement chokepoints | a hook failure must never block a tool by accident | open |
| 7 | **Account/quota routing & relogin** — which account works | claude-accounts, cc-relogin*, limit-recover, model-config.yaml SSOT, launchers | fire-time ranking (2) | login cliffs are hard walls; 4 isolated accounts | open |
| 8 | **Context economy** — when a session recycles | waiting-recycle, boundary-handoff, dod-persist, /wrap, session-continue | recycle executes via (2) | rot degrades decisions before the wall breaks them | open |
| 9 | **Memory & knowledge** — what survives sessions | MEMORY.md + topic files, skills/, plans + find-plan, session index/search | consumed by every session start | anti-capture hygiene; index at read-size limit | open (compaction backlogged b0d889846885) |
| 10 | **Observability & operator surface** — what the human sees | cc-blockers board, operator-readout, pages+damping, statusline, activation queue | renders facts owned by 1,4,5,7 | absence-is-loud WITH existence evidence; silver-platter commands | open |
| 11 | **Worktree & warm-pool management** — where writers work | worktree-gc, warm pool build, new-worktree, .worktreeinclude | claimed by (2); landed by (1) | 107 GB observed drift; ownership per artifact-class | open |
| 12 | **Daemon fleet & activation** — what runs unattended | **14** launchd jobs, plist SSOT parity, pending-activation queue, C10 boundary | carries 1,4,5,7,8 | disabled-bit trap **(CONFIRMED but INSUFFICIENT — 1 of 3 silent states; see below)**; agent stages / operator activates | **IN PROGRESS 2026-07-29** — [DAEMON_FLEET_V2.md](DAEMON_FLEET_V2.md); design landed 59f7eb38 |

**Why this cut is MECE:** every script/hook in the repo answers to exactly one row's
responsibility; overlaps are declared as seams with a single owner. Row 1's rebuild validated
the method AND the seams model (its rebuild consumed seams from 6, 10, 12 without redesigning
them).

## Unowned-surface rulings (coordinator-decided; binding — do not re-litigate)

The table's "core surfaces" are exemplary, not exhaustive. When a rebuild finds a surface named
in NO row, it pings the coordinator rather than claiming it silently; rulings land here so the
next row inherits the answer. **The deciding test is the MECE basis itself — who answers when
it breaks — not who calls it or who wrote it.** Rule by EXECUTABLE call sites, never by a
comment that asserts ownership (a comment is text, not evidence) and never with an extension
filter on the grep: this repo's `bin/` is extensionless, so `--include='*.sh'` silently hides
the very consumers that decide the question.

| Surface | Owner | Evidence for the ruling |
|---|---|---|
| `bin/cc-wave-plan` | **5** | Sole executable consumer is `bin/cc-dispatch:200`; `bin/cc-backlog`'s references (`:464`, `:535-536`) are comments describing the `wt-<id>` convention, not calls. A mis-sized wave or a false ⛔ cliff is a dispatch failure — row 5's standing constraint verbatim. It CONSUMES row 7 (`claude-accounts --rank/--json`, `cc-route --json`) without owning it. Ruled 2026-07-29 on row 5's ping. |
| `bin/cc-route` | **7** | KEY-ANCHOR parses `~/.claude/model-config.yaml` (row 7's named SSOT surface) and `claude-accounts --route`. Its exit-code contract (0 plan · 2 usage · 3 blind/no-data · 4 cliff) is pinned by `scripts/route-safety-gate.sh:33-50` and `tests/cc-route.bats` — no other row may alter it. Ruled 2026-07-29, pre-emptively, because row 5's cc-wave-plan work sits directly on top of it. |

**A test can encode a falsified premise — changing it is legitimate, hiding it is not.**
`tests/cc-wave-plan.bats:135` asserts "wave exceeds total concurrency → exit 4 cliff", i.e. the
very belief row 5 disproved. A rebuild may change such a test, but only as a deliberate
RED-proofed change with the reason recorded in its plan — never as a quietly relaxed assertion.
Its neighbour `:141` (a cc-route-propagated quota cliff) is a GENUINE cliff and must stay
distinguishable: telling a real capped-account stop apart from a wave-sizing false cliff is the
whole point of the split.

**Dispatch order recommendation (pain-first, dependency-aware):** 4 → 3 → 2 (the
liveness/comms/succession triangle shares seams — sequence, never parallel) · then 5 · 12 ·
10 · 8 · 7 · 11 · 9 · 6 last (it is every other row's enforcement surface — rebuild it after
its customers stabilize their contracts).

## What DONE means on this map (coordinator ruling 2026-07-29 — binding)

**DONE = designed + landed + adversarially proven + activation STAGED AND PLATTERED. It does
NOT mean live.** Row 4 shipped an oracle that is provably inert right now — no `~/.claude/cc-beats`,
not in any live `settings.json`, activation `.done` absent — and it is still correctly DONE,
because launchctl activation and deploy are classifier-blocked for agents (the C10 boundary) and
row 4 did the whole agent-side job: it landed, it staged `16-session-beat-activate.sh` in both the
live queue and the repo SSOT, and it named the exact operator command. The ground-up skill's
Phase 5 asks for precisely this and no more.

**Therefore, if you CONSUME another row's mechanism, consume it FAIL-SOFT.** Assume it may be
landed-but-inert and degrade cleanly; never make your design's correctness depend on a mechanism
being activated. Row 3 modelled this exactly right — it detected row 4's inert oracle during its
own Phase 1 and consumed it through a `cb_system_live()` probe rather than depending on it. Do the
same, and say in your plan what your design does when the dependency is dark.

**And check, don't trust the word DONE.** Row 3 found this only because it probed for existence
evidence instead of reading a status cell. A row that trusted "DONE" would have designed against a
phantom. Status is a claim like any other (see the constraint-cell learning below).

## Learnings (accumulate; never delete)

- 2026-07-29 **TWO LEADS IN ONE WORKTREE IS AN OVERWRITE HAZARD, NOT JUST WASTED TOKENS — and a
  tool guard, not a coordinator ruling, is what caught it.** A coordinator misjudgement (treating a
  transient 529 stall as a death and re-firing) put two row-12 leads in the same worktree. The
  duplicate's `Write` of `docs/plans/DAEMON_FLEET_V2.md` was refused by the read-before-write
  guard — **the only thing standing between it and clobbering 581 landed lines of the survivor's
  design.** The stand-down ruling was in its inbox at the time and had not yet drained, so the
  ruling would NOT have saved the file. Two consequences worth carrying: never re-fire into an
  existing worktree on silence alone (require positive death evidence — pid gone, pane gone,
  registry row gone), and treat the OVERWRITE GUARD as load-bearing infrastructure rather than
  ceremony. Full incident: `docs/plans/GROUND_UP_DISPATCH.md`, commits `f8a98f71`, `8ed8615f`.

- 2026-07-29: map created from the landing-rebuild exemplar; row 1 marked DONE. The
  methodology's distillation (what the prompt did/missed) lives in skills/ground-up/SKILL.md.
- 2026-07-29 **THIS TABLE'S "standing constraint" CELLS ARE CLAIMS, NOT VERIFIED FACTS —
  re-derive YOUR row's cell from primary disk truth before you design against it.** Surfaced
  by row 5 mid-rebuild and independently confirmed by the coordinator: row 5's cell rested on
  "the backlog>concurrency false cliff was fixed by `bef587a`", but `bef587a` landed
  **2026-07-18** while the 12 cliffs it supposedly prevents occurred **2026-07-26** — eight
  days later. The real cause was different in kind (no fleet concurrency ceiling anywhere in
  cc-dispatch: 50 sessions fired in 17.5h, quota exhausted, then it paged about its own wall).
  A rebuild that inherits a falsified cell designs against the wrong failure class and its
  "inversion" is just the old design with bigger constants — the exact Phase-2 trap the skill
  warns about. Treat the cell as the PRIOR SESSION'S HYPOTHESIS; Phase 1 is where you kill or
  confirm it, and say in your plan which one happened.
- 2026-07-29 **CHECK DAEMON-ACTIVATION TRUTH BEFORE MEASURING YOUR ROW'S METRIC — a disabled
  job makes a metric read 0% BY CONSTRUCTION, which is not a performance result.**
  ⚠ **THE COUNT IN THIS ENTRY IS SUPERSEDED — live truth is 10 disabled / 4 enabled (re-read
  2026-07-29T15:00Z; see the "COORDINATOR'S OWN COUNT WAS STALE" entry below). The LESSON is
  what stands; the number is a snapshot and re-derive is mandatory.** Verified
  at the time via `launchctl print-disabled gui/$(id -u)`: **12 of the 14 `com.claude.*` jobs
  are disabled**; only `com.claude.postland-verify` and `com.claude.deploy-live` are enabled,
  and `launchctl list` shows those two alone loaded. `com.claude.dispatcher` and
  `com.claude.discovery` are BOTH disabled, so row 5's "dispatch decision ≤5 min" was
  unmeetable before a line of code was read. Corroborated independently by `cc-backlog`
  107f27fbb00c and memory `desk-autonomy-dormancy-staged-not-loaded` (built but INERT: staged
  in pending-activation/, never loaded). ~~Whether the mass-disable was deliberate is still an
  OPEN operator question — do not assume either way.~~ **ANSWERED WITH EVIDENCE by row 12, and
  `cc-backlog 107f27fbb00c` is closed on it: the mass-disable was a DELIBERATE operator-directed
  fleet shutdown on 2026-07-26 11:46-11:56 PDT.** The weapon was recovered verbatim —
  `/tmp/claude-fleet-shutdown.sh`, running bootout+disable+unload -w over exactly 13 labels,
  set-identical to the 13 `true` entries in the override db. Motive: 4 of those jobs CREATE
  sessions on a timer (dispatcher, discovery, desk-invariant, boot-resume) and pane-closing
  would not converge at 31 live processes / load 17; the 07-27 reboot was the AMPLIFIER (latent
  bits → 0 loaded), not the cause. **Consequence binding on every row that touches the fleet:
  `desk-invariant` and `boot-resume` are the runaway GENERATORS — never re-enable them without
  a fleet concurrency ceiling, or the incident reopens. The other 8 were collateral and are
  safe.** Row 12 owns this trap; every other row
  must still run the check first, because a row that measures an inert subsystem will report a
  performance problem it does not have.
- 2026-07-29 (row 4, DONE) **ACTIVATION-TRUTH CHECK RUN AND PASSED — the trap above did not apply
  here, and the check is cheap enough that every row should state its result rather than its
  assumption.** `com.chrisren.cc-reaper` (note the `com.chrisren.*` prefix — the disabled-mass the
  learning above measured is `com.claude.*`, a DIFFERENT label family; a row that greps only
  `com.claude` will wrongly conclude its own daemon is inert) is loaded, and the log's newest sweep
  was 4.2 min old with 893 lines the same day, in `mode=REAP`. So row 4's constants are performance
  facts, not artifacts of a dead job.
- 2026-07-29 (row 4) **WHEN THE LAST GATE OVERTURNS THE MAJORITY OF UPSTREAM DECISIONS, THE UPSTREAM
  DECISION IS NOT A DECISION — IT IS A SUGGESTION.** The measurement that located row 4's inversion:
  cc-teardown refused **88 of 168** reap proposals (52.4%). Six independent safety legs had been
  added across successive incidents, and every one of them read evidence frozen at sweep start — so
  each new leg lowered the failure RATE without touching its MECHANISM. Generalisable probe for any
  row: compare what the actuator decides against what the proposer proposed. A high override rate is
  a staleness signature, and it is visible from logs alone before reading any code.
- 2026-07-29 (row 4) **A TEST CAN PIN A DEFECT AS CORRECT.** `tests/cc-teardown.bats` asserted that a
  missing who-oracle → close proceeds (exit 0), against a fixture carrying a REAL operator prompt —
  i.e. the fail-open that closed live operator conversations was protected by a green test. Grep your
  row's suites for assertions that a SAFETY check being unavailable still yields the permissive
  outcome; that shape is where fail-open hides, and it survives every code review that trusts green.

- 2026-07-29 **A REPLACEMENT MECHANISM CAN FAIL MORE QUIETLY THAN THE ONE IT REPLACES — check the
  new failure's LOUDNESS, not just its likelihood.** Row 5's near-miss, caught mid-build and worth
  generalising. The rebuild replaced a false ⛔ cliff (which PAGES) with capacity-based deferral
  (which deliberately never pages, because backlog > concurrency is normal). The first
  implementation of the ceiling read a live-SESSION count instead of dispatch's own outstanding
  workers: measured 12 vs 0, so at the default ceiling of 6 it would have admitted nothing FOREVER
  and said NOTHING — strictly worse than the bug being fixed, which at least announced itself.
  The design was right; one signal inside it was wrong, and the design's own virtue (silence on the
  normal case) is what would have hidden it. **When a rebuild converts a loud failure into a silent
  normal state, add an alarm for the SATURATED case at the same time** (row 5: F16 + A13), and pick
  control variables the subsystem actually owns — charging dispatch for the operator's panes let
  human activity throttle autonomy to zero. Caught only because the plan's measured-constants
  discipline forced a live read of both numbers before accepting the spec.
- 2026-07-29 (row 5, source of the two entries above — kept for its row-specific residue only):
  the falsified cell and the disabled-daemon trap were both surfaced here; the generalised
  statements live above, not repeated. What is additionally row-5-specific and still load-bearing:
  (a) the incumbent's cliff record `{action:"abstained",detail:"quota-cliff"}` carries **no
  evidence**, so "zero false cliffs" was not merely unmet — it was **unmeasurable**, and the
  rebuild's acceptance criterion had to create the evidence it is judged by (design rule: a verdict
  that gates an alarm must carry the evidence that falsifies it); (b) a human-driven **desk**
  session doing dispatch by hand is what masked the daemon's 3-day death — a manual fallback that
  silently substitutes for an inert automation is why nobody noticed, so the inert-alarm cannot be
  keyed on "work is happening", only on "the job that should be running, is".
- 2026-07-29 (row 12) **AN ALARM'S EXISTENCE EVIDENCE MUST COME FROM A DECLARATION, NEVER FROM THE
  SUBJECT'S OWN SUCCESS HISTORY.** The `absence-alarm-needs-existence-evidence` law is right, but
  the incumbent implements it by gating on the subject's past activity — which makes "never worked
  once" indistinguishable from "never supposed to exist", so it is never alarmed. That is exactly
  the population that matters: `com.claude.deploy-live` is enabled, loaded, and has **never once
  succeeded** (59 logged `cannot execute` failures, `runs=15`, `last exit code=1`), and its only
  covering alarm (`deploy-lag`) is gated on a GREEN stamp — of which there are **0 in 33** — so it
  is *structurally incapable of firing* no matter how long the deploy lane stays broken. Generalises
  to every "is X still working?" check in the repo: gate on the declaration, not on X's past.
- 2026-07-29 (row 12) **`launchctl list | grep <label>` is the repo's most load-bearing wrong idiom.**
  It maps six real states onto one boolean and puts four of the broken ones on the healthy side:
  not-installed and disabled both read "absent" (indistinguishable from each other and from
  never-intended), while loaded-never-ran, loaded-failing and loaded-stalled all read "present".
  Every existing check uses it. `launchctl print` (runs / last exit code / state) plus the
  root-owned override db `/var/db/com.apple.xpc.launchd/disabled.501.plist` is the read that
  separates them. Related: a broken daemon gets **quieter** with age — launchd's fast-fail throttle
  (`minimum runtime = 10`) stopped scheduling deploy-live after 59 loud failures, so any detector
  keyed on complaint volume or error rate reads recovery where there is decay.
  **COORDINATOR ADDENDUM 2026-07-29T15:00Z — the REPLACEMENT read has its own dead-parse trap, and
  I walked straight into it while re-deriving this very count.** `print-disabled` prints
  `"<label>" => disabled|enabled`; the plist behind it stores `true`/`false`. Those are different
  vocabularies for the same bit, and row 12's own archaeology (correctly) quotes the plist form
  — so "13 `true` entries" and "13 `=> disabled`" are both right about different surfaces. Grep
  the CLI output for `true` and you get **0 with exit 0**, which reads as *nothing is disabled*:
  my sweep returned `total=14 disabled=0 enabled=0` and only the failure of 0+0 to sum to 14
  exposed it. So the fix for `list | grep` is necessary but not sufficient — `print-disabled`
  parsed with the wrong vocabulary fails in the MORE dangerous direction, because `list | grep`
  at least returns nothing when it is wrong, while this returns a confident zero. **Two rules:
  grep the literal `=> disabled`, and assert that disabled + enabled SUM to the label total
  before believing either number** — a checksum is the only thing that distinguishes a real zero
  from a dead grep. Row 12's landed code does use `'=> disabled'` correctly
  (`scripts/dispatch-acceptance.sh:229`, `tests/cc-fleet.bats:60` stubs the plist form) — verified
  before writing this, precisely so the entry is not a false alarm against its own row.
- 2026-07-29 (row 12) **THE COORDINATOR'S OWN COUNT WAS STALE WITHIN HOURS — 12/2 re-derived as
  10/4.** The learning two entries above states 12 disabled / 2 enabled, verified the same morning;
  by 14:00 `dispatcher` and `discovery` were both enabled and loaded (dispatcher pid 74276). Nobody
  was wrong — the measurement decayed. **Consequence for row 5: its "dispatch decision ≤5 min"
  metric is now MEASURABLE, not 0-by-construction.** And the general point, which is row 12's whole
  thesis: any answer of the form "audit the fleet and write down the result" is already wrong; only
  a scheduled reconciler stays true. Re-derive at the moment you gate a decision on it, not once.
