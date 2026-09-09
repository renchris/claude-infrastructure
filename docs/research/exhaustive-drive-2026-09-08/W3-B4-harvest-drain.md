# W3-B4 — the corrected harvest instrument, and the peer-findings drain producer

**The instrument's own named defect was real and it was understating the loss. Screening tokens
against the HAYSTACK instead of against the closes moves the later-reader harvest rate from
21.0 % to 14.5 %, permanent loss from 34.5 % to 64.5 %, and hand-read precision on the same
20-pair protocol from 7/20 = 35 % to 16/20 = 80 %. The producer that number calls for is
`scripts/drain-peer-findings.py`: it walks transcripts that have gone quiet, lifts the clause the
LAST close used to name remaining work, and files it through `bin/cc-backlog` into
`~/.claude/autonomy/backlog.jsonl` — the one drained store that is already a ranked worklist a
later session picks from. It is landed with `--dry-run` as the default and is NOT yet scheduled.**

## 1. The instrument fix

W2-B4 reported its own defect: `--df-max` dropped a token appearing in more than 5 % of the
CLOSES, but the inflation comes from tokens that are common in the COMMIT CORPUS. `MEMORY.md`,
`slop-lint.sh`, `handoff-fire.sh`, `claude`, `master`, `origin/master` are all rare among closes
and ubiquitous among commits, and each of them scored a pair "harvested" on evidence about a
different piece of work.

**The fix is a BACKGROUND document-frequency filter measured strictly BEFORE the close.** A token
already part of the repo's commit vocabulary in the `--bg-days` (14 d) preceding a close cannot
discriminate a harvest from background chatter, so it is dropped. Measuring it pre-close is what
makes it safe rather than merely aggressive: a real harvest lands AFTER the close by construction,
so this filter can never delete a true positive — a property the close-frequency filter did not
have. `--bg-max` (default 0) is the number of pre-close documents a token may appear in.

Both corpora now reach `days + 8 + bg_days` back so every close is scored against a full
lookback. Widening backwards can add no hits: `first_hit` only counts documents strictly after the
close.

### Before / after — same box, same 14-day window, 25 minutes apart

The control arm is the PRISTINE pre-fix artifact read out of git by blob id
(`550373d55c3c9dbcc44baa077979cf97ce20314e`), not a hand-edited approximation.

| quantity | pre-fix | post-fix (`--bg-max 0`) | `--bg-max 2` |
|---|---|---|---|
| transcripts in window / sessions with a close | 839 / 549 | 839 / 549 | 839 / 549 |
| LAST closes naming drivable work | 215 (39.2 %) | 215 (39.2 %) | 215 (39.2 %) |
| measured population | 200 | **166** (34 more dropped) | 191 (9 more dropped) |
| harvested within 7 days | 131 = 65.5 % | **59 = 35.5 %** | 95 = 49.7 % |
| permanent loss | 69 = 34.5 % | **107 = 64.5 %** | 96 = 50.3 % |
| **harvested by a LATER reader (≥ 0.5 d)** | **42 = 21.0 %** | **24 = 14.5 %** | 31 = 16.2 % |
| ⇒ loss once simultaneous hits are excluded | 79.0 % | **85.5 %** | 83.8 % |

**The number moved, and it moved the way the report predicted it would.** W2-B4 wrote that
correcting for precision "moves permanent loss UP… and the ≥ 0.5 d stratum from 21.2 % harvested
toward ~ 7 %". Measured rather than extrapolated, it lands at 14.5 % — between the uncorrected
21.2 % and the naive precision-scaled 7 %, because the filter removes the spurious hits directly
instead of scaling the whole stratum.

**The cost is an honest one and it is printed, not hidden:** 34 closes (17 % of the population)
now yield no token at all and are reported as *unmeasurable, NOT harvested*. Their exclusion, like
every other exclusion in this instrument, biases the measured loss DOWNWARD.

### Precision — the test that actually decides whether the fix worked

Same protocol as W2-B4: `--sample 20`, hand-read, each hit judged real or spurious.

| | pre-fix | post-fix |
|---|---|---|
| real | 7 | **16** |
| spurious | 13 | **4** |
| precision | **35 %** | **80 %** |

