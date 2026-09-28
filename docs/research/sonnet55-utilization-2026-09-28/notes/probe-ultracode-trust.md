# Probe: ultracode keyword effort, trust-flag regression, Sonnet 5.5 on 2.1.280

Probe "ultracode-trust-passthrough", 2026-09-28. Builds: 2.1.280 (`~/.claude-280`) and 2.1.284 (`~/.claude-284`).
Both version strings were measured with `claude --version`. Accounts: next (headless) and quaternary (interactive and trust).
Scratch space with every raw artifact: `/tmp/s55/probe-ultracode-trust-passthrough/`.

**Instrument.** `proxy.py` is a logging reverse proxy to api.anthropic.com. Each claude run gets it through
`ANTHROPIC_BASE_URL`. It logs every request body (auth headers dropped) and the head of every response.
`summ.py` reads effort as `output_config.effort` from the logged body, and reads the served model from the
response's `message_start`. Interactive runs go through `ptyrun.py`. It launches `claude <flags> "<prompt>"`
under a pty, which is the positional-first-prompt shape `/handoff` fire uses (`commands/handoff.md:190`). It
never answers a dialog, and it exits with two Ctrl-C.

## Verdicts

| Q | answer | conviction |
|---|---|---|
| 1. Does 280 refuse `--model claude-sonnet-5-5`? | **No. It is served.** There is no 400 and no unrecognized_model error. The only trace is a client-side stderr log line. | 95% |
| 2. Does the `ultracode` keyword pin xhigh on 284 (or 280)? | **No, on either build.** The lead request carries `effort: high` with and without the keyword, on both builds, in both -p and interactive runs. The keyword adds only an orchestration reminder, and only in interactive sessions. | 95% |
| 3. Does 284 flip `hasTrustDialogAccepted`? | **None flipped in this probe.** That is 0 changes across 749 quaternary projects over 7 sessions, and 0 across 477 next projects over 11 headless runs. The bug is intermittent upstream, so this null result has low power. | 60% that 284 does not flip on our fleet's usage pattern |
| 4. Do `--bg` or our resume path break on a trust prompt under 284? | **Not silently.** handoff-fire re-trusts the launch dir right before every spawn, on the recycle/resume path too. If the modal still appears, the pane-modal detector matches 284's modal text and the fire abstains loudly instead of pasting into it. The fleet never launches `--bg`. On 284, `--bg` in an untrusted dir fails fast with exit 1. | 80% |

## Q1: Sonnet 5.5 on 2.1.280

MEASURED with `CLAUDE_CONFIG_DIR=~/.claude-next ~/.claude-280/.../claude -p --model claude-sonnet-5-5 --output-format json "say ok"`, output in `q1-280.json`/`.err`:
- exit 0, `"result":"ok"`, `"is_error":false`, `"api_error_status":null`. `modelUsage` key: `claude-sonnet-5-5`, `contextWindow` 200000, `maxOutputTokens` 128000.
- The only stderr line is `[claude-code:unrecognized_model] {"model":"claude-sonnet-5-5","query_source":"sdk"}`. It is a client-side log, not an API error.
- Through the proxy (`logs-q1-280/0001.json`): `POST /v1/messages?beta=true` returned **200**, with request `model=claude-sonnet-5-5` and response `message_start.model=claude-sonnet-5-5`.
- Effort pass-through on Sonnet 5.5 (`logs-s55-{280,284}-{xhigh,max}`, same command with `--effort xhigh|max`) was **identical on 280 and 284**. The request carries `output_config.effort` = `xhigh` / `max`, the server returns 200, and `contextWindow` 200000 and `maxOutputTokens` 128000 are the same on both builds.

So the brief's premise that 284 is the only build that can run claude-sonnet-5-5 is **refuted for headless -p**. What 280 lacks is client-side *recognition*. The 284 changelog says Explore subagents on 280 switch to Opus when the session model is unrecognized (cc284-workflows.md:34, 284 L47). That is a routing difference, not a refusal, and this probe did not measure it. I also did not test interactive 280 with Sonnet 5.5.

