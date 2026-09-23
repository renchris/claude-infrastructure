---
status: complete
---

# VOLUNTARY ACCOUNT SWITCH — a healthy session moves itself to better quota, in place

**Status:** plan frozen 2026-09-22; **implementation COMPLETE, landed and live 2026-09-22.**
Every §10 item is on trunk — see §11 for the per-deliverable shas and the test evidence.
The original "implementation not started" is kept in the line above only as the freeze date it
was written beside; it stopped being true the same day.
**Research:** `docs/research/voluntary-inplace-switch-2026-09-22/` (A01–A12, 12 axes).
**Scope (frozen):** a healthy, usually-idle session moves ITSELF to a better-quota account without
leaving its pane — same window id, same session uuid, new account — fired from inside that session.

---

## Phase 0 — Agent Team Orchestration (MANDATORY FIRST SECTION)

### Execution locus per wave

| Wave | Locus | Why |
|---|---|---|
| W1 (engine safety) | **T — in-session teammates** | Three tightly-coupled edits across three files that must be reviewed against each other before any lands; combined diff is small (<400 LOC incl. tests). A dispatched session per file would pay a full context each to move ~40 lines and lose the cross-file invariant. |
| W2 (the verb) | **T** | Depends on W1's `cause` field existing; same team, same worktree, sequenced after W1 merges. |
| W3 (docs + discovery) | **T** | Independent of W1/W2, runs concurrently in W1. |

The **lead is the post-recycle successor of this session**, not this session. This session's last act
is to write this plan and recycle into it.

**Lead context budget:** hold ≥50% for judgment. Succession point: if fill passes 70% before W2
merges, `/handoff` the remainder rather than riding it down.

### Roster

| # | Teammate | Owns (single owner per file — never share) | Deliverable |
|---|---|---|---|
| T1 | `sa-gate` | `scripts/handoff-fire.sh`, `tests/handoff-recycle-remote-resume.bats` | Gate the `ALLOW_LIVE_SA` forcing on cause; un-pin the test that asserts the bug |
| T2 | `transplant-order` | `scripts/limit-recover/lr-transplant.sh` + its suites | Snapshot-after-quiesce; fix the wrong-session rename guard; add `cause` to lock + tombstone |
| T3 | `switch-verb` | `bin/cc-lr`, `scripts/limit-recover/lr-handoff.sh` + their suites | `cc-lr switch` (SELF-only), `--voluntary`, MANIFEST `trigger`/`reason`, verdict vocabulary |
| T4 | `resident-docs` | `CLAUDE.global.md`, `commands/handoff.md`, `commands/recover.md`, the statusline/pane-title surface | Correct the false "cannot become" rule; `switch` mode; **make the account visible on the pane** (§8a) — NOT a Stop-hook nudge |

Max 6 concurrent; we use 4. Every brief ≤150 lines, pre-greped line ranges embedded, verbatim
"stop on issue, message lead" clause, no "investigate/explore/audit" language.

**Required reading in every brief** (do not inline it — point at it):
`docs/research/voluntary-inplace-switch-2026-09-22/A07-clean-code-standards.md` is the binding
house checklist (land-gate invocation, kill-switch-not-enable-flag, rc taxonomy, bash 3.2, the
bare-`shellcheck` rule). A teammate that has not read it will redden the land gate.

### Dependency graph

```
W1: T1 ─┐
    T2 ─┼─► merge ─► W2: T3 ─► merge ─► e2e (operator-gated)
W3: T4 ─┘  (independent; merges any time)
```

`blockedBy`: T3 ← T2 (needs the `cause` field). T1, T2, T4 are mutually independent.

### Worktrees

One per teammate off `origin/main`. Merge back rebase-onto-main, `--ff-only`, serialized,
smallest-diff first. `git rerere` is on globally. **No teammate touches a file another owns** —
`handoff-fire.sh` is T1's alone even though T3 reads it.

---

