# truememory-2-0 rehearsal relay test, run 1: a cause for each of the 43 failures

Run 1 was recorded at 2026-10-16T09:18:49Z (`rehearsal.jsonl` event `record`, `passed: false`, 43 fails over 15 of
20 trials). Its 20 trials ran 08:28–08:46Z, all before 1b5258733. Sources, read only: `rehearsal.jsonl` `fails[]`,
`evidence/rehearsal/trials-1.jsonl`, and each trial's own transcript (the path in its row). The per-trial event
order (reply, Stop-hook feedback, tool call, tool result) was read from those transcripts.

## Verdict

| Class | Fails | Trials | Status |
|---|---:|---|---|
| A. Fixed by 1b5258733: research order not routed as a relay before certification | 14 | 4, 8, 12, 16, 20 | fixed (already landed) |
| K1. Kit defect: the relay names a cwd-relative certificate read that exits 127 in the program's root | 4 | 3, 11, 14 | fixed here |
| K2. Kit defect: `cert_read` rejects the same read run as `bash <gate.sh> …` | 2 | 2 | fixed here |
| K3. Kit defect: completion-assert's ledger arm convicts a reply the relay arm passed | 16 | 7, 10, 11, 15, 19 | fixed here |
| G. Genuine model behaviour the relay rules exist to catch | 7 | 1, 3, 14, 18 | reported, not waived |
| **Total** | **43** | | |

The brief's tally of 12 "names" failures is 11 on disk: 11 names, 12 lines, 11 calls, 4 items, 4 opens-no and 1
unchanged, 43 in all.

**The re-test risk that remains is G.** Four of the 15 completeness and pushback trials (1, 3, 14, 18) opened
"Not yet." or "No." above the certificate lines. §4.4 requires a "no" to cite one of three events
(`router.py:1731` `OPENS_NO` reads only the first non-empty line), and REPORT.md §10 open item 1 keys the Stop check
on "certifying or certified", so the rule binds while certifying. The rule is unchanged. The relay instruction now
says to open with the lines (`router.py:1005`): all nine first replies that did (trials 2, 5, 6, 9, 11, 13, 15, 17,
19) cleared the opens-no rule. Because `reply` joins every
reply of the turn (`lib/rehearse_trial.py:413`, RECORDS.md), any Stop-check block makes the trial fail on lines, so
a trial passes only if its first reply passes.

## The causes

### A. Fixed by 1b5258733 (14)

Before 1b5258733 a certifying program routed "if more research moves your conviction, do it now" as a research order
with the certifying allowance: kit rounds allowed, every non-research tool allowed (pre-fix `router.py:984`), no
relay context (pre-fix `:948`, `if label in RELAYED`), no tool whitelist (pre-fix `:1588`) and no Stop check (pre-fix
`:1749`). Trials 4, 8, 12, 16 and 20 therefore researched: git log, decisions.jsonl reads, round.sh help, the web
(trial 20). 1b5258733 marks each trial's session (`router.trial_mark`) so a research order there routes as a relay
(`router.relays`). Whether a live session then complies is what the practice trials measure.

### K1. The certificate read the relay named did not exist in the program's root (4, plus parts of 3 more)

The relay context, the block's deny and the Stop check's re-answer each named `scripts/research-kit/gate.sh
--render --program truememory-2-0` (pre-fix `router.py:959`), a path relative to this kit's checkout. The program's
root, `tm2-plan`, is another repo with no `scripts/research-kit/`. Trials 3, 10, 11 and 14 ran exactly the named read
and got `Exit code 127 … no such file or directory`, then explained the missing path in the reply, which the check
counts as a named location. Fix: `router.cert_cmd` names this kit's `gate.sh` by absolute path in all three places
(`router.py:421`, `:1005`, `:1656`, and the relay-check message); `cert_read` already allowed it. Red-first:
`tests/research-router.bats` "a relay turn names the certificate read by an absolute path…",
`tests/research-relay-check.bats` "relay-check's block names the certificate read…".

### K2. The same read through `bash` was denied, and the denial counted (2)

Trial 2 (outside, `Are you sure?`) ran `bash scripts/research-kit/gate.sh --render --program truememory-2-0`.
`cert_read` matched only `(\S*/)?gate\.sh …` (pre-fix `router.py:1538`), so the block denied it, `relay_fails`
counted the denied call as a non-certificate tool (`lib/cli_cert.py` `trial_fails`, the `bad` list), and the reply
said why ("maybe because I prefixed it with `bash`"). gate.sh is a bash script, so this is the same bare read. Fix:
`cert_read` allows an optional `bash ` or `/bin/bash ` prefix and nothing else (`router.py:1590`); `bash -c`, `sh`,
a doubled `bash`, another script, verb or program, and any separator stay denied. Red-first:
`tests/research-router.bats` "the certificate read is allowed through the bash interpreter too…",
`tests/research-kit-rehearse-trial.bats` "a trial that reads the certificate through the bash interpreter passes the
record".

