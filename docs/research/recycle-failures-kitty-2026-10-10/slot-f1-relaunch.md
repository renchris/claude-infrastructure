# Slot F1 — pane 44 (2026-10-09): why the relaunch write failed twice, and why the alarm reached nobody

Read-only research. Code read at the sha that was live at the failure (`bc471e0b6`, extracted with
`git show bc471e0b6:<path>` into /tmp) and at HEAD (`b68fa8a25`). Every number is labelled
**measured** (with the command or file it came from) or **estimated** (with the method).

## 0. Corrections to the brief (measured)

- **Live-sha timeline.** The shared checkout's reflog (`git -C ~/Development/claude-infrastructure reflog --date=iso-strict`) shows
  `bc471e0b6` live from 2026-10-08T20:58:36-05:00 (01:58Z) to `f1a62145d` at 2026-10-09T00:26:26-05:00 (05:26Z).
  So F1 (04:55–05:03Z) ran on bc471e0b6, as the brief says.
- **The post-F1 fixes went live later than the brief says.** c54a3c0bd, f4b297310 and 3578b0e19 are first reachable from
  `77b525098`, fast-forwarded at **2026-10-09T15:11:37-05:00 = 20:11:37Z** (`git merge-base --is-ancestor` against each reflog entry:
  d1ccc37f5 is n/n/n, 77b525098 is y/y/y). The brief's "13:34–14:38Z" is the commits' **-0500 author time**, not UTC, and not the
  deploy time. The conclusion that they all came after F1 still holds.
- **When claude exited.** `~/.claude/logs/close-records/68284-1791493341.json`: `"started_at":"2026-10-08T21:02:21Z","ended_at":"2026-10-09T04:55:52Z","exit_code":0`.
  The typing window was therefore 04:55:52 → 05:03:21 at most, which is **449 s**.

## (a) The mechanism of "it2 relaunch write failed twice" at bc471e0b6

### The path, step by step (bc471e0b6)

1. The watcher confirms a shell. `pane_cc_state` (scripts/handoff-fire.sh:5638@bc471e0b6) checks the process tree and the
   foreground pgrp. It does not look at the screen. Log line: `→ pane 44 CONFIRMED at a shell prompt after 30s — typing relaunch`
   (watcher log line 7). The "30s" is the loop's own counter, not wall time: the `bgwork@15s` row is stamped 04:55:41 and the
   `@18s` row 04:55:51, which is 10 s of wall time for 3 counter-seconds (handoffs.jsonl, target_pane 44).
2. `sleep 2`, then `pane_enumerated` (one `it2 session list`). The launch lock is skipped because this was a fresh recycle.
3. `for _ in 1 2; do it2_type_verified …; sleep 3; done` (scripts/handoff-fire.sh:10065-10068@bc471e0b6).
4. `it2_type_verified` (:3714-3723) first runs `_it2_type_line` on the disarm line
   `unsetopt correct correct_all 2>/dev/null || true` (:3654), then on the launch line. When the disarm fails it prints the
   `⚠ could not disarm zsh spell-correction` line, which is the line that appears twice in the log.
5. `_it2_type_line` (:3677-3712) runs `FIRE_TYPE_ATTEMPTS=4` attempts. Each attempt does the following:
   - Every it2 call is `hf_bounded`, i.e. `timeout -k 3 10` (HF_TIMEOUT_S=10, :1027, :1054, :1080).
   - Send `^U`, then `sleep 0.12`.
   - Send the bracketed paste `ESC[200~: hfv-<pid>-<n>-<rand>; <line>ESC[201~`. A non-zero rc does `sleep 0.5; continue` with
     no read.
   - `sleep 0.5`, then **one** read: `it2 session read -n 500`.
   - Strip whitespace and grep the nonce wire. A focused pane needs it as a suffix.
   - On a match, send CR. Otherwise send `^U` and `sleep 0.5`.
   - The fourth attempt sends plain text instead of a paste.
   - Total: 2 rounds × 2 lines × 4 attempts = **16 attempts, every one an echo-verify failure**.
