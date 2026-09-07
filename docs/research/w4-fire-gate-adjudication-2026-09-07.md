# W4 · the spawn economy — adjudicated against trunk, 2026-09-07

Backlog row `1b00d62958a6`, condition `master-fire-gate`, DoD `origin/main:docs/plans/MASTER_FIRE_GATE.md`.
Filed 2026-08-12; **28 days old, and nothing had re-read it since.** This is that read.

**Headline: three of the four claims in the row's title are refuted on today's tree, the fourth is
half-true, and the plan's own prescribed remedy for the fourth is a trap that would blind two
downstream arms.** One code change landed here; the rest of this document is the disproof, which is
the deliverable the dispatch brief asked for.

Method: `HEAD..origin/main` = 0 (this worktree IS trunk) and the dispatcher blob that composed the
brief equals `origin/main:bin/cc-dispatch`, so every read below is a trunk read and the dispatcher
that fired the work was current. Four independent read-only adjudicators, one per sub-wave, plus
direct verification of every claim relied on.

---

## The four claims, as filed vs. as measured

| # | Claim, 2026-08-12 | Measured 2026-09-07 | Verdict |
|---|---|---|---|
| F1 | 248 live rows carry no venue label; `cc-venue run` is open-only | 147 unlabelled, **144 blocked and 3 open**; dispatch-relevant population is **4** | REFUTED on the number; residual is 4 rows |
| F2 | `cc-cloud retire` forward-only: **0** `.retired` across 41 declarations | **666 `.retired`** across 687 declarations; 79 `.returned`, 74 of 79 retired within 0–2 s | REFUTED |
| F3 | four spawn paths fire into a dispatch worktree without claiming | still true of the four paths, but **three cwd-keyed PreToolUse gates** now cover them | MITIGATED; already adjudicated 2026-08-21 |
| F4 | every `dodRef` is an absolute path into the shared checkout | 83 live rows carry a dodRef: **3 trunk-ref, 23 absolute, 57 other** | REFUTED as stated; **the defect is real** in a narrower form — fixed here |

---

## F1 — refuted on the number, and the anti-remedy was in force for 27 days

**The cure predates the filing.** `5ac7990d9` (2026-08-11) gave `cc-venue` its two missing callers:
`venue_label_new` labels a row at write time over a bounded recency window (`cc-dispatch:1747`), and
`ready_relabel` repairs an unlabelled row at ADMISSION (`cc-dispatch:1426`, fired from `:1519`).
`4b5143eea` (2026-08-24) added the scheduled `cc-venue run --apply` pass. `cc-venue run` **is** still
open-only (`bin/cc-venue:587`), so the plan's literal deliverable ("the producer is not open-only")
is unmet — but the producer is no longer only `run`, and a blocked row's `venuePlan` is read by
nothing: `cc-dispatch:1859` filters `status=="open"`, pinned by its own test at `:3507`. Over the
last 1,561 readiness records, `venue-unlabelled` fires **once**.

That commit landed **the day before** MASTER_FIRE_GATE.md was written. Its F1 section restated a
2026-08-09 triage measurement that had already been cured when the document was authored.

**The adversarial finding, and it reframes the whole wave.** F1's text carries an explicit
anti-remedy — *"🚨 Do NOT 'solve' this with `CC_DISPATCH_VENUE_ONLY=cloud`… that parks 489 rows."*
That setting was **live in the dispatcher plist from `9d2e50e34` (2026-08-11) until today
17:37:06Z**, one day before the warning was written. Its effect is in the dispatcher's own journal:

```
{"ts":"2026-09-07T17:37:06Z","actor":"cc-dispatch","action":"skipped",
 "detail":"venue-only=cloud parked 184 of 192 dispatchable item(s) — they carry a different
           venuePlan or none, and will NOT fire while this filter is set"}
```

97 such records today, the last at 17:37:06Z and **none after**; both the live plist and the in-repo
template `launchd/com.claude.dispatcher.plist` no longer export it, and the two are byte-identical
with comments stripped. So the filter parked ~95% of the local queue for 27 days — **which is why
the repair that had existed since 08-11 never drained the local rows.** Removed today, by another
session, before this adjudication began; recorded here because any reading of the IDL before
17:37Z today is a reading of a 95%-parked queue.

**Residual (real, 4 rows).** Four rows have no venue label and zero readiness records ever: two are
`sevenrooms-bridge`, absent from `dispatch-projects.conf` (`skip: project-not-dispatched`), and two
are capacity-`defer`red every pass. Neither class reaches admission, so the repair structurally
cannot see them; their only covering producer is the sweep's venue pass, which recorded rc 124
(bound exceeded) on 2 of 2 runs and walks a fixed order with no cursor, while the four rows sit at
positions 149, 162, 184 and 186 of 190 — the tail a prefix-truncated pass never reaches. With n=2 no
cause is asserted, only the effect.