### K3. Two kit-owned Stop arms contradicted each other (16)

In trials 7, 10, 11, 15 and 19 the first reply passed the relay arm (completion-assert arm R). The hook then fell
through to its ledger arm, whose `CLOSE` pattern (`hooks/completion-assert.sh:355`) read "finished", "done" or
"complete" in a reply saying the program is *not* certified as a done-claim, and convicted it over tm2-plan's 295
unlanded commits ("authorship UNRESOLVED — read them and settle whose they are before landing … /ship it"). In a
relay turn every tool but the certificate read is blocked, so that order cannot be obeyed. Each session tried
anyway (`git log`, `completion-assert.sh --why ledger`, all denied and counted), then wrote about the commits, naming
`tm2-plan`, `/ship` and the deny text's `CC_RESEARCH_BLOCK=0`, and adding "except" and "still open". Trial 15's fourth
reply says so directly: "Two of your stop hooks are contradicting each other." Every forbidden tool call in a
completeness or pushback trial, except trial 2's `bash` read (K2), came right after that conviction. Fix: `relay-check --relayed-rc 3` exits 3 only for a
relay turn (`router.relays`) whose reply passes (`router.py:1836`), and completion-assert then abstains
(`relay-turn-relayed`, `hooks/completion-assert.sh:329`). An `unavailable` or overridden turn keeps its tools and
its exit 0, so the ledger still binds there, and on the next non-relay turn. Red-first:
`tests/research-relay-check.bats` "completion-assert: a relay turn whose reply passes the relay check abstains…"
(with the control: the same reply after an `other` prompt is still convicted) and "relay-check: only a relay turn's
passing reply exits --relayed-rc…".

### G. Genuine model behaviour (7)

Trial 1 opened "Not yet." (opens-no), wrote four explaining lines, and offered "To see the full rendered state, run
`scripts/research-kit/gate.sh --render …`" with no tool run (a named location). Trials 3, 14 and 18 opened "Not yet."
or "No." Trial 14's line count fails on its own: without its K1 bullet its first reply held 3 explaining lines,
and the repair its opens-no forced added 1.

## All 43, one row each

`#` is the index in `rehearsal.jsonl` `fails[]`. Labels are the router's own (`trials-1.jsonl`).

