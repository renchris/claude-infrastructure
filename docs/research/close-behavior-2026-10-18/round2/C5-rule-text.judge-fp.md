# C5 judge: false positives and always-firing

Round 2, 2026-10-18. Adversarial judge, FP lens, on `round2/C5-rule-text.md`: the rule-text edit set
that removes the `follow-on:` licence, changes the yes payload to `nothing drivable is open`, and adds
"unfiled work the Follow-On Gate passes that nobody drives makes S2 a no, "research only" or not".
The repo was read-only for this pass, and this file is the only thing I wrote to it. Scratch work is in
`/tmp/r2-C5-judge-fp/`. Labels: **[M]** measured (the command is named), **[E]** estimated (the method
is named). Load during the pass was 278-350 on 10 cores [M: `uptime`].

**Verdict: below 90.** On this lens C5 is close to safe. It adds no hook and changes no matcher, the
new payload passes every hook probe I ran, and C5 creates no always-firing surface. ⛔ closes,
quoted templates, honest no-closes over a park and research-scope closes all pass the real hook. I
found two defects, both small and cheap to fix:

1. **A measured regression in `drain-peer-findings.py`, against the report's claim that this tool is
   unchanged.** The new payload drops the only `_SETTLED` token the template carried. 3 of 976 real
   yes closes go from no finding to a false backlog finding [M].
2. **The skeptic's carve-out for an operator-stated scope was not carried.** In fact the new text
   says the opposite: "research only" or not. In 30 days I measured 0 closes that the literal
   reading would wrongly flip. The risk is still unbounded, because whether agents misread the
   phrase is unmeasured. A version with the carve-out fits the budget [M].

C5 is the text half of a fix. Its designer puts it at about 40% to stop a repeat [E, designer's
estimate], so it does not clear 90 as the fix. That is outside this lens, and I do not dispute it.

## 1. What I re-ran (designer's numbers)

| Check | How | Result |
|---|---|---|
| Slim units | `python3 -I -B /tmp/r2-C5/bin/units.py` on pristine, core, full and `coreD-slim.md` | 30,317 → 30,301 / 30,292 / 30,303. Matches §3.3 [M] |
| Live user tier | `python3 -I -B /tmp/r2-C5/bin/tier.py` | **61,104** now, not the 60,998 in the report. The tier grew in another file since the designer measured. The delta is still −16 [M] |
| `judge()` | `python3 -I -B /tmp/r2-C5/bin/judge.py` | `[]` for core and full. Projected 61,088 / 61,079 [M] |
| Live file equals repo | `diff -q ~/.claude/rules/10-session-close.md CLAUDE.rules.slim.10-session-close.md` | identical [M] |
| Shape and polarity | `bash /tmp/r2-C5/bin/shape-probe.sh` | new yes → yes/complete; ❌ no → no; the template is still a mention (polarity none, `good-to-close-verdict` missing) [M] |
| Pinned anchors | `python3 -I -B /tmp/r2-C5/bin/anchors.py` on `repo` and `core` | 11/11 PASS on both [M] |
| Test pins | `grep -rlF` over `tests/` for each edited phrase | `who owns it` appears only in `completion-assert.bats`, as input. `nothing of mine is open` appears in 9 suites, all as the certificate or as fixture input. The remaining phrases have 0 hits, apart from unrelated comments ("beside the assertion" in three headers) [M] |
| Payload-keyed code | `grep -rn -iE` for good-to-close matchers carrying `of mine`/`drivable` in hooks, scripts, bin and lib | the only consumer of the payload words is `scripts/drain-peer-findings.py` `_SETTLED` [M] |

## 2. Finding 1: the drain regression (measured)

`_SETTLED` (`drain-peer-findings.py:81-84`) contains `nothing (of mine )?is open`. A sentence that matches it
is not drained even when it carries an open-tell word (`remain`, `parked`, `unlanded`, `left for`). The
designer probed only the bare template, which has no tell. I probed closes that do have one:

- **Adversarial** (`python3 -I -B /tmp/r2-C5-judge-fp/bin/drain-adv.py`): 4 of 6 honest yes closes flip from
  `''` to a finding once the payload is swapped. Example: `…nothing drivable is open (the remaining 👤 step is
  filed as 1dcc10d88ee3)…` [M].
- **Real corpus** (`/tmp/r2-C5-judge-fp/bin/census.py`, then `analyze.py`): the census covers 1,085 yes closes in
  468 transcripts, all main-chain, deduplicated by realpath, with no `-private-tmp` projects and none older
  than 30 days. Of the 976 that carry `nothing of mine is open`, **3 flip** (0.31%) and 2 of those are the file's
  last close, which is the population the drain reads [M]. Two of the three are
  `…nothing drivable is open (\`AHEAD=0 · UNLANDED=0 · …\`);`: the ledger token `UNLANDED` is an `_OPEN_TELL`.
- **Impact.** The tool is not scheduled: no launchd plist or script calls it [M: `grep -rln`], and it is a dry
  run unless given `--commit`. The impact is a false agent-work row on a manual `--commit` run, so it is
  small. But §4.4's claim that the tool "keeps … behaviour unchanged with no edit to it" is false.
- **Fix, measured** (`/tmp/r2-C5-judge-fp/bin/variants.py`): the payload `nothing is open` gives **0 of 976**
  flips and still drops the git-scoped "of mine". The other route is to widen `_SETTLED` to
  `nothing (of mine |drivable )?is open`, which is an edit to a second file.

