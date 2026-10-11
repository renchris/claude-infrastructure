# Slot Q5: the safest primitive for an in-place recycle on kitty

Read-only survey. Nothing was typed, sent, signalled or closed. The only actions on live state were
reads: `kitty @ ls`, `kitty @ get-text` on pane 134 (the same call `it2 session read` makes), `ps`,
and a read-only `mmap` scan of the live Claude Code binary.

## Verdict

**Recommend (b): end the predecessor by sending SIGTERM to the exact `claude` pid**, pinned by
pid and lstart, found through `pane_cc_state`'s process-tree closure. Send it only after the
transcript is proven at rest, the background-work census passes, and the keystroke-free successor
is staged. Write a recycle teardown marker immediately before the signal. Keep the composer read as
a draft guard only; it is no longer an actuator. Keep (a)'s staged successor (c54a3c0bd) unchanged
as the relaunch half.

**Conviction: 75%.** What would move it:

- **Up, to about 90%:** one scratch-pane proof on 2.1.293 that SIGTERM at rest leaves the
  transcript intact, gets the successor claimed by the pane consumer, stops the background shell,
  and is not classified CRASH once the marker exists.
- **Down:** if CC's SIGTERM path is shown to skip something the `/exit` path does, for example
  the bg exit-handoff to `adopt.json`, or if the operator rules that an unreadable composer must
  still block a recycle. In that case (b) still removes F2 and F4, but F3-shaped holds remain.

The lead's hypothesis (F4's draft is F2's own `/exit`, never removed) is **supported** by the code
at the live sha and by a replication on two more panes (§3). Q5 does not depend on it, though:
(b) removes the keystroke that creates that residue, whatever the parse bug behind it.

---

## 1. What failed, by leg (the surface the primitive must shrink)

| F | live sha | failing leg | evidence |
|---|---|---|---|
| F1 | bc471e0b6 | typed relaunch into a cold shell (16 attempts) | log `handoff-recycle-44-…n5ZjZP.log`: "CONFIRMED at a shell prompt after 30s — typing relaunch", 2× "could not disarm zsh spell-correction", "it2 relaunch write failed twice". bc471e0b6 has no successor stage (`grep -c cc_pane_successor_stage` = 0, measured). |
| F2 | e667558fc | typed `/exit` + composer read-back | `recycle-successor-staged` 00:25:42Z, then `recycle-held-exit-readback` "'<unreadable>'" 00:25:47Z. At e667558fc, `hf_exit_readback` (`/tmp/hf-e667.sh:3316-3335` = `git show e667558fc:scripts/handoff-fire.sh`) sends DELs only on `*/exit`. An unreadable read sends nothing and writes no receipt (`grep -c 'composer_residue_record "$id" "/exit"'` = 0, measured), so the typed `/exit` stays in the box. |
| F3 | 1b2b93357 (= e667558fc for handoff-fire) | composer gate cannot read the box | defer log: "composer could not be READ … for 180s". The box still held F2's `/exit` with the slash menu open, the shape 0584f0720 fixed at 01:48Z. |
| F4 | b68fa8a25 | composer gate reads F2's residue as a foreign draft | `recycle-held-draft` 02:23:36Z "over '/exit'". No receipt exists for 134, so HEAD's own-residue arm (`scripts/handoff-fire.sh:17572-17608`, `composer_residue_is_ours`) cannot claim it. |

F2, F3 and F4 are all failures of one actuator: **keystrokes into, and reads of, the CC
composer**. The successor never had a chance in F2-F4, because claude never exited.

## 2. Measured base rates (live event store)

From `jq` over `~/.claude/logs/handoffs.jsonl` (retained window 2026-10-07T05:26Z →
2026-10-11T02:26Z; measured):

- `recycle-intent` 81 · `recycle-engaged` 49.
- Composer-surface holds:
  - `recycle-held-exit-readback` 9: 8 `'<unreadable>'` and 1 `''`.
  - `recycle-held-unreachable` 12: 7 are "composer UNREADABLE" and 5 are "kitty did not answer
    the up-front probe".
  - `recycle-held-draft` 3: two of them are "over '/exit'".
  - `recycle-nudge-held` 6.
