# Review — `scripts/lead-supervisor.sh`

I read the whole file. Nine defects, ordered by severity. Line numbers are counted from `#!/bin/bash` = 1; the verbatim line is the definitive anchor in each case.

---

## 1. A checkpoint that never ran is recorded (and paged) as a successful checkpoint

**What** — `checkpoint_preserve` emits the `idl checkpoint … "dead-lead-preserve"` success record whenever `rc` is anything other than 124, including the case where `teammate-checkpoint.sh` was never found and never executed at all.

**Where** — lines 325, 330, 332, 338; and the page text at line 485.

```bash
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
```
```bash
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
```
```bash
  if [ "$rc" = 124 ]; then
```
```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```
```bash
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong** — Two reachable inputs. (a) `command -v teammate-checkpoint.sh` fails: `rc` stays 0, the `if` body is skipped, and line 338 still writes a `checkpoint` record. This is the *expected* state under launchd, whose minimal PATH is the reason lines 51–56 and 115–122 give `timeout(1)` and `cc-notify` explicit absolute-path resolution — `teammate-checkpoint.sh` got none, so it is looked up on the bare PATH only. (b) The script runs and fails with any rc in 1–123 or 125–137 (git error, dirty index, bad cwd): only 124 is special-cased, so every other failure also falls through to line 338. In both cases the IDL asserts the worktree was preserved and the DEAD page tells the operator "worktree checkpoint-preserved", while nothing was checkpointed. The 124 branch's own comment ("a checkpoint that did not happen must not be logged as one") states exactly the invariant the other failure modes violate.

---

## 2. A timed-out or failed `git status` is read as "clean tree", so stranded work is silently reaped

**What** — `work_landed`'s dirty-tree check inspects only the *output* of `git status --porcelain`, never its return code, so a cut (rc 124) or failed (rc 128) status — which produces empty stdout with stderr discarded — passes the clean-tree test.

**Where** — line 355 (consequence at lines 482, 374–376).

```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
```
```bash
    if work_landed "$cwd"; then reap_clean "$sid" "$cwd"; echo 0; return; fi
```

**Why it is wrong** — Input: a dead-pid row whose worktree is large and **dirty**, on a branch already merged to trunk. `git status` scans the working tree, so on the kind of tree this file documents (the `doc_classifier` worktree, 1.27M files, a walk measured at ~5 min — lines 278–279) it blows through the 15s `SUP_GIT_TIMEOUT_S` bound; `rev-list --count` does not scan the worktree and returns `0` in milliseconds. Result: line 355 sees empty output and proceeds, line 357 takes the fast path, `work_landed` returns 0, and `reap_clean` deletes the telemetry row and clears any standing page — no checkpoint, no DEAD page, no further coverage for that session. The uncommitted work is gone with only a `reap` record claiming "shipped-clean-worktree". An `index.lock` conflict (rc 128, empty stdout) is a second trigger. This directly contradicts lines 346–350 ("work is never silently reaped unless verified landed… a cut yields rc 124, which this function treats exactly like any other failure"): every other git call in the function checks its rc, this one does not.

---

## 3. `reobserve_effects` reports `dark` when it could not look at all, and the escalation asserts it "confirmed dark"

**What** — When `cwd` is empty or is not an existing directory, the whole probe block is skipped and the initialized value `dark` is printed, which `resolve_page` treats as a positive observation of no work-products.

**Where** — lines 264, 265, 290; consumed at 301–302; asserted at 318.

```bash
  local cwd="$2" since="$3" verdict=dark rc=0
```
```bash
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
```
```bash
  printf '%s' "$verdict"
```
```bash
  page "$1" ESCALATED "no work-products across the page deadline; supervisor re-read confirms dark (still not auto-acting)"
