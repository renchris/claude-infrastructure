# 06 — skeptic: attacking D1 and the five slots

Read-only review. Scratch scripts, fixtures and replay outputs are in `/tmp/skeptic/` (outside the repo).
Every number below is labelled with the command or method that produced it.

## 0. Verdict first

- **D1 holds as a direction. The working-copy implementation does not deliver it.** I snapshotted
  `hooks/lead-crash-watchdog.sh` at sha256 `49c14517…`, the version with all guards in place, and
  replayed its `teammate_facts` Python against all 403 teammate deaths in `claude-crashes.jsonl`. It
  rescues **4 of the 28** same-shape misses (2 of the 6 post-arm), not 28 and not 23. The cause is one
  comparison. The code checks the TaskStop **result** timestamp against the member's last write, but
  that result lands 0.0–0.5 s **after** the member's exit flush whenever TaskStop's own pane close
  works. The plan (`docs/plans/TEAMMATE_TEARDOWN_VERDICT.md:32`) says "the **order** must come … within
  the 30 minutes before its last write". The code tests the result, not the order.
- **Fix:** judge the TaskStop **tool_use** timestamp (the order), and keep the result join only as the
  proof that it succeeded. Measured over the same 403 rows: **23 of 28** rescued (6 of 6 post-arm), 52
  of 52 own-source retirements unchanged, and 0 new absolutions among the 80 teammate CRASH rows that
  have no lead order (79 of them non-jetsam).
- **The SendMessage arm (a) should not be sufficient evidence.** It decided 0 of the 28 rescues; cvf-docs
  also had a TaskStop. Its only unique reach is a member that died mid-tool after an undelivered
  request, and the request cannot have caused that death. Fixture F7 shows it absolving an unrelated
  crash.
- **The 5 remaining misses are bare kills of orphaned members.** The lead's SendMessage there returned
  `success:false "No agent named … is reachable"`. D1 cannot see them, and no D1 variant should be
  stretched to.
- Amended design and conviction are in §5.

## 1. Receipts: re-run, not trusted

