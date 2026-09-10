**Defects found: 8.**

**1. The process leg is declared "gone" and the tty-exclusivity guard is skipped whenever the registry pid is empty or already dead.**
- Where: line 182 `pid_alive()  { [ -n "${1:-}" ] && kill -0 "$1" 2>/dev/null; }`, line 577 `  if pid_alive "$pid"; then`, lines 613-614 `  if ! pid_alive "$pid"; then` / `    proc_gone=1`
- Why: `resolve()` accepts a row with `.pid` null or non-numeric, so `pid` can be empty. An empty or stale-dead pid makes `pid_alive` false. Step 6 then finds the pane present and continues. The guard at line 577 is skipped, so no foreign process on that tty is ever counted. The pane is force-closed and line 614 sets `proc_gone=1` without observing any process. The run records `TEARDOWN` with `both_legs_verified` true. A pane hosting a replacement claude or an operator's live job is closed and reported as fully verified.

**2. An empty first argument exits 0 with no record, which the documented contract reads as "torn down and verified".**
- Where: line 864 `  -h|--help|"") usage; exit 0 ;;`
- Why: a caller that passes a quoted but empty pane variable, for example `cc-teardown "$uuid" --done-evidence ...` with `uuid` unset, hits this case before `main`. Usage goes to stderr, exit status is 0, and nothing is written to the records dir. The caller treats the session as torn down.

**3. The "not an interactive shell" whitelist matches every shell process, including scripts.**
- Where: line 318 `    case "$base" in -zsh|zsh|-bash|bash|-sh|sh|login|tmux|screen|gitstatusd*|caffeinate) continue ;; esac`
- Why: `ps -o comm=` reports `bash` for `bash deploy.sh` and `zsh` for `zsh -c '...'`. Any such foreign process on the pane tty is skipped and `fp` stays 0. If its current work is shell-builtin only, or its child has just exited, the tty reads as exclusive and the pane is force-closed under a running foreign script.

**4. The `--agent-id` "real argv token" check is a substring match over the flattened args string.**
- Where: line 270 `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`, line 271 `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag`
- Why: `ps -o args=` joins argv with spaces, so text inside an argument is indistinguishable from a flag. Line 271 takes the token after the first occurrence. A `claude.exe` in the target pane whose prompt argument contains ` --agent-id x@session-<lead> ` before its own flag, or that has no real flag at all, passes lines 273 and 276 and is adopted and killed. This is the exact prose class the comment claims is excluded.

**5. A name that matches more than one registry row silently resolves to an arbitrary one.**
- Where: line 329 `     '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"`
- Why: `cc-sessions --all` includes retained rows. If a retained row and a live row share a name, `.[0]` may pick the retained one. Its pid is dead and its old pane absent, so step 6 exits 0 `ALREADY-GONE` while the live session of that name is untouched and the caller believes it was torn down.

**6. A non-numeric lease setting silently disables the freshness lease instead of refusing.**
- Where: line 551 `    if [ "$lease_age" -lt "$(( 0 - DECISION_FUTURE_SKEW_S ))" ] 2>/dev/null; then`, line 556 `    if [ "$lease_age" -gt "$DECISION_MAX_STALE_S" ] 2>/dev/null; then`
- Why: `DECIDED_AT` is validated, but `CC_REAP_DECISION_MAX_STALE_S` and the skew value are not. With a value such as `60s`, `[` errors, stderr is discarded, both tests are false, and any staleness passes. The comment states the lease is required, yet a typo in the env turns it off with no record.

**7. The assignee already-gone branch records both legs as verified when no process leg exists.**
- Where: line 422 `        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1`
- Why: `resolve_assignee` returns 1 before any pid is discovered, so `pid` is empty. Only pane absence was observed. The record claims `both_legs_verified` true, so an orphaned assignee process that outlived its pane is reported as verified gone.

**8. The selftest locates the gate from `$0` rather than the symlink-resolved `HERE`.**
- Where: line 642 `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
- Why: the header promises the script works as a lone symlink in `~/.claude/bin`. Run as `~/.claude/bin/cc-teardown --selftest`, the gate path does not exist. Line 565 gets rc 127 with empty output, line 569 labels it `DEFER`, and scenarios 1 through 5, 10, and 12 fail with exit 127. The suite goes red for a wiring reason unrelated to the branches it claims to prove.