## 1. What is already true (do not rebuild any of it)

The capability is 80% shipped. Four independent axes confirmed this, and the lead verified each
claim in the code before it entered this plan.

| Fact | Evidence |
|---|---|
| A **fresh-context** voluntary account switch ships and is tested | `recycle_repick()` `handoff-fire.sh:9436-9560`, wired at `:9742`; `tests/handoff-recycle-repick.bats` 25 tests incl. the pressure arm |
| An explicit `--account` on a recycle is honoured and never second-guessed | `handoff-fire.sh:8847`, header `:147` |
| The **session-preserving** self-move is already admitted, deliberately | `lr-handoff.sh:805-810` discards the probe rc; its comment names *"being moved to a fresher account"*; pinned by `tests/lr-handoff-launcher-quoting.bats:630-651`. Landed `e508b2344`, 2026-09-22 |
| The transplant engine is cause-agnostic | 30 of 35 rails read only "a transplant happened"; `lr-transplant.sh` contains no limit predicate at all |
| The ranking lane that encodes the operator's rule exists | `score_interactive` `bin/claude-accounts:3650`, key `1/(1+horizon(weekly_reset_h))` at `:3740` |

**Consequence:** `lr-handoff.sh --target <acct> --launch`, run from a session's own Bash call,
performs a session-preserving voluntary switch **today, with zero code change.** What is missing is
a front door, three safety fixes, and a correction to the instructions that say it is impossible.

## 2. Why no session ever does it — the actual blocking defect

`CLAUDE.global.md:715` tells every session, every turn, that an account change "needs a setup THIS
PANE CANNOT BECOME — a different **account** or **model** (both are launch-time identity)."
`commands/handoff.md:426` repeats it.

Both are false, and the refutation is already written down for the model half:
`docs/plans/NONLIMIT_RESUME_LADDER.md:707-711` — *"A recycle is exit-then-relaunch in the same pane
— a NEW process — so launch-time identity is honoured, not violated."* Nobody corrected the account
half.

No hook can outrank an instruction the model reads every turn. **T4's correction is the
highest-leverage change in this plan and must land first.**

## 3. The three safety defects that are voluntary-only

Each is unreachable when the source is quota-blocked, and reachable the moment it can still take a
turn. That asymmetry is the whole engineering problem.

### D1 — the subagent gate is disabled by the flag the move requires (S1, must not defer)

`handoff-fire.sh:9716-9722` forces `ALLOW_LIVE_SA=1` on every `--transplanted-source` recycle,
justified by *"A limit-blocked lead's subagents died with it."* True of a limit. **False of a
voluntary move**, where a healthy lead's subagents are genuinely running — and they are then
SIGKILLed with no ingest to re-audit them.

Worse, `tests/handoff-recycle-remote-resume.bats:147` asserts the auto-allow **positively**, so the
fix reddens a test that currently pins the bug. Un-pin it deliberately; do not work around it.

**Fix:** gate the forcing on `cause == limit`. Default for an ungated caller is the safe branch.

### D2 — silent transcript truncation

`lr-transplant.sh:245-263` does `cp -p` then sha-verifies src against dst. That proves the copy was
faithful *at copy time*. A blocked session cannot append after that — which is why the check has
always sufficed. A healthy one appends until `/exit` lands, and `/exit` comes later, after a
composer gate that can wait up to 180s (`handoff-fire.sh:12348`). The successor resumes a stale
transcript; the tail is orphaned; the sha check passes because it already ran.

**Fix:** snapshot *after* the source is provably quiesced, not before. Two-phase, per A03: `admit`
before the transplant, `confirm` inside `recycle_fire` immediately before `as_write "$SID" "/exit"`.

### D3 — a third pane renames a live session's transcript

`lr-transplant.sh:271` guards `mv "$SRC" "$SRC.handed-off"` with `CLAUDE_CODE_SESSION_ID != $SID` —
the **driver's** id. Correct when self-invoked. A third pane moving a healthy session is not the
driver, so it renames a transcript the harness is still appending to by path.