| Claim (slot) | Re-run | Result |
|---|---|---|
| HEAD classifies the incident `CRASH abrupt-unknown 1159 390` (01, 02, 05) | `git show HEAD:hooks/lead-crash-watchdog.sh` → `/tmp/skeptic/wd-head.sh`, `--classify 5b813b72… 23017 {1791655623, auto, ""}` with HOME and every store in mktemp | **reproduces**, all 3 death args |
| Member's last conversational record is the 18:04:26.867Z Bash tool_use with no result; no delivered `<teammate-message>` shutdown_request (01, 04, 05) | python scan of `5b813b72….jsonl` | **reproduces**: rec 386 is the open tool_use, then bridge-session, cost-state, last-prompt, cost-state. The 5 `shutdown_request` lines (10, 88, 129, 322, 357) are attachments or tool_results. `teammate-message` occurs in recs 9 and 337 only |
| Lead records 815/820/828/842/843/857 (02, 05) | parsed each line | **reproduces exactly**, incl. `toolUseResult {success:true, request_id:"shutdown-1791655466065@cvf-docs", target:"cvf-docs"}` and TaskStop result `{task_id:"t5ou0rn4u", task_type:"in_process_teammate"}`, with the name only in the tool_use input |
| Inbox drained to `[]` at 18:04:26.983Z; config mtime 18:12:12.816Z lists only team-lead (01, 02, 05) | `os.stat` (birth = mtime), `jq` | **reproduces** |
| cvf-docs worktree has 3 modified files (all) | `git -C ~/Development/.worktrees/cvf-docs status --porcelain`, `diff --stat` | **reproduces**: 3 files, 13+/11− |
| No close record for pid 23017; the crash row's `exit_code` is "" (01, 02) | `ls …/close-records/23017-*`, crash log line 5348 | **reproduces** |
| Registration line, `LEAD CRASH detected`, page DELIVERED, PAINTED (01, 03) | `grep -n 5b813b72 lead-crash-watchdog.log` | **reproduces**: :59393, :59401, :59403 (13:07:03 CDT), :59405 (13:08:04 CDT) |
| 52 `retired-teammate` rows; 78 post-arm teammate deaths; 325 pre-arm (03) | `grep -c`; my replay population (403 = 325 + 78) | **reproduces** |
| Markers: 3790 total, ~2468 older than 30 days, 669 `teammate-idle` (02) | `ls \| wc`, `find -mtime +30`, `grep -l` | **reproduces** (2475 older than 30 d now, from clock drift) |
| 0-byte composer snapshot at 18:04:51Z, win200 (04) | `ls -la` | **reproduces** |
| SKILL.md stale "idle 0/4" table and "An idle agent will never answer" (04) | `sed -n 355,365p; 438,448p` | **reproduces** |
| handle_crash team scan omits quaternary (01 incidental) | `git show HEAD:… \| grep -n 'for team_config in'` → :1973 | **reproduces**: only .claude, -secondary and -tertiary are scanned |
| **"A lead-side test catches all 28" (03)** | read `/tmp/ff/scan.py`; parsed the lead transcript for rows 1655–1659 | **refuted for D1.** 03's detector counts a SendMessage/TaskStop **tool_use regardless of success** and also counts Bash `kill`. In rows 1655–1659 (lead ba08cab8, 2026-09-14) the SendMessage results were `{"success": false, "message": "No agent named 'v1-verify-d3-d6' is reachable."}`, followed by a `kill` by pid. D1, which has no kill arm and requires success, has a ceiling of **23/28** |
| **"476 of 476 team configs" (05)** | `ls ~/.claude*/teams/*/config.json` per root | **denominator wrong**: `~/.claude-next/teams` is a symlink to `~/.claude/teams`, so a `~/.claude*` glob counts 49 configs twice. Unique: 49+64+227+90 = **430**. The ratio still holds |
| SR result shape stable? (05 open) | scanned 288 lead-side transcripts | **answered**: 302 of 302 successful results across 2.1.220/260/280/284/293 have `success`/`request_id`/`target`, all on `type:user` records with no `teamName` |

## 2. Attacks on D1 and on the working copy (snapshot 49c14517)

Method: I extracted the `teammate_facts` heredoc into `/tmp/skeptic/tf_wip.py` and ran it unmodified
with argv `(member transcript, registered agent-id, row epoch)` over all 403 teammate rows of
`/tmp/ff/out.json` (outputs: `replay.tsv`, `use.tsv`, `slack.tsv`). The synthetic fixtures are made by
`/tmp/skeptic/fx/mk.py`, each in its own mktemp base with `CC_ACCOUNT_BASES` pointed at it.

### 2.1 FATAL to the implementation: the anchor cuts off the TaskStop result

What happens when the pane close works: the TaskStop tool_use is written, then the member exits and
flushes cost-state (its last write, i.e. the mtime anchor), then the TaskStop result is written.
Measured examples, all UTC:

| member | TaskStop use | member mtime (anchor) | TaskStop result | result − anchor |
|---|---|---|---|---|
| p3-vtt 08a7fba0 | 04:18:03.375 | 04:18:03.809 | 04:18:03.968 | +0.16 s |
| p3-naming cb60df97 | 04:18:02.933 | 04:18:03.237 | 04:18:03.334 | +0.10 s |
| p3-wire daabff77 | 05:28:20.166 | 05:28:20.639 | 05:28:20.805 | +0.17 s |
| lrsh-c4 05271ce9 | 16:23:19.004 | 16:23:19.594 | 16:23:20.034 | +0.44 s |

Source: `/tmp/skeptic/diag.py`. `inwin(t)` with `t <= anchor` rejects every one of them. Over the 28
rows (`diag2.py`): **19 rejected this way** (result 0.0–0.5 s after the anchor), 5 are bare kills, and 4
are caught. The 4 caught (p3-cue, cvf-docs, b1f7-paneid, score) are exactly the cases where the pane
close failed and a later `kill -TERM` moved the member's last write past the result.