- `recycle-dead` 4:
  - 2 "never reached a confirmed shell in 600s (verdict: cc)": the `/exit` did not take.
  - 2 "relaunch write failed": F1, and live-proof C on pane 157, which was forced to fail by design.
- Successor leg since c54a3c0bd: 12 staged. Of those whose claude exited: 5 claimed, nothing typed
  (154, 158, 8, 8, 7), and 4 revoked to the typed fallback (8, 7, 4, 3), all of which then
  engaged. The 3 stages on 10-11 (134, 206, 2) never reached the claim, because each held at the
  `/exit` read-back.

**The F2 → F3/F4 chain replicates on two other panes in the same hour (measured, same store):**

- Pane 206: `successor-staged` 01:23:54Z → `held-exit-readback '<unreadable>'` 01:24:00Z →
  `deferred-turn` 01:24:45Z → `turn-ended` 01:25:03Z → `held-unreachable` 01:28:06Z. Same shape
  as F2 → F3.
- Pane 2: `successor-staged` 01:28:15Z → `held-exit-readback '<unreadable>'` 01:28:24Z →
  `held-draft … over '/exit'` 02:26:12Z. Same shape as F2 → F4, and it held under HEAD code
  (0584f0720 was live from 01:48Z).

So since c54a3c0bd landed, the dominant failure is the `/exit` leg, not the relaunch leg. A
primitive that removes typing into the composer removes this whole class.

## 3. The candidates

### (a) Today: type `/exit`, read it back, CR; staged keystroke-free successor

