# In-boot kitty restart → hands-off resume: research (2026-10-01, read-only)

## Answer first

**Yes, boot-resume.sh can drive an in-boot kitty restart, but not as it stands with today's state.
Run as-is it would either do nothing or resume the wrong set.** Five things decide it:

1. **Today's roster is silently ignored.** `alarm-reboot-prep.sh:52` appends a second line
   (`<epoch> kalloc1024_gb=1.11`) to `reboot-2026-10-01.start`. `boot-resume.sh:298` strips all
   whitespace from the whole file, which produces `17908759701790875970kalloc1024_gb=1.11`, so the
   non-numeric guard at `:299` skips the roster. Evidence:
   `tr -d '[:space:]' < ~/.claude/autonomy/reboot-2026-10-01.start => 17908759701790875970kalloc1024_gb=1.11`.
   The two test suites encode opposite contracts: `tests/boot-resume.bats:422` writes a one-line
   `.start`, and `tests/alarm-reboot-prep.bats:27` asserts the kalloc reading is inside `.start`.
   The bug arrived with 200827256 (`git log -S'kalloc1024_gb=' => 200827256`). It also breaks
   every future alarm reboot.
2. **The roster is stale anyway** (12:32, about 25 min before this report), and the classifier
   anchors on the roster's `.start`, not on the moment of death (`boot-resume.sh:310,482`), and
   ignores every record after that point (`cc-resume-classify.py:157-158,181-182`). So take a fresh
   roster at the moment of the restart.
3. **Use a separate state dir, or the launchd job will resume yesterday's fleet.** With
   `CC_BOOTTIME_OVERRIDE` against the real state dir, the marker becomes the override value. The
   launchd tick (`StartInterval 300`, plist) then sees marker ≠ real boot (`:238`), keeps
   `LOWER = boot − 86400` because `prev_boot > BOOT` (`:289`), and selects
   `reboot-2026-09-30.start = 1790799903`, a clean one-line file inside the window. That
   re-resumes **yesterday's 20-session roster** in `mode=resume`.
4. **The capacity gate will shed the whole batch at today's load.**
   `uptime => load averages: 146.44` on `hw.ncpu=10` (14.6 per core) against
   `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0` (`capacity-admit.sh:162`). `cc-resume-layout.sh:250-252`
   breaks on the **first** refusal and sheds every remaining row. boot-resume then marks the boot
   as done and never retries (`:615,649`).
5. **The nudge only continues work; it does not recover any.** Only INTERRUPTED rows get it.
   Sessions resting on a background land, a watcher or a subagent are classified AT-REST and
   restored silently. Today that includes two sessions whose `ship-land.sh` is running in the
   background right now (panes 5 and 90), plus this lead (pane 72).

**Do not restart right now:** `alarm-reboot-prep`'s own land predicate sees 4 lands in flight
(`pids 4670 22360 49762 63153 bash scripts/ship-land.sh`).

The single-step recipe and the minimal patch are in §4.

---

## 1. Can boot-resume.sh run in-boot? Selection, dedup, the override seam

**Roster selection (`boot-resume.sh:282-313`).**
- `LOWER = BOOT − RECENCY_WINDOW` (86400) (`:285`). It is raised to the previous marker when
  `prev_boot < BOOT && prev_boot > LOWER` (`:286-290`).
- A roster qualifies when its `.start` is all digits and `LOWER < st < BOOT`. The newest one wins
  (`:296-302`). It then sets `ANCHOR = roster_start` (`:310`).
- Live values: `last-boot-epoch = 1790799966 = kern.boottime` (`sysctl => { sec = 1790799966 …}`).
  `reboot-2026-10-01.start` is non-numeric (bug 1). `reboot-2026-09-30.start = 1790799903`.

**Per-boot dedup (`:237-241`).** The run exits `already-processed` when the marker equals BOOT. The
live IDL shows the launchd job abstaining every 5 min
(`{"ts":"2026-10-01T17:55:23Z",…,"reason":"already-processed"}`). The marker is written only on
`n_open=0` (`:372`) or on delivery (`:615,649`).

