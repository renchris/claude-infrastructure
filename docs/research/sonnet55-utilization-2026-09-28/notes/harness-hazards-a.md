# Harness hazards A: mid-turn injection misread, account switch and preserved thinking, progress-update blocks

Scope: the three hazards in the brief, mapped onto `claude-infrastructure` at `9eb533126`. Nothing in that repo was edited.
Sources: `/tmp/s55/prompting.txt` (P), `/tmp/s55/migration-guide.txt` (M), `/tmp/s55/preserved-thinking.txt` (PT), `/tmp/s55/whats-new-sonnet-5-5.txt` (W), `/tmp/s55/announce.txt` (A), `/tmp/s55/cl.md`, and the 2.1.284 binary (`strings` of `/tmp/s55/b284/package/claude` → `/tmp/s55/hazA_strings.txt`).
I also read the repo's `.claude/rules/*.md`. None of its lessons bear on these three hazards.

Measurement scripts (outside the repo): `/tmp/s55/hazA_scan{,2,3,4,5}.py`. Every number below names its script.
The transcript corpus is `~/.claude-{secondary,tertiary,quaternary,next}/projects/**.jsonl`. For the 3-day window that is 1,257 files: 20,391 main-thread and 32,158 subagent tool calls (hazA_scan.py).
Only 55 main-thread and 8 subagent Sonnet 5.5 assistant records exist in that window. That is too few to measure Sonnet 5.5's own reaction. The hazard below is therefore **documented exposure**, not an observed Sonnet 5.5 failure.

---

## (1) Mid-turn injection misread

**What the doc says.** P§Mid-turn user messages: text that arrives right after tool results can make Sonnet 5.5 treat it as an injection, then ignore it or ask the user to confirm. The listed causes are a token countdown after every tool result, per-step harness instructions, and user text inside `tool_result`.
The occasional one-turn reminder "arrives far less often". If you see this reaction to a reminder of your own, "send the reminder less often". Task budgets "haven't been seen to cause this misread".
P§User-facing progress updates: send the silent-turn reminder after about 5 silent steps, and stop after 2 or 3.
The mechanism and the guidance are **documented only for Sonnet 5.5**. No Opus 5.5 doc in `/tmp/s55` says the same.

### 1a. Everything that reaches the model around a tool call, by measured frequency

These are 3-day counts from hazA_scan2.py / hazA_scan3.py. The rate is per tool call of the same thread kind.

