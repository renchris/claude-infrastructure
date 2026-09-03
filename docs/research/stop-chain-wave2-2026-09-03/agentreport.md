# d8147be371cd — "Agent-tool report delivery drops final output" · drivability research

Agent: `r-agentreport2` (read-only). Repo: `/Users/chrisren/Development/claude-infrastructure`.
All figures below are measured this session from disk, 2026-09-03.

---

## VERDICT (lead this)

**NOT-AS-SPECIFIED — and the premise is FALSIFIED twice over.**

1. **There is no delivery defect.** A named `Agent({name: …})` spawn has *no return value by
   design*: its `tool_result` is a spawn acknowledgement, and the child's final text goes to its
   own transcript and nowhere else. Measured across 341 Agent calls in 21 days: **0 of 207 named
   spawns ever returned a report; 117 of 118 non-error *unnamed* spawns did (99.2%).** The lead
   used `name:` on all 13 calls. Nothing dropped anything.
2. **The proposed tool already exists, is live, and is tested.** `bin/cc-agent-harvest` (342 lines,
   landed `5e9ef347c`, symlinked into `~/.claude/bin/`, 8/8 bats green) was built on 2026-08-09 for
   *this exact failure*, and it solves the name→transcript mapping the item assumes is unsolved. I
   ran it against the failing team: it resolved **all 8 members by name** and harvested the three
   stranded wave-2 reports (20,189 / 11,352 / 584 chars).

The one real, unclosed gap is **discoverability**: `cc-agent-harvest` is named in *zero* skills,
commands, hooks, or `CLAUDE.md` — which is why a lead sitting on a stranded wave rebuilt the
recovery by hand and filed a duplicate. That is a one-line-per-file doc fix, drivable in minutes.

Close `d8147be371cd` as **duplicate/refuted**, and land the pointer.

---

## 1. CHARACTERISATION — it is (a), and (a) is the documented contract

**Not (b) harness-drop, not (c) lead's turn ending.** The lead's transcript contains a
`tool_result` for **every one of its 13 Agent calls** — zero missing. The content is the
tell.

`~/.claude-secondary/projects/-Users-chrisren-Development-claude-infrastructure/6d405232-4824-4694-80a1-23165ef59be4.jsonl:987`
is the `tool_use`, and `:990` is its `tool_result`, verbatim:

```
Spawned successfully. (This tool result is internal metadata — never quote or paste any part of it,
including the ID below, into a user-facing reply.)
agent_id: r-custody@session-6d405232
name: r-custody
The agent is now running and will receive instructions via mailbox.
```

That is the whole return. There is no second one. The 13 calls are:

| tool_use id | name | shape |
|---|---|---|
| `toolu_01TtvrSuPHtUeXpcr73Sv56f` | `stop-blockers` | named |
| `toolu_01VppUJyxo7xMz9iAxopjFRq` | `stop-readout` | named |
| `toolu_0144C5ECJRqkBPiZUh98EF9G` | `stop-context` | named |
| `toolu_01PhE6jsD6vriuncHgMpJHqD` | `stop-sideeffects` | named |
| `toolu_011ZRdnXbKbZGfGyMDkA3Jsi` | `blockers2` | named |
| `toolu_01RretBNCFuNqawerAAshNz9` | `readout2` | named |
| `toolu_012YZzxWX8j629U4E9joB7XY` | `context2` | named |
| `toolu_01UhT3pKkMpLxmgv66nTeanu` | `sidefx2` | named |
| `toolu_016acKRcCmgg93wcPE8kTvR9` | `r-custody` | named |
| `toolu_012ku4gEt8AAGPgfAnH4ni6P` | `r-guard` | named |
| `toolu_01XHQnTpuzHgZmv2w5vUqhnz` | `r-goal` | named |
| `toolu_01Lx93CZuSWGkQchVr8zkNoo` | `r-reader` | named |
| `toolu_01Mn7mTpyyhjVammmfPiZodS` | `r-agentreport` | named |

All 13 returned the spawn ack. **13/13 named. 0 unnamed.** That single input field decides the
whole outcome.

**Corroborating structure.** Every record in the lead transcript carries `isSidechain:false` —
there are no sidechain records at all. A named agent is a *separate session with its own transcript
file*, not an in-process sidechain, so there is no channel on which a final text could have
arrived.

**What the agents actually did.** Tool census of the four wave transcripts:

