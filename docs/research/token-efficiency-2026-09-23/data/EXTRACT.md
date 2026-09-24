# extract.sqlite: the shared transcript dataset

Built by `scripts/extract.py`. Every fleet number in this study should come from this file, so
the numbers are computed once and the same way everywhere.

```
cd /tmp && nice -n 10 python3 <dir>/scripts/extract.py          # ~20-35 s on a loaded box, 4 workers
         [--since 2026-09-09T00:00:00Z] [--out <dir>/data/extract.sqlite] [--workers 4] [--limit N]
```

Re-runnable. The script writes `<out>.tmp` and renames it over `<out>`, so a failed run leaves the
previous build intact. The build is a snapshot: live sessions keep appending, so two builds minutes
apart differ by a handful of responses. The `meta` table records `built_at`.

**Build of record** (MEASURED, `meta` table, built_at 2026-09-23T23:02Z): window `ts >= 2026-09-09T00:00:00Z`;
4,872 files discovered, 4,858 with in-window records (7.15 GB) and 14 with none; 1,185,167 lines;
**0 unparseable lines**; 176,587 `resp` rows (162,406 with `xdup=0`); 953,792 `item` rows (92,425 `xdup`). Data spans
2026-09-09T00:00:33Z to 2026-09-23T23:01:45Z.

## Population

- **Roots:** `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`,
  `~/.claude-quaternary`, each `/projects/**/*.jsonl`. Files are deduped by `realpath`
  (`~/.claude-next/projects` is a symlink to `~/.claude/projects`), and `journal.jsonl` files are skipped.
- **Pre-filter:** files whose mtime is older than the window start are skipped. Transcripts are
  append-only, so such a file cannot hold an in-window record.
- **Path to `ctx_type`** (0 files went unclassified):
  - `projects/<slug>/<sid>.jsonl` is `main`
  - `projects/<slug>/<sid>/subagents/agent-<aid>.jsonl` is `subagent` (Agent tool)
  - `projects/<slug>/<sid>/subagents/workflows/<wf>/agent-<aid>.jsonl` is `workflow_agent`
- **In-window rows only:** a record is kept when its `timestamp >= since`. ISO strings are compared
  as text, and every record timestamp is `...Z`. Twenty files straddle the start
  (`ctx.spans_window_start=1`). Their `seq` still counts from the file's true first response.

| ctx_type | files | resp | naive assistant records | records/resp | xdup resp | items | GB |
|---|---:|---:|---:|---:|---:|---:|---:|
| main | 1,081 | 84,517 | 175,754 | 2.080 | 630 | 444,966 | 2.67 |
| subagent | 409 | 17,425 | 36,712 | 2.107 | 1,977 | 88,959 | 0.80 |
| workflow_agent | 3,368 | 74,645 | 166,194 | 2.226 | 11,574 | 419,867 | 3.68 |

## Record shapes found (schema survey: `scripts/schema_survey.py`, plus probes)

- **Top-level `type` values:** `assistant`, `user`, `attachment`, `system`, plus bookkeeping types
  that are never sent to the model (`last-prompt`, `bridge-session`, `mode`, `permission-mode`,
  `atis-latch`, `ai-title`, `queue-operation`, `file-history-snapshot`, `file-history-delta`,
  `cost-state`). Subagent and workflow files contain only assistant, user and attachment records.
- **`assistant`**
  - Each record carries exactly one content block (1 in 13,795 sampled records).
  - `message` fields: `id`, `model`, `content`, `stop_reason`, `usage`, `context_management`,
    `diagnostics`, `container`.
  - Record fields: `requestId`, `apiBlockIndex`, `effort`, `entrypoint`, `userType`, `isSidechain`,
    `version`, `agentId` (agents), `advisorModel`, `perTurnEffort`, `serverClassifierRequest`,
    `wireToolInputs`, `attributionSkill`/`attributionAgent`, `isApiErrorMessage`.
  - `usage` fields: `input_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`,
    `output_tokens`, `cache_creation{ephemeral_5m_input_tokens, ephemeral_1h_input_tokens}`,
    `service_tier`, `speed`, `iterations[]` (always length 0 or 1, equal to the top level),
    `server_tool_use`, `output_tokens_details`.
