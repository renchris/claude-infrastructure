# In-place upgrade of Agent Teams and subagent-holding sessions (2026-09-23)

Brief: move a lead with a live pane teammate (513) and the teammate (545) onto the current binary +
model in place, keeping the team. Implementation: `scripts/limit-recover/lr-upgrade.sh` (§ THE TEAM
PROCEDURE), `scripts/handoff-fire.sh` (teammate admission, engagement by process, subagent corpse
rule + last-read re-check, `--probe-live-subagents`), `scripts/limit-recover/lr-fire-resume.sh`
(`--extra-args` / `--extra-env`). Operator doc: `commands/limit-recover.md` § Mode: upgrade.

| file | question | answer in one line |
|---|---|---|
| `q1-lead-exit.md` | what a lead's exit does to pane teammates | every graceful exit kills the members listed in the team FILE and deletes the dir; no flag skips it |
| `q2-teammate-relaunch.md` | can a teammate resume in place | yes: `--resume` + identity flags + the two team env vars, same pane, member row present |
| `q3-lead-reattach.md` | does a resumed lead re-attach | same name, but it rewrites config.json leader-only unless `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME` is set; its roster stays lead-only |
| `q4-subagents.md` | idle vs in-flight Agent-tool subagents | idle is safe (resumable by agentId); in-flight must defer; corpses from an earlier life blocked forever |
| `probe.md` | the procedure by effect | teammate-first then lead works end to end; a resumed lead cannot READ pane-member replies (vendor) |

Ordering: teammates first. The lead is held (`lead-awaits-teammates`) until every live teammate is
current, because the lead's relaunch is the step that touches the shared team file.
