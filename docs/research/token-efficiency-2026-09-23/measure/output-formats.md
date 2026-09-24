# Output formats: per-line and per-item overhead in tool results

Axis: what tools return (Bash, Read, WebFetch, MCP, …) and how much of it is format rather than content.
Window: 2026-09-09 → 2026-09-23 (14 days, the whole extract population: 4,858 transcript files).
Every $ figure is a **list-price weight**. The fleet is billed by subscription quota, not dollars. Each
figure is given twice: at each response's own model, and at Opus 5.5.

## Answer first

1. **Format overhead in tool results is small.** Every removable per-line or per-item pattern I could find
   adds up to about **$192 at each response's own model, or $97 at Opus 5.5, over 14 days**. That is
   **0.6% of fleet spend** and about 4% of what tool results cost. (MEASURED bytes × ESTIMATED tokens per
   character from the real tokenizer × MEASURED persistence weight.)
2. **ANSI is a non-issue.** Across 181k unique tool results, escape sequences total **30 KB in 319 results,
   about $1**. None of our CLIs emits ANSI when stdout is not a TTY. Adding NO_COLOR would save nothing.
3. **Volume and persistence cost money; format does not.**
   - Tool results cost **$5.1k own-model / $2.7k at Opus 5.5 (15.7% of fleet)**. Bash alone is $4.1k / $2.1k.
   - Main-thread Bash is **$2.5k** even though it is only 31% of Bash characters. A main-thread result is
     re-read by **148 later responses** on average, against about 20-25 in agents.
   - `sed -n` file slices are the single largest program, at **$1,047 / $540**.
4. **Our own CLIs are 0.5% of fleet spend** ($158 / $79 across 8.7k calls). The largest is `cc-backlog` at $50 / $25.
5. **The one knob with material upside is `bashOutputMaxChars`.** It defaults to 30,000 and no config dir
   sets it. Lowering it to 16k or 12k would save at most **$419-683 own / $227-366 at Opus 5.5 over 14 days,
   gross**. The net saving is unknown: 59% of that gross comes from deliberate file reads, which the agent
   would re-read. Put it behind a flag and A/B it; do not change it directly.

## Method (re-derivable)

| step | script | output |
|---|---|---|
| Scan every in-window `tool_result` block for pattern bytes, and classify Bash commands by program (quote-aware; skips `cd`/`export`/assignment preambles) | `scripts/of_scan.py` (about 14 s, 4 workers, nice) | `data/output_formats.sqlite` table `tr`, 201,773 rows |
| Persistence weight per (file, response index) | `scripts/of_weights.py` | table `w` |
| Tokens per removed character, measured with the real tokenizer | `scripts/of_tokprobe.py`, `scripts/of_tokprobe2.py` | `data/of_tokprobe.json` |
| Price patterns, tools and programs | `scripts/of_analyze.py` | `data/of_analyze.json` |
| Simulate a lower inline cap | `scripts/of_threshold_sim.py` | `data/of_threshold_sim.json` |
| Survey repeated boilerplate lines (800-file sample) | `scripts/of_replines.py` | `data/of_replines.json` |
| Count `cd <abs> &&` prefixes (input side) | `scripts/of_cdprefix.py` | stdout |
| Binary thresholds | `scripts/of_binctx.py <term>` plus inline mmap searches | quoted below |

Run order is scan → weights → analyze. The scan rewrites `output_formats.sqlite` and drops `w`.

**Reconciliation against the extract (MEASURED).** The scan found 201,773 tool_results carrying 463.19M
characters. The extract's `item` table holds 201,695 carrying 463.23M. 201,693 rows join on
(file, tool_use_id) and 201,693 of 201,695 agree on character count.

**Persistence weight (ESTIMATED model, MEASURED inputs).** A token appended after response *s* is
cache-written once by response *s+1* (1.25× input at 5m TTL, 2× at 1h, taken from that response's own
`cc_5m`/`cc_1h`) and cache-read by every later xdup=0 response in the same file (`cr_mult` × input).
- W is summed at each response's own model and again at Opus 5.5.
- The window has no compactions (`ctx.n_compact` is 0 in every file).
- The model ignores cache-expiry re-writes (so it under-weights) and Claude Code's time-based microcompact
  (so it would over-weight if that feature is active; see Gaps).