| Source | Owner | Where | Channel | Main (Opus 5.5) | Subagent (Opus 5.5) | Dedup/damper |
|---|---|---|---|---|---|---|
| `<total_tokens>N tokens left</total_tokens>` | **CC harness** | binary `totalTokensReminder` (@internal setting; env `CLAUDE_CODE_TOTAL_TOKENS_REMINDER`; GrowthBook default `padded-countdown`) | meta attachment after **each tool result** | 13,418 / 14,578 = **92%** | 22,512 / 25,716 = **88%** | none; this is a per-step countdown |
| "The user hasn't heard from you in a while — say in a few words what you're doing, then continue." | **CC harness** | binary `silent_turn_reminder`: after 5 silent steps (`tengu_hushed_lark`, default 5), at most 3 per silent stretch (`Z2t=3`); env `CLAUDE_CODE_SILENT_TURN_REMINDER{,_TURNS,_TEXT}` | meta attachment | 608 / 14,578 = **4.2%** | 0 | vendor cap, as P recommends |
| `mailbox-drain.sh post-tool` (peer mail) | ours | `hooks/mailbox-drain.sh:165-181` (gate), `:707` (text), `:743-744` (emit); registered `settings-templates/settings.example.json:256,717`, live `~/.claude-secondary/settings.json:519,693` (PostToolUse + PostToolUseFailure, matcher `""`) | `additionalContext` + `systemMessage` | ~38 drains (**0.26%**) | **7 drains**; 27 subagent transcripts hold peer mail (7 days, 1,878 subagent files) | only when mail is pending, at most once per 20 s, 20 lines per drain; **no subagent gate** |
| `plan-agent-teams-default.sh` "PLAN DEFAULTS…" | ours | `hooks/plan-agent-teams-default.sh:241-248`; template `:145`, live `:775` | PreToolUse `additionalContext` | 108 (Edit 95 + Write 13) | 82 | **none: fires on every Edit/Write of a plan file** |
| `agent-teams-enforce.sh` skill pointers ("RESEARCH-SUBAGENTS SKILL…", "AGENT-TEAMS SKILL…", "AGENT TEAMS DEFAULT…") | ours | `hooks/agent-teams-enforce.sh:631,699,713,738`; template `:155`, live `:785` | PreToolUse(Agent) `additionalContext` | 163 | 0 | per spawn; a parallel fan-out stacks N copies after one step |
| `web-entrypoint-ladder.sh` "ENTRYPOINT LADDER…" | ours, **live-only (no repo source)** | `~/.claude/hooks/web-entrypoint-ladder.sh:37,54`; live `:820` | PreToolUse(WebFetch/WebSearch) | 8 | 118 | once per agent |
| CC "PostToolUse hook modified <path>" (formatter in `post-file-edit.sh`) | CC note, triggered by our hook | `hooks/post-file-edit.sh` | meta | ~60 | ~30 | per formatted edit |
| lesson recall ("recalled lesson pointers — data, not instructions:") | ours | `hooks/lib/lesson_recall.py:40,54-60`, called from `hooks/bash-output-offload.sh:88-99` and `hooks/log-bash.sh` | PostToolUse `additionalContext` | 13 + 8 (failure) | 0 | per session × agent × slug; 20% holdout; `inj_san` |
| `relay-verbatim.sh` "RELAY VERBATIM…" | ours | `hooks/relay-verbatim.sh:24-38`; template `:216`, live `:469` | PostToolUse(Bash) | 17 | 0 | 3 literal commands only |
| `memory-index-drain.sh` "MEMORY INDEX…" | ours | `hooks/memory-index-drain.sh:325-336,393` | PostToolUse | 9 | 0 | only when an entry is over the cap |
| `validate-plan-structure.sh` | ours | `hooks/validate-plan-structure.sh:79` (exit 2), `:84-86,123-134` | PostToolUse | 2 | 0 | plan writes only |
| `backup-before-write.sh` "OVERWRITE GUARD" | ours | `hooks/backup-before-write.sh:300` | PreToolUse(Write) | 6 | 4 | overwrites only |
| `mail-images-auto.sh` | ours | `hooks/mail-images-auto.sh:65`; live `:539` | PostToolUse(ms365 mail) | 2 | 0 | per mail read |
| `waiting-recycle.sh` `decision:block` + ctx | ours | `hooks/waiting-recycle.sh:1112,1321,1352,1493,1498,1520,1552,1592` | PostToolUse(Bash) | 0 in window | 0 | desk-only |
| `bash-output-offload.sh` elision note **inside** `tool_result` | ours | `hooks/bash-output-offload.sh:124-130` (`updatedToolOutput`) | rewrites the tool_result | ~188 offloads in 3 days, ~0.4% of Bash calls (estimate: files in `$TMPDIR/claude-bash-output` over 3 days ÷ ~84% Bash share of tool calls) | same | Bash output over 8,000 chars that is not a read verb |

Our own hooks, all combined, inject around a tool call at about **2.9% of main and 1.0% of subagent tool calls** (hazA_scan2.py: main 281 Pre + 147 Post over 14,578; subagent 203 + 46 over 25,716).
The CC token countdown alone is **30 to 90 times more frequent** than all our hooks together.
Stop-hook blocks (`session-continue`, `completion-assert`, `anti-deference-nudge`, …) arrive as "Stop hook feedback" after `end_turn`, not after tool results. That is outside the documented trigger (hazA_scan.py: 442 `hook_blocking_error` Stop in 3 days).

### 1b. Per-item verdict (exposure / severity for a Sonnet 5.5 session or subagent / smallest change)

