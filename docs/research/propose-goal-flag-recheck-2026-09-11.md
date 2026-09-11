# `tengu_propose_goal` still OFF at 2.1.268 — and the row's falsifier now has a second reading

**Date:** 2026-09-11 · **Subject:** cc-backlog `2a65b9bf722d` ("ProposeGoal (`tengu_propose_goal`)
is default-off upstream — adopt when the flag flips") · **Method:** read out of the **2.1.268**
native binary (`/opt/claude-code/bin/claude`, ELF, 218,602,992 B) and the GrowthBook feature cache,
on an Anthropic-managed cloud VM. No flag was flipped, no setting was written, no live file touched
(C10). · **Predecessor:** `docs/research/propose-goal-flag-recheck-2026-09-10.md`.

## 🚦 Disposition: this row STAYS OPEN — and it now has a watcher

The premise is **NOT REFUTED** at 2.1.268. The disposition is unchanged from yesterday's note and
for the same reason: this is a `not-yet-true` watch row, and the only thing that should ever close
it is its own falsifier going true.

What this pass adds is the part yesterday's note *named and did not ship*. §5 there identified a
hole in the row's stored falsifier and worked out, correctly, that the fix cannot live inside the
falsifier. It then left the corrected pair in prose. Nothing in the tree ran it, so the row's
machinery was still the one-liner with the hole, and the row was re-dispatched to a fresh worker the
next morning to re-measure "still off" — which is what a watch row with no watcher does forever.

`scripts/propose-goal-flag-watch.sh` + `tests/propose-goal-flag-watch.bats` are that pair, built and
red-proved. The row still closes only on a flip; it now closes on a flip *that something is looking
for*.

## 0. The one action this note asks for — repoint the row's falsifier

**No scheduling is needed, and no launchd job should be written for this.** The dispatcher already
runs the row's stored falsifier on every dispatch — the brief that fired this session quotes its own
re-run of it. The dispatcher *is* the watcher; it was simply running the probe with the hole. So the
whole handoff is a one-line store edit on the desk, replacing the row's stored `probe` with:

```sh
bash scripts/propose-goal-flag-watch.sh --falsify
```

It is a drop-in: rc 0 still means *retract this row* and non-zero still means *keep it open*, so no
consumer changes behaviour. What changes is that the third state stops being silent — rc 2 says
*nobody asked GrowthBook inside the window* out loud, instead of spending the word `false` on it.

Anything beyond that (a cadence, a surface to page) is the operator's call and is deliberately not
built here; §8 records why.

## 1. The verdict at 2.1.268

| Question | Answer at 2.1.268 / 2026-09-11 |
|---|---|
| Is `tengu_propose_goal` on? | **No.** Absent from the cache ⇒ the `!1` default applies. |
| Is the gate still default-false? | **Yes**: `function syt(){return I("tengu_propose_goal",!1)}` |
| Was the feature removed upstream? | **No.** `ProposeGoal` 18 occurrences, `modelProposedGoals` 12, `proposal_direct` 2 — identical to 2.1.267. |
| Dispatcher vintage | brief blob `9109de61dc7a…` vs `git rev-parse origin/main:bin/cc-dispatch` = `e61bcbfc657a…`. **DIFFERENT — the dispatcher that fired this is BEHIND trunk.** |

```
$ jq -r '.cachedGrowthBookFeatures | keys[] | select(test("goal|propose";"i"))' /root/.claude.json
                                        # ← no goal- or propose-related key at all
$ date -u -d @$(( $(jq -r .cachedGrowthBookFeaturesAt /root/.claude.json)/1000 )) +%FT%TZ
2026-09-11T08:42:54Z                    # this session's own boot — the cache is FRESH
```

**Positive control for the instrument.** A cache that reads "absent" for everything proves nothing,
so the same file is checked against the per-key census A12-skeptic2 established: 618 `tengu_` keys
(623 total) · `tengu_saffron_wren` **true** · `tengu_hushed_lark` **5** · `tengu_rosy_wren`
**ABSENT** · `tengu_umber_kestrel` **ABSENT**. All four values reproduce. This is a **sixth**
independent environment agreeing with the desk's four config dirs and yesterday's VM.

## 2. The symbol moved again, one release later — §4 confirmed by event

Yesterday's §4 prescribed *"cite the gate by its argument, never by its symbol or offset"*, on the
strength of `mct` (A12, 2026-09-08) having become `cgt` (2.1.267, 2026-09-10). At 2.1.268 it is
**`syt`**. Three releases, three symbols, one unchanged argument:

| read | version | symbol | default |
|---|---|---|---|
| A12 §3 | ~2.1.2xx, 2026-09-08 | `mct` | `!1` |
| recheck-09-10 §2 | 2.1.267 | `cgt` | `!1` |
| **this note** | **2.1.268** | **`syt`** | **`!1`** |

A re-check written against last month's symbol returns nothing, which reads exactly like *the
feature was removed*. That prediction was made on 2026-09-10 and came true on 2026-09-11. The
version-proof form is now what the watcher executes, so no future reader has to remember it:

```sh
grep -a -o -E 'function [A-Za-z0-9_$]+\(\)\{return [A-Za-z0-9_$]+\("tengu_propose_goal",![01]\)\}' "$BIN"
```

## 3. The hole in the stored falsifier is not hypothetical — it is measurable on this box

The row's stored probe:

```sh
jq -es 'any(.[]; .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json
```

Run verbatim here:

```
$ jq -es 'any(.[]; .cachedGrowthBookFeatures.tengu_propose_goal == true)' ~/.claude*/.claude.json
jq: error: Could not open file /root/.claude*/.claude.json: No such file or directory
false
rc=2
```

The desk-shaped glob matches nothing on a box whose only cache is `$HOME/.claude.json`. An unmatched
glob stays literal in bash, jq fails to open it, and **the word printed is byte-identical to a
genuine negative.** A consumer reading the printed `false` — or reading only `rc != 0`, which is what
"non-zero ⇒ keep the row open" amounts to — reads *the instrument could not answer* as *the flag is
off*.

That is §5's staleness hole arriving through the **population** instead. Both are the same defect:
the probe spends one answer (`false`, non-zero) on two states that demand opposite actions. Note the
brief that dispatched this session reported the falsifier's re-run as "NOT REFUTED (exit 1)" — a
desk reading, where the glob matches. The desk and the VM get different exit codes from the same
line, and neither of them is wrong; the line simply cannot say which question it answered.

## 4. What was built

`scripts/propose-goal-flag-watch.sh` — three arms, one exit code per state, none spent twice.

| mode | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| `--falsify` | flag `true` on a **fresh** cache ⇒ **RETRACT the row** | off, instrument healthy | **NON-VERDICT** — nothing fresh, or nothing readable | — |
| `--health` | ≥1 cache refreshed inside the window | every readable cache stale | no readable cache | — |
| `--binary` | gate default is `!0`, **or** no gate match while `ProposeGoal` is present | gate still `!1` | no readable subject, or tripwire fails | `ProposeGoal` absent from a verified build — feature may be gone |
| `--report` | any arm signalling | none, every instrument healthy | none, an instrument could not answer | — |

Four design points, each of which a mutant proves load-bearing:

- **rc 2 exists because rc 1 is a claim.** Every consumer treats non-zero as "keep the row open", so
  a mode that cannot answer must not spend the "no" code — otherwise the row never learns its
  instrument went blind, which is the terminal state §5 described as *unfalsifiable in the limit*.
- **Per-member, never aggregate.** Each cache is read on its own and reported by name with its age
  and value. An aggregate over the population can only ever detect a **total** zero, and the healthy
  members are exactly what keep it quiet while one member goes blind.
- **The binary arm carries a tripwire.** `tengu_` must be present in the subject before an absence of
  `ProposeGoal` is allowed to mean "removed upstream"; otherwise pointing the instrument at the wrong
  file mints a confident retraction signal. §4 measured that exact hazard: an unrelated npm `cli.js`
  at 2.1.42 sits beside the native build and greps against *it* return 0 for all three strings.
- **`has()`, not `//`.** jq's `//` treats a literal `false` as null, so the obvious spelling reports
  a key that is **present and off** as if the account had never been in the experiment. Both read
  rc 1, so only the rendered row can tell them apart.

**The population is widened to include `$HOME/.claude.json`.** §5 excluded it on an A12-skeptic2
measurement that it had been stale since 2026-08-11 — a perishable fact standing in for a criterion.
The criterion is *do not read a stale cache*, and the freshness filter enforces that directly, per
member, at read time. On the desk this reproduces the stored behaviour for as long as the old
measurement holds; here it is the difference between a reading and the rc 2 in §3.

Live output on this VM:

```
(1) FALSIFIER  rc=1  off, on a healthy instrument — keep waiting
    window 604800s · 1 cache(s) · 1 fresh · 0 unreadable · fresh-true 0 · stale-true 0
  fresh  0h        tengu_propose_goal=ABSENT   /root/.claude.json

(2) BINARY     rc=1  gate still default-false
    subject /opt/claude-code/bin/claude
    gate    function syt(){return I("tengu_propose_goal",!1)}
    control ProposeGoal×18 · tripwire tengu_×1890

⇒ still off, on healthy instruments. The row stays open; there is nothing to adopt yet.
```

## 5. The red-proofs, and why the "keep waiting" cases are not among them

`tests/propose-goal-flag-watch.bats` — 15/15, plan line present. The subject's own `--selftest`
covers §5's seven cache rows and §4's binary rows (18 arms, run in-suite as G0).

The load-bearing cases are the ones expecting **RETRACT**. A falsifier's job is to stay quiet for
months and then, once, fire; a probe that always answers "off" is indistinguishable from a correct
one on every quiet day, which is the state this row had been in. The "still off" cases are
*equivalence guards* and are labelled as such in the suite — they would pass against several wrong
implementations, and they earn their place only because these four mutants show which assertions
discriminate:

| mutant | derangement | verdict it inverts |
|---|---|---|
| M1 | delete the freshness filter | a 30-day-stale cache reads as a live observation (rc 2 → 0) |
| M2 | delete the binary tripwire | a file that is not a Claude build reports "feature removed" (rc 2 → 3) |
| M3 | fold rc 2 into rc 1 | **the incumbent**: an empty population answers "off" (rc 2 → 1) |
| M4 | read the flag with jq's `//` | present-and-false renders as `ABSENT` (text, not status) |

M3 is worth naming separately: it does not introduce a hypothetical bug, it **reconstructs the
stored one-liner's behaviour as a consumer sees it**. The control beside it is the real subject
answering 2 on the same fixture.

Two instrument scars from building this, both the kind that pass for green:

- The first mutator used `awk sub()`, which reads its pattern as a **regex**. Every anchor here is
  shell source full of `[ $ ( | //`, so three of four mutants either compiled to a different pattern
  or failed to match — and one of them still passed the `cmp` "did it apply?" check, because the
  mangled pattern happened to change some other byte. *Applied to nothing, wearing green.* The
  helper now replaces literally in python and asserts the anchor occurs **exactly once**.
- The `--selftest` cleanup trap named a function-local `tmp`, and an EXIT trap fires after the
  locals are gone: `unbound variable` printed **after** the verdict, under `set -u`, at exit 0. Noise
  after a verdict is where a reader stops trusting the verdict.

## 6. Gate state, and what the tree caught that the suite could not

A/B against a detached worktree at pristine `origin/main`, one variable:

| suite set | pristine `origin/main` | this branch (first draft) |
|---|---|---|
| 8 tree-scanning lints (214 cases) | **214/214 ok** | 8 red |
| `bats-shellcheck-lint` (28 cases) | 2 red | 2 red — **identical**, pre-existing (shellcheck 0.9.0 on this VM) |

The 8 were this diff's, and both causes were real:

- **`pipefail-sigpipe-lint`** — `head -c 2 "$c" | grep -q '#!'` has `grep` exit on its first match,
  SIGPIPE the `head`, and under `pipefail` the pipeline then reads **FALSE on a MATCH**. The polarity
  inverts exactly where the guard matters: that test is what rejects an npm `cli.js` standing in for
  the native build, and inverted it *accepts* the wrong subject, which then answers "feature
  removed". Captured into a variable and matched with `case`.
- **`test-hermeticity-lint`** — `setup()` did not fixture `$HOME`, and the subject's default
  population is `$HOME/.claude*/.claude.json` plus `$HOME/.claude.json`, i.e. the operator's live
  caches. Every case names `PGW_CONFIG_PATHS` explicitly, so nothing was reading the fleet today; the
  leak is that a case which forgot would, and its verdict would then depend on whose box ran it.

Both fixed; 214/214 restored, suite 15/15, `shellcheck -x` clean on the subject.

## 7. Dispatcher vintage: BEHIND trunk

Yesterday's note recorded the firing dispatcher blob as EQUAL to trunk. Today it is **DIFFERENT**:
the brief was composed by `bin/cc-dispatch` blob `9109de61dc7a…` while `origin/main:bin/cc-dispatch`
is `e61bcbfc657a…`. Landed is not live. This is a convergence fact about the deploy layer, not a
defect in anything read above — but it means a remedy found on trunk was not necessarily the code
that ran when this session was fired, and it is the likeliest reason this row was re-dispatched the
morning after a full re-check landed.

## 8. What was NOT established

- Whether the flag is on for **any** account anywhere. Six caches reading absent is absence of
  observation of a `true` for those identities; GrowthBook targeting is per-identity.
- Whether an adopted `ask_user:false` proposal engages on a fired peer. Still unmeasurable — no
  environment on which the tool is enabled exists to test against.
- Whether the watcher should be **scheduled**. It is deliberately not wired to launchd or to any
  sweep lane, and §0 argues it should not be: the dispatcher already runs the row's falsifier, so a
  scheduled job would be a second watcher for a row that has one. C10 forbids editing launchd in
  place from a worker in any case, and a cadence is the operator's call.
- Everything §3 of yesterday's note priced about **adoption cost** — the 500-char `rAt` cap against
  the typed path's 4000, the `alwaysAsk` upgrade that turns an unattended proposal into a dialog
  nobody presses, the plan-mode throw — is unchanged and un-re-measured. It becomes actionable only
  when the flag flips, and nothing about 2.1.268 moves it.

## 9. How to run it

```sh
bash scripts/propose-goal-flag-watch.sh              # --report: every arm, per-member, with controls
bash scripts/propose-goal-flag-watch.sh --falsify    # rc 0 ⇒ RETRACT the row · 1 ⇒ off · 2 ⇒ NON-VERDICT
bash scripts/propose-goal-flag-watch.sh --health     # is (1)'s answer about the flag, or about the instrument?
bash scripts/propose-goal-flag-watch.sh --binary     # the argument-keyed gate read, with its tripwire
bash scripts/propose-goal-flag-watch.sh --selftest   # 18 fixture arms, no live state touched
```

The row's stored falsifier can be repointed at `--falsify` verbatim: rc 0 still means retract, and
non-zero still means keep it open, so no consumer changes behaviour. What it gains is that rc 2 now
says *nobody asked* out loud instead of spending the word `false` on it.
