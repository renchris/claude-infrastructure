# P11 — ORCHESTRATE: the runtime, its cost, and how it fails

**Stage owner:** `bin/dr` — one binary, one process tree, no daemon, no MCP server.
**Consumers:** a Claude Code agent (interactive), `pnpm design:gate` (CI), a human at a shell.
**Upstream:** nothing. ORCHESTRATE is the entry point; every other stage is a subcommand of it.
**Downstream:** everything — P1 CAPTURE, P3 EXTRACT, P4 SCREEN, P5 ROUTE, P6 PROMPT, P7 ARBITRATE,
P8 ATTRIBUTE. This stage owns the *composition*, never a finding.

**One-sentence thesis.** A design review is a resumable DAG over `(route × viewport × theme)` cells
whose only expensive edge is a model call; the orchestrator's whole job is to make every cheap edge
cacheable, every expensive edge accountable, and every failure name the cell it happened in — so that
a run that dies at cell 400 of 630 resumes at 400 and not at 0.

---

## 0. CONTRACT

### 0.1 Invocation

```
dr review  <app>              # the whole thing: capture → screen → route → judge → arbitrate → attribute
   [--routes <glob|@file|auto>]      default: auto  (see §9 — diff-affected set)
   [--viewports 1440x900,768x1024,390x844]
   [--themes auto|light|dark|light,dark]
   [--run <dir>]                     default: .dr/runs/<runid>; existing dir ⇒ RESUME
   [--since <git-ref>]               affected-set base; default: merge-base with origin/main
   [--max-routes 12]                 §9.4 fan-out cap; exceeding it marks coverage:"sampled"
   [--judge on|off]                  default on; `off` ⇒ deterministic-only, zero dollars
   [--judge-budget-usd 3.00]         hard stop; §7.4
   [--concurrency 4]                 browser workers; §4
   [--call-concurrency 6]            in-flight model calls; §4
   [--profile landing|management|web] default: inferred from <app>
   [--base-url <url>]                default: scripts/worktree-dev-port.sh, then :3000
   [--gate]                          CI mode; §10. Mutually exclusive with --judge on.
   [--json]                          machine output on stdout; the agent-facing mode

dr capture|extract|screen|route|judge|arbitrate|attribute   # one stage, over an existing --run dir
dr affected --since <ref> [--json]   # print the affected route set and exit; no browser
dr replay   --run <dir> --stage judge   # re-run one stage on stored inputs, no browser, no capture
dr control  <app>                    # re-render the clean control and assert the FP budget (§10.2)
dr cost     --run <dir>              # the token/dollar ledger for a completed or partial run
```

Every subcommand takes `--run <dir>` and is idempotent over it. `dr review` is exactly the composition
of the others; there is no code path reachable only through `review`. **A stage that cannot be run
alone against stored inputs cannot be debugged**, and a pipeline whose stage 6 can only be exercised
by re-photographing the page has made its own model calls unreproducible.

### 0.2 Inputs

| Input | Source | Required | Failure if absent |
|---|---|---|---|
| `<app>` | one of `reso-landing-app`, `reso-management-app`, `reso-web-app` | yes | exit 64 USAGE |
| a reachable dev server | `--base-url`, else `scripts/worktree-dev-port.sh` (management), else `:3000` | yes | exit 69 UNAVAILABLE, after a 600 s boot window (§6.1) |
| `<app>/.dr.toml` | repo-committed profile: route allowlist, token file paths, viewport set, auth state file | no | defaults; `profile` falls back to path-inferred |
| resolved token file | Panda `styled-system/tokens/index.mjs` **and** Tailwind 4 `@theme` block (management ships both — measured) | no | P4 K-family rules return INDETERMINATE, never PASS |
| git worktree | `git rev-parse --show-toplevel` | for `--routes auto` only | `auto` degrades to the full route set with `coverage:"full-fallback"` |

### 0.3 Outputs

One run directory, and one line of JSON on stdout. Nothing is written outside `--run`, ever —
including temp files. The directory is the API.

```
.dr/runs/2026-08-26T18-04-11Z_a91f/
  run.json                 # the manifest: app, git sha, base-url, flags, resolved route set, coverage
  journal.jsonl            # append-only step ledger — the resume substrate (§3.2)
  cells/<route-slug>/<vp>.<theme>/
      manifest.json  masters/  read/  crops/  facts/     # P1 artifacts
      facts.json  layout.json                             # P3
      screen.json  crops/                                 # P4
      route-plan.json  clip/                              # P5
      judge/<call-id>.{request.json,response.json}        # P6 — request stored, so `replay` is exact
      arbitrated/report.json  report.md                   # P7
      attribution.json                                    # P8
  report.json              # run-level roll-up: every finding, every cell, coverage, census
  report.md                # the human/agent artifact — the ONE file a session is told to read
  cost.json                # the token + dollar ledger, per call (§7)
  control/                 # the clean-control run for this app, if `dr control` ran (§10.2)
```

`report.json` header, which is a **closed census** — every cell is in exactly one bucket:

```json
{ "schema": "dr/1", "ok": true, "app": "reso-management-app", "git_sha": "bc77b22a9",
  "coverage": "affected" ,
  "cells": { "planned": 27, "captured": 27, "screened": 27, "judged": 19,
             "skipped_budget": 8, "failed": 0 },
  "findings": { "asserted": 11, "advisory": 24, "abstained": 6 },
  "cost": { "input_tokens": 359640, "output_tokens": 57780, "usd": 3.24 },
  "wall_ms": 1_284_500 }
```

`coverage` is one of `full` · `affected` · `sampled` · `full-fallback`, and it is the field that
stops a partial run from reading as a complete one. There is no default; it is computed in §9.

### 0.4 Exit codes — the whole contract, and the one rule that governs it

