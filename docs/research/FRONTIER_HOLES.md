# FRONTIER_HOLES — claude-infrastructure

Unknown-unknown ledger for the frontier tier (currently Fable 5). Capture holes here without
burning frontier tokens inline; `/frontier-run` spends the window on them. INTEGRATE — never
overwrite history. Statuses: `OPEN` → `IN-PANEL <date>` → `CONFIRMED-BY-PANEL` / `REFUTED` /
`SOLVED-PATH-KNOWN` / `ESCALATED`; closed holes move to `## Resolved` with one-line provenance.

---

## Open

_(none — H-INERT-1 CONFIRMED-BY-PANEL 2026-07-30 and moved to `## Resolved`; its capture record is
retained verbatim under `## Resolved` so the pre-panel framing is never rewritten.)_

### H-INERT-1 · What GENERATES built-but-inert mechanisms? — CONFIRMED-BY-PANEL 2026-07-30 (3 Fable panelists, baseline-blind; lead session a78e659d) — RESOLVED, see verdict below
- **Seam/axis**: the composition of four surfaces that each individually "work" —
  land pipeline (`commands/ship.md`, `scripts/ship-land.sh`) × activation queue
  (`~/.claude/autonomy/pending-activation/`, `docs/activation/`) × deploy layer (`~/.claude`
  per-file symlinks into the checkout, `deploy-live`) × the permission/settings-wiring surface
  (5 × `settings.json`). Joint invariant — *"a landed mechanism is a LIVE mechanism"* — exists
  only in prose and has never been derivation-audited.
