# Three sessions died at one instant, and nothing said so — 2026-08-09

**Status:** root cause of the SIGTERM **NOT YET CONVICTED**. Everything else below is verified from
disk. Two defects ARE convicted and are the durable value of this document.

Scope (frozen): investigate and resolve why three sessions closed abruptly and unintended — two
fired `/handoff` peers that were expected to re-ping, and one independent main session with no
handoff involved.

---

## 1. What happened, verified

Three Claude Code sessions were killed by an **external SIGTERM at `2026-08-09T07:38:17Z`**
(00:38:17 local). One signal, one instant, three sessions, two different account config dirs.

| session | cwd | account dir | role |
|---|---|---|---|
| `e55264aa-dec4-44bd-b26f-60d8fd8a1690` | `.worktrees/wt-bs-footer-motion` | `.claude-quaternary` | fired handoff peer |
| `d505227f-4e93-4a10-bd1c-876d5d58a79c` | `.worktrees/wt-rum-iad-endpoints` | `.claude-quaternary` | fired handoff peer |
| `49e10824-0c58-4a73-a1ad-69030c613780` | `lakehouse-lecture` | `.claude-next` | **independent main session** |

Evidence: `~/.claude/logs/close-records/{13020,71821,17151}-*.json` — all `exit_code 143`,
`signal 15`, `version 2.1.220`, identical `ended_at`. Identity confirmed against
`lead-crash-watchdog.log` registration rows (pid ↔ sid). All three last wrote a transcript row of
type `queue-operation` at `07:38:14.5Z`, ~2.5 s before the kill; all three of those rows are
`<task-notification>` payloads, **not** operator prompts — no queued human intent was lost.

### 1a. The misdiagnosis this cost, and why it is the interesting part

The in-flight analysis concluded these sessions had *exited cleanly of their own accord*, reasoning:
*"It printed `Resume this session with: claude --resume …` — that's Claude Code's normal exit banner.
A SIGKILL prints nothing. So the process exited cleanly."*

**That inference is invalid. SIGTERM is catchable**, and Claude Code catches it: it runs SessionEnd
hooks and prints its ordinary resume banner. A killed session and a voluntary `/exit` are
**byte-identical on screen**. The banner exonerates nothing.

Generalisable: *a graceful-looking exit is not evidence of a voluntary one.* The discriminator is
`close-records`' `signal` field, never the pane's last line.

### 1b. Exonerated, by their own evidence stores

- **`cc-teardown`** — writes a teardown marker unconditionally at the point where "the first kill is
  the next statement" (`bin/cc-teardown:275`, `write_teardown_marker`). **No marker exists** for any
  of the three. The only marker in the window is pane `894` (`mode:terminal`, `07:38:39Z`) — a
  different session.
- **`handoff-fire.sh self-close` / the SELF-RETIRE trailer** — `~/.claude/logs/close-attrib.jsonl`
  holds exactly ONE row in the window (`07:38:44Z`, pane `894`, `caller_pid 5154`). Self-close types
  `/exit`; it sends no signal.
- **`cc-reaper`'s `garbage` arm** — TERMs 2–5 processes every ~10 min and fired at `07:36:07Z`, but
  its awk predicate contains `if (comm[p]=="claude.exe") continue` and marks every ancestor of a
  live claude untouchable (`bin/cc-reaper:310-390`). Not convicted; not fully excluded either.

**Still open:** who sent it. Both agents dispatched to answer this were killed before reporting
(§3). The distinguishing fingerprint: at that instant pid `82520` (started `07:10:17Z`) **survived**
and exited cleanly rc 0 at `07:38:42Z` — whatever the predicate was, it excluded that one.

---

## 2. CONVICTED — the crash watchdog cannot fire on a caught signal

This is why nothing alarmed, and it is the more durable defect.

All three sessions **were** covered: `lead-crash-watchdog.log` shows a registration and a spawned
watchdog daemon for each. All three watchdogs then logged `pid file gone — exit`.

```
hooks/lead-crash-watchdog.sh:899
  # pid file gone = clean shutdown elsewhere
  [[ -f "$pid_file" ]] || { echo "[watchdog $sid] pid file gone — exit"; return 0; }
```

But `hooks/session-end.sh:32` removes `~/.claude/watchdog/<sid>.pid` on **any** exit — and SessionEnd
runs on a caught SIGTERM. So:

- the pid-file check sits **first** in the poll loop and wins the race against the death check;
- it returns 0 **before** reaching the crash ladder (~line 279) — the ladder that consults the
  teardown marker and classifies *marker absent* as a genuine **CRASH**;
- therefore **every externally-TERMed session launders itself into "clean shutdown elsewhere."**

The watchdog can only ever fire on a death where SessionEnd did **not** run (SIGKILL, panic). The
commonest kind of unexpected death — a caught signal — is structurally invisible to it.

**Fix direction:** on the `pid file gone` branch, do not return 0 unconditionally. Consult the same
teardown marker the crash ladder uses: marker present ⇒ sanctioned teardown, exit quietly; marker
absent **and** the process is gone ⇒ this is a crash, raise it. The discriminator already exists in
this file; it is simply on the branch these deaths never reach.

---

## 3. CONVICTED — the reaper kills read-only agents for producing no git refs

Both subagents dispatched to convict the SIGTERM sender were themselves reaped mid-work.