The four survivors are `gemini` (×2), `slop-lint.sh` and `origin/master`. Scoring the three
weakest of the sixteen (`7b406352c6f3` matched by packet mtime; `registration.json` matched as a
generic sibling of the close's distinctive token; `no-session-id`) as spurious too still gives
65 %. **The residual class is a token that is generic in ENGLISH but absent from the pre-close
corpus of that particular repo** — the filter is per-repo, and a repo where "gemini" was never
committed cannot screen it. Widening `STOP` to add `origin/master` was rejected: that enumerates
spellings, not the class (memory: `denylist-enumerates-spellings-not-the-class`).

## 2. The producer — `scripts/drain-peer-findings.py`

### The venue: `backlog.jsonl` through `bin/cc-backlog`, and no new surface

Four stores on this box are actually drained — `backlog.jsonl`, `decisions/*.json`,
`cc-registry/*.json`, and the pane mailbox. Exactly one of them is a durable, ranked worklist a
later session PICKS FROM: `scripts/drain-pick.sh` ranks backlog rows, `bin/cc-dispatch` fires
them, `bin/cc-do` and `hooks/operator-readout.sh` fold them. The IDL was considered and rejected:
every record is `{ts, hook, sid, disposition, reason}` and nothing routes a row of it to a
successor — it is a telemetry sink, not a work store. The rules file was rejected because it is
loaded into every session at full length, so a surface that grew a row per drained finding would
carry fewer bits the more it held (memory: `alarm-polarity-and-attention-budget`).

The producer never hand-writes the JSONL. The store carries an id scheme (`mk_id` = sha256 of
project ␟ title ␟ source), a done-latch, a `needs` mint brake and a 4,000-byte record guard;
bypassing `cc-backlog` would re-create every bug those exist to prevent. Re-running the producer
is therefore idempotent by the store's own construction: an identical title on an identical
project re-files as the SAME id.

### The chokepoint: out-of-session, not a Stop hook

`hooks/dispatch-assert.sh` is the obvious candidate and it is the wrong one. It already has the
matcher, the turn window and a discharge oracle over the same four stores — it simply never
writes, it blocks and hands the model a command. Two reasons not to give it the write:

1. **A Stop hook cannot know which close is the LAST one.** It fires on every turn, so it would
   file a row for work the next turn does. Measured on the live IDL, dispatch-assert evaluates 177
   times and fires **once** — `no-naming-tell` on 162 of them.
2. **It cannot see the adverse population at all.** `hooks/boundary-handoff.sh`'s own header
   admits it never runs for a session that died mid-turn.

So the producer walks transcripts that have gone quiet (`--settle-hours`, default 6) and are not
in the live-session registry. The registry is consulted as a suppressor only — a miss is not
absence (memory: `lookup-miss-is-not-absence`), so the settle window is the real guard, and its
failure direction is over-filing rather than under-filing.

### The three constraints, and what each one forced

**Constraint 1 — the matcher's errors are all false POSITIVE harvests, so a producer that trusts
it to say "already harvested" skips real losses at exactly the rate the instrument is wrong
(20 %, post-fix).** The producer therefore runs **no harvest detection as a filing gate at all**.
Harvest evidence goes into the row's `--falsifier`, a probe `cc-backlog falsify` RUNS and which
refuses to retract on exit 0 — so a false-positive harvest leaves the row OPEN. That is the
fail-safe direction; the same evidence in the filing gate would silently delete a real loss.

The one exact check that IS allowed to skip is `already_in_venue()`: if every 12-hex id the clause
names is already a row in the destination ledger, and the clause is little more than that list,
the finding has verifiably already reached this venue. That is an exact key lookup in the store we
are writing to, not the 80 %-precision harvest matcher. Test 6 red-proofs the distinction: the
mutant that relaxes it to "ANY named id already exists" drops a real finding that merely cites a
filed row in passing.

**Constraint 2 — the rate prices the CHANNEL, not the cargo.** No claim here is of the form
"recovers N % of value"; there is no measurement of what a drained finding is worth. What the
design does instead is make a low-value row cheap: `source=peer-drain`, **no `--why-not-now`**, so
the row is agent work in a ranked worklist and never enters the operator's counted `◆` pile or the
`👤` rung. A wrong row costs a grep line, not an operator decision. Test 11 asserts the absence of
`--why-not-now` on the wire.

**Constraint 3 — the 302 of 820 transcripts that died mid-turn.** They are **reachable, and the
arm is built and tested (`--include-no-close`), but OFF by default.** A transcript with no
turn-final close still has a last assistant text, and `last_assistant_text()` lifts it. What is
missing is a *number*: the matcher's 80 % precision is measured on CLOSES, and mid-turn text is
usually tool narration rather than a stated finding, so switching this on today would file rows at
an unmeasured precision into a ranked worklist that dispatches sessions. Turning it on is a
measurement, not a decision — run the producer with `--include-no-close --days 14` and hand-read
20 rows, exactly as B4's precision number was obtained. Test 14 proves the arm works and proves it
is off by default.

### Extraction, and what it deliberately drops

The row's title is the clause, then the path of the transcript that holds the whole close — a
pointer, so the close is dropped into a named store rather than deleted. The clause is S2's
`follow-on:` ledger when there is one, else the first sentence ≥ 40 chars that STATES something
open (`🔧`, still, remains, unlanded, not yet done, left to, next step, parked). The plain "carries
a naming tell" fallback was removed after a dry run over 139 real transcripts drained
*"Everything of mine is finished, landed, and now live"* and *"🔧 17:03, `ahead=1`"*. On the same
window the current rules yield 10 drainable rows from 139 transcripts, with 4 more skipped as
already-in-venue.

## 3. Red-proof — `tests/drain-peer-findings.bats`, 14/14, plan line `1..14`

The instrument's control arm is `git cat-file -p 550373d55c3c9dbcc44baa077979cf97ce20314e`. A blob
id rather than `HEAD` for two reasons: `HEAD` stops being pre-fix the moment this branch lands, and
a blob is content-addressed so a rebase that rewrites the commit sha leaves it reachable (memory:
`cited-sha-may-not-survive-the-land`). Test 1 asserts the control resolves AND that it cannot
express the fix — a control that cannot be read is not a control.

- **Test 2 is the discriminator.** One fixture, one close naming a background token: pre-fix reads
  `1 / 1 = 100.0 %` harvested by a later reader; post-fix drops the token and reports the
  population as 0. The arms disagree.
- **Test 3 is its positive control.** A genuinely distinctive token is still harvested by BOTH
  arms — without it, test 2's disagreement would be equally consistent with the "fix" being a
  blanket suppressor.
- **Tests 6, 8, 9 are mutants**, because the producer is new code with no pre-fix artifact to
  replay. Each copies the three-file tree in the shape the subject reads it (memory:
  `subject-reads-its-own-path-and-its-own-output`), changes one line, and asserts the mutant DYING
  on the fixture the real script passes.

**The red-proof discipline paid for itself immediately.** Test 9 first failed with `real=''
mutant=''` — green in both arms. The cause was a real defect: the nil-ledger guard was anchored at
end-of-string, so it could only ever match a phrase of ≤ 20 characters and was therefore fully
shadowed by the 40-character minimum. It was dead code doing nothing, and the length check was
silently doing its job by accident. Re-anchoring it to the LEAD gives it work only it can do —
`follow-on: none, everything of mine is landed and content-verified on trunk this turn.` — and the
mutant now dies. **An equivalence guard is not a weaker test; it is a test that was pointing at
code with no job.**

**Then the land's own gates found three more, and all three were mine.** This is worth recording
because it is the pattern the red-proof rule is really about — *a test that passes is not the same
as a test that is enforcing*:

- **`test-hermeticity` (a):** `setup()` passed `HOME` per-invocation but never exported it, so every
  python module load in the mutant and selftest cases resolved `~/` against the operator's live
  config — and `measure-harvest-latency.py` reads `~/.claude/autonomy/backlog.jsonl` by default.
  Now fixtured for the whole suite.
- **`test-hermeticity` (b):** the AMBIENT arm fired because a fixture token was *spelled*
  `handoff-fire.sh`, which the lint reasonably reads as a suite exercising a capacity-gated tool.
  The token was arbitrary, so it is renamed rather than the gate pinned off for a tool this suite
  never invokes.
- **`bats dead-assertion` — the sharpest of the three:** **12 of this suite's assertions were
  unreachable by errexit**, i.e. they could not fail the test they were written into. A bare
  `[[ … ]]` conditional-keyword statement, and the `! grep -q …` negation, are both in that class
  (memory: `negated-assertion-dead-unless-final`). Every one of them was *passing*, and every one
  of them was decorative. `scripts/bats-assert-liveness-fix.py` revived all 12; the suite is 14/14
  again with them live, which is the only run of it that has ever meant anything.

**Two of the three ratchets that matter here exist because someone made this mistake before, and
one of them exists for exactly the choice made in §3.** `moving-ref-control-lint` fails a land whose
pre-fix control is replayed from a ref that advances — precisely the `git archive HEAD` form the
brief warned against, and the reason the control here is a blob id. It reported
`0 moving-ref controls`.

## 4. What is NOT done, and who owns it

- **The producer is not scheduled.** It lands with `--dry-run` as the default and has never been
  run with `--commit` — this session was read-only over `~/.claude/autonomy/*` by its brief, so it
  neither wrote a row nor filed the activation. Wiring it belongs in a `c10` migration
  (`migrations/README.md`), which is staged and run by the operator. `hooks/autonomy-sweep.sh` is
  the wrong host: its §0a 900 s arm inside a 400 s self-bound has starved the pass's whole lower
  half to 0 runs/day since `a7e5a609e`.
- **The mid-turn arm needs its own precision number** before it is switched on. The measurement is
  named above and is one command plus a hand read.
- **The residual instrument blindness** is a token generic in English but absent from one repo's
  pre-close corpus. Four of twenty pairs. Not fixed by widening `STOP`.