## F2 — refuted, and behaviourally, not just structurally

666 `.retired` markers across 687 declarations (145 `superseded`, 131 `conflict`, 23 `gone`, 9
`landed`). The release path was wired by `a48ab4594` (08-12) at `scripts/cloud-return.sh:1023-1039`
and the terminal sweep by `e39aa0be1` (09-04). All 79 `.returned` sessions also carry `.retired`,
all 79 verdictless, and 74 of 79 were retired within 0–2 s of the `.returned` write (66 at delta 0)
— a co-write pattern the only other bare-retire caller (`cc-offload:955`, `CONFIRM=1`-gated manual)
cannot explain. Oldest marker 08-12 15:34, newest today.

Of F2's four secondary defects: **cloud-create verification** exists (`cloud-create-api.py` refuses
with exit 5 unless the session reads back `environment_kind==anthropic_cloud` and `sources==1`,
`cc-offload:657-666`) though there is still **no retry**, and the original "1 of 4" rate cannot be
re-derived — its instrument measured a bundle path that is no longer the create path, and no
producer logs create attempts. **Boot budget** is discharged: `boot_s`=900 with C2/C1 at
`cc-cloud:774`, `7e3124e43` expires stale C1 to ABANDONED, and `0efcc073d` (09-02) emits the BOOT
PING that this session's own brief carried. **The local freshness gate no longer touches cloud
fires** — `8454c5778` (08-21) put the `--cwd` extraction under `if [ "$venue" != cloud ]`.
**Concurrent lands** are impossible at the push: `scripts/land-lock.sh` is machine-wide and
repo-keyed with CAS inside it. What remains is narrower than filed — no per-BRANCH interlock, so two
full gates can run on one branch and the loser fails CAS, costing minutes rather than correctness,
on an operator-invoked path (`cc-offload land`).

## F3 — mitigated; the row that owns it was closed 2026-08-21

The four paths were never named in the plan; they are named in the ancestor row `579bc8781b5b`:
`bin/cc-recover-safeguard:160,202`, `scripts/boot-resume.sh:305`, and `bin/cc-offload up` via both
`api` and `cli` (`:608,:613`). None calls `cc-backlog claim`, and that is unchanged in 27 days —
the stored falsifier re-run today returns rc 1, `cc_worker_claim_admit` count 0/0/0. But the two
`cc-offload` paths fire into a cloud VM, not a dispatch worktree, so they are outside F3's own
title; and the conclusion was adjudicated on 2026-08-21 (`docs/plans/BACKLOG_DRAIN_24_7.md`
:24177-24297, row closed): three cwd-keyed, provenance-blind PreToolUse gates —
`check-edit-boundary.sh:106`, `validate-bash.sh:429`, `agent-teams-enforce.sh:128` — mean a spawn
path cannot evade a gate that reads `cwd`. Residuals the mitigation misses: the gate is passed the
FIRER's cwd, its trigger is a spelling allowlist that names none of the four, and its no-claim arm
ADMITS. **The "20 live sessions sharing one item's worktree" is not reproducible**: measured today,
101 worktrees, 21 live `claude` processes, 3 dispatch worktrees occupied, one session each.

## F4 — the claim is refuted as stated; the defect is real, and its prescribed cure is a trap

**As stated it is false.** Of 83 live rows carrying a dodRef, 3 are trunk refs, 23 are absolute
paths and 57 are some other shape. But the absolute ones are not scattered: **all 18 that point into
the shared checkout come from one producer line**, `bin/cc-discover:273` (`source=plan-open`), which
passes the absolute paths `find-plan.sh --list-open` prints.

**The harm is worse than the filing says.** Measured today the shared checkout was **1 commit behind
trunk with 23 dirty files** — so a worker that cats the absolute path can read not merely stale bytes
but a sibling's half-written file. Its own worktree is freshness-gated by `warm_worktree`; the
absolute path routes around that guard.

**The consumer was never cured.** `f9cbe177f` and `22b8824c6` harden the `staleness_rail` — the
"read what this item cites on TRUNK" preamble, which this session's own brief carried — but neither
touches `dodRef`, which `bin/cc-dispatch:3122` rendered verbatim. A rail is an instruction; nothing
verifies the read, and the whole compose block is skipped when the prompt file is already non-empty,
so an operator-authored brief gets no rail at all. Worse, `git show origin/main:/Users/…` is not a
valid pathspec and the rail never says to strip the prefix — which is precisely where a worker gives
up and cats the file instead.

