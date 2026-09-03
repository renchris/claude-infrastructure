# Why a bare `claude` lands on the pinned account — desk-router abstention

**Date:** 2026-09-01 · **Trigger:** the operator observed a session running on `next` while
`/accounts` reported the desk lane's answer as `next3`, and asked whether the cause was only a
failed quota sweep. It is not.

**Method:** live reads of `~/.claude/route/route.jsonl`, `~/.claude/logs/claude-accounts.log`,
`account-utilization.jsonl`, `auth-timeseries.jsonl` and the source, plus three independent
read-only recon agents (concurrency instrument · keychain instrument · launcher observability).

---

## 1. The proximate event, attributed rather than assumed

The `claude` process for the observing session started at **04:43:05Z** (`ps -o lstart`, pinned
`TZ=UTC`). `route.jsonl` carries exactly one decision at **04:43:05Z**:

```
{"ts":"2026-09-01T04:43:05Z","slot":"interactive","outcome":"none","acct":null,
 "excluded":{"next":"keychain-error","next4":"keychain-error",
             "next3":"keychain-error","next2":"keychain-error"}}
```

Attribution was **measured, not inferred**: `claude-accounts --readout` appends no route row and
`--route` appends exactly one (checked by line-count delta either side of each), so that row is the
launcher's own call and not a readout run by the session. The process chain
`kitty → /bin/zsh -l → cc-close-attrib → claude` with `CLAUDE_CONFIG_DIR=~/.claude-next` confirms an
operator-typed **desk launch** that fell back to the pinned account — not a fired/handoff session,
which legitimately does not route.

**Ruled out:** a cold cache. `com.claude.accounts-keepwarm` is loaded and exiting 0; cache age at
check was 74.3 s against `cache_ttl_s` 90.

## 2. The rate, and the correction to a tempting overstatement

Of **230** recorded `slot:"interactive"` decisions since the recorder's birth (2026-08-12),
**23 are abstentions — 10.0% all-time, 19.7% over the last 12 days.**

Every abstention excluded all four accounts. ⚠️ **That specific statement is near-tautological and
must not be quoted as a discovery**: `--route` returns `none` precisely when nothing is routable,
i.e. when all four are excluded. The non-trivial finding is the *uniformity of the reason*:
**20 of 23 abstentions carry a single distinct exclusion reason across all four accounts.** One
shared instrument failing takes out the whole fleet at once.

| exclusion reason | records | class |
|---|---|---|
| `concurrency-unmeasured` | 68 | data (instrument) |
| `no data (http None)` | 16 | data |
| `keychain-error` | 6 | data (instrument) |
| `5h-cutoff` | 2 | policy |

## 3. Why an instrument failure removes an account from routing

`probe_account` writes the failure state into `row["error"]`, and `_excluded()` tests `row["error"]`
**first**, ahead of every other rule and on all three lanes. `BAD_AUTH` is *not* the linkage — it has
one consumer, `cache_read`, with no routing effect.

`inherit_lastgood()` then restores the account's last-good quota, which is why the readout showed
starred percentages — but its docstring is explicit that this is deliberate and display-only:

> Merge an account's last-good quota into a quota-absent row for VISIBILITY ONLY. **NEVER touches
> `row['error']`** → `_excluded()` still bails on it, so the router excludes the row exactly as
> before (no policy change).

So the router abstained while holding quota data 74 seconds old. The distinction the code already
draws and then discards: `no-keychain-item` → `logged-out` is a **genuine credential fact** and
excluding is correct; `keychain-error` is an **instrument failure** and says nothing about whether
the account is usable — the launched binary reads the keychain itself. Confirmed transient: a
`--fresh` sweep ~60 s later read three of four healthy and routed to `next3`.

## 4. `concurrency-unmeasured` — the dominant cause. Growth hypothesis REFUTED

`k_src == "unmeasured"` iff `r["k"] is None`, whose sole producer is the `ps` census. All **501/501**
recorded failures are `TimeoutExpired` against the hardcoded `timeout=10` (`bin/claude-accounts:497`,
no override). Blowing the *walk* budget alone yields `panes`, not `unmeasured`; `walk aborted by` has
fired 0 times ever. The documented "BOTH instruments must fail" is textually true but operationally
empty — across 17,059 utilization rows, **0** have `k is None` with `k_work` measured.

