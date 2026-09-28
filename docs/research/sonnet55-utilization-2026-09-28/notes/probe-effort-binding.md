# Probe: effort binding on CC 2.1.284 (and 2.1.280), read from API request bodies

Date: 2026-09-28. Probe: effort-binding. Accounts: next (`~/.claude-next`) and next4 (`~/.claude-quaternary`).
Scratch and raw evidence: `/tmp/s55/probe-effort-binding/`.

## Instrument

- **Proxy.** `/tmp/s55/probe-effort-binding/proxy.py` is a python `http.server` reverse proxy. It forwards to `https://api.anthropic.com` over TLS, streams the response back re-chunked, and logs one JSONL record per request (`req-<tag>.jsonl`). It also saves every full request body (`req-<tag>.jsonl.bodies/NNNNN.json`).
- **Wiring.** Each `claude` process got `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`, and each run had its own proxy and port.
- **Auth.** OAuth (Max) auth works through the proxy unchanged.
- **First failure.** The first attempt failed because Python's CA store could not verify the upstream certificate (`SSLCertVerificationError`). The fix was `cafile=/etc/ssl/cert.pem`. The failed attempt still captured the request (effort `low`); it is kept as `req-pc1-sslfail.jsonl`.
- **Runner.** `run.sh` runs `claude -p --output-format json --strict-mcp-config` from `proj/`. It unsets the parent session's `CLAUDE_EFFORT` and `CLAUDE_CODE_SESSION_ID/…` variables first. `CLAUDE_EFFORT` is output-only in 2.1.284 (strings: "Also exposed to hook commands and Bash as the CLAUDE_EFFORT env var"), so unsetting it is belt and braces.
- **Where effort appears in the request.** On 2.1.284 and 2.1.280, effort is sent in two places, and every captured 5.5-family request had the same value in both:
  1. top-level `output_config.effort`;
  2. a per-turn copy at `messages[1].output_config.effort` (beta `per-turn-control-2026-07-01`).

  Requests to `claude-sonnet-5` and `claude-opus-5` carry only the top-level field.
- **Reading the tables.** `show2.py` tags each request LEAD or SUB (system prompt >5000 chars = LEAD, 2828 chars = subagent) and by the probe marker in its first user message.
- **Positive control: PASS.**
  - `-p --model claude-opus-5-5 --effort low` gave `output_config.effort="low"`.
  - `--effort xhigh` gave `"xhigh"`.
  - MEASURED: runs `pcl` and `pcx`, `python3 show2.py req-pcl.jsonl` / `req-pcx.jsonl`.
- `--debug` was not needed.

## Result table: surface × model × build → effort sent (all MEASURED from proxy request bodies)

