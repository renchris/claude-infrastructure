# A background job can recycle itself (2026-10-03)

Claude Code 2.1.284, accounts next3/next4. Raw notes: `NOTES-in-progress.md`. Live evidence: `probe-transcript.txt`.

## The incident

Job `032aa97f` (next4, cwd `wt-cc-142226-72029`) was a Claude Code background job: parent `claude bg-spare`,
no `ITERM_SESSION_ID`/`KITTY_WINDOW_ID`, no tty, `CLAUDE_JOB_DIR` set, operator chatting through Remote Control.
`hooks/boundary-handoff.sh` told it "TRANSCRIPT is 38MB … Run the /handoff rails now". `handoff-fire.sh --recycle`
refused (`needs $ITERM_SESSION_ID, $KITTY_WINDOW_ID … or --session-id`), self-close needed a pane too, and the agent
could only ask the operator to `/clear` and paste.

## 1. Succession primitives a job has (measured)

| Primitive | Result |
|---|---|
| Tool env of a job | `CLAUDE_JOB_DIR=<cfg>/jobs/<short>`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_EXECPATH` (the binary), `CLAUDE_CODE_BRIDGE_SESSION_ID`. **No `CLAUDE_CODE_SESSION_KIND`**: the repo's `SESSION_KIND=bg` checks never fire from a tool call. |
| `jobs/<short>/state.json` | `cwd`, `name`, `respawnFlags` (model, effort, permission mode, settings, allowed tools), `sessionId`, `resumeSessionId`, `bridgeSessionId`. |
| `claude --bg <prompt>` from inside a job | Starts a new job and prints `backgrounded · <short>`. The job env has `FORCE_COLOR=3`, so the id arrives wrapped in SGR codes. |
| `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` (set in some pane envs) | Makes `--bg` refuse and `agents --json` print nothing; unset it for these CLI calls. |
| `claude stop <short>` | Ends the job and keeps its conversation. Proof is `claude agents --json --all`: the row's `pid` goes null. `state` reads `stopped`, or stays `done` for a job that had already finished its turn. |
| `/goal` typed through `claude attach <short>` in a private tmux server | Arms the goal: a `goal_status` record lands in that job's transcript. Killing the tmux server only detaches. The composer renders `❯` + NO-BREAK SPACE. Typing before the job has taken its first prompt mis-reads. |
| In-session `/stop`; agents-view reply (`job_reply`, daemon socket) | No CLI; not used. |
| Native successor link | None. Fleet-view `followId` is UI focus only. |

**Does the operator's view follow a successor? No.** A `claude attach` viewer of a stopped job prints
"Session <short> has exited … Resume with: claude --resume …" and exits. Each job has its own Remote Control
bridge session, so a phone view stays on the predecessor too. The rail prints where to continue
(`claude attach <new>`, the agents view, or the Remote Control list under the same name). That is the same as a
pane recycle seen from Remote Control, whose relaunch is a new process with a new bridge.

## 2. The rail

When `handoff-fire.sh --recycle` runs inside a job (`CLAUDE_JOB_DIR` with `state.json`, checked before any pane
address), it does the following:

1. Starts `claude --bg` with the job's own respawn flags (minus `--reply-on-resume`, `--name` and resume flags; `--model`/`--effort` override), in the job's cwd and on the account the job lives on, with the brief as its prompt.
2. Confirms the successor through its `state.json`.
3. Re-arms the goal (explicit `--goal` or inherited) through attach, after the successor's first user record, and proves it by the `goal_status` record.
4. Stops this job from a detached process after a grace period (default 15 s), proving the stop through the roster.

A successor that cannot be confirmed stops nothing. `self-close --terminal|--successor <short>` stops the job the
same way, after the dirty-tree refusal. Kill switch: `HF_BGJOB=off`. The live probe ran it end to end:
`probe-transcript.txt`.

## 3. Hooks name the step that works

`hooks/lib/session-kind.sh` (`cc_bgjob_short`, `cc_bgjob_succession_step`) is used by `boundary-handoff.sh` (all
three arms plus the in-flight-exchange line) and by `handoff-intent-nudge.sh`. A job is told the job recycle
and never the `/handoff` rails or a pane uuid. Pane wording is unchanged. `waiting-recycle.sh` (the desk) fires
`--recycle`, which now works for a job.

## 4. Why the earlier `--recycle` left the conversation alive as a job

`handoffs.jsonl` 2026-10-04T02:30:34Z `recycle-bgwork-answered`: the self-recycle's `/exit` raised Claude Code's
background-work dialog, because a `pnpm review:bottles --port=3334` background task started at 02:15:49 was still
running. The watcher answered `2` (Move to background and exit), which forks the whole conversation into a new
background job with its own Remote Control bridge (032aa97f). The pane relaunch then failed (`STALE:boot`), so the
operator's phone kept talking to the fork, which fired ten draws without sign-off. The same night, this session's
own `cc-lr switch` reproduced it: fork `56c02192`, triggered by the switch's own in-flight call.

Two gaps let it through:

- **(a)** The self-recycle path never censused its own background tasks. `hf_bg_work_gate` runs only at rest, and a self-recycle is mid-turn.
- **(b)** The own-call retry (W7c) ran only for the menu without a keep-work option, so with agent view on, a self-recycle took "Move to background".

Fixes:

- **(a)** A foreground census before anything is typed, excluding the recycle's own tool call (`HF_BG_EXCLUDE_PID`). Real work refuses with each task named, and a land is named as one to wait for. A lone inbox watcher is stood down with `cc-await-ping --stand-down`. Kill switch: `CC_RECYCLE_SELF_BGWORK_CENSUS=off`.
- **(b)** The retry now runs for both menu shapes, and a self-recycle never sends the keep-work answer; a dialog that comes back is Stay plus HELD. Kill switch: `CC_RECYCLE_SELF_FORK=allow`.

Recycles of another pane (desk, reconciler) are unchanged.

C5 (`docs/research/session-durability-2026-10/C5-cc-native-bg-sessions.md` §E2) had already measured this class:
18 slash-source forks, judged a hazard.

## Residuals

- The pane relaunch's `STALE:boot` (no claude in 181 s on pane 168) still has no recorded cause; it is the watcher's existing alarm class.
- A job recycles on its own account only (`--account` is refused); switching a job's account is not built.
