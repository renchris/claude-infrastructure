# S07: a census for the limit-recover reconciler that does not shell out to ps

Slot S07-ps-free-census · 2026-10-25 ~02:05-02:30 CDT · load 597-624 on 10 cores (measured by `uptime` and `os.getloadavg()` in each script).
Read-only. I changed no repo file. Scratch scripts are in `/tmp/mtam/S07-ps-free-census/` (bench.py, diag.py, diag2.py, pidpath.py, count_events.py, tel_ps.py, xcheck.py, off.c, vis.py) along with their outputs (run1-noPS.txt, run2-withPS.txt).
I ran exactly **one** full `/bin/ps -ax` scan, inside bench.py run 2. Its output stayed in memory and only counts were printed. No argv or env content was printed or written anywhere.

## Answer in one paragraph

The census needs six fields: pid, ppid, the zombie bit of `stat`, lstart, full args (rendered the way ps renders them), and the tty name.
**One in-process `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)` call supplies everything except args and the tty name. It took 3.3 ms for 2167 rows at load 624, needs no task port, reads no target memory, and has no same-uid check.**
That last point matters. The pane roots are root-owned `login` processes (30 of 30, all children of kitty 1881). `proc_pidinfo(PROC_PIDTBSDINFO)` returns EPERM for them, so it cannot supply the pane-root lstart and tty that pane identity compares.
The tty name comes from a `/dev/tty*` `st_rdev` map: 0.7 ms per scan, against 36-56 ms for `devname()` on 48 distinct devices.
Args come from `KERN_PROCARGS2`. That is the one call that reads the target's VM, so it shares ps's stall path. It must run off the loop thread, under a per-call deadline, claude-family processes first. Those cost 9 ms total for 93 processes; reading every same-uid process costs 0.4-0.63 s.
ps stalls because it is setuid root with `com.apple.system-task-ports.read` and calls `task_read_for_pid`, `task_info`, `mach_vm_region`, `task_threads` and `thread_info` on **every** process of every uid (about 2200 processes and 6600 threads), even for `-o pid=,tty=`.
There is a natural experiment. During the 15-pass blind streak, the daemon's own in-process thread census (proc_listallpids plus PROC_PIDLISTTHREADS/THREADINFO over about 2200 pids) finished in **21 ms and 36 ms wall** while every ps call timed out at 42 s.
The log figures check out: **92 "ps degraded" abstains** in `events.jsonl` (plus 5 more in the rotated `.1`, 97 in all), and **15 blind passes** from 22:43:18 (start of the first pass) to 22:56:03 CDT on 2026-10-24.

---

## 1. Fields the census consumers need, and who uses each

The source is `/bin/ps -axww -o pid=,ppid=,stat=,lstart=,args=` plus `/bin/ps -axo pid=,tty=`, read in `scripts/limit-recover/lr_recon/observe.py:161-202`. The rows are parsed into `T.ProcRow(pid, ppid, stat, lstart, args)` (`lr_recon/types.py:409-424`) and `ttys: Dict[int,str]`.

