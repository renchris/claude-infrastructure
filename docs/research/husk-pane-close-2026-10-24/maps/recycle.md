# Map: continue / restart / recycle / handoff / resume paths, and why some leave a bare shell

Read-only mapper, 2026-10-24. Times are UTC unless marked CDT (CDT = UTC − 5; the watchdog log uses CDT).
Code is cited at the worktree HEAD 7cdb9adae. Every count below is labelled with the command that produced it.

## 1. Answer first

- **In-flight recycles are not producing bare shells right now.** handoffs.jsonl begins
  2026-10-21T14:49Z (the log was rotated, so 3.5 days of the 14 are covered). Since then: 48 non-test
  `recycle-intent`, 33 `recycle-engaged`, 0 `recycle-dead`, 0 `recycle-successor-revoked`, 0
  `recycle-relaunch-failed`, 0 post-exit `recycle-held-{fold,holder,launch-lock}`. Every attempt that
  did not engage was **held before /exit** (held-draft 7, held-bgwork 5, held-exit-readback 2, refused-no-pane 1).
  A held attempt leaves Claude Code running, so the pane still works. Every engaged successor lived 138 min or more.
- **The bare shells come AFTER a resumed session ends, in panes whose claude runs under `expect`.**
  That means `lr-fire-resume.sh`, which every `cc-lr move/switch` resume-mode recycle and every
  lr-fleet resume goes through, and to a lesser degree `reso-resume-one`. Two defects stack:
  1. **lr-fire-resume never closes on a clean exit.** Its tail always runs `exec zsh -l -i` and paints
     "ended, pane is an ordinary shell · close it (Ctrl-D)"
     (`scripts/limit-recover/lr-fire-resume.sh:2276-2304`). Its sibling `bin/reso-resume-one`
     has had `rr_close_on_clean_exit` since 2026-10-01 (`bin/reso-resume-one:1145-1186`), and
     `bin/cc-pane-runner` closes on rc 0 (`bin/cc-pane-runner:257-276`, `_close_pane` :283). lr-fire-resume
     never got that fix. `grep -n CC_PANE_CLOSE_ON_EXIT scripts/limit-recover/lr-fire-resume.sh` returns nothing.
  2. **The crash watchdog believes the pane closed, so it never queues a close.** It records
     `LEAD_TTY=$(ps -o tty= -p $LEAD_PID)` (`hooks/lead-crash-watchdog.sh:2299`). Under expect, that is
     expect's inner pty, not the pane's tty. When claude exits, expect tears the inner pty down, and
     `pane_verdict_settle` returns `closed` (`:1651`, `:1659`). `paint_pane_verdict` then returns before
     `pane_husk_row` (`:2043`). The result is no paint, no husk row, nothing for `scripts/pane-close-retry.sh`
     to retry, and no `cc-pane-close` call. `cc-pane-close` already knows about inner ptys ("KITTY NAMES THE WINDOW",
     `bin/cc-pane-close:42-45`), but nothing calls it.
  Together these strand the pane: it sits at a bare shell with a "Ctrl-D" banner and nothing will ever close it.

## 2. Cases in the window (evidence)

### 2a. lr-fire-resume fall-through husks (the live class)
`jq 'select(.tool=="lr-fire-resume")' ~/.claude/logs/pane-say.jsonl` (the log starts 2026-10-19T12:46Z) shows
7 `ended, pane is an ordinary shell` paints:

