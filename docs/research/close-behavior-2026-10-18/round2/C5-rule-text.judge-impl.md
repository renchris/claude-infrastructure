# C5 judge: implementability and regression lens

Round 2, 2026-10-18. Adversarial judge (impl) for `C5-rule-text.md`. Lens: do the insertion points exist where cited,
what do the existing suites pin, which interpreter runs the edited code, what it costs at runtime and in the resident
budget, and whether it keeps one matcher per concept. I changed nothing in the repo except this file. My copies, harnesses
and outputs are under `/tmp/r2-C5/judge-impl/`. I read the designer's `/tmp/r2-C5/` files and wrote nothing there. Load
average was 250-345 on 10 cores during the runs (measured: `uptime`). Each number is labelled measured (with the command)
or estimated (with the method).

**Verdict: below-90.** On my lens the edit set holds up. It applies cleanly, nothing pins it, it is bash 3.2-safe and it
shrinks the resident text. But the candidate does not clear 90 as a fix. The designer's own efficacy estimate is about 40,
and nothing in an implementability review can raise it. The design as submitted also has one gap the report says does
not exist: a matcher keyed on the old yes payload drifts (§6).

**Conviction 91**: my estimate that core+D, landed with the one-line companion in §8, is correct and causes no
regression. That is the "safe to land as the text half" claim, not the "prevents a repeat" claim. As submitted, without
the companion, I put it at 89 (estimated: the 0/199 real-corpus result in §6 limits the damage, but the drift is real
and so is the report's claim that the tool is unchanged).

## 1. Insertion points: cited against actual (worktree `84d63e3af`)

The six target files are byte-identical to the designer's pristine copies taken at 20:01 (measured: `cmp` against
`/tmp/r2-C5/orig/*` for the three it kept; `diff -rq` of a fresh rsync for the rest). I re-applied the designer's own
`edits.py` (it checks that each old string occurs exactly once) to a fresh rsync of the current tree, in three sets:
core, core+D (the recommended set, which the designer never built as a tree) and full. Every edit reported `count=1`
(measured: `python3 -I /tmp/r2-C5/judge-impl/bin/edits.py <tree> core|coreD|full --apply`). My full tree is
byte-identical to the designer's `/tmp/r2-C5/repo` on all six files (measured: `cmp`).

| cite in the report | actual | status |
|---|---|---|
| slim:22 template, slim:146 licence, slim:156 S6 catch-all | 22, 146, 156 | correct |
| slim:8 certificate; slim:20, 26, 34, 49, 68, 75, 77, 86, 103, 105, 148, 191 | same lines, same text | correct |
| global:560-561, 927-929, 944, 981-982, 601 | same | correct |
| why-tier.sh:90-92 (`--why hedge`), 172-173 (`--why shape`) | same | correct |
| close-shape.sh:179 (inside the `close_shape_template` heredoc) | 179 | correct |
| are-we-done.md:40 (A-a), :49 (A-d1) | 40, 49 | correct |
| are-we-done.md:58 (A-b), :59 (A-d2), "55-59" for the yes list | **60, 61, 57-62** | off by two; harmless, because `edits.py` matches exact strings |
| wrap.md:176 (R-d) | 176 | correct |
| brief's `scripts/why-tier.sh` | does not exist; `hooks/lib/why-tier.sh` | the designer's correction is right |

**It also applies to trunk.** `origin/main` (`dfdb5c273`) is 46 commits ahead. Among the targets it changes only
`CLAUDE.global.md:477`, outside every edited span (measured: `git diff --stat HEAD origin/main -- <files>`). Core+D
applied to the `origin/main` blobs gives `count=1` everywhere (measured: `git show origin/main:<f>` into
`/tmp/r2-C5/judge-impl/trunk/`, then `edits.py … coreD --apply`).

**Ordering.** D's `W-d1` old string contains `gloss. A plain`, which exists only after core's `W-a` has been applied. So D
cannot land without core. Land them as one commit.

**Coverage.** I grepped the repo outside `docs/` for every copy of the licence (`beside the assertion`,
`withdraw the assertion`, `let S2's`, `clause discharges it`) and of the payload `nothing of mine is open; follow-on`.
Every copy the report names exists, and the report misses none: slim, global, why-tier, close-shape and are-we-done
(measured: `git grep -n -F`). `CLAUDE.global.slim.md` has no copy, so its delta of 0 is correct. One copy is left out on
purpose and goes unmentioned. The separate `core/` kit has its own older no-form, `<what remains, and who owns it>`, at
`core/CLAUDE.core.md:70`, `core/commands/autonomy-wrap.md:12` and `install-core.sh:457,472`. After D it diverges from
the main template. No test pins it, and the kit already used different wording, so this is not a regression.

