# Fable 5.1 effort re-sweep — 2026-09-10

**Item:** cc-backlog `d98bf0055818` — *"the fable51_* keys are Fable 5's numbers, never probed against
5.1"* (model-upgrade runbook step 5, left open by the 2026-09-03 Fable 5.1 adoption, `9d97439a`).
**Governs:** `model-config.yaml` `effort_defaults.fable51_*`, and the Fable rows of the
`commands/handoff.md` routing table that name those keys.

## Why a sweep was owed

Anthropic, *Prompting Claude Fable 5.1*: *"Re-run the sweep even if you already ran one on Claude
Fable 5: effort level names don't correspond to the same amount of thinking across models."* The four
`fable51_*` keys (`default: high`, `capability_sensitive: xhigh`, `routine: medium`, `cheap: low`)
were written on adoption day as labelled starting points and never measured.

## Method

**Corpus — reused, not built.** The frozen `tests/fixtures/codex-probe/` corpus: nine review briefs,
each a real pre-fix file extracted byte-for-byte from git, **36 anchored ground-truth defects** across
seven defective briefs, plus two screened-clean briefs (`cp-03`, `cp-07`). Its controls are asserted
by `verify-corpus.sh` and gated by `tests/codex-probe-corpus.bats`. It was built for the T4 adversarial
slot probe and suits this one for the same reason: the defects survived a first look, so it
discriminates on exactly the open-ended grounding axis where T1/T2 found effort to be load-bearing.

**Arms.** `claude-fable-5-1` at `low · medium · high · xhigh · max`, one fresh context per
(brief, effort) cell — 45 cells — produced by `run-arms.sh`. Two reference arms come free from W2
(2026-08-11), already verbatim on trunk: `claude-fable-5 @xhigh` (arm A) and `claude-opus-5 @max`
(arm D).

**Isolation** is the W2 recipe measured in `docs/research/codex-probe-screen-2026-08-10/
W2-preflight-findings.md` §3: `--tools ""` (per-cell control: `num_turns=1`), `--setting-sources ""`
plus a neutral `mktemp` cwd, so no `CLAUDE.md` / `MEMORY.md` / hooks load. That matters here: this
repo's `MEMORY.md` states `cp-01`'s ground truth in one line.

**Binary.** 2.1.260 (`~/.claude-260`, the live track). The pinned stable 2.1.114 refuses the model
outright — `400 claude_code_version_too_old … version 2.1.251 or newer is required` — so any future
re-run must not go through `claude-latest`.

**Cost is MEASURED, not directional.** Every prior probe in `model-routing-freewin-probe.md` could
only reason about cost from first principles (`.meta.json` carries no usage; Codex reports none).
`claude -p --output-format json` returns `usage.output_tokens` and `total_cost_usd` per call, so each
cell records its own. `output_tokens` includes thinking, which makes it the positive control that the
`--effort` flag reached the model at all: a flat token curve across efforts would void the sweep.

**Scoring** — `judge.py`: three `claude-opus-5 @xhigh` judges (`effort_defaults.verify_judge`) per
defective brief, each seeing the brief, the ground-truth list and all seven outputs under labels
re-shuffled per (brief, judge). A ground-truth item is credited only for its MECHANISM, never its
topic (the W3 rule). A single-vendor panel is acceptable on this axis only: W3 measured anchored
scoring as judge-vendor-independent (98% cross-vendor vs 99% within). Headline = strict majority
(≥2 of 3), reported beside every other threshold.

**Decision rule** — the operator's lexicographic objective (`model-routing-freewin-probe.md`
§ Purpose): quality first, cost breaks ties. A lower effort is adopted for a key only when it ties the
higher one on recall; any reliable recall loss rejects it.

## Results

**Grid.** 45 cells planned: 42 produced a review, 1 produced none (an arm failure, scored 0), 2 are
unmeasured. 17 rows were HTTP 429 quota faults ($37.46 for no output): next4, then next3, hit their
5-hour limit mid-generation — several after a full 128K–192K-token stream — and those cells were
re-run on another account. The runner now records the serving account and `api_error_status` per
row, and `judge.py` sets quota faults aside by **status** (or, for rows written before the runner
recorded it, by the exact session-limit message) — never by "was anything served".

**Positive control.** Median output tokens rise with effort, 6.4K → 18.1K → 24.3K → 62.1K → 118.4K,
so `--effort` reaches 5.1. **Judging:** 21 calls, 147 rows, 0 parse failures, $11.82. The panel is
externally calibrated: on `cp-01` it scores both reference arms exactly as the 4-judge W3 panel did.

Recall, strict majority (≥2 of 3). `—` = unmeasured, never scored 0. PAIRED = the five briefs where
every arm was measured.

