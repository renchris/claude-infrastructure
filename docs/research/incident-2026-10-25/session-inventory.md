# Lane: session inventory for recovery (plan only; nothing launched)

Times are local CDT (`/etc/localtime` → America/Chicago). Boot 13:16:52 CDT (epoch 1792952212).
Raw evidence and scripts are in `rca/session-inventory/`. Deliverables: `../sessions.md` (one row per
candidate) and `../resume-plan.tsv` (10 recommended resumes in order).

## Answer first

1. **Boot-resume restored nothing because its first source, the heartbeat, said "nobody was live". It was wrong, and nothing checked it.**
   It took kitty 1881's 13:09:42 heartbeat, whose roster was `[]`. An empty roster that parses counts
   as an answer, so the search stopped before reaching the 13:15 shutdown tombstones (28 sessions) and
   the registry (25 rows for kitty 1881, 13 of their pids alive at 13:11). (Confirmed)
2. **44 claude processes were running at 13:11.** 37 were interactive sessions, 3 were teammates and 4 were headless `claude -p` workers. (Confirmed: each pid is tied to a session id below.)
3. **The real crash path cannot restore them either.** The recorded path, `cc-restore --after-crash --kitty-pid 1881`, reads the same empty roster: a plan-only run returned 0 rows (Confirmed).
   The usable path is the resume-plan TSV piped to `cc-resume-layout.sh --desktops --restore`, run
   with a reconstructed roster beside the 03:45 tree. Three worktrees must come back first.
4. **Only 3 sessions were interrupted mid-task: 502bd860, 501dda01 and 2b3becea.** One more, 3d1dc252, was probably stuck in a tool call that the incident hung. None of the candidates has uncommitted files of its own.
   11 sessions had finished and were only waiting for kitty to close their panes. They should not be resumed.

## 1. Why boot-resume restored nothing this boot

