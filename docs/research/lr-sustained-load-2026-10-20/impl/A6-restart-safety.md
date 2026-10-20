# A6: make the reconciler safe to restart (implementation design)

**Verdict:** BUILD. An agent can implement and test all of it. Turning it on needs the usual operator restart of the daemon (§7).

**Conviction:** 85%.

**Code:** `main` = worktree HEAD `28b25a119`. `git log 28b25a119..main` shows no later changes to `lr_recon/`, `handoff-fire.sh` or `lr-lib.sh` (measured). File:line citations below are to that tree.

**Labels:**
- *Measured* names its command.
- *Estimated* names its method.
- *Hypothesis* means not verified.

All research for this file was read-only. The one exception is a reproduction and two unit-test runs, which wrote only under `/tmp/a6/` (the commands are in Appendix A).

---

## 0. Summary

A daemon restart breaks three things that the reconciler assumes about its actuators.

1. **The exit code of an actuator started by the previous daemon is lost.**
   - Every actuator is a `setsid` child (`act.py:323-330`).
   - When its daemon dies, launchd adopts it and reaps it, so the new daemon's `waitpid` never sees the code.
   - `settle.dead_actuators` (`settle.py:561-565`) then returns `None`.
   - `settle_exit` (`settle.py:206-209`) then logs "code unknown — the phase decides" and scores nothing. A holder-held refusal gets no hold. A failed attempt is not bumped. A rolled-back move whose log has no `verdict=NOTMOVED` line is left as `PRE-MOVE/None`.
2. **A restart re-stamps the run claim to the new daemon's pid** (`__main__.py:1790-1794` → `store.py:427-437`).
   - The actuator the old daemon started is not a descendant of the new daemon.
   - So handoff-fire's ownership check (`hf_recycle_claim_foreign`, `handoff-fire.sh:2660-2680`) reads the claim as held by another actuator.
   - The check refuses the actuator's own recycle after the transplant (`handoff-fire.sh:16302-16305`).
3. **A restart kills the pass in progress.**
   - Settles are kept in memory and saved only at the end of the pass (`__main__.py:1728`).
   - So a score made earlier in the killed pass is lost.
   - The new daemon then re-reads the same dead process and gets "code unknown".

**The design, in four parts:**
- **(a) Durable exit capture.** The actuator wrapper writes its child's exit code to `recon/exits/<nonce>.rc`. The next daemon reads it by the spawn nonce, which is now stored on the process record.
- **(b) Explicit adoption semantics:**
  - Only the wrapper's exit is a verdict.
  - Descendant processes are liveness markers only.
  - An intent nonce found by the argv scan names its actuator.
- **(c) A claim keeper.** The run claim must name a live ancestor of whatever is driving the record. That is the daemon while it is the actuator's parent, or no actuator is live. It is the inherited wrapper while a wrapper started by an earlier daemon is still running. The startup re-stamp leaves in-flight records for the first trusted pass to decide.
- **(d) Exactly-once replay.** A killed pass's settles are replayed from the exit files. The spawn bookkeeping is saved before the pass ends.

Two optional parts:
- **(e)** A restart-forensics row, to answer the report's open question "what restarted the daemon?".
- **(f)** A pass-boundary restart request, so a deploy restart kills no pass. This needs an operator ruling.

Nothing in A6 reads load, waits for load, or turns our own timeout into a verdict.

---

## 1. Evidence

### 1.1 What each 2026-10-20 restart did (measured)

Restart rows are from `restarts.jsonl` (`tail -8 ~/.reso/limit-recover/recon/restarts.jsonl`):

| Restart | Process start (lstart) | Startup row written | pid change |
|---|---|---|---|
| R1 | 03:23:17Z | 03:23:43Z | 34812 → 47282 |
| R2 | 03:53:16Z | 03:53:21Z | 47282 → 38189 |
| R3 | 04:31:18Z | 04:31:23Z | 38189 → 51148 |

Event rows are from `python3 -I /tmp/a6/ev.py …` and `/tmp/a6/sid.py …` over `recon/events.jsonl`.

| Restart | Record | Actuator (spawned by the old daemon) | What happened | Class |
|---|---|---|---|---|
| R1 | db755a94 | R pid 89698, spawn 03:08:24 | 03:39:25 `R exited, code unknown — the phase decides`; `RECON-DEFECT PRE-MOVE/None` at 03:43:08, 03:51:29, 03:56:24 and 03:59:58; operator `refire` 04:06:15; re-driven only at 04:31:53 (`rolled-back … R rc=None → RETRY/BACKOFF`, after R3 loaded `20368fc85`) | **orphaned** for 52.5 min (03:39:25 → 04:31:53) |
| R1 | e80b61f4 | R pid 44661, spawn 03:15:54 | `!! --recycle REFUSED: another actuator holds session e80b61f4's move claim (pid 47282, lr-reconciler)` (`actlogs/e80b61f4.1.R.log:29`), then `verdict=NOTMOVED … HELD:unknown` (`:31`); 03:46:56 `R exited, code unknown` | **claim self-refusal** after the transplant; code lost |
| R1 | 769b7294 | A pid 51555, spawn 03:08:24 | 03:23:05 `A rc=6 → HOLD/HOLD-COMPOSER`. That was in the old daemon's last pass, killed at 03:23:17. At 03:28:30 the new daemon re-read the same A as `A exited, code unknown`, so the HOLD never reached disk (inferred: the dead A was still on the saved record, so the save never happened) | **mis-scored** (killed-pass loss) |
| R2 | 7aae55e1 | R pid 50017, spawn 03:43:17 | refusal naming pid 38189, the new daemon (`actlogs/7aae55e1.2.R.log:35`); 04:04:25 `R exited, code unknown` | **claim self-refusal**; code lost |
| R2 | 769b7294 | A pid 5820, spawn 03:43:17 | 03:59:01 `A exited, code unknown`; re-spawned 04:00:02 with no hold applied | **mis-scored** |
| R2 | d7eb73d2 | R pid 14105, spawn 03:23:43 | engaged 03:53:31; 03:54:17 `R exited, code unknown`. The phase table happened to derive ENGAGED | code lost, benign |
| R3 | 769b7294 | A pid 28012, spawn 04:25:51 | 04:32:49 `A rc=None → HOLD/HOLD-COMPOSER`, rescued by `20368fc85`'s actlog-verdict path (`settle.py:222-233`) | rescued, only because the log ended `NOTMOVED` |

### 1.2 Over three weeks (measured)

- **Own-actuator exits.** `python3 -I /tmp/a6/replay.py` reads `events.jsonl.1` and `events.jsonl`, 09-30 07:09Z → 10-20 12:01Z. Of 54 own-actuator exits:
  - 45 carried a code;
  - 8 read "code unknown";
  - 1 was `rc=None` and was rescued by its log.
  - All 9 without a code are restart-associated. Seven are cross-restart cases (`python3 -I /tmp/a6/cross.py`: 7 spawn→exit pairs crossed one of the 46 restarts in that span; 6 lost the code, 1 was rescued by its log). The eighth is the killed-pass re-read of 769b7294 above. The ninth is the 10-18 second B exit of 2ee922eb, whose B had spawned 08:57:10Z and first read "code unknown" at 09:52:04; by its timing it falls between the 10:03:51Z restart and 10:09:28Z and is most likely another killed-pass re-read (inferred).
  - Inside a daemon's lifetime, 0 own exits lost their code. So restarts are the whole loss.
- **Restart rate.** 4 restarts on 10-18, 5 on 10-19 and 5 on 10-20, all on development days (`restarts.jsonl`).
  - The 10-20 restarts followed lr_recon commits by 10, 12 and 19 min (`TZ=UTC git log -- scripts/limit-recover/lr_recon`).
  - The watchdog's current log has 0 kill lines (`grep -c 'killed\|KILLED' recon/watchdog.log` => 0). Restarts are therefore deploys or manual (hypothesis for the cause; nothing on disk records it).
- **Spawn volume.** `python3 -I -c …` over `events.jsonl*` counts 53 spawns, at most 27 a day. So one exit file per spawn is negligible.

### 1.3 Reproduction on today's code (measured; all state in `/tmp/a6/repro/`)

`python3 -I -B /tmp/a6/repro/repro.py <worktree> {today|fix} {old|new}`:
1. "daemon 1" takes the claim, starts the real wrapper (`setsid`) and exits.
2. The wrapper's child runs handoff-fire's real `hf_recycle_claim_foreign`, extracted by `sed` from `scripts/handoff-fire.sh`.
3. "daemon 2" re-stamps the claim and settles the exit with today's `settle.dead_actuators` and `settle.settle_exit`.

| Arm | Wrapper parent after daemon 1 dies | Claim names | handoff-fire check | Settle |
|---|---|---|---|---|
| today, old wrapper | `1` | daemon 2 | `foreign pid=<daemon2> by=lr-reconciler` (**the incident refusal**) | `R exited, code unknown — the phase decides` |
| today, new wrapper | `1` | daemon 2 | foreign | exit file `6` → `R rc=6 → HOLD/HOLD-COMPOSER`* |
| fix (claim → wrapper), old wrapper | `1` | wrapper W | `not-foreign` | code unknown |
| fix, new wrapper | `1` | W | `not-foreign` | exit file `6` → scored* |

\* In this probe, daemon 2 fed the file's value to `settle_exit` by hand, standing in for §3.3's reader. The wrapper writing the file is the real bash 3.2 code.

Also measured with `bash /tmp/a6/wrap_probe.sh`:
- `/bin/bash -c 'shift 4; "$@"'` stays the parent of its command. The child's `$PPID` is the wrapper, so bash 3.2.57 does not exec the last command.
- The proposed wrapper exits with the child's code: 6 → 6, and SIGTERM → 143, the same value `Popen.poll()` reads today.

### 1.4 Why the code is lost: mechanics (verified by reading the code)

- `act.spawn` (`act.py:308-352`):
  - saves the intent nonce;
  - runs `Popen(..., start_new_session=True)`;
  - keeps the Popen in `_CHILDREN`;
  - records `ProcRole(role="actuator", pid, lstart, argv_hash=<actuator>)`.

  The nonce lives only in `rec.intent` and in the wrapper's argv, not on the ProcRole (`types.py:404-410`).
