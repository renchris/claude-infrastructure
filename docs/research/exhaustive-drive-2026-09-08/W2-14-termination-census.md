# W2-14 — the session-termination census, as an instrument

**THE NUMBER (2026-09-09T03:34Z, 123 dead main-chain sessions in the last 24 h):
self-close 42.3% · Stop 29.3% · killed 13.0% · drain-recycle 7.3% · recycle 6.5% ·
api-error 0.8% · frozen 0.8%. Stop-chain coverage — the denominator every "% of Stops"
figure in this wave needs — is 32.5% (40 of 123), not 24%. Self-closed sids in the last
24 h: 52 (W2-B1's trigger population).**

Verdict for W3: **CROSSES 90 — conviction 94.** The instrument is built, committed, runs
in ~2 s, is red-proved 7/7, and its named consumer prints the denominator today. Two of
the critic's §0 figures are corrected in the process, and both corrections change what W3
should build.

---

## 1. The number

`scripts/measure-terminations.py --days 1`, read 2026-09-09 ~03:34Z. The corpus is live:
sessions retire and start while it runs, so three readings 20 minutes apart gave
dead = 126 / 125 / 123 with the shares stable to under a point. Quote the shares, not the
counts.

| terminal class | n | % of dead sessions | Stop chain runs? |
|---|---:|---:|---|
| **self-close** (`handoff-fire.sh self-close`) | 52 | **42.3 %** | no |
| **stop** (clean `end_turn`) | 36 | **29.3 %** | yes |
| **killed** (RESIDUAL — see §4) | 16 | **13.0 %** | 4 of the 16, yes |
| **drain-recycle** (`drain-recycle-fire.sh`) | 9 | 7.3 % | no |
| **recycle** (`handoff-fire.sh --recycle`) | 8 | 6.5 % | no |
| **api-error** | 1 | 0.8 % | no |
| **frozen** (a permission prompt pending on the terminal command) | 1 | **0.8 %** | no |
| TOTAL | 123 | 100 % | |

**Stop-chain coverage: 40 of 123 = 32.5 %.** Retired inside a tool call: 69 = 56.1 %.

Over 30 days the same instrument reads 1,875 dead sessions: stop 37.9 % · killed 20.0 % ·
self-close 19.1 % · recycle 13.3 % · drain-recycle 7.4 % · api-error 2.1 % · frozen 0.2 %;
coverage 39.4 %. **Prefer today's number** — §3 explains why the 30-day one has an
18-point uncertainty band and today's has a 6-point one.

## 2. Method

```
python3 scripts/measure-terminations.py --days 1          # the table above
python3 scripts/measure-terminations.py --days 1 --denominator   # the one consumer line
python3 scripts/measure-terminations.py --selftest        # 26 assertions, 7/7 classes
```

Committed at `scripts/measure-terminations.py` (sibling of `scripts/measure-closes.py`,
whose four-root corpus walk and per-root reporting shape it reuses). Per dead main-chain
session it takes the last conversational record (`type ∈ {assistant,user}`,
`isSidechain ≠ true`) from the tail 1.5 MB and tests, in this order:

1. `isApiErrorMessage` → **api-error**. Tested first on purpose: an API-error record *is*
   an assistant text record, so a Stop test running ahead of it counts a quota death as a
   clean close.
2. assistant, text-only, `stop_reason ∈ {end_turn, null}` → **stop**.
3. the last `tool_use` command, matched against `drain-recycle-fire.sh` → **drain-recycle**
   (before `--recycle`, because it is a `--recycle` wrapper), then `handoff-fire.sh …
   self-close` → **self-close**, then `handoff-fire.sh … --recycle` → **recycle**. Anchored
   on the *script name*, never the bare verb: `self-close` alone matches a session that only
   greps for the string (MEMORY.md `pgrep-f-matches-agent-briefs`).
4. the permission join → **frozen**.
5. everything else → **killed**, sub-split.

Liveness is the beat store's `(pid, lstart)` identity against a `ps -Ao pid=,lstart=`
snapshot — never argv. An unreadable process table makes the census **abstain (rc 2)**
rather than report, because guessing there calls the entire fleet dead.

### 2a. The instrument-level defect this measurement had to fix first

**A strict string compare of `lstart` reads every live session as dead.**
`hooks/session-beat.sh:93` writes `TZ=UTC ps -o lstart=` — TZ pinned, **locale not** — so
the beat store holds `Wed 9 Sep 03:19:56 2026`, while any reader that pins `LC_ALL=C` (as
a deterministic reader must) gets `Wed Sep  9 03:19:56 2026` **for the same live process**.
Measured on 142 in-window transcripts: strict compare → 134 dead / **0 alive**; parsed
compare → 115 dead / 19 alive. Nineteen false convictions, 13 % of the population, and the
failure is silent — a census that over-counts dead sessions reads as a busier day, never as
a broken instrument. `bin/cc-reaper:2590-2604` already carries a three-arm compat ladder for
exactly this; `norm_lstart()` expresses the same fact as a parse. MEMORY.md
`process-start-time-renders-in-ambient-timezone` names the TZ half of this; this is the
locale half, on the same axis.

## 3. Population and every excluded stratum

Denominator = **dead main-chain sessions**, 123 in the 24 h window. Excluded, each named:

| excluded | n (1 d) | n (30 d) | why, and which direction it biases |
|---|---:|---:|---|
| **alive** | 19 | 18 | its terminal event has not happened. No bias — they enter the census when they end. |
| **no-beat** (liveness UNKNOWN) | 8 | **417** | no beat file, so neither dead nor alive can be asserted. Never assumed dead. |
| **`agent-*` / `/subagents/`** | n/a | n/a | a subagent has no session to terminate; `measure-closes.py:265` excludes the same family. |
| `~/.claude-next/projects` | — | — | realpath-identical symlink to `~/.claude/projects`; excluded so it can never double-count. |
| malformed transcript lines | 0 | 5 | counted and reported, never silently dropped. |

**The `no-beat` stratum is why today's number is the sound one.** If every unknown session
were dead, coverage would lie in **[30.5 %, 36.6 %] — a 6.1 pp band — over 24 h**, but in
**[32.2 %, 50.4 %] — an 18.2 pp band — over 30 days**, because the beat store holds ~3,084
files and older sessions' beats are reaped. A 30-day coverage figure is a real measurement
with a band wide enough to contain both "a third" and "a half"; the 24 h figure is not.

Store reaches differ and no figure may be read past its store: transcripts go back months,
the **IDL only 11 days** (8 gz archives from 2026-08-29), the permission *archive* months,
and the pending-permission *beacon* only to the last reboot (0 on disk at the reading).

## 4. `killed` is a residual, and is labelled as one

There is no positive kill record on this box — no journal keys a SIGTERM to a sid — so
`killed` is defined by **exclusion**: a dead session that reached no Stop, ran no retirement
command, hit no API error, and joins to no permission prompt. It must never be read as "16
sessions were killed"; it is "16 deaths this instrument cannot name". It is reported with a
sub-breakdown so it is not opaque: after-prompt 5 · **after-stop-block 4** · after-result 3 ·
dangling-tool 2 · no-conversational-record 2.

## 5. Two corrections to CRITIC §0, and both change W3's target

**(a) The Stop chain governs a third of terminations, not a quarter (24 % → 32.5 %).** Four
sessions today died with their last record a **Stop-hook block** (`Stop hook feedback: …`).
The critic's ladder — "last conversational record = assistant `end_turn`" — puts those in the
82 no-Stop sessions, but they *did* reach a Stop and the Stop chain *did* run on them; they
died before taking the turn the block demanded. That is the difference between "the hooks
never see them" and "the hooks saw them and the session died mid-remedy", and only the second
is a bug in the hooks. Coverage is therefore reported as `stop + killed:after-stop-block`,
and the census prints the split.

**(b) Freezing is common; dying frozen is rare — 26.0 % vs 0.8 %.** The critic's "22 sessions
carried a > 300 s permission prompt today" and this census's `frozen = 1` are **not the same
population and neither is wrong**. A permission freeze is a *mid-life* state: a session can
freeze 19 h, be granted, and then self-close, and its terminal class is `self-close` — which
is correct. So the census reports freeze twice: as a terminal class (1 session, 0.8 %) and as
an **orthogonal overlay** — 32 of 123 sessions (26.0 %) carried a ≥ 300 s wait somewhere in
life, of which 19 terminally self-closed, 4 reached a Stop, 6 recycled, 2 are residual.
**W3 consequence:** a remedy aimed at "sessions frozen to death" targets ~1 session/day. The
real freeze channel is 32/day, and it is discharged by a grant, not by a close gate. Any
close-side remedy for freezing would be a correct fix pointed at 3 % of its own phenomenon.

**Compounding with A02-skeptic.** A02's skeptic found that ~24 % of its *close* population
are non-closes (API errors, one-word replies, decider verdicts). That is a denominator defect
*inside* the Stop stratum; this one is the stratum's *size*. Indicatively they multiply:
a "% of closes" figure in this wave spans roughly **32.5 % × 76 % ≈ 25 %** of terminations.
Indicative only — A02's 24 % is a share of close records, not of terminations.

## 6. The consumer — which line, and where

`scripts/idl-abstain-alarm.sh` had no "% of Stops" line, but **every row of its per-hook
table is one**: `total=` and `abst=` count *evaluations* of hooks that are Stop hooks, so a
row can only ever count sessions that reached a Stop. A reader of `waiting-recycle total=17634
abst=17630` reads a rate over sessions and gets a rate over a third of them.

The denominator now prints as the **first line of the sweep table**, immediately above the
per-hook rows (`census_denominator`, called at the head of the row loop in `sweep()`), so no
row can be read without it. Live output (captured ~20 min before the §1 reading — the counts
differ because the corpus moves, which is itself the point of §8's last row):

```
  termination-census (1d): 41 of 125 dead main-chain sessions reached a Stop (33%) — 70 (56%)
  retired inside a tool call and are invisible to every hook counted above
  HEALTHY     anti-deference-nudge   total=640  abst=617  fired/passed=23  failed=0   blind=4   (0%)
  ...
```

It is **fail-open and cannot take the sweep down**: no `python3`, a missing script, or a
census abstention prints an explicit `denominator: UNKNOWN` line rather than nothing —
a missing denominator line and a denominator of 100 % read identically to a human and only
one is true (MEMORY.md `fail-safe-default-mimics-the-healthy-state`). `CC_ABSTAIN_CENSUS=0`
suppresses it; `CC_ABSTAIN_CENSUS_CMD` re-points it for tests. Cost ~2 s on ~150 transcripts.

## 7. Red-proof

`python3 scripts/measure-terminations.py --selftest` → **26 assertions, 0 failed**, including
7 synthetic transcripts classifying **7/7**. Its arms: the locale parse (the §2a defect, both
renderings and the unparseable case); store pinning; 7/7 classification; an in-suite mutation;
the ordering traps (a drain-recycle carrying `--recycle`; a session that merely *greps* for
`self-close`; an api-error with `stop_reason: end_turn`); coverage counting a blocked Stop;
the empty-population UNKNOWN; and abstention on an unreadable process table.

**The red is reachable, shown by mutating the classifier, not the assertion:**

| mutant | selftest |
|---|---|
| the `drain-recycle` test deleted (falls through) | `FAIL drain-recycle classified as killed` · **22 passed, 4 failed, rc 1** |
| the `api-error` test deleted (a quota death would read as a Stop) | `FAIL api-error classified as killed` · **22 passed, 4 failed, rc 1** |
| `census_denominator` call deleted from the alarm | `FAIL W missing census printed nothing at all` · alarm selftest **RED** |

`scripts/idl-abstain-alarm.sh --selftest` → **48 passed, 0 failed** (44 before, +4 for the
new line: it appears, the UNKNOWN branch fires, the hook table still renders under it, and
`CC_ABSTAIN_CENSUS=0` suppresses it).

**No fixture reaches a live store.** All five store seams are pinned into one temp sandbox
per run — `CC_TERM_ROOTS`, `CC_TERM_BEATS_DIR`, `CC_PERMARCHIVE_DIR`, `CC_PERMPEND_DIR`,
`CC_TERM_PS_FILE` — and the selftest *asserts* each resolved path starts with the sandbox
before it runs anything. Rank 4's lesson is that one unpinned store is the whole leak:
`tests/completion-assert.bats` pinned `COMPLETION_IDL` and drove `session-continue` 16 times
with `CONTINUE_IDL` unpinned, putting 312 `dbl-*` rows into the live decision journal. The
census is read-only over every live store and writes nothing anywhere.

## 8. What a wrong reading looks like (the fail direction)

| the wrong reading | what produces it | which way it errs |
|---|---|---|
| "N sessions were **killed**" | reading the residual as a mechanism | over-states harness/OS deaths. `killed` is what the instrument could not name. |
| "only 1 session/day is hit by permission freezes" | reading the terminal class and skipping §5(b) overlay | under-states the freeze channel **32×**, and would kill CRITIC §0's largest measured leak. |
| "the Stop chain covers 24 %" | the critic's `end_turn` ladder, without the blocked-Stop split | under-states coverage 8 pp, and mis-attributes 4 deaths/day to "hooks never ran". |
| "coverage is 39 % (30 d)" quoted as a point estimate | ignoring the 417-session `no-beat` stratum | the true value lies anywhere in [32.2 %, 50.4 %]. Quote the 24 h figure. |
| **"the fleet is dead"** — 0 alive of 142 | a strict `lstart` string compare (§2a) | the silent one, and the only failure here that looks like data rather than a bug. |
| "coverage is stable at 32.5 %" | quoting a count from a live corpus | the corpus moves under the reader; three readings 20 min apart gave 126/125/123 dead. Shares are stable, counts are not. |

An honest abstention is designed to be visible everywhere: the census exits 2 with
`ABSTAIN` on an unreadable process table, prints `UNKNOWN` rather than 100 % on an empty
population, and the alarm prints `denominator: UNKNOWN` rather than dropping the line.

## 9. Verdict for W3

**CROSSES 90 — conviction 94.** SYNTHESIS rank 14 stood at 88 → 90 "consumer named", with
the stated risk *"errs toward another counted line nobody reads unless the alarm consumes
it"*. That risk is **discharged, not argued**: the consumer is built, the line prints today
above the table it corrects, and its absence is red-proved. The residual 6 % is the
`no-beat` stratum's reach over long windows (§3) and `killed` being a residual (§4) — both
stated in the instrument's own output, neither affecting the headline.

**For W2-B1 (self-close refusal, CRITIC C-R1): the trigger population is 52 self-closed
sids in the last 24 h**, enumerated by `--days 1 --json` (field `cls == "self-close"`); B1's
own gate is to run `wrap-ledger --machine` in their cwds and land the refusal iff under 10 %
would refuse. Note for B1: 19 of those 52 also carried a ≥ 300 s permission freeze in life,
so a refusal that makes a pane stay open must not be able to re-block on a prompt nobody is
there to answer.
