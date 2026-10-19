# C6 judge: false positives and always-firing

Round 2, 2026-10-18. Adversarial judge, FP lens, on
`round2/C6-doc-disposition-marker.md`, the design with a presence duty plus the `undriven` cap class.
This pass was read-only in the repo, and this file is its only repo write. Scratch work is in
`/tmp/r2-C6-fp/`. Labels: **[M]** measured (the command is named), **[E]** estimated (the method is
named). Load during the pass was 240-310 [M: `uptime`].

**Verdict: below 90.** The parser, the ownership rule and the store checks are quiet, and I
confirmed the designer's numbers for them. The presence duty is not quiet. In the 14-day census it
would have fired on **every** session that owns a synthesis doc and reaches a done-shaped close on
the ✅-eligible path: 20 of 20. Only 2 of those 20 had the incident's defect, undriven
high-conviction recommendations; 2 more had minor residuals. About 75-80% of its fires land on
sessions where nothing drivable was left. That breaks constraint (1) for most of the population the
term covers. It is not the "≈0.5 a day, recommends-nothing" exception that design §4 describes.

## 1. What I re-ran

| Check | How | Result |
|---|---|---|
| Owner set | `/tmp/r2-C6-fp/owners.py`: the designer's `coowners.py` join (`sess14.json` × `added14-ct.tsv`), extended to print owner session ids | 34 synthesis docs added in 14 days. 27 have exactly one qualifying writer session, 7 have none, and **0 have two** [M]. Confirms design §3.4 |
| Declarations today | `git grep -l -i -E '^Drive state:\|\|[[:space:]]*Drive state[[:space:]]*\|' -- 'docs/*.md'` | The only match is the C6 report itself, inside a fence. 0 of 85 synthesis docs declare anything [M] |
| Parser on the 27 owned docs | the prototype `/tmp/r2-C6/clean/scripts/lib/drive-state.awk`, `synth=1`, over `git show origin/main:<doc>` | **27 of 27 print `UNMARKED`** [M] |
| What each owner said at close | `/tmp/r2-C6-fp/closes.py`: main-thread assistant texts after the add commit's time; output in `closes.txt` | per-session classification in §2 [M for the text; the classification is my reading] |
| What completion-assert actually saw | `/tmp/r2-C6-fp/wouldfire.py` and `wfdetail.py`: every `completion-assert` IDL row (`idl.jsonl` plus 8 rotated `.gz` files, from about 09-27) for the 27 sids after each doc's add, joined to the message just before each row | 407 rows. **8 sessions** have a plain `ledger-clean` or capped-✅ row after the add, exactly the branch where C6 would add `contra=1` and fire [M] |
| Quoted mentions | fixtures `/tmp/r2-C6-fp/q1.md`-`q3.md` through the same awk | 3 of 3 produce records (§3) [M] |
| Laundering cost of the cure | fixture `q4.md`: the incident README plus one doc-level line naming the README's own landing commit | `VERIFY sha 1e7461db7`; `git cat-file --batch-check` reads `commit` ⇒ OK [M] (§4) |
| Fired-peer verification | read `bin/cc-custody` `list` | `list --json` without `--open` returns **every** row (open, return, abandon) from every cwd file. A returned peer's slug therefore keeps verifying, and there is no FP when a peer returns [M: code read] |
| Decisions and backlog stability | read `bin/cc-decide`, `bin/cc-backlog`; `ls ~/.claude/autonomy/decisions` | packets stay at `<id>.json` (624 files). Backlog `compact` drops only done rows older than 30 days and "has NO CALLER on this box", so `decision`/`filed` tokens do not decay within a session [M: code read] |
| ⛔ and write-free sessions | design tests 18 and 5, plus code read | ⛔ governs (`DRIVE_SRC=skip`). A write-free session hits `session_writes_paths` rc 1, which is silent. **No FP found here** |

I did not re-scan the 13.5 GB corpus: the owner set inherits the designer's scan. I did not re-run
bats, and I did not replay the full ledger on each FP case. Reachability comes from the IDL and the
transcripts, and the parser result from the awk.

## 2. The decisive measurement: who the presence duty blocks

Of the 27 owner sessions, 7 never reach the term [M: IDL rung and close text]:
- ⛔ governs in three: lr-reliability, method-exhaust and router-classifier-union.
- In one, custody is open (lr-wake-incident).
- One recycled with no done-shaped close (kitty-crash).
- One has no main-thread text after the add (router-classifier-e1h).
- One ran from a cwd in another repo (haiku55-upgrade, whose cwd is `personal/launch-film-2026`), so layer 1 reads the wrong reflog.

The other **20** reach a done-shaped close on the ✅/👤 path. Since 0 of 85 docs declare anything,
each would read `DRIVE_UNMARKED=1` and fire. The table classifies them by the session's own close
text and the doc's own status sections.

