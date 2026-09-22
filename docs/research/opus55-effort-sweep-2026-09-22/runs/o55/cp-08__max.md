1. **What:** The top-level dispatcher treats an empty first argument, or no arguments at all, as a help request and exits 0. The contract reserves exit 0 for "torn down + both legs verified".
   **Where:** line 864: `  -h|--help|"") usage; exit 0 ;;`
   **Why it is wrong:** Suppose a caller runs `cc-teardown "$pane" --done-evidence … --decided-at …` and `$pane` is empty because an upstream extraction failed. The call never reaches `main`, whose line 407 would `die` with exit 2. It returns 0 with nothing resolved, gated, closed or recorded. The caller then logs a successful teardown of a session that is still running.

2. **What:** The assignee identity check treats `--agent-id` as a real argv token, but it is a substring search over the space-joined `ps -o args=` string, so prose text can satisfy it.
   **Where:** lines 270–271:
   - `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`
   - `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"   # the token AFTER the real flag`
   
   **Why it is wrong:** `args=` flattens argv into one string.
   - A `claude.exe` on the pane tty whose prompt or task argument contains `… --agent-id foo@session-<lead> …` passes both lines.
   - `${rargs#*--agent-id }` takes the first occurrence anywhere, even one ahead of the process's own real flag.
   - The extracted token is well-shaped, so it passes line 276.
   - The unrelated process is adopted, killed, and its pane force-closed. Lines 228–233 claim this guard excludes exactly this case.

3. **What:** When the target's transcript cannot be resolved, the operator-adoption belt is skipped and the presence beat is never consulted.
   **Where:**
   - line 501: `      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"`
   - line 509: `      if [ -n "$atj" ]; then`
   - line 288: `    sess_id="$ASSIGNEE_SID"`
   
   **Why it is wrong:** The belt falls straight through to the close in these cases:
   - a handed-off session, whose transcript was renamed to `.jsonl.handed-off` (handed-off leads are a primary reaper cause);
   - a missing transcript file;
   - an assignee adopted without `--assignee-sid`, where the empty sid makes line 343 return 1.
   
   This happens even when the beat system is live and shows an operator prompt seconds ago. `beat_or_refuse`'s own contract (lines 357–360) says an unresolved transcript is gap (b) and must go to the second oracle. Line 416 also claims downstream gates stay "fully armed".

4. **What:** Only exit status 2 from `ci_last_interactive_epoch` is treated as "cannot read"; every other failure allows the close.
   **Where:**
   - line 511: `        if [ "$irc" = 2 ]; then`
   - line 517: `        case "${iep:-}" in ''|*[!0-9]*) iep="" ;; esac`
   
   **Why it is wrong:** The sourced function might fail with another status, such as 127 from a missing helper or 124/130 from interruption. It might also return 0 with non-numeric output. In either case line 517 blanks `iep` and the belt passes. Lines 513–514 say only the rc-1 result ("parsed, no operator turn") may allow a close.

5. **What:** The tty-exclusivity guard only runs when the recorded pid is alive, but the pane is force-closed either way.
   **Where:**
   - line 577: `  if pid_alive "$pid"; then`
   - line 609: `  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
   
   **Why it is wrong:** Take a registry pid that is dead or empty (`resolve` accepts a row without `pid`) while the pane still exists. One example is the /handoff --recycle-in-place window, before the successor overwrites the row. In that case:
   - The identity pin (lines 449–456) passes because `now_lstart` is empty.
   - The idempotent exit does not fire because the pane is present.
   - No occupancy check runs, and `close -f` kills whatever now lives in the pane: the booting successor, or an operator's editor or build.
   - Lines 613–614 then count the process leg as gone and record TEARDOWN with both legs verified.

6. **What:** `tty_foreign` reports 0 foreign processes when the `ps -t` table read fails or comes back empty.
   **Where:** line 301: `  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"`
   **Why it is wrong:** The target itself is on that tty, so an empty table can only mean a failed read whose error was swallowed. Both loops see nothing, `fp` stays 0, and the caller treats the tty as exclusive and proceeds to the forced close. This fails open, contradicting the "-1 = tty undeterminable (fail-closed)" contract on line 296.

7. **What:** Name resolution silently picks the first of several matching rows.
   **Where:** line 329: `     '(map(select(.paneUUID==$t)) + map(select(.name==$t))) | .[0] // empty' 2>/dev/null)"`
   **Why it is wrong:** `--all` includes retained (dead) sessions. If a dead row with the same name comes before the live one, its pid is dead and its old pane is absent. Lines 459–463 then return ALREADY-GONE with exit 0 while the live session is never touched. In the opposite order, a different live session than intended is gated and closed.

8. **What:** The blind-enumerator guard only catches a completely empty list; a non-empty list that cannot see the target reads as "absent".
   **Where:**
   - line 198: `  [ "$n" -eq 0 ] && return 2                        # zero enumerated ⇒ blind enumerator ⇒ indeterminate`
   - line 201: `  return 1`
   
   **Why it is wrong:** Lines 186–188 say it2 walks only app.windows and name buried sessions as invisible to it. If the target is buried while any other pane is listed, the function returns 1. That gives a false ALREADY-GONE when the pid is dead, or a false "pane absent" TEARDOWN verification after the kill while the pane survives.

9. **What:** The selftest looks for the safety gate next to the unresolved `$0` instead of the symlink-resolved `$HERE`.
   **Where:** line 642: `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
   **Why it is wrong:** The deployed layout is a `~/.claude/bin/cc-teardown` symlink with only this one file deployed (lines 72–73). Run through that symlink, the gate path does not exist, so every scenario that reaches the gate gets rc 127, recorded as DEFER. The teardown, fail-loud, dirty, unpushed, missing-evidence, tty-busy and blind-enumerator scenarios then go RED for reasons unrelated to the branch they test. Production is unaffected because line 82 uses `$HERE`.