**Fix:** key the guard on whether the SUBJECT is live, not on whether the subject is the driver.
This is also why the v1 verb is **SELF-only** — see §5.

## 4. The front door

`bin/cc-lr` resolves refs through `cc-find`, which requires `cf_class == LIMITED` and returns rc 2
otherwise (`cc-lr:267-270`, `cc-find:150-155`). So the existing verb is blocked a layer earlier than
its refusal text suggests.

`bin/cc-lr:202` claims *"every downstream rail (recycle, transplant, tombstone, self-close) is gated
on the quota predicate."* **That sentence is false** (§1) and is itself an instance of the defect its
own header at `:163-177` was written to fix — a refusal bounding the tool, read as a fact about the
world. T3 corrects it in the same diff that adds the verb.

**Design (A01, conviction 88%):** `cc-lr switch` — SELF-only, foreground, no `--source-pane`, no
`--detach`. This is deliberately the mirror of `cc-lr recover`: recover's subject cannot act, so a
detached driver is right; switch's subject **is** the actor. The remote form is also 0-for-9 from a
detached driver (`LIMIT_RECOVER_100P.md:455-476`).

Plus a `switch` mode in `commands/recover.md`, on the `/recover` precedent.

**Not widening `bin/cc-limited`'s census.** The SELF path never enters the class filter, so no flag
threads through cc-lr → lr-fleet → lr-handoff → probe, and the open operator call that `cc-lr:173-176`
warns about is left untouched. The census is an enumerator, not a gate.

## 5. Decisions

### DEC-1 — which ranking lane a voluntary switch asks — OPEN, operator's call

Measured live 2026-09-22 11:4x, three consecutive calls:

```
--rank interactive  →  next4 2.008866 · next3 2.006106
--rank general      →  next3 0.000018 · next4 0.000009
```

Exactly inverted. `interactive`'s sort key **is** the operator's stated rule (soonest weekly reset
with headroom); `general` is `w_rem/T²`. Every consumer asks `general` — `recycle_repick`
(`handoff-fire.sh:9491`), `lr-handoff` (`:417-429`, `:775`), `lr-fleet.sh:726`.

The objection to simply repointing them: `claude-accounts:6176` **refuses** `--rank interactive
--recovery` on the stated grounds that the desk lane picks a human's account, *"not a host for a
transplanted session."* So whether a voluntarily-switched pane is a desk or a transplant host is a
real distinction the code already draws.

**Conviction 72% that `interactive` is right for a voluntary switch** (the pane stays the operator's
desk; nothing about it becomes a background host). Below 90 after this session's research, and the
residue is a framing question, not a missing fact — so it is the operator's, filed as a class-C
packet with both readings and the live measurement attached.

**RULED 2026-09-22 by the operator: the desk rule, SAFE accounts only.** Decision packet
`25d3ac950a9e` (superseding `c616443c9616`, conviction 85%). Research between the two packets
changed the options rather than just the number:

- The objection to the desk rule protected a label, not a check. `claude-accounts` refuses
  `--rank interactive --recovery` because "the desk lane hosts no transplanted session", but
  recovery's survival ceiling is `RECOVERY_S_CEIL = 0.60`, which accounts.json says *reuses*
  `DESK_5H_FLOOR`'s 0.60. Dropping the modifier loses no survival check.
- It exposed a real flaw instead: the desk rule never refuses. When no account is safe it degrades
  and still names one, correct for a fresh launch that must land somewhere, wrong for an OPTIONAL
  move whose alternative is staying put. Hence the gate: accept only tier 2 (5-hour AND weekly
  safe), otherwise `NOTMOVED`, rc 1.
- The lanes still disagreed live at ruling time: desk → next2, general → next4.

