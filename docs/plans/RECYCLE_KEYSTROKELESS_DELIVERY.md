---
status: complete
---

# RECYCLE_KEYSTROKELESS_DELIVERY — a recycle must not strand its pane, and a failure must reach the original

**Filed:** 2026-10-09 by session 80734d02 (pane wt-cc-103912-48554), from the incident below.
**Scope (frozen):** find the true root cause of the 2026-10-09 recycle relaunch-write failure (kitty pane 44,
session 6defb493), then fix `handoff-fire --recycle` so that (a) the successor launch no longer depends on
the failing leg, and (b) when a recycle does fail after `/exit`, the original session is resumed or told,
and gets the exact correct re-fire command, instead of idling unaware. Tests, land and converge are included.
**Root-cause evidence:** Dynamic Workflow run `wf_462dbffc-a38` (5 lenses, synthesis, 2 skeptics). Its
journal is in the lead's session dir; the load-bearing facts are restated below so this file stands alone.

---

## Phase 0 — Agent Team Orchestration

**EXECUTION LOCUS: S — one dispatched handoff session**, which leads its own Agent Team (default; no
justification needed). The lead (session 80734d02) only harvests the notify-back and reviews.

**Task size band:** each unit 40–150K output ≈ 30–75 min ≈ 3–6 files. Unit 2 is the largest. Split it if
its diff passes 500 LOC.

| Unit | Owner (teammate) | Files owned (exclusive) | Deliverable | blockedBy |
|---|---|---|---|---|
| U1 | `consumer` | NEW `lib/pane-successor.sh`, `scripts/limit-recover/lr-fire-resume.sh` (fall-through only, :1536-1558), `bin/cc-close-attrib`, `install.sh` (deploy the lib only if needed) + tests | §D1 consumer side | — |
| U2 | `delivery` | `scripts/handoff-fire.sh` regions: `_it2_type_line`/`it2_type_verified` (~:3677-3724), bounds (~:1027-1055), recycle foreground staging (~:16370-16830), watcher wait/claim/typed block (~:9399-10080) + tests | §D1 producer side, §D2 | — (codes to the §D1 contract) |
| U3 | `resume` | `bin/cc-resume-debt`, `scripts/boot-resume-launch.sh`, `bin/reso-resume-one` (incl. its fall-through consumer :862-887), `hooks/session-start-dispatch.sh` child + tests | §D4 | — |
| U4 | `awareness` | `scripts/handoff-fire.sh`: NEW `rcy_recovery_packet` + `rcy_pane_paint`, `hf_alarm` (~:7900-7940), calls at each post-`/exit` terminal arm, `rcy_debt_settle` (~:9428) + tests | §D3 | U2 (same file: start after U2 merges) |
| U5a | `libfix` | `lib/pane-successor.sh`, `bin/cc-close-attrib`, `hooks/recycle-failed-inject.sh` + tests | review items 4, 6, 7, 9 | U1 (landed) |
| U5b | `resumefix` | `bin/reso-resume-one`, `bin/cc-resume-debt`, `scripts/boot-resume-launch.sh`, `scripts/boot-resume.sh` (exit-5 messages) + tests | review ORDERING + items 1, 2, 3, 5, 8 + both PLAUSIBLE | U3 (landed) |

### Completion (2026-10-09, dispatched lead aa3e64c4) — every unit DONE, landed and live

All shas below are on `origin/main` (landed in three lands: `d1ccc37f5`, `77b525098`, `7c5256c54`) and
converged to the live layer with `deploy-live.sh` (the land's own converge kick, degraded tier, never
`--force`).

- **U1 DONE** — `58649db56` (lib + lr-fire-resume and cc-close-attrib consumers), with gate fix-ups
  `71936532f` `1a266fa3e` `d1ccc37f5`. Learning: the land gate's ratchets (hermeticity seams,
  dead-assertion, .bats shellcheck, M11 capacity pins) are the real merge bar. Put them in every brief.
- **U2 DONE** — `f4b297310` (§D2 typed fallback + per-attempt telemetry), `c54a3c0bd` (§D1 producer +
  watcher claim-or-revoke), `cafed7eca` `77b525098` (claim-suite race + annotations), `7c5256c54`
  (sysctl by absolute path). Learning: the claim check must also run inside the shell-wait loop,
  because a fast consumer claims before the watcher ever samples the bare shell.
- **U3 DONE** — `0d435c754` (boot-resume-launch), `1fb6b3752` (cc-resume-debt), `38ee1eac7` (SessionStart
  child), `55bc6fe2e` (reso-resume-one).