| Class | Sessions | n |
|---|---|---|
| **TP, the incident class**: a "yes" close over undriven recommendations | startup-hooks (14:27:50Z, capped-✅ row). recycle-failures-kitty (03:18:18Z `ledger-clean`: "✅ Good to close: yes … follow-on: none filed" over a root-cause report; at 04:00 the operator asked whether it could be implemented, and at 05:48 said "Proceed with all that we can") | 2 |
| **TP-lite**: named residuals with no record | weekly-strand-next (3 of 13 ranked improvements landed, no conviction numbers). teammate-teardown-verdict ("Not done here (named for the next owner)", 5 bullets) | 2 |
| **FP, honest done**: everything driven, filed, decided or nothing recommended; blocked only for a missing declaration | autodeny-prompts, browser-loop-probe, close-verdict-first, cloud-post-eval, goal-arm-readback, limit-recover-zero-memory, lr-stranded-husk, peer-mail-headline, proactive-parallel-ops, recycle-sigterm-proof, router-classifier-e1g (unless its cwd is a research-program cwd, unverified), sessionstart-readout, tm2-cost-vs-outcome | 13 |
| **FP, honest "no" or stated park** blocked as "your close reads as done" | teammate-resurrection: both 03:17Z rows are `ledger-clean` on "❌ Good to close: no — … I'll re-fire the recycle that builds it as soon as kitty responds". load-root-cause: its first `ledger-clean` rows are "❌ Good to close: no. Four implementation waves are still running" (14:00Z) and "W3 … is still running" (19:50Z), so its 2-fire budget is spent there. reask-haiku55: 08:06Z "Good to close: no — the decision workflow … is still running in this session" | 3 |

**Precision of the presence duty as a "you left drivable work" signal:** strict, 2 of 20 = 10%. Counting TP-lite, 4 of 20 = 20% [M counts; the classification is my judgment].
**FP share:** 16 of 20 = 80% [M].

**The subset the existing hook's own log proves.** Restricted to the 8 sessions whose IDL shows the
exact branch C6 would convert:
- TP 2 (startup-hooks, recycle-failures-kitty);
- TP-lite 1 (weekly-strand-next);
- FP 5 (autodeny-prompts, cloud-post-eval, load-root-cause, reask-haiku55, teammate-resurrection).

That is **62.5% FP** even on the proven subset [M]. The other 12 reached sessions have no IDL row
at their done-close timestamps. Examples: haiku55 16:53Z and 17:07Z, peer-mail 08:51Z,
teammate-teardown 23:41Z. That is consistent with the hook not finishing inside its 5 s bound
(README F29). Wherever the hook finishes, it fires.

**Rate.**
- About 16 FP sessions in 14 days, **≈1.1 a day** [M-derived]. Each costs 1-2 forced turns (cap 2), and each cure is a doc edit plus a commit plus a re-land, because the term only runs on a clean, landed tree [E: from the code path; land time not measured].
- The design's "≈0.5 a day" covers only the recommends-nothing subclass. In this window that subclass is tm2, browser-loop-probe and recycle-sigterm-proof, ≈0.2 a day [M], so the design's estimate holds for that subclass.
- The design never counted the dominant subclass, docs whose work was already driven: ≈0.9 a day.

**Why it does not get better at steady state.**
- Nothing teaches the convention before the block: no resident text, and skills reach ≤13% of writers (design §1).
- So each new owner session meets it fresh. Within its population the presence duty is an always-firing alarm.

**The block reaches the shadow gate's verdict in advance.**
- Design §8's flip criterion (a) asks that ≥95% of would-fires be truly the session's own undriven recommendations.
- On this 14-day retro set the predicate scores 10-20%, so a 7-day shadow of the design as written would fail (a) [M on the retro set; E that next week resembles it].

**Side effects of a persistent 🔧 on an honest session** (one that ignores both blocks or hits the cap) [M: code read]:
- `boundary-handoff.sh` free-win recycle requires `RUNG=✅` (`free_win_now`, `[ "$r" = "✅" ]`), so the pane is not recycled.
- operator-readout's ✅ SAFE TO CLOSE certificate disappears.
- The ledger finds the session through `CLAUDE_CODE_SESSION_ID` (`wrap-ledger.sh:499-501`), so all of these consumers see the term.

## 3. Quoted mentions and near-misses of the exact syntax

