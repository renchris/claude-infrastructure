# Review: `scripts/lead-supervisor.sh`

I found 16 defects, ordered roughly by severity. Line numbers count `#!/bin/bash` as line 1.

---

### 1. `work_landed` treats a failed or timed-out `git status` as a clean tree

**What:** The dirty-tree gate checks only the output of `git status`, never its exit code. An empty output from a failed or cut command therefore reads as "clean".

**Where:** line 355: `  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`

**Why it is wrong:**
- `git status` can be cut at the 15s bound (a huge tree such as the 1.27M-file repo the file cites, or index contention). It can also fail outright. Either way stdout is empty, so `[ -z "" ]` passes.
- Take a dead worker with uncommitted edits whose HEAD is 0 ahead of trunk. `work_landed` returns 0, and `reap_clean` deletes its telemetry row and clears its pages. No checkpoint is taken and no DEAD page is sent.
- The comment at lines 348–350 claims a cut is treated "exactly like any other failure". It is not.

### 2. `checkpoint_preserve` records a checkpoint that never happened

**What:** A success record is written when the checkpoint script is missing, and also for any failure other than rc 124.

**Where:**
- line 325: `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
- line 332: `  if [ "$rc" = 124 ]; then`
- line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`

**Why it is wrong:**
- Under launchd's minimal PATH, `teammate-checkpoint.sh` is probably not found. The file works around that PATH for `timeout` and `cc-notify`, but not here. The script is then skipped, `rc` stays 0, and `checkpoint … dead-lead-preserve` is logged.
- Any non-124 failure also falls through to the success record. That includes a script error and rc 137 from the `-k` KILL.

### 3. The DEAD page always tells the operator the worktree was checkpoint-preserved

**What:** The page text is hard-coded and ignores what actually happened to the checkpoint.

**Where:** line 485: `    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`

**Why it is wrong:** The page claims insurance that may not exist:
- after a `checkpoint_timeout` (line 335 even says "the DEAD page below still fires");
- when `cwd` is empty or missing (line 324 returns 0 having done nothing);
- when the script is absent.

### 4. Probe-cut detection only recognises rc 124, but the `-k 5` escalation exits 137

**What:** A probe that was cut by the SIGKILL escalation is not recognised as cut.

**Where:**
- line 80: `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
- line 269: `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- line 285: `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`

**Why it is wrong:**
- timeout(1) exits 124 only when SIGTERM ends the command. If the command ignores TERM (the case lines 75–76 cite) or is stuck on a stalled volume, the KILL 5s later makes timeout exit 137.
- In `reobserve_effects`, a 137 from git leaves `last_commit` empty. A 137 from find leaves `hit` empty. The verdict stays `dark`, and `resolve_page` escalates.
- So an unobserved state is folded into `dark`, which lines 256–262 say must never happen.

### 5. The SAME-SWEEP GUARD fires on a `.page` stamped by a different state

**What:** The guard checks whether any `.page` file exists. That file is shared by every page state and stamped only once.

**Where:**
- line 507: `      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`
- line 203: `  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only`

**Why it is wrong:**
- Consider a lead being paged PAST-THRESHOLD (`used` ≥ T, telemetry fresh) that hangs. On the sweep where telemetry and transcript both cross STALL_S, it goes straight to STALL?. No OK sweep runs in between to clear the file.
- `had_page=1`, so `resolve_page` runs in the same sweep, with `paged_at` taken from the old PAST-THRESHOLD stamp.
- If that stamp is at least DEADLINE_S old, the deadline "expires" in the very sweep the STALL? page was first raised:
  - **Dark:** STALL? and ESCALATED are notified back-to-back with no operator deadline — the 2-notify storm this guard exists to stop.
  - **Fresh:** a `fresh-effects-after-deadline` void is logged, based on work done before the stall page existed.
- A leftover DEAD `.page` does the same thing.

### 6. The owner check accepts any process whose command line contains "claude"

**What:** The "alive owner" test is a case-insensitive substring match on the whole command line.

**Where:** line 432: `  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"`

**Why it is wrong:**
- A recycled pid can land on a non-session process and still pass. Examples: a hook or `cc-notify` under `~/.claude/`, a headless `claude -p`, an MCP child, or a Claude.app helper.
- The dead session then never takes the DEAD branch, so no checkpoint and no DEAD page. It is STALL?/ESCALATED as if it were alive.
- After GC_S, `gc_stale` deletes its row, silently dropping the stranded-work insurance.

### 7. `gc_stale` deletes rows of healthy live sessions based on telemetry age alone

**What:** GC acts on the premise "stale telemetry past GC_S means hung or recycled". The file itself says that premise is false.

**Where:**
- line 451: `    [ "$age" -ge "$GC_S" ] || continue`
- line 455: `    rm -f "$f" 2>/dev/null || true`

**Why it is wrong:**
- Lines 382–385 document live sessions with days-stale telemetry but warm transcripts, because backgrounded panes do not render the statusline. `gc_stale` never consults `transcript_age`.
- Such a session's row is deleted after 6h. The "self-healing" re-export (line 443) does not happen while the pane isn't rendering.
- If that session later dies with unlanded work, there is no row for the DEAD branch, so no checkpoint and no page.

