# Husk-pane git history, late slice (2026-09-15 to 2026-10-24)

Repo: `/Users/chrisren/Development/.worktrees/husk-skill-and-fix` (history shared, `git log --all`).
Method: (a) `git log --all --since=2026-09-15 -i -E --grep='husk|self-close|…|last.?pane'` matched 1410
commits (measured, `wc -l`). Most are `checkpoint:` autosaves, `fixup!`/squash duplicates and cherry-pick
copies, plus `recycle` matches outside the close pipeline. Deduplicated by subject and filtered to subjects
that name the close pipeline, 107 remain (measured, `rg | awk '!seen' | wc -l`). (b) Per-file
`git log --all` over `bin/cc-pane-close`, `bin/cc-pane-verdict`, `bin/cc-husk-sweep`,
`scripts/handoff-fire.sh`, `scripts/pane-close-retry.sh`, `bin/cc-pane-runner`,
`hooks/lead-crash-watchdog.sh`, `bin/kitty-fullscreen-guard` and `bin/it2-kitty`. Across the seven closer
files (all but handoff-fire.sh and it2-kitty), 52 distinct non-checkpoint subjects landed since
2026-09-15: 8 in September and 44 in October (measured, `sort -u | uniq -c`). (c) `git log -S` on the
specific lines.

Files that do not exist: `bin/cc-pane-say` has no history at any time (measured, `git log --all --
bin/cc-pane-say` is empty). No `hooks/*close*` or `hooks/*husk*` file exists (zsh "no matches"). The
"pane-say" writer is `lib/cc-say.sh` plus `bin/cc-pane-verdict`, which logs to `pane-say.jsonl`.

When I give one sha, the same change also landed under a cherry-pick or duplicate sha (for example
62372906a = f5930d903 = 681df85c6; 99acf1d9f = 98639e603; 957279537 = d4784459d; 03696fdd5 = 418a8e0cd).

## The four specific questions