1. **`mailbox-drain.sh post-tool`: exposed. Severity HIGH.**
   - It is the doc's exact shape. Text written by a party other than the user arrives right after a tool result and carries imperatives. Measured example: a subagent got "please add ONE pointer line to skills/launch-film/SKILL.md…" (`~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-hero-film-regrade/d64fb5fe…/subagents/agent-a29dfce6c64a18f37.jsonl:418`).
   - The wrapper says "This is a message TO you, not something you typed" (`:707`). An injection-trained model can easily read that line as the tell.
   - It is also **misdelivered**. The hook keys the inbox on `session_id` (`:146`), and a subagent's hook payload carries the parent's `session_id`. There is no `agent_id` check anywhere in `mailbox-drain.sh` or `hooks/lib/mailbox-pending.sh`, so subagents drain the lead's inbox.
   - Measured: 27 subagent transcripts in 7 days contain peer-mail attachments. A sibling note, `cc284-hooks.md` "Observation outside the brief", saw the same thing live.
   - The drain then advances the shared `.seen` cursor (`:749-751`), so the lead likely never sees that mail. This is an estimate from reading the code; I did not test it.
   - For a Sonnet 5.5 subagent the likely outcome is that it ignores the mail or asks about it. The mail is lost either way.
   - **Smallest change:** in `post-tool` mode, `exit 0` when the payload has a non-empty `.agent_id`. This is one line near `:165`. It removes the subagent exposure and the mail loss together.
   - For Sonnet 5.5 leads, optional: drop the "not something you typed" sentence, which invites the provenance question, and present the block as a peer-session notice.

2. **CC `total_tokens_reminder`: exposed; CC-owned. Severity MEDIUM, unverified.**
   - A countdown after 88-92% of tool calls, in subagents too, is exactly the pattern P names. P also says task budgets, which are similar, "haven't been seen to cause this misread", and Anthropic ships this default in CC.
   - We do not set it: no `totalTokensReminder` or `CLAUDE_CODE_TOTAL_TOKENS_REMINDER` in either settings file, any repo script, or the environment.
   - **Smallest change:** none by default. If a Sonnet 5.5 A/B shows the misread, set `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off` (or the @internal settings key `totalTokensReminder: "off"`) for Sonnet 5.5 launches only. Do not flip it fleet-wide blind.

3. **`plan-agent-teams-default.sh` PLAN DEFAULTS: exposed. Severity MEDIUM.**
   - A fixed per-step instruction, repeated on every plan edit with no dedup (`:241-248`). This is the doc's "harness adds instructions … after the tool results on every step".
   - **Smallest change:** a once-per-(session, file) marker before the `cat <<'EOF'`.

4. **`agent-teams-enforce.sh` pointers: exposed. Severity LOW-MEDIUM.**
   - Per spawn; N parallel spawns put N copies after one step.
   - **Smallest change:** once per session per pointer kind.

5. **Silent-turn reminder (CC): exposed. Severity LOW.** It is the doc's own recommended pattern and already capped at 3. Keep it. Note that it already fires on Opus 5.5 main threads (608 in 3 days), so it is not Sonnet-only in practice.

6. **Lesson recall, `web-entrypoint-ladder`, `relay-verbatim`, `memory-index-drain`, `validate-plan-structure`, `backup-before-write`, `mail-images-auto`: exposed. Severity LOW.**
   - Each is event-specific or once-per-agent, so its frequency is in the doc's "occasional" class.
   - Lesson recall already labels itself "data, not instructions", which is the right shape.
   - **SSOT note:** `web-entrypoint-ladder.sh` and `net-context-stamp.sh` are registered live (`~/.claude-secondary/settings.json:820`, SessionStart) but have no source in `hooks/`.

7. **`bash-output-offload.sh` note inside `tool_result`: exposed. Severity LOW.**
   - P's strongest warning is about **user** text inside `tool_result`. This note is harness-authored and shaped like tool output.
   - **Smallest change:** optional. Make `:124-127` purely descriptive by dropping the "read a range with sed -n … or search it with grep -n" imperative.