- `act.reap_children` (`act.py:394-415`) gets codes only for this process's own children: `Popen.poll()`, then `waitpid(-1)`. The code goes to the in-memory `EXIT_CODES`.
- After a restart, `rec.procs` comes from disk (`store.load_all`). The wrapper is no child of the new daemon. `dead_actuators` pops nothing and returns `None`.
- `act.adopt` (`act.py:360-372`) runs every pass (`__main__.py:748`). It adds every process whose args contain `--record-id <rid>` as `argv_hash="adopted"`: the descendants (lr-handoff, handoff-fire, lr-transplant), and the wrapper itself when the procs write was lost.
  - An adopted process never has a code. That gives 134 `adopted exited, code unknown` rows in three weeks (measured, replay.py).
  - Latent defect: `EXIT_CODES` is keyed by pid and filled for **any** reaped child (`act.py:405-415`; e.g. the `_provenance` Popen at `__main__.py:529`). Pids wrap about every 86 s on this box (`lr-lib.sh:771`). So a dead adopted or inherited proc can pop another process's code, and a non-zero one is scored DETERMINISTIC by `_score`. Not observed in events (0 adopted rows carried a code), but reachable.
- `act.settle_intent` (`act.py:375-383`), the startup adoption the docstring promises (`act.py:3-7`; `architecture.md` §C2 step 4), has no caller outside tests (`grep -rn settle_intent` => `act.py` and `tests/test_act.py` only).

### 1.5 Why the claim refuses (verified by reading the code)

- `_startup` re-stamps every open record's claim to the new daemon (`__main__.py:1790-1794`).
- `hf_recycle_claim_foreign` treats any live holder that is not the caller or an ancestor as foreign:
  - it reads the holder's state with `lr_claim_holder_state` (`lr-lib.sh:810-819`);
  - it walks the ancestry with `hf_pid_is_self_or_ancestor` (`handoff-fire.sh:2610-2622`).
- The ancestry walk from handoff-fire goes handoff-fire → lr-handoff → wrapper → **1** once the old daemon is gone.
- The bash side is already pinned by `tests/handoff-recycle-self-source.bats:171-207`:
  - live foreign holder → refused;
  - ancestor → proceeds;
  - dead holder → proceeds.

  A6 changes only **which pid the claim names**. handoff-fire needs no edit.
- The other lanes check the fence before they take a claim (`lr_recon_may_act`, called from `bin/cc-lr:299`, `lr-fleet.sh:951`, `lr-move-worker.sh:129`, `lr-reset-poller.sh:176`, `lr-upgrade.sh:1268` and other sites). The fence DEFERs while the heartbeat is fresh (rule 4) or while any `owned.procs` entry is alive (rule 5) (`lr-recon-fence.sh:8-21`).

  So a claim that briefly names a dead pid cannot be stolen from a reconciler-owned record. The 03:20:12 poller steal (`stolen-dead-holder`, cited as risk in REPORT A6) was on 769b7294 while the reconciler did **not** own it: `own … held` at 03:14:35 and 03:20:37 (measured, sid.py).

---

## 2. The design

### 2.1 (a) Durable exit capture

- **Wrapper.** It runs the actuator as its child, as today. When the child ends, it writes `printf '%d\n' rc` to `$LR_RECON_ROOT/exits/<nonce>.rc`, then exits with the same code.
  - Builtins only: no fork.
  - The nonce is checked to be hex before it becomes a path.
  - The `exits/` directory must exist (`[ -d ]`), so a test or tool that runs the wrapper without `LR_RECON_ROOT` writes nothing.
- **Nonce on the record.** `ProcRole` gains `nonce: str = ""`, filled at spawn.
- **Where the reader looks.** For a dead actuator, `settle.dead_actuators` tries, in order:
  1. `exits/<nonce>.rc` (exact; survives a restart and pid reuse);
  2. `EXIT_CODES[pid]`, only for pids **this process spawned** (`_SPAWNED`);
  3. `None`, which is unknown: today's "the phase decides" path, the actlog-verdict rescue (`settle.py:222-266`) and the `IN_FLIGHT_MAX_S` bound (`__main__.py:876-896`) all still apply.
- **No exit file** means a SIGKILLed wrapper, a full disk, or a legacy wrapper. That is unknown, never a negative verdict, as the operator premise requires.
- **Retention.** Exit files are removed by age (older than 7 days, the actlog bound `ACTLOG_MAX_AGE_S`) at daemon startup, never at consumption. Removing a file at consumption could lose it if the daemon dies before the record save.

### 2.2 (b) Adoption semantics, stated as rules (they go in the `act.py` module docstring)

1. **Identity.** An actuator is (pid, lstart) for liveness and nonce for its verdict. Liveness is always read from the pass's single `ps -axww` census (`snap.alive`).
2. **Inherited.** A ProcRole loaded from the record file is tracked without a respawn. While it is alive, `may_actuate` refuses `process-live` (unchanged). When it dies, its verdict comes from its exit file.
3. **Found by argv scan.** A row whose args contain `lr-recon-act --record-id <rid> --intent <nonce>` is a **wrapper**:
   - If `<nonce> == rec.intent.nonce`, it is adopted under `rec.intent.actuator` with that nonce. This covers a daemon killed between `Popen` and the procs save (§4.5 write order).
   - Otherwise (no matching intent, which should not happen because `may_actuate` allows one live actuator per record) it is adopted as `"adopted"`. It is a liveness marker only; its nonce is kept for forensics, and its exit is never scored, because no actuator name is known to score it under.
   - Every other `--record-id` match (lr-handoff, handoff-fire, lr-transplant) is a **descendant**: `argv_hash="adopted"`, no nonce.
4. **Only the wrapper's exit is a verdict.** A descendant's death never carries a code into `settle_exit`. `dead_actuators` hands it `None` whatever `EXIT_CODES` holds, which closes the pid-reuse hole in §1.4. The event text stays `adopted exited, code unknown — the phase decides`; forensic readers use it, and no code reads it (`grep` finds no reader in `report.py`, `bin/cc-lr` or `*.sh`).
5. **Claim.** The run claim names a live ancestor of the live chain (§2.3).
6. **Unknown is not a verdict.** No code from any source → `settle_exit`'s existing `None` path, unchanged.
7. **Replay.** The record on disk keeps a dead ProcRole until a save that pruned it. The settle's effects are written in the same atomic record write (`store.atomic_write_text`, `store.py:72-79`). So a settle is applied exactly once:
   - the write happened: the proc is pruned and the effects are on disk;
   - or it did not: the proc is still listed with no effects, and the next daemon replays it from the exit file.

   Events may show a replayed exit twice. Events are not state.

### 2.3 (c) The claim keeper

```text
claim_holder_for(rec, snap, me):
    live = rec's recorded actuator procs alive by (pid, lstart) in snap, the named wrapper first
    if live and snap.procs[live[0].pid].ppid != me.pid:   # started by an earlier daemon
        return live[0]                                    # only it is an ancestor of its chain
    return me                                             # our own child, or nothing live
```

- **When it writes.** It re-stamps only a claim whose `record_id` equals the record's (`store.claim_restamp` already checks that, `store.py:430-432`). It writes only when the holder changes.
- **When it runs.** Every pass, inside `_derive`, after the exit settle and before `_own_and_charge` and `_dispatch`. So in the pass a wrapper dies, the claim comes back to the daemon before anything new is dispatched.
- **At startup:**
  - A record **with** recorded actuator procs keeps its claim as is, with a `claim-inherited` event. It names the dead old daemon (or an inherited wrapper from an earlier restart). Startup has no ps census, and the keeper decides on the first trusted pass.
  - Records **without** actuator procs are re-stamped to the new daemon, as today.
  - **The window before the first trusted pass is safe:**
    - handoff-fire reads a dead holder as not foreign (bats R2 CONTROL `:189`);
    - other lanes are fenced (rule 4: heartbeat fresh; rule 5: `owned.procs` alive);
    - the daemon's own `hold_claim` matches by `record_id` (`act.py:507-509`).
- **Why not name the wrapper for our own spawns too?**
  - Every wrapper exit would then leave a dead-holder window until the next pass.
  - Naming the daemon keeps today's no-restart behaviour exactly.
- **Why not teach handoff-fire to accept `LR_RECORD_ID == claim.record_id`?** `--record-id` is in every actuator's argv and is exported as `LR_RECORD_ID` (`handoff-fire.sh:15237`). So an argv replay, which is the exact 2026-10-18 R2 incident, would pass. The ancestor rule cannot be replayed. Rejected.
- **If our own lstart is unreadable** (`proc_lstart` timed out), the keeper writes nothing that pass. That is unknown, so it retries next pass. It never writes an lstart-less "legacy" holder.

### 2.4 (d) Exactly-once replay and spawn bookkeeping

- **Exits.** The replay of exits is §2.2 rule 7. No new code is needed beyond (a).
- **Spawn bookkeeping is not replayable.**
  - `rec.close["move_attempt"]` and `rec.close["wake_eta"]` are written after `act.spawn`'s two saves (`__main__.py:1312-1318`), and reach disk only at the end of the pass (`:1728`).
  - If the pass is killed, a restarted daemon sees a stale `move_attempt`.
  - Then an exit that is still unknown, which bumps nothing (`settle.py:206-209`), lets the next move spawn reuse the attempt number. The double-typer audit counts that as a double typer (the rule at `__main__.py:1287-1297`).
  - **Fix:** one `store.save_record(ctx.paths, rec, now)` right after that bookkeeping block. That is one more atomic write per spawn, at most 27 spawns a day (measured).

### 2.5 (e) Restart forensics (optional, recommended; separable into B6)

`_startup` adds fields to the existing `restarts.jsonl` row (`__main__.py:1796`):
- `prev_pid`, `prev_lstart`, `prev_progress_age_s`: read from `recon/heartbeat` before the new heartbeat overwrites it;
- `inflight`: open records with recorded actuator procs;
- `inherited`: `["<sid8>:<actuator>", …]`;
- `code_mtime`: max `st_mtime` of `lr_recon/*.py`, about 25 `stat` calls and no fork;
- `code_newer_than_prev`: `code_mtime` > the previous daemon's lstart as epoch.

That makes "deploy-driven" measurable (REPORT §6, the A6 open question) and counts what each restart put at risk. A row of `inflight: 0` proves a quiet restart.

### 2.6 (f) Pass-boundary restart request (optional; needs an operator ruling)

- **The request.** `recon/ctl/restart.request`, a new name in the ctl directory that `_signature` already watches (`__main__.py:1751-1765`).
- **What the daemon does.** At the end of the pass, after `save_records`, it:
  1. removes the file;
  2. appends a `restarts.jsonl` row with `cause: "requested"`;
  3. exits 0.

  launchd `KeepAlive` (`com.reso.lr-reconciler.plist:45`, ThrottleInterval 10) restarts it within about 10 s.
- **The effect.** A deploy no longer kills a pass (P5 and P9 in the incident). There is no wait for quiet: the boundary comes within one pass at any load.
- **What must exempt it.** The `restart-loop` page (`__main__.py:1797-1803`) must skip `cause=requested` rows.

### 2.7 Considered and not in A6

