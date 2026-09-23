# Review of `scripts/lead-supervisor.sh`

I found 15 defects. Line numbers count from `#!/bin/bash` as line 1.

---

### 1. A cut or failed `git status` reads as a clean tree, so unlanded work can be silently reaped

**What:** `work_landed` ignores the exit status of `git status --porcelain`, so a timed-out or failed probe produces empty output and passes the "clean tree" test.

**Where:** line 355
```
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```

**Why it is wrong:**
- **Trigger:** `git status` exceeds the 15s bound (rc 124/137) or fails for any other reason on a dead lead's worktree. A very large tree like the `doc_classifier` one the file mentions is enough.
- **Result:** stdout is empty, so `-z` is true and the tree is treated as clean. The `rev-list` check does not read the working tree, so it can still return 0 ahead, and the function returns 0 ("landed").
- **Effect:** `reap_clean` deletes the telemetry row and clears pages. There is no checkpoint and no page, even if the tree is dirty.
- The block comment at lines 348–350 promises the opposite: "a timed-out probe must never be read as 'landed' and silently reaped".

---

### 2. `timeout -k` returns 137, not 124, when it has to SIGKILL, so the "cut" branches miss the case `-k` was added for

**What:** Every cut-detection check tests only for rc 124. GNU `timeout` exits 137 (128+9) when it escalates to KILL after `-k 5`.

**Where:**
- line 80: `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
- line 269: `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- line 285: `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- line 332: `  if [ "$rc" = 124 ]; then`

**Why it is wrong:**
- **Trigger:** a git or find process that ignores TERM (a stalled volume or wedged client, the exact case the `-k` comment names). It gets killed and `timeout` returns 137.
- **In `reobserve_effects`:** 137 is not recognised as a cut. `hit`/`last_commit` are empty, so the verdict is `dark` and `resolve_page` escalates on a probe that never answered. This is the silence-escalation the `unknown` state was introduced to prevent.
- **In `checkpoint_preserve`:** a killed checkpoint skips the `checkpoint_timeout` record and falls through to `idl checkpoint ... dead-lead-preserve`.

---

### 3. `checkpoint_preserve` records a successful checkpoint when none happened

**What:** The success record is written for every outcome except rc 124. That includes "script not found" (rc stays 0, nothing runs) and any non-zero failure.

**Where:**
- line 325: `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
- line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`

**Why it is wrong:**
- **Script not on PATH:** `teammate-checkpoint.sh` is looked up by PATH only. The file itself says launchd's PATH is minimal, which is why `cc-notify` gets a multi-location lookup. Under launchd the script is likely not found, no checkpoint runs, and the IDL still records `checkpoint ... dead-lead-preserve`.
- **Script fails:** the same false record is written when the script exits 1 (or 137).
- **Effect:** the IDL shows the insurance was taken when it was not.

---

### 4. The DEAD page always tells the operator the worktree was checkpoint-preserved

**What:** The page detail hard-codes "worktree checkpoint-preserved", regardless of what `checkpoint_preserve` did.

**Where:** line 485
```
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong:**
- **Trigger:** the checkpoint times out (the branch that writes `checkpoint_timeout` "the dead lead's worktree is NOT checkpoint-preserved"). The same happens if the script was not found, if `cwd` is empty or missing (early `return 0` at line 324), or if the script failed.
- **Effect:** the operator-facing page still states the worktree was preserved. A failure is reported as a success.

---

### 5. `reobserve_effects` returns `dark` when it could not look at all

**What:** The verdict starts as `dark`, so every path that skips the probes reports "dark" instead of "unknown".

**Where:**
- line 264: `  local cwd="$2" since="$3" verdict=dark rc=0`
- line 276: `      if [ -n "$ref" ]; then`

**Why it is wrong:** Each of these conditions means nothing was observed, yet each returns `dark`, and `resolve_page` escalates:
- The telemetry `cwd` is empty.
- The worktree directory no longer exists.
- `mktemp` fails, so `ref` is empty and the find walk is skipped.
- `touch` fails, leaving `ref` at the current time, so nothing is ever "newer".

The header says escalation must never happen on an unobserved state.

---

### 6. The `date -r` fallback makes a failed timestamp conversion read as "fresh"

**What:** If `date -r "$since"` fails, the reference file is set to 1970, so every file in the tree counts as newer.

**Where:** line 277
```
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```

**Why it is wrong:**
- **Trigger:** GNU `date`, where `-r` takes a file rather than an epoch. The script clearly anticipates GNU tools: `transcript_age` has a GNU `stat` fallback.
- **Effect:** the verdict is always `fresh`, so a genuinely hung lead is voided every deadline and never escalated. The comment at line 260 calls this silently EXONERATING a hung lead.

---

### 7. The pid-ownership check accepts any process whose full command line contains "claude"

**What:** `pid_alive_owner` does a case-insensitive substring match of `claude` against the entire argv. It does not check that argv0 is the claude binary, as `live_pane_count` does.

**Where:** line 432
```
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong:**
- **Trigger:** a dead session's pid is recycled to an unrelated process whose arguments or path contain "claude" or "Claude". Examples: a hook or script under `~/.claude/...`, an MCP server, `Claude.app` helpers, or `jq` reading a `.claude` file.
- **Effect:** the process is treated as the live owner, so the recycled-pid-to-non-claude case the guard exists for is not routed to DEAD. The row is STALL?-paged, and then GC'd after 6h without checkpoint or DEAD page.

---

### 8. Permission-beacon REAP 1 uses bare `kill -0`, so a recycled pid keeps paging for a dead session

**What:** The beacon reaper decides the owner is alive with `kill -0` alone. The file itself documents that this "lies" for recycled pids.

**Where:** line 554
```
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong:**
- **Trigger:** a session is hard-killed with a prompt pending and its pid is reused by any process.
- **Effect:** the beacon is not reaped, and a "⛔ PERMISSION-PENDING … operator must approve or deny" page fires for a session that no longer exists. It keeps paging for up to `PERMPEND_HORIZON_S` (24h).