**Is Opus 5.5 subject to the same?**
- Not documented. I found no Opus 5.5 statement.
- Measured on the same harness (hazA_scan5.py, 7 days): 2 of 18,816 Opus 5.5 main text blocks mention provenance or injection. Both were correct discriminations ("This turn came from forwarded peer mail, not from you"), not ignored instructions.
- So under a ~92% token countdown plus our hooks, Opus 5.5 shows no misread. Sonnet 5.5 cannot be judged here: 31 text blocks in the window.

---

## (2) Account switch and preserved thinking

**Facts (docs):**
- Sonnet 5.5 thinking blocks "work only in the account that produced them, or in an account linked to it". From another account, "the API drops the block before the model sees it, and the request succeeds. The model answers without the reasoning". The drop is silent unless the `thinking-binding-controls-2026-08-01` beta is set, in which case `input_transformations` reports `organization_binding_mismatch` (PT:74-78, W:95-97).
- The blocks are not deleted: sent again from the original account, they are readable again.
- PT says a session "might still increase" token use because "Claude can sometimes think more to re-create the dropped thinking".
- A (line 388) names "switching accounts mid-session in Claude Code" explicitly.
- **Opus 5.5 and Fable 5.1 are not account-bound.** PT:20 ties only Sonnet 5.5; "Blocks from earlier models aren't affected" (PT:76). The 2.1.284 catalog gives `org_locked_thinking` to `claude-sonnet-5-5` only.
- Opus 5.5 and Fable 5.1 still run the model check (every account) and the prefix check (default-enforced only for accounts created on or after 2026-08-31, PT:22,204-207). PT:26 says "Nothing changes for you if Claude Code … builds your requests".
- Model moves (PT:45-49):
  - Sonnet 5.5 → any other model: loses Sonnet 5.5 reasoning.
  - Opus 5.5 → Sonnet 5.5: loses Opus reasoning.
  - Opus 5.5 → Fable 5.1 (Claude API): keeps it.
  - Fable 5.1 → Opus 5.5: loses Fable reasoning.

**What the 2.1.284 binary does.**
- It records a `credential_org` attachment and, on an org change, logs `context_credential_org_change`.
- It shows a warning only when all of these hold: the history has thinking blocks, the model has `org_locked_thinking`, and the GrowthBook gate `tengu_lexical_glade` (default **false**) is on.
- The warning text reads: "Claude can't use thinking from another organization … It isn't deleted: resume this session signed in to that organization to use it again. Claude's next responses may be slower and use more tokens because it has to reread this session and generate new thinking."
- Default behaviour is therefore a **silent** drop.

**Our accounts are 4 distinct organizations** (measured, hazA_scan4.py, `credential_org.organizationUuid` per config dir): secondary `fb09ef51`, tertiary `1a71eca0`, quaternary `c570be13`, next `260ebc56`. `accounts.json` describes them as 4 separate Claude Max accounts. Nothing indicates they are "linked".

**Volume:** 34 source transcripts retired as `*.jsonl.handed-off` and 67 limit-recover bundles in 14 days (measured, `find … -mtime -14`).

### Verbs that carry thinking blocks to another account (hazard applies)

| Verb | Evidence | Mechanism |
|---|---|---|
| `cc-lr switch [--target A\|auto]` and the driver form | `bin/cc-lr:128-146`, dispatch `:1413` → `cmd_switch` `:871` | "same window, same uuid, new account" |
| `cc-lr recover` → `lr-fleet` → `lr-handoff` | `scripts/limit-recover/lr-handoff.sh:1153` builds the `lr-fire-resume` argv | transplant, then resume |
| `lr-transplant.sh` | `scripts/limit-recover/lr-transplant.sh:2-9,210,480` (`cp -p` + sha verify) | copies `<sid>.jsonl` and `<sid>/` byte-for-byte, so thinking blocks and signatures are intact |
| `lr-fire-resume.sh <account> <wt> <sid>` | `scripts/limit-recover/lr-fire-resume.sh:2-21,309-334` | `claude --resume <sid>` under the target `CLAUDE_CONFIG_DIR` |
| `handoff-fire.sh --recycle --resume-launcher F --resume-cfg DIR` (`--transplanted-source`) | `scripts/handoff-fire.sh:159-196` | the same uuid resumed on the target account |