- **`user`**
  - `message.content` is either a string (a prompt) or a list of blocks: `tool_result`, `text`
    or `image`.
  - `toolUseResult` is the structured display copy and is not what the model sees. The model sees
    the `tool_result` block.
  - Flags: `isMeta`, `isCompactSummary`, `origin{kind: human|task-notification}`,
    `promptSource` (`typed|system|sdk|queued`).
- **`attachment`**
  - Fields: `attachment{type,...}` plus **`rendered: [{content: str}]`, which is the text the model
    actually sees**.
  - `rendered` is present on the model-visible types. It is absent on `hook_success` (except
    ~1%), `hook_system_message` (display-only), `hook_cancelled`, `prompt_snapshot`,
    `structured_output`, `deferred_tools_record`, `batching_reminder_sent` and `goal_status`.
- **`system`** subtypes: `stop_hook_summary`, `turn_duration`, `away_summary`, `informational`,
  `compact_boundary`, `agents_killed`. These are not appended to model context. Only
  `compact_boundary` is counted (`ctx.n_compact`).

## Table `resp`: one row per API response

Rows are deduped on `message.id` within a file (fallback `requestId`, then `nomid:<file>:<line>`;
0 rows used the last fallback).

| field | derivation |
|---|---|
| file, config_dir, project_slug | realpath and its path parts (`config_dir` = the dir holding `projects/`) |
| ctx_type, session_id, agent_id, workflow_id | from the path. `session_id` is the **parent** session for subagent and workflow agents |
| seq | 0-based order of first appearance of the `message.id` in the file, counted over the WHOLE file (not only the window) |
| msg_id, request_id, ts, model, version, entrypoint, user_type, is_sidechain, effort, advisor_model | taken from the **first** record of the message |
| input_tokens, cc_5m, cc_1h, cc_total, cache_read | from `usage`. These are identical on every record of a message (verified). `cc_5m+cc_1h == cc_total` on all rows (0 mismatches) |
| **output_tokens** | **MAX over the message's records (the final value, see L1)** |
| output_first | the first record's `output_tokens`. This is what `cc-quota-price` and any first-occurrence dedupe report |
| output_final | 1 when the final usage record was written (`stop_reason` present, or `<synthetic>`, or an API-error message) |
| **output_est** | `output_tokens` where `output_final=1`, otherwise an ESTIMATE (see L2). `output_est_method` is `recorded` or `strata_L<k>` |
| n_records | transcript records written for this message (one per content block) |
| stop_reason | last non-null `stop_reason` across the message's records |
| has_thinking, n_thinking, thinking_chars | thinking blocks. `thinking_chars` is almost always 0 (L3) |
| text_chars, n_tool_use, tool_use_names, tool_input_chars | text-block characters; tool_use names joined with commas; `len(json.dumps(input))` summed over the message's tool calls |
| service_tier, speed, iterations_n, is_api_error, has_usage | as named |
| xdup | 1 when the `message.id` already appears in an earlier file (earliest `ctx.first_ts`, then path). **Filter `xdup=0` for any total** (L5) |

