# q2a: peak memory of the recovery machinery itself (no claude process)

Date 2026-10-06. macOS 15.7.9, Python 3.11.4, `/bin/bash` 3.2.57, `openrsync` protocol 29.
Tags: MEASURED = I ran it; READ = source or record; INFERRED = derived.
All RSS values are `/usr/bin/time -l` "maximum resident set size" (bytes, shown as MB = bytes / 1e6)
unless a row says `ps rss`. "Footprint" is the same tool's "peak memory footprint" (dirty/anonymous
memory; excludes clean file-backed pages).

## Answer

The machinery costs 45-55 MB peak RSS for under 1 s per rotation on the transcripts the fleet
actually moves (0.5-3.6 MB), about 105 MB on the largest transcript on the box (241 MB), and leaves
about 15 MB resident per rotated session (one bash + one `expect` wrapper). The 23 claude processes
alive at measurement time held 10.57 GB RSS (mean 459 MB each). Machinery memory is 2-3 orders of
magnitude below the claude processes and is not what limits concurrency.

## 1. lr-audit.py

Read-only forms used (READ `lr-audit.py:2204-2240, 2508-2527`): `--ledger-only --transcript F`
(one pass, prints JSON, no pid read, no subprocess: `:2152-2201`) and the full audit with no
`--json/--md/--salvage-dir` plus `--quiet` (the only three write sites are behind those flags).
The full form spawns `bash` (registry + `ps` census, `:396-427`) and `git for-each-ref` (`:1777`);
it was run only against sessions with no registry row (MEASURED: `grep -lE <3 sids> ~/.claude/cc-registry/*.json | wc -l` = 0 of 30 rows),
so its `kill -0` branch (`lr-lib.sh:290`) was never reached.

Transcript population (MEASURED: `find ~/.claude*/projects -maxdepth 2 -name '*.jsonl' -size +1k`, n=5778):
p50 0.51 MB, p90 3.14 MB, p99 15.4 MB, max 241.4 MB.

| Transcript bytes | Mode | Wall s (2 runs) | Peak RSS MB (2 runs) | Footprint MB (2 runs) |
|---|---|---|---|---|
| 450,094 (p50) | `--ledger-only` | 0.06 / 0.05 | 26.3 / 23.8 | 20.8 / 18.3 |
| 3,004,906 (p90) | `--ledger-only` | 0.06 / 0.06 | 25.6 / 26.8 | 20.1 / 21.3 |
| 15,439,348 (p99) | `--ledger-only` | 0.08 / 0.09 | 35.7 / 34.2 | 27.1 / 27.9 |
| 42,273,732 | `--ledger-only` | 0.11 / 0.11 | 44.4 / 36.1 | 26.1 / 24.4 |
| 241,368,760 (max; 4139 lines, longest 1.36 MB) | `--ledger-only` | 0.37 / 0.36 | 52.2 / 72.6 | 25.9 / 30.1 |
| 450,094 (no session dir) | full, `--quiet` | 0.84 / 0.82 | 35.3 / 43.6 | 22.0 / 21.6 |
| 42,273,732 (session dir 2.7 MB) | full, `--quiet` | 1.16 / 1.27 | 64.7 / 60.1 | 36.4 / 33.3 |
| 241,368,760 (session dir 60 MB, 34 files) | full, `--quiet` | 2.43 / 2.02 | 95.2 / 93.1 | 40.6 / 41.5 |
| (baseline) `python3 -c "import json,argparse,glob,hashlib,re,subprocess"` | n/a | 0.04 | 16.3 | 11.4 |

- MEASURED: RSS grows about 2x while the transcript grows 536x (0.45 MB to 241 MB, ledger-only). Footprint stays 18-30 MB.
- READ: this is by construction. `scan_lead_transcript` iterates `for raw in f` and keeps only ids and
  capped strings (`:634-765`, text capped at 200/300 chars `:673,683,727`); `sha256_file` reads 1 MiB
  chunks (`:1797-1802`); `tail_records` reads 128 KiB (`:76, :184-190`). Peak is one line's parsed JSON, so it
  tracks the longest line (1.36 MB), not the file.
- READ: the one production caller in the move path is `lr-handoff.sh:972`, full audit with `--json --md --salvage-dir --quiet`.
  That write path was not run (it writes); its extra memory is the salvage JSON of slots, INFERRED small.
- READ: `lr-ingest-verify.sh:277` uses `--ledger-only`.

## 2. lr-transplant.sh copy

What it copies (READ `lr-transplant.sh:900-915`, and the same block in `--phase confirm` `:463-480`):