**Control:**
- All visible items priced this way at 2.27 characters per token come to $21.5k own-model, against the
  fleet's MEASURED cache spend of $28.2k.
- The remaining $6.7k is plausibly the system prompt and tool schemas, which are not items.
- The decomposition therefore does not exceed the total it decomposes.

**Tokenizer (MEASURED oracle).** Headless `claude -p "/context"` calls the free count_tokens API and reports
each memory file's tokens.
- Each probe writes a real-sample text of about 30-36k characters as the project CLAUDE.md of a scratch dir
  under `/tmp/ofprobe`, fenced so `@` imports are not evaluated. Transcript content never enters the repo.
- It is measured in two forms: original, and with the pattern removed.
- A fence-only baseline is subtracted. Resolution is 0.1k tokens.

| probe | chars/token (original) | tokens per removed char |
|---|---:|---:|
| plain Bash output | 2.27 | — |
| Read output | 2.24 | line-number prefixes 0.568 (sparse-10: 0.563) |
| path-heavy output | 1.98 | repo/worktree root prefix 0.455; `/Users/chrisren/`→`~/` 0.403 |
| JSON (MCP) | 1.79 | minify 0.24 (±100-token resolution) |
| box-drawing heavy | 2.43 | box chars 0.33, rule/banner lines 0.22 (±100) |
| ANSI-bearing | 2.09 | escape sequences 0.62 |
| CR/progress | 2.37 | overwritten CR segments 0.39 |
| table padding (3+ inner spaces collapsed to 2) | — | **0.00** (under 100 tokens for 1,501 chars; space runs are single tokens) |
| `Shell cwd was reset to …` note | — | 0.424 (about 31 tokens per note) |

These are counts under the /context model's tokenizer (Opus 5.5). Opus 5 and Fable 5.1 may tokenize
slightly differently (ESTIMATED equal).

## 1. Patterns: bytes, tokens, and persistence-weighted $ (14 days, xdup=0)

| pattern | removable bytes | results | tokens (est) | $ own | $ Opus 5.5 | basis |
|---|---:|---:|---:|---:|---:|---|
| absolute repo/worktree/config-dir root prefixes | 3,456,207 | 32,257 | 1.57M | 76 | 37 | probe |
| Read line numbers (keep every 10th) | 2,321,395 | 3,496 | 1.31M | 27 | 15 | probe (all numbers: $30 / $17) |
| `Shell cwd was reset to <project>` note | 882,094 | 12,041 | 0.37M | 22 | 11 | probe; 12,039 of them are in **main threads** |
| `/Users/chrisren/` → `~/` (alternative to the row above; overlaps it) | 1,271,060 | 34,517 | 0.51M | 22 | 11 | probe |
| grep-style repeated `path:` on consecutive lines | 1,688,735 | 5,189 | 0.77M | 21 | 11 | ESTIMATED (path ratio) |
| box-drawing characters | 756,609 | 8,881 | 0.25M | 9 | 5 | probe (±100 tokens) |
| JSON repeated keys (upper bound; a columnar form still needs a header) | 524,744 | 643 | 0.29M | 7 | 4 | ESTIMATED |
| warning lines (`⚠`/`WARNING`) | 314,282 | 1,454 | 0.14M | 7 | 3 | ESTIMATED; content, mostly not removable |
| auto-mode denial text | 219,939 | 232 | 0.10M | 5 | 3 | ESTIMATED; harness-owned |
| CR-overwritten spinner segments | 410,600 | 2,131 | 0.16M | 5 | 3 | probe |
| JSON pretty-print (minify) | 845,735 | 844 | 0.20M | 5 | 3 | probe (±100) |
| WebSearch `REMINDER: You MUST include the sources…` | 480,200 | 4,802 | 0.21M | 4 | 2 | ESTIMATED; harness-owned |
| rule/banner lines | 342,580 | 1,502 | 0.08M | 2 | 1 | probe (±100) |
| **ANSI/OSC escapes** | **30,360** | **319** | **0.02M** | **1** | **0** | probe |
| `<system-reminder>` inside tool_result text | 21,725 | 193 | 0.01M | 1 | 0 | ESTIMATED |
| progress-bar lines | 28,545 | 78 | 0.01M | 0 | 0 | probe |
| table padding whitespace | 7,053,964 | 59,611 | ≈0 | 0 | 0 | probe: free |
| **sum of non-overlapping rows** | | | **5.5M** | **192** | **97** | 0.6% of fleet $32.5k / $18.3k |