## Q2: the `ultracode` keyword and effort

Every arm used `--model claude-opus-5-5 --effort high --strict-mcp-config --mcp-config '{"mcpServers":{}}'`. Prompt: `[ultracode ]reply with exactly the word ok and nothing else. Do not use any tools.`

| build | mode | keyword | main-request `output_config.effort` | keyword reminder in request body | source |
|---|---|---|---|---|---|
| 280 | -p (neutral cwd, next) | no | high | 0 mentions | `logs-q2-opus-280-ctl` |
| 280 | -p | yes | high | only the prompt itself (1 mention) | `logs-q2-opus-280-kw` |
| 284 | -p | no | high | 0 | `logs-q2-opus-284-ctl` |
| 284 | -p | yes | high | only the prompt itself (1) | `logs-q2-opus-284-kw` |
| 280 | interactive pty (repo cwd, quaternary) | no | high | 0 | `logs-int-280-ctl/0003.json` |
| 280 | interactive pty | yes | **high** | **5**: the reminder plus the auto-loaded workflow-authoring skill | `logs-int-280-kw/0003.json` |
| 284 | interactive pty | no | high | 0 | `logs-int-284-ctl/0003,0004.json` |
| 284 | interactive pty | yes | **high** | **5**: the same reminder and skill | `logs-int-284-kw/0003.json` |

The injected reminder, verbatim from the 284 interactive keyword request:
`The user included the keyword "ultracode", opting this turn into multi-agent orchestration — use the Workflow tool to fulfill the request.`
The `workflow-authoring` skill body is also prepended as a `<command-message>`. The response came from `claude-opus-5-5`.

Code reading supports this. I extracted the call sites from both binaries into `keyword-callsites.txt` and `keyword-attach.txt`:
- The keyword produces only an attachment: `Wa("workflow_keyword_request",()=>…y?.isHumanTypedPrompt&&!y.suppressWorkflowKeyword&&xAt()?z$r(…):[])` on 280, and `YNt()`/`s9o` on 284. The generator returns `[{type:"workflow_keyword_request"}]`. Neither build touches effort there.
- The xhigh pin belongs to the **`/effort ultracode` level**. The 280 string is `- ultracode: xhigh + dynamic workflow orchestration (this session only)`. The `ultra_effort_enter` attachment is keyed on that level, not on the keyword. #97442 is a feature request about the `/effort` menu, and its "always runs at xhigh" refers to selecting ultracode there.
- The `isHumanTypedPrompt` gate explains why -p never triggers the keyword on either build. It also explains why a positional first prompt in an interactive session does trigger it (measured above). A `/handoff` fire is the interactive-positional shape, so **the payload keyword works on 284 exactly as it does on 280**.

Consequences:
- cc284-adversary.md:37 claims the keyword pinned xhigh through 283, so 284 would be "a silent step down for every /handoff ultracode payload". That claim is **refuted**: on 280 the keyword lead already ran at high.
- cc284-teams.md:16 and `commands/handoff.md:409` ("the keyword changes ORCHESTRATION, not effort") are **confirmed**. The conflict noted at critic.md:71 is resolved.
- A new hazard: `claude -p "ultracode …"` never opts the turn into workflows on either build, because the gate requires a human-typed prompt. Any headless path that relies on the keyword gets a plain session.

Transcript grep:
- The 4 -p transcripts (`~/.claude/projects/-private-tmp-s55-pw-uct-neutral/{a110fc67,05c20508,fa22c7a5,1c6a8688}*.jsonl`) contain 0 `workflow_keyword_request` and 0 "opting this turn" (MEASURED with `grep -c`). That is consistent with the proxy.
- **Instrument gap:** the 4 interactive sessions persisted no `.jsonl` (only a directory, under `~/.claude-quaternary/projects/-Users-chrisren-Development-claude-infrastructure/<sid>/`). The Ctrl-C exit about 12 s after start probably came before the flush. For the interactive arms, the proxy request body is the evidence, not the transcript.