Implementation, `bin/cc-lr` `cl_switch_auto_target`: `--rank` (writes nothing, unlike `--route`,
which records a desk decision the desk hysteresis reads), `CC_ROUTE_DESK_HYST=off` (that stickiness
answers "keep the desk where it is", a different question), source account dropped by name and
refused again as a second fence. Limit recovery is untouched and still asks the general rule.
Residual, unmeasured: the 0.6% replay was on freshly launched sessions; a moved session's first,
uncached turn on the target is a 5-hour burst neither rule models. Measured move cost (0.1–0.3 pp
weekly) suggests it fits inside the 60%→85% margin, but that is an estimate.

### DEC-2 — SELF-only in v1, driver form deferred

There is **no idle/busy predicate in this subsystem**. `pane_cc_state` returns `cc` for mid-turn,
idle, modal and wedged alike; the only idle oracle in the tree is a width-dependent screen scrape
(`reso-keepalive:85-95`). A driver cannot establish that a peer is safe to move. A session can
establish it about itself trivially — it is the one taking the turn.

Driver-form voluntary switch is its own decision packet, gated on an idle oracle existing.

### DEC-3 — cause is a FIELD, never a state token

`MANIFEST.trigger` + `MANIFEST.reason`, beside the existing `in_place` flags
(`lr-handoff.sh:637-644`), and `cause` on the lock and tombstone. A new *state* value would fall into
`klass()`'s permissive `return "run"` default and render as in-flight forever (A06).

**Negative invariant, enforced by test:** no state predicate may branch on `cause`. It is there to
gate D1 and to make the artifact readable later — nothing else.

## 6. Verdict vocabulary (A06)

Partition on ACTION, not on a recovery word. `RECOVERED` is false for something that was never
broken — and `lr-fleet.sh:807` sets it as the *initialiser*, before any outcome is read.

`SWITCHED` · `SWITCHED-UNPROVEN` · `NOTMOVED` (source untouched) · `STRANDED` (source retired,
successor absent) · `FAILED`. Mandatory `from=` / `to=` / `proven=`.

`NOTMOVED` vs `STRANDED` is load-bearing: today both hide inside `PARKED`/`PARTIAL` and they demand
opposite actions.

The verdict returns as **mail, not a polling loop**. This is safe across the account change because
the inbox is **pane**-keyed (`mailbox-drain.sh:36`) and every account's `mailbox/` is a symlink to
one directory — a successor on a new account drains the same inbox. Do not key the lane on sid; the
recycle changes it by construction.

## 7. Test architecture

Full design: `A08-test-architecture.md` (20 cases, each with the mutant that kills it).

Non-negotiables:
- **Label equivalence guards as such.** Every transplant/custody case passes before and after; a test
  that passes against both the subject and its mutant proves nothing. Only D1/D2/D3 admit red proofs.
- **Two counted pins will redden** on the obvious implementation: `tests/lr-fleet.bats:320` counts
  `--in-place` occurrences in lr-handoff's argv (so the new flag must not contain that substring),
  and `tests/cc-lr-front.bats:600` is a whole-file count-equality over `bin/cc-lr` for `kill ` vs
  `kill -0`, comments included.
- **Assert the `1..N` plan line.** A gate that refuses to run emits no TAP and exits 0.
- **The e2e goes in `tests/lr-drill.sh` as a sixth session behind `live_do`** — the one door with a
  ratcheted armed-check and provenance stamp, and which no agent may run. `--no-transplant` composes
  with `--print-only` for the safe dry-run.

**Known red on the tree today, not ours:** `LR_STATE_DIR` split store (`lr-handoff.sh:489` vs
`lr-reset-poller.sh:127` hardcoded). Fix the writer or file it — do not ratchet a known split.

### 7a. Gate facts that will bite this subsystem specifically (A07)

The full 45-item checklist is `A07-clean-code-standards.md` and is required reading. These four are
called out here because each one silently *fails to protect* our files:

