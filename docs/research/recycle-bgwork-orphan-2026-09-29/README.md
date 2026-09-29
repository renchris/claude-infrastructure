# Recycle background-work orphan — the remedy, measured on 2.1.284

The defect note is `~/.reso/limit-recover/design-v2/recycle-bgwork-orphan-2026-09-29.md`: a
`--recycle` whose `/exit` raises the background-work dialog answers "Move to background and exit",
and on 2.1.284 the backgrounded copy keeps its `/goal` and keeps taking goal-driven turns (session
43ef47fc, pane 1308: ~4 min after the 19:52:09Z recycle). That production run is the positive
control; it is not re-run here, because a looping background copy has no sanctioned stop verb.

## Why not answer "Exit and stop tasks" (candidate A)

The 2.1.284 menu offers exactly three rows: `Exit and stop tasks`, `Move to background and exit`,
`Stay`. The only exit that keeps the tasks is the one that keeps the goal. "Exit and stop tasks" kills
the in-flight work a recycle is usually running (a land), which recovery never chooses (operator
decision 2, `scripts/handoff-fire.sh` pane_bgwork_seen). So the remedy is to leave the backgrounded
copy with nothing to drive: clear the goal first.

## The instrument

    python3 -m venv /tmp/pyte-venv && /tmp/pyte-venv/bin/pip install pyte
    /tmp/pyte-venv/bin/python goal-clear-probe.py <claude-binary> "$HOME/.claude-tertiary" <trusted-cwd> clear haiku 90

It spawns a real Claude Code under a PTY, starts a `run_in_background` shell, arms an unmeetable
`/goal`, then drives the watcher's exact sequence: `/exit` → dialog → Esc → `/goal clear` → `/exit`
→ dialog → the keep-work index read off the menu.

Two traps it now avoids, both of which produced false negatives first: the prompt contains the word
`STARTED`, so the wait must match the assistant's `⏺` line; and a goal armed before the background
shell starts makes our own `validate-bash.sh` refuse the shell, so the order is shell, then goal.

## Measured 2026-09-29, 2.1.284, arm `clear` (Haiku)

| step | observed |
|---|---|
| first `/exit` | dialog, `shell · sleep 150`, keep-work at index 2 |
| Esc | dialog gone, composer shows the `/exit` residue |
| `/goal clear` | `Goal cleared: <condition>`; transcript gains `goal_status {met:true, sentinel:true}` at 21:19:07Z in the ORIGINAL sid (5ee7a9c6) |
| second `/exit` | the same dialog again |
| `2` | the process exits |
| after | the conversation is RELOCATED to a new sid (59aeaf2b, "Background sleep task") carrying the same goal records, cleared one last. It took ONE turn, at 21:21:07Z, answering the `sleep 150` completion `<task-notification>`, and then stopped; no Stop-hook goal re-prompt followed |

Consequences for the code:

1. The clear is verifiable from disk: `goal_live_for_sid <original sid>` reads the sentinel
   `met:true` as terminal, so the watcher can poll it rather than trust the screen.
2. The backgrounded copy has a NEW session id, so `prev_sid` (the original) is the only join key a
   ledger row can carry; the relocated id is not knowable at answer time.
3. A background copy still wakes for its own task notifications. That residue is bounded by its
   tasks, not by a goal, and is the price of keeping the land alive.