- Variant `tf_use.py`: the TaskStop is judged by its tool_use timestamp, the result is still required
  for success, the SR keeps its own timestamp. Result: 23/28 (6/6 post, 17/22 pre), 0 flips among the
  80 no-order CRASH rows, 52/52 own preserved.
- Variant `tf_slack.py`: a +15 s slack on the anchor gives the same 23, but it also widens the SR window,
  which is worse.

**Why the bats suite passes anyway.** `lead_taskstop` writes the use and the result with the same
`iso "$2"` stamp, and the REPLAY test then runs `touch "$TX"`, which puts the anchor at *now*. The
fixture can never put the result after the member's last write. Add a realistic fixture: use T−0.4 s,
member mtime T, result T+0.2 s. It must read RETIRED. Fixture F1 reads CRASH on 49c14517 and RETIRED on
`tf_use.py`.

### 2.2 Death epoch: what each path passes

- Live: `handle_crash` calls `classify_death "$sid" "$pid"` (HEAD :1903), so the epoch is **now**.
- Backfill: `bin/cc-crash-report:100` passes `auto`. That resolves to `resolve_death_epoch` → close-record
  `ended_at`, which members never have → **transcript mtime**.
- D1 as briefed ("within 30 min before the death epoch") would therefore judge the same death
  differently on the two paths.
- On the live path "now" also admits lead actions taken **after** the member died but before a slow
  watchdog classified it. A real instance is row 1955 (8e5bcdff, inbox-census): last write 05:59:39Z,
  classified 05:59:50Z, then a stale idle_notification at 06:00:15Z and the lead's shutdown_request at
  06:00:19Z. With a watchdog lagging more than 40 s, which is plausible at load 213–623 (measured with
  `uptime` during this review), D1-as-briefed would have painted that no-order death RETIRED.
- **The working copy's anchor is the right one** (mtime capped by the caller's epoch, identical on both
  paths and in the renderer's re-call). Apply it to the order timestamp (§2.1).

### 2.3 Arm (a) SendMessage: risk with no measured benefit

- **Decisive count.** Across the 28 misses, (a) is the deciding source in 0 rows. In cvf-docs the TaskStop
  also matched. Arm (a) decides only in RECYCLE rows (deliberate-teardown), where it merely relabels.
- **Its unique reach.** It is the only arm for a member whose own transcript lacks the request. Per the
  vendor contract (04: delivery only at a turn boundary), that means either a busy member, whose death
  mid-tool the request cannot have caused, or a member that crashed before writing the request.
- **F7 fixture.** A delivered SR 20 s before an unrelated mid-tool death, with no TaskStop and no kill.
  49c14517 prints `1|cvf-docs|…|1|lead-request|1` and paints "✅ RETIRED … stopped by its lead
  (shutdown_request) … MID-TASK" over what is a genuine crash.
- **Refusal veto.** Arm (a) also motivates the `approve:false` veto, and the veto over-reaches.
  - F3 is a member that refuses, a lead that escalates to TaskStop, and a member that dies. It reads
    **CRASH**, because `refused` voids every lead source, the TaskStop included.
  - Fleet-wide there are **0 refusals**: 16 `shutdown_response` tool_uses, all `approve:true`, all
    shaped with both nested and top-level `type` (`survey.py`). So the veto is untested on real data.
  - Dropping (a) as sufficient evidence makes the veto unnecessary. TaskStop is an unambiguous stop
    whatever the member answered.

### 2.4 Scenario table (fixtures, 49c14517 vs order-timestamp variant)