**Why the plan's remedy must not be taken.** § F4 says *"the `master-*` rows write
`origin/main:docs/plans/<FILE>.md` instead; make that the rule for every producer."* Two arms
downstream resolve a dodRef as a filesystem path and both fail silently on that spelling:

- `cc-eligible._dod_path` asks `os.path.isabs("origin/main:docs/…")`, gets False, joins it onto the
  repo, and finds nothing.
- `cc-premise._plan_dodref` requires `os.path.isfile(dod)` and returns None — which **fails OPEN**
  and deletes the derived plan-open falsifier, the only falsifier those same 18 rows have.

Rewriting the store would blind both arms for every plan-open row at once. The 3 rows already
carrying a trunk ref are already invisible to them; at n=3 nobody noticed.

**A third arm was silently mis-answering the same spelling.** `dod_trunk_state` — question 1b of
cloud eligibility — treated `origin/main:docs/plans/X.md` as a *relative* path, so
`git cat-file -e origin/main:origin/main:docs/plans/X.md` could only miss. Measured pre-fix on this
tree, the SAME file returned `ok` under both the absolute and relative spellings and `absent` under
the trunk-ref one. It is **latent today** — all three trunk-ref rows refuse earlier at question 1 —
but it sits directly on the path of the only cure anyone was likely to attempt: adopting § F4's
prescription at scale would have made question 1b refuse the newly-correct rows off-box with *"your
DoD is on no trunk commit."* The remedy would have penalised exactly the rows that adopted it.

### What was built

The staleness is cured where it bites — **in the bytes the worker reads** — and the store is left
exactly as the filesystem arms expect it.

- `bin/cc-venue`: new read-only verb **`dodspec <id> [--repo R] [--ref REF]`**, exposing the existing
  `dod_trunk_state` predicate as a rendering, so the composer and the cloud-eligibility gate can
  never disagree about where an item's specification lives (memory:
  `make-the-actuator-the-arbiter`). Three answers, three exits: `0` + a line = resolved, `0` + no
  line = not a path claim, `3` = absent from trunk, `4` = could not ask.
- `bin/cc-venue`: `_dod_candidates` now strips a `<ref>:` prefix, guarded so a line suffix
  (`x.md:12`) is not mistaken for one — a ref never carries a file extension. This fixes the
  latent false-`absent` above.
- `bin/cc-dispatch:2946+`: the composer resolves the DoD line through that verb. **Fail-open by
  construction** — only exit 0 *with* a line replaces anything, so a missing or broken cc-venue
  costs nothing and the brief is byte-identical to today's.

`tests/cc-venue-dodspec.bats` (15 cases) and `tests/cc-dispatch-dodspec-brief.bats` (5 cases, each
paired against the pristine `origin/main` composer). Red-proof: 15/15 red against
`origin/main:bin/cc-venue`.

⚠️ **The red-proof needed its own correction, and the failure is worth keeping.** Running the
pre-fix `cc-venue` from `/tmp` made it exit **3** at import — it resolves siblings relative to its
own directory and could not find `cc-eligible` — and 3 is exactly what two cases expect, so both
went green against a binary that never executed a line of the code under test. 13 of 15 red became
15 of 15 once `CC_VENUE_ELIGIBLE_BIN`/`CC_VENUE_PREMISE_BIN` were passed. A third case then passed
vacuously because argument validation and "unknown verb" share exit 2; it now asserts the message.
(memory: `verification-harness-vacuous-pass-traps` — an exit code shared by an abort and a verdict
is not a verdict.)

### Not taken, deliberately

The producer (`bin/cc-discover:273`) still writes absolute paths, and that is correct until the two
filesystem arms learn the trunk-ref spelling. `bin/cc-discover:329` (`gate-red`) emits a
`$HOME/.claude/…` deployed-layer path, a worse shape than the shared checkout. Both are now rendered
correctly to the worker by the consumer-side fix; changing the store is a separate, larger change
that must move `cc-eligible._dod_path` and `cc-premise._plan_dodref` in the same diff.

---

## Disposition of the row

The DoD's five clauses: *labelled for a venue* (F1 — met for every row that can dispatch; 4
structural stragglers named above), *admitted on a term that binds* (F5, landed `61e39ef3`),
*claimed by the worker that runs it* (F3 — mitigated, not by claim coverage but by cwd-keyed gates),
*briefed from a trunk ref* (F4 — met as of this commit, at the consumer), *returned with its slot
released* (F2 — 666 markers, 79 round trips).

The wave condition as filed is discharged. The residuals are individually smaller than the row and
belong to their own rows, not to a 57-row wave.
