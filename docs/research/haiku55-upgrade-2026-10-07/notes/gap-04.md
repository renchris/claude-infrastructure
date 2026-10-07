# Gap G4: announcement accuracy-versus-cost charts, Haiku 5.5 below max effort

Source: live fetch of https://www.anthropic.com/claude-haiku-5-5 on 2026-10-07 with `curl -sL` (HTTP 200, 221,135 bytes, sha256 prefix 264938a3a185e9ab; copy at /tmp/h55-ann.html, not in the pack). The page embeds each chart's data as a CSV string (`series,x,y,label,labelPlacement`) inside four `"_type":"chart"` objects in the page's serialized content. All numbers below are read from those CSV strings, not from pixels. Derived ratios are computed by me from those values and labeled as such.

## Answer

The charts carry per-effort points for Haiku 5.5 at all five levels (low, medium, high, xhigh, max).

**Terminal-Bench 4.0** (y = "Score (pass@1, %)", x = "Cost per attempt (USD, log scale)"):

| Effort | Haiku 5.5 score | Haiku 5.5 cost/attempt | Sonnet 5.5 score | Sonnet 5.5 cost/attempt ($0.10 cache reads) |
|---|---|---|---|---|
| Low | 12.7% | $0.424 | 20% | $0.6205 |
| Medium | 20.3% | $0.6798 | 28.8% | $0.6796 |
| High | 24.8% | $1.0372 | 43% | $1.462 |
| Xhigh | 31.5% | $1.7545 | 61.5% | $4.3352 |
| Max | 39.2% | $2.6433 | 70.6% | $10.4421 |

Haiku 4.5: 0.0% at $0.7913 (one point, labeled Max).

Reading for the mechanical code-writing teammate role: at medium effort Haiku 5.5 passes about one in five of these tasks and at high about one in four, roughly half and two thirds of its max score (derived: 20.3/39.2 = 52%, 24.8/39.2 = 63%). On this benchmark Sonnet 5.5 beats or matches Haiku 5.5 on dollars at every Haiku effort from medium up: Sonnet medium (28.8% at $0.68) costs the same as Haiku medium (20.3% at $0.68) and less than Haiku high (24.8% at $1.04); Sonnet high (43% at $1.46) scores above Haiku max (39.2% at $2.64) for less. Only Haiku low ($0.42) is cheaper than every Sonnet point, and it scores 12.7%. The vendor's own text under the chart says the same: Sonnet 5.5 and Opus 5.5 "remain better choices for complex agentic coding tasks", Haiku 5.5 is "best suited to more narrowly scoped tasks ... like compaction, summarization, or subagent work" (pack/announcement.txt:228).

**GDPval-AA v2.1** (y = "Elo, as reported", x = "Cost per task (USD, log scale)"):

| Effort | Haiku 5.5 Elo | Haiku 5.5 cost/task | Sonnet 5.5 Elo | Sonnet 5.5 cost/task | GPT-6 Luna Elo | Luna cost/task |
|---|---|---|---|---|---|---|
| Low | 1125 | $0.01167 | 1179 | $0.2235 | 1036 | $0.0038 |
| Medium | 1277 | $0.03042 | 1324 | $0.2693 | 1262 | $0.02 |
| High | 1420 | $0.08938 | 1551 | $0.618 | 1344 | $0.03 |
| Xhigh | 1513 | $0.26725 | 1731 | $1.8834 | 1364 | $0.05 |
| Max | 1620 | $0.86593 | 1840 | $6.7776 | 1437 | $0.09 |

Haiku 4.5: 735 at $0.24.

Reading: the picture is the opposite of Terminal-Bench. Haiku 5.5 high (1420 at $0.089) outscores Sonnet 5.5 medium (1324 at $0.269) at about a third of the cost (derived: 0.08938/0.2693 = 33%), and Haiku xhigh (1513 at $0.267) outscores Sonnet medium at the same cost. Sonnet only pulls ahead from high effort up (1551 at $0.618). The steepest Haiku gain per dollar is medium to high: +143 Elo for about 3x the cost; high to max adds +200 Elo for about 10x the cost (derived from the table).

## Evidence

