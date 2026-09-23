# Review of `bin/cc-teardown`

I found 12 defects. Line numbers are my own count of the brief; the quoted code is verbatim and is the reliable anchor. They are ordered roughly by severity.

---

### 1. An empty target argument exits 0, the "torn down + verified" code

- **What:** When the first argument is an empty string, the script prints usage and exits 0.
- **Where:** line ~864 — `  -h|--help|"") usage; exit 0 ;;`
- **Why it is wrong:** Suppose a caller builds its target from a variable that came back empty, such as `cc-teardown "$pane" --done-evidence x` with `$pane=""`. `${1:-}` is then `""`, so the dispatcher never reaches `main`. Nothing is resolved, gated, acted on, verified or recorded, yet the process exits 0. The header contract defines exit 0 as "torn down + BOTH legs effect-verified", so this is a failure reported as a success.

### 2. The kill acts on the registry pid without proving it is still the target claude process

- **What:** Without `--expect-pid` or `--expect-lstart` (manual and desk callers), the script sends TERM and then KILL to whatever process now holds the registry pid.
- **Where:**
  - line 332 — `  pid="$(printf '%s'      "$obj" | jq -r '.pid // empty')"`
  - line 596 — `  local lstart_before; lstart_before="$(pid_lstart "$pid")"`
  - line 600 — `    kill -TERM "$pid" 2>/dev/null || true`
- **Why it is wrong:**
  - `cc-sessions --all` includes *retained* rows, so the target's claude may be long dead and its pid reused by an unrelated process.
  - `pid_alive` is then true, and `tty_foreign` examines the *stranger's* tty, never checking it against the pane's tty.
  - `lstart_before` is sampled from the stranger just before the kill, so the "lstart pin beats pid-recycling" comment protects only the verify step, not the kill.
  - Result: an unrelated process is killed, and verify can still report success.

### 3. The tty-exclusivity guard is skipped whenever the target pid is dead but the pane is still present

- **What:** The tty-exclusivity check only runs while the target pid is alive, but the pane is force-closed either way.
- **Where:**
  - line 577 — `  if pid_alive "$pid"; then`
  - line 609 — `  local close_rc; cct_bounded "$IT2" session close -f -s "$paneUUID" >/dev/null 2>&1; close_rc=$?`
- **Why it is wrong:** Suppose claude exited but the pane lives on, and the operator is now running a build or vim in that pane's shell. The idempotent short-circuit does not fire, because the pane is present. Guard 2c is skipped because the pid is dead. `session close -f` then kills the foreign work. This is exactly the "collateral close" that the guard claims to prevent.

### 4. `tty_foreign` fails open when the tty process table cannot be read

- **What:** If the `ps -t` read fails or returns nothing, `tty_foreign` reports 0 foreign processes, which reads as "exclusive", instead of -1 ("indeterminate").
- **Where:**
  - line 301 — `  tbl="$("$PS_BIN" -t "$tty" -o pid=,ppid=,comm= 2>/dev/null)"`
  - line 323 — `  echo "$fp"`
- **Why it is wrong:** The target pid is known to be on that tty, so an empty table can only mean the read failed. Even so, `fp` stays 0 and teardown proceeds. The guard is silently skipped rather than failing closed, which contradicts the "-1 = undeterminable (fail-closed)" contract.

### 5. Assignee `ALREADY-GONE` reports success with both legs verified while the process leg was never checked

- **What:** When the assignee pane is absent, the script records `both_legs_verified=1` and exits 0 without identifying or checking any process.
- **Where:**
  - line 422 — `        1) record ALREADY-GONE idempotent "assignee pane '$TARGET' is absent from a READABLE it2 enumeration — nothing to close" 1`
  - line 423 — `           say "OK — assignee pane already gone (idempotent success, exit 0)"; exit 0 ;;`
- **Why it is wrong:** The contract for idempotent success is "already-gone pane + **dead pid**". On this path `pid` is empty and never checked. The assignee `claude.exe` may still be alive, for example if the pane is merely missing from a partially-blind but non-empty enumeration. The success record is therefore unproven.

### 6. The "real `--agent-id` argv token" guard is applied to flattened `ps args=` text, so it cannot tell a token from prose

- **What:** The check that `--agent-id` is a real argv token runs on a space-joined string in which argv boundaries are gone.
- **Where:**
  - line 270 — `    case " $rargs " in *" --agent-id "*) ;; *) continue ;; esac`
  - line 271 — `    agid="${rargs#*--agent-id }"; agid="${agid%% *}"`
- **Why it is wrong:** `ps -o args=` joins argv with spaces. Consider a `claude.exe` whose prose task argument contains `... --agent-id foo@session-<lead> ...`, which is the exact incident the comment cites. It passes both the " --agent-id " match and the shape check. The script then adopts and kills that unrelated session. The guard does not cover the prose case it claims to exclude.

