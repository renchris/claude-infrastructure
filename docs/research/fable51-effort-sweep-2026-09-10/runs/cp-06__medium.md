I reviewed the script as text only. I found seven defects, listed most serious first. Line numbers are counted from the brief as pasted.

---

**1. What:** The timeout guard treats only rc 124 as "cut", but the `-k 5` kill path it was added for returns rc 137, so a KILL-terminated probe is read as a completed one.

**Where:** line 80, and the checks at lines 269, 285, 332
```
  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"
    [ "$rc" = 124 ] && { printf 'unknown'; return; }
        [ "$rc" = 124 ] && { printf 'unknown'; return; }
  if [ "$rc" = 124 ]; then
```

**Why it is wrong:** GNU timeout returns 124 only when the child dies from the TERM it sent. When the child ignores TERM and is killed by the follow-up KILL, timeout exits 137 (128+9). The comment at lines 75-76 says the -k was added precisely because wedged forks ignore TERM. In that case reobserve_effects sees rc 137, does not return "unknown", finds empty output, and reports "dark", which resolve_page escalates. checkpoint_preserve sees rc 137, skips the timeout branch, and logs a successful "dead-lead-preserve" checkpoint that never completed. Both are the outcomes the three-state design says it exists to prevent.

---

**2. What:** A failed or timed-out `git status` reads as a clean worktree because only its stdout is tested, never its exit code.

**Where:** line 355
```
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```

**Why it is wrong:** If the status probe is cut at the 15s bound (rc 124, or 137 per item 1), or fails for any reason such as index.lock contention, its captured output is empty and the test passes as "clean". If the branch is also 0 ahead by count, work_landed returns 0 and the DEAD path calls reap_clean, deleting the telemetry row and clearing pages for a worktree that may hold uncommitted work. The comment at lines 348-350 claims a cut "return 1 = cannot PROVE clean", but this line does the opposite.

---

**3. What:** checkpoint_preserve records a successful checkpoint, and the DEAD page claims "worktree checkpoint-preserved", when the checkpoint script was never found or exited non-zero.

**Where:** lines 325, 330, 338, and 485
```
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong:** The script is resolved by PATH only, and the header at lines 51-53 states launchd runs the daemon with a minimal PATH. When the script is absent, rc stays 0 and the function falls through to the success record. Any non-124 failure rc (script error, rc 137 from KILL) also reaches the success record. The IDL and the operator page both assert insurance that does not exist.

---

**4. What:** When the epoch-to-timestamp conversion fails, the find reference file is dated 1970, so every file in the tree counts as "touched after the page" and the re-read reports "fresh".

**Where:** line 277
```
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```

**Why it is wrong:** `date -r <epoch>` is a BSD-only form; on GNU date, or with a malformed `since`, it fails and the fallback fires. Any file at all in the worktree then satisfies `-newer`, verdict becomes fresh, and a genuinely dark lead is voided at every deadline and never escalated. This is the silent-exoneration case the comment at line 260 says the function must not produce.

---

**5. What:** The page deadline stamp is written only on first page and is never reset by escalation, so the STALL? deadline can be inherited from an unrelated earlier page, and once escalated the effects re-read reruns on every sweep.

**Where:** lines 203, 318, and 507-509
```
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
  page "$1" ESCALATED "no work-products across the page deadline; supervisor re-read confirms dark (still not auto-acting)"
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
```

**Why it is wrong:** A session paged PAST-THRESHOLD (or DEAD, then pid recycled to claude) already has a `.page` file. When it later enters STALL?, had_page is 1 and resolve_page runs in the same sweep against a stamp that may be hours old, so the deadline the same-sweep guard promises never elapses. Separately, after escalate_page the stamp stays, so each subsequent 30s sweep re-runs git plus the pruned find walk and emits page_escalate again, instead of re-observing at the next deadline as the S-3b protocol states.

---

**6. What:** A permission beacon is paged as PERMISSION-PENDING for a session the supervisor has already reaped or classified dead.

**Where:** lines 551-556
```
    tel="$TEL_DIR/$sid.json"
    if [ -f "$tel" ]; then
      pid="$(jq -r '.pid // empty' "$tel" 2>/dev/null)"
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong:** reap_clean and gc_stale delete the telemetry row earlier in the same sweep, so the beacon has no row to pid-check and survives until the 24h horizon, producing a false PERMISSION-PENDING page and per-sweep IDL records. Also, this branch uses bare `kill -0` rather than pid_alive_owner, so a pid recycled to a non-claude process keeps the dead session's beacon alive and paged, contradicting the DEAD classification assess() gives the same sid.

---

**7. What:** The self-check compares live claude processes against the raw count of telemetry files, which includes rows for dead sessions, so dead rows mask unseen live panes.

**Where:** lines 632, 642, and 607
```
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
  self_check "$n"
  delta=$(( live - enum ))
```

**Why it is wrong:** A stranded DEAD row is kept (not reaped) and still counted in n. With three dead rows and three live panes that never wrote telemetry, delta is 0 and no blind-spot page fires, while those panes have no coverage on any path. The detector claims to cover exactly this class.

---

**Minor:** `page()` and `checkpoint_preserve` embed `$3` and `$cwd` into IDL JSON unescaped (lines 204 and 338), unlike the permpend path which uses json_str. A cwd containing a quote or backslash produces a malformed IDL line, the class the comment at line 184 says to avoid.
