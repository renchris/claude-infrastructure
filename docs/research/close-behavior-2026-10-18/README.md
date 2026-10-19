# Close behavior 2026-10-18: synthesis

Sources: `INCIDENT.md` and `axes/01-…` to `axes/10-…`. Each axis ends with a `## Skeptic verdicts` section.
Every conviction below is the skeptic-**adjusted** number, written as `NN (axis item)`. Refuted items are
dropped, or listed in §6. Numbers are labelled measured (with the command or axis that ran it) or estimated
(with the method). `T` is the incident transcript
`~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-004752-67086/5759497b-3947-4fd7-9d8b-e095bf134dbf.jsonl`.
Its early lines (at least through T:201) have the same line numbers in the quaternary
`…5759497b-….jsonl.handed-off` file (01 skeptic, check 5). `slim:N`
is `CLAUDE.rules.slim.10-session-close.md` line N, byte-identical to the live `~/.claude/rules/10-session-close.md`
(measured, `diff -q`, axes 01, 02). `round2/` holds four candidate deep-dives that were still in progress when
this was written. They are not used here.

## 1. Answer first

1. **Root cause (90-97).** The ✅ came from inputs that cannot see undriven researched work: no store holds it, REMAINDER is always 0, and SCOPE=met only means a DoD file exists. The close that named the work reads like an honest close, so every Stop arm missed it, and the one arm that matched (D1) had been capped 68 minutes earlier.
2. **Contributing causes (80-85).** The contract text supplied the shape (slim:22 "nothing of mine is open"; the follow-on licence at slim:146 and `why-tier.sh:90-91`). "Research only" was a private, unrecorded narrowing, not a `Scope` line. The rules that forbid this close (slim:68, :86, :184, :191) were resident and were violated.
3. **Fix set.** Add a store-keyed signal for undriven work (F17). Stop the Stop chain losing the close it exists for: read the payload message (F10), latch per fact or split the cap class (F11), run text-only arms first (F12). Add a follow-on arm discharged by a store fact (F13). Make net-negative rule cuts (F1-F3).
4. **No fix clears 90% after the skeptic** (the highest is F1 at 72), so no row is "to drive". `round2/C1`, `C2`, `C3` and `C5` are raising F10, F11, F13 and F1; re-score §5 when they land.
5. **Round 2 (§8, 2026-10-19), scored on net-positive:** the rule-text set (C5) and the stated-⛔ guard (C2a) clear; C5 is
   driven here and C2a landed from a sibling session (`f3944c0f0`); the per-fact latch, the follow-on arm and the offer lexicon are dropped on measured harm; the payload
   read (C1) and the Drive-state term (C6) are below the bar with named routes up. The continuation gap stays open.

## 2. Root causes, ranked

| # | Root cause | Evidence | Conv. |
|---|---|---|---|
| R1 | **No input represents "researched, drivable, undriven", so ✅ was honest by its own inputs.** | The rung chain reads git, custody, backlog, decide, the live layer and team stores (`scripts/wrap-ledger.sh:2492-2659`). REMAINDER counts only `- [ ]` boxes (`:924-931`), and no producer writes them (`hooks/dod-persist.sh:106`, `:127`). Measured: 0 open boxes in 78 DoD files (axes 04, 05, 09). `DOD=present` is set for any existing store file (`:905`), and SCOPE derives from that plus REMAINDER (`:938-940`). FILED_MINE=0 is circular when nothing was filed (axis 08 §1.6). T:640, 14:27:32Z: `READOUT=✅ Complete & landed`. The close followed 15 s later. | 90 (09 RC1); rung chain 97 (04 RC3); SCOPE 85 (05 RC4) |
| R2 | **The close text is invisible to every Stop arm, for a structural reason.** A yes followed by an undriven `follow-on:` is lexically the same as honest owner and park closes. | `close_verdict_polarity` reads polarity only (`hooks/lib/close-shape.sh:124-145`). `CA_YES_HEDGE` (`hooks/completion-assert.sh:373`) has no "because". `CA_OFFER` (`:1280`) matches 0 times. anti-deference `TELLS` (`:168`) matches 0 of 4 incident messages. dispatch-assert `NAME_TELL` (`:247`) logged `no-naming-tell` at 14:27:48Z (IDL). Census (§3): prose matchers reach a precision of only 1 in 4 to 1 in 12. | 95 (02 RC1, 03 RC1) |
| R3 | **Cap starvation silenced the one arm that matched.** Its causal weight is low, because D1 matched the wrong object. | IDL, sid 5759497b: `class:assert` fires 1/3, 2/3 and 3/3 at 13:18:34, 13:19:02 and 13:19:40Z, all on the same fact "1 commit(s) YOU wrote are committed-but-unlanded". Then at 14:27:50Z: `capped:3>=3 suppressed_arm:handoff rung:✅`. `MAX=3` (`completion-assert.sh:132`). D1, D3, D4 and D5 always fall to `assert` (`:1608-1615`). D1 matched close line 13, "needs your hand" (the 70% settings.json item), not the §5 waves. | happened 97 (02 RC3); would have changed the outcome ≈30 (08 §3.5) |
| R4 | **The contract text supplied the shape.** | The template at slim:22 reads "`yes — nothing of mine is open; follow-on: <filed ids\|none>`". The certificate never rendered at the close (operator-readout timed out at 10,048 ms, T:651), yet the agent wrote its phrase, so the phrase came from the template. slim:146 says "A qualification goes in S2's `follow-on:` clause, beside the assertion." `hooks/lib/why-tier.sh:90-91` repeats that in hook feedback, and slim:156 adds "let S2's `follow-on:` clause cover it". The rules that forbid the close (slim:103, :105) are keyed to the rung, and the rung read ✅. The same template produced the 09-08 incident (`docs/research/conviction-close-2026-09-08.md:17`). The contract also contradicts itself, since the template types the value as ids or none. | 80 (01 RC1, RC2; 08 RC2); 65 (02 RC2) |
| R5 | **"Research only" was a private narrowing, and nothing forced the intake freeze.** | T:201, a thinking block at 06:06:11Z: "I'm scoping this as research-only". No `dod-persist.sh set` call before 20:04:35Z in the main, quaternary or 38 subagent transcripts (04, 05). The first tracked write (`git add`, 13:18:07Z) required a freeze (slim:26), and the freeze was skipped. The inline capture path is dead: `autoCompactEnabled:false` (`~/.claude/settings.json:1305`), and 0 PreCompact-labelled DoD blocks (05). "Research" was the operator's own word (T:179), and the study README says "Read-only synthesis" (README:8). | 85 (05 RC1 90, 08 RC6 85); the fence-versus-floor reading is latent, 55 (01 RC3) |
| R6 | **The resident rules already ordered the drive and were violated.** Text was not missing. | slim:68 "Above 90% there is nothing to ask: implement". slim:86 "an open plan item is open work, so drive it or answer `Good to close: no`". slim:184 "'Out of scope' … reasons, not impossibilities". slim:191. The close itself says "I'm 95% sure of it" (T:643, line 11). T:670 (agent): "your rules already say 'out of scope' isn't a reason". | 85 (synthesis estimate from 08 missed item, 05 RC2 70, 09 RC2 55) |
| R7 | **The advisory "should we" stops were lost to Stop timeouts and a stale-message race,** plus a lexicon built for asking rather than describing. | T:121 opens "Yes, but keep it narrow.", which passes the close gate through `CA_SETTLED` (`completion-assert.sh:360`, `:394-397`). completion-assert ran 5,687 ms against a 5 s timeout (T:122) and left no IDL row. T:167 says "Investigating the load now", and the turn stops with no tool call. Both hooks read the transcript tail (`completion-assert.sh:282-285`, `anti-deference-nudge.sh:159-162`), not the payload's `last_assistant_message`. The operator replied 12-19 s after each Stop (03). 07's "no hook looks at advisory turns" was refuted. | 70 (07 S0); lexicon 95 (03 RC1) |
| R8 | **The continuation actuator had nothing to fire on.** | `session-continue.sh` is state-gated (`:4-10`). The mechanical arm needs 🔧 plus the session's own dirty paths (`:1103-1110`), and the ship floor needs 📦 or 🚀 (`:1216`). The sentinel is agent-armed, and slim:217 says "On 🔧, and only on 🔧 … Clear it … as soon as the state becomes ✅". The transcript has no `set` call. `session-continue.log` holds 5 `cli-clear` records for this sid between 10:33 and 13:27Z, 4 of them from recovery runs (09 skeptic). No context-preserving self-goal path is built (09 RC3 60). Filing would not have driven anything either: the dispatcher fired 0 workers from 2026-10-17T21:57:43Z to 2026-10-19T00:59Z (135 summaries, measured, 05). | 93 (03 RC3) |
| R9 | **Delivery constraints that every fix inherits.** | operator-readout emits only `systemMessage` (`operator-readout.sh:1959,2107,2160,2200`), so it never reaches the agent. Stop timeouts measured over 3,329 Stops in 24 h: readout 20.0%, session-continue 13.4%, completion-assert 4.4% (04). Over 30 days, 18.1% (4,426 of 24,443) of completion-assert runs took 5 s or more (07). | 80 (04 RC5) |

