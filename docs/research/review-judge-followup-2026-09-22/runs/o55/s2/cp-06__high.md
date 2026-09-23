I found 12 defects in `scripts/lead-supervisor.sh`. Line numbers are my count of the file as given in the brief; the quoted code is copied verbatim.

---

### 1. A timeout that has to escalate to SIGKILL is not recognised as a cut

- **What:** Every caller treats only rc 124 as "the probe was cut". But with `-k 5`, timeout(1) returns 137 (128+9), not 124, when the child ignores SIGTERM and has to be SIGKILLed.
- **Where:**
  - L81 `"$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
  - L270 `[ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - L286 `[ "$rc" = 124 ] && { printf 'unknown'; return; }`
  - L333 `if [ "$rc" = 124 ]; then`
- **Why it is wrong:** Take a git or find that ignores TERM. The file's own comment names this case as the reason for `-k`.
  - In `reobserve_effects`, rc 137 falls through as "no hit", so the verdict is `dark`. `resolve_page` then escalates a lead it never actually observed. This is the exact "cut folded into dark" trap the comment at L257–263 says must not happen.
  - In `checkpoint_preserve`, rc 137 skips the timeout record and writes a success `checkpoint` record.

### 2. A skipped or failed checkpoint is recorded and paged as a successful checkpoint

- **What:** `checkpoint_preserve` writes `idl checkpoint ... dead-lead-preserve` whenever rc ≠ 124. It also returns silently when there is no cwd. Meanwhile the DEAD page always says "worktree checkpoint-preserved".
- **Where:**
  - L325 `[ -n "$cwd" ] && [ -d "$cwd" ] || return 0`
  - L326 `if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
  - L339 `idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - L486 `checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`
- **Why it is wrong:** The false success happens in several cases:
  - `teammate-checkpoint.sh` is not on PATH. The file itself says launchd runs with a minimal PATH, and unlike cc-notify this script is resolved only via PATH.
  - The script exits non-zero, or with rc 137.
  - The cwd is empty or missing.

  In each case the IDL shows a checkpoint and the operator is told the worktree is preserved, when no checkpoint was taken. Even on the rc-124 path the page text still claims it was preserved.

### 3. A failed or timed-out `git status` is read as "clean tree"

- **What:** `work_landed` checks only that the output of `git status --porcelain` is empty, not its exit status.
- **Where:** L356 `[ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
- **Why it is wrong:** If `git status` is cut (rc 124/137) or errors, it prints nothing, so the tree passes as clean. If `rev-list --count` then returns 0, the dead worker's row is `reap_clean`ed. That means no checkpoint and no page for a possibly dirty worktree. The header comment (L349–351) claims a cut "must never be read as landed".

### 4. A cwd the re-read could not look at is reported as `dark`

- **What:** `reobserve_effects` starts at `verdict=dark` and keeps it when it never probed anything.
- **Where:**
  - L265 `local cwd="$2" since="$3" verdict=dark rc=0`
  - L266 `if [ -n "$cwd" ] && [ -d "$cwd" ]; then`
  - L277 `if [ -n "$ref" ]; then`
- **Why it is wrong:** This covers a telemetry row with no or unreadable cwd, a worktree path that no longer exists, and a `mktemp` failure (which skips the file walk). None of these observed anything, yet each returns `dark`. `resolve_page` then escalates on an unobserved state, which is what the `unknown` state was introduced to prevent.

### 5. The deadline clock is shared across page states, so the same-sweep guard can be bypassed

- **What:** The `.page` stamp is written by any state's first page (PAST-THRESHOLD, DEAD, …). The STALL? guard treats any existing `.page` as a "pre-existing STALL? page".
- **Where:**
  - L204 `[ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"`
  - L508 `local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`
  - L510 `[ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"`
- **Why it is wrong:**
  1. A session is PAST-THRESHOLD-paged at time P. That branch never clears `.page`.
  2. Later its telemetry and transcript go stale, and the first STALL? sweep sees `had_page=1` with `now-P` ≫ `DEADLINE_S`.
  3. It re-reads effects "since P", in the same sweep as the STALL? page.

  If that re-read is dark, it escalates immediately with no deadline wait. That produces the same-sweep STALL?→ESCALATED double notify the guard was written to prevent.

### 6. `pid_alive_owner` accepts any process whose command line contains "claude"

- **What:** The owner test is a case-insensitive substring match over the whole argv.
- **Where:** L433 `ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"`
- **Why it is wrong:** A dead session's pid can be recycled to an unrelated process whose argv merely mentions a `~/.claude/...` path or a `*claude*` repo. Examples are a hook script, this supervisor itself, or `git -C .../claude-x`. That pid reads as a live owner.
  - The DEAD branch is skipped, so there is no checkpoint and no DEAD page.
  - The row takes the STALL? path instead.
  - Once past `GC_S`, `gc_stale` silently drops it. This is the "insurance lost" outcome the GC guard says must never happen.

### 7. The transcript path mangling does not match the projects-dir slug for many cwds

- **What:** The slug replaces only `/` and `.`. Claude Code's project-dir naming also replaces other non-alphanumerics, such as `_` and spaces.
- **Where:** L392 `slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"`
- **Why it is wrong:** For a cwd like `.../doc_classifier`, which the file itself names, the transcript is never found. The age becomes 999999999, so the warm-transcript exemption never applies. Healthy telemetry-stale sessions there go STALL? every cycle, which is the oscillation the exemption exists to stop.

### 8. The permission-beacon dead-session reap uses bare `kill -0`

- **What:** REAP 1 decides "owning session dead" with `kill -0`, the check this file elsewhere documents as lying about recycled pids.
- **Where:** L555 `if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`
- **Why it is wrong:** A hard-killed session whose pid was recycled to any process keeps its beacon "alive". The operator gets a PERMISSION-PENDING page for a prompt that no longer exists. Each new such beacon ts pages again, until the 24h horizon.

### 9. A beacon whose telemetry row was reaped earlier in the same sweep cannot be pid-checked

- **What:** `reap_clean` deletes the telemetry row during `assess`. `sweep_permission_pending` runs later in the same sweep and relies on that row to prove the session dead.
- **Where:**
  - L376 `rm -f "$TEL_DIR/$1.json" 2>/dev/null || true`
  - L553 `if [ -f "$tel" ]; then`
- **Why it is wrong:** Consider a dead worker with a clean, landed worktree and a leftover beacon (hard kill, no SessionEnd). Its row is reaped first. The beacon then skips REAP 1 and, past 120s, is paged as a live PERMISSION-PENDING session for a session that is gone.

### 10. The self-check "enumerated" count includes rows that are not live sessions

- **What:** `n` counts every telemetry file. That includes rows whose pid is gone, rows `reap_clean`ed in this same sweep, and rows with no pid. This count is compared against the number of live panes.
- **Where:**
  - L633 `n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`
  - L608 `delta=$(( live - enum ))`
- **Why it is wrong:** Take 3 live panes, only 1 of which has telemetry, plus 2 dead-session rows. Then enum=3, delta=0, and no blind-spot page fires. The 2 live, unmonitored panes stay invisible, which is the exact condition V3 claims to detect.

### 11. B-1 coverage is lost for a past-threshold session with stale telemetry

- **What:** B-1 requires fresh telemetry. A live owner with stale telemetry but a warm transcript (or the registered desk) falls through the STALL? branch to OK.
- **Where:**
  - L500 `if [ "$tage" -ge "$STALL_S" ]; then`
  - L516 `if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then`
  - L521 `clear_page "$sid"; echo 0`
- **Why it is wrong:** Consider a session past T that is inside one long operation. The file notes such a session renders zero statusline updates, so its telemetry goes stale while its transcript stays warm. It is neither STALL? nor PAST-THRESHOLD. It is classified OK and its pages are cleared. That is the "working-past-boundary, never Stops" case the B-1 header claims to cover.

### 12. Unescaped strings are interpolated into IDL JSON

- **What:** `sid` (from telemetry) and `cwd` are embedded raw into JSON records. The file's own comment says never to raw-`%s` strings into JSON.
- **Where:**
  - L205 `idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""`
  - L339 `idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
  - L375 `idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""`
  - Also the `checkpoint_timeout` record at L336.
- **Why it is wrong:** A cwd or sid containing `"` or `\`, which is legal in macOS paths, produces a malformed IDL line. Parsers of the IDL then drop or choke on exactly the page, checkpoint and reap records meant to make these acts auditable.
