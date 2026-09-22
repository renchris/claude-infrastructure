# L2b — How this fleet measures model cost in its binding currency (for the Opus 5.5 policy)

Read-only pass, 2026-09-22 ~20:30Z. Repo: /Users/chrisren/Development/claude-infrastructure.
Currency key used on every number: **[W-pp]** weekly plan percentage-points (per account, 100/week, 4 accounts = 400/week) ·
**[5h-pp]** 5-hour session-meter points · **[F-pp]** weekly-Fable sub-cap points · **[tok]** deduped transcript tokens ·
**[$list]** API list dollars (an economy this fleet is NOT billed in) · **[recall]** anchored defects found.

## 1. The currency argument (docs/research/fable51-vs-opus5-routing-2026-09-16/)

- Zero dollar exposure: `~/.claude/accounts.json` → `spend.usage_credits_authorized: false`, `frontier.credits_authorized: false`
  (re-read live today, unchanged). The only scarce resource is 4 × 100 [W-pp]/week. Every vendor $/task chart is the wrong currency.
- `frontier.coupling: 0.5` ("coupling = fable_cap/weekly_cap per SSOT '<=50% of weekly usage limits'"): Fable is a SUB-CAP of the
  same weekly bucket, not a second budget. 1 [F-pp] = 0.5 [W-pp]. Invariant held in 28,572/28,572 utilization rows, and the skeptic
  showed violations were expressible in 27.8% of rows (a control that could fail). Router encodes it at `bin/claude-accounts:3481`
  `f_eff = min(coupling * max(0, 1 - fable_pct/100), w_rem)`. A Fable-only week ends at fable 100 / weekly 50.
- Per-token draw ratio Fable 5.1 ÷ Opus 5: A3 first measured 2.5–2.8× (list-$ per [W-pp]); V-quota found A3 had NO `message.id`
  dedup (inflation is model-dependent: Opus 3.41×, Fable 6.21× on output) and used the refuted list-$ weighting. Corrected: **~3.2–3.7×**
  via three denominators — weekly meter pooled 4 accts 3.71× (output [tok]/[W-pp]: Fable 31,079 vs Opus 115,150); Opus-5 price
  list applied out-of-sample to Fable arms 3.73–4.44× obs/pred (Opus positive control 1.03–1.23); 5h meter 3.25×
  (Fable 7,449 vs Opus 24,221 output [tok]/[5h-pp]). The 5h meter moved 1,730 pp vs weekly 384 pp → ~4.5× less quantization-starved;
  it is the better fast denominator. Per-account spread is 5× (1.17–5.86×) ⇒ single-account reads are noise.
- The meter is NOT list-price proportional: USAGE_TELEMETRY_100P §2.2/§2.8 — cache_read = 96.95% of [tok], ≈0% of quota, bounded
  ≤0.018–0.049 [W-pp]/Mtok by a controlled experiment (31.7M cache_read + 208 output moved weekly 1 pp where list predicted 4.62).
  Quota is carried by output + cache_creation. Opus-5 price list (§2.1, deduped): ~360K output [tok]/[W-pp] marginal, ~261K realised;
  ~3.4M cache_creation [tok]/[W-pp]. ~28% of weekly burn leaves no local transcript.
- § Re-derive (both read-only, both run today):
  `python3 -c "import json;d=json.load(open('$HOME/.claude/accounts.json'));print(d['frontier'],d['spend'])"` → coupling 0.5, both
  credit flags false. `bash scripts/effort-parity-assert.sh` → still DRIFT (see §3). The doc says: never quote 3.2–3.7× or any
  pct as current; re-measure. NOTE: V-quota's deduped scripts (`v/dedup_ab.py`, `v/redo.py`, `v/pricelist.py`) are NOT on disk in
  the repo; `instruments/` holds A3's undeduped integrators (+ `census.py`, which dedups).

## 2. How effort sweeps run here

