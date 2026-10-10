# 03 — Fleet frequency: how often a lead-ordered teammate teardown is logged as a CRASH

Slot: fleet-frequency. Read-only. Every number below was **measured** by the named command unless it says *estimated*.
Helper scripts are in `/tmp/ff/` (`scan.py`, `era.py`, `sig.py`, `sub.py`, `table.py`, `detail.py`, `lead_around.py`). Raw scan output: `/tmp/ff/out.json`.

## Answer

- **Since the RETIRED arm shipped** (deaths on or after 2026-10-01T07:04:19Z, through 2026-10-10T18:12:37Z, about 9.5 days), the scan found **61 lead-ordered teammate teardowns** (deaths with a shutdown_request, TaskStop or kill from the lead in the 30 minutes before).
  - **52 (85%) were caught** as `RECYCLE/retired-teammate`.
  - 2 were caught as `RECYCLE/deliberate-teardown`, through the desk marker.
  - **6 (9.8%) were misclassified `CRASH/abrupt-unknown`**, which is the incident's defect. The incident is one of the 6.
  - 1 more carried a delivered shutdown_request and was labelled `CRASH/jetsam-oom`. That is jetsam outranking the arm by design (adjacent to this defect, not the same thing).
  - For the 59 teardowns that only the teammate arm can catch, the miss rate is **6/59 = 10.2%**. If the jetsam row is counted, it is 7/59.
- **The arm only ever fails one way.** None of the 6 misses has a `shutdown_request` record in the teammate's own transcript.
  - **5 of the 6 leads never sent a shutdown_request at all.** They tore down with `TaskStop`, sometimes followed by `kill -TERM`.
  - Only the incident (cvf-docs) sent one, and it was never delivered because the member was busy.
  - So the dominant pattern is "TaskStop-first teardown", not "undelivered message".
- **Every post-arm teammate CRASH is explained:** 9 rows, 0 genuine-unexplained.
  - 6 misclassified lead teardowns.
  - 1 jetsam row with a delivered shutdown.
  - 1 jetsam row right after the `TeammateIdle` auto-shutdown hook fired.
  - 1 member that died 14 s before its lead was torn down by the desk (collateral).
- **Before the arm** (2026-08-23 to 2026-10-01T05:29Z), all **83** lead-ordered teammate CRASH rows were misclassified, because the arm did not exist yet.
  - Today's arm would catch 61 of them: the shutdown_request is in the member's transcript.
  - **22 would still be missed**: 15 TaskStop-only, plus 7 where a shutdown_request was sent but never reached the member.
- **Same-shape misses over the whole dataset:** 22 + 6 = **28 rows** from 9 distinct leads, 2026-09-10 to 2026-10-10.
- **What the misses cost the operator:** all 6 post-arm misses sent a false "SESSION DEATH" page to the desk. Only the incident also painted a wrong pane verdict ("NOT A CLEAN EXIT … not resumable"); the other 5 panes had already closed.

## Sources and coverage

- **One crash log for the whole fleet.** `~/.claude/logs/claude-crashes.jsonl` is the only crash log.
  - `~/.claude-secondary/logs` and `~/.claude-tertiary/logs` hold only `lr-probe.log`.
  - `~/.claude-quaternary/logs` does not exist.
  - `~/.claude-next/{projects,teams,logs}` are symlinks to `~/.claude`'s directories (`os.path.samefile` printed True for all three).
  - Command: `for r in ~/.claude-*; do … ls $r/logs/claude-crashes.jsonl; done`.
- **Rows:** 5349 rows, 2026-07-23T06:42:32Z to 2026-10-10T18:12:37Z (`wc -l`, plus `scan.py` min/max).
  - 13 rows have non-UUID test sids (`pid-40813`, `bench-x`, …). None of them is a teammate.
- **Transcripts:** the index covers 6164 transcripts across `~/.claude`, `-secondary`, `-tertiary`, `-quaternary` and `-next4`.
  - Rows with a transcript, by month: 2026-07: 0/67; 08: 235/536; 09: 3870/4005; 10: 715/741.
  - Older transcripts have been cleaned up, so teammate detection effectively starts on **2026-08-23**.
- **Post-arm detection agrees across two independent sources.** Of 696 post-arm rows, 78 are teammates by transcript, 78 by the watchdog-log `registered … teammate=<name>@<team>` field (present from 2026-10-01 14:11 local), and they are the same 78.
  - 26 post-arm rows have no transcript. None of them is a registered teammate.