| transcript | lines | tool calls | SendMessage? |
|---|---|---|---|
| `4a25b4b8-c4cd-4dbb-925f-8971336c6fbe` (`blockers2`) | 123 | 8 Read, 6 Bash | **none** |
| `2da4e712-5e6f-48cb-872d-5cd4d5bc00e3` (`context2`) | 157 | 14 Bash, 5 Read, 2 SendMessage, 1 ToolSearch | 2 — both `shutdown_response` |
| `db812e05-6578-46b3-bf7d-6f7fdfc24a01` (`readout2`) | 191 | 18 Bash, 5 Read | **none** |
| `d0a1f797-6a3c-4487-81d4-7d49dd2debf1` (`sidefx2`) | 109 | 10 Bash, 5 Read | **none** |

Three of four never opened the delivery channel at all. The fourth opened it only to approve its
own shutdown, and its payload states the misconception in the agent's own words:

```json
{"type":"shutdown_response","approve":true,
 "reason":"Read-only analysis complete; report delivered in final text. No files written, nothing uncommitted."}
```

`2da4e712…jsonl`, tool_use `toolu_011nQ1m2Ntn7i3suDzHFpw4f`. **"Report delivered in final text"** is
false for this spawn shape, and the agent had no way to learn that from its brief.

**Delivery channel census on the lead side.** 13 `<teammate-message>` envelopes arrived across the
whole session — **12 are `idle_notification`, 1 is from `system`, 0 carry a report**:

```
2 blockers2 · 2 context2 · 2 readout2 · 3 sidefx2 · 1 stop-blockers · 1 stop-context · 1 stop-sideeffects · 1 system
```

Envelope shape (`:176`):

```
Another Claude session sent a message:
<teammate-message teammate_id="stop-sideeffects" color="purple">
{"type":"idle_notification","from":"stop-sideeffects","timestamp":"2026-09-02T08:09:28.580Z","idleReason":"available"}
</teammate-message>
```

**So: (a).** The agent never emitted on a channel that delivers. The lead's chase then failed for
the same reason — it asked each agent to *"Return it now as your reply"*, and a reply is exactly
the thing that goes nowhere.

### Two sub-claims in the backlog item, adjudicated

- ❌ **"SendMessage to a DEAD agent also returns success."** Refuted on the one clean instance.
  The send to `stop-blockers` returned
  `{"success":false,"message":"No agent named 'stop-blockers' is reachable.\nCheck the spelling, or use the agent ID from a background agent's spawn result."}`.
  The sends that returned `success:true` (`stop-sideeffects`, `stop-context`) went to agents whose
  *mailbox was still registered*; `success` there means **queued to inbox**, not **delivered or
  acted on** — a real but different, and much narrower, complaint.
- ✅ **"SendMessage to a live agent returns success then yields another idle ping."** True, and
  fully explained by (a): the chased agent answers in final text, which is invisible, and its next
  turn boundary emits another `idleReason:"available"`.

---

## 2. HOW GENERAL IS IT — a rate, over 341 calls / 21 days

Census: every `*.jsonl` under `~/.claude/projects` and `~/.claude-secondary/projects` modified in
the last 21 days and >10 KB; every `tool_use` with `name=="Agent"`; joined to its `tool_result` in
the same file. **Every call matched a result — 0 orphans.**

| spawn shape | n | ack only | error (spawn refused) | short (<500 ch) | **report ≥500 ch** |
|---|---:|---:|---:|---:|---:|
| **NAMED** (`input.name` set) | 207 | 180 | 26 | 1 | **0** |
| **UNNAMED** | 134 | 0 | 16 | 1 | **117** |

- **Named delivery rate: 0/207 (0%)** — 179 `Spawned successfully…`, 1 `Async agent launched
  successfully… agentId: a36e1a1ad1ec0b13d … Use SendMessage` (an older binary's ack wording, same
  semantics).
- **Unnamed delivery rate: 117/118 non-error = 99.2%.** The 16 errors are PreToolUse denials
  (`"Background subagents cannot write code. Implementation tasks require Agent Teams…"`) and
  `capacity-admit` spawn refusals — calls that never ran. The 1 short is a backgrounded Bash notice.

**Conclusion: this is not a standing defect and it is not "something about that session".** It is a
deterministic property of one input field. Unnamed subagent results arrive essentially always;
named ones never do, because they were never going to.

---

## 3. THE MAPPING PROBLEM — solved, and solved better than by name

The name→uuid mapping the item assumes is missing **is on disk**, in the team config:

`~/.claude-secondary/teams/session-6d405232/config.json`

Member record keys: `agentId, agentType, backendType, color, cwd, isActive, joinedAt, model, name,
planModeRequired, prompt, subscriptions, tmuxPaneId`. Live contents for the failing team:

