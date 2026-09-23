## Defects

### 1. `work_landed` treats a failed or timed-out `git status` as a clean worktree

**Where** — line 356:
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```

**Why it is wrong** — the check tests the *output*, not the *exit status*. If `git status` is cut at the 15 s `SUP_GIT_TIMEOUT_S` bound (index.lock contention, a stalled volume — the exact classes the header names), or fails with a fatal error, stdout is empty and the guard reads "clean tree". The header block for this function (lines 349–351) explicitly promises the opposite: "A cut yields rc 124, which this function treats exactly like any other failure — return 1". It does not. With a subsequent successful `rev-list --count` of 0, `work_landed` returns 0, and `assess` (line 483) takes `reap_clean`: the dead session's telemetry row is deleted, no DEAD page is sent, and no checkpoint is taken — a dirty, unlanded worktree is silently dropped from supervision. This is the one path in the file that destroys state on an unproven premise.

---

### 2. `checkpoint_preserve` records a completed checkpoint when the script never ran, or ran and failed

**Where** — lines 326, 331, 333, 339:
```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  fi
  if [ "$rc" = 124 ]; then
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```

**Why it is wrong** — only rc 124 is treated as "did not happen". Two other outcomes reach line 339 and write an IDL record asserting the worktree was preserved:
- `command -v teammate-checkpoint.sh` fails ⇒ the `if` body never executes, `rc` stays 0. This is the *normal* case under launchd: the file goes to great lengths to resolve `timeout` (lines 52–57) and `cc-notify` (lines 117–124) by absolute path precisely because launchd's minimal PATH excludes the dirs these tools live in, yet `teammate-checkpoint.sh` is resolved by PATH only. In the daemon's real runtime, the checkpoint is skipped and logged as done.
- The script runs and exits non-zero for any reason other than a timeout (e.g. rc 1, rc 127) ⇒ `rc=1`, the `= 124` test is false, and line 339 again records a successful checkpoint.

The audit trail then shows insurance that does not exist, which the comment at lines 333–334 says must never happen.

---

### 3. The DEAD page asserts "worktree checkpoint-preserved" regardless of whether anything was preserved

**Where** — lines 325 and 486:
```bash
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
```
```bash
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong** — `checkpoint_preserve` returns 0 with no IDL record at all when `cwd` is empty or not a directory (line 325), and returns 0 after a cut checkpoint (line 337). `assess` never inspects the return value; the operator-facing page text is a fixed string. For a dead session whose telemetry carries no `cwd`, or whose worktree was already removed, or whose checkpoint was cut at the 60 s bound, the operator is told the work was preserved when it was not — and in the empty-`cwd` case there is no `checkpoint_timeout` record to contradict it either.

---

### 4. `live_pane_count` sees no processes when run as the launchd daemon, so the self-check can never fire

**Where** — line 593:
```bash
  ps -wwEo command= 2>/dev/null | awk '
```

**Why it is wrong** — no selection option (`-A`, `-a`, `-x`) is passed. BSD/macOS `ps` with no selection option lists only processes with the invoker's EUID **and** the invoker's controlling terminal. A launchd-run daemon has no controlling terminal, so the pipeline yields nothing and `END { print c+0 }` prints `0`. `live` is then numeric, so it passes the abstain guard at line 607; `delta=$(( 0 - enum ))` is ≤ 0 for any non-empty telemetry dir, line 610 re-arms the state file and returns. The "who watches the watcher" blind-spot detector is therefore permanently inert in its only real deployment. The same asymmetry the header warns about for `timeout` applies here — an interactive test run from a terminal will count the claude processes on *that* tty and look partially wired.

---

### 5. The B-1 past-threshold check is gated on fresh telemetry, excluding the case it exists to cover

**Where** — line 516:
```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
```

**Why it is wrong** — B-1 (line 24) claims to cover "a session PAST-THRESHOLD ∧ NOT-STOPPING ... a session hung/working-past-boundary never Stops". But this file documents at lines 382–386 that the telemetry writer is the statusline, which "stops emitting when a pane is not actively rendering", so "a session inside ONE long operation ... renders ZERO times" and "a healthy BACKGROUNDED / long-turn ... session goes telemetry-stale for hours while its transcript stays warm". A session at 90 % context inside one long turn therefore has `age ≥ STALL_S`; it is exempted from the STALL? branch by the warm-transcript test at line 500, falls through line 516 because `age` is not `< STALL_S`, and lands on the OK branch (line 521) where `clear_page` wipes any standing page. The exact session state B-1 names — past threshold, still working, never Stopping — produces no page at all.

