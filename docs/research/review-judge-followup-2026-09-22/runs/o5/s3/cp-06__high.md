Line numbers below count `#!/bin/bash` as line 1.

---

## 1. `checkpoint_preserve` records a checkpoint that never ran, and the DEAD page asserts it happened

**What** — Only rc 124 is treated as "checkpoint did not happen"; a missing `teammate-checkpoint.sh`, any other non-zero rc, or a missing/empty `cwd` all end with an IDL `checkpoint` record (or with no record at all) while the DEAD page text claims the worktree was preserved.

**Where** — lines 324, 325, 330, 338, and the caller at 485:
```bash
  [ -n "$cwd" ] && [ -d "$cwd" ] || return 0
  if command -v teammate-checkpoint.sh >/dev/null 2>&1; then
    CC_CHECKPOINT_MEMBER="supervisor-$1" sup_bounded "$SUP_CKPT_TIMEOUT_S" teammate-checkpoint.sh "$cwd" >/dev/null 2>&1 || rc=$?
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
    checkpoint_preserve "$sid" "$cwd"; page "$sid" DEAD "$why; worktree checkpoint-preserved"; echo 1; return
```

**Why it is wrong** — `command -v teammate-checkpoint.sh` is a bare PATH lookup, and this file documents at lines 51–56 and 115–116 that launchd runs the daemon under a minimal PATH (which is why `timeout` and `cc-notify` are resolved by absolute path). Under launchd the lookup fails, the `if` body is skipped, `rc` stays 0, and line 338 writes a `checkpoint` outcome record for work that was never attempted; the operator page then states "worktree checkpoint-preserved". The same happens for any ordinary failure of the script (rc 1, rc 127, non-git worktree), and when `cwd` is empty/absent the function returns at line 324 with no record at all while the page still claims preservation. The one act the file calls "safe, effect-verified" is reported as a success without being verified.

---

## 2. A dead worker with unlanded/dirty work can be silently reaped, because a failed `git status` reads as "clean tree"

**What** — `work_landed` captures `git status --porcelain` output only, discarding the exit status, so a cut (rc 124) or otherwise failing `status` produces empty output and passes the clean-tree gate.

**Where** — line 355, with the consequence at 482:
```bash
  [ -z "$(sup_git -C "$cwd" status --porcelain 2>/dev/null)" ] || return 1
    if work_landed "$cwd"; then reap_clean "$sid" "$cwd"; echo 0; return; fi
```

**Why it is wrong** — Lines 347–350 state the contract explicitly: "A cut yields rc 124, which this function treats exactly like any other failure — return 1". The two neighbouring git calls (354, 356) do honour that with `|| return 1`; this one does not. Condition: a dead worker whose worktree holds uncommitted work, on a branch with no commits ahead of `$TRUNK`, while `git status` is cut at the 15s bound or fails (index.lock contention, unreadable `.git`). Output is empty ⇒ "clean"; `rev-list --count` returns `0` ⇒ the fast path at 357 returns "landed"; `reap_clean` then deletes the telemetry row and clears the page. The stranded work is never checkpointed and never paged, and the row that was the only handle on it is gone — exactly the "silently reaped" outcome line 347 forbids.

---

## 3. The effects re-read returns `dark` — the escalation-triggering verdict — in cases where it never looked

**What** — `verdict` is initialised to `dark` and returned unchanged when the probe could not be performed at all: empty `cwd`, non-existent `cwd`, `mktemp` failure, or a `cwd` that is not a git repo and whose file-mtime probe was skipped.

**Where** — lines 264, 265, 275, 290:
```bash
  local cwd="$2" since="$3" verdict=dark rc=0
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
      local ref; ref="$(mktemp 2>/dev/null)"
  printf '%s' "$verdict"
```

**Why it is wrong** — Lines 252–262 define `unknown` as "WE COULD NOT LOOK" and state that folding a could-not-look into `dark` "would ... manufacture the escalation this whole protocol exists to prevent". Only the two `rc = 124` paths produce `unknown`. A telemetry row with no `.cwd` field, or a `cwd` whose directory is temporarily unmounted/renamed, or a `mktemp` that fails because TMPDIR is full, yields `dark` with zero observations made; `resolve_page` (301–302) then calls `escalate_page`, whose page text (318) asserts "supervisor re-read confirms dark". That is an escalation on an unproven premise, reported to the operator as a confirmed observation.

---

## 4. A failed `date -r` makes every effects re-read report `fresh`, disabling escalation entirely

**What** — When `date -r "$since"` fails, the fallback sets the reference file's mtime to 1970-01-01, so `find -newer "$ref"` matches essentially any file in the tree and the verdict becomes `fresh`.

**Where** — line 277:
```bash
        touch -t "$(date -r "$since" +%Y%m%d%H%M.%S 2>/dev/null || echo 197001010000)" "$ref" 2>/dev/null
```

