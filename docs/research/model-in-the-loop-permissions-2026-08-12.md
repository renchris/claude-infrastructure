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

---

# MEASURED 2026-08-12 (second session) — the gating experiment, and the build

§OPEN above is preserved as written. Every one of its five items is answered below; item 1's answer
changed the shape of items 3 and 4, so read this section as amending §OPEN rather than replacing it.

## 1. Hook timeout — the experiment that gated everything

Nine arms, CC **2.1.220**, each an isolated headless session. Isolation was NOT a fresh
`CLAUDE_CONFIG_DIR` — auth is keyed per config dir via the Keychain item
`Claude Code-credentials-<sha256(dir)[:8]>`, so a brand-new dir is unauthenticated and every run
returns `Not logged in`. Instead each arm ran `--setting-sources ''` (loads no user/project/local
settings) plus `--settings <scratchpad file>`, with cwd in a plain non-repo directory. Confirmed by
control: every arm's `init` event lists **46 slash commands** (builtins only) against the operator's
~200, and arm A — no hook — is blocked, which it would not be if the operator's allowlists had
loaded. **Nothing was written to the five live config dirs.**

| arm | hook | `timeout` | tool ran? | hook reached END? | wall |
|---|---|---|---|---|---|
| A | none | — | no | — | 7.5s |
| C | `allow` immediately | 5 | **yes** | yes | 4.7s |
| D | `deny` immediately | 5 | no | yes | 5.6s |
| E | `ask` immediately | 5 | no | yes | 4.8s |
| **B** | `allow` after 20s | **5** | **no** | **NO — killed** | 10.8s |
| **F** | `deny` after 20s | **5** | **no** | **NO — killed** | 11.6s |
| G | `allow` after 3s | 5 | **yes** | yes | 7.9s |
| H | `allow` after 20s | **60** | **yes** | yes | 24.1s |
| I | `allow` after 90s | **180** | **yes** | yes | 94.5s |
| K | none, `defaultMode:auto` | — | no | — | 8.9s |
| J | `ask` immediately, **auto** | 5 | no | yes | 4.9s |
| L | `allow` after 20s, **auto** | 5 | no | NO — killed | 10.0s |

**Verdict: a PreToolUse hook that overruns its `timeout` has its verdict DISCARDED, and the harness
falls through to the normal permission flow — byte-identical to the hook not being configured.**
Not fail-open (B's tool did not run), not fail-closed-deny (F's `deny` never landed either; B and F
produce the same output as A). The hook child is **killed** at the deadline: no `END` stamp is ever
written, and no orphan `sleep` survives — so a decider that overruns cannot accumulate processes.

Three findings that were not in §OPEN and that change the design:

- **The timeout is SILENT.** Nothing on stderr, nothing in the transcript, no notice to the model.
  A decider that quietly stops working is indistinguishable from one that is not installed.
- **`timeout` is per-hook with no ceiling reached at 180s.** 60s and 180s were both honoured, with
  the harness blocking for the hook's full 24.1s / 94.5s. **The `timeout: 5` that §OPEN treated as
  the blocker is `smart-bash-allowlist.sh`'s own value, not a harness limit.** A model call fits.
- **A hook `allow` is more dangerous than 732147576 states.** In arm C the `allow` sailed past the
  *allowed-working-directory write guard* — a hard rule, not an `ask` entry — which A, B, D, E, K
  and L all hit. `allow` does not merely revoke `permissions.ask`; it bypasses the permission
  system entirely.

### This inverts §OPEN item 4

§OPEN required the fail direction to be `ask`, reasoning that `deny` would wedge the session. That
is right, but **doing nothing on timeout does not achieve it.** Fall-through goes to *the normal
flow*, and the operator's `defaultMode` is `auto` — so a timeout degrades to **auto-mode's
classifier, not to the human**. Reaching the human requires *emitting* `ask` before the deadline.
Hence the decider carries an internal deadline (38s) strictly below its hook timeout (60s).

Arm J is the fact that makes escalation real at all: **a hook's `ask` DOES reach the human under
`defaultMode: auto`** — the auto classifier does not override it.

## 2. The addressable set, measured — the delta over auto-mode

The beacon archive is not hypothetical volume: it is prompts that actually blocked the agent *under
`defaultMode: auto`*, i.e. by construction the population auto-mode's classifier failed to resolve.
Replayed all 1,075 Bash prompts through the live `smart-bash-allowlist.sh` and the live ask/deny
lists (`scratchpad/mitl-probe/corpus.py`):

| bucket | n | share |
|---|---|---|
| already auto-allowed by the wired static hook | 38 | 3.5% |
| **fenced** — touches `permissions.ask`; the decider may never approve these | 194 | 18.0% |
| **addressable** — the decider's actual opportunity | **843** | **78.4%** |

Fence hits: `git push` 121 · `git reset --hard` 55 · `git restore` 16 · `git stash drop` 2.

