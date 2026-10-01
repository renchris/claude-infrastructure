---
status: in-progress
---

# Implementation plan: lr-reconciler (pane-in-place parallel limit recovery), revision 2

**Scope (frozen):** Pane-in-place parallel /limit-recover for every limited pane, in three steps:
- (a) identify limited accounts, per (account, scope);
- (b) map every live pane on them;
- (c) recycle each pane in place onto a placed account, concurrently.

A closed loop detects and re-fires every non-completion, and no human is needed once `autorecover.on` exists. **Excluded:** raising KMAX, moving whole teams across accounts (v2), driving iTerm2 in place (it is HOLD), and the three fixes the sibling session owns.

Architecture: the revision-2 architecture delivered with this plan. On landing, it is integrated into `docs/plans/LIMIT_RECOVER_100P.md` as a new section, and nothing existing is deleted. Repo: `/Users/chrisren/Development/claude-infrastructure`. Line anchors were taken near `097255b53`; each wave re-greps them before it edits.

---

## Phase 0: Agent Team Orchestration

### Execution locus per wave (first field)

| Wave | Locus | Why (needed only for T/L) |
|---|---|---|
| W0 measurement and fixtures | **S** | — |
| W1 router and admission | **S** (3 teammates inside) | — |
| W2a transplant custody and lr-handoff | **S** (2 teammates inside) | — |
| W2b handoff-fire | **S** (2 **sequential** teammates inside, because both edit one file) | — |
| W2c resume and terminal plumbing | **S** (2 teammates inside) | — |
| W3 `lr_recon` package | **S** (sub-wave W3a: 6 teammates, then sub-wave W3b: 5 teammates) | — |
| W4 fences and operator surfaces | **S** (3 teammates inside, split by file ownership) | — |
| W5 rig, canaries, shadow, cutover | **S**, plus one filed operator step (loading the launchd jobs) | — |
| W6a handoff-fire + lr-handoff ruling fixes | **S** | — |
| W6b poller + lr-fleet ruling fixes | **S** | — |
| W6c router ruling fixes | **S** | — |
| W6d reconciler + page channel ruling fixes | **S** | — |
| W6e architecture/design doc corrections to as-built | **S** | — |
| W6f flip `LR_MOVE_FOCUSED` default to on | **S** (small; gated on W6a+W6d green) | — |

No wave runs as T or L on the lead. The W6 rulings section and its evidence note are written by the lead inline (doc-only synthesis of a workflow the lead ran; no code).

### Lead context budget and succession
- The lead keeps at least 50% of its window free for decisions.
- Each wave returns one notify-back ping and one printed DoD line, and the lead reads nothing else from it.
- Succession point: 60% fill, or the end of W3, whichever comes first. Succession is by `handoff-fire.sh --recycle`, with this plan document as the state.
- W3 is the largest wave and must never run on the lead.

### Prerequisite owned by the sibling session (do not duplicate)
The sibling session owns three fixes:
- (1) the fatal git read in `lr-handoff.sh:579-599`;
- (2) holder-less `run_claim_take` (`lr-reset-poller.sh:721-745`);
- (3) the `autorecover.on` drain with drain-time re-validation.

Each wave starts with `git -C ~/Development/claude-infrastructure log --oneline origin/main -- scripts/limit-recover/lr-handoff.sh scripts/limit-recover/lr-reset-poller.sh` to find the sibling's landed shas.
- Until they land, W2a does not touch `lr-handoff.sh:579-599`, and W4 does not touch `run_claim_take` or the §0 drain gate.
- W3's stale reconcile imports the sibling's re-validation function by name, found by grepping the landed poller. If that function has not landed when W3 needs it, W3 writes a local predicate carrying the same contract and a TODO naming the sibling's function, and W4 swaps the call.

### Shared-file owners (one owner per file per wave)

| File | Owner |
|---|---|
| `bin/claude-accounts` | W1 teammates T-place and T-ledger, split by function range |
| `scripts/lib/capacity-admit.sh`, `lr-lib.sh` | W1 T-admit |
| `lr-transplant.sh`, `lr-lock.py` | W2a T-custody |
| `lr-handoff.sh` | W2a T-handoff, excluding `:579-599` |
| `handoff-fire.sh` | W2b only (T-probe, then T-recycle) |
| `lr-fire-resume.sh` | W2c T-resume |
| `bin/it2-kitty`, `bin/cc-kitty-socket`, `hooks/session-register.sh` | W2c T-terminal |
| `scripts/limit-recover/lr_recon/**`, `lr-recon-fence.sh`, `lr-recon-watchdog.sh`, plists | W3 |
| `hooks/stop-failure-marker.sh`, `lr-reset-poller.sh` | W4 T-producers |
| `bin/cc-lr`, `bin/cc-resume-debt`, `lr-fleet.sh`, `lr-upgrade.sh`, `boot-resume-launch.sh` | W4 T-actors |
| `hooks/operator-readout.sh`, `scripts/launchd-parity-lint.sh`, plan doc | W4 T-surface |
| `tests/rig/**` | W5 |
| W6: `handoff-fire.sh`, `lr-handoff.sh`, `lr-lib.sh` + their bats | W6a |
| W6: `lr-reset-poller.sh`, `lr-fleet.sh`, `lr-upgrade.sh`, `hooks/stop-failure-marker.sh`, `lead-supervisor.sh` + their bats | W6b |
| W6: `bin/claude-accounts` + its bats | W6c |
| W6: `lr_recon/**`, new `scripts/limit-recover/lr-page.sh`, `tests/rig/**` (shared with W5b: W6d messages pane 1308 before editing rig files) | W6d |
| W6: `docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md`, `~/.reso/limit-recover/design-v2/*` | W6e |
| W6: this plan's W6 section and rulings | lead |

### Interface contract (frozen in Phase 0; W3 builds against it while W1/W2 build it)
- **claude-accounts:**
  - `--place --lane L --recovery --movers FILE --facts DIR --kwork FILE --json` returns `{sid:{acct|null,reason,eta_s,weight}}`. Exit 0 means a plan; exit 3 means WAIT_DATA.
  - `--assign ACCT --id ID --sid S --w N --ttl-s T`, `--assign-many FILE` (JSONL of the same fields), and `--unassign ID`.
- **capacity-admit:** env `CC_ADMIT_RESTORE_R=<int>`. Unredeemed tokens count as active.
- **lr-transplant:**
  - `--phase confirm|unconfirm|fold-stub|abort --record-id R`;
  - the confirm receipt adds `confirm_len`;
  - rc 2 reasons are `stub-beside-retired`, `lock-mismatch`, `target-held`, `stub-present`, `source-dead`.
- **lr-handoff:** new flags `--record-id --attempt --account-evidence F --no-prompt`. Env: `LR_PLACED_BY LR_ASSIGN_ID LR_ADMIT_TOKEN_PATH LR_PRESEED_DONE HF_WATCHER_RECORD HF_RECYCLE_ATTEMPT LR_WAKE_GUARD_S CC_RECYCLE_BGWORK_ANSWER`.
- **handoff-fire:**
  - the probe accepts `--account-evidence F` with `--voluntary`, and its output adds `pane_root tty window_id kitty_pid kitty_lstart bg_work` plus a `HELD:bg-work` verdict;
  - new `--recycle --husk` and `--relaunch-at-shell`;
  - watcher rows add `attempt watcher_pid watcher_lstart`;
  - `HF_WATCHER_RECORD` = `{pid,lstart,attempt,pane,sid,armed_at}`.
- **lr-fire-resume:** `--no-prompt`. Env: `LR_LAUNCH_LOCK LR_CLAUDE_BIN LR_RECR_SCHEDULE`.
- **Locks:** `locks/<sid>.launch/holder`, `locks/pane-<sha1>.recycle/holder`, `locks/git-<sha1>/holder`. Each holder is `{record_id,attempt,role,pid,lstart,at}`.
- **Fence:** `lr_recon_defers <sid>` returns rc 0 for defer and rc 1 for act.

### Dependency graph

```
sibling(1)(2)(3) ──────────────┐
W0 ──┬── W1 ───────────┬── W3a ── W3b ──┐
     ├── W2a (after sibling(1) for the git hunk only)
     ├── W2b ──────────┤                ├── W4 ── W5
     └── W2c ──────────┘                │
W1+W2a+W2b+W2c land ─────────────────────┘ (W3b's integration tests need them)
```

- W1, W2a, W2b and W2c run in parallel after W0.
- W3a can start once W1 lands, against the frozen contract.
- W3b's integration suite waits for W2*.
- W4 waits for W3b.
- W5 waits for W4.

### Team roster and sizing (≤300 LOC and ≤2,000 LOC read per teammate; split anything larger)

| Wave | Teammates (output LOC estimate) |
|---|---|
| W1 | T-place (`--place` + `--kwork`/`--facts` + per-pick floors, ~300) · T-ledger (id/void/ttl/assign-many/prune lock/sweep sid sets/max-wait, ~220) · T-admit (capacity-admit restore budget + tokens-in-flight + TTL message; lr-lib break fix and single pass, ~150) |
| W2a | T-custody (confirm refusal and link-then-unlink rename, unconfirm, fold-stub, abort, record-id lock holder, cp -c; lr-lock CUSTODY, ~280) · T-handoff (flags, evidence bypass, placed-by skip, token path, preseed, continue-prompt branches, watcher-record export, success text; git lock after the sibling lands, ~250) |
| W2b | T-probe (evidence bypass at the limit gate, identity/root/bg output, parsed teammate test, workflows glob, row nonce fields, watcher record, ~220), **then** T-recycle (fence call, per-pane recycle lock, post-confirm last read + unconfirm, `/exit` read-back, blind Enter removed, `--husk`, `--relaunch-at-shell`, FOLD call, launch lock in the watcher, 1 s shell poll, wake guard, ~300) |
| W2c | T-resume (launch-lock assert + H re-check, `--no-prompt`, agent-view env, `LR_CLAUDE_BIN`, re-send schedule, preseed, prune removed + git lock, ~200) · T-terminal (it2-kitty `--match` + kitty pid, cc-kitty-socket `--all`, session-register `KITTY_LISTEN_ON`, ~120) |
| W3a | T-store (records, owned fence file, claims, lock pattern, legacy-holder rule, events/launch log) · T-clock (sleep-aware clock, wake guard, caffeinate) · T-observe (sockets, ps tree, bg rows, slug-direct lookup, bg-shell detector, DEGRADED) · T-facts (scopes, expiry, contradiction, auth, `accounts --limited` data) · T-phase (pure `derive_phase` + fixture loader) · T-fence (`lr-recon-fence.sh` + python mirror) |
| W3b | T-plan (cohorts, `--place` driver, WAIT/ETA, stay/reset transitions, phantoms refresh/void) · T-admit (frozen R, CPU brake, per-account pacer, refusal counter + drip, AIMD B) · T-act (actuator spawn/adopt, intent nonce, env, UNCONFIRM/FOLD/ABORT/SPLIT dispatch, classification + re-arm) · T-report (pages OPEN/DELTA/CLOSE/max-age, cohort status JSON, readout line data) · T-main (loop, modes, heartbeat thread, startup order, quarantine, watchdog script, 3 plists) |
| W4 | T-producers (hook facts + parsed teammate test; poller fences, SUPERSEDED to claimed, heredoc fix, nudge stderr, backup watchdog re-page) · T-actors (cc-lr request writer + status/accounts/refire; cc-resume-debt fence/lock/in-pane; lr-fleet `lf_one` fence + enqueue file; lr-upgrade drive fences; boot-resume-launch lock + shell root + PARKED-REBOOT) · T-surface (operator-readout line, launchd-parity-lint scope, plan-doc section) |

Every teammate brief follows the agent-teams pre-spawn checklist:
- ≤150 lines;
- line ranges pre-grepped;
- no visual verification;
- the clause "Stop on issue, message lead", verbatim;
- coding conventions embedded;
- no "investigate/explore/audit" wording.

### Kill switches (all default to the safe side)
- `recon.on` absent, or `recon/mode` = `observe|plan`: no actuation.
- `LR_RECON_WORKERS` (default 16) and `LR_BOOT_MAX` (default 12).
- `LR_IDLE_FANOUT=off` disables idle moves.
- `LR_DRAFT_STASH`: **not built; nothing reads it** (corrected 2026-09-30, decision 6 ruled off: the stash existed only in doc prose).
- No team-unit switch: HELD:team is unconditional in v1 (corrected 2026-09-30, D4.10: the `LR_TEAM_UNIT=off` listed here was never read by any code).
- `LR_HEAL_CORE_BARE=off` (default). Decision 5 is settled "allow" for the legacy heal, which runs under `LR_BARE_REPAIR` (`b509a51f4`); the reconciler's own HEAL actuator stays off unless `=on` (`lr_recon/act.py:459`).
- **`~/.reso/limit-recover/autorecover.on` is the single zero-human switch** (decision 1, ruled 2026-09-30). Absent, the poller drains no hook-origin request and `reroute_parked` moves nothing (`lr-reset-poller.sh:1070`, `:1834`). The reconciler acts on a non-cc-lr record only when its own `recon/autorecover.on` also exists (D1.9, W6d `f8f1e07ea`); the operator creates that one after the first attended reconciler cohort closes clean (D1.14). No daemon creates either file.
- `LR_POLLER_REROUTE=off` disables the poller's unattended reroute of parked sessions (`lr-reset-poller.sh:1832`; W6b `fe39ee835`).
- `LR_REQUEST_MAX_PER_TICK` (default 4) caps hook-lane dispatches per account per poller tick; the overflow stays queued and the page names the queue depth and ETA (`lr-reset-poller.sh:985`, `:1294-1299`; W6b).
- `LR_MOVE_FOCUSED` defaults off (a focused LIMITED pane is held) until W6f flips it to on; after the flip, `=off` is the kill switch (decision 7).
- `CC_RECYCLE_BGWORK_ANSWER` is forced to `cancel` for reconciler actuations.
- `LR_RECR_SCHEDULE` (default `5,15,30,45`, measured by W0 item 1; the placeholder was `10,25,40`).
- `LR_AUDIT_RESUME_PREDICT=off` (W4-wf; default on): lr-audit stops predicting Workflow resume re-spend and offers the old plain resume.
- `LR_LAUNCH_GUARD=off` skips `lr-fire-resume`'s launch lock and H(sid) re-check (W2c; on by default).

### Operator steps (filed with `cc-backlog needs`, one command each)
1. **W5:** load the rig job, then the real reconciler and watchdog jobs: `bash /tmp/lr-recon-launchd.sh --confirm lr-reconciler`. The script runs `plutil -lint`, installs the plists from their repo SSOT, runs `launchctl bootstrap gui/$UID`, and verifies with `launchctl print` plus a fresh heartbeat read.
2. The decisions listed in the operator-decision set: `autorecover.on`, background-work policy, HEAL, and the rest.