- **Run `scripts/bash32-parse-lint.sh` by hand.** It is referenced by no `run_gate` arm — it reaches
  a land only through the bats smoke, which is `none`/`skipped` on 84.8% of invocations. Our poller
  plist executes by absolute path under launchd's `/bin/bash` 3.2, so this is the rule most likely
  to kill us off-box and the arm least likely to run.
- **`git-identity-lint` globs `scripts/*.sh` non-recursively**, so every file under
  `scripts/limit-recover/` is outside it. `bin/cc-lr` and `handoff-fire.sh` are inside.
- **Do not mix the two rc taxonomies.** Actuators: `0/1/2-REFUSED/3-usage`. Lints: `0/1/2-NON-VERDICT`,
  where a 2 becomes `GATE_KILLED` (exit 9), never `gate_red` (exit 6).
- **Never write `kill -9` even in a comment** in `bin/cc-lr` — `tests/cc-lr-front.bats:599` counts
  occurrences across the whole file, comments included.
- **`scripts/limit-recover/com.reso.lr-reset-poller.plist` has no `fleet.manifest` row**, because
  `fleet-manifest-lint` scopes to `launchd/com.{claude,chrisren}.*.plist`. A loaded launchd job
  invisible to the manifest lint is a gap worth a row, not a thing to fix inside this diff.

Single command covering most of the checklist: `bash scripts/ship-land.sh --precheck --working`.
Enumerate the gate's real arms with `grep -n '^  # ── ' scripts/ship-land.sh` — there are 21, not
the "fifteen" its own header claims.

## 8. Discovery (A09)

The trigger is a **non-event**: nothing errors, so a description can only be the landing page. The
push must be a hook.

`recycle_repick` is a *passenger*, never a trigger — it runs only when a recycle is already
happening, and every recycle trigger keys on context fill or interruption. The precise hole:
`waiting-recycle.sh` floors its idle threshold at `T_IDLE_FLOOR=25`, so a session idle *below* 25%
fill — exactly the one for which a switch is free — never recycles.

**Carrier: `hooks/boundary-handoff.sh`** — already registered (Stop, latched), so no `c10` migration
and no operator step. One bounded `claude-accounts --rank` call yields exclusion, scores and
`repick_ratio` together. Factor the read into `hooks/lib/` so actuator and advisory share one
predicate.

*(Do not propose a new hook registration. `recover-inject.sh` (migration 0026, 18/18 tests) and
`net-recover-arm.sh` (0030) are both landed and still absent from the live `settings.json`.)*

**Autonomy:** advisory-then-agent for a session's own pane (F1–F4 pass; precedent `/frontier-run`);
advisory-only for a peer's (auto mode's classifier denies acting on a live peer session). Arming an
unattended switching loop stays the operator's.

> **PREMISE GATE — §8 only.** A12 tests whether an idle session's residence costs anything at all.
> If it does not, the *advisory* is unjustified and T4 ships the docs correction without it. The
> verb and the safety fixes stand either way: they are correctness work on a path that is already
> reachable and already used.
>
> **RESOLVED 2026-09-22 — PREMISE FAILS. The advisory is CUT.** Gate text kept verbatim above
> because the reasoning is what justifies the cut. See §8a.

### 8a. The advisory is cut, and what replaces it (A12, measured)

| Measurement | Value |
|---|---|
| Whole addressable population, 6 weeks, **perfect foresight** | **66 bursts / 35.5 pp ≈ 1.5%** of fleet weekly capacity |
| Strand with **no donor account** (nothing walled anywhere in the final 72 h) | **290 of 335 pp = 86.6%** — relocation is arithmetically incapable there |
| A10's own check (idle @T−6h → >50k tokens) | 17 / 435 = **3.9%**, and all 17 were *already on* the expiring account |
| Strand vs demand | stranding windows moved **85.6 M** tokens vs **142.4 M** in windows that reset at 100%; `corr = −0.602`, n=19 |