| # | Finding | Label | Evidence |
|---|---|---|---|
| 1 | Boot-resume ran once for this boot at 13:21:21 and abstained with `source=heartbeat`, `reason=no-open-sessions`, `n_open=0`. Every tick after that reads `already-processed`. | Confirmed | `~/.claude/autonomy/idl.jsonl:84574` `{"ts":"2026-10-25T18:21:21Z",...,"boot":"1792952213","mode":"resume","source":"heartbeat",...,"reason":"no-open-sessions","n_open":0}`. `last-boot-epoch`/`last-boot-uuid` are dated 13:21. There is no `events/boot-1792952212/` dir. |
| 2 | Mode was `resume` and `restore-v2` was on, so it *would* have resumed. | Confirmed | `~/.claude/autonomy/boot-resume/mode` = `resume`; `restore-v2` exists (dated Oct 5) |
| 3 | The heartbeat it took was `DBDBC472…/1881` (and `/0`) at 13:09:42. Its `hb.roster.json` = `[]`, `hb.session.tsv` is empty, and `hb.census` = `ok 1792951782`. | Confirmed | file contents. `date -r 1792951782` = 13:09:42 |
| 4 | DETECT treats an empty heartbeat roster as final. Tombstones and the registry are read only when no heartbeat or roster answered. | Confirmed | `scripts/boot-resume.sh:599-603` ("A roster that parses and lists nobody is an answer … so it ends the search"), `:636-676` (heartbeat sets SOURCE), `:698` (`if [ -z "$SOURCE" ]` → tombstones), `:732` (registry) |
| 5 | The correct roster was on disk: 28 shutdown tombstones written 13:15:02–13:15:07, all `kitty_pid 1881`, `hostShutdown:false`, `endReason:other`. | Confirmed | `rca/session-inventory/tombstone-burst.tsv` (28 rows) |
| 6 | The registry still held 25 rows for kitty 1881. 13 of their pids were alive in `ps-prereboot.txt` at 13:11. | Confirmed | `rca/session-inventory/registry-snapshot/` (copied 14:0x, because `cc-sessions` reaps rows 24 h after `startedAt`) |
| 7 | The census (`cc-sessions --json`) read `ok` on every tick from 08:41 to 13:09 (~16 s each), yet each tick left the 1881 roster empty. The heartbeat code proves only that it returned no row with `kitty_pid==1881`. It does not say why. | Confirmed (fact) / Speculative (cause) | `heartbeat/census.log:766-815`. `restore-heartbeat.sh:542-545` filters `kitty_pid == $k`. A 15-16 s census matches the new 15 s bound on the registry-wide `ps`, which commit `19c297766` (08:27, "bound the registry-wide ps …", bin/cc-sessions mtime 08:38) added just before the first `ok`. Candidate causes, none verified: the pane cross-check (`have_panes=1` from a non-empty `it2 session list` that does not contain kitty pane ids), or an lstart mismatch. Reproducing it requires running `cc-sessions`, which deletes registry rows, so it was not run. |
| 8 | Before 08:41 the census failed or overran on every tick from 22:46 to 08:34 (`carried`, census_s 75-77). A carried tick keeps only the rows whose pid it still finds in a `ps` that is itself bounded at 10 s. A carried roster never gains rows: it is refilled only by an `ok` census or by a kitty-tree backfill, and the backfill needs a successful `kitty @ ls` in that tick. | Confirmed (code + log) | `restore-heartbeat.sh:510-525, 547-552, 583-593`, `census.log` |
| 9 | The kitty tree was last read successfully at 03:45. After that, no tick got a `kitty @ ls` answer within 5 s, so the backfill could never put rows back. | Confirmed (mtime) / Likely (cause = kitty not answering remote control) | `hb.kitty-ls.json` mtime 03:45, `hb.start` 13:09. Sessions said the same in their own transcripts: ad0e870f at 04:07 queued a self-close retry, and eeb8db4d at 07:33 had "tried to close itself three times; each time the terminal didn't answer". |
| 10 | No kitty-crash page was ever filed for 1881. On the new boot, `crash_page` scans only `<current boot uuid>/*`. On the old boot, 1881 never died. | Confirmed | `scripts/boot-resume.sh:432-446`. `events/` has no `1881*` entry and no `deaf-1881.paged` |
| 11 | Event (plan-only) mode with `--kitty-pid 1881` looks under the **current** boot uuid and fails with `no-heartbeat` (rc 3). With `--roster-dir <prev boot>/1881` it plans 0 rows. | Confirmed (run, state/IDL redirected to `rca/session-inventory/br-plan/`, all side-effect binaries set to `/usr/bin/false`) | `br-plan/plan-only.out`: "no heartbeat in …/47645ED5…/1881" and "plan … source=heartbeat DBDBC472…/1881 at 13:09:42 … sessions=0 … verdict=planned rows=0" |
| 12 | `worktree-gc-infra` ran at 13:31:06 on the new boot and removed 49 worktrees and 52 branches. The ones that matter here are those of 2b3becea, 58ec5fef, 3f1c1301, 28a7b735, 15f652bd, 9ddc8ad3, cf477fab, eeb8db4d, c162b95c, ba56f290 and 562baac5, all marked "clean · idle · landed on origin/main". It wrote worktree tombstones at 13:32-13:35. | Confirmed | `~/.claude/logs/worktree-gc-infra.log:486-1000`, `~/.claude/autonomy/worktree-tombstones/20261025T183*` |

## 2. lr-select and classifier

- `lr-select --scan --allow-missing-cwd` (default cap 4) picks 28a7b735, 568f7c83, 509e3aad and 58ec5fef. It misses all 3 INTERRUPTED sessions and includes 28a7b735, which had finished and asked for its pane to be closed. (Confirmed: `lr-select.default.tsv`.) Its ranking key is the last internal timestamp, and 11 transcripts got a record at 13:15:0x during shutdown, so that key no longer separates real activity. (Confirmed: `scan.jsonl`, `last_ts` vs `last_real_ts`.)
- `--max-total 40 --max-per-worktree 1` gives 40 winners, 109 listed and 57 filtered (teammates). (`lr-select.max40.*`)
- `cc-resume-classify.py --explain` on the 40: 3 INTERRUPTED (502bd860, 501dda01, 2b3becea), 28 AT-REST, 9 RETIRED, 0 UNKNOWN. The result is the same with the anchor at kern.boottime and at the 13:15:02 tombstone cut. (`classify.max40*.tsv/.explain`)
- One caveat on the classifier. Its 15-minute alive-window assumes the machine was working until the cut. Here, commits stopped at 09:34: the last land on trunk was `ba9e991dc` at 09:32 and the newest branch commit was at 09:34 (Confirmed: `git log origin/main`, `for-each-ref`). A session stuck in a tool call since then therefore reads "mid-turn but stale → AT-REST". 3d1dc252 has had an open tool_use since 09:00, so it is relabelled UNKNOWN (Likely hung by the incident), not AT-REST.

## 3. Live at the cut and not running now

