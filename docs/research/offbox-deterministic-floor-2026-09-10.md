# The off-box producer could not emit a green, and the reason was one apostrophe

**Row:** backlog `f8b71a8e0ff0` — *"re-measure the post-cure green rate against the DELIVERED cadence
(7.32 folds/day, not the cron's 24), then re-pose the retry fork only if the failing set has become
instability-dominated."* Filed 2026-09-08T22:00Z off
`docs/research/offbox-green-floor-refutation-2026-09-08.md`.

**The finding, stated first:** the fork stays closed, and it is now closed for a *mechanical* reason
rather than a statistical one. Two suites — `mcp-no-inherit` and `mcp-ssot-wire` — were red in **11
of 11** clean post-cure folds, so **every** fold contained a deterministic red and a pass-on-retry
policy would have minted **0 greens in 11 folds**. Both were red for the same cause, found here and
fixed: `scripts/mcp-ssot-wire.sh` carried an apostrophe inside a `<<'PY'` heredoc nested in a `$( )`,
which **bash 3.2 cannot parse**. macOS `/bin/bash` is 3.2 and the runner uses it; the operator's PATH
puts brew bash 5.3 first. The script died at parse time off-box and ran fine on the desk.

## 1 — The cadence premise HOLDS, but it is a regime, not a constant

Re-measured over **459** scheduled runs (full history via the API, not the `-L`-capped CLI list):

| window | folds/day | gap median | gap max |
|---|---|---|---|
| the predecessor's own window (2026-08-31 → 09-08) | **7.33** | 3.28 h | 5.64 h |
| post-cure (2026-09-08T15:02Z → 09-10T18:25Z) | **7.02** | 3.99 h | 5.06 h |
| all history (2026-08-10 → 09-10) | 14.62 | 1.01 h | 13.28 h |

The predecessor's 7.32/day reproduces to two decimals in its own window, and the post-cure window
agrees. Its projection arithmetic stands.

**What does not stand is the word "GitHub drops roughly 70% of the hourly schedule"**, read as a
standing property of the scheduler. Per-day delivery shows GitHub served the **full 24/day for
twelve consecutive days**, 2026-08-15 through 08-26, then fell to 3–9/day from 08-27 onward and has
stayed there:

    08-15..08-26   24 24 24 24 24 24 24 24 24 23 24 18     <- the cron delivered in full
    08-27..09-10    3  3  6  7  5  6  7  7  7  9  9  6  7  7  6

So 7.32/day is a correct denominator for projecting *today* and a wrong one for describing the
mechanism. Something changed on 2026-08-27; this note does not diagnose it. The operating rule is
the one the ship-policy table already takes: **re-measure the cadence at use, never quote it.**

## 2 — The post-cure green rate is 0, and the fork is answered

**Population, checked by CONTENT rather than by clock.** 16 scheduled folds were *created* after the
cure commit, but one — `34242770799`, started five minutes after it — ran a head committed eight
minutes *before* it, and is a pre-cure fold. `git merge-base --is-ancestor` excludes it; the clock
does not. **15 folds contain the cure, 14 completed, and none is green.** Of the 14, eleven are
*clean* (`suites == expected`, not a cut); one is a cut (60 unreported) and two reported more suites
than expected (`+41` each — duplicate shard folding, not analysed here).

Per-suite failure frequency across the 11 clean folds, oldest → newest:

    tests/mcp-no-inherit.bats            XXXXXXXXXXX  11/11   DETERMINISTIC
    tests/mcp-ssot-wire.bats             XXXXXXXXXXX  11/11   DETERMINISTIC
    tests/lr-reset-poller-inplace.bats   ....XXXXXXX   7/11   deterministic from fold 5
    tests/mailbox-wake-arm.bats          ...XXXXX.X.   6/11   unstable
    tests/idl-record-size.bats           ......XXXXX   5/11   deterministic from fold 7
    tests/cc-gc.bats                     X.X.X..X...   4/11   unstable
    tests/spawn-presence.bats            XXX........   3/11   CURED
    tests/deploy-parity.bats             XX.........   2/11   CURED
    tests/memory-index-drain.bats        X.......X..   2/11   unstable
    …plus 6 suites that went red together at fold 10 and stayed red

**The fork simulated against this population mints nothing.** A retry clears an *unstable* suite; it
cannot clear a deterministic one. Every one of the 11 folds contained at least one 11/11 suite, so
granting the fork in full would have published **0 greens**. That is no longer an inference from
n=1 — it is the whole post-cure record.

## 3 — The predecessor's repair population was REFUTED, in both directions

It named `deploy-parity`, `spawn-presence`, `memory-index-drain` as *"genuinely broken"* on a
two-legged on-box replay at one sha, and `cc-gc`, `mcp-no-inherit`, `mcp-ssot-wire` as *"machine-
coupled or unstable"* because they were green on this box. Measured across 12 folds the classes are
close to inverted: the first three are 2/11, 3/11 and 2/11 (two of them **cured** eight folds ago),
while two of the three "unstable" ones are the 11/11 floor.

Its own limits section named this exact risk — *"three greens on this box do not acquit `cc-gc`,
`mcp-no-inherit`, `mcp-ssot-wire` — one local green is a scalar sample of a varying quantity."* That
caveat was right, and cross-fold frequency is the instrument that settles what a single local replay
cannot. **A suite's determinism is a property measured across folds, not across two legs at one sha.**

## 4 — Root cause, and why it was invisible on the desk

Bash 3.2 does not recognise a heredoc delimiter inside `$( )`; it lexes the heredoc **body as shell
code**. `scripts/mcp-ssot-wire.sh:250` read:

    # Merge: set only the SSOT's own keys. An unrelated server already present is left alone.

inside `verdict="$( … python3 - "$f" <<'PY' … PY )"`. That lone apostrophe opened an unterminated
single-quoted string and killed the parse 38 lines later:

    /bin/bash: line 288: syntax error near unexpected token `fi'

The script exited 2 before doing anything, so every test case that *ran* it failed and the two cases
that only read JSON passed. Reproduced on this box with `bash` pinned to 3.2, the pre-fix file
replayed from git — **the off-box signatures match exactly**:

| suite | off-box, recorded | local pre-fix @ bash 3.2 | post-fix @ bash 3.2 |
|---|---|---|---|
| `mcp-ssot-wire` | 2 ok / 10 not ok | **2 ok / 10 not ok** | 12 ok / 0 |
| `mcp-no-inherit` | 20 ok / 1 not ok | **20 ok / 1 not ok** | 21 ok / 0 |

`mcp-no-inherit` shares the cause because its case 5 runs the same script.

**The fix is a comment reword.** The behaviour is untouched.

## 5 — The guard

An apostrophe ban would enumerate one *spelling* of the class. `scripts/bash32-parse-lint.sh`
asserts the *property*: every tracked file with a bash/sh shebang must parse under the real
`/bin/bash` 3.2 — which is what the runner actually does, so the check cannot drift from it. It is
**controlled**: a file is reported only when it fails under 3.2 *and* parses under a modern bash, so
a plain syntax error is some other lint's finding and this ratchet cannot take credit for it.

Measured on the tree: **554 scripts scanned, this was the only instance.** The ratchet ships green.
`tests/bash32-parse-lint.bats` carries the red-proof (the scar shape is caught), three controls (the
apostrophe-free twin is not flagged; a both-bashes-broken file is not claimed; a `.bats` file is
excluded by extension), the real pre-fix artifact replayed from git by blob sha, and a non-verdict
case (unusable environment exits 2, never a false green). Four mutants — drop the control arm, never
report, drop the exclusion, downgrade the non-verdict to 0 — each kill their case.

## 6 — What actually stands between the producer and a green

**The predecessor's framing of this lever is REFUTED, and the refutation is the useful part.** It
wrote that *"nothing today tells the author of a new suite that it just took the producer red."*
Something does: `scripts/offbox-admission-lint.sh` landed **2026-08-12** for exactly this generator —
it runs in the land gate and REFUSES a land that adds a suite which is not off-box-clean. (It ran on
this land and admitted the new ratchet, *"green off-box"*.)

So the question is not why the gate is missing. It is why it **admitted these**. Of the ten
deterministic suites, eight went red *during* the 11-fold window (one at fold 5, one at fold 7, six
together at fold 10), and six of the ten were added *after* the gate was in force.

For the two floor suites the answer is now known, and it is the gate's own stated blind spot. Commit
`35284465e` (2026-09-08) added `scripts/mcp-ssot-wire.sh` **with the apostrophe** and
`tests/mcp-ssot-wire.bats` together, and dragged `mcp-no-inherit` (added 2026-08-11) red with it,
since its case 5 runs that script. The gate ran and admitted, because the gate **runs on this box**:
`offbox-run.sh` passes `PATH="${PATH}"` through, so a bare `bash` resolves to brew 5.3 here and to
`/bin/bash` 3.2 on the runner. Its own header says so without hedging — it reproduces the
environment axes *"and NOT the machine axes … a different brew prefix"*, and argues that stating the
limit beats a gate that claimed to cover it.

**Bash version is a machine axis.** That is the gap `scripts/bash32-parse-lint.sh` closes, and it is
why the ratchet belongs in the *statics* gate rather than in the off-box runner: it is checkable here
precisely because it does not need the runner — `/bin/bash` 3.2 is already on this box.

The remaining six deterministic suites are **not** explained by this, and why admission passed them
is unmeasured here.

## 7 — Honest limits

- **The fix is verified locally, not off-box.** The next scheduled fold whose head contains it is the
  proof; this note's claim is the exact-signature reproduction in §4, not an observed green.
- **Clearing the floor does not imply a green.** Eight other deterministic suites remain, and the
  11-fold record shows 4–16 reds per fold. Expect the *next* floor, not a green.
- **The two `+41` folds are unexplained** and were excluded rather than diagnosed.
- **`.bats` files are out of the lint's population** by extension — bats parses them with the bash it
  resolves, never a bare `bash`.
- **The 24-fold threshold in the parent row was not reached** (15 folds contain the cure). It is not what the fork
  turned on: two suites red in 11/11 consecutive folds cannot be flipped by more folds, only by
  repair. Waiting was never the lever.

## Disposition

Fork: **do not put it to the operator.** It would have published nothing in 11 of 11 folds.
Repair population, corrected: `mcp-no-inherit` + `mcp-ssot-wire` (**fixed here**),
`lr-reset-poller-inplace`, `idl-record-size`, and the six that went red at fold 10
(`session-index-history-gapfill`, `runner-stdin-immunity`, `capacity-alarm-chronic`,
`cc-jetsam-exec`, `validate-bash-differential`, `cc-read-twitter`) — eight suites whose logs
show unrelated failures across unrelated subsystems, so they are eight distinct defects and
not one fix.
Next lever: §6 — why admission passed them.