- **Arm deploy time.** `b6bf10c0c` "fix(lead-crash-watchdog): a retired teammate is RETIRED" has committer date 2026-10-01T02:04:19-05:00 = **07:04:19Z**. It reached `main` (the live `~/.claude` symlink farm) in that push.
  - `~/.claude/hooks/lead-crash-watchdog.sh` resolves to `~/Development/claude-infrastructure/hooks/lead-crash-watchdog.sh`.
  - The first `retired-teammate` row is 2026-10-01T21:00:59Z.

## Method (exact)

1. **Teammate test.** Same logic as `teammate_facts`, `hooks/lead-crash-watchdog.sh:340-381`.
   - A row is a teammate if any transcript for its sid has a record with both `teamName` and `agentName`.
   - Otherwise, it is a teammate if the watchdog log registered it with `teammate=`.
   - `own_shutdown` re-implements the arm's evidence test exactly: a `type:user` / `role:user` record whose text contains `<teammate-message` and `"type":"shutdown_request"`, with requestId ending `@<name>`.
2. **Finding the lead.**
   - First try `teams/<team>/config.json` `leadSessionId` under any root.
   - Otherwise, team name `session-<sid8>` maps to every transcript whose sid starts with `<sid8>`, under any root. All 403 teammate rows resolved to at least one lead transcript.
3. **Lead-ordered.** Inside **[death − 30 min, death]**, the lead transcript has an assistant `tool_use` that is one of:
   - `SendMessage` whose input contains `shutdown_request`, with `to`/`recipient` equal to the member name or `*`.
   - `TaskStop` with `task_id` equal to the member name (or `name@…`).
   - `Bash` with `kill`/`pkill`, plus either the row's pid as a word or the string `<name>@`.

   A first pass with a +5 min tolerance after death added one false positive: 8e5bcdff, where the lead's shutdown came 29 s after the death. It is excluded in the final, strict window.
4. Runs:
   ```
   python3 -I /tmp/ff/scan.py > /tmp/ff/out.json      # ~52 s, read-only
   python3 -I /tmp/ff/era.py      # buckets by era × class/cause × lead_ordered × own_shutdown
   python3 -I /tmp/ff/sig.py      # which lead signals, Δ to death
   python3 -I /tmp/ff/sub.py      # sub-buckets for CRASH teammates with no lead order
   python3 -I /tmp/ff/table.py post|pre-miss
   ```
5. **Detector check (recall).** For all 52 `retired-teammate` rows the scanner found the lead's `SendMessage shutdown_request` in the window, 13–93 s before death (median 35 s). The arm's own ground truth and the scanner's lead-side test agree 52/52.

## Results — `era.py` output (strict window)

```
== pre-arm 325 2026-08-23T06:18:52Z 2026-10-01T05:29:42Z
   22 ('CRASH', 'abrupt-unknown', 'lead_ordered', 'no_own_shut')
   58 ('CRASH', 'abrupt-unknown', 'lead_ordered', 'own_shut')
   71 ('CRASH', 'abrupt-unknown', 'no-lead-order', 'no_own_shut')
    3 ('CRASH', 'suspected-oom-large-context', 'lead_ordered', 'own_shut')
    7 ('CRASH', 'suspected-oom-large-context', 'no-lead-order', 'no_own_shut')
    1 ('CRASH', 'suspected-oom-large-context', 'no-lead-order', 'own_shut')
    1 ('RECYCLE', 'clean-exit', 'lead_ordered', 'no_own_shut')
    3 ('RECYCLE', 'clean-exit', 'lead_ordered', 'own_shut')
    4 ('RECYCLE', 'clean-exit', 'no-lead-order', 'no_own_shut')
    7 ('RECYCLE', 'deliberate-teardown', 'lead_ordered', 'no_own_shut')
   22 ('RECYCLE', 'deliberate-teardown', 'lead_ordered', 'own_shut')
  126 ('RECYCLE', 'deliberate-teardown', 'no-lead-order', 'no_own_shut')
  all rows in era: 4653
== post-arm 78 2026-10-01T19:23:43Z 2026-10-10T18:12:37Z
    6 ('CRASH', 'abrupt-unknown', 'lead_ordered', 'no_own_shut')
    1 ('CRASH', 'abrupt-unknown', 'no-lead-order', 'no_own_shut')
    1 ('CRASH', 'jetsam-oom', 'lead_ordered', 'own_shut')
    1 ('CRASH', 'jetsam-oom', 'no-lead-order', 'no_own_shut')
    2 ('RECYCLE', 'deliberate-teardown', 'lead_ordered', 'no_own_shut')
   14 ('RECYCLE', 'deliberate-teardown', 'no-lead-order', 'no_own_shut')
    1 ('RECYCLE', 'deliberate-teardown', 'no-lead-order', 'own_shut')
   52 ('RECYCLE', 'retired-teammate', 'lead_ordered', 'own_shut')
  all rows in era: 696
```