- **U4 DONE** — `a246323e8` (handoff-alarm-polarity), `3578b0e19` (packet, paint, revoke-before-verdict,
  `--recovery-of`, hf_alarm via jq + sid address, settle `--recovery`), `fe582468b` (`HF_WATCHER_IT2`
  watcher transport seam for the live proof), `7c5256c54` (recovery-of gets its own gate denominator).
  The lead wired the polarity check into `cc-blockers` (`64c196ba2`, its own HANDOFF ALARMS section):
  live it reads RED, 0 of 15 alarms heard in 7 days.
- **U5a DONE** — `495d4d358` (inject: print before stamp), `5ac7f9159` (nonce-bound stage, pane check,
  flat successor loop). **U5b DONE** — `f062055cc` (cc-resume-debt), `55cd91521` (reso-resume-one),
  `6458e9085` (boot-resume-launch exit 6). Every review item was fixed with a test that is red before
  the fix; none was refuted.
- **Gates (DoD 2):** merged-tree bats, every new and touched suite, plan line asserted, 0 failures:
  - New suites: pane-successor 1..31, recycle-failed-inject 1..9, handoff-recycle-typed-fallback
    1..16, handoff-recycle-successor-claim 1..7, handoff-recycle-recovery-packet 1..17,
    handoff-alarm-polarity 1..7.
  - Touched suites: cc-close-attrib 1..32, reso-resume-one 1..62, cc-resume-debt 1..47,
    boot-resume-launch 1..23, boot-resume 1..72, session-start-dispatch 1..6,
    lr-recon-fence-callsites 1..22, handoff-alarm-records 1..20, handoff-recycle-custody 1..7,
    handoff-fire-recycle-custody 1..42, handoff-fire-inject 1..25, handoff-recycle-shell-flicker 1..3,
    handoff-recycle-remote-resume 1..48, handoff-recycle-dead-escalates 1..7, cc-blockers-comms 1..15,
    cc-blockers 1..107, cc-blockers-teammate-reap 1..9, handoff-fire-capacity-gate 1..52.
  - Smoke-cut suites re-run after the last land: handoff-composer-gate 1..60, cc-eligible-history
    1..16.
  - U2's wide run over its scope: 1..793, with the 2 runner-cap timeouts green when uncapped.
  - Bare `shellcheck` is green on every touched script.
