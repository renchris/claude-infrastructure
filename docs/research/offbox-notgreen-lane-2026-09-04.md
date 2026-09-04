# The off-box lane re-proved trunk 364 times in 22 days and could not say "no"

**Row:** cc-backlog `01ab05685857` — *"postland-verify is INERT — newest GREEN stamp 46h old (max
24h), so nothing is re-proving trunk; this is how 3 red suites went unnoticed."*
**Date:** 2026-09-04 · **Venue:** cloud VM (off-box), measured against `origin/main` and the GitHub
Actions API · **Cure landed:** see § What changed.

---

## Verdict in one line

The row's TITLE is refuted and its HARM is confirmed, and they come apart at a place nobody had
looked: **the lane that is not starving re-proves trunk completely every ~4h, and its answer could
only ever be heard when it was "yes."** It has not said "yes" since **2026-08-13**. The 364 complete
judgments of trunk since then — nine red suites named in the most recent one — were discarded by
construction, and the operator-facing page printed *"nothing anywhere has proven this span"* over
every one of them.

## What was measured, and how

Everything below is a live read taken from this VM on 2026-09-04, not an inference from source.

### 1. The off-box lane is not inert. It is the opposite of inert.

`.github/workflows/hermetic.yml` runs on a schedule, ~4-6h apart, and every run in the window is
`conclusion: success`. Trunk sha `11f50d3408f0`, run **431** (14:20Z), fold job `101064757671`:

```json
{"verdict":"red","suites":537,"expected":537,"green":527,"red":9,"nonverdict":1,
 "unreported":0,"run_s":6475,
 "failing":["tests/pipefail-sigpipe-lint.bats","tests/capacity-alarm.bats",
            "tests/goal-inert-watch.bats","tests/validate-bash-differential.bats",
            "tests/live-session-registry-atomic.bats","tests/cc-resume-field-order.bats",
            "tests/smart-bash-allowlist-compound.bats","tests/typed-send-lint.bats",
            "tests/deathwatch-watchfile.bats"],
 "nonverdict_suites":["tests/cc-reaper.bats"]}
```

`suites == expected == 537` and `unreported == 0`. This is a **complete** judgment of trunk — not a
sample, not a partial fold over a dead shard — and it names nine failing suites.

### 2. And nothing on the box could learn it. Three independent reasons, all deliberate.

| layer | what it does | why the red is invisible |
|---|---|---|
| the run | `conclusion: success` | the fold step is *reporting only* — "not green is not an error" |
| the `verdict` job | `skipped` | its guard is `if: needs.fold.outputs.verdict == 'green'` |
| `offbox-green-pull.sh` | writes nothing | the non-green arm was `*) : ;;` — **no store behind it** |

Each is defensible alone. Together they mean the single most complete re-proof of trunk this project
owns reaches nobody, and the failure is silent at every layer — the run is green, the job is not a
failure, and the puller reports "0 new greens" exactly as it would on a healthy quiet day.

### 3. The rate, because a state-shaped row needs one.

This row's own history records the methodological lesson (plan `BACKLOG_DRAIN_24_7.md`, finding 4):
*a row asserting a STATE needs its rate measured across the whole window since filing, never its
value sampled now.* So the sample above was extended — first to the last twenty runs, then to
**every run the workflow has ever had on `main`**, by reading the `verdict` job's conclusion on each
(`427` runs, `2026-08-10T08:24Z → 2026-09-04T14:20Z`):

```
verdict job = success :    4 / 427     runs   8, 60, 61, 67
newest green :             run 67, 2026-08-13T11:58:06Z          — 22 DAYS AGO
runs since that green :    364, every one of them `skipped`
```

**Four greens in the workflow's entire history, and none for 22 days.** The T1H acquittal tier — the
designed backstop for exactly this row's condition, built after an incident of *"534 identical
refusals … live layer 91 commits stale, ZERO pages"* — has been **structurally dead since
2026-08-13** and has never meaningfully been alive. This is not a blip and not one draw from a live
distribution; it is the whole distribution.

