# C2: capacity-admit refusals and the agent rescue loop (2026-10-17/18)

Worker scope: symptom (c), the cause behind the `✗ capacity-admit: REFUSING resume <sid> on nextN …` panes.
Read-only investigation. Times are UTC (`Z`) unless marked CDT (CDT = UTC-5).

## 1. Answer first

**What caused it.** The in-pane capacity gate (`lr-fire-resume.sh` → `cc_capacity_admit`) has two jobs that work against each other. It refuses a resume, and then the only way to get past it is to run the same launch again until it has refused three times (`refusal N of 3 … the next evaluation ADMITS`). A refusal is not put in any queue. The process exits 9, `cc-pane-runner` keeps the pane open as a plain shell, and nothing else ever retries. So the rescue agent in session 2cc3a7fa did what the message told it to do. It ran `handoff-fire.sh … --tab` again and again, and every run opened a new tab. Over about 4h20m (07:13Z–11:30Z) it ran 23 fires and left 12 refused panes behind: tabs 409–426 and 435 in kitty OS window 18. The poller then did the same thing once by itself (window 428, 509e3aad).

**Why the gate refused so often.** It counts the whole machine. There were 5–9 real mid-turn sessions, and up to 10 "admission tokens in flight" were added on top. At least some of those tokens could never be used, because of a path-vs-content bug at `lr-handoff.sh:1537`. **9 of the 22 active-term refusals would have been admits without the token term** (07:20–08:47Z).

**The fix:**
- A refused unattended launch writes **one durable request**. The poller retries it with backoff and probes *before* it opens any pane.
- The refused pane **closes** instead of sitting at a shell.
- A **time** bound replaces the "re-run to spend the budget" release.
- Admission tokens are fixed so they are actually used, and stop counting once their spawn is gone.

## 2. Evidence (measured)

### 2.1 How the gate counts (code, worktree at b2a295c94)

| Question | Answer | Where |
|---|---|---|
| What "mid-turn" means | `cc_sp_active`: sessions whose **latest beat is `kind:"prompt"`** and whose (pid, lstart) is still alive | `scripts/lib/spawn-presence.sh:337-420` |
| Per account or machine-wide? | **Whole machine.** Beats live in `$HOME/.claude/cc-beats`, shared by all 4 config dirs. A beat has no account field (`sid,pane,cwd,pid,lstart,t,kind,who,…`), so it *cannot* be per-account | `hooks/lib/cc-beat.sh:34`; beat file shape read from `~/.claude/cc-beats/*` |
| The ceiling | `CC_ADMIT_ACTIVE_CEILING:-8`. Rule: `act + inflight + 1 > ceiling` ⇒ refuse | `capacity-admit.sh:1446`, `:1468-1470` |
| Why 8 | "top of the ~4-8 band that 127/127 historic gate refusals land in". It is a count of past refusals, not a capacity measurement | `capacity-admit.sh:1404-1438` |
| Operator reserve | When the operator is `present`, the limit drops to 7 (`reserve-active`) | `capacity-admit.sh:1514-1523` |
| Tokens in flight | Every unredeemed `turn` token in `~/.claude/autonomy/capacity-admit/tokens/` younger than the TTL counts as active **for every caller** | `capacity-admit.sh:1093-1125`, `:1465` |
| Token TTL | 180+600+180+60 = **1020 s** (17 min) | `capacity-admit.sh:952-963` |
| Budget key | `<state>/lr-fire-resume.<key>.refusals`. `key = basename(LR_RUN)`, or **`direct-<sid>`** when the launcher is run by hand or by the poller | `capacity-admit.sh:576-582`; `lr-fire-resume.sh:785` |
| How the budget releases | **By count only, no clock.** The 4th consecutive evaluation admits and pages. Any admit resets the count | `capacity-admit.sh:404-419`, `:1601-1644` |
| Is a refusal re-queued? | **No.** `exit 9`. `relaunch.rc` is written only when `LR_RUN_DIR` is set (`lr-fire-resume.sh:117-118`), and it is unset on the direct and poller paths | `lr-fire-resume.sh:788-797` |
| What happens to the pane | `cc-pane-runner` keeps a shell on **any** non-zero exit (`… exited 9 — keeping a shell for diagnosis/resume`) | `bin/cc-pane-runner:179-181` |
| What the message tells the reader | "Shed load first … **then re-run this exact command**" plus "(refusal N of 3; once the budget is spent the next evaluation ADMITS and pages)" | `lr-fire-resume.sh:789-791`; `capacity-admit.sh:1637` |

There is also a second gate. `handoff-fire.sh` runs its own `capacity_gate` before it opens the tab, and its budget is **1, keyed per term for the whole machine** (`~/.claude/autonomy/capacity-fire/active.refusals`, `handoff-fire.sh:9975-9980`, `:10067`). Any fire anywhere on the box spends or resets it. handoff-fire **mints no token** for the launcher (`grep LR_ADMIT_TOKEN|token_mint scripts/handoff-fire.sh` finds no mint site). So when its gate admits, the pane's gate still evaluates from scratch. That is two gates for one spawn, the defect W2 fixed only for lr-handoff and lr-fleet.