- **Running now:** 1 interactive session (this lane's lead, cf207589, pid 12097) and 4 headless `claude -p` workers under pid 882 `classifier-warm.py serve`. (Confirmed: `ps` at 14:0x.)
- **At 13:11:** 44 claude processes. 37 interactive sessions were tied to a session id: 28 by tombstone, 5 by registry pid (568f7c83, b292a869, dd833573, 87a4411d, ad0e870f), and 4 by the 03:45 kitty tree's process ancestry plus cwd/title (352→a85a7863 Likely, 35888→5f18dd60 Likely, 44564→509e3aad Likely, 61668→2a707a01 Speculative). There were also 3 wt-pool-3 teammates and 4 headless workers under pid 2953 (Xcode Python, up 3d22h; Likely the same classifier pool). No claude process had PPID 1. (Confirmed: `ps-prereboot.txt`.)
- **Last activity:** 11 of the 37 had real transcript activity between 10:00 and 13:15. All 37 are gone after the reboot.

## 4. Ranking (full table: `../sessions.md`)

- **P1, interrupted mid-task (3):**
  - 502bd860 (B13 r27 lead, agent-context-sync)
  - 501dda01 (TrueMemory 2.0 W9 build wave)
  - 2b3becea (USAGE_LEVERS W7+ lead; worktree removed)
- **P2, active in the final hours with an open item (7):**
  - 3d1dc252 (UNKNOWN: probably hung in a tool call)
  - a85a7863 (TrueMemory 2.0 program lead; its own fallback is a fresh session reading `~/Development/claude-private/tm2-plan/recycle-lead-16p.txt`)
  - 58ec5fef (pane 314 rotation lead; worktree removed)
  - 509e3aad (VoiceInk; waiting on the operator's dictations)
  - 568f7c83 (Motion 14 lead; it respawns its 3 teammates)
  - f27965bc (Otto watcher)
  - 3f1c1301 (LKW track A, waiting on its lead; worktree removed)
- **P3, idle with an open operator item (16).** Listed in `rca/session-inventory/resume-plan.optional-p3.tsv`; resume these only on request.
- **P3-close (11):** finished and asked for their pane to be closed (self-close failed because kitty remote control was dead). Do not resume.
- **DNR:**
  - teammates, which their leads respawn
  - headless workers, which tooling relaunched
  - 9 RETIRED sessions
  - lr-select winners that were not running at the cut (ccf42eae, a37a65dd, d2aecafb, 050a764a)

## 5. Recommended command path (operator-run; nothing was fired)

- **Do not use `cc-restore --after-crash --kitty-pid 1881` or `boot-resume --event … --kind crash`.** Both read the empty heartbeat roster and restore 0 sessions (Confirmed, plan-only).
- **Use the skill's "rows from somewhere else" path:** `../resume-plan.tsv` piped to `bin/cc-resume-layout.sh --desktops --restore`.
  On its own, `--restore` cannot place panes by session id, because the 1881 roster is empty (`cc-resume-layout.sh:494, 586-589`), so the sessions would come back in the plain 2x2 layout.
  To replay the recorded arrangement, pass `--tree /Users/chrisren/incident-2026-10-25/rca/session-inventory/reconstructed-hb/1881/hb.kitty-ls.json`. That directory holds the 03:45 tree, the 13:10 displays and a roster rebuilt from the tombstones and registry, with pane→sid for 40 sessions; 4 of those are inferred and flagged `reconstructed`. Review it, then run `--dry-run` first.
- **Three P1/P2 worktrees no longer exist,** and their branches were deleted by the 13:31 GC: `wt-cc-192116-88115`, `wt-cc-225311-6680` and `lkw-scope-floor`.
  `reso-resume-one` first tries `cc-wt-restore` from the worktree tombstone, keyed by sid, which brings the tree back detached at its recorded head (Likely, since tombstones exist for this GC run). Otherwise it refuses with `branch-gone`. If it refuses, recreate each at the same path from `origin/main`; the GC verified that the work had landed. The path matters because the transcript is keyed by cwd.
- **Nudge only the 3 INTERRUPTED rows,** per the skill's Phase 3. Look at 3d1dc252 before nudging it. Do not start the keepalive for anything else.
  Check `claude-accounts` before firing; it was not run here because it can refresh tokens.

## Telemetry gaps

- `hb.roster.json` is overwritten on every tick, so there is no history of when the 1881 roster went empty.
- `census.log` records ok or carried, but not how many rows were returned or why rows were dropped.
- `cc-sessions --json` gives no reason for treating a row as dead (pid, lstart or pane check).
- `ps-prereboot.txt` has `comm` but not `args`, so 4 pids were mapped to sessions by inference.
- DETECT has no cross-check that an empty heartbeat agrees with the shutdown tombstone burst before the boot.
