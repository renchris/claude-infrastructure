# q3b — what a rotation does between "session on A" and "session on B", and what a copy-nothing design could delete

Slot scope: one in-place move traced through `lr-handoff.sh`, `lr-transplant.sh`, `handoff-fire.sh` (recycle) and `lr-fire-resume.sh`; what is copied and how; store layout on this machine; what a shared transcript store would break. Tags: MEASURED (I ran it), READ (source or record), INFERRED.

## Answer

- The transcript is **already copied with zero data bytes**: both copies in a move are APFS clones (`cp -c`), not byte copies, not hardlinks, not symlinks. MEASURED on 7 of 7 moves in batch `20261006T060534Z-next3-next2-64630`.
- The only bytes physically copied are the session dir (`rsync -a`): 0 to 120 KB for those 7 moves; p50 88 KB, p90 61 MB, max 424 MB over 155 past moves.
- Copy-related work is **at most 5 s of a 176 s move** (upper bound from 1-second record timestamps, n=1 traced, same pattern in all 7). A shared store would delete about 10 steps and about 3% of wall time (5 s plus a sub-second fold), and no memory.
- A shared store is **not** a symlink flip: the tooling equates "which store holds the transcript" with "which account owns the session" in 72 grep-matched lines across 11 files, and `lr-transplant.sh:128-131` refuses outright when source and target share a `projects/` directory.
- "Memory is the bottleneck" is not supported by the copy path. What this slot sees binding is waits around the copy (below).

## 1. One in-place move, end to end

Traced move: sid `1c0f7f90`, pane 3, next3 (`~/.claude-tertiary`) to next2 (`~/.claude-secondary`), transcript 2.20 MB (2,307,854 B at confirm), session dir 24 KB. Times are UTC on 2026-10-06, from `move/<batch>/<sid>.events.jsonl`, the bundle's `events.jsonl`, the lock, the tombstone, `stat` and the recycle watcher log.

| UTC | Step | Code | Copies? |
|---|---|---|---|
| 06:07:06.5 | worker spawned; claim, fence, slot, kernel-safety read | `lr-move-worker.sh:70-136` | no |
| 06:07:08.2 | actuate: `lr-handoff.sh --in-place --voluntary --no-prompt --no-replace` | `lr-move-worker.sh:140-152` | no |
| 06:08:16 | git reads, branch rename under git lock, source pid/argv, tier read from transcript; bundle dir minted | `lr-handoff.sh:856-970` | reads transcript once |
| 06:08:17 | `lr-audit.py` writes audit.json, audit.md, salvage/ | `lr-handoff.sh:972-977` | reads transcript |
| 06:08:18 | HANDOFF-CONTEXT.md, git-status, MANIFEST.json | `lr-handoff.sh:981-1135` | reads transcript once |
| 06:08:27-28 | precheck: handoff-fire probe (registry, composer, focus, subagents); swap admission, no token | `lr-handoff.sh:1483-1494` | no |
| 06:08:28-29 | `lr-transplant.sh --phase admit`: lock, clone transcript, rsync session dir, sha256 both sides, tombstone with `phase:admit`, source NOT retired | `lr-handoff.sh:1543-1545`; `lr-transplant.sh:896-964` | **yes** |
| 06:08:29 | launcher script minted in the bundle | `lr-handoff.sh:1595-1711` | no |
| 06:08:37 | `handoff-fire.sh --recycle --transplanted-source --resume-launcher` | `lr-handoff.sh:1822-1890` | no |
| 06:08:41 | detached watcher armed | watcher.json | no |
| 06:08:44 | `lr-transplant.sh --phase confirm`: re-clone, re-rsync, sha256 both sides, tombstone rewritten with `confirm_len`, source renamed to `.jsonl.handed-off`, stale-marker sweep on target | `handoff-fire.sh:16346`; `lr-transplant.sh:414-523` | **yes** |
| 06:08:50 | last read, resume debt opened, `/exit` typed and read back | `handoff-fire.sh:16359-16390` | no |
| 06:08:58 | lr-handoff returns rc 0 (SWITCHED-UNPROVEN) | `lr-handoff.sh:1893-1908` | no |
| ~06:09:03 | source at a shell after 12 s; `--phase fold-stub` appends the stub the exiting source re-created (2,605 B) to both copies | `handoff-fire.sh:9967-9990`; `lr-transplant.sh:564-602` | appends |
| 06:09:16 | watcher types the launcher; `lr-fire-resume.sh`: tombstone verdict, launch lock, no capacity gate (swap), spawn `CLAUDE_CONFIG_DIR=<B> claude --resume <sid>` | `lr-fire-resume.sh:273-367, 455-488, 606, 932, 1118` | no |
| 06:09:21 | READY | bundle events.jsonl | no |
| 06:09:55 | proof-first: `lr_move_verdict` P1-P7 | `lr-move-lib.sh:82-157` | no |
| 06:10:02 | MOVED, `wall_s` 176 | `<sid>.json` | no |

