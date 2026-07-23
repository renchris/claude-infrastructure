# AXIS 5 — Autonomy spine, scheduling economics, auth lifecycle

> Frontier-discovery wave, 2026-07-20. Read-only investigation; all claims from live state or code this session.

## 1. The spine + economics model as-of-today

**Standing process architecture.** Twelve plists in `launchd/`, four of which are *not* loaded (`launchctl list` vs `launchd/*.plist`): `com.claude.boot-resume`, `com.claude.caffeinate-floor`, `com.claude.log-rotation`, `com.claude.power-policy-verify`. Live cadences: dispatcher `StartInterval 900` (`launchd/com.claude.dispatcher.plist`), discovery `3600` with `RunAtLoad false`, autonomy-sweep `300`, supervisor `KeepAlive` (pid 20915). Repo and installed copies are byte-identical (`diff` clean, `plutil -lint` OK) — no deploy drift on this layer.

Activation state is a **three-state ladder, not two**: BUILT → STAGED (`pending-activation/NN-*.sh`) → LOADED. 01/02/03 carry `.done` markers (reap-guard, dispatcher, discovery). But `boot-resume` (ead33e3) and `log-rotation` are built with **no staging script at all** — `grep -l` over `pending-activation/*.sh` returns nothing for either. They are orphans between rungs, invisible to the operator-facing activation flow. `04-page-channel` and `05-pmset-caffeinate` are staged and unfired.

Consequences, measured: `~/.claude/autonomy/idl.jsonl` is **41.2 MB**, last rotated `20260719T064448Z` (~25 h ago) → ~1.6 MB/h accrual against an hourly rotator that is not loaded. `~/.claude/autonomy/pages/` holds **353** files. `com.claude.lead-supervisor.plist` still contains `<key>CC_PAGE_TO</key><string></string>` — verbatim the a17-hostile finding of 2026-07-18, **unfixed two days later**; `PUSHOVER_TOKEN` is unset and absent from `~/.zshenv`. Every terminal branch of the autonomy lattice ("page a human") remains a dead letter, and the dead-letter queue has grown to 353.

Power: AC policy *is* applied (`pmset -g custom` → AC `sleep 0`, `displaysleep 0`), but the **verifier** that detects drift (`power-policy-verify`) is unloaded, so an OS-update reset would be silent. The 15 live `caffeinate` assertions are all 300-s session-coupled timeouts, not the `KeepAlive` floor — sleep-prevention is currently an *emergent property of live sessions*, not a floor. Uptime is 8 days, so G-P10-1/G-P16-1 remain untested in the wild; live check confirms them real: `/Library/LaunchDaemons` has **zero** claude jobs, FileVault **On**, `autoLoginUser` **unset** → any reboot halts the fleet at pre-boot lock indefinitely. `lr-reset-poller` is now loaded (G-P8-1 closed — delta vs p08-quota).

**Quota routing.** `bin/claude-accounts:492` `score_general = (w_rem / T) · SF · KF · CF`, where `T` = hours to weekly reset less margin, `SF` = 5 h-session soft factor, `KF = clamp(1 − k/KMAX, 0.1, 1)` (`:469-475`), `KMAX=8`. Dividing headroom by time-to-reset is a **use-it-or-lose-it max-sustainable-rate heuristic** and it is correct: an account whose window resets soonest scores highest. `bin/cc-wave-plan:135` `place_item` then minimizes `RLOAD[i] + RCOUNTS[i]` — **pure live-session-count balancing**, with rank used only as tie-break (`:140`, strict `<`). The urgency signal computed at such care in `score_general` is therefore **discarded at placement except as a healthy-set filter**. Separately, `_prev_snapshot` (`:592`) computes a real burn delta — and feeds it to the *display* only (`:814`), never the router. `MAX_PER_ACCT=2` (`cc-wave-plan:41`), `MAX_SPAWN=2` (`cc-dispatch:54`); bef587a bounds the wave to `MAX_SPAWN`, correctly closing the false-cliff.

