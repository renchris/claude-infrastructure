# C6 judge: implementability and regression lens

Round 2, 2026-10-18. Adversarial judge (impl) for `C6-doc-disposition-marker.md`. Lens: do the insertion points exist
where cited, what do the existing suites pin, which interpreter runs it (bash 3.2, BSD awk), what it costs at runtime,
and whether it keeps one matcher per concept.

I made no repo change except this file. My harnesses and outputs are under `/tmp/r2-C6-judge/`. I read and executed
the designer's `/tmp/r2-C6/` prototype (`mut`, `repo`, `clean`, `replay/`), but the only files I wrote there were new
`replay/state/judge-*` dirs, which come from `replay/ca.sh`. Load average was 260-380 during the runs [M: `uptime`].
Each number is labelled [M] measured (with the command) or [E] estimated (with the method).

**Verdict: below-90.** The mechanism is real and well built:
- the replay reproduces;
- every new suite passes;
- it is bash 3.2- and BSD-awk-clean;
- end to end it costs little on the incident shape.

But the design **as specified would be dead on arrival in the live layer**, and it has two regressions plus a cost on its
own cure path that the report does not have. All are cheap to fix (§9).

**Conviction 80**: my estimate that C6, with the §9 changes applied, is correct, safe and net-positive once landed. The
designer gave 87. The reduction is §2-§4 plus the unmeasured behaviour and overload gaps that the designer already
names.

## 1. Insertion points: cited against actual (worktree at `84d63e3af`; `git diff --stat HEAD -- scripts hooks tests lib bin` empty)

| Cited | Actual | Holds |
|---|---|---|
| wrap-ledger header `:25`, `:30` | 🔧 and ✅ definitions | yes |
| seams `:197-206` | env-seam block, `set -uo pipefail` at `:207` | yes |
| memo key after `:640` | `:640` is the `WRAP_RESEARCH` key line | yes |
| § DRIVE STATE before `:1452` | `:1452` opens § THE DRAIN FLOOR | yes |
| call after `:2549` | `:2549` `count_resident_members`, inside the ✅-eligible `else` (custody arm at `:2530-2543`) | yes |
| rung arm between `:2574`/`:2575` | `:2571` CLOSE_FLOOR arm, `:2575` `elif [ -z "$TRUNK" ]` | yes |
| ⛔ first `:2505` | `count_blocking_decisions` at `:2504` | yes (±1) |
| emit_machine after `:2799` | `:2799` `CLOSE_FLOOR_SRC`; BUSY splice is positional, lines 1-18 only (`_wl_splice_print` `:567-590`) | yes |
| emit_full after `:2830` | `:2830` "Dirty tree:" line | yes |
| completion-assert `:1043`, `:1608`, `:1649`, `:87-89`, `:95-105` | FILEDM pair `:1042-1043`, `CLASS=assert` `:1608`, `contra` reason `:1648`, `d3` `:1649` | yes |
| session-writes before `:213`, before `:233`, `:262`/`:272` | `_sw_paths` at `:217`, `local -a srcs` at `:235`, jq at `:262`/`:272` | yes (±2) |
| anti-deference `:511-519` reads RUNG only to record it | `:514` `ld_rung`, fire keys on `ld_dirty/unl/rem` | yes |
| session-continue mechanical arm needs own dirty files | `:1103` `[ "$rung" = "🔧" ]`, then `session_dirty_mine` | yes |
| `CLAUDE.rules.slim.10-session-close.md:189` "every item at 90%+ conviction driven" | present | yes |
| operator-readout `:1323-1329`, SKILL `:534-560`, validate-plan-structure `:64-70` | present | yes |

Every citation holds within ±2 lines. Every helper the term calls exists:
- `_bounded` (`:276`), `_wl_find_transcript` (`:981`), `compute_research` (`:1049`), `SID_SRC` (`:497-502`);
- `_sw_canon_lines` (`:334`), `_sw_subagent_files` (`:206`), `_sw_bounded` (`:111`).