| pane | sid | exit (UTC) | Good to close (last assistant) | self-close? | watchdog verdict | closer rows |
|---|---|---|---|---|---|---|
| 38 | f5bbd5b5 | 10-21 04:46:55 | yes (04:44:59) | none | NOT PAINTED, "pane closed (ttys003 gone)"; pane tty was ttys067 (reg 10-20 02:58 CDT) | none |
| 26 | f583a3fd | 10-21 05:02:31 | yes (04:47:25) | none at the end | NOT PAINTED, "ttys038 gone" | only 10-21 21:39 "no registration in running kitty" |
| 55 | e80b61f4 | 10-21 16:50:34 | no | self-close 16:50:01, closed 16:50:38 (close-attrib) | — | transient: self-close landed 4 s later |
| 45 | fbe6321f | 10-22 05:59:30 | yes (05:55:33) | none | NOT PAINTED, "ttys016 gone"; pane tty ttys037 | none |
| 10 | 8d8fc9fc | 10-22 06:22:15 | yes (06:17:43) | none | NOT PAINTED, "ttys020 gone"; staged tty ttys019 | none |
| 9 | f4303515 | 10-22 06:22:17 | yes (06:18:04) | none | NOT PAINTED, "ttys018 gone"; staged tty ttys017 | none |
| 134 | 666022fd | 10-24 23:54:58 | yes (21:24:07) | self-close --success 20:20 (earlier) | NOT PAINTED, "ttys030 gone"; staged tty for 134 was ttys029 | none |

Sources: `~/.claude/logs/lead-crash-watchdog.log` (registration lines and "pane verdict NOT PAINTED" lines),
`pane-close.jsonl` (no rows for 38/45/10/9/134), `close-attrib.jsonl`, transcripts under
`~/.claude-{quaternary,tertiary}/projects/*/<sid>.jsonl` and `~/.claude/projects/*/<sid>.jsonl`.
Six of the seven are real husks. Five of those six wrote "Good to close: yes", so they meant to end, yet the
pane was kept and no closer was ever queued. Panes 134 and 289 are absent from the live `kitty @ ls` taken
at about 02:05Z (pane-close.jsonl 02:03:08Z: 289 "gone"). Something outside this mapper closed them.

### 2b. Every resume-mode recycle registers the inner pty (structural, not incidental)
Method: join handoffs.jsonl `recycle-successor-staged` ("staged for ttysN", `(resume` flag) to the next
`registered … pane=P` line in lead-crash-watchdog.log (an inline python join, measured):
**resume mode: 12 of 12 registered a tty different from the staged pane tty. Fresh mode: 0 of 21.**
Examples: pane 45 staged ttys037 / registered ttys016; pane 67 staged ttys011 / registered ttys012.

**Live latent husks right now.** I compared kitty's window tty (`ps -o tty= -p <window pid>` from
`kitty @ ls`) with the last registration. Seven live panes disagree: 2 (ttys003 vs ttys007), 5, 7, 47, 67
(lr-fire-resume) and 11, 12 (reso-resume-one). Panes 117 and 216 (fresh) agree.
When any of panes 2, 5, 7, 47 or 67 ends without a self-close that lands, it repeats §2a.

### 2c. Earlier in-window recycle failures (from research records and autonomy markers)
- **2026-10-18, pane 332, `cc-lr move` (typed era).** The watcher's nudge typed `/exit` first. The foreground
  then held on load, and `hf_recycle_hold` killed the watcher between the disarm line and the relaunch line,
  leaving a bare zsh (`docs/research/lr-wake-incident-2026-10-18/a-failed-self-recycle.md` §1).
  Resume-mode staging has since removed the typing (`lib/pane-successor.sh:16-20`, "resume or transplant stage").
