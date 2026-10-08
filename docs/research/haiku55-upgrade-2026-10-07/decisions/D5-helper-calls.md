# D5: helper calls on Haiku 5.5, pin back or leave (measured 2026-10-07/08, binary 2.1.293)

## Recommendation

**Leave the helper on the alias (Haiku 5.5). Do not set `ANTHROPIC_SMALL_FAST_MODEL`.** Conviction 88%.

The always-on thinking is real and measurable: one WebFetch page summary costs about 346 helper
output tokens on Haiku 5.5 against 38 on Haiku 4.5 (9 times as many, 8 of 8 pairs). But in plan
quota that is about 42 Opus-output-token equivalents per WebFetch call (19 to 66), roughly 0.0004
of a 5-hour percentage point. Pinning would save at most that per call, would not make sessions
measurably faster, and would put the model that reads untrusted web pages back on the one the
System Card scores far worse on prompt injection.

Is it material (more than about 5% of a short session's draw)? **By output tokens alone, yes: 17%
(8.5% to 24%). By the whole session's draw, probably not: about 2.6% (1.2% to 4.0%).** The two
differ because this short session's Opus side is mostly cache writes and reads (3,650 and 14,025
tokens against 205 output tokens), and the quota weight of those was never measured apart from
output. Either way the absolute amount is tiny, and it scales with the number of WebFetch calls,
not with session length.

## Result table

All numbers measured from each session's `modelUsage` (script `/tmp/haiku55-decisions/D5/cell.sh`,
statistics by the Python block recorded in the method), n = 8 sessions per arm, 0 dropped, served
models as requested in 16 of 16. Main model claude-opus-5-5 at low in both arms.

| | Arm A: default (helper = claude-haiku-5-5) | Arm B: `ANTHROPIC_SMALL_FAST_MODEL=claude-haiku-4-5-20251001` |
|---|---|---|
| Sessions kept / run | 8 / 8 | 8 / 8 |
| Answer correct against the planted key and regex truth | 8 / 8 | 8 / 8 |
| Helper output tokens per session: mean (median, min to max) | 345.9 (360, 238 to 439) | 38.1 (38, 38 to 39) |
| of which thinking tokens, mean | 307.4 | 0 |
| Helper input tokens per session | 274 | 203 |
| Helper cache read + cache write tokens | 0 | 0 |
| Main (Opus) output tokens per session, mean | 205.0 | 204.6 |
| Main (Opus) cache write / cache read tokens, mean | 3,650 / 14,025 | 3,662 / 14,024 |
| Helper share of the session's raw output tokens, mean (min to max) | 62.3% (53.6% to 68.2%) | 15.7% (15.6% to 16.0%) |
| Helper output in Opus-output-token equivalents (0.12, bounds 0.055 to 0.19) | 41.5 (19.0 to 65.7) | not convertible: Haiku 4.5 ratio unknown |
| Helper share of output-only draw (helper equivalents / (helper equivalents + Opus output)) | 16.8% (8.5% to 24.1%) | unknown |
| Helper share of whole-session draw, ESTIMATED (list-dollar share 0.55% scaled by 4.8x, bounds 2.2x to 7.6x) | 2.6% (1.2% to 4.0%) | unknown (list-dollar share 1.08%) |
| Wall time per session, seconds: median (mean, min to max) | 9.43 (9.73, 8.46 to 12.68) | 9.15 (11.14, 8.01 to 19.08) |
| API duration reported by the binary, median seconds | 5.12 | 4.67 |

Sign tests over the 8 A/B pairs (each pair ran at the same moment):

