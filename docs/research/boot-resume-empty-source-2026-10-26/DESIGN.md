# boot-resume after the 2026-10-25 reboot: an empty heartbeat source — design verdict

**Verdict: the fix already exists on trunk and holds on the raw artifacts. Nothing in `scripts/` changes
here; the deliverable is a raw-artifact replay suite that pins it.** Conviction 90% that no further
boot-resume change is needed to restore a cut shaped like 2026-10-25; the residuals in §5 belong to the
incident lead's recovery lane (pane 1, `docs/research/incident-2026-10-25/DESIGN.md` §6 lane E) and were
sent there rather than built a second time.

## 1. What happened

- Boot `kern.boottime` 1792952212 (2026-10-25 13:16:52 CDT). 28 sessions under kitty 1881 wrote shutdown
  tombstones at 13:15:02-07 (`endReason` other, `hostShutdown` false).
- boot-resume at 18:21:21Z: `source heartbeat, reason no-open-sessions, n_open 0`. The heartbeat it took
  (`hb.roster.json` `[]` at 13:09:42, `hb.session.tsv` empty) came from a kitty whose remote control was
  dead since 03:45 (`hb.kitty-ls.json` mtime 03:45, 9.5 h older than the roster).
- Defect 1 (empty-but-present source outranks a 28-row burst) and defect 2 (the heartbeat wrote `[]`
  while session pids were alive) are both root-caused and fixed in the incident's RCA/DESIGN on trunk
  (`docs/research/incident-2026-10-25/RCA.md` R14/R16, `DESIGN.md` C6).

## 2. What trunk already does (landed 2026-10-26 00:23, before this session's research)

| sha | change | covers |
|---|---|---|
| 1e2314fb3 (+fixups 119a4cf33, de0877dbe) | a snapshot older than the shutdown burst is no answer: every burst tombstone newer than it joins, then registry ghosts and the tree's resumed panes | defect 1, any source shape |
| 5dc64d048 | after a LOCKUP_* boot, or when the kitty tree is >2 ticks older than the heartbeat, an empty roster falls through to alarm roster → tombstones → registry | defect 1, the blind-heartbeat signal (axis 2) |
| 80a3797c7 | an ok census naming none of a kitty's sessions keeps the last roster's rows whose pid still runs | defect 2 at write time (axis 3) |
| 809c87f40 | `--kitty-pid` of an earlier boot finds that kitty's last heartbeat; its own newer tombstones join | the kitty-crash / cc-restore path (axis 4) |

That is the reconciliation design this research was converging on (union of sources keyed by session
id, with the per-source join counts in the IDL line: `tomb_joined` / `reg_joined` / `tree_joined`), plus
two independent blindness signals (boot class, tree age). Building a second one would only diverge.

## 3. Replay on the raw bytes — `tests/boot-resume-replay-2026-10-25.bats`

`tests/boot-resume.bats` pins the burst on a shifted, minimized copy (28 tombstones' DETECT fields, a
minimized tree). This suite replays the **unshifted, unminimized** heartbeat dir and tombstones
(`tests/fixtures/boot-resume-2026-10-25/`, mtimes re-applied from `MTIMES.tsv`) at the incident's own
clock (`CC_BOOTTIME_OVERRIDE` / `CC_HB_NOW` = 1792952212), in the shared hermetic env
(`tests/helpers/boot-resume-env.bash`):

| case | trunk (de0877dbe) | pre-fix (0de93a544) |
|---|---|---|
| 1 page mode: count | `source=tombstones n_open=28` | `source=heartbeat n_open=0`, `no-open-sessions` — the live run, reproduced |
| 2 resume mode, stub launcher | 28 of 28 tombstoned sessions launched once | 0 |
| 3 distrust off (`CC_BOOT_RESUME_LOCKUP_DISTRUST=off`) | `source=heartbeat tomb_joined=28 n_open=28` | — |

Finding the minimized fixture could not show: on the real bytes the **tree-age distrust fires first**
(the 03:45 tree), so the tombstones answer as the source and `tomb_joined` is 0. Case 3 switches that
guard off and proves the tombstone join covers the cut by itself — each guard is sufficient alone.

## 4. Rejected

- **A second precedence/union rewrite of `scripts/boot-resume.sh`** — trunk has it (§2); the file is
  owned by lane E.
- **Restoring from `hb.bg.tsv` watcher sids** (a85a7863 was a live watcher at 13:10 but left no
  tombstone or registry row, so trunk reaches 9 of the incident's 10 hand-picked resumes). A watcher row
  proves a `cc-await-ping` was alive, not that its session was; orphan watchers exist. ~60% conviction,
  below the bar to build; sent to lane E as an idea.

## 5. Residuals, sent to the owner (pane 1), not built here

From a read-only ownership census of boot-resume.sh at 0de93a544 (line numbers are that revision's):

1. **A hand-resumed session that is later recycled or ended is not protected from a second start** if
   boot-resume ever re-runs for that boot. No process holds it, so the launcher's holder probe reads 0;
   only a sid-keyed teardown marker newer than its last activity, or a reap record, stops it (retired
   filter, boot-resume.sh:855-895). Of 5 such sessions measured, 1 would be skipped. Today the per-boot
   uuid marker (`same_boot()`, :407-417) stops every re-run for 1792952212 before DETECT, so this needs
   the markers removed by hand to bite.
2. **A burst of `other` ends that is not a shutdown** (the operator closing a kitty window with several
   panes) can be read as the shutdown when it is the last burst before a boot with no SessionEnd. With
   the tree-age distrust making tombstones the source, the "newer than the snapshot" filter no longer
   bounds it.
3. Recycle-successor rung 1 reads `SRC_FILES`, which the tombstone branch never sets (:712-716), so a
   recycled session's successor is found only by rungs 2-3.

## 6. Tests and gates

`bats tests/boot-resume-replay-2026-10-25.bats` → `1..3`, all ok on trunk; RED-proof on a 0de93a544
export (cases 1-2 fail with the live run's numbers). Bare `shellcheck` on the suite: clean.