**The seam.** `boottime()` returns `CC_BOOTTIME_OVERRIDE` verbatim (`:173-176`). The mode comes
from `CC_BOOT_RESUME_MODE`, then `<state>/mode`, then `page` (`:211-215`). `mode` already reads
`resume`.

**Exact invocation** (after the restart, from a **plain shell in the new kitty**, not a Claude
session). It uses a one-line `.start` copy so bug 1 does not bite, and a private state dir so
hazard 3 cannot fire:

```
D=/tmp/inboot-2026-10-01
# BEFORE quitting kitty (seconds before), from any shell:
mkdir -p "$D/state" && cc-sessions --json > "$D/reboot-inboot.roster.json" && date +%s > "$D/reboot-inboot.start"
# AFTER the new kitty is up:
env CC_BOOTTIME_OVERRIDE="$(date +%s)" CC_BOOT_RESUME_MODE=resume \
    CC_BOOT_RESUME_STATE_DIR="$D/state" CC_BOOT_RESUME_ROSTER_DIR="$D" \
    bash ~/.claude/scripts/boot-resume.sh
```

Why each variable matters:
- `ROSTER_DIR=$D`: only the fresh roster is visible. The 09-30 and 10-01 rosters in
  `~/.claude/autonomy` are not.
- `STATE_DIR=$D/state`: the real marker stays `1790799966`, so the launchd tick keeps abstaining
  and a real reboot later behaves exactly as before.
- `CC_BOOT_RESUME_MODE` and `CC_BOOT_RESUME_STATE_DIR` are inherited by
  `boot-resume-launch.sh --check-only`, which reads both for PARKED-REBOOT
  (`boot-resume-launch.sh:263-265`).
- If run from a detached or launchd context instead, also pass
  `env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON CC_TERM_KITTY_TO=unix:/tmp/kitty-<newpid>` (see gap G6).

**State it writes** (with the above):
- `$D/state/last-boot-epoch` (the override value)
- `$D/state/last-classify.txt`, `last-layout.out`, `last-layout.txt`, `undelivered-<override>.page`
- one IDL row in `~/.claude/autonomy/idl.jsonl` (`:224-228`)
- because `~/.claude/cc-roles/desk` does not exist (`ls cc-roles => docs-lead drain-lead
  opus55-lead orchestrator`), one **`cc-backlog needs` row** (`:638-652`). Pass
  `CC_ROLES_DIR`/`CC_BACKLOG_BIN` if that row is unwanted.
- transient launch locks plus `launch.log` under `~/.reso/limit-recover` (fence `:403-411`,
  released `:281`)
- capacity-admit budget and IDL rows
- `~/.claude/logs/pane-spawns.jsonl` rows
- a detached `reso-keepalive` (`:548-566`), logging to `~/.reso/keepalive.{out,log}`
- possibly `git worktree add` inside `reso-resume-one` (`reso-resume-one:322`)

`~/.claude/autonomy/boot-resume/last-boot-epoch` is **not** touched.

**Preview / dry-run.** boot-resume.sh has **no** dry-run flag (its only flag is `--print-boottime`,
`:222`). There are three previews.
- **Before the restart: classifier and window plan, read-only.** I ran both. The input is the
  roster mapped to `alias\tsid\tcwd\tbranch\tlabel`, in `/tmp/inboot-admitted-preview.tsv`:
  ```
  python3 ~/Development/claude-infrastructure/bin/cc-resume-classify.py --boot-epoch "$(date +%s)" --explain < /tmp/inboot-admitted-preview.tsv
  ~/.claude/bin/cc-resume-layout.sh --desktops --dry-run < /tmp/inboot-admitted-preview.tsv
  ```
  Results: `2 INTERRUPTED (film-mvk 3a06361f, husk-pane-closers d86e6bd4), 30 AT-REST, 0 UNKNOWN`,
  and `verdict=ok launched=0 … windows=9` (plan in §2).
- **Per session:** `boot-resume-launch.sh --dry-run <alias> <cwd> <sid> [branch]` prints the exact
  command (`boot-resume-launch.sh:231-243`).
