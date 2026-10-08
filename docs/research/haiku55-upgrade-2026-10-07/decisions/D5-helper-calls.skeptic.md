# D5 skeptic review: helper calls on Haiku 5.5, pin back or leave

Reviewed 2026-10-08. No model calls were made. Everything below was recomputed with python3 from
`/tmp/haiku55-decisions/D5-helper-calls.rows.jsonl` (18 rows) and from the 18 session transcripts
under `~/.claude-quaternary/projects/-private-tmp-haiku55-decisions-D5-w-*` (read only).

## Verdict

**The recommendation survives: leave the helper on the alias, do not set `ANTHROPIC_SMALL_FAST_MODEL`.
My conviction is 86%, not the write-up's 88%, and not over 90%.**

The quota numbers all reproduce. One of the three reasons given for the recommendation is wrong:
the write-up says pinning "does not make sessions measurably faster". The worker's own transcripts
show the WebFetch call is about 1.1 to 1.25 seconds slower on Haiku 5.5 in 8 of 8 pairs. That does
not flip the decision (the fleet is billed in quota, not seconds) but it should be stated as a real
cost of leaving, not as a null.

## Recomputed numbers

| Claim in the write-up | Write-up | Recomputed (python3 over the rows) | Match |
|---|---|---|---|
| Sessions kept, served ids as requested | 16 of 16, 0 dropped | 16 of 16; every row has exactly 2 model ids; A = haiku-5-5 + opus-5-5, B = haiku-4-5-20251001 + opus-5-5 | yes |
| Helper output tokens, arm A (n=8) | 345.9 (360, 238 to 439) | 345.9 (360, 238 to 439) | yes |
| Helper output tokens, arm B (n=8) | 38.1 (38, 38 to 39) | 38.1 (38, 38 to 39) | yes |
| Helper thinking tokens, A / B | 307.4 / 0 | 307.4 / 0 | yes |
| Helper input tokens, A / B | 274 / 203 | 274 / 203 on every row | yes |
| Helper cache tokens | 0 / 0 | 0 / 0 | yes |
| Opus output, A / B | 205.0 / 204.6 | 205.0 / 204.6 | yes |
| Opus cache write and read, A / B | 3,650 and 14,025 / 3,662 and 14,024 | same | yes |
| Helper share of raw output tokens | 62.3% / 15.7% | 62.3% (53.6 to 68.2) / 15.7% (15.6 to 16.0) | yes |
| Helper in Opus-output equivalents at 0.12 | 41.5 (19.0 to 65.7) | 41.5 (19.0 to 65.7) | yes |
| Helper share, output-only draw | 16.8% (8.5 to 24.1) | 16.8% (8.5 to 24.1) | yes |
| Helper share, whole session, estimated | 2.6% (1.2 to 4.0) | 2.25% (1.04 to 3.51) counting helper output only; 2.6% if helper input is scaled the same way | yes, same method |
| Wall time median (mean), A / B | 9.43 (9.73) / 9.15 (11.14) | same | yes |
| API duration median, A / B | 5.12 / 4.67 | same | yes |
| Sign test, helper tokens | 8 of 8, p = 0.008 | 8 of 8, p = 0.0078 | yes |
| Sign test, wall and API time | 5 of 8, p = 0.73 | 5 of 8, p = 0.727 (both) | yes |
| Helper list dollars, A / B | $0.000200 / $0.000394 | $0.000200 / $0.000394 | yes |
| Per-call draw | about 0.0004 5h-pp | 41.5 x 9.35e-6 = 0.000388 | arithmetic yes; the 9.35 input is not in the decision folder (grep) and was not verified |
| Correct answers | 8 of 8 both arms | 8 of 8 both arms by exact string match to truth.json | yes |
| Title or summary records | 0 of 18 transcripts | 0 of 18; record types present are queue-operation, user, attachment, atis-latch, assistant, last-prompt, cost-state | yes |

## The checks asked for

**Was ground truth fixed by a program before the models ran?** Yes. `truth.json` and `key.txt` were
written at 23:57:03 (measured, `stat`); the first session that reached a model started at 23:57:32.
I re-ran the regex over the saved `example.html` and got `documentation`. There are 19 work
directories for 18 rows; the extra one (23:57:03, 1-byte output, no transcript directory) is the
aborted launch the write-up describes under deviations. More to the point, the headline measure is
token counts from the API usage block, which involves no judgment at all.

**Were the arms identical?** As far as the saved files can show, yes. The script differs only in the
environment variable. The loop that launched the pairs was not saved, so the extra flags per arm
cannot be read directly; I inferred equality from the outcomes: the WebFetch input is byte-identical
on 16 of 16 transcripts, 0 permission denials, 3 turns on every row, helper input constant within
each arm, and Opus-side tokens within 0.3% between arms. The pairs really did run together: first
transcript timestamps within a pair differ by -0.33 to +1.07 seconds (measured).

**Served model on every row, substitutions dropped?** Yes, 16 of 16 as requested, nothing to drop.
The pin works on binary 2.1.293: 8 of 8 arm-B rows show `claude-haiku-4-5-20251001`.

**Is n large enough?** For the token gap, yes. The arms do not overlap at all (lowest A is 238,
highest B is 39), so the exact sign test gives p = 0.0078 and an exact rank-sum test gives
p = 0.00016, and the result does not depend on how rows are paired. For session wall time, no:
the paired difference has a standard deviation of 4.58 s, and seeing a 1.1 s shift at 80% power
would take about 136 pairs (estimated, normal approximation).