The consequence compounds with the on-box starvation this row was filed about. Both tiers are down
at once: the launchd verifier stamps `cut` on ~51% of runs (`195/379` at the last census) and the
off-box tier has produced nothing since 2026-08-13 — while the off-box lane went on **completely
judging trunk 364 more times** and throwing every answer away.

### 4. The sentence this produced, which is the actual harm

`scripts/nightly-regression.sh`'s `postland_green_starvation` reported a **two-valued** field:

```
off-box acquittal: none — nothing anywhere has proven this span
```

That reading was FALSE on this repo every single day of the window. The span *had* been proven —
completely, four hours earlier — and the answer was "nine suites red." The two readings send the
operator in opposite directions, and the check's own comment says so:

> *a starving verifier over a CI-acquitted tree is a machine problem, and a span nothing anywhere
> has proven is a code problem*

The field was built to make exactly that distinction and could not express the case that was true.

## The defect, stated precisely

**The rule was right and the implementation was a different rule.** The producer's doctrine — *"this
producer may acquit; it may not convict"* — is sound: a hermetic subset cannot see the machine-coupled
suites, so it has no standing to convict a tree or block a deploy. But it was implemented as *"on a
non-green, do nothing at all."*

Those are not the same rule. **Reporting is not convicting.** The gap between them is the whole of
this row: a measurement with no store to land in is indistinguishable from a measurement that never
happened, and this project has paid for that shape before (memory:
`conclusion-must-reach-the-enforcing-store`).

## What changed

Commit `f442cfe1`. Two files, plus controls.

**`scripts/offbox-green-pull.sh`** — a non-green now writes into `offbox/notgreen/`, a **sibling
directory**, so the not-convicting property is *structural* rather than a silence:

- Both consumers of the acquittal store are path-keyed on `offbox/<tree>.json`
  (`deploy-live.sh:1746`, `nightly-regression.sh:449` — census-verified). A record one directory
  down is unreachable to them and cannot become a deploy input by accident.
- The record says `verdict:"not-green"`, a token no green predicate matches, and carries the same
  both-fields-or-neither `scope:"offbox-hermetic"` discipline the acquittal carries — so a bare file
  drop is not a claim here either.
- `check_conclusion` stops collapsing every completed non-success to one word. **`skipped`** is the
  fold refusing to certify (a *code* problem); **`failure`/`cancelled`/`timed_out`** is the publisher
  breaking (a *lane* problem). Opposite repairs; the old token could not tell them apart. Sanitised
  to the GitHub conclusion alphabet before it reaches a record a later reader parses.
- A not-green tree is **still re-queried every tick**. Only `offbox/<tree>.json` short-circuits the
  scan, so a re-run that goes green can still acquit the tree it failed on. API cost is unchanged
  from before, when such a tree was re-queried and then forgotten.
- `cmd_status` gains `-maxdepth 1`. This is a correctness clause, not a tidy-up: it is the one reader
  that *enumerates* rather than path-resolves, so without it the store's own status command counts
  not-greens under the heading "greens held" — the weaker claim laundered into the stronger one with
  no predicate edited. Red-proved: the mutant reports `greens held: 2` over one green and one
  not-green.

**`scripts/nightly-regression.sh`** — the starvation field becomes three-valued. The verdict, the
counts and the span are computed and returned **identically**; only the sentence changes.

## Red-proofs

A control that cannot fail is not a control, so each was run against a mutant:

| control | mutant | result |
|---|---|---|
| P2b–P2f (the notgreen record exists, and says what it is) | the pre-change `*) : ;;` arm restored | **FAIL** ×5 |
| P8 (status does not launder) | `cmd_status` without `-maxdepth 1` | **FAIL**, `greens held: 2` |
| 5b test 7 (the third state is reported) | pristine `origin/main` `nightly-regression.sh` | **FAIL** |
| 5b tests 8/9/10 (invariance, precedence, anti-laundering) | same pristine script | **pass both sides** — correct; they are controls, not differentials |

