# Prompt audit, shard hooks-a: model-facing text injected by hooks (first half of the list)

## Assumptions

- Scope: the 25 files that `git grep -lE 'additionalContext|systemMessage|permissionDecisionReason|"reason"' hooks` lists first alphabetically (of 52). Only the prose a hook sends to the model was audited; shell logic was read only to learn when and how often the prose is sent.
- Target model: Claude Opus 5.5 (default for every session these hooks run in); the same text reaches Sonnet 5.5 workers and Fable 5.1 panes.
- Measurement: a census of hook outputs in every transcript under ~/.claude*/projects modified in the last 7 days (1,460 files, 856 sessions with hook records), plus 14- and 30-day passes for rarer messages. Scripts: /tmp/capi-audit/hook_census.py, ctx_census.py, dod_check.py, dod_post.py, handoff_prompts.py, deny_count.py, pre_persist.py. Tokens are chars / 2.5 (the ratio fitted in docs/research/token-efficiency-2026-09-23/measure/hooks.md).
- Claude Code replaces any hook additionalContext over 10,000 chars with a <persisted-output> block holding a 2,000-char preview (hooks.md §4; confirmed here: smallest persisted 10.1 KB, largest inline 5,839 chars).
- permissionDecisionReason on allow/ask is shown to the user, not the model; systemMessage is display-only. Hooks that only use those channels cost no model tokens.

## Summary

The highest-impact finding is that the ms365 email recipe never reaches the model whole: all 19 injections in 14 days were 10.1-10.3 KB, just over the 10,000-char cap, so the model got a 2 KB preview (rules 0 and 0b) and a file path. Rules 1-6, including rule 5's thread-alias check, the one rule the hook says it cannot enforce, were cut. About 1 KB of 'this used to say' narration in the recipe is enough to fix that (hooks-a-01..05).

Second, agent-teams-enforce.sh still tells the model to call TeamCreate and pass team_name with 'worktree isolation' (hooks-a-06, -07). That text dates from 2026-04-17. The hook's own comments and the agent-teams skill say team_name and TeamCreate no longer exist, and isolation: beside name: silently demotes a teammate.

Third, five hooks re-send unchanged text into context at a high rate: PLAN GUARD on every plan Edit, the handoff-intent nudge on any prompt that mentions handoff-fire.sh, and three SessionStart blocks addressed to the operator that fire at nearly every session start (config-mirror, escalation, activation parity). Together that is about 3.5M chars (~1.4M tokens) written into context per 7 days. dod-persist's lineage injection is over the cap every time it carries history, so the preview shows the oldest captures and never the newest (hooks-a-09..14).

Counts by group: Group 1: 8 (1d migration-relative 6, 1d re-insertion 2). Group 2: 2 (stale API, conflicting with the skill). Group 3: not applicable (no tool definitions in this shard). Group 4: not applicable (no request-building code). The cost-optimization 2.2 items are 4 more, filed as cost-lever. Total 14: 8 string-replace, 4 needs-new-code, 2 operator-decision.

## Inventory (25 files) and per-file verdict