**Verbs that do not carry thinking (safe):**
- `handoff-fire.sh --recycle --account A` (default mode, `scripts/handoff-fire.sh:140-150`). It relaunches a **fresh** session from a brief payload, which is the doc's recommended "start from a summary" (PT FAQ). Same for `/handoff` fresh fires.
- `cc-lr upgrade` and `handoff-fire --same-account` keep the same account (`:166-173`).

### What happens to a moved session, per the docs

- **Sonnet 5.5 moved from account X to account Y:**
  - Every Sonnet 5.5 thinking block written on X is dropped on each request from Y. The requests succeed, and the dropped blocks are not billed.
  - The model continues without its earlier reasoning and may re-derive it, at more tokens and latency.
  - New thinking produced on Y is valid on Y.
  - Moving back to X makes X's blocks usable again, but then Y's blocks drop.
  - No error is shown in CC unless `tengu_lexical_glade` is on. Our watchers cannot see the drop, because CC does not surface `input_transformations`.
- **Opus 5.5 moved across accounts:** reasoning is kept. The only risk is a prefix change on resume, which CC owns. CC 2.1.282 fixed resume re-sending changed history; see sibling `cc284-hooks.md:61`. Whether our accounts are default-enforced for the prefix check is not determined, because their creation dates are unknown.
- **Fable 5.1 moved across accounts:** same as Opus 5.5.

**Model-switch side effects in the same verbs** (these hit Opus/Fable/Sonnet regardless of account):
- `lr-upgrade.sh:117-123` `lru_target_model` maps every non-Fable model to `versions.opus_latest` (`claude-opus-5-5`, `model-config.yaml:59`). A Sonnet 5.5 session "upgraded" in place is moved onto Opus 5.5, and all its Sonnet 5.5 reasoning is dropped: "No other model reads thinking blocks from Claude Sonnet 5.5".
- `lr-fire-resume.sh:326-334` also defaults to `opus_latest` when no `--model` is given.
- `lr-handoff.sh:621-631` carries the model from the transcript. That path keeps the model.

**Severity:** MEDIUM for Sonnet 5.5 main sessions. There are almost none today: `versions.sonnet_latest` is still `claude-sonnet-5` (`model-config.yaml:127`), and the window holds 55 main-thread Sonnet 5.5 records. Severity rises to HIGH if Sonnet 5.5 becomes a launch tier.
- Subagents: `agents/deep-research-sonnet.md` and `agents/research-decomposition-critic.md` declare `model: sonnet`, which 2.1.284 resolves to Sonnet 5.5 (`cl.md` 2.1.284 L3). Their transcripts ride the transplant, but they matter only if resumed on the new account.

**Smallest changes:**
- (a) In `lr-handoff.sh`, right after `lrh_tier_from_transcript` (`:621`): if `RT_MODEL` is `claude-sonnet-5-5` and the target differs from the source, print one line: "Sonnet 5.5 reasoning does not cross accounts; the resumed session re-derives it". Optionally prefer the brief-based `handoff-fire --recycle --account` rail.
- (b) In `lr-upgrade.sh:121-122`, add a `*sonnet*)` arm that keeps the Sonnet family (e.g. `versions.sonnet_latest`), so an in-place upgrade is not a silent model switch.

---

## (3) Progress-update thinking blocks and SendUserMessage

**What the doc says.**
- On Sonnet 5.5, between-tool notes longer than a sentence or two come back as progress-update **thinking** blocks. These are empty at the default `display:"omitted"`.
- "A response can begin with a thinking block … Don't assume the first content block is text" (M:84,91,325-329).