| Step | Source line | What | Reads whole file into memory? |
|---|---|---|---|
| `cp -c -p SRC DST \|\| cp -p SRC DST` | `:901`, `:466` | the one `<sid>.jsonl` | No. `-c` is an APFS clone (metadata only) |
| `rsync -a SRC_DIR/SID/ DST_DIR/SID/` | `:904`, `:470` | session dir (subagent transcripts, workflow journals) | No heap read, but openrsync maps the file: RSS tracks the largest file |
| `rsync -a FROM/tasks/LIST/ TO/tasks/LIST/` | `:910`, `:476` | task list dir, only when `--task-list` given | same |
| `shasum -a 256` on SRC and on DST | `:914-915`, `:479-480` | both transcript copies, sequentially | No (streamed) |
| `python3 -c realpath` x2, python heredocs for the lock | `:126-127, :179, :223, :253, :735` | small JSON | No transcript read |

No python `read()` of the transcript anywhere in the file (MEASURED: `grep -n "\.read()\|shutil\|copyfile" lr-transplant.sh` = 0 hits).

Copy primitives on a COPY of the transcript under `/tmp/q2a-mem/` (created and removed by me; one run each):

| Primitive | 241,368,760 B: wall s / RSS MB / footprint MB | 450,094 B: wall s / RSS MB |
|---|---|---|
| `cp -p` (full byte copy, new dst) | 0.07 / 2.6 / 2.4 | 0.01 / 1.7 |
| `cp -c -p` (clone, new dst) | 0.02 / 1.2 / 1.0 | 0.03 / 1.2 |
| `cp -c -p` onto an existing dst | 0.02 / 1.2 / 1.0 | 0.01 / 1.2 |
| `cp -p` overwriting existing dst | 0.06 / 2.4 / 2.2 | 0.01 / 1.8 |
| `shasum -a 256` (run twice per transplant) | 1.48 / 7.4 / 5.1 | 0.03 / 6.5 |
| `rsync -a` of a dir holding one file this size | 4.61 / 253.3 / 11.7 | 0.06 / 11.4 |
| `wc -c` (`lrt_size`) | 0.00 / 1.6 | 0.02 / 1.5 |
| `head -c N \| cmp -s -` (`lrt_stale_retired`, `:312`) | 0.05 / 2.3 | 0.02 / 2.2 |
| `cat A B \| shasum` (`lrt_sha_cat`, fold-stub `:588`) | 6.44 / 7.2 | 0.02 / 6.6 |
| `python3 -c realpath` one-liner | 0.04 / 13.0 | 0.04 / 11.6 |
| `jq -n 1` | 0.00 / 2.4 | 0.02 / 2.8 |

- MEASURED: the transcript copy itself is 1.2-2.6 MB RSS and 0.02-0.07 s at 241 MB. It is flat in file size.
- MEASURED: `rsync -a` is the only step whose RSS scales with file size: 253 MB RSS for a 241 MB file, footprint 11.7 MB.
  INFERRED: the 242 MB gap is clean file-backed mapping, which the kernel can drop without swap. It applies to the
  session dir, not the main transcript. Session dirs of the 7 sessions in batch
  `20261006T060534Z-next3-next2-64630` were 24-120 KB (MEASURED `du -sk`, 3 dirs found of 7; the other 4 have none),
  so in practice rsync runs at about 11 MB.
- MEASURED: `cp -c -p` onto an existing destination returned rc 0 and replaced the content on this macOS
  (`printf` two files, `cp -c -p a b; echo $?` = 0, `cat b` = `a`). The comment at `lr-transplant.sh:465`
  ("clonefile refuses an existing DST, and the plain copy then overwrites it") does not match this run; the
  fallback is harmless either way.
- MEASURED: the heaviest single process in a transplant is a 13 MB `python3 -c` one-liner, not the copy.

## 3. One lr-move-worker.sh bash process

`lr-move-worker.sh` was not run (it types `/exit`). Proxies, both stated as proxies:

| Proxy | n | RSS |
|---|---|---|
| `/bin/bash -c 'sleep 1; :'` under `time -l` (trivial bash) | 2 | 2.0 MB max RSS, 1.4 MB footprint |
| live `/bin/bash …/lr-fire-resume.sh` processes (`ps rss`; sources capacity-admit.sh 114 KB, `lr-fire-resume.sh:611`) | 11 | 3.8-5.7 MB, mean 4.4 MB, sum 48.8 MB |
| live `/bin/bash …/lr-reset-poller.sh` (`ps rss`; sources lr-lib.sh 75 KB, `:158`) | 1 | 5.9 MB |
| live `expect -c …` child of each lr-fire-resume (`ps rss`) | 11 | 8.2-12.5 MB, mean 10.3 MB, sum 112.8 MB |

- READ: the worker sources lr-lib.sh (74.8 KB), lr-move-lib.sh (14.4 KB), lr-recon-fence.sh (19.4 KB) and
  capacity-admit.sh (113.7 KB) (`lr-move-worker.sh:32-40`), 222 KB of function text.
- INFERRED: one idle worker is 5-7 MB RSS (live lr bash processes with one of those libs loaded sit at 3.8-5.9 MB;
  the worker loads all four). Not measured directly.