- **Live proof (DoD 3)**, scratch kitty os-windows the lead created and closed by id (153-158). No
  operator pane was touched. Evidence: `/tmp/rk-e2e/{A,B,C}/evidence.txt`.
  - **A, claim:** pane 154 logged `recycle-successor-staged`, then `recycle-successor-claimed` ("nothing
    typed"), then `recycle-engaged`. There were **0** `recycle-type-attempt` rows. The predecessor's
    close record carries `successor_claim`.
  - **B, consumer off** (`CC_PANE_SUCCESSOR=off`): pane 155 used the typed fallback and wrote one UTC
    `type-attempt` line per attempt to the watcher log, plus one `recycle-type-attempt` row each (2,
    both `verdict=submitted`), then engaged.
  - **C, typing forced to fail** (`HF_WATCHER_IT2` stub): pane 157 failed 16 typed attempts
    (`send_rc=1`) and marked the recycle dead, wrote the packet `recycle-failed/04bfa0e6….json` and
    `.prompt.md`, and painted the pane with the one relaunch command and the packet path.
    `settle --recovery` resumed the original in window 158 via reso-resume-one, whose FIRST user
    record is the packet prompt with its token. The inject child stood down (`injected_at` null). The
    original then re-fired with `--recovery-of` (`refired_at` stamped), and that re-fire was delivered
    BY CLAIM with nothing typed.
  - First attempt, lesson recorded: a scratch window whose cwd is an untrusted folder stops at Claude
    Code's workspace-trust dialog. Accepting it there made the session exit 1. Launch scratch probes
    from an already-trusted directory.
- **Filed:** `f61abdb39f2c` (needs-credential). It covers push-send's Pushover env, the one phone
  consumer the existing rows `516d31862158` and `ee8eaa873f8a` did not name.

- **U5 (added 2026-10-09 by the dispatched lead):** the originating lead's fresh-context review of the
  landed U1+U3 (`d1ccc37f5`) found 9 confirmed and 5 plausible defects
  (`/tmp/rk-review/u1u3-review-2026-10-09.md`). Its two U2/U4 must-fixes went to U4: revoke the
  staged successor BEFORE any failure verdict, and a real-fixture account test. The rest split by file
  into U5a/U5b, which run in parallel with U4. Each item is fixed with a test that fails before the
  fix, or refuted with evidence recorded below.
- **Worktrees:** one branch per teammate, created by the dispatched lead. Merge order: U1 → U3 → U2 → U4
  (smallest first, and U4 rebases on U2). Gate every merge with the land gate's own shellcheck + the
  touched bats suites.
- **Lead (80734d02) context budget:** at least 50% is reserved for review. **Succession point:** after the
  notify-back harvest and review, the lead closes. It does not implement.
- **Dispatched session's succession point:** recycle (re-arming its `/goal`) at the U2/U4 boundary if it is
  above 60% context.

---

## Root cause (what the evidence supports, and what it does not)

**Timeline (UTC, 2026-10-09).** At 04:54:48 session 6defb493 (kitty window 44, tty ttys013, predecessor
launched at 21:02Z Oct 8 by `lr-fire-resume.sh`) ran `handoff-fire.sh --recycle`. The `/exit` readback,
the background-work Esc and the `'1'` answer all landed by 04:55:51, and claude exited.
`lr-fire-resume.sh:1558` then exec'd a cold `zsh -l -i`. From about 04:56:30 to 05:03:21 the watcher
(pid 22463) ran 16 `_it2_type_line` attempts: 2 rounds × (the nocorrect line + the relaunch line) × 4.
All 16 failed. A final `session list` read the pane as "unknown". The pane was left at a bare prompt, and
the successor never ran.

**MEASURED**
- Load was about 45 runnable per core: `~/.claude/logs/capacity-alarm.jsonl` load_1m 453.67 at 04:54:33,
  falling to 422.21 at 05:02:48 on 10 cores. This is the only recycle out of 35 retained recycle logs that
  ran above load 70, and the only "write failed twice". The other 31 typed relaunches succeeded at load
  13-70.
- The same shim and the same 10 s bound DELIVERED `/exit`, Esc and `'1'` into pane 44 one minute earlier,
  at the same load. The kitty probes answered in under 1 s (`kitty-probe@1s`, `listing rc=0 in 1s`). So
  the transport was not uniformly dead.
- Kitty executed a timed-out remote-control request about 9 minutes late. boot-resume-launch's os-window
  launch returned "kitty launch failed" (rc 4) at 05:03:51, yet window 134's zsh started at 05:12:38. So
  a "failed" kitty request can still execute later.
- `_it2_type_line` (scripts/handoff-fire.sh:3677-3712) treats rc 124 on the paste as not delivered
  (`continue` with no read, :3698). The next attempt opens with ^U. A slow paste that did land is scrubbed
  unread: in a scratch window, 3 of 4 rc-124 pastes were on screen.
- The outer bound per call (HF_TIMEOUT_S=10, :1027) is smaller than it2-kitty's own 15 s bound per kitty
  call (bin/it2-kitty:95), and one `send` makes two kitty calls (prove_target, then send-text). This is the
  same inversion that was fixed for split only, at :1038-1050.
- **Awareness gap, every link measured dead.**
  1. `hf_alarm` pushes to role `desk`, which does not exist. All 24 alarm verdicts ever recorded are
     refused-rc3. Its `tr '\n\r\t"' "   '"` (:7917) also corrupted the manual command into `'$(cat …)'`.
  2. `cc-resume-debt` `_escalate` calls `cc-notify --page`, which does not exist (rc 2, bin/cc-notify:569).
  3. `_in_pane_ok` (cc-resume-debt:266-275) needs a `cc-pane state` verb that does not exist, so it always
     relaunches in a new window.
  4. reso-resume-one resumed 6defb493 in window 134 with NO prompt, although it supports `--prompt-file`
     (:74, :100-112, :686-690). Nothing in the chain passes one.
  5. A replayed task-notification does not drive a turn, so the original never woke.
  6. `_prove_debt` then discharged on liveness alone (05:44:46) and auto-closed backlog row 85f4942a130f.
  7. The phone channel is inert: 487 of 488 push records since 10-01 are inert, because PUSHOVER creds are
     unset.

**NOT DETERMINED (no per-attempt telemetry existed).** Which leg failed is unknown. The candidates are:
(i) kitty remote-control requests timing out at the 10 s bound under GPU and CPU contention (a Blender
render and 41 MTLCompilerService processes), with ^U and paste then executing late and in order, which
fits the empty prompt; (ii) a fast transport into a cold `zsh -l -i` (p10k instant prompt with
`stty -icanon` during init, bracketed-paste-magic, highlighting) whose echo arrived after the single read
0.5 s later; (iii) both. A skeptic refuted the claim that the transport "cannot deliver under that load"
because of the same-load `/exit` success. Conviction that the trigger was load-induced lateness in
keystroke delivery or echo: 85%. Conviction in any single leg: 50% or less.

**Therefore the fix does not bet on a leg.** It removes keystrokes from the successor launch entirely
(§D1). The typed path survives only as a hardened fallback that records the missing telemetry (§D2).

---

## Design

### D1 — keystroke-free successor delivery (fresh-mode recycles)

Every process that regains the pane's tty when claude exits already exists: `lr-fire-resume.sh`'s
fall-through, `reso-resume-one`'s fall-through, and `cc-close-attrib`, which wraps every `claude()` launch.
Today they only keep a shell for the watcher to type into. Instead, the recycler STAGES the successor
before `/exit`, and the consumer RUNS it. Delivery becomes a local atomic rename, so load can delay it but
cannot fail it.

**Contract** (`lib/pane-successor.sh`, bash 3.2 and zsh portable; U1 writes it, U2 and U3 code to it):
- Directory `~/.claude/run/pane-successor/` (mode 0700). Key = the pane tty basename (`ttys013`).
- Producer `cc_pane_successor_stage <tty> <cmdfile> <meta.json>` writes, via tmp + mv:
  - `<key>.cmd`: a self-sufficient command: `cd`, explicit `CLAUDE_CONFIG_DIR=<target cfg>`, account pin
    and the full launch line. It must not depend on the consumer's inherited env.
  - `<key>.json`: {pane, pane_tty, pred_sid, watcher_pid, watcher_lstart, created_epoch, ttl_s, mode,
    token}.
- Consumer `cc_pane_successor_take` → rc 0 and prints the claimed path ONLY if all hold:
  - `<key>.cmd` exists, and `meta.pane_tty` equals the caller's own `tty`. An expect inner pty never
    matches.
  - The watcher pid is alive with a matching lstart (same proof as `lib/pane-recycle-pending.sh:44-53`).
  - `now < created + ttl_s`.
  - The file is owned by this uid and is not group- or world-writable.
  - It claims with `mv <key>.cmd <key>.claimed.<pid>`. **That rename is the ack.**
- Producer revoke `cc_pane_successor_revoke <tty>`: `mv <key>.cmd <key>.revoked`. A failure means the
  consumer won.
- Consumer exec form: unset the predecessor's per-launch variables (at minimum `CLAUDE_CONFIG_DIR`, which
  the claudeN functions export through cc-close-attrib; skeptic flaw 9), then
  `exec "${SHELL:-/bin/zsh}" -l -i -c 'source "$1"; exec "${SHELL:-/bin/zsh}" -l -i' cc-successor <claimed>`.
  In cc-close-attrib, drop the trailing shell, because control returns to the parent zsh. p10k instant
  prompt disables itself under `-c` (`${+ZSH_EXECUTION_STRING}`, verified).