---

## W0: measurement, fixtures, rig assets (S, read-only on real sessions; throwaway panes only)

**Targets:** none edited. Writes `docs/research/lr-recon-w0-2026-09-29/*` and `tests/fixtures/lr-recon/*`.

**Measurements (each with its command and raw output saved):**
1. **Readiness to accept Enter.** For all 25 verified bundles plus a 10-pane throwaway drill, measure paint→first-accepted-Enter from bundle `events.jsonl` (`composer-painted`, `SUBMIT-RECR`, `submitted`). Output: p50/p90, and the recommended `LR_RECR_SCHEDULE`.
2. **No-prompt `claude --resume` of a throwaway session.** Does it write to the transcript within `KWORK_WINDOW_MIN`? The answer (mtime and line count before and after) decides `RECOVERY_IDLE_SEATS`.
3. **Background-work dialog.** On a throwaway session holding a `run_in_background` sleep, compare `/exit` with and without `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`: capture the screen and record what `pane_bgwork_key` returns. Also validate the background-shell detector (a shell `-c` child of an at-rest claude) against every live pane's children, read-only through `ps`.
4. **Launchd socket discovery.** Run `cc-kitty-socket` and a kitty-sockets enumeration under `env -i PATH=/usr/bin:/bin`, and list every `/tmp/kitty-*` owner.
5. **`/goal` across a limit.** Read-only scan of limited transcripts for goal records before and after `blocking_limit`.
6. **Fixtures for `derive_phase`.** Extract the incident rows: 2026-09-19 (the 5-attempt cohort), 09-24 (3d42fa49), 09-27 (751, 815, 18e3fd78, 798afadf, and the 810/812/814/782 switches), 09-28 (405, 906), and 09-29 (946, 947, the 04:17 four-pane cohort).
7. **Rig assets.** Capture the CC 2.1.114 composer frame, the background-work dialog frame and the resume menu frame as screen fixtures, and pick real JSONL record shapes: death with `quotaLimits`, user prompt, assistant turn, api error 529, `authentication_failed`.

**Goal:** `W0 artifacts complete — proven by 'ls docs/research/lr-recon-w0-2026-09-29/ tests/fixtures/lr-recon/ | wc -l' printing >= 12 and 'cat docs/research/lr-recon-w0-2026-09-29/SUMMARY.md' showing a measured value for each of the 7 items; do not type into any pane you did not create in this session; full brief in the prompt above, DoD at docs/plans/LIMIT_RECOVER_100P.md`

**DoD:** SUMMARY.md prints all 7 results with numbers, and the fixture count is ≥30 rows across ≥12 incidents.

---

## W1: router and admission (S; teammates T-place, T-ledger, T-admit)

**Targets:**
- `bin/claude-accounts`: `_assignment_rows :2372`, `assignment_counts :2381-2396`, `record_assignment :2426`, prune `:2447-2455`, `apply_assignments :2520-2536`, `_su_projected ~:2538`, `k_cap :2335-2337` (read-only reference; the new path bypasses it), `_excluded :3575-3645`, `score_general :3647`, `score_fable :3896`, `KF :1910`, `working_concurrency :790-859`, `get_data :4351-4393`, CLI dispatch `:6216-6233`.
- `scripts/lib/capacity-admit.sh`: `:1352-1365`, mint `:680`, TTL `:906-918`.
- `scripts/limit-recover/lr-lib.sh`: `:358-381`.

**Acceptance tests:**
- `tests/claude-accounts-place.bats` (or python unittest), with these cases:
  - (a) a `panes`-charged snapshot never yields more than `KMAX − live` seats per account, and never 40−k;
  - (b) `kwork` None gives 0 seats and the reason `k-unmeasured`;
  - (c) a fact file sets capacity 0 for its scope only (a `model:opus` fact leaves fable-lane movers unaffected);
  - (d) weights: a w=5 mover consumes 5 seats;
  - (e) per-pick floors: the 7th mover onto a 0.45-5h account with `b_sess` 7 pp/h is refused with reason `recovery-5h-thin`;
  - (f) spread: 12 equal movers over 3 equal accounts give 4/4/4;
  - (g) a source whose fact has expired is chosen (stay);
  - (h) walk-past: the source, `none`, unmapped names, and stores holding the sid are all skipped;
  - (i) void rows survive `_assignment_rows`, and `ttl_s` expiry works;
  - (j) `--max-wait 2` on a held lock returns within 2.5 s with exit 3.
- `tests/capacity-admit-restore.bats`: R frozen (a later spawn is refused a restore); tokens in flight counted; the probe does not spend the budget.
- `tests/lr-lib.bats`, new case: phantom count > 1 with 3 corpses.

**Goal:** `W1 landed and live — proven by 'bats tests/claude-accounts-place.bats tests/capacity-admit-restore.bats tests/lr-lib.bats' printing 0 failures and '~/.claude/scripts/wrap-ledger.sh --machine' showing LIVE_ADDS=0 after 'bash scripts/deploy-live.sh'; do not change KMAX or any accounts.json value; full brief above, DoD at docs/plans/LIMIT_RECOVER_100P.md`

---

## W2a: transplant custody and lr-handoff (S; T-custody, T-handoff)

**Targets:**
- `lr-transplant.sh`: confirm `:170-240` (glob `:176-179`, cp `:211`, mv `:236-238`), admit idempotence `:300-328`, cause parse `:54-59` (unchanged), cp `:210`, `:480`.
- `lr-lock.py`: its ABANDONED classifier.
- `lr-handoff.sh`: `:480-497`, `:928-957`, `:1036-1058`, `:1118`, `:1231-1258`, `:1287-1331`, `:1333`. Plus `:584-589` for the git lock only, and only after the sibling's sha lands.

**Acceptance tests:** `tests/lr-transplant-custody.bats`, driving a temp config pair:
1. Confirm with a stub beside `.handed-off` gives rc 2 `stub-beside-retired`, and `.handed-off` is byte-identical afterwards.
2. Confirm's rename never overwrites an existing file (planted destination, rc 2).
3. Unconfirm restores `<sid>.jsonl` and removes the target copy into evidence.
4. Unconfirm with a stub present gives rc 2 `stub-present`.
5. Fold-stub appends to both copies, and sha(target) == sha(retired).
6. Fold-stub when the target has advanced gives rc 2.
7. Same-target admit with a different record id and a live holder is refused.
8. ABORT with a live recorded holder is refused.
9. `lr-lock.py` classifies stub+retired as CUSTODY past the TTL.

`tests/lr-handoff-flags.bats` covers the evidence bypass (a valid fact passes, a missing or expired fact is refused), the continue-prompt branches (rc 0, A1, A2, other), and the conditional success text under `LR_INPLACE_AWAIT=0`.

**Goal:** `W2a landed and live — proven by 'bats tests/lr-transplant-custody.bats tests/lr-handoff-flags.bats tests/lr-handoff-launcher-quoting.bats' printing 0 failures and LIVE_ADDS=0 after deploy-live; do not edit lr-handoff.sh lines 579-599 before the sibling session's fix is on origin/main; full brief above`

---

## W2b: handoff-fire (S; T-probe, then T-recycle, sequential)

**Targets (re-grep first):**
- probe `:8370-8519` (limit gate `:8438-8447`, teammate `:8452-8460`, composer `:8490-8516`);
- `live_subagents_of` `:5507-5510`;
- `emit_recycle_event` `:863-888`;
- watcher detach `:1708-1716`;
- `recycle_fire` `:13132-13579`: composer gate `:13235-13292`, arm `:13413-13430`, freshness `:13436-13449`, same-account rest `:13477`, confirm `:13492-13536`, debt `:13536-13551`, `/exit` `:13552-13570`;
- watcher `__recycle` `:7395-7911`: shell wait `:7416`, bgwork `:7452-7489`, fold `:7598-7606`, boot `:7699-7785`, engage `:7850-7884`;
- `--transplant-cause` `:9603-9607` (unchanged);
- `ALLOW_LIVE_SA` `:10582-10587` (unchanged).

**Checkpoint:** T-probe's commit lands and its bats pass before T-recycle is spawned.

**Acceptance tests (`tests/handoff-fire-recycle-custody.bats`, using the existing it2 stubs):**
1. The probe with `--voluntary --account-evidence` passes a healthy pane and refuses one without evidence.
2. The probe reports `HELD:bg-work` for a stubbed bg child.
3. A workflow meta file is counted by `live_subagents_of`.
4. Watcher rows carry `attempt` and `watcher_pid`.
5. A second `recycle_fire` on the same pane while the first watcher's holder lives is refused.
6. **Last read after confirm:** a composer stub that turns non-empty after confirm leads to an UNCONFIRM call, no `/exit` typed, and a HOLD row.
7. `/exit` read-back mismatch: exactly 5 backspaces, then UNCONFIRM.
8. The blind second Enter is gone (grep assertion plus a stubbed `as_write` call count of 1).
9. `--husk` never invokes confirm.
10. `--relaunch-at-shell` refuses while the launch lock is held by a live holder and while H(sid) is non-empty.
11. FOLD is invoked instead of the `.handed-off`-only append.
12. A background-work dialog under `CC_RECYCLE_BGWORK_ANSWER=cancel` sends Esc and emits `recycle-held-bgwork`.
13. The wake guard: a fake `kern.waketime` 10 s ago defers confirm.

**Goal:** `W2b landed and live — proven by 'bats tests/handoff-fire-recycle-custody.bats' and the existing handoff-fire suites printing 0 failures, and LIVE_ADDS=0 after deploy-live; do not change the ALLOW_LIVE_SA rule or the limit-gate behaviour for callers that pass no evidence; full brief above`

---

## W2c: resume and terminal plumbing (S; T-resume, T-terminal)

**Targets:**
- `lr-fire-resume.sh`: `:263`, `:339-352` (unchanged), `:357-360`, `:374`, `:410-452`, `:883-885`, `:961`, `:1094-1133`;
- `bin/it2-kitty`: `:226-240`, `:476-484`;
- `bin/cc-kitty-socket`: line 15 contract, add `--all`;
- `hooks/session-register.sh`: `:349-357`.

**Acceptance tests:**
- `tests/lr-launch-lock.bats`:
  1. The spawn is refused when another live holder holds the launch lock.
  2. The spawn is refused when H(sid) is non-empty (stub process named claude with `--resume <sid>`).
  3. After the spawn, the holder is rewritten to the claude pid.
  4. A dead holder is stolen.
- `tests/lr-fire-resume-noprompt.bats`: no keystroke after READY; `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` is present in the spawn env; the re-send schedule is honoured.
- `tests/it2-kitty-prove.bats`: `--match` path, and the kitty-pid mismatch refused.

**Goal:** `W2c landed and live — proven by the three bats suites printing 0 failures and LIVE_ADDS=0 after deploy-live; do not change resume-prompt Enter rules other than the schedule; full brief above`

---

## W3: `lr_recon` package (S; W3a then W3b teammates)

**Targets:** new files only, plus the plists. Before spawning, the W3 lead writes `lr_recon/types.py` (the snapshot, record and fact dataclasses) from the frozen contract, so all teammates share one interface.

**Acceptance tests:**
- **`tests/lr-recon-phase.bats`** runs `python3 -m lr_recon.phase --fixtures tests/fixtures/lr-recon`. Every fixture row maps to its expected phase. Required rows:
  - SPLIT-BRAIN via a bg row;
  - EXITING (a live watcher with the source alive, which is the fatal misread case);
  - HUSK-RETIRED with and without a stub;
  - EXITED;
  - PANE-GONE with our `/exit` and without it;
  - TARGET-LIMITED, TARGET-AUTH, TARGET-TRANSIENT;
  - ENGAGED requiring the token and an offset greater than `confirm_len`, where a notification turn does not close it;
  - MOVED requiring readiness, where a parked menu gives HOLD-MENU;
  - RELAUNCHED-UNPROMPTED;
  - the 405 and 906 strand shapes;
  - the 751 and 815 false-RECOVERED shapes, which must NOT be ENGAGED.
- **Python unittests:**
  - facts: expiry per window; contradiction does not expire; model scope; auth expiry;
  - fence: every branch of the predicate;
  - clock: a simulated sleep shifts deadlines and the pass is observe-only; wake guard;
  - admit: R frozen; CPU brake with its floor; per-account pacer of 3; drip after 3 refusals;
  - classification: a repeating TRANSIENT never escalates; DETERMINISTIC on 2 attempts; ESCALATED re-arms at 15 minutes and on each input change;
  - store: the legacy holder rule; quarantine of a corrupt record; write order;
  - act: adoption by argv `--record-id`; a zombie is treated as dead; the intent nonce prevents a double spawn after `kill -9`.
- **`tests/lr-recon-watchdog.bats`:** no kill inside 180 s of stalled progress; no kill within 120 s of a wake; a kill after two stale reads; a crash-loop page at the second restart.

**Goal:** `W3 landed and live (daemon NOT loaded) — proven by 'bats tests/lr-recon-phase.bats tests/lr-recon-watchdog.bats tests/lr-recon-fence.bats' and 'python3 -m unittest discover scripts/limit-recover/lr_recon/tests' printing 0 failures, and 'python3 -m lr_recon --mode observe --once --root /tmp/lr-recon-dry' printing a census of the live fleet with 0 actuations; do not load any launchd job; full brief above`

---

## W4: fences and operator surfaces (S; T-producers, T-actors, T-surface)

**Targets:**
- `hooks/stop-failure-marker.sh`: `:373-487`, `:389-400`.
- `lr-reset-poller.sh`: `:652-670`, `:659`, `:752-925` (fence calls only; not the drain gate), `:866-869`, `:1091` and every `<(python3 - <<` site (grep `'<(python3'`), `:1372-1430`, `:1432-1668`, `:958-970` (the upgrade kick passes through the fence).
- `bin/cc-lr`: `:356-418`, `:466-479`, `:1060-1160`.
- `bin/cc-resume-debt`: `:118-128`, `:212-224`.
- `lr-fleet.sh`: `:865`, `:1432-1462`.
- `lr-upgrade.sh`: `:817-870`, `:1286-1292`.
- `scripts/boot-resume-launch.sh`.
- `hooks/operator-readout.sh`.
- `scripts/launchd-parity-lint.sh`: the scope list.
- `docs/plans/LIMIT_RECOVER_100P.md`: new section.

