# Claude Code 2.1.284 -> 2.1.293: adversary note (2026-10-07)

Role: find reasons NOT to move. Read-only run. Sources: `gh issue view` / `gh issue list` on
anthropics/claude-code (authenticated, not rate-limited: search 30/30 remaining after the sweep),
`pack/cc-changelog.md` lines 3-160, `skills/cc-upgrade/holds.md`, the local gate output in
`gate/gate-293-haiku55.*`, and read-only byte searches of the installed 2.1.284 and 2.1.293
binaries (`~/.claude-284`, `~/.claude-293`). Every count below is measured unless marked estimated.

Limits of this sweep: 2.1.293 was hours old, so the tracker holds almost nothing filed against it
(8 issues mention "2.1.293" in any state, measured by `gh issue list --search "2.1.293 in:title,body"`;
none is a macOS headless regression). Silence on day one is not evidence of safety. Issue bodies
were read truncated (first 1,100-2,200 characters plus comment heads), so later detail in a long
report may be missing here.

## (a) Held-open issues

Measured with `gh issue view <n> --json number,title,state,stateReason,closedAt,updatedAt`.

| Issue | State now | Discharges the hold? |
|---|---|---|
| #84974 spawn depth off by one | closed NOT_PLANNED 2026-10-05 | No. A closure, not a fix. Changed since the 2.1.284 row (was open). Local gate check #15 passes on 2.1.293 (depth 1 gives a flat topology), which is the only thing covering it. |
| #85264 fork subagents spawn unauthorized nested agents | open (updated 2026-10-03) | No |
| #85015 background subagents leak to 46 GiB, freeze a 16 GB Mac | open | No |
| #84224 auto-updater installs into the PATH-resolved npm prefix | open | No. This is the upgrade mechanism. |
| #85154 npm update leaves a stub, no rollback | closed NOT_PLANNED 2026-09-09 | No |
| #85886 daemon bg session binds no inbox socket | closed COMPLETED 2026-08-17 (fixed in 2.1.228 per holds.md) | Yes |
| #85497 session starts without binding its peer socket | closed NOT_PLANNED 2026-10-03 | No. Changed since the 2.1.284 row (was open). |
| #85412 same-second socket bind race | closed NOT_PLANNED 2026-09-08 | No. The race itself was never fixed. |
| #85690 SendMessage to self delivers silently | closed NOT_PLANNED 2026-09-10 | No |
| #85764 ListAgents omits in-process subagents | closed NOT_PLANNED 2026-10-05 | No. Changed since the 2.1.284 row (was open). |
| #97888 trust flag reverts to false (macOS, 2.1.283) | open | No |
| #97763 subagent `output_tokens` undercount | open (updated 2026-10-06); re-filed as #100154 on 2.1.292 | No. Still reproduces on 2.1.292. |
| #97687 opus subagent silently continues on an older opus after a cyber refusal | open | No |
| #99353 skill `allowed-tools` rule dropped when the Skill tool finishes early (2.1.289) | open (updated 2026-10-06) | No. The 2.1.292 changelog fixes a different `allowed-tools` bug (line 77). 9 fleet skill files carry `allowed-tools` (measured: `grep -rl '^allowed-tools' skills`). |
| #99130 mods served off remotely | open | No (harmless to this fleet, matches its own reading) |
| #99932 undocumented per-subagent token budget (2.1.291) | open (updated 2026-10-07) | No. See risk R2. |

Score: 1 of 16 discharged by a fix. 6 closed NOT_PLANNED (three of them since the 2.1.284 row).
9 open. No changelog line in 2.1.291-2.1.293 names any of them.

## (b) New risks

"macOS headless" = does the report reproduce on macOS in `-p` / background / unattended use.

