# Review of `scripts/lead-supervisor.sh`

I found 10 defects. Line numbers are my count of the brief's listing, so they may be off by one or two. The quoted code is verbatim.

---

### 1. A `-k` escalation to SIGKILL returns rc 137, but every "cut" check tests only for 124

- **What:** `sup_bounded` uses `timeout -k 5`. When the command ignores SIGTERM and gets SIGKILLed, the exit status is 137, not 124. Every caller recognises a cut only by `rc = 124`.
- **Where:**
  - L80 `"$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
  - L269 `[ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - L285 `[ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - L332 `if [ "$rc" = 124 ]; then`
- **Why it is wrong:** The `-k` path exists for TERM-ignoring forks, which is exactly the case described above it. In that case:
  - In `reobserve_effects`, a SIGKILLed `git log` or `find` gives empty output and rc 137. That reads as `dark`, so `escalate_page` fires on an unobserved state. This is the "cut folded into dark" trap the comment block says the code prevents.
  - In `checkpoint_preserve`, a SIGKILLed checkpoint falls through to `idl checkpoint ... dead-lead-preserve`, recording a success that did not happen.

### 2. `checkpoint_preserve` records success when nothing was checkpointed

- **What:** It logs a successful checkpoint when the script is missing or fails with any non-124 rc. Separately, the DEAD page always tells the operator the worktree was preserved.
- **Where:**
  - L325 `if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
  - L338 `idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - L485 `checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`
- **Why it is wrong:**
  - Under launchd's minimal PATH (which the file itself says excludes non-system dirs), `teammate-checkpoint.sh` is not found. `rc` stays 0 and an IDL `checkpoint` record is written anyway.
  - Any real failure (rc 1, 2, 137, …) is also logged as `checkpoint`.
  - The DEAD page text claims "worktree checkpoint-preserved" unconditionally, including after the `checkpoint_timeout` path.

  The result is that a failure is reported as a success to the operator.

### 3. `work_landed` treats a failed or timed-out `git status` as a clean tree

- **What:** A failed or cut `git status` is read as "clean".
- **Where:** L355 `[ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
- **Why it is wrong:** If `git status` is cut at the 15s bound (index.lock contention, which is the named hazard) or errors out, it prints nothing. The test only checks for empty output, not the rc, so the tree is treated as clean. If the landed checks then pass, `reap_clean` deletes the telemetry row and clears pages for a session that may have uncommitted work. No page and no checkpoint happen. The header comment claims a cut "must never be read as landed and silently reaped".

### 4. `reobserve_effects` returns `dark` when it could not look (mktemp failure)

- **What:** If `mktemp` fails, the file-mtime probe is skipped silently and the verdict stays `dark`.
- **Where:**
  - L275 `local ref; ref="$(mktemp 2>/dev/null)"`
  - L276 `if [ -n "$ref" ]; then`
- **Why it is wrong:** On a full or unwritable TMPDIR, no worktree probe runs. A lead with no new commit but active file edits reads as `dark` and is escalated. The comment says "we could not look" must return `unknown`, never `dark`.

### 5. A repeat escalation after a void is never notified

- **What:** `void_page` keeps `.notified = ESCALATED`, so a later genuine re-escalation is suppressed by the equality damping.
- **Where:**
  - L209 `[ "$last" = "$2" ] && return 0`
  - L231 `void_page(){ rm -f "$PAGEDIR/$1.page" 2>/dev/null || true; }`
- **Why it is wrong:** The sequence is:
  1. The session is ESCALATED and notified.
  2. It resumes work, so the re-read is fresh and the page is voided. The marker still says ESCALATED.
  3. Telemetry stays stale, so a new STALL? is suppressed by the sticky rule.
  4. The lead goes dark again, and a new deadline expires.
  5. `page … ESCALATED` hits `last = ESCALATED` and returns without sending.

  The operator is never told about the second dark episode. The comments claim "ESCALATED break[s] through".

### 6. After escalation the deadline clock is never reset

- **What:** Once escalated, the `.page` file is never reset, so every later sweep re-runs the full effects probe and logs another escalation.
- **Where:**
  - L316–318 `escalate_page(){` … `page "$1" ESCALATED ...`
  - L298 `[ "$(( $(now) - ${paged_at:-0} ))" -ge "$DEADLINE_S" ] || return 0`
- **Why it is wrong:** Neither `escalate_page` nor `page` restamps `.page`. On every 30s sweep:
  - `had_page=1` and the deadline is still expired.
  - `resolve_page` re-runs `git log` plus the bounded `find` walk.
  - Another `page_escalate` IDL record is written.

  This is contrary to "re-observe at the next deadline".

### 7. The STALL? deadline clock is shared with other page states

- **What:** The `.page` deadline file is shared with the PAST-THRESHOLD and DEAD pages. A STALL? candidate can therefore be resolved, and escalated, in the same sweep it is first paged.
- **Where:**
  - L203 `[ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only`
  - L507 `local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`
- **Why it is wrong:** Take a session paged PAST-THRESHOLD, which stamps `.page` at time X. It then goes telemetry- and transcript-stale. On its first STALL? sweep:
  - `had_page=1`, because the file came from the PAST-THRESHOLD page.
  - `resolve_page` measures the deadline from X, which is already expired.
  - The session can escalate immediately after the STALL? notify: two notifies in one sweep, with no deadline window.

  This is the phantom same-sweep escalation the guard claims to prevent.

### 8. The self-check counts dead and unowned telemetry rows as coverage

- **What:** The blind-spot self-check counts every telemetry file, including rows for dead or recycled pids, as coverage of a live pane.
- **Where:**
  - L632 `n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`
  - L607 `delta=$(( live - enum ))`
- **Why it is wrong:** DEAD rows are never GC'd. `gc_stale` only drops live-owner rows, and only clean completions are reaped. Take 3 live panes with no telemetry plus 3 stranded-DEAD rows: `delta = 3 - 3 = 0`. No alarm fires, though every live session is invisible, and the all-clear heartbeat is emitted.

### 9. The permission-beacon reap trusts a bare `kill -0`

- **What:** The reap decides the owning session is alive with `kill -0` alone, so a recycled pid keeps a dead session's beacon alive and paging.
- **Where:** L554 `if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`
- **Why it is wrong:** After the session exits, its pid can be recycled to any process. `kill -0` then succeeds, so REAP 1 is skipped. The beacon produces a PERMISSION-PENDING page (and IDL records every sweep) for a dead session until the 24h horizon. This is the recycled-pid failure that `pid_alive_owner` was introduced to fix elsewhere.

### 10. The transcript path mangling does not match Claude Code's projects-dir slug (moderate confidence)

- **What:** Only `/` and `.` are mangled.
- **Where:** L391 `slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'`
- **Why it is wrong:** Claude Code replaces every non-alphanumeric character (for example `_` and spaces). For a cwd like `.../doc_classifier`, the file named in this script, the computed path does not exist. `transcript_age` then returns the 999999999 "cold" sentinel and the warm-transcript exemption never applies. That brings back the false STALL?→void→re-STALL? pages it was meant to stop.

---

**Minor, same class:** the file says to never raw-`%s` strings into JSON, but `cwd` is embedded raw in IDL records at L335, L338 and L374. A cwd containing `"` or `\` produces malformed IDL lines.
