# Lens: long-horizon continuity and physical capacity (critic-added lens)

Auditor scope: does research method v1.1 (REPORT.md, kit `scripts/research-kit/`, resolver
`scripts/lib/research-program.sh`, CLI `bin/cc-research`) survive a program run by successive sessions
across recycles, worktree handoffs, account switches, /compact, usage limits, crashes and two live leads,
24/7 for weeks; and what is the physical ceiling on how long and how hard it can run.

Labels: **measured** = a command I ran this session, output quoted; **sandbox** = a run against a fixture
program in `/tmp/lhc-audit.H0hv` with `CC_RESEARCH_REGISTRY`/`CC_RESEARCH_HOME`/`CC_RESEARCH_RECORDS`
pointed there; **static** = file:line read; **asserted** = a figure a repo document states that I did not
re-measure; **modeled** = my arithmetic.

Nothing live was written. The live registry and `~/.claude/autonomy/research/truememory-2-0/` were only
read (cat/ls/jq). No vendor CLI, no handoff-fire.sh, no cc-lr, no launchctl was run. Fixtures were created
under /tmp with printf/cp/mkdir only. Vendor binaries were disabled in the one run that used the real
courier (`CC_RESEARCH_BIN_ANTHROPIC= CC_RESEARCH_BIN_OPENAI= CC_RESEARCH_BIN_GOOGLE=`, which
`courier.py:73-75` turns into "not found", so no call could be made).

## 0. Positive control (sandbox reads the sandbox, not the live file)

```
bash scripts/lib/research-program.sh resolve $SB/root            => fixture-prog certifying   rc=0
bash scripts/lib/research-program.sh resolve .../tm2-plan        => (empty)
bash scripts/lib/research-program.sh is-active $SB/root-wt2      => rc=1
```
The live registry holds only truememory-2-0 rooted at `/Users/chrisren/Development/.worktrees/tm2-plan`
(measured `cat ~/.claude/autonomy/research/programs.json`), so the empty answer for tm2-plan proves the
override at `research-program.sh:37-39` and `kit.py:49-51` is honored.

Live facts read (measured):
- Registry: truememory-2-0, state `registered`, one cwd_root (tm2-plan).
- TM2 frame: profile `standard`, pins anthropic=claude-opus-5-5, frontier=claude-fable-5-1,
  google=gemini-3.8-flash-high, openai=gpt-5.6-sol; preflight 2026-10-02 all four lanes ok.
- TM2 rounds so far: fc1 (counted=false: openai 2 slots void after 2 re-runs each, google dead after 2
  re-runs), fc2 (counted, 6/6 complete). Reviewer wall times 120-488 s, median about 360 s
  (`jq .wall_s rounds/fc*/panels/*.json`).
- cc-decide holds 6 TM2 class-B packets (`0118907dca69 57518ae1b3f9 8a7a95962f1e b44e73a345c2
  c81e1d1859b9 eced8121c3c7`), e.g. 0118907dca69 `veto_deadline 2026-10-06T04:00:00Z`,
  `default_if_no_veto add-two-path-rules`, `default_effect no-change`, conviction 44.
- Hooks `research-block.sh`, `research-precognition-nudge.sh`, `completion-assert.sh` are registered in
  `~/.claude/settings.json`; `.claude-next`, `.claude-quaternary`, `.claude-tertiary`, `.claude-secondary`
  settings.json are symlinks to it (measured readlink).
- Five research launchd plists are in `~/Library/LaunchAgents` (sweep hourly at :07). Logs:
  `research-sweep.out.log` tail = five lines `job sweep: no program in certifying|certified` through
  2026-10-04 05:07; triage and freshness logs say the same.

## 1. Transition-by-state matrix

Columns: R = registry state + cwd_roots resolution; S = operator signatures; RC = round counter + R_max
refusal + in-flight round; SV = seed vault secrecy + catch records; DP = decision packets + deadline sweep;
G = /goal inheritance; EX = standing-rule exemption; RT = router + tool block + relay check.