```

**Why it is wrong** — Input: a STALL?-paged session whose telemetry row has no `.cwd` field, or whose worktree path has been moved/removed. Nothing was probed — no git call, no filesystem walk — yet the function returns the same token as a completed probe that found nothing, so `resolve_page` escalates and pages the operator with the claim that a re-read *confirmed* the session is dark. This is the "action taken on an unproven premise" the `unknown` state exists to prevent: lines 252–261 define `unknown` as "WE COULD NOT LOOK", but only the two rc-124 paths (268, 285) ever produce it. Compare `work_landed`, which handles its own unprobeable input by refusing to conclude (line 353).

---

## 4. The `-newer` reference mtime is built by an unchecked `date`/`touch` pair; both failure modes yield a confident wrong verdict

**What** — The reference file's timestamp comes from `date -r "$since"` with a 1970 fallback, and `touch`'s own failure is discarded, so a failure on either side silently pins the verdict to `fresh` or to `dark`.

**Where** — line 277 (with the unguarded `$paged_at` passed at line 300).

```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```
```bash
  local effects; effects="$(reobserve_effects "$sid" "$cwd" "$paged_at")"
```

**Why it is wrong** — Failure direction A: `date -r <epoch>` is the BSD form; GNU coreutils `date -r` takes a *filename*, so on a GNU host it fails and the fallback stamps `$ref` at 1970-01-01. Every file in the tree is then `-newer` than the reference, `hit` is non-empty on the first candidate, and the verdict is `fresh` unconditionally — the escalation path is silently dead for every session while the IDL fills with `page_void … "fresh-effects-after-deadline"`. The same fallback fires platform-independently when `$since` is empty: line 298 guards with `${paged_at:-0}` but line 300 passes `$paged_at` raw, so an empty or truncated `.page` file reaches here as `""`. Failure direction B: if `touch` itself fails (its stderr is discarded and its rc unchecked), `$ref` keeps `mktemp`'s mtime of *now*, nothing can be newer, the verdict is `dark`, and a healthy lead is escalated — precisely the silence-reap that lines 271–272 say this construction exists to avoid.

---

## 5. `pid_alive_owner` matches "claude" anywhere in the command line, so a recycled pid is read as the original owner

**What** — The ownership test is an unanchored, case-insensitive fixed-string search over the entire command line (path and arguments included), not an argv0 identity check.

**Where** — line 432 (pattern default at line 95).

```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong** — Input: a session exits and the OS recycles its pid to any process whose command line merely mentions the string `claude` — a hook (`bash /Users/…/.claude/hooks/cc-permission-beacon.sh`), a `jq` reading `~/.claude/...`, `cc-notify` itself. `pid_alive_owner` returns 0, so line 477's DEAD branch is skipped: no `work_landed` check, no `checkpoint_preserve`, no DEAD page. The row instead takes the STALL? branch and is paged as a live-but-stale candidate, and if the command keeps matching it is eventually dropped by `gc_stale` at 6h with its worktree never checkpointed. That is exactly the class lines 423–427 claim this function resolves ("route it to DEAD, insurance intact"). The same file's `live_pane_count` (line 594) shows the identity clause this check needed — anchored on argv0 with `/claude$` — but that clause is not used here.

---

## 6. `page()` writes its IDL record before the damping returns, contradicting the documented "IDL/mailbox-quiet" behaviour

**What** — The `idl page` record is emitted unconditionally at the top of `page()`, above both damping early-returns, so a standing page is re-recorded on every sweep.

**Where** — lines 204–209 and 215.

```bash
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
  # composer damping: ONE notify per sid per STATE — a re-sweep of an already-notified state stays
  # IDL/mailbox-quiet; a state CHANGE (DEAD→ESCALATED) re-notifies (2026-07-19 page-storm fix: every
```
```bash
  [ "$last" = "$2" ] && return 0
```

**Why it is wrong** — Input: any session with a standing page (a stranded DEAD row is never removed from `$TEL_DIR`, so it re-pages forever). The notify is damped, but a `kind:"page"` line is appended to the IDL every `SWEEP` — 2/minute at the default 30s, ~2,880/day for one incident. The IDL is the S-4 audit surface this daemon is judged by; any consumer counting page records sees thousands of pages where one page occurred. The comment two lines below asserts the opposite behaviour, so code and stated contract disagree about what the record means. (`page_permpend` at line 239 has the same ordering but only claims notify damping, so it is consistent.)