## 3. Finding 2: "research only" or not, against an operator-stated scope

The round-1 skeptic (axis 01, E5) required "unless the operator's own words exclude implementation"
for exactly this case. E1(c) also asked for "a stated park is not drivable". The report argues that F1
makes an explicitly forbidden implementation fail the Gate, so the carve-out is implied. That reading
holds up. The text, however, cues the opposite reading, and the incident shows that agents here break
correct rules.

Exposure, measured with `/tmp/r2-C5-judge-fp/bin/strict.py`, a strict regex for research-only,
implement-nothing, stop-here and similar phrases over the last 12 operator prompts:

- 24 yes closes in 8 sessions over 30 days.
- 3 of them name recommendation or implementation work under an explicit no-implementation brief:
  - sevenrooms-bridge `4bd14fd9` 06:14, `follow-on: none. The next step is the renewer build (wave I2a…)`;
  - sevenrooms-bridge `ac0f0123` 06:17;
  - telemetry-rum `1722d357`, "Implement nothing".
- By my hand-label, **none is a literal-S-b flip**:
  - sevenrooms's recommendation was at **85%**, which fails F2;
  - telemetry-rum's items are operator decisions and an auth-file edit, behind G2.
- The cost of a misreading is concrete. The operator's next message after `ac0f0123` was "Yes to all
  your recommendations except 6 -- hold on…". Had the agent driven every item, as "research only" or
  not plus slim:103 push it to, it would have built the one the operator declined.

A carve-out that fits the budget, measured with `variants.py` and the repo's `judge()`:

- `, unless the operator excluded it.` in place of `, "research only" or not.` gives −7 net, and judge
  admits it.
- `…own words excluded it` gives +5 and is **refused**: the tier is over budget.
- Adding `; a stated park is not drivable` gives +24, also **refused**, unless it is paid for elsewhere.

The incident is still a no under the carve-out: the operator said "research the best …" (axis 01 RC3)
and excluded nothing.

## 4. FP hunt through the real hook (completion-assert, unchanged by C5)

`cc-bats -f FPJ /tmp/r2-C5-judge-fp/tests/fpj.bats`. The file is a copy of `completion-assert.bats`
with REPO pinned to `/tmp/r2-C5/repo` (the edited tree) and the suite's hermetic seams intact, plus 8
appended `FPJ` tests. Runs: plan **1..5**, 4 ok / 1 not ok; then plan **1..3**, 3 ok [M].

| Probe | Close | Result |
|---|---|---|
| FPJ1 | stated park as the honest no C5 pushes toward (❌ line 1, ✅ rung) | no block [M] |
| FPJ2 | research-only yes, new payload, "its two recommendations are yours to rule on" | **block**: D1 "hands the operator work in prose" [M] |
| FPJ6 | FPJ2 with the **old** payload (control) | **the same block** [M]. So this is the hook's own existing behaviour, not caused by C5 |
| FPJ7 | research-only yes, new payload, recommendations "not built, because the brief said implement nothing" | PASS [M] |
| FPJ3 | honest no over a research-only scope (the literal C5 reading) | no block [M] |
| FPJ4 | real verdict plus a quoted new template in the body | PASS [M] |
| FPJ8 | ⛔ close (filed class-C, no S2) | no block [M] |
| FPJ5 | incident shape (yes plus undriven `follow-on:`) | no output [M]. The hooks stay blind to the incident, and C5 does not change that |

Other surfaces:

- **Stated parks.** 0 of the 11 yes closes whose `follow-on:` carries park, hold or later wording came
  after an operator pause phrase [M: `park.py`]. In this corpus no operator park used the slot C5 removes.
- **Research program.** 5 yes closes in the one registered program cwd; 1 is on the trigger surface, and its
  items belong to the lead and the operator [M: `analyze.py`]. S-b is a new "no, one more thing" rule that
  carries no active-program pointer. By reading, the exemption's "residuals … are not open work" covers it.
- **Fired peers.** "Nobody drives" excludes work a peer or lead harvests. telemetry-rum is a fired peer,
  and its items go back by ping [M: close text].
- **Write-free sessions.** S2 is required only after written work. A-b adds a yes precondition to
  `/are-we-done`. That matches E0, and I found no FP from it.
- **Trigger surface.** 115 of 1,085 yes closes (10.6%) carry an undriven or unfiled-prose
  `follow-on:` [M: `analyze.py`]. Among the explicit-scope cases, the only FP exposure I found is §3's.

## 5. Gaps in this pass

- No A/B: agent reading of the new text is unmeasured, as it is for the designer.
- The scope-limit regexes miss paraphrases, so exposure may be undercounted [E].
- I did not run the full `completion-assert.bats`.
- The recommended core+D tree has measured units, but no test run of its own. The designer's runs were
  on core and on core+D+E.

## 6. Required for this lens to read 90

1. Use the payload `nothing is open` (0 of 976 flips, measured), or widen `_SETTLED` to cover
   `drivable`, and add a drain-peer-findings test with the new payload plus a tell word.
2. Replace `"research only" or not` with `unless the operator excluded it`, in slim, global, why-tier and
   are-we-done (−7 net in slim; judge admits it, measured).
3. Run the full completion-assert and drain-peer-findings suites on a git checkout of the recommended
   core+D tree, not on core or core+D+E.
