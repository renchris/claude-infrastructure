# Vendor and OSS ground truth — what already exists that we are not using

---
axis: "A8 — Vendor and OSS ground truth"
status: complete
date: 2026-08-16
headline: "Anthropic already ships the entire numerator-side instrument we would otherwise build — a token-free OpenTelemetry pipeline of 8 metrics and 15 events that this fleet has enabled in exactly zero of its five config directories — but it carries no weekly-limit denominator, and the denominator store the brief says does not exist has in fact been recording for six days at 5,017 rows and 94% wall-clock coverage."
load_bearing_claim: "Claude Code's OTel export is out-of-band (a separate SDK exporter posting to a collector) and therefore injects nothing into any model context, so enabling it costs zero tokens — making it the only instrument shape that satisfies the operator's no-bloat constraint by construction rather than by discipline."
---

## Headline

**Build almost nothing on the numerator side and fix the denominator side's discoverability instead.**
Claude Code ships a complete, documented, user-configurable OpenTelemetry pipeline —
`claude_code.token.usage`, `claude_code.cost.usage`, `claude_code.active_time.total`, five more
metrics, and fifteen events including `api_request`, `tool_decision`, and `api_error` — exported
out-of-band to a collector of our choosing. It is **token-free by construction** (a separate
LoggerProvider/MeterProvider writing to an exporter; nothing enters a prompt), which is the exact
instrument shape the "telemetry must not itself be token bloat" constraint demands. We use it in
**0 of 5** config directories. What it does **not** carry is any quota denominator: it counts
tokens spent, never allowance remaining — that lives only behind `api/oauth/usage`, whose response
keys (`five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`, `utilization`, `resets_at`)
are strings in the shipped binary. And the brief's stated gap — "no usage TIME-SERIES store was
found on disk" — is **false**: `~/.claude/logs/account-utilization.jsonl` holds 5,017 rows across
all four accounts spanning 2026-08-10 → 2026-08-16, 100% weekly-pct coverage, median inter-sample
gap 6.3 min, and has already captured five weekly resets. The brief's search missed it because the
file is named `account-utilization`, not `*usage*` or `*quota*` — a filename-glob search over a
semantically-named store. On the OSS side, **adopting beats building for the sink and loses for the
source**: Langfuse / Helicone / OpenLLMetry are worth adopting as the OTLP backend, while `ccusage`
and `claude-monitor` both re-derive from local transcripts what we already measure directly and
`claude-monitor` *estimates* plan limits by P90 when we read them from the endpoint.

---

## Findings