**Why it is wrong** — `date -r <epoch>` is the BSD form; on a GNU-coreutils `date` (`-r` means "reference file") it fails, as it does for any unparseable `$since`. The fallback then back-dates the reference to the epoch, so the very first regular file the pruned walk encounters is "newer", `verdict=fresh`, and `resolve_page` files `page_void` with `"why":"fresh-effects-after-deadline"`. A genuinely hung lead is exonerated on every deadline forever, and the audit trail records it as "alive + working" — the outcome line 260 names as the thing that "would silently EXONERATE a genuinely hung lead". (The sibling failure is equally unchecked: if `touch` itself fails, `$ref` keeps its creation mtime of *now*, nothing is newer, and the verdict is `dark` ⇒ escalation.)

---

## 5. `OWNER_PAT` is substring-matched against the whole command line, so unrelated processes count as session owners

**What** — Ownership is decided by a case-insensitive substring search for `claude` anywhere in the recycled pid's full command line, not by the process being a Claude session.

**Where** — lines 95 and 432:
```bash
OWNER_PAT="${CC_SUP_OWNER_PAT:-claude}"               # a live pid OWNS its telemetry row only if its process command matches this — kill -0 alone reads a RECYCLED pid as the original session (the STALL? zombie)
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong** — Any process whose argv contains the string, including every script under `~/.claude/...` that this tree runs (hooks, `cc-notify`, `teammate-checkpoint.sh`, this daemon itself), matches. Condition: a dead session's pid is recycled onto such a process. `pid_alive_owner` returns 0, so `assess` skips the DEAD branch at 477 entirely — no `checkpoint_preserve`, no DEAD page for a possibly dirty/unlanded worktree. Instead the row is treated as a live owner and paged as `STALL?` for a session that no longer exists, and the row is only silently dropped by `gc_stale` six hours later (GC never pages). Lines 426–427 claim the "recycled-by-NON-claude case" is routed to DEAD with "insurance intact"; the matcher does not cover that class.

---

## 6. `ps -p ... -o command=` is width-truncated, so a live session can be misclassified DEAD

**What** — `pid_alive_owner` reads the command line without `-ww`, so BSD `ps` truncates it (79 columns when stdout is not a tty, as it is here — a pipe under launchd), and the owner pattern can fall outside the truncated text.

**Where** — line 432:
```bash
  ps -p "$p" -o command= 2>/dev/null | grep -qiF "$OWNER_PAT"
```

**Why it is wrong** — `live_pane_count` at line 592 deliberately uses `ps -wwEo command=` for the same identity question; this call does not. Condition: a live session whose argv0 is a long interpreter path (e.g. a version-manager `node` path) so that the first occurrence of `claude` sits past column 79. `grep` finds nothing, `pid_alive_owner` returns 1, and `assess` takes the DEAD branch for a running session: it either pages a false DEAD for a live lead, or — if its worktree is clean and landed — calls `reap_clean`, deleting the telemetry row of a live session and removing all supervisor coverage for it.

---

## 7. The B-1 check excludes the very case B-1 claims to cover, and treats going telemetry-stale as recovery

**What** — The PAST-THRESHOLD page requires *fresh* telemetry (`age < STALL_S`), so a session past the fill threshold that is inside one long turn (the hung/working-past-boundary case) never gets the page; it falls through to the OK branch, which deletes any existing page and notify marker.

**Where** — lines 515 and 520:
```bash
  if [ "$used" -ge "$T" ] && [ "$age" -lt "$STALL_S" ]; then
  clear_page "$sid"; echo 0
```

**Why it is wrong** — Lines 23–24 claim this daemon "independently covers a session PAST-THRESHOLD ∧ NOT-STOPPING — ... a session hung/working-past-boundary never Stops", and lines 381–384 establish that precisely such a session emits no telemetry ("a session inside ONE long operation, or genuinely hung, renders ZERO times"), going stale for hours. Condition: `used_pct` ≥ 73, telemetry ≥ 1800s stale, transcript warm (so the STALL? branch at 499 falls through). Result: no PAST-THRESHOLD page for the exact class the boundary hook is blind to, and `clear_page` at 520 wipes the `.page` and `.notified` files of any page raised earlier — so the condition reads as "recovered" and re-pages from scratch whenever the statusline happens to emit again.

---

## 8. `resolve_page` can escalate off a deadline stamp left by an unrelated page state

**What** — The deadline clock is stamped only on the first page for a sid, regardless of state, so a `STALL?` page raised over a pre-existing `PAST-THRESHOLD` (or `DEAD`) `.page` file is resolved — and can be escalated — in the same sweep it was first raised.

**Where** — lines 203, 507, 509:
```bash
  [ -f "$pf" ] || printf '%s\n' "$(now)" > "$pf"           # stamp the deadline clock on first page only
      local had_page=0; [ -f "$PAGEDIR/$sid.page" ] && had_page=1
      [ "$had_page" = 1 ] && resolve_page "$sid" "$cwd"
