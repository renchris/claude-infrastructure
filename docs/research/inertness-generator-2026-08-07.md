# The inertness generator — why correct analyses do not change this machine

**Date:** 2026-08-07 · **Author:** frontier-tier derivation session (Fable 5), worktree
`inertness-generator`, base = `origin/main` exactly (`git rev-list --left-right --count
origin/main...HEAD` → `0 0` after rebase; the scan-reports-its-revision scar honored).
**Brief:** derive why this system reliably produces correct, adversarially-verified analyses that do
not change the machine, and name the single structural change that makes a conclusion become the
machine's behaviour by construction. **Not in scope:** the deploy lane's implementation — that is
owned by `docs/plans/DEPLOY_LANE_GROUND_UP.md` (T0–T3, teammates live as of 2026-08-07); §8 below
coordinates with it.

---

## 1. Evidence as verified on disk tonight (2026-08-07 ~01:40)

Every item re-read from disk before reasoning. One item in the brief was stale, and its correction
is the strongest single datum in this document.

| # | Brief's claim | Disk tonight |
|---|---|---|
| 1 | `bin/cc-bats` built (21656 B); **no** caller routed to it | **STALE.** `hooks/qos-rewrite.sh` (15223 B at the live revision) rewrites any-spelling `bats` → `cc-bats` at the PreToolUse chokepoint, is registered at `~/.claude/settings.json:464`, and is live. But it routes to the **live-revision** `cc-bats` = 21656 B (Jul 30) while trunk's is 37662 B — today's corpus-mutex fix (`db5a0483`, the one that stopped three concurrent corpus runs taking load to 66) is inert. The brief's "21656 B" was itself read from the stale live layer. |
| 2 | §12.7.7 LANDED ≠ LIVE; 85 behind; deploy-live last exit 1; 536 log lines | Confirmed and worse: shared checkout `main @ a9060c18` (2026-08-05 15:37) is **104** commits behind `origin/main` (75 on 07-31 → 85 at brief time → 104 now; accelerating). Daemon: `state = running`, `last exit code = 1`, log now 708 lines, **545 identical `REFUSED` lines**: `target 3725e5432bfc is not a descendant of live HEAD a9060c18b314 — this would ROLL BACK the live layer`. |
| — | (wedge mechanism, not in brief) | `3725e543` **is** on trunk lineage (2026-08-04 10:35) and is **older** than live HEAD (2026-08-05). The daemon's target selection picked a green stamp *behind* live; advancing to it reads as rollback (refused), and no newer stamp can mint while the corpus stands red (57 h+). Both verbs refused; the daemon relaunches and refuses forever. |
| 3 | `curl-gate-scope.sh` built + 14 bats + activation script shipped; `settings.json:435` still registers unscoped `curl-gate.py` | Confirmed exactly. The scoped file is even **deployed** (present at the live revision, Jul 31) — inert purely at the *registration* edge, which is a C10 operator hand-step sitting in the rotting queue (`26-curl-gate-scope-activate.sh`, >24 h). |
| 4 | ~40 pending activations, 11 rotting, 7 SSOT drifts | 38 pending + 27 done in the live queue; 11 rotting >24 h; **8** drifts per tonight's SessionStart banner (undeployed-mirror / repo-only / content-drift). The banner fires **every session start**. |
| 5 | GROUND_UP row 1: "DONE 2026-07-28 … 9 lands; exemplar" | Confirmed verbatim (`GROUND_UP_REBUILD_MAP.md:17`) — and that exact subsystem is the one wedged in item 2. |
| 6 | Seven correct analyses + `machine-lag-and-kitty-2026-08-06.md`; symptom recurred after each | All eight present in `docs/research/`. Not re-litigated — the brief stipulates each is correct, and this document takes that as premise. |

---

## 2. The derivation

Work from the system model; the reads above only confirm it.

### 2.1 Two kinds of store

The machine's behaviour at any moment is a function of its **enforcing stores** — the stores an act
reads *at the moment it executes*: `~/.claude/settings.json` hook registrations, the revision the
live-layer symlinks resolve to, launchd plists, PATH. Everything else the system writes —
`docs/research/`, `docs/plans/`, CLAUDE.md prose, MEMORY.md, the pending-activation queue *as
documentation* — is an **advisory store**: it binds only if some future agent or the operator
discretionarily reads it and acts.

