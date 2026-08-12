# Model-in-the-loop permission decisions — feasibility settled, engineering open

**Question (operator, 2026-08-12):** when a permission prompt blocks the agent in the UI, can it be
routed to a model — with session context and repo context — that either approves it or passes it on
to the human?

**Answer: yes, and it needs no capability that does not already exist.** What follows is what was
MEASURED on 2026-08-12, then the questions that are genuinely open. The split matters: the feasibility
half is settled and should not be re-investigated; the engineering half is unmeasured and must not be
assumed from this document.

## MEASURED — the interception point already exists and already has the context

A `PreToolUse` hook receives a JSON payload on stdin carrying, at minimum:

| field | what it gives the decider |
|---|---|
| `.tool_input` | the exact call being judged (`.tool_input.command` for Bash) |
| `.cwd` | **repo context** — which checkout/worktree this is |
| `.transcript_path` | **session context** — the entire conversation, on disk, readable |
| `.session_id` | identity, for per-session budgets/caps |

Established by reading the hooks that already consume these fields (`cc-permission-beacon.sh`,
`validate-bash.sh`, `smart-bash-allowlist.sh`) and by the eight hooks that already read
`transcript_path`: `agent-teams-enforce`, `completion-assert`, `anti-deference-nudge`,
`dispatch-assert`, `goal-inert-watch`, `plan-agent-teams-default`, `mailbox-drain`,
`session-index-end`.

The return contract has exactly the three verbs the question asks for:

```json
{"hookSpecificOutput":{"hookEventName":"PreToolUse",
 "permissionDecision":"allow|deny|ask","permissionDecisionReason":"…"}}
```

`allow` = approve silently · `deny` = refuse · **`ask` = hand it to the human**. So "decide, or escalate
to the operator" is the native shape of the interface, not something to be built around it.

`hooks/smart-bash-allowlist.sh` (wired to all 5 config dirs on 2026-08-12, activation 39) is a working
instance of this: it reads the command, decides, and emits `allow`. It differs from the thing the
operator asked for in ONE respect — its decision function is `grep`, not a model.

## MEASURED — a classifier is ALREADY in this position

`permissions.defaultMode` is `auto` in all five config dirs. Auto mode runs an LLM classifier over
calls that match no static rule. So the operator is not choosing between "rules" and "a model"; a model
is already deciding, and the real question is **whether replacing it with a session-aware,
repo-aware, operator-controlled decider is better.** Any proposal must state its delta over the
classifier that is already running, or it is proposing a rewrite of something invisible to it.

The beacon archive (`~/.claude/autonomy/permission-archive`, 1,124 resolved prompts since 2026-07-31)
is the evidence base for what that classifier actually stops on: the top blockers are COMPOUND commands
whose head is `cd` / `export PATH` / `set -e`. That is also why an allowlist PATTERN cannot help —
a pattern matches the whole command string — and why the hook seam is the only lever that reaches them.

## OPEN — none of this is measured; do not assume it from this file

1. **Latency, and the timeout that currently forbids it.** The wired hook has `timeout: 5`. A headless
   model call will exceed 5s routinely. Unknown: what the harness does on hook timeout — fail-open
   (proceed), fail-closed (deny), or fall through to the normal prompt. **Measure this before anything
   else**; it decides whether the design is even safe, and it is one experiment.
2. **Recursion.** The decider would itself be an agent making tool calls, whose calls fire `PreToolUse`.
   Needs either a sentinel env var the child sets and the hook checks first, or a headless invocation
   with hooks disabled. Unbounded recursion here is a fork bomb with a model on the inside.
3. **Cost and volume.** ~75,800 Bash invocations across 1,660 transcripts in the corpus. Even at a
   small fraction reaching the decider, per-call model spend needs a bound, and the bound needs a
   fail-direction when exhausted.
4. **Fail direction.** On decider error/timeout/budget-exhaustion the answer must be `ask`, never
   `allow` — the guard must degrade to the human, not to silence. This inverts the usual fail-closed
   instinct: `deny` would wedge the session, `ask` is the correct degraded state.
5. **What it may never auto-approve.** The operator's `permissions.ask` list (`fly deploy`,
   `git push`, `git reset --hard`, `git restore`, `git stash clear|drop`) must remain unreachable by
   the decider. A hook emitting `allow` BYPASSES the permission system, so a model-in-the-loop that
   is not explicitly fenced would silently revoke every `ask` rule — the exact defect that forced
   rules 2 and 4 out of `smart-bash-allowlist.sh` in 732147576.

## Why this was written instead of built

Feasibility took three cheap reads; the build is a measurement problem (item 1 gates everything).
Splitting them here means a fresh context can start on the experiment rather than re-deriving the
interface. **The one thing to run first is the timeout behaviour**, because a design that assumes
fail-open when the harness fails-closed is not a slow design, it is a broken one.
