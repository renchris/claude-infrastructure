# Review — `scripts/lead-supervisor.sh`

Line numbers count the listing with `#!/bin/bash` as line 1; each is given with the verbatim line so it can be located if my count drifts by a line or two.

---

## 1. A `timeout -k` kill produces rc 137, but every cut-detection tests only for 124

**What** — `sup_bounded` passes `-k 5`, so a child that ignores SIGTERM is SIGKILLed and `timeout(1)` exits **137**, not 124; all three call sites that classify a cut compare against 124 only, so the KILL case is misclassified as a normal command failure.

**Where**

- line 81: `  "$SUP_TIMEOUT_BIN" -k 5 "$s" "$@"`
- line 270: `    [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- line 286: `        [ "$rc" = 124 ] && { printf 'unknown'; return; }`
- line 333: `  if [ "$rc" = 124 ]; then`

**Why it is wrong** — The comment at lines 76–77 names the exact triggering input: "a fork that ignores TERM (a wedged AppleEvent client does)". For such a fork, GNU `timeout` returns 137 (128+9), not 124. In `reobserve_effects` the `unknown` branch is then skipped: the `git log` path leaves `last_commit` empty (`0 -gt since` false) and the `find` path leaves `hit` empty, so `verdict` stays `dark`. `resolve_page` routes `dark` to `escalate_page` — the supervisor escalates on a state it never observed, which is precisely what the third state at lines 253–263 exists to prevent. In `checkpoint_preserve`, rc 137 falls past line 333 to line 339 and records `idl checkpoint … "why":"dead-lead-preserve"` for a checkpoint that was killed.

---

## 2. `checkpoint_preserve` records a successful checkpoint when none was attempted or when it failed

**What** — Any outcome other than rc 124 — including "the script does not exist" and ordinary failure rcs (1, 127, 137) — falls through to an unconditional `idl checkpoint` success record, and the DEAD page asserts preservation regardless.

**Where**

- line 326: `  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then`
- line 331: `    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?`
- line 339: `  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""`
- line 325: `  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0`
- line 485: `    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return`

**Why it is wrong** — If `teammate-checkpoint.sh` is not on PATH (the launchd minimal-PATH case this file worries about at lines 52–57), the `if` body never runs, `rc` stays 0, and line 339 writes an IDL record claiming the dead lead's worktree was preserved. Same for a checkpoint that exits non-zero because git failed. Independently, line 325 returns 0 for a missing/empty `cwd` without recording anything, yet line 485 still pages the operator with the literal text "worktree checkpoint-preserved". The one piece of insurance the DEAD page promises is reported as delivered on an unproven premise; only the rc-124 path (line 336) is honest about it.

---

## 3. `work_landed` can return "clean+landed" for a branch that `git cherry` marked as unlanded

**What** — Under `set -o pipefail`, `grep -q` exiting early on its first match can make the pipeline return 141 (printf killed by SIGPIPE), which is non-zero, so the `|| return 0` fires and the function reports "landed" even though a `+` line was found.

**Where**

- line 33: `set -uo pipefail`
- line 363: `    printf '%s\n' "$cherry_out" | grep -q '^+' || return 0`

**Why it is wrong** — Condition: `cherry_out` is larger than the pipe buffer (~64 KiB, i.e. roughly 1500+ ahead commits, which happens with a stale `origin/main`) and an unlanded `+` commit appears early. `grep -q` matches, exits 0 immediately and closes the pipe; the forked `printf` still has data to write, dies on SIGPIPE with 141; `pipefail` makes the pipeline status 141; `|| return 0` executes. `assess` line 482 then calls `reap_clean`, which deletes `$TEL_DIR/$sid.json` and `clear_page`s the session — the dead lead's unlanded commits are never checkpointed, never paged, and the row that would have surfaced them is gone. This is the "work is never silently reaped unless verified landed" guarantee at lines 347–348 failing in the unsafe direction. (`pid_alive_owner` at line 432 has the same `cmd | grep -q` shape; its single short line of `ps` output makes the race far less reachable, but the failure there routes a *live* session to the DEAD branch.)

---

## 4. The same-sweep escalation guard keys on a state-agnostic `.page` file, so a pre-existing page of a *different* state defeats it

**What** — `had_page` only asks whether `$PAGEDIR/$sid.page` exists, but that file is created by *any* page state and its timestamp is never refreshed, so a STALL? page issued while a PAST-THRESHOLD (or DEAD) page is standing resolves in the same sweep against an already-expired deadline.

**Where**

- line 204: `  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only`
- line 507: `      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1`
- line 508: `      page "$sid" "STALL?" "pid alive but telemetry ${age}s + transcript ${tage}s stale — CANDIDATE; re-observing effects at deadline"`
- line 509: `      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"`