- **Persisting `Admission` (REPORT A6 iii).**
  - After wave 1, a restart resets the token bucket full, which is permissive. It also resets `last_drip_at` (permissive) and `refusals` (restrictive: the drip needs 3 fresh probe refusals again, `admit.py:110-118`).
  - B3's deadline override bypasses the probe and drip after `W_soft`, which makes this moot.
  - Recommended home: B3.
  - Sketch if wanted earlier: write `{refusals, last_drip_at}` to `recon/admission.json` on change; load it only while a limited record is still open. About 50 code LOC and 40 test LOC (estimated).
- **A SIGTERM handler that saves mid-pass.** It would write half-applied pass state. launchd's ExitTimeOut (20 s by default) is shorter than one placer step (120 s bound). Rejected. Replay plus (f) covers the need.
- **Relying on policy (i) "never restart mid-cohort" alone.** That is not enough:
  - The watchdog's STALL/SLOW kill (`lr-recon-watchdog.sh:315-319`) always lands mid-pass.
  - Under a standing cohort, the quiet boundary used by `lr-restart-at-boundary.sh` and `lr-band-reload.sh` (no `lr-recon-act` child, 30 min cap) may never come.

---

## 3. Exact changes

### 3.1 `scripts/limit-recover/lr_recon/types.py`

```diff
@@ class ProcRole  (types.py:404-410)
     role: str  # PROC_ROLES
     pid: int
     lstart: str
     argv_hash: str = ""
+    # the spawn nonce (act.wrap's --intent): names this actuator's exit file recon/exits/<nonce>.rc,
+    # which outlives the daemon that spawned it (A6). "" for a descendant found by argv, or a legacy row.
+    nonce: str = ""
@@ class Paths  (types.py:~300, beside `restarts`)
+    @property
+    def exits(self) -> str:
+        return self.p("exits")
@@ def reconciler_dirs  (types.py:360-370)
             self.quarantine,
             self.ctl,
+            self.exits,
         ]
```

`from_dict` ignores unknown keys and defaults missing ones (`types.py:184-191`), so old and new records load in both directions.

### 3.2 `scripts/limit-recover/lr_recon/act.py`

```diff
@@ (act.py:34)
-WRAPPER = 'shift 4; "$@"'  # $0 lr-recon-act $1..$4 = the four tokens
+# $0 lr-recon-act $1..$4 = the four tokens. The actuator runs as the wrapper's CHILD (bash 3.2 does
+# not exec the last command of a list); its code goes to $LR_RECON_ROOT/exits/<nonce>.rc, which the
+# NEXT daemon reads: a restart reparents this setsid'd wrapper to launchd, which reaps it, so no
+# waitpid of ours sees the code (2026-10-20: 6 of 7 actuators that crossed a restart read "code
+# unknown"). Builtins only. A signal-killed child is 128+N, what Popen.poll() of the wrapper reads.
+WRAPPER = (
+    'n="$4"; shift 4; "$@"; rc=$?; '
+    'case "$n" in ""|*[!0-9a-f]*) ;; *) [ -d "${LR_RECON_ROOT:-/nonexistent}/exits" ] && '
+    'printf "%d\\n" "$rc" 2>/dev/null >"$LR_RECON_ROOT/exits/$n.rc";; esac; exit "$rc"'
+)
+EXITS_OFF = "exit-files.off"   # <root>/exit-files.off: the reader ignores exit files (kill switch)
+KEEPER_OFF = "claim-keeper.off"  # <root>/claim-keeper.off: no keeper, startup re-stamps as before
+_SPAWNED: Set[int] = set()  # pids THIS process spawned: the only ones EXIT_CODES may speak for
@@ def spawn  (act.py:331-336)
     pid = int(proc.pid)
     if hasattr(proc, "poll"):  # tests inject fakes with only .pid
         _CHILDREN[pid] = proc
+    _SPAWNED.add(pid)
     rec.procs.append(
-        T.ProcRole(role="actuator", pid=pid, lstart=lstart_of(pid), argv_hash=actuator)
+        T.ProcRole(role="actuator", pid=pid, lstart=lstart_of(pid), argv_hash=actuator, nonce=nonce)
     )
@@ def adopt  (act.py:360-372)
+_WRAPPER_TOK = re.compile(r"lr-recon-act --record-id (\S+) --intent ([0-9a-f]{6,32})(?:\s|$)")
 def adopt(rec, snap):
     ...
         role = "watcher" if "__recycle" in row.args else "actuator"
-        pr = T.ProcRole(role=role, pid=row.pid, lstart=row.lstart, argv_hash="adopted")
+        name, nonce = "adopted", ""
+        m = _WRAPPER_TOK.search(row.args) if role == "actuator" else None
+        if m and m.group(1) == rec.record_id:
+            nonce = m.group(2)  # the wrapper itself: its exit file is readable (A6 rule 3)
+            if rec.intent is not None and rec.intent.nonce == nonce and rec.intent.actuator:
+                name = rec.intent.actuator  # killed between Popen and the procs save (§4.5)
+        pr = T.ProcRole(role=role, pid=row.pid, lstart=row.lstart, argv_hash=name, nonce=nonce)
@@ def reap_children  (act.py:405-415, the waitpid loop)
-        EXIT_CODES[pid] = (
-            os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
-        )
+        if pid in _SPAWNED:  # any other child (the provenance Popen) is reaped, its code dropped:
+            EXIT_CODES[pid] = (  # a reused pid must never hand an actuator a stranger's code
+                os.WEXITSTATUS(_status) if os.WIFEXITED(_status) else -os.WTERMSIG(_status)
+            )
         n += 1
+
+def read_exit(paths: T.Paths, pr: T.ProcRole) -> Optional[int]:
+    """The wrapper's durable exit code, or None (no nonce, no file, unreadable, or switched off)."""
+    if not pr.nonce or os.path.exists(paths.p(EXITS_OFF)):
+        return None
+    try:
+        with open(os.path.join(paths.exits, pr.nonce + ".rc"), encoding="ascii") as fh:
+            raw = fh.read(16).strip()
+    except (OSError, ValueError):
+        return None
+    return int(raw) if re.fullmatch(r"-?[0-9]{1,3}", raw) else None
+
+def reap_exits(paths: T.Paths, now: float) -> int:
+    """Exit files older than ACTLOG_MAX_AGE_S go, at startup only. Never at consumption: a file must
+    outlive the record write that consumed it (A6 rule 7)."""
+    # same body as reap_actlogs over paths.exits
+
+def self_ident(snap: Optional[T.Snapshot] = None) -> Tuple[int, str]:
+    """(pid, lstart) of this daemon: the pass census's own row when it has one, else one ps (cached).
+    hold_claim uses it too (replaces the inline cache at act.py:510-515)."""
+
+def claim_holder_for(rec, snap, me) -> Optional[Tuple[int, str]]:
+    """A6 (c): who the run claim must name — a LIVE ancestor of every process driving the record.
+    hf_recycle_claim_foreign (handoff-fire.sh:2660) refuses a live holder that is not the caller or an
+    ancestor, and an actuator an earlier daemon started is no descendant of this one (e80b61f4 and
+    7aae55e1, 2026-10-20). None: unknown this pass, write nothing."""
+    live = [p for p in rec.procs if p.role == "actuator" and snap.alive(p.pid, p.lstart)]
+    live.sort(key=lambda p: p.argv_hash == "adopted")  # stable: the named wrapper first
+    if live and snap.procs[live[0].pid].ppid != me[0]:
+        return (live[0].pid, live[0].lstart)
+    return me if me[1] else None
+
+def keep_claim(paths, rec, snap, me) -> str:
+    """Re-stamp the record's OWN claim to claim_holder_for, on change only. Returns the event detail."""
+    if not rec.open or os.path.exists(paths.p(KEEPER_OFF)):
+        return ""
+    cur = store.read_claim(paths, rec.sid)
+    if cur is None or not rec.record_id or cur.record_id != rec.record_id:
+        return ""  # absent, or another record's/lane's: never ours to write
+    want = claim_holder_for(rec, snap, me)
+    if want is None or (cur.pid, cur.lstart) == want:
+        return ""
+    if not store.claim_restamp(paths, rec.sid, rec.record_id, want[0], want[1]):
+        return ""
+    return "run claim %d → %d (%s)" % (cur.pid, want[0],
+        "this daemon" if want[0] == me[0] else "the actuator an earlier daemon started")
```

`act.py` needs `import re` and `Set` in its imports. `settle_intent` stays as it is; it is dead code, tested only. Its removal is a separate cleanup.

### 3.3 `scripts/limit-recover/lr_recon/settle.py`

```diff
@@ def dead_actuators  (settle.py:561-565)
-def dead_actuators(procs, exits):
-    """Pair each dead actuator with its exit code (None: exited before this daemon, or adopted)."""
-    return [(p, exits.pop(p.pid, None)) for p in procs if p.role == "actuator"]
+def dead_actuators(procs, exits, durable=None):
+    """Pair each dead actuator with its exit code (A6 rule 4/6): the wrapper's exit file first (exact
+    by nonce, survives a restart and pid reuse), then this process's own reaped code; None = unknown.
+    A descendant adopted by argv never carries a code: the wrapper's exit is the verdict."""
+    out = []
+    for p in procs:
+        if p.role != "actuator":
+            continue
+        own = exits.pop(p.pid, None)  # always popped: never left for a reused pid
+        if p.argv_hash == "adopted":  # a descendant, or a wrapper with no known actuator name:
+            out.append((p, None))     # liveness only, never a verdict (rule 4)
+            continue
+        rc = durable(p) if durable is not None else None
+        out.append((p, own if rc is None else rc))
+    return out
```

When the file and the own code both exist they agree, because the wrapper exits with the code it wrote. The file wins only to stay exact under pid reuse.

### 3.4 `scripts/limit-recover/lr_recon/__main__.py`