MEASURED bytes (`of_scan.py`); tokens and $ ESTIMATED (probe ratio × `of_weights.py`).

- **ANSI by program:** echo 4.9 KB, cat 4.8 KB, `python3 -c` 2.7 KB, for-loops 2.6 KB, ollama 1.5 KB,
  deploy-status.sh 1.1 KB, kitty-setup.sh 0.7 KB. Our CLIs contributed 1 result (claude-accounts, 161 bytes).
- **Statically:** `cc-backlog`, `session-continue.sh`, `ship-land.sh`, `cc-decide`, `cc-await-ping`,
  `cc-custody`, `cc-notify`, `wrap-ledger.sh`, `deploy-live.sh`, `cc-bats` and `cc-mission` contain no escape
  codes at all.
- `claude-accounts` and `operator-readout.sh` use colour and have TTY or NO_COLOR guards.
- `handoff-fire.sh` has 2 escape references without a guard, but none reached a transcript.

## 2. Tool results by tool, and Bash by program

| tool | results | chars | tokens (est) | $ own | $ Opus 5.5 |
|---|---:|---:|---:|---:|---:|
| Bash | 152,376 | 299.4M | 131.9M | 4,126 | 2,146 |
| Read | 8,150 | 53.8M | 24.0M | 506 | 281 |
| WebFetch | 4,307 | 26.3M | 11.6M | 237 | 125 |
| WebSearch | 4,822 | 14.0M | 6.2M | 117 | 64 |
| all MCP (40 tools, mostly ms365) | 797 | 3.9M | 2.2M | 75 | 37 |
| **all tool results** | 181,127 | 400.0M | | **5,114** | **2,679** |

Bash by context:

| context | results | chars | $ own | $ Opus 5.5 | mean later reads |
|---|---:|---:|---:|---:|---:|
| main | 75,953 | 91.8M | 2,476 | 1,210 | 148 |
| workflow agents | 61,031 | 162.3M | 1,249 | 712 | 20 |
| subagents | 15,392 | 45.4M | 401 | 224 | 25 |

**Bash result sizes** (MEASURED): p50 644 chars, p90 5,275, p99 17,531, max 66,577.
- 86% of Bash $ sits in results between 1k and 30k characters: 30% at 1-4k, 31% at 4-10k, 17% at 10-20k and 7% at 20-30k. Results under 1k account for 14%.
- 1,274 results hit the 30,000-character inline cap and were replaced by the `<persisted-output>` preview.

**Top 10 Bash programs by $** (all generic tools; `echo` and `(for-loop)` are multi-statement scripts whose first statement is an echo or a loop):

| program | calls | chars | p50 | p90 | p99 | $ own | $ Opus 5.5 |
|---|---:|---:|---:|---:|---:|---:|---:|
| sed | 15,379 | 75.0M | 3,591 | 10,446 | 22,391 | 1,047 | 540 |
| echo … | 18,178 | 36.6M | 1,001 | 4,996 | 14,266 | 522 | 261 |
| grep | 17,313 | 32.8M | 978 | 4,643 | 13,976 | 427 | 224 |
| cat | 12,330 | 31.6M | 321 | 8,472 | 25,016 | 387 | 208 |
| python3 -c | 12,029 | 20.9M | 547 | 4,679 | 17,075 | 245 | 132 |
| ls | 6,804 | 13.5M | 925 | 4,584 | 18,595 | 186 | 96 |
| for-loops | 8,713 | 14.8M | 534 | 4,373 | 17,109 | 170 | 92 |
| git show | 2,330 | 8.1M | 2,456 | 7,565 | 18,214 | 118 | 65 |
| wc | 1,443 | 4.2M | 1,089 | 7,914 | 21,462 | 64 | 34 |
| curl | 4,527 | 7.5M | 609 | 4,378 | 13,006 | 63 | 36 |

Other git commands: `git log` $32, `git fetch` $23, `git diff` $21, `git status` $12.

**Our CLIs, top 10 by $** (MEASURED; none emits ANSI when not a TTY; none prints banners of consequence):