- **Wall**: unswept-seam — 5 instances observed in ONE session (2026-07-29/30), in independent
  subsystems, each previously "fixed" individually without the pattern being named:
  `12-mailbox-posttool` (activation landed WITHOUT its implementation → unrunnable by
  construction, nagged the operator >24 h) · `ship-rail-push-allow` (hook landed `9d2bf16`,
  never wired into the 5 settings.json → EVERY model-issued land push strands; blocked this
  session's own land) · `13-mailbox-gc` (guard depends on a binary that does not exist) ·
  `14-land-pipeline-v2` (`.done` marker present, launchd job NOT loaded) · wake floor
  (prose-only 6 days at 0 armed watchers across 74 mailboxes).
- **Falsifiable question**: is there a SINGLE missing invariant/primitive whose absence
  generates all five — and would enforcing it at ONE chokepoint dissolve them? Specifically:
  (a) can "deployed AND effective" be made a *derivable* predicate per mechanism rather than a
  per-mechanism bespoke check, given that `.done` markers prove a script RAN and never that an
  EFFECT LANDED; (b) is the true generator the **split between a change and its activation
  half** (landing them as separable units), such that the fix is making them atomic rather than
  adding more detectors; (c) REFUTE the cheap answer — that "more/better absence-alarms" fixes
  it — given absence-alarms already exist per-axis and still produced 5 misses.
- **Default-tier attempts**: each instance root-caused individually at file:line this session
  (see `docs/research/mechanical-wake-asyncrewake-2026-07-29.md` §3/§5 and tasks #56, #66, #67,
  #68). Existing partial answers already ruled out as insufficient: the 3-axis activation audit
  (queue / SSOT-parity / effect-read) fires per-axis and still missed all five; memory
  [[feature-durability-mechanism-not-memory]], [[deploy-lag-checkout-behind-origin]],
  [[desk-autonomy-dormancy-staged-not-loaded]], [[classifier-enforced-activation-deploy-boundary]]
  each name ONE facet, none the generator. Not attempted: a derivation-first audit of the
  land→activate→deploy→exercise chain as a single lifecycle.
- **If true, changes**: dissolves ≥4 named worklist items at once and changes what "landed"
  is allowed to mean in the Session Close Protocol (📦 vs ✅ currently splits on
  *committed vs landed*, and would need a third rung for *landed vs live*). Campaign-candidate
  shape (generator-class) if confirmed.
- **Confidence frontier-worthy**: high — pure-derivation over a never-swept 4-way seam, which
  is Fable 5's one retained edge over the Opus 5 default per `model-config.yaml`'s own routing
  note.

#### PANEL VERDICT 2026-07-30 — CONFIRMED, and the answer is not a detector
Three baseline-blind panelists, told nothing of each other or of the 5 instances, CONVERGED on one
generator in three vocabularies: **the expectation — "what SHOULD be wired and live" — is never a
durable machine-readable declaration.** It lives imperatively (`install.sh` globs, each activation
script's `jq` edits, each detector's hand-maintained scope) and *evaporates at activation*: after
`touch <name>.done` nothing states "event E in dir D must carry hook H."
· p1 — "the mechanism POPULATION is defined imperatively, not as data" (reified only in
`launchd/fleet.manifest`); `LIVE` is therefore not uniformly derivable.
· p2 — "activation completeness is a predicate over a moving world (dir-set, script content, hook
names), recorded as a POINT EVENT." Every silent failure routes through a marker keyed on a NAME when
the contract is (content-hash × current target-set).
· p3 — the class is **CLOSED under adding detectors** (every detector is itself a wiring-layer
mechanism); **where you can generate, generating dominates detecting.**

**Sharpest NEW finding:** the settings-class detection layer is *un-activated detection of
un-activation* — `settings-drift-assert.sh` is wired in **0 of 5** dirs while the drift it names is
live. The recursion is the finding. **Irreducible residue:** no in-substrate detector can certify its
own delivery (every alarm chain ends in a Stop-hook render that is itself driftable, and is missing in
`-next` right now) ⇒ exactly ONE external deadman, human-as-timeout; N add nothing.
**Also NEW:** atomicity is partly *undesirable* — land+activate atomically means the agent activates
whatever it lands, dissolving the C10 boundary. Correct model = eventual consistency with a
re-evaluated convergence predicate, not a transaction. Apportionment (p2): consumer-absence-refined
~35% · human-gate-as-queue ~25% · **~20% residual none of the four framings names** ·
separability ~15% · ordering ~5%.

Lead re-probed every prediction before filing: **7 CONFIRMED** (2 worse than predicted — 11/23 launchd
labels loaded; 57/89 registry rows dead-pid), **1 REFUTED as stated** (p1-5 `lib/`; survives in refined
form at `lib/cc-upgrade-gate`, which has no live counterpart). Full report, probe table and
NEW/CONFIRMED/REFUTED tagging: `docs/research/inert-mechanism-generator-panel-2026-07-30.md`.
Cost: 3 Fable spawns of a 6-spawn session budget; 0 panelist writes.
→ generator-class ⇒ promoted to **C-INERT-1** under `## Campaign Candidates`.

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
| land→activate→deploy→exercise lifecycle | `commands/ship.md`·`scripts/ship-land.sh`·`docs/activation/pending-activation/*`·`hooks/activation-watch.sh`·`scripts/settings-drift-assert.sh`·`scripts/settings-hooks-lint.sh`·`scripts/deploy-link-parity.sh`·`install.sh`·`launchd/fleet.manifest`·5×`settings.json` | 2026-07-30 | Fable panel (3 panelists, baseline-blind: lifecycle-derivability / separability / adversarial+negative-space), 8 panel predictions re-probed by the lead | **CONFIRMED-BY-PANEL** → C-INERT-1. Expectation is imperative, never declared ⇒ `LIVE` not derivable. Live at sweep: detection layer wired 0/5 · 4 settings drifts · 11/23 launchd loaded · 57/89 registry dead-pid · MEMORY.md 4KB over the loader cap · `lib/cc-upgrade-gate` unlinked |

## Campaign Candidates

### C-INERT-1 — Declared ⇒ wired, by construction (GENERATOR · from H-INERT-1, Fable panel 2026-07-30)
ALL THREE panelists emitted this independently. Five parts in dependency order — note only part 3 is a
"detector", and part 2 *removes* the need for one:
1. **DECLARE** — one in-repo manifest extending `fleet.manifest`'s proven grammar to every class:
   `name | class | expectation-key | effect-probe+polarity | activation-script`, expectation-key
   class-typed (launchd→label · settings-hook→`event|normalized-command|required-dirs` · symlink→repo
   path · copy→path pair · env→var+source-file). Landing a mechanism *undeclared* must fail, exactly as
   `cc-fleet --plist-parity` already enforces for plists.
2. **GENERATE** the generable — the hook blocks of all 5 `settings.json` become a *build artifact* of the
   declaration, dir-set read from an SSOT **at generate time** (the `09` incident is precisely a dir-list
   baked at author time going stale). Drift becomes **unrepresentable rather than detected**; the
   lifecycle-pair asymmetry (register wired without deregister) becomes unrepresentable too, because
   pairs are declared as pairs. Largest single win, and it *removes* code rather than adding a watcher.
3. **RE-EVALUATE, never remember**, for the human-gated remainder (`launchctl`, deploy): every activation
   exposes a read-only `--verify` re-evaluating its full postcondition against the CURRENT world, keyed
   to its own content hash so a fixed script auto-reopens. `.done` degrades to a cache, never truth.
   Verification is read-only ⇒ **agent-legal**; only the remedy stays C10.
4. **FAIL CLOSED AT THE LAND GATE**, advisory at runtime — a chokepoint whose death is noticed within
   hours, unlike a Stop hook whose death is silent.
5. **ONE out-of-substrate deadman** for the delivery residue; the human is the timeout.
**Why it escapes the bootstrap circle:** `--verify` rides the already-wired `activation-watch` (live in
5/5 dirs), needing no activation of its own — it breaks in from the already-live side
([[deployed-layer-bootstrap-circle]]).
**Dissolves:** the launchd-only scope limit of the effect-read axis · settings-drift as a *class* ·
done-vs-version skew · the un-wired-detection recursion · the new-file-never-registered class · and the
wiring half of the pending-activation queue (collapsing N bespoke steps into one idempotent reconcile,
as `18-fleet-activate` already proved for launchd).
**Status:** candidate, NOT launched. Promotion needs `/frontier-campaign` curation + the Sonnet red-team
gate. Deliberately larger than a worklist item, and deliberately not started inline.

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