Per-stage seconds for all 7 (MEASURED, jq over the 7 `events.jsonl`):

| Wave | n | spawn to actuate | lr-handoff | actuated to proof | total |
|---|---|---|---|---|---|
| first (slot width 4) | 4 | 1 | 105-110 | 56-61 | 175-176 |
| second | 3 | 167-168 (slot wait) | 16 | 94-190 | 286-385 |

- lr-handoff itself took 16 s uncontended (n=3). The first wave's 105-110 s contains 68 s before the bundle exists; all 4 first-wave bundles were minted in the same second (06:08:16), all 3 second-wave bundles 1 s after actuate. Cause not identified here; it precedes every copy step. INFERRED: a shared wait, not I/O.
- Copy bound: admit sits between the `admitted` state row (06:08:28) and the launcher's birth (06:08:29); confirm sits between watcher armed (06:08:41) and the tombstone ts (06:08:44). At most 2 s + 3 s.

## 2. What is copied, how, how much

| Artifact | Mechanism | Result | Receipt |
|---|---|---|---|
| `<slug>/<sid>.jsonl` | `cp -c -p SRC DST \|\| cp -p SRC DST`, at admit and again at confirm | separate inode, nlink 1, APFS clone (blocks shared until either side appends) | `lr-transplant.sh:466, 901` READ; clone MEASURED below |
| `<slug>/<sid>/` (subagents, workflows, tool results) | `rsync -a`, at admit and again at confirm | real byte copy; source dir is never removed | `lr-transplant.sh:470, 904` READ |
| `tasks/<task-list>/` | `rsync -a`, only when the source had a task list | self-copy on this box: `tasks` is a symlink to `~/.claude/tasks` in every store | `lr-transplant.sh:474-478, 908-912` READ; `ls -la` MEASURED |
| `workflows/scripts/` | `rsync -a` into the bundle | byte copy into `~/.reso/limit-recover/<sid>/bundle-*/` | `lr-handoff.sh:980` READ |
| `file-history/<sid>`, `session-env/<sid>`, `todos` | **not copied** | file-history stays in the source store only | grep of `scripts/limit-recover`, `bin/cc-lr`, `bin/cc-limited`: 0 hits; 2 of 6 checked moved sessions left 12 KB and 564 KB in tertiary, nothing in secondary MEASURED |

Clone evidence (MEASURED):
- Probe in a private temp dir: `cp -c -p src dst` onto an **existing** dst returned rc 0 three times, gave dst a new inode each time (1738253363, 1738263976, 1738344883) and kept the source's birth time; a plain `cp -p` to a new name got birth = copy time. So the `|| cp -p` fallback does not run at confirm on Darwin 24.6. The comment at `lr-transplant.sh:465` ("clonefile refuses an existing DST, and the plain copy then overwrites it") does not match this.
- Real moves: 7 of 7 target transcripts carry the source's birth time (2026-10-01 to 10-05), days before the move. For `1c0f7f90` the target inode (1737555636) is higher than the launcher's (1737554105, born 06:08:29 after admit), so the target file was re-created at confirm, and a file created at 06:08:44 with a birth of 10-01 is a clone. INFERRED from those two measurements.
- All stores and `/tmp` are on one APFS volume (`df`: `/dev/disk3s5`).

Sizes (MEASURED, `stat`/`du`, read-only; MB = bytes / 1,048,576):

| Population | n | Transcript | Session dir |
|---|---|---|---|
| the 7 moves of the batch | 7 | 0.48-3.45 MB, median 1.62 MB | 0-120 KB; 4 of 7 had none |
| every retired source on disk (`*.jsonl.handed-off`, 4 stores) | 155 | p50 2.13 MB, p90 7.28 MB, max 229.78 MB | p50 88 KB, p90 61.4 MB, p99 363.7 MB, max 423.5 MB; files p50 2, p90 137, max 1,361; 110 of 155 non-empty |
| all transcripts modified in 14 days, per store | 346-1,297 | p50 0.41-0.48 MB, p90 1.5-3.2 MB, max 22-40 MB | not measured |

- Reads per move of the whole transcript: about 7 (tier read, audit, last-message read, 2 x sha256 at admit, 2 x at confirm). INFERRED from the code path; for the 2.1 MB median that is about 15 MB of sequential reads.
- Disk left behind per move: the retired transcript (a clone), the source session dir (a true duplicate; 3,824 MB summed over the 155), the tombstone. Disk, not RAM.
- Every one of the 7 sources wrote after confirm: retired size minus `confirm_len` = 2,308 to 3,797 B. The fold step ran in 8 of 8 recycle watcher logs of that window ("folded a re-created source stub ... appended to both copies"). MEASURED.

