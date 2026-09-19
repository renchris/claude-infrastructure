# `/accounts` weekly 100% is three states, not one — 2026-09-19

**Answer.** `/api/oauth/usage` reports each window as an **integer `percent` that rounds UP and
clamps at 100**, so `weekly 100%` is the single rendering of three different worlds: *99% used and
the server says allowed* · *exactly full* · *102% used and the server says rejected*. The
`anthropic-ratelimit-unified-*` response headers carry the **unclamped fraction and the server's
own verdict**, and they disagree with the meter at exactly the moment the meter is load-bearing.
Measured live, all four accounts in one sweep — `next` read `percent: 100` from the endpoint while
the wire read `7d-utilization: 0.99  7d-status: allowed_warning` and a real request returned
**HTTP 200**. `claude-accounts --rank general` was excluding it as `weekly-exhausted` at that
instant. So the answer to *"should we surface whether we are 100% exhausted"* is **yes, and it is
not a display nicety: the tool was asserting an exhaustion it has no instrument for, and refusing a
working account on it.**

## 1. The measurement

One minimal `/v1/messages` call per account (`max_tokens: 1`), headers kept, body discarded:

| account | endpoint `percent` (5h / 7d) | wire `5h-utilization` / status | wire `7d-utilization` / status | HTTP |
|---|---|---|---|---|
| next  | 12 / **100** | 0.12 `allowed` | **0.99 `allowed_warning`** | **200** |
| next4 | **100** / 92 | **1.02 `rejected`** | 0.91 `allowed_warning` | 429 |
| next3 | 74 / 28 | 0.82 `allowed` | 0.30 `allowed` | 200 |
| next2 | 21 / 5 | 0.21 `allowed` | 0.05 `allowed` | 200 |

Two independent defects in one table:

- **`next`** — the endpoint rounds 0.99 **up** to 100. ~1pp of weekly remained and the server said
  so in as many words. Routing refused it.
- **`next4`** — the endpoint **clamps** 1.02 down to 100. The 5h window was in genuine overage;
  `percent` cannot represent that, so "at the wall" and "past the wall" are the same cell.

`next3` also shows the wire is **fresher** (74→0.82, 28→0.30 in the same minute).

The endpoint's parallel `five_hour.utilization` / `seven_day.utilization` floats are **not** a
finer source: every one of them is exactly `X.0`, and over the 30,926-row recorded series all
92,381 percent samples are integers. The quantisation is server-side on that endpoint.

**The binary says both things itself**, in its bundled SDK doc for the per-window usage field:
*"events are emitted when a window's **rounded** percentage or reset time moves"* and *"values
above 1 occur when usage legitimately **runs past a window's cap**, e.g. lower-priority episodes
past the 5-hour limit."*

## 2. What the collapse costs

- **1pp of a weekly window is ~5.2% of a whole 5-hour window** at the fitted exchange rate
  (`K_FROZEN = 0.192` weekly pp per session pp) — roughly one research subagent. It is worth the
  most at exactly the moment every meter reads 100 and there is nothing else to route to.
- **An account sits pinned at `100` for a mean ~21 h before its weekly reset** (17 observed
  closed windows in the series; max **56.5 h**, `next`, window ending 2026-09-13), hard-excluded
  from every lane for that entire time.
- The series already contained the tell and nobody could read it: across **1,251** adjacent sample
  pairs with weekly at 100, the 5h meter **still rose in 12 of them**, on 3 of 4 accounts, in 6
  distinct windows — *up to 8.2 h after the weekly meter first read 100* (`next2`, 2026-08-29) and
  for three consecutive intervals in one episode (`next2`, 2026-09-12, 5h 2→4→5→6). Real work was
  being served past a meter that said the week was over.

## 3. Where the wire is, and what it costs to read

The headers ride **only** on `/v1/messages` responses. Measured: `/api/oauth/usage` carries none,
and `/v1/messages/count_tokens` carries none either (it returns 200 with an OAuth token and a
header set containing no `anthropic-ratelimit-*` at all). So there is no free read — the price is
one `max_tokens: 1` call, ~25 quota-bearing tokens against a weekly pp worth ~500k, i.e. ~4e-6 pp.

That is small but not zero, and it is the first inference `claude-accounts` has ever made, so it is
**gated to the band where the integer is ambiguous** (`WIRE_NEAR_WALL = 99`), forced by `--wire`,
and removed by `CC_ACCOUNTS_WIRE=off`. Away from the wall it never fires; a live un-forced sweep
probed 2 of 4 accounts.

Fields captured beyond the two utilizations, because each can make a `rejected` window still serve:
`*-status` ∈ {`allowed`, `allowed_warning`, `rejected`} · `representative-claim` (which window is
binding) · `fallback` (`available` = the binary's lower-priority lane) · `overage-status`.

## 4. What changed

- `fetch_wire_limits()` — one gated call; **a 429 is a successful read** (the rejection carries the
  same headers and is the case most worth knowing). Only a transport failure or an absent header
  set is a miss.
- The router consumes the wire through `weekly_headroom()` / `wire_rejects()`. The direction is
  one-way by construction: the wire may **add precision or add a refusal**, never soften one.
  `wire_rejects` is `False` whenever the wire is absent, so a miss degrades to exactly the
  endpoint-only verdict — *a read that could not happen is not a permissive answer*.
- The `ʷ` suffix in the readout marks a cell that came off the wire; a bare `100%` now means "this
  is a rounded ceiling we did not verify", which is the honest reading and was never available
  before.
- The one-line bullet splits three ways: `○ EXHAUSTED — the server is refusing it` ·
  `◐ meter reads 100% but the wire reads 99%, allowed — ~1pp left; still routable` ·
  `○ meter at 100% — rounded and clamped ... unverified`.
- **The recorded series keeps `weekly_pct` endpoint-sourced and adds `wire_*` beside it.** This is
  not fastidiousness: `_rolled()` treats any meter decrease as a window reset, so writing a wire 99
  where the previous row holds an endpoint 100 would fabricate a roll and corrupt every burn fit
  downstream. Tested (W-8).

## 5. What is NOT settled

- **The wire's own resolution is also ~1pp** (0.99, 1.02, 0.30 — two decimals on a fraction). It
  separates "99, allowed" from "100+, rejected", which is the decision, but it is not a finer
  meter. Nobody should read `0.99` as "exactly 1.00pp remain".
- **Why work is served past a weekly 100 is not fully discriminated.** Two live candidates: the
  displayed value is a *ceil* of something under 1.0 (supported here — `next` read 0.99), or the
  binary's **lower-priority / fallback lane** serves past the wall (the header
  `...-fallback: available` exists and was seen on `next3`). Both point the same way for routing,
  so the change does not rest on picking one — but a claim about *which* would need a session
  driven past its own weekly wall and watched.
- **The cost gate is keyed on the meter it exists to distrust.** `wire_wanted()` fires only at/above
  `WIRE_NEAR_WALL`, read off the ENDPOINT integer — and that integer lags (next3 read 28 against a
  wire 0.30 in the same minute). So a fast burn can cross the wall between sweeps while the integer
  still looks comfortable, and the probe will not fire. This is the price of keeping the call free
  in the common case; `--wire` is the escape, and a sweep during a known burst should use it. Pinned
  by test W-2, which can only reach a `rejected` verdict by forcing.
- **`locked_reason` was `None` on all four accounts**, including the one at 100. Its meaning is
  therefore unmeasured; it is not used.

## 6. Re-derive

```bash
claude-accounts --readout --wire --fresh      # forced: every account reads the wire
claude-accounts --readout --fresh             # gated: only rows at/above WIRE_NEAR_WALL
```