Lead signals for the lead-ordered CRASH rows (`sig.py`):

```
post CRASH/abrupt-unknown no_own_shut: TaskStop 2, TaskStop+kill 3, shutdown_request+TaskStop+kill 1
post CRASH/jetsam-oom    own_shut:     shutdown_request 1
post RECYCLE/retired-teammate own_shut: shutdown_request 47, +TaskStop 3, +TaskStop+kill 2
pre  CRASH/abrupt-unknown no_own_shut: TaskStop 15, shutdown_request+TaskStop+kill 2, shutdown_request+kill 5
pre  CRASH/abrupt-unknown own_shut:    shutdown_request 52, +TaskStop 6
pre  CRASH/suspected-oom  own_shut:    shutdown_request 2, +TaskStop 1
Δ(death − first lead signal): post abrupt-unknown median 40.5 s (10–157); post retired-teammate median 35 s (13–93); pre abrupt-unknown median 28 s (3–279)
```

### Derived rates (post-arm, measured counts; percentages are arithmetic on them)

| quantity | count | rate |
|---|---|---|
| teammate deaths | 78 | — |
| lead-ordered teardowns (any signal ≤30 min before death) | 61 | — |
| caught by RETIRED arm (`retired-teammate`) | 52 | 52/61 = 85.2% |
| caught by desk teardown marker (`deliberate-teardown`) | 2 | 2/61 |
| **misclassified `CRASH/abrupt-unknown`** | **6** | **6/61 = 9.8%** (6/59 = 10.2% of teardowns only the teammate arm can catch) |
| delivered shutdown but `CRASH/jetsam-oom` (jetsam outranks by design, `:548-556`, `:577-579`) | 1 | — |
| teammate CRASH rows total | 9 | misclassified lead teardown = 6/9 |
| teammate CRASH, genuine-unexplained | 0 | — |
| retired-teammate verdicts fired | 52 rows, 12 teams, 2026-10-01T21:00:59Z → 2026-10-10T18:12:37Z | `grep -c '"cause":"retired-teammate"' claude-crashes.jsonl` = 52; `grep -c 'death class=RECYCLE cause=retired-teammate' lead-crash-watchdog.log` = 52 |

*Estimated:* about 0.6 misclassified teammate deaths per day post-arm (6 / 9.46 days). The events cluster by lead: 4 of the 6 come from one lead (4912cb1f, 2026-10-08), so "per teardown wave" is a better unit than "per day".

## Table — post-arm lead-ordered teammate deaths logged CRASH (the misclassified sids)

The jetsam row (line 5310) is included and flagged. The other 6 are the defect.

| crashes.jsonl line | death ts (UTC) | sid | pid | member@team | class/cause | lead signals (time before death) | shutdown_request in teammate transcript | lead transcript (root:sid8) |
|---|---|---|---|---|---|---|---|---|
| 5205 | 2026-10-08T04:18:14Z | `08a7fba0-144b-4095-9e19-f0ce26f6f1c9` | 39958 | p3-vtt@session-4912cb1f | CRASH/abrupt-unknown | TaskStop(-10s) | no | .claude:4912cb1f |
| 5206 | 2026-10-08T04:18:36Z | `cb60df97-a006-4205-a9f7-862e757e18e0` | 79789 | p3-naming@session-4912cb1f | CRASH/abrupt-unknown | TaskStop(-33s) + kill(-22s) | no | .claude:4912cb1f |
| 5213 | 2026-10-08T05:08:39Z | `610544a4-3428-464d-92d0-cbc7c1e1dada` | 56139 | p3-cue@session-4912cb1f | CRASH/abrupt-unknown | TaskStop(-52s) + kill(-39s) | no | .claude:4912cb1f |
| 5215 | 2026-10-08T05:28:53Z | `daabff77-7dc7-4943-b654-3aa4c28483c7` | 57034 | p3-wire@session-4912cb1f | CRASH/abrupt-unknown | TaskStop(-32s) + kill(-1s) | no | .claude:4912cb1f |
| 5310 | 2026-10-10T01:56:07Z | `a907d47c-c544-44df-9554-468cd26bcc09` | 81304 | dwell-cmd@session-78525a5c | CRASH/jetsam-oom | SM-shutdown(-47s) | yes | .claude-quaternary:78525a5c |
| 5344 | 2026-10-10T16:24:08Z | `05271ce9-384c-43c4-ad05-f3fc62096e90` | 39476 | lrsh-c4@session-197b48ee | CRASH/abrupt-unknown | TaskStop(-48s) | no | .claude-quaternary:197b48ee |
| 5348 | 2026-10-10T18:07:03Z | `5b813b72-0d7c-40ab-bf65-40d9ee333fd3` | 23017 | cvf-docs@session-247fdf36 | CRASH/abrupt-unknown | SM-shutdown(-157s) + TaskStop(-142s) + kill(-123s) | no | .claude-quaternary:247fdf36 |