| Case | Fixture (in `/tmp/r2-C6-fp/`) | Parser output [M] | Reach |
|---|---|---|---|
| A doc that documents the convention in an unfenced table whose header is the Drive-state column | `q1.md` | `OPEN to-drive`, `OPEN driven-without-sha`, `OPEN dropped-without-reason` | any owned doc under `docs/` (the layer-1 grep admits it); rare [E], but this study's own docs are the likeliest writers |
| Prose that happens to start a line with the label | `q2.md`: a column-0 line "Drive state: fired sessions are verified …" | `VERIFY slug sessions`, which goes OPEN unless a custody row has that slug | same |
| A 4-space-indented code block (markdown code, not a fence) | `q3.md` | `OPEN to-drive` | same |
| Already dispositioned, under another header | the census of 85 synthesis docs | about **10 of 85 (≈12%)** already carry a per-recommendation disposition column under another name: `status` (close-behavior README itself), `Disposition` (cloud-post-eval: rows read "dropped" or "fixed, `cecc3f6b8`"), `Status` (proactive-parallel-ops, token-efficiency, load-hook-timeouts), `Landed` (grok-wiki-audit), `shipped` (lr100p-decisions) and others. The exact-header rule reads all of them as UNMARKED [M: header grep in `statuscols.txt`, then reading each header by hand] | all owned synthesis docs |
| Conviction tables that are not recommendations | close-verdict-first "How the 88% splits" (Part, Conviction); load-root-cause §7 "Open questions" (…, Conviction); haiku55 "Decision, Outcome, Conv." | each sets `ranked=1`, so an honest doc-level `none` is refused for the whole doc [M: grep and awk read]. The design's §4 claim that `none-over-a-ranked-table` "has no measured false-positive class" checked only reject headings | docs with any conviction column |

The fence skip is the only quote defence. Indented code, prose at column 0 and a documentation
table all parse.

## 4. The cheap cure for an FP is also the laundering hole

For an honest owner, the cheapest way to clear UNMARKED on a doc with a ranked table is one
doc-level line naming any commit object. The parser applies no conviction check to `driven`, and
`_drive_verify` checks only that the object exists:

```
$ awk -v doc=q4 -v synth=1 -f drive-state.awk q4.md   # incident README + one line, "driven 1e7461db7" (its own landing commit)
VERIFY	q4	1	sha	1e7461db7
$ printf '1e7461db7^{commit}\n' | git cat-file --batch-check
1e7461db7d343ea9e47fc035971bd9a541b54eb2 commit 789
```

So the incident README, with row #3 at 95%, clears with one line naming the doc's own commit [M].
The `dropped-at-conviction-95` refusal (design §3.3) protects only the `dropped` and `none` spellings.

There is a second escape. `fired <slug>` verifies against every custody row ever written, from any
cwd (§1). So the duty's FP burden (§2) buys less laundering resistance than §8 credits: "Laundering
of the one-line and ≥90 kinds is refused — 95".

## 5. Against the constraints (FP lens only)

| Constraint | Finding |
|---|---|
| (1) silent when nothing drivable remains | **Fails for the duty's main population.** It fires on 20 of 20 reached owner sessions, 16 of which had nothing drivable left [M]. ≈1.1 FP sessions a day, not 0.5 |
| (2) never blocks a ⛔ or a stated park | ⛔: met (test 18; ⛔ sessions measured as not reached). Stated park: **bent.** Three sessions' first fires land on honest "no, still running / will re-fire" closes, with a reason text that says "your close reads as done". Class-B (default-on-timeout) decisions such as `a4cb66b32b4b` and `05490056dd9f` [M: `jq .class` → `"B"`] do not raise ⛔, so those closes are blocked until a doc line names the decision |
| (6) one matcher per concept | Not an FP issue. Noted only because the fix in §6.3 should reuse close-shape's verdict polarity, not add a new lexicon |

## 6. What would have to change before this lens could pass 90

1. **Do not block on UNMARKED alone.** Keep it as a READOUT and IDL fact only, or gate it on evidence that work is undriven. Examples: the doc ranks a row ≥ 90 and no commit since the add touched anything outside `docs/`, or the close text itself defers the work (reuse C1/C4's matcher, not a new one). Then re-run this 20-session retro and require at least 95% of would-fires to be TP before any `on`.
2. **Accept existing disposition columns** (`Status`, `Disposition`, `Landed`, `shipped`, `Outcome`) with the same token grammar, or measure how much of the ≈12% this leaves.
3. **Skip the `undriven` class when the verdict line's polarity is NO.** Reuse `close_verdict_polarity` from `hooks/lib/close-shape.sh`. That removes the 3 honest-"no" and stated-park fires.
4. **Count a session's own filed decisions of any class as disposing** (read the decisions store by `session_sid`), so a class-B decision needs no doc edit.
5. **Close the doc-level `driven <any-sha>` hole.** Either require the sha to come from this session, after the add, and touch paths outside `docs/`, or refuse doc-level `driven` over a ranked row ≥ 90. Scope `fired` to this cwd's custody file. Without this, the FP burden buys little.
6. **Quote handling.** Skip indented code blocks. An unparseable column-0 doc line should be treated as no declaration, not OPEN. A documentation table, one whose Drive-state column holds `<placeholder>` tokens, should be ignored.

Conviction that C6 as written clears 90 on the FP lens: **about 10%**. My conviction in the
below-90 verdict: **about 90%** [E: the precision and FP share are measured on 20 sessions; the TP
and FP labels are my reading of each close and doc, and 12 of the 20 rest on transcripts rather
than IDL rows].