6. In `bin/it2-kitty@bc471e0b6` (unchanged through HEAD: `git log bc471e0b6..b68fa8a25 -- bin/it2-kitty bin/it2-wrapper` is empty):
   - **send** (:1311-1323) = `armed` check, then `prove_target` → `pane_exists` → `kt ls --match id:44` plus python3 (:429-455),
     then `kt send-text`. That is two kitty RC round trips. Each one is bounded **inside** it2-kitty at
     `IT2_KITTY_TIMEOUT_S=15` (:95, :207-211), and both sit under handoff-fire's **outer 10 s** bound. The inner bound is larger
     than the outer one.
   - **read -n 500** (:1478-1490) = `kt get-text --extent all | tail -n 500`, which reads the whole scrollback.

### What failed, measured

- **No CR was ever sent.** Every typed line carries its nonce, and a submitted line lands in zsh history. `grep -a -c "hfv-22463" ~/.zsh_history` → **0**.
  Lines from other recycles do appear there (e.g. `: hfv-13305-1-8756; unsetopt correct …`). Caveat: history coverage for that
  night is thin, so this supports the conclusion but does not prove it alone.
- **Width and wrapping are ruled out.**
  - The 69-char disarm wire failed all 8 of its attempts, exactly like the 559-char launch wire.
  - A scratch reproduction of the match logic (/tmp/f1scratch/wrapcheck.sh) folds the wire at 30/37/45/57/115 columns under a
    prompt. It gives `substring_match=1 suffix_match=1` for both lines at every width (measured). `tr -d '[:space:]'` erases
    soft-wrap newlines.
  - zsh has no right prompt that could break the focused-suffix rule: `~/.p10k-robbyrussell.zsh:27 POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=()`.
  - Pane 44's geometry at the time is **not recorded** anywhere I searched. pane-spawns.jsonl rows carry no columns, and window 44
    no longer exists in `kitty @ ls`. It does not matter, given the above.
- **Spell-correction is ruled out.** `unsetopt` and `:` are builtins and cannot be corrected. The disarm failing is a symptom of
  the same transport problem, not a separate cause.