### 2.2 IDL rows (`~/.claude/autonomy/idl.jsonl.20261018T105203Z.gz` + the live file, `gate=="capacity-admit"`, `caller=="lr-fire-resume"`)

Measured with `gzcat … | grep … | jq` (§2.2 command in the transcript of this worker). Excerpt:

```
07:20:03Z refuse active 5232121f next2  7 mid-turn + 2 tokens + 1 > 8 (1 of 3)
07:20:22Z refuse active e52f1f63 next2  7 mid-turn + 2 tokens + 1 > 8 (1 of 3)
08:00:01Z refuse active 5232121f next2  6 mid-turn + 8 tokens + 1 > 8 (2 of 3)
08:00:26Z refuse active e52f1f63 next2  8 mid-turn + 7 tokens + 1 > 8 (2 of 3)
08:01:19Z refuse active 22a76c8a next3  5 mid-turn + 8 tokens + 1 > 8 (1 of 3)
08:07:34Z refuse active b102f5af next3  5 mid-turn + 10 tokens + 1 > 8 (3 of 3)
08:41:22Z refuse active 5232121f next2  7 + 5 tokens (3 of 3)
08:43:23Z refuse active 22a76c8a next3  8 + 5 tokens (2 of 3)
08:44:05Z refuse active 2e9ed9f2 next3  8 + 5 tokens (1 of 3)
08:44:20Z refuse active e52f1f63 next2  9 + 5 tokens (3 of 3)
09:20:03Z refuse active 22a76c8a next3  9 + 1 token  (3 of 3)
09:20:29Z refuse active 2e9ed9f2 next3  9 + 1 token  (2 of 3)
10:00:14Z refuse active 509e3aad next4  8 + 1 > 8    (1 of 3)      <- poller autofire, window 428
10:04:24Z admit  budget-expired 5232121f  9 mid-turn            <- admitted into a box still over the ceiling
10:06:47Z admit  budget-expired e52f1f63  12 mid-turn
10:44:53Z admit  budget-expired 22a76c8a  8 + 2 tokens
10:57:18Z refuse active 2e9ed9f2 next3  8 + 1 > 8    (3 of 3)
11:31:51Z admit  budget-expired(reserve-slots) 2e9ed9f2  49 trees + 1 > 54-5
```

Tally for 01:00–15:30Z, measured by the same pipeline with `| sort | uniq -c`:
- `lr-fire-resume`: refuse/active **22**, refuse/reserve-active 2, refuse/reserve-slots 1, admit/budget-expired **6**, admit/measured (headroom-only) 3.
- `lr-reconciler` admits 35, `lr-move-worker` 52, `lr-move-batch` 26.

**Every lr-fire-resume admit after 05:00Z was a budget-expired release, not a measured admit.** The gate was never satisfied. It was worn down by repeated runs.

**The 12 refused panes match the 12 IDL refusal rows one-to-one.** Measured with `kitten @ get-text --match id:N`:

| pane (tab) | sid | screen says |
|---|---|---|
| 409 (157) | 5232121f | 7 + 2 tokens, 1 of 3 |
| 410 (158) | e52f1f63 | 7 + 2 tokens, 1 of 3 |
| 412 (159) | 5232121f | 6 + 8 tokens, 2 of 3 |
| 413 (160) | e52f1f63 | 8 + 7 tokens, 2 of 3 |
| 414 (161) | 22a76c8a | 5 + 8 tokens, 1 of 3 |
| 416 (162) | 5232121f | 7 + 5 tokens, 3 of 3 |
| 417 (163) | 22a76c8a | 8 + 5 tokens, 2 of 3 |
| 418 (164) | 2e9ed9f2 | 8 + 5 tokens, 1 of 3 |
| 419 (165) | e52f1f63 | 9 + 5 tokens, 3 of 3 |
| 425 (166) | 22a76c8a | 9 + 1 token, 3 of 3 |
| 426 (167) | 2e9ed9f2 | 9 + 1 token, 2 of 3 |
| 435 (173) | 2e9ed9f2 | 8 + 1 > 8, 3 of 3 |
| 428 (OS win 24) | 509e3aad | 8 + 1 > 8, 1 of 3 |

Every one of these has foreground `zsh` only (`kitten @ ls`, 13:17 CDT) and ends with `cc-pane-runner: the fleet launch line exited 9 — keeping a shell`.

### 2.3 Kitty layout (`kitten @ ls`, 13:17 CDT)

OS window 18 has **18 tabs and 19 windows**. Tab 146 holds pane 344; the other tabs hold 403, 409, 410, 412, 413, 414, 416, 417, 418, 419, 425, 426, 430, 433, 434(+454), 435 and 442. Every pane the rescue opened was a `--tab` (`/tmp/lr-rescue/fire-round.sh`, `fire-next3-batch.sh`, and the direct fires in the transcript all pass `--tab`). Symptom (b) is the same incident.

### 2.4 Token wiring bug (code plus IDL)

