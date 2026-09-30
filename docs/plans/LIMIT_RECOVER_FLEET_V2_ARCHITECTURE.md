---
status: complete
---

# Pane-in-place parallel limit recovery: architecture, revision 2

*Status (2026-09-30): this is the DESIGN, and the design is complete: revision 2, skeptic-passed, corrected to the as-built W6 code (`a14dd4362`). It carries no work of its own; its sections describe components, not phases. The remaining BUILD work (W5b canaries, shadow and cutover; W6f; the operator's `autorecover.on` steps) lives in `docs/plans/LIMIT_RECOVER_FLEET_V2.md`, which stays `in-progress`, and in its backlog rows. `complete` here does NOT mean the reconciler is live. It was marked complete because an `in-progress` design doc kept minting a duplicate "advance" backlog row (6117aef7168f) beside the implementation plan's own. Keep correcting it to the as-built code as the waves land.*

*Lines marked "as built" or "corrected 2026-09-30" were re-read on origin/main at `27a007c40` or later (FLEET_V2 W6e); every other anchor is from the original revision.* *Line numbers refer to `/Users/chrisren/Development/claude-infrastructure` near trunk tip `097255b53`. "(verified)" means the line was re-read this session. `handoff-fire.sh` moves often, so re-grep every anchor before editing it.*

## 0. Summary

**What revision 2 changes.** The skeptic pass found 7 fatal and 30 major defects in revision 1. The overall shape still holds:
- one launchd reconciler;
- per-session state derived from evidence;
- one placement decision for the whole cohort;
- the existing in-place chain as the actuator.

Eight mechanisms were missing or wrong, and revision 2 adds or replaces each one:

1. **Background work.** In revision 1 the watcher answered the background-work dialog with "Move to background and exit". That leaves a second live copy of the conversation on the source account. Revision 2 holds any session with background work before transplanting it. If the dialog still appears, the daemon answers it with Esc and undoes the confirm. Background-session rows now count as holders of the session.
2. **Transcript custody.** A second `lr-transplant --phase confirm` can overwrite the retired transcript with a stub. Revision 2 adds a stub refusal, renames by link-then-unlink, adds `unconfirm` and `fold-stub` phases, and uses a husk path that never re-runs confirm.
3. **One typer per session.** Revision 2 adds a per-session launch lock, a per-pane recycle lock, and an attempt nonce on every watcher row. A live watcher now counts as the record's live actuator (the new EXITING phase). No two processes can type a relaunch for the same session.
4. **The last read comes after confirm.** The composer, at-rest, subagent, background-work and still-limited checks now run after confirm, immediately before `/exit`. `/exit` is typed without Enter and read back before the Enter is sent. A refusal at this point runs `unconfirm`, so no husk is left behind.
5. **ENGAGED means our prompt was answered.** It is proved by three facts: the submit token's user record sits past the confirm-copy byte offset, a later non-error turn follows it, and the source process is dead.
6. **Placement respects real capacity:**
   - never the resident cap;
   - limit and auth facts are overlaid on the router snapshot;
   - each mover is weighted, subagents included;
   - survival floors are re-checked per pick with the cohort's added burn;
   - phantoms live until they are voided;
   - the source account becomes a candidate again once it resets.
7. **Admission can say no.** It uses a restore budget frozen when the cohort opens, a CPU brake set at the pre-limit load, and a per-account first-turn pacer that also absorbs 529s.
8. **The daemon fails safe in both directions:**
   - fences hold while any recorded process of the session is alive, and lapse only when the daemon is dead and nothing of the session is running;
   - the watchdog is a standalone script;
   - the clock accounts for sleep;
   - every lock carries a holder.

**The operator's three steps as one control loop:**

| Step | What does it |
|---|---|
| (a) Identify limited accounts | A fact ledger keyed on (account, scope). The scope is `5h`, `7d`, `model:<name>`, `fable`, or `auth`. The StopFailure hook fills it from the server's own `quotaLimits.status=rejected` in the same second as the death, and the wire probe corroborates. The endpoint integer and usage-endpoint 429s are never used. `cc-lr accounts --limited` renders it on top of cc-limited's existing grouping. |
| (b) Every pane on those accounts | A census, about 1 s using slug-direct transcript lookup, that joins four inputs: one `ps` table, `kitty @ ls` over every kitty instance, the registry, and background-session rows from `<cfg>/sessions/*.json`. The limit predicate runs in-process. Each session lands in exactly one bucket: LIMITED, IDLE-ELIGIBLE, WORKING, a named HOLD, TEAMMATE, HELD:team, launcher-rooted, iTerm2, or impossible. |
| (c) Recycle each in place onto the right account, concurrently | One `claude-accounts --place` per lane for the whole cohort. Then parallel setsid actuators run the proven chain: `lr-handoff --in-place`, `lr-transplant`, the `handoff-fire --recycle` watcher, then `lr-fire-resume`. Three things bound it: a boot semaphore, a per-account first-turn pacer, and a frozen restore budget. |

**Where it runs.** Everything runs in a launchd KeepAlive daemon, `com.reso.lr-reconciler`, which sits outside every session and outside the auto-mode classifier. A standalone watchdog job backs it up.

The evidence that launchd can type into panes is narrower than revision 1 claimed. The `results/upgrade-*.json` rows are serial, same-account binary upgrades: 6 of 9 poller-auto runs were confirmed, and 2 were stranded at a bare shell. Pane 906 was a no-prompt relaunch that never held a process, and pane 405 was rescued by lr-upgrade's retype, not by handoff-fire. Cross-account transplanted recycles, and anything concurrent at N≥4, stay gated behind the W5 rig and canaries.

**No fire-and-forget.** Every session in scope gets a durable record, and its phase is re-derived from evidence on every pass. It ends in exactly one of these ways:
- **CLOSED**, meaning ENGAGED (limited) or MOVED (idle), after a 5-minute sentinel window;
- NOT_NEEDED with evidence;
- REPLACED;
- IMPOSSIBLE with a reason;
- held as a named WAIT/HOLD, with a maximum age that pages when it runs out.

ESCALATED keeps ownership and re-arms on a timer and whenever an input changes.

**Operator surface.** Per cohort, where a cohort is (account, scope, resets_at):
- one OPEN page;
- coalesced DELTA pages, at most one per 5 minutes;
- one CLOSE page;
- immediate pages for SPLIT-BRAIN, ESCALATED, IMPOSSIBLE and HELD:team;
- one counted readout line.

There is no per-pane mail.

**Numbers (honest):**
- **30 panes with free seats:** about 3-4 minutes from the measured stage times at boot concurrency 6. The published target is ≤5 minutes p95, and the W5 30-session rig's measured figure replaces it. Today's manual path took 115 s for 4 panes, and the poller path takes tens of minutes when its gate is on.
- **Tonight's real capacity:** next4 had 5 free seats, and a mover that re-spawns its subagents costs about 5 seats. That moves 1-5 sessions. Every other session is named, with a reason and an ETA, on the OPEN page within about 4 s on a warm cache and ≤25 s on a cold one.
- **Tokens:** 0 for the machinery; about 80 per limited pane on the fast path; a gap-aware continue when the audit shows unfinished workflow slots; 0 per idle pane.

---

## 1. Facts this design depends on

| Fact | Evidence | Consequence |
|---|---|---|
| The watcher answers the background-work dialog with the KEEP index by default: `CC_RECYCLE_BGWORK_ANSWER:-on`, KEEP = "Move to background and exit". | `handoff-fire.sh:7474-7486`, `hooks/lib/pane-modal.sh:251` (verified) | The reconciler exports `CC_RECYCLE_BGWORK_ANSWER=cancel`, and any session with background work is held before transplant. |
| `CLAUDE_CODE_DISABLE_AGENT_VIEW` removes only option 2. No flag skips the dialog. | `docs/research/team-inplace-upgrade-2026-09-23/q1-lead-exit.md` item 3 (verified) | Set it on every relaunch so future exits cannot choose option 2. W0 confirms what `pane_bgwork_key` returns when option 2 is absent. |
| Background sessions can be enumerated as `<cfg>/sessions/*.json` with `kind=bg`, plus a host pid. | `lr-upgrade.sh:653-666` `lru_bg_sessions`; the census's `lru_bg_kind` check at `:584` (verified) | They join the holder set H(sid) and feed the HOLD-BGWORK detector. |
| Confirm globs `<sid>.jsonl`. The `already_confirmed` branch runs only on zero hits, then `cp -p` overwrites the target and `mv` renames onto `.handed-off` without checking for an existing file. | `lr-transplant.sh:176-239` (verified) | A re-created stub would overwrite the retired transcript. Confirm must refuse when a stub sits beside `.handed-off`, and renames become link-then-unlink. |
| The watcher's stub fold appends the stub to `.handed-off` only, never to the target copy. | `handoff-fire.sh:7598-7606` (verified) | The stub's records are lost from the resumed transcript. It is replaced by `lr-transplant --phase fold-stub`, which appends to both copies and verifies they match. |
| The freshness re-read comes before confirm. The at-rest and subagent re-read runs only for same-account moves. | `handoff-fire.sh:13436-13449` vs confirm `:13492`; `:13477` gate (verified) | The last read moves after confirm and applies to every class. |
| `resume_engaged` with a token needs the token's user record and then a later non-error turn. Without a token record it returns rc 1, deliberately. | `handoff-fire.sh:4198-4215` (verified) | ENGAGED uses only the token form. |
| `--transplant-cause` and `lr-transplant --cause` accept only `limit|voluntary`. lr-handoff maps any non-voluntary run to limit. `--voluntary` on a remote pane is refused by lr-handoff's own fail-fast and by the probe's limit gate. | `handoff-fire.sh:9603-9607`, `lr-transplant.sh:54-59`, `lr-handoff.sh:286-287`, `:480-497`, `handoff-fire.sh:8438-8447` (verified) | Idle moves reuse `voluntary`, with a fact-file evidence bypass in both gates. No new cause word is added. |
| `k_cap` returns KMAX_RESIDENT (40) whenever `k_src != "work"`. 21.6% of the last day's utilization rows have `k_work=null`. | `claude-accounts:2335-2337` (verified); skeptic's `account-utilization.jsonl` count | `--place` never sizes from the resident cap. The reconciler supplies its own k_work. |
| The active term refuses iff `act+1 > ceiling`. | `capacity-admit.sh:1352-1365` (verified) | A ceiling that floats with live `act` always admits a restore, so the budget is frozen at cohort open. |
| `cc-resume-debt` proves only through `cc-find` LIVE and retries in a new window. | `bin/cc-resume-debt:118-128`, `:212-224` (verified) | It must take the launch lock, re-check holders and defer to live recorded processes. |
| The sibling session's git-read fix has not landed yet. `WT_TOP=$(git … --show-toplevel)` is still fatal under `set -e`. | `lr-handoff.sh:579-581` at trunk (verified) | lr-handoff.sh:579-599 belongs to the sibling until its sha lands. W2a edits only the `switch -C` line afterwards. |
| No installer exists for LaunchAgents. `launchd-parity-lint` covers `com.chrisren.*`, `com.claude.*` and `com.reso.lr-reset-poller` only. | `scripts/deploy-live.sh` (no LaunchAgents reference), `scripts/launchd-parity-lint.sh` header (verified) | New plists need an SSOT, a wider lint scope, and an operator-run load script. |
| Stale state on disk: `requests/` holds 18 files, `runs/by-sid/` holds 23 claim dirs, and all holders are `{sid,pane,pid,ts,by}` with no lstart. | `ls` this session (verified); skeptic's holder read | Stale reconcile runs before anything acts. A legacy holder is judged by argv match, never by bare pid liveness. |
| Measured stage times: bundle→painted 20-27 s for one pane and 28-45 s at N=4. First Enter swallowed in 4 of 6 recoveries, costing 32-43 s. Submitted→engaged 12-25 s. | bundle `events.jsonl` and `handoffs.jsonl`, 2026-09-29 | These are the latency inputs in §8. |
| A fresh `claude-accounts` sweep takes median 8.3 s, p90 22 s, max 62 s. Keep-warm runs every 180 s against a 90 s TTL. | keepwarm log, 200 rows | `--place` is cache-only up to `cache_grace_s` (600 s). The fresh sweep runs in the background. |
| *(Added 2026-09-30, decision 4, D4.6.)* Claude Code's own usage-limit continue never arms on this fleet. On 2.1.284 the auto-arm and the auto-opened `/rate-limit-options` menu both return early on `Sm()` = `replBridgeActive \|\| bg-session \|\| teammateAgentId`, and `remoteControlAtStartup` is true in all 5 config dirs. | 86 of 88 limited non-teammate transcripts on 2.1.260+ carry bridge-session records (the other 2 are sdk-cli); the vendor prompt occurs in 0 real transcripts; 0 of 45 undisturbed or notification-only episodes fired; the same gate is in 2.1.260 and 2.1.280, and 2.1.220 has no auto-continue at all | Our typed `continue` is the only wake, not a fallback. (1) The "press enter to continue" state and the >24 h menu do not occur while Remote Control is on, so the wake finds a plain, empty composer. (2) The gate rests on an untracked per-machine setting (`git grep` finds no `remoteControlAtStartup` in the repo), and a failed bridge re-enables the vendor wait for that session (secondary and quaternary each record `bridgeOauthDeadFailCount=1`). So the wake waits until reset + 120 s, past the 90 s jitter maximum, and checks `lr_engaged_after` first (`lr-reset-poller.sh:792-796`). (3) If the menu ever does open, `cc_tui_submit` abstains with rc 2 and types nothing (`scripts/lib/cc-tui.sh:11`, `:531-535`), so the wake pages. Change neither `remoteControlAtStartup` nor `autoContinueAtUsageLimit`; no limit-menu recognizer, held-lead marker for `cc-pane send`, or reso-keepalive fix is needed. |

---

## 2. Components

### C1. Producer: the StopFailure hook (`hooks/stop-failure-marker.sh`)
- **Unchanged:** the marker, the `limited` beat (`:244-255`), and the request `requests/<sid>.json` with `requested_by=stop-failure-marker` and atomic `mv -f` (`:373-487`, `:462`).
- **New, only when `recon.on` exists:** the hook writes `recon/facts/<acct>.<scope>.json` = `{status:"rejected", scope, window, resets_at, first_sid, observed_at, src}` with jq and tmp+mv.
  - The scope comes from `quotaLimits.rateLimitType`: `five_hour` gives `5h`, `seven_day` gives `7d`.
  - When `quotaLimits` is absent, the scope comes from lr_predicate's text tier: `model:<name>` or `fable`. The fable scope is marked untested because no instance has been seen in 10 days.
  - The first writer keeps `observed_at`. Later writers may only raise `resets_at`.
- **New:** on `authentication_failed`, the hook writes `recon/facts/<acct>.auth.json` and kicks the existing relogin rail.
- **Teammate skip** switches from the 8 KiB substring test (`:389-400`) to the parsed `is_teammate_head`.
- **Still guaranteed:** fail-open, exit 0, empty stdout, no python fork on the death path, and the hook never touches `autorecover.on`.

### C2. `lr_recon`, the reconciler daemon (python3 stdlib)
- **Launchd:** `com.reso.lr-reconciler`, with KeepAlive, RunAtLoad, ThrottleInterval 10, and PATH copied from `com.claude.compressor-sentinel.plist`.
- **Package:** `__main__`, `clock`, `observe`, `facts`, `phase` (the pure `derive_phase`), `plan`, `admit`, `act`, `store`, `fence`, `report`. Each is ≤400 LOC. The watchdog is **not** in the package (C9).
- **Singleton:** `fcntl.flock` on `recon/reconciler.lock`. The kernel releases it on death.
- **Modes, read from `recon/mode`:**
  - `observe`: census and plan go to `recon/shadow/`. Nothing is paged except a digest, and nothing is owned.
  - `plan`: records a plan plus the OPEN/DELTA pages. Nothing is owned, claimed or charged.
  - `act`: full operation.
  The cutover writes `recon.on` together with `mode=act`.
- **Activity states:**
  - **DORMANT** (no open record, no unexpired fact, no pending request): blocks in `kqueue` on `requests/`, `recon/facts/`, `~/.claude/autonomy/stop-failure/` and `recon/ctl/`, with a **20 s** timeout. On each timeout it stats those directories and expires facts. No census runs.
  - **ACTIVE:** a full pass every 3 s while any record sits between PLANNED and RELAUNCHED, every 5 s otherwise, and immediately on any kqueue event. It also watches `handoffs.jsonl` (NOTE_EXTEND) and `~/.claude/cc-registry/`. Events are debounced 1.5 s.
- **Heartbeat.** A dedicated thread writes `recon/heartbeat` = `{pid, lstart, progress, wall, uptime_raw}` every 10 s. `progress` is a counter that only the main loop advances: on each loop iteration, on each census stage, and every 1 s inside any subprocess wait. So the file's freshness proves the process is alive, and the counter's movement proves the loop is making progress.
- **Sleep-aware clock (`clock.py`).** Each loop computes `slept = Δ time.time() − Δ time.clock_gettime(CLOCK_UPTIME_RAW)`. `CLOCK_UPTIME_RAW` does not advance during sleep. If `slept > 5 s`:
  - every deadline, progress stamp and backoff moves forward by `slept`;
  - the next pass is observe-only.
  - Before any irreversible step (confirm, `/exit`, relaunch), the daemon requires `now − kern.waketime ≥ 30 s`. The actuators check the same thing through `LR_WAKE_GUARD_S=30`.
  - While any record is between PLANNED and RELAUNCHED, the daemon holds `caffeinate -i -s -w <pid>`. That cannot stop a lid close on battery, which is why the accounting above is still required.
- **Startup order:**
  1. flock;
  2. load every record inside a per-record try/except, moving failures to `recon/quarantine/` with a page;
  3. re-stamp owned holders;
  4. adopt live actuators by scanning the ps table for `--record-id` argv tokens;
  5. write the heartbeat.
  A crash before step 5 leaves the heartbeat stale, so C10's lapse rule and C9's page apply. Restarts are logged to `recon/restarts.jsonl`, and the second restart within 10 minutes pages.
- **Reboot.** Records whose `planned_at` is earlier than `kern.boottime` become **PARKED-REBOOT**: no new windows, and they are included in boot-resume's page. They resume only if `~/.claude/autonomy/boot-resume/mode` says `resume` and the admission terms are clear, which respects the `scripts/boot-resume.sh:13-16` posture.
- **Actuation gate:**
  - A daemon-origin item (hook, census, idle fan-out) actuates only if the operator's `autorecover.on` exists. Otherwise the record is PLAN-ONLY: a plan file and pages, **with no `owned/`, no claims and no phantoms**, so manual tools are never stranded.
  - A cc-lr-origin request actuates regardless.
  - The daemon never creates `autorecover.on`.
- **Request origins.** One file per origin:
  - `requests/<sid>.json` from the hook, kept for poller compatibility;
  - `requests/<sid>.cc-lr.json` from `cc-lr` and `lr-fleet --enqueue`.
  A record's origin is the maximum seen, and a cc-lr origin is sticky: it promotes a PLAN-ONLY record to acting on the next pass. A hook request for a sid that already has an open record updates that record and never creates a second one.

### C3. Observer (step b)
1. **Processes:** `ps -axo pid,ppid,lstat,lstart,args`, taken once. Liveness is exact (pid, lstart), and zombies (state Z) count as dead. The daemon reaps its own children with `waitpid(WNOHANG)` on every pass.
2. **Panes:** every live `/tmp/kitty-<pid>` socket whose owner process is `kitty` gets `kitty @ --to <sock> ls`. This matches `kitty_sockets` in `handoff-fire.sh:1223`, not the single-socket `cc-kitty-socket`.
   - Panes are keyed by **(kitty_pid, window_id)**.
   - A session is bound to a pane by walking claude's ppid chain up to the window's root pid, never by tty.
   - `is_focused` is recorded.
   - Each actuator receives `CC_TERM_KITTY_TO` set to its own pane's instance socket.
3. **iTerm2:** a pane whose id has the iTerm2 UUID shape, or that appears in no kitty `ls`, becomes **HOLD:iterm**. The daemon never drives osascript, because detached osascript to iTerm2 failed 3 of 3 times (`handoff-fire.sh:7179-7183`).
4. **Identity:** the registry row (with `KITTY_LISTEN_ON` and the kitty pid added by `session-register.sh`), or failing that the `--resume <sid>` argv leaf (the union logic from `bin/cc-limited:398-437`).
5. **Holder set H(sid):** distinct live (pid, lstart) across three sources:
   - registry pids;
   - `--resume <sid>` leaves with wrapper parents removed;
   - `<cfg>/sessions/*.json` rows of **any kind**, across all five config dirs, whose `sessionId` is the sid and whose pid is live.
6. **Transcripts:** a slug-direct lookup from the registry cwd into each store (measured 0.015 s for 30 sids), with an index fallback. The 128 KiB tail is classified in-process with `lr_predicate.classify_tail` / `is_teammate_head`. The store fold follows `lr-lib.sh:26-49`, `:641-650`.
7. **Background work:** a session has background work if either holds:
   - a `kind=bg` session row whose host pid is this claude (`lru_bg_kind` semantics);
   - a child of this claude whose argv is a shell `-c` (a harness background shell), since no foreground tool runs while the session is at rest. W0 validates this classifier against MCP children on the live panes.
8. **Composer and pane state:** read only for sessions the plan touches, with at most 4 concurrent reads, through `composer_content` (`handoff-fire.sh:2794`).
9. **Shape:** `root_shape` is `shell`, `launcher` or `headless` (`pane_shell_root`, `:4132`).
10. **Identity tuple, recorded at precheck:** {kitty_pid, kitty_lstart, window_id, tty, root_pid, root_lstart}.
11. **Degraded instruments:** any unreadable instrument marks its part of the snapshot DEGRADED, and nothing is planned for that part. Three consecutive DEGRADED passes page on their own.

### C4. Account fact ledger (step a)
- **Store:** `recon/facts/<acct>.<scope>.json`. The scopes and what they cover:
  - `5h` and `7d` are account-wide and cover every lane;
  - `model:<name>` covers sessions on that model only;
  - `fable` covers the fable lane;
  - `auth` is account-wide and means the account cannot serve at all.
- **Added by:**
  - a C1 hook write;
  - a death row the census sees with `quotaLimits` rejected;
  - a `claude-accounts --json` row whose per-window wire field (`wire['5h_status']` / `wire['7d_status']`, `claude-accounts:1086-1090`) reads `rejected`. The wire can only add a refusal.
- **Expires only when one of these holds:**
  - `resets_at + 60 s` has passed;
  - a wire read **of the same window** reads `allowed` with a read time later than `observed_at + 60 s`. That applies to `5h` and `7d` only. The Haiku wire probe cannot see `model:*` or `fable`, so those expire only at `resets_at`;
  - for `auth`, a `claude-accounts` row with `auth=ok` read after `observed_at` **and** a non-error turn on that account.
- **Contradiction.** A non-error assistant turn after `observed_at` by a session inside the fact's scope sets `contradicted=true`. It never expires the fact, because the 2026-09-19 next3 evidence shows turns 19 s after a real death. A contradicted fact blocks idle fan-out, which is optional work, but LIMITED sessions are still driven by their own death records.
- **Never a limit signal:** the endpoint integer `>=100` (it was false for 31 minutes tonight), or a usage-endpoint 429 (a poll throttle).
- **CLI:** `cc-lr accounts --limited` extends cc-limited's per-(account, cap, resets_at) header rendering (`bin/cc-limited:852-870`) with the fact ledger's scope, source, observed_at and contradiction flag.

### C5. Batch placement: `claude-accounts --place`, the only scorer
`claude-accounts --place --lane general|fable --recovery --movers FILE --facts DIR --kwork FILE --json` returns `{sid: {acct|null, reason, eta_s, weight}}`. The algorithm is in §5. These pieces change:

- **Snapshot:** cache-only, up to `cache_grace_s` (600 s). The per-row `quota_age_s` is reported. If no servable cache exists, the result is `WAIT_DATA` with exit 3, and the reconciler starts a background fresh sweep and re-plans when it lands.
- **k_work:** `--kwork FILE` carries the reconciler's own census per account: top-level plus subagent transcripts whose mtime falls inside `KWORK_WINDOW_MIN`, found by slug-direct lookup and a listing of the session dir. When the reconciler cannot measure an account, that account gets **0 capacity (WAIT_DATA)**. `KMAX_RESIDENT` is never used on this path.
- **Facts overlay:** any unexpired fact whose scope covers the lane, or an `auth` fact, sets the account's capacity to 0 with the fact as the reason.
- **Assignments:**
  - `--assign ACCT --id ID --sid S --w N --ttl-s T`;
  - `--assign-many FILE`;
  - `--unassign ID` appends `{t, void: ID}`.
  - `_assignment_rows` (`:2372`) keeps void rows.
  - `assignment_counts` (`:2381-2396`) sums `w`, skips voided ids, and honours `ttl_s` per row, defaulting to `ASSIGN_TTL_MIN` for legacy rows.
  - The prune (`:2447-2455`) runs under the same lock as the append.
- **Sweep cache:** records a per-account set of sids from the transcript walk. `apply_assignments` (`:2520-2536`) skips a phantom whose sid appears in a cached row swept after the phantom's `engaged_at`.
- **`get_data`** (`:4361`): `--max-wait N>0` becomes a real wall-clock bound. It serves cache up to grace; otherwise it exits 3, which callers map to WAIT_DATA.

### C6. Admission (`admit.py`, plus `scripts/lib/capacity-admit.sh`)
Four independent gates apply to a limited session's **first turn**, i.e. the continue prompt. A relaunch with no prompt needs none of them.

1. **Frozen restore budget.**
   - On entering ACTIVE, the reconciler computes `R = max(CC_ADMIT_ACTIVE_CEILING, A_open + C_open)`. `A_open` is `cc_sp_active` at entry and `C_open` is the number of LIMITED corpses at entry. R is fixed until the daemon returns to DORMANT.
   - A later death converts one active session into one corpse, so R does not change.
   - A new session the operator starts after entry raises `active` and reduces restore headroom. Restoring is allowed; growth is refused.
   - The check is `cc_sp_active + unredeemed_tokens + 1 ≤ R`. The library gets `CC_ADMIT_RESTORE_R=<R>` in the active term (`:1352-1365`), and **all** callers now count unredeemed, unexpired admission tokens as in-flight active.
2. **CPU brake at the pre-limit operating point.** A first turn is admitted only while `load1/ncpu ≤ max(2.5, L_open)`, where `L_open = max(load1, load5)/ncpu` at ACTIVE entry. load5 lags, so it reflects the load before the limit. There is a floor of one admission per 20 s, so nothing starves.
3. **Per-target-account first-turn pacer.** At most 3 first turns may be submitted-but-not-ENGAGED per account. The next is released on ENGAGED, on a TARGET-* verdict, or after 20 s. The same pacer, with 0-60 s jitter, covers in-place reset wakes (WAIT_RESET, HELD:team leads). This is burst protection; limiter behaviour is unmeasured above N=6 (0/40 failures at N≤6). *Corrected 2026-09-30 (decision 8): the "5-6-concurrent infra band that produces 529s" was never measured here; it came from GH#62426 (`docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-decision-8.md`).* As built, the pacer is `Admission` (`lr_recon/admit.py:87`, `LR_PACER_PER_ACCT`, default 3; slots free after `PACER_RELEASE_S` 20 s at `:38`), and the reset wake uses `Admission.pace_wake` (`:162`). It was wired to the act path only by W6d `f8f1e07ea` (D1.12); before that nothing called it.
4. **Memory terms:** headroom ≥4 GB and compressor segments ≤50%, via `cc_capacity_probe`. The load term stays off (`lr-lib.sh:417`).

- **What a refusal does.** A LIMITED session whose first turn is refused is still relaunched with no prompt (RELAUNCHED-UNPROMPTED, a named wait). That frees its source seat and keeps it ready to prompt.
- **Bounded gate.** The reconciler owns the counter, because probe refusals never spend the library budget (`capacity-admit.sh:1495-1500`). After 3 consecutive refusals in a cohort it admits one per 30 s and pages.
- **Tokens:** one-shot and sid-bound via `cc_capacity_token_mint` (`:680`), with the library-derived TTL of 1020 s (`:906-918`). lr-handoff's "300 s" message now reads the derived value.

### C7. Store, ownership and locks (`store.py`, `fence.py`)
- **`recon/sessions/<sid>.json`:** the full record. There is one file per sid and one writer, and writes are atomic (tmp, fsync, rename).
- **`recon/owned/<sid>`:** the **fence file**, `{record_id, attempt, procs:[{role, pid, lstart}]}`. It is created O_EXCL in the same step as the run claim and rewritten whenever a recorded process starts or ends. Other tools read only this file.
- **Run claim** `runs/by-sid/<sid>.active/holder` = `{pid, lstart, owner:"lr-reconciler", record_id}`.
  - **Legacy holders** (pid only) count as alive only if that pid's argv names `lr-fleet`/`cc-lr` and this sid. Otherwise they are stolen.
  - The sibling session is adding holders to `run_claim_take`; this design reads that format.
- **One lock pattern for every mkdir lock:**
  1. `mkdir`;
  2. write `holder` = `{record_id, attempt, role, pid, lstart, at}`, with lstart rendered `TZ=UTC LC_ALL=C`;
  3. do the work;
  4. `rm -rf`.
  - Any taker that finds the holder's exact (pid, lstart) dead steals the lock at once.
  - The daemon's own locks are `fcntl.flock`.
  - "Lock holder dead" is both a re-arm input and part of the stale reconcile.
- **The locks:**

  | Lock | Purpose |
  |---|---|
  | `locks/<sid>.launch/` | The per-session launch lock. Every typer of a relaunch takes it: the watcher, B, A-husk, R, cc-resume-debt, boot-resume-launch. While holding it, the taker re-checks that H(sid) is empty. `lr-fire-resume` asserts it holds the lock (through `LR_LAUNCH_LOCK`) and re-checks H(sid) immediately before `spawn` (`:883`). After the spawn it rewrites the holder to the claude (pid, lstart), so the lock is stolen when claude dies. |
  | `locks/pane-<sha1(sock:window)>.recycle/` | The per-pane recycle lock. `recycle_fire` takes it before arming a watcher, and a second arm is refused while the holder lives. The watcher releases it at its terminal state. |
  | `locks/git-<sha1(git-common-dir)>/` | Taken around every git **write** on the recovery path: `switch -C` on `pool/*` and `worktree add`. |

- **The transplant lock** `locks/<sid>.lock` gains `holder {record_id, pid, lstart}`. The same-target idempotent admit then succeeds only for the same `LR_RECORD_ID` or when the recorded holder is dead. A legacy lock without a record id keeps today's behaviour.
- **Logs:**
  - `recon/events.jsonl` (append-only, jq-encoded, ≤1 KB per line);
  - `recon/cohorts/<cid>.json`;
  - `recon/launch.log`, one line per typer acquisition, which is the double-typer audit;
  - a terminal line in the bundle's `events.jsonl` via `lr_state_append`, so `cc-lr status` shows success.

### C8. Actuators
Actuators are setsid children, tracked by (pid, lstart) and by a `--record-id <id>` argv token. After a daemon restart they are adopted, never respawned. Every actuator gets the same environment:

```
LR_RECORD_ID=<id> LR_ATTEMPT=<n> HF_RECYCLE_ATTEMPT=<id>:<n> HF_WATCHER_RECORD=recon/sessions/<sid>.watcher.json
CC_TERM_KITTY_TO=<this pane's instance socket> CC_RECYCLE_BGWORK_ANSWER=cancel LR_WAKE_GUARD_S=30
LR_INPLACE_AWAIT=0 LR_PLACED_BY=reconciler LR_ASSIGN_ID=<id> LR_PRESEED_DONE=<cid>
```

Before writing the actuator's pid into the record, the daemon writes an intent nonce into the record, so a crash between the spawn and the record write is found by the argv scan.

| Id | When | Command / effect | Reuses |
|---|---|---|---|
| **A: move** | PRE-MOVE planned; or TRANSPLANTED with its previous actuator and watcher dead | LIMITED: `lr-handoff.sh --sid --config-dir --cwd --target <placed> --launch --in-place --source-pane P --record-id R --attempt N [--model --effort]` with `LR_ADMIT_TOKEN_PATH`. IDLE: the same plus `--voluntary --account-evidence <fact file> --no-prompt` (ALLOW_LIVE_SA is not forced) | precheck `lr-handoff.sh:959-1072`, transplant `:1075-1111`, recycle `:1287-1331`, `recycle_fire` `handoff-fire.sh:13132-13579`, watcher `:7395-7911` |
| **A-husk** | HUSK-RETIRED that UNCONFIRM cannot undo (stub present, or `/exit` never landed) | `handoff-fire.sh --recycle --transplanted-source --husk --resume-launcher <bundle launcher> --resume-cfg <tombstone handed_off_to> --source-pane P --source-session S --record-id R`. **Skips confirm** and asserts that `.handed-off` exists and the tombstone names the cfg. Watcher first, then the last read, then `/exit` with read-back. At the shell: FOLD, then relaunch | the recycle_fire gates; the new `--husk` branch |
| **B: relaunch at shell** | EXITED | `handoff-fire.sh --relaunch-at-shell --source-pane P --source-session S --resume-launcher L --resume-cfg C --resume-cwd W --expect-identity <file> --record-id R`, taken under the launch lock, with FOLD first | the watcher body from "On shell" (`:7590-7911`) |
| **C: engage** | RELAUNCHED-UNPROMPTED, once admitted, types the continue prompt; RELAUNCHED-DRAFTED with DRAFT-MINE stable ≥5 s sends Enter; WAIT_RESET wake gets a same-account in-place continue; a HELD:team lead at its reset gets a same-account in-place continue | `cc_tui_submit` through the pane's socket | `scripts/lib/cc-tui.sh:397-413`, `:475-591`; `lr-submit-probe.sh` |
| **C-retry** | TARGET-TRANSIENT | After 15/30/60 s, a one-line continue carrying a **fresh per-attempt submit token**, at most 3 times | as C |
| **UNCONFIRM** | A refusal at the post-confirm last read, a surprise background-work dialog, or HUSK-RETIRED with a HOLD-class error and no stub | `lr-transplant.sh --phase unconfirm --sid --from --to --record-id --source-pid --source-lstart` (new) | §7.3 |
| **FOLD** | Before any relaunch where a stub exists and the source is dead | `lr-transplant.sh --phase fold-stub` (new). Replaces the watcher's `.handed-off`-only fold at `:7598-7606` | §7.3 |
| **ABORT** | TRANSPLANTED, the target has become ineligible, **and** the recorded actuator and watcher are both dead | `lr-transplant.sh --phase abort --record-id R` (new) | split-brain rules `lr-transplant.sh:300-351` |
| **R: replace** | PANE-GONE (only when this reconciler typed the `/exit`, or an open resume debt names the sid); a launcher-rooted pane | the existing REPLACE (`lr-handoff.sh:1344-1352`), or a new-window resume through `boot-resume-launch.sh`, under the launch lock | outcome REPLACED or REPLACED-NEW-WINDOW |
| **SPLIT** | SPLIT-BRAIN where one holder is a background session under the source cfg and the target holder is live | `CLAUDE_CONFIG_DIR=<src> claude stop <jobId>`, then verify the bg pid is gone, and re-stop once if the daemon re-claimed it | `lr-upgrade.sh:907-1024` |
| **HEAL** | The repo's `core.bare=true` while it has a working tree and no `.git/config.lock` | `git -C <top> config --unset core.bare`, verified by a separate read. **Disabled until the operator rules** (§12). By default the pane is HOLD:repo-bare and paged | `deploy-live.sh:1685-1736` |
| **D: team unit** | **Disabled in v1** | — | a lead with live pane members is HELD:team (C11) |

**Resume prompt, decided by the launcher from `lr-ingest-verify`'s result:**
- **rc 0:** the one-line continue: `[limit-recover] Moved from <src> to <dst> after a <window> usage limit (resets <t>); same session, full transcript. Continue the task you were on. (submit <token>)`.
- **A1/A2 failure** (unfinished workflow slots or waiting agents, as both of tonight's were): the same line plus `The handoff audit found <g> gap(s) and <w> waiting agent(s) in workflow run(s) <ids>; read the Gaps section of <audit.md> and re-run what is incomplete.`
- **Any other failure:** the continue line plus the audit path.
- The full `/limit-recover ingest` (about 26.5K resident tokens, per `lr-handoff.sh:1222-1224`) is retired.
- `killed_inflight` counts workflow slots once the glob is widened (`handoff-fire.sh:5507`).
- The idle no-prompt path skips `lr-ingest-verify`.

### C9. Watchdogs
- **`scripts/limit-recover/lr-recon-watchdog.sh`** runs under launchd `com.reso.lr-reconciler-watchdog` (StartInterval 30). It is bash 3.2 and imports nothing from the package.
  - **Kill condition:** all four must hold.
    - The holder (pid, lstart) is alive.
    - `progress` has not changed across two reads ≥30 s apart.
    - At least 180 s have passed since the last advance.
    - `now − kern.waketime > 120 s`.
  - **Kill action:** TERM, wait 10 s, then KILL. KeepAlive restarts the daemon. Actuators survive because they run in their own sessions.
  - **Crash-loop detection:** the holder pid changes twice within 10 minutes, or the heartbeat is stale for more than 60 s with no live holder. Either one pages, latched once per 15 minutes, and the page includes the last line of the daemon's stderr.
- **Poller backup:** when `recon.on` exists and the heartbeat is stale, the poller pages every 15 minutes (not once) and runs a bare `launchctl kickstart`, never `-k`.

### C10. Fences: one actuator family per session
**The predicate** is `lr_recon_defers <sid>`, in `scripts/limit-recover/lr-recon-fence.sh`, with a python mirror:

```
recon.on absent                                     → act
owned/<sid> absent                                  → act
caller's LR_RECORD_ID == owned.record_id            → act   (it is the reconciler's own actuator)
heartbeat progress advanced within 180 s (sleep-adjusted) → DEFER
any owned.procs (pid,lstart) alive                  → DEFER (regardless of heartbeat)
otherwise                                           → act, but take locks/<sid>.launch and re-check H(sid) before typing
```

This resolves both skeptic findings at once:
- A dead or crash-looping daemon cannot unlock actuation while any process it started for the session is alive.
- A dead daemon with nothing of the session running does not strand the session: manual tools and the poller's arms work again.

**Call sites.** The predicate runs inside the entry functions, not in CLI mode switches:
- `lf_one` (`lr-fleet.sh:865`), which also covers `--recover` (`:1249`);
- lr-handoff main, before the precheck;
- `recycle_fire`, both the self arm and the remote arm (`handoff-fire.sh:13132`);
- `lru_switch_drive` and the upgrade drive (`lr-upgrade.sh:817-870`, `:1286-1292`);
- `cc-resume-debt`'s `_step` / `_relaunch`;
- `boot-resume-launch.sh`;
- the poller's §0, §2a, §2 and nudge arms, per sid.

**`cc-lr recover|switch`** writes `requests/<sid>.cc-lr.json` while `recon.on` exists and the heartbeat is fresh. Otherwise it uses today's direct path, and that path takes the launch lock.

**`cc-resume-debt`** takeover requires all three:
- the fence says act;
- it has taken the launch lock;
- H(sid) is empty.

It prefers an in-pane `--relaunch-at-shell` when the recorded pane is at a shell with a matching identity tuple, and uses a new window only otherwise.

### C11. Operator surface (`report.py`)
- **Cohort** = (account, scope, resets_at). It stays open until the fact expires and every member is terminal or holding.
- **OPEN**, latched once per cohort. Example:
  `next3 LIMITED (7d) until 07:00 CT · 22 blocked, 8 idle, 3 working (expected to die later) · next4←1 (weight 5) · 29 WAITING (next=kmax k_work 18; next2=5h rejected until 06:30Z) earliest wake 04:37Z`
- **DELTA:** coalesced, at most one per 5 minutes, and only when membership or dispositions change.
- **CLOSE:** `30/30 in 3m41s`, or the residue named by pane, title, reason and next action.
- **Immediate pages:** SPLIT-BRAIN, ESCALATED, IMPOSSIBLE, HELD:team (with the reset ETA).
- **Maximum ages**, after which a page fires and then re-fires hourly:

  | State | Max age |
  |---|---|
  | WAIT_DATA | 2 min |
  | WAIT_SLOT | earliest wake + 10 min |
  | WAIT_CAPACITY | 15 min |
  | HOLD-DRAFT | 15 min |
  | HOLD-BGWORK | 20 min |
  | HOLD-SUBAGENTS | 30 min |
  | HOLD-MENU | at once |
  | HOLD:repo-bare | at once |
  | HOLD:iterm | at once |
  | HELD:team | not ENGAGED 10 min after reset |

- **Commands:**
  - `cc-lr status --cohort [cid]`: per member, the phase, age, attempt, last error class, next action and ETA.
  - `cc-lr cohort refire <sid|pane>`: writes a ctl request that resets that member's budget.
  - `cc-lr accounts --limited`.
- **Readout:** one counted line in `hooks/operator-readout.sh`.
- **Mail:** one mail per cohort, only to a cc-lr requester pane. Nothing goes to the desk role.
- **Human residue:** a real draft or a background job held past its maximum age is filed through `cc-backlog needs`.
  - *Corrected 2026-09-30 (decision 6, D6.2), as built:* a held draft is **paged**, not filed. The page sink sends `cc-notify --role desk` and, unless that reports `verdict=delivered`, posts through `scripts/limit-recover/lr-page.sh` (macOS Notification Center, plus a Pushover phone leg once the operator's credentials exist) (W6d `6cd769a08`, `f8f1e07ea` D6.5). The page quotes the draft from a raw screen snapshot (`b5740ca25`, D6.7). The old sink passed `--page`, which `cc-notify` rejects with exit 2, so no reconciler page had ever been delivered.
  - *HELD:team (decision 4, D4.11):* the page fires when the hold starts, whatever the reset distance (the immediate-page set, `report.py:732-748`), so a lead with a far reset is visible at once and the operator can shut idle members down to let it move alone. There is no idle-age release rule: in the one true hold, members idle 36-40 min went back to work, and in the false hold the member had been idle only 13 min.

### C12. Repository hygiene
The daemon reads `core.bare` twice for each git-common-dir the cohort touches: before dispatch and after any actuator that ran a `git worktree` command.
- `core.bare=true` with a working tree: HOLD:repo-bare. HEAL runs only if the operator's ruling enables `LR_HEAL_CORE_BARE=on`.
- `worktree prune` leaves the resume hot path (`lr-fire-resume.sh:357`). It deletes metadata for a sibling's worktree that is only missing for a moment.
- `worktree add` runs under the git lock.

---

## 3. End-to-end flow

**T0: the first session on account X gets `quotaLimits.status=rejected`.**

1. **Hook** (event-driven, 0 s): marker, beat, request, and fact `X.<scope>`.
2. **Wake:** kqueue fires in ≤0.1 s, DORMANT becomes ACTIVE, and events are debounced 1.5 s. The sleep check and wake guard apply here.
3. **Stale reconcile**, before anything acts. It runs on the first pass after start and on every pass after that. Every request, parked record, claim, lock and stuck bundle is checked against evidence:
   - RE-ENGAGED, or live on the target: NOT_NEEDED with evidence. The request moves to `claimed/` and is never deleted.
   - **No live holder at first observation:** NOT_NEEDED(dead-before-claim). This reuses the drain-time validator the sibling session is landing for the poller, so there is one implementation.
   - Dead-holder and legacy-holder claims and locks: stolen and released.
   - Records that predate `kern.boottime`: PARKED-REBOOT.
4. **Facts, step (a):** the ledger is updated from the event. If the cached `claude-accounts --json` is older than grace, one background `--fresh` runs, bounded by a real `--max-wait 60`, and it lands off the critical path.
5. **Census, step (b), about 1 s.** Every live session in an affected scope goes into exactly one bucket:
   - **LIMITED:** its last assistant record is the limit. It moves and is prompted.
   - **IDLE-ELIGIBLE:** moves with no prompt, and only if **all** of these hold:
     - at rest, with no background work and no live subagents (workflow slots included);
     - composer affirmatively empty;
     - pane not focused;
     - an account-wide fact (`5h`/`7d`) that is **not contradicted**, with `resets_at − now ≥ 30 min`;
     - not a lead with live members.
   - **WORKING:** left alone. If it dies later it re-enters at step 1 as a DELTA.
   - **HOLD-DRAFT**, **HOLD-BGWORK**, **HOLD-SUBAGENTS** (idle only), **HOLD:iterm**, **HOLD:repo-bare**.
   - **TEAMMATE:** untouched.
   - **HELD:team:** a lead with live pane members.
   - **LAUNCHER-ROOTED:** goes to R, decided before any transplant.
   - **HEADLESS / CWD-GONE / NO-TRANSCRIPT:** IMPOSSIBLE with the reason.
   - **DUPLICATE**, i.e. |H| > 1: SPLIT-BRAIN.
   - **STAY:** the source resets within 15 minutes, so WAIT_RESET.
6. **Plan, step (c) decision, one thread, about 0.6 s:**
   - Take `admit.lock`, with a holder, so a manual `lr-fleet --one` interleaves safely.
   - Run `--place` per lane with the facts and the reconciler's own k_work.
   - Compute R and L_open on ACTIVE entry, and run one memory probe.
   - In `act` mode, write the records, the `owned/` files, claims with holders, and one `--assign-many` using ids `recon:<cid>:<sid8>:<attempt>`, each with its weight and `ttl_s=1200`. In `plan` mode write the plan file only.
   - Release the lock.
   - Unplaced movers become WAIT_SLOT with a reason and an ETA.
   - Send the OPEN page.
7. **Preseed:** once per distinct (target, cwd), with parallelism ≤4 across targets and serial inside a target's `.claude.json.lock`.
8. **Dispatch.** Order: LIMITED first, then oldest death, interleaved across targets.
   - An actuator spawns when a boot slot is free (B, §6) and fewer than 16 actuators are running.
   - Each spawn records the identity tuple and the intent nonce, and a LIMITED spawn mints its admission token.
9. **Actuate, per pane in parallel.** Actuator A:
   1. precheck, read-only, including the new background-work and launcher-root checks; a refusal is NOTMOVED;
   2. transplant admit, with the lock carrying the record id;
   3. launcher written to the bundle;
   4. `recycle_fire`:
      - composer gate;
      - take the per-pane recycle lock;
      - arm the watcher and prove its heartbeat;
      - write `HF_WATCHER_RECORD`;
      - confirm (stub refusal, link-then-unlink rename, `confirm_len` recorded);
      - open the resume debt;
      - **last read**: composer EMPTY, transcript at rest, no live subagents unless cause=limit, no background work, and for LIMITED the last record is still the limit;
      - type `/exit` **without Enter**, read it back, and press Enter only if the composer reads exactly `/exit`.
      A refusal at the last read runs 5 backspaces if our `/exit` is visible, then UNCONFIRM, then kills the watcher and records a HOLD with its reason.
   5. The watcher sees the shell (1 s poll). If a background-work dialog appears, it sends Esc and emits `recycle-held-bgwork`, and the reconciler UNCONFIRMs.
   6. The watcher takes the launch lock, runs FOLD if a stub exists, and types the nonce-verified launcher.
   7. `lr-fire-resume`: asserts the launch lock, re-checks H(sid), spawns `claude --resume` with `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` under expect, and rewrites the lock holder to the claude process.
   8. For LIMITED, the continue prompt is typed only once C6 admits it. Otherwise the session stays RELAUNCHED-UNPROMPTED.
   9. Enter is sent on a stable DRAFT-MINE, and re-sent on the measured schedule (default 10/25/40 s, at most 3 times).
   The boot slot is released at "composer painted".
10. **Confirm, on every pass, level-triggered:** `derive_phase` (§4) replaces the cached phase.
11. **Re-fire, on every pass:** any record whose recorded processes are all dead and whose deadline has passed is classified (§7) and handed its next idempotent action.
12. **Wakes, re-evaluated on every pass:** WAIT_* and HOLD_* respond to phantom voids, session ends, resets, `resets_at`, composer changes, background jobs ending, and sweep arrivals. When a WAIT_SLOT source's fact expires, the source becomes a candidate that stay prefers. At resets, the in-place engagements get 0-60 s jitter and go through the per-account pacer.
13. **Close:** members reach CLOSED after the 5-minute sentinel (no bg row for the sid reappears under the source cfg). Then:
    - void phantoms once a later sweep includes the session;
    - release claims and `owned/`;
    - settle resume debts;
    - write the requests' outcomes into `claimed/`;
    - write the bundle terminal lines;
    - send CLOSE, plus one mail if a cc-lr requester exists;
    - update the readout.
    The daemon returns to DORMANT when nothing is open.

---

## 4. Per-session durable state machine

### 4.1 Record (`recon/sessions/<sid>.json`)
- **Identity:** sid, pane `{kitty_pid, window_id}`, surface (kitty|iterm), kind (limited|idle), lane, scope, source_acct, source_cfg, source_pid, source_lstart, root_shape, identity tuple.
- **Plan:** cohort_id, origin (max of hook|census|fanout|cc-lr, cc-lr sticky), target_acct (pinned once a tombstone exists and until the session is live on the target), weight, assign_id, admit_token, submit_token (one per attempt), bundle, `confirm_len`.
- **Execution:**
  - `intent {nonce, at}`;
  - `procs[]` with role in actuator, watcher, launcher, fire_resume or claude, each with pid, lstart and argv hash;
  - timeline: detected, planned, confirmed, exit_typed_by_me, exited, relaunched, submitted, engaged;
  - attempt, attempts_by_class, last_error {class, fingerprint, detail, at}, next_eligible_at, wait {reason, wakes[], max_age};
  - `repo_state`.
- **Terminal:** goal_snapshot, terminal {outcome, proof, at}, sentinel_until.

### 4.2 `derive_phase` (pure; checked in this order; the derived phase replaces the cached one)

H(sid) is the holder set from C3 item 5. "Pane-bound" means bound to the recorded (kitty_pid, window_id) by the ppid walk.

| # | Evidence | Phase | Action |
|---|---|---|---|
| 1 | \|H(sid)\| > 1, counting bg rows under any cfg | **SPLIT-BRAIN** | Freeze and page. If a bg row under the source cfg is one of the holders and the target holder is pane-bound: SPLIT, then re-derive. |
| 2 | A pane-bound holder under the target cfg, and the last assistant record after the submit record is `kind=limit` | **TARGET-LIMITED** | Void the phantom, re-place using the facts, and hop through `lr-transplant --from <target>` (a new attempt, class WAIT). |
| 3 | The same, with `authentication_failed` | **TARGET-AUTH** | Write the auth fact, then WAIT(target-auth). Re-place and hop. Never counted against the pane's fingerprint. |
| 4 | SUBMITTED, and the last target record is an api error of kind `server_529`/`server_error`/`network` | **TARGET-TRANSIENT** | C-retry. |
| 5 | kind=limited: in the target copy a user record carrying **this attempt's** submit token at a byte offset greater than `confirm_len`, a later non-error assistant record, a pane-bound holder under the target cfg, and the source (pid, lstart) dead | **ENGAGED** | Sentinel for 5 minutes, then CLOSED. |
| 6 | kind=idle: a pane-bound `claude --resume <sid>` under the target cfg, the same (pid, lstart) on two samples ≥15 s apart, a readiness note (READY/READY-QUIET) or the composer EMPTY on two reads, and no bg row under the source | **MOVED** | Sentinel, then CLOSED. A parked-menu note (`lr-fire-resume.sh:961`) becomes HOLD-MENU. |
| 7 | A pane-bound holder under the target cfg | **RELAUNCHED** (UNPROMPTED / DRAFTED / SUBMITTED) | C per sub-state, gated by C6. |
| 8 | `.handed-off` exists, the source is alive, and a live watcher for (pane, sid) exists (argv scan, any attempt) | **EXITING** | Wait on the watcher. No action. |
| 9 | `.handed-off` exists, the source is alive at `cc`, and there is no live watcher | **HUSK-RETIRED** | If there is no stub, the target has no holder, and last_error is HOLD- or TOCTOU-class: UNCONFIRM, then PRE-MOVE. Otherwise A-husk, and only after any HOLD has cleared. |
| 10 | `.handed-off` exists, the pane is at a shell, H(sid) is empty, the identity matches, and no live watcher, launcher or `lr-fire-resume` exists | **EXITED** | B, under the launch lock. |
| 11 | `.handed-off` exists, destruction of the pane is proven (absent from every kitty socket on two consecutive observations and its tty gone), and there is no live watcher | **PANE-GONE** | R only if `timeline.exit_typed_by_me` is set or an open resume debt names the sid. Otherwise NOT_NEEDED(handed-to-resume-debt). |
| 12 | The lock and tombstone name the target, the source is not retired, and the source is alive | **TRANSPLANTED** | A again with the same record id (admit is idempotent). Or, if the target is ineligible **and** the recorded actuator and watcher are dead: ABORT, then re-place. |
| 13 | none of the above | **PRE-MOVE**: DETECTED, PLANNED, WAIT_SLOT, WAIT_RESET, WAIT_DATA, WAIT_CAPACITY, HOLD-DRAFT, HOLD-BGWORK, HOLD-SUBAGENTS, HOLD-MENU, HOLD:iterm, HOLD:repo-bare, HELD:team, PARKED-REBOOT, BACKOFF | per plan and classification |

Row 1 comes before row 5, so a husk that is still alive can never be closed as ENGAGED.

**Outcomes:**
- **Terminal:** CLOSED(ENGAGED|MOVED), NOT_NEEDED(reason), REPLACED, REPLACED-NEW-WINDOW, IMPOSSIBLE(reason).
- **ESCALATED** is not terminal. It keeps `owned/` and the claim, and it re-arms (§7.2).
- **Released only at:** a terminal state after its sentinel, or an explicit operator abandon. The resume debt is settled at the same moment.

### 4.3 Deadlines
**A record with any live recorded process is never timed out by the reconciler.** It waits on that process's own bounds:
- **Watcher:** `HF_RECYCLE_SHELL_WAIT_S` (600) + `RCY_ENGAGE_TIMEOUT` (180) + 60 s.
- **Actuator:** 300 s without a progress line in its log.

Both are multiplied by `max(1, load1/ncpu/2)` and adjusted for sleep. A process past its bound is TERMed, and the phase is re-derived.

When no recorded process is alive, the phase deadlines are:

| Phase | Deadline |
|---|---|
| PLANNED → TRANSPLANTED | 45 s |
| TRANSPLANTED → EXITED | 60 s |
| EXITED → RELAUNCHED | 60 s |
| RELAUNCHED-DRAFTED → SUBMITTED | 60 s |
| SUBMITTED → ENGAGED | 180 s |

### 4.4 Watchdog invariant, asserted every pass
Every non-terminal record must have exactly one of the following:
- a live recorded process (actuator **or watcher**, launcher, `lr-fire-resume`, or claude in a sub-state waiting on it);
- a `next_eligible_at` with a named reason;
- a HOLD or WAIT with a named reason and a maximum age.

In addition, every record from PLANNED through RELAUNCHED must hold a live phantom. A record that breaks either rule is logged as `RECON-DEFECT <sid>` and gets its next action in the same pass.

### 4.5 Crash resume
- **Daemon crash:** KeepAlive restarts it within 10 s, and the C2 startup order runs. Actuators found by the argv scan (`--record-id`) are adopted; ps state Z counts as dead. Dead actuators are replaced by the next idempotent action for the re-derived phase.
- **Daemon wedged:** C9 kills it after ≥180 s without progress.
- **Actuator crash mid-step:** handled by the evidence each step leaves:

  | Evidence | Next phase and action |
  |---|---|
  | admit done | TRANSPLANTED, then A (a no-op admit) |
  | confirm done, `/exit` not typed | HUSK-RETIRED, then UNCONFIRM or A-husk |
  | `/exit` typed, relaunch not typed | EXITED, then B |
  | relaunch typed, boot died | EXITED, then B again |

  The launch lock and the H(sid) re-check prevent a double launch in every case.
- **Write order:** claim and `owned/` first, then the intent nonce, then the spawn, then the procs update. A crash anywhere in that sequence is either adopted or leaves a claim with no record, which is stolen at once.

---

## 5. Target assignment for N movers

```
snap   = claude-accounts cache (≤ cache_grace_s) ; else → all movers WAIT_DATA, background --fresh, re-plan on arrival
kwork  = reconciler census per account (None if that part of the census is DEGRADED)
facts  = unexpired facts whose scope covers the lane, plus auth facts
for a in accounts:
    if kwork[a] is None:                     cap[a]=0 ; why="k-unmeasured"          # never KMAX_RESIDENT
    elif fact(a):                            cap[a]=0 ; why=fact.reason
    else:
        why = _excluded(a, recovery=True, k_eff=kwork[a]+phantom_w(a))   # floors, wire, 5h-cutoff, DATA
        if why == "kmax-concurrency": why=None
        cap[a] = 0 if why else max(0, KMAX - kwork[a] - phantom_w(a))
movers = own-account returners (source fact expired) first, then LIMITED by death ts, then IDLE
for m in movers:
    w = 1 + distinct subagents/**/agent-*.jsonl of m written in KWORK_WINDOW before death + killed_inflight(m)
        # as built (W6d f8f1e07ea, D3.6(d)): 1 + subagents written in the 10 min before the death
        # (timeline.detected), lr_recon/plan.py:135-138; killed_inflight is not built
    cands = [a for a in accounts if cap[a]-placed_w[a] >= w and a != "none" and a in account_map
             and not store_holds(a, m.sid)
             and (a != fold(m.src) or not fact(m.src, m.lane))                 # the source is eligible once it resets
             and floors_ok(a, n=placed_n[a]+1, b_sess=burn(m))]
    if not cands: out[m]=(None, joined reasons, eta(m)); continue
    if fold(m.src) in cands: best = fold(m.src)                                # stay: in place, no transplant
    else: best = argmax score_lane(a with k_phantom += placed_w[a]) ; tie → min placed_n → hash(sid)
    placed_w[best] += w ; placed_n[best] += 1
```

- **Per-pick survival floors:**
  - `s_proj(a,n) = su + (b_native + n·b_sess)·min(1 h, session_reset_h) < RECOVERY_S_CEIL`
  - `w_rem − (n+1)·r_w_worst·min(weekly_reset_h, 9 h) ≥ RECOVERY_W_FLOOR`
  - `b_sess` is the mover's own pre-death burn when it can be measured; otherwise the fleet p75, about 7 pp/h as measured tonight.
    - *As built (W6c `ad21bf402`, D3.6):* `b_sess = max(the mover's own pre-death burn, 7 pp/h)` (`bin/claude-accounts:4533-4534`; default `PLACE_B_SESS_DEFAULT` 0.07/h at `:4303`, env `CC_PLACE_B_SESS_DEFAULT`). A supplied burn only ever raises the charge: raw pre-death burn bounded the post-move burn for 19 of 56 transplant pairs, `max(pre, default)` for 51. A model-cap death, and a weekly-cap death within 1 h of a 5h reset, count as unmeasured, because their pre-death burn says nothing about the post-move burn. No caller supplies `burn_ph` today (the field is `lr_recon/types.py:819`, never set), so every mover is charged the default.
  - `r_w_worst` comes from `accounts.json router._recovery`.
  - **What the `(n+1)` weekly term does, and where it diverges** (decision 3, D3.5; left unchanged, the reconciler only observes):
    - (a) The weekly term has no native-burn term (`bin/claude-accounts:4514-4518`), against `b_native` in the 5h term (`:4506-4512`), so the `+1` is its only reserve for the target account's own load.
    - (b) It makes the reconciler stricter than the live lane. With `r_w_worst` 0.011/h, the first mover needs about 29.8% of the week left (`0.10 + 2·0.011·9`) when the reset is 9 h or more away, against the flat 10% (`RECOVERY_W_FLOOR_DEFAULT`, `:2358`) that the poller's `--rank --recovery` applies (`_excluded`, `:3963-3966`). On 09-12 `next3` had 23-24% left: the live lane would have moved that session and the reconciler would not.
    - (c) The one case it decided (09-12) replays as roughly a wash (about +4.7 h against -5.2 h, estimated), so n against n+1 is unsettled.
    - (d) Before `recon.on` is set, count the shadow passes where `--place` says wait on `recovery-weekly-thin` while `--rank --recovery` routes, and settle n against n+1 from that count.
- **No herd:** every pick re-scores KF with the earlier picks' weights included.
- **Phantoms:** charged with the mover's weight at PLANNED, with `ttl_s=1200` refreshed on every pass while the record is non-terminal. A dead daemon's phantoms heal within 20 minutes. They are voided:
  - at CLOSED, once a cached sweep newer than `engaged_at` includes the session;
  - at park, ABORT, re-place and terminal failure.
- **ETA for WAIT_SLOT:** projected from the in-flight movers' expected ENGAGED times plus the aging of k_work out of the 10-minute window, and from each account's `resets_at`. If the source's `resets_at` comes before the earliest projected target slot, the record becomes WAIT_RESET.
- **Stay rule:** a LIMITED session whose source resets within `EPS_H` (15 minutes) waits and is continued in place on the same account. An IDLE session moves only if at least 30 minutes remain.
- **Pinning:** from TRANSPLANTED through RELAUNCHED the target is pinned to the tombstone. Once the session is live on the target and limits there (TARGET-LIMITED), it is a new move from that target.
- **Idle seat policy:** `router.RECOVERY_IDLE_SEATS = active|resident`, default `active`, until W0 measures whether a no-prompt `--resume` writes to the transcript.

---

## 6. Admission and concurrency bounds

| Resource | Bound | Mechanism |
|---|---|---|
| Observe and plan | 1 thread | one pass per cohort decision |
| Actuator subprocesses | W = 16 | mostly waiting |
| TUI boots (relaunch typed → painted) | **B, AIMD:** start 6; +2 after a wave where every relaunch-typed→painted ≤ 15 s (measured 5-9 s); halve on any > 45 s or a boot INDETERMINATE; floor 2, cap 12 | the resource that failed at load 40+ on 2026-09-19 |
| First turns per target account | 3 submitted-not-ENGAGED; next on ENGAGED, TARGET-*, or 20 s | burst protection; limiter behaviour unmeasured above N=6 (0/40 failures at N≤6) — *corrected 2026-09-30, decision 8* |
| First turns, box-wide | frozen R, CPU brake at `max(2.5, L_open)` per core with a floor of 1 per 20 s, memory terms | C6 |
| Per target account seats | `KMAX − kwork − Σ phantom weights` | C5 |
| iTerm2 panes | none (HOLD:iterm) | detached osascript fails 3/3 |
| Kitty sockets | ≤4 concurrent reconciler reads per instance; `prove_target` uses `kitty @ ls --match id:N` and checks the kitty pid | instead of the 366 KB full `ls` per RPC |
| `.claude.json.lock` | once per (target, cwd) per cohort | preseed; drivers honour `LR_PRESEED_DONE` |
| Git writes | one lock per git-common-dir, with a holder | C7 |
| Launch / recycle | one typer per sid; one watcher per pane | C7 |
| Team units | disabled; HELD:team, unconditional in v1 (no switch); the lead is continued in its own pane at the reset | C11, § 15 |

---

## 7. Fault tolerance

### 7.1 Detecting non-completion
- Every in-scope session has a record.
- Every phase without a live process has a deadline.
- Every WAIT and HOLD has a maximum age.
- The invariant in §4.4 runs on every pass.
- An actuator's own verdict (lr-fleet mail, lr-handoff token, `results.tsv`) is never taken as success. That closes the false RECOVERED results for panes 751 and 815 and the 4 false `SWITCHED proven=yes`.

### 7.2 Classification: class first, fingerprint second
The fingerprint is (phase, class, the first `!!` line with digits and paths normalised, the actuator script's sha). When there is no `!!` line, the rc and the last stderr line stand in for it.

| Class | Examples | Disposition |
|---|---|---|
| **TRANSIENT** (allowlist) | kitty RPC timeout; `surface rc 3`; "resolved to no tty"; slow boot ("no claude process appeared within 90s"); lock busy; router exit 5; usage 429; swallowed Enter; killed actuator or watcher; `cc_tui_submit` MANGLED; a background dialog that reappears | Backoff 10/30/60/120 s, capped at 5 min. **Never escalates.** Pages at 6 attempts, then hourly while retries continue. |
| **WAIT** | no routable target (with the router's reason); capacity refused; every account limited; router exit 3; TARGET-LIMITED; TARGET-AUTH | WAIT_* with named wakes. Does not count as an attempt. |
| **HOLD** | foreign draft; background work; live subagents on an idle move; HELD:team; composer unreadable; parked menu; repo bare; iTerm2 | Re-checked every pass. Each has a maximum age (C11). No keystroke over a draft. No stash exists (decision 6, 2026-09-30); a ≤2-character stray composer on an unfocused pane is scrubbed with a receipt (`scripts/lib/composer-intent.sh:29,67-70`; non-ASCII is never a stray). |
| **DETERMINISTIC** | a fingerprint **outside** the TRANSIENT allowlist, seen on 2 consecutive attempts | **ESCALATED:** stop, page with evidence, keep ownership. Re-arms (attempt counter reset, one re-fire) when any of these happens: a live-layer sha change in the actuator scripts; a change in the repo's `core.bare` or worktree list; a change in the account eligibility set; the pane's process (pid, lstart) changes; a lock holder dies; load falls below its level at the time of failure; **or 15 minutes pass**. |
| **IMPOSSIBLE-IN-PLACE** | launcher-rooted; the pane gone after our `/exit`; headless | R, verified by the same rules, ending REPLACED or REPLACED-NEW-WINDOW. A cwd that is gone and cannot be recreated is IMPOSSIBLE. |

How the probe's NOTMOVED reasons map:

| NOTMOVED reason | Maps to |
|---|---|
| `not-limited`, kind=limited | NOT_NEEDED |
| `not-limited`, kind=idle | WAIT_DATA, re-checked next pass |
| `teammate` | NOT_NEEDED (the lead owns it) |
| `draft` | HOLD-DRAFT |
| `pane-not-cc` with the pane at a shell | EXITED |
| `bg-work` | HOLD-BGWORK |
| unreadable, capacity, router | TRANSIENT or WAIT |

### 7.3 Idempotency, per step
- **Plan:** deterministic from the snapshot. An unexecuted plan is replaced, never duplicated, and assignment ids deduplicate.
- **Claim / `owned/`:** mkdir and O_EXCL. The owner re-entering is a no-op.
- **Precheck:** read-only.
- **Admit:** to the same target with the same record id, `already_transplanted` is a no-op. Any other caller is refused.
- **Confirm (changed):**
  - Refuses with rc 2 `stub-beside-retired` when `<sid>.jsonl` and `.handed-off` both exist.
  - Asserts that the lock exists, names TO, and carries the caller's record id.
  - Renames with `ln <sid>.jsonl <sid>.jsonl.handed-off && unlink <sid>.jsonl`. `ln` fails when the destination already exists, so nothing is overwritten.
  - Writes `confirm_len` to the receipt.
  - `already_confirmed` (zero hits plus `.handed-off`) still returns rc 0.
- **Unconfirm (new):**
  - Requires: the source (pid, lstart) alive; `<sid>.jsonl` absent; the target has no holder; the lock names TO and the record id.
  - Action: `ln .handed-off <sid>.jsonl && unlink .handed-off`. A stub created in between makes `ln` fail, and the record goes to the husk path.
  - Moves the target copy into `locks/<sid>.unconfirmed-<ts>/` as evidence.
  - Renames the tombstone to `.unconfirmed`, releases the lock, and returns rc 0 or 2.
- **Fold-stub (new):**
  - Requires: the source dead, H(sid) empty, and sha(target) == sha(retired), meaning no resume has written to the target.
  - Appends the stub to both copies, verifies sha(target) == sha(retired), and unlinks the stub.
  - If the target has advanced, it refuses and pages.
- **`lr-lock.py`:** a lock whose source has both a stub and a `.handed-off` is CUSTODY and never ABANDONED.
- **ABORT:** allowed only when the source is not retired, the target has no holder, and the recorded actuator and watcher are dead.
- **`/exit`:**
  - only on an affirmative `pane_cc_state=cc`;
  - only after the post-confirm last read;
  - typed without Enter, read back, Enter only on an exact match;
  - never into an EXITED pane.
  The blind anti-strand Enter (`handoff-fire.sh:13566`, the second `as_write "$SID" ""`) is deleted. The watcher's content-gated retype at 60/150/300 s covers a stranded `/exit`.
- **Relaunch (watcher, B, A-husk, R, cc-resume-debt, boot-resume-launch):** each takes `locks/<sid>.launch` and requires, while holding it:
  - (a) `pane_cc_state=shell`;
  - (b) H(sid) empty;
  - (c) the identity tuple matches;
  - (d) the tombstone names this target;
  - (e) the recorded watcher (pid, lstart) is dead, or a `recycle-dead` row carrying **this attempt's nonce** exists. A missing watcher record counts as "alive" until `typed_at` + 600 + 180 + 60 s;
  - (f) no live launcher or `lr-fire-resume` for the sid.
  `lr-fire-resume` re-checks H(sid) immediately before the spawn.
- **Enter:** only on a DRAFT-MINE carrying this run's token, at most 3 re-sends, never while queued.
- **Engage prompt:** skipped if this attempt's token is already in a user record. A TARGET-TRANSIENT retry uses a **fresh** token, so the new prompt is not skipped.
- **Void / unassign:** keyed by id and safe to repeat.
- **Requests:** moved to `claimed/` with their outcome, never deleted. This fixes the `rm -f` at `lr-reset-poller.sh:866-869`.

### 7.4 Surfacing residue
Residue reaches the operator through:
- the OPEN, DELTA, CLOSE and immediate pages;
- `cc-lr status --cohort`;
- the readout line;
- the maximum-age pages;
- `cc-backlog needs`, for human residue only;
- an SLO page when a cohort is not fully CLOSED, or in named WAIT/HOLD **within its maximum ages**, 10 minutes after its last death.

---

## 8. Latency, 30-session cohort (from measured stages)

Measured tonight:

| Stage | Time |
|---|---|
| hook to marker | same second as the death |
| `ps` | 0.13 s |
| `kitty @ ls` | 0.07-0.08 s |
| slug-direct lookup for 30 sids | 0.015 s |
| `classify_tail` ×30 | 0.02 s |
| cached router | 0.44-0.66 s |
| memory probe | 0.63 s |
| bundle to painted | 20-27 s for one pane, 28-45 s at N=4 |
| first Enter lands | 2 of 6 cases |
| swallowed-Enter penalty | 32-43 s |
| submitted to engaged | 12-25 s |

**Time to OPEN and first dispatch:**
- **Warm cache:** kqueue 0.1 + debounce 1.5 + observe about 1.0 + place and probe 0.7 + commit 0.2, so about **3.5-5 s**.
- **Cache older than 600 s:** an immediate WAIT_DATA OPEN, then the plan about 8-22 s later (the fresh sweep's p50 and p90).

**Per pane in this design:**
- bundle and transplant: about 5 s. The per-pane admit section that took about 9 s tonight (03:04:19→03:04:28) is gone.
- arm plus the post-confirm read-back: about 3 s.
- shell detection: about 2 s.
- relaunch: about 7 s.
- boot: about 6-9 s. The hold from spawn to painted is **about 30-35 s** under concurrency.
- submit: 2 s when the first Enter lands. Otherwise 10-25 s on the new schedule, until W0 measures the real readiness signal.
- engage: 12-25 s.

**All 30 slotted (S ≥ 30), with B held at 6:**
- 5 waves × about 35 s + about 25 s submit + about 20 s engage ≈ **220 s (3.7 min)**.
- If B grows to 12 by wave 3: about 150 s.
- The per-account pacer (3 in flight per account, releasing at about 20 s cadence across 3 targets, so about 9 per 20 s) does not bind before boots do.
- The CPU brake binds only above the pre-limit operating load.
- **Published target: ≤5 minutes p95**, replaced by the W5 30-session rig's measured number.

**Deaths trickle in.** Tonight's two were 40.7 s apart, and next2's four spread over 14 minutes. A session that dies later becomes a DELTA and completes about 45-80 s after its own death, when a seat is available.

**Tonight's real capacity:**
- Open: only next4, with 5 seats (k_work 2 → 22 within 9 minutes after 4 placements).
- Excluded: next (kmax, k_work 18), next2 (5h rejected), next3 (7d rejected).
- With weights of about 5, one heavy mover or up to five light ones move.
- Everyone else is named at OPEN as WAIT_SLOT, with ETAs from the drain of k_work and next2's 06:30Z reset.
- next2's own sessions become stay candidates at 06:30Z.
- No design beats this without changing the KMAX policy, which is operator decision 8.

**Today, for comparison:**
- the manual `cc-lr` path took 115 s for 4 panes;
- 415a3aac took 20 min 05 s end to end;
- the poller path has held off auto-drain for 831 ticks, and REROUTE moves at most 4 per tick.

---

## 9. Token cost
- **Daemon, observer, planner, actuators, watchdog:** 0 model tokens.
- **Wire probe:** unchanged, about 25 quota tokens per sweep for accounts at ≥99% only. No probe is added.
- **LIMITED, fast path** (`lr-ingest-verify` rc 0): about 80 tokens of prompt, plus the unavoidable cold re-read of its own context on the new account (prompt caches do not cross accounts).
- **LIMITED with workflow gaps** (5 of the 25 verified bundles): the continue line plus a read of the audit's Gaps section. That is up to about 15K tokens if the session reads the whole 58 KB `audit.md`, which is still below the 26.5K ingest it replaces.
- **IDLE:** 0 at move time. It pays the cold re-read at the operator's next turn.
- **Stay and WAIT_RESET:** no cross-account re-read at all.
- **Requester:** one `cc-lr` call plus one cohort mail (about 150 tokens), instead of N mails and N wake-ups.

---

## 10. Safety invariants and how each is kept

| # | Invariant | Kept by |
|---|---|---|
| 1 | A teammate is never a recovery target | Parsed `is_teammate_head` in the census and the hook. The probe still refuses (`handoff-fire.sh:8452-8460`). No keystroke into members; a HELD:team lead is continued in place without `/exit`. |
| 2 | A lead with live members is never `/exit`ed without the team hold | HELD:team via `live_teammates_of` (`handoff-fire.sh:9097-9130`). The team unit is disabled in v1. *Corrected 2026-09-30 (D4.10), as built:* the hold keys on one shared live-member test, `lr_has_live_teammate <sid>` in `scripts/limit-recover/lr-team.sh` (W6d `4c3fc715f`), mirrored in the census; `live_teammates_of` (`handoff-fire.sh:6163`) is a self-close gate, and the old range was stale. The hold is unconditional in v1: there is no team-unit switch (`LR_TEAM_UNIT` was never read by any code). The lead is continued in its own pane at the reset (W6d `3ba89226e`; § 15). |
| 3 | Refusable reads come before the irreversible step; a refusal leaves nothing behind | The precheck, now with launcher-root and background-work checks. **After confirm**, the last read and the read-back, with UNCONFIRM restoring the pre-move state. |
| 4 | One actuator per session | One record per sid; `owned/` with procs; claims with (pid, lstart); the fence inside every entry function; transplant locks carrying a record id. |
| 5 | Exactly one live copy per uuid | Two-phase transplant; stub refusal; link-then-unlink renames; fold-stub into both copies; bg rows in H; the post-close sentinel with `claude stop`; the launch lock with the H re-check before spawn; `lr-fire-resume --force-split` refusal (`:339-352`). |
| 6 | Watcher first, `/exit` last | Unchanged, plus the per-pane recycle lock and the attempt nonce. |
| 7 | Never type over a foreign draft | The composer gate plus the post-confirm last read, `/exit` without Enter plus read-back, 5 backspaces only for our own `/exit`, the stash opt-in. *Corrected 2026-09-30 (decision 6):* no stash exists; the one exception is a ≤2-character stray composer on an unfocused pane, scrubbed with a receipt. |
| 8 | Typing only on an affirmative pane state; relaunch lines nonce-verified | `pane_cc_state` (`:4042`), `it2_type_verified` (`:2715`). |
| 9 | Enter only on DRAFT-MINE, never while queued; expect never exits | `lr-fire-resume` rules; only the re-send schedule changes. |
| 10 | Subagents are killed only for cause=limit | ALLOW_LIVE_SA forced only for limit (`:10582-10587`). Idle moves use `voluntary` and require zero subagents, workflow slots included. |
| 11 | Limit membership comes from `lr_predicate` only | Imported. The idle bypass is a separate, evidence-bound gate: `--voluntary --account-evidence F` where F is an uncontradicted account-wide fact with `resets_at > now + 30 min`. |
| 12 | Liveness is exact (pid, lstart) | Everywhere. Zombies are dead. Legacy holders are judged by argv. |
| 13 | Missing data is never headroom | k unmeasured, stale cache and DEGRADED census all mean 0 seats or no plan. |
| 14 | The wire only adds a refusal; the endpoint integer and usage 429s are never "limited" | C4, per window. |
| 15 | Recovery floors and the target walk | Inside `--place`, re-checked **per pick** with the cohort's burn. |
| 16 | rank → assign → probe is one decision | One pass, one process, one `--assign-many`; `admit.lock` with a holder for interop. |
| 17 | Every unattended gate is bounded | The reconciler-owned refusal counter with a drip; the B floor; the CPU-brake floor. |
| 18 | The admission token is one-shot, sid-bound, call-scoped | Unchanged; the `env -u` on the spawn line stays. |
| 19 | Verdicts fail closed | ENGAGED needs the token record plus a turn past `confirm_len` with the source dead. MOVED needs readiness. |
| 20 | `autorecover.on` is the operator's | It gates all daemon-origin actuation. PLAN-ONLY writes nothing that blocks manual tools. |
| 21 | No push, ship or deploy on the recovery path | The only git writes are the pool/* rename and `worktree add` under the git lock, plus HEAL if the operator enables it. |
| 22 | No `kickstart -k`, no flock(1), bash 3.2 on shell paths | The daemon uses python fcntl. The watchdog is bash 3.2. The poller's heredoc parse error is fixed. |
| 23 | The hook stays fail-open and append-only | Only atomic fact writes are added. |
| 24 | Ambiguity refused; group by where the session is now; `.claude` and `.claude-next` are one account | cc-find rc-2 semantics; `acct_now`; the store fold. |
| 25 | A parked record is retired only on successor proof | Stale reconcile: NOT_NEEDED only on target-side evidence or dead-before-claim. |
| 26 | Actuation only outside sessions | Only launchd jobs type. cc-lr writes requests. |
| 27 | No duplicate spawned over a live pane | R only on proven PANE-GONE that this reconciler caused, or on launcher-rooted panes; always under the launch lock. |
| 28 | **New:** the reconciler never picks "Move to background and exit" | `CC_RECYCLE_BGWORK_ANSWER=cancel`, `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` on relaunch, HOLD-BGWORK. |
| 29 | **New:** no irreversible step inside 30 s of a wake; clocks are sleep-aware | C2 clock, `LR_WAKE_GUARD_S`. |
| 30 | **New:** every lock has a holder that can be stolen from the dead | C7 lock pattern. |

---

## 11. File-level change list

**New**
- `scripts/limit-recover/lr_recon/{__main__,clock,observe,facts,phase,plan,admit,act,store,fence,report}.py` and `lr_recon/tests/`.
- `scripts/limit-recover/lr-recon-fence.sh`, the bash fence predicate and lock helpers.
- `scripts/limit-recover/lr-recon-watchdog.sh`, standalone.
- `scripts/limit-recover/com.reso.lr-reconciler.plist`, `com.reso.lr-reconciler-watchdog.plist`, `com.reso.lr-reconciler-rig.plist` (rig root, rig-tagged panes only).
- `tests/rig/{stub-claude.py, lr-recon-rig.sh, faults/*.json}`, and bats suites `tests/lr-recon-phase.bats`, `tests/lr-transplant-custody.bats`, `tests/lr-recon-fence.bats`, `tests/lr-launch-lock.bats`.
- State tree `~/.reso/limit-recover/recon/{sessions,owned,facts,cohorts,plans,shadow,quarantine,ctl}/`, `events.jsonl`, `launch.log`, `heartbeat`, `restarts.jsonl`, `reconciler.lock`, `mode`; `recon.on` (the cutover); `autorecover.on` (the operator's).

**`bin/claude-accounts`:** `--place`, `--kwork`, `--facts`, `--assign --id --sid --w --ttl-s`, `--assign-many`, `--unassign`. Void rows kept in `_assignment_rows` (`:2372`); `assignment_counts` weights, voids and ttl (`:2381-2396`); prune under the lock (`:2447-2455`); per-account sid sets in the sweep cache (`working_concurrency` `:790-859`); `apply_assignments` dedupe by sweep time (`:2520-2536`); a real `--max-wait` bound in `get_data` (`:4361`); the `RECOVERY_IDLE_SEATS` knob. The keep-warm interval is **unchanged**, to avoid more usage-endpoint 429s.

**`scripts/lib/capacity-admit.sh`:** `CC_ADMIT_RESTORE_R` in the active term (`:1352-1365`); unredeemed tokens counted as active; the TTL message reads the derived value.

**`scripts/limit-recover/lr-lib.sh`:** `:376` `break 3` becomes `break 2`, and the phantom scan becomes a single pass.

**`scripts/limit-recover/lr-transplant.sh`:**
- confirm stub refusal and link-then-unlink rename (`:176-239`);
- a lock-and-record assertion in confirm;
- `confirm_len` in the receipt;
- `--record-id` plus the lock holder, and same-target idempotence keyed on it (`:300-328`);
- new phases `unconfirm`, `fold-stub`, `abort`;
- `cp -c -p` falling back to `cp -p` (`:210`, `:480`).

**`scripts/limit-recover/lr-lock.py`:** stub plus `.handed-off` classifies as CUSTODY.

**`scripts/limit-recover/lr-handoff.sh`:**
- `--record-id`, `--attempt`, `--account-evidence`, `--no-prompt`;
- an evidence bypass in the voluntary fail-fast (`:480-497`);
- skip `lrh_target_routable` when `LR_PLACED_BY=reconciler` (`:928-957`);
- `LR_ADMIT_TOKEN_PATH` (`:1036-1058`);
- `LR_PRESEED_DONE` (`:1118`);
- the launcher's continue-prompt branches (`:1231-1258`);
- export `HF_WATCHER_RECORD` and `HF_RECYCLE_ATTEMPT`, and pass `--record-id`;
- conditional success text (`:1333`);
- the git lock around `switch -C` only, after the sibling's fix to `:579-599` lands.

**`scripts/handoff-fire.sh`:**
- probe (`:8370-8519`):
  - `--voluntary --account-evidence F` as the only alternative to the limit gate (`:8438-8447`);
  - emit `pane_root tty window_id kitty_pid kitty_lstart bg_work`;
  - parsed teammate test;
  - a background-work refusal `HELD:bg-work`;
- `live_subagents_of` also globs `subagents/workflows/*/agent-*.meta.json` (`:5507-5510`);
- `emit_recycle_event` rows gain `attempt`, `watcher_pid`, `watcher_lstart` (`:863-888`);
- `HF_WATCHER_RECORD` written at detach (`:1708-1716`, `:13413`);
- the fence call and the per-pane recycle lock in `recycle_fire` (`:13132`);
- the last read moved after confirm for every class, with an UNCONFIRM call on refusal (`:13436-13536`);
- `/exit` without Enter plus read-back, and the blind anti-strand Enter deleted (`:13552-13570`);
- `--husk` (skip confirm);
- `--relaunch-at-shell` reusing `:7590-7911`;
- FOLD replaces the `.handed-off`-only fold (`:7598-7606`);
- the watcher takes the launch lock before typing;
- the shell poll goes from 3 s to 1 s;
- the background-work cancel path signals UNCONFIRM through its row;
- `LR_WAKE_GUARD_S` checked before confirm and `/exit`.

**`scripts/limit-recover/lr-fire-resume.sh`:**
- assert the launch lock and re-check H(sid) before `spawn` (`:883-885`), and rewrite the holder to the claude process;
- `--no-prompt`;
- `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` on the spawn env;
- `LR_CLAUDE_BIN` for the rig;
- the re-send schedule from `LR_RECR_SCHEDULE`, default `10,25,40` (`:1094-1133`);
- `LR_PRESEED_DONE` (`:374`);
- `worktree prune` dropped and the git lock put around `worktree add` (`:357-360`).

**Terminal plumbing:**
- `bin/it2-kitty`: `prove_target` via `ls --match id:N` plus a kitty-pid check (`:476-484`).
- `bin/cc-kitty-socket`: `--all`.
- `hooks/session-register.sh`: records `KITTY_LISTEN_ON` and the kitty pid (`:349-357`).

**`hooks/stop-failure-marker.sh`:** fact writes (window, model, fable, auth) under `recon.on`; parsed teammate test (`:389-400`).

**`scripts/limit-recover/lr-reset-poller.sh`:**
- per-sid fence calls in §0 (`:752-925`), §2a (`:1372-1430`), §2 and nudge (`:1432-1668`, `:652-670`);
- SUPERSEDED moves to `claimed/` (`:866-869`);
- replace the `<(python3 - <<PY` sites at `:1091` and its siblings with temp files;
- nudge stderr kept (`:659`);
- the backup watchdog with a 15-minute re-page;
- **not** `run_claim_take` or the autorecover drain, which belong to the sibling.

**Other scripts:**
- `bin/cc-lr`: per-origin request writer when the fence is live (`:356-418`, `:466-479`); `status --cohort`, `accounts --limited` (on cc-limited's grouping), `cohort refire`.
- `bin/cc-resume-debt`: fence, launch lock, H re-check, in-pane preference (`:118-128`, `:212-224`).
- `scripts/limit-recover/lr-fleet.sh`: fence in `lf_one` (`:865`); `--enqueue` writes `<sid>.cc-lr.json` (`:1432-1462`).
- `scripts/limit-recover/lr-upgrade.sh`: fence in the drive and switch functions (`:817-870`, `:1286-1292`).
- `scripts/boot-resume-launch.sh`: launch lock; shell root (`zsh -ic '<launcher>; exec zsh -i'`); honours PARKED-REBOOT.
- `hooks/operator-readout.sh`: one counted line.
- `scripts/launchd-parity-lint.sh`: add `com.reso.lr-reconciler*` to the scope.
- `docs/plans/LIMIT_RECOVER_100P.md`: new section, integrated, not overwritten.

---

## 12. Rollout
Rollout is in the implementation plan. It runs W0 measurement, then W1-W4 builds, then W5 gates: the 5- and 30-session synthetic rig, real canaries, and an OBSERVE-mode shadow over 2 cohorts. After that it cuts over by writing `recon.on` with `mode=act`. Zero-human recovery then needs only the operator's `autorecover.on`. HEAL stays off until the operator rules on it.

*As built after W6 (2026-09-30):* the reconciler acts on a non-cc-lr (hook- or census-origin) record only when BOTH `~/.reso/limit-recover/autorecover.on` and its own `recon/autorecover.on` exist (D1.9, W6d `f8f1e07ea`; the daemon never creates either). The operator creates the second only after the first attended reconciler cohort closes clean (D1.14). `autorecover.on` stays the single zero-human switch for the legacy lanes: the poller's hook requests and `reroute_parked` both check it (`lr-reset-poller.sh:1070`, `:1834`). Decision 5 is settled "allow": the legacy heal `lr_heal_bare_checkout` runs under `LR_BARE_REPAIR` (`b509a51f4`), and the reconciler's own HEAL actuator stays off unless `LR_HEAL_CORE_BARE=on` (`lr_recon/act.py:459`).

## 13. Grafts rejected, and why
- **`lr-upgrade --switch-drive` for idle moves.** It submits `Run in Bash now: cc-lr switch …` (`lr-upgrade.sh:789-791`), which needs a turn on the rejected account.
- **A SQLite ledger.** It creates two stores that can disagree. A file per sid with `owned/` gives the same invariant.
- **Dropping the active ceiling wholesale.** Replaced by the frozen restore budget.
- **Runner-owned respawn in v1.** It covers 0 of the 14 live wrappers. It stays a phase-2 option under its four conditions.
- **Retiring the launchd typing gate.** Revision 1 did this on evidence that was only serial and same-account. Revision 2 keeps the gate for cross-account and concurrent moves until the W5 canaries pass.
- **Keep-warm interval ≤90 s (skeptic, cold-cache finding).** Rejected: it would roughly double polling of an endpoint that has already throttled 1,643 times. Replaced by cache-grace placement, the fact overlay, the reconciler's own k_work, and daemon-triggered background sweeps during ACTIVE only.
- **Typing a continue prompt into limited teammates at reset (skeptic, team finding).** Modified: that would drive a lead-owned session. The lead is continued in place, where no `/exit` means no team cleanup. Members are verified and named, never typed into.

## 14. Residual risks
- **Account seats are the real bound on "all at once."** Subagent-heavy sessions cost about 5 seats each. The design makes the shortfall visible within seconds, but it cannot beat KMAX.
- **Screen-scraped oracles** (composer, DRAFT-MINE, the background key, read-back) are tied to terminal width and CC version. They classify as TRANSIENT or HOLD, never as a blind keystroke.
- **The background-shell detector** (a shell `-c` child of an at-rest claude) is validated in W0. A false negative still meets the Esc-and-UNCONFIRM backstop.
- **Boot storms at load 40-60.** AIMD reacts only after the first slow wave.
- **`/goal` survival across a limit** is measured in W0. A lost goal is flagged after ENGAGED, not re-armed, in v1.
- **The reconciler is a single orchestrator.** It is mitigated by KeepAlive, the standalone watchdog, adoption, evidence-derived state, fences that hold for live processes and lapse for dead ones, the resume-debt backstop, the fixture matrix and the shadow phase.
- **HOLD-DRAFT, HOLD-BGWORK and HELD:team need the operator or a reset by design.** The operator decisions set that policy.

## 15. Team leads: the v1 hold and wake as built, and the v2 move (decision 4, ruled 2026-09-30)

**v1, as built.** A LIMITED lead with live members is HELD:team on every lane, decided in the census before placement runs (`lr_has_live_teammate`, `scripts/limit-recover/lr-team.sh`, W6d `4c3fc715f`). Decision 3 now always waits, so the hold overrides nothing in it (lead resolution 6 corrects D4.11). Nothing sends it `/exit` or relaunches it. The two wakes, one text (a plain `continue`, lead resolution 2), both behind `lr_focus_gate` (lead resolution 1):
- **Reconciler** (`act.cmd_wake`, W6d `3ba89226e`): at reset + 120 s + the sid's 0-60 s jitter, paced per account by `Admission.pace_wake`, only while the source has headroom, members are still live and the pane is at a claude prompt, once per reset. It types through `cc_tui_submit`, which refuses an occupied composer (rc 3). A fresh non-error turn after the reset closes the record CLOSED via IN-PLACE. A failed submit pages once (WAKE-FAILED) and is never retyped; the HELD:team page at reset + 10 min stays. A HELD:team record opens only for a LIMITED lead.
- **Hook lane** (`nudge_in_place`, W6b `17fbdee45`): at reset + `LR_NUDGE_AFTER_RESET_S` (120 s) plus a 0-90 s per-sid jitter, and only if no assistant turn has appeared since the reset (`lr-reset-poller.sh:782-796`); held leads route to the parked lane and stay out of the latch-expiry resume arm (D4.8).

**v2: the cross-account team move, not built** (D4.15). It needs a two-account throwaway-team probe first. Prerequisites and hazards:
- Move the members first: they inherit the lead's `CLAUDE_CONFIG_DIR`, and were limited in the same tick as their lead in all 5 poller-log pairings.
- Team dirs and inboxes are per config dir, so copy the team dir to the target account, and set `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME`.
- Accept the vendor's deaf-lead limit.
- On 2.1.284, cleanup kills only panes the exiting process spawned, but always deletes the team dir it registered.
- A `--resume`d lead registers a new, empty team (13 of 13 observable), which explains 8ad3a9d2's lost team on 08-18.
- A lead message that reaches a limited member before the member's reset is spent.
- Dialog rows and `config.json` keep members that have already exited. Before relying on either, send each member a `shutdown_request` and wait for its `shutdown_approved`, or `TaskStop` it.