| CLI | calls | chars | p50 | p90 | max | $ own | $ Opus 5.5 | notable overhead |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| cc-backlog | 1,546 | 2.33M | 312 | 4,262 | 25,534 | 50 | 25 | `list --all` 573 KB; `--help` read 119 times, 314 KB |
| session-continue.sh | 2,176 | 0.37M | 30 | 474 | 17,236 | 17 | 8 | 40 KB of absolute root paths; 321 later reads (main threads) |
| ship-land.sh | 859 | 0.54M | 464 | 1,057 | 9,121 | 15 | 7 | 56 KB of root paths; 6 KB of `⚠` lines |
| cc-decide | 265 | 0.50M | 347 | 3,309 | 29,723 | 15 | 7 | — |
| claude-accounts | 285 | 0.40M | 1,139 | 2,502 | 16,952 | 7 | 4 | 1.1k box chars |
| cc-await-ping | 881 | 0.29M | 305 | 316 | 3,258 | 7 | 3 | 52 KB of root paths |
| cc-custody | 115 | 0.14M | 515 | 2,247 | 26,061 | 6 | 3 | — |
| handoff-fire.sh | 278 | 0.29M | 902 | 2,035 | 6,927 | 6 | 3 | 17 KB of `⚠` lines |
| cc-notify | 648 | 0.35M | 453 | 857 | 6,924 | 5 | 3 | — |
| wrap-ledger.sh | 541 | 0.20M | 284 | 632 | 19,479 | 3 | 2 | — |

All our CLIs together cost $158 own / $79 at Opus 5.5 over 8,719 calls, 0.5% of fleet spend. Other named tools:
- deploy-live.sh: $3 own (273 calls).
- bats: $18 own (931 calls).
- operator-readout.sh: not among the top programs.

## 3. Binary thresholds (Claude Code 2.1.280, `claude.exe`, MEASURED by source inspection)

| threshold | value | override | where |
|---|---|---|---|
| Bash inline output cap | **30,000 chars** (`gxn`); longer output is persisted to a file and replaced by a preview | settings key **`bashOutputMaxChars`**, clamped to 4,000-128,000 (`zpo`/`PGe`) | `vje(){return g(Ye().bashOutputMaxChars)??gxn}` |
| `BASH_MAX_OUTPUT_LENGTH` | default 30,000, capped at 150,000 (`Wur`). Per the settings description it "on its own only sizes the read-back window"; `bashOutputMaxChars` replaces it when set | env | `Yne()` |
| persisted-output preview | **2,000 chars** (`Pye`), cut back to the last newline if that is past 50% of the cap; wrapper `<persisted-output>Output too large (X). Full output saved to: <path> Preview (first 2KB): …</persisted-output>` | none | `dce()`, `SBe()` |
| generic tool-result persist threshold | `min(tool.maxResultSizeChars, 50,000)` (`L$`), unless the remote flag `tengu_velvet_ibis` sets a per-tool value; fallback 400,000 (`Vpo`) | GrowthBook only | `VRe()`, `V()` |
| MCP output cap | **25,000 tokens** (`P`) | env `MAX_MCP_OUTPUT_TOKENS`, then remote `tengu_velvet_ibis.mcp_tool`; over the cap the output is truncated with `[OUTPUT TRUNCATED - exceeded N token limit]` | `u()` in the MCP chunk |
| hook output cap | **10,000 chars** (`Kpo`); longer hook output is persisted with the same 2 KB preview | none found | `ine(e,r,n,{threshold:s=Kpo})` |
| Read default line limit | **2,000 lines** (`Hvt`) | none (per-call `limit`) | Read prompt `By default, it reads up to ${Hvt} lines` |
| Read max tokens | **25,000** (`jyr`) | env `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS` | `J5()` |
| Read line-number separator | tab or `→`, chosen by remote flag `tengu_tab_read_sep` | GrowthBook only | `Vtt()` |
| Bash edit diff appended to results | `bashEditDiffEnabled`, on by default in auto/bypass modes | settings | settings schema |
| cwd reset note | `Shell cwd was reset to <cwd>` is appended when a command leaves the cwd outside the project dir and `additionalDirectories`, or always when `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` is set | settings `additionalDirectories` | `xvn()`, `Rvn` |
| old-result clearing | a time-based microcompact that replaces old results with `[Old tool result content cleared]` exists (`tengu_time_based_microcompact`, keep-recent) | remote flag | not observable in transcripts |