## Gates

`offbox-green-pull --selftest` 21/21 · `nightly-regression --selftest` 65/67 (the two are `plutil`,
macOS-only, absent on this VM) · `tests/deploy-live.bats` **145 ok / 3 not-ok — the same 3 as the
pre-change baseline on this box** (indices 49/90/129, shifted from 45/86/125 by the four added
tests) · `tests/offbox-partition.bats` + `tests/offbox-admission-lint.bats` 39/39 · `shellcheck -x`
clean · `pipefail-sigpipe` · `test-hermeticity` · `test-walltime` · `alarm-polarity` · `self-path` ·
`utc-stamp` · `subshell-cleanup` · `bats-shellcheck` · `tsv-pad` all clean · `offbox-admission-lint`
admits.

## Not fixed here — named, not swept

1. **The nine red suites are trunk's actual state, and they are not this row's work.** They belong
   to verdict-quality (`17e94bb423ef`). They were measured off-box on `macos-latest`; this VM is
   Linux and cannot reproduce them faithfully, so re-deriving them here would have produced a
   plausible diagnosis against the wrong machine — the failure mode this row's own history already
   records twice. They are named above so the next session starts from the measurement.

2. **A not-green is surfaced only when the starvation check already fires.** If the on-box verifier
   is healthy on tree *T* while off-box is red on *T*, `5b` abstains and the not-green is reported
   nowhere. The obvious extension is a standalone check — and it is **deliberately not taken here**:
   given the rate measured in §3 it would RED-page the nightly *every single night* until those nine
   suites are fixed, and this repo's own principle (`tests/deploy-live.bats`, 5b) is that *two checks
   paging over one repair is the noise that gets a nightly ignored*. A page that fires unconditionally
   for weeks is the failure mode this row is *about*, re-created one layer up. That is a live-box
   behavioural judgment about page volume, and firing it blind from a VM that cannot observe the
   resulting volume is not a call this session should make. **The right sequence is: land this, let
   the not-green records accumulate where they can be counted, fix the nine suites, and only then
   arm a standalone check — at which point it is silent by default and therefore means something.**

3. **The T1H tier's 4-greens-in-427 rate is itself a finding this row does not own.** Whether the
   hermetic partition is *achievable* — i.e. whether the exclusion manifest is sized such that a
   green is reachable at all — is a question about verdict quality and partition maintenance. This
   session establishes the rate and hands it forward; it does not adjudicate it.

4. **A dispatcher-vintage fact, not a defect.** The dispatcher that fired this session is
   `bin/cc-dispatch` blob `646b8a65`; `origin/main` carries `98ab38f5`. **DIFFERENT** — the
   dispatcher is behind trunk. Nothing here depends on it, but *landed is not live*, so a remedy read
   on trunk is not necessarily the code that ran.

## The transferable lesson

**A store with no vocabulary for an answer is a store that cannot hear it.** The failure was not a
wrong predicate or a broken producer — every component did exactly what its comments said. It was a
`case` arm with no branch, guarding a directory that was never created, under a doctrine sentence
that described a *policy about deploys* and was read as a *policy about knowledge*. 364 complete
measurements, 22 days, zero of them readable, and every layer reporting success.

**And that is why nobody noticed.** A tier that fails by producing *nothing* is invisible to every
sensor that keys on what it produces: `deploy-live`'s T1H simply never becomes eligible, the
starvation field reports the absence as "nothing has proven this", and the puller's own status line
reads `0 new greens` — the identical output it gives on a healthy quiet day. Four greens in 427 runs
is a tier that has never worked, reported for 22 days as a tier that had nothing to say.

When a lane is allowed to acquit but not convict, give the non-acquittal somewhere to live. The
separation belongs in the **topology** — a directory no consumer resolves — not in the **silence**.
