# Review of `scripts/lead-supervisor.sh`

I found 15 defects. The first 11 are high to moderate confidence. Items 12–15 are lower impact or depend on the platform or the harness.

---

### 1. A cut escalated to SIGKILL returns 137, not 124, so every "cut" check misses it

**Where:**
- Line 80: `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
- Line 269: `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- Line 285: `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- Line 332: `  if [ "$rc" = 124 ]; then`

**Why:**
- When the child ignores TERM, or sits in uninterruptible I/O (the "stalled volume" class the header names), `-k` fires. GNU timeout then sends SIGKILL to its process group, which includes itself, so the shell sees rc 137.
- In `reobserve_effects`, a KILL-cut `find` leaves `hit` empty. The verdict falls through to `dark` and `resolve_page` escalates. This is the "slow-but-healthy repo manufactures an escalation" case that the `unknown` state was added to prevent.
- In `checkpoint_preserve`, a KILL-cut checkpoint skips the timeout branch. It is recorded as a successful `checkpoint`.

### 2. `checkpoint_preserve` records a successful checkpoint when none happened

**Where:**
- Line 325: `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
- Line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`

**Why:**
- The script is found by PATH only, with no fallback paths. Under launchd's minimal PATH it is skipped entirely. The file itself documents this PATH problem and works around it for `timeout` and `cc-notify`, but not here.
- When skipped, `rc` stays 0 and the IDL gets a `dead-lead-preserve` success record.
- Any non-124 failure (rc 1, 127, 137, …) is also logged as a success.

### 3. The DEAD page always tells the operator the worktree was checkpoint-preserved

**Where:**
- Line 485: `    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`
- Line 324: `  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0`

**Why:** The page text is fixed. It claims preservation in every one of these cases:
- a timeout (where the IDL line itself says "NOT checkpoint-preserved");
- an empty or missing cwd, which returns silently at line 324;
- a missing script;
- a failed script.

The operator's only notification states something false.

### 4. `work_landed` reads a failed or timed-out `git status` as a clean tree

**Where:**
- Line 355: `  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`

**Why:**
- The exit status is never checked, only whether stdout is empty.
- A `git status` cut at 15s (index.lock contention, stalled volume) or failing outright produces empty stdout, so the tree counts as clean.
- If `ahead` is then 0, or the content check passes, `reap_clean` runs on a dirty worktree. The telemetry row is deleted, with no checkpoint and no page.
- This contradicts the claim at lines 348–350 that a cut "must never be read as landed and silently reaped".

### 5. `reobserve_effects` reports `dark` when it could not look at all

**Where:**
- Line 264: `  local cwd="$2" since="$3" verdict=dark rc=0`
- Line 265: `  if [ -n "$cwd" ] && [ -d "$cwd" ]; then`
- Line 276: `      if [ -n "$ref" ]; then`

**Why:**
- If the telemetry row has no `cwd`, the worktree was removed or renamed, or `mktemp` fails, no work-products are examined.
- The function still returns `dark`, and `resolve_page` escalates.
- That escalation rests on silence alone, which S-3b forbids.

### 6. The same-sweep guard keys on a `.page` file shared by every state

**Where:**
- Line 507: `      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`
- Line 509: `      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"`
- Line 203: `  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only`

**Why:**
- A session paged PAST-THRESHOLD at time X keeps that `.page` stamp, because B-1 re-pages every sweep and never clears it.
- When it later goes stale, the first STALL? sweep sees `had_page=1` and resolves immediately against X.
- The re-read window then includes work done before the stall. The result is either a bogus `fresh-effects-after-deadline` void, or a same-sweep ESCALATE with two notifies and no deadline ever given to the STALL? page.

### 7. Sticky ESCALATED silently swallows a later PAST-THRESHOLD advisory

**Where:**
- Line 215: `  [ "$last" = "ESCALATED" ] && [ "$2" != "DEAD" ] && return 0`

**Why:**
- An escalated session that resumes with fresh telemetry but `used ≥ T` takes the B-1 branch (lines 515–517).
- That branch never reaches the OK-branch `clear_page`, so `.notified` stays `ESCALATED`.
- Every PAST-THRESHOLD notify is suppressed for as long as the session stays past threshold. The operator never gets the /handoff advisory.

### 8. B-1 does not cover a live, working, past-threshold session whose statusline has stopped rendering