### 1a. Same-cwd recycle (`handoff-fire.sh --recycle`)
- R PASS — resolution is by path (`research-program.sh:62-107`); cwd unchanged.
- S PASS — signatures are records in `$CC_RESEARCH_HOME/<slug>/signoff.jsonl` pinned by blob sha
  (`operator_sign.py:160-182, 272-279`); no session state.
- RC FAIL if a round is in flight. round.sh is one long process (`round.py:195-267` waits on every slot;
  measured reads 120-488 s, fc1 needed 2 re-run waves), longer than the Bash tool's 10-minute ceiling, so
  it must run in the background, and a recycle ends the process. Sandbox (fixture-two): after the bundle
  step and before matrix.json,
  `round.sh run ... --round 1` => `refused: courier bundle failed: ... bundle .../rounds/1/bundle already
  exists; every round gets a fresh bundle` rc=2; `--round 2` => `certification round 2 out of order; next
  is 1 (no skipping)` rc=2. Cause: `round.py:273-282` + `courier.py:374-377`. The only way out is deleting
  the sealed bundle dir (an `rm -r`, which no unattended session can get approved). The Workflow path
  (`cli_cert.py:104-148`) has the same wedge if death falls between `courier bundle` and `plan.json`
  (a narrow window); after plan.json it is recoverable by hand with `slot`/`check-round`.
- SV PASS — keychain key `cc-research-seed-vault/<slug>` + sealed `vault/seeds.enc` (`seed.py:40-59`,
  `kit.py:435-453`); per-user, not per-session.
- DP PASS (on-disk). Liveness depends on state, see 1f.
- G PASS mechanically — `inherit_recycle_goal` (`handoff-fire.sh:7668-7683`, called at :15880) re-arms the
  predecessor's live goal. UNKNOWN interaction: the re-armed `/goal <cond>` is pasted as a prompt;
  `MACHINE_ENVELOPE` (`router.py:84-87`) does not match it, so the router classifies the goal text with
  Haiku, and the label is whatever Haiku answers (or `unavailable` under load, see 3c).
- EX PASS — same cwd.
- RT FAIL while certifying/certified. The recycle brief carries the `[handoff ` prefix
  (`completion-assert.sh:212`), and fired briefs carry `HANDOFF-ENGAGE-…` (`handoff-fire.sh:13857-13858`,
  set for every non-recycle, non-dry fire at :13717). Both match `MACHINE_ENVELOPE`, so `cmd_prompt`
  returns before classifying (`router.py:339-340`) and the new session id has no route record. Then
  `cmd_tool` treats it as unlabeled and sets `completeness` (`router.py:527-531`) and denies every tool
  except the certificate read. Sandbox:
  ```
  prompt "Continue the program. HANDOFF-ENGAGE-1-2-3" (sid succ-1) => no route file
  tool Read  (sid succ-1) => deny "...no genuine prompt has been routed in this session since the program
                             became certifying, so every tool is blocked except the certificate read..."
  tool Bash ls (sid succ-1) => same deny
  ```
  The successor can do nothing until the operator types a prompt, or relaunches with `CC_RESEARCH_BLOCK=0`,
  which turns the protection off.

### 1b. Recycle or handoff into a NEW worktree (`--worktree`)
- R FAIL for program membership. A sibling worktree is outside every cwd_root: sandbox `is-active
  $SB/root-wt2` rc=1. `cwd_roots` is set only by `gate.sh register`, which replaces the list
  (`gate.py:114-120`, `kit.py:268-269`). No verb adds a root.
- Records still resolve (absolute `cwd_roots[0]/docs/research/<slug>`, `kit.py:71-81`), so the CLI works.
- EX FAIL — the session is not "in" the program, so the standing rules (nothing left on the table,
  close questions, Follow-On Gate) apply in full. The exemption is supposed to cover "intake through build"
  (`~/.claude/rules/10-session-close.md`, Active research program exemption), but build waves normally fire
  with `--worktree`.
