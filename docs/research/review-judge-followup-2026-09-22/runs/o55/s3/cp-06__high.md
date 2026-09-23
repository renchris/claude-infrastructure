# Review of `scripts/lead-supervisor.sh`: defects found

Line numbers were counted from the brief. The quoted code is verbatim.

---

### 1. A probe cut by SIGKILL is not recognised as a cut, so it reads as `dark`

- **What:** `sup_bounded` always passes `-k 5`, but the callers only treat rc `124` as "cut". When `timeout` has to escalate to SIGKILL, it exits 137.
- **Where:** 80 `"$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`; 269 `[ "$rc" = 124 ] && { printf 'unknown'; return; }`; 285 `[ "$rc" = 124 ] && { printf 'unknown'; return; }`
- **Why it is wrong:** The `-k` comment names the target case: a child that ignores TERM. For that child the exit code is 137, not 124.
  - A hung `git log` or `find` then leaves `last_commit`/`hit` empty.
  - The verdict stays `dark`, and `resolve_page` escalates.
  - This is the "cut probe folded into dark" outcome that lines 256–262 say must never happen.

### 2. `work_landed` treats a failed or cut `git status` as a clean tree

- **What:** Status output is captured without checking its return code.
- **Where:** 355 `[ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
- **Why it is wrong:** A timeout (124 or 137) or any other `git status` error produces empty stdout, which passes the `-z` test as clean.
  - If `rev-list --count` then reports 0 ahead, the dead worker is `reap_clean`'d.
  - That deletes its telemetry row and clears its page, so no checkpoint and no DEAD page are produced.
  - The dirty worktree is lost silently.
  - This contradicts lines 348–350, which say a timed-out probe "must never be read as 'landed'".

### 3. `checkpoint_preserve` logs a successful checkpoint when none happened

- **What:** Every outcome except rc 124 is recorded as `checkpoint … dead-lead-preserve`.
- **Where:** 325 `if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`; 332 `if [ "$rc" = 124 ]; then`; 338 `idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
- **Why it is wrong:** The success record is written in all of these cases:
  - `teammate-checkpoint.sh` is not on PATH. This is likely under launchd's minimal PATH, which the file itself warns about. `rc` stays 0.
  - The script fails with rc 1, 2, and so on.
  - The script is SIGKILL-cut and exits 137.

  In each case the IDL says the insurance was taken when it was not.

### 4. The DEAD page always claims the worktree was preserved

- **What:** The page text says the checkpoint succeeded regardless of what `checkpoint_preserve` did.
- **Where:** 485 `checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`
- **Why it is wrong:** The claim is also made after a timeout, which line 335 records as "NOT checkpoint-preserved". It is made when `cwd` is empty or missing, where line 324 returns 0 without doing anything. It is made when the script is absent.
  - The operator is told the insurance exists when it does not.

### 5. The pid-owner check is a case-insensitive substring match anywhere in argv

- **What:** `grep -qiF "claude"` accepts any process whose command line contains "claude".
- **Where:** 432 `ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"`
- **Why it is wrong:** A recycled pid now running any of these still counts as the "owner":
  - a hook, e.g. `bash ~/.claude/hooks/...`
  - a `git -C …/.claude…` call
  - an MCP/node child with a `.claude` path
  - this supervisor itself, if installed under `~/.claude`

  Consequences:
  - The DEAD branch (477) is skipped, so there is no checkpoint and no DEAD page.
  - The row is STALL?-paged instead, and then GC'd at 453–455.

  The guard does not cover the "recycled to non-claude" class it claims to cover. Compare the strict argv0 test used by `live_pane_count` (594).

### 6. PAST-THRESHOLD and STALL? share one `.page` deadline clock, which defeats the same-sweep guard and the deadline

- **What:** `page()` stamps `.page` for every state. The STALL? branch treats any existing `.page` as a pre-existing STALL? page.
- **Where:** 203 `[ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"`; 507 `local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`; 509 `[ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"`
- **Why it is wrong:** Take a session paged PAST-THRESHOLD that later goes telemetry-stale.
  - On its very first STALL? sweep, `had_page=1` and the deadline has already expired, because it is measured from the old PAST-THRESHOLD stamp.
  - The effects re-read runs immediately, with `since` set to that old time.
  - The session is then either escalated with no deadline window, or voided on activity from before the stall began.

### 7. Sticky ESCALATED suppresses the B-1 PAST-THRESHOLD advisory after a recovery

- **What:** Once `.notified` holds `ESCALATED`, every non-DEAD state is damped until the OK branch clears it. The OK branch is only reached below threshold.
- **Where:** 215 `[ "$last" = "ESCALATED" ] && [ "$2" != "DEAD" ] && return 0`
- **Why it is wrong:** An escalated session can recover (fresh telemetry again) while its `used_pct` is ≥ T.
  - It then hits the PAST-THRESHOLD branch on every sweep, never reaches `clear_page`, and its `/handoff` advisory is never sent.
  - The comment's assumption that "a true recovery" clears the marker only holds for recoveries that land below threshold.

### 8. The self-check's "unreadable ps ⇒ ABSTAIN" guard can never fire