**Live economics (cache 12 s old, `/tmp/claude-accounts-cache.json`):**

| acct | 5 h % | weekly % | Fable % | k |
|---|---|---|---|---|
| next | 23 | 18 | 8 | 5 |
| next4 | 11 | 12 | 0 | 3 |
| next3 | 9 | **53** | 6 | 2 |
| next2 | 7 | 14 | 10 | 2 |

Fleet weekly utilization **97/400 = 24.3 %**; 5 h mean 12.5 %; 12 live sessions. The last-good ledger (`~/.claude/logs/claude-accounts-lastgood.json`) holds only 3 accounts — **next2 has never been captured** — and all three stamps read `2026-07-19T12:15`, ~19.5 h stale, because `save_lastgood` writes only on a 200 with `weekly_pct` (`:448-456`) and the desk has been reading the 90-s cache.

**Value economics.** `bin/cc-value` is candid in its own header about attribution fidelity: commits join to a session only via `Session-Id:`/`Land-Session:` trailers; `claim.by` is a *shell pid* so tasks stay fleet-level; Max plans meter no dollars so spend is a quota proxy. Measured coverage over `origin/main -300`: **15 `Session-Id:`, 0 `Land-Session:`, 256 non-joining `Claude-Session:` URLs → 285/300 (95 %) unattributable.** The global CLAUDE.md *mandates* the `Claude-Session:` URL trailer — the org's commit convention structurally defeats its own value ledger. Telemetry (the join's left side) lives in `/tmp/cc-telemetry` (36 files), so even the 15 joinable commits lose their key on reboot.

**Demand.** Folding `backlog.jsonl` (465 items, 2026-07-18T23:23 → 07-20T07:18): the `07-19T01` hour contains 395 adds/389 dones — a bulk backfill. Excluding it, the trailing 24 h arrival rate is **34 items ≈ 1.4/h**. Dispatch capacity is 2 per 900 s = **8/h**. Claimed items run median 3.7 h (p90 11.6 h); the 399 unclaimed closures carry real landed-commit evidence — desk-driven work outside the claim protocol, not noise.

---

## 2. Frontier rows (ranked)

### F1 — The system optimizes the non-binding constraint; autonomous *demand generation* is the real generator-class problem

- **Evidence:** `docs/L3-L4-AUTONOMY-ROADMAP.md §4` asserts "4 Max accounts running 24/7 WILL hit weekly caps… the real ceiling is quota." Telemetry refutes it: 24.3 % fleet weekly, peak account 53 % with 36 h to reset, 12.5 % on 5 h windows; arrival 1.4 items/h against 8/h dispatch capacity and 4 accounts × 8 KMAX slots. `com.claude.discovery` — the only work *generator* — shows `runs = 0`, `RunAtLoad false`, `StartInterval 3600`; it has never executed. Every scheduling artifact on this axis (rank scoring, spread placement, cliff logic, wave sizing, Kimi overflow) allocates a resource sitting at three-quarters idle.
- **Why default-tier insufficient:** the default tier accepts the brief's premise and optimizes the named constraint — precisely the failure that produced the V1 wave drift. Recognizing that a carefully-engineered subsystem is *correctly built against a falsified premise* requires refusing the frame, not executing it. No amount of scheduling sophistication moves a 24 %-utilized fleet.
- **Solution shape:** invert the loop — treat *high-value work generation* as the scarce resource. What does a discovery layer that produces net-positive items at 8/h look like, and what bounds its false-positive rate before it becomes a churn engine? This dissolves ≥4 worklist items (sleep-window batching, dispatcher cadence tuning, wave sizing, quota-cliff avoidance) by making them moot or trivially satisfiable.
- **Confidence:** **High** on the measurement; **High** that this is the binding constraint; Medium on whether autonomous generation is tractable at all — which is exactly the frontier question.

### F2 — Value attribution is 95 % blind and the blindness is structural, not a coverage gap

