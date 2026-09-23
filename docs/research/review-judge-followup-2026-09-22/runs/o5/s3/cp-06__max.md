## Summary

I found 11 defects. The three most serious let the supervisor take (or withhold) an operator-facing action on a premise it never actually established: a dead session's dirty worktree can be silently reaped, a session whose worktree cannot be examined at all is escalated as "effects-dark", and a checkpoint that never ran is recorded and paged as having happened.

---

### 1. `work_landed` reads a *cut* `git status --porcelain` as a clean tree, so a dead session's unlanded work can be silently reaped

**Where** — line 355:
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```

**Why it is wrong** — `sup_bounded` kills the fork at `SUP_GIT_TIMEOUT_S` (15s) and produces **no stdout**, so the command substitution is empty and `-z` succeeds: a probe that never answered is recorded as "tree is clean". Only stdout is inspected here; the rc is discarded — unlike line 356, which does `|| return 1`. The exact repo class the file cites (line 279: "doc_classifier holds 1.27M files") makes `status` exceed 15s while `rev-list --count` stays sub-second, so the next check passes too. With all the work uncommitted, `ahead` is `0`, line 357 returns 0 = "clean+landed", and `assess` line 482 calls `reap_clean`: the telemetry row is deleted, the page cleared, no checkpoint taken, no page sent. That directly contradicts the function contract at lines 348–350 ("A cut yields rc 124, which this function treats exactly like any other failure … a timed-out probe must never be read as 'landed' and silently reaped").

### 2. `reobserve_effects` returns `dark` — not `unknown` — when it could not look at all, so an unobservable session gets escalated

**Where** — lines 264, 265, 276, 290:
```bash
  local cwd="$2" since="$3" verdict=dark rc=0
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
      if [ -n "$ref" ]; then
  printf '%s' "$verdict"
```

**Why it is wrong** — `verdict` is initialised to `dark` and both "we could not look" guards fall straight through to the `printf` at line 290. If the telemetry row has no `.cwd`, or the cwd no longer exists (a worktree already removed), or `mktemp` fails at line 275, the function prints `dark` having observed nothing. `resolve_page` line 301 then routes that to `escalate_page`, which pages ESCALATED claiming "supervisor re-read confirms dark" (line 318). The `unknown` state exists precisely to prevent this (lines 253–262: "folding a cut probe into `dark` would let a slow-but-healthy repo … manufacture the escalation this whole protocol exists to prevent"), but only the two rc-124 paths reach it.

### 3. `checkpoint_preserve` records a completed checkpoint when the script is missing or failed, and the DEAD page asserts preservation unconditionally

**Where** — lines 325, 330, 332, 338, 485:
```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 124 ]; then
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong** — Only rc 124 is treated as "did not happen". If `teammate-checkpoint.sh` is not resolvable, line 325 is false, `rc` stays `0`, and line 338 writes an IDL record saying the worktree was checkpoint-preserved although nothing ran — and lines 51–53 state that launchd runs this daemon with a minimal PATH, which is exactly when a PATH lookup for a repo script fails. The same happens for any non-124 failure (rc 1/128 from a git error inside the script). Independently, line 485 hardcodes "worktree checkpoint-preserved" into the operator page for all three outcomes, including the 124 case that the comment at lines 333–334 admits leaves the worktree unpreserved. The operator is told the insurance exists when it does not.

### 4. The B-1 PAST-THRESHOLD page is gated on telemetry freshness, which excludes the long-turn session B-1 claims to cover

**Where** — line 515:
```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
```

**Why it is wrong** — `age` is telemetry age, and lines 381–385 establish that telemetry age is a false liveness proxy: "the statusline … stops emitting when a pane is not actively rendering … a healthy BACKGROUNDED / long-turn … session goes telemetry-stale for hours while its transcript stays warm (measured … a live session at 3.5-DAY-stale telemetry with a 5-min-warm transcript)". A session at 90% context inside one long operation therefore has `age ≥ STALL_S`, fails this conjunct, and is never paged — while the STALL? branch above it has already dropped it via the warm-transcript exemption at line 499. That is precisely the class B-1 exists for (line 24: "a session hung/working-past-boundary never Stops"), and it receives no page from any branch.

### 5. The "OK" branch clears standing pages for sessions that were never observed OK

**Where** — lines 519–520:
```bash
  # OK — clear any stale page (fresh + below threshold + alive).
  clear_page "$sid"; echo 0
```

**Why it is wrong** — The comment states the precondition (fresh + below threshold), but the branch is reached whenever the two `if`s above fall through, including `used ≥ T` with `age ≥ STALL_S` (warm transcript, or a registered desk). For a session that is past threshold and telemetry-stale, `clear_page` deletes both `<sid>.page` — the durable record autonomy-sweep globs (line 103) — and `<sid>.notified`, while the past-threshold condition still holds. When the session next renders and goes fresh, line 516 re-pages and, with the damping marker gone, re-notifies the desk; every render/long-turn cycle produces another composer ping, defeating the "ONE notify per sid per STATE" damping that lines 205–207 exist to enforce.

### 6. The same-sweep guard tests only that *a* page file exists, so a page stamped by a different state serves as the STALL? deadline clock — producing two notifies in one sweep

**Where** — lines 203, 507, 509:
```bash
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
```