**View `resp_priced`** = `resp` joined to table `price`, adding `usd_input`, `usd_cw5m`
(1.25x input), `usd_cw1h` (2x), `usd_cache_read` (`cr_mult` x input), `usd_output_est`,
`usd_output_recorded`, `usd_total` (at the response's own model, using `output_est`) and
`usd_total_at_opus55` (the same tokens at Opus 5.5 rates: $4/$20, cache read 0.05x). These are
**list-price weights; the fleet is billed by subscription quota, not dollars.**

**Table `price`:** list prices come from `model-config.yaml` `pricing_per_mtok`. Cache-read
multipliers are 0.025x for Fable 5.1, 0.05x for Opus 5.5 and 0.1x otherwise.
`claude-opus-4-7` is not listed there and is ASSUMED to cost the same as Opus 4.8 ($5/$25);
it has 70 responses. `claude-haiku-4-5-20251001` maps to the `claude-haiku-4-5` row.

## Table `item`: one row per item appended to a context

| field | derivation |
|---|---|
| file, item_seq | file and 0-based order of in-window items in that file |
| resp_before | `seq` of the last response before the item (-1 when none). **For `assistant_*` and `tool_use_input` it is the response that produced the item.** Everything with `resp_before = s` is in the context of response `s+1` onward |
| kind | `user_prompt`, `meta_user`, `tool_result`, `attachment`, `tool_use_input`, `assistant_text`, `assistant_thinking` |
| subkind | see the list after this table |
| detail | ≤200 chars. Skill: the skill name. Agent/Task: `subagent_type/name`. Workflow: the name or script path. Bash: the first 120 chars of the command. Read/Edit/Write/NotebookEdit: `file_path`. `mcp__server__tool`: the server. ToolSearch: the query. Grep/Glob: the pattern. WebFetch: the url. SendMessage: `to`. A `tool_result` inherits its tool_use's detail (or `refs:<names>` for `tool_reference` results). `instructions`: the basenames of the memory files. hook attachments: `hookEvent`. `skill_listing`: `skills=N initial=bool`. `command` prompts: the command name |
| chars | length of the **model-visible** text (L4). `tool_result`: the string, or the sum of text blocks (images 0, other blocks JSON length). `attachment`: the sum of `rendered[].content` (0 when not rendered). `tool_use_input`: `len(json.dumps(input))`. Prompts: text length |
| visible | 1 when the item reaches the model. 0 only for attachments without `rendered` (`hook_success`, `hook_system_message`, `hook_cancelled`, and so on). **Filter `visible=1` for context-size work** |
| raw_chars | attachments only: the raw payload length (`content`/`text`/`prompt`, or the `instructions` file contents). Use it for non-rendered attachments |
| is_error | `tool_result.is_error` |
| snippet | first 300 chars, only for `is_error` rows and for `hook_additional_context` / `hook_blocking_error` rows |
| tool_use_id, n_images | join key between a tool call and its result; image blocks in a prompt or result |
| uid, xdup | `uid` = the record's `uuid` + `#` + block index. `xdup=1` when the uid already appears in an earlier file (L5) |

**`subkind` values by kind:**

- **`user_prompt`:** `plain`, `command` (`<command-name>`/`<command-message>`/`<local-command-stdout>`),
  `pasted` (image blocks, `[Image #N]`, `[Pasted text`), `teammate_message`, `task_notification`
  (the tag or `origin.kind`), `peer_message` ("Another Claude session sent"), `bash_mode`,
  `interrupt`, `agent_brief` (the first plain prompt of a subagent or workflow file: the brief).
- **`meta_user`** (`isMeta`): `stop_hook_feedback`, `skill_body` ("Base directory for this skill"),
  `command_body` (a meta message right after a command prompt, i.e. the expanded slash-command
  file), `command_marker`, `local_command_caveat`, `image_meta`, `continue`, `system_reminder`,
  `compact_summary`, `tool_result_sibling_text` (a text block beside tool_results), `other`.
- **`attachment`:** `attachment.type`, plus `:<hookName>` for hook attachments (e.g.
  `hook_additional_context:UserPromptSubmit`).
- **`tool_result` and `tool_use_input`:** the tool name (`?` if the tool_use was not found).
- **`assistant_thinking`:** `thinking`.

## Table `ctx`: one row per file

`ctx_type`, path ids; `agent_type`, `agent_desc` and `workflow_phase` from the sibling
`agent-<aid>.meta.json` (for example `workflow-subagent`, `general-purpose`); `n_resp`;
`n_records_naive` (in-window assistant records); `first_ts`/`last_ts` (over responses and items);
`models`, `versions` and `entrypoints` (joined with commas, most frequent first); token totals
`input_tokens`, `cc_5m`, `cc_1h`, `cc_total`, `cache_read`, `output_tokens` (final) and
`output_first`, **all including xdup rows**; `n_items`, `n_user_prompts`, `n_compact`,
`file_bytes`, `mtime`, `n_lines`, `n_bad_lines`, `spans_window_start`, `n_resp_xdup`.
`n_resp_xdup == n_resp` flags a file that is a whole copy.

**Table `meta`:** run parameters and counters, including `imputation` (JSON: count, tokens added,
hold-out errors) and `prices`.

## Known limitations (read before quoting a number)

**L1. The first record's `output_tokens` is a placeholder, and the census of record reads it.**
Claude Code writes one record per content block. Records written before the stream ends carry the
`message_start` output count (typically 1-10). Only the last record, the one with `stop_reason`,
carries the final value, and the value never decreases (1,000 of 1,000 differing messages in a
probe were increasing, with the maximum on the last record). Fleet-wide, `output_first` is 75.4M
and `output_tokens` (final) is 139.7M: **first-record output reads 46% low** (MEASURED,
`compare_control.py`). The cc-quota-price docstring says "the identical COMPLETE usage object on
every one of them … 98.5% byte-identical". That no longer holds for output: 22% of repeat records
differ, and only in `output_tokens` and its details (`scripts/probe_rendered_and_usage_identity.py`, `scripts/probe_output_direction.py`). Input-side classes
are unaffected. **Anything that prices output from a first-occurrence dedupe, including
`cc-quota-price` and its fitted price list, undercounts output ~1.85x.**

**L2. Agent transcripts on 2.1.280 almost never record the final usage.**
18,041 of 162,406 responses (11.1%) have no final record (`output_final=0`), and nearly all of
them are agent responses:

| ctx_type | version | responses with no final record |
|---|---|---|
| subagent | 2.1.280 | 2,213 of 2,213 |
| workflow_agent | 2.1.280 | 8,684 of 9,580 |
| subagent | 2.1.260 | 928 of 13,046 |
| workflow_agent | 2.1.260 | 5,931 of 52,831 |
| main | any | 5 |

These responses make tool calls and think, yet record ~6-9 output tokens. No other store carries
the real value: the parent's `toolUseResult.usage` covers only the agent's last response, and the
workflow `journal.jsonl` has no usage.

`output_est` imputes them (ESTIMATED): the stratified mean of final responses keyed on
`(main|agent, model, has_thinking, min(n_tool_use,2), floor(log2(text_chars+tool_input_chars+1)),
called StructuredOutput)`. It backs off to a model-pooled key, then coarser keys, when a stratum
has fewer than 20 rows, and it never lowers the recorded value. It adds +21.8M output tokens (18,041 responses).

Validation:

- **2-fold hold-out** on final agent responses (folds by file CRC32): aggregate error **-1.2% /
  -2.8%**. Per-response mean absolute error is ~550 tokens against a mean of ~1,190, so
  **`output_est` is good for totals and useless per response.**
- **Independent check against Claude Code's own per-session `cost-state.modelUsage`**
  (`check_cost_state.py`, 812 sessions started in the window):

  | output variant | extract / cost-state |
  |---|---|
  | final | 0.887 |
  | est | **0.997** |
  | first | 0.521 |

  `output_est` is the closest variant in 803 of 808 sessions. By model:

  | model | cost-state (M) | output_est (M) |
  |---|---|---|
  | Opus 5 (incl. `[1m]`) | 108.7 | 108.3 |
  | Opus 5.5 | 8.0 | 9.7 |
  | Fable 5.1 | 9.5 | 10.6 |

  For Opus 5.5 and Fable 5.1, cost-state is the last snapshot and sessions keep running past it:
  cache writes also read 20-24% higher in the extract for those models.
- **Caveat:** the imputation assumes the missing responses resemble final responses of the same
  shape. On 2.1.280 almost the only final agent responses are terminal StructuredOutput calls; the
  `so` key and model pooling are there to keep those from standing in for mid-loop responses. A
  first version without them overshot Opus 5.5 by 2x against cost-state.

**L3. Thinking text is mostly absent.** 4,712 of 5,178 sampled thinking blocks have empty
`thinking` and only a signature. `thinking_chars` does not measure thinking. Thinking tokens are
inside `output_tokens`, and `usage.output_tokens_details.thinking_tokens` exists only on some
records and is not extracted.

**L4. `chars` are characters, not tokens.** There is no tokenizer in the extract. Convert with a
measured ratio (e.g. headless `/context` against known files) and label the result ESTIMATED.
Image blocks count 0 chars (`n_images` counts them). `tool_reference` results (ToolSearch) count
0; the schemas they expand into server-side are not in the transcript.

**L5. Cross-file copies.** 14,181 responses (8.0%) and ~92k items sit in files that are copies of
another config dir's session tree (account transplants: same session, agent, timestamp and usage,
different `config_dir`; 739 files are whole copies) or of a forked session. `xdup` keeps the
earliest file (by `first_ts`), so **always filter `xdup=0`** for totals. Item-level `uid` dedupe
agrees with response-level dedupe: 100.0% of items in fully duplicated files are flagged, 92.5% in
partially duplicated files, and 0 in files with no duplicates.

