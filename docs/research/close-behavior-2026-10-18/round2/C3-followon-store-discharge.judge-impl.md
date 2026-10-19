# C3 judge, implementability and regression lens

Judge: adversarial (impl). Subject: `round2/C3-followon-store-discharge.md` (D8 v2/v2b) and its prototypes
`/tmp/r2-C3/repo/` (v2) and `/tmp/r2-C3/repo2/` (v2b). The repo was only read. Every run here used copies under
`/tmp/r2-C3/` (my files are in `/tmp/r2-C3/judge-impl/`), with `HOME` sandboxed. Load during the runs: 1-min load
average 306-408 (measured: `uptime`). Each number below is labelled measured (with the command) or estimated.

## Verdict

**Below 90. Conviction that C3 as specified lands net-positive within the six constraints: 30%.** The
designer put it at 40%. I agree with the designer's headline (it does not clear the bar, mainly on held-out
precision). The implementability lens adds two things:

1. **The regression claim is overstated.** "No regression in 185 + 27 + 8 + 8 + 9" includes 16 tests that were
   skips, not passes. Four regressions that the designer did not run, or could not see, are measured below.
2. **The pieces the designer rated at or above 90% as reusable infrastructure are not ready to land.**
   `store-discharge.sh` and the dispatch-assert refactor have a pipefail/SIGPIPE false-block defect, a
   behaviour change in dispatch-assert, a shellcheck gate failure and a duplicated turn-start matcher. Each is
   small and fixable, but together they refute "at or above 90% as prototyped".

## 1. Insertion points and citations (verified)

| Claim | Check | Result |
|---|---|---|
| Base drift | `git diff --stat f12dd4b12 HEAD -- hooks scripts bin tests lib CLAUDE.rules.slim.10-session-close.md CLAUDE.global.slim.md` and `git diff --stat HEAD origin/main -- <the 7 target files>` | empty both times (measured), so the prototype base is current |
| `/tmp/r2-C3/orig` = HEAD | `cmp` on completion-assert.sh, dispatch-assert.sh, close-shape.sh, drain-peer-findings.py, completion-assert.bats, dispatch-assert.bats | all identical (measured) |
| CUSTODY `:1029-1034`, FILED_MINE `:1036-1043`, D6 gates `:1428-1455` | `sed -n` on HEAD | correct |
| dispatch-assert `discharged_since` `:166-212` | `sed -n` | correct: header at :168, body to :214 |
| `install.sh:340` lib glob | `sed -n 330,350p install.sh` | correct: `hooks/lib/*.sh` and `*.py` are per-file symlinked; the dispatch-assert and D8 `readlink` fallback covers the gap before install.sh runs |
| slim `:146` sentence, −13 chars | `sed -n 146p`; python `len()` | sentence present; 71 → 58 = −13 (measured); no test pins the old wording (`grep -rn "A qualification goes in" tests/ …` is empty) |
| One follow-on value matcher | `grep -rnE 'follow\[- \]\?on' hooks scripts bin` | only `drain-peer-findings.py:92,97`; `measure-harvest-latency.py:72` is a names-work tell, a different concept. Holds. |
| One drop regex | `grep -rnE "not worth\|dropping\|" hooks scripts bin` | one copy after the refactor. Holds, but see §2.4. |
| Interpreter | `/bin/bash -n` on all 4 changed shell files; `/usr/bin/python3` 3.9.6 and PATH python 3.11 on `--followon-value` | all parse; both Pythons return the incident value with rc 0. The designer's `replay.sh` runs the hook with `PATH=/usr/bin:/bin:…`, so the 37/41 controls already ran on `/bin/bash` 3.2.57 and `/usr/bin/awk`. This is a Stop hook, not a launchd job. |
| Python precedent at Stop | `grep -n python3 hooks/completion-assert.sh` | `:322` already shells out to `research-relay`, so D8's subprocess is not a new class of dependency |

## 2. Regressions the design report does not show (all measured)

### 2.1 `tests/why-tier.bats` P4 fails: the new arm has no `--why` topic
- **Run:** `bash /tmp/r2-C3/judge-impl/run.sh why-tier …` (real bats 1.13.0, serial). The unpatched copy gives
  `1..16` ok 16; v2b gives `1..16` ok 15, not ok 1: test 7, "P4: every arm completion-assert can compose is a
  real topic".
- **Why:** the test reads arm names from the source (`arm="${arm:+$arm+}followon"`) and requires
  `--why followon` to exit 0. Running `bash /tmp/r2-C3/repo2/hooks/completion-assert.sh --why followon` gives
  rc 3, "no such topic: followon".