The designer's replay reproduces [M: `replay/ca.sh`, 4 alternations at load 293-298]:
- control: `abstained · ledger-clean`;
- mutant: `fired · false-done · ledger · class undriven · rung 🔧 · 1/2`.

## 2. Deployment: the new `.awk` file is never linked into the live layer, so the term is silently off (blocking)

- `install.sh:733` links only `scripts/lib/*.sh` and `scripts/lib/*.py`.
- `scripts/deploy-link-parity.sh:618-619` checks those same two classes.
- No `.awk` exists in `scripts/lib/` today, and `~/.claude/scripts/lib/drive-state.awk` is absent [M: `ls`]. So does
  `~/.claude/scripts/lib/tmp-roots.list`, the one non-sh/py file there, which shows that other classes are not linked.

**Why that kills the term.**
1. Hooks run as `~/.claude/hooks/completion-assert.sh` [M: `jq '.hooks.Stop'`].
2. completion-assert finds the ledger via an unresolved `${0%/*}/../scripts/wrap-ledger.sh` (`:141`, `:516`).
3. wrap-ledger then sets `WL_SELF_DIR="${0%/*}"`, also unresolved (`:213`). That is the farm directory, not the
   repo.
4. So `awkf="$WL_SELF_DIR/lib/drive-state.awk"` and its `$HOME/.claude/scripts/lib/` fallback are both absent, and
   the term returns `DRIVE_SRC=error`. That is fail-open and silent.

**Measured.** I built per-file symlink farms of `/tmp/r2-C6/mut` that copy install.sh's classes
(`/tmp/r2-C6-judge/mkfarm.sh`). I ran the designer's `replay/ledger.sh keep on <ledger>` on the committed
38-row `to drive` variant:

| Ledger path | RUNG | DRIVE_OPEN | DRIVE_SRC |
|---|---|---|---|
| install-faithful farm (no `.awk` linked) | **✅** | 0 | **error** |
| farm with the `.awk` linked (control) | 🔧 | 38 | WRAP_SESSION_ID |
| repo path (what every bats suite exercises) | 🔧 | 38 | WRAP_SESSION_ID |

Every test stays green, because the tests run from the repo, where `WL_SELF_DIR` is the real `scripts/`. This is the
"added file lands ABSENT, consumer guard is a silent skip" class:
- `deploy-live.sh:1310-1320` describes it;
- `wrap-ledger.sh:2047-2049` records it biting three times (`hooks/*.py`, `scripts/lib/*.py`, backlog-consolidation).

**Fix (either).**
- Ship the parser as `scripts/lib/drive-state.sh`, a function that runs `awk` with the program inline. It deploys with
  no class change. This is preferred.
- Or add `*.awk` to `install.sh:733`, `deploy-link-parity.sh:618` and the class list that `deploy-parity-assert.sh`
  enumerates, plus a `deploy-parity.bats` case.

## 3. Regression: the undriven class defeats the double-block yield

`completion-assert.sh:1169-1191`:
- When session-continue blocked this same Stop, completion-assert sets `contra=0`. That is the double-block guard,
  backlog 79e2b74796af.
- D1-D5 keep firing.

The prototype has two problems on this path:
- **The class.** It claims `CLASS=undriven` whenever the drive facts are the only facts (`mut :1630`), without
  checking `contra`.
- **The reason.** It overwrites `reason` whenever `CLASS=undriven` (`mut :1674`), also without checking `contra`.

**Measured** with `/tmp/r2-C6-judge/tests/ca-dbl.bats`:
- It copies the new suite's preamble and `mkledger`.
- The marker is set through the `CC_CONTINUE_SENTINEL` seam.
- The close fires D4 ("remaining … Want me to …?" on separate lines).