**Strand is a demand problem, not a distribution problem.** The fleet oscillates between nobody
working (all four accounts strand together) and everybody walled (221.8 account-hours at 100%, 126
genuine weekly-limit refusals). The middle state — where a mover could help — is the 13.4% minority.
An automatic advisory optimising a 1.5% ceiling, against a leader that changes every 6.5 h with a
median dwell of 1.3 h, would fire constantly and chase its own tail.

**Two things A12 refutes in A10, both in the feature's favour:**
- The cost objection is wrong by ~100×. A move costs **0.109 pp** median (0.315 pp at the largest
  transcript seen), because any session idle over an hour pays the cache-cold re-ingest **in place**
  anyway — cold-share is 0.3% under 1 h and 93.7% over it (`ephemeral_1h` TTL).
- "It could have been started fresh on the target" fails: **~75% of post-idle work is continuation**
  a new session cannot reproduce. That is precisely what the context-preserving verb buys, and it is
  why §4 survives this gate.

**What replaces the advisory — T4's revised deliverable.** A12's keeper finding is not about moving
anything: **60.6% of substantial post-idle work lands on a non-perishable account**, because the
operator types into whichever pane is in front of him and cannot see which account it is on. That is
a *labelling* defect, and it is addressable where he is already looking.

T4 therefore ships: the resident-instruction correction (§2), the `switch` mode in
`commands/recover.md`, and **the account made visible on the pane itself** — statusline or pane
title, whichever the existing surface supports without a `c10` migration. It does **not** ship a
Stop-hook nudge to switch.

*Kept as the honest residual:* whether a moved pane *creates* demand is UNDECIDABLE without the
randomized arm A10 asked for. If it does, the 1.5% ceiling is a floor instead — but nothing in this
plan should be built on that hope.

## 9. Out of scope, filed not driven

> **DISPOSITION, 2026-09-22 (closing session).** This section named six defects and said *"each
> needs its own row"* — and **no row existed for any of them** until this record was written, so §9
> asserted a disposition nobody had executed. That is the §9 failure mode in miniature: a table of
> real findings is not a queue, and nothing on this machine reads a plan for unfinished work.
>
> Three were small enough that filing them would have cost more than fixing them, so they were
> **DRIVEN** — in their own commit, never folded into a teammate's feature diff, which is what this
> section actually forbids. Three are genuine design work and are now **FILED** with ids. The
> per-item verdict is in the right-hand column below.


Live defects this research surfaced that are independent of the feature. Each needs its own row; do
not fold them into a teammate's diff.