**Corrections to INCIDENT.md** (the file is left untouched, per the brief):

- No `Scope (frozen): research only` line was ever written (R5).
- The close is at 14:27:47Z (T:643), not "09:19 local".
- The three completion-assert fires were landedness fires at 13:18-13:19Z. At the close the hook was capped, and
  D1 had matched and was suppressed (R3).
- The ✅ did not come from "git state alone". The ledger reads five non-git stores, and none of them held the
  waves (R1).
- The 06:03 and 06:04 Stops were partly killed by timeouts (T:122, T:174), so the hooks were not simply blind.

## 3. Census (axes 06, 07), with cross-checks

### 3.1 Yes closes that carry follow-on work (axis 06, 30 days, non-`/private/tmp` projects)

All counts are measured by `analyze2.py` over `analyzed.json`. Where the skeptic's re-run differs, its figure follows in brackets.

- **Verdict counts.** 1,452 `✅ Good to close: yes` and 2,341 `❌ … no` [2,342].
- **Non-empty follow-on.** 494 of the yes closes (34.0%). 65 (4.5%) use explicit undriven words such as
  waves, not started or next step.
- **`none` plus prose.** 118 (8.1%) [119-122]. The claim that 61 of these name next steps, plan items or
  remaining work did not reproduce: the re-run found 39.
- **Prose with no 12-hex id.** 234 (16.1%) [236]. Of those, 161 (11.1%) [158] also lack an owner or park marker.
- **Hand label of the 158** (estimated, 06 skeptic). About 54% are owned by the operator. 26 are a benign
  `none` plus a qualifier, 12 are tracked under non-hex ids and 15 belong to a third party. Only about 10-13
  are drivable work nobody started, which is roughly 0.7-0.9% of yes closes.

**Cross-check, the same rate from five other axes.** Each axis used its own classifier, so the rows are not
additive.

| Axis | Window | Base | Prose follow-on | Undriven agent work | Measured by |
|---|---|---|---|---|---|
| 04 | 7 d | 337 yes closes | 38 with no id | 4 with no owner word, about 1 true | `sk04_census.py`; truth by hand |
| 03 | 4 d | 49 YES closes with a clause | n/a | 1 (the incident) | `f1audit.sh` |
| 09 | 14 d | 321 line-1 yes closes | 66 | about 1-3 | `a09_followon.py`; truth by hand |
| 02 | 14 d | 556 YES closes with follow-on | 54 unique | real matcher fires 14, about 2 true | prototype awk; hand read |
| 10 | 4 d | 1,240 turn-final messages | signal B fires 25 | 1-2 | `signals_bc.py` |

**Reading.** The incident shape is rare: about 1% of yes closes or fewer. It is also lexically identical to
honest closes, so any prose matcher's precision lands between about 1 in 4 and 1 in 12. That is the empirical
basis for R2, and for rejecting prose detectors in §6.

### 3.2 Pushback (axis 06)

- **Re-asks.** After a final yes, the next operator message re-asks "good to close?" in 106 of 399 cases
  (26.6%). After a no, it is 21 of 316 (6.6%).
  - The re-asks are mostly ritual. 75 of the 106 are the exact text `Good to close?`. After a re-ask, the next
    close is yes in 77 of 85 cases.
  - The rate is the same whether the yes answered a close question (16/60) or was volunteered (90/339)
    (06 skeptic).
- **Drive demands.** These are "proceed", "conviction %", "drive us" and similar. They follow 11 of 66
  named-work yes closes (16.7%), against 17-20 of 283 none or filed-id closes. Fisher p=0.027, and the
  result depends on the regex. Honest no closes draw them at the same rate, 16.5% (p=1.0).
- **Verdict placement is fixed.** Since 10-11, 315 of 329 yes closes put the verdict first (06 skeptic).

### 3.3 "Should we …?" and other advisory turns (axis 07, 30 days)

