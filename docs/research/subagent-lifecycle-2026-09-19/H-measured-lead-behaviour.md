# H — What leads actually do at the end of a teammate wave (measured, 30 days)

Window 2026-08-20 → 2026-09-19. Corpus: 7,803 transcripts (8.4 GB) across
`~/.claude`, `-secondary`, `-tertiary`, `-quaternary` (`~/.claude-next` symlinks `~/.claude`).
Per-member rows: `H-lead-wave-ends.csv` (405 rows). All timestamps UTC; the lifecycle log is
LOCAL and was converted (see § Instrument warnings).

## Headline

**The dominant lead-side behaviour is: name an agent, read its one report, and walk away.**
42 of 72 leads (58%) that successfully spawned a named member sent **no teardown signal of any
kind**. Across all 338 successfully-spawned named members, the lead sent **zero** non-shutdown
messages — the persistence that naming buys was used **0 times in 30 days**. 124 members were
killed by `hooks/teammate-auto-shutdown.sh` instead, 27 were never closed at all.

---

## (a) Agent spawns, 30 days — named vs unnamed

| | count | share |
|---|---|---|
| Agent `tool_use` records, top-level session transcripts | **904** | — |
| named (`input.name` present) | **419** | 46.3% |
| unnamed | **485** | 53.7% |
| of the named: spawn succeeded | **338** | 80.7% of named |
| of the named: refused by `capacity-admit` hook | **81** | 19.3% of named |
| Agent spawns inside subagent/workflow transcripts (`/subagents/`) | **0** | — |
| spawns carrying `team_name` | **1** | 0.1% |

`team_name` is dead: 1 of 904. The fleet is entirely on the 2.1.183+ implicit-team model
(`Agent({name})`), as `skills/agent-teams/SKILL.md` documents. The 0 nested spawns is a clean
empirical confirmation of the depth cap (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, `~/.zshrc:484`).

**Named vs unnamed is a different RUNTIME, not a label.** Measured from the `tool_result` body of
every spawn — this is the mechanism the whole question turns on:

| | named spawn (419/419) | unnamed spawn (379 launched) |
|---|---|---|
| result text | `Spawned successfully.` | `Async agent launched successfully.` |
| handle | `agent_id: <name>@session-<team>` | `agentId: <17-hex>` |
| result size | 319 B (p10 297 / med 315 / p90 ~319) | 1,137 B (p10 1,124 / p90 1,146) |
| exit contract | *"will receive instructions via **mailbox**"* | *"**You will be notified automatically when it completes**"* + `output_file:` |
| terminates on | shutdown_request / TaskStop / fleet reaper **only** | its own completion |

Median spawn→result latency is **3 s** for named spawns (n=419, p10 1 s, p90 5 s) — the tool returns
a handle, never a report. So naming a research agent does exactly what
`~/.claude/rules/research-subagents.md` warns: it converts a self-terminating async agent into a
mailbox-driven resident that nothing will ever reclaim on its own. **Empirical, not inferred.**

### Did the named agent need persistence?

Classifier: `subagent_type` ∈ {deep-research, Explore, frontier-derivation,
research-decomposition-critic, claude-code-guide} ⇒ research; otherwise keyword scan of the brief.

| brief class | members (distinct per lead) | share |
|---|---|---|
| research / read-only | **289** | 71.4% |
| ambiguous | 91 | 22.5% |
| implementation | **25** | **6.2%** |

| evidence in the brief | named spawns | note |
|---|---|---|
| explicit `READ-ONLY` / "do NOT write" clause | **230 / 419 (54.9%)** | lower bound — only first 1,200 chars scanned (median brief 3,082 chars) |
| explicit delivery contract ("write your findings to …") | 49 / 419 (11.7%) | same lower bound; this is the research-subagents field-7 shape |
| `subagent_type: deep-research` | 159 / 419 (38.0%) | the *research* agent type, named into a teammate |
| `subagent_type: Explore` | 12 / 419 | " |
| `model:` pinned | 101 / 419 (opus 93, sonnet 6, fable 2) | |

**At least 71% and plausibly 94% of named agents needed no persistence.** A `deep-research` agent
carrying a `READ-ONLY` clause and a findings-path is a research subagent with a name typed into it.

---

## (b) Teardown discipline, per lead and per member

Denominator = members whose spawn actually succeeded (338), since a refused spawn has nothing to
tear down.

**Per lead (n=72 leads with ≥1 successful named member):**

| lead disposition | leads | share |
|---|---|---|
| **NOTHING** (no shutdown_request, no TaskStop) | **42** | **58.3%** |
| `shutdown_request` to ALL members | 19 | 26.4% |
| `shutdown_request` to SOME members | 7 | 9.7% |
| `TaskStop` ALL | 3 | 4.2% |
| `TaskStop` SOME | 1 | 1.4% |
| plain-prose "shut down" only | **0** | 0% |

**Per member (n=338):**