| Hook | Ledger stub | IDL | Ledger facts in reason |
|---|---|---|---|
| mutant | `DRIVE_UNMARKED=1` | `fired · arm offer · class undriven` | **yes**: "Completion-assert: Completion-assert: your close reads as done, but a research synthesis YOU created carries no Drive state …" |
| mutant | `FILED_MINE=1` (baseline arm) | `fired · arm offer · class assert` | no (yield works) |
| control | `DRIVE_UNMARKED=1` | `fired · arm offer · class assert` | no |

So, on this path:
- the yielded ledger facts reach the agent anyway, which is the double message the guard exists to stop;
- the undriven budget is spent on an offer-only fire;
- the class of an existing D4 fire changes, which contradicts the report's "no existing case changes class";
- the prefix is doubled, because `:1682` re-prefixes whenever `contra=0`.

**Fix:** gate both lines on `[ "$contra" -eq 1 ]`, and add the case above as a test.

## 4. Store verification: the `fired` token check reads the whole fleet store, and its fallback verifies anything

`_drive_verify` runs `cc-custody list --json` with **no `--cwd`**. `bin/cc-custody:130-139` then reads every store
file.

- **Cost, on the cure path.** This is the readout's own one-line cure (`Drive state: fired <slug>`), so the cost lands
  on the steady state after a session complies.
  - Store-wide read: **3,213 rows from 92 cwds (820 KB), 1.04-1.98 s wall at load 329-362**.
  - Scoped `--cwd "$PWD"` read: **0.15-0.31 s**, 1 row [M: `/tmp/r2-C6-judge/cust.sh`, `cust2.sh`].
  - It runs under its own 5 s bound (`WRAP_CUSTODY_TIMEOUT_S`), outside the term's 3 s bound. Every Stop consumer waits
    on it through the single-flight memo. completion-assert's whole Stop has 5 s.
  - The designer's timing runs used the UNMARKED and `to drive` shapes, so this path was not measured.
- **Precision.**
  - Store-wide, a slug verifies if any session in any project ever used it. 1,617 distinct slugs exist, and 16 are
    already reused across cwds [M: `cust2.sh`].
  - The `.slug` match also accepts `return` and `abandon` rows.
- **Fallback.** A successful but empty list sets `have_slug="$slugs"`, which verifies every slug. Measured
  (`/tmp/r2-C6-judge/tests/wl-judge.bats`, real `bin/cc-custody`, empty fixture store): `Drive state: fired
  no-such-slug-ever-fired` reads `RUNG=✅ DRIVE_OPEN=0`. With a non-empty store missing the slug it reads `🔧
  DRIVE_OPEN=1`.
  - Live, the store-wide list is never empty, so today this hole is only reachable in fixtures and on a fresh machine.
  - The cost fix (scope to `--cwd`) makes it live: most cwds have no custody rows.

**Fix:**
- Query `list --json --cwd "$PWD"` and accept only `kind:"open"` and `kind:"return"` rows.
- Treat rc 0 with valid JSON, `[]` included, as authoritative.
- Fail open only when the binary is missing, errors, or times out.

The other two stores are existence-only, which the report states:
- a `filed` id is a `grep -F` over the 11 MB backlog file in any field;
- a `decision` id is "the file exists".

## 5. Interpreter

- **bash.** wrap-ledger and completion-assert are `#!/usr/bin/env bash`. Stop hooks get Homebrew bash 5.3. Only
  `com.claude.deploy-live.plist` among `launchd/` names any ledger consumer [M: `grep -l`].
  - I still ran the term under `/bin/bash` 3.2.57 by putting a `bash → /bin/bash` shim first on PATH, which also
    covers the term's child `bash -c` (`/tmp/r2-C6-judge/b32.sh`).
  - Replay ledger: `RUNG=🔧 DRIVE_OPEN=38`, identical to bash 5.
  - Cached reader under `set -u`: rc 0, 48 paths cold and warm, byte-equal to the uncached reader [M].
- **awk.** It is macOS `/usr/bin/awk` (20200816); no gawk is on PATH [M: `command -v awk`]. All suites ran on it.
- **shellcheck.** Bare shellcheck gives 0 findings on mut's three scripts and on control.
  - On `clean/` it gives 3 SC2015 infos. That is an artifact: the repo's `.shellcheckrc` sets `disable=SC2001,SC2015`,
    and the `clean/` tree has none.
  - So the report's "0" holds for the landed form.