- **The duration shows the it2 transport was slow, so a late echo alone cannot explain it.** Estimated by arithmetic on the bc471 code:
  - 16 attempts make 48–64 bounded it2 calls (3 per attempt when the paste rc≠0, 4 when it is 0). Add 4 `hf_pane_focused`
    (`kt ls`, bounded 10 s, :1451) and 2 `pane_enumerated`. That gives **54–70 bounded calls**.
  - Fixed sleeps: 16 × 0.62–1.12 s, plus 2 s and 3 s, which is about 15–23 s.
  - The rest of the 449 s spread over those calls gives an **average of about 6.1–8.0 s per it2 call** against a 10 s bound.
  - For comparison: the same `it2 session read` takes **0.17–0.24 s now at load ~4.2/core** (measured, `/usr/bin/time -p ~/.claude/bin/it2 session read -s 134 -n 5` ×3),
    and the arm-time listing took `rc=0 in 1s` (watcher log line 3).
  - If the transport had been fast and only the echo late (the plan's candidate ii), 16 attempts would have taken about
    16 × (4 × ~1 s + 1.1 s) ≈ 80–100 s, not 449 s.
  - So a large share of the calls ran near or at the 10 s bound, from kitty RC servicing, from the watcher's own process spawns
    starving at that load, or both. I cannot separate those two: there was no per-attempt telemetry at bc471.
- **The final listing failed.** `recycle-dead … (pane unknown after the failed writes)` (handoffs.jsonl 05:03:21Z). `pane_enumerated`
  returns `unknown` only when `session list` failed, timed out or came back empty. So at ~05:03:1x kitty did not answer a listing
  within 10 s that had answered within 1 s at 04:55.
- **Load and contention** (`~/.claude/logs/capacity-alarm.jsonl`): load_1m 453.67 at 04:54:33, 445.05 at 04:57:59, 433.63 at 05:00:21,
  422.21 at 05:02:48, on 10 cores (**42–45 runnable/core**). `top_procs` were Blender 17–18 GB and qemu 7.6 GB, and the kitty
  coalition held 347–542 processes. The capacity sampler itself slipped from 1-minute to 2–3-minute spacing (04:51:45 → 04:54:33 → 04:57:59).
- **kitty was intermittent, not dead.**
  - A `kitty @ launch` split for pane 133 completed at 05:00:00Z (pane-spawns.jsonl; it2-kitty writes that row only after a
    successful `kt launch`, :1231-1236).
  - boot-resume-launch logged `kitty launch failed for 6defb493…` (`~/.claude/autonomy/resume-debt/log/6defb493….log`), yet window
    134's claude started at 05:12:41Z (`close-records/19890-1791522761.json`). kitty therefore executed a "failed" request late.
- **The cold zsh is not enough to explain it** (estimated). `zsh -l -i -c exit` takes 0.37–0.50 s now (measured ×3 at load 42.9).
  Even ~10× slower at 45/core is seconds, not the 7.5 minutes over which round 2 also failed.

### The 8-minute gap, 04:55:51 → 05:03:21

- About 30 s: CC's exit (04:55:52) and the shell-confirm loop.
- Then the two-round, 16-attempt typing loop. Its wall time is set by the 54–70 bounded it2 calls averaging 6–8 s each (see above).
- Then the final `pane_enumerated` and `hf_alarm` at 05:03:21.

There is no separate stall. The gap is the bound × attempt-count product under a degraded transport.

**Conviction 80%** that the dominant cause was it2→kitty round trips running at or near the 10 s bound at load ~45/core:
kitty-side lateness, watcher-side spawn starvation, or both. In that state, pastes, ^U and reads timed out or landed after the
single 0.5 s read. A slow echo in a healthy transport is refuted as the *sole* cause. Which leg failed per attempt remains
undetermined. **What would change this:** per-attempt `recycle-type-attempt` rows from a reproduction at load above 40/core
(available since f4b297310). If they showed send_ms < 1 s with nonce_seen=0, candidate (ii) would be back in play.

## (b) Does RECYCLE_KEYSTROKELESS_DELIVERY.md already state F1's root cause?

**Mostly yes, and honestly hedged. Verified against the code, with two corrections.**

- **Verified true.**
  - 16 attempts = 2×2×4 (:10065, :3681 `FIRE_TYPE_ATTEMPTS:-4`).
  - The outer 10 s bound is below it2-kitty's 15 s per call, and a send is two kitty calls (:1027@bc471; it2-kitty:95, :1320-1321).
  - rc≠0 on the paste causes `continue` with no read, and the next attempt opens with ^U (:3693-3698@bc471).
  - The alarm detail was corrupted by `tr '\n\r\t"' "   '"`. The live record shows `'$(cat /var/folders/…/handoff-prompt-nb-9D2Ngh)'`
    in single quotes (`~/.claude/handoff-alarms/alarm-20261009T050321Z-22463-28344.json`), so the manual command in the alarm
    would pass the literal text `$(cat …)` as the prompt.
  - The role `desk` does not exist (`ls ~/.claude/cc-roles/` → docs-lead, drain-lead, opus55-lead, orchestrator, archive).
  - Load ~45/core.
- **Sharpened.** The plan's "NOT DETERMINED (i)/(ii)/(iii)" can be narrowed. The 449 s duration excludes (ii) on its own (section (a)).
  It is (i) or (iii).
- **Not verified, and doubtful.** The plan says "`lr-fire-resume.sh:1558` then exec'd a cold `zsh -l -i`". Session 6defb493 was a
  **fresh** session started at 21:02:21Z by a **typed** fresh relaunch (`recycle-submitted … 21:02:33Z`, handoffs.jsonl pane 44).
  lr-fire-resume's expect always spawns `--resume $sid` (lr-fire-resume.sh:1118-1120@bc471e0b6). So claude 68284 (ppid 68224, the
  cc-close-attrib wrapper) most plausibly returned to the zsh that ran that typed line, which was already warm. The argv in
  close-records is scrubbed (1505/1508 records read `--permission-mode auto`), so I could not settle this. It does not change
  the conclusion, because the cold-zsh startup was not the bottleneck either way.