| signal the lead sent | members | share |
|---|---|---|
| **none** | **151** | **44.7%** |
| `shutdown_request` (structured SendMessage) | 127 | 37.6% |
| `TaskStop` (bare name as `task_id`) | 60 | 17.8% |

**Teardown by brief class** — the omission is concentrated exactly where naming was unnecessary:

| brief class | none | shutdown_request | TaskStop | % abandoned |
|---|---|---|---|---|
| research | **134** | 70 | 27 | **58.0%** |
| ambiguous | 14 | 40 | 33 | 16.1% |
| implementation | 3 | 17 | 0 | **15.0%** |

A lead is ~4× more likely to abandon an agent it named for research than one it named for
implementation. The protocol at `skills/agent-teams/SKILL.md:336-410` is explicit that this is the
failure mode — *"Tear down every agent you named, **research included**, then ps-verify"* (:348),
after an incident where a lead reaped "the two agents it thought of as teammates" and left three
research agents resident.

**TaskStop is mostly not a teardown tool.** 343 `TaskStop` calls in the corpus; only **82** carry a
`task_id` equal to a spawned member name. The other 261 are background-Bash (`b…`) and workflow
(`w…`) ids. Escalation-to-TaskStop as the skill prescribes (`:378`, *"`TaskStop` is the
authoritative actuator"*) is therefore rarer than a naive `TaskStop` count suggests.

---

## (c) Wave ends: who actually closed the member

| fate of a successfully-spawned named member | n | share |
|---|---|---|
| torn down by its own lead | **187** | 55.3% |
| **reaped by `hooks/teammate-auto-shutdown.sh`** | **124** | **36.7%** |
| **never closed, by anyone** | **27** | **8.0%** |

The fleet janitor is doing a third of the fleet's teardown. Survival of a lead-abandoned member,
measured from its first `idle_notification` (or spawn, if it never reported) to the first
`Auto-shutdown` / `✓ closed pane` event for that member after its spawn:

| survival to fleet reap | members |
|---|---|
| < 30 min | 69 |
| 30 min – 2 h | 25 |
| 2 – 12 h | 30 |
| median | **21 min** |
| p90 | **2.2 h** |
| max | 2.4 h |

**105 of those 124 reaps happened BEFORE the lead's own last record** (median −130 min): the lead was
still running when the janitor killed its members. Only 19 were reaped after the lead's transcript
ended. So this is not "the lead exited and cleanup followed" — it is **the lead forgot while still
alive, and a cron-shaped hook cleaned up behind it.**

Team `config.json` is a weak instrument here and should not be used alone: of 82 configs touched in
the window, **77 have `mtime == createdAt`** (Δ < 2 s) and list only the lead — i.e. the member list
is written only for **pane-backed (`backendType: iterm2`)** members. Only 4 teams ever registered
non-lead members (24 members total: `session-4899dafd` ×8, `session-e7b0b37c` ×8,
`session-cd5eee6e` ×6, `session-6ee7e044` ×2). The other 314 named members are paneless in-process
teammates that never appear in any config. Named-member accounting must come from the transcript,
not the roster.

**Cost visible in `~/.claude/logs/teammate-lifecycle.log`, 30 days:**

| reaper event | count |
|---|---|
| worktree removal refused / "defer stands" | **661** |
| defer events | 223 |
| `⚑ SURFACE` pages (member un-reapable) | 100 |
| pages suppressed by damping | 89 |
| worktrees actually removed | 26 |
| `Auto-shutdown idle teammate` events | 333 |
| `✓ closed pane` events | 210 |

26 distinct members surfaced as un-reapable; the shared-cwd cases (`unifi-web` ×9, `microsoft-2` ×8,
`dfs-risk` ×8) are the ones burning the pages. Every one of the 199 distinct member names the closer
log touched in the window is in the named-spawn census — the janitor's entire population is our
named agents, nothing else.

---

## (d) Latency, last `idle_notification` → lead's shutdown_request

n = 58 (members with both an idle frame and a lead teardown).

| bucket | n |
|---|---|
| < 60 s | 13 |
| 1 – 5 min | 6 |
| 5 – 30 min | 7 |
| 30 min – 2 h | **23** |
| > 2 h | 9 |
| **median** | **31.8 min** (1,910 s) |
| p10 | 6 s |
| p90 | 2.9 h (10,361 s) |
| max | 11.4 h (41,174 s) |

Bimodal, and the modes are two different leads. 13 leads shut down within a minute of the report
landing — they are running the protocol. The 32 above 30 minutes are leads that kept working and got
round to it later, or never did (those are in (c), not here). The median lead that *does* tear down
leaves its member resident for **half an hour after it finished**.

---

## (e) idle_notification volume, and the idle-survivor loop

172 `idle_notification` frames reached lead transcripts in the window, across 57 of 79 leads,
covering 145 distinct (lead, member) pairs.

| idle frames received per member | members (of 338) |
|---|---|
| **0** | **205 (60.7%)** |
| 1 | 111 |
| 2 | 18 |
| 3 | 3 |
| 4 | 1 |

| | n |
|---|---|
| idle frames arriving **after** the lead's shutdown_request for that member | **11** |
| members that went idle and were never torn down by the lead | 133 emitting ≥1 idle; 75 of them with a measurable dangle |
| members spawned, never idle-reported, never torn down | **76** |

Two findings here, and they point opposite ways.

1. **The idle-survivor loop is real but small: 11 frames.** A member re-pings after the lead has
   already requested shutdown — consistent with `skills/agent-teams/SKILL.md:381` (*"An idle agent
   will never answer the request"*): the request queues, the agent wakes, re-reports idle, and the
   lead sees a frame for an agent it believes it has closed.
2. **The bigger hole is the other direction: 60.7% of members never reported idle at all.** A lead
   that waits for an idle frame before tearing down will wait forever for 205 of 338 members. The
   76 members that were neither heard from nor torn down are the population the janitor inherits.

---

## Adversarial pass — what this classifier cannot see, bounded

| blind spot | bound | method |
|---|---|---|
| **Shutdown sent by a successor session after a `--recycle`/`/handoff`** | **0 of 151** lead-abandoned members received a `shutdown_request` from any *other* session in the corpus | built a global `shutdown_request` target → sid map over all 274 event-carrying top-level transcripts; no orphan name is targeted by a session other than its own lead |
| **Teardown via Bash rather than SendMessage/TaskStop** (`cc-teardown`, `it2 session close`, `kitty @ close-window`, manual `teammate-auto-shutdown.sh`) | **8 of 79 leads** (9 × `cc-teardown`, 8 × manual `teammate-auto-shutdown`, 2 × `kitty @ close-window`, 1 × `it2 session close`) | regex over every Bash `tool_use` command string in all 79 lead transcripts. **This is the one correction the "NOTHING" figure needs**: at most 8 of the 42 NOTHING leads cleaned up out-of-band, so the true floor is **34/72 (47%) doing nothing at all**, not 58%. |
| **Leads whose transcript is missing** | **46 of 82** team configs have a `leadSessionId` with no `.jsonl` anywhere in the four config dirs (`find`-verified, not glob-inferred) | those leads are invisible to (b)/(d)/(e) entirely. They are *not* in any denominator above — every table is over the 79 leads whose transcript exists. Direction of the bias is unknown. |
| **Prose "shut down" broadcast** | 0 leads | searched all non-shutdown SendMessage bodies for `shut ?down\|stand down\|you can stop\|wrap up`. The skill's warning at `:376` (*"Plain text broadcasts do NOT close panes"*) describes a failure nobody is committing — because nobody is sending anything. |
| **`ps`-verification after teardown** | not measured | the skill mandates `pgrep -f "agent-id <name>@"` at `:382`. Not instrumented here; would need a Bash-command scan keyed on `agent-id`. Named as an open gap. |
| **`TeamDelete`** | 0 calls in 30 days | consistent with the implicit-team model having no such tool. |

**The one that changes a number is the Bash arm.** It is reported above and folded into the headline.
The 46 missing transcripts are the largest unbounded residual and the reason every figure here is
stated over the 79 observable leads rather than the 82 known leads.

---

## Instrument warnings for the next session

- **The lifecycle log is LOCAL time; transcripts are UTC (`Z`).** A first pass without conversion
  said "2 of 151 members were ever reaped"; with `America/Los_Angeles → UTC` applied the answer is
  **124 of 151**. A 7-hour offset inverted the study's main conclusion. (Same shape as
  `process-start-time-renders-in-ambient-timezone`.)
- **Member names are reused across waves** (`gate-probe`, `w1`, `reso-qa`…). Matching a close event
  to a member by name alone credits an earlier incarnation. Every match here requires
  `close_ts ≥ spawn_ts`.
- **`/usr/bin/grep -l` over the corpus is nearly useless as a prefilter**: 4,529 of 7,803 files match
  `"name":"Agent"` / `shutdown_request` / `idle_notification` because the always-loaded
  `CLAUDE.md` + `.claude/rules/agent-operating-lessons.md` quote those strings into every session.
  Only **314** files carry a real `tool_use`/frame record. Parse, don't grep-count.
- **`idle_notification` frames arrive as a plain STRING in `message.content`**, not always as a block
  list. A block-list-only walker under-counted 172 frames as 32.
- Team `config.json` registers pane-backed members only — see (c).

## Re-derive

Scripts used are throwaway (`/private/tmp/…/scratchpad/lc/`), but the pipeline is four steps:
(1) `find` all `projects/*/*.jsonl -mtime -30` across the four config dirs; (2) `xargs -P8
/usr/bin/grep -lF` the five markers to get candidates; (3) stream-parse candidates with a
`multiprocessing.Pool`, keeping only `Agent`/`SendMessage`/`TaskStop`/`TeamDelete` `tool_use` blocks
and user records containing `idle_notification`/`shutdown_response`/`teammate_terminated`;
(4) join against `~/.claude/logs/teammate-lifecycle.log` **with TZ conversion**.