| # | Claim | Evidence (command / file:line / number + denominator) | Status | Coverage |
|---|---|---|---|---|
| 1 | Claude Code emits **8 OTel metrics**: `claude_code.session.count`, `.lines_of_code.count`, `.pull_request.count`, `.commit.count`, `.cost.usage` (USD), `.token.usage` (tokens), `.code_edit_tool.decision`, `.active_time.total` (s) | WebFetch `code.claude.com/docs/en/monitoring-usage`, metrics table | MEASURED (doc, quoted) | vendor doc, 2026-08-16 |
| 2 | Claude Code emits **15 OTel events**: `user_prompt`, `assistant_response`, `tool_result`, `api_request`, `api_error`, `api_refusal`, `api_request_body`, `api_response_body`, `tool_decision`, `permission_mode_changed`, `auth`, `mcp_server_connection`, `internal_error`, `plugin_installed`, `plugin_loaded` (all `claude_code.`-prefixed) | same page, events table | MEASURED (doc, quoted) | vendor doc |
| 3 | The pipeline is **user-configurable**, not managed-settings-only: `CLAUDE_CODE_ENABLE_TELEMETRY=1` + `OTEL_{METRICS,LOGS,TRACES}_EXPORTER` ∈ {otlp, prometheus, console, none}; defaults `OTEL_METRIC_EXPORT_INTERVAL=60000` ms, `OTEL_LOGS_EXPORT_INTERVAL=5000` ms | same page: "All telemetry configuration is **user-configurable** via environment variables and can also be set in **managed settings**" | MEASURED (doc, quoted) | vendor doc |
| 4 | **It is token-free.** Metrics/logs go to an OTel exporter process-side; no field is injected into any prompt. Independently corroborated in-repo: a live run with `OTEL_LOGS_EXPORTER=console OTEL_METRICS_EXPORTER=console` produced 5,979 lines of *exporter* output | `docs/research/prompt-suggestion-filter-2026-08-05.md` §2 ("Measured, not inferred… 5,979 lines"); architecture per vendor doc | **INFERRED** (architecturally forced; the 5,979-line run measured the exporter, not a context delta) | 1 live 2.1.220 run |
| 5 | **We do not use it.** `ENABLE_TELEMETRY`/`OTEL_*` appears 0 times across all five `settings.json` (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`, `-next`) and 0 times in `.claude.json`, `.zshrc`, `.zprofile`, `.bashrc` | `grep -rn "ENABLE_TELEMETRY\|OTEL_" ~/.claude*/settings*.json ~/.claude.json ~/.zshrc …` → no output. **Positive control**: `grep -c '"hooks"'` on the same five files → 42, 42, 42, 42, 41 | MEASURED | 5/5 config dirs |
| 6 | The only repo references to OTel are **prose ruling it out** for a different purpose (`tengu_*` first-party events), not configuration | `bin/cc-suggest-filter:16-18`, `bin/cc-1p-events:8,199`, `docs/research/prompt-suggestion-filter-2026-08-05.md:41-49` | MEASURED | repo-wide grep, `--exclude-dir=.git` |
| 7 | **OTel carries no weekly-limit denominator.** All 8 metrics are counters of consumption; no metric or event names an allowance, quota, limit, or reset | metrics + events tables, monitoring-usage page — exhaustive enumeration, no quota-shaped name present | MEASURED (absence over an enumerated set) | vendor doc |
| 8 | The denominator lives at **`api/oauth/usage`**, and its response shape is `five_hour` / `seven_day` / `seven_day_opus` / `seven_day_sonnet` / `utilization` / `resets_at` | `/usr/bin/grep -a -o` on `~/.claude-versions/2.1.183/…/claude` (Mach-O arm64): `api/oauth/usage`=4, `five_hour`=41, `seven_day`=79, `seven_day_opus`=15; `strings` confirms `seven_day_sonnet`, `utilization`, `resets_at`. **Negative control** `ZZZ_NEGATIVE_CONTROL_NOT_PRESENT`=0 | MEASURED | binary 2.1.183 (newest on disk; sessions reportedly run 2.1.220 — **not** re-verified on 2.1.220) |
| 9 | **The usage time-series store the brief says is absent exists and is healthy**: 5,017 rows, 4 accounts (next 1254 / next2 1254 / next3 1255 / next4 1254), 2026-08-10T05:58Z → 2026-08-16T10:26Z (148.5 h) | `~/.claude/logs/account-utilization.jsonl`; row/field census via python | MEASURED | 5,017/5,017 rows parsed |
| 10 | That store's **weekly denominator coverage is 100%** (`weekly_pct` non-null on 5,017/5,017 rows) and it carries 14 fields incl. `session_pct`, `fable_pct`, `k`, `k_work`, `k_src`, `credits_on`, `resets_at` | same census | MEASURED | 5,017/5,017 |
| 11 | Its **cadence is ~6 min and its wall-clock coverage 94%**: median gap 6.3 min, p90 8.2 min, max 205.5 min; 5 of 1,253 gaps exceed 60 min, totalling 9.1 blind hours over a 148.5 h span | gap analysis on `acct=next`, n=1,253 gaps | MEASURED | 1 of 4 accounts (next); others same sweep, not separately gapped |
| 12 | It has **already captured 5 weekly resets** (>5 pp drops): next 1, next2 1, next3 2, next4 1 — so pace-to-reset is answerable from history, not only from a point reading | trajectory scan, weekly_pct min/max per acct (next 1→91, next2 0→92, next3 0→100, next4 1→85) | MEASURED | 4/4 accounts |
| 13 | It was **written for exactly this question and costs nothing**: "Append one row per account per LIVE sweep — the series nothing was keeping… It rides the sweep that already happened — no extra network call, no extra quota, no new daemon" | `bin/claude-accounts:2242-2270` (`UTIL_PATH`, `record_utilization`) | MEASURED (source) | — |
| 14 | `/usage` exposes **strictly more than the oauth endpoint**: per-**skill**, per-**subagent**, per-**plugin**, and per-**MCP-server** attribution as a share of recent usage, plus behavior flags (long context, cache misses) raised at ≥10% share, with 24h/7d toggle | WebFetch `code.claude.com/docs/en/costs` § "Plan usage breakdown" | MEASURED (doc, quoted) | vendor doc |
| 15 | **That attribution is computed locally, not server-side**: "The figures are approximate and computed from local session history on this machine, so usage from other devices or claude.ai is not included" | same page, quoted verbatim | MEASURED (doc, quoted) | vendor doc |
| 16 | **No rate-limit header carries the weekly allowance.** The `anthropic-ratelimit-*` family (requests/tokens/input-tokens/output-tokens × limit/remaining/reset) plus `anthropic-priority-*` and `retry-after` are all org-level API-tier RPM/ITPM/OTPM. No documented programmatic weekly read beyond `oauth/usage` | WebFetch `platform.claude.com/docs/en/api/rate-limits` § Response headers — full 19-row table enumerated, none quota/weekly-shaped | MEASURED (absence over enumerated set) | vendor doc |
| 17 | **The 1-hour cache TTL is reachable from the CLI and is already the default here.** "On a Claude subscription, Claude Code requests the one-hour TTL automatically." `ENABLE_PROMPT_CACHING_1H=1` only matters when drawing on usage credits; `FORCE_PROMPT_CACHING_5M=1` overrides | WebFetch `code.claude.com/docs/en/prompt-caching` § Cache lifetime; binary strings `ENABLE_PROMPT_CACHING_1H`=6, `FORCE_PROMPT_CACHING_5M`=3 | MEASURED | vendor doc + binary 2.1.183 |
| 18 | **Therefore `ENABLE_PROMPT_CACHING_1H=1` is a no-op for this fleet.** `credits_on` is `False` on 5,017/5,017 rows and `credits_used` is zero on every row — the credit-drawdown path that downgrades to 5 min has never fired | census of `account-utilization.jsonl` | MEASURED | 5,017/5,017 rows, 6.2 days |
| 19 | **Subagents get the 5-minute TTL even on a subscription** — "the automatic one-hour TTL applies to the main conversation" — and a subagent's first request never reads the parent's cache | prompt-caching page § Subagents and the cache | MEASURED (doc, quoted) | vendor doc |
| 20 | **Cache is scoped per-machine *and* per-directory**, worktrees included: "two sessions in different directories build different prefixes and miss each other's cache. That includes worktrees of the same repository." The documented remedy (suppress per-machine system-prompt sections) is **Agent-SDK-only**, not CLI | prompt-caching page § Cache scope | MEASURED (doc, quoted) | vendor doc |
| 21 | That scoping bites here: **381 distinct project directories**, 80 touched in the last 7 days; `claude-infrastructure` alone spans 4 distinct cwds (root, 2 worktrees, 1 scratchpad) | `ls -d ~/.claude/projects/*/ \| wc -l` → 381; `find … -mtime -7` → 80 | MEASURED (directory count) / **INFERRED** (that each is a full cold prefix — token cost not measured) | 381 dirs |
| 22 | Cache economics: read ≈ **0.1×** input rate; write **1.25×** at 5-min TTL, **2×** at 1-hour TTL. Break-even: 2 requests at 5 min, ≥3 at 1 hour | `claude-api` skill → `shared/prompt-caching.md` § Economics | MEASURED (vendor) | — |
| 23 | Cache-read tokens **do not count toward ITPM** on all current models (only retired Haiku 3.5 counts them) — so caching raises effective throughput, not just lowers cost | rate-limits page § Cache-aware ITPM | MEASURED (doc, quoted) | vendor doc |
| 24 | **`ccusage`** reads local agent-CLI usage data, reports daily/monthly/session/5-hour-block, and **cannot track subscription quota**: "explicitly cannot track subscription quotas — it analyzes only local stored usage data converted to cost estimates using cached pricing" | WebFetch `github.com/ryoppippi/ccusage` | MEASURED (upstream doc) | 18k★, 1,629 commits, actively maintained |
| 25 | **`claude-monitor`** (Maciek-roboblog) *estimates* plan limits by P90 over a 192-hour history with hardcoded per-plan token caps (Pro ~44k / Max5 88k / Max20 220k per 5-h window) | WebSearch → repo README / PyPI | INFERRED (search summary, not fetched source) | secondary sources |
| 26 | Neither OSS tool is installed here | `command -v ccusage claude-monitor ccm` → empty | MEASURED | — |
| 27 | Anthropic's official dashboards and the Claude Code Analytics API are **Team/Enterprise/Console-only**; an individual Max subscriber has no analytics dashboard and no analytics API. OTel is the one path that "works on every setup" | WebFetch `code.claude.com/docs/en/analytics` (plan table lists only Teams/Enterprise and Console) + costs page: "OpenTelemetry export works on every setup and is the only option that streams per-user token and cost metrics into your own observability stack in near real time" | MEASURED (doc, quoted) | vendor doc |
| 28 | `/insights` writes a local HTML report to `~/.claude/usage-data/report.html` over ≤200 unseen sessions per run — available on any plan — but **its analysis runs through your own account and its tokens count against your plan** | costs page § Analyze your usage patterns | MEASURED (doc, quoted) | vendor doc; dir absent locally (never run) |

---

## Method

**What I ran.**

1. **Config census with a positive control.** `grep -rn "ENABLE_TELEMETRY\|OTEL_"` across `~/.claude*/settings*.json`, `~/.claude.json`, `~/.zshrc`, `~/.zprofile`, `~/.bashrc` → zero hits. Because a bare zero is not evidence, the same five files were scanned for `"hooks"` → 42/42/42/42/41. The absence is real, not an instrument failure.
2. **Repo-wide grep** (`--exclude-dir=.git`) for the same tokens → 6 hits, all prose in `bin/cc-suggest-filter`, `bin/cc-1p-events`, and two research docs. No configuration anywhere.
3. **Binary string extraction.** `~/.claude-versions/2.1.183/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude` is a **Mach-O 64-bit arm64 executable**, not a JS bundle — the first grep attempt returned empty because GNU grep suppresses binary matches without `-a`. Re-run with `/usr/bin/grep -a -o … | wc -l` (explicit path: the Bash tool runs zsh and this repo rewrites `grep`). Fifteen tokens counted, plus one deliberate **negative control** (`ZZZ_NEGATIVE_CONTROL_NOT_PRESENT` → 0) proving the instrument can return zero.
4. **Store discovery and census.** Found `UTIL_PATH` at `bin/claude-accounts:2242`, then parsed all 5,017 rows of `~/.claude/logs/account-utilization.jsonl` in python: per-account row counts, field set, `weekly_pct` null rate, inter-sample gap distribution on `acct=next` (n=1,253), and a >5 pp-drop scan for weekly resets.
5. **Six vendor doc fetches**, all quoted rather than paraphrased: `monitoring-usage`, `costs`, `prompt-caching` (Claude Code), `api/rate-limits` (platform), `analytics`. Plus the `claude-api` skill for current model IDs, pricing, and cache multipliers rather than reciting from memory.
6. **Two OSS fetches/searches**: `github.com/ryoppippi/ccusage` (fetched), `Claude-Code-Usage-Monitor` (search only).

**Sample sizes and coverage.** The utilization census is a **population**, not a sample: all 5,017 rows on disk, 6.2 days, 4/4 accounts. The gap analysis is 1 of 4 accounts (1,253 of ~5,013 gaps, 25%) — the four accounts are written in the same batch by the same sweep, so the cadence generalizes, but I did not verify that. The transcript corpus was **not** sampled for this axis; A8 is a vendor/OSS axis and the corpus belongs to A1–A3.

**What I could not measure, and why.**

- **Whether OTel export costs zero tokens, directly.** I did not run a controlled A/B of `input_tokens` with telemetry on vs off. The claim rests on architecture (a separate exporter, documented as such, with no documented context-injection path) plus the in-repo 5,979-line console-exporter run. It is **INFERRED**, and it is the load-bearing claim — see falsification below.
- **2.1.220 binary strings.** Only 2.1.113 / 2.1.114 / 2.1.183 exist under `~/.claude-versions/`; `current` → 2.1.114. Prior art and the system context both reference 2.1.220 behavior. All binary findings are therefore stamped **2.1.183**, and every one of them is corroborated by the current vendor docs, so version drift would have to contradict both.
- **The token cost of per-directory cache fragmentation.** I counted directories (381 total, 80 active/7d) but did not measure the cold-prefix token cost per new worktree. Reported as a mechanism, not a number. **Abstained rather than imputed.**
- **`claude-monitor` internals.** Search-summary only; I did not fetch the source. Its P90 numbers are third-hand and marked INFERRED.
- **Whether `/usage`'s attribution algorithm is reproducible from our transcripts.** The doc says it is computed from local session history; I did not verify that every input it uses is present in the JSONL. That is the single highest-value follow-on.

---

## Recommendations

| # | Action | Expected effect (quantified where possible) | Quality risk | Effort |
|---|---|---|---|---|
| R1 | **Correct the brief's premise before any design work**: the usage time-series store exists (`~/.claude/logs/account-utilization.jsonl`, 5,017 rows / 4 accounts / 6.2 d / 100% weekly coverage / 5 resets captured). Any "we must start recording" proposal is already-solved work. | Deletes an entire build track. Point-in-time readings become a 6-day series with ~6-min resolution — pace-to-100% becomes computable, not guessed. | NONE | zero (already on disk) |
| R2 | **Enable native OTel with `OTEL_METRICS_EXPORTER=otlp` / `OTEL_LOGS_EXPORTER=otlp` in the `env` block of the four `settings.json`**, pointed at a local collector. This is the numerator instrument, and it is token-free by construction. | Gains 8 metrics + 15 events per session — incl. `tool_decision`, `api_error`, `active_time.total`, `code_edit_tool.decision` — that transcripts do not carry, at 0 context tokens. Default flush 60 s metrics / 5 s logs. | **LOW** — no context impact by design; the residual risk is the exporter's own CPU inside the hook-chain budget (`docs/plans/HOOK_CHAIN_COST.md`). | S — 4 env blocks + one collector |
| R3 | **Adopt an OTLP backend rather than building a store**: any of Langfuse / Helicone / OpenLLMetry, or a plain `otelcol` + file exporter, terminates R2. Do **not** write a bespoke ingester. | Removes the ingest/schema/retention build entirely; the wire format is already OTLP. | LOW | S–M |
| R4 | **Reject `ENABLE_PROMPT_CACHING_1H=1`.** Measured: `credits_on` False on 5,017/5,017 rows. The 1-h TTL is already automatic on a subscription and the credit-drawdown downgrade has never fired here. Setting it changes nothing and adds a false lever. | 0 tokens saved. Prevents shipping a no-op and the belief that it did something. | NONE | zero (a deletion) |
| R5 | **Do not adopt `ccusage` or `claude-monitor` as a data source.** `ccusage` explicitly cannot read subscription quota; `claude-monitor` *estimates* limits by P90 over 192 h. We read the real numbers from `api/oauth/usage` and already keep the series. Adopting either would replace a measurement with an estimate. | Avoids a strict downgrade in denominator fidelity. | NONE (adopting them is the risk) | zero |
| R6 | **Reproduce `/usage`'s per-skill / per-subagent / per-plugin / per-MCP-server attribution locally.** The vendor states it is "computed from local session history on this machine" — i.e. derivable from the JSONL we already hold, not a server-side secret. This is the one genuinely new *capability* the vendor surface reveals. | Turns "which of our 12-subagent fan-outs, which skills, which MCP servers actually consume the weekly allowance" from unanswerable into computable — directly serving the use-it-or-lose-it goal. | LOW | **M–L** — needs the algorithm reverse-derived; verify inputs exist in JSONL first |
| R7 | **Investigate the subagent 5-minute TTL against the standing N=12 research fan-out.** Subagents get the 5-min TTL even on a subscription and never read the parent's prefix; a 12-way fan-out is 12 cold prefixes. Measure before acting — the workflow fan-out path already staggers agents so later ones read the first one's cache. | Unquantified. Could be material at N=12, could be already-mitigated by the documented fan-out hold. Measure first. | **MEDIUM** if acted on blind — reducing N would cut research breadth, which the operator policy forbids trading for tokens. Measurement only. | M |
| R8 | **Note, do not fix, the per-directory cache split.** Cache is scoped per-machine *and* per-directory including worktrees; 381 project dirs / 80 active in 7 d. The documented remedy is Agent-SDK-only and unavailable to the CLI. | Prevents a wasted attempt at a fix the vendor does not expose. File as an open question, not a task. | NONE | zero |

---

## What would falsify my headline

1. **The load-bearing claim.** If enabling `CLAUDE_CODE_ENABLE_TELEMETRY=1` measurably raises `input_tokens` on otherwise-identical turns, OTel is not token-free and R2 collapses. **The decisive test is cheap and I did not run it**: capture `message.usage.input_tokens` across N matched turns with telemetry off, then on, same cwd/model/effort, and compare. A single non-zero delta refutes it. (Architecture says the delta must be zero; architecture is not a measurement.)
2. **The denominator claim.** If any OTel metric or event attribute carries a quota/allowance/reset value I did not find — the enumerated metric and event tables are the whole surface, so this would mean the doc is incomplete — then OTel alone suffices and the oauth/usage store is redundant. Falsify by running the console exporter for one session and reading every attribute key emitted.
3. **The store claim.** If `account-utilization.jsonl` stops being written (it is a side-car in `claude-accounts` that swallows every error by design, per its own BLAST RADIUS comment), the series silently freezes with no alarm. Falsify — or confirm the risk — by checking `mtime` freshness; it was 4 minutes stale at measurement, but a swallowed-error recorder is exactly the shape that dies quietly. **This is the store's real weakness, not its coverage.**
4. **Version drift.** All binary findings are from **2.1.183**, not the 2.1.220 the fleet reportedly runs. If 2.1.220 renamed `api/oauth/usage` or the `seven_day*` keys, finding 8 is stale. The vendor docs corroborate independently, so both would have to be wrong together.
5. **The `/usage` reproducibility claim (R6).** If the per-MCP-server and per-subagent attribution needs a field Claude Code computes in memory and never writes to the JSONL, R6 is not buildable locally and its "computed from local session history" wording is looser than I read it. Falsify by attempting the derivation on one session and diffing against what `/usage` renders for it.