- **No consumer registration.** The skeptic's flaw 8 (a registration outliving its consumer across `exec`)
  is avoided by design: the producer always stages, and §D1-watcher decides by claim-or-revoke.

**Producer (U2), fresh mode only.** Resume and lr-transplant recycles keep the typed path, because the
fold, launch-lock and holder rails (:9971, :10047, :10055) must run before anything starts (skeptic
flaw 1).
- Save `HF_ORIG_ARGV=("$@")` before option parsing.
- Stage after the lock handoff to the watcher and before `/exit`. Pass the mode through the meta file, not a
  new positional argument (the $15/$16 off-by-one at :9443-9450 is the lesson).
- Watcher, after the bgwork arms:
  - If `<key>.claimed.*` exists, skip the typing block, set `rcy_typed_at` to the claim epoch and fall into
    the existing boot and engagement wait.
  - If `at_shell` has held continuously for `CC_RECYCLE_CLAIM_GRACE_S` (default 20) with no claim, revoke.
    If the revoke wins, use the typed fallback (§D2). If it loses, the consumer claimed.
  - The watcher's EXIT trap revokes anything still staged.
- Load-scale the post-claim budgets (engagement wait RCY_ENGAGE_TIMEOUT=180 at ~:10010, at_shell wait),
  because the successor still pays a cold start under load. `arm_goal` still TYPES `/goal`: see Known
  residuals.

### D2 — the typed fallback, hardened and instrumented (U2)

