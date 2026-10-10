# Why a lead-ordered teammate teardown was painted as a crash — and the fix

**Answer.** `hooks/lead-crash-watchdog.sh` recognized a retired teammate by a single signal: a delivered `shutdown_request` record in the member's own transcript. A busy member never records the request: it arrives only at the member's next turn boundary. TaskStop writes nothing on the member's side, and a SIGTERM ends the member before that boundary. The order is recorded in a place the member cannot write: the LEAD's transcript, in harness-written form. The fix reads it there.

On the fleet's own history, the fix rescues 23 of 28 lead-ordered teardowns that had been painted CRASH. It keeps all 52 existing retirements, and it absolves none of the 77 teammate deaths that had no lead order. A teammate that dies with no lead teardown is still painted ⛔ NOT A CLEAN EXIT.

Evidence files in this directory: `01-arm-mechanics.md`, `02-evidence-census.md`, `03-fleet-frequency.md`, `04-contract-and-skill.md`, `05-design-and-control.md`, `06-skeptic.md`. They were produced by one Dynamic Workflow: five read-only slots plus a skeptic, which was re-run against the chosen design.

## The incident (pane 200, 2026-10-10)

| time (Z) | actor | event | where it is recorded |
|---|---|---|---|
| 18:03:41.102 | cvf-docs | idle_notification stamped | lead transcript, record 815 (read at 18:04:16) |
| 18:03:41.243 | cvf-docs | **resumed work** on the lead's relay message, 141 ms later | member transcript, record 337 |
| 18:04:25.438 / 26.207 | lead | SendMessage shutdown_request: tool_use, then result `{success, request_id: shutdown-…@cvf-docs, target}` | lead transcript, records 820 and 828 |
| 18:04:26.867 | cvf-docs | Bash tool_use that **never got a result** | member transcript, record 386 |
| 18:04:26.983 | cvf-docs | inbox drained to `[]` (the request was held in memory until a turn boundary that never came) | inbox file mtime |
| 18:04:40.623 / 50.929 | lead | TaskStop cvf-docs: result `{task_type: in_process_teammate}`; the process kept running | lead transcript, records 842 and 843 |
| 18:04:59.336 | lead | `kill -TERM 23017` | lead transcript, record 857 |
| ~18:06:27 | cvf-docs | exit flush (its last write); exit 143; SessionEnd never ran, so its pidfile survived | member transcript mtime |
| 18:07:03 / 07:49 | watchdog | classified CRASH/abrupt-unknown, paged the desk, painted the pane | `claude-crashes.jsonl`, `lead-crash-watchdog.log` :59402-03 |

The member was **not idle**. Its worktree held 3 uncommitted files, which its lead kept in 9bab03777 after this session flagged them. So the honest verdict is *retired by its lead, mid-task*. Both "crash" and "its work went to the lead" are wrong.

## Q1 — Which signal the RETIRED arm keyed on, and why it missed

- The arm is `retired_teammate` → `teammate_facts`. It looks for a `type:user` record in the member's transcript containing `<teammate-message` and `"type":"shutdown_request"`, with a requestId ending `@<name>`. Siblings cvf-readout and cvf-hooks matched this; cvf-docs had only prose mentions (01).
- Only `RECYCLE:retired-teammate` selects the ✅ RETIRED headline. The teammate flag on its own only swaps the reopen line. That is why the banner said both KILLED and "the lead re-spawns members" (01).
- The cause read `abrupt-unknown` rather than `external-sigterm` because members launch without `cc-close-attrib`, so they have no close record. `cc-pane-runner` prints the exit code to the pane but writes it nowhere (01).

## Q2 — Durable, unforgeable evidence of a lead-ordered teardown

| candidate | verdict | why |
|---|---|---|
| **Lead transcript: TaskStop tool_use (`input.task_id == name`), joined by `tool_use_id` to a result with `task_type: in_process_teammate`** | **use it** | Written by the harness in the lead's own store, present minutes before the classification, and its timing is exact. A failed stop is a `tool_use_error` string; a same-named background task has a different task_type. |
| Lead transcript: SendMessage result `{success:true, request_id: shutdown-…@name, target}` | use it, gated | Its shape was stable in all 302 results seen (CC 2.1.220–2.1.293). It proves the request was SENT, not that it ended the member, so it counts only for a member that died between turns and never answered approve:false. |
| Team inbox | reject | It is a queue: the recipient prunes it on read (02). |
| Team config member removal | corroboration only | No per-member timestamp, and the whole team dir is deleted on a graceful lead exit (02). |
| `teammate-orphan-pane-close.sh` | reject | It runs from the member's SessionEnd, which never ran here (02). |
| A marker written by a helper the lead calls (D3) | reject | It depends on the lead model obeying it. A pid-keyed marker is inert for members, and arm 1.5 would read a sid-keyed one as "CLOSED CLEANLY … exited on its own" (04, 05). |

## Q3 — How often this happens (measured over `~/.claude/logs/claude-crashes.jsonl`, 5,349 rows, 2026-07-23 to 2026-10-10)

