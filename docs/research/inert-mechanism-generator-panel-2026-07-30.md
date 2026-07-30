# H-INERT-1 — Fable panel: what GENERATES built-but-inert mechanisms

**Date:** 2026-07-30 · **Hole:** H-INERT-1 (`docs/research/FRONTIER_HOLES.md`) ·
**Panel:** 3 × `frontier-derivation` on Fable 5, baseline-blind, read-only, distinct axes
(p1 lifecycle-derivability · p2 separability/atomicity · p3 adversarial-refutation + negative space)
**Lead:** session a78e659d (Opus 5) — briefs carried the system model and component globs ONLY; no
instance list, no prior findings, no ledger. All panel predictions were re-probed by the lead before
filing; the probe results below are the lead's, not the panel's claims.

## Verdict — the panel converged, in three vocabularies, on ONE generator

All three panelists, told nothing about each other or about the five known instances, landed on the
same root cause and the same fix shape. That is convergence evidence, not three opinions.

**The generator: the expectation — "what SHOULD be wired and live" — is never a durable,
machine-readable declaration.** It lives imperatively and redundantly: inside `install.sh`'s glob
loops, inside each activation script's `jq` edits, inside each detector's hand-maintained scope list.
And at the moment of activation it *evaporates* — after `touch <name>.done`, no artifact anywhere
states "event E in config dir D must carry hook H." Consequences, each independently derived:

- **p1**: "*Live* is not uniformly derivable, because the mechanism **population** is defined
  imperatively, not as data." The set of mechanisms is reified for exactly one class —
  `launchd/fleet.manifest`, the repo's own best artifact — and nowhere else.
- **p2**: "*Activation completeness is a predicate over a moving world* (dir-set, script content,
  hook names), **recorded as a point event** (`touch .done`)." Every confirmed silent failure routes
  through a marker keyed on a **name** when the contract is (content-hash × current target-set).
- **p3**: The class **"correct-but-dormant" is closed under adding detectors**, because every
  detector is itself a mechanism in the wiring layer where dormancy lives. Therefore: **where you can
  generate, generating dominates detecting.**

### The sharpest single finding (p3, confirmed live)

**The detection layer for the settings class is un-activated detection of un-activation.** The
recursion *is* the finding. `scripts/settings-drift-assert.sh` is correct, exists, and is wired into
**zero** of the 5 live `settings.json` and zero launchd jobs — while the drift it exists to catch is
live right now. The proposal "add more absence-alarms" was therefore *already tried*: it produced a
correct detector, and the detector joined the dormant population.

## Probes — the lead re-ran every prediction (falsify before filing)

| # | Prediction | Result |
|---|---|---|
| p3-1 / p2-1 | `settings-drift-assert.sh` fires on first real run: exit 1, ≥4 `DRIFT [hooks]`, naming `-quaternary` + `-next`, incl. `operator-readout.sh` missing **only** in `-next` | **CONFIRMED, exactly as predicted** — rc=1; 4 drifts: `cc-unattended-ask-guard`, `session-deregister`, `desk-brief-inject` (missing in `-next` + `-quaternary`), `operator-readout` (missing in `-next` only) |
| p2-4 / p3 | The detection layer is itself unwired | **CONFIRMED** — `settings-drift-assert\|settings-hooks-lint` = **0 hits** across all 5 `settings.json` and all `launchd/*.plist` |
| p2-2 | Live `09-operator-readout-activate.sh` is the PRE-fix version | **CONFIRMED** — `grep -c claude-next` = **0**, though fix `40c6de2f` landed after the `.done` (Jul 25 14:52) |
| p2-3 | The eval track never wires `operator-readout` at all | **CONFIRMED** — `jq` over `~/.claude-next/settings.json` = **0**. The silver-platter close block never renders on the track the script's own header calls "the load-bearing one" |
| p2-5 | launchd labels loaded ≥5 short of declared | **CONFIRMED, worse** — **11 loaded vs 23 declared** in `fleet.manifest` |
| p3-5 | `MEMORY.md` exceeds the loader's ~24.4 KB cap ⇒ every new session starts on a truncated index | **CONFIRMED** — **28,495 bytes**, 2 copies over cap. *This session made it worse by appending 2 index lines before measuring.* |
| p3-4 | ≥1 registry row with a dead pid | **CONFIRMED, far worse** — **57 of 89 rows (64%)** have dead pids. The `kill -0` self-heal story understates this badly |
| p1-5 | top-level `lib/` has no live counterpart (category invisible to actuator AND checker) | **REFUTED as stated** — `~/.claude/lib` exists as a real dir of per-file symlinks. **CONFIRMED in refined form**: `lib/cc-upgrade-gate` is in the checkout with **no live counterpart**, and `config-mirror.zsh.prelink-bak` is live-only cruft. p1 had honestly self-labelled this "[instance unverified]" |

**A probe miss outranks a code finding.** p1-5's literal form failed, so p1's *shared-census* claim is
downgraded from "confirmed instance" to "confirmed structure, one instance found at a different path."
The structural claim survives; the specific blind spot p1 named did not.