1. **Telemetry first and mandatory.** Write one UTC line per attempt to the watcher log and to
   handoffs.jsonl `recycle-type-attempt`: send rc and duration, read rc and bytes, nonce_seen, suffix_ok,
   focused, load per core. The next occurrence must name its leg.
2. `HF_SEND_TIMEOUT_S` = `${HANDOFF_SEND_TIMEOUT_S:-$(( ${IT2_KITTY_TIMEOUT_S:-15}*2+10 ))}` beside
   :1050, used for send and read in `_it2_type_line`. Pin it with an arithmetic test, mirroring the split
   pin.
3. rc 124 on a send means "delivery unknown": always read before any ^U scrub.
4. Replace the single read after 0.5 s with polling for the nonce up to a deadline that scales with load
   per core.
5. Before the CR, the input line must END with the wire, after stripping a literal trailing `ESC[201~` or
   `^[[201~` echo.
6. If the CR send returns non-zero, re-read. A cleared line or a non-shell foreground means it was
   submitted, so never retype. Late kitty execution is real (§Root cause), so assume a timed-out request
   may still land.
7. Replace the fixed 4 attempts × 2 rounds with a deadline loop (default 10 min, `CC_RECYCLE_TYPE_DEADLINE_S`).
   Waiting at a bare shell costs nothing.
- **Dropped:** the synthesis's pre-`/exit` load/rtt gate ("A2"). Both skeptics showed it would not have
  fired correctly here (rtt read under 1 s at load 450), and loadavg on this box is dominated by
  QoS-demoted batch work.

### D3 — a post-`/exit` failure is impossible to miss (U4)

- `rcy_recovery_packet <class> <cause>` is called at EVERY post-`/exit` terminal arm: pane vanished
  (~:9886), surface gone (~:10033), relaunch failed (~:10075), boot or engagement failure (~:10381,
  ~:10444). It writes, with `jq -n --arg`, `~/.claude/autonomy/recycle-failed/<pred_sid>.json`:
  - failed_at, class, pane, pane_tty, cause (the last telemetry line, the pane_enumerated verdict, load
    per core);
  - brief (the ORIGINAL `--prompt-file`), goal, account AS GIVEN (`auto` stays `auto`; skeptic flaw 14),
    effort, the watcher log path;
  - token `recycle-recovery:<sid>:<epoch>`;
  - `refire_cmd` rendered with `printf %q` from `HF_ORIG_ARGV`.

  It also writes `<pred_sid>.prompt.md`: "Your self-recycle at <ts> FAILED (<class>: <cause>); the
  successor never ran. FIRST check that no successor is live (<exact check command>). If none, re-fire
  with exactly: <refire_cmd>."
- **Never-confirmed-shell arm** (~:9913-9947, the original is still ALIVE at the dialog): write no
  re-fire packet. Deliver the failure by `cc-notify` to the sid mailbox (asyncRewake path,
  `hooks/mailbox-wake-arm.sh`), and count the attempt (skeptic flaw 4).
- **Pane paint** `rcy_pane_paint`: `printf` a framed banner to the pane tty at every arm where the pane is
  a bare shell: what failed, when, and the one exact command to run. A local tty write works under any
  load. It is what the operator would have seen in pane 44 instead of a bare prompt (skeptic flaw 7).
- **Idempotency** (skeptic flaw 5): `handoff-fire.sh --recycle --recovery-of <token>` refuses (exit 2,
  named) when the token's recycle has since recorded `recycle-engaged`, or a live claude holds the pane.
  `refire_cmd` always carries `--recovery-of`.
- `hf_alarm`:
  - build the record with jq (fix the `'$(cat …)'` corruption);
  - add `refire_cmd` and packet fields;
  - when `~/.claude/cc-roles/desk` is absent, address the originating sid's mailbox instead of a dead role;
  - add an alarm-polarity check that goes red when 100% of the verdicts in the window are refused.
- `rcy_debt_settle` passes `--recovery <packet>` to `cc-resume-debt settle`.

### D4 — the resumed original wakes with the packet as its first prompt (U3)

- **reso-resume-one** is the chokepoint (skeptic flaw 6). When `recycle-failed/<sid>.json` exists and is
  undelivered, it auto-attaches `--prompt-file <sid>.prompt.md`. It submits the prompt as a launch argument
  (the only form proven to drive a turn on resume), and stamps `delivered_at` once the transcript holds the
  token in a user record. U3 also verifies, and fixes or records, which other resumers bypass
  reso-resume-one: boot-resume.sh, cc-pane, cc-resume-layout.sh, lr_recon.