- READ: its loops are `sleep` polls plus short `jq`/`awk`/`sed` children (`:79-84, :104-115, :122-126, :160-178`); nothing
  accumulates across iterations.
- MEASURED: all 7 sids of batch `20261006T060534Z-…-64630` appear in the argv of the 11 live `lr-fire-resume.sh`
  wrappers (22-27 min old at read time). So a rotated session keeps one bash + one expect resident for its
  lifetime: 14.7 MB mean per session (4.4 + 10.3).

## 4. Sum: machinery memory per rotation

Steps run one after another inside a worker, so the peak is worker + handoff + the largest child, not the sum of children.

| Component | Small (0.45-3.6 MB transcript, session dir <= 120 KB) | Large (241 MB transcript, 60 MB session dir) | Tag |
|---|---|---|---|
| worker bash (resident for the move, 110-180 s) | 5-7 MB | 5-7 MB | INFERRED from live proxies |
| lr-handoff.sh bash (158 KB script + lr-lib) | 5-7 MB | 5-7 MB | INFERRED, same proxy |
| largest transient child: full lr-audit | 35-44 MB for 0.8 s | 93-95 MB for 2.0-2.4 s | MEASURED (n=2 each) |
| transplant children (cp 1-3, shasum 7, python 13, rsync 11) | <= 13 MB | <= 13 MB; rsync up to the largest session-dir file in clean mapped RSS | MEASURED |
| **Peak RSS during the rotation** | **45-58 MB** | **about 105-110 MB** | INFERRED sum |
| **Peak footprint (dirty) during the rotation** | **about 32-36 MB** | **about 51-56 MB** | INFERRED sum |
| Steady state while waiting on the pane | 10-14 MB | 10-14 MB | INFERRED |
| Left resident after the move (fire-resume bash + expect) | 14.7 MB mean | 14.7 MB mean | MEASURED `ps rss`, n=11 pairs |

Scale, same instant (MEASURED `ps -axo rss=,comm=`): 23 claude processes, 10.57 GB RSS total, mean 459 MB, max 879 MB;
swap 2.18 GB used of 3.07 GB. Seven simultaneous small rotations with every audit coinciding would be
about 7 x 58 = 0.4 GB for under 1 s, 0.6% of 64 GiB; the realistic overlap is lower because each audit lasts 0.8 s
of a 110 s actuate (READ `…/1c0f7f90-….events.jsonl`: actuate 1791266828248 to actuated 1791266938292 ms).

## Alternatives considered

- "The audit loads the transcript": rejected. RSS 24-72 MB across a 536x size range; source streams line by line.
- "The copy doubles the transcript in memory or on disk": rejected. Clone, 1.2 MB RSS, 0.02 s.
- "RSS is the wrong metric": partly. For rsync the 253 MB is clean mapped file; footprint (11.7 MB) is the number that
  competes with claude processes for swap. Both are reported.
- "Many workers add up": 11 resident wrapper pairs total 161.7 MB (`ps rss`), 1.5% of the claude processes' RSS.

## Uncertainties

- Worker and lr-handoff bash RSS are proxies; neither was run. Error bound is a few MB.
- The audit's write path (`--salvage-dir`) was not exercised; a session with hundreds of workflow slots would hold more
  per-slot dicts. The largest tested session had 34 session-dir files.
- n=2 per audit row, n=1 per copy row; the 241 MB ledger-only RSS varied 52-73 MB between runs.
- `time -l` RSS for the full audit is the max over python and its reaped children; python is INFERRED to be the largest.
- This slot does not measure what the relaunched claude process costs, nor whether the swap-ceiling admission term
  refuses moves; those decide whether memory binds overall.

## Proposed changes

| Change | Conviction | Note |
|---|---|---|
| Spend no effort reducing machinery memory; it is 45-110 MB transient and 15 MB resident against 459 MB per claude process | 95% | Removes this branch from the plan |
| Any admission term meant to protect memory should count claude processes only; widening `LR_MOVE_SLOTS` costs about 12 MB of machinery per extra concurrent worker plus a sub-second 35-95 MB audit | 80% | Safe as a statement about machinery only; the relaunch cost is another slot's number |
| Correct the comment at `lr-transplant.sh:465`: `cp -c` onto an existing file succeeded on macOS 15.7.9 | 70% | Comment only; behavior on other macOS versions untested |
| Leave `rsync -a` for the session dir as is | 75% | Its file-sized RSS is clean mapped pages and session dirs in real moves were 24-120 KB; replacing it with `cp -c -R` changes merge semantics on the confirm re-copy |

## Left behind

None. `/tmp/q2a-mem/` and its 5 files, `/tmp/q2a-measure.sh`, `/tmp/q2a-sizes.txt`, `/tmp/q2a-a.txt`, `/tmp/q2a-b.txt` were removed (`ls /tmp | grep -c q2a` = 0).