| Field | Consumers (file:line) | What they need |
|---|---|---|
| **pid** | every map key: `snap.procs` and `ttys` (observe.py:805), `live()`/`live_as()` (observe_rows.py:63-89) | exact pid |
| **ppid** | `ancestors()` (observe_rows.py:204-215), which `kitty_of`, `bind`/`bind_src` (pane binding by ppid chain, observe_rows.py:349-380), `env_pane` (observe.py:574), `bg_host_pid` (≤4 up), `resume_leaves` (wrapper elimination) and `telemetry._under_bats` (telemetry.py:249) all build on; `children_map` (observe_rows.py:196) → `bg_work_for`, `descendants`, `telemetry` kids (telemetry.py:577); `__main__._unowned_zombies` (`r.ppid == me`, __main__.py:2649); `act.claim_holder_for` (`snap.procs[w.pid].ppid != me[0]`, act.py:721) | exact ppid, **including root-owned rows** (the chain claude → shell → `login`(root) → kitty) |
| **stat** | **only** `ProcRow.zombie = stat.startswith("Z")` (types.py:420). No other `.stat` read exists (`grep -n "\.stat\b" lr_recon/*.py`). Zombie is used by `live`, `children_map`, `resume_leaves`, `claude_count` (observe.py:991), `_unowned_zombies`, `act.adopt` (act.py:459), `evidence._argv_live`, `census.live_members`, `settle` (1174), `telemetry` (583), `Snapshot.alive` (types.py:676) | the Z letter only, i.e. `p_stat == SZOMB` |
| **lstart** (UTC, LC_ALL=C, spaces collapsed, e.g. `Wed Oct 21 21:29:30 2026`) | identity `(pid, lstart)`: `Snapshot.alive` (types.py:676), `live_as` against registry `lstart` / session `procStart` (observe_rows.py:76), `holders_for` key, `PaneObs.kitty_lstart` / `root_lstart` (observe.py:289,316,733,736), `evidence._tty_present` and `_identity_match` (`pane.root_lstart == ident.root_lstart`, evidence.py:134-153), `act.adopt`/`self_ident`, `fence` alive, `settle` 1182 and `__main__` 2290 (`_lstart_epoch`), telemetry ages | **byte-identical to the strings already persisted in records.** It is needed for **root-owned pane roots (`login`)** too |
| **args** (full, `-ww`) | `argv0()` → `is_claude`, kitty detection (`kitty_sockets` observe.py:226, `kitty_of`, `env_pane`), `SHELLS` root_shape; `resume_sid` over every non-`NOT_A_SESSION` row (observe_rows.py:262-280); `act.adopt` (`--record-id X`, `__recycle`, `_WRAPPER_TOK` act.py:100); `census.is_member_argv` (`--parent-session-id`); `bg_host_pid` (` daemon run `, `--spawned-by {"pid":N}`); `bg_work_for` (`shell-snapshots`, the cwd probe, `cc-await-ping`, `ship-land`, `tail`); `evidence._argv_live`; `settle` (`lr-fire-resume` + sid); `telemetry.role_of` (`lr-recon-act --record-id`, script names, `_hosts_session`); `_unowned_zombies` detail text | **the same tokenization ps gives.** ps applies `strvis(VIS_TAB\|VIS_NL\|VIS_NOSLASH)`, so a newline inside an owed prompt in claude's argv becomes a non-whitespace escape and stays glued to its token. Raw argv would split there under `args.split()` and could surface a `--resume <sid>` that sits inside prompt text |
| **tty** | `PaneObs.tty` (observe.py:314,734) → record identity tty; `env_pane` refuses a window root with no tty (observe.py:581). That root is the root-owned `login`; `snap.ttys` (set of names, observe.py:806) → `evidence._tty_present` (139) | the name, e.g. `ttys003`, for **root-owned** window roots |

Other ps callers in the same daemon could use the same module: `read_ps_env` (`ps -E`, observe.py:527-543, KITTY_* env), `kitty_band` (`ps -M`, observe.py:597; `band.main_thread` already does this in-process), `store.proc_lstart` ps fallback (store.py:637), `act.py:809` (`ps -o command= -p`), `fence.py:150` (`ps -o <field>= -p`).

## 2. In-process macOS source for each field