- Terminal-Bench chart object: title `"Terminal-Bench 4.0"`, subtitle `"Accuracy vs. cost"`, `chartType` line, data string beginning `haiku55,0.424,12.7,Low,below` and ending `sonnet55old,14.1511,70.6,Max,hidden`; axis labels `"Cost per attempt (USD, log scale)"` and `"Score (pass@1, %)"`. Series names: Haiku 5.5, Haiku 4.5, `Sonnet 5.5 ($0.10 cache reads)`, `Sonnet 5.5 ($0.20 cache reads)`. The old-price Sonnet series has the same scores at $0.7903, $0.8615, $1.9668, $5.8308, $14.1511. This is the chart shown as `[]` at pack/announcement.txt:217-224.
- GDPval chart object: title `"GDPval-AA v2.1"`, data string beginning `haiku55,0.01167,1125,Low,below`; axis labels `"Cost per task (USD, log scale)"` and `"Elo, as reported"`. This is the `[]` at pack/announcement.txt:91-98.
- Cross-check against the card: Terminal-Bench max 39.2%, Sonnet 70.6%, Haiku 4.5 0.0% match pack/pages/p115.txt. GDPval max 1620, medium 1277, Haiku 4.5 735, Sonnet 1840, Luna 1437 match pack/pages/p131.txt. The max and medium points agree exactly, so the chart and card describe the same runs.
- Page count correction: the announcement says "three benchmarks at each effort setting" (pack/announcement.txt:68). There are four charts in total: OSWorld, GDPval-AA and HLE in a tabbed block, plus Terminal-Bench in the pricing section. There is no FrontierCode or AA-Briefcase chart on the page.
- The other two charts, for completeness (same CSV format). OSWorld 2.1 offline subset, Haiku 5.5: low 42.0% at $0.0695, medium 53.3% at $0.1257, high 61.3% at $0.1827, xhigh 67.6% at $0.2792, max 72.4% at $0.6111 (Sonnet 5.5: 57.9/66.0/73.2/81.1/83.9% at $0.68/$0.93/$1.38/$2.22/$5.73). HLE no tools, Haiku 5.5: low 30.9% at $0.00334, medium 35.5% at $0.00693, high 39.7% at $0.02043, xhigh 44.1% at $0.06452, max 45.9% at $0.21367 (Sonnet 5.5: 41.4/43.2/47.9/53.0/56.9%).

## Caveats on using these numbers

- Sonnet 5.5's Terminal-Bench points at low, medium and high are whole or near-whole values (20, 28.8, 43) while Haiku's carry one decimal; nothing on the page explains the difference.
- Costs are API dollars. The fleet's binding cost is weekly plan quota, and the page gives no token counts per effort level, so the dollar ordering between Haiku and Sonnet may not carry over to quota.
- Terminal-Bench 4.0 is 66 hard tasks (science-adjacent and frontier engineering, p115), not mechanical edits. A 20 to 25% pass rate there does not predict the pass rate on narrowly scoped mechanical code writing; it only shows the effort slope and that Sonnet is the better buy on hard terminal work.

## What remains unknown

- NOT STATED: how cost per attempt was computed (list prices, caching assumptions, whether the over-100k-token price tier applied). The page has no methodology footnote for the charts; footnotes 1 and 2 (pack/announcement.txt:234-238) cover speed and the price-cut claim only.
- NOT STATED: trial counts, standard errors, harness and safeguard handling for the below-max Terminal-Bench points. The card gives these for max only (p115: 660 trials, SE ±1.9, Claude Code --bare, no fallback). Whether the lower-effort points used the same setup is an assumption.
- NOT STATED: Opus 5.5 by effort on either chart (Opus is not a series), and GPT-6 Luna on the Terminal-Bench chart (table gives only 16.4%).
- NOT STATED: token usage, turn count or wall time per effort level on Terminal-Bench.
- NOT STATED: any by-effort result on mechanical, narrowly scoped coding tasks. A fleet-side measurement would settle the role question: run a fixed set of our own mechanical teammate tasks with Haiku 5.5 at medium and high and Sonnet 5.5 at medium, and record pass rate and plan-quota consumption per task.