- **What:** The awk `END { print c+0 }` always emits a number, even when `ps` fails or outputs nothing.
- **Where:** 597 `END { print c+0 }'`; 606 `case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ`
- **Why it is wrong:** A failed `ps` yields `live=0`, which is treated as a valid reading.
  - The delta becomes ≤ tolerance, the "recovery" branch resets the state to `0 0`, and the blind-spot detector is silently disarmed.
  - The code does not abstain as documented.

### 9. The self-check compares live panes against all telemetry rows, including dead and stale ones

- **What:** `n` counts every `*.json` row, including rows whose pid is gone.
- **Where:** 632 `n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`; 642 `self_check "$n"`
- **Why it is wrong:** Stranded DEAD rows are never removed; they persist and are re-paged every sweep. Rows reaped by `reap_clean` in this same sweep are still counted too.
  - Example: 3 live panes, 1 of them in telemetry, plus 2 dead rows. Then `enum=3`, `delta=0`, and nothing is reported.
  - The unseen live sessions are masked by dead rows, which is exactly the blind spot this check exists to catch.

### 10. Permission-beacon REAP 1 uses bare `kill -0`, so it is fooled by a recycled pid

- **What:** A beacon's owner is judged alive with `kill -0` rather than `pid_alive_owner`.
- **Where:** 554 `if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`
- **Why it is wrong:** Suppose a session is hard-killed with a prompt pending, and its pid is recycled to an unrelated process.
  - The beacon is not reaped.
  - A "PERMISSION-PENDING … blocked" page is sent for a session that no longer exists.
  - The false beacon is kept until the 24h horizon.

  This is the "kill -0 lies" class that lines 423–428 say is handled.

### 11. A beacon whose telemetry row was just reaped or GC'd is paged as a live permission prompt

- **What:** When the telemetry file is absent, the owner check is skipped entirely and the beacon falls through to PAGE.
- **Where:** 552 `if [ -f "$tel" ]; then`; paired with 375 `rm -f "$TEL_DIR/$1.json" 2>/dev/null || true`
- **Why it is wrong:** In the same sweep, `assess` runs first and `reap_clean` deletes the dead session's row (or `gc_stale` does, at 455).
  - `sweep_permission_pending` then finds no telemetry and cannot pid-check.
  - It pages PERMISSION-PENDING for a dead session.
  - Neither `reap_clean` nor `gc_stale` removes the beacon.

### 12. The transcript slug only mangles `/` and `.`

- **What:** The projects-dir slug is built by replacing only `/` and `.` with `-`.
- **Where:** 391 `slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'`
- **Why it is wrong:** Claude Code's project-dir sanitisation replaces every non-alphanumeric character, not just `/` and `.`.
  - For a cwd containing `_`, a space, and so on, the computed path does not exist. `doc_classifier`, cited in this file, is an example.
  - `transcript_age` therefore returns 999999999 ("cold").
  - The warm-transcript exemption never applies to that cwd, and the healthy live session STALL?-pages and can ESCALATE.

### 13. "No channel wired" is a silent non-delivery

- **What:** `send_page` returns 1 with no IDL record and no log line when cc-notify is unresolved or the role file is empty.
- **Where:** 152 `[ -n "$NOTIFY_BIN" ] || return 1`; 155 `[ -n "$target" ] || return 1`
- **Why it is wrong:** Under launchd's bare PATH, where lines 116–117 say resolution can fail, or with an emptied role file:
  - Every page is recorded in the IDL as `page`.
  - Nothing is delivered, and nothing ever says so.
  - This violates the "a failure is LOUD" contract of lines 144–145.

### 14. `gc_stale` drops live-owner rows on telemetry age alone *(lower confidence)*

- **What:** GC ignores the transcript-liveness signal that the file itself says is the correct one.
- **Where:** 451 `[ "$age" -ge "$GC_S" ] || continue` … 455 `rm -f "$f" 2>/dev/null || true`
- **Why it is wrong:** Lines 383–385 document a healthy session with 3.5-day-stale telemetry and a warm transcript.
  - After 6h, GC deletes that session's row on the unproven premise that it is "hung or pid-recycled".
  - If the session later dies, there is no row, so there is no DEAD page and no checkpoint.
  - This drops the insurance the GC comment claims is never dropped.

### 15. B-1 misses a past-threshold session whose statusline stopped but whose transcript is warm *(lower confidence)*

- **What:** The warm-transcript fall-through reaches the B-1 test, which requires *telemetry* age < STALL_S.
- **Where:** 515 `if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then`
- **Why it is wrong:** Consider a session inside one long operation past the threshold. This is the "working-past-boundary, never Stops" case that B-1 (line 23) claims to cover.
  - Its telemetry is stale, so B-1 is false.
  - It falls to OK, and `clear_page` is called.
  - No advisory is ever sent.

### 16. "Could not look" states are folded into `dark` *(lower confidence)*

- **What:** An empty or missing `cwd`, or a failed `mktemp`, leaves `verdict=dark`.
- **Where:** 265 `if [ -n "$cwd" ] && [ -d "$cwd" ]; then`; 276 `if [ -n "$ref" ]; then`
- **Why it is wrong:** No file-mtime observation was made in these cases, yet `resolve_page` escalates on the result.
  - This is escalation on an unobserved state, which lines 254–262 say must be reported as `unknown`.