- **Volume and outcomes.** Over 3,294 transcripts and 7,254 operator messages there were 124 advisory turns.
  95 acted (77%), 16 recommended and stopped (13%), and 13 answered with no action (10%).
- **Clear defects, by hand reading** (estimated). 5 of 124 (4%), or 8 (6.5%) counting borderline cases. This is
  a lower bound, because acted turns that did part of the work and then asked were not hand-read.
- **How those Stops were lost.** This is the 07 S0 replay of the 16 recommended-and-stopped finals.
  - 7 passed the close gate through a line 1 opening "Yes,".
  - 2 were killed by the 5 s timeout: rs04 at 5,687 ms and rs14 at 5,077 ms.
  - 3 fit a stale transcript-tail read: rs05, rs13, rs01 (70%).
  - Arm health over 20 days: D4 fired 2 times. The anti-deference `deference` arm fired 24 times in 15,852
    records.
- **Cost to the operator.** 42 short affirmations of 80 characters or fewer in 30 days, 23 of them after a
  recommendation (`affirm.py`). "Proceed with/as your recommendation(s)" appears in 25 messages, some of
  them quoted inside fired briefs (`phrases.py`). Example: `d41d9684…jsonl:1138`, "Proceed with all
  recommendations as they are >=90% conviction."

### 3.4 Method caveats

- **Regex classes.** Every class is regex-defined, and drivability was judged by hand on small samples.
- **Axis 06 corpus.** The file count is inflated by the `~/.claude-next` symlink (7,238 paths, 5,527
  realpaths). Closes were de-duplicated, so close counts are unaffected. Its "≥1 Stop-hook feedback before
  reply" figure is cumulative over an episode: immediately after a close it is 16.2% for yes and 23.9% for no.
- **Axis 07 method.** It de-duplicates on `(sessionId, uuid)`. Its `gate.py` firing rates were refuted, because
  they measured an OR on truncated text. The act classifier's precision is about 83%, from 12 hand checks.
- **Scratch lost to the reboot.** The 16:34 reboot cleared every `/tmp` scratch directory: `close-census`,
  `should-census`, `ca-axis02`, `ax03`, `a09_*` and `detector-proto` (measured `ls`, in the skeptic and round2
  setup notes). None of the census can be re-run from disk, and every number in this section was measured
  before 16:34.

## 4. Prior art: what was tried, and why it did not hold (axis 08)

| When | What was built | Why it did not stop 10-18 |
|---|---|---|
| 07-17 | anti-deference-nudge lexicon, later widened spelling by spelling (`4074710a8`) | It detects phrases, and the close contained no deference phrase. The semantic successor, the Jev arm, was retired 09-21 after 0 marginal detections over 160 closes and an HTTP 403 on every call (`anti-deference-nudge.sh:355-368`). |
| 07-25 | dispatch-assert, for "narrated-not-dispatched follow-on work" (`2fdfa7da2`; header `:2-15` describes 10-18 85 days early) | `NAME_TELL` has no `Follow-on: <noun>` form. Its reach is 5 of 2,045 close texts (0.9%), and widening it is a standing non-action (`SYNTHESIS.md:137`). Any store write discharges it. |
| 08-01 | self-certifying close, which coined "✅ SAFE TO CLOSE — nothing of mine is open" from git (`832e286c5`) | The ownership-scoped phrase migrated into the verdict template. DoD remainder was excluded on purpose, because it "would block every close forever". |
| 08-10 | Pyramid close contract and the `follow-on: <filed ids\|none>` slot (`8ed9da234`, `cb25e3a56`) | The slot assumes follow-on work is filed and nothing validates it. A02's skeptic predicted a boilerplate `none` route-around. |
| 08-17 | class split for the starvation fix (item `3b464e94b3ff`) | It split off only shape, verdict and act. D1, D3, D4 and D5 still share `assert` (R3). |
| 08-25, 09-05 | FILED demoted to an exception; four-class `--why-not-now` impossibility gate (`4b88aa1f6`, `3d010c0f6`) | The gate binds only `cc-backlog add`. A session that files nothing never meets it. |
| 09-04/05 | FILED_MINE and the drain floor (`96db63710`, `de81e510b`) | Both key on filing, which is a circular zero. The drain floor is precedent for a rung term derived from scope words (`wrap-ledger.sh:935`). |
| 09-07 | memory `a-plan-is-not-a-queue.md` | Memory only. Nothing scans docs for unfinished waves. |
| 09-08 | exhaustive-drive wave: E0 row (slim:99), `drain-peer-findings.py` (`8ff216474`) | E0 is prose. The harvester was never scheduled: 0 `peer-drain` rows, and no LaunchAgent references it (measured, 08). |
| 09-08 | conviction protocol, UNCONVICTED_MINE (`4ddbd77d9`, `1caac9ceb`) | It gates what is filed to the operator. 10-18 filed and asked nothing, so it read 0. A prior close with the same "nothing of mine is open; follow-on" wording drew the same complaint (`conviction-close-2026-09-08.md:17-22`). |
| 09-26 | value-deadline lesson, "a narrowed scope makes ✅ honest" (`f0e1c62b1`) | A lesson in the situational tier, not on the close path. |
| 10-01 | Active research program exemption (`b1fd89b6a`; slim:74-80) | Not in play: `programs.json` holds only `truememory-2-0`. Every new arm must keep this exemption, or it reintroduces the "no, one more thing" loop that operator ruling `83adb541ea19` stopped. |
| 10-10 | close verdict first (`445749840`, `afb9d93d2`) | "The yes path is not tightened at all" (`docs/research/close-verdict-first-2026-10-10/design.md:81`). |
Standing non-actions that bind §5: `docs/research/exhaustive-drive-2026-09-08/SYNTHESIS.md` lines 119
(store-or-silence gate nags live conversations about 1:1), 137 (no `NAME_TELL` widening), 139-140 (no prose
detector for the un-filed close) and 144-147 (no agent-type Stop hook). Axis 08 F6 reconfirmed them at 88.

## 5. The fix set

**Bar.** A row is "to drive" only if its post-skeptic conviction is above 90. **Result: no row qualifies.** Every
status below is "below bar", followed by what would raise the row. Under slim:68 (F2), the next step for a row
below the bar is research that raises it, not a park. That research is the job of the round-2 slots: `round2/C1`
covers F10, `C2` F11, `C3` F13 and `C5` F1.

**Budget facts for every rule-text row.** All measured on this tree.

