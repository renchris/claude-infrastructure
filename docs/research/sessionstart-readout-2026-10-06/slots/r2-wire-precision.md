# R2: wire utilization precision. Rounded or truncated, and how many decimals?

**Verdict.** The server sends `anthropic-ratelimit-unified-{5h,7d}-utilization` on a **0.01 grid**. None of the 6,793 recorded readings has a third decimal. The value is **rounded to the nearest hundredth, not truncated**. While a window is not refused, the value is **capped at 0.99**. A refused window carries the uncapped rounded value, for example 1.0 or 1.01.
- Conviction that the grid is 2 dp: ~97%.
- Conviction for round-plus-cap over floor: ~80%.

**Consequence.** A reading of `0.99 allowed_warning` means the true use is in **[98.5%, 100%)**, so the headroom is **(0, 1.5 pp]**. When the endpoint also reads 100, the true use is in **(99%, 100%)**, so the headroom is **(0, 1 pp)**. In every hypothesis the lower bound is **0**. The board's "99.0%" and "about 1% of the week left" therefore state the *maximum* as if it were the value.

Inputs: `~/.claude/logs/account-utilization.jsonl` has 44,586 rows, 2,068 of them with wire fields, from 2026-09-19T19:50Z to 2026-10-06T06:13Z. It has no rotated siblings (`ls ~/.claude/logs`). `~/.claude/logs/claude-accounts.log` has 4,725 `probe …: wire —` lines from 2026-09-19T19:45Z to 2026-10-06T06:17Z, each with the endpoint integer beside it. The scripts are in `/tmp/ssr-research/r2_*.py`.

---

## 1. Decimal places (measured)

The jsonl is from `r2_an.py`, which regex-reads the literal JSON token. The log is from `r2_log.py`.

| source | field | non-null | 1 dp | 2 dp | ≥3 dp | `0.995` seen |
|---|---|---|---|---|---|---|
| jsonl | wire_5h_util | 2,068 | 1,816 | 252 | **0** | no |
| jsonl | wire_7d_util | 2,068 | 1,894 | 174 | **0** | no |
| log | 5h | 4,725 | 4,161 | 564 | **0** | no |
| log | 7d | 4,725 | 4,327 | 398 | **0** | no |

- The "1 dp" values are values such as `0.0`, `1.0`, `0.1` and `0.8`, which are points on the 0.01 grid. Python's `repr` drops a trailing zero. 40 distinct 5h values and 8 distinct 7d values were seen, all multiples of 0.01.
- **Our code does not round.** `_wire_float` is `float(h[name])` (bin/claude-accounts:1260-1264). `fetch_wire_limits` reads the four headers at :1316-1320. `record_utilization` writes them with `json.dumps` at :5542-5545, and the log line uses an f-string at :2481. Every value on disk is therefore the float of the server's string, and a 3-dp header would have shown up. The live copy is identical: `diff -q bin/claude-accounts ~/.claude/bin/claude-accounts` printed nothing.
- **Claude Code does not round either.** The parser in the bundled binary is `QBe(e){…let n=Number(e);return Number.isFinite(n)?n:void 0}` and `FPr` reads `` `anthropic-ratelimit-unified-${s}-utilization` `` (claude.exe, byte offset ~179249568). Its user-facing text *floors* the value: `IPr(e){let n=e.utilization?Math.floor(e.utilization*100):void 0 …` (~179245329).
- Limit: the float round-trip cannot tell `"0.99"` from `"0.990"`. **No literal header string is on disk.** Grepping `~/.cache`, `~/.claude/{debug,logs}`, `~/.claude-next*/debug` and `/tmp` found the string only in a copied `claude-accounts` source and in this run's own logged commands.

## 2. Value × status near the wall (measured)