**Overrides in force:** none. `bashOutputMaxChars`, `BASH_MAX_OUTPUT_LENGTH`, `MAX_MCP_OUTPUT_TOKENS`,
`CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS`, `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` and
`additionalDirectories` appear in none of the five config dirs' `settings.json` (MEASURED, grep).

## 4. Proposed fixes, ranked by estimated saving

| # | change | layer | category | est. saving / 14 d (own · Opus 5.5) | how estimated | quality risk | validate / roll back |
|---|---|---|---|---|---|---|---|
| 1 | `bashOutputMaxChars: 16000` (or 12000) in user settings | CC settings | **flag** | gross ≤ $419 · $227 (12k: ≤ $683 · $366); net unknown | `of_threshold_sim.py`: (chars − 2,260) × W for results over the cap. 59% is deliberate reads (sed/cat/head/tail/awk/git show) that would be re-read | medium: extra recovery turns, and the preview hides the tail | A/B on per-task $ and turns, plus `persisted` rate and follow-up Read/sed calls within 3 turns; remove the key to roll back |
| 2 | Put the worktree root in `additionalDirectories` for main sessions so `cd` persists | CC settings (permission scope) | **propose** (widens the permission surface) | about $22 · $11 in cwd notes, plus part of the $76 · $37 in root prefixes, plus part of the ESTIMATED ~$120 own spent writing and carrying `cd /abs &&` prefixes (4.58M chars in 73k commands, 39% of main and 56-58% of agent Bash calls) | pattern rows above plus `of_cdprefix.py` | low for tokens; the permission change is the operator's call | measure notes per session and cd-prefix bytes before and after |
| 3 | Stop printing absolute repo paths in our CLIs' routine output (session-continue.sh, ship-land.sh, cc-await-ping, cc-blockers, handoff-fire.sh, cc-backlog): print repo-relative paths | our scripts | direct, but **not worth it** | about $5 · $2.5 | share of root-prefix bytes in our CLIs (about 220 KB of 3.46 MB) × pattern $ | low | skip. Churn in hot scripts for $5 is a poor trade |
| 4 | Sparse Read line numbers (every 10th) | CC binary | propose (upstream) | $27 · $15 | readnum probe | low per the spec's evidence | upstream only; `tengu_tab_read_sep` is the only local-looking lever and it is remote |
| 5 | NO_COLOR / strip ANSI when not a TTY | our scripts | **drop** | about $1 | ANSI row | — | already true of every CLI we own |
| 6 | Minify JSON / columnar keys in MCP output | ms365 MCP server | drop | ≤ $12 · $7 | JSON rows | — | — |
| 7 | Grouped grep output (`rg --heading`) | agent habit | drop | ≤ $21 · $11 | grep repeated-path row | — | — |

**Net recommendation.** Format fixes have no material direct win on this axis. The measurable lever is
result volume in main threads (148 later reads each) and the Bash inline cap. Test the cap behind a flag;
leave the rest.

## Gaps

- **Microcompact.** Claude Code 2.1.280 contains a time-based microcompact that clears old tool results
  (`[Old tool result content cleared]`). Clearing happens at request build and is not in transcripts. If it
  is active for this fleet, the persistence $ above is overstated, and more so for main threads. The
  item-weighted control ($21.5k of $28.2k) does not rule it in or out.
- **Cache expiry re-writes** are ignored by W, which biases it low.
- **Tokenizer:** a single tokenizer (/context's). The box and JSON probes sit at ±100-token resolution. The
  grep-path, JSON-key, warning, denial and WebSearch-reminder ratios are ESTIMATED from the plain or path ratio.
- **Program classification is heuristic.** It takes the first non-setup statement, so multi-statement scripts
  land under `echo` or `(for-loop)`. Output from later pipeline stages is attributed to the first program.
- **The repeated-line survey is a sample** of 800 files (seed 5). The full-population regexes cover what it found.
- The **net** effect of a lower Bash cap needs an A/B test. Recovery-turn cost is not modelled.
- `rOe` (Read `maxSizeBytes`) was not resolved to a number.
- Hook `additionalContext` volume is outside this axis (tool returns only); only the hook cap is recorded here.
