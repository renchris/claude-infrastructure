# B3 — delivery target: does a limit-recover verdict reach the session that asked?

**Answer first.**
- **Mostly no, and the loss happens before any inbox is written.** In the last 7 days, 59 of 65 detached `lr-fleet --one` verdicts were never enqueued. They went to `cc-notify --role desk`, but no desk role file exists, so each returned `verdict=unresolvable enqueued=0 reason=role-unset`. 37 of those 59 needed a human: FAILED, HELD:* or PARKED.
- **`cc-lr recover` while the reconciler is live has no return path at all.** The request does not record who asked. The reconciler's requester mailer has no production caller. When the poller drains the request instead, it rejects `mode=recover` and parks the request in `results/`, where neither drainer reads it. This happened live at 03:56:01Z and 03:57:21Z today (5507881f, 58d3640a).
- **The inbox, drain and recycle-forwarding layer works.** 186 of 187 limit-recover verdict lines enqueued in 7 days were acked. That includes `[forwarded:223]` mail adopted across a recycle (NOTMOVED=7 → session ecb81dfc, acked).
- **For a hook-filed request (516b9da9), the requester is the literal string `stop-failure-marker`, not an address.** The human-facing session is the subject itself in kitty pane 212. Nothing addresses that pane, the hook prints nothing, and the verdict goes to the unset desk role. The phone fallback reached nobody: 51 sends damped, 8 unwired.

Store and window: `~/.reso/limit-recover/fleet/one-*/{verdict.txt,detached.log}` and `~/.claude/mailbox/*.md` (+ `.seen`/`.acked`), 2026-10-04T03:52Z → 2026-10-11T03:52Z.

---

## B3-1 — Daemon-dispatched recoveries mail their verdict to an unset `desk` role, so nobody receives it

- **Symptom.** A limited session recovers, fails, or is held, and neither its pane nor the operator gets the verdict. The only record is `fleet/<run>/verdict.txt`, which is read only if someone runs `cc-lr status`. This is the operator's "session recovered failed but the originating session didn't know."
- **Measured frequency.** 59 of 65 detached verdicts in 7 days were `cc-notify: verdict=unresolvable enqueued=0 uuid= reason=role-unset`. The other 6 were `delivered`, to panes 180 and 235, both direct `cc-lr recover` callers.
  - By verdict: RECOVERED 22 · FAILED 9 · HELD:bg-work 8 · HELD:unreachable 7 · PARKED 6 · HELD:pane 2 · HELD:exit-readback 2 · HELD:draft 2 · HELD:composer-unreadable 1.
  - Live case: `one-20261011T031606Z-58d3640a` (FAILED, pane 113) and `one-20261011T031601Z-5507881f` (HELD:unreachable, pane 220) are both `unresolvable enqueued=0`.
  - Phone fallback over the same 59: `fallback=phone-damped` 51, `fallback=phone-unwired` 8, `phoned` 0.
- **Root cause.**
  - `lr-fleet.sh:1690-1697` resolves the requester from `LR_FLEET_NOTIFY_PANE`, then from the caller's own `CC_PANE_ID`/`ITERM_SESSION_ID`/`KITTY_WINDOW_ID`. Both daemon dispatch sites run under launchd with no pane env and pass no `LR_FLEET_NOTIFY_PANE`:
    - `lr-reset-poller.sh:1456`, the REQUEST lane: 35 dispatches in 7 days (28 `stop-failure-marker`, 6 `stranded-husk`, 1 `235`).
    - `lr-reset-poller.sh:2077`, the REROUTE lane: 24 dispatches.
    - 35 + 24 = 59, equal to the role-unset count. That match is a count correlation, not a per-run join.
  - With an empty requester, `lr-fleet.sh:1892` falls through to `cc-notify --role desk`. There is no `~/.claude/cc-roles/desk`; `ls` shows only archive, docs-lead, drain-lead, opus55-lead and an empty orchestrator.
  - cc-notify's phone leg (`bin/cc-notify:494-531`) is inert: push-send exits 3 because PUSHOVER is not configured. It is also damped on a key made of role and reason (`bin/cc-notify:508`), so one stamp suppresses every other session's verdict for 1800 s.
  - The request's `requested_by`/`source_pane` are known at `lr-reset-poller.sh:1226-1227`, but they are only logged (`:1455`), never passed on.
  - Unlike lr-fleet, the reconciler's own sink (`lr_recon/report.py:511-522`) already falls back from the desk to `lr-page.sh`. `pages.log` shows that leg working (`os=posted`).