- **Evidence:** 285/300 trunk commits unattributable; the mandated trailer format cannot join; the join's key store is in `/tmp`; `claim.by` is a shell pid (`cc-value` header); G-P8-7 was declared addressed by T-P8-5 (57d4833/299334d) but the *tool* shipped, not the *measurement* — the VALUE column renders over a 5 %-covered join.
- **Why default-tier insufficient:** the obvious fix ("add a joinable trailer") is a one-line change that the default tier will propose and that does not solve the problem. Real attribution must survive handoff lineages (session A researches → B implements → C lands), subagent fan-out (13 workers, one lead commit), and recycles that mint new session IDs mid-task. That is a distributed-causal-tracing problem over an identity substrate that is itself ephemeral and re-minted by design. Until it is solved, *every* value-steered routing proposal — including the value-per-token placement this axis was asked to evaluate — is unfalsifiable.
- **Solution shape:** a durable lineage identity (task-scoped, not session-scoped) that survives handoff/recycle, persisted outside `/tmp`, with a defined attribution semantics for fan-out (fractional? lead-attributed? abstain?). `cc-value`'s "abstain, never fabricate" law is the right instinct — the open question is what *can* be honestly attributed.
- **Confidence:** **High** (measured, not inferred).

### F3 — The billing plane is a numerator with no denominator, and its failure mode is a capability outage, not a quota outage

- **Evidence:** the usage endpoint yields `limits[].percent/resets_at` (`claude-accounts:pick`) plus `extra_usage.{is_enabled, used_credits}` (`:439-444`) — **a spend counter with no cap field anywhere in the payload**. On 2026-07-18T10:41Z the monthly-spend cap killed 4 agents and simultaneously starved the auto-mode permission classifier, producing a mode a17-hostile names **"stunned"**: pid alive, reads work, every actuator denied; the desk sat ~11 h until a human returned. `cc-classify:81-85` now greps for `monthly spend limit`; `lr-reset-poller.sh:105-140` opens a class-B packet. But `--rank` still routes onto accounts that cannot execute a turn, and `cc-route`'s cliff cannot trip because quota reads healthy everywhere.
- **Why default-tier insufficient:** the built response models this as *a limit class needing a packet*. It is structurally different: a resource plane **above** all four accounts, observable only as a *used* counter with no bound, whose exhaustion removes the substrate the recovery machinery itself runs on (Bash is classifier-mediated → `/limit-recover` becomes un-invokable). Correctly modeling it means reasoning about a resource you can only estimate and a recovery path that must not depend on the failed capability.
- **Solution shape:** infer the denominator from observed kill events + `used_credits` trajectory (a censored-observation estimation problem); plus a classifier-independent actuator path so recovery survives its own outage.
- **Confidence:** **High** on the blind spot; Medium on tractability of denominator inference from 1 observed event.

### F4 — Auth lifecycle: one genuine hard floor, one un-escalated retry loop