🚨 **No model output may move the exit code. Ever.** The June 2026 ruling ("taste stays human, gates
adjudicate correctness/coverage only") is enforced here mechanically rather than by convention: the
process that computes the exit code (`dr`'s top frame) **never reads `judge/` or the `advisory` rung
of `arbitrated/report.json`**. It reads the journal, P4's `census`, and P7's `asserted` set. A future
edit that wires a judgement finding into an exit code has to delete that isolation to do it, which is
a reviewable diff rather than a drift.

| Exit | Name | Meaning | Who caused it | Retry safe? |
|---|---|---|---|---|
| `0` | OK | The run completed its planned cells. **Findings may exist — this is not a quality verdict.** | — | n/a |
| `1` | GATE | `--gate` only, and ≥1 `asserted` + `severity:high` correctness finding (contrast, target size, overflow, token conformance). Never a judgement finding. | the app | no — fix the page |
| `2` | PARTIAL | Some cells completed, some failed; `report.json` is written with a truthful `cells.failed`. **The most common non-zero code and the one to design for.** | mixed | yes — `dr review --run <dir>` resumes |
| `64` | USAGE | Bad flags; `--gate` with `--judge on`; unknown app. | the caller | no |
| `69` | UNAVAILABLE | Dev server never became reachable inside the boot window (§6.1); or `--base-url` 4xx/5xx on every route. | the environment | yes, after starting the server |
| `70` | INTERNAL | An orchestrator bug: journal corruption, a stage exiting with a code not in its own contract. | us | no — file it |
| `73` | CANTCREAT | `--run` exists and is not a `dr` run dir, or is unwritable. | the caller | no |
| `75` | TEMPFAIL | Model API 429/5xx exhausted its retry ladder (§8.3), **or `--judge-budget-usd` was reached**. Deterministic results are complete and written; the judge layer is short. | the API / the budget | yes — `dr review --run <dir> --judge-budget-usd <more>` |
| `78` | CONFIG | Control run missing or stale for a `--gate` invocation (§10.2). Fail closed: no report. | the repo | no |

**`2` and `75` are the honest states and they are separate on purpose.** `2` means *pixels are
missing*; `75` means *pixels are complete and judgement is short*. Collapsing them would let a run
with 27 clean captures and zero model calls read the same as a run where the browser died — and the
first is a usable review while the second is nothing at all.

**Every non-zero code writes `report.json`** except `73` and `78`. A run that dies without a report
is a run whose failure cannot be attributed, and §3.2's journal exists precisely so the report can be
reconstructed from disk after a `SIGKILL`.

---

## 1. What ORCHESTRATE cannot do, and who owns it

| Cannot | Owner |
|---|---|
| Decide whether a frame is trustworthy (DPR pinned, clamp-safe, two identical rasters) | **P1 CAPTURE** — orchestrator only propagates its exit 11/12/20 into cell state |
| Decide what is a defect | P4 SCREEN (numbers), P6 PROMPT (judgement), P7 ARBITRATE (which rung) |
| Decide which crop to take | P2 DECOMPOSE / P5 ROUTE |
| Decide which source file to edit | P8 ATTRIBUTE |
| Know whether a route is *worth* reviewing | the repo's `.dr.toml` allowlist — a human artifact, versioned |
| Know the semantic blast radius of a CSS-token edit | **nothing does.** §9.5 names this as the residual and how the run declares it |

The orchestrator's only judgement is **scheduling**, and its only assertions are about *its own*
completeness. When it says `coverage: "affected"` it is claiming something about the module graph, not
about the design.

---

## 2. One binary — reconciling the sibling specs' names

The eight upstream specs each name their own entry point: `design-capture` (P1), `cv-decompose` (P2),
`design-perceive extract` (P3), `screen` (P4), `dr prompt build` (P6). **They are one binary with
subcommands, and the names above become the subcommand.** This is not cosmetic. Three of the stages
hard-assert that they received *the same browser pass* as their sibling (P3 §1.1 I1 exits `4` on a
closed CDP session; P4 exits `2` on a `capturedAt` mismatch), and a `CDPSession` cannot be handed
between OS processes. **P1+P3 must run in one process — so the binary boundary is fixed by the CDP
handle, not by taste.**

| Sibling name | Becomes | Process | Why |
|---|---|---|---|
| `design-capture` | `dr capture` | shares a process with `extract` | one Playwright context, one CDP session, one frame |
| `design-perceive extract` | `dr extract` | ″ | P3 §1.1: same frame or exit 4 |
| `screen` | `dr screen` | separate; reads files only | pure NumPy + rules; parallel-safe, no browser |
| `cv-decompose` / ROUTE | `dr route` | separate | pure planning over JSON |
| `dr prompt build` + the API call | `dr judge` | separate; network only | the only stage that spends money |
| ARBITRATE / ATTRIBUTE | `dr arbitrate`, `dr attribute` | separate; `attribute` needs a **dev-build** server | P8 §1: prod build caps confidence at LOW |

`dr capture` and `dr extract` are therefore *phases* of one subprocess and the CLI exposes both names
for debugging, with `dr extract --run <dir>` alone refusing with exit `70` and the message
`extract cannot re-enter a closed capture; run 'dr capture --run <dir>' which re-photographs`.
Re-photographing is legitimate; *pretending* the old frame is still live is not.

---

## 3. Artifact layout and resumability

### 3.1 The cell is the unit, and it is content-addressed

A **cell** is `(route, viewport, theme, state)`. Its slug is
`<route-slug>/<w>x<h>.<theme>[.<state>]` — e.g. `admin-team/1440x900.dark`. Everything about that
cell lives under one directory and nothing about it lives anywhere else.

The cell also carries a **key**, and the key is what makes resume and cache correct:

```
cell_key = sha256(
    git_sha_of_first_party_affecting_modules   # §9.2 reverse index, sorted
  + route_path + viewport + theme + state_name
  + dr_version + capture_env_sha                # playwright ver, chromium build, dpr, flags
)
```

`capture_env_sha` folds in every determinism knob P1 already pins (`--force-device-scale-factor`,
colour profile, LCD-text off, reduced motion, fonts-ready, frozen clock
`RESO_TEST_NOW_MS=1781654400000` where the app defines one). **A knob that changes the render must
change the key**, or a resume silently mixes two instruments — which is the phantom-offset defect
arriving through the scheduler instead of through the browser.

### 3.2 The journal is the resume substrate — not directory scanning

`journal.jsonl`, append-only, `fsync` after every record, one record per stage-attempt:

```jsonc
{"t":"2026-08-26T18:05:02.114Z","cell":"admin-team/1440x900.dark","stage":"capture",
 "key":"9f3c…","attempt":1,"status":"ok","ms":3412,"exit":0,"artifacts":["masters/…png"]}
{"t":"…","cell":"admin-team/1440x900.dark","stage":"judge","call":"C1","status":"ok",
 "in_tok":5612,"out_tok":903,"usd":0.0506,"model":"claude-opus-5","prompt_sha":"2ab9…"}
{"t":"…","cell":"reports/1440x900.light","stage":"capture","attempt":3,"status":"fail",
 "exit":11,"why":"UNSTABLE: 3 attempts, no two identical rasters"}
```

**Resume = replay the journal, not `ls` the directory.** A directory listing cannot distinguish *"P4
wrote `screen.json` and succeeded"* from *"P4 wrote `screen.json` and then crashed writing
`crops/`"*, and the second must re-run. The journal's `status:"ok"` record is written **after** the
stage's last `fsync`, so an `ok` record is a claim about a *completed* write. This is
`claimed-outcome-vs-checked-outcome` applied to a scheduler: the artifact's existence is not the
verdict, the ledger entry is.

On `dr review --run <existing>`:

1. Replay `journal.jsonl` → `(cell, stage) → last status`.
2. Recompute every `cell_key` against **today's** git sha and env. Any cell whose key changed is
   `stale` and re-runs from `capture`. *(This is what makes resume-after-an-edit correct rather than
   convenient: you cannot resume half a review across a code change.)*
3. Re-run every `(cell, stage)` that is not `ok`, in dependency order.
4. `judge` records are keyed additionally on `prompt_sha`; editing a prompt template invalidates
   judge calls **without** invalidating captures. This is the single highest-value resume path —
   §5.3 shows it costs zero browser seconds.

`dr replay --run <dir> --stage judge` is step 4 forced. Because P6 stores `request.json` verbatim,
replay is byte-exact input with a new model call — the only way to measure prompt changes against a
fixed frame, which the ~30–37% order-invariant-consistency ceiling makes mandatory rather than nice.

---

## 4. What is parallel, what is serial, and why

### 4.1 The four lanes

| Lane | Unit | Default width | Bound by | Why not wider |
|---|---|---|---|---|
| **A. Warm-up** | route | `--concurrency` | `next dev` compile | §4.3 — this is the real cost, and it is one-shot per route |
| **B. capture+extract** | cell | `--concurrency` = 4 | RAM + the app's own DB | §4.2 |
| **C. screen** | cell | `min(nproc, 8)` | CPU (NumPy, single-core per cell) | embarrassingly parallel; pure file-in/file-out |
| **D. route→judge→arbitrate** | call | `--call-concurrency` = 6 | API rate limit and the token budget | §4.4 |

Lane C is fully parallel and lane B is not, and the reason is not the browser.

### 4.2 Browser concurrency is capped by the *app*, not by Chromium

`reso-management-app`'s own Playwright config pins `--workers=1` for its visual-regression project,
and its comment says why: gate specs mutate a **shared local sqlite `app.db`** per entry, and
concurrent writers produced `SQLITE_BUSY` plus one seed's `DELETE` wiping another file's expected
rows — five observed race failures including seed-free readers. **Any orchestrator that opens four
browsers against one dev server inherits that exact bug.**

So the rule is per-app and comes from the app, not from us:

```toml
# reso-management-app/.dr.toml
concurrency = 1            # shared sqlite; see e2e/playwright.config.ts
mutates_shared_state = true
frozen_clock_env = { RESO_TEST_NOW_MS = "1781654400000" }

# reso-landing-app/.dr.toml
concurrency = 4            # static marketing pages, no server state

# reso-web-app/.dr.toml
concurrency = 4            # pages router, 17 pages, no server writes
```

`concurrency = 1` with `mutates_shared_state = true` is not negotiable by a CLI flag: passing
`--concurrency 4` there is exit `64` with the message naming the `.dr.toml` line. A flag that can
override a correctness constraint is a flag that will.

**The escape hatch, and it is the right one:** when the review is read-only (it always is — we
navigate and photograph, we never submit forms), point N workers at N *dev servers* rather than N
tabs of one. `scripts/worktree-dev-port.sh` already assigns a free port per worktree, so
`dr review --shard 2/4` on four worktrees is the supported horizontal scale, and each shard writes
its own run dir which `dr merge` folds. UNVERIFIED that four concurrent `next dev` instances of a
123-route app fit in 64 GB — one probe settles it: boot four, hit one route on each, read RSS.

### 4.3 The dominant serial cost is the cold `next dev` compile, and it is one-shot

The app's own config raised its `webServer.timeout` from 180 s to **600 s** with the comment *"cold
dev-compile is ~3–4 min"* on a large app under concurrent load, noting that a prior `pnpm build`
pre-warm does **not** accelerate the dev compile. `next dev` compiles per route on first request.

This inverts the naive schedule. The right order is **warm every route first, then review**:

```
Lane A:  for route in affected:  GET <base>/<route>  (HEAD is not enough — no render, no compile)
         → parallel to --concurrency, no capture, discard the body, record compile_ms
Lane B:  only then capture, in cell order
```

Warming is safe to parallelise beyond the DB cap because it does not photograph and does not assert;
a `SQLITE_BUSY` during warm-up is a retry, not a corrupted frame. Measured consequence: on a
27-cell affected run over 9 routes, warm-up moves ~9 × 15 s of compile off the critical path of the
capture lane and into a 4-wide phase, and — the part that matters — **it takes the compile out of the
capture's stability check.** P1 exits `11 UNSTABLE` when three attempts never produce two identical
rasters; a route compiling mid-capture produces exactly that, and it would be logged as a page defect.

### 4.4 Model calls: parallel across cells, strictly serial *within* a cell

Within one cell the calls are a dependency chain, and flattening it is a correctness error:

```
C1 global (whole page)  →  its findings name regions  →  C2..Cn crop calls on those regions
                        →  P4's INDETERMINATE set     →  adjudicate call
```

Crop-refinement is the single biggest measured lever in the whole pipeline — ScreenSeekeR took a
model 18.9% → 48.1% on ScreenSpot-Pro with no model change — and it is *defined* as "look again where
the first pass pointed". Issuing C1 and C2 concurrently on guessed regions discards the mechanism and
keeps the cost. So: **6 cells in flight, ≤1 call per cell.**

The `>20 image blocks in one request` cliff never fires, because `--call-concurrency` bounds
*requests in flight*, not blocks per request, and P5 caps a single request at 12 image blocks
(P4 `--max-crops 12`). Both bounds hold independently; neither relies on the other.

---

## 5. Caching — and why the thing everyone caches is the one thing we cannot

🚨 **The vision cache is dead here and no amount of prompt-caching cleverness revives it.** Every
published VLM-pipeline speedup assumes repeated inputs; a design review loop *never shows the same
screenshot twice*, because the agent edits the source between passes and the next screenshot is by
construction different. Any design whose economics depend on image-block cache hits is budgeting for
a hit rate of ~0.

What *is* stable, measured against this repo's actual change pattern:

| Layer | Cache key | Hit rate we should expect | Saves |
|---|---|---|---|
| **Prompt prefix** (P6 templates + app profile + rubric) | `prompt_sha` | ~1.0 within a run, ~1.0 across runs until a template edit | Anthropic prompt caching on ~1,100–1,800 prefix tokens; ~90% off the *cached* portion only |
| **DOM findings** (`screen.json`) | `sha256(snapshot.json)` | **high** — a CSS-only edit changes pixels and computed styles but leaves most nodes' facts identical; a copy edit changes one text run | the full 80 ms + NumPy pass for unchanged cells |
| **Affected-set reverse index** (§9) | `sha256(.next/**/*.nft.json + ssr chunk maps)` | ~1.0 between builds | 20–40 s of manifest parsing per invocation |
| **The clean control** (§10.2) | `(app, git_sha_of_design_system, dr_version)` | ~1.0 for a copy-only PR | a whole control run |
| **The screenshot** | — | **~0.0** | — |
| **The judge response** | — | **0.0 by construction** — a cached judgement is a stale judgement | — |

**The rule that falls out: cache facts, never opinions.** A cached DOM finding is a claim about bytes
that are still on disk and can be re-verified in 80 ms. A cached judgement is a claim about a frame
that no longer exists.

**Negative caching is the one we must NOT do.** Caching "cell X had no findings" and skipping it next
run reproduces `fail-safe-default-mimics-the-healthy-state`: the clean result and the not-run result
become the same bytes. If a cell is skipped, `report.json` records it under `cells.skipped_*`, never
under a findings count of zero. This is why `cells` is a closed census with a `skipped_budget` bucket
rather than a `judged` count you are invited to subtract.

**Prompt-cache mechanics that actually apply.** Order the request so the stable prefix leads:
`system (rubric, ~1,100 tok) → app profile (~200) → cache_control:{type:"ephemeral"} → factpack
(~854, per-cell) → image → question`. The factpack is *below* the breakpoint because it changes every
cell; putting it above would invalidate the prefix on every call and buy nothing. The 5-minute
ephemeral TTL comfortably covers a 27-cell run at 6-wide (§6.3), and does not cover a 630-cell one —
so on a full-app run the prefix re-warms roughly every 5 minutes, which `cost.json` records as
`cache_creation_input_tokens` rather than hiding.

---

## 6. Latency budget

### 6.1 One cell, warm server

| Step | ms | Source |
|---|---|---|
| `goto` + network idle, warm route | 600 | Playwright, warm dev route |
| fonts ready + settle + reduced-motion arm | 800 | P1 §6 |
| raster ×2 (stability gate, full-page 1440×3488 @2) | 900 | two shots, P1 exits 11 unless byte-identical |
| `DOMSnapshot.captureSnapshot` (32 style props) | **33** | A7, measured |
| derive `read/` tiles + crops from master | 400 | resize + PNG encode |
| `dr extract` → facts.json | **53** | P3 O3 `extractMs`, measured on 2,009 nodes |
| `dr screen` (9 DOM rules + NumPy cross-check) | 600 | 80 ms measured for rules; NumPy pass estimated |
| `dr route` | 50 | pure JSON |
| **deterministic subtotal** | **≈ 3.4 s** | |
| `dr judge` C1 global (5.6 k in / 0.9 k out, Opus 5 high) | 18,000 | UNVERIFIED — §12 P3 |
| `dr judge` crop ×2, serial (chain, §4.4) | 24,000 | ″ |
| `dr judge` adjudicate, 0.6 expected | 6,000 | ″ |
| `dr arbitrate` | 200 | pure JSON |
| `dr attribute` (~3 findings × source-map lookup) | 4,000 | P8 §5 |
| **cell total, alone** | **≈ 56 s** | of which **95% is the model** |

Two things are load-bearing here. **The deterministic layer is 6% of the wall clock and finds 9 of
11 defects**, which is the whole argument for running it first and unconditionally. And **`--judge
off` turns a 56-second cell into a 3.4-second one**, which is why it is a flag and not a build-time
decision — it is the difference between a tool you run in a loop and a tool you run at a milestone.

### 6.2 Cold start, and the one number that dominates a first run

`next dev` compiles per route on first request. The app's own Playwright config raised its boot
window to 600 s over a measured **3–4 minute** cold dev-compile, and records that a `pnpm build`
pre-warm does not help. Budget, per app:

- **server already running, route already compiled:** 0 s
- **server running, route cold:** ~15 s/route (UNVERIFIED per-route figure — §12 P1)
- **server not running:** 20–240 s boot + per-route compile. `dr` waits up to **600 s** (matching the
  app's own gate) then exits `69`. Not 180 s: the app measured 180 s as insufficient under load, and
  a shorter timeout here would fail exactly when the machine is busy.

### 6.3 One app, end to end

Lanes B (capture) and D (judge) pipeline, so the run is `warm-up + max(B, D) + tail`.

| Run | Cells | Warm-up | Capture lane | Judge lane (6-wide) | **Wall** |
|---|---|---|---|---|---|
| **affected**, management, 9 routes × 3 vp | 27 | 90 s | 111 s @c=1 | 216 s | **≈ 6 min** |
| **full**, `reso-landing-app`, 6 routes × 3 vp × 1 theme | 18 | 30 s @c=4 | 18 s | 144 s | **≈ 3 min** |
| **full**, `reso-web-app`, 17 pages × 3 vp | 51 | 60 s @c=4 | 52 s | 408 s | **≈ 8 min** |
| **full**, management, 105 routes × 3 vp × 2 themes | **630** | 9 min | 43 min @c=1 | **84 min** | **≈ 1 h 40 min** |
| **full**, management, `--judge off` | 630 | 9 min | 43 min | — | **≈ 52 min** |

The 630-cell row is the reason §9 exists. It is not unaffordable in *time*; it is unaffordable in
*quota* (§7.3).

---

## 7. Cost — computed, not estimated

### 7.1 Image tokens, from `⌈w/28⌉ × ⌈h/28⌉`

| Image | Device px | Tokens | Note |
|---|---|---|---|
| viewport shot 1440×900 @1 | 1440×900 | ⌈51.43⌉·⌈32.14⌉ = 52·33 = **1,716** | the honest baseline |
| clamp-safe full page @2 | 2000×1250 | 72·45 = **3,240** | 1.89× the 1x shot for 1.39× delivered detail |
| region crop 700×440 CSS @2 | 1400×880 | 50·32 = **1,600** | the workhorse |
| **largest crop that is both clamp-safe and under the tier cap** | **2000×1800** | 72·65 = **4,680** | = 1000×900 CSS @2 |
| naive "clamp-safe" square | 2000×2000 | 72·72 = **5,184** | 🚨 **over the 4,784 tier cap** — the API resamples it |
| exact tier fit | 2576×1456 | 92·52 = **4,784** | the ceiling |

🚨 **`w ≤ 2000 && h ≤ 2000` is necessary and not sufficient.** A 2000×2000 PNG passes P1's
`clamp_safe` assertion and P5's entry check, is accepted by `Read`, and is then **resampled by the
API** because 5,184 > 4,784 visual tokens. Every geometric claim about that image is a claim about a
frame that was resized after the pipeline certified it. ORCHESTRATE therefore asserts a **second**
predicate on every model-facing image and fails the call rather than the pixels:

```
assert ceil(w/28) * ceil(h/28) <= 4784      # else: refuse the call, exit 70, name the image
```

This is the P1 clamp assertion's missing half, and it belongs here because it is a property of the
*request*, not of the file — P1 cannot see how many images a request will carry.

### 7.2 One cell, one review

Opus 5: **$5 / MTok input, $25 / MTok output**.

| Call | in (tok) | out | $ in | $ out |
|---|---|---|---|---|
| C1 global: image 3,240 + factpack 854 + rubric 1,100 + findings 400 | 5,594 | 900 | 0.0280 | 0.0225 |
| C2, C3 crops: image 1,600 + context 600 + template 700 (×2) | 5,800 | 1,000 | 0.0290 | 0.0250 |
| adjudicate, expected 0.6 × (1,600 + 900 + 700) | 1,920 | 240 | 0.0096 | 0.0060 |
| **cell** | **13,314** | **2,140** | **$0.0666** | **$0.0535** |

**≈ $0.12 per cell, ≈ 15.5 k tokens, 3.6 model calls.** Prompt caching on the 1,100-token rubric
prefix removes ~$0.004/cell at a 90% discount on the cached read — real, and not the lever anyone
expects it to be. **The image is 24% of the input tokens and the factpack is 6%**, which is the
arithmetic behind the README's *"there is no context-budget argument for withholding facts from the
judge"*: the entire deterministic fact-pack is cheaper than a quarter of one screenshot.

### 7.3 One app

| Run | Cells | Input tok | Output tok | **$** |
|---|---|---|---|---|
| affected (median PR, §9.3) | 6 | 79.9 k | 12.8 k | **$0.72** |
| affected (p90 PR) | 27 | 359 k | 57.8 k | **$3.24** |
| full `reso-landing-app` | 18 | 240 k | 38.5 k | **$2.16** |
| full `reso-web-app` | 51 | 679 k | 109 k | **$6.12** |
| **full `reso-management-app`** | **630** | **8.39 M** | **1.35 M** | **$75.60** |

🚨 **The full management run is a weekly-quota event, not a line item.** 8.39 M input tokens through
one Max account in 100 minutes will move the weekly meter visibly, and the routing question ("which
account absorbs this") is an operator decision, not the orchestrator's. `dr review --routes auto` can
therefore *never* expand to the full set silently — §9.4's cap and the `coverage` field exist for
exactly this, and a full run requires the literal `--routes all`, which prints the projected cost and
requires `--yes` when it exceeds `--judge-budget-usd`.

### 7.4 The budget is a hard stop with a defined shape

`--judge-budget-usd` (default **$3.00**) is checked **before** each call against the running ledger
plus that call's *projected* cost (input is known exactly; output is bounded by P6's schema
`maxItems`). On breach: stop issuing calls, write `report.json` with truthful `cells.skipped_budget`,
exit **75**. Never truncate a cell mid-chain — a cell with C1 and no crop pass is a cell whose
findings were never refined, and that is the 18.9%-not-48.1% configuration. The scheduler drops
**whole cells**, lowest-priority first, where priority is P5's own ranking.

---

## 8. How a Claude Code session drives it, and how results come back

### 8.1 The invocation the agent actually runs

One command, foreground, `--json`:

```bash
dr review reso-management-app --since origin/main --json
```

stdout is exactly one line — everything else goes to stderr, so the agent's `tool_result` is small:

```json
{"ok":true,"exit":0,"run":"/Users/…/.dr/runs/2026-08-26T18-04-11Z_a91f",
 "report_md":"…/report.md","report_json":"…/report.json",
 "coverage":"affected","cells":{"planned":27,"failed":0,"skipped_budget":0},
 "findings":{"asserted":11,"advisory":24,"abstained":6},
 "read_order":["…/report.md","…/cells/admin-team/1440x900.dark/read/index.png"],
 "cost_usd":3.24}
```

`read_order` is the contract that keeps the agent inside the Read ladder. It is **≤ 6 paths**, ranked,
and the agent is instructed to read them in order and stop when it has enough. It exists because the
failure it prevents is silent and hard: **more than 20 image blocks in one request tightens the
per-image cap and REJECTS oversized images rather than downscaling them.** An agent that globs
`cells/**/crops/*.png` and Reads them will hit that cliff, and the rejection is a hard failure mid-
review, not a degradation.

### 8.2 `report.md` is the artifact, and it is text-first

Findings reach the agent as **JSON coordinates plus prose, not as annotated overlays**. An overlay is
a full second image (~3,240 tokens) on top of the clean one; the same findings as JSON are ~840
tokens — ~4× cheaper for strictly more information, since a box drawn on a PNG cannot carry a
`backendNodeId` or a file path. Overlays are written to disk (`cells/*/arbitrated/overlay.png`) for a
*human* to open, and are absent from `read_order`.

```markdown
## admin/team · 1440×900 · dark

### asserted (correctness — these are measured, not judged)
- **contrast 3.01:1** `button.invite > span` — token `accent.fg` on `accent.bg`; floor 4.5:1.
  → `src/components/team/InviteButton.tsx:41` (HIGH) · `styled-system` token `accent.fg`
- **target 28×28** `button[aria-label]` at (1180, 214); floor 44×44.
  → `src/components/ui/IconButton.tsx:12` (HIGH)

### advisory (judgement — Opus 5, not a gate)
- The invite action is visually subordinate to "Export CSV", which is the rarer task.
  evidence: crops/c02.png · no measurement claimed · → `src/app/(app)/admin/(settings)/team/page.tsx:88` (MEDIUM)

### abstained (we could not tell, and are saying so)
- contrast for `section.hero > p` — backdrop is a gradient; cross-check disagreed left/right
  (4.81:1 / 1.57:1). Not a pass.
```

The three rungs are P7's, reproduced verbatim; ORCHESTRATE only groups and orders them. **Advisory
findings are never sorted above asserted ones** regardless of the model's own severity, and the
section headers carry their epistemic status in the header text, because an agent that skims will
read the header and not the parenthetical.

### 8.3 Retries, and what the agent is never asked to do

429/5xx on a model call: 3 attempts, exponential backoff `2 s → 8 s → 30 s`, jittered. Exhausted ⇒
that **cell** is `skipped_api`, the run continues, exit `75`. Never retried: a schema rejection from
P6 (that is a prompt defect, retried once by P6 itself and then dropped), and never a capture that
exited `11 UNSTABLE` (an unstable page is a finding about the page, not a flake to grind away).

The agent is never asked to compose the pipeline. There is no documented flow in which a session runs
`dr capture` then `dr judge` by hand — the composition is `dr review`, and a session doing it manually
is a session that will skip `dr screen` and hand the model a question arithmetic already answered.

---

## 9. Incremental review — the affected set

### 9.1 It is derived from the bundler graph, and heuristics are not an acceptable fallback

TurboSnap's insight is that the only sound answer to *"which pages does this commit change?"* is the
**bundler's own dependency graph**, because aliases, barrel files, dynamic imports and CSS-in-JS
re-exports all defeat directory heuristics. A path-prefix heuristic ("edited `components/team/*` ⇒
review `/admin/team`") is wrong in both directions: it misses the design-token file that changes 107
routes, and it re-reviews a route whose edited component is dead code.

### 9.2 Building the reverse index for Next — including the trap that yields zero

**Measured on `reso-management-app` today, and this is the load-bearing construction detail:**

`.next/server/app/**/*.nft.json` (node-file-trace, 123 route bundles) lists **no first-party source
files at all** — the app's own code is compiled into `chunks/ssr/*.js`, so the trace contains only
`node_modules` and chunk paths. A reverse index built from `nft.json` alone indexes **0 modules** and
reports every commit as affecting nothing. That is a silent, total false-negative, and it looks
exactly like a clean incremental run.

The composition that works, and its measured yield:

```
route bundle  --nft.json-->  chunk basenames
chunk         --.next/server/chunks/ssr/<chunk>.js.map "sources"-->  first-party source paths
                (resolve each source relative to the .map's dir; keep only paths under repo root
                 that are not node_modules/ and not .next/; the paths are percent-encoded — decode)
```

```
route bundles: 123 · SSR chunk maps carrying first-party sources: 381 of 704
nft→chunk joins: 3,664 · distinct first-party modules indexed: 1,058
```

The index is built once per build, cached on `sha256` of the manifest set (§5), and inverted to
`module → routes`.

### 9.3 The measured fan-out, which is the whole design constraint

| | modules | share |
|---|---|---|
| fan-out **= 1** (edit affects exactly one route) | 469 | **44.3%** |
| fan-out **> 12** (exceeds the default cap) | 354 | **33.5%** |
| **p50** | **2 routes** | |
| p75 | 17 routes | |
| p90 | 29 routes | |
| p99 | 84 routes | |
| max (`lib/brand-canvas.ts`, `lib/reload-guard.ts`, `src/app/global-error.tsx`, …) | **107 of 123** | |

**Read that as two populations, not one distribution.** Nearly half of all edits are leaf edits and
the median PR reviews **2 routes for ~$0.24** — incremental review is not merely viable there, it is
nearly free. And a third of all modules are design-system-shaped, where the honest affected set is
most of the app. **The p75 sits at 17, above the cap, which means the cap fires on more than a
quarter of edits — so the sampled path is a normal operating mode, not an exception**, and it has to
be designed as one.

### 9.4 The cap, the sample, and the label

```
affected = ⋃ routes(module) for module in git diff --name-only <since>..HEAD
if |affected| == 0                      → coverage:"affected", cells:0, exit 0, report says so
if |affected| <= --max-routes (12)      → coverage:"affected", review all
if |affected| >  --max-routes           → coverage:"sampled",  review a stratified sample of 12
if the index is missing or stale (§9.5) → coverage:"full-fallback", review the .dr.toml allowlist
```

**12** is `--max-routes`' default because 12 cells × 3 viewports = 36 cells ≈ $4.32 ≈ 8 minutes,
which is one order of magnitude under the full-app run and still inside a single interactive wait.
It is a budget threshold, not a statistical one, and it is exposed as a flag for that reason.

The **stratified sample** picks 12 routes to maximise *distinct rendering contexts*, not coverage
count: one route per top-level route group (`(app)/admin`, `(app)/venue`, `(auth)`, …), then fill
remaining slots by descending count of *changed* modules the route contains. Rationale: a design-token
change that breaks a card breaks it identically on 40 routes, and the second through fortieth
observations carry almost no information — while a route group with a different shell can break
differently. **This is a sampling heuristic and it is admitted as one**: `coverage:"sampled"` plus
`sampled_from: 84` in `report.json`, and `report.md` opens with `⚠️ SAMPLED — 12 of 84 affected
routes reviewed. This run cannot support a "no regressions" claim.`

### 9.5 The two residuals, named

**(a) The index is build-time, and a review runs against a dev server.** The manifests describe the
last `pnpm build`; the pixels come from `next dev`. If `git diff <build-sha>..HEAD` touches any file
**not present in the index at all** (a brand-new component, a new route), the index cannot answer and
the run degrades to `coverage:"full-fallback"` rather than guessing. Comparing `.next/BUILD_ID`'s
recorded sha against `HEAD` is the check; a stale index is the common case on a feature branch, so
**`dr affected` prints the staleness and the one command that fixes it (`pnpm build`) rather than
silently narrowing**.

**(b) Nothing derives the blast radius of a *global CSS* change.** Panda's `styled-system/` output and
Tailwind 4's `@theme` layer are both in the graph as *modules* (which is why `styled-system/helpers.mjs`
shows fan-out 84), but an edit to a **token value** changes rendering on routes that never import the
changed helper. `reso-management-app` ships **both** Panda (`@pandacss/dev ^1.9.0`, `@park-ui/panda-preset`)
and Tailwind 4 (`tailwindcss ^4.2.4`) — so this is two token systems, not one. ORCHESTRATE's rule:
**a diff touching a token source promotes the run to `--routes all` scope and therefore to the cap,
i.e. `coverage:"sampled"` with the full route population as `sampled_from`.** It never reports
`affected`. The token-source globs live in `.dr.toml`, versioned, per app.

---

## 10. CI versus on demand

### 10.1 The split, and it is mechanical

`--gate` and `--judge on` are **mutually exclusive at argument parsing** (exit `64`). That single line
is the enforcement of the June 2026 ruling; everything else about it is documentation.

| | CI (`--gate`, on every PR) | On demand (`dr review`, an agent or a human) |
|---|---|---|
| Stages | capture · extract · screen · arbitrate | all eight |
| Model calls | **zero** | 3.6 per cell |
| Cost | $0.00 | §7.3 |
| Wall | 27 cells ≈ 2 min; full app ≈ 52 min | §6.3 |
| Can fail the build | **yes**, on `asserted` + `severity:high` correctness only | never — exit 0 or 2/75 |
| Rungs it may act on | `asserted` | all three, advisory as prose |

CI gates on exactly what the deterministic layer scored **9/9 with zero false positives on the clean
control**: contrast against a solid backdrop, target size, overflow, token conformance, alignment
against the computed grid. It gates on **nothing** the model produced, and it gates on **nothing**
marked `INDETERMINATE` — an abstention in CI is a comment on the PR, never a red.

This also means CI never needs an API key, never has a rate limit, and cannot be made flaky by a
model's ~30–37% order-invariant consistency. The `--gate` path is deterministic in the strict sense:
same commit, same bytes, same exit code.

### 10.2 The false-positive budget is a CI job, and it fails closed

~20% false positives is where an AI reviewer loses human credibility regardless of catch rate, and
our two zero-FP runs are the baseline to defend. So:

- `dr control <app>` renders the app's clean control fixtures and asserts **zero** `asserted`
  findings. A new rule that fires on the control does not ship.
- The control run is keyed on `(app, design-system sha, dr_version)`. If any is newer than the stored
  control, the control is **stale**, and `--gate` exits **78** with no report. Fail closed, matching
  P7's exit 3: a gate whose calibration is unverified is a gate that convicts arbitrarily.
- The control is refreshed *deliberately* (`dr control <app> --bless`), never as a side effect of a
  failing run. `vrt:rebless`-shaped auto-blessing is exactly how a control stops being one.

### 10.3 What runs where, concretely

| Trigger | Command | Blocking |
|---|---|---|
| pre-commit | — | nothing; too slow |
| PR CI | `dr review <app> --since origin/main --gate --json` | yes, exit 1 |
| PR CI, nightly | `dr control <app>` | yes, exit 78 |
| agent, mid-task | `dr review <app> --since HEAD~1 --json` | no |
| agent, milestone | `dr review <app> --routes all --judge-budget-usd 80 --yes` | no |
| human, quarterly | `dr review reso-management-app --routes all` | no |

---

## 11. The degradation ladder — every partial state, and what it is allowed to claim

The single most dangerous outcome available to this pipeline is a run that is *quietly* less than it
appears. Each row below is a real partial state with a mechanical marker, and the right-hand column
is what `report.md` is permitted to say.

| State | Marker in `report.json` | Exit | May the report claim "clean"? |
|---|---|---|---|
| all cells complete, no findings | `cells.failed:0`, `coverage:"full"` | 0 | **yes** — this is the only row that may |
| some cells failed capture | `cells.failed:N` | 2 | no — "N cells not reviewed" in the header |
| judge budget hit | `cells.skipped_budget:N`, `judge_short:true` | 75 | no — "deterministic complete, judgement short" |
| API exhausted | `cells.skipped_api:N` | 75 | no — same header, different cause |
| `--judge off` | `judge:"off"` | 0 | **partially** — "no judgement layer ran" is stated in line 1 |
| affected-set sampled | `coverage:"sampled"`, `sampled_from:N` | 0 | no — §9.4's ⚠️ banner |
| index stale | `coverage:"full-fallback"` | 0 | no — names `pnpm build` |
| capture unpinned DPR | P1 exit 20 ⇒ the cell never runs | 2 | n/a — the cell is absent, not clean |
| clamp-safe but over 4,784 tokens | refused before the call (§7.1) | 70 | n/a |
| control stale, `--gate` | — | 78 | **no report is written at all** |

**The invariant:** there is no code path that produces an empty findings list without also producing
a `coverage` field and a non-zero bucket count that explains it. `report.md`'s first line is generated
from those fields, not written by hand, for the same reason `wrap-ledger.sh` computes a rung rather
than accepting prose.

---

## 12. UNVERIFIED, and the one probe that settles each

| # | Claim | Probe |
|---|---|---|
| P1 | ~15 s per-route cold `next dev` compile on `reso-management-app`. The app's own config asserts 3–4 min for a *whole gate boot*; the per-route figure is my division, not a measurement. | Boot `pnpm dev`, `curl -s -o /dev/null -w '%{time_total}' localhost:<port>/<route>` for 10 distinct cold routes, take p50/p90. Changes §6.2 and §4.3's warm-up sizing, nothing else. |
| P2 | The SSR-source-map join (§9.2) reproduces the same route set the **dev** server would use. It was measured against a **production** build. Turbopack's dev chunking may differ. | Edit one leaf component, `pnpm build`, re-derive `affected`, and independently confirm by rendering all 123 routes before/after and diffing SHAs. Disagreement ⇒ §9 must key on a dev-time graph. |
| P3 | 18 s for an Opus 5 global call at effort high with a 3,240-token image. No measurement was taken. | Ten `dr judge` calls on stored requests from the bench corpus; record `wall_ms`. Only §6 moves; §7's cost is token-derived and unaffected. |
| P4 | 4 concurrent `next dev` instances of a 123-route app fit in 64 GB (§4.2's horizontal-scale escape hatch). | Boot 4 on 4 worktree ports, hit one route each, `ps -o rss=`. If it does not fit, sharding is 2-wide and §6.3's full-run wall roughly doubles. |
| P5 | NumPy cross-check at 600 ms on a 2880×6976 device raster. `bench/detect_xcheck.py` was measured on the 13-page corpus, whose pages are shorter. | Run it on a real `/admin` full-page master, `time` it. Above ~3 s, lane C stops being free and needs its own concurrency knob. |
| P6 | Prompt-cache ephemeral TTL (5 min) covers a 27-cell run at 6-wide. Depends on P3's per-call latency. | Falls out of P3. |

**One thing here is not uncertain and should not be re-litigated:** the fan-out distribution in §9.3
(p50 = 2, p75 = 17, max = 107 of 123, 44.3% singletons) was computed today from this repo's own
`.next` manifests, and it is the number the incremental design rests on.

---

## 13. What this stage adds that no upstream stage could

P1–P8 each end at their own boundary and each is correct there. Three properties only exist once
something composes them, and all three are failure-avoidance rather than capability:

1. **A cell key that folds the render environment into resumability** (§3.1). Without it, resuming a
   review across a `git pull` mixes two instruments and every geometric finding inherits a phantom
   offset — the failure P1 pins the DPR to prevent, arriving through the scheduler instead.
2. **The second image predicate** (§7.1): `⌈w/28⌉·⌈h/28⌉ ≤ 4784`. P1 owns `clamp_safe`, P5 checks it,
   and both are satisfied by a 2000×2000 PNG the API will silently resample. Only the layer that
   assembles the *request* can see this, and it is one line.
3. **A closed census with a `coverage` field** (§0.3, §11). Every upstream stage reports on what it
   did; nothing upstream can report on what was never attempted. That is the whole difference between
   a review and a claim about a review.