| Defect | Evidence | Disposition (2026-09-22) |
|---|---|---|
| `dry-run` / `skipped` fall through `*)` to `verdict=FAILED` | `lr-fleet.sh:1154` | **DRIVEN.** Confirmed live, and it is §6's defect one layer down — a verdict naming the ACTUATOR's exit rather than the ACTION's outcome. Unfixed, a `--dry-run --detach` mailed `verdict=FAILED rc=0 … mech=dry-run` (that string is the red proof's own failure output). `DRYRUN` and `SKIPPED` now have arms; FAILED keeps meaning *attempted and broken*. Red proof + a labelled equivalence guard in `tests/lr-fleet.bats`. |
| `claude-accounts:84-88` documents the pre-2026-08-11 survival score, refuted at `:3652-3682` | — | **DRIVEN.** The help text reproduced the refuted **C4** argument verbatim while the function's own docstring calls it MEASURED FALSE. It matters here specifically: the operator ruling **DEC-1** would naturally read this text about the very lane in question. Also added `interactive` to the `--rank` help line — a real, working lane that line omitted. |
| `verdict="RECOVERED"` is an initialiser set before any outcome is read | `lr-fleet.sh:807` | **DRIVEN**, with its limit stated: now empty-initialised and assigned explicitly in `0)`, so it is fail-closed. **No red proof** — every arm assigns today, so no input separates the two versions; the defect is a claim about the arm nobody has written yet. |
| Nothing ever reaps a transplant lock — no TTL, no release verb | tree-wide absence | **FILED** `4f8c73bbdb35`, then **DRIVEN 2026-09-23**: `scripts/limit-recover/lr-lock.py` (`list` / `status` / `release` / `reap`). The TTL is on EVIDENCE, not on age, because the lock is also the custody record `lr_tombstone_verdict` reads — an age-only TTL would disarm the 24c9955d6c4f guard on every long-quiet successor. Each lock is classified from disk: `ORPHAN` (owner holds no transcript) and `ABANDONED` (source written after the move, successor never) expire past `LR_LOCK_TTL_S` (6 h, above the reaper-horizon floor); `QUIET` is release-only; `CUSTODY` / `SPLIT` / `UNPARSEABLE` need `release --force`. Release archives into `locks/released/`, never deletes. `lr-reset-poller.sh` applies the TTL each tick (`LR_LOCK_REAP=off`); both `lr-transplant` refusals name the verb. Red proof + age-only-TTL mutation controls: `tests/lr-lock.bats` (13). |
| A lock-less second hop erases the first hop from custody | `lr-transplant.sh:218-231` | **FILED** `ac7bdd4b2f9d`. **DRIVEN 2026-09-23:** with no lock, the hop now walks the `<sid>.HANDOFF.json` tombstones backwards across `LR_CONFIG_DIRS` (default: the five config dirs) and prepends each proven predecessor, taking `ts_first` from the origin tombstone and marking the lock and receipt `custody_from:"tombstones"`. An ambiguous predecessor (two tombstones naming one store) stops the walk; nothing is invented. Red proof plus three guards in `tests/lr-transplant.bats` (the red proof also checks C3 still passes the FIRST hop's bundle). |
| The ingest verifier has never returned clean — 3 of 3 read `rc 1`, first failure A6 | `INGEST-VERIFIED.txt` census | **FILED** `1c4905d6b2ff` — an investigation (is the verifier wrong, or the ingest?), not a fix. **ANSWERED 2026-09-22: the INGEST was wrong.** No writer ran on the self/explicit-`--in-place` paths, and every bundle came from one of those (0 `probed` records in 7 state logs). Cured by `a30670d8` + `e508b234` + `22ae2a1f`, all on trunk. Verdict, evidence and residuals: `docs/research/lr-ingest-verify-a6-verdict-2026-09-22.md`. |

## 10. Definition of done

- `cc-lr switch` moves this pane's session to a named or routed account, preserving the uuid, and
  reports `SWITCHED` with `from=`/`to=`/`proven=` by mail.
- D1, D2, D3 each have a test that fails on the unfixed subject.
- `CLAUDE.global.md` and `commands/handoff.md` no longer assert that an account change needs a new
  pane.
- Land gate green on the closing commit; landed via the project-local `/ship`; converged to the live
  layer (`scripts/deploy-live.sh`).
- DEC-1 filed as a class-C packet with its conviction, receipt and two measured options.

---

## 11. Completion record (2026-09-22) — every §10 item, with the sha that carries it

Verified from trunk by a dispatched session on 2026-09-22, tree at `origin/main` (`HEAD..origin/main
= 0`, not shallow). **Nothing in this section was re-derived** — each row was read out of
`origin/main` and each suite was RUN this turn, not recalled.

| §10 DoD item | State | Evidence |
|---|---|---|
| `cc-lr switch` moves this pane's session, preserving the uuid, verdict by mail | **DONE** | `cmd_switch` `bin/cc-lr:408`, dispatched `:759`; `22ae2a1f3` |
| Verdict vocabulary with mandatory `from=`/`to=`/`proven=` | **DONE** | `lrh_verdict` `lr-handoff.sh:531`, tokens documented `:494-508`; `22ae2a1f3`, follow-up `9f72d0b52` |
| **D1** subagent gate no longer force-disabled by a voluntary move | **DONE** | `handoff-fire.sh:9829` gates the forcing on `RCY_TRANSPLANT_CAUSE = limit`; `eb7bcc87e` |
| **D2** snapshot after quiesce (two-phase `admit`/`confirm`) | **DONE** | `lr-transplant.sh` `--phase admit\|confirm`, confirm block `:174`; `d219d4eec`, `eb7bcc87e` |
| **D3** retirement keyed on the SUBJECT, not on the driver | **DONE** | `lr-transplant.sh:413-438` — the old `CLAUDE_CODE_SESSION_ID != $SID` guard is named and replaced; `d219d4eec` |
| D1/D2/D3 each have a test that fails on the unfixed subject | **DONE** | `RED PROOF (D1)` ×2 + `RED PROOF (D2)` `tests/handoff-recycle-remote-resume.bats:181,189,213`; `D3 RED PROOF` `tests/lr-transplant.bats:88` |
| `CLAUDE.global.md` + `commands/handoff.md` no longer say an account change needs a new pane | **DONE** | `CLAUDE.global.md:716` now names only the **model** as launch-time identity; `commands/handoff.md:429`; `0812e878e` |
| §8a — the account made visible on the pane (replaces the cut advisory) | **DONE** | `statusline.sh:417-427`, which cites A12's "60.6% of post-idle work lands on a non-perishable account" as its reason; `bbf753d0e` |
| DEC-1 filed as a class-C packet with conviction, receipt and two measured options | **DONE** | packet `c616443c9616`, `status: open`, `conviction: 72`, receipt carries the live `--rank interactive` vs `--rank general` inversion. **Still the operator's — correctly so; the DoD asked that it be FILED, not answered.** |
| Land gate green; landed via project-local `/ship`; converged to the live layer | **DONE** | all shas above are ancestors of `origin/main`; `wrap-ledger.sh --machine` reads `LIVE=1 LIVE_SRC=ok LIVE_LAG=0 LIVE_ADDS=0` |

**Suites run this turn** — plan line asserted on each, because a gate that refuses to run emits no
TAP and exits 0 (§7):

```
tests/cc-lr.bats                          1..15   0 not ok
tests/cc-lr-front.bats                    1..50   0 not ok
tests/lr-transplant.bats                  1..28   0 not ok
tests/handoff-recycle-remote-resume.bats  1..44   0 not ok
tests/handed-off-session-guard.bats       1..15   0 not ok
```

### Why this section exists at all — the stale-frontmatter defect it closes

This plan's frontmatter read `status: open` and its body read *"implementation not started"* while
all four teammates' work sat on trunk. That is not cosmetic: `find-plan.sh:108` excludes only
`complete`/`superseded` from the open list, and `plan-phase-scan.sh --falsify` retracts a
`plan-open` backlog row on that same frontmatter (arm (a), `:96-102`). So the record's staleness was
**re-minting this row into the dispatch wave** — a worker was spent re-reading landed work, which is
the `a50e6ab779e8` shape ("advance README hero banner", twelve days after the banner landed) the
dispatcher's own brief warns about. The lesson generalises: **a plan's completion is a fact its
frontmatter holds, and nothing else on the machine updates it** — the land does not, the gate does
not, `/ship` does not. Marking it is the last step of the work, not bookkeeping after it.

### Residue, stated rather than hidden

- **DEC-1 (`c616443c9616`) is open and stays the operator's.** `switch` therefore routes on the lane
  every existing consumer asks (`general`). If the operator rules for `interactive`, the change is
  one argument at the `claude-accounts --rank` call site — no structural work is waiting on it.
- **§9 is now discharged, three driven and three filed** (`4f8c73bbdb35` and `ac7bdd4b2f9d` driven 2026-09-23 — five driven, one filed) — see its own table for the per-item
  verdict. None of the six had a row before this session, so §9 had been asserting a disposition
  nobody executed.
- **`verdict=""` in `lf_one` carries no red proof** and is flagged as such above rather than
  dressed up with a test that cannot fail.