- **SessionStart child** (second channel, for a manual `claude --resume`): inject an undelivered packet as
  additionalContext exactly once. This adds a child to `hooks/session-start-dispatch.sh`'s list, with no
  settings.json edit.
- **cc-resume-debt:**
  - `settle --recovery <packet>` is stored in meta, and `_relaunch` passes `--prompt-file`.
  - `_prove_debt`: with a packet, liveness alone does NOT discharge. Proof is a live successor in the pane,
    or the token followed by an assistant record (skeptic flaw 13: the re-fire then owns its own debt).
  - The deferral on H(sid)>0 counts attempts, so it escalates.
  - `_escalate` uses a real channel instead of `--page`, and puts `refire_cmd` and the packet path in the
    backlog row's title and `--run`.
- **boot-resume-launch.sh:**
  - `--prompt-file F` passthrough into CMD (~:179-180).
  - `--next-to <pane>`, which launches `--type=window --next-to id:<pane>` instead of an os-window.
  - Every launch carries `--env CC_LAUNCH_TOKEN=<nonce>`.
  - A kitty client rc 124 or 137 maps to exit 5 (indeterminate) and is reconciled with
    `kitty @ ls --match env:CC_LAUNCH_TOKEN=<nonce>`. A timed-out launch never gets a second launch or an
    escalation until reconciled, because window 134 was created 9 minutes late.
- `_in_pane_ok`: replace the dead `cc-pane state` call with the real in-pane path, or delete the dead
  branch and say so.

---

## Tests (each unit owns its own)

- **Controls replay the REAL artifacts, not the hypothesis** (skeptic: a stub that times out "reproduces"
  any cause).
  - The real cmdfile `handoff-recycle-cmd-44-1791521709-F9a6WT.sh` and the real alarm
    `~/.claude/handoff-alarms/alarm-20261009T050321Z-22463-28344.json` (it shows the `'$(cat …)'`
    corruption) are copied into fixtures.
  - Typed-mode controls, both run against D2:
    - a fast transport with a slow-to-echo receiver (echo after more than 0.5 s);
    - a transport that times out but executes late.
  - Positive control: a composer-like receiver succeeds under the same stub (the measured 04:55 `/exit`
    success).
- **D1:**
  - With the always-timing-out stub, file mode still starts the successor (marker file), with ZERO
    relaunch `session send` calls.
  - Claim vs revoke race: 50 iterations, exactly one winner each time.
  - Refusals: dead watcher or lstart mismatch, expired TTL, tty mismatch (expect inner pty),
    world-writable file.
  - Consumer env: `CLAUDE_CONFIG_DIR` from the predecessor does not leak.
  - Resume mode never stages.
- **D2:** a 124-but-delivered paste verifies with exactly one CR; a 124 CR on a consumed line causes no
  retype; an `ESC[201~` suffix verifies; residue fused with the wire causes no CR; one telemetry line per
  attempt; the bound arithmetic pin.
- **D3:**
  - Every terminal arm writes valid JSON.
  - `refire_cmd` passes `bash -n` and carries `--recycle`, the original `--prompt-file`, `--effort`,
    `--account` as given, `--goal` and `--recovery-of`.
  - The never-confirmed arm writes no re-fire packet and sends mail.
  - The paint reaches a fake tty.
  - `--recovery-of` refuses after an engaged row.
- **D4:**
  - reso-resume-one auto-attaches the prompt only while undelivered.
  - `settle --recovery` reaches the RELAUNCH argv.
  - LIVE alone does not discharge.
  - `_escalate` never passes `--page`.
  - boot-resume-launch: indeterminate gives exit 5, and token reconciliation finds the window.
  - SessionStart injects exactly once.
- Run every script that launchd or a hook runs under `/bin/bash` 3.2 as well (deployment-interpreter
  lesson).

## Definition of done

1. All four units are merged on one branch, landed via the project `/ship`, verified by content
   (`git ls-tree origin/main -- <paths>`), and converged with
   `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh`.
2. `bats` passes on every new and touched suite, with plan lines asserted (`1..N`). The land gate's
   shellcheck is green on every touched script.
3. A live end-to-end proof in a scratch kitty pane started for the purpose, never an operator pane:
   - a fresh-mode `--recycle` relaunches by claim, with zero typed relaunch;
   - with the consumer disabled, the typed fallback logs one telemetry line per attempt;
   - with typing forced to fail (a stub it2 via env), the pane is painted, the packet exists, and a
     reso-resume-one of the predecessor submits the packet prompt.
4. This plan's units are marked DONE with commit hashes and learnings.

## Known residuals (stated, not fixed here)