```
team-lead       in-process  isActive=null  pane=leader  prompt=0 chars
blockers2       iterm2      false          218          1206
readout2        iterm2      false          219          1278
sidefx2         iterm2      false          221          1289
r-custody       iterm2      true           234          2499
r-guard         iterm2      true           235          2471
r-goal          iterm2      true           236          2396
r-reader        iterm2      true           237          2361
r-agentreport   iterm2      true           238          2596
```

The config stores the **name** and the **verbatim prompt**, but **not** the session id. The join is
therefore name → prompt → transcript, because the member's own transcript opens with that same
prompt inside a `<teammate-message teammate_id="team-lead">` envelope. Same bytes on both sides; no
new bookkeeping; cannot drift. That is exactly the strategy `bin/cc-agent-harvest` documents at
`bin/cc-agent-harvest:24-30` and implements at `:230-256`.

⚠️ **Do not join on a prompt prefix.** `cc-agent-harvest:44-58` records that its first version did,
and shipped a *false* join on its first live run — sibling briefs from one panel were byte-identical
until char 320, the wrong transcript matched, and it wrote one member's report under another
member's name at exit 0. The current code matches on the **full** prompt, falls back to the
**tail** (`PROMPT_TAIL_CHARS = 400`, `:36`), demands the fallback be **unique** or reports
`AMBIGUOUS` (`:248-253`), and **consumes** a transcript when claimed (`claimed` set, `:259`).

**So a `cc-agent-report <name>` is buildable — but it should not be built**, because the thing that
resolves the name already exists and is strictly safer than the naive form the item sketches.

---

## 4. DOES SOMETHING ALREADY DO THIS — yes: `bin/cc-agent-harvest`

`bin/cc-agent-harvest`, 342 lines, landed as `5e9ef347c`
*("feat(harvest): a named Agent returns nothing — harvest it from its own transcript")*, symlinked
live: `/Users/chrisren/.claude/bin/cc-agent-harvest -> …/claude-infrastructure/bin/cc-agent-harvest`
(dated 2026-08-09). Its header (`:5-18`) states the same finding this report re-derived, from an
earlier incident — three Fable 5 derivation panelists, real frontier tokens, three complete reports,
zero delivered.

Design points worth keeping:

- **Multi-store scan** (`config_dirs()`, `:64-80`) — walks `.claude`, `.claude-next`,
  `.claude-secondary`, `.claude-tertiary`, `.claude-quaternary`. A member can live in a different
  account's store than the lead; a single-root scan is a silent miss.
- **Verdict is the exit code** (`:31-35`): `0` all accounted for · `2` usage/no team ·
  `3` loss-risk (a member has output that could not be harvested, or no locatable transcript).
- **Statuses distinguish "nothing to harvest" from "harvest failed"**: `HARVESTED` · `NO-OUTPUT`
  (produced only narration — a real answer, does not inflate the loss verdict, `:272-277`) ·
  `NO-TRANSCRIPT` / `AMBIGUOUS` (both loss) · `NO-PROMPT`.
- **Provenance in the artifact** (`:283-290`) — the written `.md` names the transcript, model,
  backend, final-block timestamp and block count.
- `--dry-run`, `--json`, `--min-chars`, `--team`, `--session`.
- Tests: `tests/cc-agent-harvest.bats`, 177 lines, **8/8 pass, run this session** — including
  *"attribution: each member harvests its OWN transcript despite a long shared brief prefix"* and
  *"loss verdict: a member with no locatable transcript exits 3, not 0"*.

### It works on the exact wave that was "lost"

```
CLAUDE_CONFIG_DIR=$HOME/.claude-secondary cc-agent-harvest \
  --session 6d405232-4824-4694-80a1-23165ef59be4 --dry-run --json
```

→ `verdict: 0`, all 8 members resolved by name to a transcript uuid:

| member | status | chars | resolved session |
|---|---|---:|---|
| `blockers2` | HARVESTED | 584 | `4a25b4b8-c4cd-4dbb-925f-8971336c6fbe` |
| `readout2` | HARVESTED | **20,189** | `db812e05-6578-46b3-bf7d-6f7fdfc24a01` |
| `sidefx2` | HARVESTED | **11,352** | `d0a1f797-6a3c-4487-81d4-7d49dd2debf1` |
| `r-custody` | NO-OUTPUT | 0 | `aba04765-cbff-4664-ac91-39ff7b2bb281` |
| `r-guard` | NO-OUTPUT | 0 | `ba822ab1-6f0a-4be1-b02d-ce790e98d096` |
| `r-goal` | NO-OUTPUT | 0 | `280bb416-2c1f-4cc3-ab75-a1c5ca4130e2` |
| `r-reader` | NO-OUTPUT | 0 | `cc0d7bd5-d757-44b0-8397-d00ff2af9ae6` |
| `r-agentreport` | NO-OUTPUT | 0 | (in flight) |