## Q3: `hasTrustDialogAccepted` (#97888)

MEASURED with `trustsnap.py` (read-only). It reads `projects[*].hasTrustDialogAccepted` from the account's `.claude.json` before and after each run, and diffs against the first snapshot:
- quaternary baseline: 749 projects, 688 True / 61 False. `/Users/chrisren/Development/claude-infrastructure` is True.
- Runs on quaternary: 284 interactive keyword (repo), 284 interactive control (repo), 280 interactive keyword (repo), 280 interactive control (repo), **284 headless -p (repo)**, 284 interactive in an untrusted dir (modal left unanswered), and 284 `--bg` in an untrusted dir.
- After each run: **0 changed and 0 removed** (`trust-q4-*.json`). The repo flag stayed True throughout.
- next: 477 projects, 378 True / 99 False, and **0 changed** after 11 headless runs.
- Census across all 5 config dirs: **no project anywhere has `lastVersionBase` 2.1.283 or 2.1.284**, so the fleet has no 283+ exposure on record. False entries that show use (`lastCost>0` or a `lastSessionId`) do exist: next 2, secondary 10, tertiary 32, quaternary 1. Every one has `lastVersionBase` ≤ 2.1.260, so they predate the regression. ESTIMATED (inference): these are dirs used only headlessly, since -p skips the dialog and never writes trust. handoff-fire.sh:13412 already records one such case (tertiary `/Users/chrisren/Development/personal`, 2026-08-15).
- Power: the reporter saw 2 occurrences in 4 days across 27 projects. My 7 sessions over about 10 minutes cannot rule out a low-rate or time-triggered revert. The null result only supports "284 does not flip the flag on start, run or exit in our usage".

## Q4: `--bg` and the resume path under a trust prompt

From code reading (read-only, `/Users/chrisren/Development/claude-infrastructure`):
- `scripts/handoff-fire.sh:10414-10432` `pre_trust()`: if the physical launch dir's flag is not already true, it writes `hasTrustDialogAccepted:true` (plus `hasCompletedProjectOnboarding:true`) into the **target** account's `.claude.json`. It is called unconditionally right before spawning:
  - `:13429` on the recycle path. In resume mode it targets `$RESUME_CFG` (`:13427-13428`).
  - `:13454` on the cold-fire path.
  So a #97888 revert that has already happened is **repaired at fire time**. The residual window is a revert between `pre_trust` and the new process's startup read (seconds), or one that CC itself writes during startup.
- If the modal still renders, `pane_wedge_reason` (`:3265`) and `hooks/lib/pane-modal.sh:95-96` (header `Accessing workspace:|Quick safety check:`, option `Yes, I trust this folder|No, continue without these permissions`) classify the pane as `workspace-trust-modal`. The fire then **abstains** (return 4, `:3637-3639`, `:3670-3674`) instead of pasting the brief into it, and fails loud rather than answering a security prompt.
- **Measured on 284** (`int-untrusted-284.screen.log`, interactive in the untrusted `/tmp/s55/pw-uct-untrusted`): the modal renders `Accessing workspace:`, `Quick safety check: Is this a project you created or one you trust?`, `❯ No, exit` and `Yes, I trust this folder`. **0 API requests** were sent in 25 s (`logs-untrusted-284` is empty), so the session stalls indefinitely.
  - The 284 modal's negative option is `No, exit`, not `No, continue without these permissions`. The detector still matches because its option regex is an alternation that includes `Yes, I trust this folder`.
  - Binary string counts for `Accessing workspace:`, `Yes, I trust this folder` and `No, continue without these permissions` are 2/2/2 on both builds. `Quick safety check:` is 2 on 280 and 4 on 284 (MEASURED by python `bytes.count` on each native binary).
