# Review of `bin/cc-teardown`

I found 11 defects. Line numbers are my count of the brief. The quoted code is verbatim and is the authoritative anchor.

---

### 1. An empty target is reported as success (exit 0)
- **What:** When the first argument is an empty string, the script prints usage and exits 0, which its own contract defines as "torn down + both legs effect-verified".
- **Where:** line 864 — `  -h|--help|"") usage; exit 0 ;;`
- **Why it is wrong:** Suppose a caller runs `cc-teardown "$pane" --done-evidence x` and `$pane` is empty (for example, a failed harvest).
  - `"${1:-}"` is `""`, so the usage branch fires and the script exits 0.
  - No record is written and nothing is closed.
  - The caller reads exit 0 as a verified teardown: a failure reported as success.

### 2. The tty-exclusivity guard is skipped when the target pid is dead or empty, but the pane is still force-closed
- **What:** The collateral-close guard runs only when the target pid is alive, yet leg 2 force-closes the whole pane regardless.
- **Where:** line 577 — `  if pid_alive "$pid"; then` (guarding `tty_foreign`), then line 609 — `  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
- **Why it is wrong:** Take a registry row whose claude pid has exited, or whose pid is null (`--all` includes retained rows), while the pane is still present. The pane now hosts other live work, such as an operator's `vim` or a build in the leftover shell.
  - The idempotent short-circuit does not fire, because the pane is present.
  - Step 2c is skipped entirely.
  - `it2 session close -f` then kills every process on the pane tty with no exclusivity check. This is exactly the "collateral close" the guard claims to prevent.

### 3. An empty or unknown pid is recorded as "process gone, effect-verified"
- **What:** The process leg is marked verified whenever `pid_alive` is false, including when there was never a pid to observe.
- **Where:** lines 613–614 — `  if ! pid_alive "$pid"; then` / `    proc_gone=1`
- **Why it is wrong:** `pid_alive` returns false for an empty `$pid`. When `resolve()` returns a row without a pid, nothing is ever killed or observed.
  - The record still says `both_legs_verified:true` with "process gone".
  - The claude process that actually lives in that pane was never identified or checked.
  - This is an action taken, and success reported, on an unproven premise.

### 4. `tty_foreign` reports "exclusive" when the tty process table cannot be read
- **What:** A failed or empty `ps -t` read yields a count of 0 foreign processes instead of −1 (indeterminate).
- **Where:** line 301 — `  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"` (result is never checked; `fp` stays 0 at line 323 `  echo "$fp"`)
- **Why it is wrong:** If `ps -t` errors or returns nothing (bad tty name, ps failure, or load), both loops iterate over nothing.
  - The function prints `0`, and step 2c treats the pane as tty-exclusive.
  - This contradicts the function's "-1 = tty undeterminable (fail-closed)" contract: it fails open.
  - A table that does not even contain the target pid is plainly not proof of exclusivity.

### 5. The adoption belt treats every who-oracle failure other than rc 2 as "nobody typed"
- **What:** Only rc 2 is routed to `beat_or_refuse`; any other failure proceeds toward the close.
- **Where:**
  - line 511 — `        if [ "$irc" = 2 ]; then`
  - line 517 — `        case "${iep:-}" in ''|*[!0-9]*) iep="" ;; esac`
- **Why it is wrong:** The code's own comment states "Only the rc-1 world … is a FACT that may license a close". Two other outcomes still license it:
  - `ci_last_interactive_epoch` returns rc 127 (the function sourced but a dependency is missing), rc 3, or any other unexpected code.
  - It returns rc 0 with non-numeric or empty output.
  
  In both cases `iep` is blanked, the belt is silently passed, and a possibly operator-adopted pane proceeds to teardown.

### 6. SIGKILL escalation is not pinned by lstart
- **What:** The kill loop keys only on the pid, although the comment claims "lstart pin beats pid-recycling" for leg 1.
- **Where:**
  - line 601 — `    for _ in $(seq 1 $((TERM_GRACE_S * 5))); do pid_alive "$pid" || break; sleep 0.2; done`
  - line 603 — `      kill -KILL "$pid" 2>/dev/null || true`
