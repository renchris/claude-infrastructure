# Stranded husk + held draft: why /limit-recover handed the operator a Ctrl-U (2026-10-10)

Scope (frozen): make a limit-recovered session whose in-place restart failed reach a live successor
with zero human steps and zero operator asks — including when the source pane's prompt box holds a
real draft — and prove it on pane 168 (session 186452ed, next2 → next4).

Operator ruling, 2026-10-10, verbatim: "you have to have the proactive behavior (perhaps that's in
CLAUDE.md/agent lifecycle hooks such as the stop hook) and the ability (perhaps allowlist) for you to
do this yourself with zero human in the loop and zero asking the human as a pause idle step."
This REPLACES the standing practice "a real draft is theirs, and so is the refusal"
(~/.claude/commands/limit-recover.md § Text in the prompt box; handoff-fire.sh:17231 "clearing it is
not ours to do"). A draft is preserved, never discarded — but preserving it is the rail's job, not a
reason to stop.

## The incident, from disk (all times UTC)

| time | event | evidence |
|---|---|---|
| 04:05:55 | pane 168 (pid 28699, next2) hits the weekly limit | quaternary + secondary .jsonl tail |
| 04:14–04:18 | lr-fleet --one: transplant to next4, lock + tombstone written | `~/.reso/limit-recover/fleet/one-20261010T041420Z-186452ed/`, `locks/186452ed….lock`, `.HANDOFF.json` ts 04:18:07 |
| 04:19:57 | recycle types `/exit` into pane 168 | secondary new 15-line .jsonl records `/exit` |
| 04:20:34 | `/exit` raised the background-work dialog; recycle answered index 2, **"Move to background and exit"** (`CC_RECYCLE_BGWORK_ANSWER` default `on`) | `~/.claude/logs/handoffs.jsonl` class `recycle-bgwork-answered` |
| 04:20–04:36 | the process never exited; nudges held; `recycle-dead` "never reached a confirmed shell in 600s" | handoffs.jsonl; `~/.claude/autonomy/recycle-failed/186452ed….never-confirmed` |
| 04:31:42 | reset poller RETIRES the record: "transplanted — the source transcript is tombstoned" — without checking that any successor is alive | `~/.reso/limit-recover/results/186452ed….json`; `lr-reset-poller.sh:1051`, `lr_recon/census.py:541` |
| 04:45 | (this session) lr-fleet --one re-drive: `lf_transplanted_live` counts ANY live holder (`lr_holder_count`), account-blind, so the retired next2 husk reads as "live on next4"; it NUDGES the husk, whose handed-off-session-guard blocks the prompt → UNPROVEN | `lr-fleet.sh:1077-1081`, `:1220`; run `one-20261010T044520Z-186452ed` |
| 04:5x | `cc-lr recover 168` → REFUSED class SESSION (source store's post-/exit transcript has non-error records) | — |
| 04:5x | `cc-lr move/rotate` → `hold:retired-source`, "repair first: cc-lr repair-markers" | `lr-upgrade.sh:952-962,994` |
| 04:5x | `cc-lr repair-markers --dry-run` → KEEP, "0 stale" (correct: the marker is not stale) | — |
| 04:5x | `lr-handoff.sh --source-pane 168 --target next4` → PRECHECK REFUSED:not-limited (limit gate reads the SOURCE store's new transcript, not the transplanted copy), points to `cc-lr move` → loop | precheck output |
| 05:0x | `handoff-fire.sh --recycle --transplanted-source --husk` (the one path that accepts this state) → REFUSED after 180 s: composer holds `[Image#5]`, "not this rail's own residue … clearing it is not ours to do" | handoff-fire.sh:17229-17231 |

State now: next4 holds the full conversation (2,902,688 bytes, identical to
`.jsonl.handed-off`); no process runs it there; pane 168 is a live husk on next2 whose every prompt is
blocked. Data loss: none. Live successor: none.

## Root causes (five, independent)

1. **Wrong background-work answer on a transplant recycle.** "Move to background and exit" hands the
   conversation to a background worker on the SOURCE account beside the transplant; the TUI did not
   exit. The team path already cancels (`CC_RECYCLE_BGWORK_ANSWER=cancel`); the transplant path does
   not. Research: what the right answer is for `--transplanted-source` (cancel + retry? "Exit and stop
   tasks" when the source is limited and its tasks are dead anyway?), and why the process did not exit.
2. **No owner for "transplanted, successor never started, source alive" (the stranded husk).** The
   poller retires on tombstone presence alone; recycle-dead writes a `never-confirmed` packet nobody
   drains; `fleet --retire-husks` assumes a successor exists. Each actor's predicate is true and the
   union strands the session. (Compare memory `succession-detector-fires-during-the-succession`.)
3. **Four entry points, four disagreeing gates — a refusal loop.** rotate/move → hold:retired-source →
   repair-markers (KEEP) ; lr-handoff/probe limit gate reads the source store, not the transplanted
   copy ; lr-fleet holder check is account-blind and nudges the husk ; cc-lr recover classifies SESSION.
   Every refusal names another verb; none names the one that works (`--husk` recycle).
4. **The composer gate holds a real draft and hands it to the human.** `composer-intent.sh` (2026-09-27)
   clears junk only; any real draft refuses. But a DRAFT CARRY already exists in the switch drainer
   (`lr-upgrade.sh:1094,1209-1223`, `LRU_SWITCH_CARRY_DRAFT`: save text → clear → move → retype UNSENT
   into the successor; restore in place on failure). The recycle path never got it. In a retired-source
   pane the draft is undeliverable where it sits (the guard blocks every submit), so carrying it is
   strictly better for the operator than holding it. Open: an IMAGE chip (`[Image#5]`) — carrying the
   text loses the image; find where Claude Code keeps pasted images (per-session image cache?) and how
   to re-attach in the successor, or save the image to disk and name it.
5. **Doctrine + no hook made the agent ask.** limit-recover.md says "a real draft is theirs, and so is
   the refusal"; handoff-fire prints "Clear/send the draft, then re-run". The agent relayed that as
   "clear it with Ctrl-U and tell me". `anti-deference-nudge.sh` does not catch "clear/press X in pane
   N and tell me" asks. Fix the doctrine (operator ruling above), the refusal text, and add the
   phrasing class to the Stop hook so the ask cannot recur. If any step needs a permission the agent
   lacks (allowlist), ask for that permission in chat as its own request — never hand back the step.

## Acceptance

- Pane 168 is recovered by the rail itself: same pane, same uuid, on next4, a live `--resume` process
  proven, its `[Image#5]` draft carried (or saved with its path named) — no operator keystroke.
- A regression test per root cause (bats / pytest per repo convention), red before, green after.
- Gates green in claude-infrastructure; landed via /ship; CI read back.