**Why it is wrong** — Input: a session pages PAST-THRESHOLD at T0 (line 516), which stamps `.page` with T0; more than `DEADLINE_S` later it goes telemetry- and transcript-stale and enters the STALL? branch. `had_page` is 1, so `resolve_page` runs on the very sweep that issues the first STALL? page; `paged_at` is T0, so the deadline check at line 299 passes immediately and `reobserve_effects` is given `since=T0`. A dark read escalates to ESCALATED in the same sweep, with no deadline wait and no re-observation window — the phantom same-sweep escalate that lines 500–506 claim to have deferred. The identical path opens when a DEAD-paged session's pid is recycled to a `claude` process (the scenario lines 422–428 describe), making `pid_alive_owner` true again.

---

## 5. `reobserve_effects` reports `dark` when the filesystem probe could not be performed at all

**What** — If `mktemp` fails, the whole file-mtime probe is skipped and `verdict` stays at its `dark` initial value; if `touch`/`date -r` fails, the reference file keeps its creation mtime (now) so nothing can be newer — again `dark`. Neither is reported as `unknown`.

**Where**

- line 265: `  local cwd="$2" since="$3" verdict=dark rc=0`
- line 276: `      local ref; ref="$(mktemp 2>/dev/null)"`
- line 277: `      if [ -n "$ref" ]; then`
- line 278: `        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null`

**Why it is wrong** — Condition: `TMPDIR` unwritable or the tmp filesystem full ⇒ `ref` empty ⇒ the `if` at line 277 is skipped entirely ⇒ `printf '%s' "$verdict"` prints `dark` ⇒ `resolve_page` escalates a session whose work-products were never examined. This is the exact conflation the function header (lines 257–263) forbids: "folding a cut probe into `dark` would let a slow-but-healthy repo … manufacture the escalation this whole protocol exists to prevent." The `touch` failure path is silent for the same reason — its rc is discarded. The `|| echo 197001010000` fallback fails in the opposite direction: where `date -r <epoch>` is unsupported (GNU `date -r` takes a *file*), `ref` is stamped at the 1970 epoch, every file in the tree is `-newer` than it, and `reobserve_effects` returns `fresh` unconditionally — silently exonerating a genuinely hung lead forever.

---

## 6. The permission-beacon reap uses bare `kill -0`, the liveness test this file elsewhere documents as unsound

**What** — REAP 1 decides "owning session provably DEAD" with `kill -0` alone, not `pid_alive_owner`, so a recycled pid keeps a dead session's beacon alive.

**Where**

- line 554: `      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then`