- **Why it is wrong:** Suppose the target exits on SIGTERM and its pid is reused before the next 0.2 s poll.
  - `pid_alive` sees the new, unrelated process as "still alive".
  - After the grace period it sends SIGKILL to that stranger.
  - `lstart_before` is only consulted afterwards, in effect-verify, never before either signal.

### 7. The teardown marker is left behind when the process survives (the FAIL path)
- **What:** The marker is written before acting and is never withdrawn when the process leg fails.
- **Where:** line 593 — `  write_teardown_marker "$paneUUID" "$sess_id" teardown` (the exit-5 path at lines 627–628 leaves it in place)
- **Why it is wrong:** If TERM and KILL both fail to stop the target (`proc_gone=0`, exit 5), the session is still alive but carries a fresh `mode=teardown` marker.
  - A genuine crash of that live session within the reader's 30-minute window will be classified as a deliberate teardown.
  - That is the exact masking the block's own comment says it avoids.
  - The same happens when the pid had already died on its own before cc-teardown ran: a real crash gets relabelled as a teardown.

### 8. Assignee identity is "proven" from flattened text, not from a real argv token
- **What:** `ps -o args=` joins argv with spaces, so the `--agent-id` "token" check is a substring match over prose.
- **Where:**
  - line 270 — `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`
  - line 271 — `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"`
- **Why it is wrong:** Consider a `claude.exe` process on the target tty whose prompt or TASK argument contains `… --agent-id foo@session-<lead> …`.
  - It passes the argv[0] check, the substring check, the `@session-$lead` suffix check, and the character-shape check.
  - It is then adopted and killed.
  - `${rargs#*--agent-id }` also takes the first occurrence, which can be the prose one rather than the real flag.
  
  This is the "text is never evidence" case the header says the check prevents.

### 9. A nonzero gate exit other than 2 or 10 escapes the exit-code contract
- **What:** The recorded decision is normalised to DEFER, but the process exits with the gate's raw return code.
- **Where:** line 573 — `    say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:** If the gate is missing (rc 127) or crashes (rc 1), the record says DEFER but cc-teardown exits 127 or 1.
  - The documented contract is only 0/10/2/5.
  - A caller branching on 10 for DEFER and 2 for REFUSE gets an undocumented code.
  - The recorded outcome and the returned outcome disagree.

### 10. Selftest REFUSE assertions can pass for the wrong reason, and the selftest is not hermetic
- **What:** The REFUSE scenarios check only `rc=2` plus `decision=REFUSE`, never `reason_kind`. Meanwhile `run_td` leaves the operator-adoption belt reading the real host environment.
- **Where:**
  - line 784 — `  [ "$rc" = 2 ] && [ "$(last_decision)" = REFUSE ] \` (scenario 5; same shape at lines 792, 801, 808, 844)
  - `run_td` at lines 712–717 sets no `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS`, `CLAUDE_CONFIG_DIR`, or `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE`.
- **Why it is wrong:** On a host where `hooks/lib/cc-interactive.sh` is absent, or a real `s.jsonl` exists, the belt REFUSEs every scenario (`presence-unprovable` or `operator-adopted`).
  - Scenario 5 ("missing done-evidence → REFUSE") then passes even if the gate's done-evidence check were broken.
  - The same applies to scenario 6 (unknown target) and to the rc and decision half of scenario 13.

### 11. Selftest bookkeeping claims more than it checks, and breaks under a symlink
- **What:** Two problems:
  - Check 11 claims every branch writes a record but inspects only the last scenario.
  - The gate path is not resolved through symlinks.
- **Where:**
  - line 853 — `  [ -n "$(last_decision)" ] && okp "no-silent-record: every decision branch writes an outcome record" \`
  - line 642 — `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
- **Why it is wrong:**
  - The "every branch" check passes if only scenario 13's branch recorded; the others are not checked for having written anything.
  - When `--selftest` is run via the `~/.claude/bin/cc-teardown` symlink (the documented deploy of "only this one file"), `GATE_SELF` points at a non-existent sibling in `~/.claude/bin`. That differs from `HERE`, which the main script resolves through the symlink.
  - Every gated scenario then gets rc 127 and the selftest fails spuriously.