- After the retired-teammate arm landed (b6bf10c0c, 2026-10-01), there were 78 teammate deaths. 61 were lead-ordered. The arm caught 52 and the desk marker caught 2. **6 were misclassified as CRASH**, and each sent one false SESSION DEATH page; only cvf-docs also painted a wrong verdict into its pane (03).
- Across the whole dataset, 28 rows from 9 leads had this shape. 20 of them were TaskStop-only (the lead never sent a request), and 5 were a bare kill with no successful order (for example, the request failed with "No agent named … is reachable") (03, 06).
- None of the post-arm teammate crashes was genuinely unexplained. The other deaths were jetsam OOM kills, or a member that died 14 s before the desk tore down its lead (03).

## Q4 — Should the skill's escalation write a marker?

No. The lead's own TaskStop and SendMessage results are already a durable record, written by the harness rather than by the model, so a helper would add a compliance dependency and new reader arms for no extra evidence.

The skill did need correcting, though. Its claims that "an idle agent will never answer" and its idle 0/4 table were overturned by the W5 probe (`SUBAGENT_LIFECYCLE_ROOT_CAUSE_2026-09-19.md` P2). It also trusted an `idle_notification` that can be stale by milliseconds. The lead escalated 14 s after the request against the skill's ~60 s wait, and killed a working member (04).

The skill now says three things:
- wait the full ~60 s;
- check the member's worktree before escalating;
- escalate through TaskStop or shutdown_request, because those are what the watchdog reads. A bare kill reads as a crash, by design.

## Q5 — A genuine crash still paints NOT A CLEAN EXIT

The CONTROL test (no lead order) asserts CRASH/external-sigterm with a 143 close record, CRASH without one, and a ⛔ banner. The guard test asserts CRASH in each of these cases:
- an order to another member, even when the lead's record mentions this one by name;
- a failed TaskStop;
- a same-named non-teammate task;
- an order to an earlier namesake;
- an order after the member's last write (the lead found it dead);
- an order more than 600 s before the death;
- a request alone to a member that was mid-call;
- a member-authored record;
- a member that refused the request.

Each guard was mutation-checked: removing it makes that case fail. Jetsam still outranks the lead-side source.

## The design that landed

- `teammate_facts` emits `TEAMMATE NAME TEAM SHUTDOWN SOURCE MIDTASK`, and `retired_teammate` reads field 4 explicitly. The identity line is flushed first, so if the bounded lead read times out it degrades to `source -` and the member is still known to be a teammate.
- **The lead transcript is found** from the team config's `leadSessionId` in any account root (the member's own project dir first), or else from the team name `session-<sid8>`.
- **The order is judged by its tool_use time, not its result.** The death anchor is the member's last write, capped by the caller's death epoch. The order must fall in `[anchor − 600 s, anchor + 2 s]` and after the member's first record.
  - Why the tool_use time: the skeptic measured that the TaskStop *result* lands 0.0–0.5 s after the member's exit flush. The first draft keyed on the result and rescued only 4 of 28.
  - Why 600 s: the observed maximum lag from order to last write is 260 s.
- **What the pane shows:**
  - member-side source: ✅ RETIRED — "its work went to the lead".
  - lead source, member between turns: ✅ RETIRED — "stopped by its lead (TaskStop / shutdown_request); this was not a crash". The pane is handed to the closer.
  - lead source, member mid-call: **⚠ RETIRED MID-TASK**, with a check-its-worktree warning. The pane is not auto-closed, because the warning is the point of the paint.
  - Class stays RECYCLE in every case, so none of them pages.
  - The re-spawn advice is removed from the retired banner and the retired death page. It stays only on the genuine-crash teammate reopen line.

## Skeptic

The skeptic's first pass failed on a network error. Re-run against the chosen design, it found:
1. The result-vs-order timing bug (fixed).
2. The SendMessage request arm decided none of the 28 rescues and could falsely absolve a member that died mid-call after a request; it is now gated on the member being between turns.
3. The approve:false veto over-reached onto TaskStop; it now applies only to the request.
4. The name prefilter masked the other-member mutant; a fixture whose lead record names the member now kills it.
5. The 30-minute window was about 7x the observed maximum; it is now 600 s.

After the amendments, a replay of the final code over all 403 fleet teammate rows agrees row-for-row with the skeptic's amended variant: 23 lead-TaskStop rescues, 52 of 52 retirements kept, and 0 of 77 no-order crashes flipped (`/tmp/ttv-fleet.tsv`, regenerable with `/tmp/ttv-fleet.sh`).

## Not done here (named for the next owner)
- Members have no close record, so a teammate death can never be named `external-sigterm`. Wrapping members in `cc-close-attrib`, or having `cc-pane-runner` persist its exit code, would fix this.
- Arm 1.5 accepts a sid-keyed marker of any `mode`, so a teammate-written `teammate-idle` marker absolves a death of that sid (02). This may be intended, since that hook is a sanctioned retirement, but no comment says so.
- `handle_crash`'s team scan omits `~/.claude-quaternary/teams` (01; not verified live).
- The banner reports the lead's worktree (`LEAD_CWD`), not the member's. A member-worktree resolver (config `members[].cwd` while the team exists) would let it print the dirty count. The mid-task warning covers the gap for now.
- 5 of the 28 rows are a bare kill with no successful order. They stay CRASH by design.
