# C4 (conditional-permission offer lexicon), efficacy judge: refuted

Round 2, 2026-10-18. I judged `C4-offer-lexicon.md` through one lens, efficacy, which asks three things:

1. Would C4 have changed the incident outcome, meaning the waves get driven or the close leads with what remains?
2. Is gaming cheaper than driving as a way to comply?
3. Does it fire at a Stop that actually runs, given the timeouts, the cap and the gates?

I worked read-only in the repo. Scratch went to `/tmp/r2-C4-judge-eff/`: a copy of the designer's harness with its
sandbox moved there, plus `afterfire.py` and `capsim.py`. The hook copies and stubs I ran are the designer's, under
`/tmp/r2-C4/`. `base/hooks/anti-deference-nudge.sh` is byte-identical to the repo's (measured: `diff -q`). Every
hook run had `HOME`, `CLAUDE_CONFIG_DIR`, `ANTIDEF_STATE_DIR` and `ANTIDEF_IDL` pointed into the sandbox. Each number
below is labelled measured (with its command) or estimated (with its method).

**Verdict: refuted as a fix for this incident. The designer's non-action verdict stands.**

- **Conviction that C4, in any measured form, is effective enough to clear 90%: 2.**
- **C4 is silent on the incident.** It never matches the 14:27 close or the two earlier stops in the same session,
  in either home it could live in (measured). That Stop was one where the hook ran, finished in time and had cap
  room, so the miss comes from the lexicon and nothing else.
- **Gaming costs one sentence.** On a true positive, the cheapest way to comply is to restate the ask as a plain
  recommendation. That is the shape the incident had, and C4 cannot see it.
- **It takes cap room from the arm that works.** Under the shared cap of 3, C4's mostly false fires would have
  displaced 8 of the 24 live `deference` fires in the IDL window (measured simulation).
- **Not run:** I did not run a model against the new block. Behaviour after a block is taken from the live
  `deference` arm as an analog.

## 1. Would C4 have changed the incident outcome? No (measured)

The design report never runs the candidate on the incident itself. I did.

| Stop (corpus id) | Text | `base` | `new` (C4) | D4 home (`d4eval.sh`): gate / offer / D4 |
|---|---|---|---|---|
| s006509, 14:27:57Z, `5759497b…jsonl:652` | "✅ Good to close: yes. Nothing of mine is open. Follow-on: the implementation waves in README §5 haven't started …" | `no-tell` | **`no-tell`** | 1 / **0** / 0 |
| s006497 (rs04, `:124`) | "Yes, but keep it narrow … What I'd do, in order …" | `no-tell` | **`no-tell`** | 1 / 0 / 0 |
| s006498 (rs05, `:176`) | "Yes to both, and they're really one job …" | `no-tell` | **`no-tell`** | 1 / 0 / 0 |

Commands (all measured):

- `bash /tmp/r2-C4-judge-eff/run.sh {base,new} /tmp/r2-C4/msgs incident.list inc`
- `bash /tmp/r2-C4/bin/d4eval.sh /tmp/r2-C4/msgs incident.list`
- `/usr/bin/grep -ciE "$CONDASK"` on the raw, unstripped text gives 0 matching lines in all three. `TELLS` also gives
  0 in all three.
- None of the three is among the designer's 503 class-matching Stops (`grep -c` on `cond_hits.list`).

The incident's defect is a YES verdict with the undriven waves named in a trailing clause. It contains no ask of
any form. The same holds for the two earlier instances: a plain "What I'd do, in order" and a plain "Yes to both".
A lexicon of asks has nothing to match in any of them, so no rewording of the class could fix this.

C4's block text also says nothing about leading the close with what remains. So even where it fires, it does not
address the readability half of the incident.

The successor the designer names in §6.1 (a >90% recommendation handed over as a question) would not fire here
either (estimated, by reading s006509). The only >90% item is "Data-loss bug … I'm 95% sure of it", and it carries
no ask, no "yours" and no ⛔. The only item handed to the operator is the 70% `settings.json` change, which the
rules allow. Do not count §6.1 as an incident fix.

## 2. Does it fire at a Stop that runs? Yes, but that is not what binds it

| Check | Result | How |
|---|---|---|
| Live `anti-deference-nudge` record at the incident Stop | `14:27:47Z abstained no-tell`. The session had **0 fires** before it, so the cap was 0/3. | measured: IDL rows for sid `5759497b`, 12:00–15:00Z, from `idl.jsonl{.20261018T105203Z.gz,}` |
| Hook duration at the incident Stop | **395 ms** against a 5 s timeout | measured: `stop_hook_summary.hookInfos` (`ad_ms` in `/tmp/r2-C4/data/stops.jsonl`). The timeout is `"timeout": 5` in `~/.claude/settings.json` `.hooks.Stop`, read-only. |
| Runs of 5 s or more, all 30-day Stops | 237 of 19,570 timed (1.2%); p50 482 ms, p99 5,056 ms | measured: `python3 -I` over `stops.jsonl` |
| Runs of 5 s or more, C4's 233 new-fire Stops | 4 of 232 timed (1.7%) | measured, same script |
| D4 (`completion-assert`) home | after the ledger read; killed at 5 s on 18.1% of runs | axis 07 §S0, not re-measured |

In the `TELLS` home the timeout is not the binding constraint. At the incident Stop the hook was healthy: it ran,
it finished, and it had cap room. C4 still adds nothing there. That isolates the lexicon as the cause of the
miss. The stale-MSG race (axis 07 §S4.2) is real but does not matter for the incident, because the final text was
read and is simply not an ask.

