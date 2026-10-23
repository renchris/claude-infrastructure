# kitty's 3-hour deaf episode, 2026-10-22, and what it says about the open kitty decisions

**Answer.** The running kitty's open-file soft limit is **2,560**, not the 256 that decision
`1ef91f32a58c` and B8 assume, and today's ~3 h remote-control outage peaked at ~390 descriptors (15% of
that). So it was not fd exhaustion, and the 8192 watcher would not have prevented it. Recommendation on
`1ef91f32a58c`: **No** (its default), conviction **88%**.

## What happened (MEASURED, kalloc plan lead session aad6ea80)

- kitty 0.48.2, pid 1881, started by launchd (ppid 1) 2026-10-21 19:54Z.
- From ~09Z intermittently, and ~13:00Z-~16:30Z continuously, every `kitten @` got `Error: EOF` within
  1 s (`~/.claude/logs/kitty-pane-actions.jsonl`, 14 `kitten-failed` rows; two W4 fires came back outcome
  UNKNOWN with no session). Load was 200-450 on 10 cores.
- During it: `lsof -p 1881` 469 lines, 258 `unix` sockets with no peer path, highest fd number 387.
- It recovered with no restart. The 5-minute heartbeat's `hb.kitty-ls.json` refreshed at 11:35 CDT
  (16:35Z); a fire at ~16:45Z engaged. At 23:xx: 103 numeric fds, 2 unix sockets, 113 zombies.
- `kitten @ … kitten ~/.claude/scripts/lib/kitty-fd-headroom.py get` (getrlimit only):
  `fd_headroom=get pid=1881 soft=2560 hard=unlimited`.

## Decisions

| Packet | Question | Recommendation | Conviction | Why |
|---|---|---|---|---|
| `1ef91f32a58c` | Load a watcher at kitty's next start that raises its open-file limit to 8192? | **No** (= its default) | 88% | Premise refuted: soft limit is 2,560 (B8 §1.7 inferred 256 from `launchctl limit maxfiles`). Today's worst pile-up used ~15% of it, so 8192 buys nothing, and it puts code inside the terminal that hosts every session. 12% left for a fresh `open -a` kitty starting at 256 (unmeasured; the B8 throwaway probe's `get` settles it). |
| `74b9bd774c40` | Upgrade to kitty 0.49.2 at the next start? | not re-researched | unchanged (55) | Today's deafness matches #10632 ("a single unresponsive peer blocking all remote control"), fixed in 0.50.0, not 0.49.2. That leaves 0.49.2's case (zombies, graceful quit) as it was. |
| `1c7000af9e41` | Test an in-kitty App Nap stop on a throwaway kitty? | not re-researched | unchanged (50) | `kitty-hygiene.sh status` reads `key=absent` (App Nap not disabled). A napped main thread under load is a plausible cause of today's deafness, but nothing measured separates it. |

## Consequence outside the packets

`scripts/kitty-hygiene.sh` reports `fds=<n>/256` from an assumed `CC_KH_FD_SOFT=256`. `cc-restore`
stops a second restore round above `CC_RESTORE_FD_MAX=180`, and today's kitty sits at `fds_all=187`. Both
thresholds rest on the refuted 256. Not changed here: whether a FRESH kitty also gets 2,560 is unmeasured
(conviction ~80%), and that gate protects a restore. Measure `get` on the next kitty start before
retuning either. Backlog row `7e912ef257cb` ("raise the running kitty's open-file limit in place") has
the same refuted premise and names a dead pid (853).

## Operator lesson (also in docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md § W4)

A deaf kitty can come back on its own as load falls, and the heartbeat's `hb.kitty-ls.json` mtime shows
it first. If a restart is needed, use `cc-restore --restart-kitty --confirm <pid>`, never ⌘Q plus
`/resume-sessions`, which kills in-flight lands and drops goals and watchers.