## Tagging (reconciled against everything the panel was NOT shown)

**NEW — the frontier delta:**
1. **The detection-recursion** (p3/p2): the settings-class detectors are themselves un-activated. No
   prior doc or memory entry names this; every prior finding treated detectors as working and subjects
   as broken.
2. **"Generating dominates detecting"** (p3): for the settings class the correct move is not detection
   at all — generate all 5 `settings.json` hook blocks from one declaration, after which drift is
   **unrepresentable** rather than detected. Prior work only ever proposed better alarms.
3. **The irreducible residue** (p3): *no in-substrate detector can certify its own delivery.* Every
   alarm chain terminates in a Stop-hook render that is itself a driftable registration — and is
   missing in `-next` right now. The only closure is **inverse polarity on independent hardware**: one
   external deadman whose *absence* the human notices. One suffices; N add nothing.
4. **T8 session-load is never disk-derivable** (p1): open sessions hold a stale settings snapshot with
   no artifact recording which one. Hook *script content* updates live via symlink; *registration*
   does not. Closable only by stamping the loaded-settings hash at SessionStart.
5. **Marker-vs-version skew** (p2): `.done` keyed on a name means a later fix to the activation script
   silently fails to reopen it — the `09` chain above, live.
6. **Atomicity is partly UNDESIRABLE** (p2): "land+activate atomically" would mean the agent activates
   whatever it lands, which dissolves the C10 security boundary. The right model is not a transaction
   but **eventual consistency with a re-evaluated convergence predicate**.

**CONFIRMED (independently re-derived, already known — confidence ↑, not discovery):** `.done` proves
a script ran, never that an effect landed · the launchd-only scope of the effect-read axis · deploy-lag
· the new-file/never-linked class · alarm-fatigue doctrine · the remedy-forbidden-to-receiver shape.

**REFUTED:** "more absence-alarms is the fix" (p3, by live instance) · "no consumer exists" in its
naive form — three sophisticated consumers exist, they are merely dormant (p2) · "activation-without-
implementation is a live class" — preflight convention holds, 0 live instances (p2) · p1-5 as stated
(above) · "the 5 MEMORY.md copies have diverged" — byte-identical (p3) · "`launchd-parity-lint` is
orphaned" — carried by a live but unexpected job (p3).

## Apportionment (p2, quantified)

separability/atomicity **~15%** (mostly deliberate; the already-atomic seam still fails) · absence of a
consumer **~35%** in the *refined* form (consumers exist but are dormant, scope-limited, and addressed
to the actor forbidden to act) · ordering **~5%** (solved by convention) · human gate as a queue
**~25%** (real accumulation; its damage is latency × world-drift) · **~20% residual the four framings
miss** — the point-event-vs-moving-predicate generator above.

## The design the panel converged on

A clean division of labour, not one mechanism:

1. **DECLARE** — one in-repo manifest, extending `fleet.manifest`'s proven grammar to all classes:
   `name | class | expectation-key | effect-probe+polarity | activation-script`, expectation-key
   class-typed (launchd→label; settings-hook→`event|normalized-command|required-dirs`; symlink→repo
   path; copy→path pair; env→var+source). Landing a mechanism undeclared must fail.
2. **GENERATE** what can be generated — the hook blocks of all 5 `settings.json` become a build
   artifact of the declaration, read from an SSOT dir-set **at generate time**. Drift becomes
   unrepresentable. This is the largest single win and it removes work rather than adding a watcher.
3. **RE-EVALUATE, don't remember** what cannot be generated (human-gated `launchctl`, deploy): every
   activation exposes a read-only `--verify` re-evaluating its full postcondition against the *current*
   world, keyed to its content hash so a fixed script auto-reopens. `.done` becomes a cache, never
   truth. Verification is read-only ⇒ agent-legal; only the remedy stays C10.
4. **FAIL CLOSED AT THE LAND GATE**, advisory at runtime — a chokepoint whose death is noticed within
   hours, unlike a Stop hook, whose death is silent.
5. **ONE external deadman** for the irreducible delivery residue. The human is the timeout.

Why this escapes the recursion: `--verify` rides the **already-wired** `activation-watch` (live in 5/5
dirs), so it needs no new activation — it breaks the bootstrap circle from the already-live side.

## Immediate, independently actionable (found by the panel, confirmed by probe)

1. `~/.claude-next` is missing `operator-readout.sh` ⇒ **the silver-platter operator close block never
   renders on the eval track.** The `09` activation is `.done` at a pre-fix version.
2. `MEMORY.md` at 28,495 B is **over the loader cap now** — sessions are running on a truncated index.
3. 57/89 registry rows carry dead pids.
4. 11 of 23 declared launchd labels are not loaded.
5. `lib/cc-upgrade-gate` has no live counterpart.

## Cost

3 Fable-5 panelists (of a 6-spawn session budget), ~19 read-only probes across the panel plus 6
verification probes by the lead. Zero writes by any panelist. Two panelists flagged their own context
contamination (ambient `MEMORY.md` index lines) unprompted and stated which conclusions were derived
before any probe — the honest-labelling the baseline-blind protocol is for.
