# C3 (D8 v2/v2b), efficacy judge: below 90

Round 2, 2026-10-18. I judged C3 through one lens, efficacy: would it have changed the incident outcome (the waves get driven, or the close leads with what remains)? Is gaming cheaper than driving? Does it fire at a Stop that actually runs?

I worked read-only in the repo. Every run used copies or `/tmp/r2-C3/judge-eff/`, with every state seam pointed into `/tmp`. Each number below is labelled measured (with its command) or estimated (with its method).

**Verdict: below 90.**
- **Conviction that C3, as designed, is effective enough to clear 90%: 30.**
- **It does fire at the incident's real Stop.** Measured on the real transcript, in the capped live state.
- **One edit gets past it.** Every cheap way out leaves the waves undriven: a text edit, a verbatim re-close, or the co-firing D1 arm's own cure.
- **The usual store cure is filing, and filing would not have driven anything that day.**
- **About a third to a half of its target Stops hit the 5 s timeout before the arm runs.**
- **Not run:** what the model actually does after the block. I did not run a model against it. The enactment share below is estimated from the dispatch-assert analog, not measured.

## 1. Does it fire at the Stop that actually ran? For the incident, yes

| Check | Result | How |
|---|---|---|
| Fires on the **real** incident transcript (cut off at the 14:27:47.478Z close), with `assert` pre-capped 3/3 | `fired arm:"handoff+followon" class:"followon" 1/2` | measured: `bash /tmp/r2-C3/judge-eff/replay_real.sh real-v2b …incident-trunc.jsonl 3`. The designer's harness used a synthetic transcript; this one uses the session's own 643 records. |
| Unpatched copy on the same input | `abstained capped:3>=3 suppressed_arm:handoff rung:✅`, the live IDL record | measured, same script, `/tmp/r2-C3/orig` hook |
| Write gate on the real transcript | positive (`session_writes_paths` lists the study's files) | measured |
| Turn start | `2026-10-18T14:27:23.140Z` | measured: `sd_turn_start` |
| Research-program gate | inactive. `programs.json` was last changed 10-16 22:57 and holds only `truememory-2-0`, rooted at `tm2-plan`. | measured: `jq` over the registry |
| Store records by the sid in [14:27:23, 14:27:47] | none. The backlog has only the 13:27:10 add and the 13:33:33 done of `9eedab74bff6`, and there are no packets. | measured: `grep -F sid \| jq` |
| completion-assert duration at the incident Stop | **3,350 ms** against a **5 s** timeout | measured: the transcript's `stop_hook_summary` at 14:27:57.597Z; the timeout is in `settings.json` `.hooks.Stop` (read-only) |
| What D8 adds against the live stores | 0.45-1.03 s, so the incident Stop would take about **3.8-4.4 s** | measured: `bash time_live.sh`, 3 runs at load average 338-356. The total is estimated: the live 3,350 ms plus this delta. |

So the necessary condition holds for the incident: it would have blocked at 14:27:50 instead of 5.5 hours later (the operator's pushback came around 20:0x, and pane 472 was fired at 20:09:15Z).

## 2. For its class, the 5 s timeout hides much of the target population

D8 is the last arm in the hook, and it needs the ledger's RUNG, so it cannot run before the ledger read. If a Stop is killed at 5 s, nothing is emitted.

| Population (14 days of `stop_hook_summary`, completion-assert entry) | n | p50 | ≥ 5,000 ms |
|---|---|---|---|
| all Stops | 11,700 | 938 ms | 13.6% |
| YES verdict closes | 426 | 4,825 ms | **48.1%** |
| YES with a non-nil verdict-line follow-on | 167 | 5,025 ms | **50.3%** |

Measured: `python3 -I /tmp/r2-C3/judge-eff/dur_yes.py`. Hook entries without a `durationMs` (about 5% in a 300-file sample) are excluded.

**A run of 5,000 ms or more means the hook was killed.** Measured with `dur_idl.py`: of the YES Stops at 5,000 ms or more, only 12 of 205 (6%) left a completion-assert IDL record. Below that line the rates are 138/143 (97%) under 3,500 ms and 77/78 (99%) at 3,500-4,999 ms. This is the designer's "103 of 212 have no IDL record at their Stop" explained, but the designer did not count it against efficacy.

**It is improving, but not solved, for YES closes.** Measured with `dur_yes_t.py`, YES closes at 5,000 ms or more:

| Period | n | ≥ 5,000 ms |
|---|---|---|
| before 10-15 | 303 | 54.1% |
| 10-15 to 10-18T10:53 | 99 | 34.3% |
| after 10-18T10:53 | 27 | 25.9% |

In that last period, 44.4% of YES closes took 4,000 ms or more. That is inside D8's own added cost of the limit.

**The in-sample true positives.** Measured with `tp_dur.py`, the five closes took 3,350 (the incident), 4,480, 5,089, 3,416 and 5,032 ms.
- Two were already killed, so D8 could not have fired on them.
- The 4,480 ms one would likely cross 5 s with the 0.45-1.03 s D8 adds (estimated).
- So the arm emits on about 2 or 3 of its 5 in-sample true positives (estimated).
- Fixing this would mean raising the hook's timeout, which is a `settings.json` edit and therefore an operator-only step, or doing F12-style reordering. C3 does neither.

## 3. Is gaming cheaper than driving? Yes, by one edit

All runs below use the v2b hook copy, with `assert` pre-capped 3/3 (the live state). Measured with `bash /tmp/r2-C3/replay.sh je-<tag> …`, fixtures in `/tmp/r2-C3/judge-eff/fx/`. Each variant changes only the incident's line 1; the other 14 lines are verbatim.

| Rewrite of the incident's own clause | D8 |
|---|---|
| unchanged (control) | **fires** |
| `Follow-on: none — the implementation waves in README §5 are a separate implementation pass.` | silent |
| `Follow-on: none filed; the implementation waves … haven't started, because this pass was research only.` | silent |
| `Follow-on: nothing, beyond the implementation waves in README §5, which a later pass picks up.` | silent |
| `Follow-on: n/a — …out of this pass's scope.` · `Follow-on: no — …separate pass.` | silent ×2 |
| `Follow-on: dropped the README §5 implementation waves from this pass, because it was research only.` | silent |
| `…haven't started; not worth starting inside a research-only pass.` | silent |
| `Follow-ons: …` (plural label) · `Follow-on — …` (no colon) | silent ×2 |
| the clause moved to line 2 | silent |
| `❌ Good to close: no — the implementation waves … haven't started…` | silent |
| `Follow-on: the implementation waves in README §5 are yours to prioritise.` | fires |

**Of the 12 one-edit rewrites, 11 silence D8.** In two of them the stated reason is the same "research only" that the block reason itself calls "not a disposition". `sd_dropped` matches only the word, never the reason. `_NIL_LEAD` is anchored to the lead, so `none —` / `none filed;` followed by the waves reads as nil. The block reason even advertises the text exits: "write follow-on: dropped <it> — <why> … the clause is follow-on: none."

There are three further exits that need no new text at all:

1. **A verbatim re-close passes.** Measured with `replay_real2.sh real-latch` run twice: the second run gives `latched-already-fired`. The message-hash latch is shared by every arm, and D8 keeps no obligation state of the kind dispatch-assert keeps (`$SKEY.pending`).
2. **The co-firing D1 arm's own cure discharges D8 without touching the waves.** The block D8 emits on the incident opens with D1's "File each operator-only step — `cc-backlog needs …`", about the 70% timeout raise. Measured on the real transcript:
   - Seeding one `needs` row for that step, filed by this sid in the turn, turns the run into `abstained capped:3>=3`: only D1 is left, and D8 is discharged (`SEED=… replay_real2.sh real-d1cure-row`).
   - Setting the ledger to `YOURS=1`/👤, which is what filing that row produces, gives `fired arm:"handoff+shape+act" class:shape`: D8 is not evaluated at 👤 (`RUNGV=👤 replay_real2.sh real-d1cure-rung`).
   - So D8's discharge is "any record by this session this turn", not "a record for the item the clause names".
3. **A parked row passes.** Filing the waves with `--why-not-now "no-capacity: research only"` passes D8 (the designer's `inc-cure-park` control) and FILED_MINE, so nothing drains the row.

## 4. Would the store cure have enacted the waves? Probably filing, and filing drove nothing on 10-18

**The closest precedent: dispatch-assert.** It is the same kind of block, discharged by a store record, built on "gaming the hook IS compliance". Measured with `python3 -I /tmp/r2-C3/judge-eff/after_block2.py` over the 53 dispatch-assert fires I could find in transcripts. Between the block and the next Stop:

| What the session did next | Count |
|---|---|
| a store write or fire | 7 |
| other tool use | 4 |
| text only | 42 |

My hand-read of the roughly 12 that look like true positives (estimated, from 160-character snippets in `after_block.tsv`):

| Response | Count |
|---|---|
| filed a row | 7 |
| drove the work in-session | 2 |
| dropped it | 2 |
| argued the hook out of it | 1-2 |

So filing is the most common way a session complies, about 58%, and driving the work is about 17%. For D1 `handoff` fires: 6 of 10 were store writes, all of them filings (measured, same script).

**Filing on 10-18 would not have driven the waves.** cc-dispatch's last fire was at `2026-10-17T21:57:43Z`, and it made none after that up to this read (about 10-19T02:00Z). That is measured from the IDL, `actor:"cc-dispatch"`, `action:"fired"`, and it agrees with README R8 and axis 05.

The designer's claim that "an agent row auto-drains through cc-dispatch" was false on the incident day. "FILED_MINE convicts it at the next ✅" is also capped in the incident's state: FILED_MINE sets contra=1, and the ledger arm draws on the `assert` class, which was already spent 3/3.

**What an unparked filing does give is readability.** It makes the rung 🔧 "Loose ends — N backlog row(s) you filed…" (`wrap-ledger.sh:2563-2566`), and D6's line-1-rung token (its budget unspent) would make the next close lead with 🔧. That is a real partial win, but the most likely outcome is that the work is recorded, not enacted.

**The block reason does not ask the close to lead with what remains.** v1's sentence ("If any of it stays undriven, line 1 is ❌ Good to close: no — <what remains + who drives it>") was removed in v2. It lists `none` as an exit, and the ❌ relabel passes with nothing to continue it (the designer's §5).

## 5. Net efficacy estimate for the incident (estimated, not measured)

| Link in the chain | Probability | Basis |
|---|---|---|
| The Stop finishes within 5 s | about 0.85-0.9 | 3,350 ms plus 0.45-1.03 s; load varies |
| The model's response, given a block | drive or fire about 0.2-0.35 · file (🔧 lead or parked ids) about 0.45-0.6 · text exit, D1-only cure, or verbatim re-close about 0.15-0.25 | the dispatch-assert analog, adjusted upward for the reason's explicit "a research-only scope is not a disposition" |

From those two links:
- **The waves get driven:** about 0.2-0.3.
- **The waves get driven, or the close leads with what remains:** about 0.5-0.65.

Both figures are well below 90. That is before the held-out precision problem: 20% for the incident class and 32% under the contract (designer §4.4). It predicts habituation, either to the one-edit exits or to `CC_CLOSE_FOLLOWON=0`, across the fleet.

## 6. Agreement with the designer

I agree with the designer's 40 and with "do not land as a blocking arm", and I put efficacy alone at 30. The mechanical claims I re-checked hold: it fires in the capped live state, both scopings are necessary, and dispatch-assert keeps its unscoped behaviour.

Three of the designer's claims are wrong or missing:
1. "filing drives continuation" (refuted for 10-18, §4);
2. the 103 Stops with no IDL record, which are timeout kills that bound the arm's reach (§2);
3. the co-firing D1 cure, which discharges D8 (§3).

## 7. What would have to change to raise efficacy

1. **Persist the obligation, as dispatch-assert does.**
   - Once D8 fires on value V, later closes in the session should be discharged only by a store record written since the original turn start that the follow-on clause cites by exact id (`filedBy`/`session_sid`/`firedBySid` = sid), or by a per-item drop.
   - Rewording to `none —`, a label change, moving the clause, a verbatim re-close and a ❌ relabel should not discharge it.
   - This closes all of §3 except the parked row.
2. **Key the discharge to the named item, not to any record this session wrote this turn,** so that D1's needs row for an unrelated step cannot silence it.
3. **Make it fit the Stop budget.** Measure the YES-close duration distribution with D8 on, under load, and show the rate of runs at 5,000 ms or more does not rise. Or take a timeout raise to the operator as a separate operator-only `settings.json` step.
4. **Put drive or fire first in the reason,** restore the "line 1 names what remains and who drives it" sentence, and stop listing `none` as an exit after a fire.
5. **Measure enactment directly.** Use a model-in-the-loop replay of the incident against the block in a sandbox, or a labelled post-block action census. The analog estimate in §4 is not enough for a 90% claim.
6. **Fix the held-out precision first,** which is the designer's own blocker. Test the scope gate on a third corpus.