An analysis changes the machine **iff its conclusion reaches an enforcing store.** Nothing else
counts, however correct.

### 2.2 Law 1 — the diode

Enumerate the edges by which anything reaches an enforcing store here:

- trunk → live layer: gated by an affirmative predicate (green stamp + descendant check);
- trunk → `settings.json` / plists: a **C10 operator hand-step** (agent stages, operator runs);
- prose → session behaviour: a future session voluntarily obeying advice.

Every edge into an enforcing store is either *permission-gated* or *discretionary*. Every edge into
an advisory store is **unconditional** — landing a doc always succeeds; the close protocol, the
gates, `/ship` all certify and reward it. Writes therefore flow freely into the advisory side and
hit a diode before every enforcing store. Under sustained production, knowledge accumulates and
behaviour stays fixed — **by flow conservation, not by accident.** The seven analyses are the flow,
pooled behind the diode. That is the whole answer to "why does knowing not help": knowing lands on
the side of the diode that cannot conduct.

### 2.3 Law 2 — a permission gate turns events into states, and states rot

Each permission gate keys on a **state record** of a past **event**: the newest green stamp is a
corpus run from 08-04; `settings.json:435` is a registration decision from whenever it was made;
"DONE 2026-07-28; exemplar" is nine lands from a week ago. States outlive the events that minted
them and *keep governing after their premises die*. Tonight's wedge is the pure case: two state
stores — stamp `3725e543` and live HEAD `a9060c18` — each movable only by machinery that reads the
other, a daemon whose only verb is "no", and 545 identical refusals that page no one. A permission
gate fails as a **state**: standing, unowned, unbounded (75 → 85 → 104). A veto fails as an
**event**: one named land reverted, once, with a culprit.

Why does the system choose permission-polarity every time? **Blame asymmetry.** An advance that
breaks something has an author — the gate that allowed it. A refusal that strands 104 commits has
none; absence of behaviour generates no incident. So every new gate is born fail-closed — locally
safe, globally fatal — and the class reproduces without anyone deciding it should. The system even
knows the corollary: *an alarm that always fires carries zero bits* (its own memory). The 545
identical `REFUSED` lines and the every-session activation banner are alarms that always fire.

### 2.4 Law 3 — inertness is the fixed point of the system's own two policies

Both of these are standing, written policy on this machine:

- **A.** *"The caller cannot be trusted"* (`MACHINE_CAPACITY_V2.md:15,722,972`): behaviour changes
  require affirmative permission — green gates, operator-run activations, C10 hand-steps.
- **B.** *Autonomous-to-100%; asking on routine decisions IS the defect* (drive-by-default,
  Follow-On Gate, the autonomous-to-100 memory): the operator must never be required in the loop.

A demands an approver; B forbids summoning one. The unique joint solution is exactly what the
machine does: produce conclusions autonomously (B satisfied), stage them into stores whose
consumption would need the permission A requires, and never obtain that permission — B forbids
asking for it, and A's approver never arrives on their own. **The system is not failing to change
the machine; it is solving its constraint system by not changing the machine.** Seven more correct
analyses cannot dent a fixed point — they add to the advisory side while leaving the constraints
untouched.

### 2.5 Why seven correct authors could not see it

Each analysis session's own definition of done terminates at **trunk** — the close protocol's top
rung is "✅ Complete & live on trunk", computed from git reads; its strongest claim is a
content-verified *land*. Behaviour lives one-to-three edges *past* trunk (deploy → registration →
invocation), and the attribution discipline explicitly teaches sessions to close ✅ across a lagging
enforcing store ("a gate-green marker the land path cannot advance … is not your red"). Correct
per-session; in composition, a contract that ends every session one hop short of the machine.
Asking "what broke?" stays inside one session's contract. "Why does knowing not help?" is a question
about the *composition*, which no session inside it is ever scoped to ask.

### 2.6 The confirming exception — the brief's one wrong item

