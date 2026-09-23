# B2: what consumes reso's `origin/main` after a land, and what reso's LAND/SHIP docs already decided

**Snapshot.** reso `origin/main` = `108be1a7b` (2026-09-23 00:04 CDT). `origin/release` = `7f84a45c2`, which is also the newest green stamp. All repo files were read with `git show origin/main:<path>`. Local state came from `~/.reso/{land.log,stamps,deploy.log,presubmit,qa}` and `~/Library/LaunchAgents/*.plist`. GitHub was read through the read-only `gh api` (repo, runs, hooks, branch protection, billing usage). **Nothing contacted Amplify or Fly.** Live Amplify/Path-F settings are taken from sibling sessions' `land-status.sh` readouts in transcripts (cited below).
Paths are repo-relative to reso unless prefixed. `L:` = `docs/infra-deploy/learnings.md`. `@cull` = `git show 6e3d03075^:<path>`: docs deleted by the W4 docs cull and not retained under their own names.

---

## 0. Findings that should shape the new design

1. **"Landing is free" holds for money but not for compute.**
   - **Money, confirmed.** Amplify `enableAutoBuild` on `main` = False and Path F `deployRef` = `refs/heads/release`, both from live-API `land-status.sh` readouts at 2026-09-22T19:14Z and 2026-09-23T01:16Z (transcripts `…wt-sec-w1d-livehrole/cba35be4…jsonl`, `…wt-pool-5/7a375ee2…jsonl`). Path F rejects main in code: `infrastructure/reso-deploy/server.ts:320-322` returns `skipped:'not-deploy-ref'`. The GitHub Actions billing API shows **net $0.00 every month Jun–Sep 2026**.
   - **Compute, not free.** A code land runs `tsc` (p50 42 s). It then runs the union suite under `cc-sem reso-land` (p50 156 s). Then it runs **the full `pnpm test:unit` a second time inside the push**, from the pre-push hook (`scripts/hooks/pre-push:130-150`). Measured over 7 days: tsc + suite + push per union round, p50 **359 s**, max 625 s (n=28).
2. **Nothing verifies trunk after a land. The verifier is in practice a step run by hand just before a deploy.**
   - No reso code or launchd job invokes `scripts/postland-verify.sh`. The `com.claude.postland-verify` plist runs `~/.claude/scripts/postland-verify.sh`, which is a symlink to **claude-infrastructure's** verifier. L:2551 says the same.
   - There were **3 stamps in 7 days against 77 exit-0 lands**. The newest stamp was 71 h old at 01:16Z. 33 of 34 deploys target a green stamp, and 17 of the newest 20 greens are deploy targets.
   - It verifies **only the tip at kick time** (`postland-verify.sh:553-556`). A second run is **skipped, not queued** (`:563`, exit 75). There is no bisect and no auto-revert. A red tip means the culprit is the whole range `(last_green, tip]`.
3. **W3b is not built, and as designed it would skip the hook's suite on almost no lands.**
   - No `presubmit` reference in `pre-push`. No `scripts/lib/presubmit-token.sh`. No W3b branch on any ref. The live canonical hook `~/.reso/land-tools/scripts/hooks/pre-push` is byte-identical to trunk (`d1967ade…`).
   - The design honours a token **only when `vitest.mode=="full"`** (L:2682, L:2677-2678). **46 of the 49 tokens on disk are `mode:"union"`**, because W3a made the union suite the default. So W3b as specified is inert on about 94% of code lands. The union-vs-full question has to be resolved first: W3b acceptance arm 5, data-blob importers.
4. **The recorded trigger for reconsidering a batch "train" plausibly fired. It is ranked lower than V2/V3's later rejection, but that rejection's premise has eroded.**
   - The 2026-07-03 design deferred an "ephemeral group-commit train" behind two triggers: "batch-green rate >0.7 AND coincident gated ships ≥2/burst" (@cull `docs/plans/SHIP_LANDING_CONCURRENCY_SCALE.md:253-263`).
   - My proxies over 7 days: suite-green 50/57 = **0.88**. Gated land attempts per active 30-min bucket: mean **2.42**, ≥2 in 12 of 24 buckets. 60% of gated attempts overlap another; peak 4 concurrent.
   - V2 rejected the queue because "with the gate off the land path there is nothing to batch" (L:1765-1769). W3a put a bounded suite back on the land path, plus the hook's duplicate full suite.