- **After the restart:** the whole chain with nothing opened. Add
  `CC_RESUME_LAYOUT_BIN=<wrapper that execs cc-resume-layout.sh --dry-run "$@">`,
  `CC_KEEPALIVE_BIN=/usr/bin/true`, `CC_IDL=$D/idl.jsonl`, `CC_ROLES_DIR=$D/roles` and
  `CC_BACKLOG_BIN=<stub printing deadbeef>` to the invocation above. Then delete
  `$D/state/last-boot-epoch` before the real run.
  A full-chain preview **before** the restart is meaningless: every session is live, so
  `--check-only` returns rc 5 (H(sid)≥1, `boot-resume-launch.sh:289-293`) for all 32.

## 2. What exactly gets restored

| Aspect | What happens | Evidence |
|---|---|---|
| Set | Roster rows (fresh cc-sessions snapshot). No `lr-select` consolidation and no total cap on roster or tombstone rows | `:408-447` |
| cwd | The roster's `.cwd`. A reaped worktree is recreated from its branch. A pooled slot now on another branch is **refused** | `reso-resume-one:322,355-371` |
| Branch | Roster rows carry **no** branch, so it is read from the directory's current HEAD at resume time (`:459-462`). The drift guard therefore compares a branch with itself. Tombstone rows do record the branch at death (`session-deregister.sh:85-90`) | roster jq: no `.branch` field |
| Account | Config basename mapped to alias: claude-next→next, claude-tertiary→next3, claude-quaternary→next4 (`lib/account-map.generated.sh`). Then `cfg` comes from the alias (`reso-resume-one:396-405`). Same account, same transcript store | ran `cc_acct_name_for_dir_basename` |
| Model / effort | **Not from the session.** `opus_latest` plus effort `high` (`reso-resume-one:172-179,384,396-410`). Harmless today: all 32 live argv read `--model claude-opus-5-5 --effort high`. A Fable or xhigh session would be silently changed | ps argv census |
| Transcript / sid | `claude … --resume $sid` (`reso-resume-one:560`), full session as-is (`:589-626`). **The sid is kept**: every live `--resume X` process is the registry row for sid X (e.g. pane 10 pid 27645 `--resume 0572baa6`, roster `session_id 0572baa6…`), and the classifier relies on a resume appending to the same transcript (`cc-resume-classify.py:157-158`) | ps census + roster |
| /goal | Restored by Claude Code on `--resume` (`~/.claude/CLAUDE.md:238`, `tengu_goal_restored_on_resume`), **provided** the as-is option is taken, which it is. The summary option drops it (`reso-resume-one:592`). A restored goal only acts at a Stop, so an idle restored session does not move until something makes it take a turn | |
| Layout | **Not the original.** The current layout cannot even be read: `kitty @ --to unix:/tmp/kitty-610 ls => connect: connection refused`. The roster has no window or tab fields. `--desktops` re-groups by repo into ≤4-pane 2x2 native-fullscreen Desktops (`cc-resume-layout.sh:192-227`). Today's plan is **9 windows**: 6 for claude-infrastructure plus its worktrees (one shared with agent-context-sync), 1 for personal (3), 1 for reso (3), 1 for voiceink (2). Stagger 12 s per pane, so about 6.4 min for 32 | dry-run output |
| Nudge | Only INTERRUPTED rows with a cwd that is unique among non-INTERRUPTED rows get it (`:543-547`). It goes through a **detached `reso-keepalive` that re-nudges every 240 s forever** whenever the pane is idle (`reso-keepalive:197-238`) | |

**The nudge text, verbatim** (`bin/reso-keepalive:54`, hardcoded, no env override):
> "Continue autonomously with your goal: do your next task, commit it, and keep going. Stop only
> when the work is genuinely complete or you hit a real blocker (auth/session, destructive
> migration, or a decision you cannot infer)."

**Does that nudge recover delegated work? No.** It names no recovery step. A resumed process owns
none of the old process's in-memory tasks:

- **Background Bash and Monitor watches.** They are children of the dead process. Live census:
  about 16 shells across 12 roster sessions, including 7 `cc-await-ping` watchers (panes 20, 21,
  3, 38, 5, 89), a render-wait loop (19), an 18 h probe (47), and **two background `ship-land.sh`
  runs (panes 5 and 90)**. limit-recover itself treats a relaunch as ending such watchers and
  needing a re-arm: `lr-upgrade.sh:1110` prompt, `commands/limit-recover.md:737-740`.
