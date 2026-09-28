I found four defects. I had no tools for this review, so the line numbers are approximate. The quoted lines are verbatim.

**1. The tty-exclusivity guard passes when the process table can't be read.**
- **What:** `tty_foreign` counts zero foreign processes when `ps -t` returns nothing, and the caller reads that as "tty is exclusive".
- **Where:** about line 268, `tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"`. It is consumed by `echo "$fp"` (`fp=0`) at the end of the function, and by `if [ "${fc:-0}" -gt 0 ] 2>/dev/null; then` in step 2c.
- **Why it is wrong:** if `ps -t <tty>` fails, times out, or returns empty, `tbl` is empty and both loops do nothing. The function prints `0`, and step 2c proceeds to kill and close. The target's own pid is always on its tty, so an empty table is proof the read failed, yet it is treated as a clean result. Only an empty tty *name* gives the fail-closed `-1`.

**2. The assignee identity check can match text inside a prose argument instead of the real flag.**
- **What:** `--agent-id` is extracted from the flattened `args=` string by taking the first occurrence of `--agent-id `, so it cannot tell a real flag from the same words inside another argument.
- **Where:** about lines 236–237, `case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac` and `agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag`.
- **Why it is wrong:** take a `claude.exe` session whose task text contains `--agent-id x@session-<lead>` before its own arguments, which is the sibling-session case the comment describes. The first occurrence is the prose one. `x@session-<lead>` passes the suffix and character-set checks, so an unrelated live session is adopted and then killed. The comment claims this is prevented, but the guard is still a text match on flattened argv.

**3. A registry pid of 0 (or any non-positive pid) is never validated, and `kill` treats it as a process group.**
- **What:** `pid` is taken from the registry JSON and passed to `kill` without checking it is a positive integer.
- **Where:** about line 168, `pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }`, and about line 640, `kill -TERM "$pid" 2>/dev/null || true`.
- **Why it is wrong:** for a row with `pid` `0`, `kill -0 0` succeeds because it targets the caller's process group. The script then runs `kill -TERM 0` and `kill -KILL 0`, which signal its own process group, including the calling desk or reaper. A `pid` of `-1` would signal every process the user may signal. Nothing checks that the value is a real claude pid.

**3b. An empty pid is reported as "process gone".**
- **What:** when the registry row has no pid, effect-verify reports the process leg as verified without observing any process.
- **Where:** about line 662, `if ! pid_alive "$pid"; then` followed by `proc_gone=1`.
- **Why it is wrong:** `pid_alive ""` is always false, so with an empty pid the tty guard and kill are skipped. The pane is force-closed and `proc_gone=1` is set with nothing observed. The run records `both_legs_verified` true and exits 0, although no process was ever proven dead.
