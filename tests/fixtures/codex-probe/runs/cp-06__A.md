- **Why it is wrong:** `timeout(1)` exits 124 only when the child dies to the initial SIGTERM. When the child *ignores* TERM and the `-k 5` SIGKILL fires, `timeout` exits 137 (128+9). The comment at lines 75–76 says `-k` exists precisely because "a fork that ignores TERM (a wedged AppleEvent client does)" must still be released — yet every cut-detection check tests only `= 124`. In `reobserve_effects` (lines 269, 285) a KILL-cut probe therefore bypasses the `unknown` branch: `last_commit`/`hit` are empty, the verdict stays `dark`, and `resolve_page` escalates — manufacturing exactly the escalation-from-an-uncut-probe the three-state contract (lines 256–262) exists to prevent. In `checkpoint_preserve` (line 332) a KILL-cut checkpoint falls through to the success record (Defect 2).

---

**Defect 4 — `reobserve_effects` reports "dark" for states it never observed: a missing/empty `cwd`, or a failed `mktemp`.**

- **Where:** lines 264–265, 275–276, 290
  ```bash
  local cwd="$2" since="$3" verdict=dark rc=0
  ```
  ```bash
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  ```
  ```bash
  local ref; ref="$(mktemp 2>/dev/null)"
  ```
- **Why it is wrong:** The verdict is *initialized* to `dark` and only ever upgraded. If the telemetry row has no `cwd`, or the worktree directory was deleted while the pid lives, both probes are skipped entirely and the function prints `dark` — so `resolve_page` escalates a session whose effects were never looked at. Same if `mktemp` fails (e.g., a full `/tmp` — plausible exactly when a machine is wedged): the file-mtime walk is silently skipped and a no-recent-commit repo reads `dark`. By the function's own contract (lines 253–254: "`unknown` = WE COULD NOT LOOK"), all of these are `unknown`, not `dark`; the code folds could-not-look into the escalation input.

---

**Defect 5 — The `find` reference timestamp line fails in both directions: a failed `date -r` stamps the ref at 1970 (everything reads "fresh"), and a silently failed `touch` leaves the ref at "now" (everything reads "dark").**

- **Where:** line 277
  ```bash
  touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
  ```
- **Why it is wrong:** `date -r <epoch>` is BSD syntax; GNU `date` treats `-r` as a *file* argument and fails — and this script elsewhere carries explicit GNU fallbacks (line 394), so GNU hosts are in scope. Wherever `date -r` fails (GNU date, or a corrupted `.page` file feeding a non-numeric `$since`), the fallback stamps the reference at 1970, `find -newer` then matches essentially every file, and the verdict is `fresh` — so a genuinely hung lead is voided at every deadline and **never escalated**, silently and permanently ("folding it into `fresh` would silently EXONERATE a genuinely hung lead", line 260). Conversely, if `touch -t` itself fails (errors are discarded by `2>/dev/null`), `$ref` keeps its `mktemp` creation time of *now*, no file can be newer, and the mtime probe is vacuously `dark` — escalating a healthy lead.

---

**Defect 6 — Telemetry rows with an empty/missing `pid` fall through every classification, land in the "OK" branch, and have their standing pages actively cleared.**

- **Where:** lines 477, 497, 520, and 453
  ```bash
  if [ -n "$pid" ] && ! pid_alive_owner "$pid"; then
  ```
  ```bash
  if pid_alive_owner "$pid" && [ "$age" -ge "$STALL_S" ] && ! is_registered_desk "$sid"; then
  ```
  ```bash
  clear_page "$sid"; echo 0
  ```
  ```bash
  pid_alive_owner "$pid" || continue                              # GONE / recycled-non-owner → leave for assess()
  ```
- **Why it is wrong:** A row whose `.pid` is absent (partial write, writer bug) can never take the DEAD branch (guarded by `[ -n "$pid" ]`), never the STALL? branch (`pid_alive_owner` fails on an empty pid), and is never GC'd (line 453 skips it, with a comment promising `assess()` will handle it — it won't). If its `ts` is stale it also fails the PAST-THRESHOLD condition (`age -lt STALL_S`), so it reaches the OK branch — commented "(fresh + below threshold + alive)", none of which was established — where `clear_page` removes any standing page for that sid. A dead or hung session whose row lost its pid is permanently invisible to every pager path, and its existing page is deleted each sweep.