The single conclusion this month that was encoded as an **enforcing-store change** and carried by a
**mechanical** path — `qos-rewrite.sh`, a chokepoint rewrite, registration carried by the 08-05
deploy's install step — is the single conclusion that governs behaviour tonight. Everything encoded
as advice (routing prose that was never even written), as an operator hand-step (curl-gate-scope's
registration), or parked behind the permission gate (trunk's current `cc-bats`) is inert. Same
month, same authors, same machine: the only variable separating live from inert is **which side of
the diode the conclusion was encoded on.** And the residue proves the second edge: qos-rewrite beat
the diode at the registration edge and still sits behind it at the *revision* edge — it routes every
`bats` to a 104-commit-stale `cc-bats`.

### 2.7 The class already survived one correct analysis of itself — the 07-30 panel

*(Integrated 2026-08-07 ~02:30 by the successor session in this worktree — fired on the same brief,
it re-derived §2's law independently before reading this document; the convergence is evidence, and
this datum is the one thing it held that this document did not.)*

`docs/research/inert-mechanism-generator-panel-2026-07-30.md` is prior art the brief did not list:
three baseline-blind Fable panelists, eight days before this document, converged on the generator
one level below this one ("the expectation is never a durable, machine-readable declaration"), had
every prediction re-probed by their lead, and shipped a five-part fix design (declare / generate /
re-evaluate / fail-closed-at-the-land-gate / one external deadman). Its fate, verified on disk
tonight: the not-run activation queue grew 11 → 38 since it landed, the settings drift it
probe-confirmed is still live, its land-gate predicate was never built, and its five "immediate,
independently actionable" items are unactioned. **A correct meta-analysis OF the inert class joined
the inert class** — five conclusions addressed to enforcing stores, delivered as advisory-store
artifacts, pooled behind the diode like everything else.

The panel even proved this about itself in advance. Its p3 theorem — *"the class correct-but-dormant
is closed under adding detectors, because every detector is itself a mechanism in the wiring layer
where dormancy lives"* — extends one level up: **the class is closed under analyses of the class.**
Any output whose terminal form is a recommendation addressed to a future actor joins the population
it describes, meta-analyses included. §3 escapes only because its landable terminal form is a
polarity change on live edges plus follow-ons filed in a ledger a renderer reads — never a design
waiting for a reader.

---

## 3. The one structural change

> **Reverse the polarity of every edge on the conclusion→behaviour path: no affirmative-permission
> gate may hold an advance; all safety is expressed as veto-after — the revert of a named land.**

This generalises the deploy-lane plan's own design principle — *"evidence vetoes red, it never
permits green"* (`2aeb23a7`; the lane later revised this two-tier in `9055ef2e` — see §9, which
narrows this law accordingly) — from evidence semantics to the entire actuation path. A permission
gate holds a *state*, states rot and then govern; a veto consumes an *event*, and events die with
their causes.

One law, four faces:

1. **The live layer is a derived view of trunk.** Converge unconditionally on every land and on a
   timer (ff + install). A standing red cannot hold it back. The only thing that moves live off
   trunk-tip is an explicit revert of a named land — which is itself a trunk commit, so live remains
   a pure function of trunk at all times. LANDED = LIVE by construction.
2. **Verification runs after convergence and its only verb is veto.** Red ⇒ revert the implicated
   land (lineage is linear and live, so bisection is cheap), page once per event. A red that
   predates a land cannot veto it — the attribution rule the system already owns
   (postland-red-triage) becomes the *gate's* semantics instead of the *session's* excuse.
3. **Activations become migrations.** A registration / plist / settings change is executable,
   idempotent state landed **in the same diff as its subject** and run by the converger at deploy —
   exactly as schema migrations run at deploy rather than from a folder the DBA is supposed to
   visit. The pending-activation queue survives only for genuinely operator-owned steps (sudo, GUI,
   credentials), each blocking its *own* item and paged once — never a standing parallel store,
   because the live queue is materialised from the repo (SSOT drift becomes unrepresentable).
4. **✅ moves one store right.** The close protocol's top rung requires the conclusion observable in
   the enforcing store (registration present live; live layer at/above the landed sha). Under faces
   1–3 that is machine-guaranteed within one converge cycle, so ✅ stays cheap — it just can no
   longer be true while the machine didn't change.

