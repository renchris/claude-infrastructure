# C1 — Do cloud sessions draw on the same Claude Max quota as local sessions?

**Verdict: SAME POOL.** Vendor-stated, and independently reproduced from this box's own stores at
p = 6.5e-06. No arm found any evidence for a separate cloud pool; two arms could not be run and are
named as such.

Date: 2026-09-10. Repo: `/Users/chrisren/Development/.worktrees/cloud-lane-research`.
Read-only throughout: no cloud fire, no token mint, no endpoint call, no store mutated.

---

## 1 · Evidence table

| # | Arm | What was read | What it shows | Verdict |
|---|---|---|---|---|
| **D1** | **Official docs — the decisive sentence** | `https://code.claude.com/docs/en/claude-code-on-the-web` § Limitations | verbatim: *"**Rate limits**: Claude Code on the web shares rate limits with all other Claude and Claude Code usage within your account. Running multiple tasks in parallel consumes more rate limits proportionately. **There is no separate compute charge for the cloud VM.**"* | **SAME** |
| D2 | Official docs — corroboration + an instrument trap | `https://code.claude.com/docs/en/costs` | Teams/Enterprise: *"each member's Claude Code usage draws from a per-seat allowance that resets on a rolling five-hour window and a weekly window. The allowance is shared with Claude chat and Cowork."* And: `/usage`'s breakdown is *"computed from local session history on this machine, so usage from other devices or claude.ai is not included."* | SAME + names why `/usage` attribution cannot see cloud |
| D3 | Support-tier corroboration | WebSearch over `support.claude.com` (article fetch returned the info **absent** from that page) | search summary: usage across claude.ai / Claude Code / Desktop counts toward one limit | SAME (secondary, weak — the direct fetch could not confirm) |
| **C1** | **Credential identity of the create** | `scripts/cloud-create-api.py:175-210` (`access_token`, `org_uuid`) | Session is created with the account's **own keychain item** → `claudeAiOauth.accessToken`, plus `oauthAccount.organizationUuid` read from that account's `.claude.json`. **Identical credential and org to the local `claude` binary.** No API key, no service org, no separate identity. | **SAME identity** |
| C2 | Product identity (makes D1 binding on us) | decl field `url=https://claude.ai/code/session_…`; `cloud-create-api.py:56-76` mirrors the binary's own `teleportToRemote` (`POST /v1/sessions`, `anthropic-beta: ccr-byoc-2025-07-29`); acceptance test pins `environment_kind == "anthropic_cloud"` | Our fired sessions **are** Claude Code on the web, not a side product | binding |
| **E1** | **Idle-account natural experiment** | 23,474 rows `~/.claude/logs/account-utilization.jsonl` × 692 `*.decl` × 6,490 transcript intervals | On hours where the account had **zero interactive sessions (ps) and zero transcript coverage in h-1/h/h+1**: weekly-% rose in **14 of 55** fire-hours (25.5%) vs **0 of 65** no-fire hours (0.0%). **Fisher one-sided p = 6.504e-06.** | **SAME** |
| E2 | Dose-response, three strata | same | Marginal excess weekly-% per fire: **+0.145** (k=0), **+0.143** (k=1), **+0.130** (k=2-3). Three near-independent strata converge. (k=4-6 −0.099 and k≥7 +1.43 are confounded — at high local concurrency the fire count is a proxy for a busy period, not an exposure.) | SAME |
| E3 | Placebo / cell-selection falsifier | fire series shifted +3d, +7d, −7d onto the **same** idle cells | **0 rises out of 35** pseudo-fire cells. The signal is attached to the fires, not to that class of hour. | rules out cell-selection |
| E4 | Per-account replication (independent orgs) | same | `next2` **10/32 vs 0/36** · `next3` **6/24 vs 0/59** (`next` n too small: 1/6 vs 1/2). Four distinct `organizationUuid`s verified, so the accounts are genuinely separate meters. | SAME, replicated |
| E5 | Magnitude coherence | `docs/research/usage-telemetry-100p-2026-08-16/exchange-rate.md` (1 weekly pp ≈ 780K Opus-5 output **or** 9.5M cache-creation; cache-read ≈ free) vs `docs/plans/CLOUD_BACKLOG_PIPELINE.md:122-127` cloud sessions at 4,080 → 84,109 output / 581K → 16.4M cache-read | 0.144 pp/fire ≈ **112K Opus-output-equivalent** — squarely inside the measured cloud-session range. The mechanism can reach the observed magnitude. | consistent |
| **S1** | **Search for a separate cloud limit in the meter itself** | two verbatim `api/oauth/usage` captures — 2026-08-16 (`exchange-rate.md:66-98`) and 2026-08-25 (`weekly-reset-utilization-2026-08-25/C-alt-sources.md:67-86`); plus 0 `usage-schema drift` events in 12,132 lines of `~/.claude/logs/claude-accounts.log` (positive control: 2,529 `probe` lines present) | `limits[]` carries only `session`, `weekly_all`, `weekly_scoped`. Eight codenamed buckets all `null`. `nimbus_quill` reads **0.0** on **both** captures — including 2026-08-25, mid-burst, when `next2` had just fired 25 then 30 cloud sessions on consecutive days. No cloud-shaped meter has ever appeared. | **no separate limit** (one residual, §4) |
| S2 | This box already prices it that way | `scripts/handoff-fire.sh:82-83`, `:5833-5875` | Design belief, stated in code: *"An off-box fire spends an account's quota rather than this box's cores, so it is opt-in per box."* and *"A cloud fire is priced in ACCOUNT rate limit, and that is the only instrument that reads it."* The fire is **gated on `claude-accounts --route general`** and returns 9 when no account is routable. | SAME (a belief, corroborating — **not** independent evidence) |
| S3 | Cloud session terminal-state error texts | 376 `*.returned` + 998 `*.retired` records | No `hit your … limit` text anywhere. **But** these records are terse `key=value` (`outcome=returned-close-failed`, `at=…`) with no status prose, so the instrument could not have seen one. | **CANNOT TELL** |
| A1 | Follow-up-send arm (an intended second exposure) | 668 `*.sends` records, 668/668 mapped to an account | **n = 0** idle-hours carrying a follow-up send with no create in h-1/h/h+1 — sends always co-occur with their create. The arm is unrunnable, not null. | **CANNOT TELL** |