---

**Defect 7 — The same-sweep escalation guard keys on the existence of *any* `.page` file, but PAST-THRESHOLD pages create one too and are never resolved, so the first STALL? sweep can escalate immediately against a deadline stamped by a different state.**

- **Where:** lines 507, 203, 515–516
  ```bash
  local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
  ```
  ```bash
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
  ```
  ```bash
  page "$sid" PAST-THRESHOLD "used ${used}% ≥ ${T}% and still running (not Stopping) — the boundary hook is blind here; advise /handoff"
  ```
- **Why it is wrong:** `resolve_page` is only ever invoked from the STALL? branch, so a PAST-THRESHOLD page's `.page` file lingers with its original timestamp (the OK branch that would clear it is unreachable while the session stays above threshold and fresh). If the session then hangs right around the threshold page (T0) and both stalenesses cross `STALL_S` ~30 minutes later, the first STALL? sweep finds the pre-existing threshold page, sets `had_page=1`, and `resolve_page` runs against a T0 deadline that expired long ago — the STALL? notify and the ESCALATED notify fire in the *same sweep* (the exact "2-notify storm" the guard's comment, lines 500–506, says it prevents), and the effects re-observation window is anchored to the threshold page rather than to the stall page, violating "the deadline clock starts AT the page".

---

**Defect 8 — Telemetry-derived strings (`sid`, `cwd`, `pid`, detail text) are raw-interpolated into IDL JSON, the exact malformed-IDL class `json_str` exists to prevent.**

- **Where:** lines 204, 335, 338, 374, 457 — e.g.
  ```bash
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
  ```
  ```bash
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
  ```
- **Why it is wrong:** `sid` and `cwd` come from telemetry JSON *content* (`jq -r '.session_id'`, `.cwd`) with no character guard (the filename guard at line 547 applies only to permission beacons), and the DEAD-page detail embeds `$pid` from the same source. A `cwd` containing `"` or `\` (legal path characters) or a corrupt/hostile `session_id` produces an unparseable IDL line for exactly the highest-stakes records — `page`, `checkpoint`, `reap`, `gc` — breaking downstream consumers of the audit trail. The file's own rule at lines 183–184 ("never raw-%s a worker/command string into JSON — the malformed-IDL class") is applied in `page_permpend`/`send_page` (`json_str`) but not on these paths.

---

**Defect 9 — The IDL `page` record is written *before* the damping check, so a standing condition writes a duplicate IDL record every sweep — contradicting the comment's claim of IDL-quiet damping; the DEAD path likewise re-runs the checkpoint every sweep.**

- **Where:** lines 204–206 and 485
  ```bash
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
  ```
  ```bash
  # composer damping: ONE notify per sid per STATE — a re-sweep of an already-notified state stays
  # IDL/mailbox-quiet; ...
  ```
  ```bash
  checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
  ```
- **Why it is wrong:** The damping early-returns (lines 209, 215) fire *after* the `idl page` call, so an already-notified standing state (a zombie STALL?, a persistent PAST-THRESHOLD session) appends an IDL `page` record every 30 s sweep — thousands of lines per day per session, and any downstream consumer that counts `page` records sees a storm the comment says was fixed. The comment claims "stays IDL/mailbox-quiet"; only the mailbox half is implemented. Relatedly, the DEAD branch has no once-guard at all: while the DEAD row sits un-reaped awaiting the operator, `checkpoint_preserve` re-executes `teammate-checkpoint.sh` (plus its `idl checkpoint` record) on every 30 s sweep for the life of the incident.

---

### Not defects, for the record

Things I checked that behave as claimed: `local ahead;` on its own line before the `$(…) || return 1` assignment (line 356) correctly preserves the exit code; the `cherry`/`diff --quiet` fallbacks in `work_landed` fail toward "page", the safe direction; `send_page`'s rc-driven marker withholding matches its stated contract; `void_page` vs `clear_page` marker semantics are internally consistent; and the permpend reap's use of raw `kill -0` acts only on proof-of-death, so its known weakness (a recycled pid) errs toward paging, not reaping.