- `hooks/accounts-board.sh`: systemMessage only, so zero model tokens. Clean.
- `hooks/activation-watch.sh`: SessionStart additionalContext. The queue axis is damped; the parity axis is not (hooks-a-14).
- `hooks/agent-teams-enforce.sh`: Spawn deny reasons and allow nudges. Stale API (hooks-a-06, -07); migration-relative coefficient passage (hooks-a-08). DUPLICATE WORKER, SPAWN DEPTH/BUDGET/GENERATION reasons: keep-list (live-session and box-safety constraints, with reasons).
- `hooks/backup-before-write.sh`: PLAN GUARD re-sent on every plan Edit (hooks-a-09). OVERWRITE GUARD and the memory-neighbour note are per-event and short: keep.
- `hooks/bash-output-offload.sh`: Truncation note on large Bash output; contract text. Clean.
- `hooks/boundary-handoff.sh`: Stop block reason (also systemMessage); calm, advisory, about 400-700 chars. Clean (the double send of Stop reasons is Claude Code's, per hooks.md §3).
- `hooks/cache-expiry-warning.sh`: UserPromptSubmit, 316 chars, corrected 2026-08-16. Clean.
- `hooks/check-edit-boundary.sh`: DUPLICATE WORKER deny: emphatic, but it guards two live sessions writing one worktree, with the reason given: keep-list. Freeze/focus reasons are short. Clean.
- `hooks/config-mirror-assert.sh`: Operator-only alarm sent to the model at nearly every SessionStart (hooks-a-12).
- `hooks/curl-gate.py`: Short factual deny/ask reasons. Clean.
- `hooks/desk-brief-inject.sh`: Injects docs/templates/desk-boot-brief.md (7.5 KB, under the cap) to the desk pane only (5 fires in 14 d). Framing is mild. Clean.
- `hooks/dod-persist.sh`: Lineage injection over the cap whenever it has history; newest captures are lost (hooks-a-11). The 'binds you' contract frame encodes the operator's frozen-DoD rule, which completion-assert enforces: keep-list.
- `hooks/enforce-email-formatting.py`: RECIPE over the 10,000-char cap (hooks-a-01..05). Its safety rules (no compose-and-send, no send in the composing turn) are keep-list. The _recipe_once docstring says '~1.8KB'; it is 10.3 KB (comment only, not model-facing).
- `hooks/escalation-watch.sh`: Operator-facing counts sent as model context at nearly every SessionStart, against its own zero-output contract (hooks-a-13).
- `hooks/goal-inert-watch.sh`: systemMessage only. Clean for model cost.
- `hooks/handoff-intent-nudge.sh`: Safety rails text: keep. Over-fires and repeats within a context (hooks-a-10). It cites memory handoff-succession-legibility, which exists only in the doc-classifier project's memory (low, flag).
- `hooks/hook-chain.sh`: No model-facing prose (selftest fixtures only).
- `hooks/keychain-guard.sh`: Deny reason guarding a destructive keychain operation, with incident and fix: keep-list. Clean.
- `hooks/lib/inject-sanitize.jq`: Sanitizer, no prose.
- `hooks/lib/instruction_budget.py`: Deny message is factual and says where content should go instead. Clean.
- `hooks/lib/jev.sh`: Returns JSON to callers; nothing injected.
- `hooks/lib/lesson_recall.py`: Pointer lines labelled 'data, not instructions', capped at 1,500 chars. Clean.
- `hooks/lib/mailbox-pending.sh`: Cursor primitives; no model-facing text (rendering lives in mailbox-drain.sh, shard hooks-b).
- `hooks/lib/read-before-write-parity.sh`: Predicate library; the deny text lives in hooks/read-before-write-parity.sh (shard hooks-b).
- `hooks/lib/smart-bash-allowlist.py`: Allow reasons only (15,070 fires in 7 d, about 98 chars). Shown to the user, not the model; no hook_additional_context element carries them. Clean.
- `hooks/mail-images-auto.sh`: Short PostToolUse pointer to extracted images. Clean.

## Measured injection volume, 7 days (my shard)

| hook (event) | fires | chars | max | note |
|---|---:|---:|---:|---|
| dod-persist.sh (SessionStart) | 634 | 22.4M | 59,718 | before 2026-10-02 median 35 KB; since then 26/26 lineage injections over 10K (persisted, 2 KB preview) |
| config-mirror-assert.sh (SessionStart) | 939 | 804K | 18,419 | about 1 per session on non-default accounts; operator-only remedy |
| activation-watch.sh (SessionStart) | 877 | 748K | 1,927 | parity axis repeats the same LIVE-ONLY drift |
| escalation-watch.sh (SessionStart) | 937 | 655K | 770 | 937 fires / 728 sessions |
| handoff-intent-nudge.sh (UserPromptSubmit) | 628 | 512K | 815 | 112 of 342 contexts got it 2-15 times |
| backup-before-write.sh (PreToolUse) | 598 | 483K | 894 | PLAN GUARD; 190 fires on one plan |
| enforce-email-formatting.py (PreToolUse) | 27 | 117K | 10,441 | recipe 19/19 over cap in 14 d |
| agent-teams-enforce.sh (PreToolUse) | 191 | 71K | 499 | plus deny reasons up to about 2.9 KB (MACHINE CAPACITY in 126 transcripts / 30 d) |
| cache-expiry-warning.sh (UserPromptSubmit) | 165 | 52K | 316 | clean |

## Findings (ordered by confidence, then impact)

### hooks-a-01 · hooks/enforce-email-formatting.py:503 · prompt-cruft · confidence high · string-replace

- Pattern: 1d migration-relative phrasing + 2.2 input tokens (10,000-char hook cap)
- Why: Measured: all 19 injections of RECIPE in 14 days were 10.1-10.3 KB, over Claude Code's 10,000-char hook-output cap, so each was replaced by a <persisted-output> 2,000-char preview (rules 0/0b only); rules 1-6, including rule 5's thread-alias check the hook says it cannot enforce, never reached the model inline. This hunk is migration-relative phrasing (prompt-audit 1d / Group 2 history narrative): it describes a previous recipe version the model never saw. The five recipe hunks together take the source from 10,272 to 9,225 chars, under the cap. Hunk: rule 1b: drop 'old answer was WRONG' / 'THE CORRECTION' / 'old ~300-char cap' diff narration, keep the measured fact.
- Impact: Hunk saves 443 chars; with the other four the recipe fits under the cap, so all of rules 0-6 reach the model inline on the first mail call instead of a 2 KB preview plus a file path (19 of 19 injections truncated in 14 d). No test pins these passages (grep of tests/email-*.bats).

Evidence (old):
```
1b. WHICH FIELD — this is the one that bites, and the old answer here was WRONG.
   Graph auto-quotes the original ONLY when you pass **Comment**. Passing **Message.body
   REPLACES that auto-quote**, so the reply threads correctly but arrives with NO VISIBLE
   HISTORY — it reads to the recipient as a brand-new email (caught in Outlook, not here,
   2026-08-24). Hook-enforced: a reply tool passing Message.body with no quote block is DENIED.
   ⚠️ THE CORRECTION (measured 2026-09-14, this mailbox): Graph strips NEWLINES from a Comment.
   It does NOT strip MARKUP. A Comment of
       <div style="color:#C00000"><p>para one</p><p>para two here</p></div>
   came back in the draft's own MIME byte-identical, sitting above Graph's own
   <hr><div id="divRplyFwdMsg"> quote. So the cure for a long, formatted reply was never
   "shorten it" and never "move to Message.body" — it is **put the HTML in the Comment**.
   That is ONE API call, keeps Graph's native quote at full depth, and nothing of the
   original ever passes through you. The old ~300-char cap is gone; it was our own number,
   not Graph's (no such limit is documented anywhere on Microsoft Learn).
```
Proposed (new):
```
1b. WHICH FIELD. Graph auto-quotes the original ONLY when you pass **Comment**. Passing
   **Message.body REPLACES that auto-quote**, so the reply threads correctly but arrives with
   NO VISIBLE HISTORY — it reads to the recipient as a brand-new email. Hook-enforced: a reply
   tool passing Message.body with no quote block is DENIED. Graph strips NEWLINES from a
   Comment but keeps its MARKUP (measured 2026-09-14: a <div><p>…</p><p>…</p></div> Comment came
   back byte-identical above Graph's own quote), so for a long or formatted reply **put the HTML
   in the Comment**: one API call, Graph's native quote at full depth, and nothing of the
   original passes through you. Graph documents no length limit on Comment.
```

### hooks-a-02 · hooks/enforce-email-formatting.py:543 · prompt-cruft · confidence high · string-replace

- Pattern: 1d migration-relative phrasing + 2.2 input tokens (10,000-char hook cap)
- Why: Measured: all 19 injections of RECIPE in 14 days were 10.1-10.3 KB, over Claude Code's 10,000-char hook-output cap, so each was replaced by a <persisted-output> 2,000-char preview (rules 0/0b only); rules 1-6, including rule 5's thread-alias check the hook says it cannot enforce, never reached the model inline. This hunk is migration-relative phrasing (prompt-audit 1d / Group 2 history narrative): it describes a previous recipe version the model never saw. The five recipe hunks together take the source from 10,272 to 9,225 chars, under the cap. Hunk: rule 3a: drop 'as this recipe used to say'.
- Impact: Hunk saves 56 chars; with the other four the recipe fits under the cap, so all of rules 0-6 reach the model inline on the first mail call instead of a 2 KB preview plus a file path (19 of 19 injections truncated in 14 d). No test pins these passages (grep of tests/email-*.bats).

Evidence (old):
```
     a. create-reply-all-draft with a UNIQUE placeholder Comment — e.g. CCPLACEHOLDER7X2Q.
        ⚠️ NOT "." as this recipe used to say: a lone "." occurs in every quoted chain, so the
        splicer's own placeholder check can never pass with it.
```
Proposed (new):
```
     a. create-reply-all-draft with a UNIQUE placeholder Comment — e.g. CCPLACEHOLDER7X2Q, never
        "." (a lone "." occurs in every quoted chain, so the splicer's placeholder check fails).
```

### hooks-a-03 · hooks/enforce-email-formatting.py:565 · prompt-cruft · confidence high · string-replace

- Pattern: 1d migration-relative phrasing + 2.2 input tokens (10,000-char hook cap)
- Why: Measured: all 19 injections of RECIPE in 14 days were 10.1-10.3 KB, over Claude Code's 10,000-char hook-output cap, so each was replaced by a <persisted-output> 2,000-char preview (rules 0/0b only); rules 1-6, including rule 5's thread-alias check the hook says it cannot enforce, never reached the model inline. This hunk is migration-relative phrasing (prompt-audit 1d / Group 2 history narrative): it describes a previous recipe version the model never saw. The five recipe hunks together take the source from 10,272 to 9,225 chars, under the cap. Hunk: rule 4: drop 'The old rule here said … Both halves are dead'.
- Impact: Hunk saves 155 chars; with the other four the recipe fits under the cap, so all of rules 0-6 reach the model inline on the first mail call instead of a 2 KB preview plus a file path (19 of 19 injections truncated in 14 d). No test pins these passages (grep of tests/email-*.bats).

Evidence (old):
```
   get-mail-message-mime on THAT DRAFT'S OWN id and inspect what you get.
   ⚠️ The old rule here said "Drafts have no MIME" and told you to DRY RUN by swapping
   recipients to yourself and SENDING. Both halves are dead: the premise was false, and
   sending is denied outright (rule 0). Verifying a draft costs one read now.
```
Proposed (new):
```
   get-mail-message-mime on THAT DRAFT'S OWN id and inspect what you get. Never verify by
   sending to yourself: sending is denied (rule 0), and the draft read is enough.
```

### hooks-a-04 · hooks/enforce-email-formatting.py:585 · prompt-cruft · confidence high · string-replace

- Pattern: 1d migration-relative phrasing + 2.2 input tokens (10,000-char hook cap)
- Why: Measured: all 19 injections of RECIPE in 14 days were 10.1-10.3 KB, over Claude Code's 10,000-char hook-output cap, so each was replaced by a <persisted-output> 2,000-char preview (rules 0/0b only); rules 1-6, including rule 5's thread-alias check the hook says it cannot enforce, never reached the model inline. This hunk is migration-relative phrasing (prompt-audit 1d / Group 2 history narrative): it describes a previous recipe version the model never saw. The five recipe hunks together take the source from 10,272 to 9,225 chars, under the cap. Hunk: rule 5: drop 'This used to add … That inference is DEAD'.
- Impact: Hunk saves 253 chars; with the other four the recipe fits under the cap, so all of rules 0-6 reach the model inline on the first mail call instead of a 2 KB preview plus a file path (19 of 19 injections truncated in 14 d). No test pins these passages (grep of tests/email-*.bats).

Evidence (old):
```
   ⚠️ This used to add "Comment mode CANNOT set from, so a «P_OTHER_SHORT» thread needs
   Message.body". That inference is DEAD (measured 2026-08-25): the create call cannot set
   `from`, but update-mail-message CAN — a PATCH carrying {"from": …, "ccRecipients": […]}
   on a Comment-created draft was read back with both applied. So a «P_OTHER_SHORT» thread is no
   longer a reason to abandon the auto-quote: use the rule-3 splice and set the alias on the
   PATCH. Nothing about the alias forces you to hand-build a chain any more.
```
Proposed (new):
```
   The create call cannot set `from`, but update-mail-message CAN (measured 2026-08-25: a PATCH
   carrying {"from": …, "ccRecipients": […]} on a Comment-created draft was read back with both
   applied). So a «P_OTHER_SHORT» thread keeps the auto-quote: set the alias on that PATCH.
```

### hooks-a-05 · hooks/enforce-email-formatting.py:595 · prompt-cruft · confidence high · string-replace

- Pattern: 1d migration-relative phrasing + 2.2 input tokens (10,000-char hook cap)
- Why: Measured: all 19 injections of RECIPE in 14 days were 10.1-10.3 KB, over Claude Code's 10,000-char hook-output cap, so each was replaced by a <persisted-output> 2,000-char preview (rules 0/0b only); rules 1-6, including rule 5's thread-alias check the hook says it cannot enforce, never reached the model inline. This hunk is migration-relative phrasing (prompt-audit 1d / Group 2 history narrative): it describes a previous recipe version the model never saw. The five recipe hunks together take the source from 10,272 to 9,225 chars, under the cap. Hunk: rule 5 WHY: keep the incident reason, drop 'it used to read … The old rule'.
- Impact: Hunk saves 140 chars; with the other four the recipe fits under the cap, so all of rules 0-6 reach the model inline on the first mail call instead of a 2 KB preview plus a file path (19 of 19 injections truncated in 14 d). No test pins these passages (grep of tests/email-*.bats).

Evidence (old):
```
   WHY THIS RULE EXISTS: it used to read "set from = «P_OTHER»" flatly. Every
   vendor email on one order was addressed to «P_DEF_SHORT»; the dispatch-hold request
   went out from «P_OTHER_SHORT», an address they had never seen on that order. They
   dispatched and charged the next morning. The old rule did not merely fail to help — it
   overrode a default that was already correct.
```
Proposed (new):
```
   Why: every vendor email on one order was addressed to «P_DEF_SHORT»; a dispatch-hold request
   sent from «P_OTHER_SHORT», an address they had never seen on that order, was not matched to it,
   and they dispatched and charged the next morning.
```

### hooks-a-06 · hooks/agent-teams-enforce.sh:772 · prompt-cruft · confidence high · string-replace

- Pattern: Group 2 volatile specifics / contradicting instruction files
- Why: Unchanged since c8d8c64e3 (2026-04-17). It tells the model to call TeamCreate and pass team_name, which the agent-teams skill (SKILL.md:18-20, 49-61) and this hook's own comment (agent-teams-enforce.sh:28-30, '0 of 1,251 Agent calls carried team_name') say no longer exist on the current runtime; following it produces an inert argument or a missing tool. The repo's current rule (global CLAUDE.md, Agent Teams section) is a dispatched session by default, or named teammates with no isolation:/cwd: beside name:.
- Impact: Fires on unnamed background spawns that read as code-writing (4 transcripts/30 d); stops sending the model to a tool that does not exist. No test asserts this string (tests/agent-teams-enforce.bats greps only decisions).

Evidence (old):
```
Background subagents cannot write code. Implementation tasks require Agent Teams for visibility and coordination. To proceed: use TeamCreate first, then spawn agents with team_name parameter set (e.g., team_name='implementation-wave-1'). You ARE authorized to use Agent Teams — this constraint exists to ensure parallel work is coordinated safely. If this task is purely research/exploration with no code changes, rephrase the prompt to clarify.
```
Proposed (new):
```
Background subagents cannot write code: an unnamed background agent runs unseen and returns nothing a lead can coordinate. Send code-writing work to a dispatched session (scripts/handoff-fire.sh, the default for an implementation wave) or to a named teammate, Agent({name: ...}), given its own worktree path in the brief (passing isolation: or cwd: beside name: silently demotes the spawn to a plain subagent; the agent-teams skill has the details). You are authorized to use Agent Teams. If this task is research or exploration with no code changes, say so in the prompt.
```

### hooks-a-07 · hooks/agent-teams-enforce.sh:787 · prompt-cruft · confidence high · string-replace

- Pattern: Group 2 volatile specifics / contradicting instruction files + 1a pressure language
- Why: Same 2026-04-17 text: it prescribes 'TeamCreate + team_name + worktree isolation'. team_name and TeamCreate are gone on this runtime (agent-teams SKILL.md:49-61), and 'isolation' beside name: is exactly the call shape the skill and global CLAUDE.md say silently demotes a teammate to a plain subagent, so obeying this nudge breaks the spawn it is steering. 'ALL ... MUST' adds caps-emphasis with no reason attached.
- Impact: Fires once per session on unnamed code-writing spawns (182 hook fires / 70 transcripts in 30 d); removes advice that, followed literally, silently demotes teammates.

Evidence (old):
```
AGENT TEAMS DEFAULT: This agent spawn involves code changes but has no team_name. Per global rules, ALL implementation tasks with 2+ code-writing tasks MUST use Agent Teams (TeamCreate + team_name + worktree isolation). Only research/exploration subagents should run without team_name. You ARE authorized to use Agent Teams.
```
Proposed (new):
```
AGENT TEAMS DEFAULT: this unnamed spawn reads as code-writing. Code-writing work across 2+ files goes to a dispatched session (scripts/handoff-fire.sh, the default for an implementation wave) or to named teammates, Agent({name: ...}), each given its own worktree path in the brief; passing isolation: or cwd: beside name: silently demotes the spawn to a plain subagent. Unnamed subagents are for research and exploration. You are authorized to use Agent Teams.
```

### hooks-a-09 · hooks/backup-before-write.sh:248 · cost-lever · confidence high · needs-new-code

- Pattern: 1d instruction re-insertion on a cadence + cost-optimization 2.2 input tokens
- Why: The Edit branch re-injects the same ~870-char PLAN GUARD + PLAN UPDATE RULES on every Edit of a plan file (190 fires on TRUEMEMORY_2_0.md alone in 7 d; 57% within-context repeats per docs/research/token-efficiency-2026-09-23/measure/hooks.md §2). Current models retain a once-stated instruction; the sibling plan-agent-teams-default.sh already injects its PLAN DEFAULTS once per (session, file) via a .plandef key, and the same rules are resident in global CLAUDE.md (Plans section). Write/overwrite paths keep their per-call warning.
- Impact: Measured 7 d: 598 fires, 483K chars (~190K tokens) written into context, each then re-read on later turns; expect ~55-60% fewer PLAN GUARD injections. EXIT trap (_bbw_rewrite_only) still runs on the early exit, so the canonical-input rewrite is unaffected.
- Plan: Apply the replacement, then add a bats case to tests/ for backup-before-write: two Edit payloads with the same session_id and plan path => first emits PLAN GUARD, second emits no additionalContext; a different file or session re-emits. Point CC_PLAN_GUARD_STATE_DIR at $BATS_TEST_TMPDIR. Run the hook's existing suites and bare shellcheck. Optionally also drop clause (3) of PLAN_RULES on the Edit path, since PLAN DEFAULTS states the same Phase 0 rule on the same event.

Evidence (old):
```
if [ "$TOOL" = "Edit" ]; then
  if [ "$IS_PLAN" = true ]; then
    _bbw_out <<EOF
```
Proposed (new):
```
if [ "$TOOL" = "Edit" ]; then
  # Once per (session, plan file), as plan-agent-teams-default.sh already does for PLAN DEFAULTS:
  # the rules do not change between edits, and re-sending ~870 chars on every Edit was the bulk of
  # this hook's context (598 fires in 7 d, 190 on one plan).
  _pg_sid="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"
  if [ "$IS_PLAN" = true ] && [ -n "$_pg_sid" ]; then
    _pg_dir="${CC_PLAN_GUARD_STATE_DIR:-$HOME/.claude/state/plan-guard}"
    _pg_key="$(printf '%s|%s' "$_pg_sid" "$FILE" | shasum 2>/dev/null | cut -c1-16)"
    if [ -n "$_pg_key" ]; then
      mkdir -p "$_pg_dir" 2>/dev/null || true
      find "$_pg_dir" -type f -mtime +7 -delete 2>/dev/null || true
      [ -f "$_pg_dir/$_pg_key" ] && exit 0
      : > "$_pg_dir/$_pg_key" 2>/dev/null || true
    fi
  fi
  if [ "$IS_PLAN" = true ]; then
    _bbw_out <<EOF
```

### hooks-a-11 · hooks/dod-persist.sh:283 · cost-lever · confidence high · needs-new-code

- Pattern: cost-optimization 2.2 input tokens (large SessionStart injection past the 10,000-char cap)
- Why: Since the lineage filter shipped (2026-10-02), every lineage injection that carries captures has been over Claude Code's 10,000-char cap: 26 of 26 in 2026-10-02..04 (max 58 KB; 634 fires/7 d before the fix at median 35 KB). Claude Code replaces it with a 2,000-char preview of the head, and because history is rendered oldest-first the preview shows the frame, the contract line and then the OLDEST captures; the newest captures, the only history likely to matter, never reach the model. The 'THE CURRENT CONTRACT' line itself survives and is kept. '(a19 HOP A)' is a session-internal label with no meaning to the reader.
- Impact: Each affected session start drops from a truncated ~2.3 KB preview of stale history to ~2-5 KB of the newest captures delivered whole; wrap-ledger/completion-assert read the store, not the injection, so they are unaffected.
- Plan: Apply the replacement in _dod_inject_lineage_only, and the same cap to the non-lineage SessionStart frame (CC_DOD_LINEAGE_ONLY=0 path, which still injects $content whole). Add bats: a store with 6 lineage captures => injection contains only the newest 3, newest first, and stays under 10,000 chars; a single capture => unchanged content. Check tests/dod-persist.bats for assertions on the old 'newest last' wording and update them in the same commit.

Evidence (old):
```
  framed="Durable frozen DoD for this session — re-injected across recycle/compaction as the completeness baseline (a19 HOP A).

$_lead

Below: ${ncap} capture(s) written by this session, a session that held this pane before it, or a recorded predecessor worktree, newest last. The other $(( nall - ncap )) capture(s) this worktree would see, from its other sessions or with no provenance, are left out (CC_DOD_LINEAGE_ONLY=1).${unote} Store: ${files}

$kept"
```
Proposed (new):
```
  # Newest captures only, newest FIRST. Past Claude Code's 10,000-char hook cap the whole injection
  # is swapped for a 2,000-char preview of its head; oldest-first, that head held only the OLDEST
  # captures (26 of 26 lineage injections 2026-10-02..04 were over the cap). The store keeps all.
  _dmax="${CC_DOD_INJECT_MAX_CAPTURES:-3}"
  case "$_dmax" in ''|*[!0-9]*) _dmax=3 ;; esac
  kept_new="$(printf '%s\n' "$kept" | awk -v n="$_dmax" '
      /^## /{b++} {l[NR]=$0; k[NR]=b}
      END{for (j=b; j>b-n && j>0; j--) for (i=1;i<=NR;i++) if (k[i]==j) print l[i]}')"
  nshow="$(printf '%s\n' "$kept_new" | grep -c '^## ' 2>/dev/null || true)"
  case "$nshow" in ''|*[!0-9]*) nshow=0 ;; esac
  framed="Durable frozen DoD for this session — re-injected across recycle and compaction as the completeness baseline.

$_lead

Below: the newest ${nshow} of ${ncap} capture(s) written by this session, a session that held this pane before it, or a recorded predecessor worktree, newest first; the rest are in the store. The other $(( nall - ncap )) capture(s) this worktree would see, from its other sessions or with no provenance, are left out (CC_DOD_LINEAGE_ONLY=1).${unote} Store: ${files}

$kept_new"
```

### hooks-a-08 · hooks/agent-teams-enforce.sh:298 · prompt-cruft · confidence medium · string-replace

- Pattern: 1d migration-relative phrasing + 1c padding (strategy/quoting guidance beside a refusal)
- Why: Added by 7078dfa83 (2026-09-08) to record a measurement. At a spawn refusal the model needs the term's meaning, the remedy and the overrides; this ~700-char passage is citation guidance for reports, and 'This sentence used to quote 2.5-5 ... refuted along with 0.172, 0.566 and 1.89' is a diff against an earlier version of the sentence that puts four refuted numbers into context. The measurement stays in the cited doc and commit.
- Impact: ~600 chars off a ~2.9 KB deny reason that appeared in 126 transcripts in 30 d (often repeated per context); tests assert only the reason's prefix (tests/agent-teams-enforce.bats:280, tests/spawn-presence.bats:531).

Evidence (old):
```
The per-active-session cost is MEASURED, on this box, at 2.390 load units per ACTIVE session +/- 0.533 (1 s.e.) — window n=85, span 5202s, all three controls PASS, raw data docs/research/data/capacity-marginal-2026-09-08.tsv (docs/research/marginal-load-per-active-session-2026-08-19.md §6e). Quote it ONLY with that s.e. and window, and read it as an UPPER bound, since the active census is a proven lower bound: right for sizing a ceiling, wrong for projecting +N sessions. This sentence used to quote 2.5-5, an aggregate/N that is refuted along with 0.172, 0.566 and 1.89 — none of those four is quotable. Ceiling 8 is anchored on the 127/127 refusal band, not on any per-session figure, so the measured coefficient does not move it. 
```
Proposed (new):
```
(Per-active-session load figures, if you need to cite one: docs/research/marginal-load-per-active-session-2026-08-19.md §6e.) 
```

### hooks-a-10 · hooks/handoff-intent-nudge.sh:40 · cost-lever · confidence medium · needs-new-code

- Pattern: 1d instruction re-insertion + cost-optimization 2.2 input tokens (per-prompt injection)
- Why: UserPromptSubmit nudge (~815 chars) fires on any prompt containing 'handoff'/'self-close'/'succession'. Classified 628 fires in 7 d: 232 were long fired briefs, ~129 task-notifications, ~103 peer messages, and only ~110 short human-length prompts; 112 of 342 contexts received the identical block 2-15 times. The text is safety-relevant (sanctioned teardown rails) so it stays; the repeats add nothing a current model loses after one statement.
- Impact: Measured 7 d: 512K chars (~205K tokens) injected, each copy re-read for ~116 later responses on average (hooks.md §2). Once-per-session removes roughly a third of fires (the repeat share) with no change to first-mention behaviour.
- Plan: Apply the replacement; in the compaction path (dod-persist.sh SessionStart source=compact, or a one-line addition to an existing SessionStart hook) delete $HOME/.claude/state/handoff-intent-nudge/<sid> so a compacted context is re-armed. Add bats cases: same session_id twice => second prompt emits nothing; new session_id => emits; '/handoff' typed => never emits. Keep the assignee skip above it.

Evidence (old):
```
if printf '%s' "$PROMPT" | grep -qiE 'hand[- ]?off|self[- ]?close|\brelieve|\brelieved\b|recycle (this|the|your|our) (session|pane)|succession'; then
  cat <<'JSON'
```
Proposed (new):
```
if printf '%s' "$PROMPT" | grep -qiE 'hand[- ]?off|self[- ]?close|\brelieve|\brelieved\b|recycle (this|the|your|our) (session|pane)|succession'; then
  # Once per session: the rails text never changes. A 7-day census found 628 fires in 342 contexts,
  # 112 of them hit 2-15 times, mostly by fired briefs and task notifications that merely name
  # handoff-fire.sh. dod-persist-style SessionStart(compact) clears the marker so a compacted
  # context gets it again.
  _hi_sid="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("session_id",""))
except Exception: pass' 2>/dev/null)"
  if [ -n "$_hi_sid" ]; then
    _hi_dir="${CC_HANDOFF_NUDGE_STATE_DIR:-$HOME/.claude/state/handoff-intent-nudge}"
    mkdir -p "$_hi_dir" 2>/dev/null || true
    find "$_hi_dir" -type f -mtime +7 -delete 2>/dev/null || true
    [ -f "$_hi_dir/$_hi_sid" ] && exit 0
    : > "$_hi_dir/$_hi_sid" 2>/dev/null || true
  fi
  cat <<'JSON'
```

### hooks-a-12 · hooks/config-mirror-assert.sh:38 · cost-lever · confidence medium · operator-decision

- Pattern: cost-optimization 2.2 input tokens; always-firing operator-only alarm injected as model context
- Why: Fires at ~every SessionStart on a non-default account (939 fires / 7 d), 670-900 chars, and its only remedy is 'converge with all that account's panes closed', which a running session cannot do. 537-628 of the 542-633 forks are backups. The hook's backup test greps '\.bak' while lib/config-mirror.zsh:208 drops backups with *bak*, so settings.json.pane-autonomy-bak-* and settings.json.permharvest-bak-* are listed as non-backups. The human path in the lib already prints nothing for a backups-only fold. accounts-board.sh sets the precedent for operator-only text: top-level systemMessage, zero model tokens.
- Impact: Measured 7 d: 804K chars (~320K tokens) written into model context at session start, re-read for ~80 later responses each (hooks.md §2). Moving the FORKED line to systemMessage removes nearly all of it; the settings.json DIVERGES line can stay in additionalContext because it changes which hooks run.
- Plan: Decision for the operator (conviction 75% for option A): A) emit the FORKED line as top-level systemMessage (operator display, like accounts-board.sh) and keep only the settings-parity line as additionalContext; B) keep additionalContext but speak only when a non-backup fork exists and the non-backup set changed (fingerprint damp as activation-watch.sh queue_damp_ok). Either way, align the backup test with the lib: grep 'bak' rather than '\.bak' on lines 30 and 32 (tests/config-mirror-assert.bats fixtures use .bak- names, so they stay green); test 'only backups forked => backups fill the five names' encodes today's behaviour and changes under either option.