| window | value | allowed | allowed_warning | rejected | source |
|---|---|---|---|---|---|
| 7d | 0.74 max allowed | 10 | | | jsonl |
| 7d | 0.91 / 0.93 | | 1 (log) / 2 (jsonl) | | |
| 7d | 0.98 | | 30 (jsonl), 58 (log) | | |
| 7d | **0.99** | | **106** (jsonl), **247** (log) | **0** | |
| 7d | **1.0** | **0** | **0** | **1,888** (jsonl), 4,311 (log) | |
| 5h | 0.83 / 0.84 max allowed | ✓ | | | |
| 5h | 0.96–0.99 | | 3 (jsonl), 6 (log) | | |
| 5h | 1.0 | 0 | 0 | 23 (jsonl), 58 (log) | |
| 5h | 1.01 | | | 16 (jsonl), 35 (log) | |

- **`rejected` is never seen below 1.0, and `1.0` is never seen with `allowed` or `allowed_warning`** (0 of 1,911 jsonl rows and 0 of 4,369 log rows).
- **`allowed_warning` first appears at 0.91–0.93** on 7d: next3 2026-10-01T23:56:03Z read 0.93 with endpoint 94. It first appears at 0.96 on 5h. The highest `allowed` reading is 0.74 on 7d and 0.84 on 5h. The server's threshold is somewhere in 0.75–0.91, and could depend on time as the client's own early-warning thresholds do. We do not record `…-surpassed-threshold`, so the exact threshold is unknown.
- Every 7d approach (13 in the jsonl) runs `0.98 aw → 0.99 aw → 1.0 rejected` and never skips through a 1.0-allowed reading (`r2_an3.py`).

## 3. Rounding or truncation: the discriminating measurements

Notation: **E** is the endpoint integer, **W** is round(wire × 100) from the same probe, and **u** is the true percentage. The endpoint read comes first and the wire read about one second later (bin/claude-accounts:2462-2466). Usage only grows, so time skew could only make W > E.

**3a. E − W (0 < W < 100)** (`r2_an4.py`, `r2_log.py`)
- 5h: {0: 273, 1: 291} in the log; {0: 125, 1: 127} in the jsonl.
- 7d: {0: 81, 1: 317}.
- E is never below W except for the 100-clamped 1.01 rows.

| hypothesis (E, W) | predicts | result |
|---|---|---|
| ceil, floor | E−W = 1 almost always | **rejected**: 273 + 81 zeros |
| round, round / ceil, ceil | E−W = 0 always | **rejected**: 291 + 317 ones, which skew cannot explain |
| **ceil, round(+cap)** | about 50/50 split of 0 and 1 | consistent |
| round, floor | about 50/50 split of 0 and 1 | consistent |

The two surviving hypotheses differ only by a half-unit shift, so 3a alone cannot separate them.

**3b. Band widths, measured in 5h-pp burned during each 7d state** (`r2_ep2.py` over the log; one row per wall approach). Burned 5h-pp is proportional to weekly pp consumed and does not depend on load.

| 7d state → next state | per-episode Δ5h-pp | mean | width predicted by ceil/round+cap | by round/floor |
|---|---|---|---|---|
| W98 E99 → W99 | 4, 2, 1, 1, 1, 2, 3, 2 | **2.0** (n=8) | (98, 98.5): 0.5 pp | [98.5, 99): 0.5 pp |
| W99 E99 → W99 E100 | 0, 1, 2, 2, 2, 2, 2, 2, 1, 2 | **1.6** (n=10) | [98.5, 99]: 0.5 pp | [99, 99.5): 0.5 pp |
| W99 E100 → rejected | 4, 4, 4, 4, 4, 3, 3, 4 | **3.75** (n=8) | (99, 100): **1 pp** | [99.5, 100): **0.5 pp** |

- The ratio (W99E100) / (W99E99) is **2.34**. Ceil/round+cap predicts **2.0** and round/floor predicts **1.0**. Per-episode standard errors are about 0.16 and 0.22, so 1.0 is more than 5 se away. This result is measured; the hypothesis fit is reasoned.
- The whole W=99 band adds up to 5.35 5h-pp, against 2.0 for the half-observed W=98 band. That fits a 1.5 pp band (round+cap: [98.5, 100)) better than a 1 pp band (floor).
- **Corroboration from Anthropic's own emitter of the same header family.** The bundled spend-gateway in claude.exe (~195911256) synthesizes this header: `o=Math.round(e.utilization*100)/100, s=e.exceeded?o:Math.min(o,0.99)` → `"anthropic-ratelimit-unified-overage-utilization":String(s)`, with `ste=[0.95,0.75]` as the allowed_warning thresholds. That is round to 2 dp, **cap at 0.99 unless exceeded**, and uncapped once exceeded. This is the pattern 3b and §2 show for the 5h and 7d windows: no 1.0 while allowed, and 1.01 once rejected.
- The SDK doc string actually reads lowercase "events are emitted when a window's **rounded** percentage or reset time moves" and "values above 1 occur when usage legitimately runs past a window's cap" (claude.exe ~173845547). It describes when the client emits events, not how precise the header is. The repo's paraphrase at bin/claude-accounts:1227-1228 capitalizes it and reads more into it than it says.