### Q1. When was cc-pane-close gate 4 (refuse on any cwd dirt) added, and why?
- **It was born with the tool**: ddeeb6b42 (also 20c381fbc, d150099dd), 2026-10-01 10:53 -0500,
  "feat(cc-pane-close): an agent closes a husk pane that should close, even while kitty remote control is
  down". The commit body lists four fail-closed gates. Gate 4 is "no uncommitted work in the session's
  cwd". The original code was `git -C "$cwd" status --porcelain | grep -c .` (`git show
  ddeeb6b42:bin/cc-pane-close` lines 29, 187-188). The motivating field run had pane 76 "refused while
  its cwd held an uncommitted file" (same commit body). Rationale: protect at-risk work.
- **The check itself has never been narrowed.** `git log -G'porcelain|skipwork' -- bin/cc-pane-close`
  shows exactly two changes: ddeeb6b42 (creation) and 54acfdb98 (2026-10-19). 54acfdb98 added `skipwork`
  exemptions only: a never-launched pane, and a session that moved and has a LIVE copy. It still counts
  untracked files, the whole cwd, and sibling sessions' files. There is no `--allow-dirty` and no
  own-paths scoping (current `bin/cc-pane-close:508-511`).
- **It was re-affirmed one day before pane 289**: 957279537, 2026-10-23 12:43, "Gate 4 (clean cwd)
  protecting a crashed teammate is pinned by a test". The reason is in
  `docs/plans/pane-end-of-life-2026-10-22.md:100-102` and
  `docs/research/husk-panes-2026-10-22/round2-2026-10-23/skeptics.md:10,31`: gate 3 accepts any
  `teamName` transcript, so gate 4 is the only thing that protects a crashed teammate's work. A
  crashed-teammate concern therefore locked whole-cwd dirt in for every session, including a
  `Good to close: yes` session in a shared checkout.
- **Known abandonment path, left open**: `docs/research/husk-panes-2026-10-22/investigators.md:251`
  (2026-10-22) says "Dirty or unlanded worktree … cc-pane-close gate 4 refuses. No record that would
  trigger a retry once the work lands → abandoned." No later commit changes gate 4's predicate.
- **This is a regression of a lesson already learned.** 9c0d42af0 (2026-07-20, "fix(reaper): dirty-checks
  must ignore untracked files — the finished-worker pile") made self-close's own dirt gate use
  `--untracked-files=no`. The comment at `scripts/handoff-fire.sh:15496-15500` says: "an untracked file …
  in a shared checkout is usually a SIBLING's scratch litter … counting it made a finished session
  permanently unable to self-close". `scripts/handoff-fire.sh:8663` warns about "the pile-up the
  --untracked-files=no fix already had to undo once". cc-pane-close (2026-10-01) re-implemented the dirt
  check without that lesson.

### Q2. When was the fullscreen guard rc70 added, and why?
- 2026-10-15 kitty crash: destroying the last pane of a native-fullscreen window crashed kitty
  (`bin/kitty-fullscreen-guard` header; `docs/research/kitty-crash-2026-10-15/README.md` § Chosen fix).
  - fd0d17f57 / 5c5506a74, 2026-10-15: `kitty-fullscreen-guard` added.
  - 62372906a, 2026-10-15 01:38: the guard went on the autonomous closers (it2-kitty `session close`,
    lr-fleet `--retire-husks`, cc-pane-close's SIGHUP).
  - 265790f36, same day: the guard was added to the runners' close-on-exit and to a root zsh's exit.
  - ebaece47d: no SIGHUP after a remote-control refusal.
  - 9d7f3c216 **reverted** d4b7c9ff2 (the guard on detach/close_tab chords), the only revert in this
    slice that touches the close pipeline.
- b8d8bfca9, 2026-10-16: the guard relaxes only when the kitty build is patched (`GLFWFsFixV2`) **and**
  the pane is onscreen. "A fullscreen window that is NOT onscreen keeps rc 3"
  (`bin/kitty-fullscreen-guard` header, RELAX ON THE FIX).
- **rc70 itself**: 1211646fb, 2026-10-16 10:58, "fix(it2-kitty): exit 70 on a refused-fs close;
  self-close pages husk-fs without retrying". Claimed failure: each husk episode of 2026-10-15/16 ran 4
  identical retries and paged "failed 4/4". Change: it2-kitty exits 70 on refused-fs, `hf_close_pane`
  maps `STILL-PRESENT-rc70` to 3 (`scripts/handoff-fire.sh:1929-1933`), the loop stops, and the husk-fs
  alarm says "Close it with ⌘W … No work at risk." (`:10369`, `:11902`). This is a reporting fix. It
  makes the refusal honest but never closes the pane.
- **The rc70 rate rose after a placement rule.** fd34d855d, 2026-10-19 07:20 (lr-wake Wave E), set the
  operator rule "every OS window fullscreen on its own Space". Overflow and `--window` fires now open
  `--os-window-state=fullscreen` (`scripts/handoff-fire.sh:19901`; `git log -S` finds this one commit).
  See also 6fd8c7068, 122d5ff18 and 242c34d5a (2026-10-18). A fired peer that gets its own OS window is
  therefore the last pane of a fullscreen, usually offscreen, window. The guard refuses it in refuse mode
  on every policy, so the pane can never close itself.
  `docs/research/husk-panes-2026-10-22/round2-2026-10-23/synthesis.md:5` (RC3) says: "a husk that is the
  only pane of its OS window can never be closed automatically, and the guard is right to refuse it."
  Pane 289 is exactly this case (`PANE-289-TIMELINE.md:7,10`: refused-fs, panes:1, FS, onscreen:false,
  os_window 25).

### Q3. When was cc-pane-verdict --recompute's uncommitted→RESUME mapping added, and why?
- 99acf1d9f / 98639e603, 2026-10-22 21:39, "feat(cc-pane-verdict): one writer for a dead pane's screen
  and title" (plan pane-end-of-life B3, husk-panes-2026-10-22 F5). It was built across checkpoint
  autosaves e31683e88, 940e0bc7c and edeb7a421 (`git log -S'uncommitted change"*)'`). Claimed failure:
  up to four writers painted dead panes at different moments and nothing repainted (panes 42, 85, 101).
- The mapping (`bin/cc-pane-verdict:86-87`) turns any closer line containing "uncommitted change" into
  RESUME with "N unsaved files". It is meant to implement the contract's RESUME state, "the session died
  mid-task, its work is at risk" (`docs/research/husk-panes-2026-10-22/synthesis.md:288-292`).
- **It contradicts that contract.** The same contract puts `Good to close: yes` under DONE
  (`synthesis.md:278`). Gate 4 runs only after gate 3 has already established that the session meant to
  end (`bin/cc-pane-close:489-506`). So every gate-4 refusal comes from a session that did mean to end.
  The closer's line drops the gate-3 "why", and the recompute cannot tell "meant to end but cwd is
  dirty" from "died mid-task".
- 03696fdd5, 2026-10-23: refined only row 2 (the refusal class: transient, operator-only or stuck). The
  STATE mapping was left alone.
- Field result: the first paint at 23:53:36 was DONE. The watchdog repainted it CANTTELL at 23:55. The
  reconciler repainted it RESUME at 00:00:14, "138 unsaved files" (`PANE-289-TIMELINE.md:8,12,13`). The
  "one writer" has three callers, and the last one wins.

### Q4. Was --allow-dirty ever meant to reach the post-exit closer?
**No (measured).**
- `rg allow.dirty` over cc-pane-close, cc-pane-verdict, cc-husk-sweep, cc-pane-runner,
  pane-close-retry.sh and lead-crash-watchdog.sh finds nothing.
- The husk row that self-close hands to the closer (`hf_husk_row`, added by d82aa7860, 2026-10-22 21:23)
  carries only `reason`, `tty`, `producer`, `kitty_sock` and `kitty_pid`. It has no dirt waiver, no
  `Good to close` and no allow-dirty bit (`git show d82aa7860`).
- cc-pane-close re-derives everything from the transcript and the cwd.
- `--allow-dirty` is a self-close-only flag (`scripts/handoff-fire.sh:14650`, `:15495-15509`, `:7847`).
- d82aa7860's purpose was to hand a pane that self-close could not close to "the pane closer's gates".
  The design assumed the closer's gates agree with self-close's gates. They do not: self-close counts
  tracked files only and honours --allow-dirty and --dirty-owner, while the closer counts every
  porcelain line and honours no waiver.

## Chronological table

| when | source | what was asked / claimed | root cause (as claimed) | change (sha) | recurred? |
|---|---|---|---|---|---|
| 2026-09-17 | commit 6cd30bfba | --recycle and self-close never completed in kitty; `as_write` failed 3x | no send-only verb path for /exit under kitty | handoff-fire `/exit` typing restored (6cd30bfba; plan 7617b43b1) | yes: /exit dialog failures again, 99601cdd8 (10-03) |
| 2026-09-19/20 | commits 01bf3745a, bb5b2e4ae | HUSK as a limit-recover census state; `lr-fleet --retire-husks` | husk predicate blind to tombstones | new layer: census + retire actuator | husks remain the lr case (30ecec45d, 10-10) |
| 2026-09-20 | commit c5b1346d6 | sweep would `--resume` a transplanted session (two writers) | no transplant guard in cc-husk-sweep | new verdict TRANSPLANTED (never resumed) | n/a |
| 2026-09-29 | commit 492b6310b | recycle watcher misses the shell | poll granularity / launch race | watcher lock, 1 s poll, `--husk`, `--relaunch-at-shell` | n/a |
| 2026-09-30 | commit 55a2a049e, doc husk-panes-2026-09-30.md | 7 husks after reboot | 8 root causes (doc) | research | n/a |
| 2026-09-30 | commit bbc40d207 | sweep named the wrong session for 3 of 7 husks; read CLAUDE.md's example "Good to close: no" | resolver order; close reader matched attachment text | watchdog-arm-first resolver | close-text reading failed again, 948810da6 (10-21) |
| 2026-09-30 | commit 7eb551b39 | 10 self-close `--terminal` runs aborted on a 10 s `it2 session list` timeout; 5 husks | timeout read as "pane unreachable" | `pane-NO-ANSWER`, re-arm, durable self-close row | rows lived forever: 85b1d7131 (10-22), 3f1a77b71 (10-23) |
| 2026-10-01 | commit 74baff1ee | every intentional exit left a husk | cc-pane-runner exec'd a shell after any command | **root-ish fix**: clean exit 0 closes the pane unless a recycle is pending | blocked by the fullscreen guard from 265790f36 (10-15) |
| 2026-10-01 | commit 3156c4dcd | teammate defer left no retry | no row at tool-in-flight defer | retry row | n/a |
| 2026-10-01 | commit ddeeb6b42 (+20c381fbc, d150099dd) | panes 55/69/76 sat for hours with kitty RC down; only remedy "press Ctrl-D" | every close went through `kitty @ close-window` | **new layer** `bin/cc-pane-close`, 4 gates incl. **gate 4 whole-cwd dirt** | gate 4 is the pane-289 refusal (21+ refusals) |
| 2026-10-01 | commit b6727f1d9 | closes printed FAILED though they worked | kitty-unreaped zombie root | zombie = closed-kitty-unreaped | refined ab7e82e9f (10-22) |
| 2026-10-01 | commit bd39fb7c7 | a deaf kitty held every husk | drainer held all rows | teammate rows go to cc-pane-close | leads still abandoned (investigators.md:249) |
| 2026-10-01 | commit 904fdd205 | sweep would resume pane 55 although its custody was collected | no custody arm | verdict COLLECTED (never resumed) | pane 289: sweep says COLLECTED while the verdict paints RESUME, so the classifiers disagree |
| 2026-10-01 | commit 4fad69e1d | closedAt and custody return written before the pane was proven | ordering | `sc_commit_close_records` after proof | n/a |
| 2026-10-01 | commit 6347b1731 | resumed session exiting cleanly left a husk | reso-resume-one exec'd a shell unconditionally | close on clean exit | gated by the fs guard (265790f36) |
| 2026-10-01 | commit c3d5a71dc | watchdog painted "✅ CLOSED CLEANLY … safe to close" and stopped; the operator closed panes by hand | nothing acted on the verdict | watchdog hands the pane to cc-pane-close after 20 s | inherits gate 4 and the guard refusals |
| 2026-10-03 | commits 1394567ae, 99601cdd8 | origin cannot retire into a successor; /exit dialogs | missing class; dialog reading | verified-successor class; screen-reading dialog answers | n/a |
| 2026-10-04 | commit b9c269850 | bgjob recycles and self-closes | new path | new layer | n/a |
| 2026-10-10 | commits 30ecec45d, d30f1f3ad | stranded lr husks | no single driver | `lr-fleet --one` | 54acfdb98 STRANDED arm (10-19) |
| 2026-10-15 | commits fd0d17f57, 62372906a, 265790f36, ebaece47d | kitty crash on destroying the last pane of a fullscreen window | AppKit fullscreen + window destroy | **new veto** in every closer (refuse mode) | it creates husk class husk-fs: 10-16, panes 165 (10-23) and 289 (10-24) |
| 2026-10-15 | commit 9d7f3c216 | — | — | **Revert** of d4b7c9ff2 (guard on detach/close_tab chords) | — |
| 2026-10-16 | commit b8d8bfca9 | guard over-refuses on the patched kitty | — | relax only on fsfix **and** onscreen | stock build still in use (round2 synthesis.md:5, fsfix false) |
| 2026-10-16 | commit 1211646fb | refused-fs retried 4x, paged "failed 4/4" | fixed refusal treated as transient | it2-kitty **exit 70**; self-close stops and pages husk-fs "No work at risk" | reporting fix only; the pane is still never closed |
| 2026-10-18 | commits 6fd8c7068, 122d5ff18, 242c34d5a, 7a33cb733 | operator rule: no tabs; overflow = fullscreen OS window; "a pane that leaves Claude either runs Claude or is closed" | — | placement policy | it **creates** offscreen-fullscreen single-pane windows the guard must refuse |
| 2026-10-19 | commit fd34d855d | lr-wake Wave E: no tabs, fires into fullscreen OS windows | — | `--os-window-state=fullscreen` on fire overflow (`handoff-fire.sh:19901`) | pane 289 (os_window 25, panes:1, offscreen) |
| 2026-10-19 | commit 54acfdb98 | overnight husks; banners said "safe to close" falsely | banners not lr-aware; closer refused never-launched panes | never-launched arm, moved-LIVE skipwork, the guard asked first, sweep lineage | gate 4 untouched |
| 2026-10-21 | commit 2f41fbde1 | a retired session came back as idle after a reboot (5d19ef73) | no durable intent | self-close-intent record | n/a |
| 2026-10-21 | commit 948810da6 | pane 476: the closer refused "nothing says … meant to end" | `Good to close: yes` survived only in a thinking block | gate 3 accepts the self-close stamp (closedAt) | n/a (gate 3 passed on 289) |
| 2026-10-22 | commit d576d6633; docs husk-panes-2026-10-22/* | panes 85/42/101 | RC1-RC7 (synthesis.md); gate-4 abandonment named (investigators.md:251) | research | — |
| 2026-10-22 | commit aea01028e, 8d69845a0 | a headless `claude -p --resume` self-closed the lead's pane 16 | inherited KITTY_WINDOW_ID | self-close only for its own pane; validate-bash deny | n/a |
| 2026-10-22 | commit c820e86f1 | an unreadable guard read was painted as "fullscreen" | guard dropped KittenFailed | separate "kitty didn't answer" | 7f7b9c293 (10-23) re-fixed the watchdog side |
| 2026-10-22 | commit 5d0be0366 | close was one attempt at death; panes 42/85/101 never retried | no durable husk row | **new layer**: `husk` queue kind + drain_husk → cc-pane-close | retries a refusal that cannot change (pane 289: 21+ gate-4 refusals) |
| 2026-10-22 | commit 2c94cf6d8 | pane 42 read "✅ closed" over "reason unknown" | paint ignored the closer's reason | refusal paints DONE or CHECK | superseded by 99acf1d9f |
| 2026-10-22 | commit 99acf1d9f | four writers, stale paints (42, 85, 101) | no final writer | **new layer** `cc-pane-verdict` incl. `--recompute`: "uncommitted change" → RESUME | pane 289 DONE → CANTTELL → RESUME |
| 2026-10-22 | commit d82aa7860 | a pane self-close could not close was never retried (pane 42) | — | `hf_husk_row` hands husk-fs/husk-pane to the closer; fired panes use LAUNCH_DIR cwd | no waiver crosses; the closer re-refuses (289) |
| 2026-10-22 | commits 85b1d7131, ab7e82e9f | self-close row logged 2,325 times; zombie called a wedge | stale rows; reap timing | drop older-kitty rows; re-read zombie | 3f1a77b71 (10-23) |
| 2026-10-23 | commit 957279537 | background closer blind to kitty; teammate registrations unreadable | unpinned it2 shim; registration regex | pinned listing; **gate 4 pinned by test** | gate 4 refused 289 the next day |
| 2026-10-23 | commits 03696fdd5, 7f7b9c293 | panes 165/144 promised "closes when it does" for hours | row 2 ignored the refusal class | transient / operator-only / stuck classes | the state mapping (RESUME) is untouched |
| 2026-10-23 | commit 4cb749ceb | pane 165 (only pane of an offscreen FS window) retried every tick, wrong page | drainer had no operator-only state | hold=operator, one page, bounded single drainer | honest hold; still never closes |
| 2026-10-23 | commits 3f1a77b71, fa6638ba2 | self-close rows never ended; drainer starved under load | kitty gate; shared launchd slot | row GC; own launchd job | n/a |
| 2026-10-24 | commit 3ebeaf508 | pane 289 | own vs sibling dirt not separated; guard | **new layer**: a `husk-pane` skill for manual diagnosis; no change to `bin/cc-pane-close` (no 10-24 commit in its log) | open |

## Mechanisms (grouped)

1. **Self-close (handoff-fire.sh)**: 6cd30bfba, 7eb551b39, 4fad69e1d, 1394567ae, 99601cdd8, 1211646fb,
   2f41fbde1, aea01028e, d82aa7860, 3f1a77b71. Its dirt gate counts tracked files only, with
   --allow-dirty and --dirty-owner (9c0d42af0, 07-20).
2. **In-pane close-on-exit (cc-pane-runner, reso-resume-one)**: 74baff1ee, 6347b1731, 7a33cb733,
   c820e86f1. All are gated by the fullscreen guard since 265790f36.
3. **Out-of-band closer (cc-pane-close)**: ddeeb6b42, b6727f1d9, 62372906a, ebaece47d, 54acfdb98,
   948810da6, ab7e82e9f, 957279537. Gate 4 has stayed whole-cwd since creation.
4. **Retry queue / drainer (pane-close-retry.sh, pane-close-queue)**: 3156c4dcd, bd39fb7c7, 7fe0e98af,
   5d0be0366, 85b1d7131, 4cb749ceb, 3f1a77b71, fa6638ba2.
5. **Painters (watchdog → cc-pane-verdict)**: c3d5a71dc, a0a41b5d1, 2c94cf6d8, 99acf1d9f, 03696fdd5,
   7f7b9c293.
6. **Classifier (cc-husk-sweep)**: c5b1346d6, bbc40d207, 904fdd205, 54acfdb98, 8d69845a0, 975dd4d94.
7. **Fullscreen guard + placement**: fd0d17f57, 62372906a, 265790f36, 9d7f3c216 (revert), b8d8bfca9,
   1211646fb, 6fd8c7068, fd34d855d.

New layers vs root fixes:
- New layers: cc-pane-close (10-01), the watchdog→closer handoff (10-01), the fullscreen guard as a veto
  everywhere (10-15), the husk queue kind (10-22), cc-pane-verdict (10-22), hf_husk_row (10-22), the
  husk-pane skill (10-24).
- Root fixes: 74baff1ee/6347b1731 (exit closes the pane) and aea01028e (self-close targets its own pane).
  The first was then vetoed for the fullscreen-last-pane case by the guard.
- Only one revert touches the pipeline: 9d7f3c216.