### 8. `reobserve_effects` returns "dark" when it never looked

**What:** The verdict starts as `dark` and stays there when the probes are skipped.

**Where:**
- line 264: `  local cwd="$2" since="$3" verdict=dark rc=0`
- line 265: `  if [ -n "$cwd" ] && [ -d "$cwd" ]; then`
- line 276: `      if [ -n "$ref" ]; then`

**Why it is wrong:**
- If `cwd` is empty or no longer a directory, both probes are skipped.
- If `mktemp` fails, the file probe is skipped.
- `resolve_page` escalates on `dark`, which is an escalation from an unobserved state.

### 9. The `-newer` reference fallbacks invert the verdict

**What:** Both failure paths in building the reference timestamp silently produce a wrong result, in opposite directions.

**Where:** line 277: `        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null`

**Why it is wrong:**
- **`date -r <epoch>` fails** (e.g. GNU date reads `-r` as a file path; the file does carry GNU fallbacks such as `stat -c`): the reference becomes 1970. Every file counts as newer, so the verdict is always `fresh` and a hung lead is voided at every deadline.
- **`touch` fails:** `ref` keeps mktemp's current mtime. Nothing since the page counts, so the verdict is `dark` and a working lead is escalated.

### 10. Permission-beacon REAP 1 uses a bare `kill -0`

**What:** The dead-session check for beacons uses the exact test the file says is unreliable.

**Where:** line 554: `      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`

**Why it is wrong:**
- Lines 423–425 say `kill -0` reads a recycled pid as the original session.
- A hard-killed session whose pid has been reused keeps its beacon. The operator is paged "PERMISSION-PENDING … must approve or deny" for a session that no longer exists, until the 24h horizon.

### 11. REAP 1 runs after the same sweep has deleted the telemetry row it depends on

**What:** Sweep ordering removes the row that REAP 1 needs to detect a dead session.

**Where:**
- line 375: `  rm -f "$TEL_DIR/$1.json" 2>/dev/null || true`
- line 552: `    if [ -f "$tel" ]; then`
- line 639: `  pp="$(sweep_permission_pending)"; found=$(( found + ${pp:-0} ))`

**Why it is wrong:**
- Take a hard-killed session (no SessionEnd, so the beacon is left behind) with a clean, landed worktree.
- `assess` runs first and `reap_clean` deletes its row.
- `sweep_permission_pending` then finds no telemetry and skips REAP 1. Because the beacon is at least 120s old, it pages PERMISSION-PENDING for a dead session. Only REAP 2 removes the beacon, after 24h.

### 12. self_check's "unreadable ps ⇒ ABSTAIN" guard can never fire

**What:** The guard waits for a non-numeric count, but the pipeline always prints a number.

**Where:**
- line 606: `  case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ`
- line 597: `    END { print c+0 }'`

**Why it is wrong:**
- awk always prints a number, so a failed `ps` (e.g. unsupported `-E`, or a sandbox) yields `0`.
- `delta` becomes negative, which is read as healthy. Line 610 then rewrites the state file to `0 0`, erasing any standing blind-spot record.
- A `ps` failure therefore silently disables the detector instead of abstaining.

### 13. The self-check's "enumerated" count includes rows that provide no coverage

**What:** `n` counts every telemetry file, not just rows that actually cover a live session.

**Where:**
- line 632: `      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`
- line 642: `  self_check "$n"`

**Why it is wrong:**
- `n` includes stranded DEAD rows (never GC'd, never reaped unless landed), rows with no pid, and rows reaped earlier in the same sweep.
- Example: 3 live panes are missing from telemetry and 3 dead-session rows remain. Δ is 0 and nothing is paged, so the blind spot is masked.

### 14. The heartbeat reports an all-clear while a blind spot is known

**What:** The self-check finding never reaches the heartbeat.

**Where:**
- line 642: `  self_check "$n"`
- line 643: `  heartbeat "$n" "$found" "$gc"`

**Why it is wrong:**
- `self_check` adds nothing to `found`, and it writes an IDL record only on the sweeps where it sends a page (lines 616–617).
- During the persistence window, and on every damped sweep after the first page, the IDL gets only `findings:0` heartbeats.
- That is exactly the all-clear that lines 640–641 say must not be emitted while live panes sit outside the world-view.

### 15. The transcript path mangling only rewrites `/` and `.`

**What:** The computed transcript directory name does not match how Claude Code names project directories.

**Where:** line 391: `  slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'`

**Why it is wrong:**
- Claude Code replaces every non-alphanumeric character with `-` when naming the `projects/` directory.
- For a cwd containing `_`, a space, and so on (e.g. the file's own `doc_classifier`), the computed path doesn't exist, so the age is 999999999.
- The warm-transcript exemption then never applies, and live sessions with stale telemetry are STALL?-paged and escalated.

### 16. `cwd` is embedded raw into IDL JSON

**What:** `cwd` is interpolated into JSON records without escaping.

**Where:**
- line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
- line 374: `  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""`
- line 335 has the same pattern.

**Why it is wrong:** A `cwd` containing `"` or `\` produces a malformed IDL line — the class line 184 warns about. The checkpoint or reap audit record is then unreadable to any JSON consumer.
