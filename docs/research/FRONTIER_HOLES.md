# FRONTIER_HOLES — claude-infrastructure

Unknown-unknown ledger for the frontier tier (currently Fable 5). Capture holes here without
burning frontier tokens inline; `/frontier-run` spends the window on them. INTEGRATE — never
overwrite history. Statuses: `OPEN` → `IN-PANEL <date>` → `CONFIRMED-BY-PANEL` / `REFUTED` /
`SOLVED-PATH-KNOWN` / `ESCALATED`; closed holes move to `## Resolved` with one-line provenance.

---

## Open

_(none)_

## In-Panel

_(none)_

## Resolved

### H-DSH-1 — Deterministic recycle ACTUATION · SOLVED-PATH-KNOWN (Fable panel 2026-07-19)
Panel verdict: a PostToolUse hook CAN safely exec `handoff-fire.sh --recycle` — the post-catnav
redesign made queue-timing invocation-agnostic (`/exit` INTERRUPTS in seconds, does NOT hold to
turn-end; payload rides as shell-eval argv, never touches the queue; setsid watcher armed BEFORE
`/exit` survives the SIGKILL). Root cause of 0/2419 = the ARM step (model-diligence), not the fire.
Design = 4 stages (deterministic arm → advisory → K=1 deterministic fire, cap-exempt → idempotency
latch). Full design + failure modes: `desk-self-handoff-2026-07-19/synthesis.md` + `panel-findings.md`.
Live bugs found: FM-D empty-payload (`handoff-fire.sh:618` `[ -f ]` not `[ -s ]`), FM-F `/exit`
self-contradiction (:63/:657/:1121 vs :554/:1141). → CORE implemented on `feat/desk-self-handoff-trigger`.

### H-DSH-2 — The safe-fire GATE · SOLVED-PATH-KNOWN (Fable panel 2026-07-19)
Panel verdict: S1-S8 predicate (add S1-sequencer-state, S3 inbound-wait w/ waiter-liveness filter,
S4 mailbox-mtime LOAD-BEARING, S5 teammate HARD-hold, S6 fire-settle, S7 dual-path freshness) + a
used_pct FLOOR on the rot-tell path (probe P1: shipped regex trips on healthy watch narration — LIVE
BUG) + a TWO-TIER bias that INVERTS above ~80% (imperfect-recycle-with-brief > auto-compact-without).
No-double-fire: atomic acquire + SID latch + floor closes the cross-generation rot-tell storm. Full
design: `desk-self-handoff-2026-07-19/synthesis.md`. → CORE implemented on the same branch.

## Seam Registry

| Seam | Components | Last swept | Depth | Verdict |
|---|---|---|---|---|
| desk self-recycle spine | `waiting-recycle.sh` · `handoff-fire.sh --recycle` · `/tmp/cc-telemetry` · `wait-contracts` | 2026-07-19 | Fable design panel (H-DSH-1/2), 2 panelists, probes P1/P4/FM-D/FM-F confirmed | SOLVED-PATH-KNOWN → core built |

## Campaign Candidates

### C-DSH-1 — Unifying recycle-lifecycle + watch-state attestation primitive
BOTH panels' top campaign idea CONVERGED: one SID/cwd-keyed write-before-act record
`{state:WATCHING|COORDINATING|FIRING, ts, DoD, lifecycle:fired→exited→relaunched→engaged}`, maintained
by the desk poll loop + the fire hook + the recycle watcher. Dissolves ≥8 named holes across both
sub-problems (hidden-obligation decidability, G-P4-4 mission-carry, S6 fire-settle, cc-board STALL?
disambiguation, Stage-3 idempotency latch, cc-notify external-typer fence, supervisor sweep target,
recycle engagement-verify anchor). GENERATOR-class (one primitive dissolves ≥3 worklist items) →
promote via `/frontier-campaign`. The shipped CORE is FN-safe without it (mailbox-mtime + contract-scan
+ discrete latch approximations); this is the elegant convergent architecture, not a prerequisite.

### C-DSH-2 — Per-CC-version `/exit` queue-semantics conformance test
Run on every binary bump: typed-`/exit` interrupt + plain-text-steering + slash-hold assertions.
Dissolves the catnav/FM-F regression class permanently and retires the file's self-contradictory prose
(`handoff-fire.sh:63/:657/:1121` "holds to turn end" vs `:554/:1141` "interrupts, does NOT enqueue").