---

### 6. The same-sweep guard keys on *any* existing page file, so a STALL? candidate can escalate on its first STALL? sweep

**Where** — lines 204, 508, 510:
```bash
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
```
```bash
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
```
```bash
      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
```

**Why it is wrong** — `$PAGEDIR/$sid.page` is one file per sid across *all* states, and its timestamp is never re-stamped after the first page of any kind (line 204). A session that was paged PAST-THRESHOLD (line 517) an hour ago, and only now goes telemetry- and transcript-stale, enters the STALL? branch with `had_page=1`. `resolve_page` then reads the hour-old PAST-THRESHOLD timestamp, finds the deadline already elapsed, and re-observes and possibly escalates **in the same sweep as the first STALL? page** — the phantom same-sweep escalate the guard at lines 499–505 is written to prevent. Worse, `reobserve_effects` is handed that hour-old `paged_at` as `since`, so "fresh vs dark" is measured over a window that has nothing to do with the stall. PAST-THRESHOLD pages are never otherwise resolved, so this stale stamp can sit for arbitrarily long.

---

### 7. `reobserve_effects` returns `dark` — not `unknown` — when it could not probe at all

**Where** — lines 276–277, 288–289:
```bash
      local ref; ref="$(mktemp 2>/dev/null)"
      if [ -n "$ref" ]; then
```

**Why it is wrong** — if `mktemp` fails (no writable TMPDIR, exhausted inodes), the entire filesystem probe is skipped and `verdict` keeps its initial value `dark` (line 265), which `resolve_page` routes straight to `escalate_page`. The same happens if `touch -t` fails (its errors are discarded at line 278): the reference file keeps its creation mtime of *now*, so no file can be `-newer` than it and the walk reports nothing. Both are "WE COULD NOT LOOK" cases that lines 254–263 insist must surface as `unknown`; instead the supervisor escalates a session whose effects it never observed — the silence-reap the whole S-3b protocol exists to prevent.

---

### 8. The `date -r` fallback makes every file in the worktree look fresh

**Where** — line 278:
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```

**Why it is wrong** — `date -r <epoch>` is BSD-specific; on a GNU `date` (`-r` means "reference file") it fails and the fallback stamps the reference file at 1970-01-01. Every regular file under `$cwd` is then newer, `find` returns a hit on its first match, and the verdict is unconditionally `fresh`. A genuinely hung lead is silently exonerated and its page voided at every deadline — the outcome line 261 names as dishonest — with no IDL record distinguishing it from a real recovery.

---

### 9. `pid_alive_owner` matches any command line containing "claude" anywhere, not a claude session

**Where** — line 433:
```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong** — `OWNER_PAT` defaults to `claude` and the match is an unanchored, case-insensitive substring over the whole command line including all arguments and paths. Any process that merely mentions the config dir — `bash /Users/x/.claude/hooks/cc-permission-beacon.sh`, `node /Users/x/.claude/...`, a `grep claude` — passes as "the original session owner". Compare the deliberately argv0-anchored clause at line 595. Consequence: when a dead session's pid is recycled to such a process, `assess` does not take the DEAD branch (line 478), so no `checkpoint_preserve` and no DEAD page happen; the row instead ages `GC_S` (6 h) and is then deleted by `gc_stale` (line 456) — precisely the silent loss of insurance that lines 441–444 declare must never occur.

---

### 10. `idl page` / `idl permission_pending` are written before the damping return, so the IDL records pages that were never sent

**Where** — lines 205 and 206, and line 240:
```bash
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
  # composer damping: ONE notify per sid per STATE — a re-sweep of an already-notified state stays
```
```bash
  idl permission_pending "\"sid\":\"$sid\",\"since\":$ts,\"age_s\":$age,\"cmd\":$(json_str "$cmd")"
```