Spot-verified against the lead transcripts (`python3 -I /tmp/ff/lead_around.py <lead.jsonl> <center> <min> <name>`):
- **p3-vtt, p3-naming, p3-lines (one lead).** Lead `4912cb1f` issued `TaskStop` for all three at 04:18:02–03Z.
  - Each result said `"Successfully stopped task … task_type":"in_process_teammate"`.
  - Its own pgrep at 04:18:07Z still printed `p3-naming ALIVE`, `p3-vtt ALIVE`. It then ran `kill -TERM 79789` at 04:18:13Z.
  - p3-cue and p3-wire went the same way: TaskStop first, then a `for p in $(pgrep -f "agent-id p3-cue@") … kill -TERM $p` loop (`RES … killed 56139`).
- **lrsh-c4.** Lead `197b48ee` ran `TaskStop {"task_id":"lrsh-c4"}` at 16:23:19Z ("Successfully stopped task: tfvu511cf … in_process_teammate"). Death row 16:24:08Z.
- **cvf-docs.** Lead `247fdf36`:
  - `SendMessage {"type":"shutdown_request"…}` at 18:04:25.438Z;
  - `TaskStop` at 18:04:40.623Z;
  - `kill -TERM 23017` at 18:04:59.336Z.
  - The teammate's last record is 18:04:26.867Z, and its transcript has no shutdown_request record (`own_shutdown`=no).
- **Watchdog log for all 6** (`grep "watchdog <sid8>" ~/.claude/logs/lead-crash-watchdog.log`):
  - each has `death class=CRASH cause=abrupt-unknown` and exactly one `death page DELIVERED`;
  - only 5b813b72 has `pane verdict PAINTED on ttys019 (pane 200): ⛔ NOT A CLEAN EXIT`;
  - the other five say `pane verdict NOT PAINTED — the pane closed`.
- **For comparison, the 52 retired rows:** 53 `pane verdict NOT PAINTED` lines and 0 death pages.

## Table — pre-arm rows the current arm would STILL miss (same shape: lead-ordered, no shutdown_request in the teammate transcript)