- RT FAIL (protection silently off): sandbox `tool Read` for sid succ-2 in root-wt2 => allow; the relay
  check needs a route record that only an in-program prompt writes.
- `--requires-gate` work-order marker: dead code for fired sessions. The marker is appended to the same
  brief as `HANDOFF-ENGAGE-…` (`handoff-fire.sh:13857-13863`), and the envelope check runs before
  `WORK_ORDER_MARKER` (`router.py:339-340` before :238-240). Sandbox: brief with both markers in the
  program root => no route file; `tool Edit` => deny "every tool is blocked". The bats test
  (`tests/research-router.bats:188-190`) feeds the marker without the engagement marker, so it passes.
- S, SV, DP, RC: as 1a.

### 1c. Account switch (`cc-lr switch`, same session uuid)
- RT PASS — route records are keyed on session_id (`router.py:120-123`), which the switch keeps; hooks
  are in the shared settings.json on every account (measured symlinks).
- R/S/SV/DP PASS — every store is under `$HOME/.claude/autonomy/research` or the keychain, not the
  account config dir (`kit.py:42-51`, `research-program.sh:37-39`).
- RC FAIL if a round.sh run is in flight. The switch relaunches the process (this run's own bundle:
  `events.jsonl` "relaunch-typed … spawning claude-opus-5-5/high on .claude-next"; `transplant.json`
  chain quaternary→next). A backgrounded round dies with it (memory "nohup ≠ detached"), giving the 1a
  wedge. Reviewer billing also follows the lead: courier passes the lead's env (`courier.py:178`), so a
  5-hour limit on the lead's account kills the Anthropic and frontier lanes together.
- G: no goal transfer is needed; same session.

### 1d. /compact
- PASS on every state element. Same session id, so the route stands; all state is on disk. /compact is a
  `<command-name>` envelope, so it is not routed and the last genuine label holds. UNKNOWN: a Workflow
  in flight across /compact (not tested).