**Agent wall-time lost waiting on these prompts: 578.9 hours** — median 48s, p90 1,907s (32 min),
max 72,957s (20 h). That is the delta the decider is spending model tokens to buy back, and it is
the number that justifies the build; the static allowlist reaches 3.5% of it.

## 3. Cost and volume, bounded

Measured live latency of one decision, real model call, `claude-haiku-4-5`, packet = command + cwd +
git branch/status + last 30 transcript turns: **6.8s / 8.2s / 12.9s** across three cases. Three
cheap exits keep most calls off the model entirely, verified live: a command covered by the
operator's 339-entry `allow` list returns in **0.1s with no model call**, and a fenced command
returns in **0.1s** — the fence runs *before* the model, so a gated command never costs a token.

Bound: `MITL_PER_SESSION_MAX=40`, `MITL_PER_DAY_MAX=400`, counters on disk. **Fail direction on
exhaustion is `ask`**, pinned by test.

## 4. Recursion containment

Two independent fences, because one of them depends on a CLI flag whose semantics could change:

1. the child runs `--setting-sources ''`, **measured** in the experiment above to load no
   user/project/local settings and therefore no PreToolUse hooks at all; and
2. the child's environment carries `CC_MITL_DECIDER=1`, which the decider checks as its very first
   action, before parsing stdin.

Both are pinned by test (M10, M11), and the child is given no tools it could act with.

## 5. The fence — what it may never auto-approve

`hooks/model-permission-decider.py`. Properties, each mutant-verified:

- **Read live, never hardcoded.** `permissions.ask` *and* `permissions.deny` are re-read from
  `~/.claude/settings.json` on every invocation, so an operator adding a rule arms the decider
  against it with no code change (test 7 adds a rule mid-test and watches the verdict flip).
- **Applied to decomposed segments, not the raw string.** The measured top blockers are compound
  commands whose head is `cd`/`export`/`set`, so `cd /tmp && … && git push origin x` must fence on
  segment three (test 2). Leading `VAR=val`, `env`, `timeout`, `nohup` wrappers are stripped first
  (test 3).
- **Indirection is fenced, not resolved.** `$(…)`, backticks, `eval`, `exec`, `sh -c`, `xargs`,
  `| sh`, `base64 -d`. The splitter cannot see through these, so claiming to have checked them
  would be a lie. This is the direct lesson of rule 4's death: that rule enumerated branch-name
  *spellings*; this one fences a *class* it declines to interpret.
- **Matching is never narrower than the permission system's own.** Gate patterns are matched as
  prefixes, so `Bash(rm -rf /)` — an exact rule for Claude Code — fences every absolute-path
  recursive delete here. Deliberately wider, in the escalate direction; a narrower match than the
  rule it mirrors would open a gap. Observed live: `rm -rf <abs path>` escalated at 0.1s.
- **The fence runs TWICE** — before the model, and again on the model's `ALLOW` before emitting.
  The model can only ever narrow. Mutant M1 removes the *first* pass and the fence tests still
  return `ask`, which is what proves the second pass holds on its own.
- **`deny` is structurally unreachable.** `emit()` refuses any verb but `allow`/`ask` and downgrades
  to `ask`; a test sweeps every exercised path for `"deny"`.
- **A crash escalates.** An unhandled exception writes nothing, and a hook that writes nothing is
  treated exactly like one that timed out — verdict discarded, gate silently withdrawn. `guarded_main()`
  emits `ask` instead. This was not theoretical: a two-vs-three-value unpack mismatch turned every
  model-consulted path into a silent no-op mid-build, and the suite reported it as `NONE`.

Two defects the suite caught in its own subject, recorded because both were failures of the
*safe-direction* instinct rather than of logic: the unreadable-settings branch originally returned a
sentinel *pattern* (`"\0UNREADABLE"`) that could never match any segment, so an unreadable fence
source approved everything; and mutant M4's first form left an `\S*` alternative alive in the regex
it was meant to disable, so it applied cleanly and killed nothing — a mutant that cannot fail is
worth exactly as much as an assertion that cannot fail.

## 6. Status — SHADOW by default, not wired

`MITL_MODE` defaults to **`shadow`**: the decider runs the full path and logs what it *would* have
decided to `~/.claude/autonomy/mitl-decider/decisions-YYYY-MM.jsonl`, and emits nothing. Arming it
means `MITL_MODE=enforce` plus wiring the hook at `timeout: 60`.

**It is deliberately not wired.** Arming an auto-approver whose `allow` bypasses the permission
system is the operator's call, and it should be made against shadow evidence from this machine
rather than against this document. The honest sequence is: wire in shadow → let it accumulate a few
hundred decisions → audit the log for any `allow` the operator would not have given → only then
enforce. Per `migrations/README.md`, that wiring belongs in a `c10` migration, not in a hand edit.
