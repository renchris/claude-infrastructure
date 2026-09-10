Twelve defects found.

**1. `work_landed` reads a failed or timed-out `git status` as a clean tree.**
Where: line 355: `  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1`
Why: only stdout is tested, never the exit code. When `git status` is cut at 15s (rc 124) or fails (corrupt index, rc 128), stdout is empty, so the tree is treated as clean. If the worker made no commits (0 ahead), line 357 then returns "landed" and line 482 reaps the row and clears its pages. A dirty, unlanded worktree is silently dropped, the exact outcome lines 348 to 350 claim cannot happen.

**2. A checkpoint that never ran, or that failed, is recorded and paged as done.**
Where: line 330: `    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?` and line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
Why: if `teammate-checkpoint.sh` is not on PATH (line 325 false) rc stays 0 and line 338 logs a checkpoint. If the script exits non-zero other than 124, line 332 does not catch it and line 338 still logs a checkpoint. In both cases line 485 pages "worktree checkpoint-preserved". The insurance the DEAD page promises is absent and nothing says so.

**3. B-1 coverage is lost for the session it exists for: a live long turn past threshold.**
Where: line 515: `  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then` and line 520: `  clear_page "$sid"; echo 0`
Why: lines 382 to 385 document that telemetry stops updating during one long operation. A session at 90% inside a 30-minute-plus turn has a warm transcript (STALL exempt) but stale telemetry, so it fails the age test, falls to the OK branch, and its standing PAST-THRESHOLD page and notify marker are deleted. When the turn ends and the statusline renders, it is re-paged and the desk is re-notified.

**4. The sticky ESCALATED marker swallows a PAST-THRESHOLD page.**
Where: line 215: `  [ "$last" = "ESCALATED" ] && [ "$2" != "DEAD" ] && return 0`
Why: after an ESCALATED notify, if the session resumes with fresh telemetry at or above `T`, assess pages PAST-THRESHOLD every sweep, but this line returns before sending and never updates the marker. The operator was last told the session is dark and is never told it woke up past threshold. The OK-branch reset cannot run while fill stays at or above `T`.

**5. A session with no cwd, or a deleted cwd, is escalated as "confirms dark" without any observation.**
Where: line 264: `  local cwd="$2" since="$3" verdict=dark rc=0` and line 265: `  if [ -n "$cwd" ] && [ -d "$cwd" ]; then`
Why: when the guard on line 265 is false the whole probe is skipped and line 290 prints the default `dark`. `resolve_page` then calls `escalate_page`, whose page text asserts a re-read confirmed dark. By the file's own rule (lines 256 to 262) an unobservable probe must be `unknown`, not `dark`.

**6. Owner identity is a case-insensitive substring match on the whole command line.**
Where: line 432: `  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"`
Why: `ps -o command=` prints all arguments. A recycled pid now running any process whose args mention a `.claude` path (a hook script, `tail -f ~/.claude/...`, an MCP child) matches `claude` and is treated as the original owner. The DEAD branch is skipped, so no checkpoint and no DEAD page. The row takes the STALL path and `gc_stale` (which also trusts this function) drops the row and clears its pages at 6h, silently discarding the insurance line 443 says GC must never drop.

**7. A dead registered desk with a clean checkout is reaped as a clean worker completion.**
Where: line 482: `    if work_landed "$cwd"; then reap_clean "$sid" "$cwd"; echo 0; return; fi`
Why: the DEAD branch never consults `is_registered_desk`. A crashed desk sitting on a clean trunk checkout returns landed, its row is deleted, and the IDL records "clean-completion-shipped-clean-worktree". No page is raised. Lines 408 to 409 claim a dead desk is caught by this branch.

**8. Under GNU coreutils every effects re-read reads fresh.**
Where: line 277: `        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null`
Why: GNU `date -r` takes a filename, so `date -r 1720000000` fails and the fallback stamps the reference file at 1970. `find -newer` then matches every file and the verdict is always fresh, so a genuinely hung lead is voided forever. The script contemplates GNU hosts (line 394 has a GNU `stat` fallback), and a Homebrew gnubin PATH puts GNU `date` first on this Mac.

**9. Beacon reap 1 uses bare `kill -0`, the check the file says lies.**
Where: line 554: `      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`
Why: a recycled pid keeps a dead session's beacon alive. Past 120s the sweep pages PERMISSION-PENDING for a session that no longer exists, and the beacon lingers until the 24h horizon.

**10. An IDL `page` record is written on every sweep, before damping and before the send.**
Where: line 204: `  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""`
Why: lines 205 to 206 claim a re-sweep stays IDL-quiet. In fact a damped sweep, and a sweep where `send_page` returns 1 (no channel wired, no failure record), both log a page that was never sent. That is the "IDL showed a page" condition line 143 names as the wrong outcome.

**11. Untrusted strings are interpolated raw into IDL JSON.**
Where: line 374: `  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""` (also lines 335, 338, 457)
Why: a cwd or pid containing a double quote or backslash yields a malformed IDL line, the class lines 183 to 184 say `json_str` exists to prevent.

**12. The self-check "abstain on unreadable ps" guard can never fire.**
Where: line 606: `  case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ`
Why: line 597 (`    END { print c+0 }'`) always prints a number, so a failed `ps` yields live=0. Delta then goes non-positive, line 610 rewrites the state to `0 0`, and a persisting blind spot's `consec` counter is reset by one flaky `ps` call.