- Typed actuators still exist: `/exit`, the background-work answers, `arm_goal`'s typed `/goal`,
  composer_scrub and the nudge retype. A successor can start without its goal under a load spike. The
  packet and engagement row carry the goal text, so it can be re-armed.
- A predecessor launched before the deploy still runs its old consumer script inode, so it takes the typed
  fallback (D2) until relaunched.
- The phone channel is inert until the PUSHOVER creds are set. That is an operator credential step, filed
  as needs-credential, not fixed here.
- The load source (renders, builds, E1k waiting for ambient load) is outside this plan.

## Refinements where the code proved the plan wrong (dispatched lead, 2026-10-09)

- **U1:** `take` also refuses a group- or world-writable STAGING DIR, not only the `.cmd`, because a
  writable dir lets another user swap the file. The requested key AND `meta.pane_tty` must both equal
  the caller's own tty. `exec` also unsets `CC_ACCOUNT_PINNED` and `CLAUDE_ISOLATION_SKIP`, the
  incident cmdfile's other per-launch prefixes. `stage` clears the previous recycle's
  `.revoked`/`.claimed.*`, and `take` touches the claim file so `claimed` reports the claim epoch
  (mv keeps the staged mtime). `install.sh` needed no edit: its `lib/*.sh` loop links the new lib.
- **U3, `_in_pane_ok`:** deleted rather than repaired. It was dead twice over: `cc-pane state` never
  existed, and `handoff-fire --relaunch-at-shell` also requires `--expect-identity`, which the debt
  store never holds. A pane at a bare shell is now reached by the pane-successor consumer. Every debt
  retry is a new window.
- **U3, escalation channel:** `cc-notify --from cc-resume-debt <sid> "<msg>"`, the stranded session's
  own mailbox (a raw uuid is a valid target), plus the needs-human backlog row. A recovery row's
  `--run` is the packet's `refire_cmd`.
- **U3, deferrals:** the 3rd H(sid)>0 deferral (`CC_RESUME_DEBT_MAX_DEFER`) counts as a failed
  attempt (relaunch_rc 75), so the next step escalates.
