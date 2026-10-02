# Quota-cache freshness — when is a cached reading wrong, and what should refresh it?

Incident 2026-10-01: the operator redeemed the banked limit reset (`/limit-reset`, `cedar_ember`)
on next4 between 20:14:26Z (a next4 session printed "You've hit your weekly limit") and 20:19:08Z
(the operator wrote "I just used our one banked reset"). The last good read, at 20:14:06Z, said
weekly 100% with a server `rejected` wire verdict. All six polls from 20:16:52Z to 20:21:28Z got
HTTP 429, so every reader replayed 100% plus the stored rejection, and `cc-lr recover --limited`
treated a freshly reset account as capped. The next good read, at 20:24:48Z, said weekly 0%,
session 1%, a new `session_reset_at`, and the same `weekly_reset_at`.

Receipts: `q1_budget.py` → `q1-output.txt`, `q2_drift.py` → `q2-output.txt`. Both are
stdlib-only, read-only, and re-runnable against `~/.claude/logs/`.

## Q1 — the 429 budget

| Question | Answer | Evidence |
|---|---|---|
| Scope | **Per token (per account), not per IP.** | 1,186 of 1,373 throttle clusters (429s within 5 s of each other) hit exactly one account. In the incident, `next` and `next2` succeeded in the same sweeps, within 3–6 s of each next4 429. |
| Do live sessions spend it? | **No measurable effect.** The first, log-only table suggested one (k=0: 1.9% vs k 1–8: 55%), but that was an artifact: successes are logged only near the wall. | On the utilization series, which samples throttled and good rows the same way, the 429 share over the last 14 days was k=0 **5.9%**, k 1–3 1.5%, k 4–8 0.7%, k 9+ 0.6% (§7). Claude Code 2.1.284 does call the same endpoint (`/api/oauth/usage`, `?at_wall=1&skip_spend=1`, `?cedar_ember=1&skip_spend=1`; found at binary offset 183,688,337), but 429s are not concentrated at the wall: 8.2% of 429s versus 8.5% of all good reads (§6). |
| Window | **Sticky, and long.** | After a 429, the same account's next event is another 429 97.6% of the time within 30 s, 82–94% at 30–300 s, 62% at 5–10 min, and 54% at 10–30 min (§2b). Episodes (first 429 until the next success) run p50 **7.3 min**, p75 37 min, p90 **91 min**, p99 7.4 h; n=196 (§8). |
| Who spends it | Our callers: keepwarm every 180 s, SessionStart (cache only), and foreground `--fresh`/`--rank` sweeps. Each 429 also cost **3 requests**, because `fetch_usage` retried twice after a 1.5–4.5 s jitter. | `bin/claude-accounts` `fetch_usage(retries=2)`. Re-polling inside 30 s fails 97.6% of the time, so the retries were spending budget for almost nothing. |
| Polls per account-hour | **Not measurable from the log.** A success is logged only when the wire fires, i.e. near the wall. Where it is logged, the median is 20 probes per account-hour (keepwarm alone accounts for 20). | §4. Limit: foreground sweeps carry no caller tag. |

**Consequence.** No cross-account budget exists to redistribute, so there is nothing to buy by
spending fewer polls on idle accounts and more on busy ones. Two levers are left. (a) Stop
spending a throttled token's budget: no in-call retry on 429, and a shared per-account backoff
that every caller obeys. (b) Read the verdict through a channel the throttle does not cover. That
channel is the **wire**: one `max_tokens: 1` call to `/v1/messages`, whose
`anthropic-ratelimit-unified-*` headers carry the server's live 5h and 7d utilization and
allow/reject status. It is a different endpoint. During the incident the 429 branch returned
before the wire was ever tried, while `next` and `next2` wire reads succeeded every few seconds.
*Unverified:* the wire has not been measured while that account's usage endpoint was throttled.
A wire miss therefore degrades to today's behavior and never to an admit.
*Update (2026-10-01, W2):* our handling of that case is now pinned by a stubbed test (a 429 usage
read plus an HTTP 200 wire read with 7d at 0, allowed: the row routes and reads 0 with no flag,
`tests/claude-accounts-freshness.bats` F-6). The server side is still unmeasured live; the first
real one will show in `claude-accounts --reset-report` as an `unscheduled/wire` row.

## Q2 — drift by live-session count (n = 33,366 consecutive live read pairs)

| Class | Meter | Gap | p99 drift | max | share > 0 |
|---|---|---|---|---|---|
| k=0 at both reads | weekly | 5–15 min (n=4,312) | **0 pp** | 1 | 0.4% |
| k=0 at both reads | session | 5–15 min (n=4,264) | 1 pp | 3 | 2.7% |
| k=0 at both reads | weekly | 15–60 min (n=70) | 0 pp | 0 | 0% |
| k≥1 | weekly | 5–15 min (n=27,365) | 1 pp | 8 | 7.3% |
| k≥1 | session | 15–60 min (n=1,229) | 28 pp | 66 | 50% |