- **Fix.**
  1. In `lr-reset-poller.sh:1456`, prefix the dispatch with `LR_FLEET_NOTIFY_PANE="$_rq_requester"`. Use the request's new `requester_pane` field (see B3-2) when present. For a hook or husk origin, use the subject's `source_pane`; that pane is the human-facing surface.
  2. Do the same at `:2077`, using the parked record's pane.
  3. In `lr-fleet.sh:1889-1896`, when the verdict is not RECOVERED and the cc-notify verdict token is not `delivered` (the same parse as `report._NOTIFY_VERDICT`), also post through `lr-page.sh`. Damp per sid, as `lf_draft_page` already does.
  - **Bats (`tests/lr-reset-poller-requests.bats`).** A stub `LR_FLEET_BIN` that records its env. A `stop-failure-marker` request with `source_pane:"212"` must show `LR_FLEET_NOTIFY_PANE=212`. The same pin goes in `tests/lr-reset-poller-reroute.bats` for `:2077`.
  - **Bats (`tests/lr-fleet.bats`, beside :878).** Use `LR_FLEET_DETACHED=1`, no requester, a cc-notify stub that prints `verdict=unresolvable`, and verdict FAILED. Assert that the `LF_PAGE_BIN` stub was called once with the sid8. Then assert it is not called for RECOVERED.
- **Size.** M.
- **Conviction.** 85. Root cause 95, from measured `uuid= reason=role-unset` on all 59. Fix 80: mailing a LIMITED subject's pane may wake it through its `cc-await-ping` watcher and spend a turn that hits the limit again. See Uncertain U1; the lr-page leg alone does not have this risk.
- **Receipts.**
  - `find fleet -maxdepth 2 -name detached.log -mtime -7 -exec grep -h -o 'cc-notify: verdict=[a-z-]* enqueued=[01]' {} + | sort | uniq -c` → `6 delivered enqueued=1`, `59 unresolvable enqueued=0`.
  - `... grep -h -o 'cc-notify: fallback=[a-z-]*'` → `51 phone-damped`, `8 phone-unwired`.
  - `awk '$1>="2026-10-04T03:52"' poller.log | grep -c 'dispatching the in-place recovery DETACHED'` → 35. The REROUTE grep → 24.
  - `ls -la ~/.claude/cc-roles/` → no `desk`.
  - `git grep -n LR_FLEET_NOTIFY_PANE -- ':!docs'` → only `lr-fleet.sh:1690`; no setter anywhere.

## B3-2 — `cc-lr recover` queued for the reconciler drops the requester, and the poller then discards the request

- **Symptom.**
  - The requester sees `cc-lr: QUEUED for the reconciler <sid8>` and never hears again.
  - When the reconciler heartbeat goes stale, the poller drains the `*.cc-lr.json`, logs `REQUEST-SKIP … unknown mode 'recover'; parked`, and moves it to `results/<sid>.cc-lr.unknown-mode.json`. Neither drainer ever reads it again.
  - This is the 03:24Z live case: the 3 `cc-lr recover` requests had no run and gave no answer.
- **Measured frequency.**
  - 3 requests written at 03:24:40-43Z, all carrying `requested_by:"cc-lr"` and no requester field.
  - 2 of the 3 were discarded while I watched. Poller log: `03:56:01Z REQUEST-SKIP 5507881f … unknown mode 'recover'` and `03:57:21Z REQUEST-SKIP 58d3640a … unknown mode 'recover'`. `results/` now holds both `*.cc-lr.unknown-mode.json`.
  - The third, 6defb493, was still queued at 03:58:44Z.
  - That is 2 lifetime occurrences in `poller.log`: 1 at the first grep, 2 by the end of the session. This exposure only exists when `recon.on` is set and the heartbeat later goes stale.
  - Requester mails sent by the reconciler, ever: 0. That is a structural zero; see the receipt.
- **Root cause.** Four defects on one path:
  1. `bin/cc-lr:262-266` (`cl_recon_queue`) writes `{sid, at, requested_by:"cc-lr", mode, pane, config_dir}`. The `pane` is the subject's pane, and nothing records the caller's own pane (`cl_this_pane`, `bin/cc-lr:303-309`). The verdict has no address before anything runs.
  2. `bin/cc-lr:599` passes `mode=recover`, and `tests/cc-lr-request.bats:84` pins that value. The consumer `lr-reset-poller.sh:1326-1330` accepts only `relaunch|prompt` and parks anything else. The writer and the drainer disagree on the contract, and the comment at `:1201-1203` ("drains … exactly as a cc-lr-origin request always has") is false for `recover`.
  3. The poller reads `source_pane` (`lr-reset-poller.sh:1219`), but the writer writes `pane`, so the pane is also lost on the fallback path.
  4. `lr_recon/report.py:736` `mail_requester` ("§C11 Mail … only to a cc-lr requester pane") has zero production callers. It is called only in `lr_recon/tests/test_report.py:152,187,609`.
