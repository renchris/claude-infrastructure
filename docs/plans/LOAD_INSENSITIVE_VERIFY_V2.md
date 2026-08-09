---
status: open
---

# LOAD-INSENSITIVE VERIFY — R1 was never propagated to the verdict path

**Scope (frozen):** the gate/land/verify path reaches a GREEN verdict and lands within one session
at **≥3.5 load/core sustained** (≤1% idle, ~12 concurrent gate runs), with **zero mechanisms that
wait on load** and **zero thresholds a permanently-saturated box cannot satisfy**.

**Standing constraint (kills lazy designs):** *no quiet period will ever exist.* 20–40 concurrent
sessions and ~12 concurrent gate runs are the **designed steady state**, not an incident. Any design
whose success requires load to fall is already failed.

Status: DESIGN 2026-07-30 · originating session 9b41fe5a · branch `docs/gpu-vs-cpu-lag-2026-07-29`

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS PER WAVE** (added 2026-08-08 — the field was missing, so the waves below were
recorded without the one fact that decides whose context pays for them):

| Wave | Locus | Why |
|---|---|---|
| 1 — T1/T2 suite pinning | **L** (lead-inline) | One mechanical transformation (the same 6-line block at the top of 37 `setup()` bodies), single shared file already single-ownered, and the wave's own load is this document's subject. See §7 for the full judgement. |
| 2 — T3 lint rule | **S** (dispatched session) | Real design work — a second ratchet rule, its grandfather list and its RED-proof. Landed before this session. |

**Lead context budget + succession point:** the lead holds the allowlist and the two plan docs and
nothing else; succession point is immediately after the land, since everything of value is on disk
(commit + this document) and no in-flight judgement survives it.

Three teammates, disjoint file ownership, no `blockedBy` edges except T3's read-only dependency on
the CONTRACT (the pin string `CC_FIRE_CAPACITY_GATE=off`), which is pinned here in Phase 0 — not on
T1's code. Spawn T1+T2 concurrently (wave 1); T3 in wave 2 so it lints a tree that already contains
fixed suites and can therefore RED-proof against real violations rather than synthetic ones.