- `--bg`: `git grep` finds no `claude … --bg` launch anywhere in the repo outside docs. handoff-fire only *detects* `--bg-pty-host` (`:3939`). MEASURED on 284 with `claude --bg … "reply …" </dev/null` in the untrusted dir: **exit 1**, `Workspace not trusted. Run \`claude\` in /private/tmp/s55/pw-uct-untrusted once and accept the trust prompt, then retry.` It failed fast rather than hanging, and no trust flag changed.
- `bin/cc` **does not exist** in the repo (the brief named it). The nearest files are `bin/cc-resume-resolve`, `bin/cc-resume-layout.sh` and `bin/cc-resume-classify.py`. `cc-resume-resolve` resolves which account can resume a session id and has no trust handling. A manual `claude --resume` run outside handoff-fire gets no `pre_trust`. Under a #97888 revert it would sit on the modal until a human answers, which is the reporter's `agent_not_ready` case.

## Hazards found while probing

1. **The ANTHROPIC_BASE_URL proxy changes the request.** With a non-default base URL, 280 sent all 221 tools with `defer_loading` 0. "say ok" then cost 436,556 cache-creation tokens and $3.49, against $0.32 without the proxy (MEASURED, `q1p-280.json` vs `q1-280.json`). Any proxy-based effort probe should add `--strict-mcp-config --mcp-config '{"mcpServers":{}}'`. With that, the tools dropped to 24-29.
2. **The cwd name leaks into the keyword grep.** My first run's cwd contained "ultracode", and the system prompt and env block echoed it (1 hit in system, 4 in messages). Keyword probes need a neutral cwd.
3. **Probe sessions run the fleet's hooks under the parent pane's identity.** Peer mail at 15:17:48 attributed a SIGTERM of pane [918]'s `cc-await-ping` watcher to my run `claude-284 -p --model claude-sonnet-5-5 --effort max` (sender pid 61020). Separately, probe session 77e0e889 recorded the pane's pre-existing watcher (pid 27697, 1h34m old) as its own in `~/.claude/mailbox/77e0e889-….watching`. I did not repair either, because both are outside my scope and pid 27697 is not mine.
4. **Quaternary rate limit on the startup request.** On every interactive startup the first request (`max_tokens: 1`) returned **429 rate_limit_error** (`x-should-retry: true`), while the main requests returned 200 (MEASURED in `logs-int-*/0001.json`). I have not established what that request is for.
5. **Stop hooks add a turn to headless runs.** The fleet's Stop hooks force an extra turn, so `--max-turns 2` produced `error_max_turns` on 2 of 4 Sonnet 5.5 runs, even though every request returned 200 at the requested effort. Headless probes should use `--max-turns` of at least 3.

Spend: the sum of `total_cost_usd` across the 11 headless JSONs is $7.58 (MEASURED). The 5 interactive runs are not included. ESTIMATED at about $1 each, from about 133K cache-creation tokens per main request at Opus rates.

## Skeptic

This is an adversarial re-read, done 2026-09-28 at about 15:35. I read every artifact cited under `/tmp/s55/probe-ultracode-trust-passthrough/`. My scratch dir is `/tmp/s55/probe-skeptic-uct/`. Spend was $0: my only live re-run failed before sending any API request.

**Instrument checks**
- **Build identity holds.** Across all 27 proxy-logged requests, the `user-agent` header names the intended build: `claude-cli/2.1.280` in every 280 dir and `2.1.284` in every 284 dir (MEASURED, python read of `headers.user-agent`). A `--version` re-run printed 2.1.280 and 2.1.284 (MEASURED). No log came from the wrong build.
- **The effort readout is not stuck at `high`.** The same proxy and `summ.py` record `xhigh` and `max` when the flag asks for them (`logs-s55-*`).
  - Missing: a positive control for the mechanism the adversary claimed. No arm ran `--effort ultracode`, which is the session state that sets xhigh. Code reading covers that gap; no measurement does.
- **The launch shape matches production.** The fleet launcher always passes `--effort "$_eff"`, with `_eff="${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}"` (`~/.zshrc:495-502`). The probe's explicit `--effort high` is therefore the production shape and does not hide a default-effort path.
- **The environment does not match a fire.** `ptyrun.py` and `q2.sh` pass the parent session's whole environment to the child. All 4 interactive screens show `⚠ Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker` (MEASURED, `grep -c` = 1 in each). A real fire starts from a fresh iTerm shell, which does not carry that marker.