**Ceiling or floor effects?** Two.
- Correctness is at the ceiling (8 of 8 both arms on a one-word question), so it says nothing about
  summary quality.
- The page is 577 bytes, the smallest WebFetch there is. Helper input is at its floor (274 or 203
  tokens). The 42-equivalents figure is the cost of summarizing a tiny page, not a typical page.

**Does the recommendation follow from the numbers or from the worker's prior?** The cost leg follows
from the numbers. The speed leg is contradicted by the worker's own data (next section). The
prompt-injection leg is not a measurement at all; it comes from a vendor document and I could not
check it here.

**Is there a cheaper explanation?** Yes, for the wall-time null. The three slow arm-B sessions were
slow on the Opus turns, not on the helper. In B6 the WebFetch call took 1.04 s while the two Opus
turns took 5.69 s and 9.24 s; in B8 the WebFetch took 1.05 s and the Opus turns 3.99 s and 7.02 s
(measured from transcript timestamps). Retries are not the cause: API time with and without retries
differs by at most 190 ms on all 16 rows (measured, `cost-state` records). Both arms use the same
main model, so this is noise unrelated to the arm, and it hid a clean helper-side effect.

## What the write-up got wrong or missed

1. **The helper call is measurably slower on Haiku 5.5.** Each transcript records the WebFetch
   tool's own duration (fetch plus summary). Arm A: median 2,332 ms (1,798 to 2,629). Arm B: median
   1,079 ms (965 to 2,135). Paired difference: A slower in 8 of 8, median +1,250 ms, mean
   +1,074 ms, sign test p = 0.0078, exact rank-sum p = 0.0006 (n = 8 pairs, measured). With the
   WebFetch time taken out, the rest of the session is the same in both arms (median 3,623 ms A,
   3,857 ms B). So pinning does make each WebFetch call roughly one second faster. The write-up
   should say "about 1.1 s slower per WebFetch call, which we accept", not "not measurably faster".

2. **"Pinning saves at most 42 equivalents" holds only for this page.** The same request counted
   274 input tokens on Haiku 5.5 and 203 on Haiku 4.5, 1.35 times as many (measured, 16 rows). On a
   long page the helper's input dominates its cost, and no quota weight is known for helper input on
   either model. For long pages the measurement cannot say whether pinning saves or costs quota.

3. **The range on 42 is only the ratio's range.** Adding sampling error on the 8 sessions (95%
   interval on mean helper output 291 to 401 tokens) widens it from 19-66 to about 16-76
   (estimated, t interval times ratio bounds). This changes nothing practical.

4. **The 5% question has a computable break-even the write-up did not give.** At list-price weights
   the Opus side of this session is worth 1,806 Opus-output equivalents (205 output plus 1,601 of
   cache). The helper crosses 5% only if quota weighs Opus cache tokens at less than 0.36 of their
   list-price weight (0.10 to 0.65 across the ratio bounds; estimated from measured tokens). Also,
   this test session is leaner than any real one: `--setting-sources ""` strips project
   instructions, hooks and MCP servers, so a real session's Opus side is larger and the helper's
   share smaller.

5. **Units.** The fleet is billed in weekly quota; the write-up converts to 5-hour points only.

6. **A small instruction-following difference went unreported.** The helper was asked to quote the
   sentence. Haiku 4.5 returned the full sentence in 8 of 8; Haiku 5.5 in 6 of 8 (two returned a
   partial quote). Not distinguished at this n (exact test p = 0.47), and the final answer was right
   every time. It is a note, not a finding.

7. **The dollar and scaling figures rest on the binary's built-in price table**, which works out to
   $0.10 in and $0.50 out per million for Haiku 5.5, $1 and $5 for Haiku 4.5, and $20 out, $8 cache
   write, $0.20 cache read for Opus 5.5 (fitted from `costUSD`, zero residual). I did not verify
   those against a published list. The whole-session estimate does not depend on the Haiku 5.5
   price; "the pinned helper is dearer in list dollars" does.

## What the measurement cannot support

- **Three of the four helper kinds named in the decision were never exercised.** No title, summary
  or prompt-suggestion call fired in headless mode. This reviewer session's environment has
  `CLAUDE_CODE_ENABLE_AWAY_SUMMARY=true` and `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true`
  (measured, `printenv`), so those helpers are switched on in the fleet and their count per session
  is unknown. The write-up's "about 300 thinking tokens each" for them is a guess.
- **Other users of the small model.** Bash was offered but never called, so nothing here says
  whether other features also call the helper, or how often.
- **Long pages**, both thinking size and input cost.
- **The saving from pinning in quota.** The Haiku 4.5 ratio is unknown, so there is no number, and
  for input-heavy calls not even a sign.
- **Whether the helper is over 5% of a short session's draw.** It depends on the quota weight of
  cache tokens, which was not measured.
- **Summary quality and injection resistance.**
- **Session-level wall time.** Eight pairs cannot resolve it; the per-call tool duration can and did.

## Why the recommendation still stands

The bound is strong. At the given ratio and the write-up's 9.35 figure, one helper call's thinking
is about 0.0004 of a 5-hour point, so it takes about 2,600 such calls to draw one point (estimated,
product of the measured 345.9 tokens and two inputs I could not verify). Even if the unmeasured
helpers fire dozens of times per session and think several times as much, the draw stays far below
anything worth an environment variable that pins a dated model id. Nothing in the data shows a
material gain from pinning. The one real gain is about a second per WebFetch call.

I stop at 86% rather than 90% because the measurement covers one helper kind on one tiny page, the
speed claim was misreported in the direction that favored the conclusion, and the quality and
injection arguments are unmeasured.