### 1e. Usage limit mid-Workflow leaving slots PENDING (this run's bundle)
Measured on this audit's own bundle: workflow `wf_04d35035-e5f` settled `COMPLETE` with `COMPLETE:2
PENDING:12`, and each PENDING slot has "no terminal record (no tool_result, no task-notification)"
(`audit.md:16-41`); `lr-ingest-verify` `FAIL A2 — counts.gaps=0 counts.waiting=12`. So the harness can
report a workflow complete while most units never ran.

Applied to `round.workflow.js` (`:56-76`): a lost reviewer agent returns no exit; the script continues to
raters and `check-round`. `cmd_check` skips `dead` panels and never lists them for re-run
(`cli_cert.py:270-272`). The re-run loop re-runs only `voided` (`round.workflow.js:69-76`). A slot that
never ran has no panel and `write_matrix` records it `dead` (`cli_cert.py:325-334`). A lane counts as live
if ANY of its slots is complete or partial (`cli_cert.py:336-341`, `round.py:296-305`), and the round
counts if every lane is live. `round.sh close` marks it quiet if no new material hole was found
(`round.py:359`), with no check that the slots completed. See §2 for the sandbox and the wedge it causes.
If the limit also kills the `check` agent, no matrix.json exists. The round stays open, `open-round` says
"already open" (`cli_cert.py:107-108`), and `close` says "has not run" (`round.py:340-341`). That can be
recovered by hand (re-run `check-round`). Attempts used by killed agents count against the cap of 3
(`cli_cert.py:166-171`).
- R/S/SV/G/EX: unaffected. RC: FAIL (missing reads counted, §2). RT: unaffected, same session.

### 1f. Lead dead while a class-B packet's deadline passes (TM2: 6 packets due 2026-10-06T04:00Z)
- cc-decide's own sweep expires them (`bin/cc-decide:481-523`, `expire-sweep` → `expired-actioned`). With
  `default_effect no-change` nothing is dispatched.
- The program's decision record is updated only by `gate.sh sweep` (`gate_sweep.py` header items 1-2).
  The launchd job runs only programs in `certifying|certified` (`cli_jobs.py:44, 73-81`). Measured logs
  say "no program in certifying|certified" every hour. TM2 is `registered`, so its defaults are never
  applied to `decisions.jsonl` until a live session runs `gate.sh sweep --program truememory-2-0` by
  hand (SKILL.md: "Run `gate.sh sweep --program <slug>` daily in the pilot").
- Safety direction holds: `gate_requires.py:45` treats `open` as blocking. Liveness FAIL. A store
  mismatch follows (cc-decide says actioned, program record says open), and a successor may reconcile it
  wrongly.
- Dead-lane class-B default ("continue on two vendors", 48 h, `kit.py:162`): no code writes frame.json
  `degraded`/`dead_lanes` (grep: only the docstring `round.py:18`). Applying it means a hand edit of
  frame.json, which stales the frame signature (pin = whole frame.json, `operator_sign.py:164-168`; row 1
  fails STALE, `gate_rows_a.py:106-110`).

### 1g. Two leads live on one program
- Nothing gives a lead a lease or ownership. The only lock is the registry write lock (`kit.py:244-277`)
  plus the activities lock (`activities.py:38-53`). REPORT §3.7 step 6 promises "an advisory lock that tells
  sibling sessions the paths research depends on" (REPORT.md:442-443). `grep -rni advisory
  scripts/research-kit bin/cc-research scripts/lib/research-program.sh` finds nothing, so it was specified
  but not built. `cmd_freeze` (`gate_cert.py:33-68`) takes no lock.
- `open-round` is effectively serialized by the bundle mkdir (`courier.py:374-379`, mkdir without
  exist_ok). Below that, races are open. Two leads running `slot` on the same pid double-spend the cap of 3
  (`cli_cert.py:166-171`). `save_vault` uses a fixed temp name with no lock (`seed.py:52-59`), so
  concurrent `seed match` loses catch updates. CR/CH ids are minted read-then-append
  (`cli_jobs.py:64-70`, `cli_records.py:101`), and the launchd drift/market/freshness jobs are a second
  writer even with one lead. `kit.fold` merges records with the same id (`kit.py:338-348`), so a
  collision silently drops one record. Probability per event is low (ms windows); the mechanism is
  certain.
- RT PASS (per session). S/SV secrecy PASS.

### Matrix summary

| transition | R | S | RC | SV | DP | G | EX | RT |
|---|---|---|---|---|---|---|---|---|
| same-cwd recycle | PASS | PASS | FAIL (in-flight round wedge) | PASS | PASS | PASS / UNKNOWN label | PASS | FAIL (all tools denied, certifying+) |
| new worktree | FAIL (outside roots) | PASS | as above | PASS | PASS | n/a (`--goal` explicit) | FAIL | FAIL (protection off) / FAIL (fired-in-root wedge) |
| account switch | PASS | PASS | FAIL (relaunch kills round) | PASS | PASS | PASS | PASS | PASS |
| /compact | PASS | PASS | PASS / UNKNOWN in-flight Workflow | PASS | PASS | PASS | PASS | PASS |
| limit mid-Workflow | PASS | PASS | FAIL (missing reads counted) | PASS | PASS | PASS | PASS | PASS |
| lead dead past class-B deadline | PASS | FAIL-liveness (dead-lane default stales frame sig) | — | PASS | FAIL-liveness (registered not swept) | — | — | — |
| two leads | PASS | PASS | FAIL (attempt cap, matrix RMW) | FAIL (vault lost update) | FAIL (id collisions) | — | PASS | PASS |
| >7 days without an operator prompt | PASS | PASS | — | — | — | — | PASS | FAIL (route reaped → all tools denied) |

Last row, sandbox: a lead labeled `work-order` on day 0 is allowed. I set its route file mtime to
2026-09-25, then another session's prompt runs `route_reap` (`router.py:133-147`, `ROUTE_HORIZON_S = 7
days`). The file is gone (count 0), and the lead's next `tool Read` => `deny`.

## 2. Lost reviewer slots: verdict

**Verdict: a lost slot is counted as a quiet read for the stop rule, rejected as a missing read by the
gate, and never re-run by the Workflow path. A program hit this way is wedged with no recovery.**

Sandbox (fixture-prog, Lite, Workflow verbs, fake courier writing complete 11-lens panels). Rounds 1-3
each ran with slot `rNp1` (anthropic) lost (never run):
```
check-round => {"voided":[],"exit":0}
matrix => counted=true, lanes all live, notcomplete=[rNp1 status dead reruns 0]
close  => round N closed: new material 0, seeds caught 0, quiet=True
round 4 slots => "the stop rule has fired: the last 2 counted rounds were quiet; certify, do not review again" rc=2
gate row 13 => FAIL  "round 1: slot r1p1 dead" "round 2: slot r2p1 dead" "round 3: slot r3p1 dead"
repair after close: cc-research slot --round 3 --pid r3p1 => rc=0, panel status complete;
                    check-round => matrix still r3p1 dead, closed=true   (write_matrix refuses a closed round, cli_cert.py:318-319)
