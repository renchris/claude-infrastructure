# Review of `scripts/lead-supervisor.sh`: 10 defects

Line numbers are counted from the `#!/bin/bash` line. The quoted code is the anchor if a count is off by one.

---

### 1. A kill-escalated timeout returns 137, not 124, so a cut probe is read as a verdict

**What:** `sup_bounded` runs `timeout -k 5`, and its callers treat only rc 124 as "cut". When the child ignores SIGTERM and gets SIGKILLed, the rc is 137, and callers read that as a real result.

**Where:**
- L80 `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
- L269 `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- L285 `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- L332 `  if [ "$rc" = 124 ]; then`

**Why it is wrong:**
- GNU `timeout` sends the `-k` SIGKILL to its own process group and exits 137. This is exactly the TERM-ignoring case the comment says `-k` exists for.
- In `reobserve_effects`, a git or find that had to be killed leaves `last_commit` and `hit` empty. The verdict stays `dark`, and `resolve_page` escalates a lead nobody actually observed. That is the silence-reap the "unknown" state exists to prevent.
- In `checkpoint_preserve`, a killed checkpoint falls through and is logged as a successful `checkpoint`.

### 2. `work_landed` ignores the rc of `git status`, so a cut or failed status reads as a clean tree

**What:** The clean-tree check tests only whether the output is empty, not whether `git status` succeeded.

**Where:** L355 `  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`

**Why it is wrong:**
- If `git status` times out (rc 124), hits a lock, or errors, it prints nothing, so the test passes as "clean".
- A dead worker with uncommitted changes but no unlanded commits (0 ahead) then returns 0.
- `assess` calls `reap_clean`: the telemetry row and pages are deleted, with no checkpoint and no page.
- The comment at L348–350 claims the opposite: "a timed-out probe must never be read as landed".

### 3. The checkpoint is recorded, and the DEAD page claims "checkpoint-preserved", when no checkpoint happened

**What:** Several paths report a checkpoint that did not happen, and the DEAD page text asserts preservation unconditionally.

**Where:**
- L325 `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
- L338 `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
- L485 `    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`

**Why it is wrong:**
- If `teammate-checkpoint.sh` is not on PATH, which is likely under launchd's minimal PATH as the file itself notes, nothing runs but `idl checkpoint` is still written.
- If the script exits with any non-124 failure, the same false `idl checkpoint` record is written.
- When cwd is empty or missing (L324 returns early), nothing is checkpointed.
- After a `checkpoint_timeout`, nothing is checkpointed either.
- In all of these cases the operator's DEAD page still says "worktree checkpoint-preserved". A failure is reported as a success.

### 4. `reobserve_effects` folds "could not look" into a verdict

**What:** A failure to build the reference timestamp is turned into a definite `fresh` or `dark` result instead of `unknown`.

**Where:**
- L275 `      local ref; ref="$(mktemp 2>/dev/null)"`
- L276 `      if [ -n "$ref" ]; then`
- L277 `        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null`

**Why it is wrong:**
- If `date -r <epoch>` fails, the reference is set to 1970, so every file is "newer" and the verdict is `fresh`. This can happen on GNU date, where `-r` takes a file, or with a malformed `paged_at`. A genuinely hung lead is then exonerated every deadline.
- If `mktemp` fails, the find is skipped and the verdict stays `dark`, which escalates without anyone looking.
- The comment block at L256–262 explicitly forbids both foldings.

### 5. The page deadline clock is shared across states and never re-stamped on a state change

**What:** A STALL? page can be resolved immediately using a deadline clock that an earlier PAST-THRESHOLD page started.

**Where:**
- L203 `  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only`
- L507 `      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`
- L509 `      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"`

**Why it is wrong:**
- A session that was paged PAST-THRESHOLD keeps its `.page` file from that first page.
- When its telemetry and transcript then go stale, the first STALL? sweep sees `had_page=1`. The deadline is long expired, so it resolves in the same sweep, with `since` set to the old PAST-THRESHOLD time.
- The STALL? candidate therefore gets no deadline window at all. The re-read window then runs back to the PAST-THRESHOLD page:
  - Work from before the stall reads as `fresh` and voids a real stall.
  - A session that wrote no files since then is ESCALATED at once.

### 6. B-1 does not cover a past-threshold session whose telemetry has gone stale

**What:** The PAST-THRESHOLD check requires fresh telemetry, so the "working past the boundary, never Stops" case it claims to cover falls through to OK.

**Where:**
- L515 `  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then`
- L520 `  clear_page "$sid"; echo 0`

**Why it is wrong:**
- A session inside one long turn stops rendering, so its telemetry age reaches `STALL_S` or more (the file's own statusline note).
- If its transcript is warm, or it is the registered desk, the STALL? branch is skipped.
- B-1 is then skipped because `age >= STALL_S`, and the session lands in OK. `clear_page` runs even though `used >= T`.
- The header describes this exact case as B-1's purpose (L23–24), yet the session gets no page.

### 7. The self-check's enumerated count includes rows for dead or reaped sessions, which masks blind spots

**What:** `n` counts every telemetry file, not the live sessions that actually have coverage.

**Where:**
- L632 `      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`
- L642 `  self_check "$n"`

**Why it is wrong:**
- DEAD rows are never removed; they persist and re-page every sweep. Rows reaped during this very sweep are also counted.
- `delta = live - n` therefore undercounts missing panes. Example: 3 lingering dead-session rows plus 3 live panes with no telemetry gives delta 0.
- The "blind spot" detector then reports all-clear for 3 sessions that have no pager at all.

### 8. Permission-beacon REAP 1 uses bare `kill -0`, which reads a recycled pid as the live owner

**What:** The dead-owner check here does not use `pid_alive_owner`.

**Where:** L554 `      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`

**Why it is wrong:**
- After the session exits and its pid is reused by any process, `kill -0` succeeds and the beacon is not reaped.
- The supervisor keeps paging "PERMISSION-PENDING … blocked" for a session that no longer exists, until the 24h horizon. It records an IDL `permission_pending` every sweep.
- The file documents this exact false-liveness trap (`pid_alive_owner`, item fdc101e8b0c7) and fixes it elsewhere, but not here.

### 9. The transcript slug mangling only maps `/` and `.`, so the warm-transcript exemption fails for other characters

**What:** Claude Code's `projects/` directory naming replaces every non-alphanumeric character with `-`. This code replaces only `/` and `.`.

**Where:** L391 `  slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'`

**Why it is wrong:**
- For a cwd containing `_`, a space, or similar, the computed path does not exist. The file itself names `doc_classifier`.
- `transcript_age` then returns 999999999, treated as "cold".
- The warm-transcript exemption never applies, so healthy idle or long-turn sessions in such directories are STALL?-paged, which is the oscillation the exemption was added to stop.

### 10. Untrusted strings are embedded raw into IDL JSON

**What:** `sid`, `cwd`, and `detail` are interpolated directly into JSON, despite the file's own rule to use `json_str`.

**Where:**
- L204 `  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""`
- L338 `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
- L374 `  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""`

**Why it is wrong:** A telemetry `cwd` or `session_id` containing `"` or `\` produces malformed IDL lines. This is the "malformed-IDL class" the comment at L183–184 says must never happen, and it corrupts the S-4 heartbeat/outcome audit trail.