**Acceptance tests:**
- `tests/lr-recon-fence-callsites.bats`: for each call site, a live owned sid defers; a stale heartbeat with a live recorded proc still defers; a stale heartbeat with no live proc lets the caller act, but only after it takes the launch lock.
- `tests/stop-failure-facts.bats`: the scope comes from `rateLimitType`, model text and auth; fail-open is kept, including a jq-missing case that still exits 0 with empty stdout.
- `tests/lr-reset-poller-bash32.bats`: runs the poller's census function under `/bin/bash` 3.2 with no `bad substitution` in stderr.
- `tests/cc-lr-request.bats`: writes `<sid>.cc-lr.json` when the fence is live, and falls back to the direct path when the heartbeat is stale.
- `launchd-parity-lint` passes against the new SSOT plists, using a fixture live dir.

**Goal:** `W4 landed and live — proven by the listed bats printing 0 failures, 'bash scripts/launchd-parity-lint.sh --fixture' green, and LIVE_ADDS=0 after deploy-live; do not touch run_claim_take or the autorecover drain gate (sibling-owned); full brief above`

---

## W5: rig, canaries, shadow, cutover (S; plus operator step 1)

### Synthetic cohort rig (`tests/rig/lr-recon-rig.sh --n 5|30 --faults FILE`)
**Environment:**
- Four throwaway config dirs `/tmp/lr-rig/cfg-{a,b,c,d}`, a rig account map (`CC_ACCOUNT_MAP`), a `claude-accounts` fixture (`CC_ACCOUNTS_FIXTURE`), and a rig facts dir.
- The rig reconciler runs as launchd `com.reso.lr-reconciler-rig`, with `LR_RECON_ROOT=/tmp/lr-rig/state` and `LR_RIG=1`. It **refuses every pane whose registry row lacks `rig:true`**.
- `LR_CLAUDE_BIN` points at `tests/rig/stub-claude.py`, symlinked as `claude`.
- Panes are kitty windows in a dedicated OS window titled `lr-rig`.

**The stub:**
- renders the captured CC 2.1.114 composer, dialog and menu frames;
- writes real JSONL record shapes;
- dies with `quotaLimits`;
- handles `/exit`, `--resume`, prompts and submit tokens.

**Fault knobs, per sid:**
- swallow the first Enter;
- slow boot of N s;
- first turn returns 529 or `rate_limit` or `authentication_failed`;
- crash after boot;
- re-create a stub on append after the rename;
- background job child;
- draft in the composer;
- a draft injected after confirm;
- parked menu.

**N=5 run (`faults/none.json`) DoD line,** printed by `cc-lr status --cohort <cid> --root /tmp/lr-rig/state`:
`ENGAGED 5/5 · same-window 5/5 · same-uuid 5/5 · double-typer 0 · split-brain 0 · lost-records 0 · p95 detect→engaged <= 120s`

**N=30 run (`faults/matrix30.json`):**

| Faults | Count |
|---|---|
| swallowed Enter | 6 |
| background work caught before the transplant | 2 |
| background work that surprises after confirm (Esc, then UNCONFIRM, then HOLD) | 1 |
| drafts, 1 of them injected after confirm | 2 |
| target-limited | 2 |
| 529 on first turn | 3 |
| target auth failure | 2 |
| stub re-created during the husk | 1 |
| `kill -9` of the rig daemon mid-cohort | 1 |
| SIGSTOP of the daemon for 200 s (watchdog) | 1 |
| clock skew simulating a 10-minute sleep | 1 |
| pane closed after our `/exit` | 1 |
| legacy holder dir | 1 |
| stale request for a dead session | 1 |
| clean | 5 |

The exact expected line:
`CLOSED 24/30 (ENGAGED 21, MOVED 3) · HOLD named 4/30 (draft 2, bgwork 2 — the 3rd bgwork recovers after its job ends) · REPLACED-NEW-WINDOW 1 · NOT_NEEDED 1 · double-typer 0 · split-brain 0 · lost-records 0 · unowned-non-terminal 0`

The W5 session reconciles the counts against the matrix file before the run, so the expected line is derived from the matrix rather than asserted after the fact.

A further audit asserts `recon/launch.log` shows at most 1 typer per (sid, attempt), and that sha(target) == sha(retired + stub) for the fold case.

### Real canaries (after operator step 1 loads the real jobs in `mode=act` with `LR_RECON_CANARY=<throwaway sids>`)
Facts are scoped `canary`, so they never affect other routing. Four canaries:
1. A cross-account idle no-prompt move of a throwaway real session.
2. The same, with a draft injected after confirm (test hook): UNCONFIRM, then HOLD-DRAFT; after the draft clears, re-plan to MOVED.
3. The watcher killed after `/exit`: B rescues in place.
4. `kill -9` of the reconciler mid-cohort: the actuators are adopted and no second `/exit` is sent.

DoD: `cc-lr status --cohort <cid>` prints each canary CLOSED with the same window id and uuid, and `double-typer 0`.

### Shadow (`mode=observe`, at least 2 real limit cohorts)
`recon/shadow/<cid>.json` is compared with what the legacy path did (from `fleet/`, `handoffs.jsonl` and `results/`). Gate:
- every planned placement was feasible;
- the census missed no limited pane that the legacy path found;
- `derive_phase` agrees with the legacy engagement truth on every recovered sid, with legacy false-RECOVERED cases resolved to the watcher's truth.

**Reopen trigger for decision 3** (added 2026-09-30, D3.7). Reopen the always-wait ruling if, 3 or more times in 30 days, a plan output records a weekly-scope limited mover with `resets_at − now > 6 h` whose reason set holds only `recovery-*-thin` plus the source account's own `src-fact` (`bin/claude-accounts:4547-4549`), and no kmax, missing-data or seat reason. Read `recon/shadow/<cid>.json` in observe mode (skip `last-pass.json` and `focus.jsonl`) and `recon/plans/<cid>.json` in plan or act mode (`write_plan`, `lr_recon/plan.py:448-454`). Observe mode, the current mode, writes nothing to `recon/plans`, so a trigger keyed only on `recon/plans` could never fire. The same shadow passes settle the `(n+1)` question (architecture § 5, D3.5(d)).

### Cutover
Write `recon.on` and `recon/mode=act`. The first real cc-lr-origin cohort (the operator or a lead runs `cc-lr recover --limited`) is the live LIMITED canary, and its DoD is the cohort status line with zero double-typer and zero split-brain in the 5-minute sentinel log.

**Goal:** `W5 gates passed and cut over — proven by the N=5 and N=30 rig DoD lines printed verbatim, the 4 canary status lines, the shadow diff for 2 cohorts, and 'cat ~/.reso/limit-recover/recon/mode' printing act; do not create autorecover.on and do not enable LR_HEAL_CORE_BARE; full brief above`

---

## W6: implement the operator's rulings (S; four parallel code waves by file owner, then docs, then the focused-pane flip)