5. **The ruled W3 trip-wire has fired and nobody acted on it.**
   - The rule: "if the rolling p50 of `suite_s` over 50 code-lands exceeds 120 s, the land-time suite reverts to the always-run set" (L:2911).
   - Measured over the last 50 suite rounds: **p50 157 s** (union-only 156 s, n=47), load1 p50 108.
   - `scripts/ship-land.sh` and `pre-push` have not changed since `1c7fc60c3` (2026-09-14).
6. **A misclassified race.** 6 of the 15 exit-9 rows in 7 days are GitHub server-side CAS losses: `! [remote rejected] HEAD -> main (cannot lock ref 'refs/heads/main': is at X but expected Y)`. `ship-land.sh:890` treats only `*non-fast-forward*|*"fetch first"*|*"Updates were rejected"*` as a race, so these become terminal "rejected, NOT by a race". Their push windows were 156–266 s, which is the hook's suite running between the ref read and the ref update.
7. **Only the admin identity can land.** Live `main` protection requires 1 PR approval, with `enforce_admins=false`, **no required status checks**, `allow_force_pushes=true`, and linear history not required (`gh api …/branches/main/protection`). Direct pushes succeed only because the pusher is the admin. A bot or off-box lander would be refused unless protection changes. Nothing server-side stops a force-push. `.github/scripts/apply-branch-protection.sh:2-14` (audit check required, no force push, enforce admins) is **not** what is live.

---

## (a) Downstream of trunk

"Batch" below means a lander pushing k commits, possibly from several sessions, as one fast-forward.

