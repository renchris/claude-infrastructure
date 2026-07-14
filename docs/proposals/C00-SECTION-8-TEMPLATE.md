# §8 — Session-Orchestration Layer (C00-class template)

**Proposal.** Append this section to a platform build's `C00-orchestration.md` (or equivalent). It is
the layer C00 §0–§7 never had: §1–§7 orchestrate **teammates inside one session**; §8 orchestrates
the **lead/session layer above them** — which account/model/effort each wave's LEAD runs on, its
context budget + succession trigger, the inter-wave write-fence, the back-channel topology, and the
pre-batched operator gates. Closes root cause **R4** (`docs/research/W0-W3_INTERVENTION_AUDIT.md` §5):
*"C00 specifies the teammate layer rigorously; the session/lead layer was improvised live."*

> **§8 ≠ Phase 0.** Phase 0 (`~/.claude/CLAUDE.md`) is *generic teammate* orchestration; C00 §1–§7 is
> its per-build instance. §8 is the *session* layer — build-specific (which accounts, which stamp),
> so it lives in the per-build spec, not a global rule.

**Usability today.** Every field has a **manual mode** (hand-run the named command) and an
**automated mode** (the primitive that will run it). Fill §8 by hand now; it upgrades as
`docs/research/SESSION_AUTONOMY_RESEARCH.md` primitives land. Effect-verification is the rule
throughout: validate against `ps`/`git`/live telemetry, **never a config file or a status report**
(audit §7 — every config, effort file, mailbox, and `isActive` flag lies on 2.1.183).

> 🚨 **Doc-authoring rule — PANE IDS (learned the hard way, 2026-07-14).** This template, the plan, and
> every filled instance are the **copy-source** for the briefs a wave spawns. A truncated pane id written
> here propagates into every downstream brief and breaks the succession that copies it. Two shapes, and
> never a third:
>
> | Use | Write | Why |
> |---|---|---|
> | **operational** (a send target) | a **ROLE token** — `<orchestrator>`, `<wave-lead>` — resolved at SEND-TIME | panes are epoch-specific; any uuid written here is stale the moment that session recycles |
> | **historical** (a status-log fact) | the **FULL uuid**, marked as a past fact | full-but-stale fails LOUD and recoverably (mailbox fallback); **truncated fails exit 3 — unresolvable, unmailboxable** |
>
> Enforced by `scripts/pane-id-lint.sh` (an 8-char prefix is a hard error; declare a genuine
> non-pane id or an intentional counter-example with a `pane-id-lint:allow` marker). It is a grep and
> not a paragraph on purpose: the author who introduced the original truncation **knew** the full uuid.

---

## §8.0 — Indexing

One **row per wave**, each naming its lead-session assignment **and** intra-wave succession sub-rows
(a lead can span waves; a wave can span leads — keep both). A wave row is not cut until its **§8.8
readiness checklist** passes.

## §8.1 — E1 · Lead-session placement

| Field | Fill | Manual mode | Automated by |
|---|---|---|---|
| account | `next` / `next2` / `next3` / `next4` | `claude-accounts --rank general\|fable` | `cc-wave-plan` (axis d) |
| launcher | `claude-<account>` (`--model fable --probe` for Fable) | — | — |
| model | `claude-opus-4-8` / `claude-fable-5` | SSOT `~/.claude/model-config.yaml` | — |
| effort | `max` / `xhigh` / `high` | — | — |