Evidence (old):
```
  msg="⚠ $forks FORKED real entry(ies) shadow ~/.claude in ${cfg##*/} ($nbak of them *.bak* backups): $shown$more — this account does NOT see updates to them, and safe mode cannot fix it.
```

### hooks-a-13 · hooks/escalation-watch.sh:262 · cost-lever · confidence medium · operator-decision

- Pattern: cost-optimization 2.2 input tokens; alarm that fires every session against its own stated contract
- Why: The hook's contract (escalation-watch.sh:13-15) is 'ZERO unseen records => ZERO output' because an always-speaking channel trains the reader to skip it. Measured: 937 fires in 728 sessions over 7 d, i.e. essentially every session, listing counts like announce-alarm 1341 / page 488 that no session can ack (cc-escalations ack is the operator's). The block is operator-facing data sent as model context.
- Impact: Measured 7 d: 655K chars (~260K tokens) injected at session start. Delivering it as systemMessage, or only when the per-class counts change, removes most of it while keeping the pull lane the hook exists for.
- Plan: Decision for the operator: A) emit as top-level systemMessage (operator sees it at every session start, zero model tokens); B) keep additionalContext but damp on an unchanged per-class count fingerprint, which needs a marker the header says the hook deliberately does not write; C) fix the upstream cause, the sweep not marking announce-alarm records seen, so the zero-output contract holds again. Conviction 70% for C plus A; the dead-letter class (unread mail) could stay in additionalContext since a session may act on it.