## 3. Store layout on this machine (`ls -la`, `find -type l`; MEASURED)

| Config dir | `projects/` | `sessions/` | `tasks/`, `todos/` | `file-history/`, `session-env/` | `projects/<slug>/memory` |
|---|---|---|---|---|---|
| `~/.claude` | real (5,941 entries) | real | real | real | 31 symlinks |
| `~/.claude-next` | symlink to `~/.claude/projects` | symlink | symlinks | symlinks | (same store) |
| `~/.claude-secondary` (next2) | real | real | symlinks to `~/.claude` | real | 5,341 symlinks |
| `~/.claude-tertiary` (next3) | real | real | symlinks to `~/.claude` | real | 4,574 symlinks |
| `~/.claude-quaternary` | real | real | symlinks to `~/.claude` | real | 5,291 symlinks |
| `~/.claude-next4` | real, 2 probe slugs only | real, empty | absent | absent | none |

- Transcript stores are per account, except the `~/.claude` / `~/.claude-next` pair, which the code treats as one account behind a mirror (`lr-lib.sh:26-49`, `hooks/handed-off-session-guard.sh:151-158`). READ.
- A config dir with a symlinked `projects/` is in live use: 10 live processes carry `CLAUDE_CONFIG_DIR=~/.claude-next` (`ps -E`, count includes child processes). MEASURED. That shows Claude Code tolerates the symlink; it is not evidence for two different accounts sharing one store.
- next3 = tertiary and next2 = secondary come from the batch's `plan.json`. The names for `~/.claude` and `~/.claude-quaternary` were not verified.

## 4. What breaks if transcripts live in one shared store

| Site | Assumption | Failure with a shared `projects/` |
|---|---|---|
| `lr-transplant.sh:124-131`, inherited by every phase (`:408-409`) | source and target stores differ | every admit, confirm, unconfirm, abort exits 2; `lr-handoff.sh:1546-1551` reports FAILED; `handoff-fire.sh:16346-16351` aborts the recycle |
| `lr-lib.sh:26-49` `lr_config_dirs` | one store per account, deduped by `pwd -P` of `projects/`, first spelling wins | returns only `~/.claude`; every scan attributes every session to `next` (72 grep-matched lines in 11 files: lr-fleet 21, lr-transplant 16, lr-lib 9, lr-upgrade 7, lr-reset-poller 5, lr-handoff 4, lr-ingest-verify 3, lr-submit-probe 2, lr-move-lib 2, cc-lr 2, lr-fire-resume 1; count includes comments) |
| `lr-move-lib.sh:38-47, 128` (P3) | exactly one live transcript, in the target store | location reads `~/.claude`; P3 is 0 for every other target, so a successful move reports FAILED |
| `lr-transplant.sh:497` retire rename; readers `lr-fleet.sh:295-309`, `lr-reset-poller.sh:1038`, `handoff-fire.sh:16311-16317`, `lr-lock.py:126-129` | `.handed-off` in the source store means "left this account" | the rename would retire the only copy; husk detection loses its signal |
| `lr-transplant.sh:358-366, 415-419, 564-602` (stub, fold) | a late source write shows up as a stub beside `.handed-off` | no tripwire: Claude Code appends by path (`handoff-fire.sh:9952-9953` READ; `lsof` on live pid 18222: 46 fds, none a `.jsonl` MEASURED, n=1), so two writers interleave lines in one file |
| `lr-transplant.sh:385-394, 530-557, 608-657` (unconfirm, abort) | the target copy can be moved away as evidence | would move the live source's only transcript |
| `lr-transplant.sh:333-357, 819-867`; `handoff-fire.sh:3376-3394` | custody chain and stale-marker sweep compare stores by `projects/` realpath | all stores share one key: no predecessor found, chain lost; handoff-fire reports "no chain tip ... (a cycle)" |
| `lr-fire-resume.sh:305-310` | "successor gone" = no transcript under the lock's target store | transcript is visible under every dir, so the allow arm never fires (pinned by `tests/lr-resume-tombstone-guard.bats:82`) |
| `lr-ingest-verify.sh:333-337` (C2), `:363-369` (C4) | target copy and source tombstone are separate facts | both fail-closed clauses pass by construction |
| `lr-transplant.sh:222-250`; `lr-fire-resume.sh:445-452` | `<cfg>/sessions/*.json` says which account holds a session | must stay per account (it is, outside the next mirror) |
| tests | per-store model | 62 cases pin it: `lr-transplant.bats` 33, `lr-transplant-custody.bats` 18, `lr-resume-tombstone-guard.bats` 11 |

