# Breaking the ~15 ceiling — the actionable ladder

**Date:** 2026-08-19 (live readout 07:30 PDT / 14:30Z) · **Box:** MacBookPro18,2 (M1 Max, `hw.ncpu`=10,
64 GiB) · **Binary:** Claude Code 2.1.220
**Question:** *"What are our ACTIONABLE outcomes to have more than 15 concurrent Claude Code session
equivalents running?"*
**Evidence:** 6 measurement axes + 3 adversarial verifiers, in
[`breaking-the-ceiling-2026-08-19/`](breaking-the-ceiling-2026-08-19/), on top of the settled
[`orchestration-units-2026-08-19.md`](https://github.com/renchris/claude-infrastructure/blob/docs/orchestration-units/docs/research/orchestration-units-2026-08-19.md)
(commit `4a3bd3373`, branch `docs/orchestration-units` — **not yet on main**).
Labels: **MEASURED · INFERRED · QUOTED · REFUTED · UNKNOWN**. §9 records every place a verifier
overturned a finder and which I took.

---

## 1 · THE ANSWER

**You are not machine-bound and you are not even fleet-quota-bound — you are bound by ONE account:
`next` is projected to wall its weekly meter at 123% while `next3` sits at 11% with 7 of your 17
panes, so today's real ceiling is 5.8 continuously-working units (≈16 panes) against a balanced 8.9
and a free-lever 11–12.**

- **More than 15 concurrently WORKING units is NOT reachable on four Max accounts by any local
  engineering.** It needs ~6.4 accounts (+3, ≈$600/mo) or capacity that is off the meter entirely.
  Every local lever in this document either redistributes one fixed weekly allowance or spends it
  faster. **MEASURED**
- **More than 15 concurrent RESIDENT sessions you already have.** Fleet pane count p95 = 37, max = 51
  (n=517 min). Panes are not the scarce thing: duty cycle `k_work/k` = **0.357** (n=527), so 15 panes
  is **5.4** working units. Any plan that counts panes as capacity is wrong by 2.8×. **MEASURED**
- **The one open question that could change this answer is free to settle and nobody has:** whether a
  cloud session bills the same 5-hour meter. Both experiments run so far are 5–13× below the
  instrument's resolution (§8.1). If cloud is off-meter, >15 sustained becomes reachable without
  buying an account.
- **Do first:** make the router's working-session walk recurse (`bin/claude-accounts:599`) and rescale
  `KMAX` 8→10 in the same diff. It is mechanical, it is actively misrouting right now, and every other
  lever's gain lands on the wrong account until it is fixed.

---

## 2 · THE LIVE STATE, VERBATIM

`/Users/chrisren/.claude/bin/claude-accounts --readout`, run at 14:30Z for this document:

```
| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| **next** ➤ | 3 | 40% | Wed 07:29 (in 17m) | 60% | 22% | Sat 20:59 (in 3d 13h) | Tue Sep 15 15:44 (in 27d 8h) |
| next4 | 2 | 22%* | Wed 09:20 (in 2.1h) | 29%* | 15%* | Sun 02:00 (in 3d 18h) | Sat Sep 12 23:02 (in 24d 15h) |
| **next3** ➤ᵍ | 7 | 0% | — | 11% | 0% | Tue 05:00 (in 5d 21h) | Thu Sep 03 10:27 (in 15d 3h) |
| next2 ← you | 5 | 54% | Wed 08:49 (in 1.6h) | 38% | 0% | Sat 03:59 (in 2d 20h) | Mon Sep 07 04:28 (in 18d 21h) |
- ↻ `next4` — poll throttled (a 90s endpoint throttle, NOT a usage cap); numbers are last-known as of 06:38; `--fresh` retries

➤ desk (bare `claude`) → **next** — earliest weekly reset among 5h-safe accounts · weekly ↻ 3d 13h · 5h 40% · safe set
➤ general → **next3** · ➤ fable → **next**
weekly burn (1.00× = lands exactly at the 100% wall): next2 burn 0.64× → ~64% by reset, needs 22%/d over 2d (recent 28%/d) · next burn 1.23× → ~123% by reset ⚠ WALL, needs 11%/d over 3d (recent 18%/d) · next4 burn 0.63× → ~63% by reset, needs 19%/d over 3d (recent 11%/d) · next3 burn 0.70× → ~70% by reset, needs 15%/d over 5d (recent 14%/d)
Fable window: **permanent** (no expiry).
_Cache ≤90s old; `--fresh` forces a live sweep._

**Agent backends beyond Claude** — registry `~/.claude/providers.json`

| backend | routable | version | auth | plan | bills outside it? | model pinned |
|---|---|---|---|---|---|---|
| Codex CLI | ✅ | codex-cli 0.147.0 | ok | ChatGPT Plus | no | gpt-5.6-sol @ xhigh ✓proven |
| Pi · Codex backend | ✅ | 0.84.1 | ok | ChatGPT Plus | no | gpt-5.6-sol ✓proven |
| Pi · Claude backend | ⊘ skipped | 0.84.1 | credentials_not_configured | Claude Pro/Max (auth works, usage does NOT draw on the plan) | 🚨 **YES** | — |
| Antigravity | ⊘ skipped | 1.107.0 | ok | UNKNOWN | UNKNOWN | — |
| Gemini CLI | ⊘ skipped | 0.29.5 | ok | UNKNOWN | UNKNOWN | gemini-3-pro-preview ⚠unproven |
| Grok CLI | ⊘ skipped | not installed | — | UNKNOWN | 🚨 **YES** | — |
- ⊘ `pi-claude` — COST GATE FAIL — bills per token outside the Max plan
- ⊘ `antigravity` — NOT AN AGENT BACKEND — the binary is the VS Code editor launcher, no non-interactive mode
- ⊘ `gemini` — DEFERRED — plan tier UNKNOWN, so the cost gate cannot clear it
- ⊘ `grok` — COST GATE FAIL — API-key-only, and we hold no xAI plan

➤ non-Claude backends ready now: **2 of 2 routable** (6 known)
- 🚨 rows marked **YES** bill OUTSIDE a plan we hold — not wired, by policy (`accounts.json spend.usage_credits_authorized=false`)
```

Three lines from that block decide this document:

1. **`next` is the only account flagged `⚠ WALL` (1.23×) and it is also where the desk lane routes.**
   Same rendered block, same instant. Six hours earlier (B4 §2.0) `next` read 1.14× — **the imbalance
   is worsening, not stable.** *Whether the desk pick is caused by the router blindness (§3 L1) or by
   the desk lane's deliberate two-key sort — 5h-safe set, then earliest weekly reset, which does not
   rank on burn rate at all (`accounts.json .router._desk`) — is **UNMEASURED**. Both are live
   candidates and both point at the same fix surface.*
2. **`next3` holds 7 of 17 panes on the account with the most slack** (11% weekly, resets in 5d 21h).
3. **Fleet weekly usage = 60+29+11+38 = 138 of 400 pp. 262 pp unused.** The fleet total is *not* the
   binding constraint. One account's share of it is.

**Imbalance ceiling, re-derived at 14:30Z with these numbers** (B4's method, fresh inputs):
mean burn ratio 0.80, max 1.23 ⇒ effective sustainable under today's mix
= `8.86 × 0.80/1.23` = **5.76 working units = 16.1 resident panes. They are running 17.**
(B4 at 13:14Z: 5.95 / 16.7 against 17. Independent re-derivation, same verdict, drifting the wrong
way.) **MEASURED**

---

## 3 · THE LADDER

**Unit:** 1 sustained session-equivalent = one continuously-WORKING unit, burning at the measured
6.45 %/day of one account's weekly meter. Multiply by 1/0.357 = **2.80** for resident panes.
Rows ordered by **sustained session-equivalents gained per unit of effort**. Every row separates
SUSTAINED (24/7 token rate) from BURST (units alive at one instant) — they are different products.

| # | Do this | SUSTAINED | BURST | Cost / effort | Does NOT fix | Today? | Exact change |
|---|---|---|---|---|---|---|---|
| **L1** | **Router walk recurses + `KMAX` rescale, one diff** | **+0.3 realised now; unlocks up to +2.9** (§3.1) | **large** — `next` was offered a head of 8 when the truthful head was 0 | one diff + one SSOT key; walk 0.045 s → **0.150 s** (3.2% of the 5.0 s budget) | the box; the total allowance | **YES** | `bin/claude-accounts:599` swap `os.scandir(slug.path)` → bounded `os.walk`, **excluding `journal.jsonl`** (158 on disk, parent-written ⇒ a phantom burner per workflow run); fix the false clause at `:543`; `accounts.json .router.KMAX` **8 → 10** |
| **L2** | **Fan out to FEWER, BIGGER units; change the CLAUDE.md rules that mandate the opposite** | **+1.5 to +3.0** | **−** (fewer units by construction) | a doc edit + discipline. **Zero engineering.** | the box; the total allowance | **YES** | §5.1 + §5.2 — replacement wording given verbatim |
| **L3** | **Settle the cloud-meter question from disk** | **UNKNOWN — and it is the only lever that could make >15 reachable** | — | ~1–2 h scripting over data already on disk | nothing yet; it is a measurement | **YES** | §8.1 |
| **L4** | **Route implementation waves to CLOUD instead of local panes** | **UNKNOWN** (0 if same-meter; unbounded if not — L3 decides) | **large, MEASURED**: 0 processes / 0 panes / 0 worktrees / 0 load; 4 simultaneous creates on ONE account in 21 s, **zero refusals**; 15 concurrent declared fleet-wide already observed | fire is 7 s and solved | the quota (probably); **there is NO kill verb** | **YES** | `cc-offload up --task /tmp/brief.txt -n N --account auto` |
| **L5** | **`--teammate-mode in-process` for ATTENDED, Read-heavy waves** | **+0 — box lever, quota-NEUTRAL** | **large**: **+7.0 MB / +0 threads** per teammate vs **282 MB / 28 threads** paned (≥28–40×) | per-invocation flag; **no config edit** | the load gate (**REFUTED** — burn is relocated into the lead, not removed); the quota | **YES** | append `--teammate-mode in-process` to the launch; `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is already set (`settings.json:6`) |
| **L6** | **Index the `cc-backlog` fold; test `CC_BACKLOG_KICK=off`** | **+0 measured** (B3's 0.4–0.7 REFUTED, §9). Frees **2.3 cores** and restores two dead close oracles | + | medium (index) / one env var (kick test) | the quota. **May make it WORSE** — a box lever that raises duty cycle spends quota faster (§8.6) | **YES** | index inside `bin/cc-backlog` (store is append-only ⇒ an offset index is exact); `CC_BACKLOG_KICK=off` as the one-variable experiment |
| **L7** | **A 5th Claude Max account** | **+2.21, linear** | + | **money** (~$200/mo) | the box; the OAuth refresh herd | purchasable | — |
| **L8** | **Hand-fired `codex exec` bursts** (≤400-line files, read-only) | **+0.054 = +0.6% of fleet** | + (4 concurrent, ~3 min, 2 pp, no pane, no Claude quota) | none if unwired; **~1 agent-day if you build the dispatcher — do not** | everything | **YES** | `codex exec --sandbox read-only --skip-git-repo-check` — ~5 bursts/week is the honest budget |
| **✗ L9** | ~~Express fan-out as workflow/unnamed agents to get more agents per pane~~ | **NEGATIVE: ÷2.43–3.53** | + (re-bound by the 8/20 caps — the cheap path is the CAPPED one) | — | — | — | **REFUTED — do not do this.** §4.3 |
| **✗ L10** | ~~Re-key `capacity_gate()` off load~~ | **+0** | +0 | — | — | — | **REFUTED.** `CC_FIRE_ADMIT_BUDGET`=1: **19/19 refusals in 8.6 days were followed by an admit, 3 at +0 s.** Zero fires permanently lost. It costs latency, never throughput — and the load term is the only sensor that can see the 42% of the box that is our own daemons |
| **✗ L11** | ~~Flip `teammateMode:"in-process"` in settings.json fleet-wide~~ | +0 | + | — | — | — | **REFUTED as a fleet setting.** The spawn generation cap is fed by a stamp `bin/it2-kitty` writes at pane creation (`hooks/agent-teams-enforce.sh:317`), so a flip silently reclassifies a POLICED unit as an unpoliced one. Per-wave flag only (L5) |
| **✗ L12** | ~~Buy ChatGPT Pro ($200/mo) for more non-Claude capacity~~ | ~1.08 units **QUOTED** | + | $200/mo | — | — | **REFUTED on price.** A 5th Claude Max returns **2.35** units at the same headline price |

### 3.1 Why L1's sustained number is a range, and what the range means

B4 and B5 disagree and both are right about different questions. I take both, labelled:

| | B4 (§2.2) | B5 (§5) |
|---|---|---|
| claim | balance is worth **+2.91** units (5.95 → 8.86, +49%) | the router fix is worth **≈ +0.3**, possibly 0 |
| what it measures | the **ceiling under today's routing mix** — a fixed mix means the fleet stops when the first account stops | the **loss already realised** — 62/671 sweeps had an account at/over the 5-h cutoff, and in **62/62 (100%)** another account sat under 40% |
| both agree | the fleet holds **262–273 pp of 400 unused weekly quota**, so weekly quota is **not binding today** | |

**Adjudication:** at today's 76–86% of allowance, imbalance costs little — B5's +0.3 is the honest
present-tense number. **The moment ANY other lever raises total burn toward the allowance, imbalance
becomes the binding constraint and it costs +2.9.** That is precisely why L1 is first: it is cheap
now and it is the prerequisite that makes L2/L4/L7's gains reach the fleet instead of piling onto
`next`.

🚨 **A unit warning that must ride with L1.** The settled **9.4 sustainable working units** was derived
as `allowance ÷ (weekly slope ÷ mean k_work)` on the **shallow** `k_work`. Deep `k_work` is 1.312×
shallow (pooled ratio-of-means, n=1,198 minutes), so the *same physical work* re-denominates to
**≈12.3 deep units. No capacity is created.** Comparing 9.4 against any post-fix reading is a unit
error.

---

## 4 · THE SEQUENCE

**Do L1 first.** Not because it is the biggest — L2 is — but because it is the only *mechanical* one,
it is actively wrong right now, and it is the denominator of every capacity number you will read
afterwards.

| Step | Do | Why THIS order |
|---|---|---|
| **1** | **L1 — recursion + `KMAX` 8→10 + partial-abstain, one diff.** Ship the over-refusal tripwire with it (§7.1). | The router hands the widest allowance to the most saturated account. MEASURED live: `next` scored `k_work = 0` while **16 workflow-agent transcripts were being appended on it**, because a lead blocked on its own fan-out stops writing (parent transcript mtime 801 s / 1,398 s stale). **Blindness and inversion are the same fact.** 85% of live writers are invisible (35 of 41), 100% of the invisible ones workflow agents. Anything fired before this lands is aimed at the wrong account. |
| **2** | **L2 — the CLAUDE.md edits (§5).** Can start the same hour: it is a documentation change, not engineering. | Largest sustained gain (+1.5 to +3.0), zero dependency, zero engineering. It is the only lever whose value is realised by *not* doing something. |
| **3** | **L3 — the free cloud-meter probe (§8.1).** | It is the only measurement that can change the top-line answer, and it costs nothing. **Do it before spending a dollar on L7** — if cloud is off-meter, L7 may be unnecessary. |
| **4** | **L4/L5 — route waves to cloud (burst) and use `--teammate-mode in-process` on attended local waves.** | Both are burst levers. They matter only once L1 stops mis-aiming them, and L4's sustained value is unknown until L3. Doing L4 at volume before L3 spends quota you cannot yet price. |
| **5** | **L6 — the `cc-backlog` index.** | Correctness + 2.3 cores, not capacity. **Do it after L1** so that its effect on `k_work` walk latency (§7.1) is separable from the recursion's. |
| **6** | **L7 — decide on a 5th account.** | **WASTED if done before steps 1–2.** You currently use 76–86% of a four-account allowance with one account walling. Adding a fifth meter to an unbalanced fleet buys a meter you will not spend. |

**Explicitly wasted if done out of order:**

- **A 5th Max account before L1+L2** — see step 6.
- **Effort on the cloud FIRE path** — it is already solved: one command, no PTY, 7 s, real VM, repo
  attached, branch pushed. The unsolved half is the **outcome**: 168 fired → 101 pushed (60%,
  re-derived row-for-row) → landed ∈ **[10, 52]** (§9.2). Live board right now:
  `0 working · 2 landed · 75 need you · 7 UNKNOWN`.
- **The capacity-gate rewrite (L10) before fixing our own daemons** — the load term is the only term
  that can see the 42% of the box that is our launchd loop.
- **Any post-fix `k_work` compared against 9.4** — unit error, §3.1.

---

## 5 · WHAT WE STOP DOING

### 5.1 The rule that makes the most expensive unit the default

**`CLAUDE.md:131-132`, verbatim:**

> **Agent Teams are the DEFAULT for all implementation work.** This applies globally.
> Code-writing tasks with 2+ files MUST use Agent Teams (`team_name` + worktree isolation).

**What it costs, MEASURED.** A named teammate is a separate `claude.exe --agent-id` OS process with
its own kitty pane, its own tty, its own MCP server (102 MB) and its own SessionStart hook:
**282 MB / 28 threads** live-sampled (382 MB including the MCP child), and it is the **one unit with
no concurrency cap in any of its three backends**. A 6-teammate wave = ~2.3 GB + 6 panes + ~108
threads.

**But the rule is right on the axis that binds.** The teammate is also the *most quota-efficient*
unit measured: **31,503 output tokens per quota point** vs 8,936 for a workflow agent and 11,622 for
an unnamed subagent — a **3.2–3.5×** advantage that survives every exchange rate tested (2.43× even
under the assumption most favourable to workflows). **So the rule is wrong about the WRAPPER, not
about the UNIT.** Do not weaken the mandate; change the backend.

**Proposed replacement for `CLAUDE.md:131-132`:**

> **Agent Teams are the DEFAULT for all implementation work.** This applies globally. Code-writing
> tasks with 2+ files MUST use Agent Teams. **The teammate BACKEND is a per-wave choice, not a fleet
> setting.** Default to **`--teammate-mode in-process`** for attended, bounded waves whose members are
> Read-heavy — MEASURED 2026-08-19: **+7.0 MB and +0 threads** per in-process teammate against
> **282 MB and 28 threads** for a paned one (≥28–40×), fully reclaimed at exit, with real roster
> membership, per-teammate `model:`, working team messaging and a working `shutdown_request`.
> **Keep panes when the wave is unattended or its members run Bash:** every in-process teammate's
> permission prompts render in the LEAD's single TUI modal and serialise there, so an unattended
> in-process wave that touches Bash **stalls with no watcher** (measured — a verifier's first probe
> deadlocked on exactly this). **Never set `teammateMode: "in-process"` in `settings.json`:** the
> spawn generation cap is fed by a stamp `bin/it2-kitty` writes at pane creation
> (`hooks/agent-teams-enforce.sh:317`), so a fleet flip silently reclassifies a policed unit as an
> unpoliced one. Accept that in-process teammates are invisible to `cc-where`, `cc-mail`,
> `assignee-pane-residency.sh`, crash-harvest and `k_work` (§7.2).

### 5.2 The rule that mints the wrong unit SIZE

**`CLAUDE.md:136-142`, verbatim (the operative clause):**

> 🚨 **PARALLELIZE BY DEFAULT** … **A "clean opportunity" = 2+ pieces of work that are independent
> (no shared file, no ordering dependency) and each self-verifiable** — fan those out immediately, in
> ONE message so they run concurrently.

**What it costs, MEASURED.** Every orchestration unit pays a roughly **class-independent** arrival
tax of **125–281K cache-creation tokens** on the way in — a workflow agent pays *more* than a teammate
(175K vs 159K) against **18× less output** (median 1,708 vs 30,518 tokens). Quota efficiency therefore
tracks unit **size**, not process shape: **1,628 out/pp below 1K output → 42,870 out/pp in the 10–50K
band, a 26× swing.** Today **10.9% of all fleet spend (67.5 of 621.2 quota points over 60 h)** goes to
units whose median output is ~1,700 tokens — **91–93% of that spend is arrival tax, not work.**

**Proposed ADDITION after that clause** (the parallelise mandate is not weakened — it is aimed):

> **Fan out to FEWER, BIGGER units.** Every unit — teammate, subagent and workflow agent alike — pays
> a fixed **125–281K cache-creation arrival tax** on the way in (MEASURED 2026-08-19, n=451 files /
> 60 h), so a unit that produces under ~1,000 output tokens spends **91–93% of its quota just
> arriving**. Before splitting a wave into N, ask whether **N/2 briefs of twice the size** would do
> the same work: below ~10K output per unit the split is a net quota loss. This does not weaken the
> parallelise mandate — the parallelism should be wide in **work**, not in **units**.

### 5.3 Stop reaching for cheap units to get "more agents per pane"

This was the wave's most likely recommendation and it is **measurably backwards**: a workflow agent
buys 0.6 MB instead of 382 MB and pays **3.2–3.5× more quota per unit of work delivered**. It buys box
capacity we do not need and spends the quota we do. **Cheapen the WRAPPER (L5), never the JOB.**

### 5.4 Stop counting resident panes as capacity

`k_work/k` = **0.357** (n=527 min; 0.42 by a second estimator over n=2,108 ledger rows). 15 panes =
5.4 working units. Every "we can run N sessions" claim needs the duty factor or it is wrong by ~2.8×.

### 5.5 Stop quoting four numbers this wave retired

| Retired | Why | Use instead |
|---|---|---|
| **"ambient load = 20.19, the gate is at its ceiling with zero Claude running"** | Unit error: the ×1.553 factor fits runnable **PROCESSES**, the count it multiplied is **THREADS**. Re-derived with a process factor actually measured (1.300): **16.9 — below the 20.0 ceiling.** And 20.19 is the box's own **p90**, not a baseline: load1 ranged **4.66 → 118.95** over 8.6 days (p50 **13.12**), and swung **15.5 points inside 10 minutes.** | *"Load is a moment, not a level."* Report **threads, never shares** — absolutes replicate to ±5% across three windows while shares move 2.5×. |
| **"~1 quota point per ~0.8M tokens"** | **REFUTED.** Measured on local burn across all 4 accounts (summing `message.usage` deduped on `message.id` over each account's own 5-h window ÷ its `utilization`): **4.9–10.6M raw tokens, $4.06–$7.29 per point** — 6–13× more expensive. | 4.9–10.6M raw / point. And **no single session can move that meter by a whole point**, so a whole-point step next to one fire is never evidence about that fire. |
| **"cloud delivers 7.8 landed items/day"** | **UNPROVEN.** `landed()` is a path-**existence** test; for **42 of the 52 positives every declared path already existed on origin/main before the session was declared.** 47/52 branch refs are gone, so no patch-id oracle is reachable. | True landed ∈ **[10, 52]** over 12 days. Fire→push (168→101, 60%) is solid; the land rate is not. |
| **"the capacity gate costs us ~1.2 fires/day"** | **REFUTED.** `CC_FIRE_ADMIT_BUDGET`=1 (`handoff-fire.sh:4334`): the 2nd consecutive refusal ADMITS. **All 19 refusals in 8.6 days were followed by an admit — 3 at +0 s (`budget-expired`), 11 within 1.1–36.6 min.** Zero fires permanently lost. | The gate costs **latency**, never throughput. Do not fund it. |

### 5.6 Stop the write→kick→write loop running as a background default

`bin/cc-backlog:5236` § *S5 KICK-ON-WRITE* spawns a detached `cc-dispatch --decide` on every
successful `add` behind a 30 s debounce; `cc-dispatch` itself calls `cc-backlog add`. Result,
MEASURED: **245 distinct `cc-backlog` PIDs in 7.6 min = 32/min = 2.3 cores held continuously**, with
`cc-dispatch` alive in **420/420** samples despite `StartInterval 300` — a single pass outlives its own
interval, ancestry three deep. Our launchd daemons are **10.393 threads = 42.3% of the box**;
`cc-backlog` alone is **6.64 / 7.34 / 7.41 threads** across three independent windows (±5%), **3.7–8.7×
the entire Claude fleet.** *(Note: lengthening `StartInterval` is REFUTED — passes already overlap and
the kick bypasses the timer. `CC_BACKLOG_KICK=off` is the one-variable test nobody has run.)*

---

## 6 · THE CEILING AFTER ALL OF IT

### SUSTAINED — continuously-working units

| State | Working units | Resident panes | **The wall that binds** |
|---|---|---|---|
| **today, as routed** | **5.8** | 16.1 (they run 17) | **`next`'s weekly meter** — 1.23× while the fleet mean is 0.80× |
| **+ L1 (balance reaches the fleet)** | **8.7–8.9** | 24–25 | the **fleet weekly meter** |
| **+ L2 (bigger units)** | **~11–12** | ~31–33 | the **fleet weekly meter**, and the box re-enters here: load gate (~4–8 mid-turn, bounded) and terminal (~30) arrive in the same range |
| **+ L7 (a 5th Max account)** | **~14** | ~39 | **the fleet weekly meter again**, plus the OAuth **refresh herd** — fan-out concentrates herd risk on one axis and its failure mode is a discontinuous account-wide logout |
| **>15 sustained** | needs **~6.4 Max accounts (+3, ≈$600/mo)** | ~42 | **not reachable locally.** Overage is closed: `extra_usage.is_enabled=false`, `can_toggle=false`, `can_purchase_credits=false` on all four; header `overage-disabled-reason=org_level_disabled`. `credits_ever_enabled=true` on two accounts ⇒ a plan/support question, not a settings one |

**The one thing that could change that last row: L3.** If a cloud session bills less, or elsewhere,
cloud becomes a sustained lever and >15 is reachable without buying accounts. Nothing measured so far
distinguishes the two hypotheses (§8.1).

### BURST — units alive at one instant

| Wall | Binds at | After the levers |
|---|---|---|
| our load gate (`CC_FIRE_MAX_LOAD_PER_CORE` 2.0 × 10) | ~4–8 mid-turn | **not a real wall** — bounded, 19/19 refusals admitted on retry. Latency only |
| quota (crossover) | ~24–25 resident panes | unchanged by any box lever |
| terminal panes | ~30 (iTerm2 froze there; kitty untested at 30) | **removed for teammates** by L5 — 0 panes |
| memory | ~70 pane sessions / ~2,400 in-process agents | **removed for teammates** by L5 — +7 MB each |
| **new binding burst wall after L5** | **the lead's single permission modal** and the lead's own context window | UNKNOWN ceiling; ≥4 proven, untested above |
| **cloud** | **no cap found** — 4 simultaneous creates on one account in 21 s, zero refusals, zero 429s; 15 concurrent declared fleet-wide observed; no cap string in 412,384 lines (positive control: 20 session endpoints found) | 8–10 is the next untested rung |

**Burst >15 is already reachable and has been observed** (p95 37 panes, max 51). The honest reframe:
*"more than 15" was never a question about 15 panes — it is a question about how many of them are
working, and that number is 5.8 today.*

---

## 7 · RISKS PER ADOPTED LEVER

### 7.1 L1 — router recursion + `KMAX` rescale

- **What breaks: over-refusal.** `_excluded` returns `kmax-concurrency` → `claude-accounts --route`
  exits rc 2 → **`handoff-fire.sh` HALTS rather than falling back.** At fleet scale: a wave lead fires
  four items, four refuse, no work starts, and the operator sees only a stalled wave.
- **Predicted magnitude, so a deviation is legible:** pooled per-account-minute exceedance
  **0.69% → 1.94%** (deep @ KMAX=10). **> 4% sustained means the rescale is too tight** — raise KMAX to
  12 (1.29%) or 14 (0.75%). One key in `accounts.json`, no code change. That is the intended escape
  hatch and it is why the integer lives in the SSOT.
- **A known interaction the SSOT already names.** `accounts.json .router._desk_w2` records an
  unfixed residual: *"`next4` stranded 15pp to `kmax-concurrency`, an EXCLUSION rather than a tier."*
  An account excluded for concurrency is removed from the candidate set, not merely deprioritised —
  and L1 **raises** the exclusion rate. Ship the tripwire below in the same diff.
- **How we notice — two sensors exist, one must be built:**
  `account-utilization.jsonl` `k_work`/`k_src` (exceedance rate at KMAX, pre-fix baselines recorded) ·
  `route-meta` `k_src=`/`k_work=`/`kwork_to=` per decision (**`bin/claude-accounts:4371`** — B5 cites
  `handoff-fire.sh:4394-4399`, which is the cloud gate; corrected here) ·
  **MISSING — build it:** log any row excluded `kmax-concurrency` **while its own `session_pct` < 43%**
  (half of `S_CUT`). Refused for concurrency while its meter says half-idle is the exact signature of
  an over-tight cap, and today it is unobservable. Expected rate ≈ 0; more than a handful/day IS the
  signal.
- **Under-refusal is impossible by construction:** DEEP `k_work` ≥ SHALLOW for every one of 1,200
  replayed minutes (it is a superset count). All new risk is on the refusal side.

### 7.2 L5 — in-process teammates

- **Unattended waves STALL.** All members' permission prompts serialise through the LEAD's one TUI
  modal. No watcher, no timeout. **Notice:** the wave produces nothing and the lead's turn never ends.
  **Mitigate:** attended only, or pre-authorise every tool the wave needs.
- **A lead crash loses every teammate's report — worse than reported.** MEASURED: a 4-teammate crash
  wrote **one** `HARVEST/status.tsv` row (`v1 in-process NO-TRANSCRIPT 0 -`); v2/v3/v4 appear in the
  CRASH_REPORT members list and **nowhere in the harvest at all.**
- **Five silent rail breaks** (silent = green over an invisible teammate, the worst polarity):
  `assignee-pane-residency.sh:189` filters `tmuxPaneId` on `^[0-9]+$` and drops the member ·
  `cc-mail` keys on paneUUID ⇒ unaddressable, empty box reads as no-mail · `cc-where` cannot answer ·
  the inbox file stays `read:false` **after a successful abort**, so `CRASH_REPORT.md` re-renders a
  delivered shutdown as an unhandled request (fails the *opposite* way to the others) · **and the
  quota-relevant one: `k`/`k_work` count N teammates as 1** (all tool rows carry the lead's sid), so
  the router UNDER-counts real burn by the teammate multiple and **the quota wall arrives sooner than
  the instruments say.** `cc-teardown` refuses loudly and harmlessly (`verdict=REFUSE
  reason_kind=unknown-target exit=2`).
- **Blocked entirely in headless.** `claude -p` never initialises `teamContext`, so `name:` is
  silently discarded and the call degrades to an ordinary async subagent (team dirs **59 → 59**; the
  tool returns a bare `agentId:` handle). **Any "headless sessions run Agent-Teams waves" plan is
  blocked here.**

### 7.3 L4 — cloud

- 🚨 **No abort path exists in anything we own, for cloud OR workflows.** No `stop`/`abort`/`cancel`/
  `terminate` endpoint in the binary (positive control: 20 session endpoints found, incl. `/archive`);
  no kill verb in `cc-cloud` (`declare fill-paths is-offbox list poll preflight retire show`) or
  `cc-offload` (`gc land ls open say setup up watch`). `cc-cloud retire` retires the *declaration*, not
  the VM. On the workflow side the largest run ever attempted here is **229 agents / 7.2 h / 39 quota
  points** with no shutdown_request, no pane and no `claude stop`. **On a quota-bound fleet an
  un-killable runaway is a capacity bug, not an inconvenience.**
- **The monitor fails silent.** `cc-offload ls` takes **74 s**; under `timeout 60` it prints
  **nothing at rc 0** — an empty board that reads as "no cloud sessions", on the exact tool the
  operator says is their pain point. Any script wrapping it needs ≥90 s.
- **`api/oauth/usage` 429s under ~20 s polling.** Any sampler needs ≥45 s spacing and a backoff
  ladder or it manufactures gaps that read as outages.
- **Never `CCR_FORCE_BUNDLE=1`.** Bundling is the path that yields `sources: []` ⇒ the git proxy
  refuses to inject a push credential (403) ⇒ the work completes and is stranded in a container that
  is later reclaimed. Push the base; the branch the VM *writes* need not pre-exist (confirmed n=4).

### 7.4 L2 — bigger units

Fewer, larger briefs raise per-unit crash blast radius and per-unit context pressure, and `/compact`
crashes teammates (GH #49593). **Notice:** teammate crash-harvest rows and truncated deliverables.
**Bound:** the existing ≤150-line brief discipline is about brief *size*, not job size — a bigger JOB
with the same brief size is the target, not a bigger brief.

### 7.5 L6 — the `cc-backlog` index

`compact` is the one non-append operation: it invalidates the `(mtime,size)` key by design, and a
concurrent reader can fold a file being rewritten. **Serialize it; never run it under a live wave.**
Also: the `timeout 5` bound is shared by `completion-assert.sh:611` **and** `wrap-ledger.sh:654`, so a
breach kills the **👤 rung** as well as the D1 oracle. Make the fold fast first, then the bound never
binds.

### 7.6 L7 — a 5th account

The OAuth **refresh herd**: fan-out concentrates herd risk on a single axis and its failure mode is a
**discontinuous account-wide logout** with no reset to wait for (login cliff — only a new `/login`
moves it). Notice: `claude-accounts` auth column; the `account-relogin` skill is the remedy.

---

## 8 · OPEN QUESTIONS, WITH THE PROBE THAT SETTLES EACH

1. 🚨 **Does a cloud session bill the 5-hour meter?** *The highest-leverage unknown in the wave — it
   decides whether >15 sustained is reachable at all without buying accounts.* Both experiments to
   date are below the instrument's grain: one 810K-token session predicts 0.08–0.19 pt; a k=4 burst
   (1,104,268 tok, $2.23) predicts 0.11–0.43 pt and moved the meter by **zero** over 21.5 min. The
   1-point quantisation makes both uninformative.
   **FREE probe, all inputs already on disk:** regress observed `five_hour` utilization against
   transcript-derived local burn (`message.usage`, deduped on `message.id`) across many
   account-windows with known cloud-fire counts, **controlling for Fable share** — uncontrolled, the
   $/point ordering is monotone in Fable share (22/15/0/0%), not in cloud fires, because Fable is 2×
   Opus and a Fable-heavy account's true cost is understated.
   *Paid alternative if the free one is inconclusive:* ~3 points of clean signal ≈ **$17–20** of cloud
   on one account (≈18–20 sessions), ideally one with no live local session — which does not currently
   exist on this box.
2. **What is cloud's true land rate?** ∈ [10, 52] of 168 over 12 days. Retrospectively unanswerable
   (47/52 branch refs gone). **Forward fix, cheap:** have `cc-cloud fill-paths` record the branch's
   **added** paths separately, so `landed()` stops passing vacuously.
3. **Is an in-process teammate cheaper in RUNNABLE threads than a paned one mid-generation?** If yes,
   L5 moves the *first* wall and returns to the top of the board. **Probe:** paired A/B, one of each
   mid-generation, `top -l 2` **second sample**, attributed per-pid. Cannot be run read-only on the
   live fleet.
4. **Does DEEP `k_work` at weight 1.0 over- or under-charge?** Measured cost per active
   entity-minute says the true weight is **0.66** (workflow agent) / **0.78** (subagent), so 1.0
   over-charges 34% while today's 0.0 under-charges 100%. **Probe:** regress each account's
   weekly-meter slope on DEEP vs SHALLOW `k_work` in fan-out vs no-fan-out minutes. Needs ~10 more
   days — `account-utilization.jsonl` only starts 2026-08-16.
5. **Does `CC_BACKLOG_KICK=off` actually drop `cc-dispatch` duty from 100%?** One env var, reversible.
   Named cost: dispatch latency rises to at most the 300 s backstop. Nobody has run it.
6. **Is duty cycle 0.357 causal or symptomatic?** If panes idle *because* the box is slow, a box lever
   (L6) raises duty and therefore burn — **converting box headroom into quota burn and making the
   imbalance worse.** Quota-forced idling is already ruled out (only 1.1% of samples ≥90% of a 5-h
   window); **box-forced idling is unruled.**
7. **Does the small-unit work actually merge?** L2's +3.0 assumes a 20-wide fan-out could have been 2
   bigger units; some genuinely cannot. Lower bound (halving unit count) is +1.5. *The 3.2–3.5×
   penalty itself is measured; only the recoverable fraction is assumed.*
8. **Is there a cloud concurrency cap above 4?** Never provoked a refusal at k=4 on one account. 8–10
   is the next rung, one burst.
9. **ChatGPT Plus's 5-hour secondary window is `null` today**, so only the weekly gate is live. If it
   arms, the 9.1 agent-hours/week budget changes shape. Nobody owns it.
10. **`kernel_task`** — 740 threads, 25–28% CPU by `top`, **0 by `ps -axM`** — and a **17.6–22.2%
    unattributable residue** sit inside every load attribution in this document. Needs
    `dtrace proc:::exec-success` / sudo. Both bias our-automation's share **downward**, i.e. §5.6 is a
    floor.

---

## 9 · ADJUDICATIONS — where a verifier overturned a finder

Three of six axes were adversarially verified. **Two of those three had their headline measurement
refuted.** That ratio is itself a calibration fact: B4, B5 and B6 are **UNVERIFIED**, and their
numbers should be read with the same suspicion the verified ones earned.

### 9.1 B1 (in-process teammate) — verifier taken on the two contested points

| Claim | Taken | Why |
|---|---|---|
| "if load-cheap, L5 moves the FIRST wall" | **VERIFIER — REFUTED** | In-process adds **0 threads** (lead flat at 19 with 3 and with 4 teammates), but threads ≠ runnable threads: the token generation and tool work now happen *inside the lead's* event loop. **Burn relocated, not removed.** Verifier also replaced B1's QUOTED 382 MB control by read-only sampling a **live** paned teammate (282 MB / 28 threads) — stronger evidence than the finder's. |
| "42× memory win" | **VERIFIER — ≥28–40×** | B1's baseline wandered 221–228 MB on a 34 MB delta ⇒ 8.5–10.25 MB/teammate. Verifier's context-loaded re-run (3 teammates × ~8,000 lines read each): **+7.0 MB each** — so the cheapness is *not* a toy-teammate artifact, which is the assumption B1 never tested. |
| "the generation cap is broken/inert" | **VERIFIER — re-scoped** | Mechanism confirmed (`agent-teams-enforce.sh:317`), but the hook's own refusal text names in-process subagents as the sanctioned uncapped alternative, and commit `60f6ca46e` already ruled the pane-spawn primitive ungated BY DESIGN. **Real risk is coverage loss, not a broken cap.** B1's recommendation stands; its reason does not. |
| shared permission modal | **VERIFIER — NEW, and it bounds the lever** | B1 missed it entirely; the verifier's first probe deadlocked on it. |
| everything else (setting not trick, works as a teammate, headless trap, rail breaks) | **FINDER — CONFIRMED by the verifier's own re-execution**, byte-exact on all five binary anchors | |

### 9.2 B2 (cloud) — verifier taken on the measurement, finder on the structure

| Claim | Taken | Why |
|---|---|---|
| "cloud bills the same 5-h meter" (n=1, +1 pt) | **VERIFIER — UNPROVEN** | At the measured true price (4.9–10.6M raw tokens/point) that session could contribute **0.08–0.19 pt**; the observed step is a quantised counter crossing an integer with 3 live local sessions on the same account. |
| "~1 pt per ~0.8M tokens, venue-independent" | **VERIFIER — REFUTED, 6–13× too cheap** | Measured on local burn, all 4 accounts, plus a 15.5-min short-window replication (next2 +4.0 pt on 40.57M raw / $26.82 ⇒ 10.14M/pt). |
| "the 2026-08-11 A/B corroborates at 1.25 pt/session" | **VERIFIER — REFUTED** | That document §5.6 says verbatim: *"The published figure is 1-point granular, so **it cannot attribute consumption per arm**."* B2 read a calibration out of a source that refuses the inference. |
| "52 landed / 7.8 items/day" | **VERIFIER — UNPROVEN** | 42/52 pass vacuously. True ∈ [10, 52]. |
| `maxConcurrent` is the local cron runner · no cloud concurrency cap · zero local footprint · no kill verb · VM creates-and-pushes · fire path solved | **FINDER — CONFIRMED, several strengthened** | Verifier re-derived `maxConcurrent` from the *consumer* (`Zmp` passes `pathToClaudeCodeExecutable` ⇒ it spawns the LOCAL binary), and re-fired at n=4. |
| "`claude-accounts --readout` exits 2 and corrupts stdout" | **NOT ADOPTED** | Verifier could not reproduce; my own invocation for §2 of this document ran clean at rc 0. **Two clean runs against one dirty one — not a standing defect.** |
| **Net effect** | B2's *conclusion* survives; its *evidentiary status* does not. **"Cloud adds zero sustained" is now an assumption, not a measurement** — which is why it is §8.1 and not a ladder row. | |

### 9.3 B3 (ambient load) — verifier taken on almost everything contested

| Claim | Taken | Why |
|---|---|---|
| "the ×1.553 is unreproducible ⇒ 20.19 inherits ~55% inflation" | **VERIFIER — unit error; conclusion survives** | The factor fits runnable **PROCESSES**; B3's counter-factors are **THREAD** factors. Re-derived: 13.000 × 1.300 = **16.9** — 20.19 still retired, but the error is 19%, not 55%. |
| "cache the two Stop-hook call sites — worth 17.5% of the box" | **VERIFIER — REFUTED, the largest error in the wave** | Caller attribution over two windows (n=420, n=330): `cc-dispatch` **66–68%**, `cc-discover` **20–23%**, **SESSION Stop path 2.0% / 2.6%** (hook forms alone 0.16%). The prescribed fix reaches **~1/40th** of the cost it was priced at. |
| "≈1.2 extra fires/day from re-keying the gate" | **VERIFIER — REFUTED, the prize is zero** | `CC_FIRE_ADMIT_BUDGET`=1; 19/19 refusals admitted. Arithmetic reproduces exactly; the interpretation counts delays as losses. |
| "5–7 s of dead wall-clock every turn-end ⇒ 0.4–0.7 working sessions recovered" | **VERIFIER — REFUTED** | `wrap-ledger.sh:287-375` has its own transcript-keyed single-flight memo wrapping `count_operator_steps()`, so the five hook callers share **ONE** fold per Stop; `completion-assert:611` is phrase-gated at `:602`. N ≈ 1, not 2, and it is bounded at 5 s. **The throughput-tax number does not survive** — this is why L6 shows **+0 measured**. |
| "`timeout 5` ⇒ rc=124, 3/3, the D1 oracle is permanently dead" | **VERIFIER — intermittent, load-dependent** | 11/11 rc=0 at load 19.4–26.9 (CPU 4.32 vs 4.38 — that half replicates exactly). Unrefuted in B3's own 34–46 band. And **worse than B3 said**: the same 5 s bound at `wrap-ledger.sh:654` also kills the 👤 rung. |
| "what is stable is the SHARE" | **VERIFIER — REFUTED, inverted** | Absolutes replicate to ±5% (`cc-backlog` 6.64/7.34/7.41 thr); shares move 2.5× (17.5→29.9→43.3%). **Report threads, never percentages.** |
| "the dynamics control FAILS" | **VERIFIER — REFUTED; the durable methodological fix** | `corr(load1, raw census)` = **−0.005**; `corr(load1, EWMA₆₀(census))` = **+0.842** (peak +0.853, 6.8 time constants, n=420). Every "the control fails" verdict in this line of research was an instrument mismatch, not a finding. |
| `cc-backlog` is the largest single work class · named suspects (gitstatusd 18, caffeinate 7, sleep 41) = **0.0000 threads** · process count is not load · **do NOT subtract ambient** | **FINDER — CONFIRMED, replicated** | |

### 9.4 B4, B5, B6 — unverified, taken with named caveats

- **B4** reproduces the landed figures independently (6.45–6.57 %/day/unit vs landed 6.08; duty 0.357
  vs 0.36; 8.70–8.86 units vs 9.4) and discloses its own 1.8%-in-8-minutes drift. **Taken.** Its
  **+2.91** is a ceiling-under-current-mix, not a realised loss — see §3.1. Its `k_work` is `None` in
  72.6% of samples, which biases the ceiling **low** (conservative).
- **B5**'s mechanism I verified myself by direct read: the depth-1 `os.scandir(slug.path)` is at
  `bin/claude-accounts:599`, and the false clause *"active subagents append to their own `.jsonl`
  **siblings**"* is at `:543`. **Taken.** Note B5 also **self-corrects the landed doc's own headline**:
  the 63%/89% blindness figures are wave-instant samples; over 1,200 replayed active minutes the
  deep/shallow ratio-of-means is **1.312**, median 1.00, and the 0-while-writing case is 0.5–2.4% of
  active minutes. It is a **burst** defect with a small sustained tail — which is exactly why its
  sustained price is +0.3, not +2.9.
- **B6**'s conclusion is robust to every uncertainty it names: two harnesses, **one** ChatGPT Plus
  meter (byte-identical `accountId` — the first credential-level proof), 11 pp per agent-hour across
  three convergent runs ⇒ **9.1 agent-hours/week = 0.054 sustained units = +0.6%.** **Taken.** Its
  Pro-multiplier figures are QUOTED and the verdict does not depend on them.

---

## 10 · THE ONE COMMAND, AND THE ONE DIFF

The measurement that changes the answer, and it costs nothing:

**§8.1** — regress observed `five_hour` utilization against transcript-derived local burn across
account-windows, controlling for Fable share. All inputs are on disk.

The change that should land first (§4 step 1), in one diff:

```
bin/claude-accounts:599   os.scandir(slug.path)  →  bounded os.walk(slug.path, followlinks=False),
                          skipping fn == "journal.jsonl"      # 158 on disk, parent-written
bin/claude-accounts:543   delete the false clause "append to their own .jsonl siblings"
bin/claude-accounts        F4b — partial abstain: return (counts, partial=True) and charge
                          max(partial_k_work, round(k × 0.42)); both are lower bounds, so max()
                          cannot over-refuse
accounts.json .router.KMAX      8 → 10          # 1.312 × 8 = 10.5, rounded down
+ the over-refusal tripwire (§7.1): log any `kmax-concurrency` exclusion whose own session_pct < 43%
```

Measured cost of the recursion: **0.045 s → 0.150 s** (3.2% of the 5.0 s `KWORK_BUDGET_S`).
Predicted exceedance: **0.69% → 1.94%**. Escape hatch: `KMAX` 12 (1.29%) or 14 (0.75%), one SSOT key.