---

## 2 · Overall verdict

> **SAME POOL.** Cloud sessions fired from this box draw on exactly the same Claude Max
> 5-hour/weekly allowance as local sessions on the same account.

**Strongest arm: D1** — Anthropic's own documentation says it in one unambiguous sentence, on the
page that governs the product our `cloud-create-api.py` actually creates (C2 makes that binding).

**Strongest *independent* arm: E1** — the vendor sentence is corroborated, not merely believed. On
55 hours where the target account had no interactive session (ps) and no transcript activity at all,
a cloud fire moved that account's server-side weekly meter 25.5% of the time against **0.0%** in 65
matched control hours (p = 6.5e-06), replicated on two separate accounts (E4), with a placebo that
returns 0/35 (E3) and a dose-response consistent across three concurrency strata (E2).

**`docs/plans/CLOUD_BACKLOG_PIPELINE.md:130` — *"there is no VM line item at all — the cost is
tokens from the account's Max quota"* — was carried as a CLAIM. It is now CONFIRMED**, on both a
vendor statement and an independent local measurement.

### Estimated size of the cloud draw

At **0.144 weekly pp per fire** (the E1/E2 estimate) × 692 declarations over the 34-day window
÷ ~19.4 account-weeks ≈ **5.1 weekly pp per account-week** — roughly **5% of one account's weekly
allowance**. Cloud is a real but minor share of what filled these windows. Caveat: the estimator is
fitted on idle-account hours, which the router preferentially selects for; fires placed on busy
accounts are unmeasured by this method.

---

## 3 · The consequence, stated both ways

**If the pool is SHARED (the finding):**
- **Cloud adds ZERO capacity when quota binds.** Routing an item to a cloud VM when `next` is at
  100% LIMITED does not buy a single extra token — it spends the same allowance from a different
  machine.
- **Worse: the lever disarms itself exactly when it is reached for.** `handoff-fire.sh:5869-5873`
  refuses an off-box fire with `cloud-account-policy` / return 9 the moment
  `claude-accounts --route general` finds no routable account. At today's picture (next **100%
  LIMITED**, next2 95%, next4 73%, next3 51%, all on pace to fill), cloud fires are already routing
  onto a shrinking set and will refuse outright as the last two fill.
