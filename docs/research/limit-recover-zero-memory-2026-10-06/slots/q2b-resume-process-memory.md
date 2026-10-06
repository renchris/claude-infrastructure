# q2b — memory cost of one relaunched `claude --resume`, by transcript size

Date 2026-10-06, macOS Darwin 24.6, 64 GiB. Tags: MEASURED (I ran it), READ (source or record), INFERRED.
All launches were throwaway sessions in a private tmux server (`tmux -L lrzm`), cwd `/tmp/lr-zm-throwaway-1`,
no prompt submitted. n = 1 launch per size.

## Answer

- A resumed session with a transcript up to 5 MB (14 of the 15 live sessions are under 4.1 MB) costs
  **177-197 MB physical footprint steady, 201-254 MB peak**, and is stable in 3-5 s. (MEASURED)
- Cost grows slowly with transcript size: steady footprint about **+1.25 MB per transcript MB**, peak footprint
  about **+2.0 MB per MB**. The largest real transcript on the box (230 MB on disk) costs 465 MB steady, 652 MB
  peak, and is stable in 28-41 s. (MEASURED, slope from the 0.08 MB and 230 MB points)
- `ps rss` overstates this 1.7x-3.5x (327 MB to 1,346 MB for the same processes) because it counts reclaimable
  and file-backed pages. A gate or a budget built on RSS is 2-3x too pessimistic. (MEASURED)
- Ten concurrent resumes of typical sessions peak near 2.5 GB of footprint, about 4% of 64 GiB. Per-process
  memory of the relaunched client does not explain a concurrency of 2. (INFERRED from the table)

## 1. Binary

| Item | Value | Tag |
|---|---|---|
| `command -v claude` | shell function (`claude ()` in the shell snapshot, routes accounts, then `_claude_pinned`) | MEASURED `type claude` |
| On PATH | `/opt/homebrew/bin/claude` -> `claude.exe`, version 2.1.278 | MEASURED `--version` |
| What all 15 live interactive sessions run | `/Users/chrisren/.claude-284/node_modules/.bin/claude`, version 2.1.284 | MEASURED `ps -axo pid,args`, `--version` |
| `~/.local/bin/claude`, `~/.claude/local` | absent | MEASURED `ls` |
| Binary used for every measurement below | the 2.1.284 fleet binary | - |

## 2. Measurements

Launch form (identical except for `--resume <uuid>`):
`tmux -L lrzm -f /dev/null new-session -d -x 200 -y 50 -c /tmp/lr-zm-throwaway-1 env -i HOME USER PATH TERM LANG SHELL DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=~/.claude-secondary <bin> --safe-mode [--resume <uuid>]`.
RSS: `ps -o rss=,%cpu= -p <pid>` every 0.25 s from launch. Footprint: `footprint <pid>` (`phys_footprint`,
`phys_footprint_peak`) at the end of the window; `vmmap --summary` agreed on the fresh run (159.7 M / 167.1 M).

| Session | Transcript bytes (lines) | RSS at end of window | Footprint steady | Footprint peak | Reclaimable (footprint col 3) | Time to RSS within 3% of final | Window |
|---|---|---|---|---|---|---|---|
| fresh, empty | 0 | 295 MB | 160 MB | 167 MB | 43 MB | 5.2 s | 45 s |
| resume small | 81,775 (18) | 327-334 MB | 177 MB | 201 MB | n/r | 3.0 s | 40 s |
| resume 5 MB | 5,238,104 (1,963) | 445-456 MB | 197 MB | 254 MB | 152 MB | 5.4 s | 60 s |
| resume 20 MB | 20,993,349 (1,584) | 424-434 MB | 247 MB | 274 MB | 81 MB | 3.3 s | 75 s |
| resume 40 MB | 42,039,496 (1,973) | 809-829 MB | 236 MB | 372 MB | 478 MB | 16.6 s | 100 s |
| resume 230 MB (largest real) | 241,368,760 (4,139) | 1,314-1,346 MB | 465 MB | 652 MB | 754 MB | 28.1 s (plateau at 41 s) | 300 s |

All rows MEASURED. The RSS range is the sampler's last value and a `ps` reading a few seconds later.

- **Peak vs steady RSS:** RSS rose monotonically and never fell in any run, so peak RSS equals final RSS. The
  transient shows only in footprint (peak minus steady: 7, 24, 57, 27, 136, 187 MB). (MEASURED)
- **230 MB curve:** 79 MB at 0 s, 1,009 MB at 10 s, 1,126 MB at 21 s, 1,285 MB at 31 s, 1,309 MB at 41 s,
  1,314 MB at 300 s. (MEASURED, `m230.csv`)
- **Child processes:** none under any of my six claude pids (`pgrep -P`), as expected under `--safe-mode`.
  (MEASURED)
- **No tokens spent:** the project entry in `~/.claude-secondary/.claude.json` records `lastCost 0`,
  `lastTotalInputTokens 0`, `lastTotalOutputTokens 0`; no spinner on any captured screen. (MEASURED)
- **Transcript shape:** none of the four larger sources has a compact boundary; 37-93% of their bytes are
  `user` records (tool results). Lines over 1 MB: 0, 3, 6, 134. (MEASURED, json parse of each source)
- **Resume writes:** each resume appended to its copy (+350 B, +2,968 B, +1,125 B, +33,063 B, +14,157 B) and
  hard-linked the original's `file-history` entries under the new uuid (0-17 files). (MEASURED, `stat`, `find`)

## 3. Cross-check against live sessions (read-only)

`ps` plus one `top -l 1 -stats pid,mem` sample; session id from `~/.claude*/sessions/<pid>.json`; n = 15 live
interactive sessions running the full fleet config (hooks, MCP, plugins).