```diff
@@ def _derive  (__main__.py:736-748)
+    me = act.self_ident(snap)
     for rec in ctx.records.values():
@@ (__main__.py:807-817)
-        for pr, rc in settle.dead_actuators(act.prune_dead(rec, snap), act.EXIT_CODES):
+        for pr, rc in settle.dead_actuators(
+            act.prune_dead(rec, snap), act.EXIT_CODES, lambda p: act.read_exit(ctx.paths, p)
+        ):
             ...
         if not rec.open:
             continue
+        kept = act.keep_claim(ctx.paths, rec, snap, me)  # A6 (c): after the exit settle, before dispatch
+        if kept:
+            _event(ctx.paths, "claim-restamp", rec.sid, rec.record_id, kept)
@@ def _dispatch  (__main__.py:1312-1318, after the wake_eta block)
             rec.close["wake_eta"] = rec.wait.eta
+        # A6 (d): the bookkeeping above is a decision, not replayable from any file; a pass killed
+        # before save_records lost it, and a later move spawn re-used the attempt (double typer).
+        store.save_record(ctx.paths, rec, now)
@@ def _startup  (__main__.py:1783-1803)
     ctx.records = store.load_all(paths, bad)
     me = store.proc_lstart(os.getpid())
+    prev = _prev_heartbeat(paths)            # (e): read before the new heartbeat replaces it
+    keeper = not os.path.exists(paths.p(act.KEEPER_OFF))
+    inherited = []
     for rec in ctx.records.values():
         claim = store.read_claim(paths, rec.sid)
-        if rec.open and claim is not None and claim.record_id == rec.record_id:
-            store.claim_restamp(paths, rec.sid, rec.record_id, os.getpid(), me)
+        if not (rec.open and claim is not None and claim.record_id == rec.record_id):
+            continue
+        acts = [p for p in rec.procs if p.role == "actuator" and p.argv_hash != "adopted"]
+        if keeper and acts:
+            # A6 (c): an actuator the last daemon started may still run, and only it (an ancestor of
+            # its handoff-fire) may hold the claim; the first trusted pass's keep_claim decides from
+            # its census. Until then a dead holder is not foreign, and the fence holds other lanes off.
+            inherited.append("%s:%s" % (rec.sid[:8], acts[-1].argv_hash))
+            _event(paths, "claim-inherited", rec.sid, rec.record_id, "pid %d left for the first pass" % claim.pid)
+            continue
+        store.claim_restamp(paths, rec.sid, rec.record_id, os.getpid(), me)
     now = time.time()
-    store.append_restart(paths, {"t": now, "pid": os.getpid(), "lstart": me})
+    act.reap_exits(paths, now)
+    store.append_restart(paths, dict({"t": now, "pid": os.getpid(), "lstart": me,
+                                      "inflight": len(inherited), "inherited": inherited[:16]},
+                                     **_restart_forensics(prev)))   # (e), optional
```

Two helpers, about 25 LOC together:
- `_prev_heartbeat(paths)` parses `recon/heartbeat`, whose fields are `pid`, `lstart` and `progress_wall`. Measured format: `cat recon/heartbeat`.
- `_restart_forensics(prev)` computes `prev_progress_age_s`, `code_mtime` and `code_newer_than_prev`. Each is wrapped in try/except and never raises.

The restart-loop page at `:1797-1803` keeps reading `t` and is unchanged.

Optional part (f), in `daemon()` (`__main__.py:1826-1849`), after `run_pass`:

```diff
+            req = os.path.join(paths.ctl, "restart.request")
+            if os.path.exists(req) and os.path.exists(paths.p("restart-request.on")):  # operator ruling
+                store._unlink(req)
+                store.append_restart(paths, {"t": time.time(), "pid": os.getpid(), "cause": "requested"})
+                return 0   # after this pass's save_records; launchd KeepAlive restarts within ~10 s
```

The restart-loop page must skip `cause=requested` rows.

### 3.5 Not changed

- `handoff-fire.sh` and `lr-lib.sh`: the R2 rule stays exactly as pinned.
- `lr-recon-fence.sh` and `fence.py`: the `owned/<sid>` procs entries gain a `"nonce":"<hex>"` key. The bash parser extracts `pid`, `lstart` and `role` by key name inside each `{…}` (`lr-recon-fence.sh:111-148`). A hex string value has no `{`, `}` or `"`, so it parses unchanged. `fence.py:65-81` builds ProcRole with explicit kwargs and ignores the key.
- The plists: no new environment. Both kill switches are files under `recon/`, the same pattern as `recon.on`, `mode` and `autorecover.on`, so they need no launchd reload.

---

## 4. Data and format changes