The `NO-OUTPUT` rows are the wave-3 agents still running at the time of the call — correct, not a
miss. The three wave-2 reports the lead believed lost were recovered whole, by name, in one command.

### And the doctrine is documented too — in three places

- `skills/agent-teams/SKILL.md:75-80` — *"⚠️ A named teammate's result reaches you ONLY via
  `SendMessage`. The Agent call already returned `{status:"teammate_spawned", …}` at spawn time —
  there is no second return, and the child's final text goes to its own transcript and pane and
  nowhere else. Measured 2026-08-03: 3 of 4 named agents finished, went idle, and delivered nothing
  until explicitly asked. **State in every teammate brief that findings go out via `SendMessage`**,
  or the work completes and stays invisible."*
- `skills/research-subagents/SKILL.md:225-241` — § Delivery Contract (mandatory field 7):
  *"A subagent's prose is invisible. Only a file is delivered."* Plus the field-6-negates-field-7
  trap and the 2026-08-05 five-agent Next.js/Replicache incident (4 of 5 stranded).
- `skills/research-subagents/SKILL.md:253-256` — the manual recovery recipe (find the JSONL, take
  the last long assistant `text` block) — i.e. exactly the "RECOVERY PATH that worked" in the
  backlog item, already written down a month earlier.

---

## 5. THE ACTUAL GAP (the only drivable work)

`grep -rn "cc-agent-harvest" skills/ commands/ hooks/ .claude/ CLAUDE.md` → **no matches.** The
tool is referenced only in `bin/`, `tests/`, `docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md`, and
two backlog-consolidation JSON dumps. So:

- the skill that *tells you the reports are stranded* (`research-subagents` §Recovery) hands you a
  manual recipe instead of the command;
- the skill that *warns named agents deliver nothing* (`agent-teams:80`) never names the harvester;
- a lead in exactly this situation rebuilds the recovery by hand and files a duplicate item — which
  is what happened, twice (this item, and the 2026-08-09 one that produced the tool).

This is the "Spec-named ≠ built" memory inverted: here the mechanism **is** built and the prose
doesn't know. One pointer line in each of the two skills closes it; a matching sentence in
`docs/plans/TEAMMATE_SELFCLOSE_INVESTIGATION.md` is optional.

### Secondary gap, worth one line in the same edit — the join key is destroyed by shutdown

`cc-agent-harvest` joins through the member's `prompt` in the team config. **A member removed from
`config.json` becomes permanently unharvestable.** Live proof in the same team: `context2` approved
shutdown and is **absent** from `~/.claude-secondary/teams/session-6d405232/config.json` — its
638 KB transcript (`2da4e712-5e6f-48cb-872d-5cd4d5bc00e3.jsonl`, 157 lines, 14 Bash + 5 Read of real
work) can no longer be reached by name. The four wave-1 members (`stop-blockers`, `stop-readout`,
`stop-context`, `stop-sideeffects`), cancelled by the operator, are likewise gone from the config.

**Operational rule that follows: harvest BEFORE shutdown, never after.** `/wrap`-time or
teardown-time is too late. If a code change is wanted rather than a doc line, the smallest correct
one is to make the teardown path run `cc-agent-harvest` first — but that is a separate, larger item
and should be filed on its own evidence, not folded into this one.

---

## Disposition for `d8147be371cd`

**Close as duplicate + partially refuted.** Its three factual claims resolve as:

| claim | verdict |
|---|---|
| "Agent-tool report delivery drops final output" | **refuted** — named spawns have no return by design; 0/207 vs 99.2% for unnamed |
| "sends to already-dead agents also return success" | **refuted on the clean instance** — `stop-blockers` returned `success:false, "No agent named … is reachable"` |
| "Worth a helper (`cc-agent-report <name>`)" | **already built** — `bin/cc-agent-harvest`, `5e9ef347c`, 8/8 green, verified working on this very team |

Replacement work, if any is filed: *"name `cc-agent-harvest` in `skills/agent-teams/SKILL.md:80` and
`skills/research-subagents/SKILL.md:253`"* — small, in-repo, no new mechanism.

### Drivable in one session?

**Yes — but not the item as written.** Building `cc-agent-report` is redundant. The doc-pointer fix
is ~10 minutes including gate + land. The teardown-ordering fix (harvest before the config entry is
removed) is a genuine second item and should be scoped separately.