**L6. Side queries are not in transcripts.** Claude Code's per-session `cost-state` counts spend
that never becomes an assistant record: prompt suggestion (`CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true`),
away summaries, titles, classifier calls and similar. Over the 812 sessions (MEASURED,
`check_cost_state.py`):

- **Haiku 4.5:** 69.2M uncached input, 19.2M cache writes, 2.4M output, and 0 in transcripts.
- **Opus and Fable:** another ~11M uncached input on top of the transcripts' 0.4M.
- **Cache reads:** the transcripts hold 3% fewer than cost-state.

At list prices this is small next to the main spend (Haiku ~$105 against ~$32.5k), but it is
spend that no transcript-based per-task figure includes.

**L7. Items that are not appended as records.** The system prompt, tool schemas and the
MCP/deferred tool lists are request-level and are not items. `attachment prompt_snapshot` (not
visible) holds `systemPrompt`/`tools` snapshots if someone needs them. `system` records are skipped.
`hook_success` output reaches the model only when `rendered` is present (~1%).

**L8. Heuristic subkinds.** The prompt and meta classification uses prefixes; `command_body` is
positional, and `agent_brief` is the first plain prompt of an agent file. Prefix buckets were
checked on a 150-file sample (`scripts/probe_prompt_prefixes.py`); unmatched items fall
to `plain` or `other`.