- **Gap:** `hooks/lib/why-tier.sh` is missing from `files_to_change`. This is the "own-scope gate misses a
  counted pin elsewhere" shape. A topic body is served on demand, so adding one costs no resident budget.

### 2.2 The bare shellcheck land gate refuses the dispatch-assert refactor
- **Run:** `~/.claude/bin/shellcheck hooks/dispatch-assert.sh hooks/lib/store-discharge.sh`. The unpatched
  copy gives rc 0. v2 and v2b give rc 1 with 4 findings:
  - SC2034 `BLG_FILE` :56, `REG_DIR` :57, `DEC_DIR` :58 (now unused);
  - SC2329 `iso_epoch` :134 (never invoked).
- **Why it blocks:** ship-land runs `shellcheck` bare (lesson "Gate invocation is contract"). The refactor
  moved every use into the lib and left the definitions behind.

### 2.3 `sd_discharged_since` (session-scoped) reads NOT discharged when two or more records match
- **The construct:** the fire-stamp and packet arms use
  `grep -lF … | while …; do jq … && echo hit; done | grep -q hit && return 0`. This runs under
  completion-assert's `set -uo pipefail`. `grep -q` exits on the first `hit`, the loop's next `echo` takes
  SIGPIPE, and pipefail makes the pipeline's status 141. That is the defect `hooks/completion-assert.sh:256`
  and `scripts/pipefail-sigpipe-lint.sh` exist for.
- **Why the lint is blind here:** its clause 1 only judges files that themselves enable pipefail
  (`pipefail-sigpipe-lint.sh:1667-1668`). The lib inherits pipefail from its caller and never sets it.
- **Unit run** (`/tmp/r2-C3/judge-impl/sigpipe.sh`, sandbox stores, 10 trials per cell):

  | Matching records by this sid this turn | Discharged, packets | Discharged, fire stamps |
  |---|---|---|
  | 1 | 10/10 | 10/10 |
  | 2-5 | 0/10 | 0/10 |

  Identical on bash 3.2.57 and 5.3.15.
- **End to end** (`cases.sh` and `cases2.sh`: the v2b hook on the incident close with store cures by this sid
  this turn):

  | Seed | D8 result |
  |---|---|
  | 1 packet | PASS |
  | 1 stamp | PASS |
  | 2 class-A packets | **falsely FIRED 5/6** |
  | 2 fire stamps | **falsely FIRED 6/6** |

- **Reach in practice is narrowed by the ledger.** A class-C packet by this session gives rung ⛔, and a
  notify-back fire gives `CUSTODY_OPEN`, so contra=1. Either keeps D8 unreached. Still reachable: non-C
  packets, and fires with no custody.
- **Why it matters more than its reach:** this is the lib the design offers to "the next consumer". The control
  matrix and the new 12-test suite seed exactly one record per cure, so neither can see it.

### 2.4 dispatch-assert is not "byte-equivalent": `dropped` now discharges it
- **The change:** `SD_DROP_RE` widens dispatch-assert's arm-4 regex from `dropping|…` to `dropp(ing|ed)|…`.
- **Run** (`/tmp/r2-C3/judge-impl/da-drop.sh`): a naming-tell turn reading "Landed: p95 latency dropped from 9 s
  to 2 s. The retry path deserves its own pass." The unpatched copy gives `fired narrated-not-dispatched`.
  v2b gives `abstained dropped`.
- **Result:** a new false-negative class in a hook the design says is unchanged. `dispatch-assert.bats` 27/27
  cannot catch it, because its drop tests use only `dropping` / `not worth` / `letting it go`.

### 2.5 Once the `followon` class is capped, D1 is suppressed even when D1's own budget is unspent
- **The change:** D8 claims class `followon` even when D1 fired (by design, so it can outlive a spent `assert`
  budget).
- **Run** (`/tmp/r2-C3/judge-impl/cases3.sh`): seed `followon` 2/2, leave `assert` untouched, then replay the
  full incident close (D1 + D8). The unpatched copy gives `fired false-done handoff`, class `assert`. v2b gives
  **`abstained capped:followon:2>=2`**: the D1 block is lost.