The corpus **did** grow 3.9× (1,870 project dirs / 3,189 transcripts across four roots, vs the
docstring's 826) — **and that is not the cause.** The full walk still measures **0.054 s warm**,
inside the docstring's own 0.04–0.07 s band and ~90× under the 5.0 s budget. Breach samples show a
**~300× per-directory slowdown** (8.7 ms/dir vs 0.029 ms/dir healthy). Not size — starvation.

**The real cause:** `com.claude.accounts-keepwarm.plist:111-115` runs the *only* sweeper at
`ProcessType: Background` + `LowPriorityIO` (PRI 4). Measured over 8,480 ticks: sweep **p50
10,245 ms, p90 34,014 ms** against a 1.85–2.53 s foreground bench; **78.1% of sweeps exceed 5 s,
33.8% exceed 15 s.** Both bounds were benched in the foreground and only ever execute in the
background band. This is `MEMORY.md` → *bound-must-fit-the-band-not-the-bench*, recurring.

**The inversion that settles instrument-vs-capacity:** the refusal does not stop the launch —
`claude()` falls through to `_claude_pinned`. A mechanism built to **spread** load converts "spread
across four accounts" into "concentrate every launch on the pinned account for up to 600 s".

## 5. `keychain-error` — same family, different threshold

Four returns collapse to one label (`bin/claude-accounts:380-404`): timeout, non-zero `security`
exit, JSON parse failure, non-object payload. Nothing was logged, `p.stderr` (carrying the OSStatus)
discarded, no elapsed time recorded.

Uniform causes are **refuted by the historical shape**: 197 `keychain-error` rows across 72 sweeps,
and **39 of 72 are PARTIAL** (1–3 of 4 accounts). All four share one login keychain, so a locked
keychain, ACL denial or modal prompt cannot fail two while two succeed in the same 10 s window.
Credentials were intact either side of the incident (`auth-timeseries` read all four OK at 04:39:28Z
and 04:45:11Z). A fork/exec `OSError` is excluded too — it would surface as `probe-error` **with a
traceback**, and there were zero such lines that day.

Association with §4 is strong but not identity: **62/69** keychain-error sweeps carry a walk-budget
breach within ±90 s, vs 29.2% of 500 control sweeps (Fisher **p = 8.1e-13**) — but the rates differ
by two orders of magnitude (2,122 walk breaches vs 72 keychain sweeps). Same *family* (starvation),
different *threshold*. "Same cause" overstates it.

## 6. The observability hole, and a claim that was a category error

`_cc_route_config_dir`'s contract says it "NEVER writes: it is a pure decision"; all six fallback
returns set only `_CC_ROUTE_NOTE`, whose consumers are two `[[ -t 2 ]]`-gated stderr prints. **The
launcher-side fallback rate was unmeasurable from disk, retroactively and prospectively.**
`claude-accounts` cannot close this: `log_route_decision` fires at one call site after `get_data()`,
so it never sees a cache-miss abstention (the `CacheOnlyUnavailable` raise precedes it — precisely
the abstention `--max-wait 0` exists to produce), and three of the six launcher fallbacks fire *after*
a `route` row is already written, making that row an upper bound rather than a count.

The launcher header claimed: *"across 931 recorded routing decisions the band has never once been
entered (max observed age 89 s)."* **All 931 rows carry `slot:"lead"`, not `slot:"interactive"`** —
they come from `bin/cc-route`, which calls `--route` with no `--max-wait` and no `--max-age`, reading
at the 90 s TTL and sweeping on a miss. Its ages are bounded under 90 s *by construction*. The claim
proved a property of a different code path with an instrument that could not observe a violation.
The desk row schema carries no `quota_age_s` at all, so the true desk band-entry rate is bounded only
to **2.2%–72.3%**.

**The silent cache-miss path is NOT the explanation here:** weighted by 1,937 session starts, cache
age exceeded 600 s on ~1% of launch moments (median age 177 s, p95 411 s) — 2–3 events across the
whole record. The recorded `none` path (§2) is the real story.

## 7. The pinned fallback is the worst available destination

Desk winners over 231 decisions: `next2` 104, `next3` 47, `next4` 39, **`next` 18 (8.7%)**; `next` is
neither winner nor runner-up in 44%, and explicitly excluded in 38. Last-7d mean weekly utilisation:
**`next` 73.0%**, next2 52.4, next4 48.6, next3 33.2 — the pinned fallback is the **most-drained**
account, and every silent fallback steers onto it. Causal direction is **undetermined** — plausibly a
feedback loop, and this doc does not claim otherwise.

---

## Shipped this session

| | change | commit |
|---|---|---|
| 1 | `read_creds` names which of its four failure paths fired (path · elapsed_ms · rc · the previously-discarded stderr); timeout becomes `CC_KEYCHAIN_TIMEOUT_S` so a test can force it | `b6d1bda77` |
| 2 | `_cc_record_launch` appends one `slot:"launch"` row naming routed-vs-pinned + account; the false grace-band claim replaced with what instrument would be needed to restore a number | `a68e94a4a` |

Six tests added across the two suites, each with a mutant that reproduces the pre-fix blindness and
goes red.

## NOT shipped — filed, with the reason  *(RESOLVED 2026-09-02 — see § RESOLVED below)*

**Inherit the last sweep's `k`** (`bin/claude-accounts:3040-3042` add `"k"` to `_prev_snapshot`'s
projection; `:1330` stamp the inherited value with a staleness marker, bounded by the existing 600 s
grace). Preferred over raising `timeout=10` (spends TTL margin a sweep already breaches at p90) and
over removing `ProcessType Background` (deliberate, and would not close the tail).