### 7. The gate's exit code is passed through verbatim, even when it is outside the contract

- **What:** Any non-zero gate return code becomes the script's exit code, and a missing or crashing gate is recorded as `DEFER`.
- **Where:**
  - line 569 — `    [ -n "$gdec" ] || { [ "$grc" = 2 ] && gdec=REFUSE || gdec=DEFER; }`
  - line 573 — `    say "$gdec — $greason (exit $grc)"; exit "$grc"`
- **Why it is wrong:** If the gate binary is missing (rc 127) or crashes (rc 1), the record says "DEFER" (work-unsafe, retry later). The process exits 127 or 1, which is none of 0/10/2/5. A caller that dispatches on the documented codes misclassifies it, and a broken actuator is reported as a work-safety verdict.

### 8. The selftest resolves the gate from `$0` without following symlinks

- **What:** `GATE_SELF` is built from the unresolved `$0`, although the header says this file is deployed as a `~/.claude/bin/cc-teardown` symlink.
- **Where:** line 642 — `  GATE_SELF="$(cd "$(dirname "$0")" && pwd)/cc-teardown-safety-gate.sh"`
- **Why it is wrong:** Running `~/.claude/bin/cc-teardown --selftest` through the symlink points `CC_TEARDOWN_GATE_BIN` at `~/.claude/bin/cc-teardown-safety-gate.sh`, which does not exist. The gate then returns rc 127, and scenarios 1–5, 10, 12 and 13 fail for a reason unrelated to the branch under test. `main` avoids this by using `HERE`; the selftest ignores it.

### 9. The selftest is not hermetic with respect to the operator-adoption belt

- **What:** `run_td` does not steer `CC_INTERACTIVE_LIB`, `CC_CLASSIFY_PROJECT_ROOTS`, the `cc-beat.sh` lookup or `CC_CLASSIFY_*`, so the belt reads the host's real `~/.claude` state.
- **Where:** lines 712–717 (the `run_td` environment block), e.g. `    CC_TEARDOWN_DIR="$d/tdmark" \`
- **Why it is wrong:**
  - On a host without `hooks/lib/cc-interactive.sh` next to the script, every gated scenario goes through `beat_or_refuse`. It then REFUSEs, or proceeds, depending on whether the host's beat system is live.
  - A host `CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1` silently disables the belt.
  - Either way, the assertions pass or fail because of the host environment, not the branch being tested.

### 10. The operator-adoption belt is silently disarmed when `sess_id` is empty, despite "fully armed"

- **What:** With an empty `sess_id`, `find_transcript` fails and the belt proceeds with no presence check at all.
- **Where:**
  - line 288 — `    sess_id="$ASSIGNEE_SID"`
  - line 501 — `      atj="$(find_transcript "$sess_id" 2>/dev/null || true)"`
- **Why it is wrong:** An `--assignee-of` caller that omits `--assignee-sid` (or a registry row without `session_id`) yields `sess_id=""`. `find_transcript` returns 1 and `atj` is empty, so no adoption check and no beat check runs. The main-path comment claims "every downstream gate then runs UNCHANGED and fully armed", but the presence guard is actually off for this whole class.

### 11. The `tty_foreign` allowlist cannot match under the comm truncation the file itself documents

- **What:** Allowlist entries are matched against `basename(comm)`, but the file states that macOS truncates `comm` to 16 characters.
- **Where:** line 318 — `    case "$base" in -zsh|zsh|-bash|bash|-sh|sh|login|tmux|screen|gitstatusd*|caffeinate) continue ;; esac`
- **Why it is wrong:** Under that truncation, `/usr/bin/caffeinate` arrives as `/usr/bin/caffein`, giving a basename of `caffein`. A `gitstatusd` under `~/.cache/...` arrives as `/Users/chrisren/`, giving an empty basename. Neither matches, so these are counted as foreign. Any pane running p10k's gitstatusd DEFERs as `tty-busy` forever, and the allowlist does not cover what it names.
- **Confidence:** Lower. This depends on the truncation claim at lines 261–263 being accurate.

### 12. Several REFUSE exits write no record

- **What:** Some exit-2 refusals leave no outcome record, contrary to the "RECORD every branch" / "NO silent teardown" contract.
- **Where:**
  - line 403 — `      --*) die "unknown option '$1'" ;;`
  - line 407 — `  [ "${#args[@]}" -ge 1 ] || die "usage: cc-teardown <pane-uuid|name> --done-evidence <text>"`
  - line 111 — `command -v jq >/dev/null 2>&1 || { echo "cc-teardown: jq required" >&2; exit 2; }`
- **Why it is wrong:** Three cases exit 2 (REFUSE) with nothing written to `~/.claude/cc-teardown/`:
  - an autonomous caller passing an option this version does not know,
  - a call with no target,
  - a machine without `jq`.

  In each case the refusal is unauditable.
