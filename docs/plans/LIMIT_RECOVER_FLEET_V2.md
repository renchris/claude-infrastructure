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

No wave runs as T or L on the lead.

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
- `LR_DRAFT_STASH=off` (default).
- `LR_TEAM_UNIT=off` (default).
- `LR_HEAL_CORE_BARE=off` (default, until the operator rules).
- `CC_RECYCLE_BGWORK_ANSWER` is forced to `cancel` for reconciler actuations.
- `LR_RECR_SCHEDULE` (default `10,25,40` until W0 measures).

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

### Cutover
Write `recon.on` and `recon/mode=act`. The first real cc-lr-origin cohort (the operator or a lead runs `cc-lr recover --limited`) is the live LIMITED canary, and its DoD is the cohort status line with zero double-typer and zero split-brain in the 5-minute sentinel log.

**Goal:** `W5 gates passed and cut over — proven by the N=5 and N=30 rig DoD lines printed verbatim, the 4 canary status lines, the shadow diff for 2 cohorts, and 'cat ~/.reso/limit-recover/recon/mode' printing act; do not create autorecover.on and do not enable LR_HEAL_CORE_BARE; full brief above`

---

## Measured Definition of Done (the whole programme)

1. **Unit gates:** every bats suite named in W1-W4 plus `python3 -m unittest discover scripts/limit-recover/lr_recon/tests` print 0 failures on the landed trunk sha, and are re-run after the last rebase.
2. **Rig:** the N=5 and N=30 lines exactly as specified, and the launch-log audit shows at most 1 typer per attempt.
3. **Canaries:** 4 of 4 CLOSED, pane-in-place (same window ids, same uuids).
4. **Shadow:** 2 real cohorts, with zero census misses and zero phase disagreements after resolution.
5. **Live:** `launchd-parity-lint` is green including `com.reso.lr-reconciler*`; `wrap-ledger.sh --machine` shows LIVE_ADDS=0; `recon/heartbeat` progress advances across two reads 30 s apart.
6. **First real acting cohort:** every member is CLOSED, or held in a named WAIT/HOLD within its maximum age, 10 minutes after the last death. Zero split-brain in the sentinel log.
7. **Zero-human:** once the operator creates `autorecover.on`, a hook-origin cohort reaches (6) with no human command. The measured detect→OPEN time and p95 detect→engaged are recorded in `docs/plans/LIMIT_RECOVER_100P.md`, replacing the design estimates.

---

## Operator decisions (filed for ruling; until ruled, the recommended default is built behind its kill switch and never enabled)

- Zero-human recovery. Should the daemon act on hook-detected limits without anyone running cc-lr, by your creating ~/.reso/limit-recover/autorecover.on? Recommendation: yes, but create it only after the W5 rig and canaries pass and the sibling session's re-validation has drained the 18 held requests. Conviction: 85%. Options: create it (recoveries start seconds after a death, with no human) / leave it absent (the daemon plans and pages, and moves happen only when a session or you run cc-lr recover).
- Background work at the limit. When a limited session still has a background job running (usually a land), may recovery ever stop that job to move the session? Recommendation: no. Hold the session until the job ends on its own, page at 20 minutes, and never choose 'Exit and stop tasks'. Conviction: 85%. Options: hold (the in-flight land or build survives, and the session waits) / stop after N minutes (the session moves sooner, and the job is killed mid-flight).
- No account passes the survival floors (weekly headroom at least 10%, projected 5-hour under 60%). Should sessions wait for their own reset, or go to the least-thin account? This is the existing LIMIT_RECOVER_100P open decision 2. Recommendation: wait, with every waiting session and its wake time named on the OPEN page. Conviction: 80%. Options: wait (no second limit cascade, longer outage) / least-thin (faster, and the cohort's burn likely hits that account's cap within about an hour).
- Agent-team leads with live members. Should v1 move whole teams across accounts, or hold the team and continue the lead in place when its account resets? Recommendation: hold in v1, then build the cross-account team move in v2 on lr-upgrade's team hold, after a probe. Conviction: 75%. Options: hold (safe, and the team is down until the reset) / move now (faster, on a path /exit's team cleanup can break and that has never run across accounts).
- Repairing core.bare. May the daemon run 'git config --unset core.bare' on a shared checkout that has a working tree, with a separate-read verification and only when .git/config.lock is absent? Tonight the auto-mode classifier denied this exact write to a session, so the daemon will not do it without your ruling. Recommendation: allow. Conviction: 85%. Options: allow (panes in that repo move and work) / deny (those panes are held as HOLD:repo-bare and paged to you).
- Operator drafts. May recovery stash a one-line draft in an unfocused pane, move the pane, and restore the draft without pressing Enter (LR_DRAFT_STASH)? Recommendation: no. Hold the pane and page at 15 minutes. Conviction: 70%. Options: off (your draft text is never touched, and those panes wait for you) / on (a single-line draft that reads back identically twice is stashed and restored).
- Focused limited panes. Should a limited pane you are currently looking at be moved? Recommendation: yes. The new post-confirm read-back makes typing into it safe, and holding it would stall the pane you most likely need. Conviction: 75%. Options: move it / hold it while it has focus.
- Seat cap during a storm. Should the per-account active cap (KMAX=8, against a measured infrastructure limit of 5-6 concurrent requests per account) be raised during a recovery storm so more sessions move at once? Recommendation: no. The design names every waiting session and its ETA instead. Conviction: 80%. Options: keep 8 (fewer parallel moves, no added 529 risk) / raise it (more parallel moves, and more 'server temporarily limiting' refusals on the target accounts).