**What happens to "the caller cannot be trusted."** It is *better* enforced, not abandoned.
Trust-in-advance is unknowable — which is why the permission predicate wedges; harm-after-the-fact
is observable — which is why veto works. The operator keeps a standing one-command rollback and a
full per-land audit. Policy A's enforcement moves from *pre* (approve every advance) to *post*
(standing veto over any advance); policy B is then satisfiable simultaneously, and the §2.4 fixed
point dissolves because permission is no longer a required input anywhere in the loop. This
re-scoping of C10 — "operator runs" becomes "operator can revert" — is the one clause a human must
ratify, once. It is the entire decision; everything else is mechanism.

**The strongest standing objection was filed eight days ago by the 07-30 panel itself** (its p2:
"land+activate atomically would mean the agent activates whatever it lands, which dissolves the C10
security boundary; the right model is eventual consistency with a re-evaluated convergence
predicate"). Two answers. Empirical: eventual consistency with an unowned convergence predicate is
what the machine has been running, and the predicate joined the dormant population (§2.7) —
*eventual* is the advisory store's name for *never*. Structural: face 3 does not self-authorize the
agent; the operator-owned residue keeps a human on every genuinely C10 step. What it abolishes is
the standing silent wait — the queue-as-store — via the rescoping above: operator-runs becomes
operator-can-revert, ratified once. The boundary survives; its silence does not.

---

## 4. Each evidence item under the change

1. **cc-bats / qos-rewrite** — already the exemplar of the authoring face. Under face 1 today's
   mutex fix is live within one cycle; under face 4 the six-day unrouted window (07-30 → 08-05)
   could never have closed ✅, so it could not have rotted silently.
2. **LANDED ≠ LIVE (§12.7.7)** — the category disappears. Live is a derived view; a 104-commit pool
   cannot form; lag exists only inside a converge cycle or an active named revert, both bounded and
   paged. The both-verbs-refused wedge is unrepresentable: there is no stamp-vs-HEAD comparison
   left to wedge — the target is always trunk-tip minus explicitly reverted lands.
3. **curl-gate-scope vs `settings.json:435`** — the registration lands in the same diff as the hook
   (face 3) and is materialised at converge. A deployed file with an inert registration cannot
   exist; item 26 never enters a hand-queue.
4. **38 pending / 11 rotting / 8 drifts** — the mechanical majority run at converge and the queue
   collapses to the operator-owned residue, each item paging once, attached to the work it blocks.
   The every-session banner — an always-firing alarm, zero bits — is deleted.
5. **"DONE 2026-07-28; exemplar"** — a standing state-claim stops governing belief because nothing
   reads rows to decide behaviour; the converger's live status is the only oracle (the pattern the
   ship-policy rewrite already adopted: never trust the paragraph, read the tool).
6. **The seven analyses** — analyses stay advisory; that is their nature. But a conclusion that
   prescribes behaviour has exactly one landable terminal form: the enforcing-store change, live
   within one cycle. The eighth lag analysis ends with the admission-control gate *registered*, not
   with a spec for one.

---

## 5. The offered framings, attacked

- **"No cross-session admission control"** — an *instance*, not the generator. It is a correct
  conclusion pooled in the advisory store; building it tonight through the current path would land
  it behind the same diode. Spec'd-but-inert is precisely what the model predicts for it.