**Validation (effect, not config):** after spawn, `ps -eo command | grep -- "--model\|--effort"` on
the lead's process MUST match the declared row. ⚠️ **D2 unresolved:** per-member teammate effort may
be INERT on 2.1.183 (the Agent tool forwards the *lead's* `--effort`) — so **the lead's effort sets
the whole wave**; resolve empirically with the `ps` grep on the first spawn, never trust
`settings.local.json`.

## §8.2 — E2 · Context budget + succession trigger

| Field | Fill | Notes |
|---|---|---|
| `start_clean` | ≤25% | target fill when the lead begins the wave |
| `mid_soft` | ~50% | accumulate on the same task (rely on in-session knowledge) |
| `boundary_recycle` | ~60% | hand to a successor lead AT the next committed+green boundary |
| `hard_handoff` | ~73% | ceiling — fires before the ~83.5% auto-compaction trigger |

**Window-relative % only — never fixed tokens** (47% of 1M ≠ 47% of 200K; a fixed threshold throws
away ~85% of a 1M window — audit §3b). §8 **declares** the numbers; the advisory boundary hook
(axis h) **consumes** them at `(a) committed+green ∧ (b) log-head==HEAD ∧ (c) used_pct≥threshold`,
one-shot-latched, never mid-slot. **Manual mode:** the operator/lead reads `cc-context --me` (or
`cc-context <sid>`) at each boundary and hands off when past `boundary_recycle`. On 1M windows the
binding constraint is **rot, not fill** — also hand off on repeated spec re-reads even below
threshold (axis g).

## §8.3 — E3 · Write-fence inter-wave handoff

- **Emit (wave N exit):** the departing lead bundles atomically — the batched ruling, the **stamp
  commit** that lands the ratification (e.g. `Ratified-By: operator`), the successor pane UUID, and
  the `handoff-fire.sh self-close --successor <uuid>` command (the mandatory succession statement).
- **Receive (wave N+1 entry):** `write_fence: ancestor(<priorStampSha>, integration)` — the incoming
  lead may read/plan but MUST NOT `git worktree add` / spawn teammates / write `integration` until
  `git merge-base --is-ancestor <priorStampSha> integration` returns true.
- **Why:** teammates branch off `integration` at spawn; spawning before the ratification stamp lands
  makes every teammate re-litigate the just-ruled deviations off a pre-ratification base.

## §8.4 — E4 · Placement-plan source + staleness

The E1 placement is a **snapshot** of the axis-d scheduler's output (`{account, launcher, model,
effort, cap≤2/account, window-expiry-ts}`), NOT a live re-rank per spawn (`--account auto` "cannot see
tracks that haven't STARTED yet" — piles a wave onto one account). Store the **recompute predicate:**
re-run the scheduler for the *next* spawn iff (a) a model window crosses `window-expiry-ts` mid-wave,
or (b) any account crosses its headroom floor. **Manual mode:** rank once (`claude-accounts --rank`),
assign explicitly round-robin ≤2/account, re-check before each new wave.

## §8.5 — E5 · Back-channel topology

| Edge | Primitive | Notes |
|---|---|---|
| teammate → wave-lead | mailbox, **pull-verified** | `cc-sessions` liveness before trusting; teammate→lead is the reliable direction |
| wave-lead → orchestrator | `cc-notify <orchestrator>` (ROLE — resolve at send-time) + **R-PING armed** (`--notify-back`) | on wave-exit; pair with background `cc-await-ping`. Never a cached uuid: the role outlives the pane |
| orchestrator → wave-lead | `cc-notify` (the ONLY sanctioned send) | never raw osascript; submit-verified (exit 4 = strand) — **verifier fixed `3b12107`; it was INERT before, see below** |

Binding corrections (must land before a merge gate) go via a **durable ruling file + commit-sha ack**
(`Acked-Ruling:<id>`), fail-closed at the merge gate — never a best-effort `SendMessage` (downward
mailbox is unreliable; auto-compaction wipes a composer instruction). Prefer **respawn-at-boundary
with the ruling in the brief** over mid-stream correction.

**Addressing (never cache a pane uuid across a succession):** resolve the CURRENT role-holder at
SEND-TIME — role→pane indirection via a succession-maintained roles file (`role=<pane>` rewritten on
each self-close) or the newest self-close-log `successor=` chain. A predecessor's pane is dead
post-self-close; a cached uuid sends into the void. `cc-notify`'s LOUD-on-strand (mailbox-only +
"unreachable", never false-delivered) is the effect-verified backstop when a stale address is used.

> 🚨 **Write pane UUIDs in FULL — an abbreviated id does not resolve.** Every succession brief, ruling,
> and status log MUST carry the complete uuid (`99261468-A46A-498A-AE9B-F39473E5E7AE`), never the 8-char
> prefix (`99261468`) <!-- pane-id-lint:allow: quoting the bad form to teach it --> that iTerm2's UI,
> this corpus, and human shorthand all default to. `cc-notify`
> resolves **only** {registered friendly name | FULL uuid} → a prefix hard-fails **exit 3**, and the
> friendly-name fallback does not exist yet (the session registry is EMPTY until **P8** is wired). On
> 2026-07-14 this broke a successor's *mandated first action* — the announcement that tells the
> orchestrator where the role now lives — i.e. the one send a succession cannot afford to lose. It failed
> LOUD (never false-delivered), and the recovery is a 30-second prefix-expand against `it2 session list`,
> but the failure is 100% avoidable: **full uuid, always.** (Queued fixes: teach `cc-notify` to expand a
> unique prefix — the abbreviated form is the human form, so pretending otherwise guarantees recurrence —
> and land P8 so names work at all.)

> ⚠️ **Trust boundary between the two tiers (audit §3g).** `cc-notify`'s submit-verifier was **inert for
> ~24h** (an it2 capture is binary; BSD grep needed `LC_ALL=C` to read it) — every send in every session
> reported `submit UNVERIFIED` while the ~1-in-6 composer strand went unwatched, and the orchestrator was
> quietly **hand-capturing panes after each ruling** to compensate. Fixed + effect-checked (`3b12107`), but
> the design lesson stands: **NOTIFY is best-effort and its "verification" is only as trustworthy as the
> last time you saw it FIRE.** Load-bearing rulings ride **BIND** (durable ruling file + `Acked-Ruling:`
> trailer + fail-closed merge gate), whose failure detector is **absence-of-ack** — the one signal that
> needs no verifier of its own.

## §8.6 — E6 · Gate-batching manifest

The operator **pre-signs ruling CLASSES at wave START** (formalizing "RATIFY ALL 7"). In-class →
auto-ratify + stamp (`Ratified-By: operator (pre-signed class Cn, manifest <ref>)` — auditable);
out-of-class → STOP-ASK, never silently absorbed. Pre-signable classes {C1–C5, C7}; conditional {C6
money-path = out-of-class by default, C8 next-wave-go}; **C9 `/ship` = permanent exclusion + retro
backstop.** 5-gate discriminator (`G-cite`, `G-shape`, `G-reversible`, `G-surface`, `G-manifest`;
`G-cite`/`G-surface` are un-fakeable greps). See `SESSION_AUTONOMY_RESEARCH.md` §3.4 (axis c).

## §8.7 — E7 · Lead-session isolation

Each **concurrent LEAD session** (wave-lead, orchestrator, overlapping successor) runs on its OWN
worktree/branch — not only teammates. Never a bare `git commit` from a session sitting on another's
branch (the `dfacccd` silent-drop incident). Carry the placement carve-outs (e.g. `NEVER write
<sibling repo>`). Validation: `git worktree list` shows one distinct worktree per live lead.

## §8.8 — E8 · Session-spawn-readiness checklist (the session-layer analog of C00 §7)

Run before cutting each wave's lead — a missing box HALTS the cut (ship as
`scripts/session-spawn-readiness.sh`):

- [ ] **E3 fence cleared** — `git merge-base --is-ancestor <priorStamp> integration` = true
- [ ] **E4 placement fresh** — ranked this wave, ≤2/account, model-window not closing mid-wave
- [ ] **E2 threshold declared** — `boundary_recycle`/`hard_handoff` set for this lead
- [ ] **E5 UUIDs registered** — orchestrator + successor pane UUIDs known; R-PING armed if staggered
- [ ] **E6 manifest signed** — operator pre-signed the in-class ruling set for this wave
- [ ] **E7 worktree isolated** — this lead on its own worktree/branch
- [ ] **E1 effort verified** — `ps | grep -- --effort` matches declared (D2 arbiter)
- [ ] **Dispatch/seam completeness** — every registered stage / surface / handler names BOTH its
  implementation slot AND the slot that lands its **runtime registration** (the dispatch wiring), not
  just implementation. The **plan-layer analog of the single-owner file table**: single-owner prevents
  file-ownership gaps; this prevents runtime-registration gaps. (W4 finding, 2026-07-14: S1–S6 stage
  *runners* were built but never dispatch-registered — the stage slots closed before the dispatch
  surface existed; the gap survived spec-freeze + 4 waves, caught only at the W4 driver plate-bank,
  fixed by an operator-approved R6 +1 spawn. A registered-but-unwired surface is invisible to an
  implementation-ownership table — only a completeness sweep over the dispatch surface catches it.)

## §8.9 — E9 · Telemetry binding + self-cost

The session/supervisor reads `cc-context --me --quota` (context fill × account headroom in one read).
The orchestration layer's own footprint is bounded (shell-side = 0 model quota; injection 1:1-replaces
a human turn) **conditional on 3 guards**: one-shot latch (boundary hook), effect-verified debounce
(supervisor), timeout-no-wake (`cc-await-ping`). See `SESSION_AUTONOMY_RESEARCH.md` §3.6/§3.1 (k, a, m).

---

_Companion: `W4-W5-SESSION-ORCHESTRATION.md` (a filled instance). Full derivation +
per-primitive spec: `docs/research/SESSION_AUTONOMY_RESEARCH.md`. This template is a PROPOSAL for a
platform build's own C00 spec — NEVER write it into a sibling repo you don't own._