| # | Surface | Model (request `model`) | Build | Effort sent | Thinking sent | Run tag |
|---|---|---|---|---|---|---|
| ctl | top-level `--effort low` | claude-opus-5-5 | 284 | **low** | adaptive/omitted | pcl |
| ctl | top-level `--effort xhigh` | claude-opus-5-5 | 284 | **xhigh** | adaptive/omitted | pcx |
| a | top-level, no `--effort`, settings `effortLevel:"high"` present | claude-opus-5-5 | 284 | **medium** | adaptive | a-opus-284 |
| a | same | claude-sonnet-5-5 | 284 | **medium** | adaptive | a-son-284 |
| a | top-level, no `--effort`, `--setting-sources project,local` (user settings dropped) | claude-opus-5-5 | 284 | **medium** | adaptive | a2-opus-284 |
| a | same | claude-sonnet-5-5 | 284 | **medium** | adaptive | a2-son-284 |
| a | top-level, no `--effort`, settings present | claude-opus-5-5 | 280 | **medium** | adaptive | a-opus-280 |
| a | top-level, no `--effort`, no user settings | claude-opus-5-5 | 280 | **medium** | adaptive | a2-opus-280 |
| a-ctl | top-level, no `--effort`, settings present | claude-opus-5 | 284 | high | adaptive | opus5-noflag-284 |
| a-ctl | top-level, no `--effort`, no user settings | claude-opus-5 | 284 | high | adaptive | opus5-noset-284 |
| b | Opus 5.5 lead `--effort high` → Agent(general-purpose, model:"sonnet") | claude-sonnet-5-5 | 284 | **high** (inherits lead) | adaptive | b-opus-284 |
| b | same lead → Agent(model:"opus") | claude-opus-5-5 | 284 | **high** | adaptive | b-opus-284 |
| b | same lead → Agent(no model) | claude-opus-5-5 | 284 | **high** | adaptive | b-opus-284 |
| b | Sonnet 5.5 lead `--effort high` → Agent(model:"sonnet") | claude-sonnet-5-5 | 284 | **high** | adaptive | b-son-284 |
| b | same lead → Agent(model:"opus") | claude-opus-5-5 (sent with `context-1m-2025-08-07` beta; modelUsage key `claude-opus-5-5[1m]`) | 284 | **high** | adaptive | b-son-284 |
| b | same lead → Agent(no model) | claude-sonnet-5-5 | 284 | **high** | adaptive | b-son-284 |
| b | Opus 5.5 lead `--effort high` → Agent(model:"sonnet") | **claude-sonnet-5** (the alias resolves to Sonnet 5 on 280) | 280 | **high** | adaptive | b-opus-280 |
| b | same lead → Agent(model:"opus") / no model | claude-opus-5-5 | 280 | **high** | adaptive | b-opus-280 |
| c | Opus 5.5 lead `--effort high` → Agent(subagent_type `eb-low-sonnet`; frontmatter `model: sonnet`, `effort: low`) | claude-sonnet-5-5 | 284 | **low** (honoured, overrides lead's high) | adaptive | c-lead-284 |
| c | same → `eb-low-opus` (`model: opus`, `effort: low`) | claude-opus-5-5 | 284 | **low** | adaptive | c-lead-284 |
| c | same → `eb-low-inherit` (no model, `effort: low`) | claude-opus-5-5 | 284 | **low** | adaptive | c-lead-284 |
| c | top-level `-p --agent eb-low-sonnet` (no `--model`/`--effort`) | claude-sonnet-5-5 | 284 | **medium** (frontmatter `low` IGNORED; catalog default wins) | adaptive | c-agentflag-son-284 |
| c | top-level `-p --agent eb-low-opus` | claude-opus-5-5 | 284 | **medium** (frontmatter ignored) | adaptive | c-agentflag-opus-284 |
| d | Opus 5.5 lead `--effort high` → Workflow `agent(p,{model:'claude-sonnet-5-5', effort:'low'})` | claude-sonnet-5-5 | 284 | **low** (honoured) | adaptive | d-284 |
| d | same → `agent(p,{model:'claude-sonnet-5-5'})` (no effort) | claude-sonnet-5-5 | 284 | **high** (inherits session) | adaptive | d-284 |
| d | same → `agent(p,{effort:'low'})` (no model) | claude-opus-5-5 | 284 | **low** | adaptive | d-284 |
| d-side | auto-mode permission classifier during the Workflow call (3 requests) | claude-sonnet-5 | 284 | none sent | `{"type":"disabled"}`, max_tokens 64 | d-284 |

All runs exited 0, `is_error:false`, and returned the expected marker, for example `PONG-S PONG-O PONG-I` or `WF-SON-LOW WF-SON-NOEFF WF-OPUS-LOW` (MEASURED: `out-<tag>.json`).

## (e) Can CC send `thinking.type:"between_tools"`? No.

- **Request bodies.** Over all 80 logged requests (23 proxy logs), the string `between_tools` appears **0 times** in any body. MEASURED: `between_tools_hits` field, `wc -l req-*.jsonl` = 80.
- **Binary.** All 12 `between_tools` hits in `/tmp/s55/cc284.strings` are dir-sync code (`tengu_dir_sync_between_tools_*`, `takeInBetweenToolCalls`, `trigger:"between_tools"`). None is a thinking type. MEASURED: python mmap/regex over cc284.strings.
- **Thinking-off knobs.** Every knob tried on Sonnet 5.5 `--effort high` **omits the `thinking` field entirely**. None of them sends `disabled` or `between_tools`, and effort `high` is still sent:
  - `CLAUDE_CODE_DISABLE_THINKING=1` (e-disthink);
  - `MAX_THINKING_TOKENS=0` (e-maxtt0);
  - `--settings '{"alwaysThinkingEnabled":false}'` (e-alwaysoff).
- **`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1`** still sends `adaptive` (e-disadapt).
- **Omitting `thinking` does not turn thinking off on Sonnet 5.5.** The vendor docs say adaptive thinking is on by default. I tested this on a small counting problem, Sonnet 5.5 `--effort high`, `--tools ""`:

  | Run | Thinking field | Thinking tokens | Answer |
  |---|---|---|---|
  | t-base | adaptive | 477 | 206 |
  | t-off (`CLAUDE_CODE_DISABLE_THINKING=1`) | omitted | 358 | 206 |

  MEASURED: `usage.output_tokens_details.thinking_tokens` in `out-t-*.json`, n=1 each, so the 477-vs-358 gap is noise-level. **The thinking-off knobs are effectively no-ops on Sonnet 5.5, and the reachable floor in CC is `effort: low` with adaptive thinking.**

## Findings

1. **The catalog default is medium for both 5.5 models, and it did not change between 280 and 284** (Opus 5.5: medium on both builds).
   - The settings file's `effortLevel: "high"` is **not applied** to Opus 5.5 or Sonnet 5.5: the no-flag runs sent medium both with user settings and without them.
   - The pre-per-model saved level still applies to older models: `claude-opus-5` sent high. That result is ambiguous, because `claude-opus-5` also sends high with user settings dropped.
   - Consequence: any surface that launches a 5.5 model without `--effort` runs at **medium**, even on accounts whose settings say high. The fleet launcher always passes `--effort`, so it is unaffected. Bare-binary, IDE and `claude-latest -p` scorer paths are affected.
2. **An Agent-tool subagent with a `model` param only inherits the lead's live effort** (high→high), for Sonnet and Opus targets, on both builds. The Agent tool has no effort parameter.
3. **Frontmatter `effort:` is honoured on the Agent-tool (subagent_type) path.** It overrides the lead's high down to low. It is **ignored on the top-level `--agent` path**, which falls back to the catalog medium. This confirms #97829 for the `--agent` path only.
4. **Workflow `agent({effort})` is honoured** (low sent from a high lead). Omitting effort inherits the session effort (high).
5. **`between_tools` cannot be reached from CC 2.1.284.** The thinking-off knobs omit the field, and Sonnet 5.5 still thinks.
6. **Side findings:**
   - `Agent(model:"opus")` spawned from a Sonnet 5.5 lead is sent with the `context-1m-2025-08-07` beta (modelUsage `claude-opus-5-5[1m]`). The same call from an Opus lead is not.
   - On 280, `Agent(model:"sonnet")` resolves to `claude-sonnet-5`.
   - The auto-mode security-monitor classifier runs on `claude-sonnet-5` with thinking disabled and max_tokens 64.

## Limits

- Everything ran headless (`-p`). Interactive `/effort`, teammates (Agent Teams) and `--agent` with an explicit `--effort` were not probed.
- (c) and (d) were measured on 284 only.
- Each cell is one run (n=1). Every effort value is deterministic request data, not a sampled output, so n=1 is sufficient for the effort column. It is not sufficient for the thinking-token comparison.
- Spend was about 23 short headless sessions across next and next4 (ESTIMATED from the count of runs).

## Skeptic

Reviewer: skeptic for probe effort-binding, 2026-09-28. I re-read every artifact in `/tmp/s55/probe-effort-binding/` and recovered the exact launch argv from the prober's transcript (`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/63a44720-…/subagents/workflows/wf_0289642e-307/agent-a592198bc7a857eee.jsonl`), because `run.sh` does not log its arguments. I also ran one decisive check of my own, in `/tmp/s55/probe-skeptic-effort-binding/`.

**Verdict: most of the effort table holds. Finding 5 (between_tools unreachable) and the "floor is low + adaptive" corollary are REFUTED. The Finding 1 "Consequence" is overbroad. The inheritance rows (b, d-no-effort) have no differential.**

### Instrument
- **UPHELD. The proxy reads the right process and the right build.**
  - Each run had its own proxy log and port. A per-run marker appears in the first user message.
  - Every saved body carries `cc_version=2.1.280.*` or `2.1.284.*` in the billing header, matching the build dir the run used. MEASURED: regex over `req-*.jsonl.bodies/*.json`.
  - The installed versions are 2.1.280 and 2.1.284. MEASURED: `package.json` in `~/.claude-{280,284}`.
  - Subagent and classifier requests also went through the proxy, so no request path bypassed `ANTHROPIC_BASE_URL`.
- **Gap: the positive control proves only the `--effort` flag → body path.** No run shows a *settings* value changing the body. Every "settings not applied" row therefore rests on negative results.
  - Code in cc284.strings (`function G()` / `W()` / `hNr`) explains those results. User-settings top-level `effortLevel` is stored as `legacyUserEffort`. It is applied only to a hard-coded legacy set (`claude-sonnet-5`, `claude-opus-5`, …), which excludes the 5.5 ids. This corroborates the rows by code reading; it is not a run.
- **Account settings confirmed.** From the recovered argv, a-opus-284 and a2-son-284 used next, and a-son-284, a2-opus-284, a-opus-280 and a2-opus-280 used next4. Both `settings.json` files have `effortLevel:"high"`. MEASURED: python json read.
- **Environment clean.** `CLAUDE_CODE_EFFORT_LEVEL` is not in the parent env (MEASURED: `env | grep -i effort`). `run.sh` does not unset it, so this matters.

### Per-claim verdicts
| Claim | Verdict | Why |
|---|---|---|
| Effort sent twice (top-level and `messages[1].output_config`), equal on every 5.5 request; Sonnet 5 and Opus 5 send top-level only | UPHELD | 61/61 5.5 bodies match; `per-turn-control-2026-07-01` beta present on 5.5 and absent on claude-opus-5. MEASURED: python over bodies. |
| 1a. Default is medium for both 5.5 models; Opus 5.5 is medium on 280 and 284 | UPHELD | MEASURED rows a/a2. Caveat: the default resolves through `Vun()`: org default → GrowthBook `tengu_witty_wand` (null in both accounts' cache) → catalog `default_effort`. A server flag can therefore move it without a build change. |
| 1b. User-settings `effortLevel:"high"` is not applied to 5.5 models | UPHELD | MEASURED plus code (legacy-set gate). This holds for the top-level user `effortLevel` only. |
| 1c. The saved level still applies to claude-opus-5 | UNSUPPORTED by measurement | The note concedes this. Code supports it: claude-opus-5 is in the legacy set. |
| 1d. "Any surface that launches a 5.5 model without `--effort` runs at medium"; fleet launcher unaffected; `claude-latest -p` scorer paths affected | OVERBROAD / NOT MEASURED | Code shows four sources that do bind 5.5 without the flag: the `CLAUDE_CODE_EFFORT_LEVEL` env (highest precedence, `X4()`); `effortLevel` in project, local, `--settings` or policy settings (sets the top-level default for all models); user `modelSettings.<model>.effortLevel`; and a per-model level saved by `/effort`. None was probed. The launcher and scorer-path claims are inference: the probe ran neither. |
| 2. An Agent-tool subagent inherits the lead's live effort | UPHELD for 2.1.284 5.5 targets, no differential | The lead was only ever `high`, so no run shows the subagent tracking a *different* lead level. User settings cannot give 5.5 a high (rows a), and the spawn code adds an effort override only when the agent definition has one, so inheritance is the best explanation. It is an inference, not a differential measurement. |
| 2 (280, Sonnet target = claude-sonnet-5) | UNSUPPORTED | claude-sonnet-5 is in the legacy set, so user-settings `high` yields high with or without inheritance. The row cannot separate the two. |
| 2'. The Agent tool has no effort parameter | UPHELD | Agent `input_schema` properties = description, isolation, mode, model, name, prompt, run_in_background, subagent_type, team_name. MEASURED: `req-b-opus-284` body #1. |
| 3. Frontmatter `effort` is honoured via Agent(subagent_type) and ignored via `--agent` (medium) | UPHELD | A real differential (low under a high lead). On the `--agent` path, the agent's system prompt (`PONG-sonnet` / `PONG-opus`) and frontmatter model reached the request, so the agent did load and only the effort was dropped. The lead's tool calls passed no model/effort (verified from the body #5 tool_use). |
| 4. Workflow `agent({effort:'low'})` is honoured | UPHELD | Differential against a high lead. The script the lead sent kept the opts exactly (verified from the `req-d-284` body #8 tool_use). |
| 4'. Workflow `agent()` with no effort inherits the session | UPHELD for 284, no differential | Same caveat as claim 2. |
| 5. `between_tools` cannot be reached from CC 2.1.284 | **REFUTED** | See the decisive check below. The binary-string scan missed the generic `CLAUDE_CODE_EXTRA_BODY` pass-through (`function Wq` in cc284.strings). |
| 5'. The reachable floor is `effort: low` with adaptive thinking | **REFUTED** | Same run: `low` + `between_tools` was sent and accepted. |
| 5''. `between_tools` appears 0 times in 80 logged requests over 23 logs | UPHELD with count errors | The 0 hits and the 80 records are correct. There are 25 logs, not 23. 11 of the 80 records are SSL-failed retries of one request, and 12 records have no saved body (their count comes from the proxy's in-memory check). |
| 6. The three thinking-off knobs omit `thinking` and keep effort high | UPHELD | All three bodies have the identical top-level key set without `thinking`. MEASURED. |
| 6'. `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` still sends adaptive | UPHELD | Code: `Y4n()` applies that env only to opus-4-6 and sonnet-4-6. So it is a designed no-op on 5.5, whatever the env propagation. |
| 6''. Omitting `thinking` does not stop Sonnet 5.5 thinking | UPHELD (direction); magnitude unsupported | t-off used 358 thinking tokens. MEASURED: `out-t-off.json`. "Effectively no-op" rests on n=1, as the note says. |
| Side: Opus sub under a Sonnet 5.5 lead gets `context-1m-2025-08-07` | UPHELD | Beta present on `b-son-284` #3/#8, absent on `b-opus-284` #3/#7. MEASURED. |
| Side: 280 `sonnet` alias → claude-sonnet-5 | UPHELD | `b-opus-280` #2/#5. MEASURED. |
| Side: classifier runs on claude-sonnet-5, thinking disabled, max_tokens 64 | UPHELD | System head reads "security monitor for autonomous AI coding agents". MEASURED: `req-d-284` #5-7. |
| `CLAUDE_EFFORT` is output-only | UPHELD (code reading) | It is written into child env and stripped from spawn env. The effort input env is `CLAUDE_CODE_EFFORT_LEVEL`. |

### Decisive check (one run, next4, 2.1.284)
- **Command:**
  ```
  CLAUDE_CONFIG_DIR=~/.claude-quaternary ANTHROPIC_BASE_URL=http://127.0.0.1:18991 CLAUDE_CODE_DISABLE_THINKING=1 CLAUDE_CODE_EXTRA_BODY='{"thinking":{"type":"between_tools"}}' ~/.claude-284/node_modules/.bin/claude -p --model claude-sonnet-5-5 --effort low --strict-mcp-config --tools "" --output-format json "SKEP-BT: reply with exactly: ok"
  ```
  It ran through a copy of the same proxy.
- **Result:**
  - The request body carried `thinking:{"type":"between_tools"}`, `output_config.effort:"low"` and `messages[1].output_config.effort:"low"`, with `cc_version=2.1.284`.
  - The API returned HTTP 200 with `is_error:false`, result `ok`, `thinking_tokens: 0`, and modelUsage key `claude-sonnet-5-5` (no fallback).
  - MEASURED: `/tmp/s55/probe-skeptic-effort-binding/req-bt.jsonl`, `…/req-bt.jsonl.bodies/00001.json`, `…/out-bt.json`.
- **Limits of this check:**
  - n=1, with a trivial prompt. `thinking_tokens: 0` proves the setting was accepted, not that it cuts thinking on hard prompts.
  - The env var is process-wide. It would also reach subagents, Opus 5.5 and the claude-sonnet-5 classifier, where `between_tools` may 400. That was not tested.
  - I did not test whether the extra-body `thinking` survives *without* `CLAUDE_CODE_DISABLE_THINKING=1`, where CC sends its own adaptive field.
- **Spend:** one request, 24,817 cache-creation input tokens. MEASURED: `usage` in `out-bt.json`.
