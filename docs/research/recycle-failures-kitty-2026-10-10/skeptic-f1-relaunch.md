# Skeptic verdicts: slot f1-relaunch (pane 44, 2026-10-09)

This is a read-only adversarial review of `slot-f1-relaunch.md`. I read the code at the live sha `bc471e0b6` from
`git show bc471e0b6:<path>` copies in `/tmp/skf1/`, and at HEAD `b68fa8a25`. Every number below is labelled
**measured** (with the command or file it came from) or **estimated** (with the method).

| Claim | Verdict | Adjusted conviction |
|---|---|---|
| 1. The relaunch write failed because it2→kitty round trips ran at or near the 10 s bound | **PLAUSIBLE** | 70 % (claimed 80 %) |
| 2. The alarm died at `refused-rc3`, the phone leg was inert, and the sweep self-bound until a single aggregate banner at 07:06Z | **CONFIRMED, with corrections** | 85 % (claimed 90 %) |

---

## Claim 1: "it2 relaunch write failed twice"

### What survives re-checking

- **No typed line was ever executed by the shell.**
  - Measured: `grep -a -c hfv-22463 ~/.zsh_history` → 0.
  - The researcher called history coverage that night "thin". It is not. Measured control: every watcher pid that logged
    `recycle-submitted`/`recycle-engaged` between 10-08 16:46Z and 10-09 23:25Z was checked against `~/.zsh_history`.
    27 of 29 have both nonce lines (disarm and launch). The 2 misses (pids 26907 and 47421) are keystroke-free
    `recycle-successor-claimed` rows ("nothing typed").
  - That includes pane 44's own previous relaunch: `hfv-19065-1-25151` and `hfv-19065-1-22428`, at history lines
    941-942. With `setopt SHARE_HISTORY` (`~/.zshrc:62`), the zero for 22463 is strong evidence, not weak evidence.
- **The bound inversion is real.**
  - The outer bound is `HF_TIMEOUT_S=10` (`scripts/handoff-fire.sh:1027@bc471e0b6`), applied as `timeout -k 3`
    (`:1080`).
  - Inside it, `bin/it2-kitty:95@bc471e0b6` allows 15 s per `kt` call. A send makes two such calls: `prove_target`
    (`kt ls --match`) and then `kt send-text` (`:1319-1321`).
- **The window length.**
  - Measured: `close-records/68284-1791493341.json` `ended_at` 04:55:52Z, and the `recycle-dead` row is at 05:03:21Z.
  - The resume-debt log was last written at **05:03:51Z** (`stat -f %Sm`, 00:03:51-0500). That is the
    `kitty launch failed` line.
- **kitty itself was badly backlogged. This is new, measured evidence, and stronger than the slot's.**
  - `kitty @ ls` gives window 134's root pid as 18273. `ps -o lstart -p 18273` → **Fri 9 Oct 00:12:38 CDT = 05:12:38Z**,
    with ppid 64211, the kitty instance that has been running since 10-05.
  - boot-resume-launch bounds its `kitty @ launch` at 20 s (`scripts/boot-resume-launch.sh:47,405@bc471e0b6`), so the
    request went out at about 05:03:31.
  - kitty therefore forked the window **about 9 min after the client gave up**.
  - No other launcher left a trace. There is no pane-spawns row for 134 on 10-09, and the IDL `boot-resume` rows at
    05:05:52 and 05:11:40 read `abstained already-processed`.
  - Once the fork happened, the chain inside the window was fast: zsh 05:12:38 → reso-resume-one 05:12:39 → expect and
    claude 05:12:41, at load_1m ≈154 on 10 cores. The 9-minute delay was therefore on kitty's side, not process-spawn
    starvation in the new window.

### What is wrong or overstated in the slot