- **Subagents.** The task-notification never arrives, so the work sits as COMPLETE_UNDELIVERED or
  PARTIAL on disk until `/limit-recover` audits it (`limit-recover.md` verdict table, lines
  ~77-92 of the command). Live: pane 72 (this lead) has 2 agent files written in the last 30 min
  and is waiting on this subagent.
- **Dynamic Workflows.** `resumeFromRunId` is "same-session-DIRECTORY, not same-process"
  (`commands/limit-recover.md:108-119`, corrected 2026-09-19). Because `--resume` keeps the sid
  and the account, the run journals under `<cfg>/projects/<slug>/<sid>/subagents/workflows/` stay
  reachable. But only `/limit-recover` invokes the resume, applying its prefix rule (`:126-151`).
  Live: workflow dirs touched in the last 2 h exist for panes 5, 72 and 91.
- **Teammates.** None live. Every roster-led team (`session-f8b54aee`, `-40ebc527`, `-09c26b2b`,
  `-16798199`) holds only its in-process `team-lead`, and no process carries a real `--agent-id`
  (pane 75's match was brief text). In-process members die with their lead. Recovery would be
  limit-recover § Teams respawn from salvage (`:410`).

**Compared with the skills.** `skills/resume-sessions/SKILL.md:223-231` uses the same continue
directive and the same keepalive. It recovers no delegated work. `commands/limit-recover.md` is
the only path that audits and recovers subagents, workflows and teammates from disk, and it runs
**inside** the session. What needs a different nudge:

- **(a) INTERRUPTED rows:** the recovery prompt below, then the keepalive.
- **(b) AT-REST rows that held live background work at the kill:** the same recovery prompt
  **once**, with no keepalive. Today: panes 5, 90, 72, 3, 20, 21, 38, 47, 89, 91. The classifier
  cannot see these (all read AT-REST in the preview), so they must be flagged from a process
  snapshot taken at roster time, or from unanswered `run_in_background`, Monitor or Workflow
  launches in the transcript.

Proposed text, modeled on `lr-upgrade.sh:1110`:

> "kitty was restarted at <HH:MM>; this session was resumed in full (same session id, same
> account). Everything that ran in the background under the old process died with it: Bash
> background jobs, Monitor watches, cc-await-ping watchers, in-flight subagents and Dynamic
> Workflow runs. Run /limit-recover now: read finished results from disk, re-run only what is
> incomplete (resume workflow runs with resumeFromRunId where the audit says so), and re-arm a
> watcher only if you still need it and no /goal is live. If a ship-land was in flight, verify by
> content (git ls-tree origin/main) before landing again. Then continue where you left off; if
> nothing was pending, reply with one line saying so."

## 3. Gaps and risks for in-boot use

- **G1. `.start` format bug (§Answer 1).** It also kills every future alarm-reboot roster.
- **G2. Stale anchor.** The classifier judges the state at `.start`, not at death. A fresh
  snapshot immediately before the restart solves it.
- **G3. Marker poisoning (§Answer 3).** Never override BOOT against the real state dir.
- **G4. Ownership checks.**
  - **H(sid) holder count** (`boot-resume-launch.sh:285-293`, `lr-lib.sh:509-538`) is keyed on
    `kill -0` of registry pids plus `--resume <sid>` argv. After kitty dies it reads 0, unless an
    old `claude` survives (then rc 5, held). That is the reason to require kitty 610 gone before
    running.
  - **Recon fence:** off (`recon.on` absent, `owned/` empty), so the verdict is act
    (`lr-recon-fence.sh:171-186`). The four stale Sep 30 launch locks (c28362b6, c8c2adc0,
    68691067, cd3bd860) name dead pid+lstart holders and are stealable (`:244-255`).
  - **PARKED-REBOOT:** no roster sid is PARKED-REBOOT (records read PRE-MOVE / ENGAGED).
- **G5. The session running the restart is in the roster.** This lead is pane 72, sid 09c26b2b,
  pid 3521 (`ps` ancestry `3521 claude.exe → … → 610 kitty`). It dies with kitty and comes back
  AT-REST and un-nudged (preview: "2.3 min idle"). It cannot run the post-restart step itself,
  and this subagent's result is lost unless it is delivered before the restart. That is why the
  post-restart step must be a pre-armed detached waiter or a plain-shell command.