**Safety detail that makes it viable:** `heal()`'s rotation gate reads `k_live` from the
`probe_account(..., k_live, ...)` **argument**, not `row["k"]`, so stamping at `:1330` leaves that
gate reading `None` and still refusing — preserving the half of the `None` contract that must never
weaken. `handoff-fire.sh:6020-6043` would need stale-marker awareness.

**Why not this session:** it is a routing-**eligibility** policy change and needs its own
mutant-proven suite; and the instrument that would let anyone evaluate it landed only in the two
commits above and has produced no data yet. Shipping the policy change ahead of its own measurement
would repeat exactly the error §6 documents.

## § RESOLVED — the `k` inheritance shipped (2026-09-02, backlog `1f6208064577`)

`inherit_k()` in `bin/claude-accounts`, behind `CC_ROUTE_K_INHERIT` (R8 pattern, default on), with
`tests/claude-accounts-k-inherit.bats` — 13 cases, **ten mutants executed and confirmed RED**, one
per invariant below. Verified against a trunk baseline: the account and router suites carry an
identical failure set before and after the diff.

**The mechanism, and the ONE place it departs from the sketch above.** The filing prescribed
stamping `row["k"]` at the sweep's finalisation loop, having established that `heal()`'s rotation
gate is safe because it reads the `k_live` **argument**. That reasoning is correct and it is not
sufficient — it enumerates one consumer of the live-census contract where there are **three**, and
the other two read `row["k"]` off `--json`, not an argument:

| consumer | what it does with `k` | under a stamped `row["k"]` |
|---|---|---|
| `heal()` rotation gate | refuses on `k_live is None` | safe — reads the argument |
| `handoff-fire.sh:5986,:6020-6043` | `[ "${k:-0}" = 0 ]` authorises a **Phase-1 headless refresh-token redeem** | a 600 s-old census reads 0 and the redeem proceeds underneath a session started inside that window |
| `cc-relogin-poll` skipped-busy gate | same shape, same field | same |

Both spell the `None` case `unmeasured` **on purpose**, so that an unread `ps` refuses. Stamping
`row["k"]` re-keys them onto a stale value in the **fail-open** direction, on a token redeem. So
the inherited count lands in its own field (`k_stale` + `k_stale_as_of`), `k` keeps meaning *live
pane census, or None*, and the fallback rung is added at the ONE derivation the router already
has — `k_src()` gains a fourth value `panes-stale`, and `_k_base()` (extracted, because `k_eff`
and `k_eff_desk` had already spelled the first two rungs identically) gains a third rung. The
filing's own "`handoff-fire.sh` would need stale-marker awareness" therefore **does not apply**:
that file is untouched, by construction rather than by audit.

**Invariants pinned, each with its RED mutant:** `k` is never written · the stamp lands after the
probes, so `k_live` reaches `heal()` as `None` · a live census is never overwritten by an inherited
one · `> cache_grace_s` is refused, not clamped · a **future** stamp fails closed · the chain ages
off the ORIGINAL measurement (`k_stale_as_of` carried forward per hop, as `inherit_lastgood` already
does for `quota_as_of`) so an inherited count cannot become immortal — measured: 6 hops at 90 s,
then refusal · the cache projection forwards all three fields · `CC_ROUTE_K_INHERIT=off` restores
the pre-fix exclusion for stamped rows too, not just new ones.

**On §6's objection — "the instrument that would let anyone evaluate it has produced no data yet".**
It binds this change too, so the change carries its own: `record_utilization` now writes `k_stale`
and `k_stale_as_of` beside the existing `k_src`, and route-meta gains `k_stale_age_s`. `k_src` alone
would say THAT a charge was inherited but never what it was or how old, which is the shape §6
documents — a claim about a code path with an instrument that cannot observe its violation. With
these, a replay can separate a decision made on a live census from one made at the far end of the
grace, and the 600 s bound is falsifiable from disk rather than argued from the quota study.

**Still true, and not addressed here:** the starvation itself (§4's `ProcessType Background` +
`LowPriorityIO` on the only sweeper) is untouched. This makes the router survive a starved sweep;
it does not make the sweep stop starving. Every item under *Open / cannot determine* stands.

## Open / cannot determine

- *Why* `ps -wwEo command=` exceeds 10 s (0.070–0.083 s foreground now, 1,176 procs). The
  `KERN_PROCARGS2`-under-I/O-throttle mechanism is inference from the plist declaration plus the
  `took_ms` distribution — nothing samples the producer's scheduling band while it runs.
- The true desk-launch denominator, and hence the true fallback rate. `~/.zsh_history` is
  `SAVEHIST`-capped and dedup'd; transcripts carry no launch-mode or account field. Commit 2 begins
  recording this prospectively.
- Whether desk band-entry is nearer 2.2% or 72.3% — needs `quota_age_s` on the interactive row.
- Causal direction of `next`'s drain.
