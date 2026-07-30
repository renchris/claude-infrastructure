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
| session-closure surface (all closers) | `cc-reaper`·`cc-classify`·`cc-teardown`·`reap-guard.sh`·`teammate-auto-shutdown.sh`·`waiting-recycle.sh`·`team-orphan-reaper.sh`·`lead-crash-watchdog.sh`·`lead-supervisor.sh`·`session-end.sh`·launchd | 2026-07-25 | Fable enumeration panel (2 panelists, baseline-blind), full closer inventory, all findings lead-verified at file:line | 3 closers FIXED (092e823 reap-guard R-d + sibling 24722de orphan-reaper + the reaper gaps); 3 residuals → C-SC-1, **all CLOSED 2026-07-29** (no campaign — see C-SC-1 § RESOLVED) |

## Campaign Candidates

### C-SC-1 — One "who-drove-the-last-turn" session-ownership oracle for every closer (GENERATOR)
BOTH 2026-07-25 enumeration panelists CONVERGED: extend `cc-classify`/`reap-guard` into the single
callable EVERY session-closing actuator must consult pre-disruption — adoption-hold + fired-stamp +
birth-grace + products + a **sticky adoption marker** (so an operator prompt evicted past the 2 MB
transcript tail is not lost) + composer-unknowable ⇒ HOLD. Dissolves ≥3 named residuals from the
2026-07-25 shutdown-hardening pass (see `session-crash-forensics-2026-07-23.md` § 2026-07-25 addendum):
(1) **waiting-recycle S6** — the 900 s-SOFT-vs-21600 s-hard window fork collapses to one constant, and
the desk self-recycle stays live because the oracle answers from the marker, not a re-read of the
tail that would deadlock it; (2) **R1 tail-eviction** — the sticky marker replaces the bounded
`tail -c 2000000` read that §4.7 + the new Gap-2 leg + reap-guard R-d all depend on; (3) **cc-teardown
caller-trust** — the final actuator (G-b accepts any non-empty string; its selftest passes literal
`"x"`) requires a fresh machine verdict ≤N-min old at the kill. Every FUTURE closer inherits the guard
instead of re-deriving the incident (retires the whack-a-mole class the memory already flagged). The
repo's own C10 module pattern (`reap-guard`, `exit-deadline`) is the template. Point-fixes were
deliberately deferred: naively hardening waiting-recycle's empty-tail case deadlocks the desk's own
self-recycle, and a rushed multi-file tail-fallback in just-shipped safety code is the exact risk the
hardening constraints guard against. GENERATOR-class (one primitive dissolves ≥3 items) → promote via
`/frontier-campaign`. Also filed as negative space: the consent-free `it2 close -f` transport (nobody
owns "which closes deserve the iTerm2 modal back"), composer-draft invisibility fleet-wide, and
`leadSessionId` having no lifecycle owner.

#### RESOLVED 2026-07-29 — closed at the DEFAULT tier, NOT promoted to a campaign
Landed as three commits: `fix(context-econ): three-valued interactive answer` (cherry-pick `-x`
**`51521697`**) · `fix(context-econ): predicate parity — image-only paste + whole-file fallback in ce_`
(cherry-pick `-x` **`255f4102`**) · `fix(cc-interactive): three-valued who-oracle — "cannot read" is not
"nobody typed"` (new). The two source shas are the stable references — they live permanently on
`fix/infra-perfection`, whereas the landed shas are rebase-volatile until the land completes.

**Why no campaign.** The generator insight was already captured and largely BUILT on 2026-07-25 (the
oracle nucleus `hooks/lib/cc-interactive.sh` + the cc-classify / teammate-auto-shutdown / cc-teardown
belts). What remained was *identified, routine* work — which the frontier-routing policy excludes by
construction: the frontier tier's value is exclusively the delta above the default on
**unknown-unknowns**, never work with a known path. Promoting this would have spent the window
re-deriving a solved design. The candidate is closed, not downgraded — its ≥3-residual claim was
honoured item by item:

| Residual (as filed) | Disposition |
|---|---|
| (c) unify `ce_` with `ci_` | **The work already existed and was STRANDED** — `255f4102` + `51521697` sat 4 days unlanded on `fix/infra-perfection` (a 55-commit, 125-file branch that never shipped). Cherry-picked with `-x`, not rebuilt. |
| (a) migrate reap-guard R-d off `ce_` | **Dissolved, not performed.** Both predicates now carry ONE three-valued contract, pinned across every readability shape by `tests/interactive-parity.bats`. R-d's `ce_` call is no longer a weaker second implementation, so the migration is now a no-op rename — and two independent bodies is the deliberate belt+suspenders (the legs cannot share a bug). |
| (b) sticky adoption marker | **NOT NEEDED — wall re-verified, and it is closed by a fallback rather than a marker.** Its stated purpose was 2 MB tail eviction; the whole-file fallback now closes that in BOTH predicates. The wall was real and material — **345 of 7319** transcripts on disk exceed 2 MB — which is why the fallback matters and why a marker would be redundant state. No transcript-*rotation* blind spot is demonstrable: the only rename in play is `<sid>.jsonl.handed-off`, which belongs to a session already dead, with nothing left to hold. |
| waiting-recycle **S6** soft/hard fork | **Deliberately NOT collapsed.** S6 is ADVISORY — it recycles the desk's own context and never kills a session — so it correctly sanitizes any non-numeric answer to `""` and keeps its softer 900 s window. Only DESTRUCTIVE consumers need the hold; collapsing the constant would have deadlocked the desk's self-recycle, exactly as the deferral note warned. |

**What the residual list had WRONG — and it was the live bug.** The list assumed the `ci_` gate was
already strict and only its `ce_` backstops were weak. Walking every consumer showed the inverse: `ci_`
was the two-valued one, and its consumers are the actuators that actually **kill** a session — so a
corrupt / truncated / empty transcript made `cc-teardown` and `teammate-auto-shutdown` close the pane.
Fixed in `513611d7`, RED-proved (pre-fix, the corrupt-transcript fixture really did close the pane).
Generalisable, and the second appearance of this shape here: **when a contract gains a third state, the
consumer that looks safest is the one to check first** — the `ce_` legs got the split because they were
the named suspects, which is exactly why the unnamed gate kept the defect four days longer.

One boundary is recorded because it was RED-proved WRONG before it was right: an *unresolvable*
transcript is NOT "unreadable". Routing it through the same refusal turned 7 of `cc-teardown`'s 17
selftest checks into REFUSE — a missing `<sid>.jsonl` is the ordinary state of a synthetic sid and of
any handoff-renamed transcript, so refusing on it is a fleet-wide teardown outage whenever the beat
world is also down (fail-closed as amplifier). Only a transcript that EXISTS and cannot be READ is
unprovable; a boundary test pins it in both directions.

Still open as negative space (unchanged, not part of this close): the consent-free `it2 close -f`
transport, composer-draft invisibility fleet-wide, and `leadSessionId`'s missing lifecycle owner.

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