- **2026-10-18, panes 390/393/398 (`~/.claude/autonomy/recycle-failed/{b102f5af,2ee922eb,5759497b}.json`).**
  `class: boot-failed`: the relaunch was typed and capacity-admit refused it (rc 9 / gate, "refusal 3 of
  budget 3"), leaving a bare shell with no claude.
- **2026-10-14, pane 434 (`docs/research/recycle-failure-2026-10-14.md`).** The successor inherited a `| tee`
  stdout, so it ran non-interactive. The marker-arm verifier then falsely logged `engaged:true`. Fixed by the
  /dev/tty re-attach in `lib/pane-successor.sh:214-222` and `lr-fire-resume.sh:2297-2303`.
- **2026-10-10, pane 168 (`docs/research/lr-stranded-husk-2026-10-10/ROOT-CAUSE.md`).** A transplant recycle
  answered "Move to background and exit" and the process never exited. The poller retired the record without
  a live successor.

## 3. Path map: what regains the tty when claude exits, and what it does

| path | how the successor starts | who regains tty on exit | rc 0 and meant to end | meant to continue | watchdog sees |
|---|---|---|---|---|---|
| `handoff-fire.sh --recycle`, fresh (self/peer) | staged `.cmd` via `lib/pane-successor.sh` stage (:93-128); watcher revokes then types if unclaimed (`handoff-fire.sh:13091-13110`) | cc-close-attrib (`bin/cc-close-attrib:600-626`), or lr/rr tail, or zsh precmd (`lib/pane-successor.sh:279-284`) | successor loop ends with `exec zsh -l -i` (`lib/pane-successor.sh:231-241`); closes only via cc-pane-runner (if its parent) or watchdog husk row → gated cc-pane-close | take + exec claim | pane tty (registration matches): paints, husk row |
| `cc-lr switch` / `cc-lr move` (resume-mode recycle, SIGTERM `recycle-exit-signal`) | staged `.cmd` = `__succ-rails` then `bash lr-launch-*.sh` → lr-fire-resume → expect → claude (see `~/.claude/run/pane-successor/ttys003.claimed.61390`) | lr-fire-resume tail (`lr-fire-resume.sh:2258-2304`) | **always keeps a shell** ("ordinary shell" banner) | claims the next stage (:2270-2274) | **inner pty, so false `closed`; no husk row** |
| `lr-fire-resume` direct (lr-fleet --one, limit-recover) | expect `spawn … --resume` (`lr-fire-resume.sh:1765-1767`) | same tail | **keeps shell** | same | **inner pty, so false `closed`** |
| boot-resume / `reso-resume-one` | kitty `launch … zsh -ic "$CMD \|\| exec zsh -i"` (`scripts/boot-resume-launch.sh:252-256`) | reso-resume-one tail | `rr_close_on_clean_exit`: rc 0, no recycle pending, guard ok → exit 0 closes (`bin/reso-resume-one:1145-1186`) | `rr_successor_take_exec` (:1193-1213) | inner pty, so false `closed` (harmless only when its own close lands; a guard refusal leaves an unqueued husk) |
| `cc-husk-sweep --resume` | types `nocorrect CC_ACCOUNT_PINNED=1 claudeN --resume <sid>` at the bare shell (`bin/cc-husk-sweep:612-625`) | the interactive zsh | nothing closes from inside; watchdog paint + husk row → gated cc-pane-close | precmd consumer | pane tty: paints |
| fresh fire pane (`cc-pane-runner`) | `CC_PANE_CMD` env or `.cmd` file (`bin/cc-pane-runner:600-646`) | cc-pane-runner | rc 0 → `_close_pane`: recycle-pending check, then fullscreen guard, then exit (`:257-330`) | `cc_pane_recycle_pending` keeps the shell (`:293-297`) | pane tty |
| "watchdog relaunch" | **does not exist.** `lead-crash-watchdog.sh` never relaunches; it paints `▶ cc-husk-sweep --pane N` / `cc-lr recover` (`:1956`, `:2010-2025`) and writes husk rows (`:2132-2152`). Engagement-retry relaunches belong to `rcy_debt_settle` / cc-resume-debt (`handoff-fire.sh:13176-13186`, :13409-13414) | — | — | — | — |

## 4. Signals that distinguish "meant to end" from "meant to continue" at exit time

**Meant to continue** (strongest first):
1. A recycle lock with a live holder: `~/.reso/limit-recover/locks/pane-<sha1(key:pane)>.recycle/holder`,
   read by `cc_pane_recycle_pending` (`lib/pane-recycle-pending.sh:27-57`). It fails toward pending.
2. A staged successor for the pane's tty: `~/.claude/run/pane-successor/<tty>.{json,cmd}` with nonce
   match, a live watcher pid with the same lstart, and age within the TTL (`lib/pane-successor.sh:130-185`).
3. handoffs.jsonl `recycle-exit-signal` (watcher SIGTERM). The exit is rc 143 / signal 15, classed
   `RECYCLE deliberate-teardown` in claude-crashes.jsonl (e.g. 8d8fc9fc 10-22T00:43:19Z).
4. An LR launch lock or record: `LR_LAUNCH_LOCK=…/locks/<sid>.launch`, `LR_RECORD_ID=move-…` in the claimed cmd.
5. Launcher refusal rc 3/9/10/11 or 75 (queued): the session never started, or a durable retry owns it
   (`bin/cc-pane-runner:263-276`, `:355-375`).

**Meant to end:**
1. The last assistant text says `Good to close: yes` (`bin/cc-pane-close:497`; `hooks/lead-crash-watchdog.sh` pane_last_close).
2. A self-close stamp: the cc-fired record has `closedAt` (`bin/cc-pane-close:499`, self_closed), and close-attrib.jsonl has `site=self-close`.
3. Custody discharge (abandon/return) after registration (`:498`); `teamName` in the transcript (`:496`).
4. SessionEnd `reason=prompt_input_exit` (sessions.log): a typed /exit with no recycle signal present.
5. rc 0 with no recycle-pending signal: the predicate cc-pane-runner and reso-resume-one use.

**Where the signals are misread today:**
- **lr-fire-resume ignores every meant-to-end signal** and keeps the shell (§1).
- **The watchdog's `closed` reads the inner pty**, so a meant-to-end exit in an expect pane is
  silently dropped (§1, §2b).
- **A gate-4 refusal implies gate 3 passed.** `cc-pane-close` checks "meant to end" (gate 3, `:489-506`) BEFORE
  "uncommitted work" (gate 4, `:508-512`), so reaching gate 4 proves the session meant to end. Yet
  `bin/cc-pane-verdict:86-87` maps `*"uncommitted change"*` to `STATE=RESUME` and paints "⛔ resume /
  stopped mid-task". That is the pane-289 contradiction: a meant-to-end signal rendered as meant-to-continue.
  Gate 4 also counts the whole checkout's `git status --porcelain`, so on a shared checkout sibling
  sessions' files count against this session.
- **Four different "should this pane close" predicates**, chosen by whichever process regains the tty:
  cc-pane-runner (rc 0), reso-resume-one (rc 0), lr-fire-resume (never), cc-close-attrib (opt-in, default
  off, `bin/cc-close-attrib:650`), and the gated cc-pane-close (Good-to-close and a clean cwd). "RECYCLE
  clean-exit" in claude-crashes.jsonl is also the class for every rc-0 exit, recycle or not, so the class
  name itself carries no continue/end meaning.

## 5. Fix levers (for the fix designers; not implemented here)
1. **One pane-exit decision, shared by every tty-regainer.** Put it in a single lib (e.g. `lib/pane-exit-decide.sh`)
   that lr-fire-resume, reso-resume-one, cc-pane-runner, cc-close-attrib and the successor loop all call:
   continue if a recycle is pending or a stage is takeable; otherwise close if any meant-to-end signal holds
   (Good to close yes, closedAt, custody, teammate, or rc 0 with `prompt_input_exit`); otherwise keep the shell AND write a husk row.
   Minimal patch: add `rr_close_on_clean_exit`'s equivalent to the lr-fire-resume tail before `exec zsh -l -i`.
2. **The watchdog keys the pane on KITTY_WINDOW_ID, not on the lead's tty.** Resolve the window's own tty through
   `kitty @ ls`, or have lr-fire-resume/reso-resume-one export the outer tty (e.g. `CC_PANE_TTY=$(tty)` before
   spawn) and record it at registration (`hooks/lead-crash-watchdog.sh:2299`). At minimum, never treat
   `closed` as final without confirming the window is absent from `kitty @ ls`; otherwise write the husk row.
3. **Every keep writes a husk row**, lr-fire-resume's fall-through included (cc-pane-runner's `_husk_row`
   pattern, `bin/cc-pane-runner:155-171`), so pane-close-retry owns the close.
4. **Gate 4 scopes to the session's own paths**, not the checkout's porcelain. **cc-pane-verdict maps a gate-4
   refusal to DONE-with-work-warning (or OWNED-by-sibling), never RESUME**, because gate 3 already proved the session meant to end.
5. Keep the post-exit rails holds (`handoff-fire.sh:13121-13137`) paired with an automatic retry (they start
   nothing by design, and each one is a bare shell until a human acts), as cc-resume-debt does for recycle-dead.