- **Removes:** the typed relaunch, when the consumer claims (5/9 since landing, measured above).
  Delivery becomes a local `mv` (`lib/pane-successor.sh`). Consumers in use:
  - `bin/reso-resume-one:997-1016` (pane 134's launcher);
  - `scripts/limit-recover/lr-fire-resume.sh:1595-1611`;
  - `bin/cc-close-attrib:579-603`.
  All three take the stage whatever claude's exit code is.
- **Keeps:**
  - Every composer actuator: `/exit` (`hf_exit_readback`, HEAD `scripts/handoff-fire.sh:3316-3340`).
  - The background-work dialog keys (Esc, then `'1'`, as in F1).
  - The five-DEL undo.
  - The CR nudge.
  - The composer gate's 180 s proven-empty wait.
  - The typed fallback after the 20 s claim grace.
- **The undo cannot work when it is needed.** Taking `/exit` back out depends on the same read
  that just failed, so an unreadable read strands the residue (e667558fc). HEAD now writes a
  receipt in that case (`scripts/handoff-fire.sh:3330-3338`). But the scrub that consumes the
  receipt, `composer_scrub_verified` (HEAD :4678), returns rc 2 "unknown box (nothing sent)" on an
  unreadable box. **This is an inference from its signature, not measured:** the next attempt
  holds whenever the box stays unreadable.
- **Also note:** a typed `/exit` when the read-back passes is still a kitty RPC, and kitty has
  executed a timed-out RPC about 9 minutes late (`docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md`,
  Root cause, MEASURED).

### (b) Non-typing exit: signal the claude process — RECOMMENDED

**What CC does on each signal. Measured on the live binary, 2.1.293**
(`~/.claude-293/…/bin/claude.exe`, 236,330,608 B), with a read-only Python `mmap` scan at byte
offset 192,234,286:

```
process.on("SIGINT",  …{…qJ(),this.shutdown(0)})      // skipped only if printModeSignalHandlersRegistered
process.on("SIGTERM", …{te("info","shutdown_signal",{signal:"SIGTERM",uptime_s,ppid_changed,…}),
                         i("tengu_shutdown_signal",…),qJ(),…;this.shutdown(143)})
process.on("SIGHUP",  …this.shutdown(129))             // ignored under CLAUDE_BG_BACKEND=daemon unless it owns the ctty
```

`shutdown(e)`, at offset 192,241,011 + ~1.2 KB, does the following in order:

1. sets `shutdownInProgress` and `process.exitCode=e`;
2. arms a failsafe of `max(5000, sessionEndTimeout+5000)`;
3. prints the resume hint;
4. races the cleanup-registry drain;
5. runs `executeSessionEndHooks` and the flushes, then `forceExit(e)`.

Every graceful path runs this one function. `docs/research/team-inplace-upgrade-2026-09-23/q1-lead-exit.md:60-84`
traced it on 2.1.280 and its §6 table (:184) lists `kill -TERM/-INT/-HUP <lead pid>` as:

- **no modal**;
- **background tasks killed**, the same as `/exit` → "Exit and stop tasks";
- **transcript flushed, SessionEnd hooks run**.

Other handlers registered for these signals are for lock release, the runner, the daemon and tail,
not for the interactive TUI. That is measured: 12 `process.on("SIGINT"` sites, each read in
context.

**Field evidence that it behaves this way:**

- `docs/research/session-sigterm-forensics-2026-08-09.md:36-38`: a SIGTERM'd session ran
  SessionEnd and printed the ordinary resume banner, "byte-identical" to `/exit`.
- `docs/research/teammate-teardown-verdict-2026-10-10/01-arm-mechanics.md:119-132`: `kill -TERM`
  at load ≈221 produced the exit flush (cost-state and last-prompt records) 88 s later. SessionEnd
  was absent there. Under load that is the same `shutdown()` the `/exit` path relies on, so it is
  not a difference between the two.
- `docs/research/kitty-quit-research-2026-10-01.md:105`: a pane close (SIGHUP) leaves the
  transcript intact apart from the in-flight turn.

**Precedent in this repo:** `bin/cc-teardown:889-902` already does `write_teardown_marker` →
`kill -TERM <pid>` → poll → KILL, with an lstart pin (`pid_lstart`, :289). handoff-fire itself has
no signal-based exit today: `grep kill -TERM|signal-child` in `scripts/handoff-fire.sh` returns 0
hits (measured).

**What (b) removes from F1-F4:**

- the typed `/exit` and its read-back (F2);
- the DEL undo and the residue (F2 → F4);
- the background-work dialog keys (F1's Esc and `'1'`);
- the CR nudge;
- the 180 s proven-empty wait as an actuator precondition. F3 arose only from F2's residue: every
  "composer UNREADABLE" hold on 10-11 (168, 206, 134) follows an earlier `exit-readback`
  failure on the same pane.

It also removes kitty-RPC latency from the exit: `kill(2)` is a local syscall, so a 15 s kitty
bound and 9-minute late execution do not apply.

**What (b) adds, each with an existing mitigation:**

1. **Target the claude pid, never the pane.**
   - `kitty @ signal-child` signals `max(pids in tcgetpgrp(pty))`. That is kitty's
     `child.py:get_pid_for_cwd` → `window.py:signal_child` (`os.kill(pid, sig)`), read from
     kitty master via curl.
   - On pane 134 that group is `{18794 bash reso-resume-one, 19771 expect}`. Claude (19890) sits
     on the expect inner pty ttys035. Measured with `ps -o pid,ppid,pgid,tpgid,tty`.
   - So `signal-child` would kill **expect**, not claude. Under a cc-close-attrib launch the group
     is `{bash, claude, bash, tee}` (`scripts/handoff-fire.sh:6151`), so it could hit `tee`.
   - Use `kill -TERM <pid>`, where the pid comes from `pane_cc_state`'s closure
     (HEAD :6155-6215, which already crosses the expect pty) and `pid_is_cc` (:5755). Pin it by
     lstart, as `cc-teardown` does.
2. **Crash attribution.**
   - Exit 143 makes the crash watchdog report `CRASH external-sigterm` and paint "⛔ KILLED". See
     `01-arm-mechanics.md:60,64` (`map_exit_class` gives 1 for 143) and the
     `.claude/rules/agent-operating-lessons-situational.md:11` desk-husk lesson.
   - Write a `mode=recycle` teardown marker immediately before the kill (cc-teardown :883-889
     pattern) and emit a `recycle-exit-signalled` row.
   - Prefer SIGTERM to SIGINT. SIGINT's `shutdown(0)` would make `rr_close_on_clean_exit`
     (`bin/reso-resume-one:965-990`) close the pane on rc 0 unless a recycle marker is pending. Rc
     143 can never trip that close.
3. **Background work skips the modal**, so the policy the modal enforced must run before the
   signal. `hf_bg_work_gate` (HEAD :2813) and `hf_transcript_at_rest` (:2655) already implement the
   at-rest census, including stop-if-only-the-watcher. Pane 134 shows "1 shell still running"
   right now (measured, get-text row 56).
4. **An operator draft is destroyed rather than merged.** Keep the composer read as a **guard**:
   - A readable non-empty box that is not receipted residue → hold or carry
     (`scripts/lib/composer-carry.sh`).
   - Unreadable → take `lr-composer-snapshot.sh` (ANSI, types nothing), then decide between hold
     and proceed. **This is a policy fork for the lead or operator.**
   - Unlike today, a wrong read can no longer write into the box.
5. **The turn-start race (F3's cc-await-ping wake).** A turn starting between the at-rest proof
   and the signal gets cut. The window is one `ps` plus one syscall, about a millisecond. Today the
   window is the composer gate, up to 180 s. A typed `/exit` interrupts a running turn too
   (`scripts/handoff-fire.sh:14371-14374`), so this is not a new hazard.

### (c) `/clear` + paste ("gate-free")

The lesson (`~/.claude/projects/-Users-chrisren-Development-reso-management-app/memory/feedback-clear-and-paste-is-the-gate-free-recycle.md`)
is about the **capacity gate** and a **manual, operator** paste. It does not show the route is
safe to automate. Automating it was the original design and it failed: the **2026-07-03 catnav
incident** (`scripts/handoff-fire.sh:147-155`, :14365-14371). Built-in slash commands wait for the
turn to end, but plain text is steered into the running turn at the next tool-result boundary. So
the payload ran inline in the OLD context while `/clear` stayed armed behind it.

- **Adds:** two composer keystroke actions where (a) has one, so more of the F2-F4 surface, not
  less.
- **Cannot do:** change binary, account, MCP config, `--settings` or effort. F1's relaunch line
  carries all of them.
- **Removes:** only the shell relaunch, which (a)'s claim already removed.
- **Verdict: rejected for automation.** It stays a manual operator path.

### (d) kitty-native transport vs `it2`

`it2` already *is* kitty remote control:

- `session send` = `prove_target` + `kitty @ send-text --match id:N -- "$text"` (`bin/it2-kitty:1311-1322`);
- `session read -n N` = `kitty @ get-text --extent all [--ansi] | tail -n N` (:1478-1488).

So swapping transports changes nothing in F2-F4, which were **parse** failures of a successfully
read screen (0584f0720), not transport failures. `--bracketed-paste` would still type into the
composer.

What kitty does offer that the repo does not use (`grep -r -- --add-cursor` = 0 files, measured):

- `get-text --add-cursor` returns the real cursor position. On pane 134 the tail was
  `ESC[?25h ESC[59;3H`: visible, row 59, column 3. Row 59 is exactly the `❯ ` composer input row
  between the two rules (rows 58 and 60). Measured, n=1, idle and empty composer.
- That is a **layout-independent anchor for the composer caret**, which `composer_content`'s
  rule and selector parse lacks. It is unmeasured with the slash menu open or with a multi-line
  draft.
- `--extent last_cmd_output` and `last_non_empty_output` return **0 bytes** on pane 134
  (measured). CC emits no shell-integration marks, so they cannot isolate the composer.
- Verdict: no gain as a primitive. `--add-cursor` is a candidate hardening for whichever
  composer *guard* remains.

### (e) New window or overlay successor instead of in place

- **Removes:** nothing on the predecessor side. The old CC must still be ended, by typed `/exit`
  (self-close also types it, :13388) or by a signal, which is (b).
- **Adds:**
  - a kitty `launch` RPC, which has executed about 9 minutes after reporting failure (rc 4 at
    05:03:51 → window 134's zsh at 05:12:38, plan Root cause), hence the token reconciliation and
    exit 6 in boot-resume-launch;
  - a new window id, which breaks pane-keyed state (registry rows, `cc-fired/<pane>.json`,
    retry tickets);
  - for `--type=overlay`, the overlay's lifetime is tied to its parent window.
- The repo already has this route as a handoff: `--split-right` + `self-close`
  (`scripts/handoff-fire.sh:17509-17511`).
- **Verdict:** a fallback when the pane cannot survive its exit (the survivability gate). It is not
  a primary primitive.

## 4. Ranking

1. **(b) SIGTERM to the pinned claude pid, plus (a)'s staged successor.** This removes every
   composer actuator in F2-F4 and keeps the measured keystroke-free relaunch. Conviction 75%.
2. **(a) as at HEAD.** 0584f0720 plus the residue receipt close the exact F2 parse and F4 receipt
   gaps. A typed actuator remains whose undo depends on the read that failed.
3. **(e)** — only where the pane does not survive.
4. **(d)** — not a primitive. Harvest `--add-cursor` for the guard.
5. **(c)** — refuted for automation by the 2026-07-03 incident.

## 5. Does any path at HEAD still type a shell line into a pane that might hold a live composer?

**The 2026-08-06 class is closed at entry.** Every shell-line typing path requires an affirmative
`shell` verdict from `pane_cc_state`. It takes the descendant closure across the expect pty
(:6155-6215). On pane 134 that closure contains claude 19890 on ttys035 under expect on ttys032
(measured with `ps`), so the pane reads `cc`, not `shell`. The gated paths:

- the recycle shell-only branch (:17521-17529; `unknown` refuses at :17530-17539);
- the watcher fallback (`at_shell` :10208, plus a 20 s claim grace);
- `--relaunch-at-shell` (:11847).

**Residual paths remain.** None of them is the reso shape:

1. **Kitty late execution.** `_it2_type_line` treats a send rc 124 as "delivery unknown". The
   plan measured kitty executing a timed-out request about 9 minutes late, and in a scratch window
   3 of 4 rc-124 pastes were on screen. A paste of `: hfv-…; cd … && claude …` (or of
   `FIRE_NOCORRECT_LINE`, :3692), or the nocorrect line in F1, that lands after the successor has
   started goes into the successor's **live composer**. The per-attempt `foreground-cc` check
   (:3812-3817) stops *further* attempts but cannot recall a queued request. No CR follows unless a
   late CR also lands, so the expected harm is a foreign draft that holds the successor's next
   recycle (the F4 shape). This applies to the typed fallback only: 4 of 9 recent exits.
2. **The per-attempt recheck is fail-open on `unknown`.** It stops only on `= cc` (:3812-3813,
   :3856-3857) and only when the caller passes `HF_TYPE_TTY`. Over the 600 s
   `CC_RECYCLE_TYPE_DEADLINE_S` loop (:10957-10968), a `ps` that fails under load reads `unknown`
   and typing continues.
3. **`it2_land` (:16893-16916)** types into a freshly created pane with no `HF_TYPE_TTY` and no
   `pane_cc_state`. Risk is low, because a fresh pane has no composer unless argv-launched, and
   that case skips typing (`HF_ARGV_ACTIVE`).
4. **Composer, not shell, but still typed:** `/exit` (:3319), the background-work digit and Esc,
   `arm_goal`'s `/goal` (:8766), composer scrubs and the nudge retype. This is the plan's own
   "Known residuals". Under (b) the first three vanish from the recycle exit.

## 6. What was not done

- Not measured live: SIGTERM against an at-rest 2.1.293 session in a scratch pane. That needs a
  pane I may not touch, so the CC behaviour above is code-read plus earlier field incidents.
- `adopt.json` exit-handoff behaviour under a signal is not verified.
- No bats suite was run; none was needed for a survey.