| brief | GT | f51@low | f51@medium | f51@high | f51@xhigh | f51@max | f5@xhigh | o5@max |
|---|---|---|---|---|---|---|---|---|
| cp-01 | 6 | 4 | 5 | 4 | 5 | 5 | 4 | 5 |
| cp-02 | 4 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| cp-04 | 6 | 2 | 3 | 3 | 3 | 3 | 3 | 3 |
| cp-05 | 4 | 0 | 0 | 1 | 0 | 1 | 1 | 1 |
| cp-06 | 6 | 0 | 0 | 0 | 0 | — | 0 | 0 |
| cp-08 | 5 | 0 | 1 | 1 | 1 | — | 0 | 1 |
| cp-09 | 5 | 0 | 0 | 1 | 0 | 0 | 1 | 2 |
| **TOTAL (measured)** | 36 | **6**/36 | **10**/36 | **10**/36 | **9**/36 | **9**/25 | **9**/36 | **12**/36 |
| **PAIRED** | 25 | **6** | **9** | **9** | **8** | **9** | **9** | **11** |

| vote threshold (paired) | f51@low | f51@medium | f51@high | f51@xhigh | f51@max | f5@xhigh | o5@max |
|---|---|---|---|---|---|---|---|
| ≥1 judge | 7 | 9 | 10 | 8 | 9 | 9 | 11 |
| ≥2 of 3 | 6 | 9 | 9 | 8 | 9 | 9 | 11 |
| unanimous | 5 | 8 | 8 | 8 | 9 | 9 | 11 |

| effort | cells measured | arm failures | median output tokens | max output tokens | cells past the 64K cap | continuations | cost USD |
|---|---|---|---|---|---|---|---|
| low | 9 | 0 | 6,449 | 16,699 | 0 | 0 | 7.52 |
| medium | 9 | 0 | 18,077 | 41,339 | 0 | 0 | 12.50 |
| high | 9 | 0 | 24,252 | 102,531 | 1 | 1 | 18.69 |
| xhigh | 9 | 0 | 62,062 | 255,464 | 3 | 6 | 47.17 |
| max | 7 | 1 (cp-09) | 118,365 | 127,944 | 4 | 4 | 47.03 |

*Continuations* = `ceil(output_tokens / 64000) − 1`: every cell ran under
`CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000`, so no single response can exceed it and any larger total was
continued at least that many times. It needs only the total — `usage.iterations` is sometimes empty.

### Verdict per key

| key | was | measured | outcome |
|---|---|---|---|
| `fable51_routine` | medium | 10/36 — ties high, beats Fable 5 @xhigh (9) at ⅔ of high's cost | **confirmed**; Anthropic's "medium ≈ Fable 5 at lower cost" reproduced |
| `fable51_default` | high | 10/36 — ties medium | **kept**; medium is a candidate free win, NOT certified (one sample/cell, recall-only — T1's fabrication-at-reduced-effort axis unmeasured) |
| `fable51_capability_sensitive` | xhigh | 9/36 vs high 10/36; high ≥ xhigh at every vote threshold; 2.5× the cost; 3/9 cells past the cap | **→ high** — the freewin rule (§ Purpose): tie + cheaper ⇒ adopt |
| `fable51_cheap` | low | 6/36 — lowest arm at every threshold | **kept as the cost tier**, annotated: below the floor on grounding-heavy review |
| max (not a key) | — | = high (paired 9/25), 1 no-review failure, ~2× xhigh's cost | **unfit** — recorded so it is not reached for |

### What else it found

1. **Effort above medium buys no recall on this class.** medium through max cluster at 8–10 of 25
   paired; only low falls below. Reported volume does not rise either (findings per output: low 6.0,
   medium 8.7, high 9.3, xhigh 8.7).
2. **The 64K output cap is the binding constraint above high** — Anthropic's "leave max_tokens
   headroom at xhigh/max" measured rather than quoted. xhigh continued in 3/9 cells (up to 255,464
   tokens, 536 short of the point where recovery gave up); max in 4/6 and, on the 60 KB `cp-09`,
   produced no review after 256K tokens and 47 minutes.
3. **Opus 5 @max (12/36, 11.1 findings/output) beats every 5.1 effort.** That strengthens T5 in
   `~/.claude/model-routing-freewin-probe.md` (the Fable premium is undemonstrated); it is not acted on
   here, because this item is the 5.1 ladder, not the frontier tier.

### Limits, stated rather than assumed

- One sample per cell over 7 defective briefs, recall only — false positives and citation accuracy
  were not scored. One task class: anchored review of a single file. The 64K cap is the tested
  condition; with more headroom the max arm might finish more often.
- `cp-06`/`cp-08` @max are **unmeasured and deliberately not re-run**: every arm scored 0 on `cp-06`
  and ≤1 on `cp-08`, so max cannot change its verdict there, and each attempt already cost ~$11–15
  before its quota wall. Their output files hold a placeholder the judges saw as a non-review; both
  cells are excluded from every total.

**Spend.** $132.91 measured cells + $37.46 quota faults + $11.82 judges ≈ $182 at API rates, drawn
from Max-plan quota that the accounts readout projected would otherwise strand at reset.

**Re-derive.** `SWEEP_CONFIG_DIR=<acct> ./run-arms.sh runs <brief>:<effort> …` ·
`JUDGE_CONFIG_DIR=<acct> python3 judge.py run runs runs/scores.jsonl` ·
`python3 judge.py table runs runs/scores.jsonl` (prints every table above). Headless Fable 5.1 needs
the 2.1.260 binary — `claude-latest` (2.1.114) returns `claude_code_version_too_old`.