- The reconciler mints a token with `cc_capacity_token_mint` and passes back **the token file's path**: `lr_recon/admit.py:202-211`, `__main__.py:1018`. It hands that on as `LR_ADMIT_TOKEN_PATH`: `lr_recon/act.py:86-87`.
- `lr-handoff.sh:1537` treats that file as if it held a token path: `LRH_ADMIT_TOKEN="$(head -n 1 "$LR_ADMIT_TOKEN_PATH" | tr -d '[:space:]')"`. A real token's first line is the record `issued<TAB>sid<TAB>uid<TAB>terms`. Stripping the tabs leaves `1792307668b102f5af-…501`. That is not a path, so the pane's redeem logs `token ABSENT (…) — evaluating fresh` (`capacity-admit.sh:990`) and **evaluates the box a second time**.
- The real token is never redeemed, so `cc_capacity_tokens_inflight` keeps counting it **against every caller for 1020 s**.
- **MEASURED** in the IDL: 7 lr-fire-resume rows overnight carry exactly that note (`token ABSENT (1792307668b102f5af-8f09-…501)` at 07:28, 07:42, 08:07, 08:34; `…2ee922eb…` at 08:47 and 10:41; `…5759497b…` at 10:33).
- Why the tests never caught it: `tests/lr-handoff-flags.bats:500-507` writes a made-up token string (`'  tok-caller-42  '`) into the file instead of using a real `cc_capacity_token_mint` output.

### 2.5 The rescue loop, reconstructed from 2cc3a7fa

Source: `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-184726-89776/2cc3a7fa-01ea-4c5d-82da-c06018901409.jsonl` (1882 lines). Tool calls and their results were extracted with `jq`. The agent's own narration is quoted.

| UTC | fires | result |
|---|---|---|
| 07:13 | 2 (e52f1f63, 5232121f; wrong cwd) | stopped by the agent at 07:18 |
| 07:19 | 2 | panes 409, 410 → in-pane refusal 1/3. handoff-fire waited ~40 min and reported `ENGAGEMENT UNPROVEN (cannot tell)`, not "exit 9" (task outputs `bfp6kt771`, `by3w2p2dk`) |
| 07:59 | 2 | 412, 413 → 2/3. handoff-fire reported `FIRE FAILED — never engaged … WINDOW EXPIRY` (`b5wfi3qzi`, `bqecpu9ql`) |
| 08:00 | `fire-next3-batch.sh` (serial; only 22a76c8a reached a pane) | 414 → 1/3 |
| 08:40 | 1 (5232121f). Agent: *"Refusal 2 of 3. The gate's own message says the next evaluation is admitted once its budget is spent. Firing 5232121f a third time."* | 416 → 3/3 |
| 08:42 | `fire-round.sh` ×3 (fire-round.sh was written here) | 417, 418, 419 |
| 09:18 | ×4. Agent: *"e52f1f63 and 5232121f have used all 3 refusals … this attempt should be admitted."* | 5232121f/e52f1f63 refused by **handoff-fire's gate** (`refusal 1 of 1`, no pane). 22a76c8a → 425, 2e9ed9f2 → 426 |
| 10:05 | ×3 | e52f1f63 admitted (budget-expired) → pane 430. Other two refused at the fire gate (1 of 1) |
| 10:44 | ×2 | 22a76c8a admitted (budget-expired) → 433. 2e9ed9f2 refused at the fire gate |
| 10:50 | ×1 | 2e9ed9f2 refused at the fire gate. Agent at 10:55: *"Refused again, still at '1 of 1', so the budget seems to reset between fires. Firing again right away, while the budget should still be spent."* |
| 10:55 | ×1 | 435 → in-pane 3/3 |
| 11:30 | ×1 | 2e9ed9f2 admitted (budget-expired, reserve-slots, 11:31:51Z) |

Totals: **23 handoff-fire invocations, 12 refused in-pane panes, 4 sessions eventually admitted, all by budget expiry.** 5232121f was admitted at 10:04:24Z into pane 429, in OS window 25 (registry `429.json`). Which fire produced 429 was not determined.

**Why the agent kept firing new panes instead of letting a queue retry.** Measured from code plus the narration:
1. **No queue existed for these launches.** The rescue launchers were hand-written `lr-fire-resume.sh` wrappers (`/tmp/lr-rescue/resume-*.sh`) fired through `handoff-fire.sh --tab`, not `cc-lr recover`. `cc-lr recover` would have written `~/.reso/limit-recover/requests/<sid>.cc-lr.json`, which the poller retries with REFUND-on-park (`lr-reset-poller.sh:1243-1285`, `:1496`, `:1625`). The gate's refusal writes nothing durable (§2.1). So the agent was *right* that nothing else would retry.
2. **The release condition can only be met by running again.** The budget is count-based with no clock (`capacity-admit.sh:430`: "The release is COUNT-based only; there is no clock"). Re-running through handoff-fire means a new tab every time.
3. **The message invites it.** "Re-run this exact command" and "the next evaluation ADMITS" (`lr-fire-resume.sh:790`, `capacity-admit.sh:1637`). The agent quoted this back as its reason at 08:40Z and 09:19Z.
4. **The fire's own verdict hid the cause and took ~20-40 min.** handoff-fire never reads the launcher's exit code. It polled for engagement for 480 s or more and printed "ENGAGEMENT UNPROVEN" or "WINDOW EXPIRY … do NOT clear the pane". So the agent learned "capacity refused" only by reading the pane screens (07:58Z). It was also told not to close the panes it had created.
5. **The fire gate's machine-wide budget of 1** made its refusals look random to the agent ("budget seems to reset between fires"), which encouraged firing straight away.