| # | Teammate | Owns (exclusive) | Deliverable | Wave |
|---|---|---|---|---|
| **T1** | `verify-pin-measured` | `tests/handoff-fire-focus.bats` · `tests/handoff-fire-payload-lint.bats` · `tests/fire-engagement.bats` | Pin the seam in the **3 measured-failing** suites (the 16 tests). Record arm-A/arm-B for each at ≥3.0 load/core. | 1 |
| **T2** | `verify-pin-remainder` | the remaining unpinned `tests/*.bats` that reach a net-new fire (T1's three EXCLUDED by name) | Same pin, same evidence standard. Split into T2a/T2b if >20 files. | 1 |
| **T3** | `herm-lint-load-rule` | `scripts/test-hermeticity-lint.sh` · `tests/test-hermeticity-lint.bats` | C2: second ratchet rule + grandfather list + RED-proof via `git archive` | 2 |

**Contract pinned here (so T3 never waits on T1/T2):** a suite is compliant iff its `setup()` or
`setup_file()` body contains `CC_FIRE_CAPACITY_GATE=off` (export or inline env). Per-test pinning does
NOT count — same rule shape as the existing `$HOME` hermeticity rule, and for the same reason: it
leaves every other test in the file reading ambient state.

**Worktrees:** one per teammate (`isolation: worktree`), all rebased onto this branch. No shared file
between T1/T2/T3 ⇒ no same-hunk conflict class.

**Single owner for the allowlist — the one real conflict risk.** The lint's grandfather list is a
one-line-per-suite block that every teammate would otherwise want to edit, i.e. the append-conflict
shape this repo has been bitten by. Rule: **T1 and T2 never touch `scripts/test-hermeticity-lint.sh`.**
T3 owns it exclusively and reconciles the list LAST, deriving it by reading the tree (`grep -L`) rather
than from T1/T2's reports — disk truth, not handed-down claims.

**Load discipline (this plan's own subject):** cap the wave at 3 concurrent; teammates run their bats
through `bin/cc-bats` (background QoS band) and must NOT run the full corpus — only their own files.
The corpus is the verifier's job, once, post-land.

**Pre-spawn checklist** (per teammate, per CLAUDE.md): brief ≤150 lines · pre-greped line ranges
embedded · no visual verification inline · verbatim "stop on issue, message lead" clause · no
"investigate/explore/audit" language · phase checkpoint or split.

---

## 1. The headline: DO NOT REBUILD. The architecture is already right.

`docs/plans/LAND_PIPELINE_V2.md` (`status: complete`, landed `8d50f953`) already encodes this exact
constraint and already solved the land half:

> **R1** land p50 ≤ 30s, p99 ≤ 3 min, at 12+ concurrent writers, **load-indifferent.**

And the land half **works** — three lands attested `gate_scope=fast` / `verify=ok`, each in seconds.
A ground-up rebuild would re-derive a design that already exists and is landed. Per the method: *if
the new design is the old one with bigger constants, return to Phase 1.* Phase 1 returned this instead:

> **R1 was propagated to the LANDER and never to the VERIFIER's corpus.**

That single omission is the whole blockage. The corpus that decides GREEN contains tests whose subject
consults **ambient machine load**, so on a permanently-saturated box those tests can never pass, the
verifier can never stamp green, `deploy-live --auto` can never open, and every branch stays stranded.

## 2. The causal chain, each link measured

| # | Link | Evidence |
|---|---|---|
| 1 | `capacity_gate()` reads live load and refuses ≥2.0/core | `scripts/handoff-fire.sh:1282-1315`, enforced `:2273`, `exit 9` |
| 2 | Load is permanently above that ceiling | measured this session: **3.39–7.27/core**, 0.0–0.28% idle |
| 3 | 39 of 43 suites invoking `handoff-fire` **never pin** the kill switch | `grep -L CC_FIRE_CAPACITY_GATE` over `tests/*.bats` |
| 4 | So those suites observe a refusal instead of the behaviour they assert | **two-sided control below** |
| 5 | Verifier is fail-closed on GREEN | `postland-verify.sh` is the sole full-suite verdict owner |
| 6 | GREEN is **vanishingly rare** — 1 in 38 | live stamp read: `{red:34, cut:2, green:1, hung:1}`. ⚠️ the inherited "zero green in 34" is STALE — see A4 |
| 7 | `deploy-live --auto` never opens; live layer sat ~48 commits behind | memory `land-pipeline-v2-verdict-inversion` |
| 8 | Work strands | **15+ branches, 43–57 commits each**, incl. `fix/infra-perfection` (55) |

### The two-sided control (2026-07-30, load 3.39/core, same tree, same minute)

```
ARM A  bats tests/fire-engagement.bats
       not ok 14  E2E: an engaged fire (marker in a transcript) prints '→ fired' exit 0
                  `[ "$status" -eq 0 ]' failed          ← capacity_gate refused, exit 9

ARM B  CC_FIRE_CAPACITY_GATE=off bats tests/fire-engagement.bats
       ok 14      E2E: an engaged fire (marker in a transcript) prints '→ fired' exit 0
```

**The only delta is an env kill switch that already ships.** The tree is not red; the *test* is
red-by-load. This is a positive control on the verifier's reds, and it corroborates the independent
one already on record: an operator `--force` deploy ran the same suite class against the LIVE layer
and got **7 of 8 ok + 1 CUT**.

## 3. The inversion

The incumbent frame asks *"is the box quiet enough for this test to pass?"* — unanswerable-by-design
here. The inversion:

> **A test may never consult ambient machine state. The verdict must be a function of the tree alone.**

This is the same shape as the hermeticity rule the repo already adopted for `$HOME` (a suite that
doesn't fixture `$HOME` reads the operator's live state and flakes). Ambient **load** is simply the
second instance of that class, and it went unnoticed because it produces a *plausible* red — a real
assertion failing for a real reason — rather than an obvious environment error.

Corollary already learned and re-confirmed: **relocating a flaky verdict does not fix it.** v2 moved
the corpus's ~2.3% P(green) off the land path onto the deploy gate, which inherited it. *"Not on the
critical path any more"* is false if something else now blocks on it.

## 4. Design — three changes, none of them a rebuild

**C1 — Pin the seam in the affected suites.** Suites that do not assert gate behaviour must set
`CC_FIRE_CAPACITY_GATE=off` in `setup()`/`setup_file()`. Suites that DO assert it
(`handoff-fire-capacity-gate.bats`) keep full control and are untouched. Start with the three
measured-failing (`handoff-fire-focus` 8, `handoff-fire-payload-lint` 6, `fire-engagement` 2 = the 16),
then the remaining unpinned suites that reach a net-new fire.

**C2 — Enforce at the existing chokepoint, do not build a new guard.**
`scripts/test-hermeticity-lint.sh` (402 lines) **already exists and already runs as a verifier
prelint** (`postland-verify.sh:219`). Extend it with a second rule — *a suite invoking `handoff-fire`
without pinning `CC_FIRE_CAPACITY_GATE` is a violation* — reusing its established **ratchet**
mechanism: grandfather current violators by name, bind on new suites, list may only shrink, and the
lint fails if you pin a suite and forget to delete its allowlist line. A lint in its own suite is
detection, not a gate; this one is already on the always-run path, which is why it is the right host.

**C3 — Extend R1 to the verdict path explicitly.** Add to `LAND_PIPELINE_V2`'s requirement table:
*R1b — the VERIFIER's corpus is load-indifferent; no test may read ambient load, and the verdict is a
function of the tree alone.* R1 was true of the lander and silently false of the verifier; naming it
is what stops the next relocation from re-inheriting it.

## 5. Rejected alternatives

| Rejected | Why |
|---|---|
| **Ground-up rebuild of the land/verify pipeline** | The architecture is correct, landed, and its land half is measurably working. The defect is one unpropagated requirement, not a design error. |
| Raise `CC_FIRE_MAX_LOAD_PER_CORE` until tests pass | The lazy design the standing constraint exists to kill. Load is unbounded above; any constant is a future permanent-refuse. Also disables the gate's real production purpose. |
| Disable `capacity_gate` globally in the verifier | Blunt: it would also disable the gate for the suite that legitimately asserts gate behaviour, and hides the dependency rather than removing it. |
| Re-add a waiting/queueing shedder (`gate_admit`) | Deleted and **lint-enforced absent**. A per-call bound multiplied to 21 h of "bounded" waiting; five gates once waited at load 16–18 for a ceiling of 8 while their own corpora *were* the load. |
| Serialize all gate runs | Rejected in `MACHINE_CAPACITY_V2` §6. Does not address red-by-load at all — a serialized run at 3.5/core still fails. |
| Wait for load to drop before landing | **The fallacy this document exists to kill.** Permanent saturation is the steady state. |

## 6. Acceptance criteria — disk-truth reads, not narration

- **A1** `CC_FIRE_CAPACITY_GATE=off` present in `setup()`/`setup_file()` of every unpinned suite that
  reaches a net-new fire — read by `grep -L`.
- **A2** `scripts/test-hermeticity-lint.sh` fails a deliberately-unpinned fixture suite and passes the
  fixed tree — RED-proof against the pristine pre-change tree via `git archive`, never a hand edit.
- **A3** The three measured-failing suites pass **at ≥3.0 load/core** — the arm-A/arm-B control re-run,
  both arms recorded.
- **A4** A verifier stamp reads **green on a tree containing the pin**. ⚠️ **Baseline corrected
  2026-07-30 — re-derived from disk, not inherited.** The memory entry and §2 line 6 of this document
  say "zero green in 34"; that was true when written and is now **stale**. Live read of
  `~/.claude/autonomy/postland/stamps`: **38 stamps = `{red:34, cut:2, green:1, hung:1}`**, and
  `~/.claude/autonomy/postland/last-green` = `34e725d629caf311cb1ea749b0044780bc496860`. So the
  bootstrap deadlock HAS been broken once (backlog #50 closed). The criterion is therefore not
  "first green ever" but **"green on a post-pin tree, and reds falling as a fraction"** — 34 of 38
  are still red, and T1's measurement shows a large share of those were red-by-load.
  (Verified two ways — `json.loads` fold and a raw `grep -ho '"verdict":"[a-z]*"'` — because a
  single parse path can silently drop malformed rows.)
- **A5** `deploy-live --auto` advances the live layer — `git rev-list --count HEAD..origin/main` on the
  deploy checkout goes to 0 (currently **15 behind**). **Never** verify a deploy by symlink presence:
  *"0 unlinked" ≠ "content current"* (a clean link sweep once read green while the checkout was 48
  commits behind).

  🚨 **The CURRENT deploy blocker is a THIRD mechanism, distinct from both of the above — read live
  from `~/.claude/autonomy/postland/deploy.log`:**

  ```
  deploy-live: REFUSED — target 34e725d629ca is not a descendant of live HEAD dd1d55a389a5
               — this would ROLL BACK the live layer
  ```

  The single green stamp is **orphaned**: `34e725d6` is not a descendant of the live HEAD, so
  `deploy-live` refuses it — **correctly**, since deploying it would roll the live layer backwards.
  `deploy-live` walks `origin/main` newest-first for a green commit; the only green it ever finds is
  unusable, and no newer commit carries one. So the gate is not "never opened for want of a green" —
  it is **holding on a green that cannot be applied**, which is a different failure with a different
  fix and would not be found by counting stamps.

  This makes the pin work load-bearing rather than merely hygienic: the requirement is a green stamp
  on a **descendant of live HEAD**, and the capacity-gate reds were the reason no recent commit could
  earn one. Do not "fix" this by forcing the orphaned stamp — refusing a rollback is the gate working.

### A6 — the verdict path's own assertions must be able to FAIL (added 2026-07-31, item `487d9f7c6bd5`)

Pinning the gate (C1) makes the corpus load-indifferent; it does not make the corpus's assertions
*discriminating*. Both halves of T3's filing were swept against disk truth:

**Use the deterministic two-arm control, never ambient load.** `CC_FIRE_LOADAVG_OVERRIDE=<n>`
(`scripts/handoff-fire.sh:1486`) forces `capacity_gate`'s verdict without touching the box, so A3's
arm-A/arm-B evidence no longer needs a loaded machine: arm A `CC_FIRE_CAPACITY_GATE=off` → rc 0, arm B
`CC_FIRE_LOADAVG_OVERRIDE=999` → rc 9, both measured. A control that *waits for load* would itself
violate this document's standing constraint.

- **Selftest case (n) was a dead assertion — FIXED.** `scripts/test-hermeticity-lint.sh` stubs
  `grep() { return 2; }`, then asserted with `printf … | grep -q 'LEAK'` — which inherits the stub's
  rc=2 and can never fire. It was the ONLY live guard on `is_hermetic()`'s fail-SAFE direction: with the
  2026-07-26 incident reinstated in the source, `--selftest` still exited 0 at a green 38/38. Now a
  `case`, per (x)'s precedent. ⚠️ RED-proof needs a **DOUBLE** mutant — `is_hermetic()` (~324) *and*
  `in_allowlist()` (~443) both `return 0`→`1`; either alone short-circuits before the LEAK line, so a
  single-mutant control proves nothing and misreads as "the fix didn't work".
- **"Non-zero status passes on exit 9" — measured, no live instance.** All 131 `[ "$status" -ne 0 ]` in
  `tests/` (one spelling only; 45 in fire-reaching suites) swept. Every one that can reach the gate
  carries a message discriminator; the 19 undiscriminated ones never execute the script top-level at
  all — they `run` either a sourced function (`composer_owned`, `pane_parked_reason`, `it2_split`,
  `spawn`, `originator_liveness`, `resolve_headless_anchor`) or a bare command (`grep`, `mktemp`, `kill`).
  Positive control: `notify-back.bats`'s bare-`--notify-back` test targets line 2859 (post-gate) and DID
  flip to `not ok` under arm B — proving both that it reaches the gate and that its companion grep
  catches an exit-9 substitution. **Structural rule for future review:** an assertion is exposed iff the
  failure it names is raised *after* `handoff-fire.sh:2505` — self-close (`exit 0` at 2460) and the
  payload checks (2496–2502) are all before it, so their suites cannot produce this class.

Kill switches: the change is additive env pins plus one lint rule; `CC_HERM_ALLOWLIST` already overrides
the lint's list, and the new rule ships with its own off seam.

## 6b. Status 2026-08-08 — C1/C2/C3 all landed; A1 met; A4/A5 still open

**C2 — DONE, and it generalised.** Landed before this session. RULE 2 exists in
`scripts/test-hermeticity-lint.sh` with its own ratchet, own allowlist, own kill switch
(`CC_HERM_FIRE_RULE=off`) and its own selftest cases. The mechanism proved reusable: RULES 3-5
(orphan-close lever, selftest scratch path, non-`$HOME` seam) were built on the same shape, so the
"extend the existing chokepoint, do not build a new guard" call in §4 paid off three more times than
it was argued for.

**C1 — DONE this session. The ratchet reached ZERO.** All 37 remaining grandfathered suites now pin
both gate terms in `setup()`, and `EMBEDDED_FIRE_ALLOWLIST` is empty — rule 2 binds on the whole tree
with nothing exempt. **A1 is met**, read from the lint's own verdict, not narrated:
`0 grandfathered (capacity gate)` where it read 37. Four of the 37 (`handoff-fire-account-sweep`,
`handoff-fire-failed-cleanup`, `handoff-fire-repo-resolution`, `handoff-recycle-engagement`) had pinned
per-test only — the shape the rule rejects — and their `setup()` now carries it; the older per-test
pins are left as redundant-but-harmless rather than risk a wider edit.

**C3 — DONE this session.** `R1b` is now in `LAND_PIPELINE_V2.md`'s requirement table.

### The finding that outlived the fix: a capacity-only pin is not load-indifferent

`capacity` and `headroom` are the two TERMS of a **single** refusal — there is exactly ONE `exit 9`
in the script (`scripts/handoff-fire.sh:4487`, `capacity_gate || exit 9`), and `capacity_gate()`
returns non-zero if EITHER the loadavg term or the M10 memory-headroom term is past its bar. Rule 2
only tests the capacity term. So a suite can satisfy the ratchet — and now, with an empty allowlist,
satisfy it tree-wide — while still consulting ambient machine state through memory. Measured
2026-08-08 over the 54 suites that pin at all: **only 14 pin BOTH terms; 40 are capacity-only.**

This is the same class as the original defect and it is worth stating plainly: *the enforcement was
written against the symptom that was measured (load) rather than against the mechanism that produces
it (the gate).* §3's inversion is the wider claim — *a test may never consult ambient machine state* —
and the lint currently enforces half of it. All 37 suites pinned in this pass set both terms, so the
hole does not grow; closing the remaining 40 and widening rule 2's predicate to demand both is filed
as follow-on work, not done here (it is a second mechanical sweep plus a lint-predicate change, and
bundling it would have put C1's landing at risk).

### Deterministic control, per A6 — the instrument had to be positive-controlled first

`CC_FIRE_LOADAVG_OVERRIDE=999` forces the refusal without touching the box. Validated against the
real artifact before any suite verdict was believed:

```
CC_FIRE_LOADAVG_OVERRIDE=999                          … --prompt-file P --dry-run  → rc 9
  "capacity gate: REFUSING a net-new fire — load 999 on 10 cores = 99.90/core > ceiling 2.0/core"
CC_FIRE_CAPACITY_GATE=off CC_FIRE_LOADAVG_OVERRIDE=999 … --prompt-file P --dry-run  → rc 0
```

⚠️ **Two instrument defects were caught by that step, and either would have produced a confident wrong
answer.** (1) The first probe passed `--prompt`, which is not a flag — the script printed usage and
exited 1 *before* the gate, so the gate was never reached and a "no refusal" reading meant nothing.
(2) The rc was read after a pipe into `tail`, so it reported `tail`'s status, not the script's. A
suite that is green in BOTH arms is therefore reported as **NO-REACH (control inert)**, never as a
pass — a control that cannot fail proves nothing about the suite it is pointed at.

### A THIRD channel, found by the verification itself: wall-clock waits sized on an idle box

The 37-suite post-change sweep came back **36 pass / 1 red / 0 non-verdict**. The red was
`tests/teammate-auto-shutdown.bats` → `not ok 15 worktree-by-name: a member-named worktree resolves
via git and IS removed (owned)`, and it is worth writing down precisely because the first instinct —
"a flake, re-run it" — would have thrown away the finding.

It is **not** caused by the pin, and that is provable rather than assumed: the suite asserts no gate
refusal (the only `capacity`/`exit 9` strings in the file are the comment C1 just added), and the pin
can only make the gate MORE permissive, so it cannot manufacture a new failure. It reproduced GREEN
4/4 on the landed tree.

The cause is one line — `tests/teammate-auto-shutdown.bats:381`:

```bash
wait_gone() { local i=0; while [ -e "$1" ] && [ "$i" -lt 60 ]; do sleep 0.05; i=$((i+1)); done; [ ! -e "$1" ]; }
```

**A 3-second wall-clock bound (60 × 0.05s) on an asynchronous `git worktree remove`.** It failed in
the one window where this session's own 37-suite sweep, a sibling's full-corpus run, and
`ship-land.sh`'s stranded-sweep over 547 branches were all running at once. So the assertion is a
statement about **how fast the box is**, dressed as a statement about the tree — which is exactly
§3's inversion, reached through a channel `capacity_gate` has nothing to do with.

That makes **three** distinct channels in this one class, and C1 closes only the first:

| # | Channel | Status |
|---|---|---|
| 1 | `capacity_gate` loadavg term | **closed** by C1 — pinned tree-wide, ratchet empty |
| 2 | `capacity_gate` headroom term | filed `dd76e48db6b2` — 40 suites still capacity-only |
| 3 | **wall-clock waits sized on an idle box** | filed — previously unnamed |

⚠️ **Do not "fix" channel 3 by enlarging the constant.** That is §5's rejected row — *raise the
ceiling until tests pass* — one row down: time is unbounded above under a designed steady state of
20-40 concurrent sessions, so any constant is a future permanent-red, and picking one here would be
guessing. The fix is to make the wait **deterministic** (assert on the operation's own completion
rather than on elapsed time), which is design work, not a constant edit. It is filed rather than
guessed at.

This also sharpens why §2's chain did not predict the whole red rate: pinning the gate cannot fix a
timing bound, so "37 suites were red-by-load" and "89% of stamps are red" were never the same claim.

### `cc-bats`'s exit 75 is what load-sensitivity looks like when it is done RIGHT

Verifying the 37 surfaced the contrast this whole document turns on. A first sweep returned `rc=75`
for all 37 in under a second — which is not 37 reds, and reading it as one would have been the same
error in a new place. `bats` on this box resolves to `bin/cc-bats`, which refuses when concurrent
execution roots exceed `CC_BATS_MAX_ROOTS` AND load/core is over its bar, and says so in words:

```
cc-bats: REFUSED — 3 concurrent bats execution root(s) (ceiling CC_BATS_MAX_ROOTS=2) AND
         1-min load/core at or above CC_BATS_MAX_LOAD_PER_CORE=2.0.
cc-bats: nothing ran, nothing was verified — this is a DEFERRAL, not a test result.
cc-bats: override for this run: CC_BATS_MAX_ROOTS=0 …
```

Both mechanisms read ambient load; only one of them is a defect. `capacity_gate` inside a corpus
suite produces a **plausible RED** — a real assertion failing with a real message — which is exactly
why §2's chain went unnoticed for so long. `cc-bats` produces a **loud non-verdict** that names
itself as one, names its holders, and prints its own override. That is R6 ("a non-verdict is never a
red") holding, and it is the shape any future load-aware mechanism in the verdict path must take:
**if a thing must consult the box, it must be incapable of being mistaken for a verdict about the
tree.** R1b forbids the first shape; it does not forbid the second.

## 7. Open / next

**Still open after 2026-08-08 (A4 and A5 only — both are OBSERVATIONS downstream of the land, not
work):** A4 wants a verifier stamp green on a post-pin tree, and A5 wants `deploy-live --auto` to
advance. Neither can be produced in the session that lands the pin: `ship-land.sh` queues the landed
head to `postland-verify.sh` (:2001-2007) and the launchd singleton `com.claude.postland-verify` owns
the verdict. Live read at land time: **104 stamps = `{red:93, cut:7, green:3, hung:1}`**, and
`deploy-live` REFUSED with a *different* message than §A5 recorded — `no GREEN tree is a DESCENDANT of
live HEAD dec39a391362 (the newest one, 71e96bcbc825, is BEHIND it)`. So the orphaned-green diagnosis
in §A5 still holds in shape while its shas have moved; re-read it live rather than quoting these.
⚠️ Do not read a post-land green as proof the pin caused it, or a post-land red as proof it did not —
the corpus has ~349 suites and this change touched 37. The honest claim is narrower and is already
proven above: those 37 can no longer go red for a reason that is not in the tree.

**Retired as done — kept for the record, since the Phase 0 call was made and should be judged:**

- C1 and C2 are code changes across ~39 test files + one lint ⇒ **Agent Teams**, disjoint file
  ownership, per the standard discipline.
  → **Judged 2026-08-08: correct for C2, over-specified for C1's remainder.** C2 was a real design
  task and got a teammate. C1's remainder turned out to be ONE mechanical transformation — the same
  6-line block at the top of 37 `setup()` bodies — whose only shared file was the allowlist this
  plan had already single-ownered. Fanning that out would have paid 37 briefs and a merge loop to
  parallelise an `awk` script, on the box whose saturation is this document's subject. It was done
  lead-inline instead, and the load discipline below is the reason. The rule the next reader should
  take: **file COUNT is not work SIZE** — what decides the locus is whether the pieces need
  independent judgment, and a mechanical sweep with one owner does not.
- **Tension to flag honestly:** spawning teammates adds load to the box whose saturation is the subject.
  Teammates run in the background QoS band and the corpus is not on the land path, so this is
  acceptable — but the wave should be small and the lint work serialized against the suite work.
- The 15+ stranded branches are a **separate** disposition question once deploy opens; several are
  `ship/backup-*` refs that may be prunable rather than landable. Do not assume stranded = landable
  (a land that never happened and a rejected design leave identical traces — only the originating doc
  distinguishes them).

## 8. Status 2026-08-09 — the verdict path was ACQUITTED; the tree really was red

**The standing conclusion of `da18f179ac50` is REFUTED, and that is this session's main output.** That
item ends *"audit the VERDICT PATH, not the suites — a verifier that cannot distinguish KILLED from
FAILED will stamp red forever on a box that logged 49 kill invocations in one night."* Measured today,
that verifier makes the distinction correctly and the reds it was writing were true.

**The elimination that closes it (the 13th).** Three measurements, none of which re-runs the filed
chain:

1. **A killed run cannot become a red — reproduced.** `timeout -k 10 6 bats a.bats b.bats` over a
   fixture whose second test merely `sleep 60`s exits **124** and its TAP contains **zero `not ok`** —
   only `bats: line 336: … Terminated: 15`. `classify_failures` therefore sees `pairs` empty and
   `notok == 0`, and takes the **CUT** arm. The killed→failed hole the item hypothesised is closed by
   C13/C23/C29 and stays closed.
2. **The convicted population had MOVED.** Not one of the six suites the chain cleared
   (deploy-parity, desk-arm-live, desk-recycle-durable, lr-team-audit, session-continue,
   waiting-recycle) appears in any recent stamp. The live convicts are
   `tests/boot-resume-launch.bats` and `tests/cc-authbrowser.bats`. Any conclusion keyed on the old
   population was reasoning about a set that no longer exists — the `scan-revision-predates-the-fix`
   shape, one level up: it was the *subject* that moved, not the scan.
3. **The conviction reproduces with postland removed entirely.** In a plain detached worktree at
   `origin/main`, a 25-file `bats` run under the same env/QoS band reddens
   `tests/cc-authbrowser.bats:509 [ "$status" -eq 4 ]` — twice, independently — and so does that test
   run **standalone under `-f`**, which is exactly what the retry ladder does. So the red survives
   with the verifier, the corpus, the load and the launchd context all subtracted. **`retries=2` with
   zero flake rows in 87 was the tell all along:** a load artefact produces flake rows; a
   deterministic failure produces none, and this file has never once had one.

**The cause, and it is one line.** `d022242d` (2026-08-08 11:00) deliberately changed the verdict for
an unrecognisable holder on the frozen CDP port from `EXIT_BROWSER` to *fall back to a free port and
succeed* — correctly, because 9341-9344 is also the range this box hands to per-worktree Node
`--inspect` debuggers, and the refusal is why `cc-relogin` phase 2 had never once launched. It
rewrote the FOREIGN-holder test for the new verdict and added three more. **It missed the positive
control one screen below**, which still asserted `[ "$status" -eq 4 ]` on precisely that path. From
that minute trunk was genuinely red, the ladder convicted honestly every sweep, and `deploy-live`
refused for want of a green descendant. Fixed and landed 2026-08-09 (`ba9f6df9` → `11f83bbb`), with
the discriminator moved from the exit code to the **port** — knob wired ⇒ cannot adopt ⇒ a different
port; knob validated-but-unwired ⇒ adopts ⇒ same port — and mutation-proven at its own line.

**The two-sided control, run because the culprit commit denied being one.** `d022242d`'s own message
ends *"41/41 `cc-bats` green; all three new tests go RED on a pre-fix mutant"* — an explicit claim
that this suite passed at that commit. Rather than date the red from a stamp, the assertion was run
at both ends of that single commit, same harness, same box:

```
d022242d^  → ok 1   POSITIVE CONTROL: the wall-clock budgets are PINNED…
d022242d   → not ok 1   … tests/cc-authbrowser.bats:509  `[ "$status" -eq 4 ]' failed
             "port 19341 is held by a foreign process (pids=unknown) … falling back to free port 50133"
```

One commit, both sides, opposite verdicts: the bisect is exact and the red starts at 2026-08-08
11:00. **So the commit's own green claim was false** — `claimed-outcome-vs-checked-outcome`, and a
reminder that a commit message is the author's *intent*, never evidence. Had that claim been taken
at face value the search would have moved past the one commit that did it. **When a commit denies
being the culprit, that denial is the cheapest thing in the investigation to test: two runs.**

⚠️ **This is a FOURTH channel of §3's inversion, and it points the opposite way from the other three.**
Channels 1-3 are tests that consult ambient machine state. This one is a test that consulted a
**stale contract**: the subject's verdict moved and one assertion stayed behind, so it stopped
guarding the property and started guarding the old behaviour (memory
`stale-assertion-becomes-an-inverted-guard`). It is worth separating because the remedies do not
overlap — pinning an env seam cannot help here, and the detector is not a lint over test bodies but
*"which assertions did the commit that changed this verdict fail to visit?"*.

🚨 **The lesson for the next reader of this document, stated plainly: a long, well-evidenced
elimination chain is itself a premise that rots.** Ten hypotheses were killed with real evidence and
the conclusion drawn from them was sound *on 2026-07-27*. What made it wrong on 2026-08-09 is that
its subject — the set of convicted suites — was replaced underneath it on 2026-08-08, and nothing in
the chain re-read that set. **Before spending a session on a filed conclusion, re-measure the thing
it is a conclusion ABOUT.** Here that cost one `ls -t stamps | head` and one grep of `flakes.jsonl`.

**Still open.** `tests/boot-resume-launch.bats::daemon context (no terminal env) + live kitty socket
-> kitty arm` is the remaining convict and it is a genuinely DIFFERENT animal: 10/10 green standalone,
green under `-f` exactly as the ladder runs it, green in postland's own detached cell under
`nice -n 19 taskpolicy -c background` — i.e. not reproducible outside the full corpus. Its one ambient
channel is `BRL_TIMEOUT_S=20` (`scripts/boot-resume-launch.sh:41`) bounding the `bin/cc-kitty-socket`
resolver — an unpinned wall-clock budget in the SUBJECT, which is channel 3 again. C29 cross-window
corroboration already downgrades it to a CUT on some sweeps. Do **not** enlarge the constant (§5's
rejected row); the fix is a pinnable seam in the suite, as `cc-authbrowser` already does for its two
budgets. Filed on `423947ccdb96`.