| Consumer | Trigger | Cost | Behaviour on a red tip | How a batched or queued lander interacts | Evidence |
|---|---|---|---|---|---|
| **Amplify Oregon** (app `djnbdqpvc08g4`, branch `main`) | GitHub push webhook to AWS API Gateway `b9uarm8730.execute-api.us-west-2…`, on every push to every ref | **$0 per land**: auto-build off on `main`. It builds only on `deploy-release.sh`'s explicit `aws amplify start-job --commit-id` (`scripts/deploy-release.sh:230`) | None. Red is irrelevant until a deploy. The Amplify preBuild runs `pnpm test:unit` + `pnpm migrate` (`amplify.yml:37`), so a red *deploy target* fails the Oregon build | One webhook per push instead of per land: neutral. **Unverified:** Amplify auto-branch-creation is recorded nowhere in the repo, and `land-status.sh:174-177` asserts `main` only. A queue that pushes new `refs/heads/*` refs could create billed Amplify branches if that setting is on. Weak counter-evidence: about 200 remote branches exist and are pushed routinely | `gh api …/hooks`; `land-status.sh:170-184`; transcript readouts above; `docs/infra-deploy/chapter-release-lane.md` Rollback |
| **Fly Path F runner** `reso-deploy` (iad) | GitHub push webhook to `reso-deploy.fly.dev`, every push | ~$3/mo fixed (`min_machines_running=1`), nothing per land. HMAC-verify, then return 200 | None. Main is filtered out (`server.ts:320-322`). On a `release` push it coalesces N webhooks into 1 in-flight + 1 pending (`server.ts:36-41`) | Neutral for main. **Deploy-time hazard, unverified:** the fix making the runner derive the deployed sha from `release` rather than main's tip (`server.ts:50-56`, `792b37b72`) is "UNPROVEN until a real /deploy runs" (backlog `a5a935d25d96`, still open). V3 says the "green-stamp guarantee is UNVERIFIED for Fly" (L:3120). If the fix did not take, `/deploy` ships **whatever the trunk tip is**, for example a red batch tip, to LAX/SIN/IAD | `server.ts:36-60,258-322`; `chapter-release-lane.md` Leg 2 |
| **GH Actions `fabricated-menu.yml`** | `on: push` + `pull_request`, **every branch, unfiltered**; `concurrency: fabricated-menu-${ref}`, `cancel-in-progress: true` | 77 runs on main in 7 days (1 per land). p50 21.5 s, billed at 1-min granularity. **Net $0** across Jun–Sep (billing API) | Red check only. Nothing consumes it: no required status checks | One run per push, not per commit. Rapid pushes cancel the older in-flight run, so only the newest tip gets a verdict. Queue refs pushed to origin add runs | `.github/workflows/fabricated-menu.yml:14-31`; `gh run list` |
| **GH Actions `security-scan.yml` / `diagrams.yml`** | Path-filtered pushes: `package.json`/lockfile on main; `assets/diagrams/**` on any branch | 6 + 6 runs in about 9 days. Net $0 | Red check only; scans, ships nothing | Neutral | workflow headers; `chapter-release-lane.md` GH Actions |
| **Scheduled workflows** (`tenant-drift`, `soketi-image-cve-scan`) | Weekly cron, from the default branch | Negligible | Not per land. Both show `failure` in recent runs, unrelated to lands | Neutral | workflow headers |
| **`scripts/postland-verify.sh`** (reso) | **Nothing automatic.** Kicked by hand or by the `/deploy` flow (`deploy.md` exit-1 row; `deploy-release.sh:73-75`). `ship.md` step 4's "it also runs on its own" is false | Local CPU, about 10–16 min per run. Recent `run_s` 710–1064 s. Fresh worktree plus `pnpm install`, then typecheck → lint → test:unit → build → bundle-budget → design:gate, serially (`:390`), `nice -n 19`, `VITEST_MAX_FORKS=3` (`:449-451`). Inner `pnpm` calls take `cc-sem general` slots (`package.json:72,99,126`) | Stamps `~/.reso/stamps/<tree>.json` `red` for the **tip tree only**. Red is terminal, and "a RED stamp blocks its own replacement" (`stamped()` `:221-226`). CUT and HUNG re-run. **No auto-revert, no bisect, no backlog row, no notification.** Culprit granularity = the whole `(last_green, tip]` range. Contrast: the *infra* verifier of the same name does bisect and auto-revert | Coalesces by construction: verifies the tip at kick, skips if busy (exit 75), so intermediate tips of a batch are never stamped. Same as today; batching does not worsen it. A red batch pins newest-green to the pre-batch green until a later tip is green (W4b red-fence unbuilt) | `postland-verify.sh:1-35,221-226,390-493,553-566`; `~/Library/LaunchAgents/com.claude.postland-verify.plist`; stamps |
| **`scripts/deploy-release.sh` / `/deploy`** | **Operator only** (`deploy.md` `disable-model-invocation: true`). Manual cadence (D3, L:1720) | **The only money step:** 1 Amplify build + 1 Fly Path-F release (3 apps) per deploy. 34 deploys since 2026-08-03 | Deploys the **newest green-stamped ancestor** within `git rev-list --max-count=200 origin/main` (`:55-64`). A red tip is skipped silently and the batch is shorter. If no green is in the window, exit 1 REFUSED. It pushes `release` **before** `start-job` (`:203` then `:230`); W7 reorder unbuilt | Neutral to batching, which leaves the commit count unchanged. **The window risk grows with trunk commits:** 111 of 200 used right now (`7f84a45c2..origin/main`), about 20 commits/day (141 in 7 days, 0 merges). Past 200 without a new green it refuses even though `release` is green (W4b fix unbuilt, L:2751) | `deploy-release.sh:52-79,203-247`; `~/.reso/deploy.log` |
| **`scripts/land-status.sh`** | Readout at session close. Always `exit 0` (`:245`) | Seconds, plus 1 AWS call and 1 curl | Reports the **newest stamp's** age and verdict, not the tip's. Stranded alarm | **The stranded alarm counts commits that are not on trunk by patch-id AND not reachable from any remote ref** (`:40-105`). A local-only queue reads as STRANDED; a queue held on remote refs does not | `land-status.sh:1-245` |
| **Hook convergence (W2)** | Every land materialises `~/.reso/land-tools` from `origin/main:scripts` (`scripts/lib/land-tools.sh:76-156`) | Seconds | A broken hook that lands on trunk becomes the hook for every worktree on the next land (L:2735 "blast radius is the whole box") | A lander's push also runs the canonical hook, so a batch pays the hook's full suite **once per push rather than once per land**. The `[skip-cd]` guard reads only HEAD's message (`pre-push:70-90`) | `land-tools.sh`; `git config core.hooksPath` = `~/.reso/land-tools/scripts/hooks` |
| **Session-close / GC consumers** (`wrap-ledger.sh`, `worktree-gc.sh`) | Session self-close; launchd GC | Negligible | None | `UNLANDED = AHEAD>0 OR CHERRY` (claude-infra `scripts/wrap-ledger.sh:532-539`). A lander that lands **copies** (new shas) leaves each session at AHEAD>0, which reads UNLANDED and refuses self-close (V3 names the same trap for the lead merge loop, L:2742). GC tests landedness by patch-id against origin/main (`worktree-gc.sh:144-168`), so **squashing breaks reaping**. History is linear (0 merges in 7 days), and `content_verify` assumes a fast-forward (`ship-land.sh:840-850`) | cited lines |
| **`com.reso.qa-nightly`** | launchd 04:17 daily: `reset --hard origin/main` in `reso-qa-runner`, then headless `claude-latest -p "/qa-commits …"` + a semantic advisory over the watermark→trunk diff | Claude tokens (account `.claude-next`), a dev server. Fixed per day, not per land. It skips ranges over 5,000 lines | Report-only, never gates | Neutral. Squashed batches reduce its per-commit triage granularity | plist; `~/.reso/qa/nightly.log`; `scripts/qa-commits-nightly.ts` header |