**Where:**
- Line 515: `  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then`
- Line 520: `  clear_page "$sid"; echo 0`

**Why:**
- Take `used ≥ T`, telemetry age ≥ `STALL_S`, and a warm transcript. The STALL? inner test fails (line 499) and B-1 requires fresh telemetry, so the row falls to OK.
- OK clears any standing page. This is the "working-past-boundary, never Stops" case B-1 claims to cover.
- The file itself says the statusline stops rendering during long operations.

### 9. The self-check compares live panes against all telemetry rows, not live-covered rows

**Where:**
- Line 632: `      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`
- Line 642: `  self_check "$n"`

**Why:**
- `n` counts stranded-DEAD rows, which the DEAD branch never deletes and which persist forever. It also counts rows `reap_clean` removed in this same sweep.
- So 3 dead rows plus 3 live panes with no telemetry gives Δ0, and no self-check page fires.
- The blind spot is masked, and the heartbeat reads as all-clear.

### 10. The permission-beacon dead-session reap relies on `kill -0` and on a telemetry row this same sweep may already have deleted

**Where:**
- Line 554: `      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`
- Line 639 runs after 628/632: `  pp="$(sweep_permission_pending)"; found=$(( found + ${pp:-0} ))`

**Why:**
- If the pid was recycled, `kill -0` succeeds; the file itself documents that "kill -0 lies" in exactly this case.
- If `assess`→`reap_clean` or `gc_stale` removed `$TEL_DIR/$sid.json` earlier in the sweep, REAP 1 cannot run at all.
- Either way, a dead session is paged "PERMISSION-PENDING … operator must approve" until the 24h horizon.

### 11. The owner check is a case-insensitive substring match on the whole command line

**Where:**
- Line 432: `  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"`

**Why:**
- A pid recycled to any process whose argv mentions "claude" reads as the original live owner. Examples: a hook or script under `~/.claude/`, `~/.claude/bin/cc-notify`, or a headless `claude -p`.
- For such a session, the DEAD branch (checkpoint plus page) is skipped. It is paged STALL? instead, then `gc_stale` drops the row without checkpoint or page once it passes `GC_S`.
- The file's own strict argv0 identity clause (lines 594–595) shows the intended class is much narrower.

### 12. `gc_stale` drops rows for sessions that are demonstrably alive

**Where:**
- Line 451: `    [ "$age" -ge "$GC_S" ] || continue`
- Line 453: `    pid_alive_owner "$pid" || continue                              # GONE / recycled-non-owner → leave for assess()`

**Why:**
- The GC premise is "has not emitted for hours — hung or recycled", but it only checks telemetry age.
- A healthy backgrounded session with days-stale telemetry and a warm transcript (measured in the comment at line 385) is GC'd anyway.
- Once its row is gone, its later death with unlanded work gets no DEAD page and no checkpoint.

### 13. `cwd` and `sid` are embedded raw into IDL JSON

**Where:**
- Line 374: `  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""`
- Line 338, as quoted in item 2.
- Line 335: the `checkpoint_timeout` line.
- Line 204: `  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""`

**Why:** A cwd or session_id containing `"` or `\` produces a malformed IDL line. The audit record for a reap or checkpoint is then lost to JSONL consumers. This is the class line 184 says must never happen.

### 14. The transcript path mangling covers only `/` and `.` (lower confidence; depends on the harness)

**Where:**
- Line 391: `  slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'`

**Why:**
- Claude Code maps every non-alphanumeric character to `-`.
- A cwd containing `_` or a space would then resolve to a nonexistent transcript. An example is `doc_classifier`, named in this very file.
- An unresolved transcript returns 999999999, so it counts as cold. The warm-transcript exemption is silently lost, and idle-live sessions get false STALL? pages.

### 15. The "GNU fallback" for `stat` does not work on GNU (low impact on macOS)

**Where:**
- Line 394: `  mt="$(stat -f %m "$tp" 2>/dev/null || stat -c %Y "$tp" 2>/dev/null || echo 0)"   # BSD stat, then GNU fallback`

**Why:**
- In GNU `stat`, `-f` takes no argument, so `%m` becomes a file operand. The command prints filesystem info for `$tp` and exits 1.
- The fallback's output is then appended, so `mt` is multi-line text and the arithmetic fails.
- `tage` ends up empty, `[ "" -ge … ]` is false, and on Linux no session ever becomes a STALL? candidate.