---

## 7. The blind-spot self-check compares live panes against *all* telemetry files, including rows for dead sessions

**What** — `self_check` is handed `n`, the count of every `.json` file enumerated in `$TEL_DIR`, and subtracts it from the live interactive-claude process count, so telemetry rows belonging to already-dead sessions mask live panes that have no row.

**Where** — lines 632, 642, 607.

```bash
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
```
```bash
  self_check "$n"
```
```bash
  delta=$(( live - enum ))
```

**Why it is wrong** — Input: a fleet where some dead sessions left stranded worktrees. Those rows are *never* removed — `reap_clean` only fires for clean+landed completions (line 482), and `gc_stale` explicitly skips non-owner pids (line 453) — so they sit in `$TEL_DIR` indefinitely. With 5 live panes, 2 of which have telemetry, plus 3 leftover dead rows, `enum` = 5, `live` = 5, `delta` = 0, and the detector re-arms at line 610 and stays silent. Three live sessions then have no coverage on any path (DEAD/STALL?/PAST-THRESHOLD/permission-beacon all iterate that dir), which is the precise condition lines 573–578 say this check exists to surface, and the sweep emits an all-clear heartbeat.

---

## 8. The B-1 branch is gated on telemetry freshness, which excludes the class it claims to cover

**What** — The PAST-THRESHOLD check requires `age < STALL_S`, using telemetry recency as a liveness proxy; a session that is past the threshold, demonstrably alive by its transcript, but telemetry-stale falls past it into the OK branch and has its standing page cleared.

**Where** — lines 515, 519–520.

```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
```
```bash
  # OK — clear any stale page (fresh + below threshold + alive).
  clear_page "$sid"; echo 0
```

**Why it is wrong** — Input: a live-owner session at `used_pct ≥ 73` inside one long turn. Lines 380–386 establish that the statusline "renders ZERO times" for exactly such a session, so its telemetry goes stale (measured: 3.5 days stale with a 5-minute-warm transcript). `age ≥ STALL_S` makes the STALL? branch at 497 apply, but the warm transcript at 499 drops it out; then line 515's second condition is false, so no PAST-THRESHOLD page is issued. The B-1 charter at lines 23–24 is "a session hung/**working-past-boundary** never Stops" — the long-turn worker is the primary member of that class, and it is the one the gate filters out. Control then reaches line 520, whose comment states the precondition "fresh + below threshold + alive" while the code arrives there with a session that is neither fresh nor below threshold, deleting both its `.page` and its `.notified` damping marker.

---

## 9. The permission-beacon reap uses bare `kill -0`, the exact test this file elsewhere rejects

**What** — REAP 1 decides "owning session provably DEAD" from `kill -0` alone, rather than `pid_alive_owner`.

**Where** — line 554.

```bash
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong** — Input: a session that died while a permission prompt was pending, whose pid has since been recycled to an unrelated process. `kill -0` succeeds, the beacon is not reaped, and once `age ≥ PERMPEND_NOTICE_S` the supervisor pages `⛔ PERMISSION-PENDING — session <sid> blocked …` for a prompt and a session that no longer exist, sending the operator to approve something in a dead pane; the beacon then persists until the 24h horizon at line 560. Lines 422–427 name this exact failure ("kill -0 proves only that SOME process holds the pid") and `pid_alive_owner` was written for it; `assess` uses it, this path does not.

---

## Minor (same class, lower impact)

**What** — `$cwd` is interpolated raw into IDL JSON despite `json_str` existing for precisely this reason.

**Where** — lines 338 and 374.

```bash
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
```
```bash
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
```

**Why it is wrong** — A worktree path containing a `"` or `\` (both legal on macOS) produces an unparseable IDL line, so the reap/checkpoint outcome record is lost to any JSON consumer — the malformed-IDL class named at lines 183–184 ("never raw-%s a worker/command string into JSON"). `beacon_cmd`'s output is passed through `json_str` at line 238; the cwd paths are not.