```
So the stop rule fires on rounds with missing reads (biased toward quiet). Gate row 13
(`gate_rows_b.py:276-286`) then refuses them, which keeps the certificate correct. But the program can no
longer issue a certificate or run another round. Recovery means hand-editing records, or an operator
reopen, which resets neither rounds nor the stop rule (`gate.py:139-145`; `plan_slots` reads every matrix,
`round.py:159-182`).

- **`partial`** (the reply has no JSON panel shape, `courier.py:509`) also makes its lane live and is
  never re-run in either path (`round.py:259-264` re-runs only dead/void; workflow only voided).
- **Re-fire and blind independence: PASS.** The bundle is built once at round open, before any slot runs,
  and EXCLUDE removes `rounds`, `holes.jsonl`, `verdicts.jsonl` and the rest (`courier.py:47-58,
  383-390`). A re-fired slot sees the same bundle and no sibling output. A reviewer that reaches outside
  the bundle and reveals it in raw output is voided by the needle grep (`courier.py:446-452, 502-507`).
  That is detection, not prevention: `codex -s read-only` can read any path.
- **Seed recall:** missing reads lower the catch count, so recall reads low and the forecast pessimistic.
  That bias is conservative.
- **Dead-lane rounds consume R_max.** Sandbox fixture-four (Lite): rounds 1-4 counted with material holes,
  rounds 5-6 with both OpenAI slots dead (the measured ChatGPT Plus wall: "walled after 15 reviewer-reads",
  about 4.5 h, research-calibration/REPORT.md:173-176):
  ```
  round 5/6 closed: counted=false lanes openai dead
  round 7: "round 7 is past R_max = 6"
  estimate.py forecast => {"stop":"running","rounds_counted":4,"r_max":6,"quiet_streak":0}
  ```
  `open-round` checks no lane health before spending a round number (`cli_cert.py:104-148`). No gate row
  requires stop ∈ {dry, cap} (grep `"stop"` in gate_rows_* returns nothing). `lines_for` prints "stopped at
  the round cap (N rounds)" for every stop other than `dry` (`gate_cert.py:195-199`), including `running`.
  So a program whose cap was used up by lost rounds certifies under the same headline as one the review
  actually stopped. Row 9 needs only one counted full round (`gate_rows_b.py:102-107`).

## 3. Physical capacity

### 3a. Anthropic fleet (measured, `~/.claude/logs/account-utilization.jsonl`, 42,942 rows 08-10 → 10-04)
- Four accounts, each with a 100 pp weekly bucket, so 400 pp/week nominal. In 2026-09-27 → 10-04 the
  fleet used **504 pp** (banked resets add to the nominal) over **41.7 working-session-days**, which is
  **12.1 pp per session-day** (per account 10.3-14.1).
- Every account reached 100% weekly in every recent window (peak table: next, next2, next3, next4 all 100
  for the windows resetting 09-22 → 10-06). Hours spent at 100% weekly that week: 54.5 / 75.0 / 10.0 /
  11.7. **The fleet is already saturated, so a research program displaces other work one for one**,
  including the 7 stale customer rows on the mission board.
- Current (cache 2026-10-04 10:19Z): weekly 10/2/50/0%, Fable 0/0/3/0%, 5 working sessions.
- 5-hour session windows: 40 samples at session_pct ≥ 100 since 09-27. This audit's lead hit one at
  07:59Z ("resets 4:40am").

### 3b. Per-read and per-program prices
- Anthropic: 0.05 pp per Opus reviewer-read, plus 0.16 pp per round for triage (measured by calibration,
  research-calibration/REPORT.md:168-172). Fable: the cost multiple is asserted at 2-5x (CLAUDE.md
  frontier section, "re-measure before quoting"), so 0.10-0.25 pp per read against a 50% Fable sub-cap,
  about 200 pp/week across the fleet.
- OpenAI: one ChatGPT Plus (`claude-accounts --agents --json`: codex plan "ChatGPT Plus"; pi-codex "rides
  the SAME ChatGPT Plus"). 70,238 tokens per read. Walled after 1,621,093 tokens in one window and refused
  for about 4.5 h (calibration §4.8). **Modeled:** about 23 reads per window; with a window every ~5 h
  that is about 4.8 windows and about 110 reads/day at most. The Plus weekly cap is unmeasured (unknown).
- Google (`agy`, gemini-3.8-flash-high): quota and plan unknown (providers registry: gemini "plan tier
  UNKNOWN"; the calibration never ran Google). **Unknown.**
- Code caps on reads per program (static `kit.py:119-168`, `round.py:166-171`): Lite ≤ 6(+1) rounds × 8 =
  56 reads + 12 frame-critique; Standard ≤ 11 × 16 = 176 + 12; Full ≤ 15 × 24 = 360 + 12. Post-signoff
  deltas are at most 2 per escape.
- **Modeled reviewer cost per program:** Standard at cap is about 40 Opus reads (2 pp), 40 Fable reads (4-10
  pp of the Fable sub-cap), 10 triage (1.6 pp), and about 40 OpenAI reads + raters ≈ 4.3M tokens ≈ 2.7 Plus
  windows. **Reviewer reads are not the binding cost. The lead's agent-days are.**

### 3c. Profile budgets in quota-days (modeled at 12.1 pp per agent-day, measured)
| profile | agent-days | pp | share of a 400 pp fleet-week | one-account-days (14.3 pp/day) |
|---|---|---|---|---|
| Lite | 4.25-6.5 | 51-79 | 13-20% | 3.6-5.5 |
| Standard | 11.5 (`kit.py:117`) | 139 | 35% | 9.7 |
| Full | 17.25 | 209 | 52% | 14.6 |
Plus reviewer and triage, which add 2-11 pp. **Fleet ceiling if the program took everything:** 400-504
pp/week ÷ 12.1 = 33-42 agent-days/week, about 4.7-6 agents sustained. That is the physical ceiling on "as
hard as possible". "As long as possible" is bounded by the code caps on purpose, and the calibration
argues wider review is net-negative at 1.13 false material calls per read (calibration REPORT.md:34-40).

### 3d. Where the method's own instruments degrade (this box: 10 cores, measured `sysctl hw.ncpu`)
- Now: `uptime` load 34.56 37.42 40.82; 24-32 claude processes.
- Router classifier: fallback 0.51 at load 45-80 and 0.96 at load ~295 against the 6 s limit (asserted,
  RESEARCH_PROGRAM_BUILD.md:172-176; a cold `claude -p` on haiku takes ~2 s at load 45 and ~5 s at 295).
  So the router is at its failure edge at today's ordinary load. A Standard round adds 16 parallel
  reviewer processes (8 `claude -p`, 4 codex, 4 agy), which pushes load past 45.
- What a fallback costs, sandbox: classifier `sleep 3; echo completeness` with timeout 1 s →
  `label=unavailable`; `relay-check` on "Yes, done. One more thing: scripts/foo.sh:12 …" => rc 0 (not
  blocked); `tool Read` => allow. Control with a fast classifier: `label=completeness`, relay-check rc 1,
  Read denied. Cause: `cmd_relay_check` returns 0 unless the label is in RELAYED (`router.py:638-641`).
  **At ordinary fleet load about half of completeness re-asks in a certified program are not checked.**
  This is the "one more thing" failure the method exists to prevent.
- Probes: P-S4-K11-openclaw "timed out (exit 124 at 900 s, machine load ~225)" (asserted,
  tm2 `residual.jsonl:6`). Courier slot timeout is 1800 s (`courier.py:558`). The router also renders the
  certificate under a 5 s timeout (`router.py:194`).
- Degradation thresholds (modeled from these points): router unreliable from load ≈ 45 (≈ 4.5/core);
  probe and reviewer timeouts become likely at ≈ 200+ (≈ 20/core). Today's baseline is 35-41, so roughly
  1-3 more heavy agents of headroom before the router fails half the time.

## 4. Strengths found
- The registry resolver is deterministic, bash 3.2-safe, longest-root, and fails toward "no program"
  (`research-program.sh:31-35, 62-107`). The sandbox override works (positive control).
- Account switch and /compact keep every state element (1c, 1d), and the hooks are shared across all four
  account configs.
- Gate row 13 fails closed on any non-complete slot in a counted round. Lost reads cannot quietly certify
  through that row.
- Re-fired slots cannot see sibling output (bundle built pre-slot, EXCLUDE list).
- The slot re-run cap is in code and survives sessions (`attempts.jsonl`).

## 5. What the strongest attainable version needs (for the operator's goal under this regime)
1. Every machine-envelope first prompt in a program root (recycle, fire, limit-recover, `/goal` paste) gets
   a deterministic route: inherit the predecessor's label by the custody/recycle chain, or default
   machine briefs to `work-order` when they carry `--requires-gate` or a recycle of a labeled lead. Drop
   the 7-day reaper for a live session (key the horizon on process liveness).
2. `unavailable` must fail toward relaying the certificate (`completeness`) at Stop, not toward
   allowing. Or move the classifier off a cold `claude -p` so it meets its 6 s budget at load 300.
3. A round counts only if every planned slot is `complete`. `close` refuses otherwise. The workflow and
   `check-round` re-run dead, missing and partial slots, not just voided ones. `open-round` refuses
   unless a fresh preflight shows every lane live, so a walled vendor costs no round number.
4. The gate requires stop ∈ {dry, cap-by-counted-rounds}. The certificate states lost rounds separately.
5. round.sh runs as a detached job (scripts/lib/detach.sh) whose state is resumable: re-entering a round
   with a bundle and no matrix resumes it instead of refusing.
6. A program lease (owner session + heartbeat) in the sealed dir, checked by every writing verb. Locked id
   minting. A vault write lock.
7. `gate.sh add-root` (or roots registered automatically by `handoff-fire --requires-gate`), so build
   worktrees stay inside the program.
8. The launchd sweep also covers `registered` programs that have open program packets.
