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
  deploy checkout goes to 0. **Never** verify a deploy by symlink presence: *"0 unlinked" ≠ "content
  current"* (a clean link sweep once read green while the checkout was 48 commits behind).

Kill switches: the change is additive env pins plus one lint rule; `CC_HERM_ALLOWLIST` already overrides
the lint's list, and the new rule ships with its own off seam.

## 7. Open / next

- C1 and C2 are code changes across ~39 test files + one lint ⇒ **Agent Teams**, disjoint file
  ownership, per the standard discipline.
- **Tension to flag honestly:** spawning teammates adds load to the box whose saturation is the subject.
  Teammates run in the background QoS band and the corpus is not on the land path, so this is
  acceptable — but the wave should be small and the lint work serialized against the suite work.
- The 15+ stranded branches are a **separate** disposition question once deploy opens; several are
  `ship/backup-*` refs that may be prunable rather than landable. Do not assume stranded = landable
  (a land that never happened and a rejected design leave identical traces — only the originating doc
  distinguishes them).