1. **The predecessor was not a "fresh session started by a typed fresh relaunch"** (slot §b). It was a **cc-lr upgrade
   resume running under lr-fire-resume's expect.**
   - zsh history line 942: `… bash /Users/chrisren/.reso/limit-recover/upgrade/6defb493-20261008T210056Z/launch.sh`.
   - That `launch.sh` does `exec bash …/lr-fire-resume.sh … 6defb493…`.
   - Its `events.jsonl` has `"state":"relaunch-typed","stage":"expect","detail":"spawning claude-opus-5-5/high"` at
     21:02:20Z, one second before claude 68284 started at 21:02:21Z.
   - When claude exits, `lr-fire-resume.sh:1537-1558@bc471e0b6` restores stty and then runs
     `exec "${SHELL:-/bin/zsh}" -l -i`.
   - So the plan's statement that the relaunch was typed into a cold `zsh -l -i` is **correct**, and the slot's "doubtful"
     is refuted. (The slot's own `/tmp/f1scratch/wrapcheck.sh` even models the `[lr-fire-resume] session ended` banner.)
2. **The cold-zsh dismissal rests on that false premise and on a mislabelled measurement.**
   - "0.37-0.50 s at load 42.9" means a load average of 42.9 on 10 cores, i.e. 4.3/core, not the 45/core of F1.
   - A mechanism the slot did not consider does exist. With p10k instant prompt (`~/.zshrc:1-6`), the shell runs
     `stty -icanon` with echo still on while `.zshrc` loads
     (`~/.oh-my-zsh/custom/themes/powerlevel10k/internal/p10k.zsh:6474-6477`). In that state the kernel echoes `^U` and
     the paste markers literally.
   - Measured with `/tmp/skf1/echoctl-check.sh`, which reproduces the bc471 match at `:3700-3703`:
     - Under ZLE echo, both the 69-char and the 559-char wire pass **both** the substring and the suffix rule.
     - Under kernel `^U^[[200~…^[[201~` echo, the substring rule passes but the **focused suffix rule fails** for both
       lines.
   - The pane was plausibly focused: the operator typed his recycle request into this session at **04:53:22Z** (from the
     transcript).
   - HEAD names exactly this state `paste-end-echo` (`_hf_wire_is_tail` returns 3, `scripts/handoff-fire.sh@b68fa8a25`).
   - It cannot be the **sole** cause, though. A failed suffix match does not slow the calls down, and window 134's zsh
     reached its child within about 1 s at 15/core. So this explains early attempts at most, not the whole 6.5 min.
     It is a co-cause the slot ruled out for the wrong reason.
3. **"All 16 attempts failed echo-verify" is not established, and the call arithmetic is off.**
   - At `:3698`/`:3700@bc471e0b6`, a paste with rc≠0 does `continue` with **no read**. That attempt makes **2** bounded
     calls (^U and the paste), not the slot's 3. An attempt whose verify passed but whose CR send failed (`:3706`) makes 5.
   - Corrected range: 16 × 2-5 calls, plus 4 `hf_pane_focused`, plus 2 `pane_enumerated`, which is **38-86 calls**.
   - Estimated: about 365-426 s of the window falls inside the typing loop. That gives **≈5-11 s per call**. The 11 s end
     is "nearly every call timed out" (all paste-fail attempts: 16×20.6 s + 40 s + 6 s ≈ 376 s, which fits the window
     exactly).
   - So the arithmetic cannot tell apart:
     - (i) the calls timed out, so the failure *is* the transport; and
     - (ii) the calls completed in ≈5-6 s and the echo was absent or failed the suffix rule.
   - The per-attempt leg stays unobserved. That is why this is PLAUSIBLE, not CONFIRMED.
4. **The degradation was not uniform with load.**
   - At load_1m 453 (04:54:33, `capacity-alarm.jsonl`), the arm-time listing still answered `rc=0 in 1s` (watcher log
     line 3).
   - The two bgwork read-and-send exchanges at 04:55:41 and 04:55:51 also worked.
   - The failure began after ≈04:56, and its trigger is not identified. A kitty RC backlog amplified by timed-out
     requests is plausible but unmeasured.
5. **The pane-157 citation is not field evidence.** The slot uses the 10-09 21:12-21:14Z pane-157 rows to show "the
   fallback failing whenever the transport fails". That run was the plan's **forced-failure live proof**: "C, typing
   forced to fail (`HF_WATCHER_IT2` stub): pane 157 failed 16 typed attempts (`send_rc=1`)"
   (`docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md:79-84`). The rows confirm it:
   - `send_ms=7`-`11`, which is far too fast to reach kitty;
   - `load_per_core=2.49-3.03`;
   - `recycle-dead … deadline 0s`.

   The slot's estimate that HEAD's 600 s typed deadline would still fail under F1 conditions survives, but on the
   05:03:31→05:12:38 kitty lag measured above, not on pane 157.

**Conviction 70 %, PLAUSIBLE.** The disjunction "end-to-end it2 calls were slow or failing, with kitty-side lateness
measured" fits best. The decisive per-attempt link is inferred.

What would change it:
- a reproduction at above 40/core with `recycle-type-attempt` rows;
- any record of pane 44's focus state at 04:56-05:03Z;
- evidence of what triggered kitty's backlog.

---

## Claim 2: the alarm never reached the operator

### What survives re-checking (all measured)

- **The push went nowhere.**
  - `alarm-20261009T050321Z-22463-28344.json.verdict` = `refused-rc3`. On disk, 19 of 20 verdicts are `refused-rc3` and
    1 is `recorded`.
  - `~/.claude/cc-roles` contains `archive docs-lead drain-lead opus55-lead orchestrator`, with no `desk`.
  - `bin/cc-notify:938-946@bc471e0b6` handles the unset role: `role-unset` → `phone_fallback` → `exit 3`.
- **The phone leg ran and was inert.**
  - `~/.claude/autonomy/push-records/push-20261009T050321Z-30452-28161.json` → `"verdict": "inert", "detail": "creds unset"`.
    430 of 431 push records are inert.
  - `~/.config/lr-page/` is empty, and `launchctl getenv PUSHOVER_TOKEN` is empty.
- **The sweep never got to its ladder.**
  - In `idl.jsonl.20261009T191129Z.gz`, `autonomy-sweep` wrote 10 `self-bound` rows from 05:05:14 to 06:56:41
    (`elapsed_s` 404-893 against `bound_s` 400).
  - The first `fired` row is 07:06:39 with `bannered:26`. Its summary is `NEW: 368 page(s), 192 alarm(s) … 1 recycle-relaunch-failed`.
  - The tick at 04:45:16 had already self-bound, so the sweep was self-bounding before F1 too.
- **The record's relaunch command was corrupted.** The alarm detail ends `… '$(cat /var/folders/…/handoff-prompt-nb-9D2Ngh)'`,
  in single quotes. The watcher log's stderr copy (line 11) still has the correct `"$(cat …)"`.
- **The deploy time is as the slot says.** `77b525098` fast-forwarded at 2026-10-09T15:11:37-05:00 = 20:11:37Z. All
  three fixes are ancestors of it and none is in `d1ccc37f5`.

### Corrections

- **The sweep ladder was not "the only operator-facing consumer" at bc471.**
  - `hooks/operator-readout.sh:298-302,481-512@bc471e0b6` reads `handoff-alarms/*.json` into the Stop readout's
    `◆ N escalation record(s) unseen` line, which is rendered in the operator's terminal.
  - The IDL has **87** `operator-readout` `fired` rows between 05:03 and 16:00Z.
  - So the record *was* surfaced, but only as one unit in an aggregate count of hundreds. The failure is drowning in an
    undifferentiated count, not an absence of any consumer.
- **The operator was awake right before F1.**
  - His prompt asking for this recycle is at **04:53:22Z** (transcript line 872).
  - That is why the sweep's 2 h delay mattered: a per-record banner at 05:03Z had a real chance; 07:06Z (02:06 CDT) did
    not.
- **"Found about 8 h later" is not what the transcript shows.**
  - The operator's first message afterwards is at **15:44:04Z**: "Checking in, as it's been some hours now the morning
    after, and I don't see a pane to our side". That is 10 h 41 m after the alarm.
  - Meanwhile the session had been auto-resumed at 05:12:41Z in window 134. It sat idle with no prompt (transcript rows
    after 05:12:58 are attachments only).

**Conviction 85 %, CONFIRMED.** The mechanics are observed in records. "Never reached the operator" is inferred, and is
better stated as "reached him only as an aggregate count and a 02:06 banner".

---

## Objections to the proposed fixes

1. **Rank 1, a per-record page in `hf_alarm`.** This is the right direction. Measured: only 4 strand-class records on disk
   from 10-03 to 10-10, so page fatigue is low. Objections:
   - **(a) The page cannot carry the command.** `lr-page`'s OS leg caps text at **200 characters** and bounds osascript
     at 10 s (`scripts/limit-recover/lr-page.sh:16-19`). F1's relaunch line is 559 characters. Page a short handle, i.e.
     the recovery-packet path or the alarm id. The proposed test ("pages exactly once *with the command*") would push an
     implementer to bypass the cap or the ARGV-injection-safe path.
   - **(b) The page can itself time out.** At F1-level spawn latency (≈10 s per call) the 10 s osascript bound can cut
     the page and nothing retries it. Add a test where the OS leg fails, and assert the record says so and the sweep
     re-pages.
   - **(c) Ordering.** Issue the page *before* the 10 s cc-notify push and `rcy_debt_settle`.
   - **(d) Seam.** Tests must stub `LR_PAGE_OSASCRIPT_BIN` so the suite never posts real banners.
   - The test is not vacuous: HEAD `hf_alarm` makes no lr-page call, so it fails before the fix.
2. **Rank 2, run the ladder early.**
   - The proposed test self-bounds "at phase 0b", and it would pass with the rung placed **after** phase 0a. But phase
     0a alone overran in the post-F1 ticks: 05:05:14 at `elapsed_s` 893 and 05:17:08 at 413, both
     `stopped_before 0b-author-death-join`. The rung must run before 0a, and the test should make 0a itself overrun.
   - The banner is still aggregate and damped, so this fix does not deliver the command or the per-record signal.
3. **Rank 3, a zsh `precmd` consumer.** Safety is acceptable: `cc_pane_successor_take` checks the tty, then
   `KITTY_WINDOW_ID`, then the watcher lstart, then the TTL, and claims with an atomic `mv`
   (`lib/pane-successor.sh:119-166@b68fa8a25`). Objections:
   - **(a) Same deploy skew it is meant to cure.** The hook exists only in a zsh started after the rc change. A warm
     shell, or a wrapper process, that predates the change is not covered. So "never revoke-then-type" is overclaimed.
     F1's cold `zsh -l -i` would have had the hook.
   - **(b) Cost on every prompt in every pane.** `take` forks jq and ps. Gate it on a fork-free `[[ -e …/<tty>.cmd ]]`
     and assert in the test that nothing forks when nothing is staged.
   - **(c) Missing negative tests:** same tty with a different window id; a dead watcher; an expired TTL. Also test the
     operator's typeahead at the prompt, which would land in the launched claude's composer.
4. **Rank 4, "page until the token is answered."**
   - Nothing owns the re-paging, because the watcher exits right after the alarm. It needs damping and a cap.
   - It largely duplicates rank 1.
   - The test, with a stub page, proves the call, not that it reached anyone. With Pushover unwired, the token should
     say `posted`/`inert`, not `reached`.
   - "sid not live" needs a liveness seam that HEAD `hf_alarm` does not have.
5. **Gap in the fix set.**
   - A recycle is exempt from the capacity gate by design (`scripts/handoff-fire.sh:8303-8305,12636@bc471e0b6`). F1
     typed `/exit`, the point of no return, at about 45/core. No proposed fix gates or defers the `/exit` when the
     post-exit path will have to type.
   - Under-tested risk at HEAD (inferred): if kitty runs a timed-out CR late, *after* the watcher has given up, the
     typed successor and the `settle --recovery` re-fire could both start.

## Not re-run

`bats tests/handoff-alarm-records.bats` was refused by the local `cc-bats` load gate. Measured: rc 75, "2 concurrent bats
execution root(s) … load/core at or above 2.0". The slot's `1..20 all ok` is not independently re-measured here.

## Scratch

- `/tmp/skf1/echoctl-check.sh`: bc471 match under ZLE versus kernel ECHOCTL echo.
- `/tmp/skf1/*-bc471*`: live-sha copies of the code.