**Verdict on "landing is free".** Money: **confirmed**. Two independent triggers are both off for `main` (live readouts). No Actions workflow deploys, and Actions net cost is $0. Compute: **refuted**. Each code land costs about 6 min of wall time across `tsc`, the union suite and the hook's full suite, all under `cc-sem`. That is exactly the "landing load congestion" the operator ruled must not grow (L:2569).

---

## (b) Roadmap: LAND/SHIP V3 status on origin/main

The plan is "DESIGNED 2026-09-11 … Nothing below is implemented" (L:2429-2432). Waves are at L:2797-3110; the dependency graph is at L:2472-2478.

| Item | Scope (short) | Status on `origin/main` | Evidence |
|---|---|---|---|
| **W0** measure only | land.log v3 + EXIT trap, cc-sem with no callers, load sampler, always-run set | **LANDED** 2026-09-13 | `973484ead`, `2084664eb`, `046acd818`; results table L:2818-2833 |
| **W1** fleet hygiene | `.gitignore`, prepare-cached, `.next` reap, pool identity | **LANDED** 2026-09-13 | `092b82ba0`, `f15d0ea19` |
| **W2** hook convergence | canonical `~/.reso/land-tools`, guarded per land (exits 20–26) | **LANDED** 2026-09-13; live | `66cf80dfe`; `ship-land.sh:279`; `core.hooksPath` = canonical; blob matches trunk |
| **W3a** admission + loop break | `LOAD_CEILING` gone, union suite under `cc-sem reso-land`, 124/137 → exit 12, token writer | **LANDED** 2026-09-14 | `3f1b7a26e`, `d07478ff8`, `1c7fc60c3`, `e8b3754a6`; L:2990 |
| W3 suite-scope trip-wire | p50 `suite_s` over 50 code-lands > 120 s → always-run set only | **FIRED, not acted on** (157 s) | L:2911; land.log v3, last 50 suite rounds |
| **W3b** hook token skip | `pre-push` stdin read + `presubmit_token_covers_push`, skip only on green ∧ full | **NOT BUILT**: no helper, no hook edit, no branch. As designed it covers about 6% of code lands (union tokens 46/49) | `pre-push` has 0 `presubmit` hits; `presubmit-token.sh` absent; L:3009-3026, L:2682 |
| **W4a** verifier scheduler + stamp v2 | `gl.reso.postland-verify` plist (600 s + wake file), `stamp-read.sh`, toolchain memo, battery arm removed | **NOT BUILT**: no plist, no `stamp-read.sh`, battery refusal still at `gate-boot-preflight.sh:65-68` despite the 2026-09-13 ruling | LaunchAgents; L:3028-3047 |
| **W4b** culprit bisect, red-fence, known-red exclusion, deploy window | bisect ≤⌈log₂k⌉, verify `culprit^`, `trunk-red.json`, window walks to `release` | **NOT BUILT**: `deploy-release.sh:57` is still `--max-count=200` | L:3049-3061 |
| **W5** demand shaping | delete the 3 close-mandate arms, drop the lead merge loop | **NOT DONE**: arms still at reso `CLAUDE.md:556-559`. Blocked by W4a by design | L:3063-3073 |
| **W6** design-gate surgery | sleeps → polls, Playwright pinned exactly, VRT attribution floor | **NOT DONE**: 3 × `waitForTimeout` remain; `@playwright/test` `^1.58.2` (`package.json:189`) | L:3075-3086 |
| **W7** deploy path | Amplify start-job → SUCCEED → push `release`; `deploy.log` writer; `/health` derivation | **NOT DONE**: push precedes start-job (`:203`/`:230`); writer `|| echo 0` (`:209`) still yields `0\n0` (json parses 7 of 34 rows); no `derivation` field | L:3088-3098 |
| **W8** infra lane | cc-sem in claude-infra, retire `CC_GATE_MAX_LOAD` | **NOT DONE**: 0 `cc-sem` refs in infra `scripts/`; `CC_GATE_MAX_LOAD` in infra `ship-land.sh:115-192` | this repo |
| W10 (candidate) rollback | one command back to a named green sha | not specified | L:3118 |
| §6(d) Path F derivation | confirm the live runner derives from `release` | **UNVERIFIED** (backlog `a5a935d25d96` open) | L:3120 |