- **U3, indeterminate launch:** a kitty rc 124/137 with no window carrying the token exits 5 WITHOUT
  opening a debt, because a debt's relaunch could double-launch beside a window that arrives 9 min
  late (the incident's timing). `settle --recovery <missing file>` settles as a plain debt instead
  of exiting 2, which would break `rcy_debt_settle`.
- **U3, double delivery:** reso-resume-one exports `CC_RECYCLE_ATTACHED_TOKEN` when the prompt it
  submits carries the token, and the SessionStart child skips that token. The child is FIRST in
  CHILDREN, so the dispatcher's 9500-char cap never truncates the packet.
- **U3, resumers that bypass reso-resume-one** (the SessionStart child is their channel):
  boot-resume.sh goes through it (via boot-resume-launch, :190); cc-resume-layout.sh goes through it
  (:165); cc-pane spawns no resume; **lr_recon does NOT** (act.py:143 uses
  `handoff-fire --relaunch-at-shell`; lr-handoff.sh:1611 and lr-upgrade.sh:60 use lr-fire-resume.sh,
  which spawns `claude --resume` itself); handoff-fire's own resume-mode launcher does not either.
- **U2, §D2 item 5 reversed:** a trailing literal `ESC[201~` / `^[[201~` in the read-back now means NO
  CR, not "strip it and submit". zsh never renders a paste-end marker it consumed, so a VISIBLE marker
  means those bytes are in the line buffer and a CR would submit them onto the last argument. The
  attempt scrubs and the next one retypes (the final attempt is plain mode, which carries no markers).
- **U2, further refinements:**
  - Any non-zero send rc means delivery-unknown, not only 124, because it2-kitty collapses its own
    inner timeout to rc 1.
  - The echo-poll deadline is settle × (4 + 2 × load/core), capped at settle × 60.
  - The typing deadline never runs fewer than the old 2 rounds.
  - The suffix rule binds unfocused panes too.
  - The claim check also runs inside the shell-wait loop: a consumer can claim and start claude
    before the watcher ever samples the bare shell, and the watcher would otherwise call the pane
    dead after 600 s. Claims are epoch-floored at the watcher's start, so an older claim on a reused
    tty cannot count.
  - A total claim bound (`CC_RECYCLE_CLAIM_MAX_S`, 120 s, load-scaled) covers a pane that never
    settles at a shell.
  - The stage call sits just before `recycle_fire_commit`, after every abort arm.
  - Load scaling is ×min(4, 1 + load/core ÷ 10) on the engagement, boot and claim bounds.
  - **Residual:** a fresh recycle into a pane with no consumer (an old consumer inode) pays the 20 s
    grace before typing.
- **U2, typing deadline in tests:** suites whose mock screen never echoes now pin
  `CC_RECYCLE_TYPE_DEADLINE_S=0`, which keeps the old two rounds. Without it the 600 s default hangs
  them past bats' per-test bound.
- **U5a (review items 4, 6, 7, 9):**
  - `stage` removes an old `.cmd` first and binds the pair with a nonce, written to meta `.nonce` and
    as the `.cmd`'s last line (`# cc-pane-successor-nonce: <n>`). `take` claims only on a match. The
    real-artifact test is therefore "staged bytes plus exactly the nonce line", no longer
    byte-identical.
  - `take` refuses when `meta.pane` and `KITTY_WINDOW_ID` are both numeric and differ; the tty alone
    decides otherwise.
  - The per-generation zsh nesting is flattened. The consumer's `-c` program is now a LOOP that
    sources the claim, then any hand-back, so one loop shell serves every generation. A cc-close-attrib
    whose ancestor (within 3 hops) is that loop writes its claim to
    `<dir>/<key>.handback.<loop pid>` and exits, instead of exec'ing a nested shell. Measured: the
    3-generation depths were 3/4/5 before the fix and constant after.
  - The SessionStart child prints first and stamps second, and treats a tokenless packet as absent.
  - **Residual (accepted):** a stage swapped in during take's check-to-rename window is moved back,
    but a watcher revoke that lands inside that microsecond window would read it as claimed.
- **U5b (review ORDERING + items 1, 2, 3, 5, 8 + both PLAUSIBLE; all fixed, none refuted):**
  - **Deferring to a live watcher.** The sweep and `step` (not `settle`) defer without counting while
    `cc_pane_recycle_pending` reads the debt's pane as pending. `settle` is excluded because its caller
    is usually the watcher itself, the lock's own holder. The deferral is bounded at 1800 s
    (`RECYCLE_WAIT_S`), because the lib reads an unparseable lock holder as pending.
  - **Kitty socket.** The lock key includes the recycler's kitty socket, so `open` records
    `CC_TERM_KITTY_TO`/`KITTY_LISTEN_ON` for the launchd sweep, which has no kitty environment.
  - **Live original.** A recovery debt whose original is ALIVE is mailed its packet prompt once
    (`mailed_at`), then waits up to 600 s for the token-answered proof before escalating.
  - **Mailbox delivery shape.** Mail reaches a transcript as an `attachment` record
    (hook_additional_context), not a `user` record, measured on a live transcript. So the
    token-answered proof and reso-resume-one's delivered check accept attachment records too.
  - **Exactly-once attach.** reso-resume-one checks the transcript before attaching. `injected_at`
    counts as delivered; tokenless, unparseable or expired packets (TTL 7 d) are absent. The signal
    traps stamp too, and transcripts are parsed line by line (`fromjson? // empty`).
  - **Proofs.** A resume-mode debt is proven by the SAME sid LIVE in its pane. A re-fire proves via
    the packet's `refired_at` or a `recycle-engaged` row naming the sid after `failed_at`.
    `page_verdict` comes from cc-notify's stderr verdict, so `mailbox-only` is recorded honestly.
  - **Indeterminate launch.** boot-resume-launch exits **6**, distinct from 5. It persists
    `pending-launch/<sid>.json` and opens the debt, and the sweep reconciles by token (window found ⇒
    live; none after 900 s ⇒ normal relaunch). boot-resume.sh reports 6 as "launch indeterminate,
    reconciling".
  - **Deferral counting.** Time-based: MAX_DEFER deferrals whose first is ≥ 600 s old.
  - **Kitty restart.** `_successor_once` compares the registry row's `kitty_pid` with the one recorded
    at open when both are known, so a kitty restart's reused window id cannot falsely discharge.
- **U3:** `--next-to` is implemented in boot-resume-launch but not passed by cc-resume-debt, because
  the recorded pane is usually gone and kitty fails a launch whose `--next-to` matches nothing.

## Status log

- 2026-10-09: filed by 80734d02 after workflow `wf_462dbffc-a38`. The operator re-fired the stranded brief
  by hand from window 134 → pane 138 (engaged 15:46Z), so no live recovery is owed.
- 2026-10-09: COMPLETE. U1-U5 landed and live (final land `7c5256c54`), DoD items 1-4 met; see
  "Completion" under Phase 0.