| # | Issue, title | Versions | macOS headless? | Rating |
|---|---|---|---|---|
| R1 | Local gate, no upstream issue: `gate/gate-293-haiku55.json` verdict RED. Check #2: account `next3` returned `is_error=True` for `claude-haiku-5-5`; `next`, `next2`, `next4` entitled. Combined with the alias flip: the 2.1.293 binary maps `haiku:"claude-haiku-5-5"` (2.1.284 maps `haiku:"claude-haiku-4-5"`; measured by byte search of both binaries). Every `model: "haiku"` retrieval spawn moves to 5.5 on upgrade with no config change, including on the account that failed. | 2.1.293 | Yes, measured on this Mac | BLOCKER until the `next3` error is explained (entitlement, quota, or auth: the gate file does not say which) or the retrieval role is pinned to `claude-haiku-4-5` by id |
| R2 | #99949 / #99950 "Server-gated 100k-token sub-agent budget (2.1.290+) makes delegated work impossible"; #99932 "Subagent budget of 30,000 tokens (new in 2.1.291)". Subagents stop near the budget and report "budget exhausted"; the orchestrator respawns them for hours. No setting, env var, or frontmatter disables it. Gated server-side per account and lead model (one reporter: Fable 5.1 on one account only). A 2.1.292 Opus 5.5 session without the line is also on record (#99932 comment). | 2.1.290-2.1.293. Budget text: 0 hits in the 2.1.284 binary, 3 distinct sentences in 2.1.293 (measured) | #99932 is macOS 2.1.291; #99949 is WSL. Applies to any session that spawns subagents | BLOCKER until probed per account and lead model. The server can switch it on later, so one clean probe narrows it but does not close it. 2.1.284 is immune because it has no code for it. |
| R3 | #99833 "--resume on opus-5-5/sonnet-5-5 re-writes the whole history to the prompt cache every time (haiku unaffected)"; #100065 "`claude -p` misses the prompt cache after a turn without thinking (Opus 5.5, Fable 5.1, Sonnet 5.5)" | 2.1.288-2.1.292. #100065 says 2.1.289 was fine before 2026-10-06 and fails now, which points to a server-side change that may also hit 2.1.284 | Yes, `-p --resume`; platform-independent | CAUTION (high). A direct weekly-quota cost for a headless fleet, but possibly not a version delta. A/B it on 284 vs 293. |
| R4 | #99965 30-minute stop on background commands in unattended sessions (`-p`, SDK); no supported way to declare a session attended | 2.1.285+ (narrowed to unattended only in 2.1.288), still in 2.1.291. `disableBackgroundDeadline`: 0 hits in 2.1.284, 3 in 2.1.293 (measured) | Yes | CAUTION (high). Cuts the 3300 s `cc-await-ping` arm in any headless session. Known from the holds file; not fixed. |
| R5 | Changelog 2.1.292 line 81: one-shot `claude -p` now waits for background commands and scheduled wakeups instead of stopping 5 s after the result | 2.1.292+ | Yes | CAUTION (high). Removes a limit. A `-p` worker that leaves a background command running no longer exits on its own; with R4 the wait is bounded at about 30 minutes (estimated from #99965's description). Check every launcher timeout. |
| R6 | #100005 "--dangerously-skip-permissions (and bypassPermissions mode) does not suppress Write/Edit approval prompt in --print mode" | 2.1.288, 2.1.291 | Yes: found via a macOS launchd job | CAUTION. The fleet pins `auto`, and gate #11 passes for a Bash command, but `bin/reso-resume-one` and `hooks/unit-gate.sh` reference bypass flags (measured by grep). Probe a Write in `-p` on 2.1.293. |
| R7 | #100117 "PreToolUse `tool_input` differs from the transcript's `tool_use.input` when the tool schema strips a key (Agent `run_in_background` under the fork-subagent gate)" | 2.1.292 | Yes, seen in `bg` sessions on macOS | CAUTION. Touches the PreToolUse(Agent) spawn-budget hooks if any reads `run_in_background` or cross-checks the transcript. |
| R8 | #100013 "Resumed teammates stay bound to the previous team after lead restart; SendMessage to team-lead reports success but messages are never delivered" | 2.1.291 | macOS; interactive lead resumed after a rate-limit pause | CAUTION. Agent Teams plus the account-switch relaunch is exactly this path. Not shown to be absent on 2.1.284. |
| R9 | #100003 "Messages queued during a running turn are lost when the session exits and is resumed"; #100004 "Resuming a session interrupted during a usage-limit retry wait answers the pending message with a synthetic 'No response requested.'" | filed 2026-10-06 on "latest" (2.1.291/292); related reports are older | macOS, `--resume` | CAUTION. Probably present on 2.1.284 too (estimated from the older linked issues), so a standing hazard more than a delta. |
| R10 | Changelog 2.1.292 line 65: `effort` parameter on the Agent tool | 2.1.292+ | Yes | CAUTION. The lead model can now choose a subagent's effort per spawn. Nothing caps it; a PreToolUse(Agent) hook is the only place to bound it. |
| R11 | Changelog 2.1.293 line 42: reverted the 2.1.281 auto-mode denial message (a denial no longer says it covers the outcome, only the exact command) | 2.1.293 | Yes | CAUTION. Loosens what a denied model believes it may retry. Related open classifier reports: #100255 (allow rule ignored in auto mode, 2.1.287, macOS), #100031 (Edit denied as destructive, 2.1.290, macOS subagent), #99894 (read-only command flagged as `rm`, prompt then deny after 120 s, 2.1.291, macOS). |
| R12 | Changelog 2.1.292 lines 123 and 135: first `-p` turn no longer waits for HTTP/SSE MCP `resources/list`; stdio MCP negotiates protocol 2026-07-28 by default. Open #88128: tools/list rejected under that protocol when cache hints are omitted (Linux). | 2.1.292+ | Yes | CAUTION. Same class as the 2.1.221 landmine (MCP not ready on the first headless turn). Gate #13 shows 7 servers connected on 2.1.293, but it passes on any one; compare per server. `MCP_PROTOCOL_NEGOTIATION=legacy` opts out. |
| R13 | Changelog 2.1.293 line 33: path-scoped rules and nested CLAUDE.md now load when a file is viewed through `cat`/`head`/`grep` in Bash | 2.1.293 | Yes | CAUTION (low). Reads as a fix; it changes what context a Bash-reading subagent picks up and adds tokens. |
| R14 | Changelog 2.1.292 line 126: `<system-reminder>` tags in hook output are escaped | 2.1.292+ | Yes | NOISE for this fleet: one hook file mentions the tag (`hooks/lib/transcript_norm.py`, measured by grep) and it reads transcripts rather than emitting the tag (inferred from the filename, not read). |
| R15 | #100154 / #97763 subagent transcripts under-report `output_tokens` about 30x | through 2.1.292 | macOS | CAUTION (low). Not a delta; any quota ledger built on subagent transcripts stays wrong after the move. |
| R16 | #99360 / #100155 subagents write 5-minute cache, `-p` and interactive write 1-hour | 2.1.278-2.1.292 | macOS | NOISE as a delta. Relevant to pricing Haiku 5.5 retrieval fan-outs. |
| R17 | #100082 "Custom subagent frontmatter model (haiku/sonnet) ignored: subagents ran on parent Opus model (2.1.283-2.1.290)" | 2.1.283-2.1.290; honored on 2.1.291/292 per the reporter | Linux, labeled duplicate, 0 comments | Cuts AGAINST holding: if real it affects 2.1.284. The fleet spawns with an explicit `model` parameter, which the report does not cover. Check one day of 2.1.284 subagent transcripts for the model actually used. |
| R18 | #100324 "Claude Code says I'm out of monthly usage, when I'm not" | 2.1.293, Windows | No | NOISE. Closed in one minute; reporter: "suddenly working again." The only regression-flagged report naming 2.1.293. |
| R19 | #98899 `--resume` finds no sessions when the project folder is a symlink (since 2.1.287) | 2.1.287+ | macOS | NOISE here: 0 symlinked entries among about 9,000 in `~/.claude/projects` and `~/.claude-secondary/projects` (measured with `find -maxdepth 1 -type l`). |
| R20 | #98744 PostToolUse no longer fires for MCP tools; #99672 `.worktreeinclude` no longer APFS-cloned; #100189 AskUserQuestion auto-continues at 200 s; #99938 `CLAUDE_CODE_CHILD_SESSION=1` interactive sessions write no transcript | all predate or include 2.1.284 | macOS | NOISE as a delta; none is fixed by 2.1.293 either. |
| R21 | #99849 transient network error during OAuth refresh logs the daemon out permanently | 2.1.290 | macOS, launchd daemon | CAUTION (low); unknown whether 2.1.284 shares it. |
| R22 | #100033 / #100034 Workflow: triggering user message relayed to every node with authority over the computed task; resume replays bad cached node results | version not stated | n/a | CAUTION (low); not shown to be a delta. |

### Haiku 5.5 in Claude Code specifically

No upstream issue reports Haiku 5.5 failing, being rejected, falling back, or lacking plan
entitlement (measured: `gh issue list --state all` for "haiku 5.5", "claude-haiku-5-5", "haiku-5-5",
"haiku fallback", "haiku entitlement", and "haiku created:>=2026-10-07" returned no relevant hit).
The model is hours old, so this is absence of reports, not a clean record. The only failure found is
local: `next3` in R1. On the three entitled accounts the gate shows no demotion in a subagent,
teammate, or workflow run (checks #7-#9).

### Changelog lines that read as features but remove a limit or change a default

- 2.1.293 line 5: Haiku 5.5 becomes the default Haiku; the `haiku` alias moves (R1). The same line prices prompts over 100K tokens at 5x ($0.50/$2.50 against $0.10/$0.50 per Mtok), so a 1M-context retrieval agent that reads past 100K changes price class.
- 2.1.293 line 42: auto-mode denial message revert (R11).
- 2.1.293 line 43: reverted fix; cloud sessions that lose a `/loop` wakeup stay asleep and Claude is not told. Touches only the `--cloud` send in `bin/cc-notify`.
- 2.1.293 line 33: instruction files load on Bash reads (R13).
- 2.1.293 line 50: agent and MCP server lists re-sorted (non-ASCII names only); changes the prompt prefix for sessions that have such names.
- 2.1.292 line 65: Agent `effort` parameter (R10).
- 2.1.292 line 81: `-p` waits for background work (R5).
- 2.1.292 lines 123, 134, 135: MCP startup and protocol default (R12).
- 2.1.292 line 127: Write, WebFetch and Read ignore stray parameters instead of failing the call; Grep accepts `file_path`. Malformed calls that used to error now run.
- 2.1.292 line 129: with strict sandbox mode, `FOO=bar python3 app.py` runs unprompted.
- 2.1.292 line 138: scheduled routine runs publish a private artifact without asking.
- 2.1.292 line 139: agent names over 256 characters are rejected (a new limit, not a removal).
- Not in any changelog line: the per-agent token budget (R2). A grep of lines 3-160 for restored / cap / ceiling / depth finds no restored spawn ceiling, so by the holds rule the band is still uncapped on spawn count.

## (c) Verdict

Strongest case for holding at 2.1.284:

1. The fleet's own gate is RED on the candidate: `next3` errors on `claude-haiku-5-5`, and 2.1.293 repoints the `haiku` alias, so the retrieval role changes model on every account the moment the binary moves (R1).
2. 2.1.290+ carries an unannounced, unconfigurable, server-switched per-subagent token budget (R2). When on, it caused hours of respawn loops. The fleet fans out about 10 subagents and its binding cost is weekly quota. 2.1.284 has no code for it; 2.1.293 can be switched on after any probe passes.
3. Only 1 of 16 held issues was fixed. The memory-storm and nested-spawn holds (#85015, #85264) are open; the upgrade mechanism's bugs (#84224, #85154) are unfixed.
4. The build is hours old, and this band shipped two regressions that took days to surface (2.1.288, 2.1.290). 2.1.292 changed headless behavior without flagging it (R5, R12).
5. Nothing forces the move: retrieval works on Haiku 4.5 today.

Evidence that would defeat it:

- `next3` passes check #2, or its error is shown to be quota or auth, or retrieval is pinned by id.
- All four accounts, under Opus 5.5 and Fable 5.1 leads, show no budget sentence in the Agent tool description and a subagent running past 100K tokens, plus a standing check that catches the server turning it on.
- A `-p --resume` cache A/B with 2.1.293 no worse than 2.1.284 (R3).
- A `-p` run with a live background command exits inside the launcher timeout (R5), and the 3300 s `cc-await-ping` arm survives (R4).
- Per-server MCP parity with 2.1.284 (R12), and the opus-5-5 gate finishing GREEN (its JSON was 0 bytes when this was written).
- 48-72 hours with no new 2.1.293 macOS headless regression filed.