- **Fix.**
  - In `cl_recon_queue`, write `mode:"relaunch"` for recover, `source_pane:$pane`, and `requester_pane:$(cl_this_pane)`.
  - In the poller, accept `recover` as an alias for `relaunch` on `*.cc-lr.json`. This covers requests already on disk.
  - Have the unknown-mode skip mail `requester_pane` when present. A park must not be silent.
  - Wire `Reporter.mail_requester` into the reconciler's terminal-cohort report for records whose request carries `requester_pane`.
  - **Bats (`tests/cc-lr-request.bats:77`).** Change the expectation to `mode=relaunch`, `source_pane=117`, and `requester_pane=$KITTY_WINDOW_ID`.
  - **Bats (`tests/lr-reset-poller-requests.bats`).** Use a `.cc-lr.json` with `mode:"recover"` and a dead reconciler. Assert that `lr-fleet --one` is dispatched with `LR_FLEET_NOTIFY_PANE=<requester_pane>` and that no `unknown-mode.json` is written.
  - **Python test.** A reconciler pass that terminates a cc-lr-origin record calls the mail sink exactly once with `requester_pane`.
- **Size.** M.
- **Conviction.** 90. Every link was read at file:line and the discard was observed live. The remaining 10 is whether the reconciler should mail per record or per cohort.
- **Receipts.**
  - `cat requests/58d3640a-….cc-lr.json` → `{"sid":…,"at":1791689080,"requested_by":"cc-lr","mode":"recover","pane":"113","config_dir":"/Users/chrisren/.claude-next"}`.
  - `tail poller.log` → the two REQUEST-SKIP lines above.
  - `ls results | grep unknown-mode` → `5507881f-….cc-lr.unknown-mode.json` and `58d3640a-….cc-lr.unknown-mode.json`.
  - `git grep -n mail_requester -- scripts/limit-recover/lr_recon` → only the definition plus test callers.

## B3-3 — A request filed by the stop-failure hook names no recipient; the human-facing session is the subject pane, and nothing addresses it

- **Symptom.**
  - Session 516b9da9 (pane 212, live pid 1207 with `KITTY_WINDOW_ID=212` and `CLAUDE_CONFIG_DIR=.claude-next`) died on the weekly cap at 03:24:21Z.
  - The hook wrote `requests/516b9da9….json` with `requested_by:"stop-failure-marker"` and `source_pane:"212"`. No run existed through 03:55:51Z (`REQUEST-STAY … resets in 249s`).
  - The pane shows only Claude Code's own limit error. Nothing tells the human that a recovery was requested, is waiting, or later failed.
- **Measured frequency.**
  - 28 `stop-failure-marker` dispatches in 7 days (poller.log). All of them fall into B3-1's role-unset population.
  - Hook-side messages emitted: 0. `grep -n 'systemMessage|cc-notify|additionalContext' hooks/stop-failure-marker.sh` → no hits.
  - Retirements (`REQUEST-RETIRED … nothing was done`, `rq_retire` at `lr-reset-poller.sh:1127`) also mail nobody: 3 seen today at 03:52:41Z, 03:53:41Z and 03:58:43Z.
- **Root cause.**
  - `requested_by` is free text (`lr-reset-poller.sh:1001`) and is used only as a policy-gate key (`:1238`). The hook writes no requester address.
  - lr-handoff deliberately does not mail a placed or limit subject (`lr-handoff.sh:756-777`), deferring to lr-fleet's mail. lr-fleet's mail then has no address (B3-1).
- **Fix.** This fix is subsumed by B3-1 steps 1 and 3.
  - For `_rq_hook==1`, the recipient is `source_pane`, via the pane-keyed box so it survives the in-place recycle, plus lr-page for non-RECOVERED verdicts.
  - Add one receipt mail at enqueue time, from the poller's first sight of a hook request: "recovery requested for <sid8>, waits for <reset>". This must go through a no-wake lane (U1).
  - **Bats.** A `stop-failure-marker` request with an `autorecover.on` fixture dispatches with `LR_FLEET_NOTIFY_PANE` equal to `source_pane`. A `REQUEST-RETIRED` of a request carrying `requester_pane` produces one notify-stub call.
- **Size.** S once B3-1 lands.
- **Conviction.** 75. The root cause is measured. The receipt-mail half depends on U1.
- **Receipts.**
  - `cat requests/516b9da9-….json` → `"source_pane":"212","requested_by":"stop-failure-marker"`.
  - `ps eww -o command= -p 1207 | tr ' ' '\n' | grep KITTY_WINDOW_ID` → `KITTY_WINDOW_ID=212`.
  - `grep 516b9da9 poller.log` → `03:55:51Z REQUEST-STAY`.
  - `ls -d fleet/*516b9da9*` → no run.