**Why it is wrong** — `page()` writes one `<sid>.page` file for *every* state, and only the OK branch/reap/GC remove it. A session that sits above `T` is paged PAST-THRESHOLD (line 516), stamping `.page`, and never reaches the OK branch while it stays above `T`. When it later goes telemetry- and transcript-stale, `had_page=1` on the *first* STALL? sweep, so `resolve_page` runs immediately with `paged_at` from the old PAST-THRESHOLD page — typically ≥ `STALL_S` (1800s) ago, well past `DEADLINE_S` (900s). The deadline test at line 298 passes instantly, the effects re-read is taken over a window that predates the STALL? page, and a dark result escalates in the same sweep that raised the candidate: `page STALL?` sends (last marker was `PAST-THRESHOLD`) and `page ESCALATED` sends right after — the two-notify same-sweep storm described at lines 500–506, reached by a route the existence check does not cover.

### 7. `pid_alive_owner` matches "claude" anywhere in the command line, so unrelated processes read as the original session owner

**Where** — line 432:
```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong** — `OWNER_PAT` defaults to `claude` (line 95) and `grep -iF` is an unanchored, case-insensitive substring test over the whole command line. Any process whose argv mentions the config directory — `/bin/bash /Users/x/.claude/hooks/cc-permission-beacon.sh`, `node /Users/x/.claude/…`, an MCP child — matches. When a dead session's pid is recycled to such a process, `pid_alive_owner` returns 0, `assess` line 477 skips the DEAD branch, and the row is treated as a live owner: it re-pages STALL?→ESCALATED until `GC_S` (6h) expires, which is the "zombie" the function was written to eliminate (lines 423–428). The file's own identity clause at line 594 anchors on argv0 and explicitly excludes "env-inherited node/MCP children"; this check does neither.

### 8. The permission-beacon reap uses bare `kill -0`, and skips the liveness check entirely when the telemetry row is gone

**Where** — lines 552, 554:
```bash
    if [ -f "$tel" ]; then
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong** — This is the one liveness test in the file that was not converted to `pid_alive_owner`; lines 423–425 record that "kill -0 proves only that SOME process holds the pid". A beacon whose session exited and whose pid was recycled reads as alive, so the beacon survives and line 564 pages "⛔ PERMISSION-PENDING — session … blocked Ns on a permission prompt" for a session that no longer exists, repeating until `PERMPEND_HORIZON_S` (24h). The same false page occurs whenever the telemetry row is absent: `reap_clean` (line 375) and `gc_stale` (line 455) delete rows, and `sweep` runs the telemetry loop before `sweep_permission_pending` (lines 630–639), so a beacon belonging to a session reaped earlier in the *same* sweep fails the `[ -f "$tel" ]` test and is never pid-checked.

### 9. The re-read reference timestamp has no failure detection in either direction

**Where** — line 277:
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```

**Why it is wrong** — `date -r <epoch>` is the BSD form; on GNU coreutils `-r` takes a *file* operand, so `date -r 1752451200` fails and the fallback stamps the reference at 1970-01-01. Every file in the worktree is then `-newer "$ref"`, `hit` is non-empty, and `reobserve_effects` returns `fresh` for every session, including a genuinely hung one — the silent exoneration lines 260 names as dishonest. The file demonstrates it expects both platforms (line 394 falls back from `stat -f` to `stat -c`). Symmetrically, if `touch` itself fails, the `mktemp` file keeps its creation mtime of *now*, nothing can be newer, and every re-read returns `dark`; both failures are swallowed by `2>/dev/null` and yield a confident verdict.

### 10. Filesystem paths and detail strings are raw-interpolated into IDL JSON despite `json_str` existing for exactly this

**Where** — lines 374, 338, 204:
```bash
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
```

**Why it is wrong** — `cwd` comes from telemetry `.cwd` (line 469) and `sid` from `.session_id` (line 466); neither is validated, and `"` and `\` are legal in POSIX path components. A worktree path containing either emits an unparseable line into `idl.jsonl`, which is the malformed-IDL class the `json_str` helper was added to prevent (lines 183–184: "never raw-%s a worker/command string into JSON"). The same call sites elsewhere do use it (lines 176, 239). The audit trail for a reap — a record of an irreversible deletion — is the one that breaks.

### 11. The registered-desk exemption reads only the role file, so it disappears under the documented `CC_PAGE_TO` / `/dev/null` configurations

**Where** — lines 415–416:
```bash
  ref="$(head -1 "$PAGE_TO_FILE" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$ref" ] || return 1
```

**Why it is wrong** — Line 100 documents `CC_PAGE_TO` as an explicit override that "wins over the role", and line 101 documents `/dev/null` as a supported `PAGE_TO_FILE` value. With `CC_PAGE_TO` set and `PAGE_TO_FILE=/dev/null`, paging still works (send_page line 165 uses `PAGE_TO`), but `head -1 /dev/null` yields an empty `ref` and `is_registered_desk` returns 1 for every session. The desk then fails the `! is_registered_desk` conjunct at line 497, and — being the legitimately-idle monitor whose telemetry *and* transcript both go stale by design (lines 399–403) — false-flags STALL? and escalates at each deadline: the exact behaviour item ff95faea46c8 was added to remove.