**Declared targets vs measured (7 days to 2026-09-23 05:10Z)**

| Target | Source | Measured | Status |
|---|---|---|---|
| Land p50 ≤ 60 s, p99 ≤ 5 min, ≥95% first-attempt success at 30+ writers | V2 R1, L:1409-1410 | exit-0 attempt wall p50 56 s, p90 476 s, max 1,728 s; first-attempt success 69/108 = 64%; lead's per-unit p95 2,887 s | **fails** p99 and first-attempt |
| code-land p50 ≤ 120 s | W3a acceptance, L:2980 | union round tsc + suite + push p50 359 s; `suite_s` p50 156 s | **fails** |
| `rows(rounds=5 ∧ push_rc∈{124,137}) = 0` | W3a, L:2976-2979 | 3 × push_rc 124, each terminal exit 12 in round 1; 1 exit 8 | **passes**: the five-round loop is gone |
| newest-green ≤ 30 min (about 102 runs/day, 67% duty on one slot) | V3 §3.5 / §1.5, L:2552, L:2693 | 3 stamps in 7 days; newest 71 h old; 111 commits undeployed behind the last green | **fails** (W4a unbuilt) |
| ≥ 8 stamps/day for 3 days (gate for W5) | L:3044-3047 | about 0.4/day | not met |
| `deploy.log` parseable rows == rows | W7, L:3093 | 7 of 34 JSON-parseable | **fails** |

---

## (c) Decisions a merge-queue or central-lander proposal must respect or overturn

Quotes are verbatim.

**C1. Landing is synchronous; no queue, no off-box lander.** V3 §2 invariant 4 (L:2565):
> "**Landing stays free, continuous, agent-driven and SYNCHRONOUS.** No merge queue, no PR lane, no off-box lander. A land either puts the session's bytes on `origin/main` or it does not happen — which is why the semaphore's shed polarity is *refuse*, never *land unproven*"

Reason: correctness of the close protocol. A session cannot close on bytes that are not on trunk (wrap-ledger rung).
**What a proposal must show:** that a session still gets a synchronous yes/no, with its HEAD reachable from trunk, and that nothing leaves it holding an unlanded sha.

**C2. A merge queue as the land mechanism is rejected, twice.**
- V2 §8 (L:1765-1769): "Solves throughput but keeps latency ≥ gate-time (fails R1), and at reso's measured coincidence (~0.12 gated ships per session per burst) the modal batch is a single rider. The prior design already deferred it behind telemetry triggers; v2 removes its reason to exist — with the gate off the land path there is nothing to batch."
- V3 §8, re-affirmed (L:3144): "merge queue / land train / bors / GitHub Merge Queue **as the land mechanism** (latency ≥ gate time; modal batch one rider; GHEC-only for private repos; Mergify's free tier is PR-shaped)".

**What has changed since:**
- The gate is partly back on the land path (W3a union suite, p50 156 s) plus the hook's duplicate full suite.
- Coincidence is no longer ~0.12: 2.42 gated attempts per active 30-min bucket.
- Evidence to overturn "modal batch one rider" now exists. "Latency ≥ gate time" still binds any design that gates the batch.