**Why it is wrong** — both records are emitted unconditionally, before the equality-damping returns at lines 210/216/244 and before `send_page` is called at all. For a standing condition (a dead-pid row, a pending permission prompt), every 30 s sweep appends a fresh `kind:"page"` / `kind:"permission_pending"` line while no notification is sent. The comment on line 206 states the opposite behaviour ("a re-sweep of an already-notified state stays IDL/mailbox-quiet"), and the S-4 contract treats the IDL as the record of operator-facing acts — so the log overstates the number of pages delivered, which is the same class of untruthfulness the `send_page` rewrite (lines 139–150) was done to remove.

---

### 11. A stranded DEAD row is never retired, so `work_landed` and `checkpoint_preserve` re-run on it every sweep forever

**Where** — line 486:
```bash
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong** — nothing deletes the telemetry row on this path (`reap_clean` runs only on the clean-completion branch), and `gc_stale` explicitly skips rows whose pid is gone (line 454). So a dead session with a dirty or unlanded worktree is re-assessed on every sweep: 3–5 `git` forks via `work_landed` plus a full `teammate-checkpoint.sh` run, indefinitely. The notify is damped by `.notified`, but the *acts* are not — the checkpoint script is re-invoked against the same worktree every 30 s, and line 339 appends another `"why":"dead-lead-preserve"` record each time, so the IDL shows an unbounded series of distinct checkpoint events for a single death.

---

### 12. The escalation branch never resets the deadline clock, so the re-observation window is frozen at the first page

**Where** — lines 302–303:
```bash
  if [ "$effects" = dark ]; then
    escalate_page "$sid" "$cwd"                 # effects-dark ⇒ disposition (never reached from silence alone)
```

**Why it is wrong** — unlike the `unknown` and fresh branches (lines 311, 314), this branch does not call `void_page`, so `$PAGEDIR/$sid.page` keeps its original timestamp. Every subsequent sweep re-enters the STALL? branch, finds `had_page=1`, sees the deadline long expired, and re-runs the full bounded `git`+`find` probe and `idl page_escalate` — once per 30 s sweep instead of once per `DEADLINE_S`. And because `since` remains the original page time rather than advancing to the last observation, the freshness test drifts ever further from "did anything happen recently": any single file touched shortly after the first page keeps reading `fresh` indefinitely, voiding later pages for a session that has since gone completely dark.

---

### 13. Permission-beacon reap 1 uses bare `kill -0`, the check this file documents as a lie

**Where** — line 555:
```bash
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong** — lines 423–427 establish that `kill -0` proves only that *some* process holds the pid, and every other liveness site in the file uses `pid_alive_owner` for that reason. Here, a dead session whose pid has been recycled reads as alive, so its orphaned beacon is not reaped and `page_permpend` keeps reporting a "PERMISSION-PENDING" prompt on a session that no longer exists — for up to `PERMPEND_HORIZON_S` (24 h) until reap 2 finally clears it. The operator is paged to answer a prompt that cannot be answered.

---

### 14. Values read from telemetry are interpolated raw into IDL JSON despite `json_str` existing for exactly this

**Where** — lines 339, 375, 458 (and the `detail` field at line 205):
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```
```bash
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
```

**Why it is wrong** — `cwd` and `sid` come from an externally written JSON file in `/tmp`, and lines 183–185 state the rule: "never raw-%s a worker/command string into JSON (the malformed-IDL class)". A path containing a double quote or backslash (both legal in macOS filenames) produces a line that is not valid JSON, so any consumer parsing the IDL either drops or chokes on the record — the reap or checkpoint outcome record that S-4 relies on is lost precisely for the unusual worktree most worth auditing.

---

### 15. `assess` uses the telemetry-supplied `session_id` in file paths without the validation the beacon sweep applies

**Where** — line 467 vs. line 548:
```bash
  sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || { echo 0; return; }
```
```bash
    case "$sid" in *[!A-Za-z0-9._-]*|''|.|..) continue ;; esac      # ignore stray/unsafe filenames
```

**Why it is wrong** — `sid` is only checked for non-emptiness, then used to build `$PAGEDIR/$sid.page`, `$PAGEDIR/$sid.notified` and `$TEL_DIR/$sid.json`, which are written and `rm -f`'d (lines 204, 220, 224, 376). `$TEL_DIR` defaults to `/tmp/cc-telemetry`, a shared-world location; a row whose `session_id` contains `../` makes `clear_page`/`reap_clean` delete files outside the pages directory. `sweep_permission_pending` guards this exact class one function away, so the omission is an inconsistency in the same file, not an unconsidered risk.