| Group | n | Transcript | RSS | top MEM (footprint) | Child-tree RSS |
|---|---|---|---|---|---|
| resumed, small | 10 | 0.5-4.1 MB | 436-801 MB | 165-240 MB | 145-175 MB (1-6 children) |
| fresh | 4 | 0.9-1.5 MB | 683-858 MB | 195-233 MB | 171-208 MB (4-16 children) |
| resumed, large | 1 | 38.5 MB | 843 MB | 280 MB | 13,209 MB (12 children, one heavy job) |

- Live footprints (165-240 MB at 0.5-4.1 MB; 280 MB at 38.5 MB) match the safe-mode numbers (177-197 MB;
  236 MB at 40 MB). `--safe-mode` therefore does not materially understate the main process. (MEASURED)
- The full config adds a child tree of about 145-208 MB RSS per session (MCP servers and hook helpers) that my
  runs do not include. RSS of those children is overstated the same way; their footprint was not measured.
  (MEASURED for RSS, INFERRED for the overstatement)
- Machine state during the runs: 77-78% memory free (`memory_pressure`), swap 2,174-2,182 MB used of 3,072 MB
  (`sysctl vm.swapusage`). (MEASURED)

## 4. What this means for the hypothesis

- Per relaunch, full config, typical transcript: about 0.2-0.25 GB footprint for the client plus up to
  0.15-0.2 GB RSS of children. Seven at once (the size of batch `20261006T060534Z-next3-next2-64630`) is
  about 2.5-3.2 GB, 4-5% of 64 GiB. (INFERRED)
- A move replaces a process that already exists, so the net steady-state change is near zero; the cost is
  the overlap while the old process is still alive. That overlap was not measured here. (INFERRED)
- Swap was 71% used while memory was 77% free. A gate keyed on swap usage can read "tight" on a machine with
  ample free RAM; that gate belongs to another slot and was not examined here. (MEASURED numbers, INFERRED link)

## 5. Deviations and incidents

| What | Why | Effect |
|---|---|---|
| `--safe-mode` on every launch | settings.json carries 10 SessionStart and 7 SessionEnd hooks; a throwaway session would have been registered in the fleet and could have been typed into by the dispatcher | hooks, MCP, plugins, CLAUDE.md not loaded; child tree taken from live sessions instead |
| `env -i` | my shell carries `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_PID` of a real session | none on memory |
| First tmux server started without `-f /dev/null` | oversight | `~/.tmux.conf` has `@continuum-restore 'on'`; the server restored 7 idle zsh panes (sessions `1`, `dev`, `lr-resume-855b332e`, `lr-resume-8843d236`, `lr-resume-8ad3a9d2`) in real project cwds inside my private server. No claude was started in them. I ran `tmux -L lrzm kill-server` about 80 s after start; all 7 pids gone; `~/.local/share/tmux/resurrect/last` still points at the 2026-09-11 file. Every later server used `-f /dev/null`. |
| First fresh launch showed "Auto-updating…" | no `DISABLE_AUTOUPDATER` in the clean env | killed within about 15 s; `find ~/.claude-284 -mmin -10` empty. Later launches set `DISABLE_AUTOUPDATER=1`. |
| Trust dialog answered once (Down, Enter) in my pane | first launch in a new directory | wrote the project entry named below |

## 6. Cleanup

- Killed: tmux sessions `fresh` (twice), `small`, `m5`, `m20`, `m40`, `m230`; the first server whole. Claude
  pids 44209, 17829, 89170, 51276, 6146, 82899, 83190 all gone (`ps -p`). `tmux -L lrzm ls`: no server.
- Removed: the five copied `.jsonl` files (plain `rm`), the empty project dir
  `~/.claude-secondary/projects/-private-tmp-lr-zm-throwaway-1` (`rmdir`), the five
  `~/.claude-secondary/file-history/<my uuid>` dirs (their hard-linked files with `rm`, then `rmdir`),
  `/tmp/lr-zm-top.txt`, the stale socket `/private/tmp/tmux-501/lrzm`.
- Left behind:
  - `/tmp/lr-zm-throwaway-1/` with the raw receipts: `run.sh`, `one.sh`, `sum.py`, and per run `*.csv`,
    `*.meta`, `*.screen`, `*.uuid`, `m230.out` (27 files).
  - The key `projects["/private/tmp/lr-zm-throwaway-1"]` in `/Users/chrisren/.claude-secondary/.claude.json`
    (trust accepted, last-session stats). Not removed: editing that file is outside the brief.
- A `find` for my five uuids and `lr-zm-throwaway` under `~/.claude` and `~/.claude-secondary` (depth 3)
  returns nothing. Not checked: whether a fleet indexer recorded the throwaway transcripts while they existed.

## 7. Alternatives considered

- Launch with the full fleet config for fidelity: rejected, hooks would register and possibly prompt the
  session; replaced by the read-only live-session cross-check.
- `--bare`: rejected, it switches auth to API key only.
- `vmmap` on live sessions: not used, it suspends the target. Live footprint came from `top`.

## 8. Uncertainties

- n = 1 per size; run-to-run variance not measured.
- Size on disk is a weak predictor: the 20 MB transcript used less RSS than the 5 MB one. None of the samples
  was compacted, so a compacted transcript of the same size may load less.
- Footprint of the MCP and hook children of a full-config session was not measured, only their RSS.
- Time to stable was measured with at most one launch at a time; it will lengthen under concurrent launches.
- The `%cpu` column from `ps` is a decaying average and was not used for any time-to-stable figure.