| Artifact | Change | Compatibility |
|---|---|---|
| `recon/sessions/<sid>.json` → `procs[]` | new key `nonce` (hex, may be `""`) | old daemon: ignored (`from_dict`); new daemon on an old record: `""` (legacy = unknown, today's path) |
| `recon/owned/<sid>` → `procs[]` | same key | bash and python fence parsers read by key (§3.5) |
| `recon/exits/<nonce>.rc` | **new**, one line, the decimal code | created by `ensure_dirs`; GC at 7 days on startup; at most 27 a day (measured) |
| `runs/by-sid/<sid>.active/holder` | `pid`/`lstart` may name an inherited wrapper instead of the daemon; `owner` stays `lr-reconciler`, `record_id` unchanged | no reader assumes the pid is the daemon (`grep read_claim` and `by-sid` readers: `act.py:507`, `__main__.py:1254`, `lr-fire-resume.sh:830-835` informational) |
| `recon/restarts.jsonl` | new keys `inflight`, `inherited`, `prev_*`, `code_*` (and `cause` for (f)) | the only reader is `_startup`'s loop page, which reads `t` |
| `recon/events.jsonl` | new events `claim-restamp`, `claim-inherited` | no reader keys on event names outside lr_recon (`grep`) |
| `recon/claim-keeper.off`, `recon/exit-files.off` | **new** kill-switch files | absent by default |

---

## 5. Failure modes under permanent 15-40/core load

No gate below reads load or waits for it to fall. Every unknown leads to a retry.

| # | Failure | Handling |
|---|---|---|
| F1 | The wrapper itself is SIGKILLed (no file) | rc `None` → "the phase decides" → actlog `NOTMOVED` rescue (`settle.py:236-266`) or the `IN_FLIGHT_MAX_S` bound (`__main__.py:876-896`). Today's behaviour, never worse |
| F2 | The exit file write fails (disk full, `exits/` missing) | `[ -d ]` guard; stderr discarded; same as F1 |
| F3 | Daemon killed after a settle, before `save_records` | the record on disk still lists the dead proc → the next daemon replays it from the file, once (§2.2 rule 7) |
| F4 | Daemon killed after the save | the proc is pruned on disk → no replay → exactly once |
| F5 | pid reuse (about 86 s wrap, `lr-lib.sh:771`) | liveness is (pid, lstart); the code comes by nonce; `EXIT_CODES` is limited to `_SPAWNED`; descendants never take a code |
| F6 | The pass's ps census is degraded or untrusted. At PRI 31 it still happens: `abstain … /bin/ps … timed out at 30s` at 11:06Z (measured, `events.jsonl` tail) | the pass abstains before `_derive` (W7a, `__main__.py:1679-1683`) → no keeper and no settle that pass → the claim stays as it was (a dead old-daemon pid or a live W, both safe, §2.3) → the next trusted pass decides |
| F7 | The wrapper exits; the claim names a dead W until the next pass (P up to minutes) | nothing in W's chain is left to check the claim; other lanes are fenced (rules 4-5); the keeper re-stamps to the daemon in that pass, before `_dispatch` |
| F8 | A second restart while the claim names W | the startup sees recorded procs → leaves the claim; the keeper confirms W while it lives |
| F9 | Our own `proc_lstart` times out (40 s bound, `store.py:525-549`) | the keeper writes nothing that pass (unknown → retry); never writes an lstart-less holder |
| F10 | Spawn's `lstart_of(pid)` times out → ProcRole `lstart ""` (an existing latent issue) | the next pass's argv scan finds the wrapper by `--intent` = `rec.intent.nonce` → re-adopted under its actuator name with its nonce → its exit is still scored. The stale `""` entry settles as unknown, a no-op |
| F11 | `claim_restamp` TOCTOU against a lane that stole a dead holder in between | not new (the startup re-stamp has it today). A reconciler-owned record is fenced, so the steal cannot happen while the heartbeat is fresh |
| F12 | Old-wrapper actuators in flight during the deploy restart | no file → today's loss, one last time; minimised by the boundary restart in §7 |
| F13 | Rollback to the old code with claims naming W | the old startup re-stamps to itself → today's defect returns, no worse |
| F14 | Canary or rig daemon | `actuator_env` sets `LR_RECON_ROOT=paths.root` (`act.py:75`) → each tree writes its own `exits/` |
| F15 | CPU cost at 31 | the wrapper adds one builtin `printf` per actuator exit; the keeper adds one small file read per open record per pass and a write only on change; startup adds about 25 `stat` calls. Estimated < 1 ms each, against passes measured in minutes |

---

## 6. Test plan

**New python module: `scripts/limit-recover/lr_recon/tests/test_restart_safety.py`.**
- Everything runs in `tempfile.mkdtemp`. The suite stays fast: the touched suites ran 124 tests in 1.9 s plus `test_main`'s 74 in 15.2 s (measured, `TMPDIR=/tmp/a6/tmp python3 -B -m unittest …`).
- Fixtures build records with `T.from_dict` from JSON that includes `nonce`. On today's tree the key is silently dropped, so each [RED] case fails **by assertion**, not with a `TypeError`.

| # | Test | Red before the fix? | What it pins |
|---|---|---|---|
| 1 | `test_an_inherited_actuator_is_scored_from_its_exit_file`: dead R pid 4242 from disk, `EXIT_CODES` empty, `exits/n1.rc = 6`, actlog `verdict: HELD:busy` with **no** `NOTMOVED` line → one pass | **RED**: today `R exited, code unknown` | event `R rc=6 → HOLD/HOLD-COMPOSER`, `attempt == 2` |
| 2 | `test_a_killed_pass_is_replayed_exactly_once`: pass 1 settles and is "killed" (record not saved) → reload → pass 2 → reload → pass 3 | **RED** (code unknown) | attempt bumped exactly once across passes 2-3; one HOLD |
| 3 | `test_a_saved_settle_is_not_replayed`: pass 1 settles and saves → pass 2 | CONTROL (green both) | no double bump. Its mutant: delete the `prune_dead` result before the save → it must fail |
| 4 | `test_the_wrapper_of_a_recorded_intent_is_adopted_under_its_actuator_name`: `rec.intent=(n1,"R")`, no procs; snapshot has the wrapper row and an lr-handoff descendant row | **RED**: today both are `adopted` | wrapper → `argv_hash "R", nonce "n1"`; descendant → `adopted, ""` |
| 5 | `test_a_descendant_never_takes_a_reaped_code`: `EXIT_CODES[pid]=6`, dead `adopted` descendant | **RED**: today `_score("adopted",6)` → `last_error.cls == "DETERMINISTIC"` | rc None, record untouched |
| 6 | `test_an_inherited_pid_never_takes_a_strangers_code`: `EXIT_CODES[4242]=0` from a non-spawned child, inherited R 4242, no file | **RED**: today `R rc=0` (would set IN-FLIGHT) | rc None |
| 7 | `test_reap_children_keeps_codes_only_for_spawned_pids` (real `Popen(['/usr/bin/true'])` not via spawn + `reap_children`) | **RED** | `EXIT_CODES` has no entry for it |
| 8 | `test_restart_with_a_live_inherited_actuator_hands_it_the_claim`: claim (old daemon pid, rid); record procs W; mocked census row W `ppid=1` → `M._startup` + `M.run_pass` | **RED**: today the claim names `os.getpid()` | claim `(pid, lstart) == W`; event `claim-restamp`; startup event `claim-inherited` |
| 9 | `test_the_claim_returns_to_the_daemon_when_the_wrapper_dies` (next pass, W absent from the census) | **RED** (no keeper) | claim = daemon, in the same pass as the exit settle and before `_dispatch` |
| 10 | `test_own_child_keeps_the_daemon_as_holder` (row W `ppid == os.getpid()`) | CONTROL (green both) | claim unchanged. **Mutant:** drop the `ppid` test in `claim_holder_for` → it must fail |
| 11 | `test_keeper_never_writes_another_records_or_an_absent_claim` | CONTROL | no write. **Mutant:** drop the `record_id` check → it must fail |
| 12 | `test_idle_record_is_restamped_at_startup_as_before` | CONTROL (green both) | today's behaviour for a record with no procs |
| 13 | `test_kill_switches`: `claim-keeper.off` → startup re-stamps to self, no keeper writes; `exit-files.off` → the reader returns None | — | rollback works without a reload |
| 14 | `test_spawn_bookkeeping_is_on_disk_before_the_pass_ends` (fake popen; `store.load_record` right after `_dispatch`) | **RED**: `move_attempt` absent on disk | `close.move_attempt == attempt` |
| 15 | `test_exit_files_older_than_7d_are_reaped_at_startup` | — | old file gone, fresh one kept |
| 16 | `test_restart_row_names_previous_daemon_and_inflight` (e) | — | keys present; `code_newer_than_prev` computed; never raises on a missing heartbeat |
| 17 | `test_real_wrapper_writes_the_childs_code`: real `/bin/bash` 3.2, children `exit 0`, `exit 6`, `kill -TERM $$` | **RED** (no file) | file == `Popen.poll()` == 0 / 6 / 143 |
| 18 | `test_a_real_orphaned_wrapper_is_scored_by_the_next_daemon`: a subprocess python runs `act.spawn` and `os._exit(0)`; the test process (the "new daemon") waits for the pid to vanish, then settles. The §1.3 reproduction, as a test | **RED**: `code unknown` | `R rc=6 → …`; wrapper `ppid` was 1 |

**New bats file: `tests/lr-recon-restart-claim.bats`.** It runs the real process chain and the real handoff-fire function (the §1.3 harness). It uses no kitty and no launchctl, and all state is in `$BATS_TEST_TMPDIR`.

| # | Case | Red before the fix? |
|---|---|---|
| 1 | **[RED] an actuator inherited across a restart passes handoff-fire's claim check**: daemon 1 spawns W and exits; daemon 2 (`python3 -c` running `M._startup` + one `run_pass` on `observe.read_ps`, then staying alive) → W's child runs the extracted `hf_recycle_claim_foreign` → `not-foreign` | RED: `foreign pid=<daemon2> by=lr-reconciler` |
| 2 | CONTROL: a live stranger holding the claim is still refused (R2 unchanged) | green both |
| 3 | Power: with `claim-keeper.off` the same chain reproduces the refusal | proves case 1 can fail |

**Rig (B1).** Add the fault `restart_daemon_after_spawn: N` to the W5 rig. The rig kills its **own** rig daemon (`$RIG/state/daemon.pid`) with SIGKILL N seconds after the k-th `spawn` event; the rig supervisor restarts it after 10 s (`tests/rig/lr-recon-rig.sh:210-216`). Run it at the §5 load levels in both band arms. Assert:
- zero own-actuator `code unknown` exits;
- zero `move claim (pid` lines in the rig's actlogs;
- the same terminal outcome per sid as a no-restart control run.

**After rollout, read-only checks.**
- Count, do not trust a quiet log. The "Fail-safe mimics healthy" rule applies: "the phase decides" looks like a calm restart.
- The rewritten `/tmp/a6/replay.py` counts own-actuator `code unknown` exits after the deploy. Expect 0 over at least 3 restarts with `inflight ≥ 1`.
- `grep -r 'move claim (pid' ~/.reso/limit-recover/recon/actlogs` must show no new hits.
- At each such restart, expect a `claim-inherited` startup event followed by `claim-restamp … earlier daemon started`.

---

## 7. Rollout and kill switches

1. **Land** in two commits, so each can be reverted alone:
   - (a)+(b)+(d), with tests 1-7 and 14-18;
   - (c), with tests 8-13 and the bats file.

   (e) rides with (c). (f) waits for its ruling.
2. **Deploy** through the normal live-layer convergence. The running daemon keeps the old code until it restarts.
3. **Operator step: restart the reconciler at a quiet boundary**, so that no old-wrapper actuator loses its code one last time:
   ```
   bash ~/.reso/limit-recover/design-v2/lr-restart-at-boundary.sh --confirm reconciler
   ```
   It waits up to 30 min for no `lr-recon-act` child, then runs `kickstart -k`, then verifies a new pid and a progressing heartbeat. If a standing cohort keeps it from finding a boundary in 30 min, a plain restart is acceptable: it costs exactly today's loss for the in-flight old-wrapper actuators.
4. **Verify (read-only):**
   - the new `restarts.jsonl` row carries `inflight`;
   - `ls ~/.reso/limit-recover/recon/exits` gains a file after the next actuator exits;
   - the §6 counts.
5. **Kill switches**, files and no reload:
   - `touch ~/.reso/limit-recover/recon/claim-keeper.off` restores the old startup re-stamp and stops the keeper;
   - `touch ~/.reso/limit-recover/recon/exit-files.off` makes the reader ignore the files;
   - the wrapper keeps writing them, which is harmless;
   - a full rollback is `git revert` of the two commits.

---

## 8. Estimated size

Estimated by summing the sketches in §3:

| Part | Code LOC | Test LOC |
|---|---|---|
| (a) wrapper, nonce, reader, `_SPAWNED`, GC | 45 | 120 (python 1, 5-7, 15, 17-18) |
| (b) nonce-aware `adopt`, `dead_actuators` | 20 | 40 (python 4-5) |
| (c) keeper, `self_ident`, startup | 45 | 170 (python 8-13, bats 1-3) |
| (d) spawn bookkeeping save | 3 | 30 (python 2-3, 14) |
| (e) restart forensics | 25 | 25 (python 16) |
| **Core total** | **~140** | **~385** |
| (f) optional restart request | 30 | 40 |
| A6 iii Admission persistence (recommended for B3 instead) | 50 | 40 |

---

## 9. Dependencies on other items

| Item | Relation |
|---|---|
| **None blocking.** | A6 needs no other item first. |
| B1-load-harness | **Consumes A6.** Its fault "a daemon restart mid-actuation" and its invariant G6 ("restart-neutral") assert what A6 builds. B1 should carry §6's rig fault. |
| B2-bounded-pass | **Coordinate.** B2's `waitpid`/SIGCHLD reaping must feed the same `dead_actuators(exits, durable)` path and keep `_SPAWNED`. Land A6 first so B2 inherits the exit-file fallback. B2's async probe and placement change nothing here. |
| B3-deadline-override | **Absorbs A6 iii** (Admission persistence). G6's "does not reset `t_detect`" is already true: `timeline.detected` is on disk. |
| B6-telemetry | (e) can move there. Either way the restart row is the restart telemetry. |
| B7-now-audit | No interaction. The keeper and the reader compare no time stamps. The exit-file GC is an `st_mtime` age, not a pass-`now` comparison. |
| G2-self-recovery | Independent. A self-recovering session would take its own claim; the keeper only touches claims whose `record_id` is the reconciler's. |
| B5-kitty-off-critical-path | Independent. B5 reorders steps after the claim check in handoff-fire, and the ancestor rule is untouched. |
| A7, D1, D2, B4, B8, C1, C2 | No interaction. |

---

## 10. Risks and open questions

- **The claim now sometimes names a non-daemon pid.** No reader assumes otherwise (`grep` of `read_claim` and `by-sid` readers, §4). `cc-lr status`-style output that prints the holder pid would show the wrapper's pid during that window, which is the true driver.
- **Every actuator now runs under a changed wrapper.** Tests 17-18 run the real `/bin/bash` 3.2 (the launchd interpreter, per the rule "Deployment interpreter ≠ yours"). The `--record-id`/`--intent` argv tokens and the `lr-recon-act` `$0` that `adopt`, `acting()` and `lr_claim_drivers` read are unchanged.
- **The window between a wrapper's exit and the next pass** leaves a claim naming a dead pid. It is fenced for reconciler-owned records (§1.5). It exists only for inherited actuators, never in a daemon's steady state.
- **The first deploy restart still loses old-wrapper codes.** Hence the boundary restart in §7.
- **Expected effect** (estimated from the incident):
  - the 2 post-transplant self-refusals (25.9 min, axis 02 §4.9) go;
  - the unknown-code class goes for every restart that does not SIGKILL a wrapper;
  - a killed pass loses at most its own latency.

  Avoiding the killed pass itself needs (f).
- **Open (hypothesis):** what restarted the daemon at 03:23, 03:53 and 04:31Z. (e) records enough to tell deploy restarts from crashes from now on.
- **Conviction: 85%.**
  - The mechanism is reproduced on the real code: the bash 3.2 wrapper and the real `hf_recycle_claim_foreign` (§1.3).
  - The residual 15% is integration: the keeper's interplay with paths not exercised at this scale (an UNCONFIRM or C inherited across two restarts), and the rig fault being unbuilt until B1.

---

## Appendix A. Commands run (all read-only, or writing only under `/tmp/a6/`)

| Command | Established |
|---|---|
| `sed -n`/`grep -n` over `lr_recon/{act,settle,store,types,__main__,admit,classify,observe}.py`, `handoff-fire.sh`, `lr-lib.sh`, `lr-recon-fence.sh`, `lr-reset-poller.sh`, `lr-band-reload.sh`, `tests/handoff-recycle-self-source.bats`, `tests/rig/lr-recon-rig.sh` | every file:line above |
| `tail -8 ~/.reso/limit-recover/recon/restarts.jsonl`; `date -u -r <t>` | restart times and pids |
| `python3 -I /tmp/a6/ev.py <lo> <hi> [evs]`, `python3 -I /tmp/a6/sid.py <lo> <hi> <sid8>` | §1.1 event rows |
| `python3 -I /tmp/a6/cross.py` | 7 spawn→exit pairs crossed a restart; 6 lost the code |
| `python3 -I /tmp/a6/replay.py` | 54 own exits: 45 code / 8 unknown / 1 rescued; 134 adopted-unknown |
| `grep -n -E 'move claim|verdict=' recon/actlogs/{e80b61f4.1,7aae55e1.2}.R.log` | the two refusals and their `NOTMOVED` |
| `bash /tmp/a6/wrap_probe.sh` | bash 3.2.57 wrapper stays the parent; new wrapper rc and file 6/6, 143/143 |
| `python3 -I -B /tmp/a6/repro/repro.py <wt> {today,fix} {old,new}` | §1.3 table |
| `TMPDIR=/tmp/a6/tmp HOME=/tmp/a6/tmp/home python3 -B -m unittest lr_recon.tests.test_{act,settle,rollback,store,wave_g}` and `…test_main` | baseline green: 124 tests in 1.9 s, 74 in 15.2 s; `git status --porcelain` empty afterwards |
| `cat ~/.reso/limit-recover/recon/heartbeat`; `grep -c 'killed\|KILLED' recon/watchdog.log` | heartbeat fields; 0 watchdog kills in the current log |
| `TZ=UTC git log --since=2026-10-20 -- scripts/limit-recover/lr_recon`; `git log 28b25a119..main -- <touched files>` | restarts follow commits; no drift since this tree |

---

## Review — efficacy-under-permanent-load

**Reviewer verdict: NEEDS-CHANGES.** Adjusted conviction **72%** (the design says 85%).

**The question.** Does A6 bound recovery time at 15-40 runnable per core, with every lane at PRI 31? Does any new wait, bound or gate assume that load falls?

**Method.** All checks were read-only. Probes wrote only under `/tmp/a6rev/`. *Measured* names its command. *Estimated* names its method. *Hypothesis* means not verified.

### R.1 What holds (verified)

- **File:line claims.** Each of these was checked against the tree and is correct:
  - `act.py:34`, `:308-352` (setsid `:323-330`), `:360-372`, `:375-383`, `:394-415`, `:507-515`;
  - `settle.py:205-209`, `:561-565`;
  - `__main__.py:748`, `:807-817`, `:1663`, `:1679-1684`, `:1728`, `:1783-1803` (the re-stamp is at `:1790-1794`);
  - `store.py:72-79`, `:427-437`, `:525-549`;
  - `types.py:184-191`, `:360-370`, `:404-410`;
  - `handoff-fire.sh:2610-2622`, `:2660-2680`, `:16302-16305`;
  - `lr-lib.sh:771`, `:810-819`;
  - `lr-recon-fence.sh:8-21`;
  - `tests/handoff-recycle-self-source.bats:171-207`.
- **(a) and (d) add no wait and read no load.**
  - After its child exits, the wrapper uses builtins only.
  - The reader does one `open()` per dead named actuator.
  - The file is read only after the census shows the wrapper gone. The wrapper writes the file before it exits, so the file is complete when read.
  - A killed child's code (124/137/143/-9/-15) is TRANSIENT (`classify.py:31`, `:124`). So a 137 or 143 read from a file leads to a retry, not a negative verdict.
- **Fence rule 4 holds at today's load.**
  - The live heartbeat reads `max_step_gap_s` 30.3 (`cat recon/heartbeat`), at load 126-207 on 10 cores (`sysctl -n vm.loadavg hw.ncpu`).
  - The freshness bound is 180 s (`lr-recon-fence.sh:199`).

### R.2 Findings

**F-A. In steady state the keeper can hand the claim to an adopted descendant (measured).**
- **The rule.** `claim_holder_for` sorts named actuators first. When no named wrapper is live, it falls through to an adopted one.
- **This happens without any restart.**
  - `python3 -I /tmp/a6rev/adopt_outlive2.py events.jsonl.1 events.jsonl` => 2 adopted exits on 4fe9935f at 10-13T06:48:31Z.
  - Both came 43 s after that record's `R rc=0`. That code was the daemon's own reaped code, so the R was not inherited.
  - Passes ran inside that gap (`in-flight relaunch gap` at 06:48:11Z).
- **The §3.2 sketch, run verbatim on that shape.** `python3 -I -B /tmp/a6rev/keeper_probe.py <wt>` => `steady state, W dead, adopted D alive -> (4300, …)`. The claim is re-stamped to a process that is not the daemon and is not an ancestor of anything that checks the claim.
- **Why it matters.**
  - It breaks §2.3's "naming the daemon keeps today's no-restart behaviour exactly".
  - It opens a dead-holder window when D exits.
- **One candidate for D.** `__succ-rails` carries `--record-id` (`handoff-fire.sh:4812`) and runs in the pane, outside W's chain. This is a hypothesis: the 10-13 actlog is past the 7-day GC.

**F-B. The startup filter misses the case rule 3 was written for.**
- The startup keeps a claim only when `acts`, the named actuator procs, is not empty.
- A daemon killed between `Popen` (`act.py:323`) and the procs save (`:334-337`) leaves `rec.intent` set and `rec.procs` empty.
- A record whose wrapper was adopted without a name has only `adopted` procs.
- Both are re-stamped to the **live** new daemon, which is the incident refusal. That lasts until the first trusted pass adopts the wrapper by nonce and the keeper hands the claim over.

**F-C. Under load the first keeper run comes minutes after a restart, not one tick later (measured).**
- **Where the keeper sits.** In `_derive`, after `observe`, `_facts` and `_census` (`__main__.py:1666-1702`).
- **One measured point, R1.**
  - The first pass after R1 began at 03:23:43Z. A spawn event carries the pass's `now` (`act.spawn`, `T.Event(t=now)`).
  - Its `_derive` reached 769b7294 at 03:28:30Z. `_event` stamps `time.time()` (`__main__.py:137`).
  - That is 287 s.
- **Across spawning passes since 10-17.** From pass start to the last event before dispatch: median 219 s, p90 736 s, max 1633 s (`python3 -I /tmp/a6rev/dispatch_lag.py events.jsonl 1792195200`).
- **On 10-20 between 04:25 and 05:20Z.** 233-301 s.
- **Caveat.** All of these predate the PRI 31 restart at 07:23Z. No pass has spawned since, so nothing can be re-measured.
- **Consequence.** The startup window and the F7 window both scale with this delay.

**F-D. The startup's dead holder relies on a check that reads a vanished pid as live.**
- **The bash check** (`lr-lib.sh:810-819`):
  1. `kill -0` succeeds;
  2. `lr_pid_lstart` (`:785-787`, no timeout) returns empty if the process exits in between;
  3. an empty lstart reads as `live`;
  4. the pid is not an ancestor, so handoff-fire refuses.
- **Why it can happen.** The pid space wraps about every 86 s (`lr-lib.sh:771`), and the startup window lasts minutes (F-C). So a dead old-daemon holder whose pid was reused can still be refused.
- **Size (estimated, hypothesis).** At most about 1% per check:
  - about 1.6% of the pid space is live at any moment (`ps -A -o pid= | wc -l` => 1561 of 99,999);
  - times the chance that the process now holding that pid exits during one `ps`.
- **REPORT §A6 already weighed this.** Its risk line chose option (ii), "re-stamp to the adopted live actuator", over "no re-stamp". At startup the design does "no re-stamp".

**F-E. About half of all restarts are watchdog kills under load; §1.2 miscounted them (measured).**
- **The miscount.** `grep -c 'killed\|KILLED'` cannot match the watchdog's line `KILL -TERM pid=…` (`lr-recon-watchdog.sh:313`).
- **The real counts.**
  - `grep -c 'KILL -TERM' recon/watchdog.log` => 28, spread 09-30 → 10-19 (2, 2, 3, 5, 5, 1, 4, 4, 2 per day).
  - `grep -c "restart after this watchdog's kill"` => 24 of the 48 `holder changed` lines.
  - R1-R3 on 10-20 are indeed not watchdog kills.
- **Consequence (i).** Restarts happen under load, not only on development days, and they come mid-pass. That raises A6's value. It also means (f) does not help them.
- **Consequence (ii): a short unfenced window.**
  - The watchdog kills only after progress has been frozen for at least 900 s or 3600 s (`lr-recon-watchdog.sh:84-85`). So fence rule 4 has already lapsed when the holder dies.
  - Today, `_startup`'s re-stamp closes that dead-holder span.
  - The design keeps in-flight claims on the dead daemon past that point, until `hb.write_now()` (`__main__.py:1822`).
  - That write comes after `_startup` and after a second `proc_lstart`, which can take up to 40 s (`store.py:525-549`).
  - In that span only rule 5 guards a record whose recorded actuators are dead, and `owned.procs` is written only at spawn (`act.py:340`).

**F-F. "Every unknown leads to a retry" (§5) is false for one shape.**
- **The shape.** A move actuator exits with rc `None`, its log does not end `NOTMOVED`, and the record is derived PRE-MOVE/None. Nothing scores it:
  - `settle_exit` returns "the phase decides" (`settle.py:205-209`);
  - `rolled_back` needs `NOTMOVED` (`settle.py:236-272`);
  - `IN_FLIGHT_MAX_S` applies only to `IN-FLIGHT` (`__main__.py:876-896`);
  - `_invariant` pages `RECON-DEFECT` every pass (`__main__.py:1569-1610`);
  - B3 deliberately does not re-drive it (`B3-deadline-override.md` §5.8).
- **Effect.** This is db755a94's 52.5-min shape. A6 makes it rare: it remains only for exits that left no file. A6 does not bound it.

**F-G. F10 is not a no-op under load (hypothesis; the path exists only because of load).**
- **The trigger.** `spawn`'s `lstart_of` times out (40 s, `store.py:525-549`). Abstain events show ps timeouts at 30-40 s, so this can happen.
- **The sequence.**
  1. The census shows the `""`-lstart entry as dead while W is alive.
  2. `adopt` adds W by its nonce, under its actuator name.
  3. `prune_dead` hands the `""` entry to `dead_actuators`, which reads `exits/<nonce>.rc`.
  4. W can exit between the census and `_derive`, which are minutes apart (F-C). The file then exists, and the exit is scored.
  5. Next pass the adopted W, which carries the same nonce, is dead and is scored again: two attempt bumps or two HOLDs.
- **A second route.** A log that already ends `NOTMOVED` is scored by `_rolled_back_by_its_log` while W is still running.
- **Today's disk.** No record has an lstart-less proc (0 of 1 procs across 138 records).

**F-H. The B2 dependency is stated wrongly.**
- **What B2 does.**
  - It deletes the `waitpid(-1)` loop and rejects a SIGCHLD reaper (`B2-bounded-pass.md` §3 F2, `:188-201`, `:926`).
  - A6's `_SPAWNED` gate edits the loop B2 deletes.
- **The hole A6 claims to close is still open in its own sketch.**
  - `dead_actuators` pops `EXIT_CODES[pid]` for every named actuator and uses it when there is no file.
  - `_SPAWNED` is never pruned, so a reused pid that A6 once spawned still supplies a code.
  - After a `waitpid(-1)` theft, `Popen.poll()` reads 0 (B2 T4, measured there).

**F-I. No test exercises the order of events under load.**
- bats 1 and py8 run `_startup` and `run_pass`, then the check.
- Under load, the inherited chain's check is most likely to land inside the startup window (F-C). No case covers that order.
- The rig fault is deferred to B1, and this round has no B1 design (`ls impl/` shows no B1 file).

**F-J. The rollout waits for quiet.**
- §7 step 3's script waits up to 1800 s for "no `lr-recon-act` child of the holder" (`~/.reso/limit-recover/design-v2/lr-restart-at-boundary.sh:30-36`).
- It does not gate recovery, because the old daemon keeps working.
- It waits for a lull that §2.7 itself says may never come.
- `pgrep -P` misses wrappers inherited from an earlier restart (their ppid is 1). So "quiet" does not mean "no old-wrapper actuator is in flight".

### R.3 Required changes

1. **Keeper (F-A).**
   - `claim_holder_for` considers only named wrappers: `argv_hash != "adopted"`. A wrapper adopted by its nonce counts as named (rule 3).
   - With no live named wrapper, the holder is the daemon.
   - Add a CONTROL test on the 4fe9935f shape: no restart, W dead, an adopted D alive whose ppid is not the daemon → the claim is unchanged. Mutant: allow adopted → the test must fail.
2. **Startup predicate (F-B).**
   - A record counts as inherited when `rec.intent is not None`, or it has any actuator-role proc, named or adopted.
   - Test: an intent-only record across a restart is not re-stamped to the new daemon.
3. **Startup stamp (F-D).**
   - At startup, stamp the record's last named actuator's recorded `(pid, lstart)` when that lstart is not empty. This needs no ps. If the actuator is dead, it is no worse a holder than the dead old daemon. With an empty lstart, leave the claim as it is.
   - This is REPORT §A6 option (ii) from the first moment. It removes the dead-holder and pid-reuse exposure for every live inherited wrapper, however long the first pass takes.
4. **Keeper placement (F-C).**
   - Run `adopt` + `keep_claim` for every open record in a cheap loop right after the W7a gate (`__main__.py:1684`), before `_facts` and `_census`.
   - Do not put it in `_derive` after the early `continue`s at `:746-791`.
   - Keep `_derive`'s own `adopt`, which is idempotent.
5. **Heartbeat order (F-E ii).**
   - In `daemon()`: first read the previous heartbeat for (e).
   - Then write the new heartbeat before `_startup`'s claim loop.
   - Use one `proc_lstart` for both. That takes a ps of up to 40 s off the restart path.
6. **Duplicate nonce (F-G).**
   - `dead_actuators` never settles a dead entry whose nonce is also carried by a live entry of the same record.
   - Test the F10 shape, with W exiting between the census and `_derive`: it is scored exactly once.
7. **Own exit codes (F-H).**
   - Key them by nonce: `_CHILDREN[pid] = (proc, nonce)`, filling a by-nonce map. `dead_actuators` then never reads a pid-keyed code.
   - Restate the B2 dependency as "B2's registered reaping feeds the by-nonce map".
   - Drop the edit to the `waitpid` loop if B2 lands first.
8. **§5 and F1/F12 wording (F-F).**
   - State plainly that a move exit with no file, on PRE-MOVE/None with no `NOTMOVED`, stays a RECON-DEFECT page with no bounded retry.
   - Name the owner: a D-series ruling, since B3 refuses a forced re-drive.
   - Add a count of such cases to the post-rollout checks, expected 0.
9. **§1.2 evidence (F-E i).**
   - Replace the grep with the two counts above.
   - Say that A6 is mainly a fix for restarts under load, and that (f) does not cover watchdog kills.
10. **Ordering tests under load (F-I).** Neither needs a CPU hog, and both stay under the test tmpdir.
    - **bats 1b.** The inherited chain checks after `_startup` and before the first `run_pass`. It must read not-foreign in two cases: a dead holder pid, and a reused pid whose process exits between `kill -0` and `ps`.
    - **py8b.** The first pass runs with a ps shim delayed 35 s, which is inside `PS_BOUND_MAX_S`. It must still re-stamp before `_dispatch`.
11. **Rollout (F-J).** Choose one:
    - restart without waiting for a boundary; or
    - make the boundary check count every `lr-recon-act` process whose `--record-id` belongs to an open record, not only the holder's children.

    Either way, the (e) row records the one-time loss.

### R.4 Effect on the bound

**With changes 1-7.**
- A6 is restart-neutral at any load for every wrapper that writes its exit file.
- It adds no wait and reads no load.
- The keeper's delay becomes the census time, not the time from pass start to `_derive` (287 s, measured once).

**Without each change.**
- **Without 4:** the keeper inherits a pass length that is unbounded until B2.
- **Without 1:** a record in a daemon that never restarted can carry a holder that is not the daemon.
- **Without 2-3:** the incident refusal survives in the gap between `Popen` and the procs save, and through pid reuse.

**What stays unbounded.** The F-F shape stays unbounded by design (B3 §5.8). That is acceptable only if A6 says so instead of claiming every unknown is retried.

---

## Review — correctness-and-safety

**Reviewer verdict: NEEDS-CHANGES.** Adjusted conviction **68%** (the design says 85%).

**The question.** Could A6:
- strand a record;
- double-move or double-score;
- type over a draft;
- leave two drivers on one session;
- break an invariant or an existing test?

**Method.** All checks were read-only. Probes wrote only under `/tmp/a6rev/`. *Measured* names its command, and *hypothesis* means not verified. Where a finding repeats one from the efficacy review above, it is cross-referenced (F-x) and not restated.

### S.1 What holds (verified)

- **The incident mechanism is right, and handoff-fire needs no edit.**
  - `hf_recycle_claim_foreign` refuses only a live holder that is not an ancestor (`handoff-fire.sh:2660-2680`).
  - Its three R2 cases are pinned (`tests/handoff-recycle-self-source.bats:171-207`).
- **The counts match §1.2.** `python3 -I -c …` over the exit events in `events.jsonl{,.1}` (measured):
  - named actuators: 45 with a code, 8 `code unknown`, 1 `rc=None`;
  - adopted: 134 `code unknown`.
- **The wrapper works under `/bin/bash` 3.2.57 with the §3.2 string verbatim** (`python3 -I /tmp/a6rev/bin/wrap_probe.py /tmp/a6rev/root`, measured):
  - hex nonce: `poll()` reads 6 and the file holds `"6\n"`; the `ps -axww` row is one line, and `_WRAPPER_TOK` matches it;
  - child killed by TERM: 143 from both `poll()` and the file;
  - wrapper itself killed by TERM: `poll()` reads -15 and there is no file, so F1 holds.
- **The actlog text does not change.** On a signalled child, the old and new wrappers print the same stderr line (`python3 -I /tmp/a6rev/bin/old_wrap.py`). So the text `classify` reads is unchanged.
- **Formats.**
  - The fence's awk parser reads `pid`, `lstart` and `role` by key (`lr-recon-fence.sh:111-148`).
  - `fence.py:65-81` builds the ProcRole with explicit kwargs.
  - So both parse a `"nonce"` key.
  - `from_dict` ignores unknown keys (`types.py:189-195`).
  - `KeepAlive` is true (`com.reso.lr-reconciler.plist:45`), so (f)'s `exit 0` is restarted.
- **Nothing else overwrites what the keeper writes.**
  - `_own_and_charge` cannot undo it: `claim_take` returns `ours` on a record_id match and does not re-stamp (`store.py:392`).
  - `_release_terminal` releases by record_id (`__main__.py:1545-1558`, `store.py:419-424`), so a claim naming W is still released when the record ends.
- **Baseline (measured).** `env -u LR_RECON_ROOT -u LR_STATE_DIR TMPDIR=/tmp/a6rev/tmp HOME=/tmp/a6rev/home python3 -B -m unittest lr_recon.tests.test_{act,settle,store,fence}` => `Ran 111 tests in 4.066s OK`. `git status --porcelain` shows only `impl/`.

### S.2 Findings

**S-1. A live inherited wrapper is unprotected at startup from some claim takers (blocking).**
- **The design's assumption.** §1.5 and §2.3 rely on fence rules 4-5.
- **The fence order.** The fence decides in order, and two rules come first (`lr-recon-fence.sh:171-186`):
  - `recon.on` absent → act;
  - `owned/<sid>` absent → act.
- **Some reconciler records have no fence.**
  - Only `take_ownership` writes `owned/<sid>`, and only for PLANNED records (`__main__.py:1058-1085`).
  - A C or C-retry gets a claim from `hold_claim` but no fence (`act.py:493-523`).
  - `spawn` updates the fence's procs only when a fence exists (`act.py:338-341`).
- **Some takers skip the fence.**
  - `lr-unstrand.sh:130` calls `lr_claim_take` without consulting the fence. It then types `/exit` and a resume into the pane (`lr-unstrand.sh:1-25`). The reconciler pages that command to the operator.
  - `lr-move-batch.sh:247` also takes the claim with no fence call in the file.
- **Today vs A6.**
  - Today the startup re-stamp names the **live** new daemon, so every such taker reads `held-live`.
  - With A6 the claim names the dead old daemon until the first trusted pass, which comes minutes later (F-C, F-E ii).
  - A live inherited W and a taker that steals the claim would then both drive the session (split brain).
- **A second form: an old-daemon claim with an empty `lstart`.**
  - `_startup` and `_own_and_charge` write such a claim when `proc_lstart` times out (`__main__.py:1790`, `:1060-1062`, `store.py:546-549`).
  - Bash then judges it by pid alone (`lr-lib.sh:815`).
  - After a pid reuse (about 86 s, `lr-lib.sh:771`) it reads `live`, and handoff-fire refuses. That is the incident, inside the window meant to prevent it.
- **Relation to F-D/F-E.** This adds to them a taker class they do not name.

**S-2. `--once` would run the keeper against the live root (blocking).**
- `main()` runs `run_pass` for `--once` without the daemon's flock, against the live root by default (`__main__.py:1893-1897`). The census docstring presents `--mode observe --once` as a proof command (`observe.py:674`).
- `_derive` runs in every mode, so the keeper would run in that process, with `me` = the `--once` pid.
- **Record with no live actuator.** The keeper re-stamps the claim to a process that exits seconds later. That is a dead holder, exposed as in S-1.
- **Record with the daemon's own live W.** In the `--once` process, W's `ppid` is not `me`, so the keeper hands the claim to W. The daemon hands it back on its next pass.

**S-3. One spawn and one exit are scored twice (blocking; measured on a model of the design).**
- **The probe.** `python3 -I -B /tmp/a6rev/bin/design_model.py <wt>/scripts/limit-recover` runs the §3.2 `adopt` and §3.3 `dead_actuators` sketches verbatim through the real `act.prune_dead` and `settle.settle_exit`.
- **The shape is F10.** Spawn's `lstart_of` timed out, and W exits between the census and `_derive`.
- **Output:**
  - `after adopt: procs = [('R', '""', '0123456789ab'), ('R', 'Tue Oct 20 03:08:24 2026', '0123456789ab')]`;
  - `pass 1 settle: R rc=6 → HOLD/HOLD-COMPOSER`;
  - `pass 2 settle: R rc=6 → HOLD/HOLD-COMPOSER`;
  - `attempt after two passes: 3 (one spawn, one exit)`.
- **The fix.** The root cause is F-G's. The fix must reach that root, not only the reader: `adopt` must never append a second entry for a nonce the record already carries.

**S-4. §3.3 drops §2.1's reader-side identity rule, and test 6 contradicts the diff (blocking).**
- **The rule and the diff disagree.**
  - §2.1: `EXIT_CODES` speaks only for pids this process spawned.
  - §3.3: `dead_actuators` pops `exits[p.pid]` for every named actuator and uses it whenever there is no file.
- **Measured (same script).** `test-6 model: rc = 0 (the design's table expects None)`.
- **The filter sits in the wrong place.**
  - It sits only in `reap_children`'s `waitpid(-1)` loop, which B2 deletes (F-H).
  - `_SPAWNED` is never pruned.
- **A stale code also survives.** After a `waitpid(-1)` theft, `poll()` reads 0 (B2 T4). `reap_children` then writes that 0 into `EXIT_CODES` (`act.py:398-404`), where a later reused pid can read it.

**S-5. A dead actuator can be scored late, against a newer spawn (blocking).**
- **Dead procs can outlive a pass.** Some `_derive` paths `continue` before the settle and leave dead procs on `rec.procs`:
  - `cohort-exit-resume` keeps the record open (`__main__.py:770-777`; `settle.py:1110` returns before setting a terminal);
  - PARKED-REBOOT (`__main__.py:779-780`).
- **A new spawn can follow.** `may_actuate` counts only live procs (`act.py:464`). So `_dispatch` can start a new actuator under a new intent while the old W is still listed.
- **Then the old W is scored against the new one.** A later pass prunes the old W and settles it against the **current** attempt's actlog and phase (`__main__.py:807-809`; `settle.actlog` uses `rec.attempt`, `settle.py:97-100`).
- **Today vs A6.**
  - Today that exit reads `code unknown`, which changes nothing.
  - With exit files it becomes a real `_score`: an attempt bump, a HOLD or BACKOFF, possibly a terminal state, all charged to the wrong spawn.
- **The keeper is skipped on the same paths**, so a dead holder there is never repaired. F-C change 4 fixes the placement but not the late score.

**S-6. `keep_claim` can crash the pass (blocking).**
- `claim_restamp` reads the holder, then writes `d/holder` through `mkstemp(dir=d)` (`store.py:427-437`, `:60-69`).
- A steal renames `d` away (`store.py:286-305`; bash `lr-lib.sh:866`).
- So if the write races a steal, `FileNotFoundError` propagates out of `_derive`, and nothing catches it.
- Today this exposure exists once per startup. The keeper makes it once per pass per record.

**S-7. The `claim-keeper.off` kill switch leaves claims naming a dead W (blocking for the switch).**
- With the switch on, `keep_claim` returns at once (§3.2). A claim already handed to a W keeps naming W after W dies.
- The daemon keeps dispatching through `hold_claim`, which returns `ours` (`act.py:508`). So it drives the session under a claim that names a dead pid, and any S-1 taker can steal it.
- The switch must mean "the holder is always the daemon", not "write nothing".

**S-8. `move_attempt` can still be lost (should fix).**
- **The windows.** The (d) save lands only after `act.spawn` returns. That leaves two windows:
  - the short gap after spawn's second save;
  - up to 40 s inside `lstart_of`, before that save (`act.py:331-337`, `store.py:525-549`).
- **The loss.** A daemon killed there leaves the intent and the bumped attempt on disk, but not `move_attempt`. The next move then reuses the attempt, which is the double typer of `__main__.py:1291-1297`.
- **The fix.** Set `rec.close["move_attempt"]` **before** `act.spawn`:
  - spawn's intent save then carries it at no extra cost;
  - if `Popen` raises, the only cost is a skipped attempt number, which is harmless.
- **`wake_eta` must stay after spawn**, as its own comment says (`__main__.py:1315-1317`). So the (d) save is still needed for it.

**S-9. If the daemon is killed between `Popen` and the procs save, the exit is still lost when W ends first (should fix).**
- **The state.** Disk holds `intent=(N, actuator)` and no proc. W exits before the new daemon's first census, so `adopt` finds nothing.
- **The loss.** `prune_dead` then clears the intent (`act.py:386-391`), and `exits/N.rc` is never read.
- **The overclaim.** §10 says the unknown-code class "goes for every restart that does not SIGKILL a wrapper". This case contradicts it.
- **The fix.** Before `prune_dead`, check two things: the intent names an actuator, and no proc or argv row carries N. If both hold and `exits/N.rc` exists, settle it once under `intent.actuator`.

**S-10. The test plan has holes (blocking for the plan).**
- **Non-hex fixture nonces.** The fixtures use nonce `n1`, which is not hex.
  - So the wrapper writes no file for it, and `_WRAPPER_TOK` cannot match it (measured: `nonce=n1 … file=None … tok=None`).
  - Test 4 therefore cannot pass against the design's own code.
  - Use 12-hex nonces throughout.
- **An equivalent mutant.** Test 11's mutant changes nothing:
  - `claim_restamp` re-checks `record_id` (`store.py:430-432`);
  - so dropping `keep_claim`'s own check leaves the behaviour identical.
  - Name a mutant the test can kill.
- **bats case 1 runs a real `run_pass`.** Its effects reach outside the sandbox:
  - `observe.observe` globs `/tmp/kitty-*` and runs `kitten @ ls` against the operator's kitty (`observe.py:204`, `:499`);
  - `_draft_snapshots` reads panes;
  - pages go to `lr-page.sh` unless `LR_PAGE_BIN` is set (`report.py:576-579`).

  The case must:
  - patch `observe.observe` with a census of its own process tree, as `test_main.py:141` does;
  - run in observe mode;
  - set `LR_PAGE_BIN` to a stub;
  - sandbox `HOME`, `LR_STATE_DIR` and `LR_RECON_ROOT`.
- **Inherited `LR_RECON_ROOT`.** `test_act.py:276-292` passes `dict(os.environ)` to `spawn`. Under the new wrapper, an inherited `LR_RECON_ROOT` makes the exit file land in that root's `exits/`. Tests should strip it.
- **An existing test the S-4 fix would break.** `test_settle.py:275-281` pairs a code with pid 4242, which was never spawned. Make the identity check an optional parameter, e.g. `spawned=None` meaning legacy behaviour, so the test keeps passing.

**S-11. Notes (non-blocking).**
- **Exactly-once covers record state only.**
  - `_release_terminal` releases the fence and the claim before `save_records` (`__main__.py:1725`, `:1728`).
  - So a killed pass can leave an open record with neither.
  - This predates A6, but rule 7's wording claims more than that.
- **Stale phase (hypothesis: mostly benign, because `_score` keys on the actuator's own log verdict).**
  - An inherited exit read after a long outage is scored against the phase the old daemon last saved.
  - The MOVED/ENGAGED guard (`settle.py:210-215`) reads that cached phase.
  - Add a test: an old exit file, plus a derive that proves MOVED, leaves the record open and not escalated.
- **(f) and the restart-loop page.** The page counts the last 3 rows (`__main__.py:1797-1803`).
  - Skipping `cause=requested` rows still counts the startup row that follows each request.
  - So two deploys within 10 min still page.
  - Also exempt a startup row whose previous row is a request.
- **Hygiene.**
  - `read_exit` should check the nonce is hex before it builds the path, because the nonce comes from a record file.
  - `_WRAPPER_TOK` should be anchored to `args` that begin `/bin/bash -c `. Then a `grep` or `pgrep` row quoting the token is never adopted under an actuator name.

### S.3 Required changes

1. **Startup holder (S-1; endorses F-D change 3).**
   - Stamp the record's last named actuator's recorded `(pid, lstart)` whenever that lstart is not empty. A dead W is still a dead holder, but then no actuator is left in flight.
   - If that lstart is empty, or the record has no named actuator, re-stamp the live new daemon as today.
   - Never leave an old-daemon claim with an empty lstart in place.
   - Test: an unfenced C record, plus a taker that skips the fence, while an inherited W is live → `held-live`.
2. **Keeper only in the daemon (S-2).**
   - Gate `keep_claim` on a flag that `daemon()` sets after `flock`.
   - `--once` and the existing tests stay keeper-free unless a test opts in.
3. **Nonce dedupe (S-3).**
   - In `adopt`, a wrapper row whose nonce a recorded proc already carries repairs that proc's `(pid, lstart)` in place, instead of appending a new entry.
   - In `dead_actuators`, a dead entry whose nonce is also carried by a live entry gets `None`.
   - Test: the S-3 model as a RED case.
4. **Own codes by nonce (S-4, F-H).**
   - Keep `_SPAWNED: Dict[pid, nonce]`, popped when a code is consumed.
   - `dead_actuators` accepts `EXIT_CODES[pid]` only when `p.nonce` is set and `_SPAWNED.get(p.pid) == p.nonce`.
   - Fix test 6 to match.
   - Leave the `waitpid(-1)` loop to B2.
5. **Stale-spawn guard (S-5).**
   - Read `want = rec.intent.nonce` before `prune_dead`.
   - A dead proc whose nonce is not `want` settles with `None`, and its event says it is stale.
   - Run `adopt` + `keep_claim` before every early `continue` (with F-C change 4).
6. **`keep_claim` never raises (S-6).**
   - Catch `OSError` → write nothing this pass (unknown, retry).
   - Re-read after the write; on a mismatch, log `claim-restamp lost-race`.
7. **Kill switch (S-7).** `claim-keeper.off` ⇒ `claim_holder_for` returns `me`. The restore-to-daemon still runs, and the hand-off to W does not.
8. **`move_attempt` before spawn (S-8).** Keep the (d) save for `wake_eta`.
9. **Intent-only exit (S-9).** Settle from `exits/<intent.nonce>.rc` when nothing carries that nonce, or strike the §10 overclaim.
10. **Test plan (S-10).**
    - Use hex nonces.
    - Give test 11 a killable mutant.
    - Stub `observe.observe` and the pager in bats case 1, and sandbox its roots.
    - Strip `LR_RECON_ROOT` in `test_act`'s spawn tests.
    - Keep `test_settle.py:275-281` valid through an optional identity parameter.
11. **Rollout (F-J).** Count every `lr-recon-act` process with any ppid, not only `pgrep -P <daemon>`. Or drop the claim that the boundary restart prevents the last loss.
