# Throwaway-team probes — the procedure proven by effect (2026-09-23, account claude-secondary)

Every step below ran against a team this session spawned itself (lead in pane 612 on 2.1.260 /
claude-opus-5, one pane teammate), never against 513/545.

## Probe 1 — manual steps, one variable at a time (lead d117c157, mate probe-mate, pane 613)
| step | observed |
|---|---|
| baseline: lead SendMessage `ping-1` | mate replied `PONG ping-1` |
| mate `/exit` | clean exit, no modal; member row KEPT in config.json (isActive flipped) |
| mate relaunch: `--resume <sid>` + identity flags + `CLAUDECODE=1 CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, 2.1.280, claude-opus-5-5 | TUI shows `@probe-mate`; lead (old) SendMessage `ping-2` → mate `PONG ping-2` → lead transcript received it |
| lead: team dir renamed aside, then `/exit` | NO modal (the old mate process had exited, so no live teammate task); mate pid SURVIVED; nothing recreated the team dir |
| dir restored, lead relaunched with `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME=session-d117c157` on 2.1.280 | config.json NOT rewritten (createdAt + both members unchanged) |
| resumed lead SendMessage `ping-3` | delivered (mate replied `PONG ping-3`), but the reply stayed `read:false` in `inboxes/team-lead.json` — also after a fresh lead turn |
| mate then went idle | reaped by the house `teammate-auto-shutdown.sh` (4th idle, defers exhausted) |

The deaf lead is vendor behaviour: the leader inbox poller runs only when `_we(teamContext)` — the
in-memory roster holds a non-lead key — and `initializeSessionTeam` builds that roster lead-only;
only in-process teammates are re-added on resume (`resumeInProcessTeammate` → `setTeammate`).

## Probe 2 — the shipped code path (`lr-upgrade.sh --drive`, worktree copy)
- Census: lead `lead-awaits-teammates`, mate `upgrade-teammate`.
- First teammate drive (with a relaunch prompt): upgraded; prompt `FAILED:submit` (known narrow-pane
  class); after a manual Enter the mate's turn ended in an idle notification, which WOKE the lead,
  whose model shut the member down (`shutdown_request`, honoured by the upgraded mate — so both
  directions of delivery worked). ⇒ the teammate relaunch was changed to NO prompt, engagement by
  process (`HF_ENGAGE_BY_PROCESS`).
- First process-engagement run failed: lr-fire-resume spawns claude under `expect` on a NEW pty, so a
  tty-scoped `ps` saw only expect ⇒ the check was made machine-wide on `--resume <sid>`.
- Re-run (mate probe-mate3, pane 619): `upgraded … no prompt by design`; the lead's assistant-record
  count was 17 before and after (not woken). Census then: mate `current`, lead `upgrade-lead`.
- Lead drive: `upgraded … as lead; confirmed by a fresh assistant turn`; config.json createdAt and both
  members unchanged; no hold dir left; mate process alive.
- Upgraded lead SendMessage `ping-e2e` → mate replied `PONG ping-e2e`, which landed `read:false` in the
  lead's inbox (the vendor limit, as predicted).

## Aftermath on the live pair — the pane that did not close (2026-09-23 08:20Z)
After its upgrade, lead 513 finished its work and sent `refute-reversals` a `shutdown_request`; the
member approved (`shutdown_approved {paneId:"545", backendType:"iterm2"}`, 08:20:37Z) and exited rc 0,
and pane 545 stayed at a bare shell. The vendor closes a member's pane from the LEAD's InboxPoller,
and only when the approval's paneId matches the lead's in-memory roster — which a resumed lead holds
lead-only, so its poller never runs and the approval stays unread. Probe 2 showed the same symptom
(pane 618 still listed after probe-mate2's approved shutdown) and it was missed at the time. Fix: the
member's SessionEnd detaches `scripts/teammate-orphan-pane-close.sh`
(`tests/teammate-orphan-pane-close.bats`). Two identity traps were hit building it — both the member
census and the member test first read argv TEXT, and this session's own brief quoted
`--agent-id refute-reversals@…`, so it read as the live member; both now key on identity (registry pid
+ vendor spawn form; pane id in the team file).