**Per-claim verdicts**
- **Q1 (280 serves `claude-sonnet-5-5`): UPHELD** for headless -p, one account, single turn.
  - The request came from UA 2.1.280, got status 200, and the response's `message_start.model` is `claude-sonnet-5-5`.
  - Effort pass-through (`xhigh`/`max`) is identical on both builds.
  - Nit: `q1-280.err` has 2 lines, not 1. The extra line is an unrelated claude.ai MCP enterprise-policy warning.
- **Q2 (the keyword does not pin xhigh): UPHELD.**
  - The verbatim reminder appears exactly once in each interactive keyword request. It appears 0 times in the control requests and in all 6 -p requests. Every main request carries `high` (MEASURED, python count over request bodies).
  - Code reading reproduced:
    - `z$r` returns only `[{type:"workflow_keyword_request"}]`.
    - xhigh comes only from the session-level `ultracode` state: the `K()` default when `Ye().ultracode===!0`, and the alias `W={ultracode:"xhigh"}`.
  - I re-read #97442 with `gh issue view`. It is a feature request, and its "always runs at xhigh" is about *selecting* ultracode in `/effort`.
  - Caveat: 281-283 were not tested. "Pinned xhigh through 283" is refuted for 280, the fleet baseline, which is the step that matters. It is not refuted for 281-283. Each cell has n=1.
- **"-p never opts into workflows because the gate needs a human-typed prompt": the measurement is UPHELD, the cause is an inference.**
  - The 4 -p transcripts have 0 `workflow_keyword_request` and 0 "opting this turn" (MEASURED, `grep -c`, re-run).
  - The Workflow tool *was* in the -p tool list (24 tools), so a missing tool does not explain the result.
  - In 280 the gate is `ro=Ve&&lw(ge)`, an origin check. That the origin check is what blocks -p is code reading, not measurement.
- **The explanation for the missing interactive transcripts is REFUTED.**
  - The cause was not a Ctrl-C before the flush. The TUI itself says transcript saving is off because of the inherited `CLAUDE_CODE_CHILD_SESSION`.
  - Both binaries gate persistence on that variable plus a second condition, and `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` overrides the gate. The -p runs persisted, so they evidently did not meet the second condition.
  - Fix for future interactive probes: run with `env -u CLAUDE_CODE_CHILD_SESSION`, or set `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1`.
- **Q3 (`hasTrustDialogAccepted`): the narrow null is UPHELD. The generalization is UNSUPPORTED.**
  - I re-diffed all 9 quaternary snapshots: 0 changed, 0 added, 0 removed (MEASURED).
  - I re-ran the census (MEASURED, python over each `.claude.json`):
    - 0 projects at 2.1.283 or 2.1.284 in all 5 config dirs.
    - Used-but-False entries: 2 / 10 / 32 / 1, with max `lastVersionBase` 2.1.260.
  - **The run count is wrong.** next had 10 headless runs, not 11: q1, q1p, q2×4 and s55×4. The 11th run (q3-284-p, 82cdd834) was on quaternary.
    - The next "before" snapshot has mtime 15:10:39. The first q2 request is at 15:10:36 (proxy `t`). So the snapshot was taken 3 s into the first bracketed run.
    - The next bracket therefore covers 8 runs, 4 of them on 284 (MEASURED, `stat` and proxy `t`).
  - **There is no positive control.** `trustsnap.py` saves only the trust boolean, so no artifact shows that a 284 process wrote `.claude.json` at all.
    - The file does take probe writes: quaternary's repo entry has `lastSessionId` 77e0e889, the 280 control probe session, and `lastVersionBase` 2.1.280 (MEASURED). That write is 280's. 284's writes were overwritten by the 280 runs that followed.
    - -p runs create no project entry: `pw-uct-neutral` is absent from next (MEASURED). So the -p arm cannot exercise an exit-time write-back of project state.
  - **Power is near zero against the reported mechanism, not merely low.**
    - What #97888 says (`gh issue view`): it was filed on 2.1.283 and says "Not version-specific". It suspects a stale in-memory `.claude.json` snapshot. On exit, that snapshot clobbers a `true` that *another* process persisted during the session.
    - No arm had a second process write trust during a 284 session.
    - The fleet's real pattern is exactly that race: many concurrent sessions per account, while `pre_trust` does a jq rewrite and `mv` of the file.
    - So "60% that 284 does not flip on our fleet's usage pattern" has no evidential support.
  - **The "used only headlessly" inference has a stronger rival.** 43 of the 45 used-but-False entries have a trusted ancestor dir in the same config (MEASURED). Trust inherited from a parent means the dialog never ran, so the flag was never written.
    - "Predate the regression" also presumes a regression, which the upstream report does not establish.