- **What cloud DOES buy stays true and is worth stating separately: capacity of a different kind.**
  Per `docs/research/cloud-local-cost-ab-2026-08-11.md` §3/§6, cloud costs **0.81×** a local
  dispatched session for the same brief (cache-write 0.82×, cache-read 0.72× — the cold VM has no
  `~/.claude` preamble to cache), and it spares **this box's cores, RAM, panes and worktrees**.
  So cloud is a **CPU/box-capacity lever and a small token *saving*, never a quota lever.**
- **Operational reading for today's picture:** with all four accounts on pace to fill, the binding
  constraint is the plan allowance, and no venue choice relieves it. The only levers that do are
  (a) reduce output + cache-creation tokens (cache **reads** are ~free against the weekly meter —
  `exchange-rate.md`, so shrinking contexts is the wrong economy), (b) wait for staggered resets,
  (c) usage credits (currently `is_enabled: false`, `user_disabled: true` on all four).

**If the pool were SEPARATE (counterfactual, for completeness):**
cloud would be additive capacity — the correct move under a filling fleet would be to shift every
eligible item to `--venue cloud`, and `handoff-fire.sh`'s account-headroom gate would be a bug that
throttles free capacity. **Do not act on this branch: three arms refute it.**

---

## 4 · Adversarial pass — where this verdict is weakest

### The strongest reading under which the overall verdict is wrong

Two distinct readings, ordered by strength.

**R1 (weaker) — "rate limits" ≠ "the allowance."** D1's sentence says *rate limits*, which in
Anthropic's platform vocabulary can mean RPM/ITPM throughput rather than the 5-hour/weekly plan
allowance. Under this reading cloud could share throughput while drawing on a separate allowance.
**Rebutted by E1**, which measures the *allowance* meter directly (`limits[].percent`,
`kind: weekly_all`) and finds it moves. The two arms are testing different quantities, which is
precisely why they compose rather than merely agree.

**R2 (the real hole) — a same-account local charge, coincident with the fire, that both idle
instruments miss.** Checked and ruled out: (a) no `claude -p` anywhere in the fire path
(`grep` over `bin/cc-offload`, `scripts/cloud-create-api.py`, `scripts/handoff-fire.sh` — the only
hits are pane-id comments and a `--print` CLI flag); (b) the create is a plain REST `POST`, zero
inference; (c) the router's headroom read is a REST call to `oauth/usage`, zero inference.
**The surviving residual:** `concurrency()` (`bin/claude-accounts:498-506`) **explicitly skips
headless one-shots** — *"Headless one-shots (-p/--print) are skipped"* — so `k=0` is a false zero for
a headless session. The transcript-interval instrument was built to cover exactly that gap
(6,490 of 6,525 files used, 99.5%), but Claude Code deletes session data older than
`cleanupPeriodDays` (30 d, per the costs page), so a headless `-p` run on the target account in
**early August whose transcript has since been deleted** would be invisible to both instruments.
That is narrow — it must be same-account, headless, transcript-deleted, and coincident with a fire
hour in a way the ±3d/±7d placebo does not reproduce — but it is the one hole this method cannot
close from disk.

### The single measurement that would settle it (designed, NOT run)

**A paired null-fire / one-fire probe on a quiesced account, read on the FLOAT meter.**

1. Pick the account `claude-accounts --route general` returns. Quiesce it: assert `k=0` via
   `ps -wwEo command=` **and** zero transcript mtime movement under its config dir, continuously.
2. **Baseline arm (the control the 08-11 A/B never had):** take ≥5 `api/oauth/usage` reads over
   30 minutes with **no fire**. Record `five_hour.utilization` and `seven_day.utilization` — the
   **top-level bucket map floats**, not `limits[].percent`. Require both flat.
3. **Treatment arm:** fire exactly **one** cloud session with a brief of known size. Wait for
   terminal state. Read `external_metadata.usage` from `GET /v1/code/sessions/<id>` for the exact
   `output` / `cache_write` / `cache_read` counts. Re-read `oauth/usage`.