## 6. Runtime cost

- **Layer 1 (git) is cheap**, even on long reflogs [M: `/tmp/r2-C6-judge/reflog.sh`, load 290-307]:
  - this worktree, 12 shas: 0.05-0.07 s;
  - the shared main checkout (1,123 reflog entries), 194 shas in a 7-day window: 0.12 s.
- **But in the main checkout layer 1 does not prune.** Its reflog is `merge <sha>: Fast-forward` entries (the deploy
  advancing trunk). The prototype's `merge` alternative admits them, so 24 h there yields 30 added docs, 4 of them
  synthesis docs, from other sessions [M].
  - Any session that lives in the main checkout therefore takes the slow path (layer 2) on every ✅-eligible Stop.
  - Layer 2 still decides ownership, so this is cost, not correctness.
  - It also contradicts "a commit this worktree made or picked". Fix: drop `merge`, or keep only non-fast-forward
    merges.
- **End to end, incident shape.** On the replay at load 293-298 the whole completion-assert Stop took 1.69-2.16 s
  control and 1.56-1.85 s mutant, warm drive cache [M: `/tmp/r2-C6-judge/ab.sh`, 4 alternations]. No visible penalty.
  The sandbox lacks the live backlog fold, so absolute times are lower than live.
- **Cache concurrency.** Concurrent computes are real: completion-assert keys apart when `--session` differs from the
  env SID (`:558-575`). All writers share one temp name, `"$cf.tmp"`, but the cache was not corrupted:
  - 12 trials × 6 concurrent cold readers on one cache dir;
  - every reader and the warm read after were byte-equal to the uncached answer, and no `.tmp` was left
    [M: `/tmp/r2-C6-judge/race.sh`].
  - The residual case needs the main transcript to grow between two writers' `stat`s. Its failure is a lost record and
    a silent term [E: reasoning on the offset interleave].
  - Fix: `tmp="$cf.tmp.$$"`.

## 7. Existing suites (what pins the changed behaviour)

- **Static.**
  - No existing suite creates a `docs/research/<dir>/{README,REPORT,SYNTHESIS,DESIGN}.md` in a fixture and records a
    Write of it. Every hit in a ledger-consumer suite is a provenance comment [M: `grep` over `tests/*.bats`].
  - `ship-land.bats:779` adds `docs/research/audit.md`, which is depth 1 with no duty.
  - No suite pins the machine key set.
  - `wrap-ledger-memo.bats:337-372` and `:575-592` count git calls *relative to* a baseline measured in the fixture,
    and the warm count must be 0. The memo still serves warm, so the extra git calls cannot break either.
  - No reader treats the completion IDL `class` as a closed set. Cap logging is generic (`:1631-1632`).
- **Run** [M: plain `bats-core --tap` on `/tmp/r2-C6/mut`. `cc-bats` refused rc 75 ("2 concurrent bats roots … load")]:

| Suite | Plan | ok | not ok | Load |
|---|---|---|---|---|
| `completion-assert-drive-state.bats` (new) | 1..6 | 6 | 0 | 323 |
| `session-writes-cache.bats` (new) | 1..4 | 4 | 0 | 333 |
| `session-writes.bats` (existing) | 1..32 | 32 | 0 | 332 |
| `wrap-ledger-drive-state.bats` (new) | 1..18 | 18 | 0 | 329 (4 m 38 s) |
| `completion-assert.bats` (existing, **full**) | 1..185 | 185 | 0 | 378 at start (17 m 29 s, rc 0) |
| `wrap-ledger.bats` (existing, **full**) | 1..140 | 140 | 0 | 318 at start (39 m 15 s, rc 0) |

- **Result.** Both full suites pass on the prototype: 325 of 325. The designer ran subsets only. So no existing pinned
  behaviour regresses on the repo path.