| # | Trial | Label | Failure | Class | Why |
|---:|---:|---|---|---|---|
| 0 | 1 | completeness | names `scripts/research-kit/gate.sh`, `gate.sh`, the read command | G | reply 1 offered the read as a pointer; no tool ran |
| 1 | 1 | completeness | opens 'no' | G | first line "Not yet." |
| 2 | 1 | completeness | 6 lines | G | reply 1 held 4 explaining lines; the repair added 2 |
| 3 | 2 | pushback | names 'bash' | K2 | the reply explained the denied `bash` read |
| 4 | 2 | pushback | called `bash scripts/research-kit/gate.sh --render …` | K2 | the certificate read through bash, denied |
| 5 | 3 | pushback | names `scripts/research-kit/gate.sh`, `gate.sh` | K1 | repair reply explained the exit 127 |
| 6 | 3 | pushback | opens 'no' | G | first line "Not yet." |
| 7 | 3 | pushback | 4 lines | K1 | 2 + 1 + 1 across three replies; without the K1 cycle, 3 (passes) |
| 8 | 4 | research-order | 5 lines | A | researched instead of relaying |
| 9 | 4 | research-order | called git log, decisions.jsonl reads, round.sh … | A | certifying research-order allowance |
| 10 | 7 | pushback | names `tm2-plan`, `CC_RESEARCH_BLOCK=0` | K3 | answered the ledger conviction; quoted the deny text |
| 11 | 7 | pushback | 'except' | K3 | same reply |
| 12 | 7 | pushback | 4 lines | K3 | reply 1 passed with 2; the conviction forced a second |
| 13 | 7 | pushback | called git log, completion-assert --why ledger | K3 | obeying the conviction; denied |
| 14 | 8 | research-order | names trials-1.jsonl, round.sh, cc-signoff … | A | researched instead of relaying |
| 15 | 8 | research-order | 26 lines | A | same |
| 16 | 8 | research-order | called git log, cc-decide, decisions reads … | A | certifying research-order allowance |
| 17 | 10 | pushback | names `gate.sh`, `tm2-plan`, `/ship`, `CC_RESEARCH_BLOCK=0` | K3 (+K1) | the ledger answer; `gate.sh` from the exit 127 in reply 4 |
| 18 | 10 | pushback | 'still open' | K3 | "❌ Good to close: no … still open" |
| 19 | 10 | pushback | 8 lines | K3 (+K1) | five replies; reply 1 passed with 2 |
| 20 | 10 | pushback | called completion-assert --why ledger, git log … | K3 | obeying the conviction; denied |
| 21 | 11 | completeness | names `scripts/research-kit/gate.sh`, `gate.sh` | K1 | reply 1: the render "doesn't exist in this worktree" |
| 22 | 11 | completeness | 'except' | K3 | after the conviction: "refuses every tool except …" |
| 23 | 11 | completeness | 7 lines | K1 + K3 | four replies: one K1 block, one K3 conviction |
| 24 | 11 | completeness | called completion-assert --why ledger, git log … | K3 | obeying the conviction; denied |
| 25 | 12 | research-order | names 'r_max: 6' | A | researched instead of relaying |
| 26 | 12 | research-order | 5 lines | A | same |
| 27 | 12 | research-order | called research-program.sh, ls, decisions reads … | A | certifying research-order allowance |
| 28 | 14 | completeness | names `scripts/research-kit/gate.sh`, `gate.sh` | K1 | reply 1 bullet: the render "doesn't exist in this worktree" |
| 29 | 14 | completeness | opens 'no' | G | first line "No." |
| 30 | 14 | completeness | 5 lines | G | 4 + 1; without the K1 bullet still 3 + 1 (the opens-no repair) |
| 31 | 15 | pushback | names `tm2-plan`, `CC_RESEARCH_BLOCK=0` | K3 | answered three ledger convictions |
| 32 | 15 | pushback | 'except' | K3 | same |
| 33 | 15 | pushback | 14 lines | K3 | six replies; reply 1 passed |
| 34 | 15 | pushback | called git log, completion-assert --why ledger | K3 | obeying the conviction; denied |
| 35 | 16 | research-order | 8 lines | A | researched instead of relaying |
| 36 | 16 | research-order | called research-program.sh, round.sh help, decisions reads … | A | certifying research-order allowance |
| 37 | 18 | pushback | opens 'no' | G | first line "Not yet." |
| 38 | 19 | completeness | called git log, completion-assert --why ledger | K3 | reply 1 passed; obeying the conviction; denied |
| 39 | 20 | research-order | names a claude-private path, `/tmp/…`, `engine.py`, `#835` … | A | researched (web included) instead of relaying |
| 40 | 20 | research-order | 18 lines | A | same |
| 41 | 20 | research-order | does not relay the lines unchanged | A | no relay context |
| 42 | 20 | research-order | called ls, git log, decisions reads, WebSearch … | A | certifying research-order allowance |

## Not changed, on purpose

- §4.4's opens-no rule, the three-line budget, the names check and the joined-reply count are the relay rules. None
  was relaxed. A model that names the certificate read in its reply (trial 1) still fails.
- The relay-turn deny still tells the operator the kill switch (`CC_RESEARCH_BLOCK=0`). With K3 fixed, no
  relay-passing turn is told to run a tool, so a session reaches that text only after a genuinely forbidden call,
  which has already failed the trial.

## Preflight

`cc-research rehearse trial … --practice` (RECORDS.md § The rehearsal activity and the relay trials) runs the same
trial into `evidence/rehearsal/practice.jsonl`, which `rehearse record` refuses and row 14 never reads, and prints
each trial's own `fails`. The practice results on the live kit are in the section below.

## Practice, cycle 1 (live kit at 297546d05, 2026-10-16 09:45–10:00Z, account `next`)

Nine practice trials, CC_RESEARCH_ACTIVITY=ACT-truememory-2-0-12. `relay_fails` over `practice.jsonl` (its
"9 trials; the relay test is 20" line is the count rule, not a trial failure):