**Alternatives considered and their status**
- Floor (truncation) on the server: disfavoured by 3b at a ratio of 2.34 against 1.0. Under floor, a 0.99 reading would mean u in [99, 100).
- Round, with refusal at a rounded 1.00 (u ≥ 99.5): this predicts a W99E100 band of 0.5 pp, a ratio of 1. Disfavoured.
- Round with no cap: this predicts 1.0-`allowed_warning` rows for u in [99.5, 100). None appear in 6,280 rows at 1.0. **Rejected.**

**Unexplained (low weight).** No 5h `(W=0, E=1)` pair was ever seen, while both surviving hypotheses predict a short 0.5 pp window for it at the start of a 5h window. Only about 4 window starts were sampled at 1–3 min spacing, and each jumped straight from `(0,0)` to `(1,1)` (next 2026-09-26T18:44:37Z → 18:47:44Z).

## 4. Headroom bound for `0.99 allowed_warning` (reasoned from §3, with measured burn)

| evidence held | true u (round+cap, ~80%) | true u (floor, ~20%) | weekly headroom |
|---|---|---|---|
| wire 0.99 aw alone | [98.5, 100) | [99, 100) | **(0, 1.5 pp]** or (0, 1 pp] |
| wire 0.99 aw **and** endpoint 100 | (99, 100) | [99.5, 100) | **(0, 1 pp)**; mean ≈ 0.5 pp on a uniform prior, or (0, 0.5 pp) under floor |
| measured burn from the first E=100 sample to the first rejected read | | | **3–4 5h-pp** (mean 3.75, n=8, never ≥ 5) and 16–138 min wall-clock |

- `weekly_headroom` (bin/claude-accounts:1358-1369) computes `1.00 − 0.99 = 0.01`, which is the **upper bound**, and compares it to WEEKLY_FLOOR 0.005.
- The note at :6746-6750 prints "about 1% of the week left, roughly 5% of one 5-hour window", using `1/K_FROZEN = 5.2`. The measured remainder from the moment E reaches 100 is **at most about 4% of a 5h window**. Inside this band the local exchange rate is about 0.27 weekly pp per 5h-pp, not 0.192.
- **The incident (reasoned from logged values).** next3 entered W99 E100 at 2026-10-06T03:55:40Z with 5h at 3%. At the 06:01:45Z row the 5h was 0.06 wire and 7 on the endpoint, so 3–4 of the band's ~3.75 5h-pp were already spent. The expected remainder was about 0–0.25 weekly pp. The 06:03:04Z refusal fits this; it was not an anomaly.
- `board_eff` floors to a tenth (bin/claude-accounts:6343). On a 0.01 grid that **always prints ".0"**: no float artifacts occur for k = 0..101 (`r2` inline check). So "99.0%" claims precision the wire does not have. The docstring and the legend examples "99.6%" (:6333, :6353) cannot occur.

## 5. Blockers and deviations

- **No live wire read was made.** `--wire` forces the read on *every* account (bin/claude-accounts:20), which breaks the one-account limit. Its JSON also exposes only the parsed float, already on disk 6,793 times. A literal-string capture would need a hand-built call with an OAuth token, which is outside the documented flag. The predicted result, values on the 0.01 grid, would not change the verdict.
- Two things stay open and could be answered at zero extra cost on the next gated read: the literal header format (`"0.99"` vs `"0.990"`) and the `…-surpassed-threshold` value.