Offsets were measured with clang `offsetof` (`/tmp/mtam/S07-ps-free-census/off.c`) on Darwin 24.6.0 (24H32):
```
sizeof kinfo_proc 648 extern_proc 296 eproc 352
p_starttime 0 p_flag 32 p_stat 36 p_pid 40 p_comm 243
e_ppid 560 e_tdev 572 e_pgid 564 e_ucred.cr_uid 420 e_pcred.p_ruid 392 e_flag 612
proc_bsdinfo 136 ppid 16 status 4 comm 48 name 64 e_tdev 108 start 120 uid 20
proc_bsdshortinfo 64 ppid 4 status 12 comm 16 uid 36
PROC_PIDT_SHORTBSDINFO 13 PROC_PIDTBSDINFO 3 PROC_ALL_PIDS 1 SZOMB 5
```
(store.py's `BSDInfo` layout agrees: tdev = `v[3]` at 108, sec at 120.)

| Field | Primary source (recommended) | Fallback | Notes |
|---|---|---|---|
| pid, ppid, zombie, start, tdev, comm, uid, p_flag | **`sysctl {CTL_KERN=1, KERN_PROC=14, KERN_PROC_ALL=0}`**: one call, 648-byte `kinfo_proc` rows | `proc_listallpids` + `proc_pidinfo(PROC_PIDTBSDINFO, arg=1)`; on EPERM, `PROC_PIDT_SHORTBSDINFO` (arg=1) | XNU `sysctl_prochandle` walks `PROC_ALLPROCLIST\|PROC_ZOMBPROCLIST` and fills from proc fields and credentials. Its only lock is the session lock; it does not touch the task or vm_map (kern_sysctl.c, via WebFetch). It has **no uid check**. `PROC_PIDTBSDINFO` **requires same uid** (proc_info.c: only SHORTBSDINFO, UNIQIDENTIFIERINFO, PATHINFO, COALITIONINFO and PLATFORMINFO skip `CHECK_SAME_USER`). SHORTBSDINFO has **no start time and no tdev**. `arg=1` is needed to see zombies (`findzomb` only when `arg != 0`) |
| stat | `p_stat` (`SZOMB=5` → "Z", `SSTOP=4` → "T", else "S") | the same from bsdinfo `pbi_status` | ps's other letters come from Mach thread states, which nothing consumes |
| lstart | `p_starttime.tv_sec` → `store.lstart_text()` | `pbi_start_tvsec`; single pid via `sysctl {1,14,KERN_PROC_PID=1,pid}` (no uid check) | the same `p->p_start` field in both XNU paths |
| tty name | `e_tdev` → map built from `os.scandir("/dev")` `tty*` entries' `st_rdev`, rebuilt when an unknown tdev appears | libc `devname(dev, S_IFCHR)` via ctypes | NODEV = 0xFFFFFFFF; ps prints `??` |
| args | `sysctl {1, KERN_PROCARGS2=49, pid}` with buffer `kern.argmax`: argc, exec path, NUL padding, argv, env | `(comm)` like ps, but **never for a claude-family row** (see the fail-closed rule) | XNU `sysctl_procargsx`: same uid or root, else **EINVAL**. It then takes a task reference and `get_task_map_reference`, `vm_map_copyin` from the target's map at its `user_stack`, then `vm_map_copy_overwrite` and copyout (kern_sysctl.c, via WebFetch). **This touches the target's VM.** The env block is present for a same-uid target that is not cs_restricted |
| exec path | `proc_pidpath` (no same-user check) | | measured 11.3 ms for 2153 pids, 1862 ok; the failures are about the zombie count |
| ps-identical args rendering | follow ps `getproclline`: NULs → spaces over argc strings, skip the exec path and its NUL padding, strip leading spaces, then libc `strvis(dst, src, VIS_TAB\|VIS_NL\|VIS_NOSLASH)` via ctypes; a zombie renders `<defunct>`; unreadable renders `(comm)` | | adv_cmds ps/print.c (WebFetch): `strvis(vis_args, cmd, VIS_TAB \| VIS_NL \| VIS_NOSLASH)`; fallback `"(%s)", p_comm`; zombies `"<defunct>"`. vis.h flags: TAB 0x08, NL 0x10, NOSLASH 0x40. libc `strvis` is callable from ctypes (vis.py: `'a\tb\nc'` → `'a\\011b\\012c'`) |

## 3. Why ps stalls, and which in-process calls share that path

**What `/bin/ps` does** (measured on this machine):
- `ls -la /bin/ps` → `-rwsr-xr-x root wheel` (**setuid root**). `codesign -d --entitlements - /bin/ps` → `com.apple.system-task-ports.read`, `com.apple.private.persona-mgmt`.
- `nm -u /bin/ps` imports `_task_read_for_pid _task_info _task_threads _thread_info _mach_vm_region _vm_deallocate _sysctl _proc_pidinfo _devname _strvis`.
- adv_cmds `ps/tasks.c get_task_info()` (WebFetch) runs per process: `task_read_for_pid`; `task_info(TASK_BASIC_INFO)`; `mach_vm_region(...VM_REGION_BASIC_INFO...)` on the **target's map**; `task_info(TASK_THREAD_TIMES_INFO)`; `task_info(TASK_SCHED_*)`; `task_threads` (a send right for each thread); `thread_info` ×2 per thread.
- `ps.c` calls `get_task_info` for every kept process under `#if defined(__APPLE__) && !PS_ENTITLEMENT_ENFORCED`, and that call does **not depend on the output format**. So `ps -axo pid=,tty=` also does every task call. That explains the 19 abstains on the *tty* call (§5).
- Because ps runs as root, it does this for **every uid's processes**: about 2200 processes and about 6600 threads (telemetry `box.thr` = 6630 at 02:09:47). The args column then adds `KERN_PROCARGS2` (target vm_map copyin plus page faults) per process.

**Why it hangs rather than just running slowly (inference, medium confidence):**
- Today, at load 621, one full scan took **1.47 s** (bench.py run 2, `E_ps_wall_s = 1.47`). CPU starvation alone does not account for 42 s.
- `events.jsonl` 2026-10-24 22:56:03 CDT: `orphan-backlog: "16 killed children not yet reaped (a kernel stall?); oldest argv /bin/ps -axww -o"`. A SIGKILLed ps that does not exit is a thread blocked in a non-abortable kernel wait.
- `vm_map` lock waits (lck_rw) and page-in or decompression of the target's pages under memory pressure are such waits. Both are on ps's per-target path: `mach_vm_region`, `KERN_PROCARGS2`, `task_threads` on a task in exec or exit.
- Which target blocked is unknown. It may be a root or other-uid process that an unprivileged in-process reader never touches.

**Which calls touch what:**

| Call | Proc table | Task (lock/ref) | Target vm_map / pages | Same-uid needed |
|---|---|---|---|---|
| `proc_listallpids` | proc_list_lock | no | no | no |
| `sysctl KERN_PROC_ALL` / `KERN_PROC_PID` | proc_iterate, session lock | no | no | no |
| `proc_pidinfo PROC_PIDTBSDINFO` | proc ref, session lock | reads task flags (`task_has_tpro`, darwinbg state); no task_reference | no | **yes** |
| `PROC_PIDT_SHORTBSDINFO` | proc ref | darwinbg only | no | no |
| `proc_pidpath` | vnode path | no | no | no |
| `PROC_PIDLISTTHREADS` / `THREADINFO` (band.py) | | task threads | no | yes |
| **`KERN_PROCARGS2`** | proc ref, dropped "because we're about to block" | task_reference | **yes: vm_map_copyin of the target's stack args** | yes (EINVAL otherwise) |
| ps's `task_read_for_pid` / `mach_vm_region` / `task_threads` | | **yes** | **yes (mach_vm_region)** | root (setuid) |

**Natural experiment (measured, `telemetry.jsonl`).** During the 15-pass blind streak, the daemon's in-process `box` census (band.py `runnable_by_base`: proc_listallpids plus PROC_PIDLISTTHREADS plus PROC_PIDTHREADINFO for every readable pid) ran twice. Its `cost` field is **wall** time (`telemetry.py:724-729`: `self.mono() - w0`).
- 22:47:04 CDT, seq 43990, l1 722.4: `procs 1604 of 2194, cost 0.021` s. In the same pass ps:all was `[1, 42.01, 42.01, 1]` (timed out).
- 22:52:33 CDT, seq 43997, l1 639.5: `procs 1656 of 2275, cost 0.036` s, while ps timed out at 42.01 s.
- Across all 1241 box rows (Oct 20 21:30 → Oct 25 02:11): wall p50 12 ms, p99 31 ms, max 60 ms; 1 partial; l1 max 1023.2.

So task-level proc_pidinfo reads on same-uid processes did not stall while ps did. **Not measured:** `KERN_PROCARGS2` during a stall. No in-process args reader existed then, and no stall was in progress during this run. It must be assumed able to block.

## 4. Micro-benchmark (bench.py, `timeout 60 python3 -I`, at the load shown)

Command: `cd /tmp && timeout 60 python3 -I /tmp/mtam/S07-ps-free-census/bench.py --no-ps` (run 1), then the same without `--no-ps` (run 2, the single ps scan). All numbers below are measured, `time.perf_counter_ns` around each call.

Run 1 (load 624.2):
```
A_claude_args.pids = 2166          list_ms = 0.96
A_claude_args.bsd_total_ms = 5.69  bsd_per_pid = n=2166 total=5.2ms p50=1.9us p99=4.6us max=0.1ms
A_claude_args.bsd_src = {'tbsd': 1640, 'short': 526, 'none': 0}   bsd_errnos = {1(EPERM): 526}
A_claude_args.zombies = 289        tty_resolve_ms (devname) = 36.45  distinct_tdev = 48  with_tty = 362
A_claude_args.args_per_call = n=93 total=8.8ms p50=71.1us p99=324.1us max=0.3ms  args_fail = 0
A.comm_claude_like = {'claude': 0, 'claude.exe': 42, 'node': 51}
B_kern_proc_all_ms = 3.32   B_kern_proc_all_rows = 2167
B_vs_A_common = 2157  B_vs_A_mismatch = {'ppid': 0, 'zomb': 0, 'sec': 0, 'tdev': 0}
B_other_uid_rows_with_start = 526      (KERN_PROC_ALL gives start for every EPERM row)
C_all_args.args_per_call = n=1607 total=403.7ms p50=87.4us p99=3472.5us max=31.9ms  args_fail = 9
D_dev_scan_ms = 0.69  D_dev_scan_entries = 180  D_devname_vs_devscan_disagree = 0
wall_s = 0.53
```
Run 2 (load 620.9), with one ps scan and a parity check against an in-process read taken right after:
```
E_ps_wall_s = 1.47  E_ps_rc = 0  E_ps_rows = 2199
F_after_ps.bsd_total_ms = 6.76
F_after_ps.args_per_call = n=1612 total=633.3ms p50=74.0us p99=6524.8us max=127.8ms  args_fail = 18
E_only_ps = 75  E_only_inproc = 48  E_common = 2124        (pid churn over the ~1.5 s between reads)
E_mismatch = {'ppid': 0, 'zomb': 0, 'lstart': 0, 'lstart_unknown': 529, 'tty': 30, 'args': 168,
              'args_unread': 270, 'args_unread_other_uid': 270}
E_claude_argv0_ps_vs_inproc = (41, 41)
E_args_mismatch_kinds = {'vis_or_nonascii': 144, 'other': 24}
```
Explaining the mismatches without a second ps scan (diag.py and diag2.py, measured):
- `tty 30`: KERN_PROC_ALL shows 31 other-uid rows with a controlling tty, `[('login', 30), ('remoted', 1)]`. The 30 `login` processes are all children of kitty 1881 (the only kitty), and their children are `bash` ×20 and `zsh` ×10. **They are the kitty window roots, and they are root-owned.** TBSDINFO returns EPERM, and SHORTBSDINFO carries no tdev or start. **KERN_PROC_ALL has both** (`B_other_uid_rows_with_start = 526`).
- `lstart_unknown 529`: the same other-uid rows. lstart over the 1595 same-uid common rows had 0 mismatches against ps.
- `args 168`: 168 in-process rows have empty argv elements and 149 contain a tab or newline; ps vis-encodes those. The rendering must follow ps's (§2). The 24 "other" mismatches are not explained. Candidates are ps's leading-space strip and the empty-element handling, or an exec in the 1.5 s between reads. Unverified, because a second ps scan was not allowed.
- `args_unread 270`: all other-uid (EINVAL by design). No consumer needs root argv except `argv0` on the `login` roots, which `comm` and `proc_pidpath` give.
- Zombies: 294 at diag time, **286 of them children of kitty 1881**. kitty is not reaping, which is a separate kitty-health signal.

pidpath.py (load 596.7): `proc_pidpath` over 2153 pids took 11.3 ms (max 2.75 ms). `KERN_PROC_PID` once per pid over all pids took 366.6 ms (max 15.23 ms). Use it only for single-pid lookups, not for the table.

## 5. ps-degraded events and blind passes, from the reconciler's own logs

Logs: `~/.reso/limit-recover/recon/events.jsonl` (28827 lines, 2026-10-05 13:08:15 → 2026-10-24 22:56:03 CDT), `events.jsonl.1` (50223 lines, 2026-09-30 02:09:50 → 2026-10-05 13:07:53 CDT), and `telemetry.jsonl` (2026-10-20 21:30:58 → 2026-10-25 02:11). The path comes from `types.Paths.from_env`: `$HOME/.reso/limit-recover/recon`. Counted by `count_events.py`, `tel_ps.py` and `xcheck.py`.

- **events.jsonl: 93 `abstain` events, 92 of them `ps degraded`. This confirms 92 for this file's window.** The other one is "claude procs fell from 26 to 4" (Oct 21 14:00).
  - On the args call: 73 (35 single timeout, 20 "timed out; timed out", 18 "timed out; ps budget spent").
  - On the tty call: 19 (15 + 2 + 1 + 1).
- events.jsonl.1 adds **5 more** ps-degraded abstains (Oct 1 to Oct 4), so **97 across the retained logs**. "92" is right only for the current file.
- **Longest streak: 15 blind passes, "(1 in a row)" … "(15 in a row)", events 22:44:42 → 22:56:03 CDT 2026-10-24.** This confirms 15. The first pass (telemetry seq 43987, dur 84.05 s) started about 22:43:18, so "22:43-22:56" is right.
  - Load was 654.6 → 769.1 over those passes. Seq 43988-44000 each ran one 42.01 s ps call: one try, because the orphan backlog suppressed retries (observe.py:179).
  - Recovery came at seq 44002, 22:56:25, l1 914.8, with ps taking 15.3 s.
  - `orphan-backlog` was logged at 22:56:03.
  - The previous longest streak was 13 (Oct 22 04:08:16 → 04:17:41).
- Telemetry window (Oct 20 21:30 → Oct 25 02:11), 4820 pass rows:
  - 84 passes had ≥1 timed-out `ps:all` call.
  - 56 had `band.ps == false`, the same as the 56 ps-degraded abstains in events.jsonl over that window. So 28 passes were saved by the retry.
  - Per-pass max `ps:all`: p50 0.27 s, p90 0.38 s, p99 42.01 s, max 81.05 s.
- Event gaps of several hours are normal: the longest was 24.7 h before 22:44 on Oct 24. Silence since 22:56 is not a writer fault.

## 6. Module design: `lr_recon/proctable.py`

```
proctable.mode(paths, env) -> "off"|"shadow"|"on"
    file recon/ps-free.off  → "off"  (read every pass, like inproc-lstart.off: __main__.py:252,263)
    else env LR_RECON_PSFREE in {off, shadow, on}; default "shadow" until parity has been proven, then "on"
proctable.kern_proc_all() -> Dict[int, KRow]          # 1 sysctl; size probe, ×1.25 + 64 rows, 3 tries on ENOMEM
proctable.bsdinfo_table() -> Dict[int, KRow]          # fallback: proc_listallpids + TBSDINFO(arg=1) | SHORTBSDINFO(arg=1)
proctable.tty_map(tdevs) -> Dict[int, str]            # /dev scan cache, rescan on miss, devname() last; NODEV → ""
proctable.stat_letter(p_stat) -> "Z"|"T"|"S"
proctable.procargs2(pid) -> Optional[Tuple[List[bytes], Dict[str,str]]]   # argv, plus ONLY the env keys asked for (KITTY_*)
proctable.render_args(argv, comm, zombie) -> str      # ps getproclline + libc strvis(VIS_TAB|VIS_NL|VIS_NOSLASH)
proctable.ArgsReader                                   # one daemon worker thread; queue of pids; per-call deadline
    ARGS_CALL_S = 0.5      (measured max 127.8 ms at load 621; ×4 headroom)
    ARGS_BUDGET_S = 3.0    per pass (measured all-same-uid 0.40-0.63 s)
    STUCK_MAX = 2          a worker past its deadline is abandoned (an in-kernel ctypes call cannot be killed); at
                           STUCK_MAX live stuck workers, no new reader starts this pass (the ORPHAN_RETRY_SKIP_AT rule)
proctable.args_order(rows) -> List[int]   # 1 claude-family by comm (claude, claude.exe, node*) — ALWAYS re-read, no cache
                                          #   (CC 2.1.293 sets process.title: cc293-src.js @16610957 "claude daemon",
                                          #    @19618530 "claude")
                                          # 2 kitty, shells, bash/python/expect script hosts; 3 descendants of claude;
                                          # 4 everyone else, served from a cache keyed (pid, start_sec, start_usec,
                                          #   comm, proc_pidpath) so an exec re-reads
proctable.read_table(paths, deadline) -> (procs: Dict[int, ProcRow], ttys: Dict[int,str], info)
    drop-in for observe.read_ps; info = {source, args_unread:[pids], stuck, ms}
proctable.proc_lstart(pid)   # KERN_PROC_PID: replaces store.inproc_lstart (which returns None for root/other-uid rows)
```

**Fallback order** in `observe.read_ps` when the mode is "on":
1. `kern_proc_all` + `tty_map` + `ArgsReader`.
2. If KERN_PROC_ALL raises or comes back empty: `bsdinfo_table`. Other-uid rows then have no lstart or tty, so degrade `ps-table-partial`. `env_pane` and `_identity_match` will refuse the `login` roots, which fails closed.
3. If both fail: the existing `/bin/ps` path (`_ps_read`), unchanged.

In "shadow" mode, ps decides as today. The in-process read also runs and logs per-pass parity to `recon/shadow/ps-free.jsonl`: mismatch counts per field, pids, and token-list hashes for claude-family args, **never argv or env text**. Switch to "on" after N passes with 0 ppid/zombie/lstart/tty mismatches and 0 claude-family token mismatches.

**Fail-closed rule** (from the repo lesson "a fail-safe default matching the healthy output is unfalsifiable"):
- An unread args value is never rendered `(comm)` for a claude-family row, a kitty, a shell under kitty, or a child of claude. `is_claude("(claude.exe)")` is False and would undercount holders, which means a move over a live session.
- Such a row marks `snap.degraded "ps-args"` with its pid, and `untrusted()` abstains. The abstain is now limited to an args read on one target timing out, not the whole table.
- `claude_count` should count by `comm` from the proc table, which never touches target VM, so the collapse check keeps working when args are partial.

**Kill switch:** `LR_RECON_PSFREE=off` (env; needs a daemon restart) or `touch ~/.reso/limit-recover/recon/ps-free.off` (read every pass; no restart).

**Also replace:** `read_ps_env` with the KERN_PROCARGS2 env block (extract KITTY_* keys only; the block can hold credentials, so never keep or log it); `kitty_band` `ps -M` with `band.main_thread`; `store.proc_lstart`, `act.py:809` and `fence.py:150` with `proc_lstart` and `procargs2`.

**Why it matters for mid-turn moves:** the move lane decides holders, the no-fork guard and SPLIT-BRAIN on this census. A census that goes blind for 15 passes at load 650-770 freezes every move decision regardless of the move mechanism. With a ps-free table, the hard dependency on target VM shrinks to about 93 claude-family args reads (9 ms measured).

## 7. Open questions
- Which target blocked ps on Oct 24? It cannot be determined after the fact. If it was root-owned, the in-process reader never touches it.
- Behaviour of KERN_PROCARGS2 during a real stall is unmeasured. Shadow mode should log per-call durations with comm, so a stall shows up.
- The 24 unexplained args mismatches. Shadow parity resolves them.
- 286 zombie children of kitty 1881: a kitty-health signal outside this slot.
- Exact ps rendering of empty argv elements, and the order of uid check versus task reference in `sysctl_procargsx` (WebFetch summaries, not line-verified).

## Commands run (key ones)
- `timeout 30 ls .claude/rules/; wc -l observe.py store.py; uptime` → load 578.85
- `grep`/`sed` reads of observe.py, observe_rows.py, types.py, store.py (530-700), band.py, telemetry.py (215-275, 462-482, 700-770, 875-930), __main__.py (252-263, 2525-2660, 2755-2775), act.py, evidence.py, census.py, clock.py
- `timeout 60 python3 -I count_events.py events.jsonl events.jsonl.1`; `tel_ps.py telemetry.jsonl`; `xcheck.py`
- `codesign -d --entitlements - /bin/ps`; `ls -la /bin/ps`; `nm -u /bin/ps`; `nm -u -arch arm64e /bin/ps`
- `clang off.c && ./off` (offsets above)
- `bench.py --no-ps` (run 1), `bench.py` (run 2, the single ps scan); `diag.py`; `diag2.py`; `pidpath.py`; `vis.py`
- `python3 -I -c` regex over `/tmp/mtam/cc293-src.js` for `process\.title\s*=` → 2 hits @16610957, @19618530
- WebFetch: adv_cmds `ps/tasks.c`, `ps/ps.c`, `ps/print.c`; xnu `bsd/kern/proc_info.c`, `bsd/kern/kern_sysctl.c` (raw.githubusercontent.com/apple-oss-distributions/...)