- **G6. Stale kitty environment.** Run from a detached child of a pane, the env carries
  `KITTY_WINDOW_ID=72` and `KITTY_LISTEN_ON=unix:/tmp/kitty-610`.
  - With `KITTY_WINDOW_ID` set, `cc-resume-layout.sh:167` skips socket resolution, and `kitty @`
    then talks to the dead socket, so every launch fails.
  - `cc-kitty-socket`'s fast path returns any `-S` socket file without a liveness check (`:57-60`).
  - The keepalive would also skip whatever new pane gets id 72 (`reso-keepalive:48,158`).
  - Fix: `env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON` plus an explicit `CC_TERM_KITTY_TO`.
- **G7. Sandbox kitty 94453 (`--instance-group kdw4`).** It is **not** picked by socket discovery:
  it listens on `/tmp/kdw4.sock`, outside the `/tmp/kitty-*` glob (`cc-kitty-socket:63`;
  `--all => unix:/tmp/kitty-610` only). But both bundles are `net.kovidgoyal.kitty 0.48.2`
  (PlistBuddy), so boot-resume's `open -a kitty` fallback (`:505`, only on layout rc 3) could
  activate the sandbox instead of starting the main kitty. Avoid it by running only after the
  main kitty's socket answers.
- **G8. Old kitty must be fully gone.** `cc-kitty-socket` picks the OLDEST live kitty (`:78`). If
  a wedged 610 survives, it is chosen and refuses connections (it does today).
- **G9. Load and batches.** The gate refuses above 2.0 per core, and the layout sheds the entire
  tail on the first refusal (`cc-resume-layout.sh:250-252`). The budget (3 consecutive refusals,
  then admit; `capacity-admit.sh`, `CC_ADMIT_BUDGET:-3`) is never reached in one run. Roster rows
  get no `MAX_TOTAL` cap (that applies to registry only, `:408-438`).
  - Batches of 4 are not a knob today. They can be emulated: re-running with
    `$D/state/last-boot-epoch` removed resumes only the not-yet-resumed rows, because the resumed
    ones now hold H(sid)=1 → rc 5.
  - Cost: one extra keepalive and one page per round.
  - `CC_ADMIT_GATE=off` is the override if the operator accepts the storm.
- **G10. Mid-land sessions.** 4 `ship-land.sh` processes are live. alarm-reboot-prep would say
  NOT-READY (`alarm-reboot-prep.sh:57-70`). Panes 5 and 90 run theirs in the background and read
  AT-REST, so they would be restored with no nudge and the land outcome unknown. Pane 72 polls pid
  4670. Restart only on `verdict=READY`.
- **G11. Keepalive is cwd-keyed.** A shared cwd drops the marker (`:543-547`). claude-infrastructure
  root holds 7 roster sessions and personal holds 3, so an INTERRUPTED session there is never
  nudged if any sibling is at rest, which is near-certain. Today's two INTERRUPTED rows have
  unique cwds. Once started, it nudges forever and also nudges new non-roster panes in a marker
  cwd.
- **G12. No resume debt on the layout path.** Only the launcher's window path opens a
  `cc-resume-debt` (`boot-resume-launch.sh:381-394,403`). The `--desktops` path opens none, so a
  pane whose resume failed inside it has no proof sweep.
- **G13. Fullscreen attribution (unverified).** A detached waiter's responsible process is the
  dead kitty, and the System Events AXFullScreen calls (`cc-resume-layout.sh:177-190`) may lose
  Accessibility attribution. The panes would still be created; only `fullscreen_failed` rises. I
  did not test this.