- **"Landed ≠ live"** — the largest single *projection* of the generator onto one edge. Dissolving
  it (the sibling's T0–T3) fixes this wedge; without the polarity law the class re-expresses at the
  registration edge — item 3 is already a live counterexample that never touches the deploy gate:
  file deployed, registration inert.
- **"Verification coupled to deployment"** — real, but it is the loop *gain*, not the generator. It
  explains why the deploy diode is an attractor (the repair path routes through the health it would
  repair), not why the same inertness appears at edges where no verification is involved at all
  (the activation queue, the routing prose).
- **"The expectation is never declared as data" (the 07-30 panel)** — the deepest prior answer, and
  necessary: it explains why dormancy is *invisible*. Not the generator: dormancy persists where
  visibility is total (the drift banner prints at every session start; nothing acts), and the
  panel's own correct fix rotted (§2.7). Declaration without polarity reversal is one more advisory
  write.
- **The brief's "at least one framing is probably wrong"** — it was an evidence item, not a framing:
  item 1's factual core is stale on disk, and its correction (§2.6) is the strongest evidence *for*
  the law.

---

## 6. Falsification

- **F1 (decisive).** With faces 1–3 live on the trunk→live and registration edges, take the next
  correct analysis and land its conclusion. Prediction: the enforcing store reflects it within one
  converge cycle with zero operator acts, and its symptom class does not recur while live. The
  theory is **refuted** if a correct, landed, chokepoint-encoded conclusion again fails to govern
  behaviour through a blocking edge that is neither a permission gate nor a discretionary copy —
  the existence of a third edge type breaks the model.
- **F2 (dynamics).** Flip only the deploy edge to veto-polarity (the sibling's lane). Prediction:
  live lag pins ≈0 and stays; the 57 h standing red converts into at most a handful of per-land
  reverts with named culprits. **Refuted** if lag re-accumulates monotonically while the converger
  is healthy — that would indict capacity or operator attention as the generator, not gate
  polarity.
- **F3 (reproduction).** Blame asymmetry (§2.3) predicts new permission-polarity gates keep being
  born unless a land-chokepoint lint forbids new affirmative-permission predicates on actuation
  paths. Count new such gates over three weeks without the lint: zero new instances **refutes** the
  reproduction mechanism (the class would be historical accident, not attractor).

---

## 7. What this document deliberately does not do

It does not prescribe `deploy-live.sh`'s target selection, the anti-rollback guard, or the alarm
kinds — `DEPLOY_LANE_GROUND_UP.md` owns those (T1 invariant landed `6b0579c9`/`c3ea951a`; T2/T3
teammates own the files). This document supplies the generator-level law those rebuilds are
instances of; if the lane's T1 invariant and §3 here disagree, the disagreement itself is a finding
and should be surfaced to the desk before either lands.

## 8. Coordination

Sent to `deploy-lane-groundup-263` on landing: this path, the §3 law, and the note that face 1/2
generalise their `2aeb23a7`-principle; faces 3–4 (activation-as-migration, ✅ one store right) are
**not** in their scope and are the follow-on work this document files. Filed: `cc-backlog
6078392359ac` (faces 3–4 + the §6 F3 reproduction lint). *Provenance note: the original landing
claimed this filing, but the ledger held no matching item — the successor session filed it
2026-08-07 ~02:30. A doc asserting a store-write that the store does not contain is §2.2 in
miniature, caught one hop from home.*

## 9. Adversarial reply from the deploy lane (2026-08-07 01:49) — and the narrowed law

`deploy-lane-groundup-263` answered within hours of the landing — §6 doing its work. An inbox
message is an advisory store with one reader, so the exchange is recorded here:

1. **Stale citation (accepted).** §3's `2aeb23a7` was the lane's first draft; `9055ef2e` revised it
   after archaeology showed the green gate answers a NAMED incident (`755dd24a`: the old nag emitted
   a raw `git pull --ff-only` — deploying origin/main verified or not). The lane's current T1 is
   two-tier: prefer a green inside a staleness budget, advance on not-red past it. The disagreement
   with §3 is confined to behaviour *inside* the budget.
2. **The law as stated overshoots (accepted — the law narrows).** The lane's point: a permission
   gate with a finite escape (budget expiry → advance-with-page) cannot rot into a standing state —
   **unboundedness is the defect, not permission-polarity as such**. This independently matches the
   successor session's own derivation (owner+deadline deferrals whose expiry escalates). The
   testable, narrowed form of §3:

   > **No gate on an actuation path may be unbounded.** Every affirmative-permission predicate must
   > carry a finite budget whose expiry converts the standing state into an event — advance+page,
   > escalate, or revert. Veto-after remains the safety default; bounded permission is a legitimate
   > tier inside its budget. "No permission gate at all" is neither necessary nor — given (3) —
   > currently safe.

3. **Measured objection to pure-veto (accepted as a live blocker).** The veto actuator on this host
   succeeds **3 of 25 all-time** (`runner.log` census: landed=3, FAILED=5, skipped=17; newest
   failure `rc=90`). Moving ALL safety onto a 12%-effective mechanism is no remedy tonight. Sharper
   still — the lane's point 5: the skips run under *"attempted once, skipped
   forever"* — a state-record governing after its premises, i.e. **Law 2 living inside the
   prescribed replacement**, and a fixed point of the system's own policy in the exact §2.4 shape.
   A veto that cannot actuate is a permission gate in disguise. Filed: `cc-backlog 8e8a306f6dc0`
   (bound the skip; page on failed revert) — a prerequisite for the pure-veto tier ever being
   reachable.

   **CLOSED 2026-08-07** (`scripts/postland-verify.sh`, C26 in `tests/postland-verify.bats`). Two
   findings from re-running the census before fixing it. First, a correction: the counts hold, but
   the 17 skips are **four** culprits, not one — `a1743ffebd35` ×3, `47a5350498ee` ×3,
   `57e162494c10` ×3, `b3f728858a6f` ×8. That strengthens the objection rather than weakening it;
   the fixed point is the marker's *shape*, reproduced independently four times, not one unlucky
   sha. Second, and the reason the fix is not simply "expire the marker": the four are two different
   facts wearing one reason token. `b3f728858a6f`'s revert **landed** (`3725e5432bfc`) — its 8 skips
   are the *correct* refusal to revert a commit already out of trunk, and bounding them would have
   built the revert war guard 2 exists to prevent. The other three never landed, and were disarmed
   by a fact about a single trunk tip (`rc 90` = the revert conflicted off *that* tip). So the bound
   is asymmetric by outcome: a landed revert stays permanent, a failed one re-arms on new evidence
   (moved tip) or decay, bounded by `POSTLAND_REVERT_RETRY_MAX`. Both terminal arms now page and
   file a backlog item — under the old code the mechanism declined on 17 of 25 encounters and told
   nobody, which is the half of "a veto that cannot actuate" that made it *invisible* as well as
   inert. **This is §3 face 2 applied to itself**: the veto's own disarm was an unbounded standing
   state, and §9's narrowed law — every permission predicate carries a finite budget whose expiry
   converts the state into an event — is what it was fixed with.

Both documents stand; T0–T3 remain the lane's. The generator-level law survives contact narrowed,
not refuted — and the narrowing came through the one channel this document argued for: a store a
mechanism reads (the lane's own escalation path), not a reader's discretion.

## 10. Faces 3–4 and the F3 lint, as built (2026-08-07, `cc-backlog 6078392359ac`)

Pre-req confirmed before starting: the lane's T2 advance-by-default is on trunk, and the wedge §1
item 2 measured has drained — **live-layer lag 104 → 8 commits**. F2's prediction held.

| Face | Landed | What it is |
|---|---|---|
| 3 · activations become migrations | `6c695187` | `migrations/` + `scripts/deploy-migrations.sh`, run by the converger. |
| 4 · ✅ moves one store right | `55ee2b8a` | `wrap-ledger` rung 🚀 between 📦 and 👤; `operator-readout` arm. |
| §6 F3 · reproduction lint | `8582749a` | `scripts/permission-gate-lint.sh`, blocking leg of `run_gate`. |

**Face 3.** Two phases at every converge. *Materialise* makes the live pending-activation queue a
derived view of `docs/activation/pending-activation/`, so REPO-ONLY and CONTENT-DRIFT cannot survive
one cycle; a dry run against the live box reproduced all 7 of that morning's drifts and would clear
them in one pass. LIVE-ONLY deliberately remains a finding — the converger never writes repo-side,
because a `cp live -> repo` recreates a committed file as a local diff the next ff must conflict on.
*Migrate* runs un-applied `migrations/*.sh` once, ledgered, with failure as an **event**: it stops
the ordered run, retries with a climbing attempt count, and clears on recovery.

**The C10 boundary was NOT crossed, and that is the load-bearing design decision.** §3 says the
rescope — *operator runs* → *operator can revert* — is the one clause a human must ratify once. It
has not been ratified, so the runner does not self-authorize it: every migration declares its class,
`mechanical` runs at converge, `c10` is **staged and never executed** — filed once into `cc-backlog`,
whose event-keyed ids make "paged once" a property of the store rather than of a damping window. An
undeclared class is a hard error rather than a default, because *both* defaults are wrong: mechanical
would run a settings-touching migration unattended, and c10 would silently rejoin the hand-queue this
mechanism exists to abolish. Promoting a migration the day the rescope is ratified is a one-word diff.

**Face 4** is bounded, and the bound is the whole design. The converger ticks every 600 s, so a
session that lands and closes immediately *always* sees live < HEAD; a rung that fired there would
fire at every write-close and carry exactly as many bits as one that cannot fire at all. So inside
the budget the fact is attached to ✅, and only a lag **past** budget mints 🚀. This is §9's narrowed
law applied to the close protocol rather than to an actuation path.

**The F3 lint implements §9's narrowed law, not §3's absolute** — a guard-refusal on an actuation
path must carry a *declared* finite escape. Whether a gate is bounded is not decidable from bash, and
the 07-30 panel's finding was precisely that the expectation is never a durable machine-readable
declaration; so the lint requires the declaration rather than inferring it. Its controls are the real
artifacts recovered from git: RED on `0c393936`'s unbounded stamps-dir gate (the 545-refusal scar),
GREEN on `dcf2f11a`'s fix carrying the same predicate and the same `die` with its bound declared.
Same shape, opposite verdicts. The ratchet is a per-file **count**, since a path allowlist would
exempt `ship-land.sh` wholesale and every new gate leg added to it.

### What this does NOT close

- **The C10 ratification** is still the one human decision, and it now has a mechanism waiting for it
  rather than a design document. Filed as an operator step.
- **The 38 legacy queue entries** are not reclassified. Which are still needed is per-item judgment,
  not a mechanical sweep; new wiring goes through `migrations/` instead.
- **F1 remains unrun by construction** — it needs *the next* correct analysis, landed through this
  path. This section is the instrument, not the result.

### The scar this section exists to record

Two sessions built this simultaneously. `cc-backlog` held **two claimed items for one condition** —
`6078392359ac` (this one) and `97f16b6709fa` — because its event key is project+title+source, so two
wordings of one condition hash differently. Both worktrees independently produced a declaration-based
migration runner with a mechanical/operator class split, a new bounded rung between 📦 and 👤 for
landed-but-not-live, fail-open on an unresolvable sensor, and a content-hash escape on the retry
latch. The convergence is real evidence the design is forced; the duplication is pure waste, and it
is the *same defect one level up* — the ledger's dedupe is a permission-style predicate on a
**state record** (a title hash) that rots the moment the same condition is described differently.
A dispatch that leased the CONDITION rather than the row would have caught it. Filed rather than
fixed here: it is the dispatcher's edge, not this document's.

**Closed** (backlog `0bded74c6fa2` → `docs/plans/CONDITION_LEASE.md`). The lease is built, and the
build corrected this paragraph's prescription on one point worth recording, because it is this
document's own thesis turned on itself. "Lease the condition" could not be implemented as written:
`--condition` derives the item **id** from the condition, so two rows sharing one cannot exist —
0 such groups in 1257 add events — and a lease keyed on that field governs an empty population.
The mechanism was *named* and *reachable by nothing*, which is precisely face 2's shape. What was
missing was a verb to join rows that already exist (`cc-backlog link`), and the lease then lives in
`cc-backlog claim` — the actuator that holds the fold one step before the append — not in
cc-dispatch, which would have had to sample-then-act. The obvious automatic key (`dodRef`, which
both duplicates *did* share) was refuted by measurement rather than by argument: replayed over the
ledger's claim intervals it produces 81 concurrent pairs for ~1 real duplicate, and this very
document's dodRef holds a third item (`8e8a306f6dc0`) that is unrelated work — so the signal groups
the duplicate *with* the non-duplicate even in the one case it was derived from. It ships as a
report (`cc-backlog dups`), never as a gate.