- **Not covered by the plan: the sweep self-bound.** The plan's awareness-gap list (§Root cause 1–7) does not name the leg that
  actually delayed the only operator-facing signal (section (d)).

## (c) Would HEAD (b68fa8a25) prevent F1?

**Only via the claim path, and only if a current consumer holds the pane. The typed path is still reachable and is still
F1-vulnerable.**

- F1 was a fresh recycle, so HEAD stages: `hf_succ_stage` (scripts/handoff-fire.sh:3919@HEAD), called at :17994.
- If a consumer claims the stage, the watcher sets `ok=1` with **zero keystrokes** (:10878-10960). The consumers are:
  - `_cca_take_successor` in bin/cc-close-attrib:579@HEAD;
  - lr-fire-resume.sh:1593-1610;
  - reso-resume-one:992-1012.
  The successor then launches by a local rename plus exec, with no kitty RC call, so F1's failed leg is bypassed entirely.
- **Typing is still reached when any of these holds:**
  1. **Mode is not fresh** (resume, transplant or remote). These never stage (`hf_succ_mode`, :3910-3916@HEAD).
  2. **Staging is refused**: `CC_PANE_SUCCESSOR=off`, no lib, no config dir for the launcher, unreadable watcher lstart, or a
     failed write.
  3. **Nobody claims within `CC_RECYCLE_CLAIM_GRACE_S`=20 s at a bare shell, or `CLAIM_MAX`=120 s load-scaled.** This happens when
     the process that regains the tty is not one of the three consumers, or is an instance started before the consumer code went
     live (bash runs the code it started with), or its tty differs (the expect inner pty), or the TTL has expired. Then it
     **revokes and types**.
- **How often** (measured, handoffs.jsonl since 10-09T20:49Z): **12 staged, 5 claimed, 4 revoked → typed, 3 undecided (F2/F3-era holds)**.
  - Revoked: pane 8 @23:26Z 10-09, 7 @02:56Z, 4 @08:26Z, 3 @12:18Z.
  - Panes 8 and 7 were revoked on their *first* post-deploy recycle and claimed on the next one. That fits a consumer process that
    predates the deploy.
  - F1's own predecessor was launched 10-08 21:02Z, before the deploy. Under HEAD it would have been **revoked and typed**.
- **Under F1 conditions, the HEAD typed fallback probably still fails** (estimated).
  - HEAD has: a 40 s send bound (:1067), read-before-scrub, an echo poll capped at 30 s, and a 600 s deadline loop (:10957).
  - A deadline starting around 04:56:30 ends around 05:06:30. kitty was still executing requests late until about 05:12:38. The
    10-09 21:12–21:13Z attempts by pane 157 (`send_rc=1 … echo-unverified`) show the fallback failing whenever the transport fails.
  - **What HEAD changes is the aftermath:** `rcy_recovery_packet`, `rcy_pane_paint` (a local tty printf, :10141, :10980), and
    `cc-resume-debt settle --recovery`, which resumes the original with the packet's `.prompt.md` and requires the token to be
    answered (bin/cc-resume-debt:12-15, :192-215).
  - **Residual:** that recovery resume itself needs `kitty @ launch` (boot-resume-launch), which is the very component that failed
    at 05:03:51.

**Conviction 85%** that HEAD prevents F1 only when the claim path runs, and that the typed fallback stays F1-vulnerable.

## (d) "push=refused-rc3": where the alarm went, and what pages the operator now

**At bc471e0b6.**

