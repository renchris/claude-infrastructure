Line numbers below refer to the listing in the brief.

---

### 1. `-k 5` makes a cut fork exit 137, not 124, so every "was this probe cut?" branch misses the exact case `-k` was added for

**Where** — L80, and the three rc tests that depend on it (L269, L285, L332):
```bash
  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"
```
```bash
    [ "$rc" = 124 ] && { printf 'unknown'; return; }
```
```bash
  if [ "$rc" = 124 ]; then
```

**Why it is wrong** — `timeout(1)`'s documented exit status is 124 on timeout *but 137 (128+9) when the command is killed by the KILL signal*, which is precisely what `-k 5` causes for a fork that ignores SIGTERM. The comment at L75–76 says `-k` exists for "a fork that ignores TERM (a wedged AppleEvent client does)" — that fork yields 137. So in `reobserve_effects`, a `git log` or `find` that had to be SIGKILLed falls through the `= 124` test with `verdict` still `dark`, `resolve_page` reads `dark`, and `escalate_page` fires on a state that was never observed — the "silence-reap" the `unknown` state exists to prevent. In `checkpoint_preserve`, a SIGKILLed checkpoint skips the `checkpoint_timeout` record and is logged as a successful `dead-lead-preserve`.

---

### 2. `checkpoint_preserve` records a completed checkpoint when the checkpoint never ran or failed

**Where** — L325, L330, L338:
```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
```
```bash
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
```
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```

**Why it is wrong** — Only `rc = 124` is treated as a non-checkpoint. If `command -v teammate-checkpoint.sh` fails, the `if` body never runs, `rc` stays 0, and the function still emits `idl checkpoint ... dead-lead-preserve`; the caller (L485) then pages `DEAD ... worktree checkpoint-preserved`. Same for any ordinary failure (rc 1, 127, 137). This is the launchd case the file argues about for `timeout` (L51–53) and `cc-notify` (L116–117): under launchd's minimal PATH, `teammate-checkpoint.sh` is the one external here resolved *only* by PATH, so it is likely absent exactly in the daemon that matters. The IDL and the operator page then assert insurance that does not exist, contradicting L333–334 ("a checkpoint that did not happen must not be logged as one").

---

### 3. `work_landed` reads a failed or cut `git status` as a clean worktree

**Where** — L355:
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```

**Why it is wrong** — Only stdout is inspected and stderr is discarded, so *any* non-zero exit that produced no stdout (rc 124/137 from the 15s bound on a large or contended repo, a torn-down `.git`, an index error) satisfies `-z` and is read as "clean tree". If the subsequent `rev-list --count` then succeeds with `0` (a worker that committed nothing since branching, or whose branch is level with trunk), `work_landed` returns 0 and `assess` calls `reap_clean`: the telemetry row is deleted and any standing page cleared for a dead session with uncommitted work, with no DEAD page and no checkpoint. L348–350 claims exactly the opposite ("A cut yields rc 124, which this function treats exactly like any other failure — return 1").

---

### 4. `pid_alive_owner` matches any process whose command line merely contains the string `claude`, so recycled pids read as the original session owner

**Where** — L432:
```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong** — `OWNER_PAT` defaults to `claude` and `grep -qiF` is an unanchored substring test over the whole argv. In this tree virtually every helper runs with `~/.claude/...` in its command line (hooks, `cc-notify`, MCP `node` children, even this script's own children), so a pid recycled to any of them is certified as the row's original claude session. Consequences: `assess`'s DEAD branch (L477) is skipped for a session that has actually exited, so nothing is checkpoint-preserved and no DEAD page fires; and `gc_stale`'s guard at L453 (`pid_alive_owner "$pid" || continue`, documented at L440–443 as "only a still-ALIVE OWNER is GC'd here … GC must never silently drop that insurance") passes, so after `GC_S` the row *and* its page are deleted and the stranded work is never surfaced. Compare `live_pane_count` (L594), which does an argv0-anchored identity check for the same question.

---

### 5. The B-1 PAST-THRESHOLD check requires *fresh* telemetry, excluding the long-turn sessions it exists to cover — and then clears their page

**Where** — L515, and the fallthrough at L520:
```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
```
```bash
  clear_page "$sid"; echo 0
```

**Why it is wrong** — The file's own model of the telemetry writer (L381–385) is that the statusline "stops emitting when a pane is not actively rendering … a session inside ONE long operation, or genuinely hung, renders ZERO times", with a measured live session at 3.5-day-stale telemetry. Take such a session: `used_pct` ≥ 73, telemetry `age` ≥ 1800s, transcript warm. The STALL? branch (L497–499) declines it via the warm-transcript exemption, then L515 declines it because `age` is not `< STALL_S`, and control reaches L520, which `clear_page`s it — deleting any earlier PAST-THRESHOLD page *and* its `.notified` marker. So a session that is past the context boundary and demonstrably still working — B-1's stated case, "the exact case the boundary hook is blind to" (L23–24) — gets no page at all, and a previously issued one is withdrawn.

---

### 6. The `.page` deadline stamp is shared across states and never re-stamped, so a first-ever STALL? page can be escalated in the same sweep

**Where** — L203, L507, L509:
```bash
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
```
```bash
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
```
```bash
      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
