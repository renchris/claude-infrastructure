# W7c step 0 — what the exit dialog counts at a self-recycle (2.1.284, agent view off)

Measured 2026-09-30 by pane 48 (session 28d7958b) with throwaway haiku sessions under a PTY
(`probe.py`, `probe2.py` in this directory; pyte venv at `.v`). Hooks disabled unless noted,
`CLAUDE_CODE_DISABLE_AGENT_VIEW=1`, binary `~/.claude-284/node_modules/.bin/claude`. No digit was
ever sent; every dialog was answered with Esc.

| arm | state when `/exit` is typed | dialog | exited |
|---|---|---|---|
| control | idle, no tool ever run | no | yes |
| early (p2-early.txt) | foreground Bash `sh -c 'touch M1; sleep 12; touch M2'`, 0.3 s after M1 | no | yes |
| late (p2-late.txt) | same call, 4 s after M1 (still running) | **yes** — `shell · sh -c 'touch …late.m1; sleep 12; to…'`, `1. Exit and stop tasks · 2. Stay` | no |
| late, continued | call RETURNED (M2 exists) + 4 s | dialog STILL UP, still listing the finished call (snapshot) | no |
| late, cure | Esc → composer reads `''` → `/exit` again | **no** | **yes** |
| after (p2-after.txt) | call returned 5 s before `/exit` | no | yes |
| latebg (p2-latebg.txt) | run_in_background `sleep 600` from an earlier turn + the same late fg call | yes, lists BOTH | no |
| latebg, cure | Esc → `/exit` again after the fg call returned | **yes again, lists only `shell · sleep 600`** | no (hold is correct) |
| bg (out-bg.txt) | run_in_background `sleep 600`, idle | yes, `shell · sleep 600` | no |
| Stop asyncRewake hook (out-*-stophook.txt) | a Stop hook `asyncRewake:true` running `sleep 600` (it ran: stophook-ran.*) | NOT listed | — |

## Conclusions

1. The subject is the recycle's OWN foreground Bash tool call, once it has been running more than a
   second or two (0.3 s in: not counted; 4 s in: counted). handoff-fire's foreground types `/exit` ~10 s
   into its call, so the call is always counted. That is why W5b2's TaskStop found nothing: a foreground
   call is not a TaskStop task.
2. The dialog is a SNAPSHOT. It stays up after the listed call has returned, so waiting cannot clear it.
   Only a new `/exit` re-evaluates it.
3. The cure is Esc (Stay), wait until the invoking call has returned, then type `/exit` again. With no
   other work the session exits. With real background work the dialog comes back listing only that
   work, and the existing Stay/hold stays correct. Stop-tasks is never chosen.
4. The asyncRewake inbox watcher (mailbox-wake-arm) is not what the dialog counts.
5. W5b2's own read at 22:55:25 showed a `shell ·` line, and its transcript has no run_in_background
   task live at 22:52:47–22:53:14 (TaskStop on all three bg ids: "No task found").