Evidence (old):
```
    body='ESCALATIONS (unseen dead-letter records):'
```

### hooks-a-14 · hooks/activation-watch.sh:393 · cost-lever · confidence medium · needs-new-code

- Pattern: cost-optimization 2.2 input tokens; undamped repeating SessionStart finding
- Why: Only the queue axis is damped (queue_damp_ok, fingerprint + 24 h window). The parity axis repeats the same LIVE-ONLY finding for 44-jev-batch-activate.sh with a 300-char cp command at every session start (347 of the sampled fires in 3 d carried the identical ~830-char block). The remedy is an operator repo write, unrelated to almost every session that receives it.
- Impact: Measured 7 d: 877 fires, 748K chars (~300K tokens). Damping axis 2 with the same fingerprint scheme cuts it to one page per change or per 24 h.
- Plan: Reuse queue_damp_ok with a second damp file (e.g. $DIR/.parity-page.damp) keyed on the sorted drift list; when suppressed, emit one counted line ('ACTIVATION SSOT PARITY: N drift(s), unchanged; full list: bash activation-watch.sh --parity'). Add a selftest/bats case mirroring the queue-axis damping test.

Evidence (old):
```
parity_axis() { # → the live-vs-repo SSOT finding (axis 2), empty when the two copies agree
```