**C3. The deferred ephemeral train: the closest prior proposal, parked behind triggers.** 2026-07-03 Rank 7 (@cull `SHIP_LANDING_CONCURRENCY_SCALE.md:253-263`):
> "Only after ranks 1-5 land AND telemetry shows batch-green rate >0.7 AND coincident gated ships ≥2/burst: the land-lock **winner** (leadership re-elects per landing — **no daemon**) drains `.req` files, cherry-picks frozen shas into a scratch worktree, ejects any drizzle/conflicting/sha-drifted branch to solo, runs ONE gate on the union, pushes ONE atomic FF, and on ANY failure **rejects the whole train with no retry**"

Its conditions: static N ≤ 3; migrations always land solo; whole-train reject, where "the failing solo gate IS the attribution"; the `.req` lifecycle (enqueue / ack / dead-pid GC / sha-drift) is a "required deliverable". Named risk: "a flake strands N riders — the exact 3am mode that killed the daemon". This was never ratified. V2 later superseded it, calling it "deferred behind telemetry triggers" (L:1767-1769). By my proxies (§0 item 4) the triggers now appear met. This is **unverified as a formal measurement**: "burst" was never defined in code.

**C4. A persistent lander daemon was killed twice.**
- 2026-07-02 (@cull `docs/research/SHIP_LANDING_100P_2026-07-02.md:219-221`): "Landing daemon + durable queue + integration worktree (L1/L5/L6: a wedged train blocks all sessions — worst 3am failure; the lock captures the win at ~5% of the code)".
- 2026-07-03 §3(a) (@cull `…CONCURRENCY_SCALE.md:269`): "the persistent **daemon stays killed** (today's live 4507s wedge proves the 3am mode is current)".

The same roadmap also killed:
- "speculative rebase chains (industry/R1: speculative *rebase* re-imports the F1 journal trap; elastic fan-out needs cloud CI this box lacks)" (@cull `…100P…:225-226`);
- "conflict-class parallel lanes (industry/R5: parallel gate capacity is exactly what this machine must not use)" (`:229-230`);
- the adaptive batch controller and CQ-style bisection.

Its Tier-2 fallback: "Minimal batching/train: only if `~/.reso/land.log` shows lock-wait p95 > ~15 min at real burst" (`:206-209`).

**C5. Shed semantics.** V3 §3.2 (L:2623):
> "Never run-anyway (D3/D5) — a soft bound does not bound the box under exactly the burst it exists for. Never land-unproven (D2/D4) — that manufactures a landed sha nothing verified"

L:3148-3149 re-rejects both. A lander that lands a batch on a partial or unadmitted gate violates this.

**C6. Keep verdict-only work off the land path.** V3 §2 invariant 8 (L:2569):
> "**Nothing that exists only to produce a deploy verdict runs on the land path** — operator ruling 2026-09-13 (*"reduce anything if anything adds to the landing load congestion; otherwise keep as recommended"*)."

**C7. $0 on gating.** V3 §2 invariant 1 (L:2562): "**Zero additional spend on gating.** Actions minutes, hosted VRT, paid runners: CLOSED. Moving verification off-box is not vetoed; spending on it is." The operator ruled $0 on 2026-09-13 (L:3116), which rejects the $35–75/mo Fly verifier. Off-box CI as the verdict owner is also rejected: the design:gate goldens are "calibrated on this machine's renderer" (L:1793-1797).

**C8. No auto-revert in reso.**
- V2 §8 (L:1801-1807): "**Deferred, not adopted.** In claude-infrastructure a revert is cheap and local; in reso a revert inside a migration range is explicitly banned (journal-vs-fleet drift wedges every subsequent deploy)".
- V3 §3.5 (L:2715): "**No auto-revert** (banned inside a migration range)".

The substitute is designed but unbuilt (W4b): bisect, then verify `culprit^`, then `trunk-red.json`, then **known-red exclusion**. Without that exclusion, "the refuse-on-statics-red polarity lets one bad trunk commit stall every land on the box".

**C9. The verifier batches by design; batching cannot buy freshness.**
- L:2719: "A run verifies the **tip at start**; every commit in `(last_green, tip]` inherits the verdict as a batch. Quiescence is **not** the trigger".
- L:2552: "Batch policy cannot help — the largest batch this repo has ever offered at that cadence is **3.13 commits**".

