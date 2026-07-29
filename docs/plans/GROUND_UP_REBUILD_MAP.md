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
| 3 | **Cross-session comms** — messages between peers | cc-notify, mailbox+ack cursor, .forward chains, cc-await-ping, mailbox-drain | wake path (2); desk inbox (5) | delivery must survive recycles; exactly-once ack | open (v3 design exists — cross-session-mail-v3 memory) |
| 4 | **Session registry & reaping** — who is alive, who gets closed | session-register, cc-reconcile, cc-reaper, cc-teardown, liveness oracles (cwd/lsof) | teardown of (2)'s panes | never reap a live operator conversation | open |
| 5 | **Autonomy dispatch & discovery** — what gets worked on | cc-dispatch, cc-backlog, cc-discover, desk loop, launchd dispatcher/discovery | fires via (2); reads (10) | backlog > concurrency is normal, not a cliff | **REBUILDING 2026-07-29** — [AUTONOMY_DISPATCH_V2.md](AUTONOMY_DISPATCH_V2.md); design landed 7400c614 |
| 6 | **Guardrail/hook layer** — what a session may do | 69 hook entries / 12 events, validate-bash, permission rails, Stop asserts, OVERWRITE guard | every subsystem's enforcement chokepoints | a hook failure must never block a tool by accident | open |
| 7 | **Account/quota routing & relogin** — which account works | claude-accounts, cc-relogin*, limit-recover, model-config.yaml SSOT, launchers | fire-time ranking (2) | login cliffs are hard walls; 4 isolated accounts | open |
| 8 | **Context economy** — when a session recycles | waiting-recycle, boundary-handoff, dod-persist, /wrap, session-continue | recycle executes via (2) | rot degrades decisions before the wall breaks them | open |
| 9 | **Memory & knowledge** — what survives sessions | MEMORY.md + topic files, skills/, plans + find-plan, session index/search | consumed by every session start | anti-capture hygiene; index at read-size limit | open (compaction backlogged b0d889846885) |
| 10 | **Observability & operator surface** — what the human sees | cc-blockers board, operator-readout, pages+damping, statusline, activation queue | renders facts owned by 1,4,5,7 | absence-is-loud WITH existence evidence; silver-platter commands | open |
| 11 | **Worktree & warm-pool management** — where writers work | worktree-gc, warm pool build, new-worktree, .worktreeinclude | claimed by (2); landed by (1) | 107 GB observed drift; ownership per artifact-class | open |
| 12 | **Daemon fleet & activation** — what runs unattended | 13+ launchd jobs, plist SSOT parity, pending-activation queue, C10 boundary | carries 1,4,5,7,8 | disabled-bit trap; agent stages / operator activates | open |

**Why this cut is MECE:** every script/hook in the repo answers to exactly one row's
responsibility; overlaps are declared as seams with a single owner. Row 1's rebuild validated
the method AND the seams model (its rebuild consumed seams from 6, 10, 12 without redesigning
them).

**Dispatch order recommendation (pain-first, dependency-aware):** 4 → 3 → 2 (the
liveness/comms/succession triangle shares seams — sequence, never parallel) · then 5 · 12 ·
10 · 8 · 7 · 11 · 9 · 6 last (it is every other row's enforcement surface — rebuild it after
its customers stabilize their contracts).

## Learnings (accumulate; never delete)

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
  job makes a metric read 0% BY CONSTRUCTION, which is not a performance result.** Verified
  this session via `launchctl print-disabled gui/$(id -u)`: **12 of the 14 `com.claude.*` jobs
  are disabled**; only `com.claude.postland-verify` and `com.claude.deploy-live` are enabled,
  and `launchctl list` shows those two alone loaded. `com.claude.dispatcher` and
  `com.claude.discovery` are BOTH disabled, so row 5's "dispatch decision ≤5 min" was
  unmeetable before a line of code was read. Corroborated independently by `cc-backlog`
  107f27fbb00c and memory `desk-autonomy-dormancy-staged-not-loaded` (built but INERT: staged
  in pending-activation/, never loaded). Whether the mass-disable was deliberate is still an
  OPEN operator question — do not assume either way. Row 12 owns this trap; every other row
  must still run the check first, because a row that measures an inert subsystem will report a
  performance problem it does not have.
- 2026-07-29 (row 5): the Phase-1 "re-derive every handed-down count" rule paid immediately —
  row 5's own standing-constraint framing ("backlog > concurrency is a false cliff, fixed by
  bef587a") is FALSIFIED by disk: that fix landed 2026-07-18, the 12 observed cliffs occurred
  2026-07-26. The real cause was an unbounded spawn rate with no fleet concurrency ceiling.
  **Generalisation for later rows: a map row's "standing constraint" cell is itself a claim —
  re-derive it before designing against it.** Second finding of the same shape: the row's two
  launchd jobs had been `disabled` and silently inert for ~3 days with zero alarm, so the row's
  metric was being met 0% of the time by construction. Check activation truth FIRST on any row
  whose surfaces include a daemon (rows 5, 12, and the deploy half of 1).