4. **Predict before comparing:** expected weekly delta = `output/780,000 + cache_write/9,500,000` pp
   (`exchange-rate.md`). Same-pool predicts the observed float delta matches within the exchange
   rate's CV RMSE (1.63 pp over ≥2h intervals; far tighter at this scale). Separate-pool predicts a
   delta indistinguishable from the baseline arm's zero.

**Why the float is the whole design.** `limits[].percent` is a 1-point-granular integer — this is
exactly threat 6 that defeated the 08-11 A/B (*"the published figure is 1-point granular, so it
cannot attribute consumption per arm"*), and it is why E1 could only ever be a rate-of-rise
argument. `five_hour.utilization` / `seven_day.utilization` are **floats** in the raw payload and
would resolve a single session directly. Cost: one fire, ~10 min, ~0.15 weekly pp.

### Named blockers, uncertainties and a forward-looking blind spot

- **`nimbus_quill`** — the one non-null codenamed bucket in the usage payload, `utilization: 0.0`,
  `resets_at: null`, rendered by nothing on this box, and named nowhere in the binary. **Cannot
  tell** what it meters. It reads 0.0 on two captures nine days apart, the second mid-burst on the
  account that had just fired 55 cloud sessions in two days, which is weak evidence it is *not* the
  cloud meter — but it is inference, not measurement.
- 🚨 **A cloud-surface-scoped cap could arrive and be INVISIBLE to every consumer on this box.**
  The schema already carries the slot: `limits[].scope` is `{model: {...}, surface: null}`.
  `pick()` (`bin/claude-accounts:910-918`) filters `weekly_scoped` on `scope.model.display_name`
  only and **never reads `surface`**; `limits_drift()` (`:920-962`) flags only *unmodeled kinds*,
  and `weekly_scoped` is a **known** kind — so a `{kind: weekly_scoped, scope: {model: null,
  surface: "cloud"}}` limit would be silently skipped, log nothing, and change no row. The first
  symptom would be an unexplained refusal. This is a live gap regardless of today's verdict.
- **`~/.claude/logs/account-utilization.jsonl` drops the float.** `record_utilization()` persists
  `limits[].percent` (int) and discards the whole top-level bucket map including
  `five_hour.utilization` / `seven_day.utilization` (floats) and `limit_dollars` /
  `used_dollars` / `remaining_dollars`. Persisting the floats would make every future question of
  this shape answerable **retrospectively**, at zero marginal cost — the sweep already has the
  payload in hand. (Confirmed dropped: `weekly-reset-utilization-2026-08-25/C-alt-sources.md:59-72`.)
- **S3 and A1 are genuine "cannot tell", not nulls.** No cloud terminal-state record on this box has
  ever carried status prose, so it could not have recorded a usage-limit death; and no idle hour
  carries a follow-up send without its create, so the second exposure arm has zero cells.
- **`docs/research/orchestration-units-2026-08-19/A6-quota-economics.md` mentions cloud/VM/web
  ZERO times** — the repo's dedicated quota-economics axis never considered this question. This
  report is the first measurement of it.
- **`bin/claude-accounts` never called.** Every usage figure here is read from the on-disk
  time-series and from two previously-captured verbatim payloads; no token was minted or refreshed.

---

## 5 · Method / reproduce

```
$S/work-C1/corr.py                    # hourly bins, k-stratified, spearman
$S/work-C1/tight.py                   # tightened k=0 control, lag structure, per-account replication
$S/work-C1/headless.py                # transcript-interval idle control + ±3d/±7d placebo
$S/work-C1/sends.py                   # follow-up-send exposure arm (n=0)
$S/work-C1/transcript-intervals.tsv   # 6,525 (acct, birth, mtime, size) rows
```

Account → config dir → transcript root (verified from `~/.claude/accounts.json` and four distinct
`oauthAccount.organizationUuid`s): `next`→`~/.claude/projects` (`~/.claude-next/projects` is empty;
`.claude` mirrors `.claude-next`), `next2`→`~/.claude-secondary`, `next3`→`~/.claude-tertiary`,
`next4`→`~/.claude-quaternary`.

Idle definition used for E1: `max(k)==0` over ≥3 utilization samples in hour *h*, **and** zero
transcript-interval coverage in *h−1*, *h*, *h+1*. Intervals built from `stat -f '%B %m %z'`,
excluding files <2,000 B and spans >7 d (35 of 6,525 files, 0.5%).