With no live session on this Mac, an account does not move: 141 of ~8,800 k=0 pairs rose by ≥1 pp,
and only one rose by ≥3 pp (next, session +3 pp, 2026-09-28). Other surfaces (claude.ai, mobile,
desktop, cloud) are therefore **immaterial**, at ≤1 pp at p99. Active weekly drift is p99 9.9–14.3
pp/h, by k bucket (§3). Limit: the meters are integer percents.

**Consequence for scheduling.** An idle account's poll carries almost no information. Its budget
is its own, though (Q1), so skipping it frees nothing for busy accounts. Changing the router to
consume k=0 rows carried forward without a read would be all risk for no measured gain. **Not
built.** The 180 s keepwarm cadence stays: the drift over one tick on active accounts (weekly p99
1 pp at 5–15 min) does not justify going faster, and the per-token budget does not justify going
slower.

## Q3 — events that move usage DOWN

13 decreases with no reset stamp passing, 8 of them ≥5 pp (`q2-output.txt` §4):

| Event | Seen as | Local evidence, before any poll |
|---|---|---|
| Natural reset | `*_reset_at` passes | **The stamp itself.** `inherit_lastgood` already blanks a rolled meter, but it kept replaying the stored `wire_rejects` for that window. |
| Banked reset (`/limit-reset`) | weekly and session fall, `weekly_reset_at` unchanged, new `session_reset_at`; next4 2026-10-01: −100 pp | **None.** Not in any of 61 transcripts modified that hour, not in the four `history.jsonl` files, and no debug log. `history.jsonl` holds the operator's `/limit-recover` prompts around it, but not the redemption. The binary posts `reset_rate_limits` and records only telemetry (`tengu_cedar_ember_*`). |
| Fleet-wide server reset | every account fell together (2026-09-04 19:57→20:07Z: next −31, next2 −49, next3 −13, next4 −16 weekly) | None. |
| Relogin | an auth change; usage is per account, so it does **not** fall | Not a usage event. A new token may carry a new 429 budget, but that is unmeasured. |

**What to show and route on.** A reading taken before a known reset is wrong, and wrong in the
safe direction: it over-states usage. Show it as **"reset since this reading"** with the
evidence, never as a current figure, and drop the stored rejection for the window that reset.
Positive evidence that may clear a stored rejection: (1) that window's reset stamp has passed;
(2) a **recorded** redemption (a manual flag on `claude-accounts`, written by whoever learns of
it, e.g. a `/limit-recover` run told "I just used the banked reset"); (3) a fresh wire read in
which the server itself no longer rejects that window. *Superseded 2026-10-01 (W2): (2) and its
flag were removed — the read detects a banked reset with nobody's action, because a throttled
reading of a capped account is always >= 90% and so always fires the wire (3).* Routing still needs a figure. A rolled or
redeemed meter with no new read stays *unknown*, and unknown is refused. Only a fresh wire read
supplies the figure the router may act on.

## Q4 — what the producer and the callers now do

1. **No in-call retry on 429.** Default 0, `CC_ACCOUNTS_USAGE_429_RETRIES` to override. A retry
   inside 30 s fails 97.6% of the time.
2. **Shared per-account backoff** (`claude-accounts-pollstate.json`). After a 429, *every* caller
   (keepwarm, `--fresh`, `--rank`) skips that account's usage poll for 180 s, then 360 s, capped
   at 600 s, and the backoff resets on the next success. The cap comes from §2b: past 5 min the
   chance that the next poll succeeds stops improving with the gap (38% at 5–10 min, 46% at
   10–30 min).
3. **The wire substitutes for the throttled read** when it has something to decide: the last
   reading was near a wall (≥ 90%), carried a stored rejection, or a reset has been evidenced
   since. The cost is one request instead of three.
4. **A fresh wire verdict outranks a stored one.** It clears a stored rejection only when the
   server says that window is not `rejected`, and it admits the row for routing only on the
   wire's own utilizations (5h and 7d). A row whose Fable figure predates a reset routes without
   a Fable figure, which is refused on the Fable lane.
5. **Reset evidence makes keepwarm sweep now.** It ignores the cache-age skip when an account has
   a reset stamp passed, or a recorded redemption, after its last good read. (Recorded
   redemptions superseded 2026-10-01, W2; a stamp is the only stored evidence now.)

## Q5 — the readout

The board, `/accounts` and the markdown readout already marked a last-known row with `*`, `↻` and
an "as of" time. They now also: render a pre-reset meter as `—` with "reset since this reading
(<evidence>)"; show the wire's live figure on a throttled row that has one; and replace the
"--fresh to retry" advice, which would spend the throttled budget, with the backoff deadline.
Startup still only reads the board file. Nothing on the session-start path polls.