### Decision research, 2026-09-29 (origin lead; 8 read-only agents, one per decision)

The full table is in the design bundle, `decision-research-2026-09-29.md`. What it changes here:

| # | Status | Revised recommendation (conviction) |
|---|---|---|
| 1 | on since 05:22Z | Keep automatic recovery on (88%). The first unattended recovery (pane 918, 05:32→05:38Z) spent 5 of its 6 minutes waiting for the poller to finish its pass before it reached the request, so the reconciler must start a recovery the moment a request lands (W3). |
| 2 | **SETTLED** | Hold until the job ends. Page at 60 minutes when the job is a ship-land (claude-infrastructure lands take p50 836 s and p95 3456 s, and 30% exceed 20 minutes), and at 20 minutes otherwise (92%). |
| 3 | operator | Hybrid. A 5-hour cap always waits: the median reset is 1.9 h (max 4.5 h), and a second cascade was measured on 2026-09-19. A weekly cap with reset ≤ 6 h waits. A weekly cap with reset > 6 h moves at most 1-2 sessions per pass to the least-thin account, re-checking the floors on each pick (75%). |
| 4 | operator | Hold in v1, and resume the lead in place at its reset, with no `/exit`, so the team stays whole (88%). |
| 5 | **SETTLED** | Allow. The heal already landed in `b509a51f4`: 4 checks, a backup, verification by a separate call, and the `LR_BARE_REPAIR=off` switch (92%). |
| 6 | operator | No. The composer reader strips spaces and truncates by width, and there have ever been only 3 real draft holds (80%). |
| 7 | operator; the gate is built regardless | Move the pane, but behind a focus gate (W2b). The planned `/exit` read-back did not exist: `handoff-fire.sh:1538` sent the text and Enter together (65%). |
| 8 | operator; the probe is drivable | Keep 8. **Correction:** "5-6 concurrent requests per account" was never measured on this machine; it came from GH#62426 and habit. KMAX counts sessions written in the last 10 minutes, not requests, and the first-turn pacer (3 per account) is the burst protection. W0 item 9 runs the burst probe (65%). |

## Provenance

Dynamic Workflow wf_99ea9654-29f (22 agents, 0 errors: 8 subsystem maps, 4 designs, 3 judges, 5 skeptics, 2 synthesis passes). The architecture is `docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md`. The 55 skeptic findings (4 fatal, 30 major) and their dispositions stayed in the design bundle outside the repo.

## Status log

- 2026-09-29: plan and architecture committed (programme lead, branch lr-fleet-v2-lead). Waves fire as dispatched sessions in dependency order.
- 2026-09-29 (lead, `d4d7e4aec` landed): W0, W1 and W2a fired concurrently. The dependency graph drew W1 and W2a after W0, but neither shares a file with W0 or reads a W0 measurement, so they did not wait. W2b and W2c wait for W0, because they consume its bg-work dialog and Enter-readiness measurements. Firing was bounded by accounts, not by the graph: W2a waited about 10 minutes for a free seat on `next4` (both routable accounts were at KMAX).
- Scope (grown): +W4-wf, an early W4 slice fired when W0 lands. After a move, a Workflow run whose dangling slots precede completed ones must get a salvage-seeded continuation, never a plain `resumeFromRunId`, which re-spends the finished slots (session 7c395da7 re-ran about 24 audit agents on 2026-09-28). Target: `scripts/limit-recover/lr-audit.py`, whose ACTION table and run-level gap rows feed the relaunch bundle. No other wave owns the file, so it does not wait for W3.
- Operator decision 5 (core.bare): the sibling's heal (`lr_heal_bare_checkout`, switch `LR_BARE_REPAIR`, landed `b509a51f4`) stays as landed and is reverted only on a "deny" ruling. The reconciler honours `LR_HEAL_CORE_BARE=off` by exporting `LR_BARE_REPAIR=off` into every actuation (W3 T-act).