- `hf_alarm` (scripts/handoff-fire.sh:7903-7950@bc471e0b6) writes the record first, then pushes
  `hf_bounded cc-notify --role desk` (:7933) and records `refused-rc$_rc` (:7944).
- **rc 3 = cc-notify's `role-unset`.** `role_uuid desk` fails because there is no `~/.claude/cc-roles/desk`, giving
  `verdict unresolvable reason=role-unset … exit 3` (bin/cc-notify:938-946@bc471e0b6).
- Its `phone_fallback` (:944) then calls push-send, which is **inert**:
  - `~/.config/lr-page/` is empty and PUSHOVER_* is unset in this environment (measured; the plan measured 487/488 push records inert).
  - `~/.claude/autonomy/pages/notify-phone/desk-role-unset.stamp` shows that leg has been firing and damping.
  - The stderr that would say `fallback=phone-unwired` is folded into `_out` and discarded. Only the token survives.
- **Where it went** (measured):
  - The record is `~/.claude/handoff-alarms/alarm-20261009T050321Z-22463-28344.json` with `.verdict` = `refused-rc3`.
  - **19 of the 20** alarm verdicts on disk are `refused-rc3` (`cat *.verdict | sort | uniq -c`).
- **Why nobody saw it.** The only operator-facing consumer is `scripts/autonomy-sweep.sh` `ladder_v2` (:2432@bc471e0b6), which
  runs at the **end** of a sweep tick.
  - Every tick from 05:05:14Z to 06:56:41Z (**10 consecutive**) wrote `disposition:"self-bound"`, stopping at phases
    `0b`/`1`/`2`/`2b` with `elapsed_s` 404–893 against `bound_s` 400 (`gzcat ~/.claude/autonomy/idl.jsonl.20261009T191129Z.gz`,
    tool=autonomy-sweep). None of them reached the ladder.
  - The first ladder run was **07:06:39Z (02:06 local, CDT)**: one notification-center banner, `bannered:26`. Its summary was
    `NEW: 368 page(s), 192 alarm(s), 192 push-failed, 65 open decision(s), 34 handoff-alarm(s) (… 1 recycle-relaunch-failed …)`.
    It was aggregate, carried no command, and arrived at 2 am.
  - `.bannered` then damped every later banner for that record (`mark_surfaced_bannered` :2349). The marker's mtime (10-10 08:24
    local) is the last re-touch, not the first banner. Inferred: no ladder run occurred between 05:03Z and 07:06Z, so the first
    banner covering the record was 07:06:39Z.
  - The phone rung inside r2 is gated on credentials that do not exist (:2472).
  - Separately, the session was resumed in window 134 with no prompt (plan §Root cause 4), so the session itself was never told
    either.
- **Did 3578b0e19 fix the addressing?**
  - **Partly.** At HEAD, `hf_alarm` builds the record with jq: the `"$(cat …)"` text survives, as shown by
    `bats tests/handoff-alarm-records.bats` → **1..20, all ok** (measured; test 12 replays the pane-44 line). When the desk role is
    absent and a sid is known, it addresses `sid:<sid>` (:8450-8451@HEAD; test 13).
  - For a relaunch-failed alarm that sid is **the predecessor that just exited**, so the push is a **mailbox-only enqueue to a dead
    session** (token `recorded`, not `reached`). A human reads it only if the session is resumed and takes a turn.
  - The never-confirmed arm deliberately keeps `role:desk` (`HF_ALARM_SID_FALLBACK=0`, :10770). That is why the HEAD-era pane-168
    alarm (10-10T04:36:45Z) still reads `role:desk … refused-rc3`.
- **What would page the operator now, at HEAD:**
  - **Nothing reaches his phone.** Pushover is unwired, and the sweep's phone rung and cc-notify's fallback are both inert.
  - **Push surfaces:**
    1. the sweep's aggregate OS banner, still behind the self-bound;
    2. the pane paint: a banner printed to the pane's own tty, robust under load but visible only if he looks at that pane;
    3. operator-readout's counted `◆` line at any session's Stop;
    4. after `_escalate`, a `needs-human` backlog row plus a mail to the dead sid (bin/cc-resume-debt:605-645@HEAD).
  - **Self-heal path:** the recovery resume carries the failure prompt and refire command into the original session. That is the
    main improvement, and it still depends on a kitty launch.