## 2. Existing suites: what pins the changed text

**Static pin checks (independent of the designer's scan).**

- I scanned every 5-word window of text that each core+D edit removes, across `tests/`. The windows from the licence,
  S6, A-b, A-d1 and A-d2 spans have 0 hits. The payload and owns→drives windows hit fixture closes and the certificate
  string (`SAFE TO CLOSE — nothing of mine is open`) in `cc-decide`, `operator-readout`, `session-writes`,
  `completion-assert-forks`, `watchdog-retired-teammate`, `drain-peer-findings` and `completion-assert`. All of these are
  inputs to unchanged matchers or assertions on the unchanged certificate (`operator-readout.sh:1352`). None is an
  assertion on an edited span (measured: `python3 -I /tmp/r2-C5/judge-impl/bin/ngram.py`, then read each hit).
- **Flip test.** I rendered everything the edited code can emit, for pristine and for core+D: the template,
  `close_shape_reason` for ✅/👤 × four missing-sets, and all 15 `--why` bodies. Then I evaluated every asserted pattern
  in the five suites that read those libs (`completion-assert`, `why-tier`, `operator-readout`, `wrap-ledger`,
  `completion-assert-forks`) against both renders. There were 576 `grep` patterns and 32 `== *"…"*` substrings. **0 flip**
  (measured: `/tmp/r2-C5/judge-impl/bin/flip.py` and its inline glob twin). So no assertion in those suites can change
  truth value because of these edits.
- **Which suites read the edited files.** `completion-assert.bats` reads only `close-shape.sh` and `why-tier.sh` among the
  edited files, plus the unedited `commands/ship.md` (measured: `grep -n 'CLAUDE\.\|commands/' tests/completion-assert.bats`).
  The suites that read the slim, global or command files by path are research-program-exemption-rules, wrap-ledger,
  cc-memory-search and cc-memory-supersession-check. Every other hit uses its own fixture file. No test or tool reads
  `are-we-done.md` (measured: `grep -rln are-we-done tests scripts bin hooks` is empty).

**bats on the recommended core+D tree** (measured, `cc-bats` with plain admission and no waiver; TAP files in
`/tmp/r2-C5/judge-impl/out/`):

| suite | plan | ok | not ok |
|---|---|---|---|
| `research-program-exemption-rules.bats` | 1..4 | 4 | 0 |
| `why-tier.bats` | 1..16 | 16 | 0 |
| `completion-assert.bats -f verdict-first` (the 37 the designer could not get a slot for) | 1..37 | 37 | 0 |
| `completion-assert.bats` full | 1..185 | 2 | (1, my kill) |

The full run did about 0.3 tests per minute at this load, so I stopped it by PID at test 3. The `not ok 3` is my own
SIGTERM landing in that test's fixture builder: the failing line is `w="$(mkrepo_unlanded "kq$i")"`, mid-clone. The
same test passes (`ok 3`) in the designer's run on byte-identical `completion-assert.sh`, `close-shape.sh` and
`why-tier.sh`. Two attempts to re-run it alone were refused by cc-bats admission with rc 75: two roots held by other
sessions, load above the per-core ceiling. That is a deferral, not a result. The killed TAP is kept as
`out/coreD-ca-full.KILLED-at-test3.tap`.

The designer's runs on `/tmp/r2-C5/repo` (full set) carry over to core+D for every suite that reads only the hook libs,
`wrap.md` or `are-we-done.md`, because those files are byte-identical between core+D and full (measured: `cmp`). That
covers completion-assert 1-75 (75 ok), the 7 template tests, the 4 C5PROBE tests and wrap-ledger parity 6/6. I checked
the TAP files on disk. The designer's suite copy only appends the probes: `diff` shows 0 deleted lines and 26 added.

**Pure-function replay under both interpreters.** I replayed the bats assertions that read the template and why bodies,
plus the 17-row polarity table extracted from `_cvf_pol_rows`, the new-payload yes and the incident rewritten as a ❌
no. Core, core+D and full all pass 49/49 under both `/bin/bash` 3.2.57 and Homebrew bash 5.3.15. Pristine passes 45/49:
the 4 failures are exactly the checks that the new text is present, which is the positive control (measured:
`<bash> /tmp/r2-C5/judge-impl/bin/replay.sh <tree>`).

`drain-peer-findings.bats` tests 1-4 failed in the designer's copy for lack of `.git`. They exercise only a historical
blob and the unedited `scripts/measure-harvest-latency.py`. `diff -rq pristine coreD` lists only the six edited files,
so those tests cannot change under C5. That is a fact from the diff, not a guess from reading.

## 3. Interpreter

- `close-shape.sh` and `why-tier.sh` are `#!/usr/bin/env bash` libraries. They are sourced by the Stop hooks
  (completion-assert, session-continue, boundary-handoff, waiting-recycle, handoff-claim-assert), by `operator-readout.sh`
  (polarity only), and by `/wrap`'s `!` line through PATH `bash`. No LaunchAgent or plist references either one
  (measured: `git grep` on plists, and `ls ~/Library/LaunchAgents`).
- Every edit sits inside a quoted heredoc (`<<'TPL'`, `<<'WHY'`) and adds no `(`, `)`, `$` or backtick. So the
  bash 3.2 paren-in-heredoc trap (situational lesson `bash-32-counts-parens-inside-a-heredoc-it-never-runs`) cannot fire.
  `/bin/bash -n` and `bash -n` are clean on all four trees, and the functions run under 3.2 (§2 replay).
- No awk, sed or regex is added or changed. Python: none in the design. My companion in §8 is one regex alternation in
  a Python 3 script.

## 4. Runtime and budget cost

- **Runtime.** No new process, file read, matcher or hook arm. The D6 reason grows from 1,634 to 1,637 bytes (measured:
  `close_shape_reason ✅ good-to-close-verdict | wc -c`, pristine against core+D). The `--why` bodies go hedge 191→196
  words and shape 249→248 (P7's floor is 40; no ceiling exists).
- **Resident budget.** The designer's deltas reproduce exactly with the repo's own `instruction_budget.parse`: slim rules
  30,317 → 30,301 (core), 30,303 (core+D), 30,292 (full); global slim 28,343, unchanged (measured:
  `python3 -I /tmp/r2-C5/judge-impl/bin/budget.py`).
- **The report's tier figure is stale.** The live user tier now measures **61,104**, not 60,998, because
  `~/.claude/CLAUDE.md` was redeployed at 21:19 (29,000 bytes; it differs from the worktree's `CLAUDE.global.slim.md` at
  line 182). The conclusion does not change. `judge()` returns `[]` for core, core+D, full and the trunk-based tree; the
  projected tier for core+D is 61,090; a +1-character control is refused with `kind: tier` in all 5 config dirs (measured,
  same script).
- **Land ratchet.** `CLAUDE.global.md` is not budgeted (`classify` → `[]`; config `_deploy_sources`: deploys non-loaded as
  `CLAUDE.full.md`). The slim rules file classifies as `source → ~/.claude/rules/10-session-close.md` and shrinks, so
  `cc-instruction-budget range` (ship-land.sh:3865-3901, own-range growth only) has nothing to refuse (measured:
  `/tmp/r2-C5/judge-impl/bin/classify.py`).
- **Freshness record.** The global's `derived-from` staleness is informational only. `cc-instructions-variant` prints
  STALE; neither install nor land enforces it (read: `bin/cc-instructions-variant:142-156`, and `grep derived-from` on
  install.sh and ship-land.sh).

## 5. One matcher per concept: the template copies

C5 adds no matcher and changes no regex. The template changes once in code, in the `close_shape_template` heredoc, and
in each of the five prose copies, in step. That keeps one wording per concept, as the `close-shape.sh` header asks.
Every matcher that reads the S2 line keys on the glyph, on `good to close` and on yes or no, never on the payload words:
`CA_SETTLED`, `CA_RETRACT`, `CA_YES_HEDGE`, `CA_VERDICT_*`, `CA_PLACEHOLDER` (`+` keeps the new no-form out of it),
`CA_HANDOFF`/`CA_NEG` (no `drive` term), `NAME_TELL`, and the `Good to close: (yes|no)` readers in `cc-pane-close`,
`cc-husk-sweep`, `lead-crash-watchdog` and `dl` (measured: grep of every `CA_*=` and every `Good to close` regex outside
comments). The measured exception is §6.

A-b adds a fourth prose statement of S-b's rule: slim S-b, global G-b, why-tier W-a and are-we-done A-b. No test keeps
them in agreement. That matches how the repo already handles its prose copies, so it is drift risk rather than a defect.

## 6. One matcher per concept: `drain-peer-findings._SETTLED` drifts (new; the report says it does not)

`scripts/drain-peer-findings.py:81-84` `_SETTLED` is the matcher for "this sentence asserts closure", and it keys on the
old payload: `nothing (of mine )?is open`. The report (§4.4) measured only the exact template string and concluded the
tool "keeps that tool's behaviour unchanged with no edit to it". That holds for the template string and fails for
ordinary variants. When the payload and an open-tell word share one clause, the old wording was suppressed by `_SETTLED`
and the new wording is not (measured: `python3 -I /tmp/r2-C5/judge-impl/bin/drain-variants.py <tree>`):

| close | old payload | new payload |
|---|---|---|
| exact template, `follow-on: none` | no finding | no finding |
| `yes — {P}, and the sealed test set stays parked on its data.` | no finding | **false finding** |
| `yes — {P}, though the nightly job still has to run once.` | no finding | **false finding** |
| `yes. {P} — everything landed; the census rows remain filed.` | no finding | no finding |
| `Yes, good to close: {P} and nothing remains on my side of this work.` | no finding | **false finding** |

**Practical size, measured on real closes.** Over the last 14 days of transcripts in `~/.claude` and `~/.claude-secondary`,
199 unique assistant texts contain `Good to close` and `nothing of mine is open`. Rewriting old → new in each gives **0**
new false findings and 0 lost (measured: `python3 -I /tmp/r2-C5/judge-impl/bin/drain-corpus.py 14`; 67 of 67 over 3
days). The tool is also unscheduled: no caller outside `tests/`, and 0 `peer-drain` rows in the live backlog (measured:
`grep`). So this is latent and small, not a live regression. It is still the kind of drift constraint 6 exists to
prevent: the template changes the canonical phrase and the one matcher that recognises it is not updated. Future closes
copy the new phrase into shapes the old fixtures never had.

**The fix is one line, measured.** Change the alternation to `nothing (of mine |drivable )?is open` (copy:
`/tmp/r2-C5/judge-impl/out/drain-peer-findings.patched.py`). Results: the five variants give 0 false findings; the
script's `--selftest` is green 17/17; the M2 fixture still drains nothing; a real follow-on (`… still remains unlanded …`)
still drains (measured, same probes). The M2 mutant in `drain-peer-findings.bats` neutralises `_SETTLED.search(s)` by
sed on the call, not the regex text, so it keeps its power.

## 7. What is still unmeasured on my lens

- **Full `completion-assert.bats` on the edited libs.** 75 (designer, identical libs) + 37 (me, verdict-first) + 7
  (template) of 185 are green, with overlap between those sets. My full run of 1..185 on core+D was stopped at test 3
  (§2). 68 tests have no green run on the edited libs (measured: 185 less the union of tests 1-75, the 37 `verdict-first`
  tests and the 7 template tests, counted over the suite's `@test` list). They feed
  fixture closes to unchanged matchers. The §2 flip test shows that no assertion in the suite changes truth
  value under the edit. Residual risk is estimated at about 1%.
- **Behavioural side effects** (the designer's estimate of about 5%: rows filed to make a yes reachable; `"research
  only" or not` read as overriding an operator's explicit research-only scope). These belong to the efficacy and
  false-positive lenses and cannot be measured here. I take the designer's number into the 91 above without change.

## 8. Required changes

1. **Companion matcher edit (required by constraint 6).** In `scripts/drain-peer-findings.py:83`, change
   `nothing (of mine )?is open` → `nothing (of mine |drivable )?is open`. Add one new-payload settled fixture beside the
   two in `selftest()` (`:413-421`), for example `"Good to close: yes — nothing drivable is open, and the sealed set
   stays parked on data."` → `""`. That file is not on the owned list.
2. **Land core and D as one commit.** D depends on W-a's new text.
3. **Before landing, run `completion-assert.bats` in full on the landing tree and read its `1..N` plan line.** ship-land
   sheds smoke under load (lesson: Landed ≠ tested). Also run `drain-peer-findings.bats` if the companion lands.
4. **Report corrections** (cosmetic): are-we-done.md cites become :57-62, :60 and :61; the live tier figure is 61,104 as
   of 23:0x (the conclusion is unchanged).

None needs `settings.json`, an owned file, or resident growth. The companion is outside the resident tier.

## 9. Verdict

The edit set is implementable as written and is cheap: -14 resident units, no runtime cost, no interpreter exposure, 0
pinned spans, 0 assertion flips, and every suite that reads the edited files green on the recommended tree as far as it
ran. The design report's safety case survives this lens with one correction, the `_SETTLED` drift. It is fixed by one
regex alternation and is measured at 0/199 on real closes. **Below-90** stands for the candidate. C5 is the text half and
is safe to land beside a mechanism; it is not a 90% fix for the incident. Its efficacy (designer: about 40) is outside
this lens, and nothing found here raises it.