## Flag-only / low confidence (no edit proposed)

- handoff-intent-nudge.sh:42 cites '(memory: handoff-succession-legibility)'. That file exists only under ~/.claude/projects/-Users-chrisren-Development-doc-classifier/memory/, so sessions in other projects cannot follow the pointer. Either name a repo path or drop the citation.
- check-edit-boundary.sh:113 and agent-teams-enforce.sh:187: the clause 'self-close exits 2, ORIGIN session, not a fired peer, and such a session STAYS UP' quotes handoff-fire.sh's refusal text inline and reads as garbled. Quoting it explicitly would be clearer. Deliberate (3a2d81bcd); low value.
- enforce-email-formatting.py:672 docstring says the recipe is '~1.8KB'; it is 10.3 KB. This is a comment, not model-facing, but it is the reason nobody noticed the cap. After hooks-a-01..05 the recipe is 9,225 chars, plus up to about 670 chars of alias advisory on the same call, which is still tight. Add a test that asserts len(RECIPE) <= 9,300.
- Cross-shard: skills/agent-teams/SKILL.md:98 (Decision Rule table) and :268 still say 'TeamCreate + worktrees'. This is the same stale API as hooks-a-06/07, outside this shard.
- activation-watch.sh / dod-persist.sh use session-internal labels in model-facing text ('D-v axis 2', 'a19 HOP A', 'C10'). The reader cannot resolve them. Low. hooks-a-11 drops the dod one.

## Verification done

- Every old_text is an exact, unique substring (checked by /tmp/capi-audit/hooks_a_build.py).
- Every string-replace and needs-new-code edit was applied to scratch copies (/tmp/capi-audit/scratch.*). All pass `bash -n` and bare `shellcheck` (rc 0), and the email hook passes py_compile. The dod newest-first awk was run on a sample store.
- No test pins the replaced text: grep of tests/ for the recipe passages, the TeamCreate strings and the capacity coefficient found nothing. tests/agent-teams-enforce.bats:280 asserts only the MACHINE CAPACITY prefix, which is kept.