Scope (frozen): the six operator decisions are ruled as the exhaustive re-research recommended (operator, 2026-09-30 ~00:20Z: "exhaustively research all decisions until exhausted. then. proceed with all as recommended"). W6 builds every non-operator implementation step of those rulings, with the lead's resolutions of the critic's 22 issues below, lands them, and records each ruling. Evidence: `docs/research/lr-fleet-v2-decisions-2026-09-30/` (`rulings.json` holds each decision's full recommendation, `why`, and numbered `implementation_steps`; a step is cited below as D<n>.<index>).

### The rulings (final, after 3 lenses + up to 3 drivable-question rounds + 2 skeptics + adjudication per decision)

| # | Ruling | Conviction |
|---|---|---|
| 1 | Keep `autorecover.on`. It becomes the single zero-human switch: every unattended move (hook requests AND `reroute_parked`) checks it. The reconciler may act only after its four cutover defects are fixed, under its own operator-created marker. | 84% |
| 3 | **Changed:** always wait when no account passes the floors, for 5-hour and weekly caps alike; do not build the least-thin move. Wait is already live; W6 pins it with a test and makes the page say why. | 85% |
| 4 | Hold a lead with live members on every lane; at its reset, type one plain continue into its own pane (no `/exit`, no relaunch). Cross-account team move stays v2. | 90% |
| 6 | Draft stash stays off (it exists only in prose). Fix the page channel so a held draft reaches the operator. | 90% |
| 7 | **Changed:** move a focused pane, but only after five on-path fixes and focus logging land green (W6a), then flip the code default (W6f). Until then hold stays in force. | 70% |
| 8 | Keep KMAX=8; no storm raise. Correct the "5-6 measured" premise (it came from GH#62426). Re-measure KMAX binding after D1.8's over-count fix, which counts subagents only while unfinished. | 86% |

### Lead resolutions of the critic's cross-decision issues (bind every W6 wave)

1. **One focus rule for every typing path** (poller `cc_tui_submit`, `nudge_in_place`, the HELD:team wake, handoff-fire's `/exit`): a single helper `lr_focus_gate <pane>` in `lr-lib.sh` (W6a) — refuse while focused unless `LR_MOVE_FOCUSED=on`; when on, require 2 empty composer reads ~10 s apart and re-check focus immediately before the keystroke. W6b and W6d call it; nobody re-implements it.
2. **One wake text:** a still-limited, at-rest session woken in place at its reset gets a plain `continue`, never `/limit-recover` (which runs the skill and can choose a move). Applies to D1.4's post-reset dispatch and D4's HELD:team wake.
3. **`nudge_in_place` has one owner (W6b) and one spec:** repair its routing (85 NUDGE-FAILED / 0 NUDGED), gate it with rule 1, type rule 2's text. It is REQUIRED, not low priority: decisions 3 and 4 both rely on the in-place resume.
4. **Trickle cost is stated, not hidden:** real poller ticks run ~14-16 min apart, so a per-tick cap of 4 drains a 30-session cohort in ~1.6-1.9 h. W6b sets the cap per account per tick and logs queue depth + ETA on the page.
5. **KMAX evidence is re-based after D1.8** (W6c): record the before/after count on tonight's capped accounts in the evidence dir.
6. **D4.11 is corrected:** HELD:team overrides nothing in decision 3, which now always waits; the note records that instead.
7. **D6's revisit trigger includes focused panes** (the one real draft, pane 513, was focused), because W6f starts moving them.
8. **`reroute_parked` (lr-reset-poller.sh:1577-1612) checks `autorecover.on`**, and the kill-switch list names `LR_POLLER_REROUTE=off`. The unattended record is 1 move in 5 attempts (the 03:07Z reroute failed rc=128), not 1 in 4.
9. **Stay-near-reset applies to `reroute_parked` §2a too** (lr-reset-poller.sh:1643-1644), not only the request loop.
10. **D1.2 targets the right code:** the at-rest check goes in `hf_bg_work_gate`'s limited branch (handoff-fire.sh:~2533-2540, which today calls a limited pane "at rest by construction") and in `hf_recycle_last_read`'s limited branch (~2908-2922) — not `lr-handoff.sh:594-600`, which only voluntary moves reach.
11. **D1.3's cached-rank fallback rejects any cache taken before the source account's reset** (tonight's timeouts sat on the 06:30Z reset boundary; a pre-reset cache is what moved a cohort 5 s after reset).
12. **The `--one` lane gets a real concurrency cap** (W6b): `lf_pool_max` covers only batch mode; until the reconciler's admission is wired (D1.12, W6d) the unattended lane has none.
13. **Paging works before any hold relies on it:** W6d lands `scripts/limit-recover/lr-page.sh` (liveness-free Notification Center + phone leg when configured) as its FIRST commit and pings the lead; `report.py` stops calling the non-existent `cc-notify --page`. W6b's hook-lane pages (D6.6, REQUEST-EXHAUSTED) and D4's wake-failure page use it. The phone leg needs Pushover credentials (operator step, filed).
14. **Rulings are recorded as `cc-decide action <id> --evidence <rulings doc>`**: the tool cannot store a ruling or conviction on an existing packet, so the evidence doc carries both.
15. **`hf_recycle_last_read` has one editor (W6a)**, covering D1.2, D4.2 and D7.2-7.3 together; the exit-6 HELD mapping is W6a's in `lr-handoff.sh` and W6b's in `lr-fleet.sh`, with the verdict names frozen here: `HELD:draft`, `HELD:focused`, `HELD:team`, `HELD:busy`.

### Waves (each a dispatched session with its own worktree; each reads its steps' full `detail` from `rulings.json`)

- **W6a** (`handoff-fire.sh`, `lr-handoff.sh`, `lr-lib.sh`): resolutions 1, 10, 15; D1.2, D4.0 (probe + lr-handoff parts), D4.2, D6.8, D7.1, D7.2, D7.3, D7.4, D7.5. Land `lr_focus_gate` early and ping the lead (W6b consumes it).
- **W6b** (`lr-reset-poller.sh`, `lr-fleet.sh`, `lr-upgrade.sh`, `stop-failure-marker.sh`, `lead-supervisor.sh`): resolutions 2, 3, 4, 8, 9, 12; D1.3 (lr-fleet side), D1.4, D1.5, D1.6, D1.15/D4.7/D7.7 (one nudge spec), D4.0 (poller part), D4.3, D4.8, D6.6, D6.7. The nudge + page work rebases onto W6a's helper and W6d's `lr-page.sh` once they land.
- **W6c** (`bin/claude-accounts`): resolutions 5, 11; D1.3 (router side), D1.7, D1.8, D3.1, D3.2 (router test), D3.6, D8.4.
- **W6d** (`lr_recon/**`, `lr-page.sh`, rig): resolution 13 first; D1.9, D1.10, D1.11, D1.12, D3.2 (reconciler test), D3.3, D4.1, D4.4, D4.9, D4.10, D4.12, D4.13, D6.3, D6.4, D6.5. `recon.on` stays absent.
- **W6e** (after W6a-d land): the doc steps D1.16, D3.4, D3.5, D3.7, D4.6, D4.11 (as corrected by resolution 6), D4.14, D4.15, D6.2, D7.8, D8.2, D8.3, D8.5, written against the as-built code.
- **W6f** (after W6a and W6d are green): D7.6, flip `LR_MOVE_FOCUSED` to default on in handoff-fire and `census.py`; `=off` is the kill switch. Operator step afterwards: restart the reconciler so the new default loads.
- **W7d** (`lr-recon-watchdog.sh`, 2026-10-01, landed): at load 174/427/354 the watchdog killed reconciler 79972 mid-pass, then its replacement 38808 at progress 0, and paged its own two kills as a "crash loop". A kill now also needs the holder's CPU time (self plus reaped children, `ps -S`) to have advanced less than 0.5 s over the trailing 180 s; a holder accruing CPU is logged "slow, not stalled" and spared. Progress 0 within 600 s of the holder's lstart gets a startup grace, and frozen progress past 900 s is killed whatever its CPU. Restarts the watchdog caused are left out of the crash-loop count and page as "watchdog killed N stalled holders". Commits: `git log origin/main -- scripts/limit-recover/lr-recon-watchdog.sh`.

Operator-only steps (filed, not built): D1.14 create the reconciler zero-human marker after the first attended reconciler cohort closes clean; D6.9 Pushover credentials for the phone leg; the reconciler restart after W6d/W6f.

Every W6 wave: explicit-path commits, its suites' `1..N` plan line printed, shellcheck bare on touched shell, one mutant per new site, land via project `/ship` (never wrapped in a timeout), converge with `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`, then ping the lead `DONE <shas>`.

### Decision records and corrections against the as-built code (W6e, 2026-09-30)

Written against origin/main at `27a007c40` or later. The eight packets were already actioned by the lead with evidence, so the corrections live here and in the architecture doc, not in the packets.

**Decision 1 — keep `autorecover.on` (D1.16).**
- Measured on the unattended lane since the flag appeared (05:22:55Z): death to dispatch 4m50s-8m31s (n=4); 1 of 4 moved (pane 918, 6m21s to reply), 2 parked on the router's 3 s bound, and 1 was correctly refused because the operator had already recovered it. The hand-driven median is 9m20s (n=6), but 3 of those 6 were the sessions the unattended lane failed to recover, so it is not an independent comparison.
- The 85-of-85 failed in-place nudges ran under the poller's AUTOFIRE switch, not this flag. The nudge is repaired in W6b `17fbdee45`.
- Scope split: `autorecover.on` gates the legacy unattended lanes (hook requests and `reroute_parked`); the reconciler additionally needs its own `recon/autorecover.on` (D1.9).
- At the ruling the first-turn pacer was not wired on trunk (nothing called `Admission`); W6d `f8f1e07ea` wired it (D1.12).
- **The four reconciler cutover blockers, all driven by W6d:** (i) the reset/stay path (D1.11, `f8f1e07ea`, wake `3ba89226e`); (ii) admission never called (D1.12, `f8f1e07ea`); (iii) `owned/<sid>` never released (D1.10, `f8f1e07ea`) — the design finding (`findings.json:44` in the bundle) had marked this "Fixed" while trunk had no caller until then; (iv) limited cohorts moved cross-account 5 s after reset (D1.11, `f8f1e07ea`). Plus the scope split (D1.9).
- Still between the reconciler and `recon/mode=act`: W6f (gated on decision `28740361e7dd`); the reconciler restart after W6d/W6f (operator); the W5b shadow over 2 real cohorts (backlog `8e67a18de9ad`); D1.13, a review of the first real unattended move on the current build; and D1.14, the reconciler's own marker (operator step, backlog `be52a4c8a99f`, linked to `8e67a18de9ad`).

**Decision 3 — wait (D3.4, D3.5, D3.7).**
- (1) 0 of 25 weekly parks with a reset over 6 h were all-thin under the live floors, and 1 (09-12) under `--place`'s floors.
- (2) On today's code the 09-12 move is roughly a wash (about +4.7 h against -5.2 h at a 7/10 recovery rate, estimated). The old 16-19 h cost came from the pane-341 no-tty failure and the missing reroute (`results/5e0d69f7-…log`; `poller.log:2522-2528`; fixed by `08bdf357d` and `b4eef1cb8`).
- (3) The hybrid's floor re-check rejects every pick.
- The "second cascade measured 2026-09-19" is replaced by an estimate: about 93% of next3's burn came from its own sessions and about 6.5% from 2 movers.
- As built: the dead switch is deleted (D3.1), tests pin the all-thin wait in the router (W6c) and the reconciler (W6d, WAIT_SLOT re-offered every pass, eta = the source reset, page at eta + 600 s), and the page says "no account has safe room; re-checked every pass" (D3.3).
- The `(n+1)` weekly term is left unchanged and documented in architecture § 5 (D3.5). The reopen trigger is in § W5 Shadow (D3.7).

**Decision 4 — hold, and continue in place at reset (D4.6, D4.11, D4.14, D4.15, D4.10 doc half).**
- D4.6: Claude Code's own usage-limit continue never arms here, because Remote Control blocks it; our typed continue at reset + 120 s is the only wake (architecture § 1, with the evidence).
- D4.11, as corrected by lead resolution 6: the census returns HELD:team before placement runs, and decision 3 always waits, so the hold overrides nothing. Measured waits: team pairings 0.6, 1.3, 3.5, 3.8 and 5.2 h, plus one 10.9 h weekly re-park (`ff519bfd`); corpus seven_day waits have a median of 7.9-9.9 h and a max of 36.7 h. The HELD:team page fires when the hold starts, for any reset distance (`lr_recon/report.py:732-748`). No idle-age release rule: in the one true hold, members idle 36-40 min went back to work; in the false hold, the member had been idle only 13 min.
- D4.14, the evidence corrected:
  - Frequency, with each period: on 2.1.260+ (transcripts from 08-19), 1-2 of 109 limit episodes (0.9-1.8%); only 3c73a9d9 had a member write after the limit, and 0 episodes were on 2.1.280/2.1.284. From 08-01 to 08-18 (2.1.220; the poller was blind to `next` until `eaf0ff66d` on 09-10), 5 poller-log team pairings: 5 of 108 PARKED events (4.6%) overall, and 0 of the 70 PARKED events from 08-19 on.
  - Resume base: 13 of 13 observable resumes made a new team (10 historical with a surviving team dir, 3 live processes), not "0 of 267"; 257 of the 267 left no team dir to observe.
  - The 3c73a9d9 hold kept the team intact, and that is all it shows: the lead was not continued at its 12:00Z reset (3 NUDGE-FAILED, then LATCHED); it sat idle until 15:25:51Z, woken by something unmeasured; 0 of its 8 members were limited and only 5 of 8 wrote again; the poller later `--resume`d it into a new pane at 18:42:24Z.
  - The W0 premise reads "0/12 goals cleared, 5/12 proven armed".
- D4.15: the v2 cross-account team move and its prerequisites are in architecture § 15.
- D4.10: the phantom `LR_TEAM_UNIT` is removed from the kill-switch list and the W3 log line; the hold is unconditional in v1.

**Decision 6 — draft stash off (D6.2).** The corrected receipt is in the decision-research table, row 6. What ends a draft hold: the operator sends or clears the draft. The reconciler re-probes a HOLD-DRAFT every 120 s (`settle.py:28`) and pages at 15 min through `cc-notify`, falling back to `lr-page.sh`, quoting the draft from a raw snapshot (W6d `f8f1e07ea`, `b5740ca25`); the hook lane names `HELD:draft` in the verdict, keeps the screen (W6b `72dda9cb6`) and pages on REQUEST-EXHAUSTED. The one exception to "nothing is typed into a draft pane": on an unfocused pane, a composer of 2 characters or fewer is a stray keystroke and is scrubbed with a receipt (`scripts/lib/composer-intent.sh:29,67-70`); non-ASCII is never a stray (W6a `0234a15da`). Revisit if the raw-screen capture finds 3 or more genuine one-line drafts, counting focused panes too once W6f moves them (lead resolution 7).

**Decision 7 — move a focused pane after the fixes (D7.8).**
- Focus is a three-way conjunction (window ∧ tab ∧ OS window, `handoff-fire.sh:1359-1364`), so at most one pane is focused at a time.
- 6 of the night's 7 recoveries were manual runs typed from lead session 83010792 at 03:04Z and 04:16Z; only pane 918 was unattended.
- The only multi-pane batch since `autorecover.on` (05:22Z) had the operator at 3 of 3 target panes at the reset.
- The presence proxy is 6 of 192 limit records (3.1%, 4 of 85 sessions).
- The focus gate landed at 10:09Z (`18910dd50`), after every event cited.
- Four code comments still read "unruled" (`census.py:165`, `types.py:73`, `handoff-fire.sh:2835`, `:14768`); W6f takes them (lead, 2026-09-30).

**Decision 8 — keep KMAX 8 (D8.2, D8.3).** Evidence note: `docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-decision-8.md`. Burst protection stays as it is: 2 concurrent recoveries on the live legacy lane, then the 3-per-account first-turn pacer after the reconciler cutover. **Revisit** if act-mode `recon/plans/*.json` show a cohort waiting on `kmax-concurrency` for more than about 10 min, or a REQUEST-EXHAUSTED whose attempts were all kmax-excluded. The real levers are separate items: (a) the mover-weight rule (as built, subagents written in the 10 min before the death, `lr_recon/plan.py:135-138`; the rule itself is D8.6's open question); (b) `bound_kwork` compares counts, not session ids (`bin/claude-accounts:2380`); (c) the source-account skip in `lf_pick_target` (`lr-fleet.sh:780`); (d) the hook lane falls back to `KMAX_RESIDENT` 40 when k_work is unmeasured (`bin/claude-accounts:2537-2548`).

---

## Measured Definition of Done (the whole programme)

1. **Unit gates:** every bats suite named in W1-W4 plus `python3 -m unittest discover -t scripts/limit-recover -s scripts/limit-recover/lr_recon/tests` print 0 failures (corrected 2026-09-30: without `-t` the package imports fail) on the landed trunk sha, and are re-run after the last rebase.
2. **Rig:** the N=5 and N=30 lines exactly as specified, and the launch-log audit shows at most 1 typer per attempt.
3. **Canaries:** 4 of 4 CLOSED, pane-in-place (same window ids, same uuids).
4. **Shadow:** 2 real cohorts, with zero census misses and zero phase disagreements after resolution.
5. **Live:** `launchd-parity-lint` is green including `com.reso.lr-reconciler*`; `wrap-ledger.sh --machine` shows LIVE_ADDS=0; `recon/heartbeat` progress advances across two reads 30 s apart.
6. **First real acting cohort:** every member is CLOSED, or held in a named WAIT/HOLD within its maximum age, 10 minutes after the last death. Zero split-brain in the sentinel log.
7. **Zero-human:** once the operator creates `autorecover.on`, a hook-origin cohort reaches (6) with no human command. The measured detect→OPEN time and p95 detect→engaged are recorded in `docs/plans/LIMIT_RECOVER_100P.md`, replacing the design estimates.

---

## Operator decisions (filed for ruling; until ruled, the recommended default is built behind its kill switch and never enabled)

**All ruled or settled, 2026-09-30.** The six open decisions (1, 3, 4, 6, 7, 8) were ruled "as recommended" after the exhaustive re-research (§ W6 carries the final rulings), and all eight packets were actioned with evidence by the origin lead (decisions 2 and 5 were already settled). The bullets below are the filing text, kept as filed; a **Ruled** line and any correction follow each one.

- Zero-human recovery. Should the daemon act on hook-detected limits without anyone running cc-lr, by your creating ~/.reso/limit-recover/autorecover.on? Recommendation: yes, but create it only after the W5 rig and canaries pass and the sibling session's re-validation has drained the 18 held requests. Conviction: 85%. Options: create it (recoveries start without a human — *corrected 2026-09-30, D1.16: the filing said "seconds after a death"; measured on the unattended lane, death to dispatch was 4m50s-8m31s (n=4), and 1 of 4 moved (6m21s to reply), 2 parked on the router's 3 s bound, 1 was refused because the operator had already recovered it*) / leave it absent (the daemon plans and pages, and moves happen only when a session or you run cc-lr recover).
  - **Ruled 2026-09-30: keep `autorecover.on` (84%)**, as the single zero-human switch for every unattended move; the reconciler gets its own marker (D1.9). Packet `7d93315f2591`.
- Background work at the limit. When a limited session still has a background job running (usually a land), may recovery ever stop that job to move the session? Recommendation: no. Hold the session until the job ends on its own, page at 20 minutes, and never choose 'Exit and stop tasks'. Conviction: 85%. Options: hold (the in-flight land or build survives, and the session waits) / stop after N minutes (the session moves sooner, and the job is killed mid-flight).
  - **Settled 2026-09-29, packet actioned 2026-09-30:** hold until the job ends; page at 60 minutes for a ship-land and at 20 minutes otherwise (92%).
- No account passes the survival floors (weekly headroom at least 10%, projected 5-hour under 60%). Should sessions wait for their own reset, or go to the least-thin account? This is the existing LIMIT_RECOVER_100P open decision 2. Recommendation: wait, with every waiting session and its wake time named on the OPEN page. Conviction: 80%. Options: wait (no second limit cascade, longer outage) / least-thin (faster, and the cohort's burn likely hits that account's cap within about an hour).
  - **Ruled 2026-09-30: wait (85%)**, for 5-hour and weekly caps alike; the least-thin move is not built. Packet `0fb99f3a4668`. Evidence in § W6 "Decision records".
- Agent-team leads with live members. Should v1 move whole teams across accounts, or hold the team and continue the lead in place when its account resets? Recommendation: hold in v1, then build the cross-account team move in v2 on lr-upgrade's team hold, after a probe. Conviction: 75%. Options: hold (safe, and the team is down until the reset) / move now (faster, on a path /exit's team cleanup can break and that has never run across accounts).
  - **Ruled 2026-09-30: hold on every lane; continue the lead in its own pane at reset + 2 min with our typed continue, and page on failure (90%)**; the cross-account team move stays v2. Packet `46ed0af12b01`.
- Repairing core.bare. May the daemon run 'git config --unset core.bare' on a shared checkout that has a working tree, with a separate-read verification and only when .git/config.lock is absent? Tonight the auto-mode classifier denied this exact write to a session, so the daemon will not do it without your ruling. Recommendation: allow. Conviction: 85%. Options: allow (panes in that repo move and work) / deny (those panes are held as HOLD:repo-bare and paged to you).
  - **Settled 2026-09-29, packet actioned 2026-09-30:** allow; the heal landed in `b509a51f4` with the `LR_BARE_REPAIR=off` switch (92%).
- Operator drafts. May recovery stash a one-line draft in an unfocused pane, move the pane, and restore the draft without pressing Enter (LR_DRAFT_STASH)? Recommendation: no. Hold the pane and page at 15 minutes. Conviction: 70% at filing, 90% at the ruling. Options: off (your draft text is never touched, and those panes wait for you) / on (a single-line draft that reads back identically twice is stashed and restored).
  - **Ruled 2026-09-30: off (90%).** `LR_DRAFT_STASH` was never built; the fix is the page channel. Packet `7561eb4a4dfb`.
- Focused limited panes. Should a limited pane you are currently looking at be moved? Recommendation: yes. The new post-confirm read-back makes typing into it safe, and holding it would stall the pane you most likely need. Conviction: 75%. Options: move it / hold it while it has focus.
  - **Ruled 2026-09-30: move (70%)**, applied as a code default (`LR_MOVE_FOCUSED` on, `=off` the kill switch) only after the five on-path fixes and focus logging land green (W6a) and W6f flips it; until then the hold stays. W6f is also gated on decision `28740361e7dd`. Packet `ad16e2858036`.
- Seat cap during a storm. Should the per-account active cap (KMAX=8; limit unmeasured here: 0/40 probe failures at N≤6, 0 terminal limiter errors, retries not persisted) be raised during a recovery storm so more sessions move at once? Recommendation: no. The design names every waiting session and its ETA instead. Conviction: 80%. Options: keep 8 (fewer parallel moves) / raise it (more parallel moves, and more 'server temporarily limiting' refusals on the target accounts).
  - *Corrected 2026-09-30 (D8.3):* the filing said "a measured infrastructure limit of 5-6 concurrent requests per account" and "no added 529 risk"; neither was measured here (the band came from GH#62426).
  - **Ruled 2026-09-30: keep 8 (86%); a recovery-only raise is also rejected.** Packet `4a08882545c5`. Evidence: `docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-decision-8.md`.

### Decision research, 2026-09-29 (origin lead; 8 read-only agents, one per decision)

The full table is in the design bundle, `decision-research-2026-09-29.md`. What it changes here:

| # | Status | Revised recommendation (conviction) |
|---|---|---|
| 1 | on since 05:22Z · **RULED 2026-09-30: keep on (84%); packet actioned** | Keep automatic recovery on (88%). The first unattended recovery (pane 918, 05:32→05:38Z) spent 5 of its 6 minutes waiting for the poller to finish its pass before it reached the request, so the reconciler must start a recovery the moment a request lands (W3). |
| 2 | **SETTLED** · packet actioned 2026-09-30 | Hold until the job ends. Page at 60 minutes when the job is a ship-land (claude-infrastructure lands take p50 836 s and p95 3456 s, and 30% exceed 20 minutes), and at 20 minutes otherwise (92%). |
| 3 | **RULED 2026-09-30: wait (85%); packet actioned** | **Wait (85%)**, 5-hour and weekly alike; evidence in § W6 "Decision records". *Superseded 09-29 text follows.* Hybrid. A 5-hour cap always waits: the median reset is 1.9 h (max 4.5 h), and a second cascade would follow (*corrected 2026-09-30: "a second cascade was measured on 2026-09-19" overstated it; by attribution about 93% of next3's burn came from its own sessions and about 6.5% from 2 movers, estimated*). A weekly cap with reset ≤ 6 h waits. A weekly cap with reset > 6 h moves at most 1-2 sessions per pass to the least-thin account, re-checking the floors on each pick (75%). |
| 4 | **RULED 2026-09-30: hold; continue in place at reset (90%); packet actioned** | Hold in v1, and resume the lead in place at its reset, with no `/exit`, so the team stays whole (88%). |
| 5 | **SETTLED** · packet actioned 2026-09-30 | Allow. The heal already landed in `b509a51f4`: 4 checks, a backup, verification by a separate call, and the `LR_BARE_REPAIR=off` switch (92%). |
| 6 | **RULED 2026-09-30: off (90%); packet actioned** | No. *Receipt corrected 2026-09-30 (D6.2):* at least 26 draft holds from 08-23 to 09-30, at least 8 of them unreadable, and 1 genuine operator draft (pane 513, 09-24, a focused self-recycle, read back with every space stripped); no hold in a limited pane was genuine. The reader strips spaces, and height cuts text off (the composer is height-capped and follows the cursor, `scripts/lib/cc-tui.sh:282-284`) while width only wraps it. What fails is the alert, not the hold. (The 09-29 text read "truncates by width … only 3 real draft holds (80%)".) |
| 7 | **RULED 2026-09-30: move after the on-path fixes, via W6f's default flip (70%); packet actioned** | Move the pane, but behind a focus gate (W2b). The planned `/exit` read-back did not exist: `handoff-fire.sh:1538` sent the text and Enter together (65%). |
| 8 | **RULED 2026-09-30: keep 8 (86%); a recovery-only raise is also rejected; packet actioned** (evidence `docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-decision-8.md`) | Keep 8. **Correction:** "5-6 concurrent requests per account" was never measured on this machine; it came from GH#62426 and habit. KMAX counts sessions written in the last 10 minutes, not requests, and the first-turn pacer (3 per account) is the burst protection. W0 item 9 runs the burst probe (65%). |

## Provenance

Dynamic Workflow wf_99ea9654-29f (22 agents, 0 errors: 8 subsystem maps, 4 designs, 3 judges, 5 skeptics, 2 synthesis passes). The architecture is `docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md`. The 55 skeptic findings (4 fatal, 30 major) and their dispositions stayed in the design bundle outside the repo.

## Status log

- 2026-09-29: plan and architecture committed (programme lead, branch lr-fleet-v2-lead). Waves fire as dispatched sessions in dependency order.
- 2026-09-29 (lead, `d4d7e4aec` landed): W0, W1 and W2a fired concurrently. The dependency graph drew W1 and W2a after W0, but neither shares a file with W0 or reads a W0 measurement, so they did not wait. W2b and W2c wait for W0, because they consume its bg-work dialog and Enter-readiness measurements. Firing was bounded by accounts, not by the graph: W2a waited about 10 minutes for a free seat on `next4` (both routable accounts were at KMAX).
- Scope (grown): +W4-wf, an early W4 slice fired when W0 lands. After a move, a Workflow run whose dangling slots precede completed ones must get a salvage-seeded continuation, never a plain `resumeFromRunId`, which re-spends the finished slots (session 7c395da7 re-ran about 24 audit agents on 2026-09-28). Target: `scripts/limit-recover/lr-audit.py`, whose ACTION table and run-level gap rows feed the relaunch bundle. No other wave owns the file, so it does not wait for W3.
- Operator decision 5 (core.bare): the sibling's heal (`lr_heal_bare_checkout`, switch `LR_BARE_REPAIR`, landed `b509a51f4`) stays as landed and is reverted only on a "deny" ruling. The reconciler honours `LR_HEAL_CORE_BARE=off` by exporting `LR_BARE_REPAIR=off` into every actuation (W3 T-act).
- 2026-09-29, **W1 done** (session fire-w1, teammates T-place, T-ledger, T-admit). The frozen contract was built as written, and the landed shas are in `git log origin/main -- bin/claude-accounts scripts/lib/capacity-admit.sh`. Acceptance: `tests/claude-accounts-place.bats` (cases a-j plus the ledger contract, 1..17), `tests/capacity-admit-restore.bats` (1..4), `tests/lr-lib.bats` (1..53); all 14 existing `claude-accounts*.bats` suites and the three existing capacity-admit suites stayed green. Learnings and decisions W3 needs:
  - `--place` inputs: movers are JSONL `{sid, src (name or config dir), kind limited|idle, w, model?, burn_ph? (pp/h), death_ts?}`, kwork is JSON `{acct: int|null}`, and facts are `<acct>.<scope>.json`. The source store is exempt from the store-holds-sid skip, because otherwise "stay" could never happen. An account the lane scorer cannot score (for example no fable limit) is dropped with its reason. `r_w_worst` is a code default of 0.011/h (router key `RECOVERY_R_W_WORST`, env `CC_ROUTE_RECOVERY_R_W_WORST`), so accounts.json is unchanged. The default `b_sess` is 0.07/h (`CC_PLACE_B_SESS_DEFAULT`).
  - No snapshot row carries a wire read time today, so a wire read never expires a 5h/7d fact. Facts expire at `resets_at + 60` until a producer stamps `wire.read_at`.
  - Ledger: ids deduplicate (the newest row wins) and a void row kills its id anywhere in the ledger. The append lock is non-blocking with 5 s of retries and then exit 5, because `claude-accounts-fresh-lock-bound.bats` forbids an unbounded flock. `--assign-many` rejects keys outside `{acct,id,sid,w,ttl_s}`. The k_sids skip also applies to `k_phantom_desk`.
  - `--max-wait N>0` is now a real bound, measured from process start on the CLI path (interpreter start plus import cost 0.7-1.2 s at load 40-130). That changes the `--rank --recovery --max-wait 3` callers in lr-fleet and lr-reset-poller: past the bound they get exit 3 and empty stdout, which they already handle. **Residual:** a sweep timer that fires during a heal orphans the heal subprocess (the process calls `os._exit`).
  - Admission: in-flight tokens count in the reserve term as well as the active term; without that, one token in flight would stop the operator reserve from binding. A malformed `CC_ADMIT_RESTORE_R` is recorded as blind term `restore-r` and falls back to the ceiling.
  - Not built: the `RECOVERY_IDLE_SEATS` knob. It is in the architecture change list, but its semantics wait on W0's no-prompt `--resume` measurement, and no W1 acceptance case covers it.
  - Blockers: none.
- 2026-09-29, **W0 done** (branch lr-fv2-w0; the landed sha is in the lead's ping). Evidence and per-item detail: `docs/research/lr-recon-w0-2026-09-29/SUMMARY.md`. Fixtures: `tests/fixtures/lr-recon/`. Measured defaults:
  - `LR_RECR_SCHEDULE=5,15,30,45`, with every re-send gated on DRAFT-MINE. In 30 throwaway panes on 2.1.284 the first Enter was accepted each time, sent ≤ 0.62 s after paint. The user record lands in the transcript 1.6-11 s later, so transcript-only swallow checks misfire.
  - `RECOVERY_IDLE_SEATS=active`. A no-prompt resume writes 17 records within 7 s.
  - The goal survives a usage-limit death (12 of 12), so no re-arm is needed on the same-uuid path.
  - Under `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`, `pane_bgwork_key` returns no key and option 2 becomes "Stay".
  - Launchd resolves the socket through the `/tmp` glob, and needs the absolute `kitten` path.
  - Item 9, the burst probe: 0 of 40 first turns failed or retried at N = 2..6 simultaneous cold starts on `next4` and `next`, with their live fleets running on top. So the first-turn pacer of 3 is conservative rather than measured; KMAX=8 is unaffected; and the design's "5-6 concurrent requests" band is unmeasured on this machine.

  Learnings for later waves:
  - **W2c:** `cc-kitty-socket --all` is silently ignored today.
  - **W3:** submit tokens are split by the paste wrapper; a §4.2 gap exists (source dead, watcher live, no holder); a parked menu must be checked before row 7; the 405/906 strands derive PRE-MOVE.
  - **W4/W5:** a Workflow resume re-spends every completed slot whose call index shifts. The briefed rule, "every slot after the first dangling one", was refuted for 7c395da7.
  - **W5 rig:** the fleet runs 2.1.284, and 2.1.114 parks at an invalid-settings dialog on today's `settings.json`.
  - **HOLD-BGWORK:** 6 of 20 live panes hold only a `cc-await-ping` shell.

  No blockers.
- 2026-09-29, **W4-wf done** (session fire-w4wf, lead-inline; the landed sha is in the lead's ping). `lr-audit.py` now predicts, per Workflow run, how many completed slots a plain `resumeFromRunId` would re-spend (`resume_prediction` in audit.json, one line in audit.md). When the count is > 0, the run's gap row reads `SALVAGE-SEEDED CONTINUATION — do NOT resume`, with the count, the cache hits, the cause and the salvage path. The unfinished slots' rows point at it, and a STALLED run reads `GATED CONTINUATION`, with the stall gate first. The text reaches the successor through `audit.md`'s gap ledger, which ingest reads, so `lr-handoff.sh` is untouched. Kill switch `LR_AUDIT_RESUME_PREDICT=off`. Tests: `tests/lr-audit-workflow-prefix.bats`, with the new timing fixture `tests/fixtures/lr-recon/workflow-prefix-7c395da7-calls.json`. It predicts 625 of 633 completed slots re-spent for 7c395da7 (608 verify), behind exactly the 8 measured index-stable hits. Learnings:
  - **The open question is settled by measurement.** The resume re-issues a completion-ordered stage in upstream INDEX order. In `wf_efe43f63-ce7`, find 0's first verify had been call 459, because find 0 finished 7th, and it became call 9 on the resume. A resume replays only the unchanged prefix of calls (the Workflow tool reference), so the prefix ends at the first reordered call.
  - **Detection keys on call timing, not labels.** It reads `workflowProgress[].index`, `queuedAt`/`startedAt` and `durationMs`. A burst issued while earlier calls are still in flight was released by a completion, and two or more such bursts in one busy window are assumed to reorder. The rule is conservative on purpose: the downstream issue lags its trigger by up to seconds, so matching each burst to the completion that released it misassigned triggers on the real run. On the last ~30 real runs, pipelines break at their first reordered stage, and barrier, sequential and queued-parallel runs predict 0.
  - **Residual:** a run summary with no `workflowProgress` gets `UNPREDICTED` and keeps the plain resume text.
- 2026-09-29, **W3 done** (session fire-w3; the landed sha is in the lead's ping). The `lr_recon` package is in `scripts/limit-recover/lr_recon/`, with `lr-recon-fence.sh`, `lr-recon-watchdog.sh` and three plists that are declared `staged` in `launchd/fleet.manifest` and not loaded. W3a ran as 6 teammates. In W3b, admit, report and watchdog were teammates, and census, plan, act, main and evidence were written by the lead: the capacity gate refused spawns 3 times (active ceiling, then the operator's memory reserve), and it directs that work to the lead. Acceptance: `lr-recon-phase.bats`, `lr-recon-fence.bats`, `lr-recon-watchdog.bats`, and 223 unittests on both python 3.9.6 and 3.11. The `derive_phase` fixtures give 65 of 65 rows passing, 4 of them PRE-MOVE substates that the plan owns. Contract decisions later waves inherit:
  - **lstart is space-collapsed.** It is `ps -o lstart=` under `TZ=UTC LC_ALL=C` with runs of spaces collapsed (`Sep  9` becomes `Sep 9`). Observe, store, the fence, the watchdog and the heartbeat all compare that form. macOS `ps` has no `lstat` keyword, so the state column is `stat`.
  - **Every state file is compact JSON** (`separators=(",",":")`), because the bash readers (the fence, the watchdog, lr-lib's `lr_claim_holder_pid`) sed fields out of it. The heartbeat gained `progress_wall`, so the fence answers "advanced within 180 s" from one read, sleep-adjusted as `now − max(progress_wall, kern.waketime)`.
  - **Drained requests go to `claimed/` under the limit-recover root**, the poller's `CLAIMED` store, never a second store. They are moved only in `act` mode, never deleted.
  - **Actuator argv:** every actuator runs under an `lr-recon-act --record-id R --intent N` bash wrapper, so adoption by argv works even for tools that do not yet take `--record-id`. The intent nonce is saved before the spawn, and (pid, lstart) after it.
  - **`--mode` only lowers `recon/mode`.** Acting also needs `recon.on`, and PLAN-ONLY records never act. `--once` in observe mode never starts the background `--fresh` sweep, because that sweep hits the usage endpoint.
  - **Kill switches, all on the safe side:** `LR_IDLE_FANOUT` defaults off. `LR_MOVE_FOCUSED` defaults off, so a focused LIMITED pane is held as the new `HOLD-FOCUS` (decision 7). Decision 3 ruled wait (2026-09-30): no least-thin pick and no switch (the `LR_NO_FLOOR_POLICY` this line first named was deleted by W6d `f8f1e07ea`). HELD:team is unconditional (corrected 2026-09-30: the `LR_TEAM_UNIT` named here was never read). HEAL is disabled unless `LR_HEAL_CORE_BARE=on`. `CC_RECYCLE_BGWORK_ANSWER=cancel` is forced on every actuation. `LR_BARE_REPAIR` is not touched, per decision 5.
  - **Watcher-only background work** (a shell holding only `cc-await-ping`) does not hold a LIMITED session, and it does hold an idle move. Decision 2 (SETTLED) holds real jobs as HOLD-BGWORK, paging at 60 minutes for a ship-land and at 20 minutes otherwise.
  - **The stale reconcile** carries a local predicate with the sibling's `rq_stale_reason` contract (`lr-reset-poller.sh:745`) and a `TODO(W4)` to swap once that predicate is extracted into lr-lib.
  - **Module size:** the post-write formatter reflows to 88 columns, so store, report, main and types measure over the architecture's 400-line cap. The code is not over-scoped.
  - **Not yet exercised: the W3b integration against W1/W2.** W2a, W2b and W2c were not on trunk at W3's land. The actuator command builders follow the frozen Phase 0 contract and are unit-tested, but they have not been run against the W2 flags (`--record-id`, `--husk`, `--relaunch-at-shell`, `--phase unconfirm|fold-stub|abort`, `--no-prompt`); the W5 rig does that. SPLIT needs a background job id that the census does not carry yet, so it pages instead.
  - **For W5's installer:**
    - The rig plist sets `LR_RECON_RIG=1` with root `/tmp/lr-recon-rig/recon`, where this plan's W5 text says `LR_RIG` and `/tmp/lr-rig/state`. Match the plist.
    - launchd does not create a `StandardOutPath` parent directory, so the installer must create `recon/` and the rig root before bootstrap.
    - The manifest rows name the activation script `lr-recon-launchd.sh`, which W5 writes.
    - A freshly started watchdog needs 180 s of its own observation before it will kill, and it never kills when `kern.waketime` is unreadable.
  - **The live observe census was not run.** The auto-mode classifier denied `python3 -m lr_recon --mode observe --once` against the live fleet. It is filed as an operator step (see the lead's ping). The 0-actuation property is proven offline by `test_main` over a synthetic census.
- 2026-09-29, **W2c done** (session fire-w2c, teammates T-resume and T-terminal; the landed shas are in `git log origin/main -- scripts/limit-recover/lr-fire-resume.sh bin/it2-kitty bin/cc-kitty-socket hooks/session-register.sh`). Acceptance: `tests/lr-launch-lock.bats` + `tests/lr-fire-resume-noprompt.bats` + `tests/it2-kitty-prove.bats` (1..30); the existing lr-fire-resume, it2-kitty, cc-kitty-socket, kitty-socket-address and session-register suites stayed green. What W3/W4/W5 build against:
  - **Launch lock:** `lr-fire-resume` takes or re-takes `${LR_LAUNCH_LOCK:-locks/<sid>.launch}` immediately before the spawn (before `trap - EXIT`). The holder is OURS on the same `LR_RECORD_ID` + `LR_ATTEMPT`; it is STALE on a dead, zombie or lstart-moved pid, or on an unreadable holder in a dir older than 60 s. A live foreign holder gives rc 10. It then refuses (rc 11) if H(sid) is non-empty: `--resume <sid>` argv leaves (shell and wrapper parents dropped), registry rows (lstart-checked), and `<cfg>/sessions/*.json` rows across the five config dirs. After the spawn the holder is rewritten to the claude pid and is never released. Both rcs go to `relaunch.rc`. Kill switch `LR_LAUNCH_GUARD=off`.
  - **Re-send schedule:** `LR_RECR_SCHEDULE` offsets are wall-clock seconds after the first CR, then every 15 s. The initial deadline covers the first look, because a poll window shorter than 5 s used to end the loop before any look. `LR_SUBMIT_RECR_MAX` (2), not the deadline, now bounds re-sends. The old "exactly one re-Enter" was an artefact of deadline = t+15 = the next look. A composer holding someone else's text stops the looks but not the transcript poll, because breaking at 5 s would convict submits whose record lands at 1.6-11 s.
  - **`--no-prompt`** types nothing after ready and notes `READY` / `READY-QUIET` once (W3's MOVED evidence). `CLAUDE_CODE_DISABLE_AGENT_VIEW=1` is on both spawn lines. `LR_CLAUDE_BIN` and `LR_PRESEED_DONE` are honoured. `worktree prune` is gone: `worktree add` runs under `locks/git-<sha1(common dir)>`, with a single `-f` retry only for a missing-but-registered `$WT` whose branch lives nowhere else.
  - **Terminal:** `it2-kitty` proves a target with `ls --match id:N`, and an optional `CC_TERM_KITTY_PID` proof refuses a window in another kitty. `cc-kitty-socket --all` lists every live instance, oldest first; an unknown argument is rc 64. Registry rows carry `kitty_listen_on` + `kitty_pid`, which are null unless the socket is live.
  - **Learning:** `hooks/validate-bash.sh`'s pane-spawn lineage gate splits a command on `(`, so a commit message with the scope `(it2-kitty)` reads as a pane spawn and is denied. Use a different scope.
  - Blockers: none.
- 2026-09-29, **W2a done** (session fire-w2a, teammates T-custody and T-handoff; the landed shas are in `git log origin/main -- scripts/limit-recover/lr-transplant.sh scripts/limit-recover/lr-handoff.sh`). Acceptance: `tests/lr-transplant-custody.bats` (cases 1-9 plus controls), `tests/lr-handoff-flags.bats`, and `tests/lr-handoff-launcher-quoting.bats` unchanged and green; `lr-transplant.bats`, `lr-lock.bats` and the other four `lr-handoff-*.bats` suites stayed green. Decisions and learnings W2b, W3 and W4 need:
  - **Refusal shape.** Every new custody refusal exits 2 with stdout `{"ok":false,"reason":R,"detail":D,"sid":…}`, where R is one of the five frozen reasons. Branch on `detail`; its values are no-lock, owner-mismatch, record-id-mismatch, not-retired, live-actuator, live-watcher, target-held, holder-live, target-advanced, target-missing, source-retired, stub-present, source-dead and stub-beside-retired. Pre-existing FATAL paths keep their text and rc 2.
  - **The confirm lock check is keyed on the caller's record id**, not on the lock's existence. `lr-handoff.sh` confirms with no admit on its spawn and close-source paths, so a strict "lock must exist" rule would refuse every one of them. With a record id, the lock must exist, name TO and carry that id (a lock with no record id passes the id check). With no id and no lock, confirm is today's single step. With a lock and no id, the owner must equal TO. Unconfirm, fold-stub and abort are always strict.
  - **Holders** are `<cfg>/sessions/*.json` rows whose (`pid`, `procStart`) is alive; `procStart` is exactly `TZ=UTC LC_ALL=C ps -o lstart=`. The lock holder is `${LR_HOLDER_PID:-$PPID}`, and abort does not count the caller itself as a live blocker. Both the custody liveness check and lr-handoff's git lock compare lstart space-collapsed on BOTH sides (W3's form), so a watcher or lock holder recorded by either writer reads as the same live process on days 1-9 of a month (custody case 8c; red against the raw compare). W2b and W2c should do the same. Unconfirm with no `.handed-off` is `lock-mismatch`/`not-retired` and points at abort. Fold-stub survives a crash at either append.
  - **`lr-lock.py`:** a stub beside `.handed-off` is CUSTODY ahead of ORPHAN and ABANDONED. On the case-9 fixture the old classifier said ABANDONED, which the TTL reaps.
  - **lr-handoff:** the continue-prompt branches (rc 0, A1/A2, other) apply only under `LR_PLACED_BY=reconciler`; every other caller keeps the `/limit-recover ingest` fallback byte-for-byte. The new manifest fields (`record_id`, `attempt`, `placed_by`, `assign_id`) are written only when one is set, so W3 reads an absent field as "". `--attempt` defaults `HF_RECYCLE_ATTEMPT` to `R:1`. `--record-id` and `--account-evidence` reach handoff-fire only once its live copy parses them (W2b). `--no-prompt` joins the live-parser preflight, so it refuses rc 5 until W2c's `lr-fire-resume --no-prompt` is live. The TTL message uses W1's `cc_capacity_token_ttl_s`. The git lock around `switch -C` degrades to the unlocked rename when it cannot be built, and skips only on a 10 s timeout. The sibling's core.bare heal is unchanged.
  - No blockers.
- 2026-09-29, **W4 done** (session fire-w4; teammates T-producers, T-actors-a, T-actors-b, T-surface. T-actors was split in two at planning because its estimate was over 300 LOC. The landed sha is in the lead's ping and in `git log origin/main -- scripts/limit-recover/lr-recon-fence.sh`). Every legacy actor now asks the fence before it touches a session: the poller's request, reroute, resume and nudge arms; `lf_one`; both lr-upgrade drives; cc-lr recover and switch; cc-resume-debt's relaunch; and boot-resume-launch. Acceptance: `lr-recon-fence-callsites.bats` (1..22), `stop-failure-facts.bats` (1..11), `lr-reset-poller-bash32.bats` (1..2), `cc-lr-request.bats` (1..14), `lr-recon-fence.bats` (1..24), `operator-readout-recon.bats` (1..5), `launchd-parity-lint.bats` (1..18), and `bash scripts/launchd-parity-lint.sh --fixture` PASS (39 SSOT copies clean, one drifted reconciler plist flagged alone). The poller and `lf_one` call-site cases are in `lr-recon-fence-callsites-poller.bats` (1..22) and `-fleet.bats` (1..7), because those files had different owners. The existing hook, poller, fleet, cc-lr, upgrade, debt, boot-resume and readout suites stayed green, and so did the 229 lr_recon unittests. The box sat at load 200 or more on 10 cores the whole wave, so every bats run went through a recorded `cc-bats` waiver, one suite at a time.
  - **One gate for every caller:** `lr_recon_may_act <sid> <role> [always]` in `lr-recon-fence.sh`, paired with `lr_recon_act_done`. A "lapsed" verdict acts only while the caller holds `locks/<sid>.launch`, exported as `LR_LAUNCH_LOCK`. `always` (cc-resume-debt, boot-resume-launch) takes the lock on every act. A child that inherits a live lock for the same sid acts under it and never releases it. `lr_recon_live` means recon.on is present and the heartbeat is fresh. Every take is logged to `recon/launch.log`.
  - **A detached driver must not inherit a lock:** cc-lr releases its lock before it fires `lr-fleet --one --detach`, and `lf_one` takes it again under the driver's own pid. Inheriting it would leave the driver acting on a lock that cc-lr's EXIT trap drops about 3 s later.
  - **Requests:** cc-lr and `lr-fleet --enqueue` write `requests/<sid>.cc-lr.json` while the reconciler is live. The poller leaves those files alone while it is live and drains them when it is not, so none strands. A request superseded by a live run now moves to `claimed/` instead of being deleted.
  - **Producer facts:** under recon.on, stop-failure-marker writes one fact per death through `python3 -m lr_recon.facts hook-write`. The scope comes from, in order: an auth error, the rateLimitType (5h or 7d), or the model named in the limit text (fable or model:<name>). The teammate test now parses the transcript head (`"agentName":null` is no longer a teammate). With jq missing, the hook still exits 0 with empty stdout.
  - **Backup watchdog:** under recon.on with a stale heartbeat, the poller pages at most every 15 min and runs a bare `launchctl kickstart` (never `-k`). The readout shows the stale warning even when no cohort is open.
  - **Readout:** the daemon writes `recon/readout.line` every pass, and `operator-readout.sh` reads it with builtins only. The line names each HOLD-BGWORK session with the time it will page: 60 min for a ship-land job, 20 min otherwise (decision 2). `cc-lr cohort refire` writes `recon/ctl/<sid>.refire.json`; the daemon re-arms that member through classify and moves the file to `ctl/done/`.
  - **boot-resume-launch** exits 5 for every "not ours to launch" case: the reconciler owns the sid, its lock is held, it has a live holder, or it is PARKED-REBOOT in page mode. `boot-resume.sh` counts rc 5 as held, not failed. The launched window runs `zsh -ic '<resume>; exec zsh -i'`, so it stays at a shell after claude exits. The reconciler stores PARKED-REBOOT in `substate` under `recon/sessions/`, not `records/`.
  - **Carried TODO:** W3's local stale predicate in `census.py` stays. The sibling's `rq_stale_reason` is on trunk (`49c16be7e`), but it lives inside the poller's executable body and has not been extracted into `lr-lib.sh`, so there is nothing to import. Moving it would edit sibling-owned drain code.
  - **For W5, not yet exercised:** (1) In the lapsed case, `lf_one`'s launch-lock holder is still alive when W2c's `lr-fire-resume` starts in the new pane. `lr_launch_guard` accepts only the same record and attempt, its own pid or a stale holder, so it would refuse with rc 10. The legacy lock needs a record/attempt hand-down across the pane boundary before a crashed reconciler can fall back to manual tools. This never happens today, because recon.on is absent. (2) cc-resume-debt's in-pane relaunch never fires, because `cc-pane` has no state verb, and it has not been run against W2b's real `--relaunch-at-shell`. (3) `lr-handoff` main has no fence of its own; its W4 callers (`lf_one`, cc-lr) fence before calling it, and `recycle_fire`'s fence belongs to W2b.
  - Blockers: none.
- 2026-09-29, **W2b done** (session fire-w2b; teammates T-probe, then T-recycle-a and T-recycle-b in sequence, because all three edit `handoff-fire.sh`). The probe half landed first, as the plan's checkpoint (`6ed411ee0`, `95d54abd5`), and the recycle half lands with this entry: `git log origin/main -- scripts/handoff-fire.sh tests/handoff-fire-recycle-custody.bats`. Acceptance: `tests/handoff-fire-recycle-custody.bats`, which holds cases 1-13 plus 1b, 12b, F (focus), P (1 s poll) and X (launch-lock prefix). The existing handoff-fire*, handoff-recycle* and probe suites stay green. Learnings and decisions later waves need:
  - **Probe output, which W3 T-observe and T-act parse:**
    - After `pane_state: cc`: `tty:`, `window_id:`, `kitty_pid:`, `kitty_lstart:`, `pane_root: <pid> <comm>`, `focused:`.
    - `bg_work: <none|watcher|work|unknown> shipland=<yes|no> pids=<…>`.
    - Verdicts: `HELD:bg-work:ship-land` and `HELD:bg-work:other` (the reconciler pages at 60 or 20 minutes), `HELD:mid-turn` (voluntary path, transcript in flight or unreadable), `HELD:focused`.
  - **The evidence bypass.** `--voluntary --account-evidence F` passes only a fact that is `rejected`, uncontradicted, `5h` or `7d`, has `resets_at − now ≥ 1800 s`, and names the pane's own account. The registry row's `.account` is a config-dir basename, so the probe maps it through the generated account map, and an unmapped basename refuses as `account-unmapped` (a W5-rig finding, fixed here). `--account-evidence` without `--voluntary` is a usage error (exit 2). Callers without the new flags get today's limit-gate lines byte-for-byte.
  - `lr-predicate.sh is-teammate-head` takes a transcript PATH (with `LR_HEAD_BYTES`), not stdin. If it is unreachable, the probe falls back to the old substring test.
  - **Recycle order is now:**
    1. fence, focus gate, composer gate, pane recycle lock;
    2. watcher armed, plus `HF_WATCHER_RECORD`;
    3. wake guard, then confirm (`--record-id` only when set: W2a's CLI rejects an empty value);
    4. the last read: composer, at rest or still limited, subagents, background work, focus;
    5. debt, then `/exit` typed without Enter, read back, with Enter only on an exact match. Otherwise the watcher sends five DELs.

    Any refusal after confirm calls `lr-transplant --phase unconfirm` and holds with `recycle-held-<reason>`, whose detail records `unconfirm rc N`. The blind anti-strand Enter is gone from the recycle path; self-close keeps its own.
  - **The watcher:**
    - It polls for the shell every 1 s.
    - It FOLDs a stub through `--phase fold-stub`. An rc 2 holds without typing, and an rc 3 falls back to the legacy append.
    - Before typing, it takes `locks/<sid>.launch` and re-checks `lr_holder_count`.
    - The background-work dialog is recognized in both shapes. When the menu has no keep-work option, which is the agent-view-off shape and a W5-rig finding fixed here, or under `CC_RECYCLE_BGWORK_ANSWER=cancel`, the watcher sends exactly one Esc and records `recycle-held-bgwork … unconfirm=needed`. It never types a digit.
  - **Launch-lock handover (W2c contract).** `lr_launch_guard` counts a holder as its own only when `record_id` and `attempt` both match, so the resume-mode relaunch is typed as `nocorrect env LR_LAUNCH_LOCK=… LR_RECORD_ID=… LR_ATTEMPT=… bash <launcher>`. With no reconciler record, the watcher mints one.
  - **New verbs:**
    - `--recycle --transplanted-source --husk` skips confirm. It asserts that `.handed-off` exists and that the tombstone names `--resume-cfg`.
    - `--relaunch-at-shell` checks the launch lock, then H(sid), then `pane_cc_state=shell`, then the identity tuple. It then execs the same watcher.
  - **Kill switches** (default on, `off` restores today's behaviour): `HF_RECYCLE_LOCK_GATE`, `HF_EXIT_READBACK`, `HF_FOLD_STUB`, `HF_LAUNCH_LOCK`, `HF_BGWORK_ANY_SHAPE`. Two more: `LR_MOVE_FOCUSED` (default off, so a focused pane is HELD, per decision 7, unruled at the time; ruled 2026-09-30: move once W6f flips the default) and `LR_WAKE_GUARD_S` (default 30).
  - **Incident.** T-recycle-a stalled for 30 minutes on a Bash permission prompt for `rm -r` of its own /tmp scratch dir. A teammate's permission prompt routes to the lead, and nothing in the lead can answer it. The lead checkpointed the work, stopped the teammate, and fixed what it had not reached. Later briefs forbid deletes outside the repo and keep scratch under `$BATS_TEST_TMPDIR`; T-recycle-b ran clean under that rule.
  - Blockers: none.
- 2026-09-29, **W5a in progress** (session fire-w5, lead-inline code: the stub, driver and daemon fixes co-evolved with every integration defect, so one author; a read-only agent extracted the stub contract). Branch `lr-fv2-w5`, 18 commits, not yet landed at this entry; `git log origin/main..lr-fv2-w5` lists them. Operator step 1 is written and pinned (`scripts/limit-recover/lr-recon-launchd.sh`, `tests/lr-recon-launchd.bats` 1..7) and not yet filed. The rig runs end to end: a one-session cohort ENGAGEs in the same window with the same uuid about 30 s after detection, the DoD line matches the matrix-derived one, the launch-log audit and the planted-row refusal pass. A 12-session run ENGAGEs clean, swallowed-Enter, 529 (via C-retry), daemon kill -9, clock-skew and legacy-holder sessions, holds the draft and bg-work sessions, and hops TARGET-LIMITED and TARGET-AUTH as new attempts.
  - **The rig:** `tests/rig/lr-recon-rig.sh` isolates everything by `HOME=/tmp/lr-rig/home` (the generated account map resolves `$HOME/.claude-*`, so four throwaway config dirs need no code change), `LR_STATE_DIR=/tmp/lr-rig/lr`, `LR_RECON_ROOT=/tmp/lr-rig/state`. A detached supervisor plays launchd (KeepAlive with a 10 s throttle, the watchdog every 30 s). Recovery is requested the operator's way, `cc-lr recover --limited --account next`, because census-origin records stay PLAN-ONLY without `autorecover.on`; a matrix with idle sessions writes `autorecover.on` and `LR_IDLE_FANOUT=on` under the RIG root only. The rig plist now matches the DoD command (`/tmp/lr-rig/state`, its own HOME).
  - **Stub contract** (the read-only agent's findings; the full contract is not committed): a Python stub is not `claude` to the scripts unless argv0 ends in `/claude`, which only `exec -a` onto the framework's `Python.app` binary keeps (`tests/rig/claude`). kitty wraps a launched shell in `login`, which lr_recon reads as a launcher root, so panes launch via `/usr/bin/env zsh`. The screen reads need `CC_PANE_ID`/`ITERM_SESSION_ID` and `CC_TERM=kitty` in the pane, and `~/.claude/bin/it2` is `bin/it2-wrapper`.
  - **Integration defects fixed in lr_recon (each with a test that fails on the old code):** the daemon loop never started (`Caffeinate()` without a pid; only `--once` had run). Actuator exits were never read, so a refused move re-spawned every 3 s (`settle.py` now settles each exit through the precheck's named refusal or `classify`). The derived action was discarded. ENGAGED's offset rule rejected the first append after the transplant (`>=` not `>`). `confirm_len`, the submit token and `timeline.submitted` were never set. A confirmed move fell back to PLANNED in the relaunch gap and was dispatched a second time (now IN-FLIGHT; the audit counts a second move spawn per attempt as a double typer). C typed a second prompt while lr-fire-resume's own was landing (C now needs 60 s of quiet). Holds never cleared (census re-bucket, draft re-probe every 2 min). Auth cliffs wrote no fact. Hops overwrote their own substate. A stale request and an R replacement left no cohort member. tty presence used the device node, which macOS never deletes, and a freed tty number is re-used within seconds (now the pane root's pid+lstart). A capacity-shed actuator escalated instead of waiting, a WAIT had no eligibility time, and `should_rearm` was never called.
  - **Outside lr_recon:** `lr-handoff` passes `--voluntary` beside `--account-evidence` to the probe (every idle move was refused), types the reconciler's token under `LR_PLACED_BY=reconciler`, carries record id and attempt call-scoped into `lr-fire-resume` (which logs its launch-lock take), and accepts a live `auth` fact as evidence (lead decision, 88%). The fence logs `attempt=`/`record=`. `cc-lr status --cohort` takes `--root` and prints the `DoD:` line (`report.dod_line`, both plan shapes).
  - **Queued for after W2b lands, rebased, one writer at a time (lead decisions):** in `handoff-fire.sh`, `hf_account_evidence_check` accepts scope `auth` (pins: a live auth fact passes with `--voluntary`, an expired one is refused, and an auth fact without `--voluntary` is still refused), and `hf_transplant_evidence` takes the chain tip instead of refusing a multi-hop session (pins: 2-hop and 3-hop resolve to the tip; a fork refuses; a cycle or a missing destination store refuses; the refusals keep the "disambiguate by hand" message). W2b itself fixes `hf_account_evidence_check` comparing the fact's account name with the registry's `claude-<suffix>` basename (every voluntary move is refused as account-mismatch).
  - **Still to exercise in the rig (they need W2b's husk and UNCONFIRM paths):** bg-work after confirm (Esc, UNCONFIRM, HOLD, then recovers), draft after confirm, the stub re-created during the husk (the fold audit's evidence path must move out of `sessions/`), idle MOVED ×3, and the two hops end to end. Then the N=5 and N=30 DoD runs, the land, the converge, and filing operator step 1.
  - **Measured on this box:** load sits at 50-55 on 10 cores, so capacity-admit sheds resumes (boot-resume-launch exit 9) until its refusal budget is spent. A 200 s SIGSTOP is usually not killed by the watchdog, which needs roughly 210-240 s of stall to convict; the session ENGAGEs either way.
- 2026-09-29, **W5a continuation, interim land** (session fire-w5c; superseded fire-w5 after it froze ~50 min on a heredoc permission prompt; lead-inline plus read-only diagnosis agents and teammates t-settle, t-plan, t-hf with disjoint file ownership). Lands everything green so far; the N=30 DoD line is NOT yet met, see the last bullet.
  - **N=5 PASS** on the landed code: `ENGAGED 5/5 · same-window 5/5 · same-uuid 5/5 · double-typer 0 · split-brain 0 · lost-records 0 · p95 detect→engaged <= 120s`, measured p50 22 s / p95 22 s detect→engaged, cohort wall 323 s (the 300 s sentinel included); launch-log audit 1 typer and 1 move spawn per (sid, attempt); the planted non-rig row REFUSED. The rig now prints these timings (`rig_lib.py timings`, from the daemon's records).
  - **Queued items done:** an `auth` fact is voluntary-move evidence in `hf_account_evidence_check` and lr-handoff (live without `resets_at`, expired once `resets_at + 60 < now`, per account, only beside `--voluntary`); `hf_transplant_evidence` resolves a multi-hop session to its chain tip (`hf_ts_chain_tip`, pins in `tests/handoff-fire-transplant-chain.bats`: 2-hop, 3-hop, fork, two-into-one, cycle, cycle beside a chain, missing store); B2 was already pinned; the IN-FLIGHT relaunch gap is owned for `IN_FLIGHT_MAX_S`.
  - **Integration defects the rig found, fixed with a pin each:** kitty flags `is_focused` on the active window of EVERY tab in the focused OS window, so the W2b focus gate held every background-tab pane (in the real fleet, every limited pane in the operator's frontmost window); focus is now the OS-window ∧ tab ∧ window conjunction. handoff-fire's main parser lacked `--record-id` (only `--relaunch-at-shell` had it, so lr-handoff's grep detection was a false positive and every reconciler recycle STRANDED its husk). A STRANDED verdict is never terminal (a usage dump's "headless" had scored IMPOSSIBLE on moved sessions). boot-resume-launch's `CC_ADMIT_DONE` never reached the new window (R re-gated inside it after rc 0). The daemon never set `rec.bundle` (every A-husk/B got `--resume-launcher ""`), never read the watcher's `recycle-held-* unconfirm=needed` row, trusted a `confirm_len` that an unconfirm had undone, re-fired R each pass with no proof deadline, blamed a move's target for its source's copied death record (phantom 5h facts), hopped over a contradicted auth fact and over a still-live watcher, and parked an auth hop in WAIT_RESET (a dead end). The stale-request reconcile checked only the live holder's path (false NOT_NEEDED for sessions mid-move; the dead session's record landed in an orphan cohort). The watcher could not see the target answer with a limit or auth failure and held the pane lock for its whole timeout; the last read took a re-created stub alone as "limit cleared"; lr-handoff called a held-and-unconfirmed recycle STRANDED.
  - **Rig isolation defect, now closed:** the R window is built from kitty's (the operator's) environment, so its resume engine ran under the real HOME and wrote the real `~/.claude/autonomy/capacity-admit/reso-resume-one.refusals` (value 3 at 06:58; a consecutive-refusal counter that resets on the next admit; not restored, since its prior value is unknown). No real claude was started. The R launcher now re-enters the rig, and each run prints any real-HOME capacity-admit write.
  - **Open at the interim land (since closed, below):** second N=30 run, 24/30 settled after 15 min; still diverging: target-auth ×2 (PLANNED, DETERMINISTIC), draft-after-confirm (PRE-MOVE/None), bgwork-after-confirm (HUSK-RETIRED held), pane-closed-after-exit (the R window read LAUNCHER-ROOTED), one clean-idle stuck IN-FLIGHT.
- 2026-09-29, **W5a DONE (rig half)**. The recycled session (pane 1102, sid 4abeeb5d) froze on a bare `git stash drop` permission prompt (approving would have dropped another session's stash@{0}); the lead made fire-w5c's surviving background process the owner. Its teammate t-recon2's seven lr_recon commits were collected by `cherry-pick -x` (a6130bc00, ea6fb2d06, 496500a83, de6d0f95e, f4102a0f2, 05b11aab6, 3945b1606).
  - **N=30 PASS:** `CLOSED 24/30 (ENGAGED 21, MOVED 3) · HOLD named 4/30 (draft 2, bgwork 2 — the 3rd bgwork recovers after its job ends) · REPLACED-NEW-WINDOW 1 · NOT_NEEDED 1 · double-typer 0 · split-brain 0 · lost-records 0 · unowned-non-terminal 0`, equal to the line derived from `faults/matrix30.json` before the run; measured detect→engaged p50 51 s / p95 73 s over 24 engaged, cohort wall 489 s. Launch-log audit: 42 (sid, attempt) keys, max 1 launch-lock taker and 1 move spawn per key; fold audit sha(target) == sha(retired + stub). N=5 re-run on the same code: PASS, p50/p95 22 s, wall 322 s.
  - **Round 2, fixed with a pin each:** actuator exit codes were stolen by unrelated `subprocess` calls (Popen kept); an unconfirm with no recorded `confirm_len` never cleared IN-FLIGHT; `lr-transplant` rejected the daemon's `--source-pid/--source-lstart`; an identical UNCONFIRM failure never escalated (held-row latch per attempt); an auth-cliff API-error record read as a turn in flight (both at-rest mirrors); an auth hop stays reversible until its new attempt confirms; a recovered death was re-recorded by the census; the rig filter hid an owned sid; IN-FLIGHT past its bound is a failure; the watcher's Esc on the bgwork dialog left its own `/exit` in the composer (read as a draft forever; scrubbed only on an exact `/exit` read-back); the resume-debt drain inherited the record id and relaunched beside R as "own-actuator" (the fence now defers it); R went out under A's attempt (a second move spawn opens a new attempt); the stale reconcile was never given the account stores (a dead session's member landed in `unknown-none-0`). The rig stub now answers `--version` like Claude Code.
  - **Learning — teammates:** round-1 teammates finished, went idle and never drained their inbox (no final report; round-2 assignments never received); a finished teammate is not a reusable worker. **Learning — prompts:** both W5a successors froze on a permission prompt with nobody present (a heredoc edit, then a bare `git stash drop`).
  - Operator step 1 filed: backlog `0810a1f8a508` (not run). Blockers: none.
- 2026-09-29 (programme lead, pane 966), **build complete through W5a; W5b waits on operator step 1.** Every wave's sha is an ancestor of origin/main: plan `d4d7e4aec`, W0 `55e4cbf07`, W1 `e6683d61b`, W2a `e933d0bdc`, W2b `31a3bcbc7`, W2c `dd43fd728`, W3 `6d6928d5e`, W4 `fe39ed003`, W4-wf `ac2dccaba`, W5a `fd57b0dc3`, and the lead's trunk-red fix `1262c130c`.
  - **Measured.** N=5 took 322 s of cohort wall time, with detect→engaged p50/p95 22 s. N=30 took 489 s, with p50 51 s and p95 73 s over 24 engaged. The design estimated both p95 values at ≤ 120 s.
  - **Remaining programme DoD.** Items 3-7 (canaries, shadow, live parity, the first acting cohort, zero-human) need the real launchd jobs loaded (operator step `0810a1f8a508`). The live observe census was classifier-denied (operator step `f0df9145b73a`). The W5b fire is filed as `8e67a18de9ad` (not-yet-true; it retracts itself once `recon/mode` reads `act`).
  - **W5b fire recipe.** Once the jobs are loaded, one dispatched session runs the four canaries, the shadow comparison over two real cohorts, and the cutover, using this section's W5 text as its brief plus the prompt-discipline rules in `docs/lessons/a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md`.
  - **Lead learnings.**
    - Two of the plan's dependency edges were conservative: W1 and W2a read nothing from W0 and ran beside it, and W5a built its rig before W2b landed. Accounts, not the graph, bounded the fan-out: `next` and `next4` sat at KMAX at the first fire.
    - The rig was the first run of W3 against the real W2 flags. It found about 30 integration defects that 223 unit tests against the frozen contract could not see, including the account-name mapping, the 2-option bgwork dialog, the transplant chain tip and the TARGET-AUTH hop. Plan the first rig run as early as the actuators exist.
    - Three unattended sessions froze on permission prompts (a teammate's `rm -r`, a heredoc edit, a bare `git stash drop`). Recovery was a supersede by patch, never a keystroke. The lesson is extended in the file named above.
    - Decisions taken at the lead: TARGET-AUTH hops on a per-account `auth` fact (88%), and a multi-hop transplant resolves to its chain tip (90%).
  - **Residue, named.** The rig once wrote the real `~/.claude/autonomy/capacity-admit/reso-resume-one.refusals` (value 3, 06:58). Its reset was classifier-denied as local destruction and was left. It self-heals at the next `reso-resume-one` admit; the worst case is one early forced admit and one page.
- 2026-09-29, **W5b real canaries: 4 of 4 PASS; shadow waiting on real limits; cutover not yet** (session fire-w5b, pane 1308, lead-inline; one read-only agent mapped the legacy stores). Evidence and every run's transcript: `docs/research/lr-recon-w5b-2026-09-29/`.
  - **Vehicle.** The canaries could not run on the live job in act mode: that needs the operator's `recon.on`, and the hook lane was the live actuator. So `LR_RECON_CANARY=<sids>` became a scope (`371128ac0`): the daemon sees and acts on those sids only, from its own tree `recon-canary/` with its own switch `canary.on`, shares the real locks/runs/ledger with every legacy actor, and the fence defers legacy actors to a canary-owned sid. Faults 2 and 3 use `HF_CANARY_HOOK`, inert without `LR_RECON_CANARY`. Driver: `tests/rig/lr-recon-canary.sh --canary N` (one throwaway haiku session per run on `next`, its own kitty OS window).
  - **Verdicts** (each `cc-lr status --cohort` read `CLOSED 1/1 (ENGAGED 0, MOVED 1) · … · double-typer 0 · split-brain 0 · lost-records 0`, same window, same uuid, cross-account): 1 idle no-prompt move next→next4; 2 draft after confirm → HOLD, UNCONFIRM, HOLD-DRAFT, re-plan next→next3, MOVED; 3 watcher SIGKILLed after `/exit` → B in place, engaged by process, next→next2; 4 reconciler SIGKILLed 5 s after its move spawn → restarted, actuator adopted, one `/exit`, next→next4.
  - **Seven real defects the rig could not see, each fixed with a pin red on the old code** (`git log origin/main --grep 'W5b' --oneline` lists the fixes): a `next` session's source config read as `~/.claude` through the symlinked `sessions/` (plus a PRE-MOVE source refresh, so records the pre-fix observe daemon wrote heal at cutover); `LR_PRESEED_DONE` claimed a trust preseed nothing ran (`bf00f9045`); the resume launcher pinned its minted attempt, so B could never succeed; a placed move mailed the session it was moving, which woke it mid-move; the husk's background-work gate read the stub alone and held an at-rest session; a held husk re-spawned every ~4 s, 181 times; a no-prompt relaunch was judged by an assistant turn, and the late rc 1 re-opened a MOVED record. Canaries 1-2 passed their first engagement check only because their sessions happened to take a turn.
  - **Shadow.** `tests/rig/shadow_lib.py` computes the three gate checks per cohort; its `watch` archives each live cohort (the observe daemon reaps facts and overwrites `shadow/<cid>.json` every pass) and mails the waiting session. No real limit since the observe daemon started at 17:42Z.
  - **Census step** `f0df9145b73a` closed with the launchd daemon's own observe pass (0 actuations, degraded none).
  - **Learning — a peer's mail is a keystroke.** A real session's inbox watcher turns any mail into a turn; the mover must not be the sender, and any mid-move turn must leave the husk path recoverable. **Learning — engagement proof must match the prompt.** A no-prompt move owes no turn; judging it by one is a coin flip on whether something else woke the session.
- 2026-09-30 (origin lead, pane 954): **operator ruled all six open decisions "as recommended" after an exhaustive re-research** (Dynamic Workflow `wf_4da836fc-d58`: 115 agents, 0 errors; 3 lenses per decision, up to 3 drivable-question rounds, 2 skeptics + adjudication, a cross-decision critic that raised 22 issues). Two recommendations changed: decision 3 is now always-wait (the hybrid's least-thin move is not built), and decision 7 moves a focused pane only after five on-path fixes land. The critic's issues change how each ruling is built, not its direction; the lead's 15 resolutions and the W6 waves are in § W6. Evidence: `docs/research/lr-fleet-v2-decisions-2026-09-30/rulings.json`. Also landed today by a lead-fired session: a recycle clears the predecessor's `/goal` before moving it to the background (`c26948b8d`, `981cb302c`, research `077e401ab`).
- 2026-09-30, **W6a-W6d landed; W6e docs landed with this entry; W6f open.** Four code waves ran as dispatched sessions (W6a pane 1338, W6b 1339, W6c, W6d 1341), with early-land relays through the lead (`lr_focus_gate`, `lr-page.sh`, `lr-team.sh`, `lr-composer-snapshot.sh`). Every sha below is an ancestor of origin/main.
  - **W6a** (handoff-fire, lr-handoff, lr-lib): `04d42c170` `4dfecf11d` `42fd80397` `3e9bc100b` `7bb905db7` `0234a15da` `09d1a37aa` `450954178`, and D4.0/D4.2 `b6321a910`.
  - **W6b** (poller, lr-fleet, lr-upgrade): `7a70cf9e2` `5aa5610b3` `72dda9cb6` `17fbdee45` `62ec919ce` `be5561e27` `7e16ce5f7` `fe39ee835` `034f30edf` `af18e7abf` `27a007c40`.
  - **W6c** (router): `2dbf35a85` `75b0f84a0` `ad21bf402` `4d1b569cc` `90ae83707` `30d6bb335`.
  - **W6d** (reconciler, page channel, rig): `6cd769a08` `4c3fc715f` `8ac0fa5e6` `0b31c89be` `f8f1e07ea` `de71c990d` `cc624e797` `3ba89226e` `b5740ca25`.
  - **W6e** (docs): the decision records in § W6, the kill-switch and decision-table corrections, the architecture corrected to the as-built code (§ 1 vendor-continue fact, § 5 `b_sess`/`(n+1)`/mover weight, § 15 team leads), and the decision 8 evidence note (`docs/research/lr-fleet-v2-decisions-2026-09-30/kmax-decision-8.md`). `git log origin/main -- docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md` lists its commits.
  - **KMAX re-based after D1.8:** the cap bound in 11 of 12 account-sweeps before the working-count fix and 4 of 12 after (`kmax-rebase.md`). D1.8 loosened KMAX in effect, as the critic predicted; the ruling to keep 8 is unchanged.
  - **Operator decision open:** D7.2(a) (the handed-off guard and the transplant tombstone phase) was refused by the auto-mode classifier as a shared-resource edit, so it is filed as decision `28740361e7dd` (conviction 85%, allow recommended) with the patch staged. W6f waits on its ruling.
  - **Finding: the background-work dialog wraps at 29 columns.** At that width `pane_bgwork_dialog`/`pane_bgwork_choice` return rc 1 where the unwrapped dialog returns rc 0, which is the root cause of the self-recycle deadlock under a live `/goal` (W5b evidence `handoff-recycle-1308-1790740312-14A3O3.log`). The fix spec (join rows before matching, the nudge classifies the modal, 29/40/80-column fixtures) went to W6a and is not yet on trunk.
  - **W6f still owes:** D7.6, flipping `LR_MOVE_FOCUSED` to default on in handoff-fire and `census.py` (gated on decision `28740361e7dd`); D6.3's remainder, switching `lead-supervisor.sh`'s own Notification Center page to `lr-page.sh`; and the four "decision 7 unruled" code comments (`census.py:165`, `types.py:73`, `handoff-fire.sh:2835`, `:14768`). Then the operator restarts the reconciler so the new defaults load.
  - **Operator steps:** the Pushover credentials for the phone leg (backlog `516d31862158`); the reconciler's own zero-human marker after the first attended reconciler cohort closes clean (D1.14, backlog `be52a4c8a99f`); the reconciler restart after W6f.
- 2026-09-30, **W6f landed: focused panes move by default.** Prerequisites checked on origin/main first (D7.1 `09d1a37aa`, D7.2(a) `8cd6bb953`, D7.2(b) `7bb905db7`, D7.2(c)/D7.4/D7.5 `42fd80397`, D7.3 `3e9bc100b`, D7.5 `450954178`; custody 1..36 and bgwork-dialog 1..24 green). `edcf4806e` flips `LR_MOVE_FOCUSED` in `lr_focus_gate` (the one rule every typing path calls), handoff-fire's `_it2_type_line` and `census.py`: unset moves, only `=off` holds; lr-lib unreachable still holds. The "decision 7 unruled" wording is gone from `scripts/` (the only `unruled` left is two test assertions that it is absent). `c883cd181` routes `lead-supervisor.sh`'s page through `lr-page.sh` (D6.3), keeping `CC_SUP_OS_CHANNEL` as its switch; `cc76d81a7` revives two dead assertions the land gate caught. 7 of 7 mutants killed. Operator step still open: restart the reconciler so `census.py`'s new default loads (until `recon.on` exists this changes only shadow records). Unrelated, found in passing: `tests/osa-bounds.bats` test 7 is red on trunk over `scripts/coreaudiod-watch.sh:165`, a printed hint the lint reads as a call.
- 2026-09-30, **W7a landed: a census the reconciler cannot trust decides nothing** (backlog `fcb4b148c86a`, `8e67a18de9ad`; commit `fix(lr_recon): an untrusted census abstains, and the ps read survives load`). Every recorded 0-claude census was `degraded: ps`, a failed read rather than a matcher miss. A live degraded pass at 19:09Z (load 344) escalated 4 live sessions as "no holder" (`docs/research/lr-recon-census-2026-09-30.md`). `observe.untrusted()` is now the one gate in `run_pass` ahead of every deciding stage. It trips on ps degraded, on fewer claude processes than half the claude panes kitty shows, or on a drop from 8 or more to under a quarter of the last reading. The pass then leaves one `abstain` event, the readout-line note and `last-pass.json` `abstain`. `read_ps` scales its bound with load (20-40 s), retries once inside a 90 s budget and records why it failed. `plan.kwork`'s `ps` check stays as a unit-level guard. Operator step: the reconciler restart already owed after W6f also loads this.
- 2026-09-30, **W7b landed: the three W5b2 shadow defects on the final code** (backlog `fcb4b148c86a`, `8e67a18de9ad`; four `fix(lr-recon)` commits, evidence in their bodies). **B:** the census owns the reboot park. `census.park` sets PRE-MOVE / PARKED-REBOOT with a named wait, `_derive` skips a parked record and `may_actuate` refuses one, so cd3bd860 stops flapping (408 stale and 408 RECON-DEFECT events an hour) and R can no longer run boot-resume-launch.sh for it; its status now says boot-resume owns the relaunch. **A:** `_report` keeps each cohort's reset (the cid's own key) and opening (its first member's detection) from the cohort file, so the file, the open and close pages and the shadow's stop-marker window stop reading null and 0. **C:** `settle.engaged_elsewhere` closes a record whose one live holder runs under neither its source nor its own move's target and has taken a healthy turn since detection (CLOSED via ENGAGED, `close.by` elsewhere), ahead of the park and the escalation re-arm, so it never pages ESCALATED or IMPOSSIBLE. Grown: `evidence._debt_open` reads a resume debt's own state; every debt's history starts "open", so a proven debt had read as open and derived R. Unit suite 416 OK, mutants 34/34 killed. A dry pass of the new code on a copy of the live tree settled 4d7c9bce, ceaa8922 and cd3bd860 as engaged elsewhere and re-parked the three iTerm records with 0 defects; its second pass logged no event. Operator step: the reconciler restart (the lead files it), after which W5b2's cutoff and cohort count start over.