- **Comparison:** the `act` class precedent (completion-assert latch comment: "no existing firing case changes
  class, count or reason string") is broken here. D8 needs a cap fall-back to the arm's own class.

### 2.6 The existing suite barely reaches D8, and where it does, it is not hermetic
- **Run** (instrumented copy `/tmp/r2-C3/judge-impl/repo2i`, `run-trace.sh`): `completion-assert.bats` gives
  `1..185` ok 185. The D8 gate was evaluated 94 times, 15 of those had a YES verdict line, and only **1**
  reached the store reads: test "verdict-first: a yes verdict line with a parked follow-on …" (fixture t6a,
  `follow-on: 1dcc10d88ee3 (the sealed test set, parked on data).`).
- **With empty sandbox stores**, that same fixture makes v2b **block** (`cases4.sh`:
  `fired false-done followon`). The test still passes because it only asserts "no hedge".
- **With the real HOME** (the land gate), D8 reads the live backlog, because `completion-assert.bats` setup pins
  `CC_FIRED_DIR` but not `HOME`, `CC_BACKLOG_FILE` or `CC_DECISIONS_DIR`. There
  `grep -c '"id":"1dcc10d88ee3"'` = 45, so the same test is discharged.
- **Conclusion:** the 185/185 says nothing about D8. D8's outcome on its one reaching fixture depends on the
  box. It also shows the design blocking a cited, stated park whenever the row sits in a store D8 cannot see.

### 2.7 Overstated evidence in the design report's §7
- `completion-assert-durations.bats` and `completion-assert-forks.bats` are **8/8 `# skip` in every arm**
  (measured: `grep -c '# skip' /tmp/r2-C3/tap/*-completion-assert-{durations,forks}.tap` = 8). The cause is
  `shf_old_tree … || skip "the pre-change commit … is not in this clone"`.
- Those two suites are the Stop-phase fork and time budgets, which is exactly what D8 adds to, and they were
  never run.
- The 4 `drain-peer-findings.bats` failures are the measure-harvest-latency blob controls (tests 1-4), not the
  follow-on path. Tests 9-10 (the nil-ledger mutant and the real-ledger drain) pass on v2b, and the M3 mutant
  anchor `_NIL_LEAD.match(cand)` survived the refactor.

### 2.8 One-matcher-per-concept: turn start now has two copies
`sd_turn_start` is documented as "dispatch-assert's T_TURN, verbatim", but dispatch-assert still computes its
own inline `T_TURN` (`/tmp/r2-C3/repo2/hooks/dispatch-assert.sh:141`). That is a second copy of the turn-boundary
matcher, and a third counting the pre-existing `hooks/lib/deadline-capture.sh:90`. The lib was meant to absorb
the copy, not add one.

## 3. Runtime against the hook's real budget

- **Budget:** `settings.json` gives `completion-assert.sh` **`timeout: 5`** (measured: `jq` over
  `~/.claude/settings.json`, read-only). A timed-out Stop hook fails open (`completion-assert-durations.bats`
  header: 24 s against 5 s, killed, no block).
- **D8 component costs on the live stores, read-only** (`idcost.sh`, `sdcost.sh`, `pytime.sh`; load 306-359):

  | Component | Measured |
  |---|---|
  | `--followon-value` CLI | 0.083-0.090 s |
  | `sd_ids_exist` with 1 / 5 / 10 / 20 distinct 12-hex non-ids | 0.25 / 0.75 / 1.47 / 3.08 s |
  | session-scoped discharge | 0.35-0.69 s |
  | `sd_turn_start` on the largest live transcript (27 MB) | 0.45 s |

- **Why the ids check is the risk:** it is linear, about 0.15 s per token, because each token means one 10.9 MB
  backlog grep plus one 623-file packet grep. v2b scans the **whole close** for ids, so the token count is
  unbounded.
- **Estimated total**, by summing the components above: D8 adds about 1.0-1.7 s on a typical close that reaches
  it, and over 3.5 s on one carrying 20 sha-shaped tokens. That is inside the same 5 s as the rest of the hook,
  whose baseline at a ✅ Stop the IDL does not record.
- **Reach:** the designer estimates about 15 such Stops a day. So the cost is rare, but each one risks turning a
  block into a silent fail-open on exactly the heavy closes.

## 4. What holds

- There is no settings.json edit, and none of the six reserved files is touched.
- The rule-text change is −13 chars.
- The follow-on value has one matcher, through `--followon-value`.
- The D6 origin/writer gate is factored, not copied.
- The interpreter paths, bash 3.2 and Python 3.9, both work.
- The dispatch-assert unscoped arms 1-3 are behaviourally unchanged; only arm 4 changed (§2.4).
- The designer's controls 37/37 and 41/41, and the new suite 12/12, stand as reported for single-record cures.

## 5. Bottom line

Even with every defect in §2 fixed, which is mechanical work, the candidate stays below 90 for the designer's own
measured reason: held-out precision of 20% on the incident class and 32% under the contract, with 12 of 25
fires being operator picks inside an interactive loop. This judgment does not move that. It removes the fallback
claim that the infrastructure half is ready at or above 90%: as prototyped, it fails the land gate (§2.1, §2.2),
can block a filed or fired close (§2.3), and changes dispatch-assert (§2.4) and D1 (§2.5).