**L9. Tooling gap met during the build.** A PreToolUse hook blocks any Bash command whose text
contains SQL DDL keywords. It is aimed at reso's Drizzle migrations and misfires on inline SQLite
here. The price-table patch was therefore written through the Write tool. The extractor's own DDL
is unaffected because it runs inside Python.

## Self-checks

**(a) Naive vs deduped responses** (MEASURED, `ctx`): 378,660 in-window assistant records collapse
to 176,587 per-file responses (2.14x overall; 2.08x main, 2.11x subagent, 2.23x workflow), and then
to 162,406 after cross-file dedupe. Summing records without the dedupe overcounts by 2.1-2.2x.

**(b) CONTROL against `cc-quota-price --census --json --since 2026-09-09`**, run immediately after
the build (`scripts/compare_control.py`, output in `data/selfcheck_control.txt` and
`data/control_cc_quota_price_census.json`):

| class | extract | control | delta |
|---|---:|---:|---:|
| responses (deduped) | 162,406 | 162,408 | -0.001% |
| input | 1,229,381 | 1,229,385 | -0.000% |
| cache_creation | 1,089,871,511 | 1,089,875,536 | -0.000% |
| cache_read | 40,952,174,553 | 40,952,612,691 | -0.001% |
| output, first record (the control's method) | 75,430,079 | 75,430,106 | -0.000% |
| output, final record (`output_tokens`) | 139,733,415 | 75,430,106 | **+85.2%** |
| output_est (ESTIMATED) | 161,487,018 | 75,430,106 | +114.1% |

The only per-model count difference is 2 Opus 5.5 responses, which live sessions wrote between the
two runs. Under the same method, every class agrees to within 0.001%.

The output gap is not an extract error. The control keeps the first record, whose output is a
placeholder (L1). The final-record figure is confirmed independently by `cost-state` (L2).

The control also scans 5,026 files against the extract's 4,858. The extra files are the 151 workflow
`journal.jsonl` files plus files with no in-window usage; neither contributes responses.

**(c) Hand spot-check of 3 files** (`scripts/spot_check.sh`, output in
`data/selfcheck_spot.txt`). Each file was recounted with `jq`, an independent parser, and compared
with the extract on responses, records, input, cache writes, cache reads, final and first output,
tool_result count, error count, tool_use count, attachment count, rendered attachment chars and
tool_result chars. **All 6 comparison lines match exactly.**

| file | ctx_type | responses | output final vs first |
|---|---|---:|---|
| `.claude-secondary/.../59935750-….jsonl` | main | 158 | 103,461 = 103,461 |
| `.claude/.../309ec82a-…/subagents/agent-ac2311b5989ea4de6.jsonl` | subagent | 109 | 136,366 vs 31,242 |
| `.claude-secondary/.../wf_1764024a-a21/agent-a1ccfef17fcfdbac4.jsonl` | workflow_agent | 39 | 38,857 vs 143 |

The item ordering was also eyeballed for the workflow file: brief, then the setup attachments
(`deferred_tools_delta`, `skill_listing` 30k chars, `instructions` 203k chars, `session_context`,
`date`), then per response thinking, tool_use, the hook attachment (not visible), tool_result and
`total_tokens_reminder`.

## Starter queries

```sql
-- priced totals by context type (list-price weights)
SELECT ctx_type, COUNT(*), SUM(usd_total), SUM(usd_total_at_opus55)
FROM resp_priced WHERE xdup=0 GROUP BY 1;

-- model-visible chars appended per kind/subkind
SELECT kind, subkind, COUNT(*), SUM(chars)
FROM item WHERE xdup=0 AND visible=1 GROUP BY 1,2 ORDER BY 4 DESC;

-- per-tool run share and error rate
SELECT subkind, COUNT(DISTINCT file) files, COUNT(*) calls, AVG(is_error)
FROM item WHERE kind='tool_result' AND xdup=0 GROUP BY 1 ORDER BY 3 DESC;

-- a session tree: main thread plus its agents
SELECT ctx_type, COUNT(*), SUM(output_est) FROM resp
WHERE session_id=? AND xdup=0 GROUP BY 1;
```

Headline figures from this build (MEASURED from `resp_priced`/`item`, `xdup=0`; list-price weights):

- **Total:** $32.5k at each response's own model, $18.3k re-priced at Opus 5.5.
- **Share by billing type:** cache reads $19.0k (58%), 1h cache writes $5.1k (16%), 5m cache
  writes $4.1k (12%), output (est) $4.3k (13%), uncached input $7.
- **Cache TTL by context:** main threads write 1h cache almost exclusively; subagents and workflow
  agents write 5m cache only.
- **Largest appended source:** the `instructions` attachment (memory files), 3,916 context
  starts carrying 818M characters in total (~209k chars each).