```json
{ "kind":"reap-decision", "member":"killer-hunt", "decision":"REAP",
  "reason_kind":"shared-no-refs", "age_s":995, "grace_s":300,
  "reason":"SHARED cwd: no refs/wip|checkpoints ref for this member, and a read-only member
            writes none by construction (teammate-checkpoint.sh:201-204 exits 0 with no ref
            when the tree matches HEAD) — birth grace, not R-b, is what holds a just-born
            member here; accepted residual: produced-nothing is reaped like
            produced-nothing-durable" }
```
— `~/.claude/reap-guard/reap-killer-hunt-20260809T080526Z-47874-10614.json`

The reason string **states the defect and accepts it as residual**. A read-only member writes no
`refs/wip` ref *by construction*, so "no refs ⇒ produced nothing ⇒ reapable" convicts every
read-only agent that outlives the 300 s birth grace. `killer-hunt` was killed at 995 s having
produced nothing *durable* — because it was explicitly briefed to produce nothing durable.

`loss-audit` survived its first idle only because the birth grace happened to cover it by **five
seconds** (`age 295s < 300s`, `decision: DEFER`), got its report out, and was reaped on its next
idle.

**Compounding surface defect:** Claude Code's own agent list kept showing both as live (`Vibing…
18m`), and clicking through showed only the brief — the agents were killed mid-turn, so nothing was
written back, and CC never learned they died. The UI asserted "working" over two corpses.

**Fix direction:** reap-eligibility must not use "wrote a git ref" as a proxy for "produced
something" for members that cannot write one. Either classify read-only members explicitly and
exempt them, or key the proxy on evidence a read-only member *does* leave (messages sent, transcript
growth) — not on an artifact its brief forbids.

---

## 4. Work disposition (all recovered or protected)

| session | verdict | evidence / action |
|---|---|---|
| `bs-footer-motion` | **SAFE** — landed, content-verified | `origin/main:docs/plans/BOTTLE_SERVICE_MOTION_GROUND_UP.md` line 3608 reads `(LANDED 2026-08-09)`; a sibling rescued it via rebase at `00:42:59`, 4 m 42 s after the kill. ⚠️ It landed **without its `pnpm build` gate ever going green** — the build task was killed by the same SIGTERM. |
| `rum-iad-endpoints` | **STRANDED → protected** | 310 uncommitted lines + a new 177-line test existing nowhere else. Salvaged non-destructively: patch `~/.claude/salvage/rum-iad-endpoints-sigterm-20260809T073817Z.patch` (21,888 B) and ref `refs/wip/rum-iad-endpoints/sigterm-salvage` → `dee9d33b9`. Working tree left byte-identical. |
| `lakehouse-lecture` | **STRANDED (mild) → resumed** | 1 unpushed commit `6db845f`; was idle 13 min at death, nothing in flight. Resumed 2026-08-09 ~00:55 and re-engaged. |

**Undelivered mail — the "reping" that structurally could not arrive.** The lead's reply to
`bs-footer-motion` was sent `07:37:31Z` and sits at `~/.claude/mailbox/891.md` (899 B, 1 line). There
has never been an `891.acked`, `891.seen`, or any `.watchers/891.*` entry — it was written to disk
and **never surfaced to the model**. The session had 46 s of life left and no turn boundary in them.
`cc-notify`'s `no-watcher` verdict was not a warning that delivery might be late; it was delivery
failing.

Its second ask died with it and is now filed as backlog `a44eef543cfa`: *does production
`MoneyTicker`/`CartDrawer` share the caption-vs-figure clock split that rendered a figure $1,787
wrong in the largest type facing the guest, for ~30 frames?* Nobody has checked production.

---

## 5. Repo-membership gap found while documenting the resume path

The `resume-sessions` runbook is in the repo; **its actuators are not.**

| piece | tracked |
|---|---|
| `skills/resume-sessions/{SKILL,REFERENCE}.md` | ✅ |
| `scripts/limit-recover/lr-select.py` + 7 siblings | ✅ |
| `bin/kitty-split-launch.sh` | ✅ |
| `~/.reso/bin/reso-resume-one`, `reso-keepalive`, `reso-quota` | ❌ **untracked** |

Consequence, measured today: `reso-resume-one` hardcodes `bin=$HOME/.claude-183/…` (that path now
holds **2.1.215**) and `model=claude-opus-4-8 effort=max`. The session it was used to resume ran
**2.1.220 / claude-opus-5** in every one of its versioned rows. Using the tool as shipped would have
silently downgraded both binary and model on a recovery. No lint, test, or review can catch this
because the file is not in the repo.

The resume performed today therefore used a corrected one-off launcher (same `expect` wrapper —
auto-answers "Resume from summary", forwards SIGWINCH — with `.claude-220` / `claude-opus-5 @ high`).

**Fix direction:** bring the three `reso-*` actuators into `bin/`, or delete them and fold their one
load-bearing part (the `expect` wrapper) into a tracked script the skill can name.

---

## 6. Next actions

1. **Convict the SIGTERM sender.** Re-run the hunt; see §1b for what is already excluded and the
   pid-`82520`-survived fingerprint. Highest-value unread store: `~/.claude/logs/bash-execution.log`
   rows in `07:36:00–07:39:00Z`, plus cross-account transcripts and `~/.zsh_history` at that second.
   **Do not dispatch a read-only subagent to do this until §3 is fixed — it will be reaped again.**
2. **Fix §2** (`lead-crash-watchdog.sh:899` consults the teardown marker before exiting quietly).
3. **Fix §3** (reap-eligibility must not convict members that cannot write refs).
4. Land the README row in §4 of `README.md` documenting `resume-sessions` (in this branch).
5. Decide on §5 (track the `reso-*` actuators, or retire them).