- The user tier is **60,998** against a budget of **60,000**. Measured with the repo loader,
  `instruction_budget.Loader(DiskFS(), Excludes()).user("~/.claude")`: `CLAUDE.md` 28,397 + `00-mission-board.md`
  2,284 + `10-session-close.md` 30,317.
- `judge()` (`hooks/lib/instruction_budget.py:648`) refuses a change when `nt > budget and nt > ct`. Each
  rule-text commit must therefore be **net-negative on its own**: an addition lands in the same commit as its
  paired cut.
- The X1-X5 pointer tails are pinned by `tests/research-program-exemption-rules.bats:32-37` and cannot be cut.
- These cuts are unpinned. Each anchor matches once, and `grep -rlF` over `tests/` finds no pin. Sizes are in
  UTF-16 units:
  - **X6**: the slim:217 parenthetical "(each `set` resets the counter; …)", 207.
  - **X7**: the slim:184 sentence "Unused weekly quota does not roll over … understates spend.", 219.
  - **X8**: the slim:4 sentence " Before writing or debugging a Stop hook, read the reference … extend the turn.", 212.

  All three repeat text kept in `CLAUDE.global.md` (axis 01 §3, re-measured by its skeptic).
- `CLAUDE.global.md` deploys as the non-loaded `~/.claude/CLAUDE.full.md` (`config/instruction-budget.json`
  `_deploy_sources`). Editing its mirrors is hygiene only: no budget, no behaviour (01 skeptic, check 3).

### 5.1 Rule text

| id | fix | files | conviction | always-firing guard | status |
|---|---|---|---|---|---|
| F1 | **Delete the follow-on licence.** Remove the slim:146 sentence " A qualification goes in S2's `follow-on:` clause, beside the assertion." (−72). At slim:156, change ``omit S6 and let S2's `follow-on:` clause cover it.`` to `omit S6.` (−42). In the same commit, change the hook text `why-tier.sh:90-91` ("Anything that would withdraw the assertion goes in the `follow-on:` clause…", 0 budget) and the global mirrors `:927-929` and `:982`. **Δ −114, a pure cut.** | slim; `hooks/lib/why-tier.sh`; `CLAUDE.global.md` | 72 (01 E2/E3); 55 (02); 40 (06 F2) | Text only, no alarm. | below bar. On a repo copy, show that `why-tier.bats`, `completion-assert.bats` and `research-program-exemption-rules.bats` stay green; grep finds no pin on either sentence. Show on a close corpus that parked-with-id qualifications stay in `follow-on:` and do not move to line 1, where D3 `CA_RETRACT` (`completion-assert.sh:361`) fires (06 F2). |
| F2 | **Retype the yes payload.** At slim:22, change `nothing of mine is open` to `nothing drivable remains` (+1) and `who owns it` to `who drives it` (+2). Append " A stated park or a filed id is not drivable." after ``(`line-1-rung`).`` (+45). **Δ +48, paid by X8.** Mirror in `close-shape.sh:179`, `why-tier.sh:172-173`, `commands/are-we-done.md:40,49,61`, `commands/wrap.md:176`, `operator-readout.sh:1352` and `CLAUDE.global.md:560`. | slim; the 6 mirror files | 70 (01 E1); 65 (08 F1) | Text only. A yes stays reachable on `none`, on filed ids and on a stated park; ⛔ is untouched. | below bar. The phrase sits on 21 test lines in 9 files (measured `grep -c`), 9 of which pin `nothing of mine is open; follow-on`. Run them, plus `completion-assert.bats:2468` (t6a must still pass), on a copy. Measure whether `follow-on: none` followed by a silent drop increases (01 E1 risk a). |
| F3 | **Make the hold rule rung-independent.** At slim:103, change `may end a turn holding work.` to `may end a turn holding drivable work, whatever the rung.` **Δ +28, paid by X6.** | slim | unscored (01 skeptic, missed item 4) | Text only. ⛔, money-landing 📦 and stated parks still end a turn. | below bar. Needs a skeptic score, and reconciliation with slim:86 and :148, which keep an honest no as a valid resting place (01 missed item 8). |
| F4 | **A drop names its failed test.** At slim:72, change `…one-line mention unless` to `…one-line mention naming the failed test unless`. **Δ +23, paid by X7.** | slim | ≈70 (01 E7 alone) | Text only. | below bar. It was scored only inside the refuted E7/E8 pair and needs its own pass. |
| F5 | **Every S2 verdict asks about the task.** At slim:86, change `…"100% complete?") asks` to `…"100% complete?"), and every S2 verdict, asks` (+23). Change `an open plan item is open work` to `an open plan item, or an unfiled recommendation over 90% in a doc this session wrote, is open work` (+68). **Δ +91, paid by X7.** Keep `relaying the certificate` on the line, because `research-program-exemption-rules.bats:34` pins it. | slim | 65 (01 E4) | Text only. Scoped to over 90% and unfiled, so items at 90% or below handed to cc-decide, and stated parks, do not force a no. | below bar. Re-score the scoped wording, which is narrower than the E4 the skeptic scored. |
| F6 | **Name the "should we" shape; docs store findings only.** At slim:99, add `(a "should we …?" answered with a plan included)` after `names drivable work` (+49). At slim:171, add `(findings, never remaining work)` after `measurements` (+33). **Δ +82, paid by X6.** | slim | 60 (01 E9/E10) | Text only. | below bar. slim:99 already covered the 06:03 turn and was violated (R6). Nothing shows that moving or adding text changes behaviour. |
| F7 | **Trim slim:34.** Change `No ledger, no auto-continue, no readout. Work the turn itself named is not exempt (see E0 below).` to `No ledger, no readout. Work the turn names still drives (E0 below).` **Δ −30, a pure cut.** | slim | 55 (03 rule text) | Text only. | below bar. 07 S1 found the row is not read as a licence (55). The resident cut is 30 characters, not 240, and no behaviour change is measured. |
| F8 | **Size is never a FAIL.** At slim:70, append `; size is never a FAIL: fire sessions or a team for what one context cannot hold` to `Bounded means scoped, not deferred`. **Δ +80, paid by X8.** | slim | 55 (01 E6) | Text only. The no-capacity filing class (slim:184) stays as the backstop. | below bar. The incident used no size-based FAIL (01 RC4). |
| F9 | **A research scope is a floor.** At slim:26, append "A research scope bounds what is researched, not whether its findings over 90% get driven, unless the operator's own words exclude implementation." **Δ +146, paid by the X6-X8 remainders.** | slim | 45 (01 E5, 05 P1). The routing clause "drive, fire with `--notify-back`, or decide" scores 60 (05 P4), but slim:184 already says it. | Text only. An explicit operator exclusion binds, and the research-program exemption is unaffected. | below bar. It targets a path the incident did not take: the narrowing was private and unrecorded (R5). |