**The shared cap is a measured cost to the existing arm.** `capsim.py` merges the live IDL fires (372 in
2026-09-28 → 10-19, all kinds) with C4's new-fire Stops in the same window (182 of the 233, in 90 sessions). It
sorts them by timestamp and applies the shared cap of 3 per session (verified at `anti-deference-nudge.sh:41-43`
and `:596`). Result:

- C4 keeps 131 fires, and 51 of its own are capped.
- **34 live fires are displaced: 23 `opaque-identifier`, 8 `deference`, 1 `false-done`, 1 `pane-step-handback`,
  1 `category-not-idea`.**

Measured: `python3 -I /tmp/r2-C4-judge-eff/capsim.py`. The model is counterfactual, because it assumes later
traffic in the session stays the same. With C4's precision at 6.7%, it would mostly spend the session's three
blocks on legitimate asks. It would also take a third of the blocks from the one offer arm that, as §3 shows,
mostly produces action.

## 3. Is gaming cheaper than driving? Yes

**How a lexical offer block is answered today (the analog).** I scanned 30 days of main-session transcripts (2,561
files) for live `deference` blocks whose trigger is an offer tell ("say the word", "want me to", "say go",
"shall i", "on your word", "awaiting/holding for your"). I found 37 distinct blocked messages. What followed each,
up to the next operator message or the next block:

| Response | n |
|---|---|
| tool calls, then a new close | 26 |
| text-only re-close, which explains the gate | 4 |
| no assistant text before the next operator message or the end of the file | 7 |

Measured: `python3 -I /tmp/r2-C4-judge-eff/afterfire.py`, then grouping on `offer_blocks.json`.

So when an offer arm fires on a real deferral, agents usually act. That speaks for the mechanism. It does not
speak for C4, because C4 rarely fires on a real deferral:

- **True-positive yield (estimated):** 233 distinct fires × 4/60 gives about 16 a month (6–37 from the Wilson
  interval). At the analog's 26/37 act rate, about 11 a month would get driven.
- **Cost of that yield:** about 217 blocks on legitimate asks, 86 class-B packets (measured by the designer), and
  the cap displacement in §2.

**The cheapest compliance on a true positive is a re-word, and it lands in the incident's shape.**

- Each new message gets a new hash. The latch and the class judge only the text. The block itself says "name that
  gate in plain words instead of asking for a yes".
- So "If you say yes, I'll send it both changes" becomes "Sending both changes adds scope; that's your call", or
  "I recommend sending both changes as added scope, at 95%." Either one sentence stops cleanly. Measured with
  `bash /tmp/r2-C4-judge-eff/run.sh new gm g.list game`: the original gives `fired conditional-ask`, and both
  rewrites give `abstained no-tell`. Each rewrite also has 0 `CONDASK` and 0 `TELLS` matches under
  `/usr/bin/grep -ciE`.
- The second rewrite is exactly the rs04/rs14 shape: a recommendation, no ask, then a stop. That is the defect
  population C4 is blind to. One sentence is cheaper than driving the item, and the cheap path moves the defect
  out of the detector's view rather than fixing it.

**On a false positive, the "comply" path does harm.** For 52 of 60 sampled fires the ask was legitimate. Some of the
fires show what complying would cost:

- At the axis 07 counter-example (`58d3640a…:3380`, which the designer measured as firing), "above 90%, do it now"
  means building the page the operator did not choose.
- The other route the block allows, "file it as `cc-decide open --class C`", turns a page-order preference into a
  heavy filing.
- The third answer seen in the analog, a text-only re-close that restates the gate (4 of 37), is the best case on
  a false positive. Even that costs a block and a round trip, and it changes nothing.

## 4. Spot-check of the designer's numbers

All measured:

- `labels60.tsv` counts TP 4, BORDER 4, FP 52. `newfires_distinct.list` has 233 lines. `corp-new.tsv` has 248
  blocking `conditional-ask` rows.
- Both bats taps read `1..61`, with 5 `not ok` for base and 6 for new. The extra one is `not ok 11 silent: 'should i
  download' does not match 'should i do'`.
- The live fire counts reproduce: `deference` 24 and `opaque-identifier` 302 (one more than the report's 301,
  because a fire has landed since).

**Second reader on the labels.** I re-read 10 random FP labels (seed 777): s006096, s009012, s019481, s007903,
s011403, s006908, s007515, s011218, s001740 and s019362. I agree with all 10. They are a credential set-up, a
default-page pick the operator had objected to, a blind rank, a voice pick, a sign-in, waiting on a call, a publish
call, a filed ⛔ at 85%, a signature, and a permission-settings change (estimated, by hand-reading).

I also read all 8 TP and BORDER labels and found nothing to move. So the precision finding does not depend on one
reader.

## 5. What the report should change

These do not change the verdict.

1. **Lead with the incident result.** C4 never matches s006509, s006497 or s006498, in either home, and the live
   hook at 14:27:47Z was uncapped and ran in 395 ms. That is the strongest efficacy evidence against C4, and it is
   absent from §1.
2. **Count the shared-cap cost.** Its fires would displace 34 live fires, 8 of them from the 24 `deference` fires,
   in the IDL window. Today the report counts only C4's own capping.
3. **Say plainly that the §6.1 successor (the >90% item-level parser) would not fire on the incident** (the 95% item
   has no ask). The 50% estimate should not be read as a path to fixing the 2026-10-18 shape.
4. **Name the gaming path.** The block text's own instruction ("name that gate in plain words") lets an agent escape
   with a one-sentence relabel into a plain recommendation. That is the population the class cannot see.
5. **Separate the two homes on timing.** The `TELLS` home runs within its timeout on 98.8% of Stops. The 5 s kill
   argument applies only to the D4 home.