**Why it is wrong** — Lines 422–424 state the rule for this file: "kill -0 proves only that SOME process holds the pid — after a session exits, the OS recycles its pid to an unrelated process". Input: a session with a pending permission beacon is hard-killed and its pid is reused. `kill -0` succeeds, so the beacon is not reaped, `age` keeps growing past `PERMPEND_NOTICE_S`, and `page_permpend` pages the operator about a permission prompt on a session that no longer exists — repeatedly (a new beacon `ts` is not needed; the first page's marker damps re-notifies, but the page and the `permission_pending` IDL records stand) until the 24 h `PERMPEND_HORIZON_S` finally reaps it. The comment on line 550 asserts "owning session provably DEAD (pid gone via its telemetry)" — the check does not prove that.

---

## 7. The B-1 branch cannot fire for the long-turn past-threshold session it exists to cover, and the OK branch then clears its page

**What** — The B-1 test conjoins `age < STALL_S`, so a session that is past threshold *and* in one long turn (statusline not rendering ⇒ telemetry stale) but with a warm transcript matches neither the STALL? branch nor B-1, and falls into the OK branch which deletes any standing page.

**Where**

- line 499: `    if [ "$tage" -ge "$STALL_S" ]; then`
- line 515: `  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then`
- line 519: `  # OK — clear any stale page (fresh + below threshold + alive).`
- line 520: `  clear_page "$sid"; echo 0`

**Why it is wrong** — Input: `used_pct=80` (≥ `T`=73), telemetry `age`=3000 s (≥ `STALL_S`=1800), transcript age 60 s, pid a live claude owner. Line 497's outer condition is true, but line 499 is false (warm transcript), so control leaves the block; line 515 is false because `age` is not `< STALL_S`; execution reaches line 520 and `clear_page` removes both `.page` and `.notified`. The session gets no page at all — yet this is exactly B-1's stated class (lines 24–25: "a session hung/working-past-boundary never Stops"), and the file itself explains at lines 381–386 that a healthy long turn *is* the case that makes telemetry stale while the transcript stays warm. The comment on line 519 describes the reached state as "fresh + below threshold + alive"; here it is neither fresh nor below threshold.

---

## 8. The blind-spot self-check compares counts, so unreaped dead telemetry rows mask uncovered live panes

**What** — `self_check` compares the number of live `claude` processes against the number of files in `$TEL_DIR`, with no identity matching, so stale rows belonging to already-dead sessions offset live panes that have no row.

**Where**

- line 606: `  delta=$(( live - enum ))`
- line 608: `  if [ "$delta" -le "$PANE_DELTA_TOL" ]; then`
- and the count it is fed, line 630-ish: `      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))`

**Why it is wrong** — `$TEL_DIR` rows are removed only by `reap_clean` (clean dead workers) and `gc_stale` (live-owner rows past 6 h), so a dirty/unlanded dead session's row persists indefinitely by design (lines 441–443 say GC must leave them). Input: 5 live panes, of which 2 have no telemetry row, plus 2 lingering rows for dead sessions ⇒ `enum`=5, `live`=5, `delta`=0 ⇒ the branch at line 608 re-arms the state file and returns, emitting a clean heartbeat. The two live, entirely unpagered panes — the condition described at lines 574–579 as having "NO pager coverage on any path" — are not detected, and the detector reports all-clear.

---

## Lower-severity

**9. `SWEEP` is bounded only from above.** Line 89: `[ "$SWEEP" -le "$SUPERVISOR_SWEEP_MAX_S" ] 2>/dev/null || SWEEP="$SUPERVISOR_SWEEP_MAX_S"`. `SUPERVISOR_SWEEP=0` (or a negative value) passes `-le` and is accepted, so the daemon loop at the bottom runs `sleep 0` and sweeps continuously — forking `git`/`find`/`ps` without pause. Non-numeric input is caught (the `[` error routes to the default); zero and negative are not.

**10. `sid` from telemetry is interpolated raw into IDL JSON and into file paths, without the validation the beacon loop applies.** Line 466: `sid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)"; [ -n "$sid" ] || { echo 0; return; }` feeds line 205 (`"\"sid\":\"$1\"…"`) and line 203 (`local pf="$PAGEDIR/$1.page" …`). A `session_id` containing `"` produces a malformed IDL line — the failure class lines 184–185 warn about and provide `json_str` for — and one containing `/` writes the page marker outside `$PAGEDIR`. The beacon loop guards its equivalent value at line 547 (`case "$sid" in *[!A-Za-z0-9._-]*|''|.|..) continue ;; esac`); `assess` does not.

**11. `work_landed`'s cherry path reads empty output as "landed".** Line 363: `    printf '%s\n' "$cherry_out" | grep -q '^+' || return 0`. `git cherry` excludes merge commits, so a HEAD whose only commits ahead of `$TRUNK` are merges yields no output, no `+` line, and `return 0` — the content those merges brought in is treated as landed and the row is reaped at line 482.