- **Evidence:** `heal()` (`claude-accounts:240-246`) gates on `k_live == 0` — correct, and irreducible: with CC running, CC owns token rotation (GH #54443). Failures that are not `invalid`/`revoked` leave `auth="stale"` and set only `heal_note` (`:401-402`) — **no backoff, no escalation, no packet**. Observed: `claude-accounts.log` records **11 consecutive `heal next2: FAIL — status code 400`** between 10:11 and 11:13 on 07-19, ~every 5–8 min, then silence; next2 later self-recovered. Nothing on a schedule triggers `account-relogin`; the only automatic path is `handoff-fire.sh:628-745` Phase-1 headless relogin, i.e. **only when a handoff happens to fire**. The hard floor is real: Phase 2 needs Dia consent + email code, and Graph covers 1 of 4 mailboxes (G-P8-4).
- **Why default-tier insufficient:** mostly it isn't — see §3. The genuinely frontier fragment is narrow: full auth autonomy has an *interactive-OAuth floor*, so the design question is what the system should do when an account is unrecoverable-without-a-human **and the human is absent by design** — degrade to N−1 permanently? That is a policy question about accepting irreducible capability loss, which the "page a human" lattice cannot express.
- **Confidence:** High on mechanism; Medium that the residual is frontier rather than policy.

---

## 3. NOT frontier — routing

- **Greedy vs. optimal scheduling at N=4 (sub-question 1): anti-frontier verdict, high confidence.** At 24 % utilization with arrival 1.4/h against 8/h capacity, no placement policy can outperform another by a measurable margin — there is no contention to resolve. Predictive burn modeling, value-per-token placement, and cliff-avoidance-under-uncertainty would all optimize slack. **Do not build.** Revisit only if fleet weekly sustains >70 % — add that as the trigger condition rather than the work.
- **Placement discards the use-it-or-lose-it signal** (`cc-wave-plan:140` balances on `k`, ignoring `w_rem/T` and the already-computed burn delta). Real defect, ~15-line fix (blend rank score into the placement key). But currently **economically free** — next3's stranding costs nothing because no demand goes unserved. → backlog, P2, default tier.
- **`k` (session count) as load proxy rather than burn rate.** next3 burned 38 %→53 % weekly on 2 sessions while next held 5 sessions at 18 % — session count is a ~10×-error proxy for cost. Same fix site as above. → backlog, P2.
- **Activation-ladder drift** (BUILT ≠ STAGED ≠ LOADED). `boot-resume` + `log-rotation` built with no staging script; `caffeinate-floor` + `power-policy-verify` staged, unloaded. Per the whack-a-mole memory rule this is a **systemic gap deserving an invariant**, not per-item clearing: an assertion that every `launchd/*.plist` is either loaded or has a staging script with a rationale. → backlog, default tier, one teammate.
- **Page channel dead (`CC_PAGE_TO=""`, Pushover unset, 353 queued).** Fully specified in `04-page-channel-activate.sh`; C10 operator-secret step. → **Operator Blocker Board with `--run`**, not research.
- **idl.jsonl 41 MB / hourly rotator unloaded; dispatcher logs to `/tmp`.** → backlog, trivial.
- **Kimi hedge** blocked on `claude-kimi set-key` (63fab19b9a27). Note the waste signal: three workers claimed and released it at ~10-min intervals (09:09/09:27/09:55) before the block was filed — operator-gated items should be `block`ed at file time, not left claimable. → small systemic fix, backlog.
- **Reboot survival (G-P10-1/G-P16-1):** confirmed live (0 LaunchDaemons, FileVault On, no auto-login). This is **decided-engineering awaiting an operator security call** (LaunchDaemon conversion vs. auto-login), not open design. → operator decision packet.
- **Morning digest:** `bin/cc-digest` exists with output for 07-18/07-19, but is scheduled nowhere and has produced nothing for 07-20. Tool built, cadence missing. → backlog, trivial. **Sleep-window batching: zero implementation hits** across `bin/`, `scripts/`, and the 24×7 plan, despite §4 naming it "the highest-leverage single move" — but under F1 it is leverage on the wrong constraint. Deprioritize rather than build.

---

## 4. Could not determine

- **Whether the fleet has *ever* approached the weekly frontier.** The last-good ledger is 19.5 h stale and holds 3 of 4 accounts; there is no historical quota time series. The 24 % figure is one instantaneous read plus one 19.5 h-old comparison. A weekly-percent trend log would settle F1 definitively — currently the strongest counter-argument to F1 is that this may be sampling a trough.
- **Whether `extra_usage.is_enabled` was true at the 07-18T10:41Z kill.** All four accounts read `credits_on: false, credits_used: 0.0` today. If credits were off then too, the monthly-spend cap is *not* the extra-usage budget and the F3 denominator-inference shape is wrong. `p08-quota.md` contains no `credits`/`extra_usage` mention. This is the single highest-value fact to recover for F3.
- **What closed the 399 unclaimed backlog items** — evidence strings show real landed commits, so they are genuine work, but the actor is unrecorded (a direct instance of F2).
- **Whether next2's 11×400 heal failures and its absence from the last-good ledger share a root cause.** Plausible (no 200 → no ledger write) but not confirmed that next2 has *never* had a successful sweep since the ledger's introduction.