- Harness `docs/research/fable51-effort-sweep-2026-09-10/run-arms.sh`: one fresh `claude -p` per (brief, effort) cell; isolation =
  W2 recipe `--tools "" --setting-sources "" --strict-mcp-config --disable-slash-commands --no-session-persistence`, neutral mktemp
  cwd (repo MEMORY.md leaks cp-01's answer), `CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000`, `--output-format json`. Env knobs:
  `SWEEP_MODEL`, `SWEEP_BIN`, `SWEEP_CONFIG_DIR`, `SWEEP_PAR`. Records account, api_error_status (429 = quota fault, set aside),
  cost_usd, all 4 token classes, num_turns (=1 control).
- Corpus: frozen `tests/fixtures/codex-probe/` — 9 briefs (7 defective, 2 clean), 36 anchored defects; ONE task class
  (single-file anchored review). Controls: `verify-corpus.sh`, `tests/codex-probe-corpus.bats`.
- Judges `judge.py`: 3 × claude-opus-5 @xhigh, blind per-(brief,judge) label shuffle, credit only on MECHANISM; strict majority
  headline; panel calibrated vs W3 on cp-01 (W3: judges 98% cross-vendor agreement).
- Cost read: `total_cost_usd` [$list] + `output_tokens` (includes thinking ⇒ the positive control that --effort reached the model).
  Never converted to [W-pp] in that README.
- Findings (Fable 5.1): recall low 6 · medium 10 · high 10 · xhigh 9 · max 9/25 · Fable5@xhigh 9 · Opus5@max 12 [recall/36];
  median output [tok] 6.4K/18.1K/24.3K/62.1K/118.4K. Effort above medium bought no recall on this class; 64K cap binds above high.
  Skeptic: Opus-vs-Fable direction only, sign test p=0.6875; 21/36 defects found by no arm. Keys moved: capability_sensitive xhigh→high.
- D3 (opus5-adaptation-2026-08-01.md): `effort_defaults.default` max→high on 2026-08-01 WITHOUT a sweep (it is "the guide's
  starting point, not a measured optimum"); the only per-class certification (T1, wf_771c1e9f-644, 4 classes: verify/judge,
  synthesis, mechanical-with-search, coding) was on OPUS 4.8 and is model-scoped. `routing-economics.md` R2 (2026-08-16) specified
  the Opus-5 panel: {high,xhigh,max} × four T1 classes, ≈27 runs ≈0.5–1 [W-pp]. Never run. Opus 5 @high is unbenchmarked (B3).
- Reusability for Opus 5.5: run-arms.sh YES as-is via env (`SWEEP_MODEL=claude-opus-5-5`,
  `SWEEP_BIN=$HOME/.claude-280/node_modules/.bin/claude` — 2.1.280 is installed; 2.1.260 refuses the id by name). Raise
  `CLAUDE_CODE_MAX_OUTPUT_TOKENS` (5.5 has 128K out). judge.py needs a small edit: `arms()` hardcodes `f51@{effort}` and REFS
  {f5@xhigh, o5@max}; add an o55@{effort} arm family + an Opus-5@high reference. Re-verify isolation on 2.1.280 (num_turns=1,
  rising token curve). Only covers the review class; the other three T1 classes have no frozen corpus in the repo (T1 briefs were
  live reso briefs in a Dynamic Workflow) ⇒ per-class needs corpus assembly.

## 3. Live state (read today)

`bin/claude-accounts` (live · Tue 15:31 local), each value = % of that account's plan limit:

| acct | 5h [5h-pp] | 5h reset | weekly [W-pp] | weekly-Fable [F-pp] | week reset |
|---|---|---|---|---|---|
| next | 9% | 2.6h | 20% | 0% | 4d 7h |
| next4 | 0% | 4.8h | 14% | 0% | 4d 12h |
| next3 | 3% | 4.8h | 8% | 6% | 6d 15h |
| next2 | 35% | 8m | 46% | 36% | 3d 14h |

Strand nowcast: next4 ~37 [W-pp] of 86, next ~36 of 80 will die at reset (~73 [W-pp] stranding) ⇒ a sweep is affordable from
quota that would otherwise be lost. Routing: general → next, fable → next, desk → next2.

Per-MODEL instruments: `cc-quota-price` fits a BLENDED price (keeps per-bucket model mix, warns when dominant model <~95%);
it has no per-model split. Ran `--census --since 7d` (8.8 s): 63,038 billed responses; output 34.18M, cache_creation 462.0M,
input 0.19M, cache_read 17.17B [tok]; dedup 57.6% repeats (2.40× over-count avoided). Ran the fit `--since 7d` (5.8 s): 66 moving
6h buckets, R² 0.637, rel-RMSE 0.936, output coef 0.000 (NNLS boundary artifact), input 883 [W-pp]/Mtok — DEGENERATE, do not quote;
mix opus-5 88% / fable-5-1 11% / opus-5-5 0%. My own per-model deduped census (7d, 1,808 files, read-only python):
opus-5 30.43M out (89.0%) · fable-5-1 3.64M (10.6%) · **opus-5-5 53,507 out / 3.89M cache_creation / 133 responses, first seen
2026-09-22T19:24Z** · sonnet-5 27K · others negligible [tok]. 53K output ≈ 0.15 [W-pp] at the Opus-5 price — below the integer
meter's resolution.

effort-parity-assert: floor high, launcher default high; BELOW on .claude (medium), .claude-next (low), .claude-tertiary (medium),
.claude-quaternary (low); OK .claude-secondary. Relevant to 5.5: its API default effort is MEDIUM and 2.1.280 stops a saved /effort
applying to newly released models (model-config.yaml:45-72), so every surface not passing --effort explicitly drops a rung.

## 4. NOT yet measured for Opus 5.5, and the cheapest instrument for each

1. **Plan-quota draw per token, Opus 5.5 vs Opus 5 [W-pp]/[5h-pp].** Unmeasured; 133 responses exist. The vendor list is $4/$20,
   cache read $0.20 (0.8× Opus 5 on output/cache_creation). NB model-config.yaml:48-53 calls the cache-read cut "a 2.5x cut on the
   axis this fleet actually spends" — that is a [$list] claim; in quota currency cache_read is ≈0 (§2.8), so the relevant axes are
   output + cache_creation, and the meter is already known NOT to follow list price (Fable 1.79× per list $). Cheapest instruments:
   (a) passive, zero-spend: after the 2.1.280 flip, V-quota's deduped single-model-interval integration on the 5h meter against
   `~/.claude/logs/account-utilization.jsonl` + the Opus-5 price list applied out-of-sample (positive control = Opus arm ≈1.0–1.2).
   Needs roughly ≥1–2M Opus-5.5 output [tok] in single-model intervals across ≥2 accounts (≈1 fleet-day). Scripts must be rebuilt
   (v/ files not on disk) or `cc-quota-price` given a `--model` bucket filter (it already tracks per-bucket model mix, l.378).
   (b) controlled, ~1 [W-pp]: the §2.8 M0 meter experiment (`meter-experiment.md`) — one idle account, fixed workload per model,
   both meters read fresh. Settles the accounting rule; spends quota.
2. **Per-class effort optimum on our tasks [recall] × [W-pp].** Unmeasured for 5.5 AND for Opus 5 @high. Cheapest: run-arms.sh +
   judge.py over codex-probe, arms Opus 5.5 @{low,medium,high,xhigh,max} plus Opus 5 @high (closes R2/B3 at once); ≈9 cells/arm.
   Rough draw at Opus-5 price: medium/high ≈0.5–0.7 [W-pp] per arm, full 5-effort grid ≈5–6 [W-pp] + judges — fits in the ~73 [W-pp]
   stranding. That is one class only; the other three T1 classes (coding, synthesis, mechanical-search) need a frozen corpus built
   first, then R2's design (≈27 runs, ≈0.5–1 [W-pp] per effort triple). Single sample per cell: power is weak (Fable sweep p=0.69).
3. Also unmeasured: fabrication-at-reduced-effort (T1's axis) at 5.5's default medium; whether 5.5 needs >64K output at xhigh/max.