### 2.6 Was the ceiling count right?

- **Counting other accounts.** Yes, by construction (§2.1). For a CPU gate that is correct in principle, since the box is the shared resource. But it means next2/next3 rescues were held back by next/next4 activity, including the rescuer 2cc3a7fa itself. Its turn ran from ~07:12Z to 07:41Z and later, mostly inside `until …; sleep 15` poll loops (transcript 07:20:32Z, 07:25:31Z, 07:30:37Z). A "prompt" beat with no "stop" counts as active even when the turn is blocked in `sleep`. INFERRED: the rescuer counted as one of its own 8.
- **Stale tokens.** At least 7 tokens were never redeemed because of the §2.4 bug (MEASURED). Each one inflated the active term for up to 17 min. The in-flight figure reached 10 when only 5 sessions were mid-turn (08:07:34Z). If the `+inflight` term is removed, **9 of the 22 active refusals between 07:20Z and 08:47Z would have admitted** (computed from the IDL `act` values: `act + 1 ≤ 8`). Which of the 5-10 tokens were real pending spawns and which were orphans cannot be split after the fact. The tokens dir now holds 1 file, already past its TTL (`5759497b…`, issued 1792329413, now 1792347773).
- **Token kind.** The reconciler mints without `CC_ADMIT_TOKEN_KIND` (`admit.py:206`), so every reconciler token is `kind=turn`, including no-prompt moves that owe no turn (`capacity-admit.sh:715-727` added the `swap` kind for exactly this case).

### 2.7 509e3aad / window 428 (the poller, not the agent)

`poller.log:217680`: `10:00:12Z RESUMED 509e3aad on next4 (autofire, gui) — pane opened`. Two seconds later the in-pane gate refused (IDL 10:00:14Z, 1 of 3). Launcher: `/var/folders/0s/…/T/lr-poller-launch-509e3aad-DTj06v.sh` (exec `lr-fire-resume.sh next4 …voiceink 509e3aad … --prompt /limit-recover`).

The poller's autofire path **does not probe before spawning**. It logs "pane opened", and **moves the parked record to RESUMED** (`lr-reset-poller.sh:2598-2603`), so the refusal is never retried. `poller.log:217875` `12:12:17Z REQUEST-RETIRED 509e3aad — no longer LIMITED`. The transcript is on next4 and was last written at 18:04:40Z. INFERRED: 509e3aad is running in its original pane 28 (VoiceInk, claude started 2026-10-16 02:14 CDT, no `--resume`). That means window 428 was a would-be duplicate and the refusal accidentally prevented a split-brain.

### 2.8 Load (~85-120)

Measured 13:15-13:21 CDT:
- `uptime`: 78.81 / 104.40 / 110.58. `sysctl vm.loadavg`: 63.09 / 77.39 / 96.44. 10 cores.
- `top -l 3 -s 5`: 1281 procs, 45 running, **CPU 51.8% user / 33.5% sys / 14.8% idle**, PhysMem 59G used (27G wired, 2.5G compressor), 2.8G unused.
- Earlier, the agent measured **154 / 161 / 216** at 07:30Z (transcript 07:30:11Z).

`ps -axo` census (~13:17 CDT, 1682 procs, 70 in R state):

| family | count | note |
|---|---|---|
| claude TUIs | 39 `claude` + 4 `claude.exe` | 183% + 26% CPU snapshot |
| `cc-close-attrib` wrappers | 46 | one per claude |
| `lead-crash-watchdog.sh` | 39 bash loops | one per session |
| MCP-related argv | 109 | |
| zsh | 102 | ≥14 are leftover plain-shell panes |
| bash | 205 | |
| `cc-kqwait` | 15 | |
| Dia browser | 29 helpers + main | one renderer at 147%, many 0-s-old renderers; browser automation |
| `chrome-headless-shell` | 13 | |
| bats | 2 live suites | `lr-fire-resume-reply-drain.bats`, `lr-handoff-voluntary.bats`, `cc-lr-move-self.bats`, `cc-classify.bats`, `cc-lr-request.bats` |
| `lr-move-worker` | 7 argv | |
| live non-test `lr-fire-resume` | 4 | |
| caffeinate | **11**: 1 long-lived `-i -s` (17 d) + 10 per-turn `-i -t 300` | idle, ~0 CPU, not a load source |

INFERRED: the load is mostly runnable-thread count, not useful work. Contributors: ~43 resident TUIs plus their MCP children, Dia automation, and fork/exec churn from per-session bash pollers, hooks (jq/ps) and test suites (33% sys, with `kernel_task`, `syspolicyd` and `XProtect` near the top). **None of this is what the active term counts.** The gate refused on "8 mid-turn" while sleeping turns and non-claude load went unmeasured.

## 3. Causal chain