- Helper output tokens, A greater than B: 8 of 8, two-sided p = 0.008. **Distinguished.**
- Wall time, A greater than B: 5 of 8, p = 0.73. **Not distinguished.** A was slower by 0.7 to
  3.3 s in the first five pairs, B was slower by 2 to 11 s in the last three (B's outliers).
- API duration: 5 of 8, p = 0.73. **Not distinguished.**
- Correctness: 8 of 8 in both arms, so no difference to test.

Other measured facts:

- **No session title was generated in headless `-p`**, with session persistence on: 0 of 18
  transcripts under `~/.claude-quaternary/projects/` contain a title or summary record, and the one
  session where WebFetch was denied (pilot1) shows no helper model in `modelUsage` at all. The only
  helper call these sessions make is the WebFetch page summary. So the number above is the cost
  **per WebFetch call**, and the title, summary and prompt-suggestion helpers were not measured.
- In list dollars the pinned helper is the dearer one: $0.000394 per session on Haiku 4.5 against
  $0.000200 on Haiku 5.5 (the binary's `costUSD`, n = 8 each). List dollars are not our currency,
  but it shows the 9x token gap does not mean a 9x cost gap.
- Estimated absolute draw: 41.5 Opus-output equivalents at the record's 9.35 5h-pp per million Opus
  output tokens is about 0.0004 5h-pp per WebFetch call; 1,000 WebFetch calls would be about 0.4
  5h-pp (estimate, product of two measured figures).

## Method (five lines)

1. Truth fixed before any model ran: a random key planted in `key.txt` (`secrets.token_hex`) and the word matched by the regex `use in (\w+) examples` over a `curl` of https://example.com (`documentation`); stored in `/tmp/haiku55-decisions/D5/truth.json`.
2. One session = 2.1.293 binary, `-p "<prompt>" --model claude-opus-5-5 --effort low --output-format json --setting-sources "" --tools "Read,Bash,WebFetch" --allowedTools "WebFetch(domain:example.com)"`, session persistence on, account `~/.claude-quaternary`, fresh mktemp directory per session; the prompt asks for exactly one Read of `key.txt` and one WebFetch of example.com with a question, then a two-line answer.
3. Arm A is that command as is; arm B adds `ANTHROPIC_SMALL_FAST_MODEL=claude-haiku-4-5-20251001`; 8 sessions per arm, run as 8 simultaneous A/B pairs (2 in parallel) so drift hits both arms alike.
4. Per session the script (adapted from `measure/extraction/cell.sh`) records the full `modelUsage`, served model ids, wall time around the process, the binary's own durations, permission denials and the answer; a session is kept only if the main and helper ids are the ones requested.
5. Quota conversion uses the record's 0.12 (0.055 to 0.19) for Haiku 5.5 output tokens only; Haiku 4.5 is reported in tokens; differences are tested with a two-sided sign test over the 8 pairs.

Total model use: 18 sessions (2 pilots + 16), each with 3 main-model turns and at most one helper
call; well under the 150-call limit.

## Raw rows

`/tmp/haiku55-decisions/D5-helper-calls.rows.jsonl` (18 rows: pilot1, pilot2, A1 to A8, B1 to B8).
Script, truth and per-session raw JSON: `/tmp/haiku55-decisions/D5/`.

## Deviations from the brief

- `--allowedTools "WebFetch(domain:example.com)"` was added to the child command. Without it
  WebFetch is denied in headless mode (pilot1, kept in the rows) and no helper call happens. It is a
  flag on the test process for the one named domain; no settings or permission file was touched.
- The prompt was placed directly after `-p`; placed last, `--tools` swallows it and the binary exits
  without calling a model.
- Session identity variables inherited from the calling session (messaging socket and token, bridge
  and session ids, task list id, child-session flags) were unset for the child so it could not reach
  another session; fleet feature toggles were left as inherited.
- Because the brief requires session persistence, the 18 sessions wrote transcripts under
  `~/.claude-quaternary/projects/-private-tmp-haiku55-decisions-D5-w-*`. Nothing was deleted (the
  delete guard refuses it in a worker); remove them if unwanted.

## What remains unsettled

- **Title, summary, away-summary and prompt-suggestion helpers.** They do not fire in headless `-p`,
  so their per-session cost in an interactive pane is unmeasured. Each should carry a similar
  thinking overhead (about 300 tokens per call seen here), but how many such calls an interactive
  session makes is not known from this run.
- **Whether the helper is over 5% of a short session's draw.** It is 17% of output-only draw and an
  estimated 2.6% of whole-session draw; settling it needs the quota weight of Opus cache writes and
  reads, which the record measured only bundled with output at a 0.4 ratio (here the ratio is 18).
- **The plan-quota ratio of a Haiku 4.5 output token.** Unknown, so the saving from pinning cannot
  be stated in quota, only bounded above by arm A's whole helper cost.
- **Wall time.** n = 8 pairs cannot distinguish the arms; a 1 s difference in either direction is
  compatible with the data.
- **Longer pages.** example.com is 577 bytes. Thinking on a long page summary may be larger than 300
  tokens; one page size was measured.
- **Summary quality and injection resistance** were not measured here beyond one trivially easy
  question (8 of 8 both arms); the injection argument for Haiku 5.5 rests on the vendor card.