---

### 9. `reap_clean` deletes the telemetry row that the beacon reaper needs, in the same sweep

**What:** `assess` runs before `sweep_permission_pending`. `reap_clean` removes `$TEL_DIR/$sid.json`, so the beacon sweep finds no telemetry and cannot prove the owner dead.

**Where:**
- line 375: `  rm -f "$TEL_DIR/$1.json" 2>/dev/null || true`
- line 552: `    if [ -f "$tel" ]; then`

**Why it is wrong:**
- **Trigger:** a clean-completion dead session that left a pending-permission beacon.
- **Effect:** the beacon becomes an "orphan" and is PERMISSION-PENDING paged as a live blocked session until the 24h horizon. REAP 1 would have removed it if the row still existed.

---

### 10. The SAME-SWEEP GUARD keys on a `.page` file that other states also stamp

**What:** `had_page` treats any existing `$sid.page` as "a pre-existing STALL? page". The deadline clock is also stamped only on the first page of any state, including PAST-THRESHOLD.

**Where:**
- line 203: `  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only`
- line 507: `      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`

**Why it is wrong:**
- **Trigger:** a session is B-1 paged (PAST-THRESHOLD, which never passes through `clear_page`), then goes stale into STALL?.
- **What happens:** `.page` already exists with the B-1 timestamp, which is typically ≥1800s old. On the very first STALL? sweep, `resolve_page` runs immediately with the deadline already expired, and re-observes from the B-1 time.
- **If dark:** it escalates in the same sweep as the first STALL? notify. That is the phantom same-sweep double-notify the guard claims to prevent.
- **If fresh:** effects from before the stall void the candidate. Either way the STALL? page never gets its own deadline window.

---

### 11. The self-check counts dead and stranded telemetry rows as coverage, which masks blind spots

**What:** The enumerated count `n` counts every `*.json` row, including rows whose pid is dead. It is not a count of live panes that have telemetry.

**Where:**
- line 632: `      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`
- line 607: `  delta=$(( live - enum ))`

**Why it is wrong:**
- Stranded-DEAD rows (dirty or unlanded worktrees) are never deleted by the supervisor, and `gc_stale` skips non-owner pids.
- Each such row therefore permanently offsets one live pane that has no telemetry.
- **Example:** 2 invisible live panes plus 2 stranded dead rows gives delta 0. No SELF-CHECK page fires, and the heartbeat looks healthy, which is the exact blind spot V3 is meant to detect.

---

### 12. The "unreadable ps ⇒ ABSTAIN" guard can never fire

**What:** `awk ... END { print c+0 }` always prints a number, even when `ps` fails or prints nothing, so the non-numeric check is dead code.

**Where:**
- line 597: `    END { print c+0 }'`
- line 606: `  case "$live" in ''|*[!0-9]*) return 0 ;; esac      # unreadable ps ⇒ ABSTAIN (no verdict), never a phantom Δ`

**Why it is wrong:**
- **Trigger:** `ps` fails.
- **Result:** `live` reads as 0 and delta goes negative. The recovery branch then writes `0 0` to the state file.
- **Effect:** the persistence counter and the "paged" marker for a standing blind spot are reset. The function should have abstained instead.

---

### 13. The transcript path mangling does not match Claude Code's, so the warm-transcript exemption is silently skipped

**What:** Only `/` and `.` are replaced. Claude Code's `projects/` directory name replaces every non-alphanumeric character with `-`, including `_`, spaces and `+`. This claim relies on Claude Code's behaviour rather than on anything in this file.

**Where:** line 391
```
  slug="$(printf '%s' "$cwd" | sed 's|[/.]|-|g')"          # CC projects/ dir mangling: every '/' and '.' → '-'
```

**Why it is wrong:**
- **Trigger:** a cwd containing `_` or similar, for example `.../doc_classifier`, which becomes the wrong slug.
- **What happens:** `tp` never exists, so the function returns 999999999 ("cold").
- **Effect:** a live session with a warm transcript is STALL?-paged and possibly escalated. This reintroduces the oscillation the exemption was added to stop.

---

### 14. `pipefail` plus `grep -q` can turn an unlanded branch into "landed"

**What:** With `set -o pipefail`, if `grep -q` matches early and exits, `printf` can die of SIGPIPE (141). The pipeline then fails and `|| return 0` reports landed.

**Where:** line 362
```
    printf '%s\n' "$cherry_out" | grep -q '^+' || return 0
```

**Why it is wrong:**
- **Trigger:** `git cherry` output larger than the pipe buffer (roughly >64KB, a long-lived branch with many ahead commits), with a `+` line early in the output.
- **What happens:** grep returns 0 but the pipeline returns 141.
- **Effect:** `work_landed` returns 0 for unlanded work, and `reap_clean` drops it with no page and no checkpoint.

---

### 15. Unescaped strings are embedded in IDL JSON

**What:** `cwd`, `sid` and page `detail` are interpolated raw into JSON bodies. This is despite the file's own rule (lines 183–184) never to raw-embed such strings.

**Where:**
- line 338: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
- line 374: `  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""`
- line 204: `  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""`

The same pattern appears in the `checkpoint_timeout` record at line 335.

**Why it is wrong:**
- **Trigger:** a worktree path or a telemetry `session_id` containing `"` or `\`.
- **Effect:** a malformed IDL line is written for the reap, checkpoint or page record, which is the malformed-IDL class the comment cites.