```

**Why it is wrong** — `had_page` only asks whether *some* `.page` file exists, not whether it belongs to this state, and L203 refuses to restamp an existing file. A session paged `PAST-THRESHOLD` (L516) or `DEAD` (L485) leaves `$sid.page` on disk indefinitely — the OK branch that would clear it is never reached while those branches keep firing. When that session later crosses into STALL?, the STALL? page inherits a `paged_at` from hours earlier, `resolve_page` finds the deadline long expired, and an effects-dark read escalates on the very first sweep the stall is detected. That defeats the stated invariant "The deadline clock starts AT the page; re-observation belongs to a later sweep" (L504–505) and re-creates the two-notify burst the SAME-SWEEP GUARD was written to stop (STALL? notify at L219, then ESCALATED notify from L318, both in one sweep, since `.notified` holds `PAST-THRESHOLD`/`DEAD` and neither equality nor the ESCALATED-sticky test damps them).

---

### 7. The permission-beacon reap uses bare `kill -0`, the recycled-pid lie this file documents everywhere else

**Where** — L554:
```bash
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong** — `pid_alive_owner` exists precisely because "kill -0 proves only that SOME process holds the pid" (L423), but REAP 1 does not use it. When the prompt-blocked session dies and the OS recycles its pid to any unrelated process, `kill -0` succeeds, the beacon is not reaped, and every sweep past `PERMPEND_NOTICE_S` keeps the beacon alive until `PERMPEND_HORIZON_S` (24h default) — so the operator is paged `PERMISSION-PENDING` for a session that no longer exists, with an age counter that keeps growing.

---

### 8. When `date -r` fails, the reference file is stamped at 1970, making every effects re-read report `fresh`

**Where** — L277:
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```

**Why it is wrong** — The fallback is a fixed epoch-zero timestamp, so `find … -newer "$ref"` matches the first file it encounters and `verdict` becomes `fresh`. `date -r <epoch>` is BSD-only (GNU `date -r` takes a *file*), and it also fails when `since` is empty — which `resolve_page` can pass, since L297 defaults `paged_at` only inside the arithmetic test and hands the raw value to `reobserve_effects` at L300. In either case the re-read unconditionally certifies "alive + working", `resolve_page` takes the `page_void` branch, and a genuinely hung lead is exonerated at every deadline forever — the outcome L259–260 names as dishonest ("folding it into `fresh` would silently EXONERATE a genuinely hung lead"). The mirror-image failure exists too: if `touch` itself fails, `$ref` keeps its `mktemp` mtime of *now*, nothing is ever newer, and every re-read is `dark`.

---

### 9. `page()` writes an IDL `page` record before the damping check, so a standing page is not "IDL-quiet"

**Where** — L204, ahead of the damping tests at L209/L215:
```bash
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
```

**Why it is wrong** — The comment at L204–207 states the contract as "ONE notify per sid per STATE — a re-sweep of an already-notified state stays IDL/mailbox-quiet". Only the mailbox side is damped; the IDL line is emitted unconditionally on every call. A session held in `DEAD` or `ESCALATED` produces one `kind:"page"` record per sweep (120/hour at the 30s default) for the life of the incident, so anything counting `page` records in the IDL — the durable audit surface this file leans on for S-4 — reads a single standing incident as continuous re-paging.

---

### 10. The headless-session exclusion in `live_pane_count` only scans argv fields 2–7

**Where** — L595:
```bash
      for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
```

**Why it is wrong** — A one-shot invoked with more than six leading arguments — e.g. `claude --dangerously-skip-permissions --output-format stream-json --verbose --model claude-opus-5 -p "…"`, where `-p` lands at field 8 — is not excluded and is counted as a live interactive pane. Headless one-shots write no telemetry row, so `live` is inflated relative to `enum`, `delta` exceeds `PANE_DELTA_TOL` (default 0), and after `SELFCHECK_MIN_PERSIST` sweeps `self_check` pages "live Claude pane(s) … have NO supervisor coverage" for sessions that need none. The guard claims to be "excluding headless one-shots (-p/--print/--version)" (L586) but covers only those whose flag appears early in argv.

---

### 11. Shell-interpolated values are written raw into IDL JSON, bypassing the file's own `json_str` rule

**Where** — L374 and L338 (and L204):
```bash
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
```
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```

**Why it is wrong** — L183–184 states the rule ("never raw-%s a worker/command string into JSON (the malformed-IDL class)") and provides `json_str`, which is used for the beacon command and the page target but not for `cwd`, `sid`, or `detail`. `cwd` comes straight from the telemetry row's `.cwd`; a worktree path containing a double quote or a backslash (both legal on macOS) emits a line that is not valid JSON. The record most likely to be corrupted is the one recording an irreversible act — `reap`, which has just deleted the telemetry row — so the audit trail for that deletion is the line that fails to parse.