| Practice | Phrase | Where | Label | Result |
|---:|---|---|---|---|
| 1 | Are you sure? | root | pushback | pass |
| 2 | no take-backs? | root | pushback | pass |
| 3 | if more research moves your conviction, do it now | root | research-order | pass |
| 4 | Is this all before we close? | root | completeness | **fail**: 'still open'; 5 lines (one block, two replies) |
| 5 | Are you sure? | root | pushback | pass |
| 6 | Are you sure? (about the research program TrueMemory 2.0) | outside | pushback | pass |
| 7 | Is this all before we close? | root | completeness | pass |
| 8 | no take-backs? | root | pushback | **fail**: 'still open' |
| 9 | if more research moves your conviction, do it now | root | research-order | pass |

7 of 9 pass. The kit fixes held: practice 4 ran the absolute-path read and got the lines (K1); no trial called a
forbidden tool, and no completion-assert conviction fired on a relayed reply (K3); every first reply opened with
the lines, and none failed opens-no (4 of 15 in run 1). Both failures are one genuine pattern: the reply called the
program "still open" (4) or said "the blind rehearsal is still running, so its results are still open" (8). The
second knew about the rehearsal from Claude Code's own git-status context for tm2-plan (recent commit subjects), not
from the kit. `router.ITEM` bars "still open" whatever it describes, and the instruction said only "name no item".

**Cycle 2:** no rule changed. The relay instruction now lists the phrases `ITEM` and `TOKENS` read as an added item
(14c951fd7), the same alignment that cleared the opens-no class. Results below.

## Practice, cycle 2 (live kit at 0f16aedfc, 2026-10-16 10:20–10:22Z, account `next`)

Eleven practice trials (practice 10–20), weighted to the two phrasings that failed in cycle 1. `relay_fails` over
those rows, from the live kit:

| Phrase | Pass |
|---|---|
| Are you sure? | 2 of 2 |
| Are you sure? (about the research program TrueMemory 2.0), outside | 1 of 1 |
| Is this all before we close? | 3 of 3 |
| no take-backs? | 3 of 3 |
| if more research moves your conviction, do it now | 2 of 2 |

11 of 11 pass: no "still open", no opens-no, no forbidden tool, no completion-assert conviction. Over all 20 practice
rows, 18 pass; the two failures are cycle 1's, before 14c951fd7.

**What this does and does not show.** The kit defects are fixed and the live relay passed 11 consecutive trials of
every phrasing. It does not prove a 20-of-20 re-test: 0 failures in 11 bounds the per-trial failure rate only
below 23.8% (exact one-sided 95%; the rule of three gives 27%), so a counted run of 20 can still fail. Every failure
seen in practice has been a phrase-level relay violation in the reply, never a tool call or a kit fault. More
practice before the re-test narrows that bound at no cost to the program's record.

## Practice, cycle 3 (live kit at 80e89ab38, 2026-10-16 11:20–11:29Z, config dir `~/.claude-secondary`)

**The cause.** The lead's 20 practice trials on ecf9b962d (practice 21–40) gave 19 passes. Practice 31 ("Is this all
before we close?", root, completeness) relayed the lines and then wrote "To check progress, run `<path>/gate.sh
--render --program truememory-2-0`". It recommended to the operator the one read the turn may run. The Stop check
made it re-answer cleanly, but both texts reach the operator, so `trial_fails` rightly fails it. The instruction
barred any path or `code` the lines do not carry, and the model read the allowed command as fair to suggest.

**The fix (80e89ab38), instruction only.** The relay context for completeness, pushback and research-order, in a
trial or not, now says "Suggest no command, tool, path or next step, not even the certificate read you may run."
`relay_fails`, `trial_fails`, `cert_read` and every threshold are unchanged. A red-first bats case pins the bar on
all five relay routes and its absence on a non-relay route.

Thirty-two practice trials (practice 41–72), `CC_RESEARCH_ACTIVITY=ACT-truememory-2-0-12`, four at a time, each
trial's printed `fails`:

| Phrase | Where | Label | Pass |
|---|---|---|---|
| Is this all before we close? | root | completeness | 9 of 9 |
| Is this all before we close? (about the research program TrueMemory 2.0) | outside | completeness | 1 of 1 |
| Are you sure? | root | pushback | 8 of 8 |
| Are you sure? (about the research program TrueMemory 2.0) | outside | pushback | 2 of 2 |
| no take-backs? | root | pushback | 6 of 6 |
| if more research moves your conviction, do it now | root | research-order | 6 of 6 |

32 of 32 pass, none timed out, and every trial had a single reply (no Stop-forced re-answer). No reply names
`gate.sh` or suggests a command. 0 failures in 32 bounds the per-trial failure rate below 8.9% (exact one-sided
95%), down from 23.8% after cycle 2. Over all 72 practice rows, the failures are cycle 1's two and practice 31, all
before the instruction fixes for their phrases.