| crashes.jsonl line | death ts (UTC) | sid | pid | member@team | class/cause | lead signals (time before death) | shutdown_request in teammate transcript | lead transcript (root:sid8) |
|---|---|---|---|---|---|---|---|---|
| 1317 | 2026-09-10T08:17:01Z | `b1b03831-e051-49ff-864d-b69f290a5645` | 33705 | b1f7-paneid@session-68d18dc1 | CRASH/abrupt-unknown | SM-shutdown(-267s) + TaskStop(-94s) + kill(-9s) | no | .claude-secondary:68d18dc1 |
| 1644 | 2026-09-14T16:41:13Z | `882d78ad-b9fb-4b97-859d-43b990334521` | 40497 | a7-cleanup@session-ba08cab8 | CRASH/abrupt-unknown | TaskStop(-17s) | no | .claude-quaternary:ba08cab8 |
| 1645 | 2026-09-14T16:41:14Z | `121a7370-a013-48b5-94f3-4b1ddfe58fcb` | 6007 | a2-ollama-params@session-ba08cab8 | CRASH/abrupt-unknown | TaskStop(-18s) | no | .claude-quaternary:ba08cab8 |
| 1646 | 2026-09-14T16:41:21Z | `9fa9d450-614e-4dfd-8734-be4a395c3fbb` | 51358 | a8-adversarial@session-ba08cab8 | CRASH/abrupt-unknown | TaskStop(-25s) | no | .claude-quaternary:ba08cab8 |
| 1647 | 2026-09-14T16:41:22Z | `49f96e26-14a2-4eca-88c4-a0aef0de3728` | 14740 | a4-ladder-order@session-ba08cab8 | CRASH/abrupt-unknown | TaskStop(-26s) | no | .claude-quaternary:ba08cab8 |
| 1655 | 2026-09-14T21:27:49Z | `d3a7ad58-9edc-4c93-a89c-3ec3fd9c19bb` | 94706 | a1-arming-ui@session-ba08cab8 | CRASH/abrupt-unknown | SM-shutdown(-15s) + kill(-10s) | no | .claude-quaternary:ba08cab8 |
| 1656 | 2026-09-14T21:27:53Z | `4220d419-bee8-43f6-a529-8512a5d7a4cc` | 94057 | v3-verify-d11-d13@session-ba08cab8 | CRASH/abrupt-unknown | SM-shutdown(-21s) + kill(-14s) | no | .claude-quaternary:ba08cab8 |
| 1657 | 2026-09-14T21:27:59Z | `354f3621-4426-4993-811a-5bb99493428f` | 97715 | v4-verify-d14-d17@session-ba08cab8 | CRASH/abrupt-unknown | SM-shutdown(-26s) + kill(-20s) | no | .claude-quaternary:ba08cab8 |
| 1658 | 2026-09-14T21:27:59Z | `256525b2-7875-4566-9873-2aa8424fd9bc` | 54996 | v1-verify-d3-d6@session-ba08cab8 | CRASH/abrupt-unknown | SM-shutdown(-28s) + kill(-20s) | no | .claude-quaternary:ba08cab8 |
| 1659 | 2026-09-14T21:28:05Z | `b308c3ad-b51d-4166-ba18-d4d56e3d2d89` | 60787 | v2-verify-d7-d10@session-ba08cab8 | CRASH/abrupt-unknown | SM-shutdown(-34s) + kill(-26s) | no | .claude-quaternary:ba08cab8 |
| 1694 | 2026-09-15T20:37:55Z | `b77270df-25ac-4f22-a49d-52e91afdd6c4` | 35464 | local-apps-2@session-59ed2093 | CRASH/abrupt-unknown | TaskStop(-16s) | no | .claude:59ed2093 |
| 1757 | 2026-09-17T05:14:35Z | `5b5195df-a683-476e-bf06-120649038f2b` | 92898 | A1-openrouter@session-a11fe2dc | CRASH/abrupt-unknown | TaskStop(-3s) | no | .claude-quaternary:a11fe2dc |
| 1758 | 2026-09-17T05:14:37Z | `18ae3ea6-94fa-47a7-bff3-3417ad996eaf` | 43867 | A6-exposure@session-a11fe2dc | CRASH/abrupt-unknown | TaskStop(-5s) | no | .claude-quaternary:a11fe2dc |
| 1759 | 2026-09-17T05:14:40Z | `bd67708e-9f45-42f2-bada-8721122c1c52` | 1321 | A2-cloudflare@session-a11fe2dc | CRASH/abrupt-unknown | TaskStop(-8s) | no | .claude-quaternary:a11fe2dc |
| 1760 | 2026-09-17T05:14:41Z | `f37530b1-49a0-498c-8376-6ada2f4ef346` | 93744 | A10-verify@session-a11fe2dc | CRASH/abrupt-unknown | TaskStop(-8s) | no | .claude-quaternary:a11fe2dc |
| 1761 | 2026-09-17T05:14:46Z | `1cd04b3a-d1b2-4606-9a37-00885154ec53` | 57468 | A7-priorart@session-a11fe2dc | CRASH/abrupt-unknown | TaskStop(-14s) | no | .claude-quaternary:a11fe2dc |
| 1790 | 2026-09-17T23:33:18Z | `a43d1f6a-5a3b-4de1-b184-0deb78617853` | 67606 | hooks-4@session-c2edde7f | CRASH/abrupt-unknown | TaskStop(-4s) | no | .claude-quaternary:c2edde7f |
| 1791 | 2026-09-17T23:33:19Z | `fc6dc04f-102f-43af-a492-bf13f7c9e378` | 68257 | hooks-3@session-c2edde7f | CRASH/abrupt-unknown | TaskStop(-5s) | no | .claude-quaternary:c2edde7f |
| 1792 | 2026-09-17T23:33:20Z | `0ab6158f-ff78-4916-9a5f-687c49f97019` | 69108 | hooks-5@session-c2edde7f | CRASH/abrupt-unknown | TaskStop(-6s) | no | .claude-quaternary:c2edde7f |
| 1793 | 2026-09-17T23:33:27Z | `613d3de5-e8af-410e-853f-9a1322682cf7` | 75874 | hooks-6@session-c2edde7f | CRASH/abrupt-unknown | TaskStop(-13s) | no | .claude-quaternary:c2edde7f |
| 1794 | 2026-09-17T23:33:40Z | `258867a0-ec55-4ce5-9d4d-2bef3715be4c` | 59998 | hooks-2@session-c2edde7f | CRASH/abrupt-unknown | TaskStop(-26s) | no | .claude-quaternary:c2edde7f |
| 4107 | 2026-09-26T18:54:39Z | `d81071ea-2f47-4c99-acf0-96e7c4e2ea48` | 84089 | score@session-3345b730 | CRASH/abrupt-unknown | SM-shutdown(-98s) + TaskStop(-14s) + kill(-8s) | no | .claude-quaternary:3345b730 |