| Fixture | 49c14517 | tf_use | Correct |
|---|---|---|---|
| F1 TaskStop with realistic timing | CRASH (miss) | RETIRED | RETIRED |
| F2 member crashed, lead TaskStops 20 s later | CRASH | CRASH | CRASH ✓ |
| F3 refuse → TaskStop → death | CRASH (miss) | CRASH (miss) | RETIRED (fixed by dropping the veto for TaskStop) |
| F4 refuse → genuine crash 10 min later | CRASH | CRASH | CRASH ✓ |
| F5 TaskStop by internal task id `t5ou0rn4u` | CRASH (miss) | CRASH (miss) | RETIRED (see 2.6) |
| F6 member `docs`, lead stopped/asked `cvf-docs` | CRASH | CRASH | CRASH ✓ |
| F7 SR delivered, unrelated mid-tool death | **RETIRED (false)** | **RETIRED (false)** | CRASH |
| F9 TaskStop of cvf-hooks whose input mentions cvf-docs | CRASH | CRASH | CRASH ✓ |
| F10 member-authored toolUseResult inside the lead tx | CRASH | CRASH | CRASH ✓ |
| F11 bare `kill -TERM` only | CRASH | CRASH | CRASH (by design) |

These attacks fail against D1:
- **Same-name re-spawn.** The generation guard (order ≥ the member's first record) holds, in the WIP
  bats and in my fixtures.
- **Substring names.** `"@cvf-docs".endswith("@docs")` is false, and the task_id test is exact.
- **Forgery.** The member can only reach the lead's toolUseResult by appending raw bytes to another
  session's JSONL, which is the same local-write trust as markers. Member prose in the lead transcript
  arrives as string content with no `toolUseResult`. A Bash or Read result has `stdout`/`file` keys,
  never `request_id`/`task_type`.

### 2.5 Window width

- **Measured lag** from the first lead order to the member's last write (`/tmp/skeptic` lag script):
  - 20 of 26 lead-TaskStop rows: 0.3–0.7 s.
  - Lead-TaskStop maximum: 260 s.
  - Own-source rows: maximum 108 s, median 5.7 s (n=52).
- **What the 30-min window admits.** It is about 7× the maximum observed lag, and it absolves the
  "zombie" case: TaskStop did not kill the process (exactly cvf-docs's state at 18:04:50Z), and the
  orphan then genuinely crashes up to 30 min later.
- **Recommendation.** 600 s covers every observed case with 2.3× margin (estimate from the max lag).

### 2.6 Misses that remain (documented, not fixed by D1)

- **Bare kill of an orphan: 5/28**, all from lead ba08cab8 on 2026-09-14, after SendMessage `success:false`.
  The skill should state that a kill with no successful TaskStop is paged as a crash by design.
- **TaskStop by internal task id: 18 of 166** successful `in_process_teammate` TaskStops (`survey.py`; the
  grep included subagent transcripts, so this is approximate). 0 crash-log deaths are affected, because
  none fell within 30 min after such a stop. The skill already says "bare agent name as task_id"; keep it.
- **Custom team names.** The working copy requires `team.startswith("session-")` even when `config.json`
  could resolve the lead. That is 1 of 430 teams.
- **Classification before the result write.** If the 30 s poll lands between the member's exit and the
  TaskStop result, the result is not on disk yet. Estimated probability ≈ lag / 30 s ≈ ≤2% on the fast
  path. A one-shot re-read after ~15 s, done only when an unanswered TaskStop tool_use for the name sits
  in the window, would close it.
- **Lead roots.** `~/.claude-next4` has its own `projects/` (2 dirs) and is outside the 4 roots
  (negligible). 8 of 403 rows have the lead transcript in a different root from the member, so the
  4-root search is needed.
- **Compaction.** Whether `/compact` ever rewrites the JSONL was **not measured**: none of the 288
  lead-side transcripts contains a `compact_boundary` string.

### 2.7 Cost and timeout inside the bounded Python

- **The lead read is cheap.** The largest lead transcript of the 57 that still exist is 17.4 MB
  (542 lines). A name-filtered pass took 0.05 s (measured).
- **The glob is the cost.** About 17k project dirs per root. Exact lead sid: 1.19 s. sid8 prefix: 2.85 s.
  Miss: 2.09 s (load 213, `globtime.py`). On the 27.6 MB member at load 623, the working copy took
  **5.79 s**, against HEAD's **0.15 s** (`/usr/bin/time`).
- **Why that matters.** It shares the 30 s budget. On a timeout the script prints nothing, `out`
  becomes `0 - - 0 - 0`, and the teammate **loses its identity**: the banner then offers `--resume` for
  a member, which is worse than HEAD.
- **Two cheap fixes.**
  1. Probe `dirname(member_tx)/<leadSessionId>.jsonl` before any glob. The lead is in the same project
     dir for 363 of 403 rows, the same root for 32, and another root for 8.
  2. Write and flush the identity fields before the lead read. Bash keeps partial output from a killed
     child: `out=$(timeout 1 python3 -c '…write;flush;sleep 5')` yields the partial line (tested).

### 2.8 The working copy was being mutated during this review

- The working copy changed while I reviewed it: `49c14517` → `1e488f8b` (drops `not refused`) →
  `88e0b7e6` (drops `task_id == name`, restores the veto) → `ce376e47` (drops the `task_type` check).
  That sequence looks like mutation testing.
- **The bats "someone-else" case cannot kill the `task_id` mutant.** The `name not in line` prefilter
  hides the other member's TaskStop record. F9 can: on `88e0b7e6` it prints `lead-taskstop` for
  cvf-docs from a TaskStop of cvf-hooks.
- Re-review the final diff. This review is against 49c14517.

## 3. Frequency denominators

- **Teammate identification is sound.** Transcript `teamName`+`agentName` agrees 78/78 with the watchdog
  registration post-arm (03). I reused 03's row set, but my HEAD-predicate replay reproduces the logged
  class on all 52 retired rows.
- **The lead-order definition is too loose for D1.** 03 counts tool_use at classification time without
  checking success, and it counts kills. Restated for D1: 23 rows were successful TaskStops misread as
  CRASH and 5 were bare kills. 02's census (TaskStop result joined, 6 of 7 post-arm) is the right
  denominator and agrees with mine.
- **Team-config counting** double-counts the `.claude-next` symlink (430 unique, not 476).
- **Lead lookup across 4 roots is correct.** 03 also scanned `.claude-next4`, with no effect.
- **The false-positive test is thin, and the slots said so only partly.** Of the 9 post-arm teammate
  CRASH rows, only 2 have no lead order at all: 1 jetsam (outranked anyway) and 14ded077. A third,
  a907d47c, is a jetsam with a delivered shutdown. So "flags none of the 9" is close to vacuous. The
  real FP evidence is the 78 pre-arm no-order CRASH rows plus the 8e5bcdff late-lead-action case.
  The amended design flips none of the 80 no-order rows, jetsam included (measured, `use.tsv`).

## 4. What the slots missed

1. **The anchor bug** (§2.1). It decides whether D1 works at all, and it is invisible to the fixtures.
2. **Arm (a) has zero measured benefit** and a demonstrable false-absolution shape (§2.3).
3. **Dirty worktree, and the ✅ glyph.**
   - **The flag is precise.** `mid` (any open tool_use) matched "last conversational record is an open
     tool_use" in 16 of 400 teammate transcripts, with 0 stale orphans.
   - **Mid-call is not dirty.** An idle member with uncommitted edits gets "This pane holds nothing" plus
     an auto-close, and `bin/cc-pane-close:209-212` checks the *lead's* tree.
   - **The glyphs mislead.** The mid-task body still sits under a "✅ RETIRED" headline and a
     "✅ retired" tab title.
   - My answer to the brief's question: **no ✅ for a lead-stopped member that was mid-task or has a
     dirty tree.** Keep class RECYCLE (no desk page; the lead owns it), but use a ⚠ headline and
     title, and never auto-close.
   - **Name the tree.** Find the member's worktree by name: the `git worktree list` path whose basename
     equals the member name (`~/Development/.worktrees/cvf-docs` matches; heuristic, label it). Print
     its dirty count.
4. **Measurability.** "No new cause" means `claude-crashes.jsonl` cannot separate own-source from
   lead-source retirements, so the next audit cannot measure D1's false-absolution rate. Add a
   `retired_source` field to the crash row, or a cause string the same renderer case handles.
5. **Arm order** (consistent with D1, flagged for awareness). Arm 1.4 now runs before 1.5. A
   teammate-idle auto-shutdown that also has a lead TaskStop is relabelled `retired-teammate`; 3 such
   RECYCLE rows in the replay. That is harmless.

## 5. Final recommended design (amended D1)

1. **Lead-side evidence is TaskStop only.**
   - A `TaskStop` tool_use whose `input.task_id == name` (also accept `name@team`), joined by
     `tool_use_id` to a result whose `toolUseResult.task_type == "in_process_teammate"`.
   - The **tool_use** timestamp must be ≥ the member's first record and in
     `[last_write − 600 s, last_write + 2 s]`.
   - `last_write` is the member transcript mtime, capped by the caller's epoch. That is the working
     copy's anchor, unchanged.
   - Load-bearing change, against 49c14517:
     ```python
     stops[b.get("id")] = t                      # remember the ORDER's timestamp
     ...
     if not isinstance(r, dict): continue        # no window test on the result record itself
     ... and inwin(stops.get(b.get("tool_use_id")))   # window the order, not its result
     ```
2. **The SendMessage shutdown_request result is wording only** ("its shutdown_request at <ts> was never
   delivered"), not sufficient evidence. Drop the `approve:false` veto for TaskStop. If the lead keeps
   (a), gate it on `mid == 0` and keep the veto for (a) alone.
3. **Lead-transcript resolution order:** `config.json` `leadSessionId` in any root (custom names
   allowed), then `dirname(member_tx)/<sid>.jsonl`, then the sid8 glob.
4. **Robustness:** flush TEAMMATE/NAME/TEAM/SHUTDOWN before the lead read, so a timeout degrades to
   SOURCE `-`, not "not a teammate". Optionally run a one-shot re-read after ~15 s when an unanswered
   TaskStop for the name sits in the window.
5. **Renderer:** as in the working copy (no "re-spawns members" outside the genuine-crash reopen line).
   For mid-task or a dirty name-matched tree: a ⚠ headline and title, the worktree path and dirty count,
   no auto-close.
6. **Tests to add:**
   - F1 realistic timing: RETIRED.
   - F7 SR-only with a mid-tool death: CRASH.
   - F9 TaskStop of another member whose record mentions this name: CRASH. This kills the `task_id`
     mutant.
   - F2 order after the last write: CRASH.
   - Keep test :102 and the WIP controls.
7. **Out of scope, but real:** the quaternary team scan at :1973; arm 1.5 ignoring `mode` (both already
   in the plan's follow-ups).

**Conviction.**
- About 95% that 49c14517 as snapshotted misses 19 of the 23 reachable rows (measured, not inferred).
- About 85% that the amended design is right. The residual 15%:
  - A member that dies with no exit flush right after a TaskStop would still read CRASH (safe direction;
    not observed: 20 of 26 flushed 0.3–0.7 s after the order).
  - The 600 s window is fitted to 26 + 52 observations.
  - The name-matched worktree heuristic is not validated fleet-wide.

## 6. Deviations

- In my first replay runner I ran `rm -rf "$T"` on six of my own `mktemp -d /tmp/skeptic/home.*` dirs,
  then noticed the brief's no-`rm -r` rule and removed the line. I also ran a single
  `rm -f /tmp/skeptic/slack.done` on a scratch file that did not yet exist. Nothing outside `/tmp/skeptic`
  was touched.
- Scratch writes: `/tmp/skeptic/**` (scripts, fixtures, symlinks to real transcripts, replay TSVs), and
  `/tmp/skeptic-home.UwUKyl` (mktemp HOME). No tracked file and no live store was written.
- `--classify` and `--pane-verdict` ran with HOME, every store, and `CC_PANE_VERDICT=0` /
  `CC_PANE_VERDICT_CLOSE=off` pointed at mktemp dirs. Nothing was painted and no pane was closed.
- `ipt.files` also matched this session's own transcript, which mentions `in_process_teammate`. That
  affects only the approximate 18/166 TaskStop-form count, not any verdict replay.