What survives: `hooks/handed-off-session-guard.sh:157-158` already decides source vs target from `CLAUDE_CONFIG_DIR`, and its same-account branch (`:82-139`) already handles two processes on one transcript by pid. That is the model a shared store would need everywhere.

## 5. Steps a copy-nothing design could delete

| Step | Code | Fires today | Saving |
|---|---|---|---|
| admit clone + rsync + 2 x sha256 | `lr-transplant.sh:900-918` | every move | at most 2 s |
| confirm re-clone + rsync + 2 x sha256 | `:466-484` | every in-place move | at most 3 s |
| retire rename | `:497` | every move | ms |
| fold-stub after exit | `:564-602`; `handoff-fire.sh:9967-9990` | 8 of 8 | under 1 s |
| unconfirm restore, abort evidence filing | `:385-394, 530-557, 608-657` | on held or failed moves | rare |
| stale round-trip set-aside | `:289-357` | round trips only | rare |
| tombstone back-walk for the chain | `:802-880` | lock-less hops | ms |
| same-target completeness check, multiple-copies refusals | `:423-427, 680-705, 757-762` | retries | ms |
| tasks rsync | `:474-478, 908-912` | already a self-copy here | 0 |

Not deletable by any store change: bundle and audit, precheck probe (about 10 s), custody lock, a marker for the prompt guard, launcher, watcher arm, `/exit`, 12 s wait for the shell, `lr-fire-resume` guards, the new process boot (5 s to READY), proof polling (34 s to first proof plus a 5 s stability re-read).

## 6. Memory, as far as this slot can see

- The copy path runs `cp`, `rsync`, `shasum` and short `python3` JSON readers; none holds a transcript in memory by design. Peak RSS was not measured (the timing experiment was denied by the permission system). ESTIMATED small.
- Live `claude` processes: n=21, RSS p50 472 MB, p90 811 MB, max 862 MB, total 10.8 GB on a 64 GiB box (`ps -axo rss=,comm=`, one sample). MEASURED.
- An in-place move starts the target only after the source is at a shell (watcher log), so a session never has two processes.

## 7. Changes I would make

| # | Change | Conviction | Risk |
|---|---|---|---|
| 1 | Keep per-account `projects/` stores; drop "shared or linked transcript store" from W1 as a memory or throughput fix | 88% | none; it forgoes about 3% of wall time |
| 2 | Correct the comment at `lr-transplant.sh:465` to the measured behaviour (re-clone, new inode, fallback not taken) | 90% | comment only |
| 3 | Clone the session dir instead of `rsync -a` (`cp -c -R -p "$SRC_DIR/$SID/." "$DST_DIR/$SID/"`, rsync as fallback) | 60% | merge semantics into an existing dir at confirm; value only above about 60 MB (p90) |
| 4 | Skip the tasks rsync when both `tasks/` resolve to one directory | 80% | negligible value |
| 5 | Carry `file-history/<sid>` with the move, or symlink `file-history` as `tasks` and `todos` already are | 50% | unverified that a resumed session reads it |

## Alternatives considered

- **Symlink every `projects/` to one store.** Rejected: section 4. Probability a plain flip is correct and safe: about 5%.
- **Hardlink the transcript into the target.** Dominated by the clone: same zero bytes, but the retired name would be the live inode and keep growing, which breaks the prefix test (`lr-transplant.sh:304-313`), the stub test and fold-stub's equality checks.
- **Rename the session dir instead of copying.** Zero bytes, but unconfirm and abort need the source dir still in place.

## Uncertainties

- Clone inference rests on birth-time preservation and monotonic APFS inode numbers (probe n=1 per case; 7 of 7 real targets agree), and on the drainer's `cp` being `/bin/cp`.
- `lr-transplant.sh` was not timed in isolation (it writes); the 5 s figure is an upper bound from 1-second timestamps.
- The 68 s before the bundle in the first wave is unexplained here.
- Account names for `~/.claude` and `~/.claude-quaternary` are unverified (reading `accounts.json` was denied; not pursued).
- Whether two different accounts can share one store in Claude Code itself (per-slug `.last-session-id`, cleanup, `session-index.db`) is untested.
- Thinking blocks of one model family are said to be account-bound (`lr-handoff.sh:957-965`); read, not verified; unaffected by how the file gets there.
- Session-dir percentiles come from retired sources, which skew toward heavy recovered sessions.

## Left behind

- `/Users/chrisren/.claude/backups/src__20261006-013643-92841.bak` (56 B): written by the overwrite-guard hook when I rewrote my own probe file in `/tmp`. Under `~/.claude`, so I left it.
- Removed: `/tmp/q3b-cptest-MsB202/` (4 probe files) and `/tmp/q3b-moved-sizes.tsv`.