- **Gap.** No test covers §2 (deploy), §3 (yield) or §4 (custody scope and empty store).

## 8. One matcher per concept

- The synthesis-path `case` is written **twice inside `count_drive_state`** (layer-1 filter and the `synth=` flag).
  It is a third reading of "research lead doc" beside `scripts/research-kit/research-index.py:28` `LEAD_DOCS`, which
  has no DESIGN.md. Fix: one `_drive_is_synth()` helper, plus a cross-reference.
- **Two detectors for "has a declaration", which already disagree.**
  - The layer-1 prefilter is `grep -i '^Drive state:|\| Drive state \|'`, which is case-insensitive.
  - The parser's doc line is `/^Drive state:/`, which is case-sensitive. Its header cell is case-insensitive.
  - Example: `drive state: none` passes the filter, but the parser reads it as UNMARKED.
  - `**Drive state:** …`, the form an agent is likely to bold, is also not a doc line.
  - Fix: one regex shared by both, or let the parser decide on every candidate.
- **The cure vocabulary is restated in five strings:** two ledger READOUTs, two `_ca_drive_facts` sentences, and the
  undriven reason. That is the drift that `close-shape.sh` warns about. Fix: the ledger emits one `DRIVE_CURE=` field,
  and completion-assert quotes it.
- **What does hold.**
  - completion-assert consumes `DRIVE_*` and derives nothing.
  - Ownership reuses `session_writes_paths`.
  - `_SW_WRITE_TOOLS` unifies the tool list, which the `session-writes.bats` 32/32 run shows is safe.
  - `close-shape.sh` is untouched.
  - None of the six owned files is touched [M: diff file list].
  - There is no `settings.json` edit and no resident text.

## 9. Required changes (all small; none needs settings.json or resident text)

1. **Deploy (§2):**
   - make the parser a `scripts/lib/*.sh` lib, or extend the link and parity classes to `*.awk`;
   - add a farm-path test: run the ledger through a per-file symlink farm and assert `DRIVE_SRC != error`.
2. **Yield (§3):**
   - gate `CLASS=undriven` and the undriven reason on `contra -eq 1`;
   - add the double-block case with a D4 close as a test.
3. **Custody (§4):**
   - `list --json --cwd "$PWD"`, open and return rows only;
   - a successful `[]` is authoritative, and only a missing, failed or timed-out binary verifies nothing;
   - put the call inside the term's bound;
   - add tests for a fake slug against an empty store and against a non-empty store.
4. **Layer 1 (§6):** drop `merge` (or keep non-fast-forward merges only), so the main checkout's deploy merges do not
   force the slow path.
5. **Matchers (§8):**
   - one synthesis-path helper;
   - one declaration regex shared by the prefilter and the parser, accepting `**Drive state:**`;
   - a single `DRIVE_CURE` text emitted by the ledger.
6. **Cache (§6):** a per-process temp name.
7. **Measurement before `on` (the designer's own §8):** land in shadow mode with the elapsed-ms IDL row. It is not
   prototyped. Re-time the `fired`-token path after change 3.

## 10. Verdict

- **Implementable:** yes, with small changes.
  - The citations hold.
  - The code is bash 3.2- and BSD-awk-clean.
  - The new suites pass (28/28 plus 32/32 for `session-writes.bats`).
  - The full existing `completion-assert.bats` (185/185) and `wrap-ledger.bats` (140/140) pass (§7).
- **As specified:** not shippable.
  - The deploy omission makes it inert in production while every suite is green.
  - The yield bypass and the store-wide custody read are regressions the report misses.
- **The remaining gaps are the designer's own:** blocked-agent behaviour below 90, and load 500+. Neither is measured,
  so the design stays below the bar even after the fixes.
- **Conviction 80** that the fixed design, landed, clears 90% and keeps the six constraints [E: the designer's 87, less
  §3 and §4, which are fixable but unmeasured once fixed; §2 is binary and fully fixed by change 1].