- **Q4 (`--bg` and resume under a trust prompt): UPHELD, with one measurement added.**
  - Line cites confirmed: `pre_trust` at 10414, the recycle call at 13429 with `RESUME_CFG` at 13427-13428, the cold-fire call at 13454, `--bg-pty-host` at 3939, and `pane-modal.sh:95-96`. Nit: `pane_wedge_reason` starts at 3262, not 3265.
  - **The detector matches 284's modal (MEASURED).** I ran the repo's `pane_modal_reason` on the ANSI-stripped `int-untrusted-284.screen.log` and got `workspace-trust-modal`, rc 0. The controls behave as expected: prose gives rc 1, and header-only gives rc 1. Files are in `/tmp/s55/probe-skeptic-uct/`.
    - Caveat: production reads the iTerm-rendered screen through `it2`, not raw pty bytes.
  - **`--bg` exits 1.** The original artifact holds only the message, with no exit code. My re-run gave `exit=1` with the same message, an unchanged `.claude.json` mtime, and 0 trust changes (MEASURED, `bg-rerun.{rc,err}` and `trust-q4-{pre,post}-bg.json`).
  - **"Stalls indefinitely" is an inference.** The evidence is a 27 s window with events `trust` and `TIMEOUT`.
  - **Also upheld:**
    - "The fleet never launches `--bg`": `git grep` outside docs finds only banner, svg and bats flags.
    - `bin/cc` is absent.
    - The string counts 2/2/2, and 2 vs 4 for `Quick safety check:`, reproduced (MEASURED, python `bytes.count` on each resolved `claude.exe`).

**Hazards and spend**
- **H1 (the proxy changes the request): UPHELD, and the cause is confirmed in the binary.**
  - 280 contains `[ToolSearch:optimistic] disabled: ANTHROPIC_BASE_URL=… is not a first-party Anthropic host. Set ENABLE_TOOL_SEARCH=true …`.
  - `logs-q1-280/0001.json` has 221 tools and 0 with `defer_loading` (MEASURED).
  - `ENABLE_TOOL_SEARCH=true` is a cheaper fix than stripping MCP.
- **H2 (the cwd name leaks into the grep): UPHELD.**
- **H3 (probe sessions act as the parent pane): PARTLY UPHELD.**
  - `~/.claude/mailbox/77e0e889-….watching` exists and contains `pid=27697` (MEASURED).
  - The peer-mail SIGTERM attribution has no saved artifact, so it is UNVERIFIED.
  - Likely mechanism (inference): the wholesale environment inheritance noted above.
- **H4 (429 on the startup request): UPHELD.**
- **H5 (Stop hooks add a turn): PARTLY UPHELD.**
  - 2 of 4 runs ended in `error_max_turns`: s55-280-xhigh and s55-284-max, each with `num_turns` 3.
  - No driver script was saved, so the `--max-turns 2` value is unverified. The Stop-hook cause is an inference.
- **Spend: UPHELD.** The python sum over the 11 JSONs is $7.579. Nit: the untrusted interactive run sent 0 requests, so 4 interactive runs cost money, not 5.