**Budget ledger, if F1-F9 all land.** All figures are UTF-16 units, measured per edit with python against this tree.

| Cut | Pays for | Left over |
|---|---|---|
| X8 −212 | F2 +48, F8 +80 | −84 |
| X6 −207 | F3 +28, F6 +82 | −97 |
| X7 −219 | F4 +23, F5 +91 | −105 |
| leftovers −286 | F9 +146 | −140 |
| F1 −114, F7 −30 | (pure cuts) | −144 |

The net change is **−284**, so the tier goes from 60,998 to 60,714. That is still over 60,000, but it is a
decrease, which `judge()` admits. This is estimated by arithmetic on the measured deltas.

### 5.2 Stop hook arms

| id | fix | files | conviction | always-firing guard | status |
|---|---|---|---|---|---|
| F10 | **Read the Stop payload's `.last_assistant_message` first**, falling back to the transcript-tail scan. Change `completion-assert.sh:282-285` and `anti-deference-nudge.sh:159-162`. Both already hold the payload in `$input` (`:182`, `:142`). In-repo precedent: `hooks/subagent-stop.sh:93` and `hooks/stop-failure-marker.sh:111`. | the 2 hooks; their bats | unscored as a fix; the race it cures is 70 (07 S0) | No new arm. Existing arms read the right text, and the fallback keeps today's behaviour. | below bar. Confirm that the Stop payload carries the field on the installed 2.1.293, then replay rs05, rs13 and rs01. `round2/C1` is in progress. |
| F11 | **Stop repeated ledger convictions from starving the terminal close.** Variant A, a per-fact latch: a ledger-only `assert` fire whose `facts` string already fired this session abstains `latched-same-fact` and spends no slot (`completion-assert.sh:1617-1620`; FIRED line format at `:1636`). Variant B: give D1, D3 and D4 their own cap classes at `:1608-1615`. | `hooks/completion-assert.sh`; `tests/completion-assert.bats` | B: 70 (08 F3) and 40 (02 surface). A: unscored (02 skeptic: 19 of 30 sessions with 3 or more fact-bearing fires spent at least 3 on one fact). | Every class keeps a hard cap and the per-message latch. | below bar. B turns `completion-assert.bats:1894-1906` red by design, and its marginal reach is 4 non-ledger-only trips in 20 days (08 skeptic). For A, whether a repeated conviction is useful is unmeasured. `round2/C2` is in progress. |
| F12 | **Decide the text-only arms (D3, D4, D6) before the ledger and backlog reads**, so a 5 s kill no longer loses them. | `hooks/completion-assert.sh` | unscored (07 S4) | No new firing. | below bar. Needs a design and a latency measurement. 18.1% of runs took 5 s or more over 30 days, but only 1.2% after 10:53Z on 10-18, so the slow runs cluster under load (07). |
| F13 | **A follow-on arm discharged by a store fact (D8 v2).** On a ✅ yes from an origin session with written work, the arm reads the verdict line's `follow-on:` value from `MSG_UNQ` (`:441`). If the value is neither `none` nor `dropped …`, it blocks once, unless this session wrote a backlog, registry or cc-decide record (dispatch-assert's `discharged_since`, `dispatch-assert.sh:168-173`). It gets its own class `followon` (max 2) and keeps the D6 gates (`:1409-1416`). | `hooks/lib/close-shape.sh`; `hooks/completion-assert.sh`; `tests/completion-assert.bats` | ≈70 (02 skeptic's variant); D8 v1 50; 03 F1 62; 06 F1 45 | Silent on `none`, a NO verdict, 👤, ⛔, assignees, fired peers, write-free sessions and active research programs. Capped at 2. | below bar. `round2/C3` is in progress. It must answer the standing non-action at `SYNTHESIS.md:139-140`. A filed row discharges it (FILED-as-exit, 08 §4) and a ❌ relabel passes it, so it repairs honesty, not continuation. |
| F14 | **A plan-not-driven arm in anti-deference-nudge**, for the "What I'd do, in order" and "diagnosed, not applied" shapes. | `hooks/anti-deference-nudge.sh`; bats | 45 (03 F2, F3); 40 (10 F4) | Needs silencers for a ⛔ line 1, a 12-hex id, `Parked:`, armed `session-continue.sh set`, `fired`, and plan mode. The hook reads neither the operator message nor `permission_mode`. The branch must sit before `:529` to avoid the FIRE_KIND mislabel. | below bar. Synthetic fixtures p8-p13 fire on a decision, on a park and on the arm's own remedy (03 skeptic). The prototypes were lost in the reboot. |
| F15 | **Bind open_packet_B's conviction to the fork's own sentence** (`anti-deference-nudge.sh:123-125`). | same | 45 (03 F4) | No change to firing. | below bar. Taking the message's first number gives 95 on m4, which cc-decide refuses (it accepts 90 or less). |
| F16 | **Flag work handed over as "yours / your call" with a stated recommendation above 90%** and no cc-decide packet. | `hooks/completion-assert.sh` | 40 (07 F4) | Needs both the number (above 90, not 90 or more) and the framing. | below bar. Rests on n=1; matches 2 of 42 pre-affirmation turns. |

### 5.3 Ledger input

| id | fix | files | conviction | always-firing guard | status |
|---|---|---|---|---|---|
| F17 | **Drive-state rows plus an undriven ledger term.** A doc that lists drivable work carries a `Drive state` column. Each row holds exactly one token: `driven <sha>`, `fired <session>`, `filed <id>`, `decision <id>`, `parked <condition>` or `dropped <why>`. `wrap-ledger.sh` counts empty or invalid cells in docs this session wrote as a 🔧 term beside FILED_MINE (`:2563-2570`). completion-assert consumes the term in **its own class**, not `assert`. | `scripts/wrap-ledger.sh`; `hooks/lib/session-writes.sh`; `hooks/completion-assert.sh`; bats | 60 (10 F1, 04 Fix1, 08 F2); 55 (05 P2). The completion-assert twin scores 40 in class `assert` (04 Fix2) and 50 (09 F2). | Silent unless this session wrote such a doc, and silent once every row holds a valid token. ⛔ outranks it (`:2505`). Research-program exemption; fails open. | below bar. (a) `dropped: research only` clears it (measured, 10 skeptic), so tokens must be verified against the stores. (b) shas must be checked by patch-id, because ship-land rebases. (c) Ownership must come from the session's own Write content and Edit `new_string`, not from the reflog (`session-writes.sh:56-72`). (d) Latency: `session_writes_paths` takes 0.42 s, and 38 verified rows take 1.45-1.63 s, inside a 5 s Stop. (e) The incident doc had no such table, so coverage needs F25 or F18. (f) The prototype was lost in the reboot. |
| F18 | **A write-time Drive-state lint** in `hooks/validate-plan-structure.sh`, in its own branch. Not the `:64-70` case, which reaches the blocking status gate. Latched per (session, file). | that hook; `tests/validate-plan-structure.bats` | 50 (10 F2) | A non-blocking warning, latched, and silent once a table exists. | below bar. Without the latch it would repeat on up to 544 qualifying edits in 4 days. It flags finished docs. It must merge into the single JSON object pinned at bats `:120-131`. |
| F19 | **SCOPE=met only from this lineage's own frozen line** (`wrap-ledger.sh:903-940`). | `scripts/wrap-ledger.sh`; bats | 55 (04 Fix4) | No rung change. It only withholds the certificate. | below bar. "completeness UNKNOWN" would become near-universal: 8 attributed captures against 117 yes-closing sessions in 7 days. It breaks 4 fixture files. The 05 P3 skeptic's variant ("wrote tracked files and has no frozen line of its own") is unscored. |
| F20 | **Retire or repair REMAINDER.** Replace slim:11-12 `frozen-DoD remainder 0` with `no undriven follow-on (ledger)` and pay with a cut on slim:8 (net −15, 04 skeptic). | `scripts/wrap-ledger.sh`; `hooks/dod-persist.sh`; slim | 50 (04 Fix5) | No rung moves. | below bar. Other consumers: `handoff-fire.sh:7700` and `:7740-7765`. Pinned by `handoff-fire-ledger-stamp.bats:124`, `completion-assert.bats:171`, `anti-deference-nudge.bats:307` and `operator-readout-research.bats:120`. It must land after F17. Mirrors: `CLAUDE.global.md:850`, `commands/wrap.md:78`, `commands/are-we-done.md:60`. |
| F21 | **Readout 🔧 parts terms** for FILED_MINE, UNCONVICTED_MINE, CLOSE_FLOOR and any new term (`operator-readout.sh:1323-1330`). | `hooks/operator-readout.sh` | 50 (04 Fix3) | Display only. | below bar. A `systemMessage` never reaches the agent (R9). Measured: 6 "loose ends" fallbacks in 1,952 renders. |
| F22 | **Write the waves as `- [ ]` boxes under `Scope (grown):`** via `dod-persist.sh set`. REMAINDER>0 then gives 🔧 and a completion-assert contradiction, with no new arm. | `hooks/dod-persist.sh` | unscored (02 skeptic, missed item 7) | None: the store is append-only and has no verb to tick a box (05 RC3), so a written box never clears. | below bar. Needs a tick verb first. session-continue refuses to act on REMAINDER (`:997-999`), and `handoff-fire --terminal` refuses on it (`:7740-7765`). |

### 5.4 Continuation

| id | fix | files | conviction | always-firing guard | status |
|---|---|---|---|---|---|
| F23 | **A research synthesis emits `docs/plans/<slug>.md` with `status: open`.** cc-discover's plan-open critic already files those (`bin/cc-discover:311`, `scripts/find-plan.sh:93,165`, launchd `com.claude.discovery`). | the synthesis contract | 70 (08 skeptic, missed item) | No Stop alarm; the rows go to the dispatcher. | below bar. The dispatcher fired 0 workers from 2026-10-17T21:57:43Z to 2026-10-19T00:59Z: 135 summaries, and post-reboot `admitted=6 fired=0` (05). Of the C2 critic's 482 done rows, 387 are flood retractions. |
| F24 | **An enact floor in session-continue**, between the ship and wake floors (`session-continue.sh:1317-1322`). It is fed by a marker that `ship-land.sh` writes when a landed doc carries implementation sections. | `scripts/ship-land.sh`; `hooks/session-continue.sh`; a new lib; bats | 55 (09 F1); 40 (03 F6) | Once per doc blob sha, at most 2 per session. A `clear` issued after the marker parks it. | below bar. Discharge-by-fire must key on fired-peers `firedBySid`, because handoffs `firing_sid` is a pane (`handoff-fire.sh:17318`). `clear` writes `.mech` unconditionally (`:258-263`). Filing any backlog row must not discharge it. It has no fired-peer exemption. 29 of 30 implementer commits on such docs are docs-only, so it would trip on sessions that are enacting. |
| F25 | **An Enact step at the end of the research recipe** (`commands/research.md`, `skills/research-subagents/SKILL.md`): fire each row above 90% with `handoff-fire.sh --goal`, or file it with an impossibility class. | those 2 files | 45 (08 F4); 30 (09 F4) | On-demand text; no hook. | below bar. The incident ran `workflow-authoring` and `Workflow`, which are not in this repo, and never loaded either file. |
| F26 | **A cc-discover research-waves critic (C5).** | `bin/cc-discover` | 30 (05 P5) | Needs a date gate and F17's markers to stay quiet. | below bar. The dispatcher is idle, the C2 flood is the precedent, and it depends on F17. |
| F27 | **A context-preserving self-goal**: a detached watcher runs `arm_goal` (`handoff-fire.sh:9726`) on the session's own pane. | `scripts/handoff-fire.sh` | unscored. 09 skeptic: feasible; precedent row `recycle-bgwork-selfcall` at 20:10:54Z. | Agent-armed only. | below bar. Unbuilt; needs a design and a skeptic pass. |
| F28 | **Retire `scripts/drain-peer-findings.py`**, which has been print-only since 2026-09-09. | that script; `tests/drain-peer-findings.bats` | 30 (08 F5, scored as schedule-or-retire) | n/a | below bar. Choose between this and F30 first. Leaving it as is repeats the incident class. |

### 5.5 Operator-only

| id | fix | files | conviction | always-firing guard | status |
|---|---|---|---|---|---|
| F29 | **Stop-hook timeouts** in `~/.claude/settings.json`: `:1039` session-continue 5 s, `:1044` anti-deference 5 s, `:1049` completion-assert 5 s, `:1064` operator-readout 10 s. | `settings.json` (operator-only) | unscored | n/a | below bar; operator-only. The agent-side substitute is F12. Measured cost: 18.1% of completion-assert runs took 5 s or more over 30 days. |
| F30 | **Schedule `drain-peer-findings.py`** through a c10 migration that the operator stages (`8ff216474`). | `migrations/` | 30 (08 F5) | Needs a per-day cap. | below bar; operator-only. Its `--settle-hours 6.0` would have skipped the incident, which sat idle for 5 h 35 m. It files rows and drives nothing. |

### 5.6 Build notes for the closest candidates

No row clears 90, so the brief's per-fix insertion points and test sketches are given here for the five
candidates closest to the bar. When round 2 re-scores a row above 90, the implementation wave works from these
notes.

- **F1.**
  - Edits: the three anchors in the F1 row. Each matches once (measured).
  - Test: `grep -c 'A qualification goes in S2' CLAUDE.rules.slim.10-session-close.md` returns 0. `bats
    tests/why-tier.bats tests/completion-assert.bats tests/research-program-exemption-rules.bats` passes.
  - Budget: the loader's `user` total falls by 114, from 60,998 to 60,884.
  - Deploy: `diff -q` against `~/.claude/rules/10-session-close.md` after deploy.
- **F10.**
  - Edit: before `completion-assert.sh:282`, set
    `MSG="$(printf '%s' "$input" | jq -r '.last_assistant_message // empty')"`. Run the transcript scan only
    when that is empty. Make the same change at `anti-deference-nudge.sh:159`.
  - Bats, positive: the payload carries a close, and the transcript tail ends one record earlier. The arm must
    fire.
  - Bats, fallback: a payload without the field must behave exactly as today.
  - Replay: rs13 (`4a70830c…`, `:437`) must fire D4.
  - Fork budget: `tests/completion-assert-forks.bats:93-104` pins 0 `python3` calls on the no-close-tell path.
    Keep the change pure `jq`.
- **F11, variant A.**
  - Edit: at `:1636`, write `"$HASH $CLASS $FH"`, where FH is a short hash of `$facts`. At `:1617`, abstain
    `latched-same-fact` when `CLASS=assert`, d1-d7 are all 0, and field 3 already holds FH.
  - Bats: copy CAP SPLIT (`completion-assert.bats:1696`). Three ledger convictions with identical facts on three
    messages give 1 fire and 2 `latched-same-fact`. A following D1 close fires as class `assert`, count 2/3.
  - The test at `:1894` stays as it is.
- **F13.**
  - Lib: add the matcher after `close-shape.sh:161`. It reads only the verdict line's `follow-on:`, on `MSG_UNQ`.
  - Hook: the D8 block goes after `completion-assert.sh:1541`. Add `d8` to the abstain test at `:1546-1547` and
    to the arm string after `:1601`. Claim class `followon` right after `:1612`. The reason goes after `:1654`.
    Kill switch: `CC_CLOSE_FOLLOWON=0`.
  - Bats, fires: the T:643 text at RUNG ✅ with no store write must fire class `followon`, including when
    `assert` is pre-capped at 3/3.
  - Bats, silent: the same text with a cc-decide packet written this session. Also `follow-on: none`,
    `follow-on: dropped …`, the incident clause quoted in backticks on another line, rung 👤, an assignee, and a
    write-free session.
- **F17.**
  - Ledger: define the term after `wrap-ledger.sh:1451`. Source session-writes only in the bounded child, as at
    `:1759-1772`. Call it after `:2549`, and put the 🔧 arm beside FILED_MINE at `:2563-2570`. Emit keys after
    `:2799`, and extend the memo key at `:628-639`.
  - completion-assert: read the term next to `:1042-1043`, but claim a new class at `:1608-1615`.
  - Bats, ledger: an empty cell gives 🔧 with UNDRIVEN=1. All cells valid gives ✅. An open ⛔ decision gives ⛔.
    An active research program abstains.
  - Bats, completion-assert: copy CAP SPLIT. With `assert` at 3/3 and UNDRIVEN=1, the hook fires the new class.

## 6. Rejected approaches, and why

- **A new phrase lexicon, or widening `NAME_TELL`, `CA_OFFER` or `TELLS`** (07 F2 at 40; 03 F1's lexical
  core). This is a standing non-action (`SYNTHESIS.md:137`), reconfirmed at 88 (08 F6). Widening `CA_OFFER`
  adds 0 clear defects (07 skeptic). Lexical arms are evaded by dropping or relabelling the clause, and they
  punish naming the work (03 skeptic fixtures p1-p6).
- **An LLM judge or agent-type Stop hook.** The Jev arm was retired with 0 drivable detections at p≥0.90 over
  160 closes, and every one of 372 calls returned HTTP 403 (`anti-deference-nudge.sh:355-368`). See also
  `SYNTHESIS.md:144-147`.
- **A store-or-silence terminal gate.** It nags live conversations about 1:1 (75:44:42, `SYNTHESIS.md:119`).
- **An advisory-stop arm placed before `no-close-tell`** (07 F1, refuted, 25). The AND form hits 0 of 5 clear
  defects, the OR form hits legitimate forks, and 4 of the 5 defects already pass the gate.
- **"Fail any yes whose follow-on is not `none` or ids" as prose** (06 F1 at 45, D8 v1 at 50). Its precision is
  about 2 in 14 to 6-8%, and it blocks operator steps at 👤. F13's store-discharge variant supersedes it.
- **Hardening D8 ids against `_ca_blg_cached`** (refuted, 15). That fold holds blocked rows only.
- **Paying for rule text with X1-X5** (refuted, 15). They are pinned by `research-program-exemption-rules.bats:32-37`.
- **"Merely naming remaining work is a defect"** (E8, refuted, 30). It turns legitimate one-line drops and
  slim:22 into defects, and it breaks the anchor at `research-program-exemption-rules.bats:37`.
- **Rule swaps that grow the budget:** 07 F3 (refuted, 15; +25 words net, and its cut phrase is absent from the
  global file) and 10 F3 (refuted, 15; +13 words net, and it cuts the pinned slim:191 sentence).
- **SCOPE through a lineage filter** (05 P3, refuted, 20). SCOPE derives from the store file existing
  (`wrap-ledger.sh:905`), not from the blocks the filter selects.
- **Putting ✅ on the verdict line only when follow-on is `none`** (06 F3, 20). It reverses a 2026-10-10 operator
  decision (`close-shape.sh:112-114`), and line 2 must carry the rung glyph anyway.
- **A readout-only remedy for continuation.** `systemMessage` never reaches the agent (R9).
- **DoD remainder in the mechanical or continue arm.** It "would block every close forever" (`832e286c5`;
  `session-continue.sh:997-999`).
- **A `research-wave` `--why-not-now` class.** `cc-backlog` refuses non-class reasons (`bin/cc-backlog:2428-2445`),
  and filing is not driving (05 P4).
- **Any new arm in the shared `assert` budget.** It starves exactly as R3 did (04 S0; 08 §4).

## 7. Pointers

| Axis | What it holds |
|---|---|
| `axes/01-rule-text.md` | Rule and contract text; edit and cut spans E1-E10 and X1-X8; the loader budget (skeptic check 2). |
| `axes/02-completion-assert.md` | Cap-starvation proof (latch file `25fe0af89b86448c.fired`); D8 spec and its refutation; the D8 v2 variant. |
| `axes/03-continue-and-nudge.md` | anti-deference and session-continue blind spots; F1-F6 and the FIRE_KIND bug. |
| `axes/04-ledger-readout.md` | Rung-chain inputs; REMAINDER and SCOPE; readout delivery; timeout rates; S0 cap finding. |
| `axes/05-dod-backlog-dispatch.md` | No Scope line; dead PreCompact capture; backlog and dispatcher throughput (0 fires since 10-17T21:57Z). |
| `axes/06-census-closes.md` | 30-day yes and no census; pushback; hand label (skeptic). |
| `axes/07-census-should-we.md` | 30-day advisory-turn census; S0 timeout and race mechanism. |
| `axes/08-prior-art.md` | Thirteen prior attempts; standing non-actions; plan-open critic. |
| `axes/09-goal-continuation.md` | Continuation levers, goal arming, enact floor. |
| `axes/10-detector-design.md` | Drive-state convention; heuristic-classifier audit (1 TP of 15). |
| `round2/C1`, `C2`, `C3`, `C5` | Round-2 deep-dives on F10, F11, F13 and F1, in progress at writing. |
| `round2/C1`-`C6` + `*.judge-{fp,efficacy,impl}.md` | Round 2, complete: six designs, each with three adversarial judges (§8). |

## 8. Round 2 outcome and drive state (2026-10-19)

**The bar, corrected** (critic, item 6). slim:68 asks for conviction that *landing the change is net-positive*. Round 1
scored rows on whether each alone would have prevented the incident, a defect seen in about 1% of yes closes, which no
row can clear; that bar reproduces "research done, nothing enacted". Each row below carries both numbers, and the >90
bar applies to net-positive.

| Row | Change | Net-positive | Prevents a repeat | Drive state |
|---|---|---|---|---|
| C5 (F1-F3) | Rule text: the yes payload says "nothing drivable is open"; the `follow-on:` licence (slim:146, why-tier, global) becomes its inverse; the S6 catch-all goes; the no-form names "who drives it". Resident rules −14 units. Companion: `drain-peer-findings.py` settles the new payload. | 90 designer, 91 impl judge; FP judge "close to safe" (3 of 976 past closes flip) | 35-45 that line 1 then leads with the remainder; 10-15 that the waves get driven | **driven** — `5a46647ad`, `8a9c8f0a3` |
| C2a | ⛔ guard: a close that LEADS with ⛔ (or a NO verdict over a ⛔ line 2) answers the ⛔ ledger term. 27 genuine ⛔ closes in 14 days were blocked. Tightened past the design: containment and a yes verdict never count (FP judge §4 found the designer's guard exonerated "✅ Good to close: yes" over ⛔). | 95 designer (27 of 27 hand-read genuine) | ~0 (fixes constraint 2, not the incident) | **driven by a sibling session** — `f3944c0f0` ("⛔ term spares a close that answers no", from `docs/research/research-pending-implementation-close-2026-10-18/`) landed first, and it is stricter: polarity from close-shape.sh, no line-2 disjunct. This study's equivalent was dropped at rebase as redundant |
| C2b (F11) | Per-fact latch on the `assert` cap. | 82 designer; FP judge ~10 | 5 | **dropped**: the budget it frees lands ~90% on honest closes, 4 of them genuine ⛔ decisions — a new constraint-2 violation |
| C1 (F10) | Stop hooks read the payload's `last_assistant_message` (the race is real: 20-23% of discriminating Stops judged the previous message). | 93 designer, 91 impl; FP judge 65-70 (+~75 FP blocks/day from un-blinding low-precision arms) | 0 for this incident | **below bar** — raise by: shadow mode first, plus the opaque-id gloss widening and an armed-wait park (C1 judge-fp §4); C2a is the ⛔ half of those guards and is now landed |
| C3 (F13) | Follow-on arm discharged by a store fact. | 25-30 (all three judges) | — | **dropped**: prose `follow-on:` precision 4-6% before gates; the cheapest compliance is a relabel |
| C4 | Conditional-permission offer lexicon. | 2-3 (designer's own non-action verdict confirmed) | — | **dropped**: 6.7% precision; ~81 junk class-B packets per window |
| C6 (F17/F18) | A `Drive state:` declaration in synthesis docs a session writes, read by wrap-ledger as UNDRIVEN ⇒ 🔧. | 87 designer; impl judge 80 with its §9 changes | the only row aimed at the cause (R1) | **below bar** — raise by the impl judge's §9 changes, then shadow mode with an elapsed-ms IDL row |

**Q4, readability** (critic, item 2). The ❌ form already leads by contract (slim:22, D6 verdict-first; 315 of 329 yes
closes since 10-11 put the verdict first). The defect was the remainder riding in the tail of a yes; C5 removes the
licence for that and names the driver. The incident close, correctly written:
`❌ Good to close: no — six implementation waves in README §5 remain; I am driving wave 1 now.`

**What remains, and who drives it.** No landed row turns finished research or an honest ❌ into the next action
(critic, item 3): every detector of undriven prose measured at 4-25% precision, and the one exact signal (C6) depends on
a declaration that 0 of the incident's writers and at most 13% of synthesis writers would have been prompted to write.
That is a framing question, not a missing fact, after two rounds and 46 agents; this session drives it through the
frontier escalation (CLAUDE.md § Frontier Tier Routing), then C6 and C1 in shadow mode from whatever that returns.

**Update, round 3** (`round3-frontier-panel.md`, H-CLOSE-1 solved-path-known). The panel refuted the verdict-no latch on
measured precision: an honest no-close names its driver in ~95% of ~40 sessions, so the leak is the yes-with-follow-on
shape, which C5 now makes a contract breach. The next build, a store-act disposition for non-✅ closes, waits on a
7-day post-C5 census (backlog `562b31cb7d99`, parked not-yet-true until 2026-10-26). C1 and C6 stay below the bar until that census.
