---
status: open
---

# VOLUNTARY ACCOUNT SWITCH — a healthy session moves itself to better quota, in place

**Status:** plan frozen 2026-09-22, implementation not started.
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
| T4 | `resident-docs` | `CLAUDE.global.md`, `commands/handoff.md`, `commands/recover.md`, `hooks/boundary-handoff.sh` | Correct the false "cannot become" rule; `switch` mode; the turn-boundary advisory |

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

## 9. Out of scope, filed not driven

Live defects this research surfaced that are independent of the feature. Each needs its own row; do
not fold them into a teammate's diff.

| Defect | Evidence |
|---|---|
| `verdict="RECOVERED"` is an initialiser set before any outcome is read | `lr-fleet.sh:807` |
| `dry-run` / `skipped` fall through `*)` to `verdict=FAILED` | `lr-fleet.sh:1154` |
| Nothing ever reaps a transplant lock — no TTL, no release verb | tree-wide absence |
| A lock-less second hop erases the first hop from custody | `lr-transplant.sh:218-231` |
| The ingest verifier has never returned clean — 3 of 3 read `rc 1`, first failure A6 | `INGEST-VERIFIED.txt` census |
| `claude-accounts:84-88` documents the pre-2026-08-11 survival score, refuted at `:3652-3682` | — |

## 10. Definition of done

- `cc-lr switch` moves this pane's session to a named or routed account, preserving the uuid, and
  reports `SWITCHED` with `from=`/`to=`/`proven=` by mail.
- D1, D2, D3 each have a test that fails on the unfixed subject.
- `CLAUDE.global.md` and `commands/handoff.md` no longer assert that an account change needs a new
  pane.
- Land gate green on the closing commit; landed via the project-local `/ship`; converged to the live
  layer (`scripts/deploy-live.sh`).
- DEC-1 filed as a class-C packet with its conviction, receipt and two measured options.