- **G14. Never exercised.** The only real run was page mode (`idl:
  2026-09-30T20:50:16Z … "mode":"page" … "n_open":11 … "reason":"no-desk-role"`), and the state
  dir has no `last-layout`/`last-classify` files. The hermetic suites (`boot-resume`,
  `boot-resume-launch`, `cc-resume-layout-desktops`, `alarm-reboot-prep`, `reso-keepalive`) were
  **refused twice by cc-bats** (rc 75, "2 concurrent bats execution root(s) … AND 1-min load/core
  at or above 2.0", no `1..N` plan line). That is a deferral, not a result. I did not waive it.
- **G15. Tombstones are the fallback if no fresh roster exists.** `reason=other` SessionEnd →
  tombstone with branch (`session-deregister.sh:79-97`). The burst rule takes the restart burst,
  and the anchor is the true death time. But 09-30 measured 19 of 20, and with no tombstones the
  registry fallback consolidates to **4 total** across 45 rows, 13 of them already dead.

## 4. One hands-off step

**Precondition (operator, one look):** `bash ~/.claude/scripts/alarm-reboot-prep.sh` prints
`verdict=READY` (no lands in flight), and this lead has received this report.

**Arm before restarting**, from any pane: `detach` so it survives kitty, per `scripts/lib/detach.sh:1-40`.

```
. ~/.claude/scripts/lib/detach.sh && detach /tmp/inboot-2026-10-01.log env -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON bash /tmp/inboot-resume-waiter.sh
```

`/tmp/inboot-resume-waiter.sh` (described, not written) does:

1. Refuse if `ship-land.sh` is running (the alarm-reboot-prep predicate).
2. While `kill -0 610`: every 10 s write `cc-sessions --json` to `$D/reboot-inboot.roster.json`
   (tmp + mv), the one-line epoch to `$D/reboot-inboot.start`, and a per-pid list of
   non-MCP child processes to `$D/bg.tsv`. Only replace the snapshot when the row count did not
   drop by more than 2, so a mid-shutdown snapshot is never kept.
3. After 610 exits: poll `~/.claude/bin/cc-kitty-socket` until it returns a socket whose pid ≠ 610
   and `kitty @ --to $S ls` succeeds (cap 30 min).
4. Wait until load1/ncpu < 2.0 (cap 10 min).
5. Run the §1 invocation plus `CC_TERM_KITTY_TO=$S`.
6. While `$D/state/last-layout.out` reports `shed>0`: wait for load, remove only
   `$D/state/last-boot-epoch`, and re-run with a new `CC_BOOTTIME_OVERRIDE` (at most 8 rounds).
7. Send the §2 recovery prompt once to every resumed pane whose sid is INTERRUPTED or listed in
   `bg.tsv`, addressed by kitty window id from `pane-spawns.jsonl` (`resume-layout … sid=` rows),
   via `bin/it2-kitty session send` behind the keepalive's idle and prompt predicates.

**Minimal patch, so this becomes the launchd path instead of a /tmp script:**

1. `boot-resume.sh:298`: `st="$(head -1 "${f%.roster.json}.start" … | tr -d '[:space:]')"`, or
   move the kalloc reading to a sibling `.kalloc` file in `alarm-reboot-prep.sh:52`. Add a bats
   case pairing the two scripts.
2. A `--event <epoch>` mode (terminal restart): BOOT := event, a separate marker file
   (`last-event-epoch`), and `LOWER` from that marker, so the real per-boot marker is never
   rewritten (removes hazard 3).
3. The roster/tombstone path honours `MAX_TOTAL` as batch size and loops with a load wait instead
   of one shed-and-mark (G9).
4. `cc-resume-classify.py`: a 4th verdict `WAKE-LOST` (AT-REST, but background tasks were
   unanswered at the anchor). It and INTERRUPTED get a **one-shot recovery nudge targeted by
   window id**, not a cwd marker (fixes G11). Make `reso-keepalive`'s `NUDGE` env-overridable
   (`CC_KEEPALIVE_NUDGE`, `reso-keepalive:54`).
5. Write `branch` (and model/effort from argv) into the roster in `alarm-reboot-prep` /
   `cc-sessions`, and pass `--effort` through the layout to `reso-resume-one`.
6. Open a `cc-resume-debt` per pane in the `--desktops` path (G12).

Side files from this research: `/tmp/inboot-admitted-preview.tsv`,
`/tmp/inboot-classified-preview.tsv`, `/tmp/inboot-classify-explain.txt`, `/tmp/inboot-ps.txt`,
`/tmp/inboot-bats-*.txt` (refusals).