---

## How addressing works (Q1/Q2, for reference — MEASURED unless marked)

- **Target resolution in cc-notify** (`bin/cc-notify:139-141`), in order:
  - `--cloud` → `--role` (`~/.claude/cc-roles/<name>`) → registry friendly name (live rows only) → raw key → uuid prefix → `--self`.
  - Then the `<key>.forward` chain: 4 hops, cycle-safe, with occupant expiry for reusable kitty keys (`hooks/lib/mailbox-pending.sh:593-660`).
  - Then, for a target that is not live, a reroute to `--role desk`, followed by the phone fallback.
- **Mailbox store.** `~/.claude/mailbox/<key>.md` holds one line per message. Cursors are `.seen` (emitted) and `.acked` (consumed).
  - The key is a kitty window id. Kitty sessions carry `ITERM_SESSION_ID=w0t0p0:<winid>` (measured by `ps eww` on pids 1207, 4039 and 6737), so `cl_this_pane`/`own_pane` = the window id. The other key form is a session uuid.
  - Store size: 2604 files, 1004 `.md`, 18 `.forward`, 7 `.forward.expired`.
- **Drain.** `hooks/mailbox-drain.sh` runs at SessionStart, UserPromptSubmit and PostToolUse; PostToolUse is limited to every 20 s and 20 lines (`:170-191`).
  - It reads the session box (`:160-164`) and folds in the pane box.
  - M4 pull-adoption re-stamps a predecessor's unread mail as `<ts> [forwarded:<key8>] …` (`mailbox-pending.sh:723`).
  - Subagents never drain (`:97-105`).
- **Recycle via `handoff-fire --recycle` in kitty.** The window id survives, so pane-keyed mail reaches the successor. Measured: the move-batch verdict `NOTMOVED=7` was sent to box 223, adopted into `ecb81dfc….md` line 2 as `[forwarded:223]`, and `.seen=.acked=3` of 3 lines (registry: `wt-cc-221850-13950-223`, pid 7871).

## Ruled out

- **The drain loses enqueued verdicts (rejected).**
  - Measured with `python3 -I` over `~/.claude/mailbox/*.md`, using a tz-aware timestamp filter for 7 days and a pattern for lr-fleet/lr-handoff/CC-LR-*/cc-lr move/lr-upgrade/lr-fire-resume lines.
  - Result: 187 lines in 39 boxes; 186 acked and 1 seen-not-acked. The one is `a286f0c7…` line 6, `[lr-fire-resume] ✗ NOT SUBMITTED`, in a session box with no live occupant.
  - Zero lines are UNDRAINED.
- **Recycle lineage breaks pane-keyed mail (rejected).** 38 acked limit-recover lines sit in pane boxes carrying a `.forward`, and the `[forwarded:223]` case above was acked.
- **The poller's launchd env carries a pane (rejected).** All 59 cc-notify lines show `uuid=` empty.
- **The move-batch lane loses its verdict (rejected).** `lr-move-batch.sh:92-93` mails `requested_by` = the caller's pane. The live batch's NOTMOVED=7 reached and was acked by the requester (above).
- **The direct `cc-lr recover` path, with the reconciler not live (works).** The 6 delivered verdicts are all of this kind (panes 180 and 235).

## Uncertain

- **U1.** Would mailing a LIMITED subject's pane wake it through an armed `cc-await-ping` and spend a turn that re-hits the cap, filing another stop-failure request? `lr-handoff.sh:770-777` cites 3 of 3 mailed no-prompt resumes taking a turn on the mail. I did not verify a no-wake mail lane (`--no-wake` only suppresses `cc-wake`, `bin/cc-notify:24`; the watcher polls the inbox independently). Until that is settled, lr-page is the safe leg for non-RECOVERED verdicts.
- **U2. Kitty window-id reuse after a kitty restart.** A pane-keyed verdict sent hours after the request (a reconciler cohort waiting for reset) could be drained by an unrelated session that now holds the same id. Forward expiry covers `.forward` pointers only, not raw pane keys. Not measurable cheaply: the drain does not record which session acked.
- **U3.** The 35 + 24 = 59 mapping of daemon dispatches to role-unset runs is a count match, not a per-run join. The 1 REQUEST dispatch "for 235" (a pane requester) is inside the 59, which suggests the requester is dropped even when a pane is named. That case alone is not verified per run.
- **U4.** `pages.log` records no titles or sids (`<epoch>\tposted\tos=posted\tphone=skipped`), so I could not check whether any of the 59 verdicts reached Notification Center by another route. lr-fleet pages only draft holds (`lf_draft_page`, `lr-fleet.sh:1269`).
