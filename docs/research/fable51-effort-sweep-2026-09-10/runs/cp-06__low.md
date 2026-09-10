Reviewing `scripts/lead-supervisor.sh` from the brief text only. Findings below, ordered by severity.

**1. A cut or failed `git status` reads as a clean tree, so a stranded death can be auto-reaped.**

Where: line ~355
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```
Why: the header above `work_landed` claims a timeout "yields rc 124, which this function treats exactly like any other failure ⇒ return 1". This line never looks at the rc. When `git status` is killed by the bound (or fails for any reason: index.lock, corrupt index), stdout is empty, the `-z` test passes, and the dirty tree is treated as clean. If the following `rev-list --count` then returns 0 (a worker that committed nothing but has uncommitted edits), `reap_clean` deletes the telemetry row and clears the page. No checkpoint, no DEAD page, and the IDL records a clean completion for a session with unsaved work.

**2. `checkpoint_preserve` records a checkpoint that never happened when the script is missing or fails with a non-124 rc.**

Where: lines ~325, ~330, ~338
```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
```
```bash
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
```
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```
Why: only rc 124 is handled. If the script is not on PATH (the file itself notes launchd runs with a minimal PATH that excludes Homebrew and the repo bin), the `if` is skipped, `rc` stays 0, and the function writes an IDL `checkpoint` record. The same happens when the script runs and exits 1. The DEAD page then says "worktree checkpoint-preserved" (line ~485) for a worktree that was not preserved. This is a failure reported as success on the one auto-act the file promises is effect-verified.

**3. The pid-owner guard matches the substring "claude" anywhere in the command line, so a recycled pid is misread as the original session.**

Where: line ~432
```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```
Why: the check is case-insensitive fixed-substring against the full argv. Every helper in this tree lives under `~/.claude/...` (this daemon itself, `cc-notify`, `cc-reaper`, hooks), so any of them, or any process with a path or argument containing "claude", satisfies it. When a dead session's pid is recycled to such a process, `assess` skips the DEAD branch, the worktree is never checkpointed or paged, and after six hours `gc_stale` (line ~453) drops the row and calls `clear_page`. The header says GC "must never silently drop that insurance", but that is exactly what happens for this class.

**4. The `touch -t` fallback timestamp flips the effects re-read to "fresh" for every session, silently disabling escalation.**

Where: line ~277
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```
Why: `date -r <epoch>` is BSD-only. On GNU date `-r` takes a file, so it fails and the fallback sets the reference mtime to 1970. `find -newer` then matches the first regular file in any worktree, `verdict=fresh`, and `resolve_page` voids the page. A genuinely hung lead is exonerated at every deadline, the opposite of the "unknown" discipline the function documents. The file elsewhere carries GNU fallbacks (`stat -c`), so this is not a darwin-only path. Conversely, if `touch` itself fails, `ref` keeps the mktemp time (now), nothing is newer, and the verdict is `dark`, which escalates on an unobserved state.

**5. An unreadable or absent cwd is folded into `dark` and escalates, instead of the third state the function defines for "we could not look".**

Where: lines ~264 to ~265, ~290
```bash
  local cwd="$2" since="$3" verdict=dark rc=0
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
```
```bash
  printf '%s' "$verdict"
```
Why: when the telemetry row has no `cwd`, or the directory no longer exists, the whole probe body is skipped and the initial `dark` is printed. `resolve_page` treats `dark` as observed evidence and calls `escalate_page`. A live session whose worktree moved or whose telemetry omitted `cwd` is escalated at every deadline on a state that was never observed, which the comment block above the function says must not happen.

**6. `cwd` is interpolated raw into IDL JSON, producing malformed records.**

Where: lines ~335, ~338, ~374
```bash
    idl checkpoint_timeout "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"bound_s\":$SUP_CKPT_TIMEOUT_S,\"why\":\"teammate-checkpoint.sh exceeded its bound and was cut — the dead lead's worktree is NOT checkpoint-preserved; the DEAD page below still fires\""
```
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```
```bash
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
```
Why: `json_str` exists (line ~185) precisely for this, and is used for `cmd` and `target`, but not for `cwd`. A worktree path containing a double quote or backslash yields an invalid IDL line, so the S-4 audit record for that checkpoint or reap cannot be parsed by consumers of the file.

No other defects found. The same-sweep guard in `assess`, the sticky ESCALATED damping, the `send_page` rc handling, and the self-check state machine behave as their comments describe.