**C10. Migrations serialize.**
- V2 R5 (L:1417-1422): `ship-reconcile.sh` runs in full on **every** CAS round, and there is "No 'fast final rebase' shortcut".
- V3 invariant 5 (L:2566): "the drizzle mutex stays (the one genuine serialization need, 2.4% of lands)".
- Deploy re-asserts DROP confirmation by basename (`deploy-release.sh:125-195`).

A batch lander must eject drizzle-touching members to solo, as C3 already required.

**C11. Hook polarity.**
- L:2657: the hook suite is "**not deleted** … it is **gated on a token**, so a bare `git push` outside ship-land still gets the full suite".
- L:3156 rejects "Deleting the suite from `pre-push` outright".
- L:2682: the token is honoured only for `mode=="full"`.

**C12. The deploy model is ratified.** V2 §5.5 (L:1718-1720):
- D1: the release ref is the deploy trigger.
- D2: auto-landing is adopted.
- D3: "**Deploy cadence = manual `/deploy` only.** No scheduled or on-green auto-deploy."

V3 invariant 3 (L:2564) keeps `/deploy` operator-only. `deploy-release.sh:212-222` rejects a watched Amplify `release` branch because 62 SecureStrings are branch-scoped.

**C13. Only one cache.** V2 §8 (L:1789) rejects a "Content-addressed gate cache / OCC skip token" as a new mechanism: the tree-keyed stamp is "the only cache v2 needs". V3 allows *extending* it (L:3144). PRs + review are out of scope (L:1770).

**C14. Per-teammate lands.** L:2742: "`wrap-ledger.sh:502-509` computes `UNLANDED = AHEAD>0 **OR** CHERRY` … every lead-merged teammate stays `UNLANDED=1` forever". This makes "per-teammate lands a hard requirement of constraint 4". A central lander that lands cherry-picked copies hits the same wall.

---

## What a batched or queued lander must handle

This section is derived from the evidence above.

1. **Identity and protection.** It pushes as the admin, or `main` protection changes (§0 item 7). It never force-pushes: `allow_force_pushes=true` means nothing server-side catches that.
2. **CAS classification.** Treat `cannot lock ref … expected` as a lost race, not a terminal rejection (`ship-land.sh:890` gap).
3. **Session closure.** Each session's HEAD must end up reachable from trunk, or `wrap-ledger`/GC semantics must change. Preserve patch-ids: no squash.
4. **Queue durability.** Hold the queue on remote refs, or `land-status` reports it as stranded. First verify Amplify auto-branch-creation (unverified) before any design pushes new `refs/heads/*`.
5. **Duplicate suite.** Resolve the hook's full-suite duplicate first: W3b as designed does not do it for union tokens. A batch pays the hook's suite once per push, which is the one saving batching delivers for free.
6. **Red batches.** A red batch tip currently gives whole-range culprit granularity and no alert. Known-red exclusion and red-fence are prerequisites (C8), or one red batch stalls every lander.
7. **Deploy window.** It is 200 commits (`deploy-release.sh:57`), 56% used now.

## Unverified or open items

- **Amplify auto-branch-creation:** unknown. Not recorded in the repo; I was not allowed to query Amplify.
- **Path F sha derivation on the live runner:** unproven (backlog `a5a935d25d96`).
- **The 6 hook-suite failures after a green union suite (7 days):** real regressions the union selection missed, or load flakes? Undecidable, because the hook writes no log (L:2508).
- **C3 trigger proxies:** my own operationalisation. "Coincident per burst" was never defined in code.
- **Actions billing:** the per-repo September quantity (7 min) contradicts 77+ runs. Only the net $0 figure is reliable.
- **Stale docs:**
  - `docs/infra-deploy/chapter-gates.md:85`: verifier "runs once per trunk tip".
  - `ship.md` step 4: "it also runs on its own".
  - `chapter-release-lane.md`: "Four active workflows" (`fabricated-menu` was added 2026-09-05).
  - `pre-push:123` comment: "~3s, 209 cases".
  - `postland-verify.sh:491-493`: writes a `gate-green` cursor that no reso script reads.
- **Not examined:** `ship-reconcile.sh` internals. `plans/001-land-arch2-fix-family.md` is retired (`plans/README.md:25`) and is not a landing-architecture document.