1. **Origin:** batch moves next4→next2 and next→next3 overnight (lr-move workers and reconciler). Several in-place relaunches did not verify, so transcripts were on the new account with no process: e52f1f63, 5232121f, 22a76c8a, 2e9ed9f2, b102f5af.
2. **Rescue session 2cc3a7fa** (next3, OS window 18 / pane 344's program) wrote `/tmp/lr-rescue/resume-<sid>.sh` and `prompt-<sid>.txt`. It fired them with `handoff-fire.sh --tab` (07:13Z onward), bypassing the `cc-lr recover` request queue.
3. Each fire opens a **new tab** (→ symptom b). Inside it, `lr-fire-resume` runs the second gate. The machine-wide active term is inflated by unredeemed reconciler tokens (bug at `lr-handoff.sh:1537`) and by sleeping turns. Result: refusal (exit 9, budget key `direct-<sid>`).
4. `cc-pane-runner` keeps a shell on rc 9 (→ **symptom c**: a plain kitty pane showing a wall-of-text refusal). handoff-fire waits ~40 min, then reports "unproven" or "window expiry", not "capacity refused".
5. The message says "re-run" and "the next evaluation ADMITS", and nothing else will retry. **The agent re-fires**, adding another tab and pane each time, until the count budget releases. The release then admits into a box that is *still* over the ceiling (9-12 mid-turn), so the gate added delay and leftover panes without protecting anything.
6. Separately, the poller's autofire opened window 428 for 509e3aad without probing first, and the gate refused it. That is the same end state from a different origin.

## 4. Immediate remediation (describe only; nothing was done)

1. **Close the 12 refused rescue panes** in OS window 18: windows 409, 410, 412, 413, 414, 416, 417, 418, 419, 425, 426, 435 (tabs 157-167, 173). All have foreground `zsh` only and their screens show the refusal. None holds a session:
   - 5232121f is live in 429 (registry `429.json`).
   - e52f1f63 is live in 430 (registry `430.json`).
   - 22a76c8a's pane 433 now holds session 09e18eed (INFERRED: recycled successor).
   - 2e9ed9f2 was admitted at 11:31Z. Pane 442 (personal, session fad30cb7, "personal housing-search session") is INFERRED to be its successor. **Confirm with `cc-lr find 2e9ed9f2` / its transcript tail before closing 435.**
2. **Pane 403** (tab 156): launch line exited **1** (an earlier failure, not this gate). Read its scrollback, then close it.
3. **Window 428** (OS window 24): close it. 509e3aad is retired by the poller as recovered, and its transcript is being written from its original holder (pane 28). Optionally clear `~/.claude/autonomy/capacity-admit/lr-fire-resume.direct-509e3aad-….refusals` (value 1).
4. **Do not re-fire anything** for these 5 sids, and do not run `/tmp/lr-rescue/fire-round.sh` again. Its `--tab` and new-pane-per-retry design is the defect. Renaming or archiving `/tmp/lr-rescue/` stops a future session from re-using it.
5. Re-home the remaining live panes in OS window 18 (344, 430, 433, 434/454, 442) into fullscreen windows of at most 4 splits, each on its own Space. The symptom (b) worker owns the mechanics.

## 5. Long-term fix

### 5.1 A refused unattended launch writes one durable request and leaves no pane

- **`scripts/limit-recover/lr-fire-resume.sh:788-797`**: on rc 9 from `cc_capacity_admit` (`basis=measured`, i.e. not token-stale, not probe):
  - Call a new `lr_enqueue_capacity_retry "$SID" "$ACCT" "$CWD" "$MODEL" "$EFFORT" "$PROMPT"`. It writes `~/.reso/limit-recover/requests/<sid>.cc-lr.json` atomically (mktemp + mv) with `mode:"recover"`, `target:$ACCT`, `cause:"capacity"`, `first_refused_at`, `refusals:n`, `next_at`.
  - **One file per sid.** A re-run updates the counters and keeps `first_refused_at`.
  - Then `exit 75` (EX_TEMPFAIL, meaning "queued").
  - Replace the three stderr lines with a short summary that leads with the answer:
    ```
    ⏸ QUEUED  2e9ed9f2 → next3
       box busy: 8/8 turns in progress (+1 pending)
       the poller retries in ~2 min; this pane will close — nothing to do
    ```
  - Remove "re-run this exact command" and "next evaluation ADMITS" from this unattended path.
- **`bin/cc-pane-runner:179-181`**: treat rc 75 from a fleet launch line as **close** (print the one-line summary, then exit the runner). Keep the shell only for unexplained failures.
- **`scripts/limit-recover/lr-reset-poller.sh` request drain (`:1496-1625`)**: for `cause:"capacity"` requests, run `cc_capacity_probe` **before** any spawn.
  - On refuse: `REQUEST-STAY` with exponential backoff (`next_at += min(60·2^k, 900)` s), **no attempt spent**, no pane.
  - On admit: `cc_capacity_token_mint` with `CC_ADMIT_TOKEN_KIND=turn`, then spawn with `LR_ADMIT_TOKEN` set, so the in-pane gate redeems (basis `token`) instead of deciding again.
  - **The bound becomes time-based for queued requests:** once `now - first_refused_at > LR_CAPACITY_QUEUE_MAX_S` (e.g. 2700 s), admit and page. That satisfies §9's "no unbounded gate" without anyone having to re-run.
- **`lr-reset-poller.sh:2595-2603` (autofire)**: probe before `spawn_resume`. On refuse, leave the parked record in PARKED (`log CAP-WAIT`) instead of moving it to RESUMED. Pass a minted token in the launcher.
- **`scripts/handoff-fire.sh`**:
  - When `--launcher` targets `lr-fire-resume.sh` and `capacity_gate` admitted, mint a token and export `LR_ADMIT_TOKEN` into the launch line, so there is one decision per spawn.
  - Key `_cc_fire_budget_file` (`:9975-9980`) per fire subject (sid or launcher hash) as well as per term, so unrelated fires cannot spend or reset each other's budget. That is the U05 §3.4 per-run keying, applied here too.
  - After the tab launches, read the launcher's `relaunch.rc` (or rc 75 / 9 from the runner) and report "capacity-queued" within seconds, instead of polling 480 s for engagement.
- **Rescue procedure (rules/docs, not code):** a rescue of a stranded moved session goes through `cc-lr recover <sid> --target <acct>`, which queues. Never hand-fire `handoff-fire.sh --tab` with a custom `lr-fire-resume` launcher. `--tab` should be refused for `--launcher …lr-fire-resume…`.

### 5.2 Fix the token path (and stop counting orphans)

- **`scripts/limit-recover/lr-handoff.sh:1536-1540`**: `LR_ADMIT_TOKEN_PATH` *is* the token. Set `LRH_ADMIT_TOKEN="$LR_ADMIT_TOKEN_PATH"` when the file passes `_cc_admit_token_shape` (4-field record, our uid, this sid). Fall back to the old first-line read only when the file is not a token record.
- **`scripts/lib/capacity-admit.sh:1093-1125`** (`cc_capacity_tokens_inflight`): count a token only while its spawn is plausibly pending.
  - Either bind a launcher pid or run dir at mint time (a third line, `run=`), and drop the token once `relaunch.rc` exists or the pid is gone.
  - Or count it only for a short window (e.g. 180 s, `RCY_BOOT_STALE_S`) instead of the full 1020 s TTL.
- **`lr_recon/admit.py:206`**: pass `CC_ADMIT_TOKEN_KIND=swap` for no-prompt moves.

### 5.3 A better admission signal

Keep the count machine-wide (the box is the resource, and account limits are a different subject). Change what counts as "active":
- **Turn in progress AND CPU-active.** A mid-turn beat counts only if its claude process tree used more than ~0.25 core over the last 30 s. A sampler that already runs (the compressor-sentinel cadence, every 10 s) writes `~/.claude/autonomy/active-cpu.json` with CPU seconds per tree, so the gate reads a file and never sleeps. Turns blocked in `Bash sleep`, `Monitor` or background waits, like 2cc3a7fa's 270 s poll loops, then stop counting.
- **The ceiling in cores of claude work, not a session count.** For example, refuse when Σ(active claude-tree CPU) + 2.39 (the measured per-active-session marginal, §6e) > `ncpu × 0.8 − unsheddable`. Keep the segment and headroom terms as they are.
- **Pending admissions** are counted from live launcher processes (or run dirs without `relaunch.rc`), not from token files.

### 5.4 Tests that would have caught it

1. `tests/lr-fire-resume-capacity-queue.bats`, new. Setup: `CC_SP_ACTIVE_OVERRIDE=8`, `CC_ADMIT_BUDGET=3`, lr-fire-resume run under `bin/cc-pane-runner` with `CC_PANE_CMD_INTERACTIVE=1`, stubbed `expect`. Assert:
   - rc 75;
   - exactly **one** `requests/<sid>.cc-lr.json`, and it is still one after three re-runs (`refusals` 3, `first_refused_at` unchanged);
   - the runner **exits**, with no `keeping a shell` line;
   - stderr does not contain `re-run this exact command`.
2. Poller drain case in `tests/cc-lr-request.bats`. With a `cause:capacity` request and `cc_capacity_probe` stubbed to refuse: `spawn_resume` is never called, `next_at` grows, attempts are unchanged. Flip the probe to admit: one spawn, the launcher env carries `LR_ADMIT_TOKEN`, and the in-pane IDL row has `basis:"token"`.
3. `tests/lr-handoff-flags.bats:500`: replace the made-up `tok-caller-42` fixture with a real `cc_capacity_token_mint` output. Assert that the pane redeems (`basis token`) and that `cc_capacity_tokens_inflight` goes back to 0.
4. Two-gate case for handoff-fire: with `--launcher <lr-fire-resume stub>` and the fire gate admitting, the in-pane gate row is `basis:"token"`, never a fresh `measured`.

## 6. Confidence

- **Overall: 85%** for the causal chain and the fix direction. The gate code, the IDL rows, the pane screens and the agent's own quoted reasoning all point the same way.
- **90%** that `lr-handoff.sh:1537` mismatches the reconciler's contract (code plus 7 IDL `token ABSENT (<record>)` rows).
- **60%** for how much of the 5-10 in-flight tokens were orphans rather than real pending spawns. This cannot be split after the fact.

What would change these numbers:
- The `tokens/` directory history (not kept) or per-token mint logs showing those tokens were redeemed elsewhere would lower the orphan share.
- If 2e9ed9f2 turns out not to be running anywhere (unverified: no `--resume 2e9ed9f2` process exists; pane 442 is only INFERRED to be its successor), it is still stranded. It would then need one `cc-lr recover`, not another fire.
- The load attribution in §2.8 comes from single snapshots. A sustained `top` / `powermetrics` window would be needed to rank contributors with confidence.

## Adversarial verification

Verifier: an independent read-only pass at about 13:25 CDT on 2026-10-18. I opened every cited line again rather than trusting the citations above.

**Verdict: NOT refuted. The core mechanism holds, with corrections.** The in-pane gate refuses with exit 9. On the direct path it writes nothing durable. `cc-pane-runner` keeps a shell. The release is by count only, and the message invites re-runs. Together these produced the 12 rescue panes. Two claims are wrong and they change the fix: "nothing else would retry", and the poller fix as proposed. Details below.

### Re-checked and confirmed (MEASURED)
- `lr-fire-resume.sh:785-797`:
  - The budget key falls back to `direct-$SID`.
  - It prints "re-run this exact command".
  - It calls `lr_relaunch_rc 9`, which returns without writing when `LR_RUN_DIR` is unset (`:112-113`).
  - Then `exit 9`.
- The `/tmp/lr-rescue/resume-*.sh` launchers `exec` lr-fire-resume and set no `LR_RUN`/`LR_RUN_DIR`. The poller's autofire launcher (`lr-reset-poller.sh:2591-2595`) does not set them either.
- `bin/cc-pane-runner:179-181`: any non-zero exit means "keeping a shell for diagnosis/resume".
- `capacity-admit.sh`:
  - `:404-419` is a count-only charge that releases when n > budget.
  - `:430` says "no clock".
  - `:1637` is the "next evaluation ADMITS" wording.
  - `:1446-1470` is `act + inflight + 1 > 8`.
  - `:1093-1125` counts every unredeemed `turn` token for up to the TTL.
- The token bug is real and still live:
  - `cc_capacity_token_mint` prints a **path** (`capacity-admit.sh:724-765`).
  - The reconciler passes that path as `LR_ADMIT_TOKEN_PATH` (`act.py:86-87`, `__main__.py:1018`).
  - `lr-handoff.sh:1537` reads line 1 of the token file, which is the record, as if it held a path.
  - It is visible in lr-handoff's own state log: `~/.reso/limit-recover/5232121f-…/bundle-20261018T070248Z/events.jsonl`, 07:04:17Z, `admitted gate "token 17923069335232121f-…501 (caller-owned, …/tokens/5232121f-…)"`.
- `tests/lr-handoff-flags.bats:500-507` uses the made-up `tok-caller-42` fixture.
- The rescue transcript (2cc3a7fa) shows fires through `--tab`, and the agent quoting the "budget spent ⇒ admits" logic.
- The fire task output `bfp6kt771.output` shows the INC-4 re-send **abstained**: "verified paste ABSTAINED — no proof a live CC session owns pane 409". So no brief was typed into the refused zsh panes.

### Corrections
1. **Pane 429 (5232121f) was opened by the poller, not the rescue.**
   - `poller.log:217683`: `10:04:31Z RESUMED 5232121f… on next2 (autofire, gui) — pane opened`. That is 7 s after the IDL admit at 10:04:24Z.
   - It was admitted `budget-expired` only because the **rescue's** three refusals (07:20, 08:00, 08:41) had charged the same key, `lr-fire-resume.direct-5232121f…`.
   - So the `direct-<sid>` key is shared across actors: one actor's refusals release another actor's spawn. §2.5's "which fire produced 429 was not determined" is now answered.
2. **"No queue existed … the agent was right that nothing else would retry" is false for 5232121f and 509e3aad.**
   - The poller parked 5232121f at 07:34:47Z (`poller.log:217129`, "next2, weekly, resets 09:00Z").
   - It rerouted it at 07:41:28Z and 07:58:08Z (`:217142`, `:217330`, lr-fleet driver pid 72607).
   - Bundles `…070248Z`, `…074753Z` and `…082504Z` each ended `FAILED … lr-transplant exited 2`.
   - The poller also queued 509e3aad: PARKED at 07:08:16Z, REQUEST at 07:26:21Z and 07:48:08Z (`:216947-217171`).
   - So for these two sids, the rescue agent and the lr machinery worked on the same session at the same time.
   - The claim does hold for e52f1f63, 22a76c8a and 2e9ed9f2: the poller logged only `CLAIMED-NOT-LIVE` for them.
3. **509e3aad's live holder is now MEASURED, not INFERRED.**
   - `~/.claude/cc-beats/509e3aad-….json` shows pane 28, pid 7301, lstart "Fri 16 Oct 07:14:57" (UTC).
   - `ps -p 7301` shows that pid is alive and started 02:14:57 CDT.
   - Its transcript on next4 carries weekly-limit errors at 06:59:31Z and 07:18:23Z.
   - So the 10:00:12Z autofire opened a **duplicate resume of a live session**, and the capacity refusal is the only thing that stopped a split-brain.
4. **The statistic.** "9 of the 22 active-term refusals between 07:20Z and 08:47Z" mixes two windows.
   - 07:20-08:48Z holds **13** active refusals, and 9 of them have `act ≤ 7` (MEASURED: `jq` over the IDL, `uniq -c` of `act`: 5×2, 6×3, 7×4, 8×3, 9×1).
   - 22 is the total for 01:00-15:30Z.
5. **"Every lr-fire-resume admit after 05:00Z was budget-expired"** holds only up to 13:17Z. `13:17:33Z admit headroom-only 5759497b` falls inside the tally's own 01:00-15:30Z window.
6. **The "7 token ABSENT rows" count covers only the rotated IDL file.**
   - Rows in the live file bring it to **12 through 13:17Z**: b102f5af 07:28/07:42/08:07/08:34, 2ee922eb 08:47/10:41/12:22/12:50, 5759497b 10:33/12:16/12:50/13:17.
   - Plus 3e929a81 at 18:25:44Z.
   - The bug is still firing on trunk now.
7. **Fire count.** At 07:13:12Z a serial loop fired 2, and `fire-next3-batch.sh` runs 3 serial `handoff-fire` calls (for 22a76c8a, 2e9ed9f2 and b102f5af). Counting per `handoff-fire` process gives **25**, not 23. That changes no conclusion.

### Missing from the report
- **A second source of symptom (c) panes: the reconciler's own in-place relaunches.**
  - The b102f5af (07:28-08:07Z) and 2ee922eb refusals are not rescue panes. They are lr-handoff relaunches whose in-pane gate evaluated fresh *because of* the `lr-handoff.sh:1537` bug.
  - They refused with exit 9 inside the pane that had just run `/exit`. Here `LR_RUN_DIR` is set, so the reconciler does retry (b102f5af was retried 4 times with the same token, issued at 1792307668).
  - So the token bug strands panes directly, not only by inflating the count.
- **The stranding origin is not a gate refusal.**
  - 5232121f's first bundle: `07:00:06Z admitted gate "gate-exempt: swap"`, then `07:06:55Z STRANDED … recycle did not verify (handoff-fire rc=1)`.
  - Why that recycle failed is outside this report and belongs to the symptom (a) report.
- **The next2 weekly limit (INFERRED).**
  - 5232121f's only API error is "You've hit your weekly limit · resets 4am (America/Chicago)" at 06:51:35Z, 5 s after its swap onto next2. The poller attributed it to next2 (resets 09:00Z), and 7b50757e was also parked as next2 weekly at 07:34:37Z.
  - If that attribution is right, any next2 admit before 09:00Z would have hit the limit straight away. Then the gate refusals for e52f1f63 and 5232121f before 09:00Z cost nothing. The record could also come from next4's pre-exit process; this is unresolved.

### Where the proposed fix would break or fall short
1. **§5.1, poller autofire ("probe, then mint a token and spawn").** This would have **admitted the 509e3aad duplicate** on a quieter box.
   - The poller already holds the right signal: the beat file names a live (pid, lstart) holder in pane 28. It already uses that path for another session (`poller.log` 09:55:46Z `NUDGED 0c354704 … in place`).
   - Required change at `lr-reset-poller.sh:2595`: before any spawn, if `cb_last_beat <sid>` names a live pid+lstart, nudge in place or skip, and never open a pane. The current claim check sees only `--resume` argv, and pid 7301 was started without `--resume`.
   - Test: a parked record whose sid has a live beat holder ⇒ `spawn_resume` is never called.
2. **§5.1, the request file written on rc 9.** It must be deduped against existing poller state: `parked/<sid>`, `runs/by-sid/<sid>.active` and the open `requests/`. Otherwise it adds a third actor for sids like 5232121f.
   - It must also be written only when `LR_RUN_DIR` is unset. When it is set, the reconciler or lr-handoff watcher already reads `relaunch.rc` and retries, and a request file there would double-queue.
3. **The budget key.** `direct-<sid>` must also carry the actor (for example `direct-<sid>-<caller-pid-or-launcher-hash>`). Otherwise the rescue's spent budget keeps releasing the poller's spawns, as in Correction 1.
4. **`cc-pane-runner` closing on rc 75.** This is safe for fresh panes from a fleet launch line: they hold no session, and the transcript is on disk. It must **never** apply to an in-place pane. Poller in-place recoveries address panes by id (`REQUEST … target auto, pane 28`), so closing that pane would break the next retry. The in-place relaunch runs `bash <launcher>` in an interactive shell, not as cc-pane-runner's launch line, so the proposed hook point is right, but the bats case should assert the in-place shell survives.
5. **handoff-fire.** It already has a "pane PARKED, launcher never ran" verdict (`handoff-fire.sh:19890-19905`, `ENGAGE_RC=2`). It did not fire, because the launcher *did* run and exited 9 before the pane went back to zsh. The cheaper fix is to make that same branch also recognise "the pane's foreground is the shell again, and the runner printed `exited <rc>`", not only "never ran". Do that rather than add a new rc channel.

### Live state at verification time (MEASURED, `kitten @ ls` about 13:25 CDT)
- The 12 rescue panes (409-426, 435), window 428 and pane 403 no longer exist.
- OS window 18 now holds a single tab 172 with panes 433 and 434.
- Panes 344, 429, 430 and 442 are in OS window 25, tab 169. Panes 429 and 430 show the foreground `expect`+`bash`.
- §4 remediation items 1-3 appear to have been done already by someone else.

**Adjusted confidence: 70%.** The core mechanism is unchanged. Confidence drops because "nothing else retries" is partly false, the proposed autofire fix would have caused a split-brain, and two counts were misstated.