**What we observe.**
- CC writes one transcript record per content block.
- In our Sonnet 5.5 records the thinking blocks are **empty** (2 of 2, hazA check). Progress notes are therefore not persisted as text.
- The 2.1.284 binary sets `display:"updates"` only under a conditional `connector_text` mode. Whether that reaches the persisted transcript is not determined.

**No `content[0]` readers.**
- I grepped `hooks scripts bin lib core tools` for `content[0]`-style indexing of transcript records. The only hit is `hooks/pr-gate.sh:160`, which indexes PR-body lines, not a transcript.
- All 27 files that filter `type=="text"` were listed.

**Parsers whose verdicts depend on assistant text and could shift under Sonnet 5.5:**

| Parser | Where | Behaviour | Sonnet 5.5 effect | Severity / change |
|---|---|---|---|---|
| Stop classifiers: anti-deference, completion-assert, handoff-claim-assert | `hooks/anti-deference-nudge.sh:159-161`, `hooks/completion-assert.sh:243-245`, `hooks/handoff-claim-assert.sh:53-56` | walk back to the **last record with non-empty text** | robust: the final answer is text | none |
| `dispatch-assert.sh` TURN_TEXT | `hooks/dispatch-assert.sh:145-148` | concatenates all text in the turn to find a stated dispatch or drop | a statement made as a between-tool note is invisible, which risks a false "not stated" block | LOW-MEDIUM; document that claims must be in final text, or accept the risk |
| `cc-classify` `safeguard_blocked` | `bin/cc-classify:355-381` | counts a post-refusal assistant record as recovery (`TURN`) only if it has non-empty text; checked **before** `active` (`:845-860`) | a Sonnet 5.5 session that recovers and proceeds with tool calls plus thinking-only notes stays `safeguard-blocked`. Also, 2.1.284 changed the Sonnet safeguard notice wording (`cl.md` 2.1.284 L67), so `SAFEGUARD_SIGNATURES` (`:82`) may miss it; the `model_refusal_no_fallback` subtype remains as a corroborator | LOW-MEDIUM; count a non-error `tool_use` record as `TURN` |
| `cc-classify` `livelock_census` | `bin/cc-classify:271-280` | text only | fewer samples, so it fails toward "not livelocked" (safe) | none |
| `cc-classify` `last_assistant_ts` / `turn_census` | `bin/cc-classify:221-253` | block-type agnostic | liveness unaffected | none |
| `waiting-recycle.sh` rot / open-decision hold | `hooks/waiting-recycle.sh:1033-1054,1080,1148` | takes the **last assistant record of any type** (no `isSidechain` filter) and extracts its text | at PostToolUse the last record is structurally the `tool_use` record, so MSG is almost always empty **for every model**. This is a pre-existing defect that Sonnet 5.5 does not make worse | pre-existing; walk back to the last text record, as the Stop hooks do |
| `lr-audit.py` last_kind | `scripts/limit-recover/lr-audit.py:333-340,1405` | an empty-text record becomes `assistant_thinking`; "finished" requires `assistant_text` | final answers are text, so this is fine | none |
| `transcript_norm.py` (session index, memory extract) | `hooks/lib/transcript_norm.py:55-65` | text only | Sonnet 5.5 progress notes are absent (they are empty on disk anyway) | informational |
| `/goal` evaluator (CC) | `CLAUDE.global.md:225-228` | "sees only … assistant prose or a tool_result" | proof stated only in a progress-update block is likely invisible to the evaluator. This is an estimate: CC-owned, not tested | LOW-MEDIUM; for Sonnet 5.5 goal sessions, state proof in final text or as a tool_result |

**SendUserMessage.**
- The 2.1.284 binary ships a `SendUserMessage` tool (its strings include "You ended the turn without calling SendUserMessage").
- Nothing in our repo or settings references it. No PreToolUse catch-all exists, so nothing blocks it.
- Our PostToolUse catch-alls (`mailbox-drain post-tool`, `teammate-checkpoint`, `cc-permission-beacon clear`) would also fire after it, so peer mail could land right after a message to the user.
- Severity LOW. The fix is the same `agent_id`/damper change as in (1).