Pre-arm rows that today's arm *would* catch (delivered shutdown_request, logged CRASH only because the arm did not exist): 61. That is 58 `abrupt-unknown` + 3 `suspected-oom-large-context`. They are not tabled here; regenerate them with `python3 -I /tmp/ff/table.py pre-caught`.

## CRASH teammate deaths with NO lead order (`sub.py`)

```
post-arm: 1 TeammateIdle-auto-shutdown-hook (017a9501 w3-p6, labelled jetsam-oom; hook "Idle teammate auto-shutdown" at 06:22:23Z, death 06:23:00Z)
          1 lead-died-within-10min (14ded077 w3-p2: died 2026-10-02T16:13:05Z, its lead 2205cb66 RECYCLE/deliberate-teardown at 16:13:19Z — collateral of a desk teardown of the lead; lead transcript silent since 06:19Z)
pre-arm: 62 TeammateIdle-auto-shutdown-hook   (hooks/teammate-auto-shutdown.sh "continue":false — a hook-ordered self-retirement, also logged CRASH)
          4 lead-died-within-10min (lead CRASH/abrupt-unknown)
          3 lead-died-within-10min (lead RECYCLE/clean-exit)
         10 unexplained: 25885d39 ecbaa32b 40f00a61 7483d281 236ce250 85f2cce7 c9be558b 212692c2 d562369e cac9f716
```

Two adjacent misclassification classes show up here. Neither is the incident's lead-teardown defect, and both are out of scope:
- **Idle auto-shutdown.** 62 pre-arm rows, and 1 post-arm row that jetsam masked. Only one occurs post-arm, so it appears mostly resolved.
- **Collateral death of members when the desk tears down their lead.** 1 post-arm row. The teardown markers are keyed on the lead's sid/pane/pid (`:600-` arm 1.5/1.6), not on its members.

## What this says about the fix (evidence-scoped)

- **The arm's evidence lives on the wrong side.** `retired_teammate` (`hooks/lead-crash-watchdog.sh:383-386`, called at `:556` and `:584`) reads only the member's transcript.
  - In 5 of 6 post-arm misses, and 15 of 22 pre-arm still-missed rows, the lead never sent a shutdown_request. `TaskStop` is the teardown, and it leaves no trace in the member's transcript.
  - In the rest (1 post, 7 pre), the request was sent but not delivered.
- **A lead-side test would have caught all 28 same-shape rows.** That test is: the lead transcript (found via `teams/<team>/config.json` leadSessionId, else `session-<sid8>` prefix) has a `SendMessage shutdown_request`, `TaskStop` or `kill` naming the member or its pid ≤30 min before death. The same test re-identifies all 52 rows the arm already catches.
- **Measured false-positive risk of that test:** 0 among the 9 post-arm teammate CRASH rows. One pre-arm candidate had only a post-death signal and is excluded by the "before death" bound.

## Caveats

- Deaths with no crash-log row are invisible to this scan, for example a member whose watchdog never registered.
  - Post-arm registration agrees 78/78 with transcript detection.
  - Pre-2026-08-23 transcripts are gone, so the pre-arm era undercounts.
- `lead-crash-watchdog.log` contains test-fixture lines (`[watchdog s_ext]`, `s_killed`, …). Counts here come from `claude-crashes.jsonl` with real-UUID sids, and from log lines matched on real sids.
- The 30-min window and the 2026-10-01T07:04:19Z era boundary are choices.
  - Every lead-ordered CRASH found had its first signal 3–279 s before death, so any window ≥5 min gives the same counts.
  - No teammate died between 05:29:42Z and 19:23:43Z on 2026-10-01, so the boundary moves no row.