**Conviction 90%** on the delivery chain: rc3 = role unset, phone inert, sweep self-bound until 07:06Z, then one damped aggregate
banner. **What would change it:** evidence that the operator had another channel watching handoff-alarms (none found:
`git grep handoff-alarms bc471e0b6` lists only autonomy-sweep, cc-escalations, operator-readout, docs and tests).

## Suggested fixes (ranked)

1. **Give post-/exit strand classes a direct, per-record, liveness-free page.** Classes: recycle-relaunch-failed, recycle-dead,
   surface-gone. hf_alarm should call `lr-page`/`osascript` itself with the one-line command, rather than relying on the sweep's
   end-of-tick aggregate. Wiring Pushover creds is the operator's step.
   - Where: scripts/handoff-fire.sh `hf_alarm` (~:8440-8500@HEAD).
   - Test: a bats case with a stub `CC_SWEEP_LR_PAGE_BIN`/osascript seam asserts exactly one page per strand-class record and none
     for other classes.
2. **Run the sweep's notify ladder (or a strand-only rung) before the expensive phases**, so a self-bounding tick still banners.
   - Where: scripts/autonomy-sweep.sh, phase order around `sweep_yield` (:422) and `ladder_v2` (:2432@bc471, same at HEAD).
   - Test: force `CC_SWEEP_BOUND_S` to self-bound at phase `0b`, seed one new `recycle-relaunch-failed` record, and assert an
     `os-banner` IDL row with `bannered>=1`.
3. **Make the consumer universal for interactive panes**, so a revoke-then-type happens only for non-fresh modes. Use a zsh
   `precmd` hook (kitty-setup rc block) that calls `cc_pane_successor_take` on its own tty. The measured revokes (4/9) were all
   panes whose consumer predated the deploy.
   - Where: lib/pane-successor.sh plus the scripts/kitty-setup.sh rc block.
   - Test: an interactive `zsh -i` in a pty with a staged successor claims within one prompt cycle and leaves no
     `recycle-successor-revoked`.
4. **Address relaunch-failed alarms to something with a reader.** A dead predecessor's mailbox is `recorded`, not `reached`. Route
   to the recovery packet's resume and, until that is proven, to rung 1.
   - Where: hf_alarm callers at :10981-10983@HEAD.
   - Test: extend tests/handoff-alarm-records.bats so that a relaunch-failed alarm with a dead sid yields an operator page and not
     only a mailbox enqueue.

## Evidence index

- Watcher log: /Users/chrisren/Development/.worktrees/wt-pool-7/.claude-plans/recycle-failures-2026-10-10/logs/handoff-recycle-44-1791521709-n5ZjZP.log
- Alarm: ~/.claude/handoff-alarms/alarm-20261009T050321Z-22463-28344.json (+ `.verdict` = refused-rc3); sweep marker ~/.claude/autonomy/sweep-seen/alarm-20261009T050321Z-22463-28344.json.bannered
- Sweep IDL: ~/.claude/autonomy/idl.jsonl.20261009T191129Z.gz (rows 05:05:14Z–07:06:39Z)
- Load: ~/.claude/logs/capacity-alarm.jsonl (04:51:45–05:08:09Z)
- Exit time: ~/.claude/logs/close-records/68284-1791493341.json; window 134 start: close-records/19890-1791522761.json
- Resume debt: ~/.claude/autonomy/resume-debt/log/6defb493-e229-4318-b0ab-86e7167c39e3.log (`kitty launch failed`)
- Scratch width check: /tmp/f1scratch/wrapcheck.sh
- Successor stats: `grep recycle-successor- ~/.claude/logs/handoffs.jsonl`