```

**Why it is wrong** — Condition: a session is paged PAST-THRESHOLD at T0 (line 516 calls `page`, which stamps `.page`), then more than `DEADLINE_S` later it goes telemetry- and transcript-stale. On the *first* STALL? sweep, `had_page` is 1 (the stale PAST-THRESHOLD file), `page` does not re-stamp, and `resolve_page` computes `now - T0 ≥ DEADLINE_S` ⇒ it re-observes immediately and, on `dark`, escalates. The invariant stated at lines 503–505 — "The deadline clock starts AT the page; re-observation belongs to a later sweep" — is violated, and the same-sweep-escalate the guard at 507 exists to prevent happens anyway. The re-read window is also wrong: `since` is T0, a moment unrelated to the stall being judged.

---

## 9. `cwd` and page detail are interpolated raw into IDL JSON

**What** — Strings taken from telemetry (`cwd`) and the page detail are embedded directly in the IDL line instead of going through `json_str`.

**Where** — lines 335, 338, 374, 204:
```bash
    idl checkpoint_timeout "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"bound_s\":$SUP_CKPT_TIMEOUT_S,\"why\":\"teammate-checkpoint.sh exceeded its bound and was cut — the dead lead's worktree is NOT checkpoint-preserved; the DEAD page below still fires\""
  idl checkpoint "\"sid\":\"$1\",\"cwd\":\"$cwd\",\"why\":\"dead-lead-preserve\""
  idl reap "\"sid\":\"$1\",\"cwd\":\"$2\",\"why\":\"clean-completion-shipped-clean-worktree\""
  idl page "\"sid\":\"$1\",\"state\":\"$2\",\"detail\":\"$3\""
```

**Why it is wrong** — Lines 182–183 state the rule and the incident behind it: "never raw-%s a worker/command string into JSON (the malformed-IDL class...)". A `cwd` containing a `"` or `\` — both legal in POSIX/macOS paths — produces an unparseable IDL line. For `reap` that line is the *only* durable record of a telemetry-row deletion (lines 370–371 call it "an outcome record, never a silent deletion"), so a jq-based reader of the IDL either errors or skips it, and the deletion becomes effectively silent.

---

## 10. The permission-beacon reap uses bare `kill -0`, the check this file elsewhere calls a lie

**What** — REAP 1 decides the owning session is dead using `kill -0` alone, not `pid_alive_owner`.

**Where** — line 554:
```bash
      if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
```

**Why it is wrong** — Lines 423–425 establish that "kill -0 proves only that SOME process holds the pid" and that a dead session's pid is recycled. Condition: a session died while its permission beacon was on disk, and its pid has since been recycled to any process. `kill -0` succeeds, the beacon is not reaped, and once `age ≥ PERMPEND_NOTICE_S` the daemon fires a `PERMISSION-PENDING` page telling the operator to "approve or deny" a prompt belonging to a session that no longer exists. `page_permpend` has no deadline/re-observation path, so nothing ever retracts it; the beacon then sits until the 24h `PERMPEND_HORIZON_S` reap.

---

## 11. The world-view self-check compares counts, so stale rows mask the blind spot it exists to detect

**What** — `delta = live - enum` where `enum` is every file in `$TEL_DIR`, including rows belonging to sessions that are dead or long gone, so uncovered live panes are cancelled out one-for-one by leftover rows.

**Where** — lines 607, 632, 642:
```bash
  delta=$(( live - enum ))
      n=$((n+1)); r="$(assess "$f")"; found=$(( found + ${r:-0} ))
  self_check "$n"
```

**Why it is wrong** — Condition: three live panes whose statusline is not emitting (so they have no telemetry row) plus three leftover rows for sessions that have exited. `live = 3`, `enum = 3`, `delta = 0` ⇒ line 609 writes `0 0` ("re-arm on recovery") and returns, and `heartbeat` emits a clean all-clear. Lines 577–578 state the detector's purpose: sessions absent from the world-view "have no pager at all, and nothing says so." In this state nothing says so, and the check reports recovery rather than abstention.

---

## 12. The headless-invocation exclusion only scans argv positions 2–7

**What** — `live_pane_count` looks for `-p`/`--print`/`--version` in fields 2 through 7 only, so a headless invocation with more leading flags is counted as an interactive pane.

**Where** — line 595:
```bash
      for (i=2; i<=7 && i<=NF; i++) if ($i=="-p" || $i=="--print" || $i=="--version") next
```

**Why it is wrong** — Line 586 states the clause excludes "headless one-shots (-p/--print/--version)" as a class. A call such as `claude --settings … --add-dir … --allowedTools … --model … -p "…"` places `-p` beyond field 7 and is counted as a live pane. `live` is then inflated relative to `enum`, and since headless one-shots write no telemetry row, the inflation persists across sweeps, satisfying `SELFCHECK_MIN_PERSIST` and firing a SELF-CHECK blind-spot page that tells the operator live sessions have no supervisor coverage when none are missing.
